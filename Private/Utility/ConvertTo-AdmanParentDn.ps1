#Requires -Version 5.1
<#
.SYNOPSIS
    ConvertTo-AdmanParentDn - return the parent DN of an LDAP distinguished name.

.DESCRIPTION
    Splits a DN at the first unescaped RDN separator (RFC 4514 comma) and returns
    everything after it. Escaped commas (\,) and escaped backslashes (\\) are
    respected so a CN such as 'Doe\, John' does not produce an invalid parent.

    This is the single source for parent-DN extraction (WR-01). Callers that only
    need to compare scope should still use ConvertTo-AdmanNormalizedDn.
#>

Set-StrictMode -Version Latest

function ConvertTo-AdmanParentDn {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Dn
    )

    if ([string]::IsNullOrWhiteSpace($Dn)) { return '' }

    # Split on the first comma that is NOT escaped by a single backslash.
    # A comma preceded by an even number of backslashes (including zero) is a
    # component separator; a comma preceded by an odd number is escaped.
    $parts = [regex]::Split($Dn, '(?<!\\)(?:\\\\)*,', 2)
    if ($parts.Length -lt 2) { return '' }
    return $parts[1].Trim()
}
