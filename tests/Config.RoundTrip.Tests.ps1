#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) round-trip tests for Initialize-AdmanConfig / Save-AdmanConfig (CONF-03):
    every save uses ConvertTo-Json -Depth >=5 (proven by a mock capturing -Depth), nested keys
    survive a save+reload, the loader reads a PSCustomObject (5.1-safe, no -AsHashtable), and the
    impl source carries -Depth >=5 on every ConvertTo-Json save.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. The module
    $script:StorePath is pointed at a per-test temp dir so the real .store/ is never touched.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000b3'
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

    function New-AdmanRoundTripConfig {
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

Describe 'Initialize-AdmanConfig round-trip (CONF-03)' -Tag 'Unit' {

    It 'save uses ConvertTo-Json -Depth >=5 and round-trips nested keys losslessly' {
        $store = Join-Path $TestDrive 'roundtrip-save'
        $null = New-Item -ItemType Directory -Path $store -Force
        $path = Join-Path $store 'config.json'
        $cfg = New-AdmanRoundTripConfig

        $script:capturedDepth = $null
        Mock ConvertTo-Json -ModuleName adman {
            param($InputObject, $Depth, [switch]$Compress)
            $script:capturedDepth = $Depth
            Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress:$Compress
        }

        $null = & (Get-Module adman) { param($c, $p) Save-AdmanConfig -Config $c -Path $p -Confirm:$false } -ArgumentList $cfg, $path

        $script:capturedDepth | Should -Not -BeNullOrEmpty -Because 'every save must pass -Depth (Pitfall 8)'
        [int]$script:capturedDepth | Should -BeGreaterOrEqual 5

        # Loader read path (5.1-safe): raw JSON -> PSCustomObject, index by property (no -AsHashtable).
        $reloaded = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        [int]$reloaded.transport.timeouts.WinRM | Should -Be 15
        [int]$reloaded.transport.timeouts.CIM | Should -Be 20
        [bool]$reloaded.credentialPolicy.allowRememberMe | Should -BeFalse
        $reloaded.PSObject | Should -Not -BeNullOrEmpty -Because '5.1 read must yield a PSCustomObject'
    }

    It 'Initialize-AdmanConfig reload preserves nested keys and yields a PSCustomObject' {
        $store = Join-Path $TestDrive 'roundtrip-load'
        $null = New-Item -ItemType Directory -Path $store -Force
        $cfg = New-AdmanRoundTripConfig
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $store 'config.json') -Encoding UTF8

        $null = & (Get-Module adman) { param($p) $script:StorePath = $p; Initialize-AdmanConfig } -ArgumentList $store

        & (Get-Module adman) {
            $script:ConfigLoaded | Should -BeTrue
            $script:Config.PSObject | Should -Not -BeNullOrEmpty -Because 'loaded config must be a PSCustomObject (5.1-safe)'
            [int]$script:Config.transport.timeouts.CIM | Should -Be 20
            @($script:Config.transport.order).Count | Should -Be 4
        }
    }

    It 'static: every ConvertTo-Json save carries -Depth >=5; no Core-only hashtable switch' {
        Test-Path -LiteralPath $script:ImplPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ImplPath -Raw
        $depths = @([regex]::Matches($src, 'ConvertTo-Json[^\r\n]*-Depth\s+(\d+)') |
                ForEach-Object { [int]$_.Groups[1].Value })
        $depths.Count | Should -BeGreaterOrEqual 1 -Because 'at least one ConvertTo-Json -Depth save must exist'
        foreach ($d in $depths) { $d | Should -BeGreaterOrEqual 5 }
        @($src | Select-String -Pattern '\-AsHashtable').Count | Should -Be 0
    }
}
