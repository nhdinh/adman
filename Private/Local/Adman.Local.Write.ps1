#Requires -Version 5.1
<#
.SYNOPSIS
    Adman.Local.Write - the gate-only raw local-account write wrappers (D-02).

.DESCRIPTION
    ONE thin wrapper per allow-listed local verb. These wrappers are the ONLY code in the
    repo that names the real LocalAccounts cmdlets; the local mutation gate
    (Invoke-AdmanLocalMutation) is the ONLY caller (via & "Adman.Local.Write.$Verb"). Each
    wrapper:
      * declares [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')],
      * forwards -WhatIf:$WhatIfPreference -Confirm:$false (no per-object re-prompt; the
        gate already confirmed once), and
      * iterates the resolved -Objects array, invoking the matching real LocalAccounts
        cmdlet per object.
    NO -Server parameter (LocalAccounts cmdlets have none).

    CRITICAL (B3 fix): every local wrapper strips 'ComputerName' from the local $Parameters
    splat copy BEFORE splatting - LocalAccounts cmdlets do not accept a -ComputerName
    parameter, so leaving it in the splat makes every local verb throw 'A parameter cannot
    be found that matches parameter name ComputerName'.
#>

Set-StrictMode -Version Latest

function Adman.Local.Write.New-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'New-LocalUser')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            New-LocalUser -Name $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Disable-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Disable-LocalUser')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            Disable-LocalUser -Name $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Enable-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Enable-LocalUser')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            Enable-LocalUser -Name $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Set-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Set-LocalUser')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            Set-LocalUser -Name $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Remove-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Remove-LocalUser')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            Remove-LocalUser -Name $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Add-LocalGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name) -> $($Parameters['Group'])", 'Add-LocalGroupMember')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            $p.Remove('Group')
            Add-LocalGroupMember -Group $Parameters['Group'] -Member $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Remove-LocalGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name) -> $($Parameters['Group'])", 'Remove-LocalGroupMember')) {
            $p = $Parameters.Clone()
            $p.Remove('ComputerName')
            $p.Remove('Group')
            Remove-LocalGroupMember -Group $Parameters['Group'] -Member $o.Name @p `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}
