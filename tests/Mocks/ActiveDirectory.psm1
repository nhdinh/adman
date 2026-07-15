#Requires -Version 5.1
<#
.SYNOPSIS
    Offline mocks for every ActiveDirectory / CIM / remoting cmdlet used by adman.

.DESCRIPTION
    Guarantees unit tests NEVER touch a live domain (project constraint / T-00-11). Each stub
    returns a canned PSCustomObject (tagged with an AdmanMock.* TypeName so tests can prove the
    mock - not real AD - answered) or $null for write verbs. No stub performs a network call.
    Import with: Import-Module tests/Mocks/ActiveDirectory.psm1 -Force

    Phase 1 (Plan 01-02): Get-ADUser and Get-ADComputer now accept the scoped paged-read
    parameter set used by the Find verbs (-Filter, -SearchBase, -SearchScope, -ResultPageSize,
    -Properties, -Server). The mocks return a small array of AdmanMock-tagged PSCustomObjects
    whose properties include the requested -Properties list, honor -SearchBase by returning
    objects whose DistinguishedName ends with the supplied DN, and ALWAYS include at least one
    object whose DistinguishedName is OUTSIDE the ManagedOUs scope so the read-side scope
    re-check (Test-AdmanInManagedScope) can be exercised. The captured -Filter/-SearchBase
    arguments are stashed on $script:CapturedCalls so tests can assert exact filter construction
    (e.g. doubled single quotes for O'Brien).
#>

Set-StrictMode -Version Latest

$script:MockSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1000'
$script:MockDomainSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333'

# Captured call log so tests can assert the exact -Filter/-SearchBase/-ResultPageSize/-Server
# arguments the Find verbs constructed. Reset per test via Reset-AdmanMockCapture.
$script:CapturedCalls = [System.Collections.Generic.List[hashtable]]::new()

function Reset-AdmanMockCapture {
    [CmdletBinding()]
    param()
    $script:CapturedCalls.Clear()
}

function Get-AdmanMockCapture {
    [CmdletBinding()]
    param()
    return $script:CapturedCalls.ToArray()
}

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

# Build a scoped-read result row. Honors the requested -Properties list by ensuring each
# requested property exists on the returned object (defaults to $null when no canned value).
function New-AdmanMockScopedRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][string]$DistinguishedName,
        [Parameter(Mandatory)][string]$SamAccountName,
        [string[]]$Properties = @(),
        [hashtable]$ExtraProps = @{}
    )
    $canned = [ordered]@{
        Name                       = ($DistinguishedName -replace '^CN=([^,]+),.*$', '$1')
        SamAccountName             = $SamAccountName
        Enabled                    = $true
        DistinguishedName          = $DistinguishedName
        ObjectSid                  = $script:MockSid
        ObjectGuid                 = [guid]'11111111-2222-3333-4444-555555555555'
        DisplayName                = 'Mock Display'
        UserPrincipalName          = "$SamAccountName@mock.local"
        LockedOut                  = $false
        PasswordExpired            = $false
        PasswordLastSet            = [datetime]'2026-01-01T00:00:00Z'
        AccountExpirationDate      = $null
        OperatingSystem            = 'Windows 11 Pro'
        OperatingSystemVersion     = '10.0 (26200)'
        OperatingSystemServicePack = ''
        IPv4Address                = '10.0.0.10'
        DNSHostName                = 'mockpc.mock.local'
        LastLogonDate              = [datetime]'2026-07-01T00:00:00Z'
        whenCreated                = [datetime]'2025-01-01T00:00:00Z'
        whenChanged                = [datetime]'2026-06-01T00:00:00Z'
        objectClass                = @('top', 'person', 'organizationalPerson', 'user')
        memberOf                   = @()
    }
    foreach ($k in $ExtraProps.Keys) { $canned[$k] = $ExtraProps[$k] }

    # Ensure every requested property is present (default $null when not in the canned set).
    $row = [ordered]@{}
    foreach ($k in $canned.Keys) { $row[$k] = $canned[$k] }
    foreach ($p in @($Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
        if (-not $row.Contains($p)) { $row[$p] = $null }
    }

    $o = [pscustomobject]$row
    $o.PSObject.TypeNames.Insert(0, $TypeName)
    return $o
}

# --- Read stubs (no ShouldProcess needed) ---------------------------------------------------

function Get-ADUser {
    [CmdletBinding()]
    param(
        $Identity,
        $Filter,
        $SearchBase,
        $SearchScope,
        $ResultPageSize,
        $Properties,
        $Server
    )
    # Legacy single-object call shape (Identity-only) keeps prior behavior.
    if ($Identity -and -not $Filter) {
        return (New-AdmanMockObject -TypeName 'AdmanMock.ADUser')
    }

    # Scoped paged read (Filter parameter set). Capture the call for filter-construction tests.
    [void]$script:CapturedCalls.Add(@{
        Cmdlet         = 'Get-ADUser'
        Filter         = $Filter
        SearchBase     = $SearchBase
        SearchScope    = $SearchScope
        ResultPageSize = $ResultPageSize
        Properties     = $Properties
        Server         = $Server
    })

    $sb = [string]$SearchBase
    if ([string]::IsNullOrWhiteSpace($sb)) { $sb = 'OU=Managed,DC=mock,DC=local' }

    # In-scope rows: DN ends with the supplied SearchBase.
    $inScope1 = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADUser' `
        -DistinguishedName "CN=Alice InScope,$sb" `
        -SamAccountName 'alice.inscope' -Properties $Properties
    $inScope2 = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADUser' `
        -DistinguishedName "CN=Bob InScope,OU=Sub,$sb" `
        -SamAccountName 'bob.inscope' -Properties $Properties
    # Out-of-scope row: DN does NOT end with the SearchBase (sibling OU).
    $outScope = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADUser' `
        -DistinguishedName 'CN=Carol OutScope,OU=NotManaged,DC=mock,DC=local' `
        -SamAccountName 'carol.outscope' -Properties $Properties

    return @($inScope1, $inScope2, $outScope)
}

function Get-ADComputer {
    [CmdletBinding()]
    param(
        $Identity,
        $Filter,
        $SearchBase,
        $SearchScope,
        $ResultPageSize,
        $Properties,
        $Server
    )
    if ($Identity -and -not $Filter) {
        return (New-AdmanMockObject -TypeName 'AdmanMock.ADComputer' -Props @{
            objectClass    = @('top', 'person', 'organizationalPerson', 'user', 'computer')
            SamAccountName = 'MOCKPC$'
        })
    }

    [void]$script:CapturedCalls.Add(@{
        Cmdlet         = 'Get-ADComputer'
        Filter         = $Filter
        SearchBase     = $SearchBase
        SearchScope    = $SearchScope
        ResultPageSize = $ResultPageSize
        Properties     = $Properties
        Server         = $Server
    })

    $sb = [string]$SearchBase
    if ([string]::IsNullOrWhiteSpace($sb)) { $sb = 'OU=Managed,DC=mock,DC=local' }

    $inScope1 = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADComputer' `
        -DistinguishedName "CN=PC-INSCOPE-01,$sb" `
        -SamAccountName 'PC-INSCOPE-01$' -Properties $Properties `
        -ExtraProps @{ objectClass = @('top', 'person', 'organizationalPerson', 'user', 'computer') }
    $inScope2 = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADComputer' `
        -DistinguishedName "CN=PC-INSCOPE-02,OU=Sub,$sb" `
        -SamAccountName 'PC-INSCOPE-02$' -Properties $Properties `
        -ExtraProps @{ objectClass = @('top', 'person', 'organizationalPerson', 'user', 'computer') }
    $outScope = New-AdmanMockScopedRow -TypeName 'AdmanMock.ADComputer' `
        -DistinguishedName 'CN=PC-OUTSCOPE-01,OU=NotManaged,DC=mock,DC=local' `
        -SamAccountName 'PC-OUTSCOPE-01$' -Properties $Properties `
        -ExtraProps @{ objectClass = @('top', 'person', 'organizationalPerson', 'user', 'computer') }

    return @($inScope1, $inScope2, $outScope)
}

function Get-ADObject { [CmdletBinding()] param($Identity, $Properties, $Server, $LDAPFilter) New-AdmanMockObject }
function Get-ADGroup { [CmdletBinding()] param($Identity, $Properties, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'group') } }
function Get-ADGroupMember { [CmdletBinding()] param($Identity, $Recursive, $Server) @(New-AdmanMockObject) }
function Get-ADOrganizationalUnit { [CmdletBinding()] param($Identity, $Filter, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'organizationalUnit') } }
function Get-ADOptionalFeature { [CmdletBinding()] param($Identity, $Filter, $Server) New-AdmanMockObject -Props @{ objectClass = @('top', 'msDS-OptionalFeature') } }

# Configurable lastLogonTimestamp replication interval (D-07 MEDIUM-1 conversion matrix).
# Tests set $script:MockLogonSyncInterval via Set-AdmanMockLogonSyncInterval before invoking
# Initialize-Adman or Get-AdmanLogonSyncInterval. Default = 14 (integer shape).
$script:MockLogonSyncInterval = 14

function Set-AdmanMockLogonSyncInterval {
    [CmdletBinding()]
    param($Value)
    $script:MockLogonSyncInterval = $Value
}

function Search-ADAccount {
    [CmdletBinding()]
    param(
        $Identity,
        $Server,
        $SearchBase,
        $SearchScope,
        $ResultPageSize,
        [switch]$AccountDisabled,
        [switch]$AccountExpired,
        [switch]$LockedOut,
        [switch]$PasswordExpired,
        [switch]$UsersOnly,
        [switch]$ComputersOnly
    )

    # Capture the call for state-switch / scoping assertions.
    [void]$script:CapturedCalls.Add(@{
        Cmdlet          = 'Search-ADAccount'
        Server          = $Server
        SearchBase      = $SearchBase
        SearchScope     = $SearchScope
        ResultPageSize  = $ResultPageSize
        AccountDisabled = [bool]$AccountDisabled
        AccountExpired  = [bool]$AccountExpired
        LockedOut       = [bool]$LockedOut
        PasswordExpired = [bool]$PasswordExpired
        UsersOnly       = [bool]$UsersOnly
        ComputersOnly   = [bool]$ComputersOnly
    })

    $sb = [string]$SearchBase
    if ([string]::IsNullOrWhiteSpace($sb)) { $sb = 'OU=Managed,DC=mock,DC=local' }

    # Determine which state bucket this call represents.
    $bucket = $null
    if ($AccountDisabled) { $bucket = 'Disabled' }
    elseif ($AccountExpired) { $bucket = 'Expired' }
    elseif ($LockedOut) { $bucket = 'Locked' }
    elseif ($PasswordExpired) { $bucket = 'PasswordExpired' }

    # Determine object type.
    $isComputer = [bool]$ComputersOnly
    $typeName = if ($isComputer) { 'AdmanMock.ADComputer' } else { 'AdmanMock.ADUser' }
    $samSuffix = if ($isComputer) { '$' } else { '' }

    if ($null -eq $bucket) {
        # No state switch - legacy call shape; return a single generic mock.
        return @(New-AdmanMockObject)
    }

    # Return one in-scope row tagged with the requested state bucket, plus one out-of-scope row
    # so the read-side Test-AdmanInManagedScope re-check can be exercised.
    $inScope = New-AdmanMockScopedRow -TypeName $typeName `
        -DistinguishedName ("CN=Mock{0},{1}" -f $bucket, $sb) `
        -SamAccountName ("mock.{0}{1}" -f $bucket.ToLower(), $samSuffix) `
        -ExtraProps @{
            Enabled               = ($bucket -ne 'Disabled')
            LockedOut             = ($bucket -eq 'Locked')
            PasswordExpired       = ($bucket -eq 'PasswordExpired')
            AccountExpirationDate = if ($bucket -eq 'Expired') { [datetime]'2026-01-01T00:00:00Z' } else { $null }
        }
    $outScope = New-AdmanMockScopedRow -TypeName $typeName `
        -DistinguishedName ("CN=OutScope{0},OU=NotManaged,DC=mock,DC=local" -f $bucket) `
        -SamAccountName ("outscope.{0}{1}" -f $bucket.ToLower(), $samSuffix) `
        -ExtraProps @{
            Enabled               = ($bucket -ne 'Disabled')
            LockedOut             = ($bucket -eq 'Locked')
            PasswordExpired       = ($bucket -eq 'PasswordExpired')
            AccountExpirationDate = if ($bucket -eq 'Expired') { [datetime]'2026-01-01T00:00:00Z' } else { $null }
        }

    return @($inScope, $outScope)
}

function Get-ADDomain {
    [CmdletBinding()] param($Identity, $Server)
    $o = [pscustomobject]@{
        DomainSID                     = $script:MockDomainSid
        DNSRoot                       = 'mock.local'
        NetBIOSName                   = 'MOCK'
        DistinguishedName             = 'DC=mock,DC=local'
        LastLogonReplicationInterval  = $script:MockLogonSyncInterval
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
    'Get-CimInstance', 'New-CimSession', 'Invoke-Command', 'New-PSSession', 'Test-WSMan',
    'Reset-AdmanMockCapture', 'Get-AdmanMockCapture', 'Set-AdmanMockLogonSyncInterval'
)
