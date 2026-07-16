#Requires -Version 5.1
<#
.SYNOPSIS
    Move-AdmanUser - move a single AD user to another OU within managed scope
    through the mutation gate (USER-06, T-02-08).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Validates -TargetPath under managed roots
    BEFORE calling the gate (UX fail-fast), then routes through
    Invoke-AdmanMutation -Verb 'Move-ADObject' with $Parameters['TargetPath'].

    Destination validation (T-02-08 mitigation): the target OU DN is normalized
    via ConvertTo-AdmanNormalizedDn (lowercase, RDN-trimmed, escape-unescaped)
    and compared against every root in $script:Config.ManagedOUs with a
    component-boundary anchor: $t -eq $r -or $t.EndsWith(',' + $r). A naive
    prefix check would false-pass 'OU=ManagedX' against 'OU=Managed'; the
    boundary anchor refuses it. Out-of-scope destinations throw
    "TargetPath '<x>' is outside managed OU scope." BEFORE the gate call.

    The gate ALSO runs the same TargetPath validator inside Invoke-AdmanMutation
    (Plan 02-01) so direct gate callers cannot bypass it; this Public-verb check
    is the UX fail-fast layer.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Leavers,OU=Managed,DC=contoso,DC=local'

.EXAMPLE
    Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Sub,OU=Managed,DC=contoso,DC=local' -WhatIf
#>

Set-StrictMode -Version Latest

function Move-AdmanUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPath,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # T-02-08: validate -TargetPath under managed roots BEFORE the gate call.
    # Component-boundary anchored: exact match OR ends-with ','+root.
    $tp = ConvertTo-AdmanNormalizedDn -Dn $TargetPath
    $tpInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
    }
    if (-not $tpInScope) {
        throw "TargetPath '$TargetPath' is outside managed OU scope."
    }

    # Build the gate $Parameters.
    $params = @{ TargetPath = $TargetPath }

    Invoke-AdmanMutation -Verb 'Move-ADObject' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference
}
