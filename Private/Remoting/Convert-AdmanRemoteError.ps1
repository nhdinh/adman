#Requires -Version 5.1
<#
.SYNOPSIS
    Convert-AdmanRemoteError - translate raw WinRM/CIM/DCOM exceptions into short operator strings.

.DESCRIPTION
    Maps common HRESULTs and error text (RPC unavailable, access denied, double-hop, WinRM
    unreachable) to concise, actionable strings. Returns a safe string for $null input and never
    throws. Consumed by the query layer and ladder logging in Phase 3.
#>

Set-StrictMode -Version Latest

function Convert-AdmanRemoteError {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [System.Exception]$Exception
    )

    if ($null -eq $Exception) { return 'Remote error: unknown' }

    $msg = $Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) { return 'Remote error: unknown' }

    if ($msg -match '0x800706BA|RPC server is unavailable') {
        return 'RPC server unavailable (DCOM firewall)'
    }
    if ($msg -match '0x80070005|Access is denied') {
        return 'Access denied'
    }
    if ($msg -match '0x8009030e|ANONYMOUS LOGON') {
        return 'Double-hop blocked'
    }
    if ($msg -match 'WinRM cannot complete the operation|2150859046') {
        return 'WinRM unreachable'
    }

    $firstLine = ($msg -split "[\r\n]")[0].Trim()
    if ([string]::IsNullOrWhiteSpace($firstLine)) { return 'Remote error: unknown' }
    return "Remote error: $firstLine"
}
