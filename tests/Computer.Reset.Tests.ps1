#Requires -Modules Pester
<#
.SYNOPSIS
    COMP-04 contract tests for Reset-AdmanComputerAccount.

.DESCRIPTION
    Pins the contract for the computer account reset verb:
      * Routes through Invoke-AdmanMutation with -Verb 'Set-ADAccountPassword'
        and $Parameters containing Reset=$true (AD-side "Reset Account", the
        ADUC equivalent).
      * Emits guidance text naming BOTH methods: the AD-side reset (this verb)
        AND the on-machine Test-ComputerSecureChannel -Repair runbook step.
        Guidance is emitted via Write-PSFMessage AND surfaced on the return
        object's Guidance property (NOT via Write-Host — the CLAUDE.md
        PSAvoidUsingWriteHost suppression covers only the TUI-rendering module).
      * The guidance text states that the AD-side reset breaks the secure
        channel until the machine rejoins or the channel is repaired on-machine.
      * Forwards -Force to the gate.
      * Throws the WR-01 init message when $script:Config.ManagedOUs is absent.
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains
        'Reset-AdmanComputerAccount' explicitly; Get-Command -Module adman
        -Name 'Reset-AdmanComputerAccount' resolves after Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live
    domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'

    # PSFramework stub.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000cc'
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

    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }
}

Describe 'Reset-AdmanComputerAccount: gate routing (COMP-04)' -Tag 'Unit' {

    It 'calls Invoke-AdmanMutation with -Verb Set-ADAccountPassword and $Parameters containing Reset=$true' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        Reset-AdmanComputerAccount -Identity 'PC-01'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADAccountPassword' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'PC-01' -and
            $Parameters['Reset'] -eq $true
        }
    }

    It 'forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        Reset-AdmanComputerAccount -Identity 'PC-01' -Force

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADAccountPassword' -and $Force -eq $true
        }
    }

    It 'throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Reset-AdmanComputerAccount -Identity 'PC-01' } |
                Should -Throw '*not initialized*Initialize-Adman*'
        } finally {
            & (Get-Module adman) {
                $script:Config = [pscustomobject]@{
                    ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                    DC         = 'dc.mock.local'
                }
            }
        }
    }
}

Describe 'Reset-AdmanComputerAccount: honest guidance (COMP-04)' -Tag 'Unit' {

    It 'emits guidance via Write-PSFMessage naming Test-ComputerSecureChannel -Repair' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        Reset-AdmanComputerAccount -Identity 'PC-01'

        Should -Invoke -ModuleName adman Write-PSFMessage -Times 1 -ParameterFilter {
            $Message -match 'Test-ComputerSecureChannel' -and
            $Message -match '-Repair'
        }
    }

    It 'guidance states the AD-side reset breaks the secure channel until rejoin or repair' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        Reset-AdmanComputerAccount -Identity 'PC-01'

        Should -Invoke -ModuleName adman Write-PSFMessage -Times 1 -ParameterFilter {
            ($Message -match 'rejoin' -or $Message -match 'repair') -and
            $Message -match 'secure channel'
        }
    }

    It 'surfaces the guidance on the return object Guidance property (pipeline-visible)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        $result = Reset-AdmanComputerAccount -Identity 'PC-01'

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Guidance'
        $result.Guidance | Should -Match 'Test-ComputerSecureChannel'
        $result.Guidance | Should -Match 'rejoin|repair'
    }

    It 'does NOT emit guidance under -WhatIf (no real mutation occurred)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Write-PSFMessage { }

        Reset-AdmanComputerAccount -Identity 'PC-01' -WhatIf

        Should -Invoke -ModuleName adman Write-PSFMessage -Times 0
    }
}

Describe 'Reset-AdmanComputerAccount: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Reset-AdmanComputerAccount'
        (Get-Command -Module adman -Name 'Reset-AdmanComputerAccount' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
