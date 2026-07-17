#Requires -Version 5.1
<#
.SYNOPSIS
    Connect-AdmanTarget - per-host transport ladder + process-only cache (RMT-01, D-04, D-05).

.DESCRIPTION
    Determines the workable transport for a single target host using the ladder defined by
    $script:Config.transport.order, normalizing the legacy 'Skip' value to 'Skipped'. When
    transport.order is missing or empty, the fixed fallback ladder is used:
      1. WinRM (Test-WSMan)
      2. CIM over WSMAN (New-CimSessionOption -Protocol Wsman)
      3. CIM over DCOM (New-CimSessionOption -Protocol Dcom)
      4. Skipped
    The winning transport name is cached per process, keyed by uppercase computer name. Dead or
    timeout hosts return 'Skipped' without throwing (RMT-02, D-06). An optional -TimeoutSeconds
    override lets callers pass a smaller budget (for example, the remaining total fleet cap).
#>

Set-StrictMode -Version Latest

function Connect-AdmanTarget {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter()][int]$TimeoutSeconds
    )

    $key = $ComputerName.ToUpperInvariant()
    if ($script:TransportCache.ContainsKey($key)) {
        return $script:TransportCache[$key]
    }

    $cap = [int]$script:Config.transport.timeouts.perHostProbeCap
    $timeoutSeconds = if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds } else { $cap }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $transport = 'Skipped'

    $order = @()
    if ($script:Config.transport.PSObject.Properties.Name -contains 'order' -and
        $null -ne $script:Config.transport.order) {
        $order = @($script:Config.transport.order)
    }
    if ($order.Count -eq 0) {
        $order = @('WinRM', 'CimWsman', 'CimDcom', 'Skipped')
    }

    try {
        foreach ($step in $order) {
            $normalized = if ($step -eq 'Skip') { 'Skipped' } else { $step }
            if ($normalized -eq 'Skipped') { break }

            $remainingSeconds = [int]($timeoutSeconds - $stopwatch.Elapsed.TotalSeconds)
            if ($remainingSeconds -le 0) { break }

            switch ($normalized) {
                'WinRM' {
                    $result = Test-AdmanWsmanTimeout -ComputerName $ComputerName -TimeoutSeconds $remainingSeconds
                    if ($null -ne $result) { $transport = 'WinRM' }
                }
                'CimWsman' {
                    if (Test-AdmanCimSessionTimeout -ComputerName $ComputerName -Protocol Wsman -TimeoutSeconds $remainingSeconds) {
                        $transport = 'CimWsman'
                    }
                }
                'CimDcom' {
                    if (Test-AdmanCimSessionTimeout -ComputerName $ComputerName -Protocol Dcom -TimeoutSeconds $remainingSeconds) {
                        $transport = 'CimDcom'
                    }
                }
                default {
                    Write-Verbose "Unknown transport order entry '$step'; skipping."
                }
            }

            if ($transport -ne 'Skipped') { break }
        }
    } catch {
        $transport = 'Skipped'
    }

    $script:TransportCache[$key] = $transport
    return $transport
}
