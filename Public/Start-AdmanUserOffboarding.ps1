#Requires -Version 5.1
Set-StrictMode -Version Latest

function Start-AdmanUserOffboarding {
    <#
    .SYNOPSIS
        Start-AdmanUserOffboarding - reversible offboarding workflow (FLOW-02, D-19..D-21).

    .DESCRIPTION
        Composes Disable-AdmanUser, Remove-AdmanGroupMember, and Move-AdmanUser under a
        single outer confirmation. The workflow:

          * Resolves the target user and validates the configured quarantine OU is within
            a managed-OU root before any AD write or confirmation.
          * Classifies each group in the user's memberOf as protected or removable using
            resolved SIDs against $script:ProtectedSIDs, $script:DenyRids, and
            $script:ProtectedGroupDns (including unresolved-SID entries).
          * Presents one outer Confirm-AdmanAction; inner verbs are called with -Force:$true
            so they do not re-prompt (review finding / FLOW-02).
          * Disables the account, removes only non-protected groups, moves the account to
            the quarantine OU, and records the original OU and stripped groups in the audit
            log for restore (FLOW-03).
          * A mid-workflow failure stops later steps for that target; the failing inner verb
            writes its own Failure audit through the mutation gate, so this workflow does not
            duplicate it (FLOW-04).
          * After a successful offboarding, prints a plain-text checklist of typical cleanup
            items (mailbox, home directory, GPO) with explicit "manual only" wording; none
            of these are automated.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is missing.

    .PARAMETER Identity
        The user to offboard. Accepts sAMAccountName, DN, GUID, or UPN.

    .PARAMETER Force
        Skip the workflow confirmation prompt.

    .EXAMPLE
        Start-AdmanUserOffboarding -Identity 'jdoe-fake'

    .EXAMPLE
        Start-AdmanUserOffboarding -Identity 'jdoe-fake' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Validate the offboarding template is present and carries the required keys (D-19).
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

    # Validate quarantine OU under managed roots BEFORE any AD write or confirmation
    # (same boundary-anchored check as Move-AdmanUser, T-02-08).
    $q = ConvertTo-AdmanNormalizedDn -Dn $quarantineOu
    $qInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($q -eq $r -or $q.EndsWith(',' + $r)) { $qInScope = $true; break }
    }
    if (-not $qInScope) {
        throw "TargetPath '$quarantineOu' is outside managed OU scope."
    }

    # Resolve the target once; preview and execute use the same object (SAFE-10).
    $user = Resolve-AdmanTarget -Targets @($Identity) | Select-Object -First 1
    if ($null -eq $user) {
        throw "Identity '$Identity' could not be resolved to a single user."
    }

    $originalOu = ConvertTo-AdmanParentDn -Dn $user.DistinguishedName

    # Classify memberOf groups. Resolve each group and test SID/RID/DN against the
    # protected sets. If resolution fails, fall back to DN-string membership in
    # $script:ProtectedGroupDns (covers unresolved-SID entries stored there).
    if (-not $script:ProtectedSIDs -or -not $script:DenyRids -or -not $script:ProtectedGroupDns) {
        throw 'Protected identity caches are not initialized. Run Initialize-Adman first.'
    }
    $groupsToRemove = [System.Collections.Generic.List[string]]::new()
    foreach ($g in @($user.memberOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $isProtected = $false
        try {
            $group = Resolve-AdmanGroup -Identity $g
            $groupSid = if ($group.PSObject.Properties['objectSid']) { $group.objectSid } else { $null }
            $sidString = if ($null -eq $groupSid) {
                $null
            } elseif ($groupSid -is [System.Security.Principal.SecurityIdentifier]) {
                $groupSid.Value
            } else {
                [string]$groupSid
            }

            if (-not [string]::IsNullOrEmpty($sidString)) {
                if ($script:ProtectedSIDs -contains $sidString) {
                    $isProtected = $true
                } else {
                    $rid = ($sidString -split '-')[-1]
                    if ($script:DenyRids -contains $rid) { $isProtected = $true }
                }
            }
            if (-not $isProtected -and
                $group.PSObject.Properties['DistinguishedName'] -and
                $script:ProtectedGroupDns -contains $group.DistinguishedName) {
                $isProtected = $true
            }
        } catch {
            if ($script:ProtectedGroupDns -contains $g) { $isProtected = $true }
            if (-not $isProtected -and $g -like 'S-1-*') {
                if ($script:ProtectedSIDs -contains $g) { $isProtected = $true }
                $rid = ($g -split '-')[-1]
                if ($script:DenyRids -contains $rid) { $isProtected = $true }
            }
            if (-not $isProtected -and $g -match '^CN=.+') {
                try {
                    $fallbackGroup = Resolve-AdmanGroup -Identity $g
                    $fallbackSid = if ($fallbackGroup.objectSid -is [System.Security.Principal.SecurityIdentifier]) {
                        $fallbackGroup.objectSid.Value
                    } else {
                        [string]$fallbackGroup.objectSid
                    }
                    if ($script:ProtectedSIDs -contains $fallbackSid) { $isProtected = $true }
                    $fallbackRid = ($fallbackSid -split '-')[-1]
                    if ($script:DenyRids -contains $fallbackRid) { $isProtected = $true }
                } catch {
                    Write-Warning "Could not resolve group '$g' for protected-group classification: $_"
                }
            }
        }

        if (-not $isProtected) { $groupsToRemove.Add($g) }
    }

    # Single outer confirmation for the whole workflow (FLOW-02).
    $confirm = Confirm-AdmanAction -Verb 'Start-AdmanUserOffboarding' -Targets @($user) -Force:$Force -WhatIf:$WhatIfPreference
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    try {
        # Inner destructive verbs run with -Force:$true because the operator already
        # confirmed the whole workflow.
        $null = Disable-AdmanUser -Identity $Identity -Force:$true -WhatIf:$WhatIfPreference

        foreach ($g in $groupsToRemove) {
            $null = Remove-AdmanGroupMember -Identity $Identity -GroupIdentity $g `
                -Force:$true -WhatIf:$WhatIfPreference
        }

        $null = Move-AdmanUser -Identity $Identity -TargetPath $quarantineOu `
            -Force:$true -WhatIf:$WhatIfPreference

        $null = Write-AdmanAudit -Verb 'Start-AdmanUserOffboarding' -Target $user `
            -Result 'Success' -OriginalOU $originalOu -Groups @($groupsToRemove) `
            -WhatIf:$WhatIfPreference
    } catch {
        # WR-03 fix: inner verbs (Disable-AdmanUser / Remove-AdmanGroupMember /
        # Move-AdmanUser) already write their own Failure audit through the mutation gate.
        # Writing a second Failure record here would duplicate the entry with a different
        # correlation ID, so we rethrow without adding another audit.
        throw
    }

    # Cleanup checklist: surfaced as plain text only; no automation (FLOW-02 / T-04-13).
    # WR-02 fix: use Write-PSFMessage -Level Host instead of Write-Host so the cleanup
    # checklist respects PSFramework log sinks and stays out of the TUI-only Write-Host
    # suppression (the suppression belongs only in Start-Adman).
    if (-not $WhatIfPreference) {
        Write-PSFMessage -Level Host -Message "Offboarding complete for '$Identity'. Manual cleanup checklist:"
        Write-PSFMessage -Level Host -Message '  - Mailbox: archive or convert to shared mailbox (manual only)'
        Write-PSFMessage -Level Host -Message '  - Home directory: review, archive, or delete per retention policy (manual only)'
        Write-PSFMessage -Level Host -Message '  - GPO / profile: remove mapped drives, printers, and profile data (manual only)'
    }
}
