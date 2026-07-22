#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanLocalMutation - THE LOCAL GATE: the single, non-exported local mutation
    funnel (D-02).

.DESCRIPTION
    Mirrors the AD gate's fixed order byte-for-byte but swaps the resolver to
    Resolve-AdmanLocalTarget, the policy to Test-AdmanLocalTargetAllowed, and the wrapper
    namespace to Adman.Local.Write.*. ValidateSet is the seven-verb local set. The audit
    Target records MACHINE\username + local SID (no DN); the result object's Targets array
    formats as "{Machine}\{Name}".

    Fixed order (do not reorder):
      Resolve-AdmanLocalTarget (ONCE - SAFE-10) ->
        [New-LocalUser: create-branch synthetic target (D-02 BLOCKER fix)] ->
      [New-LocalUser: uniqueness pre-flight - Get-LocalUser hit refuses BEFORE confirm] ->
      Test-AdmanLocalTargetAllowed (per target; refusals logged 'Refused' + skipped) ->
      Assert-AdmanBulkPolicy (cap placeholder) ->
      Confirm-AdmanAction (returns @{ Outcome; WhatIf }) ->
      Write-AdmanAudit(Result='PENDING') [THROWS on failure => refusal BEFORE the write] ->
      & "Adman.Local.Write.$Verb" -WhatIf:$confirm.WhatIf -Confirm:$false ->
      Write-AdmanAudit(Result='Success').

    TOCTOU closure (D-02 BLOCKER fix): the uniqueness pre-flight runs BEFORE confirm, but a
    race between pre-flight and write is closed by letting New-LocalUser itself throw on
    collision; the wrapper's -ErrorAction Stop propagates the throw and the OUTCOME audit
    write records Result='Failure' with the exception message.

    HIGH #1: the wrapper invocation is wrapped in try/catch. On catch the gate writes
    Write-AdmanAudit -Result 'Failure' -Reason <exception> BEFORE rethrowing, so a wrapper
    throw never leaves a PENDING orphan.
#>

Set-StrictMode -Version Latest

function Invoke-AdmanLocalMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('New-LocalUser', 'Disable-LocalUser', 'Enable-LocalUser',
            'Set-LocalUser', 'Remove-LocalUser',
            'Add-LocalGroupMember', 'Remove-LocalGroupMember')]
        [string]$Verb,
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [hashtable]$Parameters = @{},
        [switch]$Force
    )

    $cid = [guid]::NewGuid().ToString()

    # CR-01: fail-closed initialization guard. Local mutations share the same safety caches
    # (DenyRids, ProtectedSIDs, ProtectedGroupDns) as AD mutations; refuse if they are not ready.
    Assert-AdmanInitialized

    # SAFE-10: ONE resolver, called once. New-LocalUser routes through the create-branch
    # (synthetic target; the object does not exist yet, so Get-LocalUser would throw).
    $resolved = @()
    if ($Verb -eq 'New-LocalUser') {
        $resolved = @(Resolve-AdmanLocalTarget -Targets $Targets `
                -ComputerName $Parameters['ComputerName'] -Verb $Verb -Create)
    } else {
        $resolved = @(Resolve-AdmanLocalTarget -Targets $Targets `
                -ComputerName $Parameters['ComputerName'] -Verb $Verb)
    }

    # Uniqueness pre-flight (New-LocalUser only): Get-LocalUser hit refuses BEFORE confirm.
    if ($Verb -eq 'New-LocalUser') {
        $proposed = [string]$Parameters['Name']
        $machine = if ($resolved.Count -gt 0) { $resolved[0].Machine } else { $env:COMPUTERNAME }
        $hit = Get-LocalUser -Name $proposed -ErrorAction SilentlyContinue
        if ($hit) {
            throw "local user '$proposed' already exists on $machine."
        }
    }

    # Deny / protected / scope: refusals logged 'Refused' and skipped (never reach the write).
    $allowed = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $resolved) {
        $decision = Test-AdmanLocalTargetAllowed -Object $t -Verb $Verb
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

    # SAFE-02: scaled confirmation. Returns @{ Outcome; WhatIf }.
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force

    # Genuine decline: write NOTHING and never mutate.
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    # Write-ahead reservation: the writer THROWS on PENDING-write failure => refusal BEFORE
    # the write below (SAFE-04).
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
        -Result 'PENDING' -WhatIf:$confirm.WhatIf

    # The ONE real write. HIGH #1: try/catch writes a Failure outcome audit record on
    # wrapper throw BEFORE rethrowing, so a wrapper exception never leaves a PENDING orphan.
    try {
        & "Adman.Local.Write.$Verb" -Objects $allowed.ToArray() -Parameters $Parameters `
            -WhatIf:$confirm.WhatIf -Confirm:$false
    } catch {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
            -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$confirm.WhatIf
        throw
    }

    # OUTCOME best-effort.
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
        -Result 'Success' -WhatIf:$confirm.WhatIf

    return [pscustomobject]@{
        Action        = $Verb
        Targets       = @($allowed | ForEach-Object { "{0}\{1}" -f $_.Machine, $_.Name })
        Denied        = ($resolved.Count - $allowed.Count)
        Succeeded     = $allowed.Count
        Failed        = 0
        WhatIf        = [bool]$confirm.WhatIf
        CorrelationId = $cid
    }
}
