#Requires -Version 5.1
<#
.SYNOPSIS
    ConvertTo-AdmanNormalizedDn - shared DN normalization for the scope boundary check.

.DESCRIPTION
    Normalize a DN for the component-boundary scope test: lowercase, trim each RDN, and
    unescape the common DN escape sequences so an escaped comma/backslash in a leaf CN does
    not defeat (or spoof) the boundary anchor.

    This is the SINGLE SOURCE for DN normalization (MEDIUM-3). Both the write path
    (Test-AdmanTargetAllowed, SAFE-07 step (c)) and the read path (Test-AdmanInManagedScope,
    D-02) call this shared helper - no logic duplication. Extracted from
    Private/Safety/Test-AdmanTargetAllowed.ps1 in Phase 1 Plan 01-02.
#>

Set-StrictMode -Version Latest

function ConvertTo-AdmanNormalizedDn {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Dn)

    if ($null -eq $Dn) { return '' }
    $s = $Dn.ToLowerInvariant()
    # Unescape common DN escapes ( \, \+ \" \\ \; \< \> \= and hex \XX ) so the boundary test
    # compares canonical component text, not escape artifacts.
    $s = [regex]::Replace($s, '\\([0-9a-f]{2})', {
            param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16)
        })
    $s = $s -replace '\\(.)', '$1'
    # Trim whitespace around each RDN (split on unescaped commas - after unescape above, commas
    # that remain are component separators).
    $parts = $s -split ','
    $parts = $parts | ForEach-Object { $_.Trim() }
    return ($parts -join ',')
}
