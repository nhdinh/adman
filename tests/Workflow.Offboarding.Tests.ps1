#Requires -Modules Pester
<#
.SYNOPSIS
    FLOW-02 / FLOW-04 contract tests for Start-AdmanUserOffboarding.

.DESCRIPTION
    Pins the reversible offboarding workflow:
      * One outer confirmation gates disable + strip non-protected groups + move to quarantine.
      * Protected groups are classified by resolved SID against $script:ProtectedSIDs,
        $script:DenyRids, and $script:ProtectedGroupDns, and left intact.
      * The original OU and stripped groups are recorded in the audit log.
      * A mid-workflow failure stops later steps and writes a Failure audit.
      * Cleanup (mailbox/home directory/GPO) is surfaced as a plain-text checklist only.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
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
    GUID              = 'b0000000-0000-0000-0000-0000000000d2'
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

    $script:DomainSid = 'S-1-5-21-111-222-333'

    function script:Seed-OffboardingConfig {
        param(
            [string]$QuarantineOU = 'OU=Quarantine,OU=Managed,DC=mock,DC=local',
            [string[]]$ProtectedSIDs = @("$script:DomainSid-512"),
            [string[]]$ProtectedGroupDns = @('CN=ProtectedByDn,OU=Groups,DC=mock,DC=local'),
            [string[]]$DenyRids = @('500', '501', '502')
        )
        & (Get-Module adman) {
            param($QuarantineOU, $ProtectedSIDs, $ProtectedGroupDns, $DenyRids)
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
                AuditDir   = (Join-Path $TestDrive 'audit')
                templates  = [pscustomobject]@{
                    offboarding = [pscustomobject]@{
                        quarantineOU = $QuarantineOU
                    }
                }
            }
            $script:ProtectedSIDs = $ProtectedSIDs
            $script:ProtectedGroupDns = $ProtectedGroupDns
            $script:DenyRids = $DenyRids
        } -QuarantineOU $QuarantineOU -ProtectedSIDs $ProtectedSIDs -ProtectedGroupDns $ProtectedGroupDns -DenyRids $DenyRids
    }

    function script:New-MockUser {
        param(
            [Parameter(Mandatory)][string]$Dn,
            [string]$Sid = "$script:DomainSid-1000",
            [string[]]$MemberOf = @()
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = $MemberOf
        }
    }

    function script:New-MockGroup {
        param(
            [Parameter(Mandatory)][string]$Name,
            [string]$Sid = "$script:DomainSid-1001"
        )
        [pscustomobject]@{
            Name              = $Name
            DistinguishedName = "CN=$Name,OU=Groups,DC=mock,DC=local"
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'group')
        }
    }
}

Describe 'Start-AdmanUserOffboarding: happy path + composition (FLOW-02)' -Tag 'Unit' {

    BeforeEach {
        Seed-OffboardingConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
        $script:HostCalls = [System.Collections.Generic.List[string]]::new()
    }

    It 'disables the user, removes non-protected groups, moves to quarantine, and records originalOU/groups' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $normalGroup = 'CN=NormalGroup,OU=Groups,DC=mock,DC=local'
        $protectedGroup = 'CN=ProtectedGroup,OU=Groups,DC=mock,DC=local'
        $user = New-MockUser -Dn $userDn -MemberOf @($normalGroup, $protectedGroup)

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -MemberOf @($normalGroup, $protectedGroup) }
        Mock -ModuleName adman Resolve-AdmanGroup {
            if ($Identity -eq $protectedGroup) {
                return New-MockGroup -Name 'ProtectedGroup' -Sid "$script:DomainSid-512"
            }
            return New-MockGroup -Name 'NormalGroup' -Sid "$script:DomainSid-1001"
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { $script:HostCalls.Add([string]$Object) }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; OriginalOU = $OriginalOU; Groups = $Groups; Reason = $Reason }) }

        Start-AdmanUserOffboarding -Identity 'jdoe' -Force

        Should -Invoke -ModuleName adman Disable-AdmanUser -Times 1 -ParameterFilter { $Identity -eq 'jdoe' }
        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 1 -ParameterFilter { $Identity -eq 'jdoe' -and $GroupIdentity -eq $normalGroup }
        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 0 -ParameterFilter { $GroupIdentity -eq $protectedGroup }
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1 -ParameterFilter { $Identity -eq 'jdoe' -and $TargetPath -eq 'OU=Quarantine,OU=Managed,DC=mock,DC=local' }

        $success = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOffboarding' -and $_.Result -eq 'Success' })
        $success.Count | Should -Be 1
        $success[0].OriginalOU | Should -Be 'OU=Users,OU=Managed,DC=mock,DC=local'
        @($success[0].Groups).Count | Should -Be 1
        $success[0].Groups[0] | Should -Be $normalGroup
    }

    It 'calls Confirm-AdmanAction exactly once and forces inner verbs only after confirmation' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Write-AdmanAudit { }

        Start-AdmanUserOffboarding -Identity 'jdoe'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 1 -ParameterFilter {
            $Verb -eq 'Start-AdmanUserOffboarding' -and $Force -eq $false
        }
        Should -Invoke -ModuleName adman Disable-AdmanUser -Times 1 -ParameterFilter { $Force -eq $true }
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1 -ParameterFilter { $Force -eq $true }
    }

    It 'propagates -WhatIf to composed verbs' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'DryRun'; WhatIf = $true } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Write-AdmanAudit { }

        Start-AdmanUserOffboarding -Identity 'jdoe' -WhatIf

        Should -Invoke -ModuleName adman Disable-AdmanUser -Times 1 -ParameterFilter { $WhatIf -eq $true }
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1 -ParameterFilter { $WhatIf -eq $true }
    }

    It 'outputs a plain-text manual-only cleanup checklist on success' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { $script:HostCalls.Add([string]$Object) }
        Mock -ModuleName adman Write-AdmanAudit { }

        Start-AdmanUserOffboarding -Identity 'jdoe' -Force

        $script:HostCalls.Count | Should -BeGreaterThan 0
        ($script:HostCalls -join ' ') | Should -Match 'manual only'
        ($script:HostCalls -join ' ') | Should -Match 'mailbox|home directory|GPO'
    }
}

Describe 'Start-AdmanUserOffboarding: protected-group classification (D-21 / T-04-16)' -Tag 'Unit' {

    BeforeEach {
        Seed-OffboardingConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 'preserves a group whose resolved SID is in $script:ProtectedSIDs' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $normalGroup = 'CN=NormalGroup,OU=Groups,DC=mock,DC=local'
        $protectedGroup = 'CN=ProtectedGroup,OU=Groups,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -MemberOf @($normalGroup, $protectedGroup) }
        Mock -ModuleName adman Resolve-AdmanGroup {
            if ($Identity -eq $protectedGroup) {
                return New-MockGroup -Name 'ProtectedGroup' -Sid "$script:DomainSid-512"
            }
            return New-MockGroup -Name 'NormalGroup' -Sid "$script:DomainSid-1001"
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Groups = $Groups }) }

        Start-AdmanUserOffboarding -Identity 'jdoe' -Force

        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 0 -ParameterFilter { $GroupIdentity -eq $protectedGroup }
        $success = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOffboarding' -and $_.Result -eq 'Success' })
        @($success[0].Groups) | Should -Not -Contain $protectedGroup
        @($success[0].Groups) | Should -Contain $normalGroup
    }

    It 'preserves an unresolved memberOf entry that matches a SID string in $script:ProtectedGroupDns' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $unresolvedSid = "$script:DomainSid-518"
        $normalGroup = 'CN=NormalGroup,OU=Groups,DC=mock,DC=local'

        Seed-OffboardingConfig -ProtectedGroupDns @($unresolvedSid)

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -MemberOf @($unresolvedSid, $normalGroup) }
        Mock -ModuleName adman Resolve-AdmanGroup {
            if ($Identity -eq $unresolvedSid) { throw 'unresolved' }
            return New-MockGroup -Name 'NormalGroup' -Sid "$script:DomainSid-1001"
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Groups = $Groups }) }

        Start-AdmanUserOffboarding -Identity 'jdoe' -Force

        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 0 -ParameterFilter { $GroupIdentity -eq $unresolvedSid }
        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 1 -ParameterFilter { $GroupIdentity -eq $normalGroup }
        $success = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOffboarding' -and $_.Result -eq 'Success' })
        @($success[0].Groups) | Should -Not -Contain $unresolvedSid
    }
}

Describe 'Start-AdmanUserOffboarding: safety gates (FLOW-02 / FLOW-04)' -Tag 'Unit' {

    BeforeEach {
        Seed-OffboardingConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 'throws before confirmation when the quarantine OU is outside managed scope' {
        Seed-OffboardingConfig -QuarantineOU 'OU=Quarantine,OU=NotManaged,DC=mock,DC=local'
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { }
        Mock -ModuleName adman Disable-AdmanUser { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { }

        { Start-AdmanUserOffboarding -Identity 'jdoe' -Force } |
            Should -Throw '*outside managed OU scope*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
        Should -Invoke -ModuleName adman Disable-AdmanUser -Times 0
    }

    It 'writes a Failure audit and stops later steps when disable fails' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Disable-AdmanUser { throw 'disable failed' }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        { Start-AdmanUserOffboarding -Identity 'jdoe' -Force } |
            Should -Throw '*disable failed*'

        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 0
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 0
        $failures = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOffboarding' -and $_.Result -eq 'Failure' })
        $failures.Count | Should -Be 1
        $failures[0].Reason | Should -Match 'disable failed'
    }

    It 'throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Start-AdmanUserOffboarding -Identity 'jdoe' } |
                Should -Throw '*not initialized*Initialize-Adman*'
        } finally {
            Seed-OffboardingConfig
        }
    }
}

Describe 'Start-AdmanUserOffboarding: manifest export' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Start-AdmanUserOffboarding'
        (Get-Command -Module adman -Name 'Start-AdmanUserOffboarding' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
