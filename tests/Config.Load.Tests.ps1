#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) load-path tests for Initialize-AdmanConfig (CONF-01/03, D-04/D-05):
    pinned-path load (Import-PSFConfig -Path, never the per-user auto-import persistence),
    setup-mode exemption, single seed with no re-seed, and static source invariants.

.NOTES
    Pester 6. Private functions are exercised via InModuleScope adman. PSFramework is satisfied
    by a throwaway 1.14.457 stub on $TestDrive so the human-gated real install is NOT required.
    The module's $script:StorePath is pointed at a per-test temp dir so the real .store/ is never
    touched. No AD cmdlet is invoked (all config-only).
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000b1'
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
    $script:ImplPath = Join-Path $script:RepoRoot 'Private\Config\Initialize-AdmanConfig.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Minimal well-formed config builder (ManagedOUs populated so the scope gate does not throw).
    function New-AdmanTestConfig {
        [CmdletBinding()]
        param(
            [string[]]$ManagedOUs = @('OU=Managed,DC=mock,DC=local'),
            $DenyList = @(
                @{ token = '500'; note = 'starter, not exhaustive' },
                @{ token = '501'; note = 'starter, not exhaustive' },
                @{ token = '502'; note = 'starter, not exhaustive' }
            ),
            [switch]$NoDenyList
        )
        $o = [ordered]@{
            ManagedOUs           = $ManagedOUs
            safety               = @{ bulkConfirmThreshold = 5 }
            bulk                 = @{ maxCount = 50 }
            AuditDir             = '.store/audit'
            ReportDir            = 'reports'
            transport            = @{ order = @('WinRM', 'CimWsman', 'CimDcom', 'Skip'); timeouts = @{ WinRM = 15; CIM = 20; perHostProbeCap = 10; totalInventoryRemoteCap = 120 } }
            credentialPolicy     = @{ allowRememberMe = $false }
            AdmanProtectedGroup  = ''
            DC                   = ''
            delegatedAdminGroup  = ''
            security             = @{
                passwordSource         = 'Generate'
                passwordGeneration     = @{ length = 20 }
                mustChangeAtNextLogon  = $true
            }
        }
        if (-not $NoDenyList) { $o['DenyList'] = $DenyList }
        return [pscustomobject]$o
    }
}

Describe 'Initialize-AdmanConfig load path (CONF-01/03, D-04/D-05)' -Tag 'Unit' {

    It 'loads a valid config from a pinned path and populates $script:Config (CONF-01)' {
        $store = Join-Path $TestDrive 'load-valid'
        $cfg = New-AdmanTestConfig
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8
        $expectedPath = Join-Path $store 'config.json'

        Mock Import-PSFConfig -ModuleName adman { }
        $result = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -p $store

        $result | Should -BeTrue
        & (Get-Module adman) {
            $script:ConfigLoaded | Should -BeTrue
            @($script:Config.ManagedOUs).Count | Should -Be 1
            [int]$script:Config.safety.bulkConfirmThreshold | Should -Be 5
        }
        Should -Invoke Import-PSFConfig -ModuleName adman -Times 1 -ParameterFilter { $Path -eq $expectedPath }
    }

    It 'setup-mode (-SetupMode) bypasses the empty-scope fail-closed gate and performs no AD mutation (D-04)' {
        $store = Join-Path $TestDrive 'setup-mode'
        $cfg = New-AdmanTestConfig -ManagedOUs @()   # empty scope - would throw without -SetupMode
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        # Initialize-AdmanConfig is a config-only loader; it never calls AD cmdlets. The D-04
        # contract: in -SetupMode the empty-scope gate is bypassed (wizard may write an
        # empty-scope config) while AD-mutating entry points (Phase 2) still enforce it.
        $result = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig -SetupMode } -p $store

        $result | Should -BeTrue
        & (Get-Module adman) { $script:ConfigLoaded | Should -BeTrue }
    }

    It 'seeds the deny-list once on a truly fresh file and never re-seeds on a second load (D-05)' {
        $store = Join-Path $TestDrive 'seed-once'
        $cfg = New-AdmanTestConfig -NoDenyList   # ManagedOUs present, DenyList absent
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        # First load -> seed written into the JSON.
        $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -p $store
        $first = Get-Content -LiteralPath (Join-Path $store 'config.json') -Raw | ConvertFrom-Json
        $firstTokens = @($first.DenyList | ForEach-Object { $_.token })
        $firstTokens | Should -Contain '500'
        $firstTokens | Should -Contain '501'
        $firstTokens | Should -Contain '502'
        @($first.DenyList).Count | Should -Be 3

        # Second load -> file is the source of truth; no duplication.
        $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -p $store
        $second = Get-Content -LiteralPath (Join-Path $store 'config.json') -Raw | ConvertFrom-Json
        @($second.DenyList).Count | Should -Be 3 -Because 'a second load must not re-seed/duplicate the deny-list'
    }

    It 'static source invariants: pinned -Path, no per-user auto-import, strips _comment, 5.1-safe' {
        Test-Path -LiteralPath $script:ImplPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ImplPath -Raw
        # Import-PSFConfig is used WITH -Path (D-01 pin)
        ($src | Select-String -Pattern 'Import-PSFConfig').Count | Should -BeGreaterOrEqual 1
        $src | Should -Match 'Import-PSFConfig\s+-Path'
        # NEVER the per-user auto-import registration cmdlet for safety values (Pitfall 7, T-00-07)
        @($src | Select-String -Pattern 'Register-PSFConfig').Count | Should -Be 0
        # Loader strips annotated-example '_comment' keys (D-04)
        ($src | Select-String -Pattern '_comment').Count | Should -BeGreaterOrEqual 1
        # 5.1-safe: Core-only ConvertFrom-Json hashtable switch must NOT appear (Pitfall 8)
        @($src | Select-String -Pattern '\-AsHashtable').Count | Should -Be 0
        # Phase 3: timeout additive-merge must be sourced from adman.defaults.json (not hard-coded).
        $src | Should -Match 'adman\.defaults\.json'
    }
}

Describe 'Initialize-AdmanConfig Phase 3 timeout config (RMT-01/02, D-02)' -Tag 'Unit' {

    It 'Test-AdmanConfigValid accepts a config with transport.timeouts.perHostProbeCap and totalInventoryRemoteCap' {
        $cfg = New-AdmanTestConfig
        $cfg.transport.timeouts.perHostProbeCap = 7
        $cfg.transport.timeouts.totalInventoryRemoteCap = 90
        $cfgObj = $cfg | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $null = & (Get-Module adman) { param($c, $root) Test-AdmanConfigValid -Config $c -ModuleRoot $root } -c $cfgObj -root $script:RepoRoot
        $true | Should -BeTrue
    }

    It 'Test-AdmanConfigValid throws when transport.timeouts.perHostProbeCap is missing' {
        $cfg = New-AdmanTestConfig
        $cfg.transport.timeouts = @{ WinRM = 15; CIM = 20; totalInventoryRemoteCap = 120 }
        $cfgObj = $cfg | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        { & (Get-Module adman) { param($c, $root) Test-AdmanConfigValid -Config $c -ModuleRoot $root } -c $cfgObj -root $script:RepoRoot } | Should -Throw -ExpectedMessage '*perHostProbeCap*'
    }

    It 'Test-AdmanConfigValid throws when transport.timeouts.totalInventoryRemoteCap is missing' {
        $cfg = New-AdmanTestConfig
        $cfg.transport.timeouts = @{ WinRM = 15; CIM = 20; perHostProbeCap = 10 }
        $cfgObj = $cfg | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        { & (Get-Module adman) { param($c, $root) Test-AdmanConfigValid -Config $c -ModuleRoot $root } -c $cfgObj -root $script:RepoRoot } | Should -Throw -ExpectedMessage '*totalInventoryRemoteCap*'
    }

    It 'config/adman.defaults.json carries perHostProbeCap=10 and totalInventoryRemoteCap=120' {
        $d = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config\adman.defaults.json') -Raw | ConvertFrom-Json
        [int]$d.transport.timeouts.perHostProbeCap | Should -Be 10
        [int]$d.transport.timeouts.totalInventoryRemoteCap | Should -Be 120
    }

    It 'Initialize-AdmanConfig merges missing timeout keys from shipped defaults while preserving existing WinRM/CIM values' {
        $store = Join-Path $TestDrive 'merge-timeouts'
        $cfg = New-AdmanTestConfig
        $cfg.transport.timeouts = @{ WinRM = 99; CIM = 88 }   # missing Phase 3 keys
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -p $store

        & (Get-Module adman) {
            [int]$script:Config.transport.timeouts.WinRM | Should -Be 99
            [int]$script:Config.transport.timeouts.CIM | Should -Be 88
            [int]$script:Config.transport.timeouts.perHostProbeCap | Should -Be 10
            [int]$script:Config.transport.timeouts.totalInventoryRemoteCap | Should -Be 120
        }
    }

    It 'Initialize-AdmanConfig preserves an existing perHostProbeCap value while adding a missing totalInventoryRemoteCap default' {
        $store = Join-Path $TestDrive 'preserve-timeout'
        $cfg = New-AdmanTestConfig
        $cfg.transport.timeouts = @{ WinRM = 15; CIM = 20; perHostProbeCap = 42 }
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -p $store

        & (Get-Module adman) {
            [int]$script:Config.transport.timeouts.perHostProbeCap | Should -Be 42
            [int]$script:Config.transport.timeouts.totalInventoryRemoteCap | Should -Be 120
        }
    }

    It '$script:TransportCache is initialized as an empty hashtable in adman.psm1' {
        & (Get-Module adman) {
            $script:TransportCache | Should -Not -BeNullOrEmpty
            $script:TransportCache -is [hashtable] | Should -BeTrue
            $script:TransportCache.Count | Should -Be 0
        }
    }
}
