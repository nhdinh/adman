#Requires -Modules Pester
<#
.SYNOPSIS
    G-02-6 refusal-surface Write-Warning tests.

.DESCRIPTION
    Pins the operator-visible refusal surface:
      * Test 1: out-of-scope target refused -> Write-Warning carries the scope
        reason ('outside managed-OU scope') and the target DN.
      * Test 2: protected-identity target refused -> Write-Warning carries the
        protected reason ('recursive member of protected group') and the target DN.
      * Test 3: group refused (Add to protected group) -> Write-Warning carries
        the group-refusal reason before the throw.
      * Test 4: the summary object is still returned (Denied=1, Succeeded=0)
        after the warnings - the warning is additive, not a behavior change.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax. PSFramework
    satisfied by a throwaway 1.14.457 stub on $TestDrive.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d1'
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

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Get-ADObject { [CmdletBinding()] param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties) }
    function global:Resolve-AdmanTarget { param($Targets) }
    function global:Resolve-AdmanGroup { param($Identity) }
    function global:Confirm-AdmanAction { param($Verb, $Targets, $Group, [switch]$Force) }
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf) }
    function global:Adman.AD.Write.Disable-ADAccount { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Add-ADGroupMember { param($Objects, $Parameters) }

    function Set-AdmanTestState {
        [CmdletBinding()]
        param()
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
                AuditDir   = 'C:\unused'
                safety     = [pscustomobject]@{ bulkConfirmThreshold = 5 }
                bulk       = [pscustomobject]@{ maxCount = 50 }
            }
            $script:Initialized = $true
            $script:DenyRids = @('500', '501', '502')
            $script:ProtectedSIDs = @('S-1-5-21-111-222-333-512')
            $script:ProtectedGroupDns = @('CN=Domain Admins,CN=Users,DC=mock,DC=local')
        }
    }

    function New-AdmanTestUser {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Dn,
            [string]$Sid = 'S-1-5-21-111-222-333-1000'
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = @()
        }
    }

    function New-AdmanTestGroup {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Dn,
            [string]$Sid = 'S-1-5-21-111-222-333-2000'
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'group')
        }
    }
}

Describe 'G-02-6: refusal-surface Write-Warning' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanTestState
    }

    It 'Test 1: out-of-scope target refused -> Write-Warning carries scope reason and target DN' {
        $outOfScope = New-AdmanTestUser -Dn 'CN=Alice,OU=NotManaged,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $outOfScope }
        Mock Get-ADObject -ModuleName adman { $null }
        Mock Write-AdmanAudit -ModuleName adman { }

        $warnings = @()
        $result = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') `
                -Confirm:$false -WarningVariable +script:warnings
        }
        # WarningVariable inside the module scope doesn't propagate; capture via 3>&1 instead.
        $warnings = @(& (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') `
                -Confirm:$false 3>&1
        } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

        $warnings.Count | Should -BeGreaterOrEqual 1 -Because 'the gate emits a Write-Warning on refusal'
        $warnings[0].Message | Should -Match 'outside managed-OU scope'
        $warnings[0].Message | Should -Match 'CN=Alice,OU=NotManaged,DC=mock,DC=local'
    }

    It 'Test 2: protected-identity target refused -> Write-Warning carries protected reason and target DN' {
        $protected = New-AdmanTestUser -Dn 'CN=Bob,OU=Managed,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $protected }
        # IN_CHAIN hit: the member IS a recursive protected-group member.
        Mock Get-ADObject -ModuleName adman {
            param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties)
            if ($LDAPFilter -match 'IN_CHAIN|1\.2\.840\.113556\.1\.4\.1941') {
                return [pscustomobject]@{ DistinguishedName = 'CN=Bob,OU=Managed,DC=mock,DC=local' }
            }
            return $null
        }
        Mock Write-AdmanAudit -ModuleName adman { }

        $warnings = @(& (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('bob') `
                -Confirm:$false 3>&1
        } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

        $warnings.Count | Should -BeGreaterOrEqual 1
        $warnings[0].Message | Should -Match 'recursive member of protected group'
        $warnings[0].Message | Should -Match 'CN=Bob,OU=Managed,DC=mock,DC=local'
    }

    It 'Test 3: group refused (Add to protected group) -> Write-Warning carries group-refusal reason before throw' {
        $member = New-AdmanTestUser -Dn 'CN=Carol,OU=Managed,DC=mock,DC=local'
        $protectedGroup = New-AdmanTestGroup -Dn 'CN=Domain Admins,CN=Users,DC=mock,DC=local' -Sid 'S-1-5-21-111-222-333-512'

        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Resolve-AdmanGroup -ModuleName adman { $protectedGroup }
        Mock Write-AdmanAudit -ModuleName adman { }

        # Capture warnings via -WarningVariable on the module-scope invocation. The gate
        # throws AFTER the Write-Warning, so the warning stream is populated before the throw.
        $caught = $null
        & (Get-Module adman) {
            $script:capturedWarnings = @()
        }
        try {
            & (Get-Module adman) {
                Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @('carol') `
                    -Parameters @{ GroupIdentity = 'Domain Admins' } -Confirm:$false `
                    -WarningVariable +script:capturedWarnings
            }
        } catch {
            $caught = $_
        }
        $warnings = @(& (Get-Module adman) { $script:capturedWarnings })

        $caught | Should -Not -BeNullOrEmpty -Because 'the gate throws after the group-refusal warning'
        $caught.Exception.Message | Should -Match 'Group refused'
        $warnings.Count | Should -BeGreaterOrEqual 1 -Because 'the gate emits a Write-Warning before throwing'
        $warnings[0] | Should -Match 'Group refused'
        $warnings[0] | Should -Match 'protected set'
    }

    It 'Test 4: summary object still returned (Denied=1, Succeeded=0) after warnings - additive, not a behavior change' {
        $outOfScope = New-AdmanTestUser -Dn 'CN=Dave,OU=NotManaged,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $outOfScope }
        Mock Get-ADObject -ModuleName adman { $null }
        Mock Write-AdmanAudit -ModuleName adman { }

        $result = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('dave') `
                -Confirm:$false -WarningAction SilentlyContinue
        }

        $result | Should -Not -BeNullOrEmpty
        $result.Action | Should -Be 'Disable-ADAccount'
        $result.Denied | Should -Be 1
        $result.Succeeded | Should -Be 0
        $result.Failed | Should -Be 0
        $result.CorrelationId | Should -Not -BeNullOrEmpty
    }
}
