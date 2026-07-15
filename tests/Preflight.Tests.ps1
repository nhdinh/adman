#Requires -Modules Pester
<#
.SYNOPSIS
    D-07 / D-08 preflight contract tests for Initialize-Adman.

.DESCRIPTION
    Pins the sync-interval preflight (D-07) and recovery-posture caching (D-08):
      * Get-AdmanLogonSyncInterval reads (Get-ADDomain).LastLogonReplicationInterval.
      * MEDIUM-1 conversion matrix: TimeSpan / integer / zero / negative / $null inputs each
        produce the expected grace days.
      * Initialize-Adman caches LogonSyncIntervalDays and LogonSyncGraceDays on $script:Config.
      * LogonSyncGraceDays = [math]::Max(14, interval) + 1.
      * Initialize-Adman caches RecoveryPosture on $script:Config.
      * Get-ADDomain failure falls back to 14 (grace = 15).
      * Recovery-posture failure never blocks startup.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d1'
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

    # Import the AD mocks FIRST so Get-ADDomain resolves to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with the minimum shape Initialize-Adman touches.
    function script:Set-AdmanPreflightConfig {
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
                DC                  = 'dc.mock.local'
                AuditDir            = (Join-Path $TestDrive 'audit')
                DenyList            = @()
                AdmanProtectedGroup = ''
                delegatedAdminGroup = ''
                credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
                transport           = [pscustomobject]@{ timeouts = [pscustomobject]@{ WinRM = 15; CIM = 20 } }
            }
        }
    }
}

Describe 'Get-AdmanLogonSyncInterval: MEDIUM-1 conversion matrix (D-07)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanPreflightConfig
    }

    It 'returns 14 when Get-ADDomain throws' {
        Mock Get-ADDomain -ModuleName adman { throw 'ADWS unreachable' }
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }

    It 'returns 14 when LastLogonReplicationInterval is $null' {
        Set-AdmanMockLogonSyncInterval -Value $null
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }

    It 'converts a [TimeSpan] via .Days (truncates sub-day remainder)' {
        Set-AdmanMockLogonSyncInterval -Value ([TimeSpan]::FromDays(14))
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }

    It 'converts a [TimeSpan] with sub-day remainder by dropping the remainder' {
        Set-AdmanMockLogonSyncInterval -Value ([TimeSpan]::FromDays(7.9))
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 7
    }

    It 'returns the integer value when given an integer' {
        Set-AdmanMockLogonSyncInterval -Value 21
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 21
    }

    It 'returns 14 when given zero (malformed)' {
        Set-AdmanMockLogonSyncInterval -Value 0
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }

    It 'returns 14 when given a negative value (malformed)' {
        Set-AdmanMockLogonSyncInterval -Value (-5)
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }

    It 'truncates a double toward zero' {
        Set-AdmanMockLogonSyncInterval -Value 9.7
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 9
    }

    It 'returns 14 for an unexpected type (defensive fallback)' {
        Set-AdmanMockLogonSyncInterval -Value 'not-a-number'
        & (Get-Module adman) { Get-AdmanLogonSyncInterval } | Should -Be 14
    }
}

Describe 'Initialize-Adman: sync-interval + recovery-posture caching (D-07 / D-08)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanPreflightConfig
        # Stub the startup steps that are not under test so Initialize-Adman completes.
        Mock Initialize-AdmanConfig -ModuleName adman { }
        Mock Test-AdmanAuditWritable -ModuleName adman { $true }
        Mock Get-AdmanCredential -ModuleName adman { $null }
        Mock Test-AdmanCapability -ModuleName adman { [pscustomobject]@{} }
        Mock Resolve-AdmanDomainSid -ModuleName adman { }
        Mock Get-AdmanProtectedIdentity -ModuleName adman { }
        Mock New-EventLog -ModuleName adman { }
    }

    It 'caches LogonSyncIntervalDays and LogonSyncGraceDays = Max(14, interval) + 1' {
        Set-AdmanMockLogonSyncInterval -Value 21
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $true; ForestFunctionalLevel = 'Windows2016Forest'; TombstoneLifetime = 180 }
        }

        & (Get-Module adman) { Initialize-Adman }

        $cfg = & (Get-Module adman) { $script:Config }
        $cfg.LogonSyncIntervalDays | Should -Be 21
        $cfg.LogonSyncGraceDays | Should -Be 22
    }

    It 'uses 14 as the floor when interval is below 14 (grace = 15)' {
        Set-AdmanMockLogonSyncInterval -Value 7
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $true; ForestFunctionalLevel = 'Windows2016Forest'; TombstoneLifetime = 180 }
        }

        & (Get-Module adman) { Initialize-Adman }

        $cfg = & (Get-Module adman) { $script:Config }
        $cfg.LogonSyncIntervalDays | Should -Be 7
        $cfg.LogonSyncGraceDays | Should -Be 15
    }

    It 'falls back to grace=15 when Get-ADDomain throws' {
        Mock Get-ADDomain -ModuleName adman { throw 'ADWS unreachable' }
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $true; ForestFunctionalLevel = 'Windows2016Forest'; TombstoneLifetime = 180 }
        }

        & (Get-Module adman) { Initialize-Adman }

        $cfg = & (Get-Module adman) { $script:Config }
        $cfg.LogonSyncIntervalDays | Should -Be 14
        $cfg.LogonSyncGraceDays | Should -Be 15
    }

    It 'caches RecoveryPosture on $script:Config' {
        Set-AdmanMockLogonSyncInterval -Value 14
        $expected = [pscustomobject]@{ RecycleBinEnabled = $true; ForestFunctionalLevel = 'Windows2016Forest'; TombstoneLifetime = 180 }
        Mock Get-AdmanRecoveryPosture -ModuleName adman { $expected }

        & (Get-Module adman) { Initialize-Adman }

        $cfg = & (Get-Module adman) { $script:Config }
        $cfg.RecoveryPosture.RecycleBinEnabled | Should -BeTrue
        $cfg.RecoveryPosture.ForestFunctionalLevel | Should -Be 'Windows2016Forest'
        $cfg.RecoveryPosture.TombstoneLifetime | Should -Be 180
    }

    It 'continues startup when Get-AdmanRecoveryPosture throws' {
        Set-AdmanMockLogonSyncInterval -Value 14
        Mock Get-AdmanRecoveryPosture -ModuleName adman { throw 'unexpected posture failure' }

        { & (Get-Module adman) { Initialize-Adman } } | Should -Not -Throw

        $cfg = & (Get-Module adman) { $script:Config }
        $cfg.RecoveryPosture | Should -BeNullOrEmpty
        & (Get-Module adman) { $script:Initialized | Should -BeTrue }
    }
}
