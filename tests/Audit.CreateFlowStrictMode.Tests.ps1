#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (02-08) - G-02-3: synthetic pre-create target PENDING write succeeds under StrictMode.

    Proves the guarded SID extraction in Write-AdmanAudit's AD-target branch:
      * Test 1: synthetic pre-create target (DistinguishedName set, objectSid=$null, IsSynthetic=$true)
        writes a PENDING record WITHOUT throwing under Set-StrictMode -Version Latest. The audit
        record's targets[0].dn equals the synthetic DN; targets[0].sid is $null. (G-02-3 closed.)
      * Test 2: existing-AD-object target (real SecurityIdentifier objectSid) still writes PENDING;
        targets[0].sid equals the SID string. (No regression on the existing-object path.)
      * Test 3: local target (Machine+Name+SID, no DN) still writes PENDING; targets[0].sid equals
        the local SID string; the target string is 'MACHINE\username'. (No regression on the
        local-target path.)
      * Test 4: fail-closed preserved — mock Open-AdmanAuditStream to throw; Write-AdmanAudit
        -Result 'PENDING' throws 'AUDIT FAIL-CLOSED'. (D-01 invariant intact.)
      * Test 5: AD-shaped target WITHOUT the objectSid property at all (deserialized PSCustomObject
        / mock) writes PENDING without throwing under StrictMode; targets[0].sid is $null.
        (REV-2 regression guard: proves the property-existence guard runs BEFORE any .objectSid
        read, so StrictMode does not throw 'The property objectSid cannot be found on this object'.)

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. Uses the REAL
    seams against a TestDrive audit dir (no mock) for Tests 1/2/3/5 so the on-disk record is
    authoritative; Test 4 mocks Open-AdmanAuditStream to drive the fail-closed throw. No live
    domain.
#>

BeforeAll {
    Set-StrictMode -Version Latest

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
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    function New-AdmanAuditConfig {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$AuditDir)
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = 'dc.mock.local'
            AuditDir            = $AuditDir
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
        }
    }

    function Set-AdmanAuditState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
        } -Config $Config
    }

    # Read the single JSONL record written to today's file under $AuditDir.
    function Read-AdmanAuditRecord {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$AuditDir)
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $AuditDir $name
        $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop | Where-Object { $_ -and $_.Trim() })
        $lines.Count | Should -BeGreaterOrEqual 1 -Because 'Write-AdmanAudit must append one JSONL record'
        return ($lines[-1] | ConvertFrom-Json)
    }
}

Describe 'G-02-3: Write-AdmanAudit synthetic pre-create target PENDING write under StrictMode' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
    }

    It 'Test 1: synthetic pre-create target (objectSid=$null) writes PENDING without throwing under StrictMode' {
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Alice Jones,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'ajones'
            Name              = 'Alice Jones'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }
        $cid = [guid]::NewGuid().ToString()

        {
            & (Get-Module adman) {
                param($Cid, $T)
                Write-AdmanAudit -CorrelationId $Cid -Verb 'New-ADUser' -Target $T -Result 'PENDING'
            } -Cid $cid -T $synthetic
        } | Should -Not -Throw -Because 'the guarded SID extraction must tolerate objectSid=$null (synthetic pre-create target)'

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $rec.result | Should -Be 'PENDING'
        $rec.what | Should -Be 'New-ADUser'
        $rec.correlationId | Should -Be $cid
        @($rec.targets).Count | Should -Be 1
        $rec.targets[0].dn | Should -Be 'CN=Alice Jones,OU=Managed,DC=mock,DC=local'
        # sid must be $null (or absent) — NOT a fabricated SID, NOT a throw.
        $sidProp = $rec.targets[0].PSObject.Properties['sid']
        if ($null -ne $sidProp) {
            $rec.targets[0].sid | Should -BeNullOrEmpty -Because 'a synthetic pre-create target has no SID yet; the audit record must emit sid=$null, not fabricate one'
        }
    }

    It 'Test 2: existing-AD-object target (real SecurityIdentifier objectSid) still writes PENDING' {
        $existing = [pscustomobject]@{
            DistinguishedName = 'CN=Bob,OU=Managed,DC=mock,DC=local'
            objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1001'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        }
        $cid = [guid]::NewGuid().ToString()

        {
            & (Get-Module adman) {
                param($Cid, $T)
                Write-AdmanAudit -CorrelationId $Cid -Verb 'Set-ADUser' -Target $T -Result 'PENDING'
            } -Cid $cid -T $existing
        } | Should -Not -Throw

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $rec.targets[0].dn | Should -Be 'CN=Bob,OU=Managed,DC=mock,DC=local'
        $rec.targets[0].sid | Should -Be 'S-1-5-21-111-222-333-1001'
    }

    It 'Test 3: local target (Machine+Name+SID, no DN) still writes PENDING' {
        $local = [pscustomobject]@{
            Machine = 'MOCKPC'
            Name    = 'localuser'
            SID     = 'S-1-5-21-111-222-333-1002'
        }
        $cid = [guid]::NewGuid().ToString()

        {
            & (Get-Module adman) {
                param($Cid, $T)
                Write-AdmanAudit -CorrelationId $Cid -Verb 'Set-LocalUser' -Target $T -Result 'PENDING'
            } -Cid $cid -T $local
        } | Should -Not -Throw

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $rec.target | Should -Be 'MOCKPC\localuser'
        $rec.targets[0].sid | Should -Be 'S-1-5-21-111-222-333-1002'
    }

    It 'Test 4: fail-closed preserved — Open-AdmanAuditStream throw -> AUDIT FAIL-CLOSED' {
        $synthetic = [pscustomobject]@{
            DistinguishedName = 'CN=Alice Jones,OU=Managed,DC=mock,DC=local'
            SamAccountName    = 'ajones'
            Name              = 'Alice Jones'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            objectSid         = $null
            memberOf          = @()
            ParentOuDn        = 'OU=Managed,DC=mock,DC=local'
            IsSynthetic       = $true
        }

        InModuleScope adman -Parameters @{ Synthetic = $synthetic; AuditDir = $script:AuditDir } {
            param($Synthetic, $AuditDir)
            Mock Open-AdmanAuditStream { throw 'simulated I/O failure' }
            {
                Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'New-ADUser' -Target $Synthetic -Result 'PENDING'
            } | Should -Throw -ExpectedMessage '*AUDIT FAIL-CLOSED*' -Because 'a genuine I/O failure on the PENDING write must still throw and refuse the mutation (D-01)'
        }
    }

    It 'Test 5: AD-shaped target WITHOUT the objectSid property writes PENDING without throwing under StrictMode' {
        # REV-2 regression guard: mocks / deserialized PSCustomObjects may lack the objectSid
        # property entirely. The property-existence guard must run BEFORE any .objectSid read.
        $noSidObj = [pscustomobject]@{
            DistinguishedName = 'CN=NoSid,OU=Managed,DC=mock,DC=local'
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        }
        $cid = [guid]::NewGuid().ToString()

        {
            & (Get-Module adman) {
                param($Cid, $T)
                Write-AdmanAudit -CorrelationId $Cid -Verb 'Set-ADUser' -Target $T -Result 'PENDING'
            } -Cid $cid -T $noSidObj
        } | Should -Not -Throw -Because 'the property-existence guard must run before any .objectSid read so StrictMode does not throw'

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $rec.targets[0].dn | Should -Be 'CN=NoSid,OU=Managed,DC=mock,DC=local'
        $sidProp = $rec.targets[0].PSObject.Properties['sid']
        if ($null -ne $sidProp) {
            $rec.targets[0].sid | Should -BeNullOrEmpty -Because 'an AD-shaped object lacking objectSid must emit sid=$null'
        }
    }
}
