#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanGroupAllowed - group-side policy for Add/Remove-ADGroupMember (D-04, GRP-03).

.DESCRIPTION
    Returns @{ Allowed = [bool]; Reason = [string] }. Reasons are ACCUMULATED. Three checks:

      (i)   group objectSid DIRECT equality against $script:ProtectedSIDs - SKIPPED when
            Operation='Remove-ADGroupMember' (asymmetric remediation: removing a principal
            FROM a protected group is allowed; adding TO a protected group is refused).
            Direct equality is used (NOT IN_CHAIN) - the group's own SID is the boundary,
            not its nested memberships.
      (ii)  group SID RID against $script:DenyRids - applies on BOTH Add and Remove.
      (iii) objectClass contains msDS-GroupManagedServiceAccount or msDS-ManagedServiceAccount.

    The member side is checked separately by Test-AdmanTargetAllowed (unchanged).
#>

Set-StrictMode -Version Latest

function Test-AdmanGroupAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object,
        [Parameter(Mandatory)]
        [ValidateSet('Add-ADGroupMember', 'Remove-ADGroupMember')]
        [string]$Operation
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # (iii) gMSA / legacy sMSA objectClass pre-filter (a group-class object would not normally
    #       carry these classes, but the check is cheap and keeps the policy uniform).
    $objectClass = @($Object.objectClass)
    if ($objectClass -contains 'msDS-GroupManagedServiceAccount' -or
        $objectClass -contains 'msDS-ManagedServiceAccount') {
        $reasons.Add('gMSA/service account (objectClass)')
    }

    # (ii) deny-list by RID - applies on BOTH Add and Remove (D-04).
    $sid = if ($Object.PSObject.Properties['objectSid']) { $Object.objectSid } else { $null }
    if ($null -ne $sid) {
        $sidString = ([System.Security.Principal.SecurityIdentifier]$sid).Value
        # WR-07 fix: coerce both sides to string explicitly. If $script:DenyRids was
        # loaded from JSON as integers (e.g. [512] rather than ['512']), the case-sensitive
        # string -in comparison would fail silently and the deny-list would be bypassed.
        $rid = [string]($sidString.Split('-')[-1])
        $denyStrings = @($script:DenyRids | ForEach-Object { [string]$_ })
        if ($rid -in $denyStrings) {
            $reasons.Add("deny-listed RID $rid")
        }

        # (i) protected-SID direct equality - SKIPPED on Remove (asymmetric remediation).
        if ($Operation -eq 'Add-ADGroupMember') {
            if ($sidString -in @($script:ProtectedSIDs)) {
                $reasons.Add('group is in the protected set (direct SID equality)')
            }
        }
    }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}
