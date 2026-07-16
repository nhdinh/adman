#Requires -Modules Pester
<#
.SYNOPSIS
    G-02-8 / G-02-9 remediation-asymmetry + per-member group-refusal audit tests.

.DESCRIPTION
    Pins the D-04 remediation asymmetry end-to-end through the gate:
      * Test 1: Remove-ADGroupMember of a protected-group member FROM a non-protected
        group is ALLOWED. Test-AdmanTargetAllowed is called with -Operation
        'Remove-ADGroupMember'; step (d) recursive protected-membership is SKIPPED;
        the member passes (deny-RID and scope still apply).
      * Test 2: Add-ADGroupMember of a protected-group member TO a non-protected
        group is REFUSED by step (d) with 'recursive member of protected group'.
      * Test 3: Add-ADGroupMember TO a protected group writes one Refused audit
        record PER MEMBER with the member DN in the target field and the group DN
        in the group field (G-02-9).
      * Test 4: Remove-ADGroupMember with a deny-listed-RID member is still REFUSED
        (the asymmetry skips ONLY step (d), not step (b)).
      * Test 5: the -Operation ValidateSet spans all 10 gate verbs (REV-1 regression
        guard). New-ADUser and Set-ADUser both reach policy/audit without a
        ParameterBindingException.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no
    live domain. Pester 6 syntax. PSFramework satisfied by a throwaway 1.14.457
    stub on $TestDrive.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d0'
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

    # NOTE: do NOT import tests/Mocks/ActiveDirectory.psm1 here. Its Get-ADObject signature
    # lacks -SearchBase/-SearchScope, which the gate's New-ADUser uniqueness pre-flight
    # requires. All AD collaborators are Pester-mocked with -ModuleName adman instead.
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Get-ADObject { [CmdletBinding()] param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties) }
    function global:Resolve-AdmanTarget { param($Targets) }
    function global:Resolve-AdmanGroup { param($Identity) }
    function global:Resolve-AdmanCreateTarget { param($Name, $SamAccountName, $ParentOuDn) }
    function global:Confirm-AdmanAction { param($Verb, $Targets, $Group, [switch]$Force) }
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf) }
    function global:Adman.AD.Write.Add-ADGroupMember { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Remove-ADGroupMember { param($Objects, $Parameters) }
    function global:Adman.AD.Write.New-ADUser { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Set-ADUser { param($Objects, $Parameters) }

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

Describe 'G-02-8 / G-02-9: group remediation asymmetry + per-member audit' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanTestState
    }

    It 'Test 1: Remove-ADGroupMember of a protected-group member FROM a non-protected group is ALLOWED (step (d) skipped)' {
        # Member IS a recursive protected-group member (IN_CHAIN hit on step d).
        # On Remove, step (d) must be SKIPPED so the member passes.
        $member = New-AdmanTestUser -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $group = New-AdmanTestGroup -Dn 'CN=Helpdesk,OU=Managed,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Resolve-AdmanGroup -ModuleName adman { $group }
        # IN_CHAIN hit: the member IS a recursive protected-group member. If step (d) ran,
        # the member would be refused. Skipped on Remove -> allowed.
        Mock Get-ADObject -ModuleName adman {
            param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties)
            if ($LDAPFilter -match 'IN_CHAIN|1\.2\.840\.113556\.1\.4\.1941') {
                return [pscustomobject]@{ DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local' }
            }
            return $null
        }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Remove-ADGroupMember -ModuleName adman { }

        $result = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Remove-ADGroupMember' -Targets @('alice') `
                -Parameters @{ GroupIdentity = 'Helpdesk' } -Confirm:$false
        }

        $result.Succeeded | Should -Be 1 -Because 'remediation (Remove from a non-protected group) skips step (d) and succeeds'
        $result.Denied | Should -Be 0
        Should -Invoke Adman.AD.Write.Remove-ADGroupMember -ModuleName adman -Times 1 `
            -Because 'the write wrapper runs for the allowed member'
    }

    It 'Test 2: Add-ADGroupMember of a protected-group member TO a non-protected group is REFUSED by step (d)' {
        $member = New-AdmanTestUser -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $group = New-AdmanTestGroup -Dn 'CN=Helpdesk,OU=Managed,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Resolve-AdmanGroup -ModuleName adman { $group }
        Mock Get-ADObject -ModuleName adman {
            param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties)
            if ($LDAPFilter -match 'IN_CHAIN|1\.2\.840\.113556\.1\.4\.1941') {
                return [pscustomobject]@{ DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local' }
            }
            return $null
        }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Add-ADGroupMember -ModuleName adman { }

        $result = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @('alice') `
                -Parameters @{ GroupIdentity = 'Helpdesk' } -Confirm:$false `
                -WarningAction SilentlyContinue
        }

        $result.Denied | Should -Be 1 -Because 'the member is a recursive protected-group member and Add refuses via step (d)'
        $result.Succeeded | Should -Be 0
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Refused' -and $Reason -match 'recursive member of protected group'
        } -Because 'the member-side Refused audit record carries the protected-membership reason'
        Should -Invoke Adman.AD.Write.Add-ADGroupMember -ModuleName adman -Times 0
    }

    It 'Test 3: Add-ADGroupMember TO a protected group writes per-member Refused audit (member DN in target, group DN in group)' {
        $member = New-AdmanTestUser -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $protectedGroup = New-AdmanTestGroup -Dn 'CN=Domain Admins,CN=Users,DC=mock,DC=local' -Sid 'S-1-5-21-111-222-333-512'

        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Resolve-AdmanGroup -ModuleName adman { $protectedGroup }
        Mock Write-AdmanAudit -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @('alice') `
                -Parameters @{ GroupIdentity = 'Domain Admins' } -Confirm:$false `
                -WarningAction SilentlyContinue
        } } | Should -Throw -ExpectedMessage '*Group refused*'

        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Refused' -and
            $Target.DistinguishedName -eq 'CN=Alice,OU=Managed,DC=mock,DC=local' -and
            $Group -eq 'CN=Domain Admins,CN=Users,DC=mock,DC=local' -and
            $Reason -match 'protected set'
        } -Because 'the group-refusal audit names the MEMBER DN in target and the GROUP DN in group (G-02-9)'
    }

    It 'Test 4: Remove-ADGroupMember with a deny-listed-RID member is still REFUSED (asymmetry skips ONLY step (d), not step (b))' {
        $member = New-AdmanTestUser -Dn 'CN=Administrator,OU=Managed,DC=mock,DC=local' -Sid 'S-1-5-21-111-222-333-500'
        $group = New-AdmanTestGroup -Dn 'CN=Helpdesk,OU=Managed,DC=mock,DC=local'

        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Resolve-AdmanGroup -ModuleName adman { $group }
        Mock Get-ADObject -ModuleName adman { $null }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Remove-ADGroupMember -ModuleName adman { }

        $result = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Remove-ADGroupMember' -Targets @('administrator') `
                -Parameters @{ GroupIdentity = 'Helpdesk' } -Confirm:$false `
                -WarningAction SilentlyContinue
        }

        $result.Denied | Should -Be 1 -Because 'deny-RID still applies on Remove (the asymmetry is narrow)'
        $result.Succeeded | Should -Be 0
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Refused' -and $Reason -match 'deny-listed RID 500'
        }
        Should -Invoke Adman.AD.Write.Remove-ADGroupMember -ModuleName adman -Times 0
    }

    It 'Test 5: -Operation ValidateSet spans all 10 gate verbs (REV-1 regression guard) - New-ADUser and Set-ADUser reach policy/audit' {
        # Leg A: New-ADUser. Uses Resolve-AdmanCreateTarget + synthetic target.
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Bob,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'bob'
            Name              = 'Bob'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        Mock Resolve-AdmanCreateTarget -ModuleName adman { $synthetic }
        Mock Get-ADObject -ModuleName adman {
            param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties)
            return $null
        }   # uniqueness pre-flight: no collision
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.New-ADUser -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'New-ADUser' -Targets @('bob') `
                -Parameters @{ Name = 'Bob'; SamAccountName = 'bob'; ParentOuDn = 'OU=Managed,DC=mock,DC=local' } `
                -Confirm:$false
        } } | Should -Not -Throw -Because 'New-ADUser is in the -Operation ValidateSet (no ParameterBindingException)'

        Should -Invoke Write-AdmanAudit -ModuleName adman -ParameterFilter {
            $Result -eq 'PENDING' -and $Verb -eq 'New-ADUser'
        } -Because 'New-ADUser reaches policy/audit (PENDING)'

        # Leg B: Set-ADUser via direct gate invocation. Member is benign (no IN_CHAIN hit).
        $member = New-AdmanTestUser -Dn 'CN=Carol,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $member }
        Mock Get-ADObject -ModuleName adman { $null }   # no IN_CHAIN hit
        Mock Adman.AD.Write.Set-ADUser -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Set-ADUser' -Targets @('carol') `
                -Parameters @{ ChangePasswordAtLogon = $true } -Confirm:$false
        } } | Should -Not -Throw -Because 'Set-ADUser is in the -Operation ValidateSet (no ParameterBindingException)'

        Should -Invoke Write-AdmanAudit -ModuleName adman -ParameterFilter {
            $Result -eq 'PENDING' -and $Verb -eq 'Set-ADUser'
        } -Because 'Set-ADUser reaches policy/audit (PENDING)'
    }
}
