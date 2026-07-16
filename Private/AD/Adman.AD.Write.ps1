#Requires -Version 5.1
<#
.SYNOPSIS
    Adman.AD.Write - the gate-only raw AD write wrappers (SAFE-08/09).

.DESCRIPTION
    ONE thin wrapper per allow-listed verb. These wrappers are the ONLY code in the repo that
    names the real AD write cmdlets; the mutation gate (Invoke-AdmanMutation) is the ONLY caller
    (via & "Adman.AD.Write.$Verb"). Each wrapper:
      * declares [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')],
      * pins -Server $script:Config.DC,
      * forwards -WhatIf:$WhatIfPreference -Confirm:$false (no per-object re-prompt; the gate
        already confirmed once), and
      * iterates the resolved -Objects array, invoking the matching real AD cmdlet per object.
    There is NO wrapper for the hard-delete verb (SAFE-09) - "delete" is a reversible
    disable+quarantine, never an irreversible object removal. The 00-01 AST guard scopes to
    Public/, so these Private wrappers are expected and intended to contain the banned cmdlet
    names; do NOT add these names anywhere under Public/.
#>

Set-StrictMode -Version Latest

function Adman.AD.Write.Disable-ADAccount {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Disable-ADAccount')) {
            Disable-ADAccount -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Enable-ADAccount {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Enable-ADAccount')) {
            Enable-ADAccount -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Move-ADObject {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Move-ADObject')) {
            Move-ADObject -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Set-ADUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Set-ADUser')) {
            Set-ADUser -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Set-ADComputer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Set-ADComputer')) {
            Set-ADComputer -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Set-ADAccountPassword {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    # CR-01 fix: this wrapper invokes ONLY Set-ADAccountPassword. The ChangePasswordAtLogon
    # and Unlock follow-ups are separate AD writes with separate failure modes; conflating
    # them under one gate invocation produced a single audit record whose 'what' field
    # misrepresented the directory mutations (and a partial-failure state where the password
    # was reset but the audit said 'Failure'). The Public verb (Set-AdmanUserPassword) now
    # invokes the gate separately for Set-ADUser (ChangePasswordAtLogon) and Unlock-ADAccount,
    # giving each sub-operation its own PENDING/OUTCOME audit pair and its own confirmation.
    # Strip the follow-up keys here so a legacy caller that still splats them in does not
    # leak them into the Set-ADAccountPassword call (which would throw: unknown parameter).
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Set-ADAccountPassword')) {
            $p = $Parameters.Clone()
            $p.Remove('ChangePasswordAtLogon')
            $p.Remove('Unlock')
            Set-ADAccountPassword -Identity $o.DistinguishedName -Server $script:Config.DC @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Unlock-ADAccount {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    # HIGH #3: the gate forwards a PDCe override via $Parameters['Server']; splatting
    # @Parameters alongside a hardcoded -Server would duplicate the parameter. Compute the
    # effective server here, strip 'Server' from the splat copy, and pass exactly one -Server.
    $server = $script:Config.DC
    if ($Parameters.ContainsKey('Server') -and $Parameters['Server']) {
        $server = [string]$Parameters['Server']
    }
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Unlock-ADAccount')) {
            $p = $Parameters.Clone()
            $p.Remove('Server')
            Unlock-ADAccount -Identity $o.DistinguishedName -Server $server @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Add-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    # D-04 dual-resolution shape: the GROUP DN arrives via $Parameters['GroupIdentity']
    # (resolved once by the gate); the MEMBER objects arrive via -Objects. Swap
    # Identity/Members when calling the real cmdlet and strip 'GroupIdentity' from the splat.
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.DistinguishedName) -> $($Parameters['GroupIdentity'])", 'Add-ADGroupMember')) {
            $p = $Parameters.Clone()
            $p.Remove('GroupIdentity')
            Add-ADGroupMember -Identity $Parameters['GroupIdentity'] -Members $o.DistinguishedName `
                -Server $script:Config.DC @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.Remove-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    # D-04 dual-resolution shape: see Add-ADGroupMember above.
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.DistinguishedName) -> $($Parameters['GroupIdentity'])", 'Remove-ADGroupMember')) {
            $p = $Parameters.Clone()
            $p.Remove('GroupIdentity')
            Remove-ADGroupMember -Identity $Parameters['GroupIdentity'] -Members $o.DistinguishedName `
                -Server $script:Config.DC @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.AD.Write.New-ADUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    # ChangePasswordAtLogon consumption (D-05): the wrapper MUST NOT hardcode $true. Honor
    # the caller-supplied value when present; otherwise fall back to
    # $script:Config.security.mustChangeAtNextLogon with a $true default.
    $changePwd = $true
    if ($Parameters.ContainsKey('ChangePasswordAtLogon')) {
        $changePwd = [bool]$Parameters['ChangePasswordAtLogon']
    } elseif ($script:Config.PSObject.Properties['security'] -and
        $null -ne $script:Config.security -and
        $script:Config.security.PSObject.Properties['mustChangeAtNextLogon'] -and
        $null -ne $script:Config.security.mustChangeAtNextLogon) {
        $changePwd = [bool]$script:Config.security.mustChangeAtNextLogon
    }

    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'New-ADUser')) {
            New-ADUser -Name $o.Name -SamAccountName $o.SamAccountName `
                -UserPrincipalName $Parameters['UserPrincipalName'] `
                -Path $o.ParentOuDn `
                -AccountPassword $Parameters['AccountPassword'] `
                -Enabled $true `
                -ChangePasswordAtLogon $changePwd `
                -Server $script:Config.DC `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}
