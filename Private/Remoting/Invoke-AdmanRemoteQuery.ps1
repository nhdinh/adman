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

    $session = $null
    try {
        $opt = New-CimSessionOption -Protocol $protocol
        $session = New-CimSession -ComputerName $ComputerName -SessionOption $opt -OperationTimeoutSec $remainingSeconds -ErrorAction Stop

        $remainingSeconds = [int]($TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds)
        if ($remainingSeconds -le 0) {
            return $emptyResult
        }
        $os = Get-CimInstance -CimSession $session -ClassName 'Win32_OperatingSystem' -OperationTimeoutSec $remainingSeconds -ErrorAction Stop

        $remainingSeconds = [int]($TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds)
        if ($remainingSeconds -le 0) {
            return $emptyResult
        }
        $cs = Get-CimInstance -CimSession $session -ClassName 'Win32_ComputerSystem' -OperationTimeoutSec $remainingSeconds -ErrorAction Stop

        $remoteOS = (@($os.Caption, $os.Version, $os.CSDVersion) -join ' ').Trim()
        $uptime = if ($os.LastBootUpTime) { (Get-Date) - $os.LastBootUpTime } else { $null }
        $loggedOn = $cs.UserName

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
        if ($null -ne $session) {
            Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
        }
    }
}
