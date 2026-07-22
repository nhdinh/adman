#Requires -Version 5.1
Set-StrictMode -Version Latest

function Restore-AdmanQuarantinedUser {
    <#
    .SYNOPSIS
        Restore-AdmanQuarantinedUser - reverse offboarding from the authoritative audit log (FLOW-03).

    .DESCRIPTION
        Reverses a successful offboarding by re-adding the recorded groups, moving the user
        back to the original OU, and enabling the account last. This ordering invariant
        ensures that a partial restore leaves the account disabled.

        Safety behavior:
          * The target must currently be in the configured quarantine OU; otherwise the
            restore is refused before any AD write or confirmation.
          * Restore state is read from the latest successful, non-dry-run offboarding audit
            record matched by exact user DN or SID. Get-AdmanOffboardingState performs this
            lookup: it searches all audit-*.jsonl files in the live audit directory and in
            the rotated archive folders under .store/audit/archive/YYYYMM/. There is no
            arbitrary lookback cutoff, so restore works as long as the archive file exists.
          * Audit files are retained in the live audit directory for the configured
            audit.retentionDays value (default 90) and then moved into
            .store/audit/archive/YYYYMM/ by Invoke-AdmanAuditRotation (D-05 / 05-03).
          * The recorded original OU is re-checked against managed-OU roots before the move.
          * One outer Confirm-AdmanAction gates the whole job; inner verbs are called with
            -Force:$true so they do not re-prompt.
          * A mid-workflow failure stops later steps and writes a Failure audit before
            rethrowing (FLOW-04).

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is missing.

    .PARAMETER Identity
        The quarantined user to restore. Accepts sAMAccountName, DN, GUID, or UPN.

    .PARAMETER Force
        Skip the workflow confirmation prompt.

    .EXAMPLE
        Restore-AdmanQuarantinedUser -Identity 'jdoe-fake'

    .EXAMPLE
        Restore-AdmanQuarantinedUser -Identity 'jdoe-fake' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [switch]$Force
    )

    Assert-AdmanInitialized

    if (-not $script:Config.PSObject.Properties['templates'] -or
        $null -eq $script:Config.templates -or
        -not $script:Config.templates.PSObject.Properties['offboarding'] -or
        $null -eq $script:Config.templates.offboarding) {
        throw 'Offboarding template is missing from config (templates.offboarding).'
    }
    $template = $script:Config.templates.offboarding

    if (-not $template.PSObject.Properties['quarantineOU'] -or
        [string]::IsNullOrWhiteSpace([string]$template.quarantineOU)) {
        throw "Offboarding template is missing required key 'quarantineOU'."
    }
    $quarantineOu = [string]$template.quarantineOU

    # Resolve the target once; preview and execute use the same object (SAFE-10).
    $user = Resolve-AdmanTarget -Targets @($Identity) | Select-Object -First 1
    if ($null -eq $user) {
        throw "Identity '$Identity' could not be resolved to a single user."
    }

    # CR-01: after Move-AdmanUser changes the DN, re-resolution by DN fails. Use the
    # stable sAMAccountName for all composed verbs; fall back to the original input
    # for mocks/deserialized objects that lack SamAccountName.
    $stableIdentity = if ($user.PSObject.Properties['SamAccountName'] -and $user.SamAccountName) {
        $user.SamAccountName
    } else {
        $Identity
    }

    # The account must currently be in the configured quarantine OU.
    $currentParent = ConvertTo-AdmanParentDn -Dn $user.DistinguishedName
    $currentNorm = ConvertTo-AdmanNormalizedDn -Dn $currentParent
    $quarantineNorm = ConvertTo-AdmanNormalizedDn -Dn $quarantineOu
    if ($currentNorm -ne $quarantineNorm) {
        throw 'User is not currently in the quarantine OU; refusing restore.'
    }

    $state = Get-AdmanOffboardingState -Identity $stableIdentity
    if ($null -eq $state) {
        throw "No successful offboarding state found for '$stableIdentity'; cannot restore."
    }

    # Re-check the recorded original OU is under managed roots (T-04-14).
    $orig = ConvertTo-AdmanNormalizedDn -Dn $state.OriginalOU
    $origInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($orig -eq $r -or $orig.EndsWith(',' + $r)) { $origInScope = $true; break }
    }
    if (-not $origInScope) {
        throw "Recorded original OU '$($state.OriginalOU)' is outside managed OU scope."
    }

    # Single outer confirmation for the whole workflow (FLOW-03).
    $confirm = Confirm-AdmanAction -Verb 'Restore-AdmanQuarantinedUser' -Targets @($user) -Force:$Force
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    try {
        # Re-add groups first, then move, then enable last so a partial failure leaves
        # the account disabled.
        foreach ($g in @($state.Groups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $null = Add-AdmanGroupMember -Identity $stableIdentity -GroupIdentity $g `
                -Force:$true -WhatIf:$WhatIfPreference
        }

        $null = Move-AdmanUser -Identity $stableIdentity -TargetPath $state.OriginalOU `
            -Force:$true -WhatIf:$WhatIfPreference

        $null = Enable-AdmanUser -Identity $stableIdentity -Force:$true -WhatIf:$WhatIfPreference

        $null = Write-AdmanAudit -Verb 'Restore-AdmanQuarantinedUser' -Target $user `
            -Result 'Success' -WhatIf:$WhatIfPreference
    } catch {
        $null = Write-AdmanAudit -Verb 'Restore-AdmanQuarantinedUser' -Target $user `
            -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$WhatIfPreference
        throw
    }
}
