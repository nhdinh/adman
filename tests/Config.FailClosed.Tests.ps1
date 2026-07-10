#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) fail-closed tests for Initialize-AdmanConfig (CONF-02): empty managed-OU
    scope, malformed JSON, and a failed (wrong-type) deny-list all THROW a terminating error
    before any mutating operation; the loader never returns a half-valid config.

.NOTES
    Pester 6. Private function exercised via InModuleScope semantics (Get-Module adman) {...}.
    PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. The module $script:StorePath
    is pointed at a per-test temp dir so the real .store/ is never touched.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000b2'
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
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    function New-AdmanBaseConfig {
        [CmdletBinding()] param()
        [pscustomobject][ordered]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DenyList            = @(@{ token = '500'; note = 'starter, not exhaustive' })
            safety              = @{ bulkConfirmThreshold = 5 }
            bulk                = @{ maxCount = 50 }
            AuditDir            = '.store/audit'
            ReportDir           = 'reports'
            transport           = @{ order = @('WinRM', 'CimWsman', 'CimDcom', 'Skip'); timeouts = @{ WinRM = 15; CIM = 20 } }
            credentialPolicy    = @{ allowRememberMe = $false }
            AdmanProtectedGroup = ''
            DC                  = ''
            delegatedAdminGroup = ''
        }
    }
}

Describe 'Initialize-AdmanConfig fail-closed (CONF-02)' -Tag 'Unit' {

    It 'throws a terminating error on empty ManagedOUs mentioning managed-OU/ManagedOUs (CONF-02 scope)' {
        $store = Join-Path $TestDrive 'empty-scope'
        $cfg = New-AdmanBaseConfig
        $cfg.ManagedOUs = @()
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $err = $null
        try {
            $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -ArgumentList $store
        } catch { $err = $_ }

        $err | Should -Not -BeNullOrEmpty -Because 'empty scope must throw before any mutating op'
        $err.Exception.Message | Should -Match 'managed-OU|ManagedOUs'
        & (Get-Module adman) { $script:ConfigLoaded | Should -Not -BeTrue }
    }

    It 'throws on malformed JSON and never returns a half-valid config (CONF-02 load failure)' {
        $store = Join-Path $TestDrive 'malformed'
        $null = New-Item -ItemType Directory -Path $store -Force
        '{ this is : not valid json ' | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $err = $null
        try {
            $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -ArgumentList $store
        } catch { $err = $_ }

        $err | Should -Not -BeNullOrEmpty -Because 'malformed JSON must throw (fail-closed)'
        & (Get-Module adman) { $script:ConfigLoaded | Should -Not -BeTrue }
    }

    It 'throws on a failed deny-list load (wrong type) and never returns a half-valid config (CONF-02)' {
        $store = Join-Path $TestDrive 'bad-denylist'
        $cfg = New-AdmanBaseConfig
        $cfg.DenyList = 'not-an-array'   # wrong type: must be an array of {token,note}
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $err = $null
        try {
            $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -ArgumentList $store
        } catch { $err = $_ }

        $err | Should -Not -BeNullOrEmpty -Because 'a failed deny-list load must throw (fail-closed)'
        & (Get-Module adman) { $script:ConfigLoaded | Should -Not -BeTrue }
    }
}
