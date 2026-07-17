#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-02 timeout-wrapper tests for Test-AdmanWsmanTimeout.

.DESCRIPTION
    Proves Test-WSMan is wrapped in a hard-timeout Start-Job so dead hosts cannot hang the menu
    on Windows PowerShell 5.1. Mocks the job cmdlets to avoid real background jobs.
#>

Describe 'Test-AdmanWsmanTimeout hard-timeout wrapper (RMT-02, Pitfall 1)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e4'
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
        Mock Wait-Job -ModuleName adman {
            param([Parameter(ValueFromPipeline = $true)]$Job)
            if ($Job -and $Job.State -eq 'Completed') { return $Job }
            return $null
        }
        Mock Receive-Job -ModuleName adman {
            param($Job)
            if ($Job) { return $Job.Output }
            return $null
        }
        Mock Remove-Job -ModuleName adman { }
        Mock Stop-Job -ModuleName adman { }
    }

    It 'returns the wrapped Test-WSMan result when the job completes within the timeout' {
        $expected = [pscustomobject]@{ ProductVersion = 'OS: 0.0.0 SP: 0.0 Stack: 3.0' }
        Mock Start-Job -ModuleName adman {
            return [pscustomobject]@{
                State  = 'Completed'
                Output = $expected
            }
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanWsmanTimeout -ComputerName $cn -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -Be $expected
        Should -Invoke Remove-Job -ModuleName adman -Times 1
        Should -Invoke Stop-Job -ModuleName adman -Times 0
    }

    It 'returns $null when the job output is an ErrorRecord' {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('WS-Man failure'),
            'TestWSManError',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null
        )
        Mock Start-Job -ModuleName adman {
            return [pscustomobject]@{
                State  = 'Completed'
                Output = $err
            }
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanWsmanTimeout -ComputerName $cn -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -BeNullOrEmpty
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'returns $null and cleans up the job when Test-WSMan does not complete within the timeout' {
        Mock Start-Job -ModuleName adman {
            return [pscustomobject]@{
                State  = 'Running'
                Output = $null
            }
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanWsmanTimeout -ComputerName $cn -TimeoutSeconds $to } -cn 'DEADHOST' -to 10

        $result | Should -BeNullOrEmpty
        Should -Invoke Stop-Job -ModuleName adman -Times 1
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'returns $null and cleans up the job when the job state is Failed' {
        Mock Start-Job -ModuleName adman {
            return [pscustomobject]@{
                State  = 'Failed'
                Output = $null
            }
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanWsmanTimeout -ComputerName $cn -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -BeNullOrEmpty
        Should -Invoke Stop-Job -ModuleName adman -Times 1
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'leaves no adman probe jobs behind after timeout and failure cases' {
        Mock Start-Job -ModuleName adman {
            return [pscustomobject]@{
                State  = 'Running'
                Output = $null
            }
        }

        $null = & (Get-Module adman) { param($cn, $to) Test-AdmanWsmanTimeout -ComputerName $cn -TimeoutSeconds $to } -cn 'DEADHOST' -to 10

        @((Get-Job)).Count | Should -Be 0
    }
}
