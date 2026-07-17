#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-02 first-class Skipped outcome tests for Connect-AdmanTarget.

.DESCRIPTION
    Probes that unreachable or timeout hosts return 'Skipped' and that no terminating error
    escapes the connector for a dead host.
#>

Describe 'Convert-AdmanRemoteError translation (T-03-02)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e7'
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
    }

    It 'maps RPC-unavailable HRESULT to DCOM firewall string' {
        $ex = [System.Exception]::new('The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)')
        $result = & (Get-Module adman) { param($e) Convert-AdmanRemoteError -Exception $e } -e $ex
        $result | Should -Be 'RPC server unavailable (DCOM firewall)'
    }

    It 'maps access-denied HRESULT to Access denied' {
        $ex = [System.Exception]::new('Access is denied. (Exception from HRESULT: 0x80070005)')
        $result = & (Get-Module adman) { param($e) Convert-AdmanRemoteError -Exception $e } -e $ex
        $result | Should -Be 'Access denied'
    }

    It 'maps ANONYMOUS LOGON / 0x8009030e to Double-hop blocked' {
        $ex = [System.Exception]::new('Logon failure: unknown user name or bad password (0x8009030e)')
        $result = & (Get-Module adman) { param($e) Convert-AdmanRemoteError -Exception $e } -e $ex
        $result | Should -Be 'Double-hop blocked'
    }

    It 'returns a safe string for $null input without throwing' {
        { & (Get-Module adman) { Convert-AdmanRemoteError -Exception $null } } | Should -Not -Throw
        $result = & (Get-Module adman) { Convert-AdmanRemoteError -Exception $null }
        $result | Should -Be 'Remote error: unknown'
    }
}

Describe 'Connect-AdmanTarget Skipped outcome (RMT-02, D-06)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e3'
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

    It "returns 'Skipped' for a dead host without throwing" {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $false }

        { & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'DEADHOST' } | Should -Not -Throw
        $result = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'DEADHOST'
        $result | Should -Be 'Skipped'
    }

    It 'caches Skipped so repeated calls do not re-probe' {
        Mock Test-AdmanWsmanTimeout -ModuleName adman { return $null }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { return $false }

        $first  = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'DEADHOST'
        $second = & (Get-Module adman) { param($cn) Connect-AdmanTarget -ComputerName $cn } -cn 'deadhost'

        $first | Should -Be 'Skipped'
        $second | Should -Be 'Skipped'
        Should -Invoke Test-AdmanWsmanTimeout -ModuleName adman -Times 1
    }
}
