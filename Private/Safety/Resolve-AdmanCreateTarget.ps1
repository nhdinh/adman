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

    [pscustomobject]@{
        DistinguishedName = "CN=$Name,$ParentOuDn"
        SamAccountName    = $SamAccountName
        Name              = $Name
        objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        objectSid         = $null
        memberOf          = @()
        ParentOuDn        = $ParentOuDn
        IsSynthetic       = $true
    }
}
