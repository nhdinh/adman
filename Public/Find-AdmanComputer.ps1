#Requires -Version 5.1
Set-StrictMode -Version Latest

function Find-AdmanComputer {
    <#
    .SYNOPSIS
        Find-AdmanComputer - scoped, read-only AD computer search (COMP-01).
    
    .DESCRIPTION
        Searches Active Directory for computers matching the supplied -Name, scoped to the
        configured ManagedOUs roots. Returns a normalized PSCustomObject[] in the D-03 schema;
        renderers NEVER see a raw AD object.
    
        Filter construction (HIGH-1 - MANDATORY):
          * The user-supplied -Name value is passed through Escape-AdmanAdFilterLiteral BEFORE
            being interpolated into the -Filter string. Single quotes are doubled (' -> '')
            and backslashes are doubled (\ -> \\).
          * -Name uses wildcard (-like) semantics per D-02; wildcards in the user input pass
            through unchanged so the -like operator still works.
          * The RFC4515 LDAP assertion escape helper is NEVER used here - that helper is for
            -LDAPFilter only and does NOT escape single quotes.
    
        Scope & paging invariants (D-02, structural):
          * Loops over EVERY root in $script:Config.ManagedOUs.
          * -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC
            on every call. ResultPageSize 1000 per the PITFALLS performance trap (default 256).
          * -Server pinning reuses the Phase 0 $script:Config.DC pattern.
    
        Post-filter scope re-check (SAFE-07 step (c) on reads):
          * Every returned object passes through Test-AdmanInManagedScope on its
            DistinguishedName. Out-of-scope objects are dropped. The deny-list and
            protected-group checks are NOT applied to reads (D-02, RESEARCH Pitfall 7).
    
        Properties list (D-02, hard-coded):
          Name, SamAccountName, Enabled, DistinguishedName, ObjectSid, ObjectGuid,
          OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack, LastLogonDate,
          whenCreated, whenChanged, IPv4Address, DNSHostName.
    
    .PARAMETER Name
        Wildcard-enabled computer name to search for (-like semantics).

    .EXAMPLE
        Find-AdmanComputer -Name 'PC-*'
        Find-AdmanComputer -Name 'WEB-SRV-01'
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    Assert-AdmanInitialized

    # D-02 hard-coded Properties list (MUST NOT shrink below this set).
    $properties = @(
        'Name', 'SamAccountName', 'Enabled', 'DistinguishedName',
        'ObjectSid', 'ObjectGuid', 'OperatingSystem', 'OperatingSystemVersion',
        'OperatingSystemServicePack', 'LastLogonDate', 'whenCreated', 'whenChanged',
        'IPv4Address', 'DNSHostName'
    )

    # Build the -Filter string with Escape-AdmanAdFilterLiteral on the user-supplied value.
    $esc = Escape-AdmanAdFilterLiteral -Value $Name
    $filter = "Name -like '$esc'"

    # Loop every ManagedOUs root; map and scope-check each result.
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($script:Config.ManagedOUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $raw = Get-ADComputer -Filter $filter `
            -SearchBase $root `
            -SearchScope Subtree `
            -ResultPageSize 1000 `
            -Server $script:Config.DC `
            -Properties $properties `
            -ErrorAction Stop
        foreach ($obj in ($raw | Where-Object { $null -ne $_ })) {
            $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType 'Computer'
            if (Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName) {
                $results.Add($mapped)
            }
        }
    }

    return $results.ToArray()
}
