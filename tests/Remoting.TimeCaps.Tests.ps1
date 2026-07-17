#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-02 per-host cap tests for Connect-AdmanTarget.

.DESCRIPTION
    Proves the per-host probe cap stops classification and marks the host Skipped when the ladder
    has consumed more time than allowed.
#>

Describe 'Connect-AdmanTarget per-host time cap (RMT-02, D-02)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e6'
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

    It 'returns Skipped when Test-AdmanWsmanTimeout exceeds perHostProbeCap and does not attempt CIM steps' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman {
            Start-Sleep -Milliseconds 1100
            return $null
        }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $true }

        & (Get-Module adman) { $script:Config.transport.timeouts.perHostProbeCap = 1 }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'SLOWHOST'

        $result | Should -Be 'Skipped'
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 0
    }

    It 'still classifies normally when the ladder completes inside the cap' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman {
            if ($Protocol -eq 'Wsman') { return $true }
            return $false
        }

        & (Get-Module adman) { $script:Config.transport.timeouts.perHostProbeCap = 10 }

        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'FASTHOST'

        $result | Should -Be 'CimWsman'
    }
}
