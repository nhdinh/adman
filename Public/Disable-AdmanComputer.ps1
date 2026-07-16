#Requires -Version 5.1
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

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Disable-AdmanComputer -Identity 'PC-01'

.EXAMPLE
    Disable-AdmanComputer -Identity 'PC-01' -WhatIf
#>

Set-StrictMode -Version Latest

function Disable-AdmanComputer {
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
