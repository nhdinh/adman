#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanGroup - single-shot group resolver for the D-04 dual-resolution group path.

.DESCRIPTION
    Materializes the canonical ADGroup object for the group side of an Add/Remove-ADGroupMember
    call. The gate resolves the MEMBER via Resolve-AdmanTarget (existing) and the GROUP via
    this resolver, then runs Test-AdmanTargetAllowed on the member and Test-AdmanGroupAllowed
    on the group. -Server is ALWAYS pinned to $script:Config.DC and -Properties is exact.
#>

Set-StrictMode -Version Latest

function Resolve-AdmanGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    Get-ADGroup -Identity $Identity -Server $script:Config.DC `
        -Properties objectSid, objectClass, DistinguishedName -ErrorAction Stop
}
