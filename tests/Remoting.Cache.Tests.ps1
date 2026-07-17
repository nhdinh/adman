#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-01 cache tests for Connect-AdmanTarget.

.DESCRIPTION
    Proves the process-only transport-name cache is keyed by uppercase computer name and
    suppresses re-probing on subsequent calls.
#>

Describe 'Connect-AdmanTarget process-only cache (D-04)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e2'
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

    It 'caches the winning transport and returns it on a second call with different case' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return [pscustomobject]@{ } }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $true }

        $first  = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC01'
        $second = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'pc01'

        $first | Should -Be 'WinRM'
        $second | Should -Be 'WinRM'
        Should -Invoke Test-AdmanWsmanTimeout -ModuleName adman -Times 1
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 0
    }

    It 'stores only the transport name string, never live session objects' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return [pscustomobject]@{ } }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $true }

        $null = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'PC01'

        & (Get-Module adman) {
            $script:TransportCache['PC01'] | Should -Be 'WinRM'
            $script:TransportCache['PC01'] | Should -BeOfType [string]
        }
    }
}
