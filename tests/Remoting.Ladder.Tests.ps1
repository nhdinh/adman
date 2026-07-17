#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-01 ladder-order tests for Connect-AdmanTarget.

.DESCRIPTION
    Proves the fixed transport ladder with mocks for the two timeout wrappers so no network
    traffic is required: WinRM first, then CIM/WSMan, then CIM/DCOM, then Skipped.
#>

Describe 'Connect-AdmanTarget ladder order (RMT-01, D-05)' -Tag 'Unit' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'

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

        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
                transport  = [pscustomobject]@{
                    timeouts = [pscustomobject]@{
                        perHostProbeCap         = 10
                        totalInventoryRemoteCap = 120
                    }
                }
            }
            $script:TransportCache = @{}
        }
    }

    BeforeEach {
        & (Get-Module adman) { $script:TransportCache = @{} }
    }

    It 'returns WinRM when Test-AdmanWsmanTimeout returns a non-null result and does not call CIM steps' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return [pscustomobject]@{ } }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $true }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC01'

        $result | Should -Be 'WinRM'
        Should -Invoke Test-AdmanWsmanTimeout -ModuleName adman -Times 1
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 0
    }

    It 'returns CimWsman when WinRM fails but WSMAN CIM probe succeeds, even if DCOM would also succeed' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman {
            if ($Protocol -eq 'Wsman') { return $true }
            return $true   # DCOM would also succeed, but ladder must stop at Wsman
        }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC02'

        $result | Should -Be 'CimWsman'
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 1
    }

    It 'returns CimDcom when WinRM and WSMAN fail but DCOM probe succeeds' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman {
            if ($Protocol -eq 'Wsman') { return $false }
            return $true
        }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC03'

        $result | Should -Be 'CimDcom'
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 2
    }

    It "returns 'Skipped' when all ladder steps fail" {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $false }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC04'

        $result | Should -Be 'Skipped'
        Should -Invoke Test-AdmanWsmanTimeout -ModuleName adman -Times 1
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 2
    }
}
