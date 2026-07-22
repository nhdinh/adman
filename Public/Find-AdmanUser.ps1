#Requires -Version 5.1
Set-StrictMode -Version Latest

function Find-AdmanUser {
    <#
    .SYNOPSIS
        Find-AdmanUser - scoped, read-only AD user search (USER-01).
    
    .DESCRIPTION
        Searches Active Directory for users matching the supplied criteria, scoped to the
        configured ManagedOUs roots. Returns a normalized PSCustomObject[] in the D-03 schema;
        renderers NEVER see a raw AD object.
    
        Filter construction (HIGH-1 - MANDATORY):
          * Every user-supplied value is passed through Escape-AdmanAdFilterLiteral BEFORE
            being interpolated into the -Filter string. Single quotes are doubled (' -> '')
            and backslashes are doubled (\ -> \\) so a name like O'Brien cannot break the
            filter or inject LDAP operators.
          * -SamAccountName and -DisplayName use exact-match (-eq) semantics.
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
            DistinguishedName. Out-of-scope objects are dropped (defense in depth; the
            -SearchBase already enforces scope but the post-filter re-check is the structural
            invariant). The deny-list and protected-group checks are NOT applied to reads -
            those gate mutations only (D-02, RESEARCH Pitfall 7).
    
        Properties list (D-02, hard-coded):
          Name, SamAccountName, DisplayName, Enabled, DistinguishedName, ObjectSid, ObjectGuid,
          UserPrincipalName, LastLogonDate, PasswordLastSet, PasswordExpired, LockedOut,
          AccountExpirationDate, whenCreated, whenChanged, MemberOf.
    
    .PARAMETER Name
        Wildcard-enabled user name to search for (-like semantics).

    .PARAMETER SamAccountName
        Exact sAMAccountName to search for (-eq semantics).

    .PARAMETER DisplayName
        Exact display name to search for (-eq semantics).

    .EXAMPLE
        Find-AdmanUser -SamAccountName 'alice'
        Find-AdmanUser -Name 'ali*'           # wildcard -like match
        Find-AdmanUser -DisplayName "O'Brien" # exact -eq match; quote doubled internally
    #>

    [CmdletBinding()]
    param(
        [string]$Name,

        [string]$SamAccountName,

        [string]$DisplayName
    )

    # At least one search criterion is required.
    if ([string]::IsNullOrWhiteSpace($Name) -and
        [string]::IsNullOrWhiteSpace($SamAccountName) -and
        [string]::IsNullOrWhiteSpace($DisplayName)) {
        throw 'Find-AdmanUser requires at least one of -Name, -SamAccountName, or -DisplayName.'
    }

    # WR-01: fail with a clear message when Initialize-Adman has not run; otherwise
    # $script:Config.ManagedOUs throws PropertyNotFoundException under StrictMode.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # D-02 hard-coded Properties list (MUST NOT shrink below this set).
    $properties = @(
        'Name', 'SamAccountName', 'DisplayName', 'Enabled', 'DistinguishedName',
        'ObjectSid', 'ObjectGuid', 'UserPrincipalName', 'LastLogonDate',
        'PasswordLastSet', 'PasswordExpired', 'LockedOut', 'AccountExpirationDate',
        'whenCreated', 'whenChanged', 'MemberOf'
    )

    # Build the -Filter string with Escape-AdmanAdFilterLiteral on every user-supplied value.
    # WR-05: require the caller to disambiguate when more than one search criterion is supplied.
    $criteria = @('Name', 'SamAccountName', 'DisplayName') | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if ($criteria.Count -gt 1) {
        throw "Find-AdmanUser: only one of -Name, -SamAccountName, or -DisplayName may be specified (supplied: $($criteria -join ', '))."
    }

    $filter = $null
    if (-not [string]::IsNullOrWhiteSpace($SamAccountName)) {
        $esc = Escape-AdmanAdFilterLiteral -Value $SamAccountName
        $filter = "sAMAccountName -eq '$esc'"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        $esc = Escape-AdmanAdFilterLiteral -Value $DisplayName
        $filter = "DisplayName -eq '$esc'"
    }
    else {
        $esc = Escape-AdmanAdFilterLiteral -Value $Name
        $filter = "Name -like '$esc'"
    }

    # Loop every ManagedOUs root; map and scope-check each result.
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($script:Config.ManagedOUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $raw = Get-ADUser -Filter $filter `
            -SearchBase $root `
            -SearchScope Subtree `
            -ResultPageSize 1000 `
            -Server $script:Config.DC `
            -Properties $properties `
            -ErrorAction Stop
        foreach ($obj in ($raw | Where-Object { $null -ne $_ })) {
            $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType 'User'
            if (Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName) {
                $results.Add($mapped)
            }
        }
    }

    return $results.ToArray()
}
