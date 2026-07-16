#Requires -Version 5.1
<#
.SYNOPSIS
    Enable-AdmanUser - enable a single AD user through the mutation gate (USER-03).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Routes through Invoke-AdmanMutation with
    -Verb 'Enable-ADAccount' and -Targets @($Identity). The gate resolves the target
    once (SAFE-10), runs Test-AdmanTargetAllowed (deny-RID, protected-membership,
    managed-OU scope), confirms via Confirm-AdmanAction, writes the PENDING audit,
    and invokes the Adman.AD.Write.Enable-ADAccount wrapper for the one real write.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Enable-AdmanUser -Identity 'jdoe'

.EXAMPLE
    Enable-AdmanUser -Identity 'jdoe' -WhatIf
#>

Set-StrictMode -Version Latest

function Enable-AdmanUser {
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

    Invoke-AdmanMutation -Verb 'Enable-ADAccount' -Targets @($Identity) `
        -Force:$Force -WhatIf:$WhatIfPreference
}
