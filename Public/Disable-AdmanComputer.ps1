#Requires -Version 5.1
Set-StrictMode -Version Latest

function Disable-AdmanComputer {
    <#
    .SYNOPSIS
        Disable-AdmanComputer - disable a single AD computer through the mutation gate (COMP-02).

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Routes through Invoke-AdmanMutation with
        -Verb 'Disable-ADAccount' and -Targets @($Identity). Computer objects are AD
        security principals; the same Disable-ADAccount wrapper serves both user and
        computer targets. The gate resolves the target once (SAFE-10), runs
        Test-AdmanTargetAllowed (deny-RID, protected-membership, managed-OU scope),
        confirms via Confirm-AdmanAction, writes the PENDING audit, and invokes the
        Adman.AD.Write.Disable-ADAccount wrapper for the one real write.

        This state-changing verb routes through the mutation gate, which writes a PENDING/OUTCOME
        audit pair, prompts for confirmation, and supports -WhatIf for dry-run preview.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is absent.

    .PARAMETER Identity
        The sAMAccountName, distinguished name, GUID, or SID of the AD computer to disable.

    .PARAMETER Force
        Bypasses the confirmation prompt when set. -WhatIf still previews the action.

    .EXAMPLE
        Disable-AdmanComputer -Identity 'PC-01'

    .EXAMPLE
        Disable-AdmanComputer -Identity 'PC-01' -WhatIf
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [switch]$Force
    )

    Assert-AdmanInitialized

    Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @($Identity) `
        -Force:$Force -WhatIf:$WhatIfPreference
}
