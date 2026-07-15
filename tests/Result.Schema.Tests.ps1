#Requires -Modules Pester
<#
.SYNOPSIS
    D-03 schema contract tests for ConvertTo-AdmanResult + scope tests for Test-AdmanInManagedScope.

.DESCRIPTION
    Pins the D-03 result-object schema:
      * Fixed identity/scope columns always present (both types): ObjectType, Name,
        SamAccountName, Enabled, DistinguishedName, ObjectSid, ObjectGuid.
      * User-only nullable extras: DisplayName, UserPrincipalName, LockedOut, PasswordExpired,
        PasswordLastSet, AccountExpirationDate.
      * Computer-only nullable extras: OperatingSystem, OperatingSystemVersion,
        OperatingSystemServicePack, IPv4Address, DNSHostName.
      * Shared nullable timestamps: LastLogonDate, whenCreated, whenChanged.
      * All timestamp cells are [datetime] or $null.
      * No raw AD object properties leak beyond the schema.

    Also pins Test-AdmanInManagedScope behavior:
      * Returns $true for DNs under a configured ManagedOUs root.
      * Returns $true for the root itself.
      * Returns $false for out-of-scope DNs (sibling OU, parent domain, unrelated tree).
      * Component-boundary anchored (a sibling whose DN merely CONTAINS the root string is rejected).
      * Calls the shared ConvertTo-AdmanNormalizedDn (no logic duplication, MEDIUM-3).
      * Does NOT call Test-AdmanTargetAllowed (scope-only check; deny/protected are mutation-only).

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:MapperPath = Join-Path $script:RepoRoot 'Private/Reporting/ConvertTo-AdmanResult.ps1'
    $script:ScopePath = Join-Path $script:RepoRoot 'Private/Reporting/Test-AdmanInManagedScope.ps1'
    $script:NormPath = Join-Path $script:RepoRoot 'Private/Utility/ConvertTo-AdmanNormalizedDn.ps1'
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000cb'
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

    # Seed $script:Config.ManagedOUs so Test-AdmanInManagedScope has roots to check.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local', 'OU=Subsidiary,DC=mock,DC=local')
            DC         = 'dc.mock.local'
        }
    }

    # Helpers to invoke module-private functions from the test scope.
    # Uses the & (Get-Module adman) { ... } -Arg pattern (same as Audit.FailClosed tests).
    # We pass the hashtable as a single positional arg, then splat it inside the scriptblock.
    function script:Invoke-AdmanPrivate {
        param([string]$Name, [hashtable]$Params = @{})
        $mod = Get-Module adman
        # Bind the scriptblock to the module's session state, then call with named args so
        # the hashtable survives the boundary without being unrolled.
        $boundSb = $mod.NewBoundScriptBlock({
            param($n, [hashtable]$h)
            & $n @h
        })
        & $boundSb -n $Name -h $Params
    }

    # Build a fake raw AD user row (mimics the shape returned by Get-ADUser with the D-02
    # Properties list). Extra raw-only properties (MemberOf, objectClass, PropertyNames)
    # are present to prove the mapper drops them.
    function script:New-RawAdUser {
        [pscustomobject]@{
            Name                  = 'Alice InScope'
            SamAccountName        = 'alice.inscope'
            Enabled               = $true
            DistinguishedName     = 'CN=Alice InScope,OU=Managed,DC=mock,DC=local'
            ObjectSid             = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1001'
            ObjectGuid            = [guid]'11111111-2222-3333-4444-555555555555'
            DisplayName           = 'Alice A. InScope'
            UserPrincipalName     = 'alice.inscope@mock.local'
            LockedOut             = $false
            PasswordExpired       = $false
            PasswordLastSet       = [datetime]'2026-01-15T00:00:00Z'
            AccountExpirationDate = $null
            LastLogonDate         = [datetime]'2026-07-01T00:00:00Z'
            whenCreated           = [datetime]'2025-01-01T00:00:00Z'
            whenChanged           = [datetime]'2026-06-01T00:00:00Z'
            # Raw-only properties that MUST NOT leak into the schema:
            MemberOf              = @('CN=Group1,OU=Groups,DC=mock,DC=local')
            objectClass           = @('top', 'person', 'organizationalPerson', 'user')
            PropertyNames         = @('Name', 'SamAccountName')
        }
    }

    function script:New-RawAdComputer {
        [pscustomobject]@{
            Name                       = 'PC-INSCOPE-01'
            SamAccountName             = 'PC-INSCOPE-01$'
            Enabled                    = $true
            DistinguishedName          = 'CN=PC-INSCOPE-01,OU=Managed,DC=mock,DC=local'
            ObjectSid                  = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-2001'
            ObjectGuid                 = [guid]'22222222-3333-4444-5555-666666666666'
            OperatingSystem            = 'Windows 11 Pro'
            OperatingSystemVersion     = '10.0 (26200)'
            OperatingSystemServicePack = ''
            IPv4Address                = '10.0.0.10'
            DNSHostName                = 'pc-inscope-01.mock.local'
            LastLogonDate              = [datetime]'2026-07-01T00:00:00Z'
            whenCreated                = [datetime]'2025-01-01T00:00:00Z'
            whenChanged                = [datetime]'2026-06-01T00:00:00Z'
            MemberOf                   = @()
            objectClass                = @('top', 'person', 'organizationalPerson', 'user', 'computer')
        }
    }
}

Describe 'D-03 schema: User result object' -Tag 'Unit' {

    It 'emits exactly the D-03 user property set' {
        $raw = New-RawAdUser
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'User' }
        $expected = @(
            'ObjectType', 'Name', 'SamAccountName', 'Enabled', 'DistinguishedName', 'ObjectSid', 'ObjectGuid',
            'DisplayName', 'UserPrincipalName', 'LockedOut', 'PasswordExpired', 'PasswordLastSet', 'AccountExpirationDate',
            'LastLogonDate', 'whenCreated', 'whenChanged'
        )
        $actual = @($result.PSObject.Properties.Name)
        ($actual | Sort-Object) | Should -Be ($expected | Sort-Object)
    }

    It 'pins ObjectType to User' {
        $raw = New-RawAdUser
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'User' }
        $result.ObjectType | Should -Be 'User'
    }

    It 'emits all timestamp cells as [datetime] or $null' {
        $raw = New-RawAdUser
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'User' }
        foreach ($prop in 'LastLogonDate', 'whenCreated', 'whenChanged', 'PasswordLastSet', 'AccountExpirationDate') {
            $v = $result.$prop
            if ($null -ne $v) { $v | Should -BeOfType [datetime] }
        }
    }

    It 'does NOT leak raw AD properties beyond the schema' {
        $raw = New-RawAdUser
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'User' }
        $result.PSObject.Properties.Name | Should -Not -Contain 'MemberOf'
        $result.PSObject.Properties.Name | Should -Not -Contain 'objectClass'
        $result.PSObject.Properties.Name | Should -Not -Contain 'PropertyNames'
    }

    It 'leaves missing user-only cells as $null (no throw under StrictMode)' {
        $raw = [pscustomobject]@{
            Name              = 'Sparse'
            SamAccountName    = 'sparse'
            Enabled           = $true
            DistinguishedName = 'CN=Sparse,OU=Managed,DC=mock,DC=local'
            ObjectSid         = $null
            ObjectGuid        = $null
        }
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'User' }
        $result.DisplayName | Should -BeNullOrEmpty
        $result.UserPrincipalName | Should -BeNullOrEmpty
        $result.PasswordLastSet | Should -BeNullOrEmpty
        $result.AccountExpirationDate | Should -BeNullOrEmpty
        $result.LastLogonDate | Should -BeNullOrEmpty
    }
}

Describe 'D-03 schema: Computer result object' -Tag 'Unit' {

    It 'emits exactly the D-03 computer property set' {
        $raw = New-RawAdComputer
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'Computer' }
        $expected = @(
            'ObjectType', 'Name', 'SamAccountName', 'Enabled', 'DistinguishedName', 'ObjectSid', 'ObjectGuid',
            'OperatingSystem', 'OperatingSystemVersion', 'OperatingSystemServicePack', 'IPv4Address', 'DNSHostName',
            'LastLogonDate', 'whenCreated', 'whenChanged'
        )
        $actual = @($result.PSObject.Properties.Name)
        ($actual | Sort-Object) | Should -Be ($expected | Sort-Object)
    }

    It 'pins ObjectType to Computer' {
        $raw = New-RawAdComputer
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'Computer' }
        $result.ObjectType | Should -Be 'Computer'
    }

    It 'emits all timestamp cells as [datetime] or $null' {
        $raw = New-RawAdComputer
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'Computer' }
        foreach ($prop in 'LastLogonDate', 'whenCreated', 'whenChanged') {
            $v = $result.$prop
            if ($null -ne $v) { $v | Should -BeOfType [datetime] }
        }
    }

    It 'does NOT leak raw AD properties beyond the schema' {
        $raw = New-RawAdComputer
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'Computer' }
        $result.PSObject.Properties.Name | Should -Not -Contain 'MemberOf'
        $result.PSObject.Properties.Name | Should -Not -Contain 'objectClass'
    }

    It 'does NOT include user-only columns on a Computer result' {
        $raw = New-RawAdComputer
        $result = Invoke-AdmanPrivate -Name 'ConvertTo-AdmanResult' -Params @{ ADObject = $raw; ObjectType = 'Computer' }
        $result.PSObject.Properties.Name | Should -Not -Contain 'DisplayName'
        $result.PSObject.Properties.Name | Should -Not -Contain 'UserPrincipalName'
        $result.PSObject.Properties.Name | Should -Not -Contain 'LockedOut'
        $result.PSObject.Properties.Name | Should -Not -Contain 'PasswordExpired'
    }
}

Describe 'Test-AdmanInManagedScope: scope-only boundary check' -Tag 'Unit' {

    It 'returns $true for a DN directly under a ManagedOUs root' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
        } | Should -BeTrue
    }

    It 'returns $true for a DN in a nested OU under a ManagedOUs root' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Bob,OU=Sub,OU=Managed,DC=mock,DC=local'
        } | Should -BeTrue
    }

    It 'returns $true for the ManagedOUs root itself' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'OU=Managed,DC=mock,DC=local'
        } | Should -BeTrue
    }

    It 'returns $true for a DN under the SECOND configured root' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Carol,OU=Subsidiary,DC=mock,DC=local'
        } | Should -BeTrue
    }

    It 'returns $false for a sibling OU outside any ManagedOUs root' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Dave,OU=NotManaged,DC=mock,DC=local'
        } | Should -BeFalse
    }

    It 'returns $false for the domain root itself' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'DC=mock,DC=local'
        } | Should -BeFalse
    }

    It 'returns $false for an unrelated tree' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Eve,OU=Managed,DC=other,DC=example'
        } | Should -BeFalse
    }

    It 'is component-boundary anchored (substring match alone is NOT sufficient)' {
        # 'OU=ManagedExtra' contains 'OU=Managed' as a substring but is a different component.
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Frank,OU=ManagedExtra,DC=mock,DC=local'
        } | Should -BeFalse
    }

    It 'handles escaped commas in the leaf CN without breaking the boundary check' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{
            DistinguishedName = 'CN=Doe\, John,OU=Managed,DC=mock,DC=local'
        } | Should -BeTrue
    }

    It 'returns $false for empty/null DN' {
        Invoke-AdmanPrivate -Name 'Test-AdmanInManagedScope' -Params @{ DistinguishedName = '' } | Should -BeFalse
    }
}

Describe 'Test-AdmanInManagedScope: structural invariants' -Tag 'Unit' {

    It 'calls the shared ConvertTo-AdmanNormalizedDn (MEDIUM-3, no logic duplication)' {
        $content = Get-Content $script:ScopePath -Raw
        $content | Should -Match 'ConvertTo-AdmanNormalizedDn'
    }

    It 'does NOT redefine ConvertTo-AdmanNormalizedDn locally' {
        $content = Get-Content $script:ScopePath -Raw
        $content | Should -Not -Match 'function\s+ConvertTo-AdmanNormalizedDn'
    }

    It 'does NOT call Test-AdmanTargetAllowed (scope-only check; deny/protected are mutation-only)' {
        $content = Get-Content $script:ScopePath -Raw
        $content | Should -Not -Match 'Test-AdmanTargetAllowed'
    }

    It 'does NOT reference the deny-list or protected-group state' {
        $content = Get-Content $script:ScopePath -Raw
        $content | Should -Not -Match 'DenyRids'
        $content | Should -Not -Match 'ProtectedGroupDns'
    }
}
