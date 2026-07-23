# adman Usage Guide

Operator reference for the `Start-Adman` interactive menu and every exported function in `adman.psd1`.

For remote computer operations, see `docs/REMOTE-OPS.md`. For disaster recovery and certificate rotation, see `docs/RECOVERY-RUNBOOK.md`.

## Menu navigation

`Start-Adman` prints a numbered flat menu. Enter the number of the action you want, or:

- `B` at any prompt returns to the top-level menu.
- `Q` exits adman.

Read-only report verbs prompt for output format after they run:

1. Console table
2. CSV file
3. HTML file

## Menu reference

| # | Label | Verb | Inputs |
|---|-------|------|--------|
| 1 | Find user | `Find-AdmanUser` | `SamAccountName` (required): Enter sAMAccountName |
| 2 | Find computer | `Find-AdmanComputer` | `Name` (required): Enter computer name |
| 3 | Stale/inactive report | `Get-AdmanStaleReport` | None |
| 4 | Account-state report | `Get-AdmanAccountStateReport` | None |
| 5 | Fleet inventory report (with remote enrichment) | `Get-AdmanInventoryReport` | None |
| 6 | Recovery posture | `Get-AdmanRecoveryPostureReport` | None |
| — | --- User writes --- | — | — |
| 7 | Create user | `New-AdmanUser` | `Name` (required): Enter full name (CN); `SamAccountName` (required): Enter sAMAccountName; `UserPrincipalName` (required): Enter UPN (user@domain); `ParentOuDn` (required): Enter parent OU DN; `AccountPassword` (required): Password source — Generate (recommended) or Prompt |
| 8 | Disable user | `Disable-AdmanUser` | `Identity` (required): Enter user identity (sAMAccountName/DN) |
| 9 | Enable user | `Enable-AdmanUser` | `Identity` (required): Enter user identity (sAMAccountName/DN) |
| 10 | Reset user password | `Set-AdmanUserPassword` | `Identity` (required): Enter user identity (sAMAccountName/DN); `NewPassword` (required): Password source — Generate (recommended) or Prompt |
| 11 | Unlock user | `Unlock-AdmanUser` | `Identity` (required): Enter user identity (sAMAccountName/DN) |
| 12 | Move user to OU | `Move-AdmanUser` | `Identity` (required): Enter user identity (sAMAccountName/DN); `TargetPath` (required): Enter destination OU DN |
| — | --- Computer writes --- | — | — |
| 13 | Disable computer | `Disable-AdmanComputer` | `Identity` (required): Enter computer identity (NAME or NAME$) |
| 14 | Enable computer | `Enable-AdmanComputer` | `Identity` (required): Enter computer identity (NAME or NAME$) |
| 15 | Move computer to OU | `Move-AdmanComputer` | `Identity` (required): Enter computer identity (NAME or NAME$); `TargetPath` (required): Enter destination OU DN |
| 16 | Reset computer account | `Reset-AdmanComputerAccount` | `Identity` (required): Enter computer identity (NAME or NAME$) |
| — | --- Local writes --- | — | — |
| 17 | Create local user | `New-AdmanLocalUser` | `Name` (required): Enter local user name; `Password` (required): Password source — Generate (recommended) or Prompt |
| 18 | Reset local user password | `Set-AdmanLocalUser` | `Name` (required): Enter local user name; `Password` (required): Password source — Generate (recommended) or Prompt |
| 19 | Enable local user | `Set-AdmanLocalUser` | `Name` (required): Enter local user name |
| 20 | Disable local user | `Set-AdmanLocalUser` | `Name` (required): Enter local user name |
| 21 | Remove local user | `Remove-AdmanLocalUser` | `Name` (required): Enter local user name |
| 22 | Add local group member | `Add-AdmanLocalGroupMember` | `Name` (required): Enter local user name; `Group` (required): Enter local group name |
| 23 | Remove local group member | `Remove-AdmanLocalGroupMember` | `Name` (required): Enter local user name; `Group` (required): Enter local group name |
| — | --- Group membership --- | — | — |
| 24 | Add to AD group | `Add-AdmanGroupMember` | `Identity` (required): Enter user/computer identity; `GroupIdentity` (required): Enter AD group identity |
| 25 | Remove from AD group | `Remove-AdmanGroupMember` | `Identity` (required): Enter user/computer identity; `GroupIdentity` (required): Enter AD group identity |
| — | --- Bulk & workflows --- | — | — |
| 26 | Bulk action from CSV | `Invoke-AdmanBulkAction` | `Action` (required): Select bulk action — Disable, Enable, Move, AddGroup, RemoveGroup; `Path` (required): Enter CSV path; `TargetPath` (optional): Enter destination OU DN (Move only); `GroupIdentity` (optional): Enter AD group identity (AddGroup/RemoveGroup only) |
| 27 | Onboard new user | `Start-AdmanUserOnboarding` | `FirstName` (required): Enter first name; `LastName` (required): Enter last name |
| 28 | Offboard user | `Start-AdmanUserOffboarding` | `Identity` (required): Enter user identity (sAMAccountName/DN) |
| 29 | Restore quarantined user | `Restore-AdmanQuarantinedUser` | `Identity` (required): Enter user identity (sAMAccountName/DN) |

## Exported functions

Examples use `contoso.local` placeholders. Replace them with your domain values. Never pass plaintext passwords on the command line; use the menu path or prompt for a `SecureString`.

### `Initialize-Adman`

Loads and validates the non-secret config, runs the capability probe, resolves protected SIDs and the deny-list, and ensures the audit directory is writable.

Parameters: `-SetupMode`

```powershell
Initialize-Adman
Initialize-Adman -SetupMode
```

### `Start-Adman`

Interactive menu entry point. Dispatches every read and write verb through the same Public functions available at the PowerShell prompt.

Parameters: none

```powershell
Start-Adman
```

### `Test-AdmanCapability`

Re-runs the startup capability probe on demand and returns a capability object.

Parameters: none

```powershell
Test-AdmanCapability
```

### `Get-AdmanConfig`

Returns the current non-secret config, or a single key if `-Key` is supplied.

Parameters: `-Key`

```powershell
Get-AdmanConfig
Get-AdmanConfig -Key 'ManagedOUs'
```

### `Set-AdmanConfig`

Updates a value in the non-secret config and writes it back to `.store/config.json`.

Parameters: `-Key`, `-Value`, `-Path`

```powershell
Set-AdmanConfig -Key 'ManagedOUs' -Value @('OU=Users,DC=contoso,DC=local')
```

### `Export-AdmanConfig`

Backs up the non-secret config to a JSON file.

Parameters: `-Path`

```powershell
Export-AdmanConfig -Path 'C:\Backups\adman-config.json'
```

### `Import-AdmanConfig`

Restores the non-secret config from a JSON file. Use `-SetupMode` to run the first-run wizard after import.

Parameters: `-Path`, `-SetupMode`

```powershell
Import-AdmanConfig -Path 'C:\Backups\adman-config.json'
```

### `Find-AdmanUser`

Scoped, read-only AD user search. Returns users matching `-Name`, `-SamAccountName`, or `-DisplayName` within the configured managed OUs.

Parameters: `-Name`, `-SamAccountName`, `-DisplayName`

```powershell
Find-AdmanUser -SamAccountName 'jdoe'
Find-AdmanUser -DisplayName 'Jane Doe'
```

### `Find-AdmanComputer`

Scoped, read-only AD computer search. Returns computers matching `-Name` within the configured managed OUs.

Parameters: `-Name`

```powershell
Find-AdmanComputer -Name 'WKSTN-42'
```

### `Get-AdmanStaleReport`

Reports stale or inactive user and computer accounts. Output is a D-03 result object with a `Bucket` column.

Parameters: none

```powershell
Get-AdmanStaleReport | Format-AdmanReport
Get-AdmanStaleReport | Export-AdmanReportCsv -Path 'C:\Reports\stale.csv'
```

### `Get-AdmanAccountStateReport`

Reports account state information (enabled/disabled/locked/password status). Output is a D-03 result object with a `Bucket` column.

Parameters: `-ObjectType`

```powershell
Get-AdmanAccountStateReport -ObjectType 'User' | Format-AdmanReport
```

### `Get-AdmanRecoveryPostureReport`

Reports AD recovery posture: Recycle Bin status, forest functional level, tombstone lifetime, and report freshness.

Parameters: none

```powershell
Get-AdmanRecoveryPostureReport | Format-AdmanReport
```

### `Get-AdmanInventoryReport`

Fleet inventory report with optional remote enrichment via WinRM/CIM. See `docs/REMOTE-OPS.md` for transport and firewall details.

Parameters: none

```powershell
Get-AdmanInventoryReport | Export-AdmanReportHtml -Path 'C:\Reports\inventory.html' -Title 'Contoso Fleet'
```

### `Format-AdmanReport`

Formats a D-03 result object as a console table. Use `-UseGridView` on PowerShell 7 if `Microsoft.PowerShell.ConsoleGuiTools` is installed.

Parameters: `-InputObject`, `-UseGridView`, `-Properties`

```powershell
Get-AdmanStaleReport | Format-AdmanReport
```

### `Export-AdmanReportCsv`

Exports a D-03 result object to CSV. `-Properties` pins the header order even when the result set is empty.

Parameters: `-InputObject`, `-Path`, `-Properties`

```powershell
Get-AdmanAccountStateReport | Export-AdmanReportCsv -Path 'C:\Reports\account-state.csv'
```

### `Export-AdmanReportHtml`

Exports a D-03 result object to a self-contained HTML report. `-Properties` pins the header order even when the result set is empty.

Parameters: `-InputObject`, `-Path`, `-Title`, `-Properties`

```powershell
Get-AdmanInventoryReport | Export-AdmanReportHtml -Path 'C:\Reports\inventory.html' -Title 'Contoso Fleet'
```

### `New-AdmanUser`

Creates an AD user inside a managed OU. `-AccountPassword` accepts a `SecureString`; `-AccountPasswordSource` records whether it was generated or prompted.

Parameters: `-Name`, `-SamAccountName`, `-UserPrincipalName`, `-ParentOuDn`, `-AccountPassword`, `-AccountPasswordSource`, `-Force`

```powershell
New-AdmanUser `
    -Name 'Jane Doe' `
    -SamAccountName 'jdoe' `
    -UserPrincipalName 'jdoe@contoso.local' `
    -ParentOuDn 'OU=Users,DC=contoso,DC=local' `
    -WhatIf
```

### `Disable-AdmanUser`

Disables an AD user account.

Parameters: `-Identity`, `-Force`

```powershell
Disable-AdmanUser -Identity 'jdoe' -WhatIf
```

### `Enable-AdmanUser`

Enables a previously disabled AD user account.

Parameters: `-Identity`, `-Force`

```powershell
Enable-AdmanUser -Identity 'jdoe' -WhatIf
```

### `Set-AdmanUserPassword`

Resets an AD user password. `-NewPassword` accepts a `SecureString`; `-NewPasswordSource` records whether it was generated or prompted.

Parameters: `-Identity`, `-NewPassword`, `-NewPasswordSource`, `-ChangePasswordAtLogon`, `-Unlock`, `-Force`

```powershell
Set-AdmanUserPassword -Identity 'jdoe' -WhatIf
```

### `Unlock-AdmanUser`

Unlocks a locked-out AD user account.

Parameters: `-Identity`, `-Force`

```powershell
Unlock-AdmanUser -Identity 'jdoe' -WhatIf
```

### `Move-AdmanUser`

Moves an AD user to a new OU. Both source and destination must be inside managed OUs.

Parameters: `-Identity`, `-TargetPath`, `-Force`

```powershell
Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Disabled,OU=Managed,DC=contoso,DC=local' -WhatIf
```

### `Disable-AdmanComputer`

Disables an AD computer account.

Parameters: `-Identity`, `-Force`

```powershell
Disable-AdmanComputer -Identity 'WKSTN-42' -WhatIf
```

### `Enable-AdmanComputer`

Enables a previously disabled AD computer account.

Parameters: `-Identity`, `-Force`

```powershell
Enable-AdmanComputer -Identity 'WKSTN-42' -WhatIf
```

### `Move-AdmanComputer`

Moves an AD computer account to a new OU.

Parameters: `-Identity`, `-TargetPath`, `-Force`

```powershell
Move-AdmanComputer -Identity 'WKSTN-42' -TargetPath 'OU=Workstations,OU=Managed,DC=contoso,DC=local' -WhatIf
```

### `Reset-AdmanComputerAccount`

Resets an AD computer account (equivalent to `Reset-ComputerMachineAccount`).

Parameters: `-Identity`, `-Force`

```powershell
Reset-AdmanComputerAccount -Identity 'WKSTN-42' -WhatIf
```

### `New-AdmanLocalUser`

Creates a local user account on a remote computer. `-Password` accepts a `SecureString`; `-PasswordSource` records whether it was generated or prompted.

Parameters: `-Name`, `-Password`, `-PasswordSource`, `-ComputerName`, `-Force`

```powershell
New-AdmanLocalUser -Name 'srvadmin' -ComputerName 'WKSTN-42' -WhatIf
```

### `Set-AdmanLocalUser`

Resets a local user password, enables, or disables a local user account on a remote computer. Use parameter sets: password reset, `-Enable`, or `-Disable`.

Parameters: `-Name`, `-Password`, `-PasswordSource`, `-Enable`, `-Disable`, `-ComputerName`, `-Force`

```powershell
Set-AdmanLocalUser -Name 'srvadmin' -ComputerName 'WKSTN-42' -WhatIf
Set-AdmanLocalUser -Name 'srvadmin' -ComputerName 'WKSTN-42' -Enable -WhatIf
Set-AdmanLocalUser -Name 'srvadmin' -ComputerName 'WKSTN-42' -Disable -WhatIf
```

### `Remove-AdmanLocalUser`

Removes a local user account from a remote computer.

Parameters: `-Name`, `-ComputerName`, `-Force`

```powershell
Remove-AdmanLocalUser -Name 'srvadmin' -ComputerName 'WKSTN-42' -WhatIf
```

### `Add-AdmanLocalGroupMember`

Adds a local user to a local group on a remote computer.

Parameters: `-Name`, `-Group`, `-ComputerName`, `-Force`

```powershell
Add-AdmanLocalGroupMember -Name 'srvadmin' -Group 'Administrators' -ComputerName 'WKSTN-42' -WhatIf
```

### `Remove-AdmanLocalGroupMember`

Removes a local user from a local group on a remote computer.

Parameters: `-Name`, `-Group`, `-ComputerName`, `-Force`

```powershell
Remove-AdmanLocalGroupMember -Name 'srvadmin' -Group 'Administrators' -ComputerName 'WKSTN-42' -WhatIf
```

### `Add-AdmanGroupMember`

Adds a user or computer to an AD group.

Parameters: `-Identity`, `-GroupIdentity`, `-Force`

```powershell
Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'CN=Helpdesk,OU=Groups,DC=contoso,DC=local' -WhatIf
```

### `Remove-AdmanGroupMember`

Removes a user or computer from an AD group.

Parameters: `-Identity`, `-GroupIdentity`, `-Force`

```powershell
Remove-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'CN=Helpdesk,OU=Groups,DC=contoso,DC=local' -WhatIf
```

### `Invoke-AdmanBulkAction`

Runs a bulk action from a CSV or pipeline input. Supported actions: `Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`.

Parameters: `-Action`, `-InputObject`, `-Path`, `-TargetPath`, `-GroupIdentity`, `-Force`

```powershell
Invoke-AdmanBulkAction -Action 'Disable' -Path 'C:\Bulk\users.csv' -WhatIf
Invoke-AdmanBulkAction -Action 'Move' -Path 'C:\Bulk\computers.csv' -TargetPath 'OU=Retired,DC=contoso,DC=local' -WhatIf
```

### `Start-AdmanUserOnboarding`

Guided workflow that creates a new user, sets an initial password, and applies the configured onboarding group/OU defaults.

Parameters: `-FirstName`, `-LastName`, `-Force`

```powershell
Start-AdmanUserOnboarding -FirstName 'Jane' -LastName 'Doe' -WhatIf
```

### `Start-AdmanUserOffboarding`

Guided workflow that disables a user, moves the account to a quarantine OU, and removes group memberships.

Parameters: `-Identity`, `-Force`

```powershell
Start-AdmanUserOffboarding -Identity 'jdoe' -WhatIf
```

### `Restore-AdmanQuarantinedUser`

Restores a user from the quarantine OU back to an active OU.

Parameters: `-Identity`, `-Force`

```powershell
Restore-AdmanQuarantinedUser -Identity 'jdoe' -WhatIf
```

---

*Last updated: 2026-07-22 for adman Phases 0-4.*
