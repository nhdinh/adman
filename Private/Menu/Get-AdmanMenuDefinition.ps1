#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanMenuDefinition - returns the ordered Phase-1 menu-item table.

.DESCRIPTION
    Single source of truth for the Start-Adman flat menu (D-01). Each entry is a
    PSCustomObject with four fields:

      * Label      - human-readable menu text shown next to the number.
      * Verb       - the Public function name the menu dispatches to (MENU-04: same
                     function a senior calls directly).
      * PromptSpec - array of @{ Name; Prompt; Required; Choices? } records consumed
                     by Read-AdmanActionParams to build the parameter hashtable.
      * Properties - [string[]] of D-03 schema column names the verb emits. Plan 01-04
                     passes this to Format-AdmanReport / Export-AdmanReportCsv /
                     Export-AdmanReportHtml so a zero-row report still renders headers
                     (Cycle 4 finding).

    The menu body (Start-Adman) reads this table and dispatches via & $Verb @params.
    No AD read logic, no formatting logic, no renderer dispatch lives here.

    Pinned Properties arrays (D-03 schema in 01-02 ConvertTo-AdmanResult plus the
    Bucket column added by report verbs in 01-03):
      * Find verbs -> D-03 type schema, no Bucket.
      * Report verbs -> D-03 type schema + Bucket.
      * Recovery posture -> five-field shape (RecycleBinEnabled, ForestFunctionalLevel,
        TombstoneLifetime, Generated, Freshness).
#>

Set-StrictMode -Version Latest

function Get-AdmanMenuDefinition {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $userProperties = [string[]]@(
        'ObjectType','Name','SamAccountName','Enabled','DistinguishedName','ObjectSid','ObjectGuid',
        'DisplayName','UserPrincipalName','LockedOut','PasswordExpired','PasswordLastSet',
        'AccountExpirationDate','LastLogonDate','whenCreated','whenChanged'
    )

    $computerProperties = [string[]]@(
        'ObjectType','Name','SamAccountName','Enabled','DistinguishedName','ObjectSid','ObjectGuid',
        'OperatingSystem','OperatingSystemVersion','OperatingSystemServicePack','IPv4Address',
        'DNSHostName','LastLogonDate','whenCreated','whenChanged'
    )

    $userReportProperties = [string[]]($userProperties + 'Bucket')
    $computerReportProperties = [string[]]($computerProperties + 'Bucket')

    $recoveryPostureProperties = [string[]]@(
        'RecycleBinEnabled','ForestFunctionalLevel','TombstoneLifetime','Generated','Freshness'
    )

    $menu = @(
        [pscustomobject]@{
            Label      = 'Find user'
            Verb       = 'Find-AdmanUser'
            PromptSpec = @(
                @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
            )
            Properties = $userProperties
        }
        [pscustomobject]@{
            Label      = 'Find computer'
            Verb       = 'Find-AdmanComputer'
            PromptSpec = @(
                @{ Name = 'Name'; Prompt = 'Enter computer name'; Required = $true }
            )
            Properties = $computerProperties
        }
        [pscustomobject]@{
            Label      = 'Stale/inactive report'
            Verb       = 'Get-AdmanStaleReport'
            PromptSpec = @()
            Properties = $userReportProperties
        }
        [pscustomobject]@{
            Label      = 'Account-state report'
            Verb       = 'Get-AdmanAccountStateReport'
            PromptSpec = @()
            Properties = $userReportProperties
        }
        [pscustomobject]@{
            Label      = 'Inventory report'
            Verb       = 'Get-AdmanInventoryReport'
            PromptSpec = @()
            Properties = $computerReportProperties
        }
        [pscustomobject]@{
            Label      = 'Recovery posture'
            Verb       = 'Get-AdmanRecoveryPostureReport'
            PromptSpec = @()
            Properties = $recoveryPostureProperties
        }
    )

    return $menu
}
