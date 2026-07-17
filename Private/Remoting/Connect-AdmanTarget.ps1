#Requires -Version 5.1
<#
.SYNOPSIS
    Connect-AdmanTarget - per-host transport ladder + process-only cache (RMT-01, D-04, D-05).

.DESCRIPTION
    Determines the workable transport for a single target host using the fixed ladder:
      1. WinRM (Test-WSMan)
      2. CIM over WSMAN (New-CimSessionOption -Protocol Wsman)
      3. CIM over DCOM (New-CimSessionOption -Protocol Dcom)
      4. Skipped
    The winning transport name is cached per process, keyed by uppercase computer name. Dead or
    timeout hosts return 'Skipped' without throwing (RMT-02, D-06).
#>

Set-StrictMode -Version Latest

function Connect-AdmanTarget {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ComputerName
    )

    $key = $ComputerName.ToUpperInvariant()
    if ($script:TransportCache.ContainsKey($key)) {
        return $script:TransportCache[$key]
    }

    $cap = [int]$script:Config.transport.timeouts.perHostProbeCap
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $transport = 'Skipped'

    try {
        # Step 1: WinRM
        $remainingSeconds = [int]($cap - $stopwatch.Elapsed.TotalSeconds)
        if ($remainingSeconds -gt 0) {
            $result = Test-AdmanWsmanTimeout -ComputerName $ComputerName -TimeoutSeconds $remainingSeconds
            if ($null -ne $result) {
                $transport = 'WinRM'
            }
        }

        # Step 2: CIM over WSMAN
        if ($transport -eq 'Skipped') {
            $remainingSeconds = [int]($cap - $stopwatch.Elapsed.TotalSeconds)
            if ($remainingSeconds -gt 0) {
                if (Test-AdmanCimSessionTimeout -ComputerName $ComputerName -Protocol Wsman -TimeoutSeconds $remainingSeconds) {
                    $transport = 'CimWsman'
                }
            }
        }

        # Step 3: CIM over DCOM
        if ($transport -eq 'Skipped') {
            $remainingSeconds = [int]($cap - $stopwatch.Elapsed.TotalSeconds)
            if ($remainingSeconds -gt 0) {
                if (Test-AdmanCimSessionTimeout -ComputerName $ComputerName -Protocol Dcom -TimeoutSeconds $remainingSeconds) {
                    $transport = 'CimDcom'
                }
            }
        }
    } catch {
        $transport = 'Skipped'
    }

    $script:TransportCache[$key] = $transport
    return $transport
}
