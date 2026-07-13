#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) — SAFE-05 deny-list tests (match by objectSid/RID, never sAMAccountName).

    Test-AdmanTargetAllowed must REFUSE a target whose objectSid RID is in $script:DenyRids
    (500/501/502), with a Reason containing 'deny-listed'. A renamed built-in Administrator
    (RID-500, arbitrary sAMAccountName) is still refused because matching is by RID, never by
    name (T-00-08). To isolate the deny branch: objectClass=user (not gMSA), DN in-scope, and
    the IN_CHAIN Get-ADObject call is mocked to $null (not a protected-group member).

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
    GUID              = 'b0000000-0000-0000-0000-0000000000c5'
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
            [string]$Sam = 'some.user',
            [string[]]$ObjectClass = @('top', 'person', 'organizationalPerson', 'user')
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = $ObjectClass
            sAMAccountName    = $Sam
            memberOf          = @()
        }
    }
}

Describe 'SAFE-05: deny-list matches by objectSid/RID, never sAMAccountName' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig) `
            -ProtectedGroupDns @('CN=Domain Admins,CN=Users,DC=mock,DC=local') `
            -DenyRids @('500', '501', '502')
        # Neutralize the protected (IN_CHAIN) branch: not a member of any protected group.
        Mock Get-ADObject -ModuleName adman { $null }
    }

    It 'refuses a deny-listed RID: <Name>' -TestCases @(
        @{ Name = 'RID-500 built-in Administrator'; Sid = 'S-1-5-21-111-222-333-500'; Sam = 'Administrator' }
        @{ Name = 'RID-501 Guest'; Sid = 'S-1-5-21-111-222-333-501'; Sam = 'Guest' }
        @{ Name = 'RID-502 krbtgt'; Sid = 'S-1-5-21-111-222-333-502'; Sam = 'krbtgt' }
    ) {
        param($Name, $Sid, $Sam)
        $target = New-AdmanTarget -Dn 'CN=X,OU=Managed,DC=mock,DC=local' -Sid $Sid -Sam $Sam
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target
        $decision.Allowed | Should -BeFalse -Because "$Name is deny-listed"
        $decision.Reason | Should -Match 'deny-listed'
    }

    It 'refuses a RENAMED built-in Administrator (RID-500, arbitrary sAMAccountName)' {
        # RID-500 is routinely renamed via GPO; matching by name would miss it. Match by RID.
        $target = New-AdmanTarget -Dn 'CN=RenamedAdmin,OU=Managed,DC=mock,DC=local' `
            -Sid 'S-1-5-21-111-222-333-500' -Sam 'totally-not-admin'
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target
        $decision.Allowed | Should -BeFalse -Because 'a renamed RID-500 is still deny-listed (T-00-08)'
        $decision.Reason | Should -Match 'deny-listed'
    }

    It 'allows a non-deny-listed RID (1000)' {
        $target = New-AdmanTarget -Dn 'CN=Jane,OU=Managed,DC=mock,DC=local' `
            -Sid 'S-1-5-21-111-222-333-1000' -Sam 'jane'
        $decision = & (Get-Module adman) { param($t) Test-AdmanTargetAllowed -Object $t } -t $target
        $decision.Allowed | Should -BeTrue -Because 'RID 1000 is not in the deny-list (Reason='' + $decision.Reason + '')'
    }

    It 'static: deny matches by RID via Split(''-'')[-1]; never reads sAMAccountName' {
        Test-Path -LiteralPath $script:TargetAllowedPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:TargetAllowedPath -Raw
        @($src | Select-String -Pattern "Split\('-'\)\[-1\]").Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'sAMAccountName').Count | Should -Be 0 -Because 'deny-list must match by RID, never by name (D-05)'
    }
}
