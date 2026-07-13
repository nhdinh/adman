#Requires -Modules Pester
<#
.SYNOPSIS
    Task 3 (RED) — SAFE-08 mutation-gate order + behavior tests (Invoke-AdmanMutation).

    The gate runs the FIXED order:
      Resolve-AdmanTarget -> Test-AdmanTargetAllowed (per target) -> Assert-AdmanBulkPolicy ->
      Confirm-AdmanAction -> Write-AdmanAudit(PENDING) -> Adman.AD.Write.<Verb> ->
      Write-AdmanAudit(OUTCOME/Success).
    Proven under FULL mocking (no real audit writer, no live domain):
      * Test 1: fixed order via a call-sequence log.
      * Test 2: ValidateSet == Get-AdmanAllowedWriteVerbs (9 verbs); a non-allow-listed verb
        (incl. the hard-delete verb) is rejected by parameter validation before any AD call.
      * Test 3: a refused target writes a 'Refused' audit record and skips the AD write wrapper.
      * Test 4: PENDING is written BEFORE the write; if PENDING throws, the write never runs.
      * Test 5: -WhatIf flow (Confirm returns DryRun/WhatIf=$true) -> PENDING(whatIf=$true) ->
        wrapper WITH -WhatIf:$true -> OUTCOME(whatIf=$true); NO decline throw. NEGATIVE: a
        genuine decline (Outcome='Declined') -> gate throws the decline message and writes ZERO
        audit records (confirm-first, no orphan PENDING).
      * Test 6: canonical result object with a non-empty CorrelationId shared by PENDING+OUTCOME.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. ALL collaborators
    mocked (-ModuleName adman); no live domain, no real audit writer. Named binding into the
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
    GUID              = 'b0000000-0000-0000-0000-0000000000ca'
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
    $script:GatePath = Join-Path $script:RepoRoot 'Private\Safety\Invoke-AdmanMutation.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Resolve-AdmanTarget { param($Targets) }
    function global:Test-AdmanTargetAllowed { param($Object) }
    function global:Assert-AdmanBulkPolicy { param($Count, [switch]$EnforceCap) }
    function global:Confirm-AdmanAction { param($Verb, $Targets, [switch]$Force) }
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf) }
    function global:Adman.AD.Write.Disable-ADAccount { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Enable-ADAccount { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Move-ADObject { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Set-ADUser { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Set-ADComputer { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Set-ADAccountPassword { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Unlock-ADAccount { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Add-ADGroupMember { param($Objects, $Parameters) }
    function global:Adman.AD.Write.Remove-ADGroupMember { param($Objects, $Parameters) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param([int]$BulkConfirmThreshold = 5, [int]$BulkMaxCount = 50, [string]$DC = 'dc.mock.local')
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = $DC
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

    # Test-script-scope call-sequence recorder (Pester -ModuleName mock bodies run in the test
    # file's script scope, so this list is visible to the mocks - see 00-03 Deviation 2).
    function Reset-AdmanOrder { $script:AdmanOrder = [System.Collections.Generic.List[string]]::new() }
    function Get-AdmanOrder { return $script:AdmanOrder.ToArray() }
}

Describe 'SAFE-08: Invoke-AdmanMutation fixed order + behavior (THE GATE)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig)
        Reset-AdmanOrder
    }

    It 'Test 1: runs the fixed order Resolve -> Allow -> BulkPolicy -> Confirm -> Audit(PENDING) -> Write -> Audit(OUTCOME)' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $script:AdmanOrder.Add('resolve'); , @($t1) }
        Mock Test-AdmanTargetAllowed -ModuleName adman { $script:AdmanOrder.Add('allow'); @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { $script:AdmanOrder.Add('bulkpolicy'); @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { $script:AdmanOrder.Add('confirm'); @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf)
            $script:AdmanOrder.Add("audit-$Result")
        }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { $script:AdmanOrder.Add('write') }

        $null = & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -Confirm:$false }

        $order = Get-AdmanOrder
        $order | Should -Be @('resolve', 'allow', 'bulkpolicy', 'confirm', 'audit-PENDING', 'write', 'audit-Success')
    }

    It 'Test 2: ValidateSet equals Get-AdmanAllowedWriteVerbs; a non-allow-listed verb is rejected before any AD call' {
        $allowed = & (Get-Module adman) { Get-AdmanAllowedWriteVerbs }
        # Read the gate's ValidateSet via AST.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:GatePath, [ref]$tokens, [ref]$errors)
        $validateSet = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.AttributeAst] -and
                $n.TypeName.Name -eq 'ValidateSet' }, $true) | Select-Object -First 1
        $validateSet | Should -Not -BeNullOrEmpty -Because 'the gate must declare a ValidateSet on -Verb'
        $setValues = $validateSet.PositionalArguments | ForEach-Object { $_.Extent.Text.Trim("'") }
        foreach ($v in $allowed) { $setValues | Should -Contain $v }
        @($setValues).Count | Should -Be @($allowed).Count
        $setValues | Should -Not -Contain 'Remove-ADObject'

        # Runtime: a non-allow-listed verb is rejected by parameter validation before any AD call.
        Mock Resolve-AdmanTarget -ModuleName adman { throw 'Resolve must NOT run for an invalid verb' }
        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Remove-ADObject' -Targets @('x') -Confirm:$false } } |
            Should -Throw -Because 'the hard-delete verb is not in the allow-list (SAFE-09)'
        Should -Invoke Resolve-AdmanTarget -ModuleName adman -Times 0
    }

    It 'Test 3: a refused target writes a Refused audit record and skips the AD write wrapper' {
        $tAllowed = New-AdmanTarget -Dn 'CN=Ok,OU=Managed,DC=mock,DC=local'
        $tDenied = New-AdmanTarget -Dn 'CN=Bad,OU=Managed,DC=mock,DC=local' -Sid 'S-1-5-21-111-222-333-1001'
        Mock Resolve-AdmanTarget -ModuleName adman { , @($tAllowed, $tDenied) }
        Mock Test-AdmanTargetAllowed -ModuleName adman {
            param($Object)
            if ($Object.DistinguishedName -eq 'CN=Bad,OU=Managed,DC=mock,DC=local') {
                @{ Allowed = $false; Reason = 'deny-listed RID 500' }
            } else { @{ Allowed = $true; Reason = '' } }
        }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { }

        $null = & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('ok', 'bad') -Confirm:$false }

        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Refused' -and $Reason -match 'deny-listed'
        } -Because 'a refused target is logged with its Reason'
        # The write wrapper runs only for the allowed target (1 call), not the denied one.
        Should -Invoke Adman.AD.Write.Disable-ADAccount -ModuleName adman -Times 1 -ParameterFilter {
            (@($Objects).Count -eq 1) -and ($Objects[0].DistinguishedName -eq 'CN=Ok,OU=Managed,DC=mock,DC=local')
        } -Because 'the denied target must not reach the AD write wrapper'
    }

    It 'Test 4: PENDING is written BEFORE the write; if PENDING throws, the write never runs' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { , @($t1) }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf)
            if ($Result -eq 'PENDING') { throw 'AUDIT FAIL-CLOSED: cannot write PENDING' }
        }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { throw 'WRITE MUST NOT RUN when PENDING fails' }

        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -Confirm:$false } } |
            Should -Throw -ExpectedMessage '*PENDING*'
        Should -Invoke Adman.AD.Write.Disable-ADAccount -ModuleName adman -Times 0 `
            -Because 'a PENDING-write failure refuses the action BEFORE the mutation (SAFE-04)'
    }

    It 'Test 5: -WhatIf flow -> PENDING(whatIf=$true) -> wrapper WITH -WhatIf:$true -> OUTCOME(whatIf=$true); NO decline throw' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:WrapperWhatIf = $null
        Mock Resolve-AdmanTarget -ModuleName adman { , @($t1) }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'DryRun'; WhatIf = $true } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman {
            param($Objects, $Parameters, [switch]$WhatIf)
            $script:WrapperWhatIf = [bool]$WhatIf
        }

        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -WhatIf } } |
            Should -Not -Throw -Because 'a -WhatIf dry-run is NOT a decline (C3-H1)'

        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'PENDING' -and [bool]$WhatIf
        } -Because 'the PENDING record carries whatIf=$true under a dry-run'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Success' -and [bool]$WhatIf
        } -Because 'the OUTCOME record carries whatIf=$true under a dry-run'
        $script:WrapperWhatIf | Should -BeTrue -Because 'the inner wrapper received -WhatIf:$true (truthful preview, no mutation)'
    }

    It 'Test 5 (negative): a genuine decline -> gate throws the decline message and writes ZERO audit records' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { , @($t1) }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Declined'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { throw 'WRITE MUST NOT RUN on a decline' }

        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -Confirm:$false } } |
            Should -Throw -ExpectedMessage '*declined*'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 0 `
            -Because 'a declined action writes NO audit record of any kind (confirm-first -> no orphan PENDING)'
        Should -Invoke Adman.AD.Write.Disable-ADAccount -ModuleName adman -Times 0
    }

    It 'Test 6: returns a canonical result with a non-empty CorrelationId shared by PENDING + OUTCOME' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:AuditCids = [System.Collections.Generic.List[string]]::new()
        Mock Resolve-AdmanTarget -ModuleName adman { , @($t1) }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf)
            $script:AuditCids.Add($CorrelationId)
        }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { }

        $result = & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -Confirm:$false }

        $result.Action | Should -Be 'Disable-ADAccount'
        $result.Succeeded | Should -Be 1
        $result.Failed | Should -Be 0
        $result.CorrelationId | Should -Not -BeNullOrEmpty
        { [guid]::Parse($result.CorrelationId) } | Should -Not -Throw
        # PENDING + OUTCOME share the same CorrelationId.
        @($script:AuditCids | Select-Object -Unique).Count | Should -Be 1
        ($script:AuditCids[0]) | Should -Be $result.CorrelationId
    }

    It 'static: gate is NOT exported; fixed order present in source; PENDING precedes the write; no direct AD write cmdlet; Outcome branching' {
        Test-Path -LiteralPath $script:GatePath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:GatePath -Raw

        # Not exported.
        $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw
        @($manifest | Select-String -Pattern 'Invoke-AdmanMutation').Count | Should -Be 0 `
            -Because 'the gate is Private/ and NOT in FunctionsToExport (SAFE-08)'

        # Fixed order present.
        foreach ($tok in @('Resolve-AdmanTarget', 'Test-AdmanTargetAllowed', 'Assert-AdmanBulkPolicy', 'Confirm-AdmanAction', "'PENDING'", 'Adman.AD.Write', "'Success'")) {
            @($src | Select-String -Pattern [regex]::Escape($tok)).Count | Should -BeGreaterOrEqual 1 -Because "$tok must appear in the gate"
        }
        # PENDING textually precedes the write call.
        $pendingIdx = $src.IndexOf("'PENDING'")
        $writeIdx = $src.IndexOf('Adman.AD.Write.')
        $pendingIdx | Should -BeLessThan $writeIdx -Because 'the PENDING audit reservation precedes the write (write-ahead)'

        # No direct AD write cmdlet in the gate (only via Adman.AD.Write.*).
        @($src | Select-String -Pattern '\bSet-ADUser\b|\bSet-ADComputer\b|\bDisable-ADAccount\b|\bEnable-ADAccount\b|\bMove-ADObject\b|\bSet-ADAccountPassword\b|\bUnlock-ADAccount\b|\bAdd-ADGroupMember\b|\bRemove-ADGroupMember\b|\bNew-ADUser\b|\bNew-ADComputer\b').Count |
            Should -Be 0 -Because 'the gate only calls Adman.AD.Write.*, never a real AD write cmdlet directly'

        # Outcome branching (C3-H1): branches on $confirm.Outcome; throws the decline message on Declined;
        # forwards -WhatIf:$confirm.WhatIf to PENDING/OUTCOME/write.
        @($src | Select-String -Pattern '\$confirm\.Outcome|Outcome\s+-eq\s+''Declined''').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern "throw\s+['\`"]Operator declined").Count | Should -BeGreaterOrEqual 1
        [regex]::Matches($src, '\$confirm\.WhatIf').Count | Should -BeGreaterOrEqual 3 `
            -Because 'PENDING, OUTCOME, and the write all forward the confirm WhatIf flag'
    }
}
