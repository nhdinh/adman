#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-AdmanInventoryReport {
    <#
    .SYNOPSIS
        Get-AdmanInventoryReport - computer OS/inventory report with remote enrichment (RPT-06, RMT-03).
    
    .DESCRIPTION
        Returns computers from the configured ManagedOUs roots with OS version and basic AD
        attributes. Each result is mapped through ConvertTo-AdmanResult -ObjectType Computer
        and annotated with a Bucket column set to 'Inventory'.
    
        Remote enrichment (Phase 3):
          * Every row is extended with Transport, RemoteOS, Uptime, and LoggedOnUser.
          * Transport is 'WinRM', 'CimWsman', 'CimDcom', or 'Skipped'.
          * RemoteOS is a trimmed string from Win32_OperatingSystem Caption/Version/CSDVersion.
          * Uptime is a [TimeSpan] from LastBootUpTime when the host is reachable.
          * LoggedOnUser is the console user from Win32_ComputerSystem.UserName.
          * AD-side OperatingSystem, OperatingSystemVersion, and OperatingSystemServicePack
            columns are preserved unchanged.
          * Hosts that cannot be reached or that exhaust the per-host/total time budget are
            reported as Transport='Skipped' with empty remote fields. A single Write-Warning
            summarizes how many hosts were skipped.
    
        Scope & paging invariants (D-02):
          * Loops every $script:Config.ManagedOUs root.
          * Get-ADComputer -Filter * -SearchBase $root -SearchScope Subtree
            -ResultPageSize 1000 -Server $script:Config.DC -Properties <D-02 list
            plus OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack,
            IPv4Address, DNSHostName>.
          * Every returned object passes through Test-AdmanInManagedScope on its
            DistinguishedName; out-of-scope objects are dropped.
    
        The report is read-only and never mutates the directory.
    
    .EXAMPLE
        Get-AdmanInventoryReport
    #>

    [CmdletBinding()]
    param()

    # WR-01: fail with a clear message when Initialize-Adman has not run; otherwise
    # $script:Config.ManagedOUs throws PropertyNotFoundException under StrictMode.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # D-02 hard-coded Properties list plus inventory-specific attributes (RPT-06).
    $properties = @(
        'Name', 'SamAccountName', 'Enabled', 'DistinguishedName',
        'ObjectSid', 'ObjectGuid', 'OperatingSystem', 'OperatingSystemVersion',
        'OperatingSystemServicePack', 'IPv4Address', 'DNSHostName',
        'LastLogonDate', 'whenCreated', 'whenChanged'
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($script:Config.ManagedOUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $raw = Get-ADComputer -Filter * `
            -SearchBase $root `
            -SearchScope Subtree `
            -ResultPageSize 1000 `
            -Server $script:Config.DC `
            -Properties $properties `
            -ErrorAction Stop
        foreach ($obj in @($raw)) {
            $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType 'Computer'
            if (-not (Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName)) { continue }
            $mapped | Add-Member -MemberType NoteProperty -Name 'Bucket' -Value 'Inventory' -Force
            $results.Add($mapped)
        }
    }

    # Phase 3 remote enrichment (D-01, D-02, D-03).
    $perHostCap = [int]($script:Config.transport.timeouts.perHostProbeCap)
    $totalCap = [int]($script:Config.transport.timeouts.totalInventoryRemoteCap)
    $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $skipped = 0

    foreach ($row in $results) {
        $transport = 'Skipped'
        $targetName = if ($row.DNSHostName) { $row.DNSHostName } else { $row.Name }

        $totalRemaining = [int]($totalCap - $totalStopwatch.Elapsed.TotalSeconds)
        if ($totalRemaining -le 0) {
            $transport = 'Skipped'
            $skipped++
        }
        else {
            $hostStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $hostBudget = [math]::Min($perHostCap, $totalRemaining)
            $transport = Connect-AdmanTarget -ComputerName $targetName -TimeoutSeconds $hostBudget
            if ($transport -eq 'Skipped') {
                $skipped++
            }

            $queryRemaining = [int]($hostBudget - $hostStopwatch.Elapsed.TotalSeconds)
            if ($queryRemaining -le 0) {
                if ($transport -ne 'Skipped') { $skipped++ }
                $transport = 'Skipped'
            }
            else {
                $remote = Invoke-AdmanRemoteQuery -ComputerName $targetName -Transport $transport -TimeoutSeconds $queryRemaining
                if ($remote.Transport -eq 'Skipped' -and $transport -ne 'Skipped') {
                    $skipped++
                    $transport = 'Skipped'
                }
                else {
                    $row | Add-Member -MemberType NoteProperty -Name 'RemoteOS' -Value $remote.RemoteOS -Force
                    $row | Add-Member -MemberType NoteProperty -Name 'Uptime' -Value $remote.Uptime -Force
                    $row | Add-Member -MemberType NoteProperty -Name 'LoggedOnUser' -Value $remote.LoggedOnUser -Force
                }
            }
        }

        $row | Add-Member -MemberType NoteProperty -Name 'Transport' -Value $transport -Force
    }

    if ($skipped -gt 0) {
        Write-Warning "Remote enrichment skipped for $skipped of $($results.Count) hosts."
    }

    return $results.ToArray()
}
