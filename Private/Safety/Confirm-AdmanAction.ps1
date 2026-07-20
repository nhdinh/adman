#Requires -Version 5.1
<#
.SYNOPSIS
    Confirm-AdmanAction - scaled confirmation returning an Outcome shape (SAFE-01/02; C3-H1).

.DESCRIPTION
    Returns @{ Outcome = 'Proceed' | 'DryRun' | 'Declined'; WhatIf = [bool] }. This function
    NEVER writes an audit record and NEVER throws the decline message - the GATE owns both
    (confirm-first: a declined action has no PENDING reservation to orphan, so nothing is
    audited). The only throw permitted here is the typed-count mismatch ("Confirmation failed").

    Order is load-bearing - check -WhatIf FIRST, before any prompt and before reading a
    ShouldProcess $false as a decline:
      (1) $isWhatIf = [bool]$WhatIfPreference. If truthy (a REAL -WhatIf; the engine sets a
          SwitchParameter $true, NEVER the string 'Simulate'), emit the what-if line once and
          RETURN Outcome='DryRun'/WhatIf=$true. No Read-Host, no throw, no audit write. A
          ShouldProcess $false under -WhatIf is the simulation, NOT a refusal.
      (2) Else if (-not $Force -and ($ConfirmPreference -ne 'None')):
            - at/above threshold -> Read-Host exact-count token; if ($token -cne "$count") throw
              "Confirmation failed: expected $count. Refused." (case-sensitive exact match; no
              Enter-to-accept).
            - below threshold -> if (-not $PSCmdlet.ShouldProcess("$count object(s)", $Verb))
              RETURN Outcome='Declined'/WhatIf=$false (a GENUINE decline; this function writes
              nothing - the gate throws the decline message and writes no record).
      (3) RETURN Outcome='Proceed'/WhatIf=$false.

    NEVER read the automatic confirm-flag variable (StrictMode, issue #14294); test suppression
    via $ConfirmPreference -eq 'None'. -Force / -Confirm:$false skip ONLY this prompt - deny /
    protected / scope / cap already ran upstream (non-bypassable).
#>

Set-StrictMode -Version Latest

function Confirm-AdmanAction {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Verb,
        [Parameter(Mandatory)]
        $Targets,
        [string]$Group,
        [switch]$RequireTypedCount,
        [switch]$Force
    )

    $count = @($Targets).Count
    $threshold = [int]$script:Config.safety.bulkConfirmThreshold   # default 5 (D-07)
    # WR-02 fix: data-driven per-verb typed-count override. Verbs listed in
    # safety.typedCountVerbs (default @('Remove-LocalUser'); D-03) force typed-count
    # confirmation even at count=1, regardless of bulkConfirmThreshold. Adding a new
    # irreversible verb no longer requires a code change here.
    $typedCountVerbs = @('Remove-LocalUser')
    if ($script:Config.PSObject.Properties['safety'] -and
        $null -ne $script:Config.safety -and
        $script:Config.safety.PSObject.Properties['typedCountVerbs'] -and
        $null -ne $script:Config.safety.typedCountVerbs) {
        $typedCountVerbs = @($script:Config.safety.typedCountVerbs | ForEach-Object { [string]$_ })
    }
    if ($Verb -in $typedCountVerbs) { $threshold = 1 }

    # D-04: when -Group is supplied, render the group in the prompt so the operator sees
    # both sides of the membership change.
    $targetDesc = "$count object(s)"
    if (-not [string]::IsNullOrEmpty($Group)) {
        $targetDesc = "$count object(s) -> group $Group"
    }

    # (1) -WhatIf FIRST: a real -WhatIf is a dry-run, NOT a decline. The discriminator is the
    #     boolean cast [bool]$WhatIfPreference (truthy under a real -WhatIf: the engine sets a
    #     SwitchParameter $true). It is NEVER a string comparison against the literal word
    #     'Simulate' - the engine never produces that string, so such a comparison is $false in
    #     every state and would misclassify every dry-run as a decline (C3-H1).
    $isWhatIf = [bool]$WhatIfPreference
    if ($isWhatIf) {
        # Under -WhatIf this ShouldProcess returns $false by design - that $false is the
        # simulation, NOT a refusal. Emit the what-if line once and return DryRun.
        [void]$PSCmdlet.ShouldProcess($targetDesc, $Verb)
        return @{ Outcome = 'DryRun'; WhatIf = $true }
    }

    # (2) Prompt unless -Force / -Confirm:$false (ConfirmPreference='None'). Skips ONLY the prompt.
    if (-not $Force -and ($ConfirmPreference -ne 'None')) {
        if ($RequireTypedCount -or ($count -ge $threshold)) {
            $token = Read-Host "Type the exact count ($count) to $Verb these $targetDesc"
            if ($token -cne "$count") {
                throw "Confirmation failed: expected $count. Refused."
            }
        } else {
            if (-not $PSCmdlet.ShouldProcess($targetDesc, $Verb)) {
                # GENUINE decline (no -WhatIf). This function writes nothing; the gate throws the
                # decline message and writes no record (confirm-first -> no orphan PENDING).
                return @{ Outcome = 'Declined'; WhatIf = $false }
            }
        }
    }

    # (3) Proceed.
    return @{ Outcome = 'Proceed'; WhatIf = $false }
}
