#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) Initialize-Adman orchestration tests (D-04).
      * Test 6 (orchestration order): Initialize-Adman calls Initialize-AdmanConfig ->
        Test-AdmanAuditWritable -> Get-AdmanCredential -> Test-AdmanCapability ->
        Resolve-AdmanDomainSid -> Get-AdmanProtectedIdentity in that fixed order (asserted via a
        module-scope sequence recorder), then sets $script:Initialized.
      * -SetupMode: runs config load + seed but SKIPS the fail-closed scope/audit throws and the
        AD-touching resolution (wizard creates the config with no AD mutation).

.NOTES
    Pester 6. PSFramework stub on $TestDrive. The six step functions are mocked (-ModuleName
    adman); order is recorded into a TEST-script-scope list ($script:AdmanOrder) so no $global: is
    used (lint PSAvoidGlobalVars). Named binding into the module-scope scriptblock (PS 5.1).
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c4'
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
    $script:InitPath = Join-Path $script:RepoRoot 'Public\Initialize-Adman.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Test-scope stubs (global:) for the startup-step functions not yet implemented at RED so
    # Pester's Mock resolver can resolve them (-ModuleName adman). Initialize-AdmanConfig (00-02)
    # and Get-AdmanCredential (00-03 Task 1) already exist; New-EventLog is a core cmdlet. Inert
    # fallbacks - the real module functions shadow them at GREEN. Live only in the test process.
    function global:Test-AdmanAuditWritable { }
    function global:Test-AdmanCapability { }
    function global:Resolve-AdmanDomainSid { }
    function global:Get-AdmanProtectedIdentity { }

    function Reset-AdmanOrder {
        # Test-script-scope recorder: -ModuleName adman mock bodies execute in the TEST file's
        # script scope (verified empirically), so the recorder MUST live here - NOT in the adman
        # module scope - for the mocks' .Add() calls to be visible to Get-AdmanOrder. Keeping it
        # on $script: (not $global:) stays lint-clean (PSAvoidGlobalVars).
        $script:AdmanOrder = [System.Collections.Generic.List[string]]::new()
    }
    function Get-AdmanOrder {
        # Emit the flat array (no comma-wrap): the test-scope recorder unrolls into the pipeline
        # as N elements so 'Should -Be @(...)' compares element-wise. (The previous module-scope
        # version needed a leading comma to survive the & (Get-Module adman) boundary unrolling;
        # the test-scope version does not cross that boundary.)
        $script:AdmanOrder.ToArray()
    }
    function Set-AdmanMinimalConfig {
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
                DC                  = 'dc.mock.local'
                AuditDir            = '.store/audit'
                DenyList            = @()
                AdmanProtectedGroup = ''
                delegatedAdminGroup = ''
                credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
                transport           = [pscustomobject]@{ timeouts = [pscustomobject]@{ WinRM = 15; CIM = 20 } }
            }
        }
    }
}

Describe 'Initialize-Adman orchestration (D-04)' -Tag 'Unit' {

    It 'Test 6: calls the six startup steps in fixed order and sets $script:Initialized' {
        Reset-AdmanOrder

        Mock Initialize-AdmanConfig -ModuleName adman { $script:AdmanOrder.Add('Initialize-AdmanConfig') }
        Mock Test-AdmanAuditWritable -ModuleName adman { $script:AdmanOrder.Add('Test-AdmanAuditWritable'); $true }
        Mock Get-AdmanCredential -ModuleName adman { $script:AdmanOrder.Add('Get-AdmanCredential'); $null }
        Mock Test-AdmanCapability -ModuleName adman { $script:AdmanOrder.Add('Test-AdmanCapability'); [pscustomobject]@{} }
        Mock Resolve-AdmanDomainSid -ModuleName adman { $script:AdmanOrder.Add('Resolve-AdmanDomainSid') }
        Mock Get-AdmanProtectedIdentity -ModuleName adman { $script:AdmanOrder.Add('Get-AdmanProtectedIdentity') }
        Mock New-EventLog -ModuleName adman { }

        & (Get-Module adman) { Initialize-Adman }

        Get-AdmanOrder | Should -Be @(
            'Initialize-AdmanConfig',
            'Test-AdmanAuditWritable',
            'Get-AdmanCredential',
            'Test-AdmanCapability',
            'Resolve-AdmanDomainSid',
            'Get-AdmanProtectedIdentity'
        )
        & (Get-Module adman) { $script:Initialized | Should -BeTrue }
    }

    It 'Test 6 (SetupMode): -SetupMode runs config load only and skips fail-closed throws + AD resolution' {
        Reset-AdmanOrder

        Mock Initialize-AdmanConfig -ModuleName adman { $script:AdmanOrder.Add('Initialize-AdmanConfig') }
        Mock Test-AdmanAuditWritable -ModuleName adman { $script:AdmanOrder.Add('Test-AdmanAuditWritable'); $true }
        Mock Get-AdmanCredential -ModuleName adman { $script:AdmanOrder.Add('Get-AdmanCredential') }
        Mock Test-AdmanCapability -ModuleName adman { $script:AdmanOrder.Add('Test-AdmanCapability') }
        Mock Resolve-AdmanDomainSid -ModuleName adman { $script:AdmanOrder.Add('Resolve-AdmanDomainSid') }
        Mock Get-AdmanProtectedIdentity -ModuleName adman { $script:AdmanOrder.Add('Get-AdmanProtectedIdentity') }

        { & (Get-Module adman) { Initialize-Adman -SetupMode } } | Should -Not -Throw

        Should -Invoke Initialize-AdmanConfig -ModuleName adman -Times 1 -ParameterFilter { $SetupMode }
        Should -Invoke Test-AdmanCapability -ModuleName adman -Times 0 -Because 'the wizard performs no AD mutation'
        Should -Invoke Resolve-AdmanDomainSid -ModuleName adman -Times 0
        Get-AdmanOrder | Should -Be @('Initialize-AdmanConfig')
    }

    It 'Test 6 (static): Initialize-Adman.ps1 references the six steps in order and -SetupMode' {
        Test-Path -LiteralPath $script:InitPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:InitPath -Raw
        foreach ($name in @('Initialize-AdmanConfig', 'Test-AdmanAuditWritable', 'Get-AdmanCredential',
                            'Test-AdmanCapability', 'Resolve-AdmanDomainSid', 'Get-AdmanProtectedIdentity')) {
            @($src | Select-String -Pattern $name).Count | Should -BeGreaterOrEqual 1 -Because "$name must be called"
        }
        $src | Should -Match '\-SetupMode'
        # Order guard: each step name must appear at an increasing offset in the source.
        $pos = @()
        foreach ($name in @('Initialize-AdmanConfig', 'Test-AdmanAuditWritable', 'Get-AdmanCredential',
                            'Test-AdmanCapability', 'Resolve-AdmanDomainSid', 'Get-AdmanProtectedIdentity')) {
            $pos += $src.IndexOf($name)
        }
        $sorted = @($pos | Sort-Object)
        ($pos -join ',') | Should -Be ($sorted -join ',') -Because 'the six steps must be sourced in the fixed startup order'
    }
}
