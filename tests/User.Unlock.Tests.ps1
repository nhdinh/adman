#Requires -Modules Pester
<#
.SYNOPSIS
    USER-05 contract tests for Unlock-AdmanUser (PDCe-pinned unlock).

.DESCRIPTION
    Pins the contract for the unlock verb:
      * Resolves the PDC emulator via (Get-ADDomain).PDCEmulator and passes it as
        $Parameters['Server'] to the gate (T-02-05 mitigation).
      * Reads LockedOut first on the PDCe via Get-ADUser -Server $pdc -Properties
        LockedOut; returns a clear "Account is not locked out." message and skips
        the gate call when not locked.
      * Calls Invoke-AdmanMutation with -Verb 'Unlock-ADAccount' when the account
        IS locked.
      * WR-01 init check throws when $script:Config.ManagedOUs is absent.
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains 'Unlock-AdmanUser'
        explicitly; Get-Command -Module adman -Name 'Unlock-AdmanUser' resolves
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

Describe 'Unlock-AdmanUser: PDCe pinning + LockedOut pre-read (USER-05, T-02-05)' -Tag 'Unit' {

    It 'resolves the PDC emulator via (Get-ADDomain).PDCEmulator and passes it as $Parameters[Server] to the gate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Get-ADDomain {
            return [pscustomobject]@{
                PDCEmulator = 'pdc.mock.local'
                DNSRoot     = 'mock.local'
            }
        }
        Mock -ModuleName adman Get-ADUser {
            return [pscustomobject]@{
                SamAccountName = 'jdoe'
                LockedOut      = $true
            }
        }

        Unlock-AdmanUser -Identity 'jdoe'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Unlock-ADAccount' -and
            $Parameters['Server'] -eq 'pdc.mock.local'
        }
    }

    It 'reads LockedOut first on the PDCe and returns a clear "Account is not locked out." message when not locked (no gate call)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Get-ADDomain {
            return [pscustomobject]@{
                PDCEmulator = 'pdc.mock.local'
                DNSRoot     = 'mock.local'
            }
        }
        Mock -ModuleName adman Get-ADUser {
            return [pscustomobject]@{
                SamAccountName = 'jdoe'
                LockedOut      = $false
            }
        }

        $output = Unlock-AdmanUser -Identity 'jdoe'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 0
        $output | Should -Match 'not locked out'
    }

    It 'calls Invoke-AdmanMutation with -Verb Unlock-ADAccount when the account IS locked' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Get-ADDomain {
            return [pscustomobject]@{
                PDCEmulator = 'pdc.mock.local'
                DNSRoot     = 'mock.local'
            }
        }
        Mock -ModuleName adman Get-ADUser {
            return [pscustomobject]@{
                SamAccountName = 'jdoe'
                LockedOut      = $true
            }
        }

        Unlock-AdmanUser -Identity 'jdoe'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Unlock-ADAccount' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe'
        }
    }

    It 'reads LockedOut on the PDCe (Get-ADUser -Server $pdc -Properties LockedOut)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Get-ADDomain {
            return [pscustomobject]@{
                PDCEmulator = 'pdc.mock.local'
                DNSRoot     = 'mock.local'
            }
        }
        $script:GetADUserCalls = @()
        Mock -ModuleName adman Get-ADUser {
            param($Identity, $Server, $Properties)
            $script:GetADUserCalls += [pscustomobject]@{
                Identity   = $Identity
                Server     = $Server
                Properties = $Properties
            }
            return [pscustomobject]@{
                SamAccountName = 'jdoe'
                LockedOut      = $true
            }
        }

        Unlock-AdmanUser -Identity 'jdoe'

        $script:GetADUserCalls.Count | Should -BeGreaterOrEqual 1
        $script:GetADUserCalls[0].Server | Should -Be 'pdc.mock.local'
        $script:GetADUserCalls[0].Properties | Should -Contain 'LockedOut'
    }

    It 'throws the WR-01 init message when $script:Config.ManagedOUs is absent' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Unlock-AdmanUser -Identity 'jdoe' } |
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

Describe 'Unlock-AdmanUser: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Unlock-AdmanUser'
        (Get-Command -Module adman -Name 'Unlock-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
