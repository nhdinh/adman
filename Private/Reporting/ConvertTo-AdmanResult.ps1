#Requires -Version 5.1
<#
.SYNOPSIS
    ConvertTo-AdmanResult - canonical D-03 schema mapper for AD query results.

.DESCRIPTION
    Maps a raw AD user/computer object (or mock equivalent) into the fixed-schema flat
    PSCustomObject that every renderer consumes. Renderers NEVER touch a raw AD object;
    they only see this schema.

    Fixed identity/scope columns (always present, both types):
      ObjectType, Name, SamAccountName, Enabled, DistinguishedName, ObjectSid, ObjectGuid.

    Nullable type-specific extras:
      User     -> DisplayName, UserPrincipalName, LockedOut, PasswordExpired,
                  PasswordLastSet, AccountExpirationDate.
      Computer -> OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack,
                  IPv4Address, DNSHostName.

    Shared nullable timestamps:
      LastLogonDate, whenCreated, whenChanged.

    Timestamp normalization: all timestamp cells are emitted as [datetime] when present;
    missing cells stay $null. The never-logged-on sentinel (1601-01-01 FILETIME epoch)
    is NOT handled here - that is a report-layer concern (D-03 / D-06).

    This mapper does NOT perform any scope check; that is Test-AdmanInManagedScope's job.
#>

Set-StrictMode -Version Latest

function ConvertTo-AdmanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ADObject,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'Computer')]
        [string]$ObjectType
    )

    # Helper: safely read a property that may not exist on the source object.
    # Returns $null when the property is absent (never throws under StrictMode).
    function script:Get-AdmanProp {
        param($Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj.PSObject.Properties[$Name]) { return $Obj.$Name }
        return $null
    }

    # Fixed identity/scope columns (always present, both types).
    $result = [ordered]@{
        ObjectType        = $ObjectType
        Name              = [string](Get-AdmanProp $ADObject 'Name')
        SamAccountName    = [string](Get-AdmanProp $ADObject 'SamAccountName')
        Enabled           = [bool](Get-AdmanProp $ADObject 'Enabled')
        DistinguishedName = [string](Get-AdmanProp $ADObject 'DistinguishedName')
        ObjectSid         = (Get-AdmanProp $ADObject 'ObjectSid')
        ObjectGuid        = (Get-AdmanProp $ADObject 'ObjectGuid')
    }

    # Nullable type-specific extras.
    if ($ObjectType -eq 'User') {
        $result['DisplayName']           = (Get-AdmanProp $ADObject 'DisplayName')
        $result['UserPrincipalName']     = (Get-AdmanProp $ADObject 'UserPrincipalName')
        $result['LockedOut']             = (Get-AdmanProp $ADObject 'LockedOut')
        $result['PasswordExpired']       = (Get-AdmanProp $ADObject 'PasswordExpired')
        $result['PasswordLastSet']       = (Get-AdmanProp $ADObject 'PasswordLastSet')
        $result['AccountExpirationDate'] = (Get-AdmanProp $ADObject 'AccountExpirationDate')
    }
    else {
        $result['OperatingSystem']            = (Get-AdmanProp $ADObject 'OperatingSystem')
        $result['OperatingSystemVersion']     = (Get-AdmanProp $ADObject 'OperatingSystemVersion')
        $result['OperatingSystemServicePack'] = (Get-AdmanProp $ADObject 'OperatingSystemServicePack')
        $result['IPv4Address']                = (Get-AdmanProp $ADObject 'IPv4Address')
        $result['DNSHostName']                = (Get-AdmanProp $ADObject 'DNSHostName')
    }

    # Shared nullable timestamps.
    $result['LastLogonDate'] = (Get-AdmanProp $ADObject 'LastLogonDate')
    $result['whenCreated']   = (Get-AdmanProp $ADObject 'whenCreated')
    $result['whenChanged']   = (Get-AdmanProp $ADObject 'whenChanged')

    return [pscustomobject]$result
}
