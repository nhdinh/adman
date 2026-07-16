#Requires -Modules Pester
<#
.SYNOPSIS
    GRP-01 contract tests for Add-AdmanGroupMember.

.DESCRIPTION
    Pins the contract for the Add group membership Public verb:
      * Test 1: calls Invoke-AdmanMutation with -Verb 'Add-ADGroupMember',
        -Targets @($Identity), and $Parameters containing GroupIdentity.
      * Test 6: throws the WR-01 init message when uninitialized.
      * Test 7: forwards -Force to the gate.
      * Test 8 (HIGH #2 review fix): adman.psd1 FunctionsToExport contains
        'Add-AdmanGroupMember' explicitly; Get-Command -Module adman resolves
        it after Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no
    live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'

    # PSFramework stub so the module import works in a clean test host.
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

    # Import the AD mocks FIRST so AD cmdlets resolve to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }
}

Describe 'Add-AdmanGroupMember: gate routing (GRP-01, D-04)' -Tag 'Unit' {

    It 'Test 1: calls Invoke-AdmanMutation with -Verb Add-ADGroupMember, -Targets @($Identity), and $Parameters containing GroupIdentity' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Add-ADGroupMember' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe' -and
            $Parameters['GroupIdentity'] -eq 'Helpdesk'
        }
    }

    It 'Test 6: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk' } |
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

    It 'Test 7: forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Helpdesk' -Force

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Add-ADGroupMember' -and $Force -eq $true
        }
    }
}

Describe 'Add-AdmanGroupMember: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'Test 8: adman.psd1 FunctionsToExport contains Add-AdmanGroupMember explicitly; Get-Command resolves it' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Add-AdmanGroupMember'
        (Get-Command -Module adman -Name 'Add-AdmanGroupMember' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
