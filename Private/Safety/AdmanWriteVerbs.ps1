#Requires -Version 5.1
<#
.SYNOPSIS
    AdmanWriteVerbs - the single-sourced 9-verb AD write allow-list (SAFE-09).

.DESCRIPTION
    Get-AdmanAllowedWriteVerbs returns the EXACT set of AD write verbs the mutation gate may
    invoke. This is the single source consumed by:
      * Invoke-AdmanMutation's ValidateSet (Task 3), and
      * the Adman.AD.Write.* wrappers (Task 2).
    The hard-delete verb is deliberately ABSENT (SAFE-09): "delete" is a reversible
    disable+quarantine, never an irreversible object removal. The banned-literal complement
    (which includes the hard-delete verb) lives only in rules/AdmanSafetyRules.psm1
    (Get-AdmanBannedWriteVerbs); the two are kept in lockstep by tests.
#>

Set-StrictMode -Version Latest

function Get-AdmanAllowedWriteVerbs {
    <#
    .SYNOPSIS
        Return the 9-verb AD write allow-list (SAFE-09; the hard-delete verb is excluded).
    #>
    [CmdletBinding()]
    param()

    return @(
        'Disable-ADAccount'
        'Enable-ADAccount'
        'Move-ADObject'
        'Set-ADUser'
        'Set-ADComputer'
        'Set-ADAccountPassword'
        'Unlock-ADAccount'
        'Add-ADGroupMember'
        'Remove-ADGroupMember'
        'New-ADUser'
    )
}
