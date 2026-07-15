#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanTargetAllowed - scope + deny + protected policy for a single target (SAFE-05/06/07).

.DESCRIPTION
    Returns @{ Allowed = [bool]; Reason = [string] }. Reasons are ACCUMULATED (no early return
    on a gMSA hit) so layered signals are preserved: a gMSA that is ALSO a nested protected-group
    member returns BOTH the objectClass phrase AND the recursive-membership phrase.

    Order (D-02 / Pitfall 3):
      (a) gMSA/sMSA objectClass pre-filter FIRST -> if objectClass contains either class, ADD
          reason 'gMSA/service account (objectClass)' and CONTINUE (do not return).
      (b) deny-list by RID -> the target's objectSid RID against $script:DenyRids (D-05, never
          matched by account name); on a hit ADD reason "deny-listed RID <rid>".
      (c) managed-OU scope (Pitfall 5) -> normalize target DN + each root (lowercase/trim/
          unescape); in-scope only if $t -eq $root OR $t.EndsWith(',' + $root) for SOME root
          (component-boundary anchored; NEVER a -like substring); else ADD reason
          'outside managed-OU scope'.
      (d) recursive protected membership ALWAYS runs after (a) for layering -> escape every
          DN/value via Escape-AdmanLdapFilterValue (RFC 4515) BEFORE interpolation, then ONE
          DC-side IN_CHAIN (1.2.840.113556.1.4.1941) query bound to the TARGET via the
          -LDAPFilter parameter set ONLY (the target's DN is ANDed inside the filter with the
          ORed IN_CHAIN group clauses; the Identity parameter set is NOT used on this call -
          PowerShell rejects an Identity+LDAPFilter mix with 'Parameter set cannot be resolved'
          BEFORE the safety check runs, so they must never combine on one invocation). On a hit
          ADD reason 'recursive member of protected group'.

    The stale-on-removal admin-count attribute is NEVER read (SDProp-window lag; D-02). This
    function is called identically for preview and execute (SAFE-10).
#>

Set-StrictMode -Version Latest

function Test-AdmanTargetAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # (a) gMSA / legacy sMSA objectClass pre-filter FIRST (precise reason); CONTINUE (no early return).
    $objectClass = @($Object.objectClass)
    if ($objectClass -contains 'msDS-GroupManagedServiceAccount' -or
        $objectClass -contains 'msDS-ManagedServiceAccount') {
        $reasons.Add('gMSA/service account (objectClass)')
    }

    # (b) flat deny-list by RID - the hard floor (D-05); match objectSid, never by account name.
    #     Guard: non-security-principals (OU/container/other) have NO objectSid, so the RID check
    #     is SKIPPED for them (robustness - a null/absent objectSid must not throw under
    #     StrictMode). Such a target is NOT silently allowed: it is still subject to step (c)
    #     managed-OU scope and step (d) protected-membership. Any object WITH an objectSid (users,
    #     groups, computers, gMSA) runs the exact prior RID-deny check - a renamed RID-500 is still
    #     refused. The guard never allows a principal that would otherwise be denied.
    $sid = if ($Object.PSObject.Properties['objectSid']) { $Object.objectSid } else { $null }
    if ($null -ne $sid) {
        $rid = ([System.Security.Principal.SecurityIdentifier]$sid).Value.Split('-')[-1]
        if ($rid -in $script:DenyRids) {
            $reasons.Add("deny-listed RID $rid")
        }
    }

    # (c) managed-OU scope (Pitfall 5) - component-boundary anchored; NEVER a -like substring.
    $targetDn = [string]$Object.DistinguishedName
    $t = (ConvertTo-AdmanNormalizedDn -Dn $targetDn)
    $inScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = (ConvertTo-AdmanNormalizedDn -Dn ([string]$root))
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($t -eq $r -or $t.EndsWith(',' + $r)) { $inScope = $true; break }
    }
    if (-not $inScope) {
        $reasons.Add('outside managed-OU scope')
    }

    # (d) recursive protected-group membership - ONE DC-side IN_CHAIN query bound to the TARGET
    #     via the -LDAPFilter parameter set ONLY. Every DN/value is RFC-4515-escaped BEFORE
    #     interpolation so a special-char CN fails closed (false refusal) rather than throwing a
    #     malformed filter (C2-L1). Runs even after a gMSA hit (layering).
    $dnEsc = Escape-AdmanLdapFilterValue -Value $targetDn
    $or = ''
    foreach ($g in @($script:ProtectedGroupDns)) {
        if ([string]::IsNullOrWhiteSpace([string]$g)) { continue }
        $gEsc = Escape-AdmanLdapFilterValue -Value ([string]$g)
        $or += "(memberOf:1.2.840.113556.1.4.1941:=$gEsc)"
    }
    if (-not [string]::IsNullOrEmpty($or)) {
        $hit = Get-ADObject -Server $script:Config.DC `
            -LDAPFilter "(&(distinguishedName=$dnEsc)(|$or))" -ErrorAction Stop
        if ($hit) {
            $reasons.Add('recursive member of protected group')
        }
    }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}
