#Requires -Modules Pester
<#
.SYNOPSIS
    LUSR-02 contract tests for Add/Remove-AdmanLocalGroupMember.

.DESCRIPTION
    Pins the contract for the two local group membership Public verbs:
      * Add-AdmanLocalGroupMember routes through Invoke-AdmanLocalMutation with
        -Verb 'Add-LocalGroupMember' and $Parameters containing Group and ComputerName.
      * Remove-AdmanLocalGroupMember routes through Invoke-AdmanLocalMutation with
        -Verb 'Remove-LocalGroupMember' and $Parameters containing Group and ComputerName.
      * Both verbs validate -ComputerName to localhost (throw "Remote targets arrive
        in Phase 3" otherwise).
      * Both verbs throw the WR-01 init message when uninitialized.
      * Both verbs forward -Force to the gate.
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains the two verbs
        explicitly; Get-Command -Module adman resolves them after Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live
    domain, no real local accounts touched. Pester 6 syntax.
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

    # Import the AD mocks FIRST so LocalAccounts cmdlets resolve to the mock when the module loads.
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

Describe 'Add-AdmanLocalGroupMember: gate routing (LUSR-02, D-02)' -Tag 'Unit' {

    It 'Test 1: calls Invoke-AdmanLocalMutation with -Verb Add-LocalGroupMember and $Parameters containing Group and ComputerName' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Add-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators'

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Add-LocalGroupMember' -and
            $Parameters['Group'] -eq 'Administrators' -and
            $Parameters.ContainsKey('ComputerName')
        }
    }

    It 'Test 3: validates -ComputerName to localhost (throws "Remote targets arrive in Phase 3" on otherhost)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        { Add-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' -ComputerName 'otherhost' } |
            Should -Throw '*Remote targets arrive in Phase 3*'
    }

    It 'Test 4: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Add-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' } |
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

    It 'Test 5: forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Add-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' -Force

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Add-LocalGroupMember' -and $Force -eq $true
        }
    }
}

Describe 'Remove-AdmanLocalGroupMember: gate routing (LUSR-02, D-02)' -Tag 'Unit' {

    It 'Test 2: calls Invoke-AdmanLocalMutation with -Verb Remove-LocalGroupMember and $Parameters containing Group and ComputerName' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Remove-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators'

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Remove-LocalGroupMember' -and
            $Parameters['Group'] -eq 'Administrators' -and
            $Parameters.ContainsKey('ComputerName')
        }
    }

    It 'Test 3: validates -ComputerName to localhost (throws "Remote targets arrive in Phase 3" on otherhost)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        { Remove-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' -ComputerName 'otherhost' } |
            Should -Throw '*Remote targets arrive in Phase 3*'
    }

    It 'Test 4: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Remove-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' } |
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

    It 'Test 5: forwards -Force to the gate' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Remove-AdmanLocalGroupMember -Name 'luser' -Group 'Administrators' -Force

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Remove-LocalGroupMember' -and $Force -eq $true
        }
    }
}

Describe 'Local group verbs: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'Test 6: adman.psd1 FunctionsToExport contains the two local group verbs explicitly' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Add-AdmanLocalGroupMember'
        $content | Should -Match 'Remove-AdmanLocalGroupMember'
        (Get-Command -Module adman -Name 'Add-AdmanLocalGroupMember' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        (Get-Command -Module adman -Name 'Remove-AdmanLocalGroupMember' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
