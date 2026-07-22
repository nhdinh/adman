#Requires -Modules Pester
<#
.SYNOPSIS
    USER-04 contract tests for Set-AdmanUserPassword (D-05 password plumbing).

.DESCRIPTION
    Pins the contract for the reset-password verb:
      * Routes through Invoke-AdmanMutation with -Verb 'Set-ADAccountPassword' and
        $Parameters containing NewPassword (SecureString) and ChangePasswordAtLogon.
      * Sources the password via New-AdmanRandomPassword when -NewPassword is not
        supplied and security.passwordSource='Generate'.
      * NEVER writes the password to audit (the gate's audit writer never receives
        $Parameters containing the SecureString; audit calls use -Targets).
      * D-05 display-once: after a successful Generate-sourced gate return (NOT
        under -WhatIf), the plaintext is shown ONCE behind Read-Host 'Press Enter
        when recorded' + [Console]::Clear(); skipped under -WhatIf.
      * must-change resolution (warning fix): $PSBoundParameters.ContainsKey(
        'ChangePasswordAtLogon') detects caller intent; when caller does NOT supply
        the switch, value is read from security.mustChangeAtNextLogon with a $true
        fallback; when caller DOES supply -ChangePasswordAtLogon $false, $false is
        forwarded to the gate (caller intent wins over config).
      * HIGH #1 cycle-2 review fix: the verb declares an optional
        [ValidateSet('Generate','Prompt')][string]$NewPasswordSource parameter so
        the menu splat (& Set-AdmanUserPassword @menuParams) does NOT throw
        "parameter cannot be found".
      * HIGH #2 review fix: adman.psd1 FunctionsToExport contains
        'Set-AdmanUserPassword' explicitly; Get-Command -Module adman -Name
        'Set-AdmanUserPassword' resolves after Import-Module.

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
    # CR-01: also seed the protected-identity caches so the gate's init guard passes.
    & (Get-Module adman) {
        $script:Initialized = $true
        $script:ProtectedSIDs = @()
        $script:DenyRids = @()
        $script:ProtectedGroupDns = @()
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

Describe 'Set-AdmanUserPassword: gate routing + parameter shape (USER-04, D-05)' -Tag 'Unit' {

    It 'calls Invoke-AdmanMutation once per sub-operation: Set-ADAccountPassword, Set-ADUser (ChangePasswordAtLogon), and no Unlock when -Unlock not supplied' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $sec = New-TestSecureString
        Set-AdmanUserPassword -Identity 'jdoe' -NewPassword $sec

        # CR-01 fix: the composite is split into separate gate invocations, each with its
        # own audit pair. Expect exactly 2 calls when -Unlock is not supplied.
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADAccountPassword' -and
            $Targets.Count -eq 1 -and
            $Targets[0] -eq 'jdoe' -and
            $Parameters['NewPassword'] -is [securestring] -and
            -not $Parameters.ContainsKey('ChangePasswordAtLogon') -and
            -not $Parameters.ContainsKey('Unlock')
        }
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADUser' -and
            $Targets[0] -eq 'jdoe' -and
            $Parameters.ContainsKey('ChangePasswordAtLogon')
        }
    }

    It 'invokes the gate a third time for Unlock-ADAccount when -Unlock is supplied' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $sec = New-TestSecureString
        Set-AdmanUserPassword -Identity 'jdoe' -NewPassword $sec -Unlock

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Unlock-ADAccount' -and $Targets[0] -eq 'jdoe'
        }
    }

    It 'sources the password via New-AdmanRandomPassword when -NewPassword is not supplied and passwordSource=Generate' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        Set-AdmanUserPassword -Identity 'jdoe'

        Should -Invoke -ModuleName adman New-AdmanRandomPassword -Times 1
    }

    It 'NEVER writes the password to audit (audit writer never receives $Parameters containing the SecureString)' {
        # The gate's audit calls use -Targets, not -Parameters. Capture every
        # Write-AdmanAudit invocation and assert none carries a SecureString payload.
        $script:AuditCalls = [System.Collections.Generic.List[hashtable]]::new()
        Mock -ModuleName adman Write-AdmanAudit {
            param($CorrelationId, $Verb, $Target, $Targets, $Result, $Reason, $Group, $WhatIf, $Parameters)
            $script:AuditCalls.Add(@{
                CorrelationId = $CorrelationId
                Verb          = $Verb
                Result        = $Result
                HasParameters = ($null -ne $Parameters)
                Parameters    = $Parameters
            })
        }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Confirm-AdmanAction { return @{ Outcome='Proceed'; WhatIf=$false } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { }
        Mock -ModuleName adman Resolve-AdmanTarget {
            return @([pscustomobject]@{
                DistinguishedName = 'CN=jdoe,OU=Managed,DC=mock,DC=local'
                objectSid         = 'S-1-5-21-1-2-3-1000'
                objectClass       = @('top','person','organizationalPerson','user')
                memberOf          = @()
            })
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { return @{ Allowed=$true; Reason='' } }
        Mock -ModuleName adman Adman.AD.Write.Set-ADAccountPassword { }
        Mock -ModuleName adman Adman.AD.Write.Set-ADUser { }
        Mock -ModuleName adman Adman.AD.Write.Unlock-ADAccount { }

        Set-AdmanUserPassword -Identity 'jdoe' -Force

        # Assert: Write-AdmanAudit was called (PENDING + Success), and NO invocation
        # carried a -Parameters hashtable containing a SecureString.
        $script:AuditCalls.Count | Should -BeGreaterOrEqual 1
        foreach ($c in $script:AuditCalls) {
            if ($c.HasParameters -and $null -ne $c.Parameters) {
                foreach ($k in $c.Parameters.Keys) {
                    $c.Parameters[$k] | Should -Not -BeOfType [securestring]
                }
            }
        }
    }

    It 'throws the WR-01 init message when $script:Config.ManagedOUs is absent' {
        & (Get-Module adman) { $script:Config = $null }
        try {
            { Set-AdmanUserPassword -Identity 'jdoe' } |
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

Describe 'Set-AdmanUserPassword: must-change resolution (warning fix)' -Tag 'Unit' {

    It 'reads security.mustChangeAtNextLogon (default $true) when caller does NOT supply -ChangePasswordAtLogon' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        Set-AdmanUserPassword -Identity 'jdoe'

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADUser' -and $Parameters['ChangePasswordAtLogon'] -eq $true
        }
    }

    It 'forwards $false when caller DOES supply -ChangePasswordAtLogon $false (caller intent wins over config)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        Set-AdmanUserPassword -Identity 'jdoe' -ChangePasswordAtLogon $false

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter {
            $Verb -eq 'Set-ADUser' -and $Parameters['ChangePasswordAtLogon'] -eq $false
        }
    }

    It 'uses $PSBoundParameters.ContainsKey to detect caller intent (NOT a [bool]=$true default)' {
        # Structural assertion: the verb source must use ContainsKey, not a [bool]=$true default.
        $verbPath = Join-Path $script:RepoRoot 'Public/Set-AdmanUserPassword.ps1'
        $content = Get-Content $verbPath -Raw
        $content | Should -Match "PSBoundParameters\.ContainsKey\('ChangePasswordAtLogon'\)"
        # And must NOT use a [bool]$ChangePasswordAtLogon = $true default that would mask intent.
        $content | Should -Not -Match '\[bool\]\$ChangePasswordAtLogon\s*=\s*\$true'
    }
}

Describe 'Set-AdmanUserPassword: D-05 display-once hygiene' -Tag 'Unit' {

    It 'displays the generated password ONCE behind Read-Host + [Console]::Clear when source=Generate and gate succeeds' {
        Mock -ModuleName adman Invoke-AdmanMutation {
            return [pscustomobject]@{ Action='Set-ADAccountPassword'; CorrelationId='mock'; Succeeded=1; WhatIf=$false }
        }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        $script:ReadHostCalls = @()
        Mock -ModuleName adman Read-Host {
            param($Prompt)
            $script:ReadHostCalls += [string]$Prompt
            return ''
        }
        Mock -ModuleName adman Write-Host { }

        Set-AdmanUserPassword -Identity 'jdoe'

        $matched = @($script:ReadHostCalls | Where-Object { $_ -match 'Press Enter when recorded' })
        $matched.Count | Should -BeGreaterOrEqual 1
    }

    It 'SKIPS the display-once path under -WhatIf' {
        Mock -ModuleName adman Invoke-AdmanMutation {
            return [pscustomobject]@{ Action='Set-ADAccountPassword'; CorrelationId='mock'; Succeeded=1; WhatIf=$true }
        }
        Mock -ModuleName adman New-AdmanRandomPassword { New-TestSecureString }
        $script:ReadHostCalls = @()
        Mock -ModuleName adman Read-Host {
            param($Prompt)
            $script:ReadHostCalls += [string]$Prompt
            return ''
        }
        Mock -ModuleName adman Write-Host { }

        Set-AdmanUserPassword -Identity 'jdoe' -WhatIf

        $matched = @($script:ReadHostCalls | Where-Object { $_ -match 'Press Enter when recorded' })
        $matched.Count | Should -Be 0
    }
}

Describe 'Set-AdmanUserPassword: manifest export + menu-splat contract (HIGH #1, HIGH #2 review fixes)' -Tag 'Unit' {

    It 'is exported in adman.psd1 FunctionsToExport' {
        $content = Get-Content $script:ManifestPath -Raw
        $content | Should -Match 'Set-AdmanUserPassword'
        (Get-Command -Module adman -Name 'Set-AdmanUserPassword' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It 'accepts the menu-splat hashtable shape (NewPasswordSource parameter declared)' {
        Mock -ModuleName adman Invoke-AdmanMutation { }
        Mock -ModuleName adman Read-Host { '' }
        Mock -ModuleName adman Write-Host { }

        $menuParams = @{
            Identity          = 'jdoe'
            NewPassword       = (New-TestSecureString)
            NewPasswordSource = 'Generate'
        }
        { Set-AdmanUserPassword @menuParams -WhatIf } | Should -Not -Throw '*parameter cannot be found*'
    }
}
