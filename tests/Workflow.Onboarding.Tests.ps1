#Requires -Modules Pester
<#
.SYNOPSIS
    FLOW-01 / FLOW-04 contract tests for Start-AdmanUserOnboarding.

.DESCRIPTION
    Pins the behavior of the config-driven new-user onboarding workflow:
      * Builds sAMAccountName/UPN from templates.onboarding and top-level domain.
      * Validates baseline groups before creating the user or adding memberships.
      * Presents one outer confirmation and suppresses inner re-confirmations.
      * Stops later steps on mid-workflow failure and writes a Failure audit.
      * Rejects empty FirstName/LastName at parameter binding.
      * Preflights generated sAMAccountName (non-empty, <=20 chars, no wildcards).

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

    # Import the AD mocks FIRST so AD cmdlets resolve to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with the onboarding template and domain key.
    function script:Seed-OnboardingConfig {
        param(
            [string]$NamePattern = '{0}.{1}',
            [string[]]$BaselineGroups = @('G1', 'G2'),
            [string]$Domain = 'mock.local'
        )
        & (Get-Module adman) {
            param($NamePattern, $BaselineGroups, $Domain)
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
                AuditDir   = (Join-Path $TestDrive 'audit')
                domain     = $Domain
                templates  = [pscustomobject]@{
                    onboarding = [pscustomobject]@{
                        ParentOuDn     = 'OU=Users,OU=Managed,DC=mock,DC=local'
                        BaselineGroups = $BaselineGroups
                        NamePattern    = $NamePattern
                    }
                }
            }
        } -NamePattern $NamePattern -BaselineGroups $BaselineGroups -Domain $Domain
    }

    function script:New-MockGroup {
        param([string]$Name)
        [pscustomobject]@{
            Name              = $Name
            DistinguishedName = "CN=$Name,OU=Groups,DC=mock,DC=local"
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001'
            objectClass       = @('top', 'group')
        }
    }
}

Describe 'Start-AdmanUserOnboarding: happy path + composition (FLOW-01)' -Tag 'Unit' {

    BeforeEach {
        Seed-OnboardingConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 'calls New-AdmanUser once with derived sAMAccountName/UPN and Add-AdmanGroupMember once per baseline group' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force

        Should -Invoke -ModuleName adman New-AdmanUser -Times 1 -ParameterFilter {
            $Name -eq 'John Doe' -and
            $SamAccountName -eq 'john.doe' -and
            $UserPrincipalName -eq 'john.doe@mock.local' -and
            $ParentOuDn -eq 'OU=Users,OU=Managed,DC=mock,DC=local'
        }

        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 2 -ParameterFilter {
            $Identity -eq 'john.doe' -and ($GroupIdentity -eq 'G1' -or $GroupIdentity -eq 'G2')
        }
    }

    It 'calls Confirm-AdmanAction exactly once and forwards -Force:$false while forcing inner verbs' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { }

        # Call WITHOUT -Force on the workflow.
        Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 1 -ParameterFilter {
            $Verb -eq 'Start-AdmanUserOnboarding' -and $Force -eq $false
        }
        Should -Invoke -ModuleName adman New-AdmanUser -Times 1 -ParameterFilter {
            $SamAccountName -eq 'john.doe' -and $Force -eq $true
        }
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 2 -ParameterFilter {
            $Identity -eq 'john.doe' -and $Force -eq $true
        }
    }

    It 'propagates -WhatIf to composed verbs' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'DryRun'; WhatIf = $true } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { }

        Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -WhatIf

        Should -Invoke -ModuleName adman New-AdmanUser -Times 1 -ParameterFilter {
            $WhatIf -eq $true
        }
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 2 -ParameterFilter {
            $WhatIf -eq $true
        }
    }
}

Describe 'Start-AdmanUserOnboarding: baseline group policy (D-17 / T-04-08)' -Tag 'Unit' {

    BeforeEach {
        Seed-OnboardingConfig -BaselineGroups @('G1', 'ProtectedGroup', 'G3')
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 'throws before New-AdmanUser when a baseline group is protected' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed {
            if ($Object.Name -eq 'ProtectedGroup') {
                return @{ Allowed = $false; Reason = 'group is in the protected set' }
            }
            return @{ Allowed = $true; Reason = '' }
        }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { }

        { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
            Should -Throw '*ProtectedGroup*protected*'

        Should -Invoke -ModuleName adman New-AdmanUser -Times 0
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 0
    }
}

Describe 'Start-AdmanUserOnboarding: mid-workflow failure (FLOW-04 / T-04-09)' -Tag 'Unit' {

    BeforeEach {
        Seed-OnboardingConfig
        $script:AuditCalls = [System.Collections.Generic.List[object]]::new()
    }

    It 'writes a Failure audit and prevents further group adds when a group add fails' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { throw 'group add failed' }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
            Should -Throw '*group add failed*'

        $failures = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOnboarding' -and $_.Result -eq 'Failure' })
        $failures.Count | Should -Be 1
        $failures[0].Reason | Should -Match 'group add failed'
    }

    It 'stops after the first failing group add and skips remaining baseline groups' {
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { throw 'first group add failed' } -ParameterFilter { $GroupIdentity -eq 'G1' }
        Mock -ModuleName adman Add-AdmanGroupMember { } -ParameterFilter { $GroupIdentity -eq 'G2' }
        Mock -ModuleName adman Add-AdmanGroupMember { throw 'unexpected group' }
        Mock -ModuleName adman Write-AdmanAudit { $script:AuditCalls.Add([pscustomobject]@{ Verb = $Verb; Result = $Result; Reason = $Reason }) }

        { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
            Should -Throw '*first group add failed*'

        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 1 -ParameterFilter { $GroupIdentity -eq 'G1' }
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 0 -ParameterFilter { $GroupIdentity -eq 'G2' }

        $failures = @($script:AuditCalls | Where-Object { $_.Verb -eq 'Start-AdmanUserOnboarding' -and $_.Result -eq 'Failure' })
        $failures.Count | Should -Be 1
        $failures[0].Reason | Should -Be 'first group add failed'
    }
}

Describe 'Start-AdmanUserOnboarding: parameter + preflight validation' -Tag 'Unit' {

    BeforeEach {
        Seed-OnboardingConfig
    }

    It 'rejects empty FirstName at parameter binding' {
        { Start-AdmanUserOnboarding -FirstName '' -LastName 'Doe' } |
            Should -Throw '*FirstName*'
    }

    It 'rejects empty LastName at parameter binding' {
        { Start-AdmanUserOnboarding -FirstName 'John' -LastName '' } |
            Should -Throw '*LastName*'
    }

    It 'throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' } |
                Should -Throw '*not initialized*Initialize-Adman*'
        } finally {
            Seed-OnboardingConfig
        }
    }

    It 'throws when the domain key is missing' {
        & (Get-Module adman) { $script:Config.domain = '' }
        try {
            { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
                Should -Throw '*domain key*'
        } finally {
            Seed-OnboardingConfig
        }
    }

    It 'throws when the onboarding template is missing' {
        & (Get-Module adman) { $script:Config.templates = $null }
        try {
            { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
                Should -Throw '*Onboarding template*'
        } finally {
            Seed-OnboardingConfig
        }
    }

    It 'throws before confirmation when generated sAMAccountName exceeds 20 characters' {
        Seed-OnboardingConfig -NamePattern '{0}.{1}'
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { }

        $longFirst = 'A' * 10
        $longLast  = 'B' * 11

        { Start-AdmanUserOnboarding -FirstName $longFirst -LastName $longLast -Force } |
            Should -Throw '*20-character*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
        Should -Invoke -ModuleName adman New-AdmanUser -Times 0
    }

    It 'throws before confirmation when generated sAMAccountName contains wildcards' {
        Seed-OnboardingConfig -NamePattern '{0}*{1}'
        Mock -ModuleName adman Resolve-AdmanGroup { New-MockGroup -Name $Identity }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Write-AdmanAudit { }

        { Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force } |
            Should -Throw '*wildcard*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
        Should -Invoke -ModuleName adman New-AdmanUser -Times 0
    }
}

Describe 'Start-AdmanUserOnboarding: manifest export' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Start-AdmanUserOnboarding'
        (Get-Command -Module adman -Name 'Start-AdmanUserOnboarding' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
