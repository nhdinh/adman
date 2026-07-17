#Requires -Version 5.1
<#
.SYNOPSIS
    Hard-timeout wrapper for Test-WSMan on Windows PowerShell 5.1 (RMT-02, Pitfall 1).

.DESCRIPTION
    Test-WSMan has no native timeout parameter on Windows PowerShell 5.1. This wrapper runs
    Test-WSMan inside a Start-Job and enforces a hard timeout so dead hosts cannot hang the
    menu. The job is always removed before returning.
#>

Set-StrictMode -Version Latest

function Test-AdmanWsmanTimeout {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $job = $null
    $success = $false
    try {
        $job = Start-Job -ScriptBlock {
            param($cn)
            Test-WSMan -ComputerName $cn -ErrorAction SilentlyContinue
        } -ArgumentList $ComputerName

        $completed = $job | Wait-Job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($completed) {
            $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($null -ne $result -and $result -isnot [System.Management.Automation.ErrorRecord]) {
                $success = $true
                Remove-Job -Job $job -ErrorAction SilentlyContinue
                return $result
            }
        }
    } finally {
        if ($null -ne $job -and -not $success) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -ErrorAction SilentlyContinue
        }
    }

    return $null
}
