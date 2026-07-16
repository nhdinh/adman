#Requires -Version 5.1
<#
.SYNOPSIS
    Remove-AdmanGroupMember - remove a user or computer from an AD group through
    the mutation gate (GRP-02, D-04).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanMutation -Verb 'Remove-ADGroupMember'. The gate performs D-04 dual
    resolution: the MEMBER is resolved via Resolve-AdmanTarget and checked by
    Test-AdmanTargetAllowed UNCHANGED (gMSA pre-filter, deny-RID, managed-OU scope,
    recursive protected-membership); the GROUP is resolved via Resolve-AdmanGroup
    and checked by Test-AdmanGroupAllowed.

    D-04 ASYMMETRY (remediation): removing a principal FROM a protected group is
    ALLOWED as remediation. The group-side protected-SID check (i) is SKIPPED on
    Remove; the deny-RID (ii) and gMSA (iii) checks still apply, and ALL member-side
    checks still apply. This makes Tier-0 cleanup a first-class workflow (jdoe found
    in Domain Admins -> remove).

    The audit record names BOTH the member DN (target) and the group DN (group
    field). Preview and confirmation render both sides (SAFE-10 preserved: each
    side resolved ONCE, the same two arrays feed preview and execute).

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Remove-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk'

.EXAMPLE
    Remove-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Domain Admins' -WhatIf
#>

Set-StrictMode -Version Latest

function Remove-AdmanGroupMember {
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

    Invoke-AdmanMutation -Verb 'Remove-ADGroupMember' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
