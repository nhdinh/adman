#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED/GREEN) capability-probe + startup SID/deny-resolution tests (MENU-05, D-02/D-05).
    Covers behavior Tests 1-5:
      * Test 1 (probe flags): Test-AdmanCapability returns RsatPresent/DomainReachable/
        AuditWritable/RecycleBinEnabled (+ rights/transport hints); RSAT probe uses
        Get-Module -ListAvailable ActiveDirectory.
      * Test 2 (no real write for rights): rights probed via a managed-OU read + whoami /groups;
        NEVER a Set-AD*/Disable-AD*/New-AD* call.
      * Test 3 (fail-closed): empty ManagedOUs => throw 'managed-OU'; AuditWritable=$false =>
        throw 'audit'; both terminating.
      * Test 4 (no hang): short timeout (OperationTimeoutSec / constant <= 30s) on the transport
        probe; domain/transport errors are caught into flags, never thrown (except the two
        fail-closed throws).
      * Test 5 (protected-SID resolution, D-02): Get-AdmanProtectedIdentity builds
        $script:ProtectedGroupDns from DomainSID-512 / forest-root-518/519 + S-1-5-32-544/-548/
        -551/-549 (+525) + AdmanProtectedGroup, and $script:DenyRids = {500,501,502}; it calls
        Get-ADDomain/Get-ADForest (mocked) and never hard-codes a domain SID (D-05/A3).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. $script:StorePath
    pointed at a per-test temp dir. All AD/CIM/remoting cmdlets are mocked (-ModuleName adman) -
    no live domain, no network. Named binding is used into the module-scope scriptblock (PS 5.1
    positional -ArgumentList does not bind object args).
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c3'
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
    $script:CapPath = Join-Path $script:RepoRoot 'Public\Test-AdmanCapability.ps1'
    $script:ProtPath = Join-Path $script:RepoRoot 'Private\Safety\Get-AdmanProtectedIdentity.ps1'
    $script:SidPath = Join-Path $script:RepoRoot 'Private\Foundation\Resolve-AdmanDomainSid.ps1'
    $script:AuditProbePath = Join-Path $script:RepoRoot 'Private\Foundation\Test-AdmanAuditWritable.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Test-scope stubs (global:) so Pester's Mock resolver (Get-Command) finds commands that are
    # not resolvable on this host: RSAT AD cmdlets (Get-AD*/Set-AD*/...) when RSAT is absent, and
    # the module-private probe/resolver functions that only exist at GREEN. Inert fallbacks; the
    # real module-private/public functions shadow them at GREEN. Live only in the test process.
    function global:Get-ADDomain { param($Identity, $Server) }
    function global:Get-ADForest { param($Identity, $Server) }
    function global:Get-ADGroup { param($Identity, $Properties, $Server) }
    function global:Get-ADOrganizationalUnit { param($Identity, $Filter, $Server) }
    function global:Get-ADOptionalFeature { param($Identity, $Filter, $Server) }
    function global:Set-ADUser { param($Identity) }
    function global:Set-ADComputer { param($Identity) }
    function global:Disable-ADAccount { param($Identity) }
    function global:Enable-ADAccount { param($Identity) }
    function global:New-ADUser { param($Name) }
    function global:Move-ADObject { param($Identity, $TargetPath) }
    function global:Test-AdmanAuditWritable { }
    # NOTE: Test-AdmanCapability and Get-AdmanProtectedIdentity are intentionally NOT stubbed here -
    # at RED their call sites fail (right reason); at GREEN the real functions answer.

    function New-AdmanCapConfig {
        [CmdletBinding()]
        param(
            [string[]]$ManagedOUs = @('OU=Managed,DC=mock,DC=local'),
            [string]$DC = 'dc.mock.local',
            [string]$AuditDir = '.store/audit',
            [string]$Delegated = '',
            [string]$AdmanProtectedGroup = 'CN=Adman-Protected,OU=Groups,DC=mock,DC=local',
            $DenyList = @(
                @{ token = '500'; note = 'starter, not exhaustive' },
                @{ token = '501'; note = 'starter, not exhaustive' },
                @{ token = '502'; note = 'starter, not exhaustive' }
            )
        )
        [pscustomobject]@{
            ManagedOUs          = $ManagedOUs
            DC                  = $DC
            AuditDir            = $AuditDir
            ReportDir           = 'reports'
            delegatedAdminGroup = $Delegated
            AdmanProtectedGroup = $AdmanProtectedGroup
            DenyList            = $DenyList
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            transport           = [pscustomobject]@{
                order    = @('WinRM', 'CimWsman', 'CimDcom', 'Skip')
                timeouts = [pscustomobject]@{ WinRM = 15; CIM = 20 }
            }
        }
    }

    function Set-AdmanCapState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]$Config,
            [Parameter(Mandatory)][string]$Store,
            [switch]$ClearSids
        )
        & (Get-Module adman) {
            param($Config, $Store, $ClearSids)
            $script:Config = $Config
            $script:StorePath = $Store
            if ($ClearSids) {
                Remove-Variable -Name DomainSid, ForestRootSid -Scope Script -ErrorAction SilentlyContinue
            }
        } -Config $Config -Store $Store -ClearSids:$ClearSids
    }

    $script:MockSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333'
}

Describe 'Test-AdmanCapability probe + startup SID/deny resolution (MENU-05, D-02/D-05)' -Tag 'Unit' {

    It 'Test 1: returns capability flags; RSAT probe uses Get-Module -ListAvailable ActiveDirectory' {
        $store = Join-Path $TestDrive 'cap1'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig -AuditDir (Join-Path $store 'audit')) -Store $store

        Mock Get-Module -ModuleName adman { [pscustomobject]@{ Name = 'ActiveDirectory'; Version = '1.0.0' } } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' }
        Mock Get-ADDomain -ModuleName adman { [pscustomobject]@{ DomainSID = $script:MockSid; DNSRoot = 'mock.local' } }
        Mock Test-AdmanAuditWritable -ModuleName adman { $true }
        Mock Get-ADOptionalFeature -ModuleName adman { [pscustomobject]@{ Name = 'Recycle Bin Feature'; EnabledScopes = @(1) } }
        Mock Get-ADOrganizationalUnit -ModuleName adman { [pscustomobject]@{ DistinguishedName = 'OU=Managed,DC=mock,DC=local' } }
        Mock Test-WSMan -ModuleName adman { $true }

        $cap = & (Get-Module adman) { Test-AdmanCapability }

        $cap.RsatPresent | Should -BeTrue
        $cap.DomainReachable | Should -BeTrue
        $cap.AuditWritable | Should -BeTrue
        $cap.RecycleBinEnabled | Should -BeTrue
        Should -Invoke Get-Module -ModuleName adman -Times 1 -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' }
    }

    It 'Test 2: rights are probed by reading the managed OU - NEVER an AD write cmdlet' {
        $store = Join-Path $TestDrive 'cap2'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig -AuditDir (Join-Path $store 'audit')) -Store $store

        Mock Get-Module -ModuleName adman { [pscustomobject]@{ Name = 'ActiveDirectory' } } -ParameterFilter { $ListAvailable }
        Mock Get-ADDomain -ModuleName adman { [pscustomobject]@{ DomainSID = $script:MockSid } }
        Mock Test-AdmanAuditWritable -ModuleName adman { $true }
        Mock Get-ADOptionalFeature -ModuleName adman { [pscustomobject]@{ EnabledScopes = @(1) } }
        Mock Get-ADOrganizationalUnit -ModuleName adman { [pscustomobject]@{ DistinguishedName = 'OU=Managed,DC=mock,DC=local' } }
        Mock Test-WSMan -ModuleName adman { $true }
        Mock Set-ADUser -ModuleName adman { }
        Mock Set-ADComputer -ModuleName adman { }
        Mock Disable-ADAccount -ModuleName adman { }
        Mock Enable-ADAccount -ModuleName adman { }
        Mock New-ADUser -ModuleName adman { }
        Mock Move-ADObject -ModuleName adman { }

        $null = & (Get-Module adman) { Test-AdmanCapability }

        Should -Invoke Get-ADOrganizationalUnit -ModuleName adman -Times 1 -Because 'rights are read from the managed OU'
        Should -Invoke Set-ADUser -ModuleName adman -Times 0 -Because 'the rights probe must never write'
        Should -Invoke Disable-ADAccount -ModuleName adman -Times 0
        Should -Invoke New-ADUser -ModuleName adman -Times 0
        Should -Invoke Move-ADObject -ModuleName adman -Times 0
    }

    It 'Test 2 (static): Public/Test-AdmanCapability.ps1 contains no AD write cmdlet name' {
        Test-Path -LiteralPath $script:CapPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:CapPath -Raw
        @($src | Select-String -Pattern 'Set-AD|Disable-AD|Enable-AD|New-AD|Move-ADObject|Remove-AD').Count | Should -Be 0
    }

    It 'Test 3a: empty ManagedOUs throws fail-closed mentioning managed-OU' {
        $store = Join-Path $TestDrive 'cap3a'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig -ManagedOUs @() -AuditDir (Join-Path $store 'audit')) -Store $store

        Mock Get-Module -ModuleName adman { $null } -ParameterFilter { $ListAvailable }
        Mock Test-AdmanAuditWritable -ModuleName adman { $true }

        { & (Get-Module adman) { Test-AdmanCapability } } | Should -Throw -ExpectedMessage '*managed-OU*'
    }

    It 'Test 3b: AuditWritable=$false throws fail-closed mentioning audit' {
        $store = Join-Path $TestDrive 'cap3b'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig -AuditDir (Join-Path $store 'audit')) -Store $store

        Mock Get-Module -ModuleName adman { [pscustomobject]@{ Name = 'ActiveDirectory' } } -ParameterFilter { $ListAvailable }
        Mock Get-ADDomain -ModuleName adman { [pscustomobject]@{ DomainSID = $script:MockSid } }
        Mock Test-AdmanAuditWritable -ModuleName adman { $false }
        Mock Get-ADOptionalFeature -ModuleName adman { [pscustomobject]@{ EnabledScopes = @(1) } }
        Mock Get-ADOrganizationalUnit -ModuleName adman { [pscustomobject]@{ DistinguishedName = 'OU=Managed,DC=mock,DC=local' } }
        Mock Test-WSMan -ModuleName adman { $true }

        { & (Get-Module adman) { Test-AdmanCapability } } | Should -Throw -ExpectedMessage '*audit*'
    }

    It 'Test 4: domain/transport probe failures are caught into flags (no throw); source declares a short timeout <= 30s' {
        $store = Join-Path $TestDrive 'cap4'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig -AuditDir (Join-Path $store 'audit')) -Store $store

        Mock Get-Module -ModuleName adman { [pscustomobject]@{ Name = 'ActiveDirectory' } } -ParameterFilter { $ListAvailable }
        Mock Get-ADDomain -ModuleName adman { throw 'ADWS unreachable' }
        Mock Test-AdmanAuditWritable -ModuleName adman { $true }
        Mock Get-ADOptionalFeature -ModuleName adman { [pscustomobject]@{ EnabledScopes = @(1) } }
        Mock Get-ADOrganizationalUnit -ModuleName adman { [pscustomobject]@{ DistinguishedName = 'OU=Managed,DC=mock,DC=local' } }
        Mock Test-WSMan -ModuleName adman { throw 'WinRM refused' }
        Mock Test-AdmanCimSessionTimeout -ModuleName adman { $false }

        $cap = $null
        { $cap = & (Get-Module adman) { Test-AdmanCapability } } | Should -Not -Throw -Because 'probe failures must become flags, never throw (fail-closed throws excepted)'
        $cap.DomainReachable | Should -BeFalse -Because 'an unreachable domain is a flag, not a terminating error'

        Test-Path -LiteralPath $script:CapPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:CapPath -Raw
        $src | Should -Match '(?i)Test-AdmanWsmanTimeout' -Because 'the WinRM probe uses the hard-timeout wrapper'
        $src | Should -Match '(?i)Test-AdmanCimSessionTimeout' -Because 'the CIM/DCOM fallback uses the hard-timeout wrapper'
        $src | Should -Match '(?i)probeTimeoutSec\s*=\s*(1[0-5]|[1-9])\b' -Because 'the probe timeout is short (<= 30s) so the menu never hangs'
    }

    It 'Test 5: Get-AdmanProtectedIdentity resolves protected SIDs + deny RIDs from the live domain SID (D-02/D-05/A3)' {
        $store = Join-Path $TestDrive 'cap5'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCapState -Config (New-AdmanCapConfig) -Store $store -ClearSids

        Mock Get-ADDomain -ModuleName adman { [pscustomobject]@{ DomainSID = $script:MockSid; DNSRoot = 'mock.local' } }
        Mock Get-ADForest -ModuleName adman { [pscustomobject]@{ RootDomain = 'mock.local'; Name = 'mock.local' } }
        Mock Get-ADGroup -ModuleName adman {
            param($Identity)
            [pscustomobject]@{ DistinguishedName = "CN=Group-$Identity,OU=Groups,DC=mock,DC=local" }
        }

        $res = & (Get-Module adman) { Get-AdmanProtectedIdentity }

        $res.ProtectedGroupDns | Should -Not -BeNullOrEmpty
        ($res.ProtectedGroupDns -join '|') | Should -Match '-512' -Because 'Domain Admins (DomainSID-512) is resolved'
        ($res.ProtectedGroupDns -join '|') | Should -Match 'S-1-5-32-544' -Because 'builtin Administrators is included'
        ($res.ProtectedGroupDns -join '|') | Should -Match 'Adman-Protected' -Because 'the configured adman-Protected group is appended'
        $res.DenyRids | Should -Contain '500'
        $res.DenyRids | Should -Contain '501'
        $res.DenyRids | Should -Contain '502'
        Should -Invoke Get-ADDomain -ModuleName adman -Times 2 -Because 'domain + forest-root SIDs are both resolved (A3)'
        Should -Invoke Get-ADForest -ModuleName adman -Times 1

        Test-Path -LiteralPath $script:ProtPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ProtPath -Raw
        @($src | Select-String -Pattern 'S-1-5-21-').Count | Should -Be 0 -Because 'no domain SID is hard-coded (D-02/D-05)'
        $src | Should -Match 'S-1-5-32-544'
        $src | Should -Match '(?i)forest' -Because 'the 518/519 forest-root resolution is documented (A3)'
    }
}
