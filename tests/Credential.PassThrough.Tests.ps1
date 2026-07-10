#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED/GREEN) pass-through + rights-decision tests for Get-AdmanCredential
    (CONF-06 pass-through default, D-06). Proves:
      * rights sufficient  => return $null, NEVER prompt (regardless of allowRememberMe)
      * rights insufficient => prompt (Get-Credential) even when allowRememberMe=$false
      * rights insufficient + allowRememberMe + readable stored file => restore (no prompt)
      * regression: allowRememberMe=$false + insufficient MUST still prompt (no silent $null)
        and MUST NOT write a DPAPI file (pins the unreachable-prompt bug)
      * the cheap non-destructive rights helper (Test-AdmanRightsSufficient) is the decision
        input when $script:RightsInsufficient is not pre-set.

.NOTES
    Pester 6. PSFramework is satisfied by a throwaway 1.14.457 stub on $TestDrive (human-gated
    real install NOT required). $script:StorePath is pointed at a per-test temp dir so the real
    .store/ is never touched. Get-Credential is not resolvable on this host (Security module
    TypeData conflict), so a test-scope stub is provided strictly so Pester can Mock it; it is
    never shipped. No real AD/DPAPI is exercised (Import-Clixml/Get-Credential are mocked).
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c1'
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

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:ImplPath = Join-Path $script:RepoRoot 'Private\Foundation\Get-AdmanCredential.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Test-scope stubs for cmdlets not resolvable on this host (so Pester can Mock them).
    # Qualified with global: so Get-Command (used by Pester Mock) resolves them from any scope -
    # a plain `function X {}` inside BeforeAll is Describe-scoped and Pester's Mock resolver does
    # not see it. Get-Credential's Security module fails to load here (TypeData conflict); the AD
    # helper is module-private at GREEN. Module calls resolve the module-private versions at GREEN;
    # these global: doubles are inert fallbacks and live only in the test process (never shipped).
    function global:Get-Credential { param($Message) }
    function global:Read-AdmanRememberMeConsent { }
    function global:Get-ADOrganizationalUnit { param($Identity, $Server, $Filter) }

    # Build a [pscredential] without ConvertTo-SecureString (Security module may be absent).
    function New-AdmanTestCred {
        [CmdletBinding()]
        param([string]$Value = 'Str0ng!')
        $sec = New-Object System.Security.SecureString
        if ($Value) { $Value.ToCharArray() | ForEach-Object { $sec.AppendChar($_) } }
        $sec.MakeReadOnly()
        return [pscredential]::new('DOMAIN\user', $sec)
    }

    function Get-AdmanCredTestConfig {
        [CmdletBinding()]
        param(
            [bool]$Allow = $false,
            [string]$Delegated = '',
            [string[]]$ManagedOUs = @('OU=Managed,DC=mock,DC=local')
        )
        [pscustomobject]@{
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $Allow }
            DC                  = 'dc.mock.local'
            ManagedOUs          = $ManagedOUs
            delegatedAdminGroup = $Delegated
        }
    }

    function Set-AdmanCredState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]$Config,
            [Parameter(Mandatory)][string]$Store,
            [switch]$RightsSufficient,
            [switch]$RightsInsufficient,
            [switch]$RightsUnknown
        )
        & (Get-Module adman) {
            param($Config, $Store, $RightsSufficient, $RightsInsufficient, $RightsUnknown)
            $script:Config = $Config
            $script:StorePath = $Store
            Remove-Variable -Name RightsInsufficient -Scope Script -ErrorAction SilentlyContinue
            if ($RightsSufficient) { Set-Variable -Name RightsInsufficient -Scope Script -Value $false }
            if ($RightsInsufficient) { Set-Variable -Name RightsInsufficient -Scope Script -Value $true }
            # RightsUnknown => leave unset so Get-AdmanCredential computes via Test-AdmanRightsSufficient.
        } -Config $Config -Store $Store `
            -RightsSufficient:$RightsSufficient -RightsInsufficient:$RightsInsufficient -RightsUnknown:$RightsUnknown
    }
}

Describe 'Get-AdmanCredential pass-through + rights decision (CONF-06, D-06)' -Tag 'Unit' {

    It 'Test 1a: rights sufficient + allowRememberMe=$true -> returns $null and never prompts' {
        $store = Join-Path $TestDrive 't1a'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store -RightsSufficient

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred | Should -BeNullOrEmpty -Because 'pass-through must return $null when rights are sufficient'
        Should -Invoke Get-Credential -ModuleName adman -Times 0 -Because 'no prompt when rights sufficient (even with remember-me on)'
    }

    It 'Test 1b: rights sufficient + allowRememberMe=$false -> returns $null and never prompts' {
        $store = Join-Path $TestDrive 't1b'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $false) -Store $store -RightsSufficient

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred | Should -BeNullOrEmpty
        Should -Invoke Get-Credential -ModuleName adman -Times 0
    }

    It 'Test 2a: rights insufficient + allowRememberMe=$false -> prompts exactly once (no silent $null)' {
        $store = Join-Path $TestDrive 't2a'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $false) -Store $store -RightsInsufficient

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue -Because 'insufficient rights must yield a prompted credential, not $null'
        Should -Invoke Get-Credential -ModuleName adman -Times 1
    }

    It 'Test 2b: rights insufficient + allowRememberMe=$true + readable stored file -> restore, no prompt' {
        $store = Join-Path $TestDrive 't2b'
        $null = New-Item -ItemType Directory -Path $store -Force
        'placeholder' | Set-Content -LiteralPath (Join-Path $store 'adman.credential.xml') -Encoding UTF8
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store -RightsInsufficient

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Import-Clixml -ModuleName adman { New-AdmanTestCred 'Stored!' }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        $cred.GetNetworkCredential().Password | Should -Be 'Stored!' -Because 'a readable stored file is restored instead of prompting'
        Should -Invoke Get-Credential -ModuleName adman -Times 0 -Because 'no prompt when a stored credential restores'
    }

    It 'Test 8 (regression): allowRememberMe=$false + insufficient -> prompts AND writes no DPAPI file' {
        $store = Join-Path $TestDrive 't8'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $false) -Store $store -RightsInsufficient

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred }
        Mock Export-Clixml -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue -Because 'the prompt path must be reachable when remember-me is off (regression guard)'
        Should -Invoke Get-Credential -ModuleName adman -Times 1
        Should -Invoke Export-Clixml -ModuleName adman -Times 0 -Because 'no DPAPI file is written when remember-me is off'
    }

    It 'rights helper: readable managed OU + no delegatedAdminGroup -> sufficient (compute path)' {
        $store = Join-Path $TestDrive 'th1'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Delegated '') -Store $store -RightsUnknown

        Mock Get-ADOrganizationalUnit -ModuleName adman { [pscustomobject]@{ DistinguishedName = 'OU=Managed,DC=mock,DC=local' } }
        $ok = & (Get-Module adman) { Test-AdmanRightsSufficient }

        $ok | Should -BeTrue -Because 'a readable managed OU with no group gate means pass-through rights are sufficient'
    }

    It 'rights helper: unreadable managed OU -> insufficient (compute path)' {
        $store = Join-Path $TestDrive 'th2'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig) -Store $store -RightsUnknown

        Mock Get-ADOrganizationalUnit -ModuleName adman { throw 'Access is denied' }
        $ok = & (Get-Module adman) { Test-AdmanRightsSufficient }

        $ok | Should -BeFalse -Because 'an unreadable managed OU means pass-through rights are insufficient'
    }
}
