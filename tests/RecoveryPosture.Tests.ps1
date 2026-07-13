#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED) - read-only recovery-posture reporter (Get-AdmanRecoveryPosture; RPT-07 feed).

    Proves the read-only Recycle Bin / Forest Functional Level / tombstone reporter:
      * Test 3 (read-only posture): returns { RecycleBinEnabled, ForestFunctionalLevel,
        TombstoneLifetime } via Get-ADOptionalFeature (Name -like 'Recycle Bin*') +
        (Get-ADForest).ForestMode + (Get-ADObject configuration partition tombstoneLifetime) -
        all mocked; performs NO write; returns a warning flag when Recycle Bin is disabled.
      * Test 4 (does not gate): never throws to block an operation when Recycle Bin is off
        (it reports; the tool ships no hard-delete verb so there is nothing to gate - SAFE-09).

    This helper is the report-grade source feeding the 00-03 probe's RecycleBinEnabled flag and
    Phase-1 RPT-07; it does NOT re-implement the probe gate.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. ALL AD calls
    mocked via tests/Mocks/ActiveDirectory.psm1 + per-test Mock overrides; no live domain.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000ca'
    FunctionsToExport = @('Set-PSFConfig','Get-PSFConfig','Register-PSFConfigValidation','Export-PSFConfig','Import-PSFConfig','Write-PSFMessage')
}
"@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
    @'
function Set-PSFConfig { [CmdletBinding()] param($Value, [switch]$Initialize, $Name, $Module) }
function Get-PSFConfig { [CmdletBinding()] param($Name, $Module) }
function Register-PSFConfigValidation { [CmdletBinding()] param() }
function Export-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Import-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Write-PSFMessage { [CmdletBinding()] param($Level, $Message) }
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psm1') -Encoding UTF8
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:PosturePath = Join-Path $script:RepoRoot 'Private\Foundation\Get-AdmanRecoveryPosture.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Get-AdmanRecoveryPosture { }
    function global:Get-ADOptionalFeature { param($Filter, $Identity, $Server) }
    function global:Get-ADForest { param($Identity, $Server) }
    function global:Get-ADObject { param($Identity, $Properties, $Server) }
    function global:Write-PSFMessage { param($Level, $Message) }

    function New-AdmanAuditConfig {
        [CmdletBinding()]
        param([string]$DC = 'dc.mock.local')
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = $DC
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
        }
    }

    function Set-AdmanAuditState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
        } -Config $Config
    }
}

Describe 'Get-AdmanRecoveryPosture read-only recovery-posture reporter (RPT-07 feed)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanAuditState -Config (New-AdmanAuditConfig)
        Mock Write-PSFMessage -ModuleName adman { }
    }

    It 'Test 3: returns RecycleBinEnabled + ForestFunctionalLevel + TombstoneLifetime (all mocked); no write' {
        Mock Get-ADOptionalFeature -ModuleName adman {
            [pscustomobject]@{ Name = 'Recycle Bin Feature'; EnabledScopes = @('scope1') }
        }
        Mock Get-ADForest -ModuleName adman {
            [pscustomobject]@{ ForestMode = 'Windows2016Forest' }
        }
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{ tombstoneLifetime = 180 }
        }

        $posture = & (Get-Module adman) { Get-AdmanRecoveryPosture }

        $posture.RecycleBinEnabled | Should -BeTrue `
            -Because 'an enabled Recycle Bin (EnabledScopes non-empty) reports $true'
        $posture.ForestFunctionalLevel | Should -Be 'Windows2016Forest'
        $posture.TombstoneLifetime | Should -Be 180
    }

    It 'Test 3b: a disabled Recycle Bin reports RecycleBinEnabled=$false and surfaces a warning flag' {
        Mock Get-ADOptionalFeature -ModuleName adman {
            [pscustomobject]@{ Name = 'Recycle Bin Feature'; EnabledScopes = @() }
        }
        Mock Get-ADForest -ModuleName adman {
            [pscustomobject]@{ ForestMode = 'Windows2012R2Forest' }
        }
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{ tombstoneLifetime = 180 }
        }

        $posture = & (Get-Module adman) { Get-AdmanRecoveryPosture }

        $posture.RecycleBinEnabled | Should -BeFalse `
            -Because 'an empty EnabledScopes means the Recycle Bin is NOT enabled'
        # Warning surfaced (report-grade; never a block).
        Should -Invoke Write-PSFMessage -ModuleName adman -ParameterFilter {
            $Level -eq 'Warning'
        } -Because 'a disabled Recycle Bin is surfaced as a warning (RPT-07 feed)'
    }

    It 'Test 4: never throws to block when Recycle Bin is off (reports; SAFE-09 ships no hard delete)' {
        Mock Get-ADOptionalFeature -ModuleName adman {
            [pscustomobject]@{ Name = 'Recycle Bin Feature'; EnabledScopes = @() }
        }
        Mock Get-ADForest -ModuleName adman {
            [pscustomobject]@{ ForestMode = 'Windows2012R2Forest' }
        }
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{ tombstoneLifetime = 180 }
        }

        { & (Get-Module adman) { Get-AdmanRecoveryPosture } } | Should -Not -Throw `
            -Because 'recovery posture is a warning, never a gate (SAFE-09: no hard-delete verb)'
    }

    It 'Test 4b: AD read failures are caught into a $null field + warning, never thrown' {
        Mock Get-ADOptionalFeature -ModuleName adman { throw 'ADWS unreachable' }
        Mock Get-ADForest -ModuleName adman { throw 'ADWS unreachable' }
        Mock Get-ADObject -ModuleName adman { throw 'ADWS unreachable' }

        { & (Get-Module adman) { Get-AdmanRecoveryPosture } } | Should -Not -Throw `
            -Because 'transport/domain failures are caught into fields, not thrown (read-only probe)'
    }

    It 'static: read-only and non-blocking; references the three AD sources' {
        Test-Path -LiteralPath $script:PosturePath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:PosturePath -Raw

        # No terminating throw anywhere in the reporter.
        [regex]::Matches($src, 'throw\s').Count | Should -Be 0 `
            -Because 'the recovery-posture reporter never throws to block an operation (SAFE-09)'

        # References the three AD sources.
        [regex]::Matches($src, 'Get-ADOptionalFeature').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the reporter reads the Recycle Bin optional feature'
        [regex]::Matches($src, 'ForestMode').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the reporter reads the forest functional level'
        [regex]::Matches($src, 'tombstoneLifetime').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the reporter reads the tombstone lifetime'

        # Read-only: no AD write cmdlet.
        [regex]::Matches($src, '\b(?:Set-AD|Remove-AD|Disable-AD|Enable-AD|New-AD|Move-ADObject)').Count |
            Should -Be 0 -Because 'the recovery-posture reporter performs NO write'
    }
}
