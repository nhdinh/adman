#Requires -Modules Pester
<#
.SYNOPSIS
    RMT-04 double-hop guard tests for the Phase 3 remoting connector.

.DESCRIPTION
    Proves that adman Phase 3 remoting is local-on-target only and that CredSSP
    and remote-session constructs are absent from the connector:

      * Invoke-AdmanRemoteCimQuery rejects any class outside the allow-list with the D-07 message.
      * Private/Remoting/*.ps1 contains no references to CredSSP, Invoke-Command, or New-PSSession.
      * Private/Remoting/*.ps1 contains exactly two distinct -ClassName values.
      * Invoke-AdmanRemoteQuery never calls Invoke-Command or New-PSSession at runtime.

    The static parser for -ClassName values is intentionally simple. If class names are
    refactored into variables, update the parser accordingly; the real policy enforcement
    is the allow-list inside Invoke-AdmanRemoteCimQuery.

    Runs offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:RemotingPath = Join-Path $script:RepoRoot 'Private/Remoting'

    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000e9'
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

Describe 'Invoke-AdmanRemoteCimQuery structural guard (RMT-04, D-07)' -Tag 'Unit' {

    It 'throws the D-07 message for Win32_Share' {
        $msg = 'Second-hop operation not supported in adman remote queries.'
        {
            & (Get-Module adman) {
                param($cn, $tr)
                Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_Share'
            } -cn 'PC01' -tr 'WinRM'
        } | Should -Throw -ExpectedMessage "*$msg*"
    }

    It 'throws the D-07 message for Win32_Process' {
        $msg = 'Second-hop operation not supported in adman remote queries.'
        {
            & (Get-Module adman) {
                param($cn, $tr)
                Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_Process'
            } -cn 'PC01' -tr 'WinRM'
        } | Should -Throw -ExpectedMessage "*$msg*"
    }

    It 'does not throw for the allowed Win32_OperatingSystem class' {
        Mock New-CimSession -ModuleName adman { param($ComputerName, $SessionOption, $OperationTimeoutSec) $script:LocalCimSession }
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) [pscustomobject]@{ Caption = 'Windows 11 Pro'; Version = '10.0'; CSDVersion = '' } }
        Mock Remove-CimSession -ModuleName adman { param($CimSession) }

        {
            & (Get-Module adman) {
                param($cn, $tr)
                Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_OperatingSystem'
            } -cn 'PC01' -tr 'WinRM'
        } | Should -Not -Throw
    }

    It 'does not throw for the allowed Win32_ComputerSystem class' {
        Mock New-CimSession -ModuleName adman { param($ComputerName, $SessionOption, $OperationTimeoutSec) $script:LocalCimSession }
        Mock Get-CimInstance -ModuleName adman { param($CimSession, $ClassName, $OperationTimeoutSec) [pscustomobject]@{ UserName = 'MOCK\alice' } }
        Mock Remove-CimSession -ModuleName adman { param($CimSession) }

        {
            & (Get-Module adman) {
                param($cn, $tr)
                Invoke-AdmanRemoteCimQuery -ComputerName $cn -Transport $tr -ClassName 'Win32_ComputerSystem'
            } -cn 'PC01' -tr 'WinRM'
        } | Should -Not -Throw
    }
}

Describe 'Static proof: no CredSSP or remote-session constructs in connector (RMT-04)' -Tag 'Unit' {

    BeforeAll {
        $script:SourceFiles = Get-ChildItem -Path $script:RemotingPath -Filter '*.ps1'
        $script:SourceText = ($script:SourceFiles | Get-Content -Raw) -join "`n"
    }

    It 'has source files to inspect' {
        $script:SourceFiles.Count | Should -BeGreaterThan 0
    }

    It 'contains zero case-insensitive references to CredSSP' {
        $script:SourceText | Should -Not -Match 'CredSSP'
    }

    It 'contains zero case-insensitive references to Invoke-Command' {
        $script:SourceText | Should -Not -Match 'Invoke-Command'
    }

    It 'contains zero case-insensitive references to New-PSSession' {
        $script:SourceText | Should -Not -Match 'New-PSSession'
    }

    It 'contains exactly the two allowed -ClassName values' {
        $pattern = '-ClassName\s+[''"]([^''"]+)[''"]'
        $matches = [regex]::Matches($script:SourceText, $pattern)
        $classNames = $matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $classNames | Should -Be @('Win32_ComputerSystem', 'Win32_OperatingSystem')
    }
}

Describe 'Invoke-AdmanRemoteQuery runtime: no second-hop cmdlets invoked (RMT-04)' -Tag 'Unit' {

    BeforeEach {
        $script:FakeJobOutput = @{
            Caption        = 'Windows 11 Pro'
            Version        = '10.0 (26200)'
            CSDVersion     = ''
            LastBootUpTime = [datetime]'2026-07-10T00:00:00Z'
            UserName       = 'MOCK\alice'
        }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { $true }
        Mock Start-Job -ModuleName adman { $script:FakeJob }
        Mock Wait-Job -ModuleName adman { $script:FakeJob }
        Mock Receive-Job -ModuleName adman { $script:FakeJobOutput }
        Mock Stop-Job -ModuleName adman { }
        Mock Remove-Job -ModuleName adman { }
        Mock Invoke-Command -ModuleName adman { }
        Mock New-PSSession -ModuleName adman { }
    }

    It 'does not invoke Invoke-Command or New-PSSession for a WinRM transport' {
        $null = & (Get-Module adman) {
            param($cn, $tr)
            Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr
        } -cn 'PC01' -tr 'WinRM'

        Should -Invoke Invoke-Command -ModuleName adman -Times 0
        Should -Invoke New-PSSession -ModuleName adman -Times 0
    }

    It 'does not invoke Invoke-Command or New-PSSession for a CimDcom transport' {
        $null = & (Get-Module adman) {
            param($cn, $tr)
            Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr
        } -cn 'PC01' -tr 'CimDcom'

        Should -Invoke Invoke-Command -ModuleName adman -Times 0
        Should -Invoke New-PSSession -ModuleName adman -Times 0
    }

    It 'short-circuits for Skipped without invoking Invoke-Command or New-PSSession' {
        $null = & (Get-Module adman) {
            param($cn, $tr)
            Invoke-AdmanRemoteQuery -ComputerName $cn -Transport $tr
        } -cn 'PC01' -tr 'Skipped'

        Should -Invoke Invoke-Command -ModuleName adman -Times 0
        Should -Invoke New-PSSession -ModuleName adman -Times 0
    }
}
