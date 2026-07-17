#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanRemoteQuery - online status, OS, uptime, and logged-on-user enrichment (RMT-03, D-01).

.DESCRIPTION
    Runs the two local-on-target CIM queries allowed by Invoke-AdmanRemoteCimQuery:
    Win32_OperatingSystem (Caption/Version/CSDVersion/LastBootUpTime) and
    Win32_ComputerSystem (UserName). Returns RemoteOS as a trimmed string, Uptime as a
    [TimeSpan], and LoggedOnUser as the console user name.

    This function intentionally does NOT call Invoke-AdmanRemoteCimQuery. It keeps one
    transient CIM session for both allowed classes so the per-host time budget is spent on
    data, not session setup twice. Refactoring it to call the single-class helper would
    double the session-setup cost per host - do not do that.

    The session setup and both CIM queries run inside a single Start-Job bounded by the
    remaining per-host timeout (WR-02). This prevents a hung provider or dropped host from
    blocking the menu on Windows PowerShell 5.1, where -OperationTimeoutSec does not always
    cover the initial TCP handshake as reliably as the job wrapper.

    Skipped transport, session-setup failure, budget exhaustion, or any CIM error returns
    empty remote fields with Transport='Skipped' so the report counts the host as skipped.
#>

Set-StrictMode -Version Latest

function Invoke-AdmanRemoteQuery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet('WinRM','CimWsman','CimDcom','Skipped')][string]$Transport,
        [Parameter()][int]$TimeoutSeconds = 10
    )

    $emptyResult = [pscustomobject]@{
        RemoteOS     = $null
        Uptime       = $null
        LoggedOnUser = $null
        Transport    = 'Skipped'
    }

    if ($Transport -eq 'Skipped') {
        return $emptyResult
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $protocol = if ($Transport -eq 'WinRM') { 'Wsman' } else { $Transport -replace '^Cim','' }

    # Hard-cap session setup: a silently-dropped host cannot hang here.
    $probeOk = Test-AdmanCimSessionTimeout -ComputerName $ComputerName -Protocol $protocol -TimeoutSeconds $TimeoutSeconds
    if (-not $probeOk) {
        Write-Verbose "Session setup timed out or failed for $ComputerName"
        return $emptyResult
    }

    $remainingSeconds = [int]($TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds)
    if ($remainingSeconds -le 0) {
        return $emptyResult
    }

    # WR-02: run the real session setup + CIM queries inside a single Start-Job so the entire
    # data path is bounded by the hard timeout on Windows PowerShell 5.1. The job extracts only
    # the primitive properties we need so CIM-instance serialization cannot surprise us.
    $job = $null
    try {
        $job = Start-Job -ScriptBlock {
            param($cn, $proto, $to)
            $opt = New-CimSessionOption -Protocol $proto
            $sess = New-CimSession -ComputerName $cn -SessionOption $opt -OperationTimeoutSec $to -ErrorAction Stop
            $os = Get-CimInstance -CimSession $sess -ClassName 'Win32_OperatingSystem' -OperationTimeoutSec $to -ErrorAction Stop
            $cs = Get-CimInstance -CimSession $sess -ClassName 'Win32_ComputerSystem' -OperationTimeoutSec $to -ErrorAction Stop
            Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue
            @{
                Caption        = $os.Caption
                Version        = $os.Version
                CSDVersion     = $os.CSDVersion
                LastBootUpTime = $os.LastBootUpTime
                UserName       = $cs.UserName
            }
        } -ArgumentList $ComputerName, $protocol, $remainingSeconds

        $completed = $job | Wait-Job -Timeout $remainingSeconds -ErrorAction SilentlyContinue
        if (-not $completed) {
            return $emptyResult
        }

        $output = Receive-Job -Job $job -ErrorAction SilentlyContinue

        # Arrays containing an ErrorRecord are failures even if other objects are present.
        $hasError = $output -is [System.Management.Automation.ErrorRecord]
        if (-not $hasError -and $output -is [array]) {
            $hasError = $null -ne ($output.Where({ $_ -is [System.Management.Automation.ErrorRecord] }, 'First'))
        }
        if ($hasError -or $null -eq $output -or -not ($output -is [hashtable])) {
            return $emptyResult
        }

        $remoteOS = (@($output.Caption, $output.Version, $output.CSDVersion) -join ' ').Trim()
        $uptime = if ($output.LastBootUpTime) { (Get-Date) - $output.LastBootUpTime } else { $null }
        $loggedOn = $output.UserName

        return [pscustomobject]@{
            RemoteOS     = $remoteOS
            Uptime       = $uptime
            LoggedOnUser = $loggedOn
            Transport    = $Transport
        }
    }
    catch {
        Write-Verbose (Convert-AdmanRemoteError -Exception $_.Exception)
        return $emptyResult
    }
    finally {
        if ($null -ne $job) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -ErrorAction SilentlyContinue
        }
    }
}
