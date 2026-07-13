#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanRecoveryPosture - read-only Recycle Bin / Forest Functional Level / tombstone reporter
    (RPT-07 feed; SAFE-09 warning-only).

.DESCRIPTION
    Returns the directory's recovery posture as a PSCustomObject:
      * RecycleBinEnabled     - Get-ADOptionalFeature (Name -like 'Recycle Bin*') EnabledScopes non-empty
      * ForestFunctionalLevel - (Get-ADForest).ForestMode
      * TombstoneLifetime     - (Get-ADObject configuration partition Directory Service).tombstoneLifetime

    READ-ONLY and NON-BLOCKING by design: every AD read is wrapped in try/catch that degrades the
    field to $null and emits a Write-PSFMessage -Level Warning; the function NEVER throws to block
    an operation. This is a REPORT, not a gate - the tool ships no hard-delete verb (SAFE-09), so
    there is nothing to gate; a disabled Recycle Bin is surfaced as a warning so the operator knows
    out-of-tool hard deletes are tombstone-only.

    This helper is the report-grade source feeding the 00-03 probe's RecycleBinEnabled flag and
    Phase-1 RPT-07. It does NOT re-implement the probe gate - it consumes the same AD reads and
    returns the full three-field posture for reporting.
#>

Set-StrictMode -Version Latest

function Get-AdmanRecoveryPosture {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $dc = $script:Config.DC

    # Recycle Bin optional feature (warning-only; never a blocker).
    $recycleBinEnabled = $null
    try {
        $rb = Get-ADOptionalFeature -Filter "Name -like 'Recycle Bin*'" -Server $dc -ErrorAction Stop |
            Select-Object -First 1
        $recycleBinEnabled = [bool]($null -ne $rb -and @($rb.EnabledScopes).Count -gt 0)
    } catch {
        $recycleBinEnabled = $null
        Write-PSFMessage -Level Warning -Message "Recovery posture: could not read Recycle Bin optional feature ($($_.Exception.Message))."
    }

    # Forest functional level.
    $forestFunctionalLevel = $null
    try {
        $forestFunctionalLevel = (Get-ADForest -Server $dc -ErrorAction Stop).ForestMode.ToString()
    } catch {
        $forestFunctionalLevel = $null
        Write-PSFMessage -Level Warning -Message "Recovery posture: could not read forest functional level ($($_.Exception.Message))."
    }

    # Tombstone lifetime from the configuration partition Directory Service object. The
    # configuration naming context is derived from the forest root domain (DC= parts) so no extra
    # directory round-trip is needed beyond the already-read forest. Property reads are
    # StrictMode-safe (a partial/mocked forest object may lack RootDomain/Name).
    $tombstoneLifetime = $null
    try {
        $forest = Get-ADForest -Server $dc -ErrorAction Stop
        $rootDomain = $null
        foreach ($prop in @('RootDomain', 'Name')) {
            $p = $forest.PSObject.Properties[$prop]
            if ($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) {
                $rootDomain = [string]$p.Value
                break
            }
        }
        $configNC = 'CN=Configuration'
        if ($rootDomain) {
            $configNC = 'CN=Configuration,{0}' -f (($rootDomain -split '\.' | ForEach-Object { "DC=$_" }) -join ',')
        }
        $dsPath = "CN=Directory Service,CN=Windows NT,CN=Services,$configNC"
        $tombstoneLifetime = (Get-ADObject -Identity $dsPath -Properties tombstoneLifetime -Server $dc -ErrorAction Stop).tombstoneLifetime
    } catch {
        $tombstoneLifetime = $null
        Write-PSFMessage -Level Warning -Message "Recovery posture: could not read tombstone lifetime ($($_.Exception.Message))."
    }

    if ($recycleBinEnabled -eq $false) {
        Write-PSFMessage -Level Warning -Message 'AD Recycle Bin is not enabled; out-of-tool hard deletes are tombstone-only and not recoverable through adman.'
    }

    [pscustomobject]@{
        RecycleBinEnabled     = $recycleBinEnabled
        ForestFunctionalLevel = $forestFunctionalLevel
        TombstoneLifetime     = $tombstoneLifetime
    }
}
