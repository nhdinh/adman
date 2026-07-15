#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanInManagedScope - SAFE-07 step (c) scope-only boundary check for reads.

.DESCRIPTION
    Returns $true only when the supplied DistinguishedName is inside one of the configured
    ManagedOUs roots. Component-boundary anchored: a DN is in-scope when its normalized form
    EQUALS a normalized root OR ends with ',<root>'. NEVER a -like substring match.

    This helper applies ONLY the SAFE-07 step (c) boundary. It does NOT check the deny-list
    and does NOT check protected-group membership - those are mutation-only gates (D-02,
    RESEARCH Pitfall 7). Reads are subject to the same scope as writes, but not to the
    mutation-only deny/protected checks.

    DN normalization is delegated to the SHARED ConvertTo-AdmanNormalizedDn utility in
    Private/Utility/ConvertTo-AdmanNormalizedDn.ps1 (MEDIUM-3 - no logic duplication).
    The same normalization is used by the write path's SAFE-07 step (c) scope check.
#>

Set-StrictMode -Version Latest

function Test-AdmanInManagedScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return $false }

    $t = ConvertTo-AdmanNormalizedDn -Dn $DistinguishedName
    if ([string]::IsNullOrEmpty($t)) { return $false }

    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($t -eq $r -or $t.EndsWith(',' + $r)) { return $true }
    }
    return $false
}
