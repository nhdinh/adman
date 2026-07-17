#Requires -Modules Pester
<#
.SYNOPSIS
    RPT-06 contract tests for Get-AdmanInventoryReport.

.DESCRIPTION
    Pins the inventory report contract:
      * Requests the D-02 computer properties plus OperatingSystem,
        OperatingSystemVersion, OperatingSystemServicePack, IPv4Address,
        DNSHostName.
      * Uses -Filter * with -SearchScope Subtree and -ResultPageSize 1000.
      * Returns computer objects with OS version and network attributes.
      * Out-of-scope objects are dropped via Test-AdmanInManagedScope.
      * Bucket column is set to 'Inventory'.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT,
    no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:InventoryPath = Join-Path $script:RepoRoot 'Public/Get-AdmanInventoryReport.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d4'
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

    # Import the AD mocks FIRST so Get-ADComputer resolves to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with Phase 3 timeout keys.
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
    }

    # Default Phase 3 remoting mocks: every host is reachable via WinRM with canned enrichment.
    Mock Connect-AdmanTarget -ModuleName adman { 'WinRM' }
    Mock Invoke-AdmanRemoteQuery -ModuleName adman { [pscustomobject]@{ RemoteOS = 'Windows 11 Pro 10.0 (26200)'; Uptime = [timespan]'7.12:34:56'; LoggedOnUser = 'MOCK\alice'; Transport = 'WinRM' } }

    # Helper to invoke the exported Get-AdmanInventoryReport with the mock capture reset.
    function script:Invoke-InventoryReport {
        Reset-AdmanMockCapture
        Get-AdmanInventoryReport
    }
}

Describe 'Get-AdmanInventoryReport: D-02 paging + properties invariants' -Tag 'Unit' {

    It 'requests the D-02 computer properties plus inventory attributes' {
        Invoke-InventoryReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls.Count | Should -BeGreaterOrEqual 1
        $calls[0].Properties | Should -Contain 'OperatingSystem'
        $calls[0].Properties | Should -Contain 'OperatingSystemVersion'
        $calls[0].Properties | Should -Contain 'OperatingSystemServicePack'
        $calls[0].Properties | Should -Contain 'IPv4Address'
        $calls[0].Properties | Should -Contain 'DNSHostName'
        $calls[0].Properties | Should -Contain 'LastLogonDate'
        $calls[0].Properties | Should -Contain 'whenCreated'
        $calls[0].Properties | Should -Contain 'whenChanged'
    }

    It 'uses -Filter * with -SearchScope Subtree and -ResultPageSize 1000' {
        Invoke-InventoryReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls[0].Filter | Should -Be '*'
        $calls[0].SearchScope | Should -Be 'Subtree'
        $calls[0].ResultPageSize | Should -Be 1000
        $calls[0].Server | Should -Be 'dc.mock.local'
    }
}

Describe 'Get-AdmanInventoryReport: inventory contract (RPT-06)' -Tag 'Unit' {

    It 'returns computer objects with OperatingSystem and OperatingSystemVersion' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].OperatingSystem | Should -Not -BeNullOrEmpty
        $result[0].OperatingSystemVersion | Should -Not -BeNullOrEmpty
    }

    It 'returns computer objects with IPv4Address and DNSHostName' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].IPv4Address | Should -Not -BeNullOrEmpty
        $result[0].DNSHostName | Should -Not -BeNullOrEmpty
    }

    It 'sets Bucket column to Inventory on every row' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        foreach ($row in $result) {
            $row.Bucket | Should -Be 'Inventory'
        }
    }

    It 'drops out-of-scope objects via Test-AdmanInManagedScope' {
        $result = Invoke-InventoryReport
        # The mock returns 2 in-scope and 1 out-of-scope per SearchBase.
        foreach ($row in $result) {
            $row.DistinguishedName | Should -Match 'OU=Managed,DC=mock,DC=local$'
        }
    }

    It 'returns D-03 schema objects (no raw AD property leakage)' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].PSObject.Properties.Name | Should -Contain 'ObjectType'
        $result[0].PSObject.Properties.Name | Should -Contain 'Name'
        $result[0].PSObject.Properties.Name | Should -Contain 'SamAccountName'
        $result[0].PSObject.Properties.Name | Should -Contain 'Enabled'
        $result[0].PSObject.Properties.Name | Should -Contain 'DistinguishedName'
        $result[0].PSObject.Properties.Name | Should -Contain 'ObjectSid'
        $result[0].PSObject.Properties.Name | Should -Contain 'ObjectGuid'
        $result[0].PSObject.Properties.Name | Should -Contain 'Bucket'
        # Raw AD properties must NOT leak.
        $result[0].PSObject.Properties.Name | Should -Not -Contain 'MemberOf'
        $result[0].PSObject.Properties.Name | Should -Not -Contain 'objectClass'
        $result[0].PSObject.Properties.Name | Should -Not -Contain 'PropertyNames'
    }
}

Describe 'Get-AdmanInventoryReport: remote enrichment (RMT-03, D-01)' -Tag 'Unit' {

    BeforeEach {
        Mock Connect-AdmanTarget -ModuleName adman { 'WinRM' }
        Mock Invoke-AdmanRemoteQuery -ModuleName adman { [pscustomobject]@{ RemoteOS = 'Windows 11 Pro 10.0 (26200)'; Uptime = [timespan]'7.12:34:56'; LoggedOnUser = 'MOCK\alice'; Transport = 'WinRM' } }
        Mock Write-Warning -ModuleName adman { }
    }

    It 'enriched rows contain Transport, RemoteOS, Uptime, LoggedOnUser and Bucket=Inventory' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        foreach ($row in $result) {
            $row.PSObject.Properties.Name | Should -Contain 'Transport'
            $row.PSObject.Properties.Name | Should -Contain 'RemoteOS'
            $row.PSObject.Properties.Name | Should -Contain 'Uptime'
            $row.PSObject.Properties.Name | Should -Contain 'LoggedOnUser'
            $row.Bucket | Should -Be 'Inventory'
        }
    }

    It 'preserves AD-side OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack' {
        $result = Invoke-InventoryReport
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].OperatingSystem | Should -Not -BeNullOrEmpty
        $result[0].OperatingSystemVersion | Should -Not -BeNullOrEmpty
        # ServicePack may be empty on the mock; assert it exists as a property.
        $result[0].PSObject.Properties.Name | Should -Contain 'OperatingSystemServicePack'
    }

    It 'marks Skipped and warns once when Connect-AdmanTarget returns Skipped' {
        Mock Connect-AdmanTarget -ModuleName adman { 'Skipped' }
        Mock Invoke-AdmanRemoteQuery -ModuleName adman { [pscustomobject]@{ RemoteOS = $null; Uptime = $null; LoggedOnUser = $null; Transport = 'Skipped' } }

        $result = Invoke-InventoryReport

        foreach ($row in $result) {
            $row.Transport | Should -Be 'Skipped'
            $row.RemoteOS | Should -BeNullOrEmpty
            $row.Uptime | Should -BeNullOrEmpty
            $row.LoggedOnUser | Should -BeNullOrEmpty
        }
        Should -Invoke Write-Warning -ModuleName adman -Times 1
    }

    It 'marks Skipped and warns once when Invoke-AdmanRemoteQuery returns Skipped due to CIM error' {
        Mock Invoke-AdmanRemoteQuery -ModuleName adman { [pscustomobject]@{ RemoteOS = $null; Uptime = $null; LoggedOnUser = $null; Transport = 'Skipped' } }

        $result = Invoke-InventoryReport

        foreach ($row in $result) {
            $row.Transport | Should -Be 'Skipped'
        }
        Should -Invoke Write-Warning -ModuleName adman -Times 1
    }

    It 'passes a shrinking remaining timeout budget and marks hosts Skipped when the per-host cap is exhausted' {
        # Cap=2s gives headroom for one fast host and one slow host.
        & (Get-Module adman) {
            $script:Config.transport.timeouts.perHostProbeCap = 2
        }
        $captured = @{ Timeouts = [System.Collections.Generic.List[int]]::new() }
        Mock Connect-AdmanTarget -ModuleName adman {
            param($ComputerName)
            if ($ComputerName -eq 'PC-INSCOPE-01.mock.local') { Start-Sleep -Milliseconds 600; 'WinRM' }
            else { Start-Sleep -Milliseconds 2100; 'WinRM' }
        }
        Mock Invoke-AdmanRemoteQuery -ModuleName adman {
            param($ComputerName, $Transport, $TimeoutSeconds)
            $captured.Timeouts.Add([int]$TimeoutSeconds)
            [pscustomobject]@{ RemoteOS = 'Windows 11 Pro'; Uptime = [timespan]'1.00:00:00'; LoggedOnUser = 'MOCK\alice'; Transport = 'WinRM' }
        }

        $result = Invoke-InventoryReport

        $captured.Timeouts.Count | Should -Be 1
        $captured.Timeouts[0] | Should -BeLessThan 2
        $skippedRows = @($result | Where-Object { $_.Transport -eq 'Skipped' })
        $skippedRows.Count | Should -BeGreaterOrEqual 1
    }

    It 'enforces the total cap by skipping remaining rows without further probes' {
        & (Get-Module adman) {
            $script:Config.transport.timeouts.totalInventoryRemoteCap = 0
        }

        $result = Invoke-InventoryReport

        Should -Invoke Connect-AdmanTarget -ModuleName adman -Times 0
        foreach ($row in $result) {
            $row.Transport | Should -Be 'Skipped'
        }
        Should -Invoke Write-Warning -ModuleName adman -Times 1
    }

    It 'comment-based help mentions remote enrichment, new columns, and Skipped hosts' {
        $content = Get-Content $script:InventoryPath -Raw
        $content | Should -BeLike '*remote enrichment*'
        $content | Should -BeLike '*Transport*'
        $content | Should -BeLike '*RemoteOS*'
        $content | Should -BeLike '*Uptime*'
        $content | Should -BeLike '*LoggedOnUser*'
        $content | Should -BeLike '*Skipped*'
    }
}
