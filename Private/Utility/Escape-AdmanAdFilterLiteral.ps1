#Requires -Version 5.1
<#
.SYNOPSIS
    Escape-AdmanAdFilterLiteral - escape a string for safe interpolation into an AD
    PowerShell -Filter string-literal position (between single quotes).

.DESCRIPTION
    Returns a string safe for interpolation into an AD PowerShell -Filter string-literal
    position. The AD -Filter parser uses single-quote doubling and backslash escaping for
    string literals - this is NOT the same as RFC 4515 LDAP assertion-value escaping.

    Escaping rules (HIGH-1 - distinct from RFC4515):
      * Single quote (') is DOUBLED ('') - the AD -Filter string-literal escape. A name
        like O'Brien becomes O''Brien and the filter still parses as a single literal.
      * Backslash (\) is DOUBLED (\\) - backslash is the AD -Filter escape character; a
        literal backslash must be escaped.
      * Wildcard characters (* and ?) are NOT escaped by this helper. The Find verbs
        intentionally use -like semantics on -Name (D-02); callers that need exact-match
        semantics use -eq and the caller is responsible for not passing user-controlled
        wildcards into -eq positions.
      * Parentheses ( ) and NUL are NOT special inside an AD -Filter string literal
        (unlike RFC4515 LDAP assertions) and are passed through unchanged.

    Returns the empty string for $null or empty input.

.NOTES
    Use this helper for AD PowerShell -Filter strings. Use Escape-AdmanLdapFilterValue for
    -LDAPFilter (RFC4515) strings. The two are NOT interchangeable:
      * Escape-AdmanAdFilterLiteral escapes ' and \ for -Filter string literals.
      * Escape-AdmanLdapFilterValue escapes \ * ( ) and NUL to hex form for RFC4515
        assertion values inside -LDAPFilter.
    Confusing them produces either an unparseable filter or an injectable one.
#>

Set-StrictMode -Version Latest

function Escape-AdmanAdFilterLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) { return '' }

    # Order matters: double backslashes FIRST so a backslash introduced by the quote rule
    # below cannot itself be re-escaped. Then double single quotes.
    $escaped = $Value -replace '\\', '\\'
    $escaped = $escaped -replace "'", "''"
    return $escaped
}
