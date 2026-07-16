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

    -Operation (D-04 remediation asymmetry): when Operation='Remove-ADGroupMember', step (d)
    recursive protected-membership is SKIPPED. Rationale: removing a principal FROM a protected
    group is remediation - the membership in the protected group IS the state being undone, so
    refusing on that membership makes remediation impossible. Other member-side checks (a gMSA,
    b deny-RID, c scope) still apply on Remove. For every other verb (or when -Operation is
    absent), step (d) runs as before - no behavior change. The ValidateSet spans all 10 gate
    verbs (copied verbatim from Invoke-AdmanMutation.ps1) so the call-site can pass -Operation
    $Verb unconditionally; the parameter is consulted ONLY for the Remove skip.
#>

Set-StrictMode -Version Latest

function Test-AdmanTargetAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object,
        [ValidateSet('Disable-ADAccount','Enable-ADAccount','Move-ADObject','Set-ADUser','Set-ADComputer','Set-ADAccountPassword','Unlock-ADAccount','Add-ADGroupMember','Remove-ADGroupMember','New-ADUser')]
        [string]$Operation
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # CREATE-BRANCH (D-01): synthetic pre-create targets skip (a)(b)(d) entirely - no SID
    # exists yet, no group memberships exist yet, and the gMSA objectClass check would
    # false-positive on the synthetic 'user' class. Run ONLY the managed-OU scope check
    # against the PARENT OU DN (the to-be-created object has no DN in AD yet, so its own
    # DistinguishedName is fabricated; the parent OU is the authoritative scope boundary).
    if ($Object.PSObject.Properties['IsSynthetic'] -and $Object.IsSynthetic) {
        $parentDn = [string]$Object.ParentOuDn
        $p = (ConvertTo-AdmanNormalizedDn -Dn $parentDn)
        $parentInScope = $false
        foreach ($root in @($script:Config.ManagedOUs)) {
            $r = (ConvertTo-AdmanNormalizedDn -Dn ([string]$root))
            if ([string]::IsNullOrEmpty($r)) { continue }
            if ($p -eq $r -or $p.EndsWith(',' + $r)) { $parentInScope = $true; break }
        }
        if (-not $parentInScope) {
            $reasons.Add('parent OU outside managed-OU scope')
        }
        return @{
            Allowed = ($reasons.Count -eq 0)
            Reason  = ($reasons -join '; ')
        }
    }

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
        # WR-07 fix: coerce both sides to string explicitly. If $script:DenyRids was
        # loaded from JSON as integers (e.g. [512] rather than ['512']), the case-sensitive
        # string -in comparison would fail silently and the deny-list would be bypassed.
        $rid = [string]([System.Security.Principal.SecurityIdentifier]$sid).Value.Split('-')[-1]
        $denyStrings = @($script:DenyRids | ForEach-Object { [string]$_ })
        if ($rid -in $denyStrings) {
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
    #     D-04 asymmetry: SKIPPED when Operation='Remove-ADGroupMember' - the membership IS the
    #     state being remediated, so refusing on it makes remediation impossible.
    if ($Operation -ne 'Remove-ADGroupMember') {
        $dnEsc = Escape-AdmanLdapFilterValue -Value $targetDn
        $or = ''
        foreach ($g in @($script:ProtectedGroupDns)) {
            if ([string]::IsNullOrWhiteSpace([string]$g)) { continue }
            $gEsc = Escape-AdmanLdapFilterValue -Value ([string]$g)
            $or += "(memberOf:1.2.840.113556.1.4.1941:=$gEsc)"
        }
        if (-not [string]::IsNullOrEmpty($or)) {
            # WR-02: contract is a hashtable return, not a throw. If the DC is unreachable,
            # record a refusal reason instead of letting the exception propagate.
            # WR-05 fix: distinguish infrastructure failures (DC unreachable / network /
            # timeout) from query/parse failures. Both fail closed (safety invariant), but
            # the reason text categorizes the failure so the operator can tell a transient
            # DC outage from a policy refusal, and so internal DC topology details from
            # infrastructure error messages are not leaked verbatim into the audit log.
            try {
                $hit = Get-ADObject -Server $script:Config.DC `
                    -LDAPFilter "(&(distinguishedName=$dnEsc)(|$or))" -ErrorAction Stop
                if ($hit) {
                    $reasons.Add('recursive member of protected group')
                }
            } catch {
                $exc = $_.Exception
                $isInfra = $false
                # Walk the exception chain looking for well-known infrastructure error types.
                while ($null -ne $exc) {
                    $tname = $exc.GetType().FullName
                    if ($tname -match 'System\.DirectoryServices\.AccountManagement\.PrincipalServerDownException' -or
                        $tname -match 'System\.Net\.Sockets\.SocketException' -or
                        $tname -match 'System\.DirectoryServices\.Protocols\.LdapException' -or
                        $tname -match 'Microsoft\.ActiveDirectory\.Management\.ADServerDownException' -or
                        $tname -match 'Microsoft\.ActiveDirectory\.Management\.ADIdentityNotFoundException' -or
                        ($exc.PSObject.Properties['HResult'] -and ($exc.HResult -eq -2147023541 -or $exc.HResult -eq -2147016646))) {
                        $isInfra = $true
                        break
                    }
                    $exc = $exc.InnerException
                }
                if ($isInfra) {
                    # Infrastructure failure: do NOT leak the raw exception message (may
                    # contain DC hostnames / topology). Categorize so operator knows to
                    # retry rather than treat as a policy refusal.
                    $reasons.Add('protected-membership check unavailable: DC unreachable (infrastructure failure; fail-closed)')
                } else {
                    $reasons.Add("protected-membership check failed: $($_.Exception.Message)")
                }
            }
        }
    }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}
