#Requires -Modules Pester
<#
.SYNOPSIS
    USER-06 contract tests for Move-AdmanUser (managed-OU destination validation).

.DESCRIPTION
    Pins the contract for the move verb:
      * Validates -TargetPath under managed roots BEFORE calling the gate; throws
        "TargetPath '<x>' is outside managed OU scope." when out of scope
        (T-02-08 mitigation, component-boundary anchored via
        ConvertTo-AdmanNormalizedDn).
      * Calls Invoke-AdmanMutation with -Verb 'Move-ADObject' and $Parameters
        containing TargetPath when in scope.
      * WR-01 init check throws when $script:Config.ManagedOUs is absent.
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains 'Move-AdmanUser'
        explicitly; Get-Command -Module adman -Name 'Move-AdmanUser' resolves
        after Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live
    domain. Pester 6 syntax.
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

    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }
}

Describe 'Move-AdmanUser: managed-OU destination validation (USER-06, T-02-08)' -Tag 'Unit' {

    It 'validates -TargetPath under managed roots BEFORE calling the gate; throws when out of scope' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        { Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=NotManaged,DC=mock,DC=local' } |
            Should -Throw "*outside managed OU scope*"

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 0
    }

    It 'calls Invoke-AdmanMutation with -Verb Move-ADObject and $Parameters containing TargetPath when in scope' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Sub,OU=Managed,DC=mock,DC=local'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Move-ADObject' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe' -and
            $Parameters['TargetPath'] -eq 'OU=Sub,OU=Managed,DC=mock,DC=local'
        }
    }

    It 'accepts a TargetPath that IS a managed root exactly' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        { Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Managed,DC=mock,DC=local' } |
            Should -Not -Throw

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1
    }

    It 'rejects a TargetPath that is a sibling of a managed root (component-boundary anchored)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        # 'OU=ManagedX' would match a naive prefix check against 'OU=Managed' but is
        # NOT under the managed root. The component-boundary anchor ( EndsWith(','+root)
        # or -eq root ) must refuse it.
        { Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=ManagedX,DC=mock,DC=local' } |
            Should -Throw "*outside managed OU scope*"

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 0
    }

    It 'throws the WR-01 init message when $script:Config.ManagedOUs is absent' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Move-AdmanUser -Identity 'jdoe' -TargetPath 'OU=Managed,DC=mock,DC=local' } |
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

Describe 'Move-AdmanUser: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Move-AdmanUser'
        (Get-Command -Module adman -Name 'Move-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
