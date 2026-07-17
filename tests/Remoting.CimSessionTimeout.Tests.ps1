#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-02 timeout-wrapper tests for Test-AdmanCimSessionTimeout.

.DESCRIPTION
    Proves New-CimSession setup is wrapped in a hard-timeout Start-Job so a silently-dropped host
    cannot hang the menu during CIM/WSMan or CIM/DCOM legs. Uses a lightweight C# synthetic Job
    so no real background jobs are created.
#>

Describe 'Test-AdmanCimSessionTimeout hard-timeout wrapper (RMT-02, Pitfall 1)' -Tag 'Unit' {

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e5'
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

        if (-not ('AdmanTestJob' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Management.Automation;

public class AdmanTestJob : Job {
    public object TestOutput { get; private set; }
    public override string StatusMessage { get { return ""; } }
    public override bool HasMoreData { get { return false; } }
    public override string Location { get { return "localhost"; } }

    public AdmanTestJob(string state, object output) : base("adman-probe", "adman-probe") {
        TestOutput = output;
        SetJobState((JobState)Enum.Parse(typeof(JobState), state));
    }

    public override void StopJob() { }
}
'@
        }
    }

    BeforeEach {
        Mock Wait-Job -ModuleName adman {
            param([Parameter(ValueFromPipeline = $true)][System.Management.Automation.Job[]]$Job, [int]$Timeout)
            if ($Job -and $Job[0].State -eq [System.Management.Automation.JobState]::Completed) { return $Job[0] }
            return $null
        }
        Mock Receive-Job -ModuleName adman {
            param([System.Management.Automation.Job[]]$Job)
            if ($Job -and $Job[0] -is [AdmanTestJob]) { return $Job[0].TestOutput }
            return $null
        }
        Mock Remove-Job -ModuleName adman { param([System.Management.Automation.Job[]]$Job) }
        Mock Stop-Job -ModuleName adman { param([System.Management.Automation.Job[]]$Job) }
    }

    It 'returns $true when the probe job completes successfully' {
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Completed', $null)
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Wsman' -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -Be $true
        Should -Invoke Remove-Job -ModuleName adman -Times 1
        Should -Invoke Stop-Job -ModuleName adman -Times 0
    }

    It 'returns $false when the job output is an ErrorRecord' {
        $err = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('CIM failure'),
            'NewCimSessionError',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null
        )
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Completed', $err)
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Wsman' -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -Be $false
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'returns $false and cleans up the job when New-CimSession does not complete within the timeout' {
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Running', $null)
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Dcom' -TimeoutSeconds $to } -cn 'DEADHOST' -to 10

        $result | Should -Be $false
        Should -Invoke Stop-Job -ModuleName adman -Times 1
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'returns $false and cleans up the job when the job state is Failed' {
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Failed', $null)
        }

        $result = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Wsman' -TimeoutSeconds $to } -cn 'PC01' -to 10

        $result | Should -Be $false
        Should -Invoke Stop-Job -ModuleName adman -Times 1
        Should -Invoke Remove-Job -ModuleName adman -Times 1
    }

    It 'supports both Wsman and Dcom protocol parameter values' {
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Completed', $null)
        }

        $wsman = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Wsman' -TimeoutSeconds $to } -cn 'PC01' -to 10
        $dcom  = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Dcom' -TimeoutSeconds $to } -cn 'PC01' -to 10

        $wsman | Should -Be $true
        $dcom | Should -Be $true
    }

    It 'leaves no adman probe jobs behind after timeout and failure cases' {
        Mock Start-Job -ModuleName adman {
            return [AdmanTestJob]::new('Running', $null)
        }

        $null = & (Get-Module adman) { param($cn, $to) Test-AdmanCimSessionTimeout -ComputerName $cn -Protocol 'Dcom' -TimeoutSeconds $to } -cn 'DEADHOST' -to 10

        @((Get-Job)).Count | Should -Be 0
    }
}
