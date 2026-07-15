#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanAccountStateReport - four-state account report (RPT-05 / D-06).

.DESCRIPTION
    Returns accounts from the configured ManagedOUs roots bucketed as 'Disabled', 'Expired',
    'Locked', or 'PasswordExpired' using Search-ADAccount state switches. NEVER uses
    UAC bit math.

    For each ManagedOUs root, Search-ADAccount is called four times:
      * -AccountDisabled   -> Bucket 'Disabled'
      * -AccountExpired    -> Bucket 'Expired'
      * -LockedOut         -> Bucket 'Locked'
      * -PasswordExpired   -> Bucket 'PasswordExpired'

    An account can appear in multiple buckets if it matches multiple states.

    Scope & paging invariants (D-02):
      * Loops every $script:Config.ManagedOUs root.
      * Shared splat: -SearchBase $root -SearchScope Subtree -ResultPageSize 1000
        -Server $script:Config.DC -UsersOnly (or -ComputersOnly).
      * Every returned object passes through Test-AdmanInManagedScope on its DistinguishedName.
      * Each in-scope object is mapped through ConvertTo-AdmanResult and annotated with a
        Bucket column.

.PARAMETER ObjectType
    'User' (default) or 'Computer'. Determines whether -UsersOnly or -ComputersOnly is passed
    to Search-ADAccount.
#>

Set-StrictMode -Version Latest

function Get-AdmanAccountStateReport {
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Computer')]
        [string]$ObjectType = 'User'
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run; otherwise
    # $script:Config.ManagedOUs throws PropertyNotFoundException under StrictMode.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($script:Config.ManagedOUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

        $splat = @{
            SearchBase     = $root
            SearchScope    = 'Subtree'
            ResultPageSize = 1000
            Server         = $script:Config.DC
            ErrorAction    = 'Stop'
        }
        if ($ObjectType -eq 'Computer') { $splat['ComputersOnly'] = $true } else { $splat['UsersOnly'] = $true }

        # Four state queries per root.
        $stateQueries = @(
            @{ Switch = 'AccountDisabled'; Bucket = 'Disabled' },
            @{ Switch = 'AccountExpired';  Bucket = 'Expired' },
            @{ Switch = 'LockedOut';       Bucket = 'Locked' },
            @{ Switch = 'PasswordExpired'; Bucket = 'PasswordExpired' }
        )

        foreach ($sq in $stateQueries) {
            $callSplat = $splat.Clone()
            $callSplat[$sq.Switch] = $true
            $raw = Search-ADAccount @callSplat
            foreach ($obj in @($raw)) {
                # CR-02: Search-ADAccount returns a fixed property set with 'SID'
                # (NOT 'ObjectSid') and has no -Properties parameter. Annotate the
                # raw object so ConvertTo-AdmanResult sees ObjectSid; otherwise the
                # D-03 schema column is silently $null for every row.
                if ($null -ne $obj -and
                    $obj.PSObject.Properties['SID'] -and
                    -not $obj.PSObject.Properties['ObjectSid']) {
                    $obj | Add-Member -MemberType NoteProperty -Name 'ObjectSid' -Value $obj.SID -Force
                }
                $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType $ObjectType
                if (-not (Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName)) { continue }
                $mapped | Add-Member -MemberType NoteProperty -Name 'Bucket' -Value $sq.Bucket -Force
                $results.Add($mapped)
            }
        }
    }

    return $results.ToArray()
}
