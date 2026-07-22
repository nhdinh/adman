#Requires -Modules Pester
<#
.SYNOPSIS
    LUSR-01 contract tests for New/Set/Remove-AdmanLocalUser.

.DESCRIPTION
    Pins the contract for the three local user lifecycle Public verbs:
      * Each verb routes through Invoke-AdmanLocalMutation with the correct -Verb
        ('New-LocalUser' / 'Set-LocalUser' / 'Enable-LocalUser' / 'Disable-LocalUser' /
        'Remove-LocalUser') and the expected $Parameters shape.
      * New-AdmanLocalUser sources the password per D-05 (Generate via
        New-AdmanRandomPassword; Prompt via Read-Host -AsSecureString +
        Test-AdmanPasswordComplexity).
      * Set-AdmanLocalUser declares three parameter sets ('Reset', 'Enable', 'Disable')
        and throws a parameter-set resolution error when neither -Password nor
        -Enable/-Disable is supplied.
      * Remove-AdmanLocalUser help text states plainly: irreversible, no Recycle-Bin
        equivalent.
      * All three verbs validate -ComputerName to localhost (accept $null, '.',
        $env:COMPUTERNAME, 'localhost'; throw "Remote targets arrive in Phase 3"
        otherwise).
      * All three verbs throw the WR-01 init message when uninitialized.
      * HIGH #1 cycle-2 review fix: New-AdmanLocalUser and Set-AdmanLocalUser declare
        an optional [ValidateSet('Generate','Prompt')][string]$PasswordSource parameter
        so the menu splat does NOT throw "parameter cannot be found".
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains the three verbs
        explicitly; Get-Command -Module adman resolves them after Import-Module.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live
    domain, no real local accounts touched. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:NewVerbPath = Join-Path $script:RepoRoot 'Public/New-AdmanLocalUser.ps1'
    $script:SetVerbPath = Join-Path $script:RepoRoot 'Public/Set-AdmanLocalUser.ps1'
    $script:RemoveVerbPath = Join-Path $script:RepoRoot 'Public/Remove-AdmanLocalUser.ps1'

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

    # Import the AD mocks FIRST so LocalAccounts cmdlets resolve to the mock when the module loads.
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

Describe 'New-AdmanLocalUser: gate routing + parameter shape (LUSR-01, D-02)' -Tag 'Unit' {

    It 'Test 1: calls Invoke-AdmanLocalMutation with -Verb New-LocalUser and $Parameters containing Name, Password, ComputerName' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $sec = New-TestSecureString
        New-AdmanLocalUser -Name 'luser' -Password $sec

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'New-LocalUser' -and
            $Parameters['Name'] -eq 'luser' -and
            $Parameters['Password'] -is [securestring] -and
            $Parameters.ContainsKey('ComputerName')
        }
    }

    It 'Test 2: sources the password via New-AdmanRandomPassword when -Password is not supplied and passwordSource=Generate' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        New-AdmanLocalUser -Name 'luser'

        Should -Invoke -ModuleName adman New-AdmanRandomPassword -Times 1
    }

    It 'Test 6: validates -ComputerName to localhost (throws "Remote targets arrive in Phase 3" on otherhost)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        $sec = New-TestSecureString
        { New-AdmanLocalUser -Name 'luser' -Password $sec -ComputerName 'otherhost' } |
            Should -Throw '*Remote targets arrive in Phase 3*'
    }

    It 'Test 7: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            $sec = New-TestSecureString
            { New-AdmanLocalUser -Name 'luser' -Password $sec } |
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

    It 'Test 12: accepts the menu-splat hashtable shape (PasswordSource parameter declared)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $menuParams = @{
            Name           = 'luser'
            Password       = (New-TestSecureString)
            PasswordSource = 'Generate'
            ComputerName   = $null
        }
        { New-AdmanLocalUser @menuParams -WhatIf } | Should -Not -Throw '*parameter cannot be found*'
    }
}

Describe 'Set-AdmanLocalUser: gate routing + parameter sets (LUSR-01, D-02)' -Tag 'Unit' {

    It 'Test 3: calls Invoke-AdmanLocalMutation with -Verb Set-LocalUser for password reset; sources the password per D-05' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        # The menu path supplies -PasswordSource to request D-05 sourcing on the Reset set.
        Set-AdmanLocalUser -Name 'luser' -PasswordSource 'Generate'

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-LocalUser' -and
            $Parameters['Name'] -eq 'luser' -and
            $Parameters['Password'] -is [securestring]
        }
        Should -Invoke -ModuleName adman New-AdmanRandomPassword -Times 1
    }

    It 'Test 8: routes -Enable to Enable-LocalUser and -Disable to Disable-LocalUser' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Set-AdmanLocalUser -Name 'luser' -Enable
        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Enable-LocalUser'
        }

        Set-AdmanLocalUser -Name 'luser' -Disable
        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Disable-LocalUser'
        }
    }

    It 'Test 6: validates -ComputerName to localhost (throws "Remote targets arrive in Phase 3" on otherhost)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        { Set-AdmanLocalUser -Name 'luser' -Enable -ComputerName 'otherhost' } |
            Should -Throw '*Remote targets arrive in Phase 3*'
    }

    It 'Test 7: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Set-AdmanLocalUser -Name 'luser' -Enable } |
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

    It 'parameter-set resolution: sources a password via D-05 when no switch is supplied' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        # Default 'Reset' set binds with no -Password; D-05 sourcing generates one and
        # routes to the Set-LocalUser gate (WR-02: no throw, no silent no-op).
        { Set-AdmanLocalUser -Name 'luser' -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName adman New-AdmanRandomPassword -Times 1
        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-LocalUser' -and $Parameters['Password'] -is [securestring]
        }
    }

    It 'parameter-set conflict: -Enable and -Disable are mutually exclusive' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        { Set-AdmanLocalUser -Name 'luser' -Enable -Disable -ErrorAction Stop } |
            Should -Throw
    }

    It 'Test 13: accepts the menu-splat hashtable shape (PasswordSource on Reset set declared)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $menuParams = @{
            Name           = 'luser'
            Password       = (New-TestSecureString)
            PasswordSource = 'Generate'
            ComputerName   = $null
        }
        { Set-AdmanLocalUser @menuParams -WhatIf } | Should -Not -Throw '*parameter cannot be found*'
    }
}

Describe 'Remove-AdmanLocalUser: gate routing + irreversibility (LUSR-01, D-03)' -Tag 'Unit' {

    It 'Test 4: calls Invoke-AdmanLocalMutation with -Verb Remove-LocalUser and relies on the gate per-verb threshold override' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }

        Remove-AdmanLocalUser -Name 'luser'

        Should -Invoke -ModuleName adman Invoke-AdmanLocalMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Remove-LocalUser' -and
            $Parameters.ContainsKey('ComputerName')
        }
    }

    It 'Test 5: help text states plainly: irreversible, no Recycle-Bin equivalent' {
        $content = Get-Content $script:RemoveVerbPath -Raw
        $content | Should -Match 'IRREVERSIBLE'
        $content | Should -Match 'no Recycle Bin'
    }

    It 'Test 6: validates -ComputerName to localhost (throws "Remote targets arrive in Phase 3" on otherhost)' {
        Mock -ModuleName adman Invoke-AdmanLocalMutation { }
        { Remove-AdmanLocalUser -Name 'luser' -ComputerName 'otherhost' } |
            Should -Throw '*Remote targets arrive in Phase 3*'
    }

    It 'Test 7: throws the WR-01 init message when uninitialized' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Remove-AdmanLocalUser -Name 'luser' } |
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

Describe 'Local user verbs: manifest export (HIGH #2 review fix)' -Tag 'Unit' {

    It 'Test 11: adman.psd1 FunctionsToExport contains the three local user verbs explicitly' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'New-AdmanLocalUser'
        $content | Should -Match 'Set-AdmanLocalUser'
        $content | Should -Match 'Remove-AdmanLocalUser'
        (Get-Command -Module adman -Name 'New-AdmanLocalUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        (Get-Command -Module adman -Name 'Set-AdmanLocalUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        (Get-Command -Module adman -Name 'Remove-AdmanLocalUser' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
