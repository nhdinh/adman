#Requires -Modules Pester
<#
.SYNOPSIS
    COMP-01 contract tests for Find-AdmanComputer.

.DESCRIPTION
    Pins the D-02 / D-03 / HIGH-1 contract for the scoped, read-only computer search:
      * ManagedOUs are looped (one Get-ADComputer call per configured root).
      * -ResultPageSize is 1000 on every call.
      * -Server is pinned to $script:Config.DC on every call.
      * -SearchScope is Subtree on every call.
      * Out-of-scope objects are dropped via Test-AdmanInManagedScope.
      * Returned objects are the D-03 schema (ObjectType=Computer, fixed columns).
      * HIGH-1: user input is escaped via Escape-AdmanAdFilterLiteral before interpolation
        into -Filter. A name like O'Brien produces the doubled-quote form.
      * Escape-AdmanLdapFilterValue is NEVER called.
      * -Name uses -like semantics (D-02).

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:FindComputerPath = Join-Path $script:RepoRoot 'Public/Find-AdmanComputer.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000cd'
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

    # Seed $script:Config with TWO ManagedOUs roots so we can prove the loop iterates all of them.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local', 'OU=Subsidiary,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }

    # Helper to invoke the exported Find-AdmanComputer with the mock capture reset.
    function script:Invoke-FindComputer {
        param([hashtable]$Params)
        Reset-AdmanMockCapture
        Find-AdmanComputer @Params
    }
}

Describe 'Find-AdmanComputer: parameter validation' -Tag 'Unit' {

    It 'requires -Name' {
        { Find-AdmanComputer } | Should -Throw
    }

    It 'accepts -Name' {
        { Invoke-FindComputer -Params @{ Name = 'PC-*' } } | Should -Not -Throw
    }
}

Describe 'Find-AdmanComputer: ManagedOUs loop + paging invariants (D-02)' -Tag 'Unit' {

    It 'loops every ManagedOUs root (one Get-ADComputer call per root)' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls.Count | Should -Be 2
        $calls[0].SearchBase | Should -Be 'OU=Managed,DC=mock,DC=local'
        $calls[1].SearchBase | Should -Be 'OU=Subsidiary,DC=mock,DC=local'
    }

    It 'pins -ResultPageSize 1000 on every call' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        foreach ($c in $calls) { $c.ResultPageSize | Should -Be 1000 }
    }

    It 'pins -Server to $script:Config.DC on every call' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        foreach ($c in $calls) { $c.Server | Should -Be 'dc.mock.local' }
    }

    It 'pins -SearchScope Subtree on every call' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        foreach ($c in $calls) { $c.SearchScope | Should -Be 'Subtree' }
    }

    It 'passes the D-02 hard-coded Properties list on every call' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        foreach ($c in $calls) {
            $c.Properties | Should -Contain 'Name'
            $c.Properties | Should -Contain 'SamAccountName'
            $c.Properties | Should -Contain 'Enabled'
            $c.Properties | Should -Contain 'DistinguishedName'
            $c.Properties | Should -Contain 'ObjectSid'
            $c.Properties | Should -Contain 'ObjectGuid'
            $c.Properties | Should -Contain 'OperatingSystem'
            $c.Properties | Should -Contain 'OperatingSystemVersion'
            $c.Properties | Should -Contain 'OperatingSystemServicePack'
            $c.Properties | Should -Contain 'LastLogonDate'
            $c.Properties | Should -Contain 'whenCreated'
            $c.Properties | Should -Contain 'whenChanged'
            $c.Properties | Should -Contain 'IPv4Address'
            $c.Properties | Should -Contain 'DNSHostName'
        }
    }
}

Describe 'Find-AdmanComputer: HIGH-1 filter construction with Escape-AdmanAdFilterLiteral' -Tag 'Unit' {

    It 'builds -like filter for -Name (D-02 wildcard semantics)' {
        Invoke-FindComputer -Params @{ Name = 'PC-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls[0].Filter | Should -Be "Name -like 'PC-*'"
    }

    It "doubles single quotes in -Name (O'Brien -> O''Brien)" {
        Invoke-FindComputer -Params @{ Name = "O'Brien" } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls[0].Filter | Should -Be "Name -like 'O''Brien'"
    }

    It 'doubles backslashes in user input' {
        Invoke-FindComputer -Params @{ Name = 'PC\SERVER' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls[0].Filter | Should -Be "Name -like 'PC\\SERVER'"
    }

    It 'preserves wildcards in -Name for -like semantics (D-02)' {
        Invoke-FindComputer -Params @{ Name = 'WEB-*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADComputer' })
        $calls[0].Filter | Should -Match '\*'
    }
}

Describe 'Find-AdmanComputer: scope re-check drops out-of-scope objects (SAFE-07 step (c))' -Tag 'Unit' {

    It 'drops objects whose DN is outside every ManagedOUs root' {
        $results = @(Invoke-FindComputer -Params @{ Name = 'PC-*' })
        # The mock returns 3 rows per call: 2 in-scope + 1 out-of-scope (OU=NotManaged).
        # With 2 ManagedOUs roots looped, we get 6 raw rows -> 4 in-scope after filtering.
        $results.Count | Should -Be 4
        foreach ($r in $results) {
            $r.DistinguishedName | Should -Not -Match 'OU=NotManaged'
        }
    }

    It 'returns objects with the D-03 schema (ObjectType=Computer)' {
        $results = @(Invoke-FindComputer -Params @{ Name = 'PC-*' })
        $results.Count | Should -BeGreaterThan 0
        foreach ($r in $results) {
            $r.ObjectType | Should -Be 'Computer'
            $r.PSObject.Properties.Name | Should -Contain 'SamAccountName'
            $r.PSObject.Properties.Name | Should -Contain 'DistinguishedName'
            $r.PSObject.Properties.Name | Should -Contain 'ObjectSid'
            $r.PSObject.Properties.Name | Should -Contain 'ObjectGuid'
            $r.PSObject.Properties.Name | Should -Contain 'OperatingSystem'
            $r.PSObject.Properties.Name | Should -Contain 'OperatingSystemVersion'
            $r.PSObject.Properties.Name | Should -Contain 'OperatingSystemServicePack'
            $r.PSObject.Properties.Name | Should -Contain 'IPv4Address'
            $r.PSObject.Properties.Name | Should -Contain 'DNSHostName'
            $r.PSObject.Properties.Name | Should -Contain 'LastLogonDate'
            $r.PSObject.Properties.Name | Should -Contain 'whenCreated'
            $r.PSObject.Properties.Name | Should -Contain 'whenChanged'
        }
    }
}

Describe 'Find-AdmanComputer: structural invariants (HIGH-1)' -Tag 'Unit' {

    It 'calls Escape-AdmanAdFilterLiteral on the -Name parameter' {
        $content = Get-Content $script:FindComputerPath -Raw
        $content | Should -Match 'Escape-AdmanAdFilterLiteral'
    }

    It 'NEVER calls Escape-AdmanLdapFilterValue (RFC4515 helper is for -LDAPFilter only)' {
        $content = Get-Content $script:FindComputerPath -Raw
        $content | Should -Not -Match 'Escape-AdmanLdapFilterValue'
    }

    It 'NEVER calls Test-AdmanTargetAllowed (deny/protected checks are mutation-only)' {
        $content = Get-Content $script:FindComputerPath -Raw
        $content | Should -Not -Match 'Test-AdmanTargetAllowed'
    }

    It 'calls Test-AdmanInManagedScope on every emitted object' {
        $content = Get-Content $script:FindComputerPath -Raw
        $content | Should -Match 'Test-AdmanInManagedScope'
    }

    It 'is exported in adman.psd1 FunctionsToExport' {
        # Import-PowerShellDataFile is PS7+; parse the manifest directly for 5.1 compat.
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match "Find-AdmanComputer"
        # Also verify the module actually exports it.
        (Get-Command -Module adman -Name 'Find-AdmanComputer' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
