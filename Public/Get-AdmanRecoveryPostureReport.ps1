#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-AdmanRecoveryPostureReport {
    <#
    .SYNOPSIS
        Get-AdmanRecoveryPostureReport - Public recovery-posture report (RPT-07 / D-08).
    
    .DESCRIPTION
        Thin Public wrapper over Private/Foundation/Get-AdmanRecoveryPosture.ps1.
        Returns a PSCustomObject with the three posture fields plus a Generated timestamp and a
        Freshness string describing the lastLogonTimestamp sync interval.
    
        Reads from $script:Config.RecoveryPosture when Initialize-Adman has already run; otherwise
        calls Get-AdmanRecoveryPosture directly so the report works pre-init.
    
        Freshness string format:
          'lastLogonTimestamp fresh to within N days (sync interval = X)'
    
        Where N is $script:Config.LogonSyncGraceDays (default 15) and X is
        $script:Config.LogonSyncIntervalDays (default 14).

    .EXAMPLE
        Get-AdmanRecoveryPostureReport
        Returns AD Recycle Bin status, forest functional level, and tombstone lifetime.
    #>

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # Resolve posture: prefer the Initialize-Adman cache; fall back to a direct read.
    $posture = $null
    if ($script:Config -and $script:Config.PSObject.Properties['RecoveryPosture'] -and $null -ne $script:Config.RecoveryPosture) {
        $posture = $script:Config.RecoveryPosture
    }
    else {
        $posture = Get-AdmanRecoveryPosture
    }

    # Resolve freshness inputs from config cache (defaults when uninitialized).
    $graceDays = 15
    $intervalDays = 14
    if ($script:Config) {
        if ($script:Config.PSObject.Properties['LogonSyncGraceDays'] -and $script:Config.LogonSyncGraceDays) {
            $graceDays = [int]$script:Config.LogonSyncGraceDays
        }
        if ($script:Config.PSObject.Properties['LogonSyncIntervalDays'] -and $script:Config.LogonSyncIntervalDays) {
            $intervalDays = [int]$script:Config.LogonSyncIntervalDays
        }
    }

    $freshness = 'lastLogonTimestamp fresh to within {0} days (sync interval = {1})' -f $graceDays, $intervalDays

    [pscustomobject]@{
        RecycleBinEnabled     = $posture.RecycleBinEnabled
        ForestFunctionalLevel = $posture.ForestFunctionalLevel
        TombstoneLifetime     = $posture.TombstoneLifetime
        Generated             = [datetime]::UtcNow
        Freshness             = $freshness
    }
}
