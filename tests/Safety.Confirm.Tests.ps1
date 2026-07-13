#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED) — SAFE-02 scaled-confirmation tests + SAFE-01 -WhatIf carve-out (C3-H1).

    Confirm-AdmanAction returns an Outcome shape @{ Outcome='Proceed'|'DryRun'|'Declined';
    WhatIf=[bool] } and NEVER writes audit / NEVER throws the decline message (the gate owns
    both). Order is load-bearing: it evaluates [bool]$WhatIfPreference FIRST (truthy under a
    real -WhatIf) BEFORE interpreting a ShouldProcess $false as a decline.

      * Below threshold: single default-No ShouldProcess naming the count. Genuine decline
        (ShouldProcess=$false, NO -WhatIf) -> Outcome='Declined', zero Write-AdmanAudit.
      * At/above threshold: Read-Host exact-count token; refuse (throw 'Confirmation failed')
        when the token does NOT exactly equal the count (-cne). Accept ONLY an exact match.
      * -Force / $ConfirmPreference='None': skip ONLY the prompt -> Outcome='Proceed'.
      * -WhatIf (real): Outcome='DryRun', WhatIf=$true, NO throw, NO Read-Host, NO audit write.
      * NEVER reads the automatic $Confirm variable (StrictMode); uses $ConfirmPreference.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. Write-AdmanAudit
    and Read-Host are mocked (-ModuleName adman); no live domain. Named binding into the
    module-scope scriptblock.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c8'
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
    $script:ConfirmPath = Join-Path $script:RepoRoot 'Private\Safety\Confirm-AdmanAction.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf) }
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
            safety              = [pscustomobject]@{ bulkConfirmThreshold = $BulkConfirmThreshold }
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

    function New-AdmanTargets {
        [CmdletBinding()]
        param([int]$Count)
        $list = [System.Collections.Generic.List[object]]::new()
        for ($i = 1; $i -le $Count; $i++) {
            $list.Add([pscustomobject]@{
                DistinguishedName = "CN=User$i,OU=Managed,DC=mock,DC=local"
                objectSid         = [System.Security.Principal.SecurityIdentifier]"S-1-5-21-111-222-333-1$i"
                objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            })
        }
        return , $list.ToArray()
    }
}

Describe 'SAFE-02: Confirm-AdmanAction scaled confirmation + -WhatIf carve-out (C3-H1)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig -BulkConfirmThreshold 5)
        Mock Write-AdmanAudit -ModuleName adman { }
    }

    It 'below threshold, genuine proceed -> Outcome=Proceed, WhatIf=$false' {
        $targets = New-AdmanTargets -Count 3
        # ShouldProcess proceeds: run with -Confirm:$false so the single ShouldProcess returns $true.
        $r = & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t -Confirm:$false } -t $targets
        $r.Outcome | Should -Be 'Proceed'
        $r.WhatIf | Should -BeFalse
    }

    It 'genuine decline writes nothing (confirm-first): DECLINED shape exists, zero Write-AdmanAudit, no decline-throw in this function' {
        # A genuine operator decline is ShouldProcess=$false WITHOUT -WhatIf. $PSCmdlet.ShouldProcess
        # cannot be mocked directly in Pester, and there is no non-interactive way to make it return
        # $false for a decline (only -WhatIf or an interactive "No" do). The runtime genuine-decline
        # path (Confirm-AdmanAction returns Outcome='Declined'; the gate then throws the decline
        # message and writes ZERO audit records) is proven end-to-end in the Task 3 gate test, where
        # Confirm-AdmanAction is fully mocked to Outcome='Declined'. Here we pin the function-level
        # contract statically: the DECLINED outcome shape exists, and Confirm-AdmanAction itself
        # writes NO audit record and throws NO decline message (the gate owns both - confirm-first
        # means a declined action has no PENDING reservation to orphan, so nothing is audited).
        Test-Path -LiteralPath $script:ConfirmPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ConfirmPath -Raw
        @($src | Select-String -Pattern "Outcome\s*=\s*'Declined'").Count | Should -BeGreaterOrEqual 1 `
            -Because 'a genuine decline yields Outcome=Declined'
        @($src | Select-String -Pattern 'Write-AdmanAudit').Count | Should -Be 0 `
            -Because 'Confirm-AdmanAction never writes audit (the gate owns it; confirm-first -> no orphan PENDING)'
        @($src | Select-String -Pattern "throw\s+['\`"]Operator declined").Count | Should -Be 0 `
            -Because 'the decline throw lives in the gate, not in Confirm-AdmanAction (C3-H1)'
    }

    It 'at/above threshold, exact-count token accepted -> Outcome=Proceed' {
        $targets = New-AdmanTargets -Count 5
        Mock Read-Host -ModuleName adman { '5' }
        $r = & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t } -t $targets
        $r.Outcome | Should -Be 'Proceed'
        $r.WhatIf | Should -BeFalse
    }

    It 'at/above threshold, wrong/off-by-one/empty token REFUSED (throw Confirmation failed): <Name>' -TestCases @(
        @{ Name = 'threshold-1 typed'; Typed = '4' }
        @{ Name = 'threshold+1 typed'; Typed = '6' }
        @{ Name = 'wrong token'; Typed = 'abc' }
        @{ Name = 'empty token'; Typed = '' }
        @{ Name = 'case-mismatch'; Typed = ' 5 ' }
    ) {
        param($Name, $Typed)
        $targets = New-AdmanTargets -Count 5
        Mock Read-Host -ModuleName adman { $Typed }
        { & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t } -t $targets } |
            Should -Throw -ExpectedMessage '*Confirmation failed*' -Because "$Name must refuse (exact-count, -cne)"
    }

    It '-Force skips the prompt -> Outcome=Proceed without Read-Host' {
        $targets = New-AdmanTargets -Count 9
        Mock Read-Host -ModuleName adman { throw 'Read-Host must NOT be called under -Force' }
        $r = & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t -Force } -t $targets
        $r.Outcome | Should -Be 'Proceed'
        Should -Invoke Read-Host -ModuleName adman -Times 0
    }

    It '$ConfirmPreference=None skips the prompt -> Outcome=Proceed without Read-Host' {
        $targets = New-AdmanTargets -Count 9
        Mock Read-Host -ModuleName adman { throw 'Read-Host must NOT be called when ConfirmPreference=None' }
        $r = & (Get-Module adman) {
            param($t)
            $ConfirmPreference = 'None'
            Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t
        } -t $targets
        $r.Outcome | Should -Be 'Proceed'
        Should -Invoke Read-Host -ModuleName adman -Times 0
    }

    It 'REAL -WhatIf below threshold -> Outcome=DryRun, WhatIf=$true, NO throw, NO Read-Host, NO audit write' {
        $targets = New-AdmanTargets -Count 3
        Mock Read-Host -ModuleName adman { throw 'Read-Host must NOT be called under -WhatIf' }
        # Drive with a REAL -WhatIf: the engine sets $WhatIfPreference to a SwitchParameter $true,
        # so [bool]$WhatIfPreference is $true. Do NOT assign $WhatIfPreference='Simulate' (the engine
        # never produces that string).
        $r = & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t -WhatIf } -t $targets
        $r.Outcome | Should -Be 'DryRun'
        $r.WhatIf | Should -BeTrue
        Should -Invoke Read-Host -ModuleName adman -Times 0
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 0 `
            -Because 'a -WhatIf dry-run is NOT a decline and writes no audit record (C3-H1)'
    }

    It 'REAL -WhatIf at/above threshold -> Outcome=DryRun, WhatIf=$true, NO typed-count prompt' {
        $targets = New-AdmanTargets -Count 7
        Mock Read-Host -ModuleName adman { throw 'Read-Host must NOT be called under -WhatIf (even at/above threshold)' }
        $r = & (Get-Module adman) { param($t) Confirm-AdmanAction -Verb 'Disable-ADAccount' -Targets $t -WhatIf } -t $targets
        $r.Outcome | Should -Be 'DryRun'
        $r.WhatIf | Should -BeTrue
        Should -Invoke Read-Host -ModuleName adman -Times 0 `
            -Because 'neither below nor at/above threshold prompts for the typed count under -WhatIf'
    }

    It 'static: discriminator is [bool]$WhatIfPreference (NOT the string -eq Simulate); Outcome shape + WhatIf flag present' {
        Test-Path -LiteralPath $script:ConfirmPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ConfirmPath -Raw
        @($src | Select-String -Pattern '\[bool\]\s*\$WhatIfPreference').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the -WhatIf discriminator is the boolean cast, truthy under a real -WhatIf'
        @($src | Select-String -Pattern "\`$WhatIfPreference\s+-eq\s+'Simulate'").Count | Should -Be 0 `
            -Because 'the engine sets a SwitchParameter $true under -WhatIf, never the string Simulate'
        @($src | Select-String -Pattern "Outcome\s*=\s*'DryRun'").Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern "Outcome\s*=\s*'Proceed'").Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern "Outcome\s*=\s*'Declined'").Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'WhatIf\s*=\s*\$true|WhatIf\s*=\s*\$false').Count | Should -BeGreaterOrEqual 1
    }

    It 'static: correct -cne comparison (refuse on mismatch); NO inverted -ceq throw; NO $Confirm read; ConfirmPreference present' {
        Test-Path -LiteralPath $script:ConfirmPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ConfirmPath -Raw
        @($src | Select-String -Pattern '\-cne\s+"?\$count|\$token\s+-cne').Count | Should -BeGreaterOrEqual 1 `
            -Because 'refuse when the typed token does NOT exactly equal the count (-cne)'
        @($src | Select-String -Pattern '\$Confirm\b').Count | Should -Be 0 `
            -Because 'never read the automatic $Confirm variable (StrictMode, issue #14294)'
        @($src | Select-String -Pattern "\`$ConfirmPreference\s+-eq\s+'None'|\`$ConfirmPreference\s+-ne\s+'None'").Count | Should -BeGreaterOrEqual 1
    }

    It 'static: declares SupportsShouldProcess ConfirmImpact=High and exposes a -Force switch' {
        Test-Path -LiteralPath $script:ConfirmPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ConfirmPath -Raw
        @($src | Select-String -Pattern 'SupportsShouldProcess').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'ConfirmImpact').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern '\[switch\]\$Force').Count | Should -BeGreaterOrEqual 1
    }

    It 'static: no decline-throw and no Cancelled-style record in Confirm-AdmanAction (the gate owns both)' {
        Test-Path -LiteralPath $script:ConfirmPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ConfirmPath -Raw
        @($src | Select-String -Pattern "throw\s+['\`"]Operator declined").Count | Should -Be 0 `
            -Because 'the decline throw lives in the gate, not in Confirm-AdmanAction (C3-H1)'
        @($src | Select-String -Pattern 'Cancelled').Count | Should -Be 0 `
            -Because 'no abort/cancel-style record (confirm-first -> a declined action never starts)'
    }
}
