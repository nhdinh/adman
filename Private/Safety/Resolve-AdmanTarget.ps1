#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanTarget - the single target resolver shared by preview AND execute (SAFE-10).

.DESCRIPTION
    Materializes the canonical ADObject array for a set of identities. The gate calls this
    ONCE and hands the SAME array reference to both the -WhatIf preview and the execute loop,
    so the preview cannot lie (no re-query between preview and execute).

    The lookup binds the Identity parameter set ONLY: -Identity, -Server, -Properties. It does
    NOT bind -SearchBase / -SearchScope - the Identity parameter set has neither (it has
    -Partition); an -Identity...-SearchBase mix cannot bind and would throw 'Parameter set
    cannot be resolved' BEFORE any safety logic runs (C2-H1). Managed-OU scope is NOT weakened
    by dropping -SearchBase: it is enforced downstream in Test-AdmanTargetAllowed step (c)
    (component-boundary DN suffix, SAFE-07) on every target, identically for preview and
    execute.

    This function does NO policy filtering (that is Test-AdmanTargetAllowed); it only
    materializes canonical ADObjects. -Server is ALWAYS pinned to $script:Config.DC and
    -Properties is exact.
#>

Set-StrictMode -Version Latest

function Resolve-AdmanTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,

        # WR-04: optional additional properties so callers can make their dependency on
        # specific AD attributes explicit (e.g. Invoke-AdmanBulkAction for memberOf checks).
        # The base set (objectSid, objectClass, DistinguishedName, memberOf, Enabled) is
        # always requested because the mutation gate and common no-op checks rely on it.
        [Parameter()]
        [string[]]$Properties = @()
    )

    $baseProperties = @('objectSid', 'objectClass', 'DistinguishedName', 'memberOf', 'Enabled')
    $requested = @($baseProperties + $Properties | Select-Object -Unique)

    foreach ($id in $Targets) {
        # Identity parameter set ONLY: -Identity + -Server + -Properties (NO -SearchBase/-SearchScope).
        # Scope is enforced downstream in Test-AdmanTargetAllowed step (c), identically for
        # preview and execute (SAFE-07/SAFE-10).
        # WR-03: include Enabled so callers (e.g. Invoke-AdmanBulkAction) can detect
        # already-disabled/enabled accounts without a second AD query.
        Get-ADObject -Identity $id -Server $script:Config.DC `
            -Properties $requested -ErrorAction Stop
    }
}
