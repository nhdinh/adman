#Requires -Modules Pester
<#
.SYNOPSIS
    USER-03 contract tests for Disable-AdmanUser and Enable-AdmanUser.

.DESCRIPTION
    Pins the contract for the disable/enable verbs:
      * Disable-AdmanUser routes through Invoke-AdmanMutation with -Verb 'Disable-ADAccount'
        and -Targets @($Identity).
      * Enable-AdmanUser routes through Invoke-AdmanMutation with -Verb 'Enable-ADAccount'
        and -Targets @($Identity).
      * Both verbs forward -Force to the gate.
      * Both verbs throw the WR-01 init message when $script:Config.ManagedOUs is absent.
      * Both verbs are exported in adman.psd1 FunctionsToExport (HIGH #2 review fix).

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

Describe 'Disable-AdmanUser / Enable-AdmanUser: gate routing (USER-03)' -Tag 'Unit' {

    It 'Disable-AdmanUser calls Invoke-AdmanMutation with -Verb Disable-ADAccount and -Targets @($Identity)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Disable-AdmanUser -Identity 'jdoe'
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Disable-ADAccount' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe'
        }
    }

    It 'Enable-AdmanUser calls Invoke-AdmanMutation with -Verb Enable-ADAccount and -Targets @($Identity)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Enable-AdmanUser -Identity 'jdoe'
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Enable-ADAccount' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe'
        }
    }

    It 'Disable-AdmanUser forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Disable-AdmanUser -Identity 'jdoe' -Force
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Disable-ADAccount' -and $Force -eq $true
        }
    }

    It 'Enable-AdmanUser forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Enable-AdmanUser -Identity 'jdoe' -Force
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Enable-ADAccount' -and $Force -eq $true
        }
    }

    It 'Disable-AdmanUser throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Disable-AdmanUser -Identity 'jdoe' } |
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

    It 'Enable-AdmanUser throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Enable-AdmanUser -Identity 'jdoe' } |
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

Describe 'Disable-AdmanUser / Enable-AdmanUser: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'Disable-AdmanUser is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Disable-AdmanUser'
        (Get-Command -Module adman -Name 'Disable-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'Enable-AdmanUser is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Enable-AdmanUser'
        (Get-Command -Module adman -Name 'Enable-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
