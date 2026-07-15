#Requires -Modules Pester
<#
.SYNOPSIS
    RPT-05 / D-06 contract tests for Get-AdmanAccountStateReport.

.DESCRIPTION
    Pins the four-state account bucketing contract:
      * Emits objects with Bucket 'Disabled', 'Expired', 'Locked', or 'PasswordExpired'.
      * Uses Search-ADAccount state switches; NEVER userAccountControl bit math.
      * Calls Search-ADAccount four times per ManagedOUs root (one per state).
      * Shared splat includes -SearchBase, -SearchScope Subtree, -ResultPageSize 1000, -Server.
      * -UsersOnly by default; -ComputersOnly when -ObjectType Computer.
      * Out-of-scope objects are dropped via Test-AdmanInManagedScope.
      * An account can appear in multiple buckets.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:AccountStatePath = Join-Path $script:RepoRoot 'Public/Get-AdmanAccountStateReport.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d3'
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

    # Import the AD mocks FIRST so Search-ADAccount resolves to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with TWO ManagedOUs roots so we can prove the loop iterates all of them.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local', 'OU=Subsidiary,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }

    # Helper to invoke the exported Get-AdmanAccountStateReport with the mock capture reset.
    function script:Invoke-AccountStateReport {
        param([hashtable]$Params)
        Reset-AdmanMockCapture
        if ($null -eq $Params -or $Params.Count -eq 0) {
            Get-AdmanAccountStateReport
        } else {
            Get-AdmanAccountStateReport @Params
        }
    }
}

Describe 'Get-AdmanAccountStateReport: D-02 paging + scoping invariants' -Tag 'Unit' {

    It 'calls Search-ADAccount four times per ManagedOUs root' {
        Invoke-AccountStateReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Search-ADAccount' })
        $calls.Count | Should -Be 8  # 2 roots x 4 states
    }

    It 'uses -SearchScope Subtree and -ResultPageSize 1000 on every call' {
        Invoke-AccountStateReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Search-ADAccount' })
        foreach ($c in $calls) {
            $c.SearchScope | Should -Be 'Subtree'
            $c.ResultPageSize | Should -Be 1000
            $c.Server | Should -Be 'dc.mock.local'
        }
    }

    It 'uses -UsersOnly by default' {
        Invoke-AccountStateReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Search-ADAccount' })
        foreach ($c in $calls) {
            $c.UsersOnly | Should -BeTrue
            $c.ComputersOnly | Should -BeFalse
        }
    }

    It 'uses -ComputersOnly when -ObjectType Computer' {
        Invoke-AccountStateReport -Params @{ ObjectType = 'Computer' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Search-ADAccount' })
        foreach ($c in $calls) {
            $c.ComputersOnly | Should -BeTrue
            $c.UsersOnly | Should -BeFalse
        }
    }

    It 'never references userAccountControl' {
        $src = Get-Content -LiteralPath $script:AccountStatePath -Raw
        $src | Should -Not -Match 'userAccountControl' -Because 'UAC bit math is forbidden (D-06)'
    }
}

Describe 'Get-AdmanAccountStateReport: four-state bucketing (D-06)' -Tag 'Unit' {

    It 'emits Bucket Disabled for -AccountDisabled results' {
        $result = Invoke-AccountStateReport
        $disabled = @($result | Where-Object { $_.Bucket -eq 'Disabled' })
        $disabled.Count | Should -BeGreaterOrEqual 1
    }

    It 'emits Bucket Expired for -AccountExpired results' {
        $result = Invoke-AccountStateReport
        $expired = @($result | Where-Object { $_.Bucket -eq 'Expired' })
        $expired.Count | Should -BeGreaterOrEqual 1
    }

    It 'emits Bucket Locked for -LockedOut results' {
        $result = Invoke-AccountStateReport
        $locked = @($result | Where-Object { $_.Bucket -eq 'Locked' })
        $locked.Count | Should -BeGreaterOrEqual 1
    }

    It 'emits Bucket PasswordExpired for -PasswordExpired results' {
        $result = Invoke-AccountStateReport
        $pwExpired = @($result | Where-Object { $_.Bucket -eq 'PasswordExpired' })
        $pwExpired.Count | Should -BeGreaterOrEqual 1
    }

    It 'drops out-of-scope objects via Test-AdmanInManagedScope' {
        $result = Invoke-AccountStateReport
        $outScope = @($result | Where-Object { $_.DistinguishedName -like '*OU=NotManaged*' })
        $outScope.Count | Should -Be 0
    }

    It 'returns D-03 schema objects with Bucket annotation' {
        $result = Invoke-AccountStateReport
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].ObjectType | Should -Be 'User'
        $result[0].PSObject.Properties['Bucket'] | Should -Not -BeNullOrEmpty
    }

    It 'populates ObjectSid on every row (CR-02: real Search-ADAccount returns SID, not ObjectSid)' {
        $result = Invoke-AccountStateReport
        $result.Count | Should -BeGreaterOrEqual 1
        foreach ($row in $result) {
            $row.ObjectSid | Should -Not -BeNullOrEmpty -Because 'D-03 schema requires ObjectSid; production maps SID->ObjectSid after Search-ADAccount'
        }
    }
}
