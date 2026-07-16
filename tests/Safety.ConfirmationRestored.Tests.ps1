#Requires -Modules Pester
<#
.SYNOPSIS
    Plan 02-07 Task 2 - regression tests proving the ShouldProcess prompt is RESTORED on the
    cmdlet path after removing the unconditional -Confirm:$false forwarding at every Public
    mutation verb call site (G-02-5 / SAFE-01 / SAFE-02).

.DESCRIPTION
    Root cause: every Public mutation verb forwarded -Confirm:$false into Invoke-AdmanMutation
    (or Invoke-AdmanLocalMutation). Via dynamic scope that set $ConfirmPreference='None' inside
    the gate, which collapsed the prompt condition at Confirm-AdmanAction.ps1:81
    (-not $Force -and ($ConfirmPreference -ne 'None')) and silently disarmed confirmation for
    all 20 mutation call sites - including the typed-count branch for Remove-LocalUser (D-03).

    Fix: Task 1 removed the -Confirm:$false token from every Public call site. These tests
    prove the fix end-to-end:

      * Test 1: Disable-AdmanUser invoked WITHOUT -Force and WITHOUT -Confirm:$false reaches
        Confirm-AdmanAction with $ConfirmPreference != 'None' (the prompt would fire).
      * Test 2: caller-side -Confirm:$false still bypasses the prompt (dynamic-scope
        inheritance preserved) - Confirm-AdmanAction sees $ConfirmPreference -eq 'None'.
      * Test 3: caller-side -Force still bypasses the prompt - Confirm-AdmanAction receives
        -Force $true.
      * Test 4: Remove-AdmanLocalUser invoked WITHOUT -Force reaches the typed-count branch
        (per-verb threshold override at Confirm-AdmanAction.ps1:58 sets $threshold=1 for
        'Remove-LocalUser'); Read-Host is called and the exact-count token '1' is accepted.
      * Test 5 (REV-4, AST-based): parse each Public/*.ps1 file (excluding Public/Config/*)
        and assert NO Invoke-AdmanMutation / Invoke-AdmanLocalMutation invocation carries a
        -Confirm parameter whose argument is the literal $false. Robust to line-continuation
        formatting changes.
      * Test 6 (REV-4 counter-assertion): the Private wrappers (Adman.AD.Write.ps1 and
        Adman.Local.Write.ps1) STILL contain -Confirm:$false on their inner AD/LocalAccounts
        cmdlet calls. The post-confirm suppression is intact - Task 1 did NOT touch them.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. Mocks import
    from tests/Mocks/ActiveDirectory.psm1. No live domain, no real audit writer.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000cb'
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

    # Mocks for AD cmdlets (offline, no live domain).
    Import-Module (Join-Path $script:RepoRoot 'tests\Mocks\ActiveDirectory.psm1') -Force -ErrorAction Stop

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Resolve-AdmanTarget { param($Targets) }
    function global:Test-AdmanTargetAllowed { param($Object) }
    function global:Assert-AdmanBulkPolicy { param($Count, [switch]$EnforceCap) }
    function global:Confirm-AdmanAction { param($Verb, $Targets, [switch]$Force) }
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf) }
    function global:Adman.AD.Write.Disable-ADAccount { param($Objects, $Parameters) }
    function global:Resolve-AdmanLocalTarget { param($Targets, $ComputerName, $Verb, [switch]$Create) }
    function global:Test-AdmanLocalTargetAllowed { param($Object, $Verb) }
    function global:Adman.Local.Write.Remove-LocalUser { param($Objects, $Parameters) }
    function global:Read-Host { param($Prompt) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param([int]$BulkConfirmThreshold = 5, [int]$BulkMaxCount = 50)
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = 'dc.mock.local'
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{
                bulkConfirmThreshold = $BulkConfirmThreshold
                typedCountVerbs      = @('Remove-LocalUser')
            }
            bulk                = [pscustomobject]@{ maxCount = $BulkMaxCount }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
        }
    }

    function Set-AdmanSafetyState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
        } -Config $Config
    }

    function New-AdmanTarget {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Dn, [string]$Sid = 'S-1-5-21-111-222-333-1000')
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            memberOf          = @()
        }
    }
}

Describe 'G-02-5: ShouldProcess prompt restored on the cmdlet path (SAFE-01/SAFE-02)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig)
    }

    It 'Test 1: Disable-AdmanUser plain invocation -> Confirm-AdmanAction sees $ConfirmPreference -ne ''None''' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:CapturedConfirmPreference = $null
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        # The mock captures the caller-scope $ConfirmPreference via dynamic scope. The mock
        # body runs inside the module's session state, so $ConfirmPreference here is the value
        # the gate sees at the Confirm-AdmanAction call site.
        Mock Confirm-AdmanAction -ModuleName adman {
            param($Verb, $Targets, [switch]$Force)
            $script:CapturedConfirmPreference = $ConfirmPreference
            @{ Outcome = 'Proceed'; WhatIf = $false }
        }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { }

        # Invoke the Public verb through the module so its CmdletBinding sets
        # $ConfirmPreference='High' (ConfirmImpact='High' default). We do NOT pass -Confirm,
        # so the Public verb's $ConfirmPreference remains at its default ('High' under
        # ConfirmImpact='High'). The gate inherits that value via dynamic scope.
        # The mocked Confirm-AdmanAction short-circuits before ShouldProcess fires, so no
        # actual prompt blocks the test runner.
        & (Get-Module adman) {
            Disable-AdmanUser -Identity 'alice'
        }

        $script:CapturedConfirmPreference | Should -Not -BeNullOrEmpty `
            -Because 'Confirm-AdmanAction must be reached (the gate ran)'
        $script:CapturedConfirmPreference | Should -Not -Be 'None' `
            -Because 'the forwarded -Confirm:$false was removed; the gate now inherits the Public verb''s default $ConfirmPreference (High), not None'
    }

    It 'Test 2: caller-side -Confirm:$false still bypasses the prompt (dynamic scope inheritance preserved)' {
        # Use the REAL Confirm-AdmanAction (do NOT mock it) so we prove the actual gate
        # behavior: when $ConfirmPreference='None' reaches Confirm-AdmanAction.ps1:81, the
        # prompt condition (-not $Force -and ($ConfirmPreference -ne 'None')) evaluates to
        # $false and the function returns Outcome='Proceed' WITHOUT calling ShouldProcess.
        #
        # We cannot capture $ConfirmPreference inside a -ModuleName mock body because Pester's
        # module-scoped mock machinery runs the mock body in a fresh scope that does NOT
        # preserve the caller's $ConfirmPreference via dynamic scope (verified by probe).
        # Instead we prove the BEHAVIOR: the mutation completes (wrapper is called) without
        # any prompt, which is only possible if Confirm-AdmanAction saw $ConfirmPreference='None'.
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { }

        # If the prompt were NOT bypassed, the real Confirm-AdmanAction would call
        # $PSCmdlet.ShouldProcess(...) which, under $ConfirmPreference='High' (the wrong
        # inherited value), would prompt and block the test runner. The fact that this call
        # completes proves the prompt was bypassed.
        { & (Get-Module adman) {
            Disable-AdmanUser -Identity 'alice' -Confirm:$false
        } } | Should -Not -Throw `
            -Because 'caller-side -Confirm:$false sets $ConfirmPreference=''None'' in the Public verb scope; that value flows through dynamic scope to the gate and bypasses the prompt'

        # The wrapper MUST have been called (the mutation proceeded).
        Should -Invoke Adman.AD.Write.Disable-ADAccount -ModuleName adman -Times 1 `
            -Because 'the mutation must proceed when the prompt is bypassed'
    }

    It 'Test 3: caller-side -Force still bypasses the prompt' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:CapturedForce = $null
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman {
            param($Verb, $Targets, [switch]$Force)
            $script:CapturedForce = [bool]$Force
            @{ Outcome = 'Proceed'; WhatIf = $false }
        }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { }

        & (Get-Module adman) {
            Disable-AdmanUser -Identity 'alice' -Force
        }

        $script:CapturedForce | Should -BeTrue `
            -Because '-Force is forwarded to Confirm-AdmanAction (prompt bypass); deny/protected/scope/cap are not flag-bypassable'
    }

    It 'Test 4: Remove-AdmanLocalUser plain invocation reaches the typed-count branch (D-03); exact-count token accepted' {
        # Use the REAL Confirm-AdmanAction (do NOT mock it) so the typed-count branch is
        # exercised end-to-end. Mock Read-Host to return the exact-count token '1'.
        $localTarget = [pscustomobject]@{
            Machine  = $env:COMPUTERNAME
            Name     = 'luser'
            SID      = 'S-1-5-21-111-222-333-1001'
            LocalRid = '1001'
            Enabled  = $true
        }
        $script:ReadHostCalled = $false
        Mock Resolve-AdmanLocalTarget -ModuleName adman { $localTarget }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Read-Host -ModuleName adman {
            param($Prompt)
            $script:ReadHostCalled = $true
            return '1'
        }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.Local.Write.Remove-LocalUser -ModuleName adman { }

        # Plain invocation: no -Force, no -Confirm:$false. The Public verb's ConfirmImpact='High'
        # sets $ConfirmPreference='High'; the gate inherits it; Confirm-AdmanAction.ps1:81
        # evaluates ($ConfirmPreference -ne 'None') as $true; the per-verb threshold override
        # (line 58) sets $threshold=1 for 'Remove-LocalUser'; count=1 >= threshold=1 -> typed-
        # count branch fires -> Read-Host is called.
        { & (Get-Module adman) {
            Remove-AdmanLocalUser -Name 'luser'
        } } | Should -Not -Throw -Because 'the exact-count token ''1'' matches count=1'

        $script:ReadHostCalled | Should -BeTrue `
            -Because 'the typed-count branch (D-03) must fire for Remove-LocalUser at count=1'
    }

    It 'Test 5 (REV-4, AST): no Public verb forwards -Confirm:$false into Invoke-AdmanMutation / Invoke-AdmanLocalMutation' {
        $publicFiles = Get-ChildItem -Path (Join-Path $script:RepoRoot 'Public') -Filter *.ps1 -Recurse |
            Where-Object { $_.FullName -notmatch '\\Config\\' }
        $publicFiles | Should -Not -BeNullOrEmpty

        foreach ($file in $publicFiles) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object { $_.GetCommandName() -in @('Invoke-AdmanMutation', 'Invoke-AdmanLocalMutation') }
            foreach ($c in $cmds) {
                for ($i = 0; $i -lt $c.CommandElements.Count; $i++) {
                    $el = $c.CommandElements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'Confirm') {
                        $arg = $c.CommandElements[$i + 1]
                        $arg.Extent.Text | Should -Not -BeExactly '$false' `
                            -Because "$($file.Name) must not forward -Confirm:`$false into the gate (G-02-5)"
                    }
                }
            }
        }
    }

    It 'Test 6 (REV-4 counter-assertion): Private wrappers STILL carry -Confirm:$false (post-confirm suppression intact)' {
        $adWrapperPath = Join-Path $script:RepoRoot 'Private\AD\Adman.AD.Write.ps1'
        $localWrapperPath = Join-Path $script:RepoRoot 'Private\Local\Adman.Local.Write.ps1'

        Test-Path -LiteralPath $adWrapperPath | Should -BeTrue
        Test-Path -LiteralPath $localWrapperPath | Should -BeTrue

        $adSrc = Get-Content -LiteralPath $adWrapperPath -Raw
        $localSrc = Get-Content -LiteralPath $localWrapperPath -Raw

        # The wrappers' inner -Confirm:$false on the raw AD/LocalAccounts cmdlets is CORRECT:
        # the gate has already confirmed once, so the per-object re-prompt must remain
        # suppressed. Task 1 must NOT have touched these files.
        ([regex]::Matches($adSrc, [regex]::Escape('-Confirm:$false'))).Count |
            Should -BeGreaterOrEqual 1 `
            -Because 'Adman.AD.Write.ps1 must still suppress the per-object re-prompt on the raw AD cmdlets'
        ([regex]::Matches($localSrc, [regex]::Escape('-Confirm:$false'))).Count |
            Should -BeGreaterOrEqual 1 `
            -Because 'Adman.Local.Write.ps1 must still suppress the per-object re-prompt on the raw LocalAccounts cmdlets'
    }
}
