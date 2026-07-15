#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanInventoryReport - computer OS/inventory report (RPT-06).

.DESCRIPTION
    Returns computers from the configured ManagedOUs roots with OS version and
    basic AD attributes. Each result is mapped through ConvertTo-AdmanResult
    -ObjectType Computer and annotated with a Bucket column set to 'Inventory'.

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

Set-StrictMode -Version Latest

function Get-AdmanInventoryReport {
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

    return $results.ToArray()
}
