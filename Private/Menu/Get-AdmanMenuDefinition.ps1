#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanMenuDefinition - returns the ordered menu-item table (Phase 1 read + Phase 2 write).

.DESCRIPTION
    Single source of truth for the Start-Adman flat menu (D-01). Each entry is a
    PSCustomObject with five fields:

      * Label      - human-readable menu text shown next to the number.
      * Verb       - the Public function name the menu dispatches to (MENU-04: same
                     function a senior calls directly). $null for non-selectable
                     section separator entries.
      * PromptSpec - array of @{ Name; Prompt; Required; Choices?; Type?; Kind? } records
                     consumed by Read-AdmanActionParams to build the parameter
                     hashtable. The optional Type field defaults to 'Text'; the
                     value 'GeneratedPassword' triggers the D-05 Generate/Prompt
                     numeric sub-choice. The values 'AdIdentity' and 'AdOuDn'
                     (G-02-2 / G-02-4) route through Resolve-AdmanIdentity at
                     prompt time so malformed input re-prompts instead of
                     crashing the gate. 'AdIdentity' honors the optional Kind
                     field: 'AdUser' (default) or 'AdComputer' (REV-3 - tries
                     both NAME and NAME$ sAMAccountName forms).
      * Properties - [string[]] of D-03 schema column names the verb emits. Plan 01-04
                     passes this to Format-AdmanReport / Export-AdmanReportCsv /
                     Export-AdmanReportHtml so a zero-row report still renders headers
                     (Cycle 4 finding). Empty for write verbs (they do not produce
                     D-03 report rows).
      * FixedParameters - optional hashtable of parameters the dispatcher injects
                     WITHOUT prompting (MEDIUM #6 review fix). Used by the
                     Set-AdmanLocalUser Enable/Disable entries to inject the
                     -Enable / -Disable switch declaratively (the operator picked
                     the action by picking the menu item; no further prompt).

    PROMPTSPEC-PARAMETER NAME CONTRACT (HIGH #1 cycle-2 review fix): every PromptSpec
    Name MUST exactly match a parameter name on the target verb. Start-Adman
    dispatches via `& $Verb @params`, so a PromptSpec Name that is not a declared
    parameter on the verb throws "parameter cannot be found" from the menu path
    while direct senior calls succeed. The password PromptSpec names are per-verb:
      * 'AccountPassword'  -> New-AdmanUser         (auto marker: AccountPasswordSource)
      * 'NewPassword'      -> Set-AdmanUserPassword (auto marker: NewPasswordSource)
      * 'Password'         -> New-AdmanLocalUser, Set-AdmanLocalUser (auto marker: PasswordSource)
    The accompanying "${name}Source" markers are declared as optional
    [ValidateSet('Generate','Prompt')] parameters on the corresponding verbs in
    Plans 02-02 and 02-04, so the menu can safely set them and the splat binds.

    VALIDATION: a FixedParameters key MUST NOT collide with a PromptSpec Name on the
    same entry (a fixed key shadowing a prompted key would silently drop the
    operator's input). This is enforced by a Pester test in tests/Menu.Tests.ps1.

    The menu body (Start-Adman) reads this table and dispatches via & $Verb @params.
    No AD read logic, no formatting logic, no renderer dispatch lives here.

    Pinned Properties arrays (D-03 schema in 01-02 ConvertTo-AdmanResult plus the
    Bucket column added by report verbs in 01-03):
      * Find verbs -> D-03 type schema, no Bucket.
      * Report verbs -> D-03 type schema + Bucket.
      * Recovery posture -> five-field shape (RecycleBinEnabled, ForestFunctionalLevel,
        TombstoneLifetime, Generated, Freshness).
      * Write verbs -> empty [string[]]@() (writes do not produce D-03 report rows).
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
    $computerReportProperties = [string[]]($computerProperties + 'Bucket' + 'Transport' + 'RemoteOS' + 'Uptime' + 'LoggedOnUser')

    $recoveryPostureProperties = [string[]]@(
        'RecycleBinEnabled','ForestFunctionalLevel','TombstoneLifetime','Generated','Freshness'
    )

    $emptyProperties = [string[]]@()

    # Helper: build a non-selectable section separator entry. Verb=$null tells
    # Start-Adman to render the label as a plain text line (no number prefix,
    # not selectable).
    $newSeparator = {
        param([string]$Label)
        [pscustomobject]@{
            Label           = $Label
            Verb            = $null
            PromptSpec      = @()
            Properties      = $emptyProperties
            FixedParameters = $null
        }
    }

    $menu = @(
        # --- Phase 1 read-only entries (Search + Reports) -------------------------
        [pscustomobject]@{
            Label           = 'Find user'
            Verb            = 'Find-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
            )
            Properties      = $userProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Find computer'
            Verb            = 'Find-AdmanComputer'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter computer name'; Required = $true }
            )
            Properties      = $computerProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Stale/inactive user report'
            Verb            = 'Get-AdmanStaleReport'
            PromptSpec      = @()
            Properties      = $userReportProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Account-state report'
            Verb            = 'Get-AdmanAccountStateReport'
            PromptSpec      = @()
            Properties      = $userReportProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Fleet inventory report (with remote enrichment)'
            Verb            = 'Get-AdmanInventoryReport'
            PromptSpec      = @()
            Properties      = $computerReportProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Recovery posture'
            Verb            = 'Get-AdmanRecoveryPostureReport'
            PromptSpec      = @()
            Properties      = $recoveryPostureProperties
            FixedParameters = $null
        }

        # --- User writes (Phase 2) -----------------------------------------------
        & $newSeparator '--- User writes ---'
        [pscustomobject]@{
            Label           = 'Create user'
            Verb            = 'New-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter full name (CN)'; Required = $true }
                @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
                @{ Name = 'UserPrincipalName'; Prompt = 'Enter UPN (user@domain)'; Required = $true }
                @{ Name = 'ParentOuDn'; Prompt = 'Enter parent OU DN'; Required = $true; Type = 'AdOuDn' }
                @{
                    Name     = 'AccountPassword'
                    Prompt   = 'Password source'
                    Required = $false
                    Type     = 'GeneratedPassword'
                    Choices  = @('Generate (recommended)', 'Prompt')
                }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Disable user'
            Verb            = 'Disable-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Enable user'
            Verb            = 'Enable-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Reset user password'
            Verb            = 'Set-AdmanUserPassword'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
                @{
                    Name     = 'NewPassword'
                    Prompt   = 'Password source'
                    Required = $false
                    Type     = 'GeneratedPassword'
                    Choices  = @('Generate (recommended)', 'Prompt')
                }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Unlock user'
            Verb            = 'Unlock-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Move user to OU'
            Verb            = 'Move-AdmanUser'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
                @{ Name = 'TargetPath'; Prompt = 'Enter destination OU DN'; Required = $true; Type = 'AdOuDn' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }

        # --- Computer writes (Phase 2) --------------------------------------------
        & $newSeparator '--- Computer writes ---'
        [pscustomobject]@{
            Label           = 'Disable computer'
            Verb            = 'Disable-AdmanComputer'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter computer identity (NAME or NAME$)'; Required = $true; Type = 'AdIdentity'; Kind = 'AdComputer' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Enable computer'
            Verb            = 'Enable-AdmanComputer'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter computer identity (NAME or NAME$)'; Required = $true; Type = 'AdIdentity'; Kind = 'AdComputer' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Move computer to OU'
            Verb            = 'Move-AdmanComputer'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter computer identity (NAME or NAME$)'; Required = $true; Type = 'AdIdentity'; Kind = 'AdComputer' }
                @{ Name = 'TargetPath'; Prompt = 'Enter destination OU DN'; Required = $true; Type = 'AdOuDn' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Reset computer account'
            Verb            = 'Reset-AdmanComputerAccount'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter computer identity (NAME or NAME$)'; Required = $true; Type = 'AdIdentity'; Kind = 'AdComputer' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }

        # --- Local writes (Phase 2) -----------------------------------------------
        & $newSeparator '--- Local writes ---'
        [pscustomobject]@{
            Label           = 'Create local user'
            Verb            = 'New-AdmanLocalUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
                @{
                    Name     = 'Password'
                    Prompt   = 'Password source'
                    Required = $false
                    Type     = 'GeneratedPassword'
                    Choices  = @('Generate (recommended)', 'Prompt')
                }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Reset local user password'
            Verb            = 'Set-AdmanLocalUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
                @{
                    Name     = 'Password'
                    Prompt   = 'Password source'
                    Required = $false
                    Type     = 'GeneratedPassword'
                    Choices  = @('Generate (recommended)', 'Prompt')
                }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Enable local user'
            Verb            = 'Set-AdmanLocalUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = @{ Enable = $true }
        }
        [pscustomobject]@{
            Label           = 'Disable local user'
            Verb            = 'Set-AdmanLocalUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = @{ Disable = $true }
        }
        [pscustomobject]@{
            Label           = 'Remove local user'
            Verb            = 'Remove-AdmanLocalUser'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Add local group member'
            Verb            = 'Add-AdmanLocalGroupMember'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
                @{ Name = 'Group'; Prompt = 'Enter local group name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Remove local group member'
            Verb            = 'Remove-AdmanLocalGroupMember'
            PromptSpec      = @(
                @{ Name = 'Name'; Prompt = 'Enter local user name'; Required = $true }
                @{ Name = 'Group'; Prompt = 'Enter local group name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }

        # --- Group membership (Phase 2) -------------------------------------------
        & $newSeparator '--- Group membership ---'
        [pscustomobject]@{
            Label           = 'Add to AD group'
            Verb            = 'Add-AdmanGroupMember'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user/computer identity'; Required = $true; Type = 'AdIdentity' }
                @{ Name = 'GroupIdentity'; Prompt = 'Enter AD group identity'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Remove from AD group'
            Verb            = 'Remove-AdmanGroupMember'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user/computer identity'; Required = $true; Type = 'AdIdentity' }
                @{ Name = 'GroupIdentity'; Prompt = 'Enter AD group identity'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }

        # --- Bulk & workflows (Phase 4) -------------------------------------------
        & $newSeparator '--- Bulk & workflows ---'
        # v1: CSV-only bulk in the TUI. Search-based bulk is available via direct
        # PowerShell pipeline to Invoke-AdmanBulkAction (review finding).
        [pscustomobject]@{
            Label           = 'Bulk action from CSV'
            Verb            = 'Invoke-AdmanBulkAction'
            PromptSpec      = @(
                @{ Name = 'Action'; Prompt = 'Select bulk action'; Required = $true; Choices = @('Disable', 'Enable', 'Move', 'AddGroup', 'RemoveGroup') }
                @{ Name = 'Path'; Prompt = 'Enter CSV path'; Required = $true }
                @{ Name = 'TargetPath'; Prompt = 'Enter destination OU DN (Move only)'; Required = $false }
                @{ Name = 'GroupIdentity'; Prompt = 'Enter AD group identity (AddGroup/RemoveGroup only)'; Required = $false }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
        [pscustomobject]@{
            Label           = 'Onboard new user'
            Verb            = 'Start-AdmanUserOnboarding'
            PromptSpec      = @(
                @{ Name = 'FirstName'; Prompt = 'Enter first name'; Required = $true }
                @{ Name = 'LastName'; Prompt = 'Enter last name'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
            SkipOutputPrompt = $true
        }
        [pscustomobject]@{
            Label           = 'Offboard user'
            Verb            = 'Start-AdmanUserOffboarding'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
            SkipOutputPrompt = $true
        }
        [pscustomobject]@{
            Label           = 'Restore quarantined user'
            Verb            = 'Restore-AdmanQuarantinedUser'
            PromptSpec      = @(
                @{ Name = 'Identity'; Prompt = 'Enter user identity (sAMAccountName/DN)'; Required = $true; Type = 'AdIdentity' }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
            SkipOutputPrompt = $true
        }
    )

    return $menu
}
