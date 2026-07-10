#Requires -Version 5.1
<#
.SYNOPSIS
    Offline mocks for every ActiveDirectory / CIM / remoting cmdlet used by adman.

.DESCRIPTION
    Guarantees unit tests NEVER touch a live domain (project constraint / T-00-11). Each stub
    returns a canned PSCustomObject (tagged with an AdmanMock.* TypeName so tests can prove the
    mock - not real AD - answered) or $null for write verbs. No stub performs a network call.
    Import with: Import-Module tests/Mocks/ActiveDirectory.psm1 -Force
#>

Set-StrictMode -Version Latest

$script:MockSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1000'
$script:MockDomainSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333'

function New-AdmanMockObject {
    [CmdletBinding()]
    param(
        [string]$TypeName = 'AdmanMock.ADObject',
        [hashtable]$Props = @{}
    )
    $base = [ordered]@{
        objectSid         = $script:MockSid
        objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        DistinguishedName = 'CN=Mock User,OU=Mock,DC=mock,DC=local'
        memberOf          = @()
        Enabled           = $true
        SamAccountName    = 'mock.user'
    }
    foreach ($k in $Props.Keys) { $base[$k] = $Props[$k] }
    $o = [pscustomobject]$base
    $o.PSObject.TypeNames.Insert(0, $TypeName)
    return $o
}

# --- Read stubs (no ShouldProcess needed) ---------------------------------------------------
function Get-ADUser { [CmdletBinding()] param($Identity, $Properties, $Server) New-AdmanMockObject }
function Get-ADComputer { [CmdletBinding()] param($Identity, $Properties, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'person', 'organizationalPerson', 'user', 'computer'); SamAccountName = 'MOCKPC$' } }
function Get-ADObject { [CmdletBinding()] param($Identity, $Properties, $Server, $LDAPFilter) New-AdmanMockObject }
function Get-ADGroup { [CmdletBinding()] param($Identity, $Properties, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'group') } }
function Get-ADGroupMember { [CmdletBinding()] param($Identity, $Recursive, $Server) @(New-AdmanMockObject) }
function Get-ADOrganizationalUnit { [CmdletBinding()] param($Identity, $Filter, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'organizationalUnit') } }
function Get-ADOptionalFeature { [CmdletBinding()] param($Identity, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'msDS-OptionalFeature') } }
function Search-ADAccount { [CmdletBinding()] param($Identity, $Server) @(New-AdmanMockObject) }

function Get-ADDomain {
    [CmdletBinding()] param($Identity, $Server)
    $o = [pscustomobject]@{
        DomainSID         = $script:MockDomainSid
        DNSRoot           = 'mock.local'
        NetBIOSName       = 'MOCK'
        DistinguishedName = 'DC=mock,DC=local'
    }
    $o.PSObject.TypeNames.Insert(0, 'AdmanMock.ADDomain')
    return $o
}

function Get-ADForest {
    [CmdletBinding()] param($Identity, $Server)
    $o = [pscustomobject]@{ RootDomain = 'mock.local'; Name = 'mock.local' }
    $o.PSObject.TypeNames.Insert(0, 'AdmanMock.ADForest')
    return $o
}

function Get-CimInstance {
    [CmdletBinding()] param($ClassName, $CimSession, $ComputerName, $Filter)
    $o = [pscustomobject]@{ ClassName = $ClassName; Mock = $true }
    $o.PSObject.TypeNames.Insert(0, 'AdmanMock.CimInstance')
    return $o
}

function Test-WSMan { [CmdletBinding()] param($ComputerName) return $true }

function Invoke-Command {
    [CmdletBinding()] param($ScriptBlock, $Session, $ComputerName, $ArgumentList)
    if ($ScriptBlock) { return (& $ScriptBlock) }
    return $null
}

# --- Write stubs (SupportsShouldProcess keeps the lint gate clean) --------------------------
function Set-ADUser { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Description, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADUser (mock)')) { } }
function Set-ADComputer { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Description, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADComputer (mock)')) { } }
function Set-ADObject { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADObject (mock)')) { } }
function Set-ADAccountPassword { [CmdletBinding(SupportsShouldProcess)] param($Identity, $NewPassword, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADAccountPassword (mock)')) { } }
function Disable-ADAccount { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Disable-ADAccount (mock)')) { } }
function Enable-ADAccount { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Enable-ADAccount (mock)')) { } }
function Unlock-ADAccount { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Unlock-ADAccount (mock)')) { } }
function Move-ADObject { [CmdletBinding(SupportsShouldProcess)] param($Identity, $TargetPath, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Move-ADObject (mock)')) { } }
function New-ADUser { [CmdletBinding(SupportsShouldProcess)] param($Name, $SamAccountName, $Server) if ($PSCmdlet.ShouldProcess($Name, 'New-ADUser (mock)')) { New-AdmanMockObject } }
function New-ADComputer { [CmdletBinding(SupportsShouldProcess)] param($Name, $SamAccountName, $Server) if ($PSCmdlet.ShouldProcess($Name, 'New-ADComputer (mock)')) { New-AdmanMockObject -Props @{ objectClass = @('computer') } } }
function Add-ADGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Members, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Add-ADGroupMember (mock)')) { } }
function Remove-ADGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Members, $Server) if ($PSCmdlet.ShouldProcess($Identity, 'Remove-ADGroupMember (mock)')) { } }

function New-CimSession { [CmdletBinding(SupportsShouldProcess)] param($ComputerName, $SessionOption) if ($PSCmdlet.ShouldProcess($ComputerName, 'New-CimSession (mock)')) { [pscustomobject]@{ ComputerName = $ComputerName; Mock = $true } } }
function New-PSSession { [CmdletBinding(SupportsShouldProcess)] param($ComputerName, $Credential) if ($PSCmdlet.ShouldProcess($ComputerName, 'New-PSSession (mock)')) { [pscustomobject]@{ ComputerName = $ComputerName; Mock = $true } } }

Export-ModuleMember -Function @(
    'Get-ADUser', 'Get-ADComputer', 'Get-ADObject', 'Get-ADGroup', 'Get-ADGroupMember',
    'Get-ADDomain', 'Get-ADForest', 'Get-ADOrganizationalUnit', 'Get-ADOptionalFeature', 'Search-ADAccount',
    'Set-ADUser', 'Set-ADComputer', 'Set-ADObject', 'Set-ADAccountPassword',
    'Disable-ADAccount', 'Enable-ADAccount', 'Unlock-ADAccount', 'Move-ADObject',
    'New-ADUser', 'New-ADComputer', 'Add-ADGroupMember', 'Remove-ADGroupMember',
    'Get-CimInstance', 'New-CimSession', 'Invoke-Command', 'New-PSSession', 'Test-WSMan'
)
