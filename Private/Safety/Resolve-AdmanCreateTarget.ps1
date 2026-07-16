#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanCreateTarget - fabricate a synthetic pre-create target for New-ADUser (D-01).

.DESCRIPTION
    Builds a PSCustomObject shaped like an ADObject WITHOUT calling Get-ADObject -Identity
    (the object does not exist yet). The synthetic target flows through the gate's fixed
    order unchanged: Test-AdmanTargetAllowed (create-branch) -> Confirm-AdmanAction ->
    Write-AdmanAudit PENDING -> Adman.AD.Write.New-ADUser -> OUTCOME. SAFE-10 preserved:
    preview and audit Target name the to-be-created DN.

    Carries:
      DistinguishedName = "CN=<Name>,<ParentOuDn>"
      SamAccountName    = proposed sAMAccountName
      Name              = proposed CN
      objectClass       = @('top','person','organizationalPerson','user')
      objectSid         = $null   (no SID exists yet)
      memberOf          = @()     (no group memberships exist yet)
      ParentOuDn        = the parent OU DN (used by the create-branch scope check)
      IsSynthetic       = $true   (the create-branch marker)
#>

Set-StrictMode -Version Latest

# WR-08: RFC 4514 RDN escaping for the CN value. A CN containing a comma, equals, plus,
# backslash, double-quote, angle bracket, semicolon, or a leading/trailing space or
# leading '#' would otherwise produce a malformed DistinguishedName. The escape rules
# below follow RFC 4514 section 2.4.
function ConvertTo-AdmanRdnEscaped {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    $v = $Value
    # Backslash first (each escape introduces a backslash).
    $v = $v -replace '\\', '\\'
    # RFC 4514 special characters.
    $v = $v -replace ',', '\,'
    $v = $v -replace '=', '\='
    $v = $v -replace '\+', '\+'
    $v = $v -replace '"', '\"'
    $v = $v -replace '<', '\<'
    $v = $v -replace '>', '\>'
    $v = $v -replace ';', '\;'
    # Leading '#' must be escaped (otherwise parsed as hex BER encoding).
    if ($v.StartsWith('#')) { $v = '\' + $v }
    # IN-01 fix: escape ALL leading/trailing spaces per RFC 4514, not just the first/last.
    # The previous code only handled a single leading or trailing space; a value like
    # '  John' (two leading spaces) would leave the second space unescaped.
    if ($v -match '^(\s+)') {
        $leading = $Matches[1]
        $escapedLeading = $leading -replace ' ', '\ '
        $v = $escapedLeading + $v.Substring($leading.Length)
    }
    if ($v -match '(\s+)$') {
        $trailing = $Matches[1]
        $escapedTrailing = $trailing -replace ' ', '\ '
        $v = $v.Substring(0, $v.Length - $trailing.Length) + $escapedTrailing
    }
    return $v
}

function Resolve-AdmanCreateTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$SamAccountName,
        [Parameter(Mandatory)]
        [string]$ParentOuDn
    )

    # WR-08 fix: escape the CN per RFC 4514 before interpolating into the DN. A Name like
    # 'Doe, John' would otherwise produce a malformed DN (the comma would be parsed as an
    # RDN separator). The downstream scope check normalizes the parent OU only, so a
    # malformed CN would not break the scope check, but the audit record's target field
    # and the ShouldProcess preview line would carry the malformed DN.
    $cnEsc = ConvertTo-AdmanRdnEscaped -Value $Name

    [pscustomobject]@{
        DistinguishedName = "CN=$cnEsc,$ParentOuDn"
        SamAccountName    = $SamAccountName
        Name              = $Name
        objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        objectSid         = $null
        memberOf          = @()
        ParentOuDn        = $ParentOuDn
        IsSynthetic       = $true
    }
}
