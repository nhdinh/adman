#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanRemoteCimQuery - guarded, local-only CIM runner (RMT-04, D-07).

.DESCRIPTION
    Builds a transient CIM session for the supplied transport and reads a single CIM class.
    The ClassName is strictly allow-listed to Win32_OperatingSystem and Win32_ComputerSystem;
    any other class throws the D-07 structural guard message. The session is removed in a
    finally block. This helper exists for future single-class callers; Invoke-AdmanRemoteQuery
    intentionally does not call it so it can reuse one session for both allowed queries.
#>

Set-StrictMode -Version Latest

function Invoke-AdmanRemoteCimQuery {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet('WinRM','CimWsman','CimDcom')][string]$Transport,
        [Parameter(Mandatory)][string]$ClassName,
        [Parameter()][int]$TimeoutSeconds = 10
    )

    $allowedClasses = @('Win32_OperatingSystem', 'Win32_ComputerSystem')
    if ($allowedClasses -notcontains $ClassName) {
        throw 'Second-hop operation not supported in adman remote queries.'
    }

    $protocol = if ($Transport -eq 'WinRM') { 'Wsman' } else { $Transport -replace '^Cim','' }
    $session = $null
    try {
        $opt = New-CimSessionOption -Protocol $protocol
        $session = New-CimSession -ComputerName $ComputerName -SessionOption $opt -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
        return Get-CimInstance -CimSession $session -ClassName $ClassName -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
    }
    finally {
        if ($null -ne $session) {
            Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
        }
    }
}
