#Requires -Version 5.1
<#
.SYNOPSIS
    Remove-AdmanLocalUser - remove a single local user through the local mutation gate
    (LUSR-01, D-03).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanLocalMutation -Verb 'Remove-LocalUser'.

    This action is IRREVERSIBLE. Local accounts have no Recycle Bin or quarantine OU
    equivalent (SAFE-09's reversible-delete mechanism cannot apply to the local SAM).
    The gate's Confirm-AdmanAction per-verb threshold override (built in Plan 02-01)
    forces typed-count confirmation even at count=1, so the operator always types the
    exact count. Pre-delete state (local SID, name, group memberships, profile path)
    is captured in the audit record for manual re-create.

    Phase 2 localhost validation (D-02): accepts $null, '.', $env:COMPUTERNAME,
    'localhost'; throws "Remote targets arrive in Phase 3" otherwise.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Remove-AdmanLocalUser -Name 'luser'

.EXAMPLE
    Remove-AdmanLocalUser -Name 'luser' -WhatIf
#>

Set-StrictMode -Version Latest

function Remove-AdmanLocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$ComputerName,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Phase 2 localhost validation (D-02).
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        $ComputerName -ne '.' -and
        $ComputerName -ne 'localhost' -and
        $ComputerName -ne $env:COMPUTERNAME) {
        throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
    }

    # D-03: Remove-LocalUser is irreversible (no Recycle Bin). The gate's
    # Confirm-AdmanAction overrides bulkConfirmThreshold to 1 for this verb (typed-count
    # even at count=1). Pre-delete state capture happens in the audit record via the
    # resolved local target's PreDeleteState property (group memberships + profile path,
    # captured by Resolve-AdmanLocalTarget in Plan 02-01).
    $params = @{ ComputerName = $ComputerName }

    Invoke-AdmanLocalMutation -Verb 'Remove-LocalUser' -Targets @($Name) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
