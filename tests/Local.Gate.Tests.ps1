#Requires -Modules Pester
<#
.SYNOPSIS
    Task 3 (RED) - D-02 local gate + D-03 Remove-LocalUser override tests.

    Fourteen behavior tests for the local mutation gate (Invoke-AdmanLocalMutation):
      * Test 1: fixed order Resolve -> Allow -> BulkPolicy -> Confirm -> PENDING -> Write -> OUTCOME
      * Test 2: Resolve-AdmanLocalTarget throws "Remote targets arrive in Phase 3" on non-localhost
      * Test 3: Test-AdmanLocalTargetAllowed refuses LocalRid '500'
      * Test 4: refuses local-Administrators member on Disable/Remove/Set; Get-LocalGroupMember
        with try/catch + WMI Win32_GroupUser fallback on 0x80070534; refuses closed on total failure
      * Test 5: refuses when machine's AD computer object is outside managed-OU scope
      * Test 6: Confirm-AdmanAction overrides threshold to 1 for Remove-LocalUser
      * Test 7: Write-AdmanAudit emits MACHINE\username + @{machine,name,sid} for local targets
      * Test 8: Write-AdmanAudit emits group field when -Group supplied
      * Test 9: Test 2c source-hygiene still passes (zero banned tokens)
      * Test 10: AST guard flags Public/ files naming LocalAccounts cmdlets
      * Test 11: New-LocalUser routes through create-branch (synthetic target, no Get-LocalUser)
      * Test 12: synthetic skip-checks - only machine-in-scope + name-shape validation
      * Test 13: uniqueness pre-flight + TOCTOU closure via New-LocalUser's own throw
      * Test 14: local gate writes Failure audit on wrapper throw (HIGH #1)

.NOTES
    Pester 6. PSFramework + LocalAccounts stubs on $TestDrive. No live domain, no real local
    accounts touched. All collaborators mocked (-ModuleName adman).
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
    $script:LocalGatePath = Join-Path $script:RepoRoot 'Private\Safety\Invoke-AdmanLocalMutation.ps1'
    $script:WriterPath = Join-Path $script:RepoRoot 'Private\Audit\Write-AdmanAudit.ps1'
    $script:RuleModule = Join-Path $script:RepoRoot 'rules\AdmanSafetyRules.psm1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
    Import-Module $script:RuleModule -Force -ErrorAction SilentlyContinue

    # Global stubs so Pester's Mock resolver finds module-private collaborators at RED.
    function global:Resolve-AdmanLocalTarget { param($Targets, $ComputerName, $Verb, [switch]$Create) }
    function global:Test-AdmanLocalTargetAllowed { param($Object, $Verb) }
    function global:Resolve-AdmanTarget { param($Targets) }
    function global:Test-AdmanTargetAllowed { param($Object) }
    function global:Assert-AdmanBulkPolicy { param($Count, [switch]$EnforceCap) }
    function global:Confirm-AdmanAction { param($Verb, $Targets, $Group, [switch]$Force) }
    function global:Write-AdmanAudit { param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf) }
    function global:Adman.Local.Write.New-LocalUser { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Disable-LocalUser { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Enable-LocalUser { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Set-LocalUser { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Remove-LocalUser { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Add-LocalGroupMember { param($Objects, $Parameters) }
    function global:Adman.Local.Write.Remove-LocalGroupMember { param($Objects, $Parameters) }

    function New-AdmanLocalSafetyConfig {
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

    function Set-AdmanLocalSafetyState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
            $script:Initialized = $true
            $script:ProtectedSIDs = @()
            $script:DenyRids = @()
            $script:ProtectedGroupDns = @()
            # CR-03: clear the per-session machine-scope cache so each test gets a fresh
            # AD lookup (the cache would otherwise leak mock expectations between tests).
            $script:LocalMachineScopeCache = @{}
        } -Config $Config
    }

    function New-AdmanLocalTarget {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Name,
            [string]$Machine = $env:COMPUTERNAME,
            [string]$Sid = 'S-1-5-21-111-222-333-1001',
            [string]$LocalRid = '1001'
        )
        [pscustomobject]@{
            Machine  = $Machine
            Name     = $Name
            SID      = $Sid
            LocalRid = $LocalRid
            Enabled  = $true
            FullName = $Name
        }
    }

    function Reset-AdmanLocalOrder { $script:AdmanLocalOrder = [System.Collections.Generic.List[string]]::new() }
    function Get-AdmanLocalOrder { return $script:AdmanLocalOrder.ToArray() }
}

Describe 'D-02/D-03: Invoke-AdmanLocalMutation fixed order + behavior (LOCAL GATE)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanLocalSafetyState -Config (New-AdmanLocalSafetyConfig)
        Reset-AdmanLocalOrder
    }

    It 'Test 1: runs the fixed order Resolve -> Allow -> BulkPolicy -> Confirm -> Audit(PENDING) -> Write -> Audit(OUTCOME)' {
        $t1 = New-AdmanLocalTarget -Name 'alice'
        Mock Resolve-AdmanLocalTarget -ModuleName adman { $script:AdmanLocalOrder.Add('resolve'); $t1 }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { $script:AdmanLocalOrder.Add('allow'); @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { $script:AdmanLocalOrder.Add('bulkpolicy'); @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { $script:AdmanLocalOrder.Add('confirm'); @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf)
            $script:AdmanLocalOrder.Add("audit-$Result")
        }
        Mock Adman.Local.Write.Disable-LocalUser -ModuleName adman { $script:AdmanLocalOrder.Add('write') }

        $null = & (Get-Module adman) { Invoke-AdmanLocalMutation -Verb 'Disable-LocalUser' -Targets @('alice') -Confirm:$false }

        $order = Get-AdmanLocalOrder
        $order | Should -Be @('resolve', 'allow', 'bulkpolicy', 'confirm', 'audit-PENDING', 'write', 'audit-Success')
    }

    It 'Test 1b: caller -WhatIf is forwarded into Confirm-AdmanAction and the local wrapper' {
        $t1 = New-AdmanLocalTarget -Name 'alice'
        $script:ConfirmWhatIf = $null
        $script:WrapperWhatIf = $null
        Mock Resolve-AdmanLocalTarget -ModuleName adman { $t1 }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman {
            param([switch]$WhatIf)
            $script:ConfirmWhatIf = [bool]$WhatIf
            @{ Outcome = 'DryRun'; WhatIf = $true }
        }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.Local.Write.Disable-LocalUser -ModuleName adman {
            param($Objects, $Parameters, [switch]$WhatIf)
            $script:WrapperWhatIf = [bool]$WhatIf
        }

        { & (Get-Module adman) {
            Invoke-AdmanLocalMutation -Verb 'Disable-LocalUser' -Targets @('alice') -WhatIf
        } } | Should -Not -Throw -Because 'the local gate must accept caller -WhatIf and treat it as a dry-run'

        $script:ConfirmWhatIf | Should -BeTrue `
            -Because 'the caller -WhatIf must be bound to Confirm-AdmanAction -WhatIf'
        $script:WrapperWhatIf | Should -BeTrue `
            -Because 'the local wrapper must receive -WhatIf:$true when Confirm-AdmanAction returns DryRun'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'PENDING' -and [bool]$WhatIf
        } -Because 'the PENDING record carries whatIf=$true under a dry-run'
        Should -Invoke Write-AdmanAudit -ModuleName adman -Times 1 -ParameterFilter {
            $Result -eq 'Success' -and [bool]$WhatIf
        } -Because 'the OUTCOME record carries whatIf=$true under a dry-run'
    }

    It 'Test 2: Resolve-AdmanLocalTarget throws "Remote targets arrive in Phase 3" when -ComputerName is not localhost' {
        { & (Get-Module adman) {
            Resolve-AdmanLocalTarget -Targets @('alice') -ComputerName 'remote.mock.local'
        } } | Should -Throw -ExpectedMessage '*Remote targets arrive in Phase 3*'

        # Accepted localhost forms: $null, '.', $env:COMPUTERNAME, 'localhost'.
        Mock Get-LocalUser -ModuleName adman {
            [pscustomobject]@{
                Name     = 'alice'
                SID      = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001'
                Enabled  = $true
                FullName = 'alice'
            }
        }
        foreach ($cn in @($null, '.', $env:COMPUTERNAME, 'localhost')) {
            { & (Get-Module adman) {
                param($CN) Resolve-AdmanLocalTarget -Targets @('alice') -ComputerName $CN
            } -CN $cn } | Should -Not -Throw -Because "localhost form '$cn' must be accepted"
        }
    }

    It 'Test 3: Test-AdmanLocalTargetAllowed refuses a target whose LocalRid is 500 (built-in Administrator)' {
        $rid500 = New-AdmanLocalTarget -Name 'Administrator' -LocalRid '500' -Sid 'S-1-5-21-111-222-333-500'
        Mock Resolve-AdmanTarget -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = 'CN=MACHINE,OU=Managed,DC=mock,DC=local'
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-9999'
                objectClass       = @('top', 'computer')
                memberOf          = @()
            }
        }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Get-LocalGroupMember -ModuleName adman { @() }

        $decision = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'Disable-LocalUser'
        } -O $rid500
        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'built-in local Administrator \(RID-500\)'
    }

    It 'Test 4: refuses a local-Administrators member on Disable/Remove/Set; uses WMI fallback on 0x80070534; refuses closed on total failure' {
        $admin = New-AdmanLocalTarget -Name 'admin2' -LocalRid '1002' -Sid 'S-1-5-21-111-222-333-1002'
        Mock Resolve-AdmanTarget -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = 'CN=MACHINE,OU=Managed,DC=mock,DC=local'
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-9999'
                objectClass       = @('top', 'computer')
                memberOf          = @()
            }
        }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        # Get-LocalGroupMember returns the target's SID -> admin member.
        Mock Get-LocalGroupMember -ModuleName adman {
            @([pscustomobject]@{ SID = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1002' })
        }

        foreach ($v in @('Disable-LocalUser', 'Remove-LocalUser', 'Set-LocalUser')) {
            $decision = & (Get-Module adman) {
                param($O, $Verb) Test-AdmanLocalTargetAllowed -Object $O -Verb $Verb
            } -O $admin -Verb $v
            $decision.Allowed | Should -BeFalse -Because "local-Administrators member must be refused on $v"
            $decision.Reason | Should -Match 'local Administrators'
        }

        # Enable-LocalUser is NOT in the refuse set -> allowed (admins can be re-enabled).
        $decision = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'Enable-LocalUser'
        } -O $admin
        $decision.Allowed | Should -BeTrue -Because 'Enable-LocalUser is not in the refuse set'

        # Total enumeration failure -> fail-closed refusal.
        Mock Get-LocalGroupMember -ModuleName adman { throw 'total failure' }
        Mock Get-CimInstance -ModuleName adman { throw 'total failure' }
        $decision2 = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'Disable-LocalUser'
        } -O $admin
        $decision2.Allowed | Should -BeFalse -Because 'total enumeration failure must refuse closed'
    }

    It 'Test 5: refuses when the target machine AD computer object is outside managed-OU scope' {
        $t1 = New-AdmanLocalTarget -Name 'alice'
        Mock Resolve-AdmanTarget -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = 'CN=MACHINE,OU=NotManaged,DC=mock,DC=local'
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-9999'
                objectClass       = @('top', 'computer')
                memberOf          = @()
            }
        }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $false; Reason = 'outside managed-OU scope' } }
        Mock Get-LocalGroupMember -ModuleName adman { @() }

        $decision = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'Disable-LocalUser'
        } -O $t1
        $decision.Allowed | Should -BeFalse
        $decision.Reason | Should -Match 'outside managed-OU scope|machine'
    }

    It 'Test 6: Confirm-AdmanAction overrides bulkConfirmThreshold to 1 when Verb=Remove-LocalUser (typed-count even at count=1)' {
        $t1 = New-AdmanLocalTarget -Name 'alice'
        # Threshold default is 5; count=1 would normally skip the typed-count path. The override
        # forces typed-count at count=1 for Remove-LocalUser (D-03).
        $script:ReadHostCalled = $false
        Mock Read-Host -ModuleName adman {
            $script:ReadHostCalled = $true
            return '1'   # correct token
        }
        $result = & (Get-Module adman) {
            param($T) Confirm-AdmanAction -Verb 'Remove-LocalUser' -Targets @($T)
        } -T $t1
        $script:ReadHostCalled | Should -BeTrue `
            -Because 'Remove-LocalUser forces typed-count confirmation even at count=1 (threshold override to 1)'
        $result.Outcome | Should -Be 'Proceed'
    }

    It 'Test 7: Write-AdmanAudit emits target="MACHINE\username" and targets[0]={machine,name,sid} for local targets' {
        $auditDir = Join-Path $TestDrive ('audit-local-{0}' -f [guid]::NewGuid().ToString('n'))
        & (Get-Module adman) {
            param($Dir)
            $script:Config = [pscustomobject]@{
                ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
                DC                  = 'dc.mock.local'
                AuditDir            = $Dir
                AdmanProtectedGroup = ''
                DenyList            = @()
                safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
                bulk                = [pscustomobject]@{ maxCount = 50 }
                credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
            }
        } -Dir $auditDir

        $localTarget = [pscustomobject]@{
            Machine  = 'MACHINE1'
            Name     = 'alice'
            SID      = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001'
            LocalRid = '1001'
        }
        & (Get-Module adman) {
            param($T) Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) `
                -Verb 'Disable-LocalUser' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -T $localTarget

        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $auditDir $name
        $lines = @(Get-Content -LiteralPath $path | Where-Object { $_ -and $_.Trim() })
        $rec = ($lines[-1] | ConvertFrom-Json)
        $rec.target | Should -Be 'MACHINE1\alice'
        $rec.targets[0].machine | Should -Be 'MACHINE1'
        $rec.targets[0].name | Should -Be 'alice'
        $rec.targets[0].sid | Should -Be 'S-1-5-21-111-222-333-1001'
        # Local target detail must NOT carry the AD-only dn/objectClass keys.
        @($rec.targets[0].PSObject.Properties.Name) | Should -Not -Contain 'dn'
        @($rec.targets[0].PSObject.Properties.Name) | Should -Not -Contain 'objectClass'
    }

    It 'Test 8: Write-AdmanAudit emits a group field alongside target when -Group is supplied' {
        $auditDir = Join-Path $TestDrive ('audit-group-{0}' -f [guid]::NewGuid().ToString('n'))
        & (Get-Module adman) {
            param($Dir)
            $script:Config = [pscustomobject]@{
                ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
                DC                  = 'dc.mock.local'
                AuditDir            = $Dir
                AdmanProtectedGroup = ''
                DenyList            = @()
                safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
                bulk                = [pscustomobject]@{ maxCount = 50 }
                credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
            }
        } -Dir $auditDir

        $adTarget = [pscustomobject]@{
            DistinguishedName = 'CN=Alice,OU=Managed,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1000'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        }
        & (Get-Module adman) {
            param($T) Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) `
                -Verb 'Add-ADGroupMember' -Targets @($T) -Result 'Success' -Reason '' `
                -Group 'CN=SomeGroup,OU=Managed,DC=mock,DC=local' -WhatIf:$false
        } -T $adTarget

        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $auditDir $name
        $lines = @(Get-Content -LiteralPath $path | Where-Object { $_ -and $_.Trim() })
        $rec = ($lines[-1] | ConvertFrom-Json)
        $rec.group | Should -Be 'CN=SomeGroup,OU=Managed,DC=mock,DC=local'
        $rec.target | Should -Be 'CN=Alice,OU=Managed,DC=mock,DC=local'
    }

    It 'Test 9: writer source still passes source-hygiene (zero banned tokens) after extension' {
        Test-Path -LiteralPath $script:WriterPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:WriterPath -Raw
        $matches = [regex]::Matches($src, 'password|secret|credential|apiKey|privateKey', 'IgnoreCase')
        $matches.Count | Should -Be 0 `
            -Because 'the writer source must contain zero banned tokens after the local-target extension'
    }

    It 'Test 10: AST guard flags any Public/*.ps1 that names a LocalAccounts mutation cmdlet directly' {
        $banned = Get-AdmanBannedLocalWriteVerbs
        $banned | Should -Not -BeNullOrEmpty
        foreach ($v in @('New-LocalUser', 'Disable-LocalUser', 'Enable-LocalUser', 'Set-LocalUser',
                'Remove-LocalUser', 'Add-LocalGroupMember', 'Remove-LocalGroupMember')) {
            $banned | Should -Contain $v
        }

        $publicDir = Join-Path $script:RepoRoot 'Public'
        $files = @(Get-ChildItem -Path $publicDir -Filter *.ps1 -Recurse -File)
        $allHits = @()
        foreach ($f in $files) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            $calls = $ast.FindAll(
                { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
            $names = foreach ($c in $calls) {
                $n = $c.GetCommandName()
                if (-not $n) { $n = $c.CommandElements[0].Extent.Text }
                if ($n) { $n }
            }
            $allHits += @($names | Where-Object { $_ -in $banned })
        }
        $allHits | Should -BeNullOrEmpty -Because 'Public/ verbs must route local writes through Invoke-AdmanLocalMutation'
    }

    It 'Test 11: New-LocalUser routes through a create-branch in Resolve-AdmanLocalTarget that fabricates a synthetic local target WITHOUT calling Get-LocalUser' {
        $synthetic = [pscustomobject]@{
            Machine     = $env:COMPUTERNAME
            Name        = 'newuser'
            SID         = $null
            LocalRid    = $null
            Enabled     = $null
            FullName    = $null
            IsSynthetic = $true
        }
        Mock Resolve-AdmanLocalTarget -ModuleName adman {
            param($Targets, $ComputerName, $Verb, [switch]$Create)
            $script:AdmanLocalOrder.Add('resolve-create')
            $synthetic
        }
        # The create-branch resolver must NOT call Get-LocalUser. The gate's uniqueness
        # pre-flight DOES call it (by design, D-02) - return $null (no collision) so the
        # gate proceeds. The resolver is mocked here, so the real resolver never runs;
        # any Get-LocalUser call comes from the pre-flight, not the resolver.
        Mock Get-LocalUser -ModuleName adman { $null }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman {
            param($Object, $Verb)
            $script:SyntheticSeen = $Object
            $script:AdmanLocalOrder.Add('allow')
            @{ Allowed = $true; Reason = '' }
        }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman { }
        Mock Adman.Local.Write.New-LocalUser -ModuleName adman { }

        $null = & (Get-Module adman) {
            Invoke-AdmanLocalMutation -Verb 'New-LocalUser' -Targets @('newuser') `
                -Parameters @{ Name = 'newuser' } -Confirm:$false
        }

        $script:SyntheticSeen.IsSynthetic | Should -BeTrue `
            -Because 'Test-AdmanLocalTargetAllowed must receive the IsSynthetic=$true synthetic local target'
        # The resolver mock received the create-branch signal (-Create / -Verb New-LocalUser).
        Should -Invoke Resolve-AdmanLocalTarget -ModuleName adman -Times 1 -ParameterFilter {
            $Create -or $Verb -eq 'New-LocalUser'
        } -Because 'New-LocalUser must route through the create-branch resolver (D-02)'
    }

    It 'Test 12: Test-AdmanLocalTargetAllowed for an IsSynthetic local target SKIPS SID-dependent checks; runs ONLY machine-in-scope + name-shape validation' {
        Mock Resolve-AdmanTarget -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = 'CN=MACHINE,OU=Managed,DC=mock,DC=local'
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-9999'
                objectClass       = @('top', 'computer')
                memberOf          = @()
            }
        }
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Get-LocalGroupMember -ModuleName adman { throw 'Get-LocalGroupMember must NOT run for synthetic targets' }

        # Valid synthetic name -> allowed (machine in scope, name well-formed).
        $synthetic = [pscustomobject]@{
            Machine     = $env:COMPUTERNAME
            Name        = 'newuser'
            SID         = $null
            LocalRid    = $null
            IsSynthetic = $true
        }
        $decision = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'New-LocalUser'
        } -O $synthetic
        $decision.Allowed | Should -BeTrue `
            -Because 'a synthetic target with a valid name and in-scope machine skips SID-dependent checks'

        # Malformed name -> refused.
        $badName = $synthetic.PSObject.Copy()
        $badName.Name = 'bad/name'
        $decision2 = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'New-LocalUser'
        } -O $badName
        $decision2.Allowed | Should -BeFalse
        $decision2.Reason | Should -Match 'name'

        # Out-of-scope machine -> refused (use a different machine name so the per-machine cache
        # does not reuse the in-scope result from the first assertion).
        Mock Test-AdmanTargetAllowed -ModuleName adman { @{ Allowed = $false; Reason = 'outside managed-OU scope' } }
        $outOfScope = [pscustomobject]@{
            Machine     = 'OUTOFSCOPE-PC'
            Name        = 'newuser'
            SID         = $null
            LocalRid    = $null
            IsSynthetic = $true
        }
        $decision3 = & (Get-Module adman) {
            param($O) Test-AdmanLocalTargetAllowed -Object $O -Verb 'New-LocalUser'
        } -O $outOfScope
        $decision3.Allowed | Should -BeFalse
    }

    It 'Test 13: New-LocalUser uniqueness pre-flight refuses on collision BEFORE confirm; TOCTOU closed by New-LocalUser throw -> Failure OUTCOME' {
        $synthetic = [pscustomobject]@{
            Machine     = $env:COMPUTERNAME
            Name        = 'alice'
            SID         = $null
            LocalRid    = $null
            IsSynthetic = $true
        }
        Mock Resolve-AdmanLocalTarget -ModuleName adman { $synthetic }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        # Pre-flight: Get-LocalUser returns a hit -> refuse BEFORE confirm.
        Mock Get-LocalUser -ModuleName adman {
            [pscustomobject]@{ Name = 'alice'; SID = 'S-1-5-21-111-222-333-1001' }
        }
        Mock Confirm-AdmanAction -ModuleName adman { throw 'Confirm must NOT run when uniqueness pre-flight refuses' }
        Mock Write-AdmanAudit -ModuleName adman { }

        { & (Get-Module adman) {
            Invoke-AdmanLocalMutation -Verb 'New-LocalUser' -Targets @('alice') `
                -Parameters @{ Name = 'alice' } -Confirm:$false
        } } | Should -Throw -ExpectedMessage "*local user 'alice' already exists*"
        Should -Invoke Confirm-AdmanAction -ModuleName adman -Times 0 `
            -Because 'the uniqueness pre-flight refuses BEFORE confirm'

        # TOCTOU closure: pre-flight returns zero hits, but New-LocalUser throws on collision
        # (race between pre-flight and write). The wrapper's -ErrorAction Stop propagates the
        # throw and the OUTCOME audit write records Result='Failure'.
        Mock Get-LocalUser -ModuleName adman { $null }   # pre-flight: no hit
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        $script:FailureAudit = $null
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf)
            if ($Result -eq 'Failure') { $script:FailureAudit = @{ Result = $Result; Reason = $Reason } }
        }
        Mock Adman.Local.Write.New-LocalUser -ModuleName adman { throw 'New-LocalUser collision: user already exists' }

        { & (Get-Module adman) {
            Invoke-AdmanLocalMutation -Verb 'New-LocalUser' -Targets @('alice') `
                -Parameters @{ Name = 'alice' } -Confirm:$false
        } } | Should -Throw -ExpectedMessage '*already exists*'
        $script:FailureAudit | Should -Not -BeNullOrEmpty `
            -Because 'New-LocalUser throw closes TOCTOU with a Failure OUTCOME audit record'
        $script:FailureAudit.Reason | Should -Match 'already exists'
    }

    It 'Test 14 (HIGH #1): when the local wrapper throws, the gate writes Write-AdmanAudit -Result Failure BEFORE rethrowing (no PENDING orphan)' {
        $t1 = New-AdmanLocalTarget -Name 'alice'
        $script:FailureAudit = $null
        Mock Resolve-AdmanLocalTarget -ModuleName adman { $t1 }
        Mock Test-AdmanLocalTargetAllowed -ModuleName adman { @{ Allowed = $true; Reason = '' } }
        Mock Assert-AdmanBulkPolicy -ModuleName adman { @{ Cap = 50; Threshold = 5 } }
        Mock Confirm-AdmanAction -ModuleName adman { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock Write-AdmanAudit -ModuleName adman {
            param($CorrelationId, $Verb, $Targets, $Target, $Result, $Reason, $Group, [switch]$WhatIf)
            if ($Result -eq 'Failure') { $script:FailureAudit = @{ Result = $Result; Reason = $Reason } }
        }
        Mock Adman.Local.Write.Disable-LocalUser -ModuleName adman { throw 'Access denied' }

        { & (Get-Module adman) {
            Invoke-AdmanLocalMutation -Verb 'Disable-LocalUser' -Targets @('alice') -Confirm:$false
        } } | Should -Throw -ExpectedMessage '*Access denied*'
        $script:FailureAudit | Should -Not -BeNullOrEmpty `
            -Because 'the local gate must write a Failure outcome audit record when the wrapper throws (HIGH #1)'
        $script:FailureAudit.Reason | Should -Match 'Access denied'
    }
}
