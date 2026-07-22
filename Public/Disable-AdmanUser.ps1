#Requires -Version 5.1
Set-StrictMode -Version Latest

function Disable-AdmanUser {
    <#
    .SYNOPSIS
        Disable-AdmanUser - disable a single AD user through the mutation gate (USER-03).

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Routes through Invoke-AdmanMutation with
        -Verb 'Disable-ADAccount' and -Targets @($Identity). The gate resolves the target
        once (SAFE-10), runs Test-AdmanTargetAllowed (deny-RID, protected-membership,
        managed-OU scope), confirms via Confirm-AdmanAction, writes the PENDING audit,
        and invokes the Adman.AD.Write.Disable-ADAccount wrapper for the one real write.

        This state-changing verb routes through the mutation gate, which writes a PENDING/OUTCOME
        audit pair, prompts for confirmation, and supports -WhatIf for dry-run preview.

        Use -WhatIf to preview the change without applying it.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is absent.

    .PARAMETER Identity
        The sAMAccountName, distinguished name, GUID, or SID of the AD user to disable.

    .PARAMETER Force
        Bypasses the confirmation prompt when set. -WhatIf still previews the action.

    .EXAMPLE
        Disable-AdmanUser -Identity 'jdoe'

    .EXAMPLE
        Disable-AdmanUser -Identity 'jdoe' -WhatIf
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

    Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @($Identity) `
        -Force:$Force -WhatIf:$WhatIfPreference
}
