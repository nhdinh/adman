#Requires -Modules Pester
<#
.SYNOPSIS
    USER-01 contract tests for Find-AdmanUser.

.DESCRIPTION
    Pins the D-02 / D-03 / HIGH-1 contract for the scoped, read-only user search:
      * ManagedOUs are looped (one Get-ADUser call per configured root).
      * -ResultPageSize is 1000 on every call (PITFALLS performance trap).
      * -Server is pinned to $script:Config.DC on every call.
      * -SearchScope is Subtree on every call.
      * Out-of-scope objects are dropped via Test-AdmanInManagedScope.
      * Returned objects are the D-03 schema (ObjectType=User, fixed columns).
      * HIGH-1: user input is escaped via Escape-AdmanAdFilterLiteral before interpolation
        into -Filter. A name like O'Brien produces the doubled-quote form
        "sAMAccountName -eq 'O''Brien'".
      * Escape-AdmanLdapFilterValue is NEVER called (RFC4515 helper is for -LDAPFilter only).
      * -SamAccountName and -DisplayName use -eq; -Name uses -like (D-02).
      * At least one search criterion is required.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:FindUserPath = Join-Path $script:RepoRoot 'Public/Find-AdmanUser.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000cc'
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

    # Import the AD mocks FIRST so Get-ADUser resolves to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with TWO ManagedOUs roots so we can prove the loop iterates all of them.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local', 'OU=Subsidiary,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }

    # Helper to invoke the exported Find-AdmanUser with the mock capture reset.
    function script:Invoke-FindUser {
        param([hashtable]$Params)
        Reset-AdmanMockCapture
        Find-AdmanUser @Params
    }
}

Describe 'Find-AdmanUser: parameter validation' -Tag 'Unit' {

    It 'throws when no search criterion is supplied' {
        { Find-AdmanUser } | Should -Throw '*at least one of*'
    }

    It 'accepts -SamAccountName alone' {
        { Invoke-FindUser -Params @{ SamAccountName = 'alice' } } | Should -Not -Throw
    }

    It 'accepts -DisplayName alone' {
        { Invoke-FindUser -Params @{ DisplayName = 'Alice' } } | Should -Not -Throw
    }

    It 'accepts -Name alone' {
        { Invoke-FindUser -Params @{ Name = 'ali*' } } | Should -Not -Throw
    }
}

Describe 'Find-AdmanUser: ManagedOUs loop + paging invariants (D-02)' -Tag 'Unit' {

    It 'loops every ManagedOUs root (one Get-ADUser call per root)' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls.Count | Should -Be 2
        $calls[0].SearchBase | Should -Be 'OU=Managed,DC=mock,DC=local'
        $calls[1].SearchBase | Should -Be 'OU=Subsidiary,DC=mock,DC=local'
    }

    It 'pins -ResultPageSize 1000 on every call' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        foreach ($c in $calls) { $c.ResultPageSize | Should -Be 1000 }
    }

    It 'pins -Server to $script:Config.DC on every call' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        foreach ($c in $calls) { $c.Server | Should -Be 'dc.mock.local' }
    }

    It 'pins -SearchScope Subtree on every call' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        foreach ($c in $calls) { $c.SearchScope | Should -Be 'Subtree' }
    }

    It 'passes the D-02 hard-coded Properties list on every call' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        foreach ($c in $calls) {
            $c.Properties | Should -Contain 'Name'
            $c.Properties | Should -Contain 'SamAccountName'
            $c.Properties | Should -Contain 'DisplayName'
            $c.Properties | Should -Contain 'UserPrincipalName'
            $c.Properties | Should -Contain 'LastLogonDate'
            $c.Properties | Should -Contain 'PasswordLastSet'
            $c.Properties | Should -Contain 'PasswordExpired'
            $c.Properties | Should -Contain 'LockedOut'
            $c.Properties | Should -Contain 'AccountExpirationDate'
            $c.Properties | Should -Contain 'whenCreated'
            $c.Properties | Should -Contain 'whenChanged'
            $c.Properties | Should -Contain 'MemberOf'
        }
    }
}

Describe 'Find-AdmanUser: HIGH-1 filter construction with Escape-AdmanAdFilterLiteral' -Tag 'Unit' {

    It 'builds -eq filter for -SamAccountName' {
        Invoke-FindUser -Params @{ SamAccountName = 'alice' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "sAMAccountName -eq 'alice'"
    }

    It 'builds -eq filter for -DisplayName' {
        Invoke-FindUser -Params @{ DisplayName = 'Alice A. InScope' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "DisplayName -eq 'Alice A. InScope'"
    }

    It 'builds -like filter for -Name (D-02 wildcard semantics)' {
        Invoke-FindUser -Params @{ Name = 'ali*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "Name -like 'ali*'"
    }

    It "doubles single quotes in -SamAccountName (O'Brien -> O''Brien)" {
        Invoke-FindUser -Params @{ SamAccountName = "O'Brien" } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "sAMAccountName -eq 'O''Brien'"
    }

    It "doubles single quotes in -DisplayName (O'Brien -> O''Brien)" {
        Invoke-FindUser -Params @{ DisplayName = "O'Brien" } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "DisplayName -eq 'O''Brien'"
    }

    It "doubles single quotes in -Name (O'Brien -> O''Brien)" {
        Invoke-FindUser -Params @{ Name = "O'Brien" } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "Name -like 'O''Brien'"
    }

    It 'doubles backslashes in user input' {
        Invoke-FindUser -Params @{ SamAccountName = 'CN=Doe\John' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be "sAMAccountName -eq 'CN=Doe\\John'"
    }

    It 'preserves wildcards in -Name for -like semantics (D-02)' {
        Invoke-FindUser -Params @{ Name = 'ali*' } | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Match '\*'
    }
}

Describe 'Find-AdmanUser: scope re-check drops out-of-scope objects (SAFE-07 step (c))' -Tag 'Unit' {

    It 'drops objects whose DN is outside every ManagedOUs root' {
        $results = @(Invoke-FindUser -Params @{ SamAccountName = 'alice' })
        # The mock returns 3 rows per call: 2 in-scope + 1 out-of-scope (OU=NotManaged).
        # With 2 ManagedOUs roots looped, we get 6 raw rows -> 4 in-scope after filtering.
        $results.Count | Should -Be 4
        foreach ($r in $results) {
            $r.DistinguishedName | Should -Not -Match 'OU=NotManaged'
        }
    }

    It 'returns objects with the D-03 schema (ObjectType=User)' {
        $results = @(Invoke-FindUser -Params @{ SamAccountName = 'alice' })
        $results.Count | Should -BeGreaterThan 0
        foreach ($r in $results) {
            $r.ObjectType | Should -Be 'User'
            $r.PSObject.Properties.Name | Should -Contain 'SamAccountName'
            $r.PSObject.Properties.Name | Should -Contain 'DistinguishedName'
            $r.PSObject.Properties.Name | Should -Contain 'ObjectSid'
            $r.PSObject.Properties.Name | Should -Contain 'ObjectGuid'
            $r.PSObject.Properties.Name | Should -Contain 'DisplayName'
            $r.PSObject.Properties.Name | Should -Contain 'UserPrincipalName'
            $r.PSObject.Properties.Name | Should -Contain 'LockedOut'
            $r.PSObject.Properties.Name | Should -Contain 'PasswordExpired'
            $r.PSObject.Properties.Name | Should -Contain 'PasswordLastSet'
            $r.PSObject.Properties.Name | Should -Contain 'AccountExpirationDate'
            $r.PSObject.Properties.Name | Should -Contain 'LastLogonDate'
            $r.PSObject.Properties.Name | Should -Contain 'whenCreated'
            $r.PSObject.Properties.Name | Should -Contain 'whenChanged'
        }
    }
}

Describe 'Find-AdmanUser: structural invariants (HIGH-1)' -Tag 'Unit' {

    It 'calls Escape-AdmanAdFilterLiteral at least once per parameter' {
        $content = Get-Content $script:FindUserPath -Raw
        # One call per parameter branch (Name, SamAccountName, DisplayName).
        $matches = [regex]::Matches($content, 'Escape-AdmanAdFilterLiteral')
        $matches.Count | Should -BeGreaterOrEqual 3
    }

    It 'NEVER calls Escape-AdmanLdapFilterValue (RFC4515 helper is for -LDAPFilter only)' {
        $content = Get-Content $script:FindUserPath -Raw
        $content | Should -Not -Match 'Escape-AdmanLdapFilterValue'
    }

    It 'NEVER calls Test-AdmanTargetAllowed (deny/protected checks are mutation-only)' {
        $content = Get-Content $script:FindUserPath -Raw
        $content | Should -Not -Match 'Test-AdmanTargetAllowed'
    }

    It 'calls Test-AdmanInManagedScope on every emitted object' {
        $content = Get-Content $script:FindUserPath -Raw
        $content | Should -Match 'Test-AdmanInManagedScope'
    }

    It 'is exported in adman.psd1 FunctionsToExport' {
        # Import-PowerShellDataFile is PS7+; parse the manifest directly for 5.1 compat.
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match "Find-AdmanUser"
        # Also verify the module actually exports it.
        (Get-Command -Module adman -Name 'Find-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
