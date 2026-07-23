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
    function global:Confirm-AdmanAction { param($Verb, $Targets, [switch]$Force, [switch]$WhatIf) }
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
            $script:Initialized = $true
            $script:ProtectedSIDs = @()
            $script:DenyRids = @()
            $script:ProtectedGroupDns = @()
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
        Mock Resolve-AdmanTarget -ModuleName adman { $script:AdmanOrder.Add('resolve'); $t1 }
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
        $script:WrittenDns = $null
        Mock Resolve-AdmanTarget -ModuleName adman { $tAllowed; $tDenied }
        Mock Test-AdmanTargetAllowed -ModuleName adman {
            param($Object)
            if ($Object.DistinguishedName -eq 'CN=Bad,OU=Managed,DC=mock,DC=local') {
                @{ Allowed = $false; Reason = 'deny-listed RID 500' }
            } else { @{ Allowed = $true; Reason = '' } }
        }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman {
            param($Objects, $Parameters)
            $script:WrittenDns = @($Objects | ForEach-Object { $_.DistinguishedName })
        }

        $null = & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('ok', 'bad') -Confirm:$false }

        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Refused' -and $Reason -match 'deny-listed'
        } -Because 'a refused target is logged with its Reason'
        # The write wrapper runs once, and ONLY for the allowed target (the denied DN never reaches it).
        Should -Invoke Adman.AD.Write.Disable-ADAccount -ModuleName adman -Times 1 `
            -Because 'the write wrapper runs once for the allowed set'
        $script:WrittenDns | Should -Be @('CN=Ok,OU=Managed,DC=mock,DC=local') `
            -Because 'the denied target must not reach the AD write wrapper'
    }

    It 'Test 4: PENDING is written BEFORE the write; if PENDING throws, the write never runs' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
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
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
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

    It 'Test 5b: caller -WhatIf is forwarded into Confirm-AdmanAction and the inner wrapper' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:ConfirmWhatIf = $null
        $script:WrapperWhatIf = $null
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman {
            param($Verb, $Targets, [switch]$Force, [switch]$WhatIf)
            $script:ConfirmWhatIf = [bool]$WhatIf
            @{ Outcome = 'DryRun'; WhatIf = $true }
        }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman {
            param($Objects, $Parameters, [switch]$WhatIf)
            $script:WrapperWhatIf = [bool]$WhatIf
        }

        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -WhatIf } } |
            Should -Not -Throw -Because 'the gate must accept caller -WhatIf and treat it as a dry-run'

        $script:ConfirmWhatIf | Should -BeTrue `
            -Because 'the caller -WhatIf must be bound to Confirm-AdmanAction -WhatIf'
        $script:WrapperWhatIf | Should -BeTrue `
            -Because 'the wrapper must receive -WhatIf:$true when Confirm-AdmanAction returns DryRun'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'PENDING' -and [bool]$WhatIf
        } -Because 'the PENDING record carries whatIf=$true under a dry-run'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Success' -and [bool]$WhatIf
        } -Because 'the OUTCOME record carries whatIf=$true under a dry-run'
    }

    It 'Test 5 (negative): a genuine decline -> gate throws the decline message and writes ZERO audit records' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
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
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
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

        # Not exported: the gate must be absent from the manifest's FunctionsToExport array
        # (comments may mention it; only the export list is the boundary). Test-ModuleManifest
        # works on PS 5.1 (Import-PowerShellDataFile does not) and returns the exported commands;
        # the PSFramework stub on $TestDrive (BeforeAll) makes the exact-pinned dependency resolvable.
        $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
        $exported = @($manifest.ExportedFunctions.Keys)
        $exported | Should -Not -Contain 'Invoke-AdmanMutation' `
            -Because 'the gate is Private/ and NOT in FunctionsToExport (SAFE-08)'

        # Fixed order present. ($src is a -Raw string; Select-String over a single string binds
        # one MatchInfo per pattern, not per occurrence, and can fail to bind - use [regex]::Matches.)
        foreach ($tok in @('Resolve-AdmanTarget', 'Test-AdmanTargetAllowed', 'Assert-AdmanBulkPolicy', 'Confirm-AdmanAction', "'PENDING'", 'Adman.AD.Write', "'Success'")) {
            [regex]::Matches($src, [regex]::Escape($tok)).Count | Should -BeGreaterOrEqual 1 -Because "$tok must appear in the gate"
        }
        # PENDING textually precedes the write call. Use the actual CALL sites (the doc comment
        # also mentions 'PENDING' and the wrapper invocation, so a naive IndexOf on the bare token
        # would match the comment first). Anchor on the real statements: the PENDING audit call and
        # the dynamic wrapper invocation with its -Objects argument (unique to the code, not the doc).
        $pendingIdx = $src.IndexOf("-Result 'PENDING'")
        $writeIdx = $src.IndexOf('& "Adman.AD.Write.$Verb" -Objects')
        $pendingIdx | Should -BeGreaterOrEqual 0 -Because 'the gate writes a PENDING audit reservation'
        $writeIdx | Should -BeGreaterOrEqual 0 -Because 'the gate invokes the Adman.AD.Write.<Verb> wrapper'
        $pendingIdx | Should -BeLessThan $writeIdx -Because 'the PENDING audit reservation precedes the write (write-ahead)'

        # No direct AD write cmdlet CALL in the gate (only via Adman.AD.Write.*). The ValidateSet
        # lists the 9 verbs as quoted string literals and the doc comment names them - neither is a
        # call. A real invocation is the verb followed by a parameter (' -'); a quoted list entry or
        # comment mention is not. Require the verb be immediately followed by whitespace + '-'.
        [regex]::Matches($src, '\b(?:Set-ADUser|Set-ADComputer|Disable-ADAccount|Enable-ADAccount|Move-ADObject|Set-ADAccountPassword|Unlock-ADAccount|Add-ADGroupMember|Remove-ADGroupMember|New-ADUser|New-ADComputer)\s+-').Count |
            Should -Be 0 -Because 'the gate only calls Adman.AD.Write.*, never a real AD write cmdlet directly'

        # Outcome branching (C3-H1): branches on $confirm.Outcome; throws the decline message on Declined;
        # forwards -WhatIf:$confirm.WhatIf to PENDING/OUTCOME/write.
        [regex]::Matches($src, '\$confirm\.Outcome|Outcome\s+-eq\s+''Declined''').Count | Should -BeGreaterOrEqual 1
        [regex]::Matches($src, "throw\s+['\`"]Operator declined").Count | Should -BeGreaterOrEqual 1
        [regex]::Matches($src, '\$confirm\.WhatIf').Count | Should -BeGreaterOrEqual 3 `
            -Because 'PENDING, OUTCOME, and the write all forward the confirm WhatIf flag'
    }

    It 'Test 7: New-ADUser routes through Resolve-AdmanCreateTarget (not Resolve-AdmanTarget); Test-AdmanTargetAllowed receives IsSynthetic=$true' {
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'alice'
            Name              = 'Alice'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        $script:SyntheticSeen = $null
        Mock Resolve-AdmanCreateTarget -ModuleName adman { $script:AdmanOrder.Add('resolve-create'); $synthetic }
        Mock Resolve-AdmanTarget -ModuleName adman { throw 'Resolve-AdmanTarget must NOT run for New-ADUser (D-01)' }
        Mock Test-AdmanTargetAllowed -ModuleName adman {
            param($Object)
            $script:SyntheticSeen = $Object
            $script:AdmanOrder.Add('allow')
            @{ Allowed = $true; Reason = '' }
        }
        Mock Get-ADObject -ModuleName adman { $null }   # uniqueness pre-flight: no collision
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.AD.Write.New-ADUser -ModuleName adman { }

        $null = & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'New-ADUser' -Targets @('alice') `
                -Parameters @{ Name = 'Alice'; SamAccountName = 'alice'; ParentOuDn = 'OU=Managed,DC=mock,DC=local' } `
                -Confirm:$false
        }

        Should -Invoke Resolve-AdmanCreateTarget -ModuleName adman -Times 1 `
            -Because 'New-ADUser must route through the synthetic pre-create resolver (D-01)'
        Should -Invoke Resolve-AdmanTarget -ModuleName adman -Times 0
        $script:SyntheticSeen.IsSynthetic | Should -BeTrue `
            -Because 'Test-AdmanTargetAllowed must receive the IsSynthetic=$true synthetic object'
    }

    It 'Test 8: create-branch skips gMSA/deny-RID/protected-membership; runs ONLY managed-OU scope against parent OU DN; out-of-scope parent refuses' {
        # The create-branch logic is INSIDE Test-AdmanTargetAllowed (the real one, not a mock).
        # Build a synthetic target whose parent OU is OUTSIDE managed scope and call the real
        # Test-AdmanTargetAllowed via the module.
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                DC         = 'dc.mock.local'
            }
            $script:DenyRids = @('500', '501', '502')
            $script:ProtectedGroupDns = @()
        }
        $syntheticOutOfScope = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=NotManaged,DC=mock,DC=local'
            SamAccountName    = 'alice'
            Name              = 'Alice'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=NotManaged,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        $decision = & (Get-Module adman) {
            param($O) Test-AdmanTargetAllowed -Object $O
        } -O $syntheticOutOfScope
        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'parent OU outside managed-OU scope'

        # In-scope parent OU -> allowed (proves gMSA/deny-RID/protected-membership are SKIPPED
        # for synthetic targets: objectSid is null and memberOf is empty, yet the decision is
        # Allowed=$true, so those checks did not run / did not refuse).
        $syntheticInScope = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'alice'
            Name              = 'Alice'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        $decision2 = & (Get-Module adman) {
            param($O) Test-AdmanTargetAllowed -Object $O
        } -O $syntheticInScope
        $decision2.Allowed | Should -BeTrue `
            -Because 'an in-scope synthetic target skips gMSA/deny-RID/protected-membership and passes the parent-OU scope check'
    }

    It 'Test 9: drift triple - Get-AdmanAllowedWriteVerbs == gate ValidateSet == Adman.AD.Write.* wrapper set (with New-ADUser)' {
        $allowed = & (Get-Module adman) { Get-AdmanAllowedWriteVerbs }
        $allowed | Should -Contain 'New-ADUser'

        # Gate ValidateSet.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:GatePath, [ref]$tokens, [ref]$errors)
        $validateSet = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.AttributeAst] -and
                $n.TypeName.Name -eq 'ValidateSet' }, $true) | Select-Object -First 1
        $setValues = @($validateSet.PositionalArguments | ForEach-Object { $_.Extent.Text.Trim("'") })
        foreach ($v in $allowed) { $setValues | Should -Contain $v }
        @($setValues).Count | Should -Be @($allowed).Count

        # Wrapper set: every allowed verb has a matching Adman.AD.Write.<Verb> function.
        $wrapperPath = Join-Path $script:RepoRoot 'Private\AD\Adman.AD.Write.ps1'
        $wrapperSrc = Get-Content -LiteralPath $wrapperPath -Raw
        foreach ($v in $allowed) {
            $wrapperSrc | Should -Match "function\s+Adman\.AD\.Write\.$([regex]::Escape($v))\b" `
                -Because "wrapper Adman.AD.Write.$v must exist"
        }
    }

    It 'Test 10: Test-AdmanGroupAllowed refuses a group whose objectSid is in $script:ProtectedSIDs when Operation=Add-ADGroupMember (direct SID equality)' {
        & (Get-Module adman) {
            $script:ProtectedSIDs = @('S-1-5-21-111-222-333-512')
            $script:DenyRids = @('500', '501', '502')
        }
        $protectedGroup = [pscustomobject]@{
            DistinguishedName = 'CN=Domain Admins,CN=Users,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-512'
            objectClass       = @('top', 'group')
        }
        $decision = & (Get-Module adman) {
            param($G) Test-AdmanGroupAllowed -Object $G -Operation 'Add-ADGroupMember'
        } -G $protectedGroup
        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'protected'
    }

    It 'Test 11: Test-AdmanGroupAllowed SKIPS protected-SID check when Operation=Remove-ADGroupMember (asymmetric remediation) but still applies deny-RID and gMSA checks' {
        & (Get-Module adman) {
            $script:ProtectedSIDs = @('S-1-5-21-111-222-333-512')
            $script:DenyRids = @('500', '501', '502')
        }
        $protectedGroup = [pscustomobject]@{
            DistinguishedName = 'CN=Domain Admins,CN=Users,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-512'
            objectClass       = @('top', 'group')
        }
        $decision = & (Get-Module adman) {
            param($G) Test-AdmanGroupAllowed -Object $G -Operation 'Remove-ADGroupMember'
        } -G $protectedGroup
        $decision.Allowed | Should -BeTrue `
            -Because 'removing a principal FROM a protected group is remediation and is ALLOWED (D-04 asymmetry)'

        # deny-RID still applies on Remove.
        $denyRidGroup = [pscustomobject]@{
            DistinguishedName = 'CN=Administrator,CN=Users,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-500'
            objectClass       = @('top', 'group')
        }
        $decision2 = & (Get-Module adman) {
            param($G) Test-AdmanGroupAllowed -Object $G -Operation 'Remove-ADGroupMember'
        } -G $denyRidGroup
        $decision2.Allowed | Should -BeFalse
        $decision2.Reason | Should -Match 'deny-listed RID 500'
    }

    It 'Test 12: Test-AdmanGroupAllowed refuses a group whose SID RID is in $script:DenyRids regardless of Operation' {
        & (Get-Module adman) {
            $script:ProtectedSIDs = @()
            $script:DenyRids = @('500', '501', '502')
        }
        $denyGroup = [pscustomobject]@{
            DistinguishedName = 'CN=Guest,CN=Users,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-501'
            objectClass       = @('top', 'group')
        }
        foreach ($op in @('Add-ADGroupMember', 'Remove-ADGroupMember')) {
            $decision = & (Get-Module adman) {
                param($G, $Op) Test-AdmanGroupAllowed -Object $G -Operation $Op
            } -G $denyGroup -Op $op
            $decision.Allowed | Should -BeFalse -Because "deny-RID applies on $op"
            $decision.Reason | Should -Match 'deny-listed RID 501'
        }
    }

    It 'Test 13: uniqueness pre-flight - sAMAccountName OR CN collision refuses BEFORE confirm with a precise reason' {
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'alice'
            Name              = 'Alice'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        Mock Resolve-AdmanCreateTarget -ModuleName adman { $synthetic }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        # sAMAccountName collision: the FIRST Get-ADObject call (sAMAccountName lookup) returns a hit.
        Mock Get-ADObject -ModuleName adman {
            param($Identity, $Filter, $SearchBase, $SearchScope, $Server, $LDAPFilter, $Properties)
            if ($Filter -match 'sAMAccountName') { return [pscustomobject]@{ DistinguishedName = 'CN=Existing,OU=Managed,DC=mock,DC=local' } }
            return $null
        }
        Mock Confirm-AdmanAction -ModuleName adman { throw 'Confirm must NOT run when uniqueness pre-flight refuses' }
        Mock Write-AdmanAudit -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'New-ADUser' -Targets @('alice') `
                -Parameters @{ Name = 'Alice'; SamAccountName = 'alice'; ParentOuDn = 'OU=Managed,DC=mock,DC=local' } `
                -Confirm:$false
        } } | Should -Throw -ExpectedMessage "*sAMAccountName 'alice' already exists*"
        Should -Invoke Confirm-AdmanAction -ModuleName adman -Times 0 `
            -Because 'the uniqueness pre-flight refuses BEFORE confirm'
    }

    It 'Test 14: Adman.AD.Write.New-ADUser consumes $Parameters[''ChangePasswordAtLogon''] (NOT hardcoded $true); falls back to config when absent' {
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                DC       = 'dc.mock.local'
                security = [pscustomobject]@{ mustChangeAtNextLogon = $false }
            }
        }
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'alice'
            Name              = 'Alice'
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
        }
        $script:CapturedChangePwd = $null
        Mock New-ADUser -ModuleName adman {
            param($Name, $SamAccountName, $UserPrincipalName, $Path, $AccountPassword, $Enabled, $ChangePasswordAtLogon, $Server)
            $script:CapturedChangePwd = $ChangePasswordAtLogon
        }

        # Explicit $false from caller.
        & (Get-Module adman) {
            param($O) Adman.AD.Write.New-ADUser -Objects @($O) -Parameters @{
                UserPrincipalName = 'alice@mock.local'
                AccountPassword   = ([securestring]::new())
                ChangePasswordAtLogon = $false
            } -Confirm:$false
        } -O $synthetic
        $script:CapturedChangePwd | Should -BeFalse `
            -Because 'the wrapper must forward the caller-supplied ChangePasswordAtLogon=$false (not hardcode $true)'

        # Caller omits the key -> fall back to $script:Config.security.mustChangeAtNextLogon ($false here).
        $script:CapturedChangePwd = $null
        & (Get-Module adman) {
            param($O) Adman.AD.Write.New-ADUser -Objects @($O) -Parameters @{
                UserPrincipalName = 'alice@mock.local'
                AccountPassword   = ([securestring]::new())
            } -Confirm:$false
        } -O $synthetic
        $script:CapturedChangePwd | Should -BeFalse `
            -Because 'the wrapper must fall back to config security.mustChangeAtNextLogon when the key is absent'

        # Config key absent -> default $true.
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                DC       = 'dc.mock.local'
                security = [pscustomobject]@{}
            }
        }
        $script:CapturedChangePwd = $null
        & (Get-Module adman) {
            param($O) Adman.AD.Write.New-ADUser -Objects @($O) -Parameters @{
                UserPrincipalName = 'alice@mock.local'
                AccountPassword   = ([securestring]::new())
            } -Confirm:$false
        } -O $synthetic
        $script:CapturedChangePwd | Should -BeTrue `
            -Because 'the wrapper must default to $true when neither the parameter nor the config key is present'
    }

    It 'Test 15: Move-ADObject destination validation runs INSIDE the gate (per-verb Parameters validator); refuses out-of-scope TargetPath BEFORE confirm' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Confirm-AdmanAction -ModuleName adman { throw 'Confirm must NOT run when TargetPath is out of scope' }
        Mock Write-AdmanAudit -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanMutation -Verb 'Move-ADObject' -Targets @('alice') `
                -Parameters @{ TargetPath = 'OU=NotManaged,DC=mock,DC=local' } `
                -Confirm:$false
        } } | Should -Throw -ExpectedMessage "*TargetPath*outside managed OU scope*"
        Should -Invoke Confirm-AdmanAction -ModuleName adman -Times 0 `
            -Because 'the gate-side TargetPath validator refuses BEFORE confirm (direct gate callers cannot bypass)'
    }

    It 'Test 16 (HIGH #1): when the wrapper throws, the gate writes Write-AdmanAudit -Result ''Failure'' -Reason <exception> BEFORE rethrowing (no PENDING orphan)' {
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:FailureAudit = $null
        Mock Resolve-AdmanTarget -ModuleName adman { $t1 }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, [switch]$WhatIf)
            if ($Result -eq 'Failure') {
                $script:FailureAudit = @{ Result = $Result; Reason = $Reason }
            }
        }
        Mock Adman.AD.Write.Disable-ADAccount -ModuleName adman { throw 'ADPasswordComplexityException: password too weak' }

        { & (Get-Module adman) { Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @('alice') -Confirm:$false } } |
            Should -Throw -ExpectedMessage '*password too weak*'
        $script:FailureAudit | Should -Not -BeNullOrEmpty `
            -Because 'the gate must write a Failure outcome audit record when the wrapper throws (HIGH #1 - no PENDING orphan)'
        $script:FailureAudit.Reason | Should -Match 'password too weak'
    }

    It 'Test 17 (HIGH #3): Adman.AD.Write.Unlock-ADAccount honors $Parameters[''Server''] without a duplicate-parameter collision' {
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{ DC = 'dc.mock.local' }
        }
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:CapturedServer = $null
        Mock Unlock-ADAccount -ModuleName adman {
            param($Identity, $Server)
            $script:CapturedServer = $Server
        }

        # PDCe override from Unlock-AdmanUser.
        { & (Get-Module adman) {
            param($O) Adman.AD.Write.Unlock-ADAccount -Objects @($O) -Parameters @{ Server = 'pdc.mock.local' } -Confirm:$false
        } -O $t1 } | Should -Not -Throw `
            -Because 'stripping Server from the splat prevents a duplicate-parameter collision (HIGH #3)'
        $script:CapturedServer | Should -Be 'pdc.mock.local' `
            -Because 'the wrapper must honor the PDCe override from $Parameters[''Server'']'

        # No override -> fall back to $script:Config.DC.
        $script:CapturedServer = $null
        & (Get-Module adman) {
            param($O) Adman.AD.Write.Unlock-ADAccount -Objects @($O) -Parameters @{} -Confirm:$false
        } -O $t1
        $script:CapturedServer | Should -Be 'dc.mock.local' `
            -Because 'the wrapper must fall back to $script:Config.DC when $Parameters[''Server''] is absent'
    }

    It 'Test 18 (HIGH #4): Adman.AD.Write.Set-ADAccountPassword splits ChangePasswordAtLogon to a follow-up Set-ADUser call after the reset' {
        & (Get-Module adman) {
            $script:Config = [pscustomobject]@{
                DC       = 'dc.mock.local'
                security = [pscustomobject]@{ mustChangeAtNextLogon = $true }
            }
        }
        $t1 = New-AdmanTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $script:ResetSplatKeys = $null
        $script:SetUserChangePwd = $null
        $script:CallOrder = [System.Collections.Generic.List[string]]::new()
        Mock Set-ADAccountPassword -ModuleName adman {
            param($Identity, $Server, $Reset, $NewPassword)
            $script:CallOrder.Add('reset')
            $script:ResetSplatKeys = @($PSBoundParameters.Keys)
        }
        Mock Set-ADUser -ModuleName adman {
            param($Identity, $ChangePasswordAtLogon, $Server)
            $script:CallOrder.Add('setuser')
            $script:SetUserChangePwd = $ChangePasswordAtLogon
        }

        & (Get-Module adman) {
            param($O) Adman.AD.Write.Set-ADAccountPassword -Objects @($O) -Parameters @{
                Reset                 = $true
                NewPassword           = ([securestring]::new())
                ChangePasswordAtLogon = $true
            } -Confirm:$false
        } -O $t1

        $script:ResetSplatKeys | Should -Not -Contain 'ChangePasswordAtLogon' `
            -Because 'Set-ADAccountPassword does not accept -ChangePasswordAtLogon; it must be stripped from the splat (HIGH #4)'
        $script:CallOrder.ToArray() | Should -Be @('reset') `
            -Because 'the wrapper invokes ONLY Set-ADAccountPassword; ChangePasswordAtLogon is handled by a separate gate invocation (CR-01)'
        Should -Invoke Set-ADUser -ModuleName adman -Times 0 `
            -Because 'the wrapper must NOT call Set-ADUser; ChangePasswordAtLogon follow-up is a separate gate invocation (CR-01)'
    }
}
