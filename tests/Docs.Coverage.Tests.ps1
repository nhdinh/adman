#Requires -Modules Pester
<#
.SYNOPSIS
    Docs coverage contract test for README.md, docs/USAGE.md, and docs/RECOVERY-RUNBOOK.md.

.DESCRIPTION
    Verifies that operator-facing documentation stays in sync with the module manifest
    (FunctionsToExport) and the private menu definition (Get-AdmanMenuDefinition).

    Runs entirely offline; the real PSFramework install is NOT required.
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
    GUID              = 'b0000000-0000-0000-0000-0000000000dc'
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

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:UsagePath = Join-Path $script:RepoRoot 'docs/USAGE.md'
    $script:RecoveryPath = Join-Path $script:RepoRoot 'docs/RECOVERY-RUNBOOK.md'
    $script:ReadmePath = Join-Path $script:RepoRoot 'README.md'

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Source of truth: private menu definition accessed through module scope.
    $script:MenuDefinition = & (Get-Module adman) { Get-AdmanMenuDefinition }
    $script:MenuEntries = @($script:MenuDefinition | Where-Object { $_.Label -ne '---' })

    # Source of truth: exported function names from the manifest.
    $script:ExportedFunctions = @((Get-Command -Module adman).Name | Sort-Object)
}

AfterAll {
    Remove-Module -Name adman -Force -ErrorAction SilentlyContinue
}

Describe 'README.md coverage contract' -Tag 'Unit' {

    It 'README.md exists' {
        Test-Path -LiteralPath $script:ReadmePath | Should -BeTrue
    }

    It 'README.md contains the required section headings' {
        $raw = Get-Content -LiteralPath $script:ReadmePath -Raw
        foreach ($heading in @('## Installation', '## First run', '## Safe usage', '## What works today', '## Code signing', '## Commit guard')) {
            $raw | Should -Match ([regex]::Escape($heading))
        }
    }

    It 'README.md contains the exact commit-guard installation command' {
        $raw = Get-Content -LiteralPath $script:ReadmePath -Raw
        $raw | Should -Match ([regex]::Escape('git config core.hooksPath .githooks'))
    }

    It 'README.md references Trusted Publishers GPO deployment' {
        $raw = Get-Content -LiteralPath $script:ReadmePath -Raw
        $raw | Should -Match 'Trusted Publishers'
        $raw | Should -Match 'Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies'
    }

    It 'README.md explains DPAPI-bound credential portability limitation' {
        $raw = Get-Content -LiteralPath $script:ReadmePath -Raw
        $raw | Should -Match ([regex]::Escape('.store/config.json'))
        $raw | Should -Match ([regex]::Escape('.store/adman.credential.xml'))
        $raw | Should -Match 'DPAPI'
    }

    It 'README.md no longer describes Start-Adman as a stub' {
        $raw = Get-Content -LiteralPath $script:ReadmePath -Raw
        $raw | Should -Not -Match 'currently a stub'
        $raw | Should -Not -Match 'Phase 0 only'
    }
}

Describe 'docs/RECOVERY-RUNBOOK.md coverage contract' -Tag 'Unit' {

    It 'docs/RECOVERY-RUNBOOK.md exists' {
        Test-Path -LiteralPath $script:RecoveryPath | Should -BeTrue
    }

    It 'docs/RECOVERY-RUNBOOK.md contains the required section headings' {
        $raw = Get-Content -LiteralPath $script:RecoveryPath -Raw
        foreach ($heading in @('## Restore from quarantine', '## Restore from AD Recycle Bin', '## Authoritative restore warning', '## Certificate renewal and trust-anchor rotation')) {
            $raw | Should -Match ([regex]::Escape($heading))
        }
    }
}

Describe 'docs/USAGE.md menu coverage contract' -Tag 'Unit' {

    It 'docs/USAGE.md exists' {
        Test-Path -LiteralPath $script:UsagePath | Should -BeTrue
    }

    It 'docs/USAGE.md contains every non-separator menu Label' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        foreach ($entry in $script:MenuEntries) {
            $raw | Should -Match ([regex]::Escape($entry.Label)) -Because "menu label '$($entry.Label)' must be documented"
        }
    }

    It 'docs/USAGE.md documents PromptSpec Name and Prompt for each non-separator entry' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        foreach ($entry in $script:MenuEntries) {
            foreach ($spec in $entry.PromptSpec) {
                $raw | Should -Match ([regex]::Escape($spec.Name)) -Because "PromptSpec Name '$($spec.Name)' for '$($entry.Label)' must be documented"
                $raw | Should -Match ([regex]::Escape($spec.Prompt)) -Because "PromptSpec Prompt '$($spec.Prompt)' for '$($entry.Label)' must be documented"
            }
        }
    }

    It 'docs/USAGE.md documents Required flag for each PromptSpec field' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        foreach ($entry in $script:MenuEntries) {
            foreach ($spec in $entry.PromptSpec) {
                if ($spec.Required) {
                    $raw | Should -Match 'required' -Because "required PromptSpec field '$($spec.Name)' for '$($entry.Label)' must be marked"
                }
            }
        }
    }
}

Describe 'docs/USAGE.md exported-function coverage contract' -Tag 'Unit' {

    It 'docs/USAGE.md contains an Exported functions section' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        $raw | Should -Match '#{1,2} Exported functions'
    }

    It 'docs/USAGE.md mentions every exported function under the Exported functions section' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        $sectionMatch = [regex]::Match($raw, '#{1,2} Exported functions.*?(?=\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $sectionMatch.Success | Should -BeTrue
        $section = $sectionMatch.Value
        foreach ($func in $script:ExportedFunctions) {
            $section | Should -Match ([regex]::Escape($func)) -Because "exported function '$func' must appear in the Exported functions section"
        }
    }

    It 'every exported function has a fenced PowerShell example in its section' {
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        $sectionMatch = [regex]::Match($raw, '#{1,2} Exported functions.*?(?=\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $sectionMatch.Success | Should -BeTrue
        $section = $sectionMatch.Value

        foreach ($func in $script:ExportedFunctions) {
            # Find the function's heading inside the Exported functions section.
            $funcPattern = '(?m)^###?\s+`' + [regex]::Escape($func) + '`?\s*$'
            $funcMatch = [regex]::Match($section, $funcPattern)
            $funcMatch.Success | Should -BeTrue -Because "exported function '$func' must have a heading in the Exported functions section"

            $start = $funcMatch.Index
            # Slice from the function heading until the next '## ' or '### ' function heading.
            $nextMatch = [regex]::Match($section.Substring($start + $funcMatch.Length), '(?m)^###?\s+', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($nextMatch.Success) {
                $funcSection = $section.Substring($start, $funcMatch.Length + $nextMatch.Index)
            } else {
                $funcSection = $section.Substring($start)
            }

            $funcSection | Should -Match '```powershell' -Because "function '$func' must have a PowerShell example"
            $funcSection | Should -Match '```' -Because "function '$func' example must be closed"
        }
    }

    It 'every exported function section documents its non-common parameters' {
        $common = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','WhatIf','Confirm')
        $raw = Get-Content -LiteralPath $script:UsagePath -Raw
        $sectionMatch = [regex]::Match($raw, '#{1,2} Exported functions.*?(?=\n## |\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $sectionMatch.Success | Should -BeTrue
        $section = $sectionMatch.Value

        foreach ($func in $script:ExportedFunctions) {
            $funcPattern = '(?m)^###?\s+`' + [regex]::Escape($func) + '`?\s*$'
            $funcMatch = [regex]::Match($section, $funcPattern)
            $funcMatch.Success | Should -BeTrue -Because "exported function '$func' must have a heading"

            $start = $funcMatch.Index
            $nextMatch = [regex]::Match($section.Substring($start + $funcMatch.Length), '(?m)^###?\s+', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($nextMatch.Success) {
                $funcSection = $section.Substring($start, $funcMatch.Length + $nextMatch.Index)
            } else {
                $funcSection = $section.Substring($start)
            }

            $cmd = Get-Command $func -ErrorAction Stop
            $params = $cmd.Parameters.Keys | Where-Object { $_ -notin $common }

            foreach ($param in $params) {
                $funcSection | Should -Match ([regex]::Escape("-$param")) -Because "parameter '$param' of '$func' must be documented in its section"
            }
        }
    }
}
