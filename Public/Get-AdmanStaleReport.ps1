#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-AdmanStaleReport {
    <#
    .SYNOPSIS
        Get-AdmanStaleReport - stale / never-logged-on user report (RPT-04 / D-05).
    
    .DESCRIPTION
        Returns users from the configured ManagedOUs roots bucketed as 'Stale' or 'NeverLoggedOn'
        using the replicated lastLogonTimestamp attribute. NEVER queries per-DC lastLogon.
    
        Bucketing rules (D-05):
          * lastLogonTimestamp is 0 or $null:
              - Cross-check whenCreated against the grace window.
              - Only bucket as 'NeverLoggedOn' if whenCreated is OLDER than the grace window.
              - Accounts created INSIDE the grace window are excluded (not yet expected to log on).
          * lastLogonTimestamp is non-zero:
              - Convert with [datetime]::FromFileTimeUtc.
              - Bucket as 'Stale' if older than (Get-Date).AddDays(-$script:Config.LogonSyncGraceDays).
              - Otherwise excluded (fresh).
    
        The grace window is $script:Config.LogonSyncGraceDays, cached by Initialize-Adman (D-07).
        If Initialize-Adman has not run, the default of 15 days is used.
    
        Scope & paging invariants (D-02):
          * Loops every $script:Config.ManagedOUs root.
          * Get-ADUser -Filter * -SearchBase $root -SearchScope Subtree -ResultPageSize 1000
            -Server $script:Config.DC -Properties <D-02 list + lastLogonTimestamp>.
          * Every returned object passes through Test-AdmanInManagedScope on its DistinguishedName.
          * Each in-scope object is mapped through ConvertTo-AdmanResult -ObjectType User and
            annotated with a Bucket column ('Stale' or 'NeverLoggedOn').

    .EXAMPLE
        Get-AdmanStaleReport
        Returns stale and never-logged-on users from managed OUs.
    #>

    [CmdletBinding()]
    param()

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # D-02 hard-coded Properties list plus lastLogonTimestamp (RPT-04).
    $properties = @(
        'Name', 'SamAccountName', 'DisplayName', 'Enabled', 'DistinguishedName',
        'ObjectSid', 'ObjectGuid', 'UserPrincipalName', 'LastLogonDate',
        'PasswordLastSet', 'PasswordExpired', 'LockedOut', 'AccountExpirationDate',
        'whenCreated', 'whenChanged', 'MemberOf', 'lastLogonTimestamp'
    )

    # Grace window from Initialize-Adman cache; default 15 when uninitialized.
    $graceDays = 15
    if ($script:Config -and $script:Config.PSObject.Properties['LogonSyncGraceDays'] -and $script:Config.LogonSyncGraceDays) {
        $graceDays = [int]$script:Config.LogonSyncGraceDays
    }
    $staleCutoff = (Get-Date).ToUniversalTime().AddDays(-$graceDays)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($root in @($script:Config.ManagedOUs)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $raw = Get-ADUser -Filter * `
            -SearchBase $root `
            -SearchScope Subtree `
            -ResultPageSize 1000 `
            -Server $script:Config.DC `
            -Properties $properties `
            -ErrorAction Stop
        foreach ($obj in ($raw | Where-Object { $null -ne $_ })) {
            $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType 'User'
            if (-not (Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName)) { continue }

            $bucket = $null
            $llt = $null
            if ($obj.PSObject.Properties['lastLogonTimestamp']) { $llt = $obj.lastLogonTimestamp }

            if ($null -eq $llt -or $llt -eq 0) {
                # Never logged on: only bucket if whenCreated is older than the grace window.
                # CR-02 fix: normalize whenCreated to UTC before comparing with the UTC cutoff.
                $created = $null
                if ($obj.PSObject.Properties['whenCreated']) { $created = $obj.whenCreated }
                if ($null -ne $created -and $created -is [datetime] -and $created.ToUniversalTime() -lt $staleCutoff) {
                    $bucket = 'NeverLoggedOn'
                }
            }
            else {
                # Replicated timestamp: convert and compare.
                $lastLogonDateTime = [datetime]::FromFileTimeUtc([int64]$llt)
                if ($lastLogonDateTime -lt $staleCutoff) {
                    $bucket = 'Stale'
                }
            }

            if ($null -ne $bucket) {
                $mapped | Add-Member -MemberType NoteProperty -Name 'Bucket' -Value $bucket -Force
                $results.Add($mapped)
            }
        }
    }

    return $results.ToArray()
}
