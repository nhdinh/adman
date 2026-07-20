#Requires -Modules Pester
<#
.SYNOPSIS
    Phase 4 bulk and workflow menu integration tests.

.DESCRIPTION
    Contract tests for the Phase 4 menu entries added in plan 04-04:
      * Invoke-AdmanBulkAction (CSV-scoped bulk entry)
      * Start-AdmanUserOnboarding
      * Start-AdmanUserOffboarding
      * Restore-AdmanQuarantinedUser

    Verifies MENU-04 dispatch contract, the SkipOutputPrompt skip contract for
    workflow/checklist verbs, and that no PromptSpec/FixedParameters key drifts
    from the declared verb parameters.

    Runs offline; no RSAT, no live domain.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:MenuDefPath = Join-Path $script:RepoRoot 'Private/Menu/Get-AdmanMenuDefinition.ps1'
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'

    # PSFramework stub so the module manifest resolves.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000e1'
    FunctionsToExport = @('Set-PSFConfig','Get-PSFConfig','Register-PSFConfigValidation','Export-PSFConfig','Import-PSFConfig','Write-PSFMessage')
}
"@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
    @'
function Set-PSFConfig { [CmdletBinding()] param($Value, [switch]$Initialize, $Name, $Module) }
function Get-PSFConfig { [CmdletBinding()] param($Name, $Module) }
function Register-PSFConfigValidation { [CmdletBinding()] param() }
function Export-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Import-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Write-PSFMessage { [CmdletBinding()] param($Level, $Message) }
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psm1') -Encoding UTF8
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}

Describe 'Phase 4 bulk and workflow menu entries exist' -Tag 'Unit' {

    BeforeAll {
        . $script:MenuDefPath
        $script:menuDef = Get-AdmanMenuDefinition
        $script:byVerb = @{}
        foreach ($e in $script:menuDef) {
            if ($null -eq $e.Verb) { continue }
            if (-not $script:byVerb.ContainsKey($e.Verb)) {
                $script:byVerb[$e.Verb] = New-Object System.Collections.ArrayList
            }
            [void]$script:byVerb[$e.Verb].Add($e)
        }
    }

    It 'menu contains an entry for Invoke-AdmanBulkAction' {
        $script:byVerb.ContainsKey('Invoke-AdmanBulkAction') | Should -BeTrue
    }

    It 'menu contains an entry for Start-AdmanUserOnboarding' {
        $script:byVerb.ContainsKey('Start-AdmanUserOnboarding') | Should -BeTrue
    }

    It 'menu contains an entry for Start-AdmanUserOffboarding' {
        $script:byVerb.ContainsKey('Start-AdmanUserOffboarding') | Should -BeTrue
    }

    It 'menu contains an entry for Restore-AdmanQuarantinedUser' {
        $script:byVerb.ContainsKey('Restore-AdmanQuarantinedUser') | Should -BeTrue
    }

    It 'all four Phase 4 write entries have empty [string[]] Properties' {
        $phase4Verbs = @('Invoke-AdmanBulkAction', 'Start-AdmanUserOnboarding', 'Start-AdmanUserOffboarding', 'Restore-AdmanQuarantinedUser')
        foreach ($v in $phase4Verbs) {
            $entry = $script:menuDef | Where-Object { $_.Verb -eq $v } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty
            ,$entry.Properties | Should -BeOfType [string[]]
            $entry.Properties.Count | Should -Be 0 -Because "$v is a write verb and emits no D-03 report rows"
        }
    }
}

Describe 'Phase 4 bulk entry is CSV-scoped in v1' -Tag 'Unit' {

    BeforeAll {
        . $script:MenuDefPath
        $script:menuDef = Get-AdmanMenuDefinition
        $script:bulkEntry = $script:menuDef | Where-Object { $_.Verb -eq 'Invoke-AdmanBulkAction' } | Select-Object -First 1
    }

    It 'bulk entry exposes Action choices Disable/Enable/Move/AddGroup/RemoveGroup' {
        $script:bulkEntry | Should -Not -BeNullOrEmpty
        $actionSpec = $script:bulkEntry.PromptSpec | Where-Object { $_.Name -eq 'Action' }
        $actionSpec | Should -Not -BeNullOrEmpty
        $actionSpec.Choices | Should -Contain 'Disable'
        $actionSpec.Choices | Should -Contain 'Enable'
        $actionSpec.Choices | Should -Contain 'Move'
        $actionSpec.Choices | Should -Contain 'AddGroup'
        $actionSpec.Choices | Should -Contain 'RemoveGroup'
    }

    It 'bulk entry requires Path (CSV ingestion in v1)' {
        $pathSpec = $script:bulkEntry.PromptSpec | Where-Object { $_.Name -eq 'Path' }
        $pathSpec | Should -Not -BeNullOrEmpty
        $pathSpec.Required | Should -BeTrue
    }

    It 'bulk entry has optional TargetPath and GroupIdentity prompts' {
        $tpSpec = $script:bulkEntry.PromptSpec | Where-Object { $_.Name -eq 'TargetPath' }
        $tpSpec | Should -Not -BeNullOrEmpty
        $tpSpec.Required | Should -BeFalse

        $giSpec = $script:bulkEntry.PromptSpec | Where-Object { $_.Name -eq 'GroupIdentity' }
        $giSpec | Should -Not -BeNullOrEmpty
        $giSpec.Required | Should -BeFalse
    }

    It 'bulk entry does NOT set SkipOutputPrompt' {
        $script:bulkEntry.PSObject.Properties.Name | Should -Not -Contain 'SkipOutputPrompt'
    }
}

Describe 'Phase 4 workflow entries skip the generic output-format prompt' -Tag 'Unit' {

    BeforeAll {
        . $script:MenuDefPath
        $script:menuDef = Get-AdmanMenuDefinition
    }

    It 'Start-AdmanUserOnboarding entry has SkipOutputPrompt = $true' {
        $entry = $script:menuDef | Where-Object { $_.Verb -eq 'Start-AdmanUserOnboarding' } | Select-Object -First 1
        $entry.SkipOutputPrompt | Should -BeTrue
    }

    It 'Start-AdmanUserOffboarding entry has SkipOutputPrompt = $true' {
        $entry = $script:menuDef | Where-Object { $_.Verb -eq 'Start-AdmanUserOffboarding' } | Select-Object -First 1
        $entry.SkipOutputPrompt | Should -BeTrue
    }

    It 'Restore-AdmanQuarantinedUser entry has SkipOutputPrompt = $true' {
        $entry = $script:menuDef | Where-Object { $_.Verb -eq 'Restore-AdmanQuarantinedUser' } | Select-Object -First 1
        $entry.SkipOutputPrompt | Should -BeTrue
    }

    It 'pre-Phase 4 entries may have SkipOutputPrompt absent or $null without breaking the contract' {
        $prePhase4 = @(
            'Find-AdmanUser', 'Find-AdmanComputer', 'Get-AdmanStaleReport',
            'Get-AdmanAccountStateReport', 'Get-AdmanInventoryReport',
            'Get-AdmanRecoveryPostureReport', 'New-AdmanUser', 'Disable-AdmanUser',
            'Enable-AdmanUser', 'Set-AdmanUserPassword', 'Unlock-AdmanUser',
            'Move-AdmanUser', 'Disable-AdmanComputer', 'Enable-AdmanComputer',
            'Move-AdmanComputer', 'Reset-AdmanComputerAccount', 'New-AdmanLocalUser',
            'Set-AdmanLocalUser', 'Remove-AdmanLocalUser', 'Add-AdmanLocalGroupMember',
            'Remove-AdmanLocalGroupMember', 'Add-AdmanGroupMember', 'Remove-AdmanGroupMember'
        )
        foreach ($v in $prePhase4) {
            $entry = $script:menuDef | Where-Object { $_.Verb -eq $v } | Select-Object -First 1
            if ($null -eq $entry) { continue }
            $hasProp = $entry.PSObject.Properties.Name -contains 'SkipOutputPrompt'
            if ($hasProp) {
                $entry.SkipOutputPrompt | Should -BeIn @($true, $false, $null) -Because "pre-Phase 4 entry $v SkipOutputPrompt must be a boolean or null"
            }
        }
    }
}

Describe 'Phase 4 menu entry parameters resolve to declared verb parameters' -Tag 'Unit' {

    BeforeAll {
        . $script:MenuDefPath
        $script:menuDef = Get-AdmanMenuDefinition
    }

    It 'every Phase 4 entry PromptSpec Name + FixedParameters key resolves to a declared parameter on the target verb' {
        $phase4Verbs = @('Invoke-AdmanBulkAction', 'Start-AdmanUserOnboarding', 'Start-AdmanUserOffboarding', 'Restore-AdmanQuarantinedUser')
        foreach ($v in $phase4Verbs) {
            $entry = $script:menuDef | Where-Object { $_.Verb -eq $v } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty
            $cmd = Get-Command $v -ErrorAction Stop
            $declaredParams = @($cmd.Parameters.Keys)

            $splatKeys = New-Object System.Collections.ArrayList
            foreach ($spec in $entry.PromptSpec) {
                [void]$splatKeys.Add([string]$spec.Name)
            }
            if ($null -ne $entry.FixedParameters) {
                foreach ($key in $entry.FixedParameters.Keys) {
                    [void]$splatKeys.Add([string]$key)
                }
            }

            foreach ($key in $splatKeys) {
                $declaredParams | Should -Contain $key -Because "menu entry '$($entry.Label)' splats '$key' but $v does not declare it"
            }
        }
    }
}
