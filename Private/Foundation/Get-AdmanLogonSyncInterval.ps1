#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanLogonSyncInterval - read the domain's lastLogonTimestamp replication interval (D-07).

.DESCRIPTION
    Returns the number of days the domain uses as the lastLogonTimestamp replication interval.
    This is the value the stale-report grace buffer self-tunes against (D-07).

    Source (MEDIUM-2, RESOLVED in CONTEXT.md):
      (Get-ADDomain -Server $script:Config.DC).LastLogonReplicationInterval

    The domain NC head exposes this attribute directly via the Get-ADDomain cmdlet. Do NOT
    read the Configuration partition Directory Service object - that attribute is
    tombstoneLifetime, NOT the sync interval.

    Conversion rules (MEDIUM-1) - applied in this exact order:
      * $null                     -> 14 (AD default)
      * [TimeSpan]                -> [int]$value.Days (truncate toward zero; sub-day remainders
                                     dropped because the AD replication interval is configured
                                     in whole days)
      * numeric ([int]/[long]/[double])
          - value < 1 (zero/neg) -> 14 (a non-positive interval is malformed)
          - otherwise            -> [int]$value (truncate toward zero)
      * any other type            -> 14 (defensive fallback)
      * ANY exception from Get-ADDomain -> 14

    READ-ONLY and NON-BLOCKING: never throws; always returns a positive integer.
#>

Set-StrictMode -Version Latest

function Get-AdmanLogonSyncInterval {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $default = 14

    $raw = $null
    try {
        $raw = (Get-ADDomain -Server $script:Config.DC -ErrorAction Stop).LastLogonReplicationInterval
    } catch {
        return $default
    }

    if ($null -eq $raw) { return $default }

    if ($raw -is [TimeSpan]) {
        return [int]$raw.Days
    }

    if ($raw -is [int] -or $raw -is [long] -or $raw -is [double]) {
        if ($raw -lt 1) { return $default }
        return [int][math]::Truncate([double]$raw)
    }

    return $default
}
