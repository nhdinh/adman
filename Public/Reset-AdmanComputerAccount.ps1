#Requires -Version 5.1
Set-StrictMode -Version Latest

function Reset-AdmanComputerAccount {
    <#
    .SYNOPSIS
        Reset-AdmanComputerAccount - reset a single AD computer account through the
        mutation gate (COMP-04) with honest guidance on which method applies.

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Routes through Invoke-AdmanMutation with
        -Verb 'Set-ADAccountPassword' and $Parameters['Reset']=$true. This is the
        AD-side "Reset Account" semantics — the ADUC equivalent.

        Two methods exist for recovering a broken computer-account / secure-channel
        state; this verb implements the FIRST and documents the SECOND:

          1. AD-side "Reset Account" (THIS VERB): Set-ADAccountPassword -Reset resets
             the machine account password to the default. ADUC equivalent. Breaks
             the secure channel until the machine rejoins the domain OR the channel
             is repaired on-machine.

          2. On-machine channel repair (RUNBOOK STEP, OUT-OF-GATE):
             Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
             runs ON the affected machine and requires local admin rights there.
             Use this when the machine is otherwise healthy and only the channel
             is broken — it preserves the domain membership and avoids a rejoin.

        After the gate call returns (and NOT under -WhatIf), the verb emits the
        guidance text via Write-PSFMessage -Level Host (the established diagnostic
        pattern — Write-Host would trip the lint gate; the CLAUDE.md
        PSAvoidUsingWriteHost suppression covers ONLY the TUI-rendering module)
        AND attaches it to the return object's Guidance property so pipeline
        callers can surface it.

        This state-changing verb routes through the mutation gate, which writes a PENDING/OUTCOME
        audit pair, prompts for confirmation, and supports -WhatIf for dry-run preview.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is absent.

    .PARAMETER Identity
        The sAMAccountName, distinguished name, GUID, or SID of the AD computer account
        to reset.

    .PARAMETER Force
        Bypasses the confirmation prompt when set. -WhatIf still previews the action.

    .EXAMPLE
        Reset-AdmanComputerAccount -Identity 'PC-01'

    .EXAMPLE
        Reset-AdmanComputerAccount -Identity 'PC-01' -WhatIf
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

    # Build the gate $Parameters. Reset=$true is the AD-side "Reset Account"
    # semantics (ADUC equivalent).
    $params = @{ Reset = $true }

    $gateResult = Invoke-AdmanMutation -Verb 'Set-ADAccountPassword' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference

    # COMP-04: emit the honest guidance naming BOTH methods and the trade-off.
    # Skip under -WhatIf (no real mutation occurred; nothing to recover from).
    $guidance = "AD-side reset complete for $Identity. The secure channel is now broken until the machine rejoins the domain OR the channel is repaired on-machine. To repair the channel ON the affected machine (requires local admin), run: Test-ComputerSecureChannel -Repair -Credential (Get-Credential). If the machine cannot rejoin, use the ADUC 'Reset Account' context menu or this verb again."

    if (-not $WhatIfPreference) {
        Write-PSFMessage -Level Host -Message $guidance
    }

    # Surface the guidance on the return object so pipeline callers can render it.
    # The gate may return $null (e.g., under -WhatIf with certain mock shapes);
    # always emit a fresh PSCustomObject carrying the Guidance property.
    [pscustomobject]@{
        Target     = $Identity
        Verb       = 'Set-ADAccountPassword'
        WhatIf     = [bool]$WhatIfPreference
        GateResult = $gateResult
        Guidance   = $guidance
    }
}
