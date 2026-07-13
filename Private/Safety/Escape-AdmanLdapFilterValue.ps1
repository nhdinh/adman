#Requires -Version 5.1
<#
.SYNOPSIS
    Escape-AdmanLdapFilterValue - RFC 4515 assertion-value escaping for LDAP filters.

.DESCRIPTION
    Escapes a value before it is interpolated into an LDAP filter assertion, per RFC 4515
    (String Representation of Search Filters) section 3. The five characters that are
    significant inside a filter assertion value are escaped to their hex form:
        \   -> \5c
        *   -> \2a
        (   -> \28
        )   -> \29
        NUL -> \00
    Applied to every DN / group value interpolated into the protected-check IN_CHAIN
    -LDAPFilter so a CN containing ( ) * \ or NUL cannot break the filter (fails closed ->
    a false refusal, never a bypass). (C2-L1)
#>

Set-StrictMode -Version Latest

function Escape-AdmanLdapFilterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) { return '' }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Value.ToCharArray()) {
        switch ($ch) {
            '\'  { [void]$sb.Append('\5c'); continue }
            '*'  { [void]$sb.Append('\2a'); continue }
            '('  { [void]$sb.Append('\28'); continue }
            ')'  { [void]$sb.Append('\29'); continue }
            default {
                if ([int]$ch -eq 0) { [void]$sb.Append('\00'); continue }
                [void]$sb.Append($ch)
            }
        }
    }
    return $sb.ToString()
}
