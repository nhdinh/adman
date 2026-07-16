#Requires -Modules Pester
<#
.SYNOPSIS
    GRP-03 / D-04 contract tests for protected-group refusal and remediation asymmetry.

.DESCRIPTION
    Pins the safety-critical invariant for the two group membership verbs:
      * Test 3: the gate REFUSES Add-AdmanGroupMember when the group's objectSid is
        in $script:ProtectedSIDs (GRP-03). The refusal is logged 'Refused' with a
        reason matching 'protected' and the write wrapper is NEVER called.
      * Test 4: the gate ALLOWS Remove-AdmanGroupMember when the group's objectSid
        is in $script:ProtectedSIDs (D-04 asymmetry — remediation). Member-side
        checks still apply; the write wrapper IS called.
      * Test 5: the audit record for a group mutation contains BOTH the target
        (member DN) and the group (group DN) fields.

    Exercises the gate's D-04 dual-resolution path end-to-end with module-scope
    mocks for Resolve-AdmanTarget, Resolve-AdmanGroup, Test-AdmanTargetAllowed,
    Test-AdmanGroupAllowed, Write-AdmanAudit, Confirm-AdmanAction,
    Assert-AdmanBulkPolicy, and the Adman.AD.Write.* wrapper.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'

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

    # Import the AD mocks FIRST so AD cmdlets resolve to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config + ProtectedSIDs/DenyRids.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
            AuditDir   = (Join-Path $TestDrive 'audit')
            safety     = [pscustomobject]@{ bulkConfirmThreshold = 5 }
        }
        $script:ProtectedSIDs = @('S-1-5-21-111-222-333-512')
        $script:DenyRids      = @('500', '501', '502')
    }

    # Helpers to build mock AD-shaped objects.
    function script:New-MockMember {
        param([string]$Dn = 'CN=jdoe,OU=Managed,DC=mock,DC=local')
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = @()
        }
    }
    function script:New-MockGroup {
        param(
            [string]$Dn = 'CN=Domain Admins,CN=Users,DC=mock,DC=local',
            [string]$Sid = 'S-1-5-21-111-222-333-512'
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'group')
        }
    }
}

Describe 'Group verbs: protected-group refusal + remediation asymmetry (GRP-03, D-04)' -Tag 'Unit' {

    BeforeEach {
        # Reset the audit call recorder between tests.
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
        $script:WrapperCalled = 0
    }

    It 'Test 3: gate REFUSES Add-AdmanGroupMember when group objectSid is in ProtectedSIDs (GRP-03); writes Refused audit; skips write wrapper' {
        $mockGroup = New-MockGroup
        $mockMember = New-MockMember

        Mock -ModuleName adman Resolve-AdmanTarget { return @($mockMember) }
        Mock -ModuleName adman Resolve-AdmanGroup { return $mockGroup }
        Mock -ModuleName adman Test-AdmanTargetAllowed { return @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Test-AdmanGroupAllowed {
            return @{ Allowed = $false; Reason = 'group is a protected identity (SID S-1-5-21-111-222-333-512)' }
        }
        Mock -ModuleName adman Write-AdmanAudit {
            $script:AuditCalls.Add([pscustomobject]@{
                Result = $Result; Reason = $Reason; Group = $Group; Verb = $Verb
            })
        }
        Mock -ModuleName adman Confirm-AdmanAction { return @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { }
        Mock -ModuleName adman Adman.AD.Write.Add-ADGroupMember { $script:WrapperCalled++ }

        { Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Domain Admins' } |
            Should -Throw '*protected*'

        # The write wrapper must NEVER run for a refused group.
        $script:WrapperCalled | Should -Be 0

        # A 'Refused' audit record was emitted with a reason matching 'protected'.
        $refused = @($script:AuditCalls | Where-Object { $_.Result -eq 'Refused' })
        $refused.Count | Should -BeGreaterThan 0
        $refused[0].Reason | Should -Match 'protected'
    }

    It 'Test 4: gate ALLOWS Remove-AdmanGroupMember when group objectSid is in ProtectedSIDs (D-04 asymmetry — remediation); write wrapper IS called' {
        $mockGroup = New-MockGroup
        $mockMember = New-MockMember

        Mock -ModuleName adman Resolve-AdmanTarget { return @($mockMember) }
        Mock -ModuleName adman Resolve-AdmanGroup { return $mockGroup }
        Mock -ModuleName adman Test-AdmanTargetAllowed { return @{ Allowed = $true; Reason = '' } }
        # The protected-SID check is SKIPPED on Remove; Test-AdmanGroupAllowed returns Allowed=$true.
        Mock -ModuleName adman Test-AdmanGroupAllowed {
            return @{ Allowed = $true; Reason = '' }
        }
        Mock -ModuleName adman Write-AdmanAudit {
            $script:AuditCalls.Add([pscustomobject]@{
                Result = $Result; Reason = $Reason; Group = $Group; Verb = $Verb
            })
        }
        Mock -ModuleName adman Confirm-AdmanAction { return @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { }
        Mock -ModuleName adman Adman.AD.Write.Remove-ADGroupMember { $script:WrapperCalled++ }

        { Remove-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Domain Admins' } |
            Should -Not -Throw

        # The write wrapper IS called for the remediation path.
        $script:WrapperCalled | Should -Be 1
    }

    It 'Test 5: the audit record for a group mutation contains BOTH target (member DN) and group (group DN) fields' {
        $mockGroup = New-MockGroup -Dn 'CN=Mock Group,OU=Managed,DC=mock,DC=local' -Sid 'S-1-5-21-111-222-333-2001'
        $mockMember = New-MockMember

        Mock -ModuleName adman Resolve-AdmanTarget { return @($mockMember) }
        Mock -ModuleName adman Resolve-AdmanGroup { return $mockGroup }
        Mock -ModuleName adman Test-AdmanTargetAllowed { return @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Test-AdmanGroupAllowed { return @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Write-AdmanAudit {
            $script:AuditCalls.Add([pscustomobject]@{
                Result  = $Result
                Group   = $Group
                Verb    = $Verb
                Targets = $Targets
            })
        }
        Mock -ModuleName adman Confirm-AdmanAction { return @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { }
        Mock -ModuleName adman Adman.AD.Write.Add-ADGroupMember { }

        Add-AdmanGroupMember -Identity 'jdoe' -GroupIdentity 'Mock Group'

        # The PENDING audit write must carry BOTH -Targets (member) AND -Group (group DN).
        $pending = @($script:AuditCalls | Where-Object { $_.Result -eq 'PENDING' })
        $pending.Count | Should -BeGreaterThan 0
        $pending[0].Group | Should -Be 'CN=Mock Group,OU=Managed,DC=mock,DC=local'
        # The member DN flows through -Targets.
        $pending[0].Targets[0].DistinguishedName | Should -Be 'CN=jdoe,OU=Managed,DC=mock,DC=local'
    }
}
