#Requires -Version 5.1
<#
.SYNOPSIS
    Add-AdmanGroupMember - add a user or computer to one or more AD groups through
    the mutation gate (GRP-01, D-04).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanMutation -Verb 'Add-ADGroupMember'. The gate performs D-04 dual
    resolution: the MEMBER is resolved via Resolve-AdmanTarget and checked by
    Test-AdmanTargetAllowed UNCHANGED (gMSA pre-filter, deny-RID, managed-OU scope,
    recursive protected-membership); the GROUP is resolved via Resolve-AdmanGroup
    and checked by Test-AdmanGroupAllowed.

    Group-side checks on Add (D-04):
      (i)   the group's own objectSid is NOT in $script:ProtectedSIDs — direct SID
            equality, NOT IN_CHAIN (GRP-03 is identity, not membership). Adding any
            principal to a protected group is REFUSED.
      (ii)  the group's SID RID is NOT in $script:DenyRids.
      (iii) the group is NOT a gMSA (defense-in-depth).

    The audit record names BOTH the member DN (target) and the group DN (group
    field). Preview and confirmation render both sides (SAFE-10 preserved: each
    side resolved ONCE, the same two arrays feed preview and execute).

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk'

.EXAMPLE
    Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk' -WhatIf
#>

Set-StrictMode -Version Latest

function Add-AdmanGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$GroupIdentity,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    $params = @{ GroupIdentity = $GroupIdentity }

    Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
