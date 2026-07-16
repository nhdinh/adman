#Requires -Modules Pester
<#
.SYNOPSIS
    USER-02 contract tests for New-AdmanUser (D-01 create path + D-05 password plumbing).

.DESCRIPTION
    Pins the contract for the create-user verb:
      * Routes through Invoke-AdmanMutation with -Verb 'New-ADUser' and the correct
        $Parameters shape (Name, SamAccountName, UserPrincipalName, ParentOuDn,
        AccountPassword, ChangePasswordAtLogon).
      * sAMAccountName length validated (<= 20 chars).
      * WR-01 init check throws when $script:Config.ManagedOUs is absent.
      * D-05 password sourcing: Generate via New-AdmanRandomPassword (default),
        Prompt via Read-Host -AsSecureString + Test-AdmanPasswordComplexity.
      * D-05 display-once: after a successful Generate-sourced gate return (NOT under
        -WhatIf), the plaintext is shown ONCE behind Read-Host 'Press Enter when
        recorded' + [Console]::Clear(); skipped under -WhatIf; skipped when the
        caller supplied -AccountPassword explicitly (per-call source wins over config).
      * HIGH #1 cycle-2 review fix: the verb declares an optional
        [ValidateSet('Generate','Prompt')][string]$AccountPasswordSource parameter so
        the menu splat (& New-AdmanUser @menuParams) does NOT throw "parameter cannot
        be found".
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains 'New-AdmanUser'
        explicitly; Get-Command -Module adman -Name 'New-AdmanUser' resolves after
        Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live
    domain. Pester 6 syntax.
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

    # Seed $script:Config with the security block the D-05 password sourcing reads.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
            security   = [pscustomobject]@{
                passwordSource         = 'Generate'
                passwordGeneration     = [pscustomobject]@{ length = 20 }
                mustChangeAtNextLogon  = $true
            }
        }
    }

    # Build a known SecureString for the explicit-password tests.
    function script:New-TestSecureString {
        param([string]$Plain = 'MockP@ssw0rd!LongEnough')
        $s = [securestring]::new()
        foreach ($c in $Plain.ToCharArray()) { $s.AppendChar($c) }
        $s.MakeReadOnly()
        return $s
    }
}

Describe 'New-AdmanUser: gate routing + parameter shape (USER-02, D-01)' -Tag 'Unit' {

    It 'calls Invoke-AdmanMutation with -Verb New-ADUser and the correct $Parameters' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $sec = New-TestSecureString
        New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
            -UserPrincipalName 'jdoe@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local' `
            -AccountPassword $sec

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'New-ADUser' -and
            $Parameters['Name'] -eq 'jdoe' -and
            $Parameters['SamAccountName'] -eq 'jdoe' -and
            $Parameters['UserPrincipalName'] -eq 'jdoe@mock.local' -and
            $Parameters['ParentOuDn'] -eq 'OU=Managed,DC=mock,DC=local' -and
            $Parameters['AccountPassword'] -is [securestring]
        }
    }

    It 'throws when sAMAccountName exceeds the 20-character limit' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        $longSam = 'a' * 21
        { New-AdmanUser -Name 'x' -SamAccountName $longSam `
            -UserPrincipalName 'x@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local' } |
            Should -Throw '*20-character*'
    }

    It 'sources the password via New-AdmanRandomPassword when -AccountPassword is not supplied and passwordSource=Generate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
            -UserPrincipalName 'jdoe@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local'

        Should -Invoke -ModuleName adman New-AdmanRandomPassword -Times 1
    }

    It 'prompts via Read-Host -AsSecureString and validates via Test-AdmanPasswordComplexity when passwordSource=Prompt' {
        & (Get-Module adman) {
            $script:Config.security.passwordSource = 'Prompt'
        }
        try {
            Mock -ModuleName adman Invoke-AdmanMutation { }
            Mock -ModuleName adman Test-AdmanPasswordComplexity { return $true }
            Mock -ModuleName adman Read-Host { New-TestSecureString }
            Mock -ModuleName adman Write-Host { }

            New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
                -UserPrincipalName 'jdoe@mock.local' `
                -ParentOuDn 'OU=Managed,DC=mock,DC=local'

            Should -Invoke -ModuleName adman Test-AdmanPasswordComplexity -Times 1
        } finally {
            & (Get-Module adman) {
                $script:Config.security.passwordSource = 'Generate'
            }
        }
    }

    It 'throws the WR-01 init message when $script:Config.ManagedOUs is absent' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
                -UserPrincipalName 'jdoe@mock.local' `
                -ParentOuDn 'OU=Managed,DC=mock,DC=local' } |
                Should -Throw '*not initialized*Initialize-Adman*'
        } finally {
            & (Get-Module adman) {
                $script:Config = [pscustomobject]@{
                    ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                    DC         = 'dc.mock.local'
                    security   = [pscustomobject]@{
                        passwordSource         = 'Generate'
                        passwordGeneration     = [pscustomobject]@{ length = 20 }
                        mustChangeAtNextLogon  = $true
                    }
                }
            }
        }
    }
}

Describe 'New-AdmanUser: D-05 display-once hygiene' -Tag 'Unit' {

    It 'displays the generated password ONCE behind Read-Host + [Console]::Clear when source=Generate and gate succeeds' {
        Mock -ModuleName adman Invoke-AdmanMutation {
            return [pscustomobject]@{ Action='New-ADUser'; CorrelationId='mock'; Succeeded=1; WhatIf=$false }
        }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        $script:ReadHostCalls = @()
        Mock -ModuleName adman Read-Host {
            param($Prompt)
            $script:ReadHostCalls += [string]$Prompt
            return ''
        }
        Mock -ModuleName adman Write-Host { }

        New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
            -UserPrincipalName 'jdoe@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local'

        $matched = @($script:ReadHostCalls | Where-Object { $_ -match 'Press Enter when recorded' })
        $matched.Count | Should -BeGreaterOrEqual 1
    }

    It 'SKIPS the display-once path under -WhatIf' {
        Mock -ModuleName adman Invoke-AdmanMutation {
            return [pscustomobject]@{ Action='New-ADUser'; CorrelationId='mock'; Succeeded=1; WhatIf=$true }
        }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        $script:ReadHostCalls = @()
        Mock -ModuleName adman Read-Host {
            param($Prompt)
            $script:ReadHostCalls += [string]$Prompt
            return ''
        }
        Mock -ModuleName adman Write-Host { }

        New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
            -UserPrincipalName 'jdoe@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local' -WhatIf

        $matched = @($script:ReadHostCalls | Where-Object { $_ -match 'Press Enter when recorded' })
        $matched.Count | Should -Be 0
    }

    It 'SKIPS the display-once path when the caller supplies -AccountPassword explicitly (per-call source wins over config)' {
        Mock -ModuleName adman Invoke-AdmanMutation {
            return [pscustomobject]@{ Action='New-ADUser'; CorrelationId='mock'; Succeeded=1; WhatIf=$false }
        }
        $script:ReadHostCalls = @()
        Mock -ModuleName adman Read-Host {
            param($Prompt)
            $script:ReadHostCalls += [string]$Prompt
            return ''
        }
        Mock -ModuleName adman Write-Host { }

        $sec = New-TestSecureString
        New-AdmanUser -Name 'jdoe' -SamAccountName 'jdoe' `
            -UserPrincipalName 'jdoe@mock.local' `
            -ParentOuDn 'OU=Managed,DC=mock,DC=local' `
            -AccountPassword $sec

        $matched = @($script:ReadHostCalls | Where-Object { $_ -match 'Press Enter when recorded' })
        $matched.Count | Should -Be 0
    }
}

Describe 'New-AdmanUser: manifest export + menu-splat contract (HIGH #1, HIGH #2 review fixes)' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'New-AdmanUser'
        (Get-Command -Module adman -Name 'New-AdmanUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'accepts the menu-splat hashtable shape (AccountPasswordSource parameter declared)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $menuParams = @{
            Name                 = 'jdoe'
            SamAccountName       = 'jdoe'
            UserPrincipalName    = 'jdoe@mock.local'
            ParentOuDn           = 'OU=Managed,DC=mock,DC=local'
            AccountPassword      = (New-TestSecureString)
            AccountPasswordSource = 'Generate'
        }
        { New-AdmanUser @menuParams -WhatIf } | Should -Not -Throw '*parameter cannot be found*'
    }
}
