#Requires -Modules Pester
<#
.SYNOPSIS
    G-02-2 / G-02-4 contract tests for Resolve-AdmanIdentity and the menu prompt
    Type dispatch (Plan 02-09).

.DESCRIPTION
    Pins the prompt-time identity/OU-DN resolution contract:

      * Resolve-AdmanIdentity -Kind AdUser accepts a sAMAccountName OR a full DN
        and returns the resolved ADObject. Unresolvable input throws a typed
        'No AD object found' error (re-prompt signal).
      * Resolve-AdmanIdentity -Kind AdComputer tries BOTH the exact sAMAccountName
        form and the trailing-dollar form (REV-3) so operators can type either
        'PC01' or 'PC01$'.
      * Resolve-AdmanIdentity -Kind AdOuDn validates DN shape (contains '=' AND
        ',') and resolves to an existing AD organizationalUnit. Non-DN input
        throws 'is not a distinguished name' (re-prompt signal).
      * Read-AdmanActionParams with a Type='AdIdentity' PromptSpec stores the
        RESOLVED DistinguishedName (not the raw sAMAccountName) in $params.
      * Read-AdmanActionParams with a Type='AdOuDn' PromptSpec re-prompts on
        non-DN input: the first bad value triggers a Write-Host + continue, the
        second valid value is stored.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1 plus Pester
    mocks; no RSAT, no live domain. Pester 6 syntax.
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
    GUID              = 'b0000000-0000-0000-0000-0000000000e1'
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

    # Import the AD mocks FIRST so Get-ADObject / Get-ADOrganizationalUnit resolve
    # to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with a DC and a minimal ManagedOUs array.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=adman-test,DC=lab,DC=local')
            DC         = 'mock-dc'
        }
    }

    # Helper: build a canned user ADObject with the properties the resolver reads.
    function script:New-UatUserAdObject {
        [pscustomobject]@{
            DistinguishedName = 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
            SamAccountName    = 'uat-reset1'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-5001'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = @()
        }
    }

    # Helper: build a canned OU object.
    function script:New-UatOuObject {
        [pscustomobject]@{
            DistinguishedName = 'OU=adman-test,DC=lab,DC=local'
            objectClass       = @('top', 'organizationalUnit')
        }
    }

    # Helper: build a canned computer ADObject (REV-3).
    function script:New-Pc01ComputerAdObject {
        [pscustomobject]@{
            DistinguishedName = 'CN=PC01,OU=Computers,DC=mock,DC=local'
            SamAccountName    = 'PC01$'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-6001'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user', 'computer')
            memberOf          = @()
        }
    }
}

Describe 'Resolve-AdmanIdentity: AdUser kind' -Tag 'Unit' {

    It 'Test 1: resolves a sAMAccountName to the ADObject with the correct DN' {
        Mock Get-ADObject -ModuleName adman {
            New-UatUserAdObject
        } -ParameterFilter { $Filter -eq "sAMAccountName -eq 'uat-reset1'" }
        $r = & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdUser' } -i 'uat-reset1'
        $r.DistinguishedName | Should -Be 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
        $r.SamAccountName | Should -Be 'uat-reset1'
    }

    It 'Test 2: passes a full DN through to Get-ADObject -Identity (DN passthrough)' {
        Mock Get-ADObject -ModuleName adman {
            New-UatUserAdObject
        } -ParameterFilter { $Identity -eq 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local' }
        $r = & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdUser' } -i 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
        $r.DistinguishedName | Should -Be 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
    }

    It 'Test 3: throws "No AD object found" for an unresolvable sAMAccountName' {
        Mock Get-ADObject -ModuleName adman { @() } -ParameterFilter { $Filter }
        {
            & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdUser' } -i 'no-such-user'
        } | Should -Throw '*No AD object found*'
    }
}

Describe 'Resolve-AdmanIdentity: AdOuDn kind' -Tag 'Unit' {

    It 'Test 4: throws "is not a distinguished name" for non-DN input' {
        {
            & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdOuDn' } -i 'adman-test'
        } | Should -Throw '*is not a distinguished name*'
    }

    It 'Test 5: returns the OU object for a valid OU DN' {
        Mock Get-ADOrganizationalUnit -ModuleName adman {
            New-UatOuObject
        } -ParameterFilter { $Identity -eq 'OU=adman-test,DC=lab,DC=local' }
        $r = & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdOuDn' } -i 'OU=adman-test,DC=lab,DC=local'
        $r.DistinguishedName | Should -Be 'OU=adman-test,DC=lab,DC=local'
    }
}

Describe 'Read-AdmanActionParams: Type dispatch (G-02-2 / G-02-4)' -Tag 'Unit' {

    BeforeAll {
        # Dot-source the helper directly (mirroring tests/Menu.Tests.ps1 MENU-08 pattern)
        # so we can stub Resolve-AdmanIdentity in the script scope. The module import
        # above makes the real resolver available inside the module, but for these
        # tests we want to isolate the menu dispatch logic from the resolver itself
        # (the resolver is proven by Tests 1-5, 8).
        . (Join-Path $script:RepoRoot 'Private/Menu/Read-AdmanActionParams.ps1')
    }

    It 'Test 6: Type=AdIdentity stores the resolved DN (not the raw sAMAccountName)' {
        # Stub the resolver in the script scope so the dotted Read-AdmanActionParams
        # resolves it here (not in the adman module). Returns a canned ADObject whose
        # DistinguishedName is the expected stored value.
        function script:Resolve-AdmanIdentity {
            param([string]$InputValue, [string]$Kind)
            if ($InputValue -ne 'uat-reset1') { throw "No AD object found with sAMAccountName '$InputValue'." }
            [pscustomobject]@{
                DistinguishedName = 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
                SamAccountName    = 'uat-reset1'
            }
        }
        Mock Read-Host { 'uat-reset1' }
        $spec = @(
            @{ Name = 'Identity'; Prompt = 'Enter user identity'; Required = $true; Type = 'AdIdentity' }
        )
        $result = Read-AdmanActionParams -PromptSpec $spec
        $result.Identity | Should -Be 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local'
    }

    It 'Test 7: Type=AdOuDn re-prompts on non-DN input and stores the valid DN' {
        # Stub the resolver: throws on the bad (non-DN) input, returns the OU on the good DN.
        function script:Resolve-AdmanIdentity {
            param([string]$InputValue, [string]$Kind)
            if ($InputValue -eq 'adman-test') {
                throw "'$InputValue' is not a distinguished name. Enter the full OU DN (e.g. OU=adman-test,DC=lab,DC=local)."
            }
            if ($InputValue -eq 'OU=adman-test,DC=lab,DC=local') {
                return [pscustomobject]@{ DistinguishedName = 'OU=adman-test,DC=lab,DC=local' }
            }
            throw "Cannot resolve OU '$InputValue'."
        }
        $script:answers = @('adman-test', 'OU=adman-test,DC=lab,DC=local')
        $script:answerIdx = 0
        Mock Read-Host { $script:answers[$script:answerIdx++] }
        $spec = @(
            @{ Name = 'ParentOuDn'; Prompt = 'Enter parent OU DN'; Required = $true; Type = 'AdOuDn' }
        )
        $result = Read-AdmanActionParams -PromptSpec $spec
        $result.ParentOuDn | Should -Be 'OU=adman-test,DC=lab,DC=local'
        # Prove the re-prompt happened: Read-Host was called twice (bad input + good input).
        $script:answerIdx | Should -Be 2
    }
}

Describe 'Resolve-AdmanIdentity: AdComputer kind (REV-3)' -Tag 'Unit' {

    It 'Test 8: bare NAME resolves via the trailing-dollar fallback (NAME$)' {
        # Exact form returns zero hits; trailing-dollar form returns the computer.
        # WR-04 fix: the trailing-dollar lookup now filters by objectClass -eq 'computer'
        # so a user account with a trailing-dollar sAMAccountName cannot false-positive
        # as a computer target.
        Mock Get-ADObject -ModuleName adman { @() } `
            -ParameterFilter { $Filter -eq "sAMAccountName -eq 'PC01'" }
        Mock Get-ADObject -ModuleName adman {
            New-Pc01ComputerAdObject
        } -ParameterFilter { $Filter -eq "(&(sAMAccountName -eq 'PC01$')(objectClass -eq 'computer'))" }

        $r = & (Get-Module adman) { param($i) Resolve-AdmanIdentity -InputValue $i -Kind 'AdComputer' } -i 'PC01'
        $r.DistinguishedName | Should -Be 'CN=PC01,OU=Computers,DC=mock,DC=local'
        $r.SamAccountName | Should -Be 'PC01$'

        # Prove the exact form was tried first, then the trailing-dollar form.
        Should -Invoke Get-ADObject -ModuleName adman -Times 1 `
            -ParameterFilter { $Filter -eq "sAMAccountName -eq 'PC01'" }
        Should -Invoke Get-ADObject -ModuleName adman -Times 1 `
            -ParameterFilter { $Filter -eq "(&(sAMAccountName -eq 'PC01$')(objectClass -eq 'computer'))" }
    }
}
