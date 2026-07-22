#Requires -Version 5.1
Set-StrictMode -Version Latest

function Start-AdmanUserOnboarding {
    <#
    .SYNOPSIS
        Start-AdmanUserOnboarding - gated new-user onboarding workflow (FLOW-01, D-08..D-18).

    .DESCRIPTION
        Composes New-AdmanUser and Add-AdmanGroupMember under a single outer confirmation.
        The request is built from the config-driven onboarding template
        ($script:Config.templates.onboarding):

          * NamePattern formats the generated sAMAccountName from FirstName and LastName.
          * The top-level domain key builds the UPN as sAMAccountName@domain.
          * ParentOuDn is the authoritative destination OU; the operator cannot override it.
          * BaselineGroups are validated through Test-AdmanGroupAllowed before any user
            creation or group add (D-17 / T-04-08).

        Safety behavior:
          * Empty FirstName/LastName are rejected at parameter binding.
          * The generated sAMAccountName is preflighted before confirmation: non-empty,
            length <= 20, and no wildcard characters (*, ?).
          * One outer Confirm-AdmanAction gates the whole job; inner verbs are called with
            -Force:$true so they do not re-prompt (review finding / FLOW-01).
          * A mid-workflow failure stops later steps for that target and writes a Failure
            audit before rethrowing (FLOW-04 / T-04-09).
          * -WhatIf propagates to New-AdmanUser and every Add-AdmanGroupMember.
          * Password display-once hygiene is owned by New-AdmanUser (D-14); this workflow
            does NOT duplicate it.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is missing.

    .PARAMETER FirstName
        The new user's first name.

    .PARAMETER LastName
        The new user's last name.

    .PARAMETER Force
        Skip the workflow confirmation prompt.

    .EXAMPLE
        Start-AdmanUserOnboarding -FirstName 'Jane-fake' -LastName 'Doe-fake'

    .EXAMPLE
        Start-AdmanUserOnboarding -FirstName 'Jane-fake' -LastName 'Doe-fake' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LastName,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Validate the onboarding template is present and carries the required keys (D-09).
    if (-not $script:Config.PSObject.Properties['templates'] -or
        $null -eq $script:Config.templates -or
        -not $script:Config.templates.PSObject.Properties['onboarding'] -or
        $null -eq $script:Config.templates.onboarding) {
        throw 'Onboarding template is missing from config (templates.onboarding).'
    }
    $template = $script:Config.templates.onboarding

    foreach ($key in @('ParentOuDn', 'BaselineGroups', 'NamePattern')) {
        if (-not $template.PSObject.Properties[$key]) {
            throw "Onboarding template is missing required key '$key'."
        }
        if ($key -eq 'BaselineGroups') {
            if ($null -eq $template.$key) {
                throw "Onboarding template is missing required key '$key'."
            }
        } elseif ($key -eq 'NamePattern') {
            if ([string]::IsNullOrWhiteSpace([string]$template.$key)) {
                throw "Onboarding template is missing required key '$key'."
            }
            # WR-06: validate NamePattern is a usable two-argument format string before
            # the preflight checks run, so malformed patterns produce a clear error.
            try {
                $null = $template.NamePattern -f 'First', 'Last'
            } catch {
                throw "Onboarding template NamePattern '$($template.NamePattern)' is not a valid two-argument format string: $_"
            }
        } elseif ([string]::IsNullOrWhiteSpace([string]$template.$key)) {
            throw "Onboarding template is missing required key '$key'."
        }
    }

    # Domain is required to build the UPN (review finding / D-11).
    if (-not $script:Config.PSObject.Properties['domain'] -or
        [string]::IsNullOrWhiteSpace([string]$script:Config.domain)) {
        throw 'Onboarding template is missing the domain key; cannot build UPN.'
    }
    $domain = [string]$script:Config.domain

    # Build the derived identity.
    $sam = ([string]($template.NamePattern -f $FirstName, $LastName)).ToLower()
    $upn = "$sam@$domain"

    # Preflight the generated sAMAccountName before any group validation or confirmation
    # (review finding / T-04-10).
    if ([string]::IsNullOrWhiteSpace($sam)) {
        throw 'Generated sAMAccountName is empty. Check the onboarding NamePattern.'
    }
    if ($sam.Length -gt 20) {
        throw "Generated sAMAccountName '$sam' exceeds the 20-character limit (got $($sam.Length))."
    }
    if ($sam -match '^\s|\s$') {
        throw "Generated sAMAccountName '$sam' has leading or trailing whitespace."
    }
    if ($sam -match '["\[\]:|<>+=;]') {
        throw "Generated sAMAccountName '$sam' contains characters not allowed in AD sAMAccountName."
    }
    if ($sam -match '[\*\?]') {
        throw "Generated sAMAccountName '$sam' contains wildcard characters (* or ?)."
    }

    # Validate every baseline group before creating the user or adding memberships (D-17).
    $baselineGroups = @($template.BaselineGroups)
    foreach ($g in $baselineGroups) {
        $groupObj = Resolve-AdmanGroup -Identity $g
        $decision = Test-AdmanGroupAllowed -Object $groupObj -Operation 'Add-ADGroupMember'
        if (-not $decision.Allowed) {
            throw "Baseline group '$g' refused: $($decision.Reason)"
        }
    }

    # Single outer confirmation for the whole workflow (FLOW-01).
    $confirm = Confirm-AdmanAction -Verb 'Start-AdmanUserOnboarding' -Targets @($sam) -Force:$Force
    if ($confirm.Outcome -eq 'Declined') {
        throw 'Operator declined.'
    }

    try {
        # Create the user. New-AdmanUser owns password sourcing/display-once hygiene (D-14).
        $null = New-AdmanUser -Name "$FirstName $LastName" -SamAccountName $sam `
            -UserPrincipalName $upn -ParentOuDn ([string]$template.ParentOuDn) `
            -Force:$true -WhatIf:$WhatIfPreference

        # Add baseline groups. A failure stops subsequent adds for this target (FLOW-04).
        foreach ($g in $baselineGroups) {
            $null = Add-AdmanGroupMember -Identity $sam -GroupIdentity $g `
                -Force:$true -WhatIf:$WhatIfPreference
        }
    } catch {
        Write-AdmanAudit -Verb 'Start-AdmanUserOnboarding' -Target $sam `
            -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$WhatIfPreference
        throw
    }
}
