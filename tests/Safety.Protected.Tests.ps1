#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) — SAFE-06 protected-account tests (gMSA objectClass pre-filter + recursive
    IN_CHAIN membership, never adminCount; RFC-4515 LDAP-filter escaping).

    Test-AdmanTargetAllowed must:
      * Run the gMSA/sMSA objectClass pre-filter FIRST (Reason contains 'objectClass') and
        CONTINUE (no early return) so a gMSA that is ALSO a nested protected-group member
        returns BOTH reasons (layered).
      * Refuse a nested member of a protected group via ONE DC-side IN_CHAIN
        (1.2.840.113556.1.4.1941) query bound to the TARGET via the -LDAPFilter parameter set
        ONLY (never the Identity parameter set on that call).
      * Escape every DN/value via Escape-AdmanLdapFilterValue before building the -LDAPFilter,
        so a special-char CN ( ( ) * \ ) cannot break the filter (fails closed, no throw).
      * NEVER read adminCount.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. All AD cmdlets
    mocked (-ModuleName adman); no live domain. Named binding into the module-scope scriptblock.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c6'
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
    $script:TargetAllowedPath = Join-Path $script:RepoRoot 'Private\Safety\Test-AdmanTargetAllowed.ps1'
    $script:EscapePath = Join-Path $script:RepoRoot 'Private\Safety\Escape-AdmanLdapFilterValue.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    function global:Get-ADObject { param($Identity, $Properties, $Server, $LDAPFilter) }
    function global:Get-ADGroup { param($Identity, $Properties, $Server) }
    function global:Get-ADDomain { param($Identity, $Server) }
    function global:Get-ADForest { param($Identity, $Server) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param(
            [string[]]$ManagedOUs = @('OU=Managed,DC=mock,DC=local'),
            [string]$DC = 'dc.mock.local'
        )
        [pscustomobject]@{
            ManagedOUs          = $ManagedOUs
            DC                  = $DC
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
        }
    }

    function Set-AdmanSafetyState {
        [CmdletBinding()]
        param($Config, $ProtectedGroupDns, $DenyRids)
        & (Get-Module adman) {
            param($Config, $ProtectedGroupDns, $DenyRids)
            $script:Config = $Config
            $script:ProtectedGroupDns = @($ProtectedGroupDns)
            $script:DenyRids = @($DenyRids)
        } -Config $Config -ProtectedGroupDns $ProtectedGroupDns -DenyRids $DenyRids
    }

    function New-AdmanTarget {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Dn,
            [string]$Sid = 'S-1-5-21-111-222-333-1000',
            [string[]]$ObjectClass = @('top', 'person', 'organizationalPerson', 'user')
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = $ObjectClass
            memberOf          = @()
        }
    }
}

Describe 'SAFE-06: protected-account detection (gMSA pre-filter + IN_CHAIN, never adminCount)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig) `
            -ProtectedGroupDns @('CN=Domain Admins,CN=Users,DC=mock,DC=local') `
            -DenyRids @('500', '501', '502')
    }

    It 'refuses a nested member of a protected group via ONE IN_CHAIN -LDAPFilter bound to the target' {
        # The recursive-membership Get-ADObject call must use -LDAPFilter (not -Identity) and
        # return a hit for a protected-group member.
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{ DistinguishedName = 'CN=NestedAdmin,OU=Managed,DC=mock,DC=local' }
        } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=NestedAdmin,OU=Managed,DC=mock,DC=local'
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target

        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'recursive member of protected group'
        Should -Invoke Get-ADObject -ModuleName adman -Times 1 -ParameterFilter {
            $LDAPFilter -and
            $LDAPFilter -match '1\.2\.840\.113556\.1\.4\.1941' -and
            $LDAPFilter -match [regex]::Escape('CN=NestedAdmin,OU=Managed,DC=mock,DC=local')
        } -Because 'the IN_CHAIN filter must contain the OID AND the target DN'
    }

    It 'the recursive-membership call uses the -LDAPFilter parameter set ONLY (never -Identity on that call)' {
        # AST assertion over the source: the Get-ADObject call that supplies -LDAPFilter must NOT
        # also supply -Identity (Identity and LDAPFilter are mutually exclusive parameter sets).
        Test-Path -LiteralPath $script:TargetAllowedPath | Should -BeTrue
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:TargetAllowedPath, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Get-ADObject' }, $true)
        $ldapCalls = @($calls | Where-Object {
            ($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'LDAPFilter' })
        })
        $ldapCalls.Count | Should -BeGreaterOrEqual 1 -Because 'the protected check must call Get-ADObject -LDAPFilter'
        foreach ($c in $ldapCalls) {
            $hasIdentity = @($c.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Identity'
            }).Count
            $hasIdentity | Should -Be 0 -Because 'Identity and LDAPFilter are mutually exclusive parameter sets (C2-H1)'
        }
    }

    It 'refuses a gMSA by objectClass even when NOT in any protected group (Reason contains objectClass)' {
        # gMSA pre-filter matches; IN_CHAIN returns $null (not nested). Still refused via objectClass.
        Mock Get-ADObject -ModuleName adman { $null } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=svc-gmsa,OU=Managed,DC=mock,DC=local' `
            -ObjectClass @('top', 'msDS-GroupManagedServiceAccount')
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target

        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'objectClass'
    }

    It 'refuses a legacy sMSA (msDS-ManagedServiceAccount) by objectClass' {
        Mock Get-ADObject -ModuleName adman { $null } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=svc-legacy,OU=Managed,DC=mock,DC=local' `
            -ObjectClass @('top', 'msDS-ManagedServiceAccount')
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target

        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'objectClass'
    }

    It 'gMSA pre-filter does NOT early-return: the IN_CHAIN query STILL runs afterward (layering)' {
        # Even when the gMSA pre-filter matches, the IN_CHAIN Get-ADObject call must still be invoked.
        Mock Get-ADObject -ModuleName adman { $null } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=svc-gmsa,OU=Managed,DC=mock,DC=local' `
            -ObjectClass @('top', 'msDS-GroupManagedServiceAccount')
        $null = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target

        Should -Invoke Get-ADObject -ModuleName adman -Times 1 -ParameterFilter { $LDAPFilter } `
            -Because 'the IN_CHAIN layering check must run even after a gMSA objectClass hit (no early return)'
    }

    It 'a gMSA that is ALSO a nested protected-group member returns BOTH reasons (layered)' {
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{ DistinguishedName = 'CN=svc-gmsa,OU=Managed,DC=mock,DC=local' }
        } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=svc-gmsa,OU=Managed,DC=mock,DC=local' `
            -ObjectClass @('top', 'msDS-GroupManagedServiceAccount')
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target

        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'objectClass'
        $decision.Reason | Should -Match 'recursive member'
    }

    It 'a special-char CN ( ( ) * \ ) is RFC-4515-escaped and does NOT throw a malformed-filter error' {
        # The target DN contains LDAP-filter metacharacters; escaping must keep the query safe.
        Mock Get-ADObject -ModuleName adman { $null } -ParameterFilter { $LDAPFilter }

        $target = New-AdmanTarget -Dn 'CN=Weird (Name) *star* \back,OU=Managed,DC=mock,DC=local'
        { & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target } |
            Should -Not -Throw -Because 'RFC-4515 escaping must prevent a malformed-filter error (C2-L1)'
    }

    It 'Escape-AdmanLdapFilterValue maps \ * ( ) NUL to \5c \2a \28 \29 \00' {
        Test-Path -LiteralPath $script:EscapePath | Should -BeTrue
        $esc = & (Get-Module adman) { param($v) Escape-AdmanLdapFilterValue -Value $v } -v "a\b*c(d)e"
        $esc | Should -Be 'a\5cb\2ac\28d\29e'
        $escNul = & (Get-Module adman) { param($v) Escape-AdmanLdapFilterValue -Value $v } -v ("x" + [char]0 + "y")
        $escNul | Should -Be 'x\00y'
    }

    It 'static: IN_CHAIN OID present; gMSA classes present; adminCount NEVER read; Escape helper used on DN/group values' {
        Test-Path -LiteralPath $script:TargetAllowedPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:TargetAllowedPath -Raw
        @($src | Select-String -Pattern '1\.2\.840\.113556\.1\.4\.1941').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'msDS-GroupManagedServiceAccount').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'msDS-ManagedServiceAccount').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'adminCount').Count | Should -Be 0 -Because 'adminCount is never a trustworthy signal (D-02)'
        @($src | Select-String -Pattern 'Escape-AdmanLdapFilterValue').Count | Should -BeGreaterOrEqual 1 `
            -Because 'DN/group values must be RFC-4515-escaped before the IN_CHAIN -LDAPFilter (C2-L1)'
    }
}
