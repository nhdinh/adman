#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) — SAFE-07 managed-OU scope tests (component-boundary DN suffix).

    Test-AdmanTargetAllowed must accept a target only when its canonical DN equals a managed
    root OR ends with ','+root (component-boundary anchored). A substring `-like "*root*"` is
    NEVER used (T-00-02 landmine). To isolate scope, the gMSA/deny/protected branches are
    neutralized: objectClass=user, RID=1000 (not in DenyRids), and the IN_CHAIN Get-ADObject
    call is mocked to $null (not a protected-group member).

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
    $script:TargetAllowedPath = Join-Path $script:RepoRoot 'Private\Safety\Test-AdmanTargetAllowed.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds AD cmdlets when RSAT is absent.
    function global:Get-ADObject { param($Identity, $Properties, $Server, $LDAPFilter) }
    function global:Get-ADGroup { param($Identity, $Properties, $Server) }
    function global:Get-ADDomain { param($Identity, $Server) }
    function global:Get-ADForest { param($Identity, $Server) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param(
            [string[]]$ManagedOUs = @('OU=Managed,DC=mock,DC=local'),
            [string]$DC = 'dc.mock.local',
            [int]$BulkConfirmThreshold = 5,
            [int]$BulkMaxCount = 50
        )
        [pscustomobject]@{
            ManagedOUs          = $ManagedOUs
            DC                  = $DC
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = $BulkConfirmThreshold }
            bulk                = [pscustomobject]@{ maxCount = $BulkMaxCount }
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

Describe 'SAFE-07: managed-OU scope is component-boundary anchored' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig) `
            -ProtectedGroupDns @('CN=Domain Admins,CN=Users,DC=mock,DC=local') `
            -DenyRids @('500', '501', '502')
        # Neutralize the protected (IN_CHAIN) branch: not a member of any protected group.
        Mock Get-ADObject -ModuleName adman { $null }
    }

    It 'accepts an in-scope DN: <Name>' -TestCases @(
        @{ Name = 'root itself'; Dn = 'OU=Managed,DC=mock,DC=local' }
        @{ Name = 'direct child user'; Dn = 'CN=Jane Doe,OU=Managed,DC=mock,DC=local' }
        @{ Name = 'deeper child OU'; Dn = 'OU=Sub,OU=Managed,DC=mock,DC=local' }
        @{ Name = 'case-different root'; Dn = 'ou=managed,dc=mock,dc=local' }
        @{ Name = 'case-different child'; Dn = 'CN=Jane,ou=managed,DC=MOCK,DC=LOCAL' }
        @{ Name = 'escaped comma in leaf CN'; Dn = 'CN=Smith\, John,OU=Managed,DC=mock,DC=local' }
        @{ Name = 'spacious root normalized'; Dn = 'CN=Jane, OU=Managed, DC=mock, DC=local' }
    ) {
        param($Name, $Dn)
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t (New-AdmanTarget -Dn $Dn)
        $decision.Allowed | Should -BeTrue -Because "$Name is inside the managed root (Reason='$($decision.Reason)')"
    }

    It 'refuses an out-of-scope / substring-spoof DN: <Name>' -TestCases @(
        @{ Name = 'same-prefix sibling (ManagedX)'; Dn = 'OU=ManagedX,DC=mock,DC=local' }
        @{ Name = 'plain sibling OU'; Dn = 'OU=NotManaged,DC=mock,DC=local' }
        @{ Name = 'different domain component'; Dn = 'OU=Managed,DC=evil,DC=local' }
        @{ Name = 'leaf CN literally named OU=Managed at domain root'; Dn = 'CN=OU=Managed,DC=mock,DC=local' }
        @{ Name = 'deep under a sibling'; Dn = 'CN=x,OU=Sub,OU=NotManaged,DC=mock,DC=local' }
        @{ Name = 'root value embedded in an unrelated RDN'; Dn = 'CN=OU=Managed\,DC=mock\,DC=local,DC=other,DC=local' }
    ) {
        param($Name, $Dn)
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t (New-AdmanTarget -Dn $Dn)
        $decision.Allowed | Should -BeFalse -Because "$Name must NOT be treated as in-scope"
        $decision.Reason | Should -Match 'outside managed-OU scope'
    }

    It 'static: scope check is EndsWith('','' + $root) anchored; never a substring -like "*"' {
        Test-Path -LiteralPath $script:TargetAllowedPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:TargetAllowedPath -Raw
        @($src | Select-String -Pattern 'EndsWith\(').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern '\-like\s+"?\*').Count | Should -Be 0 -Because 'a substring -like "*" match is spoofable (T-00-02)'
    }
}
