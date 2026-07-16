#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanMutation - THE GATE: the single, non-exported mutation funnel (SAFE-08).

.DESCRIPTION
    Every destructive action flows through this one gate. It is Private/ and NOT exported
    (excluded from FunctionsToExport since 00-01). It never calls an AD write cmdlet directly -
    only via & "Adman.AD.Write.$Verb". The ValidateSet is the SAFE-09 boundary: the hard-delete
    verb is deliberately ABSENT (the same 10 verbs as Get-AdmanAllowedWriteVerbs; a test asserts
    they cannot drift).

    Fixed order (do not reorder):
      Resolve-AdmanTarget (ONCE - SAFE-10: the same array feeds preview AND execute) ->
        [New-ADUser: Resolve-AdmanCreateTarget instead - synthetic pre-create target (D-01)] ->
      [New-ADUser: uniqueness pre-flight - sAMAccountName OR CN collision refuses BEFORE confirm] ->
      [Move-ADObject: TargetPath managed-OU validator - refuses BEFORE confirm] ->
      [Add/Remove-ADGroupMember: dual resolution - member via Resolve-AdmanTarget, group via
        Resolve-AdmanGroup; Test-AdmanGroupAllowed on the group (D-04)] ->
      Test-AdmanTargetAllowed (per target; refusals logged 'Refused' + skipped) ->
      Assert-AdmanBulkPolicy (cap placeholder - Phase 4 enforces; threshold source) ->
      Confirm-AdmanAction (returns @{ Outcome; WhatIf } - WhatIf-aware, C3-H1) ->
      Write-AdmanAudit(Result='PENDING') [the 00-05 writer THROWS on failure => refusal BEFORE
        the write below; whatIf=$true under a dry-run] ->
      & "Adman.AD.Write.$Verb" -WhatIf:$confirm.WhatIf -Confirm:$false [the ONE real write;
        no-ops under -WhatIf -> truthful preview; no per-object re-prompt] ->
      Write-AdmanAudit(Result='Success') [OUTCOME best-effort; whatIf=$true under a dry-run].

    Outcome branching (C3-H1): Outcome='Proceed' and Outcome='DryRun' BOTH reach the PENDING
    audit + inner wrapper (WhatIf flag from the shape: Proceed->$false, DryRun->$true). ONLY
    Outcome='Declined' throws the decline message in the gate and writes NOTHING (no PENDING, no
    abort/cancel-style record) so a declined action leaves no orphan PENDING (confirm-first).
    -Force is forwarded to Confirm-AdmanAction only (prompt bypass); deny/protected/scope/cap are
    not flag-bypassable.

    HIGH #1: the wrapper invocation is wrapped in try/catch. On catch the gate writes
    Write-AdmanAudit -Result 'Failure' -Reason <exception> BEFORE rethrowing, so a wrapper
    throw never leaves a PENDING orphan.
#>

Set-StrictMode -Version Latest

function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Disable-ADAccount', 'Enable-ADAccount', 'Move-ADObject',
            'Set-ADUser', 'Set-ADComputer', 'Set-ADAccountPassword', 'Unlock-ADAccount',
            'Add-ADGroupMember', 'Remove-ADGroupMember', 'New-ADUser')]   # SAFE-09: hard-delete verb deliberately ABSENT
        [string]$Verb,
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [hashtable]$Parameters = @{},
        [switch]$Force
    )

    $cid = [guid]::NewGuid().ToString()

    # SAFE-10: ONE resolver, called once. The same array feeds preview AND execute.
    # D-01: New-ADUser routes through the synthetic pre-create resolver (the object does
    # not exist yet, so Get-ADObject -Identity would throw).
    $resolved = @()
    if ($Verb -eq 'New-ADUser') {
        $resolved = @(Resolve-AdmanCreateTarget `
                -Name $Parameters['Name'] `
                -SamAccountName $Parameters['SamAccountName'] `
                -ParentOuDn $Parameters['ParentOuDn'])
    } else {
        $resolved = @(Resolve-AdmanTarget -Targets $Targets)
    }

    # D-01 uniqueness pre-flight (New-ADUser only): sAMAccountName OR CN collision refuses
    # BEFORE confirm. The CN check uses -SearchScope OneLevel because AD enforces CN
    # uniqueness within the immediate parent container only; the default Subtree scope
    # would over-refuse a valid create when a same-CN object exists in a child OU.
    if ($Verb -eq 'New-ADUser') {
        $samEsc = Escape-AdmanAdFilterLiteral -Value ([string]$Parameters['SamAccountName'])
        $cnEsc = Escape-AdmanAdFilterLiteral -Value ([string]$Parameters['Name'])
        $parentDn = [string]$Parameters['ParentOuDn']

        # WR-06 fix: include the conflicting object's DistinguishedName in the refusal so
        # the operator can locate the collision even when it lives in an unmanaged OU
        # they cannot browse. AD enforces sAMAccountName uniqueness forest-wide, so the
        # check itself remains correct without a -SearchBase; the DN is the diagnostic.
        $samHit = Get-ADObject -Filter "sAMAccountName -eq '$samEsc'" `
            -Server $script:Config.DC -Properties DistinguishedName -ErrorAction Stop
        if ($samHit) {
            throw "sAMAccountName '$($Parameters['SamAccountName'])' already exists at '$($samHit.DistinguishedName)'."
        }
        $cnHit = Get-ADObject -Filter "cn -eq '$cnEsc'" `
            -SearchBase $parentDn -SearchScope OneLevel `
            -Server $script:Config.DC -Properties DistinguishedName -ErrorAction Stop
        if ($cnHit) {
            throw "CN '$($Parameters['Name'])' already exists in parent OU '$parentDn' at '$($cnHit.DistinguishedName)'."
        }
    }

    # Move-ADObject TargetPath validator (gate-side enforcement): the destination must be
    # under a managed root. This runs BEFORE Test-AdmanTargetAllowed so direct gate callers
    # cannot bypass it (Public verbs MAY keep their own early check for UX fail-fast, but
    # this check is the authoritative enforcement point).
    if ($Verb -eq 'Move-ADObject') {
        $targetPath = [string]$Parameters['TargetPath']
        $tp = (ConvertTo-AdmanNormalizedDn -Dn $targetPath)
        $tpInScope = $false
        foreach ($root in @($script:Config.ManagedOUs)) {
            $r = (ConvertTo-AdmanNormalizedDn -Dn ([string]$root))
            if ([string]::IsNullOrEmpty($r)) { continue }
            if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
        }
        if (-not $tpInScope) {
            throw "TargetPath '$targetPath' is outside managed OU scope."
        }
    }

    # D-04 dual-resolution group path: resolve the GROUP once and run Test-AdmanGroupAllowed
    # on it. The MEMBER side flows through Test-AdmanTargetAllowed unchanged below.
    $groupObj = $null
    if ($Verb -eq 'Add-ADGroupMember' -or $Verb -eq 'Remove-ADGroupMember') {
        $groupObj = Resolve-AdmanGroup -Identity $Parameters['GroupIdentity']
        $groupDecision = Test-AdmanGroupAllowed -Object $groupObj -Operation $Verb
        if (-not $groupDecision.Allowed) {
            # G-02-9: write one Refused record PER MEMBER so the audit names the member DN
            # (target field) AND the group DN (group field) - forensics can tell which member
            # the add was attempted on.
            foreach ($memberObj in $resolved) {
                Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $memberObj -Result 'Refused' `
                    -Reason $groupDecision.Reason -Group $groupObj.DistinguishedName `
                    -WhatIf:$WhatIfPreference
            }
            # G-02-6: surface the refusal reason to the operator before throwing.
            Write-Warning "Group refused: $($groupDecision.Reason)"
            throw "Group refused: $($groupDecision.Reason)"
        }
    }

    # Deny / protected / scope: refusals logged 'Refused' and skipped (never reach the write).
    # G-02-8: pass -Operation $Verb unconditionally so Test-AdmanTargetAllowed can skip step (d)
    # recursive protected-membership on Remove-ADGroupMember (D-04 remediation asymmetry).
    $allowed = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $resolved) {
        $decision = Test-AdmanTargetAllowed -Object $t -Operation $Verb
        if (-not $decision.Allowed) {
            if ($groupObj) {
                Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' `
                    -Reason $decision.Reason -Group $groupObj.DistinguishedName `
                    -WhatIf:$WhatIfPreference
            } else {
                Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' `
                    -Reason $decision.Reason -WhatIf:$WhatIfPreference
            }
            # G-02-6: surface the precise refusal reason to the operator (not just 'Denied: 1').
            Write-Warning "Refused $($t.DistinguishedName): $($decision.Reason)"
        } else {
            $allowed.Add($t)
        }
    }

    if ($allowed.Count -eq 0) {
        return [pscustomobject]@{
            Action        = $Verb
            Targets       = $Targets
            Denied        = $resolved.Count
            Succeeded     = 0
            Failed        = 0
            WhatIf        = [bool]$WhatIfPreference
            CorrelationId = $cid
        }
    }

    # Cap placeholder (Phase 4 enforces) + threshold source.
    Assert-AdmanBulkPolicy -Count $allowed.Count | Out-Null

    # SAFE-02: scaled confirmation. Returns @{ Outcome; WhatIf } (WhatIf-aware; C3-H1). No
    # -CorrelationId - Confirm-AdmanAction never writes audit.
    if ($groupObj) {
        $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() `
            -Group $groupObj.DistinguishedName -Force:$Force
    } else {
        $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force
    }

    # Genuine decline: write NOTHING (no PENDING, no abort/cancel-style record) and never mutate.
    # confirm-first -> no orphan PENDING (C3-H1).
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    # Write-ahead reservation: the 00-05 writer THROWS on PENDING-write failure => the refusal
    # happens BEFORE the write below (SAFE-04). whatIf=$true under a dry-run.
    if ($groupObj) {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
            -Result 'PENDING' -Group $groupObj.DistinguishedName -WhatIf:$confirm.WhatIf
    } else {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
            -Result 'PENDING' -WhatIf:$confirm.WhatIf
    }

    # The ONE real write (no-ops under -WhatIf -> truthful preview); no per-object re-prompt.
    # HIGH #1: try/catch writes a Failure outcome audit record on wrapper throw BEFORE
    # rethrowing, so a wrapper exception never leaves a PENDING orphan.
    try {
        & "Adman.AD.Write.$Verb" -Objects $allowed.ToArray() -Parameters $Parameters `
            -WhatIf:$confirm.WhatIf -Confirm:$false
    } catch {
        if ($groupObj) {
            Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
                -Result 'Failure' -Reason $_.Exception.Message `
                -Group $groupObj.DistinguishedName -WhatIf:$confirm.WhatIf
        } else {
            Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
                -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$confirm.WhatIf
        }
        throw
    }

    # OUTCOME best-effort (whatIf=$true under a dry-run).
    if ($groupObj) {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
            -Result 'Success' -Group $groupObj.DistinguishedName -WhatIf:$confirm.WhatIf
    } else {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
            -Result 'Success' -WhatIf:$confirm.WhatIf
    }

    return [pscustomobject]@{
        Action        = $Verb
        Targets       = @($allowed | ForEach-Object { $_.DistinguishedName })
        Denied        = ($resolved.Count - $allowed.Count)
        Succeeded     = $allowed.Count
        Failed        = 0
        WhatIf        = [bool]$confirm.WhatIf
        CorrelationId = $cid
    }
}
