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
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Set-ADAccountPassword')) {
            Set-ADAccountPassword -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
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
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Unlock-ADAccount')) {
            Unlock-ADAccount -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
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
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Add-ADGroupMember')) {
            Add-ADGroupMember -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
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
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'Remove-ADGroupMember')) {
            Remove-ADGroupMember -Identity $o.DistinguishedName -Server $script:Config.DC @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}
