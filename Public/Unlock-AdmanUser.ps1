#Requires -Version 5.1
<#
.SYNOPSIS
    Unlock-AdmanUser - unlock a single AD user through the mutation gate, pinned
    to the PDC emulator (USER-05, T-02-05).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Resolves the PDC emulator via
    (Get-ADDomain).PDCEmulator, reads LockedOut first on the PDCe, and routes
    through Invoke-AdmanMutation -Verb 'Unlock-ADAccount' with
    $Parameters['Server'] = $pdc so the wrapper pins to the PDCe.

    PDCe pinning rationale (Pitfall 2): account lockout state is PDCe-authoritative.
    Reading LockedOut on a non-PDCe DC can return stale $false (the lockout has not
    replicated yet), causing a false "not locked out" no-op. The unlock itself must
    also target the PDCe so the state change is authoritative.

    LockedOut pre-read: if the account is NOT locked, the verb returns a clear
    "Account is not locked out." message and skips the gate call entirely (no
    confirm, no audit, no write). This is a UX fail-fast, not a safety boundary.

    PDCe resolver note (warning resolution): the PDCe pinning covers the WRAPPER
    (via $Parameters['Server']) but NOT the gate's Resolve-AdmanTarget call. This
    is intentional: Resolve-AdmanTarget binds by DN/SAM via Get-ADObject -Identity,
    and DN/SID identity is stable across DCs in a single domain (no cross-DC
    ambiguity for the identity bind). Only the lockout STATE (LockedOut /
    lockoutTime) is PDCe-authoritative, and that state is read explicitly on the
    PDCe by the Get-ADUser call above BEFORE the gate runs. Extending
    Resolve-AdmanTarget with a -Server pass-through would add complexity for no
    safety benefit — the resolver's output (the ADObject identity) is identical
    regardless of which DC answers.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Unlock-AdmanUser -Identity 'jdoe'

.EXAMPLE
    Unlock-AdmanUser -Identity 'jdoe' -WhatIf
#>

Set-StrictMode -Version Latest

function Unlock-AdmanUser {
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

    # Resolve the PDC emulator. Lockout state is PDCe-authoritative (Pitfall 2).
    $pdc = (Get-ADDomain -Server $script:Config.DC).PDCEmulator

    # Read LockedOut first on the PDCe. If not locked, no-op with a clear message.
    $user = Get-ADUser -Identity $Identity -Server $pdc -Properties LockedOut -ErrorAction Stop
    if (-not $user.LockedOut) {
        Write-Output "Account is not locked out."
        return
    }

    # Build the gate $Parameters with the PDCe pin.
    $params = @{ Server = $pdc }

    Invoke-AdmanMutation -Verb 'Unlock-ADAccount' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
