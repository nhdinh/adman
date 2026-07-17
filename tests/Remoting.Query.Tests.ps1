#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-03 / RMT-04 unit tests for Invoke-AdmanRemoteCimQuery and Invoke-AdmanRemoteQuery.

.DESCRIPTION
    Pins the local-on-target CIM query layer:
      * Invoke-AdmanRemoteCimQuery allow-lists only Win32_OperatingSystem and Win32_ComputerSystem.
      * Invoke-AdmanRemoteQuery returns RemoteOS, Uptime, LoggedOnUser for reachable hosts.
      * Skipped transport short-circuits to empty fields without touching CIM.
      * CIM errors are caught, translated, and returned as Skipped.
      * Exactly one CIM session is created per host and the timeout budget shrinks.

    Get-CimInstance's -CimSession parameter requires a real Microsoft.Management.Infrastructure.
    CimSession object, so the New-CimSession mock returns a short-lived local DCOM session. The
    session is removed in AfterAll; no remote targets are contacted.

    Runs offline; no RSAT, no live domain. Pester 6 syntax.
#>

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
    GUID              = 'b0000000-0000-0000-0000-0000000000e8'
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

    # Build a real Microsoft.Management.Infrastructure.CimSession object without a live DCOM
    # connection so Get-CimInstance parameter binding accepts the mock return (WR-07).
    $script:LocalCimSession = [Microsoft.Management.Infrastructure.CimSession]::Create('localhost')

    # Create one real completed background job so the Start-Job mock can return an object that
    # Wait-Job/Receive-Job accept without running a live job per test (WR-02).
    $script:FakeJob = Start-Job { $null }
    $null = Wait-Job $script:FakeJob
}

AfterAll {
    if ($null -ne $script:LocalCimSession) {
        CimCmdlets\Remove-CimSession -CimSession $script:LocalCimSession -ErrorAction SilentlyContinue
    }
    if ($null -ne $script:FakeJob) {
        Remove-Job -Job $script:FakeJob -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-AdmanRemoteCimQuery local-only guard (RMT-04, D-07)' -Tag 'Unit' {

    BeforeEach {
        $script:CapturedTimeouts = [System.Collections.Generic.List[int]]::new()
        Mock New-CimSession -ModuleName adman { param($ComputerName, $SessionOption, $OperationTimeoutSec) $script:LocalCimSession }
        Mock Remove-CimSession -ModuleName adman { param($CimSession) }
    }

    It 'returns the mocked OS object for Win32_OperatingSystem' {
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) [pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0 (26200)'; CSDVersion = ''; LastBootUpTime = [datetime]'2026-07-10T00:00:00Z' } }

        $result = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_OperatingSystem' } -cn 'PC01' -tr 'WinRM'

        $result | Should -Not -BeNullOrEmpty
        $result.Caption | Should -Be 'Windows 11 Pro'
        Should -Invoke Remove-CimSession -ModuleName adman -Times 1
    }

    It 'returns the mocked computer system object for Win32_ComputerSystem' {
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) [pscustomobject]@{ UserName = 'MOCK\alice' } }

        $result = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_ComputerSystem' } -cn 'PC01' -tr 'WinRM'

        $result | Should -Not -BeNullOrEmpty
        $result.UserName | Should -Be 'MOCK\alice'
        Should -Invoke Remove-CimSession -ModuleName adman -Times 1
    }

    It 'throws the D-07 structural guard message for a disallowed class' {
        $msg = 'Second-hop operation not supported in adman remote queries.'
        { & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_Share' } -cn 'PC01' -tr 'WinRM' } | Should -Throw -ExpectedMessage "*$msg*"
    }

    It 'builds the session with the protocol that matches the supplied transport' {
        $captured = @{ Protocol = $null }
        Mock New-CimSessionOption -ModuleName adman { param($Protocol) $captured.Protocol = $Protocol; New-CimSessionOption -Protocol $Protocol }
        Mock New-CimSession -ModuleName adman { param($ComputerName, $SessionOption, $OperationTimeoutSec) $script:LocalCimSession }
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) [pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0'; CSDVersion = '' } }

        $null = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_OperatingSystem' } -cn 'PC01' -tr 'WinRM'
        $captured.Protocol | Should -Be 'Wsman'

        $captured.Protocol = $null
        $null = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_OperatingSystem' } -cn 'PC01' -tr 'CimDcom'
        $captured.Protocol | Should -Be 'Dcom'
    }

    It 'passes TimeoutSeconds to both New-CimSession and Get-CimInstance OperationTimeoutSec' {
        $captured = @{ NewSession = $null; Query = $null }
        Mock New-CimSession -ModuleName adman { param($ComputerName, $SessionOption, $OperationTimeoutSec) $captured.NewSession = $OperationTimeoutSec; $script:LocalCimSession }
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) $captured.Query = $OperationTimeoutSec; [pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0'; CSDVersion = '' } }

        $null = & (Get-Module adman) { param($cn, $tr, $to) Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_OperatingSystem' -TimeoutSeconds $to } -cn 'PC01' -tr 'WinRM' -to 17

        $captured.NewSession | Should -Be 17
        $captured.Query | Should -Be 17
    }
}

Describe 'Invoke-AdmanRemoteQuery enrichment (RMT-03, D-01)' -Tag 'Unit' {

    BeforeAll {
        $script:FakeJobOutput = @{
            Caption        = 'Windows 11 Pro'
            Version        = '10.0 (26200)'
            CSDVersion     = ''
            LastBootUpTime = [datetime]'2026-07-10T00:00:00Z'
            UserName       = 'MOCK\alice'
        }
    }

    BeforeEach {
        $script:CapturedTimeouts = [System.Collections.Generic.List[int]]::new()
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { $true }
        Mock Start-Job -ModuleName adman {
            param($ScriptBlock, $InitializationScript, $ArgumentList)
            if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 2) {
                $script:CapturedTimeouts.Add([int]$ArgumentList[2])
            }
            $script:FakeJob
        }
        Mock Wait-Job -ModuleName adman { $script:FakeJob }
        Mock Receive-Job -ModuleName adman { $script:FakeJobOutput }
        Mock Stop-Job -ModuleName adman { }
        Mock Remove-Job -ModuleName adman { }
    }

    It 'returns empty fields for Transport Skipped without touching CIM' {
        $result = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'Skipped'

        $result.Transport | Should -Be 'Skipped'
        $result.RemoteOS | Should -BeNullOrEmpty
        $result.Uptime | Should -BeNullOrEmpty
        $result.LoggedOnUser | Should -BeNullOrEmpty
        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 0
        Should -Invoke Start-Job -ModuleName adman -Times 0
    }

    It 'returns RemoteOS, TimeSpan Uptime, and LoggedOnUser for a reachable host' {
        $result = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'WinRM'

        $result.Transport | Should -Be 'WinRM'
        $result.RemoteOS | Should -Be 'Windows 11 Pro 10.0 (26200)'
        $result.Uptime | Should -BeOfType [timespan]
        $result.LoggedOnUser | Should -Be 'MOCK\alice'
    }

    It 'starts exactly one CIM job per host' {
        $null = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'WinRM'

        Should -Invoke Start-Job -ModuleName adman -Times 1
        Should -Invoke Wait-Job -ModuleName adman -Times 1
        Should -Invoke Receive-Job -ModuleName adman -Times 1
    }

    It 'probes session setup with Test-AdmanCimSessionTimeout before starting the CIM job' {
        $null = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'WinRM'

        Should -Invoke Test-AdmanCimSessionTimeout -ModuleName adman -Times 1
    }

    It 'catches a CIM error and returns empty fields with Transport Skipped' {
        Mock Receive-Job -ModuleName adman { [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('RPC server unavailable'), 'MockError', 'OperationStopped', $null) }
        Mock Write-Verbose -ModuleName adman { }

        $result = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'WinRM'

        $result.Transport | Should -Be 'Skipped'
        $result.RemoteOS | Should -BeNullOrEmpty
        $result.Uptime | Should -BeNullOrEmpty
        $result.LoggedOnUser | Should -BeNullOrEmpty
    }

    It 'forwards a shrinking TimeoutSeconds to the CIM job' {
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { Start-Sleep -Milliseconds 50; $true }
        $script:CapturedTimeouts.Clear()

        $null = & (Get-Module adman) { param($cn, $tr, $to) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr -TimeoutSeconds $to } -cn 'PC01' -tr 'WinRM' -to 10

        $script:CapturedTimeouts.Count | Should -Be 1
        $script:CapturedTimeouts[0] | Should -BeLessOrEqual 10
    }

    It 'never calls Invoke-AdmanRemoteCimQuery; the two helpers stay separate' {
        Mock Invoke-AdmanRemoteCimQuery -ModuleName adman { }

        $null = & (Get-Module adman) { param($cn, $tr) Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr } -cn 'PC01' -tr 'WinRM'

        Should -Invoke Invoke-AdmanRemoteCimQuery -ModuleName adman -Times 0
    }
}
