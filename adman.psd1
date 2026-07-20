#
# Module manifest for module 'adman'
#
# Safety scaffold (Phase 0, plan 00-01). The export boundary is the static SAFE-08
# control: FunctionsToExport is an explicit list (NEVER '*') and the mutation gate
# Invoke-AdmanMutation is deliberately ABSENT from it. RSAT/AD is a prerequisite,
# never a bundled dependency, so it is not listed in RequiredModules.
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule = 'adman.psm1'

    # Version number of this module.
    ModuleVersion = '0.1.0'

    # Supported PSEditions — Desktop only until the Phase 5 CI matrix passes on 7.6.
    CompatiblePSEditions = @('Desktop')

    # ID used to uniquely identify this module.
    GUID = 'a1d2a3a4-0000-4a6d-9a6e-000000000001'

    # Author of this module.
    Author = 'adman team'

    # Company or vendor of this module.
    CompanyName = 'adman'

    # Copyright statement for this module.
    Copyright = '(c) 2026 adman. Internal use.'

    # Description of the functionality provided by this module.
    Description = 'adman - safety-first on-prem AD user/computer administration toolkit (Phase 0 foundation scaffold).'

    # Minimum version of the PowerShell engine required by this module.
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module.
    # PSFramework is pinned with an EXACT RequiredVersion (a ModuleVersion value would only be a
    # minimum floor and could let a newer PSFramework satisfy the requirement). Pinned to the
    # build-time-verified version (see 00-01-PSFramework-verified.md).
    RequiredModules = @(
        @{
            ModuleName      = 'PSFramework'
            RequiredVersion = '1.14.457'
        }
    )

    # Functions to export from this module. Explicit list ONLY (SAFE-08). The gate
    # Invoke-AdmanMutation is intentionally NOT exported. 00-02 appends the *-AdmanConfig
    # verbs and Test-AdmanCapability; Phase 1 wires Start-Adman to the menu.
    FunctionsToExport = @('Initialize-Adman', 'Start-Adman', 'Get-AdmanConfig', 'Set-AdmanConfig', 'Export-AdmanConfig', 'Import-AdmanConfig', 'Test-AdmanCapability', 'Find-AdmanUser', 'Find-AdmanComputer', 'Get-AdmanStaleReport', 'Get-AdmanAccountStateReport', 'Get-AdmanRecoveryPostureReport', 'Format-AdmanReport', 'Export-AdmanReportCsv', 'Export-AdmanReportHtml', 'Get-AdmanInventoryReport', 'New-AdmanUser', 'Disable-AdmanUser', 'Enable-AdmanUser', 'Set-AdmanUserPassword', 'Unlock-AdmanUser', 'Move-AdmanUser', 'Disable-AdmanComputer', 'Enable-AdmanComputer', 'Move-AdmanComputer', 'Reset-AdmanComputerAccount', 'New-AdmanLocalUser', 'Set-AdmanLocalUser', 'Remove-AdmanLocalUser', 'Add-AdmanLocalGroupMember', 'Remove-AdmanLocalGroupMember', 'Add-AdmanGroupMember', 'Remove-AdmanGroupMember', 'Invoke-AdmanBulkAction', 'Start-AdmanUserOnboarding', 'Start-AdmanUserOffboarding', 'Restore-AdmanQuarantinedUser')

    # Cmdlets to export from this module.
    CmdletsToExport = @()

    # Variables to export from this module.
    VariablesToExport = @()

    # Aliases to export from this module.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess.
    PrivateData = @{
        PSData = @{
            Tags = @('adman', 'safety', 'foundation')
            ReleaseNotes = @'
Phase 0 (00-01) scaffold only: export boundary + loader + lint/test harness.
CompatiblePSEditions is Desktop-only on purpose; it gains Core only after the
Phase 5 dual-edition CI matrix passes on PowerShell 7.6 (honest edition claim).
The mutation gate Invoke-AdmanMutation is private and not exported (SAFE-08).
'@
        }
    }

}
