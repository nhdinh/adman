#Requires -Modules Pester
<#
.SYNOPSIS
    RPT-07 / D-08 contract tests for Get-AdmanRecoveryPostureReport.

.DESCRIPTION
    Pins the Public recovery-posture report contract:
      * Returns RecycleBinEnabled, ForestFunctionalLevel, TombstoneLifetime, Generated, Freshness.
      * Freshness string contains the actual grace days and sync interval.
      * Reads from $script:Config.RecoveryPosture when Initialize-Adman has run.
      * Falls back to direct Get-AdmanRecoveryPosture call when pre-init.
      * Graceful degradation when AD is unreachable.

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
    GUID              = 'b0000000-0000-0000-0000-0000000000d4'
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

    # Import the AD mocks FIRST so AD cmdlets resolve to mocks when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    function script:Set-AdmanRecoveryConfig {
        param([bool]$WithPosture = $true, [int]$GraceDays = 15, [int]$IntervalDays = 14)
        & (Get-Module adman) {
            param($WithPosture, $GraceDays, $IntervalDays)
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
            }
            $script:Config | Add-Member -MemberType NoteProperty -Name 'LogonSyncGraceDays' -Value $GraceDays -Force
            $script:Config | Add-Member -MemberType NoteProperty -Name 'LogonSyncIntervalDays' -Value $IntervalDays -Force
            if ($WithPosture) {
                $script:Config | Add-Member -MemberType NoteProperty -Name 'RecoveryPosture' -Value ([pscustomobject]@{
                    RecycleBinEnabled     = $true
                    ForestFunctionalLevel = 'Windows2016Forest'
                    TombstoneLifetime     = 180
                }) -Force
            }
        } -WithPosture $WithPosture -GraceDays $GraceDays -IntervalDays $IntervalDays
    }
}

Describe 'Get-AdmanRecoveryPostureReport: shape and freshness (RPT-07)' -Tag 'Unit' {

    It 'returns the five expected fields' {
        Set-AdmanRecoveryConfig -WithPosture $true
        $report = Get-AdmanRecoveryPostureReport
        $report.RecycleBinEnabled | Should -BeTrue
        $report.ForestFunctionalLevel | Should -Be 'Windows2016Forest'
        $report.TombstoneLifetime | Should -Be 180
        $report.Generated | Should -BeOfType [datetime]
        $report.Freshness | Should -BeOfType [string]
    }

    It 'Freshness string contains the actual grace days and sync interval' {
        Set-AdmanRecoveryConfig -WithPosture $true -GraceDays 22 -IntervalDays 21
        $report = Get-AdmanRecoveryPostureReport
        $report.Freshness | Should -Be 'lastLogonTimestamp fresh to within 22 days (sync interval = 21)'
    }

    It 'reads from $script:Config.RecoveryPosture when initialized' {
        Set-AdmanRecoveryConfig -WithPosture $true
        Mock Get-AdmanRecoveryPosture -ModuleName adman { throw 'should not be called' }
        { Get-AdmanRecoveryPostureReport } | Should -Not -Throw
    }

    It 'falls back to direct Get-AdmanRecoveryPosture when pre-init' {
        Set-AdmanRecoveryConfig -WithPosture $false
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $false; ForestFunctionalLevel = 'Windows2012R2Forest'; TombstoneLifetime = 60 }
        }
        $report = Get-AdmanRecoveryPostureReport
        $report.RecycleBinEnabled | Should -BeFalse
        $report.ForestFunctionalLevel | Should -Be 'Windows2012R2Forest'
        $report.TombstoneLifetime | Should -Be 60
    }

    It 'uses default grace/interval when config cache is absent' {
        & (Get-Module adman) { $script:Config = [pscustomobject]@{ ManagedOUs = @('OU=Managed,DC=mock,DC=local'); DC = 'dc.mock.local' } }
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $true; ForestFunctionalLevel = 'Windows2016Forest'; TombstoneLifetime = 180 }
        }
        $report = Get-AdmanRecoveryPostureReport
        $report.Freshness | Should -Be 'lastLogonTimestamp fresh to within 15 days (sync interval = 14)'
    }

    It 'degrades gracefully when AD is unreachable' {
        Set-AdmanRecoveryConfig -WithPosture $false
        Mock Get-AdmanRecoveryPosture -ModuleName adman {
            [pscustomobject]@{ RecycleBinEnabled = $null; ForestFunctionalLevel = $null; TombstoneLifetime = $null }
        }
        { Get-AdmanRecoveryPostureReport } | Should -Not -Throw
        $report = Get-AdmanRecoveryPostureReport
        $report.RecycleBinEnabled | Should -BeNullOrEmpty
    }
}
