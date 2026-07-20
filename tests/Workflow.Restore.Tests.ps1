#Requires -Modules Pester
<#
.SYNOPSIS
    FLOW-03 / FLOW-04 contract tests for Get-AdmanOffboardingState and Restore-AdmanQuarantinedUser.

.DESCRIPTION
    Pins the offboarding restore behavior:
      * Get-AdmanOffboardingState returns the latest successful, non-dry-run offboarding
        audit record matched by exact user DN or SID against targets[].dn / targets[].sid.
      * Restore validates the user is currently in the configured quarantine OU.
      * Restore re-adds recorded groups, moves back to the original OU, and enables the
        account last so a partial failure leaves the account disabled.
      * Restore writes Success/Failure audits and excludes dry-run or failure offboarding
        records as restore state.

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
    GUID              = 'b0000000-0000-0000-0000-0000000000d3'
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

    function script:Seed-RestoreConfig {
        param(
            [string]$QuarantineOU = 'OU=Quarantine,OU=Managed,DC=mock,DC=local'
        )
        $auditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
        & (Get-Module adman) {
            param($QuarantineOU, $AuditDir)
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
                AuditDir   = $AuditDir
                templates  = [pscustomobject]@{
                    offboarding = [pscustomobject]@{
                        quarantineOU = $QuarantineOU
                    }
                }
            }
            $script:ProtectedSIDs = @('S-1-5-21-111-222-333-512')
            $script:ProtectedGroupDns = @()
            $script:DenyRids = @('500', '501', '502')
        } -QuarantineOU $QuarantineOU -AuditDir $auditDir
        return $auditDir
    }

    function script:New-MockUser {
        param(
            [Parameter(Mandatory)][string]$Dn,
            [string]$Sid = "$script:DomainSid-1000"
        )
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = @()
        }
    }

    function script:Get-OffboardingStateForTest {
        param([Parameter(Mandatory)][string]$Id)
        & (Get-Module adman) { param($I) Get-AdmanOffboardingState -Identity $I } -I $Id
    }

    function script:Write-TestAuditRecord {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][hashtable]$Record
        )
        $line = $Record | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    }
}

Describe 'Get-AdmanOffboardingState: exact-match state reader (FLOW-03)' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Seed-RestoreConfig
    }

    It 'returns the latest successful offboarding record by exact DN match' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $userSid = "$script:DomainSid-1000"
        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))

        Write-TestAuditRecord -Path $path -Record @{
            tsUtc      = '2026-07-19T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Success'
            whatIf     = $false
            targets    = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Old,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=G1,OU=Groups,DC=mock,DC=local')
        }
        Write-TestAuditRecord -Path $path -Record @{
            tsUtc      = '2026-07-20T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Success'
            whatIf     = $false
            targets    = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=G2,OU=Groups,DC=mock,DC=local')
        }

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -Sid $userSid }

        $state = & (Get-Module adman) { param($Id) Get-AdmanOffboardingState -Identity $Id } -Id 'jdoe'
        $state | Should -Not -BeNullOrEmpty
        $state.OriginalOU | Should -Be 'OU=Users,OU=Managed,DC=mock,DC=local'
        $state.Groups | Should -Contain 'CN=G2,OU=Groups,DC=mock,DC=local'
    }

    It 'matches by exact SID when the DN differs' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $userSid = "$script:DomainSid-1000"
        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))

        Write-TestAuditRecord -Path $path -Record @{
            tsUtc      = '2026-07-20T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Success'
            whatIf     = $false
            targets    = @(@{ dn = 'CN=other,OU=Users,OU=Managed,DC=mock,DC=local'; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=G1,OU=Groups,DC=mock,DC=local')
        }

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -Sid $userSid }

        $state = Get-OffboardingStateForTest -Id 'jdoe'
        $state | Should -Not -BeNullOrEmpty
    }

    It 'excludes dry-run offboarding records' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $userSid = "$script:DomainSid-1000"
        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))

        Write-TestAuditRecord -Path $path -Record @{
            tsUtc      = '2026-07-20T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Success'
            whatIf     = $true
            targets    = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=G1,OU=Groups,DC=mock,DC=local')
        }

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -Sid $userSid }

        Get-OffboardingStateForTest -Id 'jdoe' | Should -BeNullOrEmpty
    }

    It 'excludes failure offboarding records' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $userSid = "$script:DomainSid-1000"
        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))

        Write-TestAuditRecord -Path $path -Record @{
            tsUtc      = '2026-07-20T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Failure'
            whatIf     = $false
            targets    = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=G1,OU=Groups,DC=mock,DC=local')
        }

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -Sid $userSid }

        Get-OffboardingStateForTest -Id 'jdoe' | Should -BeNullOrEmpty
    }

    It 'returns $null when no matching record exists' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }

        Get-OffboardingStateForTest -Id 'jdoe' | Should -BeNullOrEmpty
    }

    It 'searches all audit files, not just the last 30 days' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'
        $userSid = "$script:DomainSid-1000"
        $oldPath = Join-Path $script:AuditDir 'audit-20250101.jsonl'

        Write-TestAuditRecord -Path $oldPath -Record @{
            tsUtc      = '2025-01-01T10:00:00.0000000Z'
            what       = 'Start-AdmanUserOffboarding'
            result     = 'Success'
            whatIf     = $false
            targets    = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            originalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
            groups     = @('CN=OldGroup,OU=Groups,DC=mock,DC=local')
        }

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn -Sid $userSid }

        $state = Get-OffboardingStateForTest -Id 'jdoe'
        $state | Should -Not -BeNullOrEmpty
        $state.Groups | Should -Contain 'CN=OldGroup,OU=Groups,DC=mock,DC=local'
    }
}

Describe 'Restore-AdmanQuarantinedUser: reverse offboarding (FLOW-03 / FLOW-04)' -Tag 'Unit' {

    BeforeEach {
        Seed-RestoreConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 're-adds groups, moves back to original OU, and enables last in order' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'
        $groups = @('CN=G1,OU=Groups,DC=mock,DC=local', 'CN=G2,OU=Groups,DC=mock,DC=local')

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{ OriginalOU = $originalOu; Groups = $groups }
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result }) }

        Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force

        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 2 -ParameterFilter {
            $Identity -eq 'jdoe'
        }
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1 -ParameterFilter {
            $Identity -eq 'jdoe' -and $TargetPath -eq $originalOu
        }
        Should -Invoke -ModuleName adman Enable-AdmanUser -Times 1 -ParameterFilter {
            $Identity -eq 'jdoe'
        }

        $success = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Restore-AdmanQuarantinedUser' -and $_.Result -eq 'Success' })
        $success.Count | Should -Be 1
    }

    It 'throws before confirmation when the user is not in the quarantine OU' {
        $userDn = 'CN=jdoe,OU=Users,OU=Managed,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Confirm-AdmanAction { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { }

        { Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force } |
            Should -Throw '*not currently in the quarantine OU*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
        Should -Invoke -ModuleName adman Enable-AdmanUser -Times 0
    }

    It 'throws when no offboarding state is found' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState { $null }
        Mock -ModuleName adman Confirm-AdmanAction { }
        Mock -ModuleName adman Add-AdmanGroupMember { }

        { Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force } |
            Should -Throw '*No successful offboarding state*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
    }

    It 'throws before confirmation when the recorded originalOU is outside managed scope' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'
        $badOriginalOu = 'OU=Users,OU=NotManaged,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{ OriginalOU = $badOriginalOu; Groups = @() }
        }
        Mock -ModuleName adman Confirm-AdmanAction { }
        Mock -ModuleName adman Add-AdmanGroupMember { }

        { Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force } |
            Should -Throw '*outside managed OU scope*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
    }

    It 'leaves the account disabled when Move-AdmanUser fails (ordering invariant)' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{ OriginalOU = $originalOu; Groups = @('CN=G1,OU=Groups,DC=mock,DC=local') }
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { throw 'move failed' }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        { Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force } |
            Should -Throw '*move failed*'

        Should -Invoke -ModuleName adman Enable-AdmanUser -Times 0
        $failures = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Restore-AdmanQuarantinedUser' -and $_.Result -eq 'Failure' })
        $failures.Count | Should -Be 1
    }

    It 'writes a Failure audit when a step fails' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{ OriginalOU = $originalOu; Groups = @('CN=G1,OU=Groups,DC=mock,DC=local') }
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Add-AdmanGroupMember { throw 'add failed' }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        { Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force } |
            Should -Throw '*add failed*'

        $failures = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Restore-AdmanQuarantinedUser' -and $_.Result -eq 'Failure' })
        $failures.Count | Should -Be 1
        $failures[0].Reason | Should -Match 'add failed'
    }

    It 'propagates -WhatIf to composed verbs' {
        $userDn = 'CN=jdoe,OU=Quarantine,OU=Managed,DC=mock,DC=local'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'

        Mock -ModuleName adman Resolve-AdmanTarget { New-MockUser -Dn $userDn }
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{ OriginalOU = $originalOu; Groups = @('CN=G1,OU=Groups,DC=mock,DC=local') }
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'DryRun'; WhatIf = $true } }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { }

        Restore-AdmanQuarantinedUser -Identity 'jdoe' -WhatIf

        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 1 -ParameterFilter { $WhatIf -eq $true }
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1 -ParameterFilter { $WhatIf -eq $true }
        Should -Invoke -ModuleName adman Enable-AdmanUser -Times 1 -ParameterFilter { $WhatIf -eq $true }
    }

    It 'throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Restore-AdmanQuarantinedUser -Identity 'jdoe' } |
                Should -Throw '*not initialized*Initialize-Adman*'
        } finally {
            Seed-RestoreConfig
        }
    }
}

Describe 'Restore-AdmanQuarantinedUser: manifest export' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Restore-AdmanQuarantinedUser'
        (Get-Command -Module adman -Name 'Restore-AdmanQuarantinedUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
