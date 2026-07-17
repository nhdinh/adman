#Requires -Version 5.1
<#
.SYNOPSIS
    Hard-timeout probe for New-CimSession setup over WSMAN or DCOM (RMT-02, Pitfall 1).

.DESCRIPTION
    Creates a New-CimSession with an explicit -Protocol inside a Start-Job so the initial TCP
    connect cannot hang the menu on a silently-dropped host. Returns $true if the session was
    created within the timeout; $false otherwise. The session created inside the job is discarded
    (D-04); this is a probe-only wrapper.
#>

Set-StrictMode -Version Latest

function Test-AdmanCimSessionTimeout {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet('Wsman','Dcom')][string]$Protocol,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $job = $null
    $success = $false
    try {
        $job = Start-Job -ScriptBlock {
            param($cn, $proto, $to)
            $opt = New-CimSessionOption -Protocol $proto
            $null = New-CimSession -ComputerName $cn -SessionOption $opt -OperationTimeoutSec $to -ErrorAction Stop
        } -ArgumentList $ComputerName, $Protocol, $TimeoutSeconds

        $completed = $job | Wait-Job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($completed) {
            $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
            # WR-02: arrays containing an ErrorRecord must be treated as failures even if
            # other objects are present. A null/empty output is the normal success shape for
            # New-CimSession.
            $hasError = $output -is [System.Management.Automation.ErrorRecord]
            if (-not $hasError -and $output -is [array]) {
                $hasError = $null -ne ($output.Where({ $_ -is [System.Management.Automation.ErrorRecord] }, 'First'))
            }
            if (-not $hasError) {
                $success = $true
                Remove-Job -Job $job -ErrorAction SilentlyContinue
                return $true
            }
        }
    } finally {
        if ($null -ne $job -and -not $success) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -ErrorAction SilentlyContinue
        }
    }

    return $false
}
