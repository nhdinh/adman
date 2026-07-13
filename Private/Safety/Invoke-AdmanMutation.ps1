#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanMutation - THE GATE: the single, non-exported mutation funnel (SAFE-08).

.DESCRIPTION
    Every destructive action flows through this one gate. It is Private/ and NOT exported
    (excluded from FunctionsToExport since 00-01). It never calls an AD write cmdlet directly -
    only via & "Adman.AD.Write.$Verb". The ValidateSet is the SAFE-09 boundary: the hard-delete
    verb is deliberately ABSENT (the same 9 verbs as Get-AdmanAllowedWriteVerbs; a test asserts
    they cannot drift).

    Fixed order (do not reorder):
      Resolve-AdmanTarget (ONCE - SAFE-10: the same array feeds preview AND execute) ->
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
#>

Set-StrictMode -Version Latest

function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Disable-ADAccount', 'Enable-ADAccount', 'Move-ADObject',
            'Set-ADUser', 'Set-ADComputer', 'Set-ADAccountPassword', 'Unlock-ADAccount',
            'Add-ADGroupMember', 'Remove-ADGroupMember')]   # SAFE-09: hard-delete verb deliberately ABSENT
        [string]$Verb,
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [hashtable]$Parameters = @{},
        [switch]$Force
    )

    $cid = [guid]::NewGuid().ToString()

    # SAFE-10: ONE resolver, called once. The same array feeds preview AND execute.
    $resolved = @(Resolve-AdmanTarget -Targets $Targets)

    # Deny / protected / scope: refusals logged 'Refused' and skipped (never reach the write).
    $allowed = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $resolved) {
        $decision = Test-AdmanTargetAllowed -Object $t
        if (-not $decision.Allowed) {
            Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' `
                -Reason $decision.Reason -WhatIf:$WhatIfPreference
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
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force

    # Genuine decline: write NOTHING (no PENDING, no abort/cancel-style record) and never mutate.
    # confirm-first -> no orphan PENDING (C3-H1).
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    # Write-ahead reservation: the 00-05 writer THROWS on PENDING-write failure => the refusal
    # happens BEFORE the write below (SAFE-04). whatIf=$true under a dry-run.
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() -Result 'PENDING' `
        -WhatIf:$confirm.WhatIf

    # The ONE real write (no-ops under -WhatIf -> truthful preview); no per-object re-prompt.
    & "Adman.AD.Write.$Verb" -Objects $allowed.ToArray() -Parameters $Parameters `
        -WhatIf:$confirm.WhatIf -Confirm:$false

    # OUTCOME best-effort (whatIf=$true under a dry-run).
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() -Result 'Success' `
        -WhatIf:$confirm.WhatIf

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
