#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) behavior tests for the adman module boundary (SAFE-08, T-00-01).

.NOTES
    Pester 6. The PSFramework RequiredModule is satisfied by a throwaway stub built on
    $TestDrive so the real (human-gated) PSFramework install is NOT required to load the
    manifest in unit tests. No AD cmdlet is available or invoked — import must be side-effect-free.
#>

BeforeAll {
    # Throwaway PSFramework 1.14.457 stub so RequiredModules resolves without a real install.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-000000000001'
    FunctionsToExport = @('Set-PSFConfig','Register-PSFConfigValidation','Export-PSFConfig','Import-PSFConfig','Write-PSFMessage')
}
"@ | Set-Content -Path (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
    @'
function Set-PSFConfig { [CmdletBinding()] param($Value, [switch]$Initialize) }
function Register-PSFConfigValidation { [CmdletBinding()] param() }
function Export-PSFConfig { [CmdletBinding()] param($Path) }
function Import-PSFConfig { [CmdletBinding()] param($Path) }
function Write-PSFMessage { [CmdletBinding()] param($Level, $Message) }
'@ | Set-Content -Path (Join-Path $stubDir 'PSFramework.psm1') -Encoding UTF8
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:ModuleName = 'adman'
    $script:ManifestPath = Join-Path $PSScriptRoot '..\adman.psd1'
    $script:ModulePath = Join-Path $PSScriptRoot '..\adman.psm1'
}

AfterAll {
    Remove-Module -Name $script:ModuleName -Force -ErrorAction SilentlyContinue
}

Describe 'adman module boundary (SAFE-08 / T-00-01)' {

    It 'imports on Windows PowerShell 5.1 and sets ErrorActionPreference=Stop inside the module scope' {
        { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        $eap = & (Get-Module $script:ModuleName) { $ErrorActionPreference }
        $eap | Should -Be 'Stop'
    }

    It 'exports exactly the manifest FunctionsToExport and does NOT export the gate (Invoke-AdmanMutation)' {
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
        $exported = @((Get-Command -Module $script:ModuleName).Name)
        $mf = Test-ModuleManifest $script:ManifestPath -ErrorAction Stop
        $expected = @($mf.ExportedFunctions.Keys)

        $exported.Count | Should -Be $expected.Count
        Compare-Object -ReferenceObject $expected -DifferenceObject $exported | Should -BeNullOrEmpty
        $exported | Should -Not -Contain 'Invoke-AdmanMutation'
        $exported | Should -Contain 'Initialize-Adman'
        $exported | Should -Contain 'Start-Adman'
    }

    It 'manifest pins PSFramework (exact) and excludes ActiveDirectory and the export wildcard' {
        $raw = Get-Content $script:ManifestPath -Raw -ErrorAction Stop

        # No wildcard export (SAFE-08: FunctionsToExport is explicit, never '*')
        $raw | Should -Not -Match "FunctionsToExport\s*=\s*['`"]\*['`"]"

        # PSFramework pinned with an EXACT RequiredVersion (not a ModuleVersion floor)
        $raw | Should -Match "ModuleName\s*=\s*'PSFramework'"
        $raw | Should -Match "RequiredVersion\s*=\s*'1\.14\.457'"
        $raw | Should -Not -Match "ModuleVersion\s*=\s*'1\.14\.457'"

        # RSAT/ActiveDirectory is a prerequisite, never a bundled dependency
        $raw | Should -Not -Match 'ActiveDirectory'
    }

    It 'import is side-effect-free (no domain touch; ActiveDirectory not loaded)' {
        function Get-ADDomain { }   # stand-in so Pester can mock; the loader must never call it
        Mock Get-ADDomain { }

        { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw

        Should -Invoke Get-ADDomain -Times 0 -Because 'module import must not touch the domain'

        # Prove the REAL RSAT ActiveDirectory module was not loaded by adman's import.
        # The offline mock at tests/Mocks/ActiveDirectory.psm1 is ALSO named 'ActiveDirectory'
        # (filename-derived) and may already be loaded by Harness.Tests.ps1 in the same Pester
        # run, so a bare `Get-Module 'ActiveDirectory'` collides with the mock. Filter out any
        # module living under the repo tests/ tree so we assert only on the genuine RSAT module.
        $realAd = Get-Module 'ActiveDirectory' |
            Where-Object { $_.ModuleBase -notmatch '[\\/]tests[\\/]' }
        $realAd | Should -BeNullOrEmpty -Because 'adman import must not load the real RSAT ActiveDirectory module'
    }

    It 'FunctionsToExport contains all 17 Phase 2 write verbs explicitly (HIGH #2 review fix re-verification)' {
        $mf = Test-ModuleManifest $script:ManifestPath -ErrorAction Stop
        $exported = @($mf.ExportedFunctions.Keys)

        $phase2Verbs = @(
            'New-AdmanUser'
            'Disable-AdmanUser'
            'Enable-AdmanUser'
            'Set-AdmanUserPassword'
            'Unlock-AdmanUser'
            'Move-AdmanUser'
            'Disable-AdmanComputer'
            'Enable-AdmanComputer'
            'Move-AdmanComputer'
            'Reset-AdmanComputerAccount'
            'New-AdmanLocalUser'
            'Set-AdmanLocalUser'
            'Remove-AdmanLocalUser'
            'Add-AdmanLocalGroupMember'
            'Remove-AdmanLocalGroupMember'
            'Add-AdmanGroupMember'
            'Remove-AdmanGroupMember'
        )
        foreach ($v in $phase2Verbs) {
            $exported | Should -Contain $v -Because "Wave 2 plans landed the export for $v (HIGH #2 review fix re-verification)"
        }

        # Explicit list only — never the wildcard.
        $raw = Get-Content $script:ManifestPath -Raw -ErrorAction Stop
        $raw | Should -Not -Match "FunctionsToExport\s*=\s*['`"]\*['`"]"
    }

    It 'FunctionsToExport contains all four Phase 4 bulk/workflow verbs explicitly' {
        $mf = Test-ModuleManifest $script:ManifestPath -ErrorAction Stop
        $exported = @($mf.ExportedFunctions.Keys)

        $phase4Verbs = @(
            'Invoke-AdmanBulkAction'
            'Start-AdmanUserOnboarding'
            'Start-AdmanUserOffboarding'
            'Restore-AdmanQuarantinedUser'
        )
        foreach ($v in $phase4Verbs) {
            $exported | Should -Contain $v -Because "Phase 4 plans must export $v"
        }
    }
}
