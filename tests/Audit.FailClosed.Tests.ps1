#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) - SAFE-04 fail-closed audit writer behavior (Write-AdmanAudit).

    Proves the write-ahead fail-closed contract by mocking ONLY the private wrapper seams
    (New-AdmanAuditMutex, Open-AdmanAuditStream, Write-AdmanEventLog) - NEVER raw .NET statics
    (the File.Open / Mutex constructor calls), which Pester cannot mock cleanly:
      * Test 3 (PENDING throw = refusal): when Open-AdmanAuditStream throws on a PENDING write,
        Write-AdmanAudit -Result 'PENDING' THROWS a terminating error containing 'AUDIT FAIL-CLOSED'
        and the verb. (The 00-04 gate test proves the AD write wrapper is then never invoked.)
      * Test 4 (OUTCOME failure escalates, no rollback): when the OUTCOME write throws, the
        function does NOT throw to the caller; it calls Write-AdmanEventLog (mocked) and sets
        $script:AuditDegraded=$true; it never calls an AD write/remove to "roll back".
      * Test 5 (durability + ordering): the stream's Flush is called with $true (durable), the
        mutex WaitOne/ReleaseMutex are called (acquired before, released after), and the daily-
        rotated filename matches 'audit-yyyyMMdd.jsonl'.
      * Test 6 (concurrency): the mutex seam is used (WaitOne called) so two writers serialize.

    Static assertions: the writer mocks the seams (not raw .NET), contains AUDIT FAIL-CLOSED in
    the PENDING branch, has Flush($true) + the named mutex, and has ZERO AD write cmdlets and
    ZERO PSFramework routing.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. ALL I/O mocked via
    the seams; no real filesystem for the fail-closed cases. No live domain.
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
    $script:WriterPath = Join-Path $script:RepoRoot 'Private\Audit\Write-AdmanAudit.ps1'
    $script:IoPath = Join-Path $script:RepoRoot 'Private\Audit\AdmanAuditIO.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds module-private seams at RED.
    function global:New-AdmanAuditMutex { }
    function global:Open-AdmanAuditStream { param($Path) }
    function global:Write-AdmanEventLog { param($EventId, $EntryType, $Message) }

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
            $script:AuditDegraded = $false
        } -Config $Config
    }

    function Get-AdmanAuditDegraded {
        & (Get-Module adman) { $script:AuditDegraded }
    }

    function New-AdmanAuditTarget {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Dn, [string]$Sid = 'S-1-5-21-111-222-333-1000')
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        }
    }

    # A fake stream that records Write/Flush calls (returned by the Open-AdmanAuditStream mock).
    function New-AdmanFakeStream {
        [CmdletBinding()]
        param()
        $rec = [ordered]@{
            FlushArgs = [System.Collections.Generic.List[object]]::new()
            Wrote     = $false
            Disposed  = $false
        }
        $obj = [pscustomobject]$rec
        $obj | Add-Member -MemberType ScriptMethod -Name Write -Value {
            param($bytes, $offset, $count)
            $this.Wrote = $true
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Flush -Value {
            param([bool]$flushToDisk)
            $this.FlushArgs.Add($flushToDisk)
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Disposed = $true
        }
        return $obj
    }

    # A fake mutex that records WaitOne/ReleaseMutex (returned by the New-AdmanAuditMutex mock).
    function New-AdmanFakeMutex {
        [CmdletBinding()]
        param()
        $rec = [ordered]@{ WaitOneCalled = 0; ReleaseCalled = 0; Disposed = $false }
        $obj = [pscustomobject]$rec
        $obj | Add-Member -MemberType ScriptMethod -Name WaitOne -Value {
            $this.WaitOneCalled++
            return $true
        }
        $obj | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value {
            $this.ReleaseCalled++
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Disposed = $true
        }
        return $obj
    }
}

Describe 'SAFE-04: Write-AdmanAudit fail-closed write-ahead behavior' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
        $script:FakeMutex = New-AdmanFakeMutex
        $script:FakeStream = New-AdmanFakeStream
        $script:OpenedPath = $null
    }

    It 'Test 3: a PENDING-write failure THROWS AUDIT FAIL-CLOSED (the refusal) before AD is touched' {
        Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
        Mock Open-AdmanAuditStream -ModuleName adman { throw 'ERROR_DISK_FULL (112)' }
        Mock Write-AdmanEventLog -ModuleName adman { }

        $t1 = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        {
            & (Get-Module adman) {
                param($T)
                Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
            } -T $t1
        } | Should -Throw -ExpectedMessage '*AUDIT FAIL-CLOSED*' `
            -Because 'a PENDING-write failure is the SAFE-04 refusal and must throw'

        # The thrown message names the verb.
        {
            & (Get-Module adman) {
                param($T)
                Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
            } -T $t1
        } | Should -Throw -ExpectedMessage '*Disable-ADAccount*'
    }

    It 'Test 4: an OUTCOME-write failure escalates (Event Log + AuditDegraded) and does NOT throw or roll back AD' {
        Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
        Mock Open-AdmanAuditStream -ModuleName adman { throw 'sharing violation' }
        $script:EventLogCalls = 0
        Mock Write-AdmanEventLog -ModuleName adman { $script:EventLogCalls++ }

        $t1 = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        {
            & (Get-Module adman) {
                param($T)
                Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false -WarningAction SilentlyContinue
            } -T $t1
        } | Should -Not -Throw `
            -Because 'an OUTCOME-write failure must NOT throw to the caller (mutation already applied)'

        $script:EventLogCalls | Should -BeGreaterOrEqual 1 `
            -Because 'an OUTCOME-write failure escalates to the Windows Event Log (best-effort)'
        (Get-AdmanAuditDegraded) | Should -BeTrue `
            -Because 'an OUTCOME-write failure sets $script:AuditDegraded=$true'
    }

    It 'Test 5: durable Flush($true) + mutex acquired/released + daily-rotated filename' {
        Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
        Mock Open-AdmanAuditStream -ModuleName adman {
            param($Path)
            $script:OpenedPath = $Path
            $script:FakeStream
        }
        Mock Write-AdmanEventLog -ModuleName adman { }

        $t1 = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        & (Get-Module adman) {
            param($T)
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -T $t1

        # Durable flush: Flush called with $true (flush to disk, not just OS cache).
        $script:FakeStream.FlushArgs | Should -Contain $true `
            -Because 'the record must be flushed with Flush($true) to durable media (SAFE-04)'
        $script:FakeStream.Wrote | Should -BeTrue -Because 'the record bytes are written'
        $script:FakeStream.Disposed | Should -BeTrue -Because 'the stream is disposed'

        # Mutex acquired before and released after.
        $script:FakeMutex.WaitOneCalled | Should -BeGreaterOrEqual 1 -Because 'the named mutex is acquired'
        $script:FakeMutex.ReleaseCalled | Should -BeGreaterOrEqual 1 -Because 'the named mutex is released'

        # Daily-rotated filename matches audit-yyyyMMdd.jsonl.
        $script:OpenedPath | Should -Match 'audit-\d{8}\.jsonl$' `
            -Because 'the audit file is daily-rotated as audit-yyyyMMdd.jsonl'
        $expectedName = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        (Split-Path -Leaf $script:OpenedPath) | Should -Be $expectedName
    }

    It 'Test 6: the named-mutex seam is used so concurrent writers serialize (WaitOne called)' {
        Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
        Mock Open-AdmanAuditStream -ModuleName adman { $script:FakeStream }
        Mock Write-AdmanEventLog -ModuleName adman { }

        $t1 = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        # Two sequential writes both go through the mutex seam (serialization point).
        1..2 | ForEach-Object {
            & (Get-Module adman) {
                param($T)
                Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
            } -T $t1
        }

        $script:FakeMutex.WaitOneCalled | Should -BeGreaterOrEqual 2 `
            -Because 'every write acquires the named mutex (the serialization point for concurrent writers)'
        $script:FakeMutex.ReleaseCalled | Should -BeGreaterOrEqual 2
    }

    It 'static: writer mocks the seams (not raw .NET), has AUDIT FAIL-CLOSED in PENDING branch, Flush($true), named mutex, zero AD cmdlets, zero PSFramework' {
        Test-Path -LiteralPath $script:WriterPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:WriterPath -Raw

        # Named mutex (Global\adman-audit) referenced via the seam or the literal name.
        [regex]::Matches($src, 'New-AdmanAuditMutex').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the writer acquires the named mutex via the New-AdmanAuditMutex seam'
        # Durable flush.
        [regex]::Matches($src, 'Flush\(\$true\)').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the writer flushes durably with Flush($true)'
        # Append + read-share (via the seam or the FileStream open).
        [regex]::Matches($src, 'Open-AdmanAuditStream').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the writer opens the file via the Open-AdmanAuditStream seam (Append/Write/Read-share)'

        # AUDIT FAIL-CLOSED present and inside the PENDING branch.
        [regex]::Matches($src, 'AUDIT FAIL-CLOSED').Count | Should -BeGreaterOrEqual 1
        $pendingIdx = $src.IndexOf("if (`$Result -eq 'PENDING')")
        $failClosedIdx = $src.IndexOf('AUDIT FAIL-CLOSED: cannot write audit record')
        $pendingIdx | Should -BeGreaterOrEqual 0 -Because 'the writer branches on Result -eq PENDING'
        $failClosedIdx | Should -BeGreaterThan $pendingIdx `
            -Because 'the AUDIT FAIL-CLOSED throw is inside the PENDING branch'

        # Zero AD write cmdlets (no rollback on OUTCOME failure).
        [regex]::Matches($src, '\b(?:Set-AD|Remove-AD|Disable-AD|Enable-AD|Move-ADObject)').Count |
            Should -Be 0 -Because 'the writer never calls an AD write/remove cmdlet (no fake rollback)'

        # Zero PSFramework routing (audit never via PSFramework - async breaks fail-closed).
        [regex]::Matches($src, 'Write-PSFMessage|PSFramework').Count |
            Should -Be 0 -Because 'the audit record is never routed through PSFramework (D-01)'

        # The seams file defines the three wrapper seams.
        Test-Path -LiteralPath $script:IoPath | Should -BeTrue
        $ioSrc = Get-Content -LiteralPath $script:IoPath -Raw
        foreach ($seam in @('New-AdmanAuditMutex', 'Open-AdmanAuditStream', 'Write-AdmanEventLog')) {
            [regex]::Matches($ioSrc, "function\s+$([regex]::Escape($seam))").Count | Should -BeGreaterOrEqual 1 `
                -Because "AdmanAuditIO.ps1 defines the $seam seam"
        }
        # The named-mutex literal lives in the IO seam (the real .NET call).
        [regex]::Matches($ioSrc, 'Global\\adman-audit').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the New-AdmanAuditMutex seam wraps the Global\adman-audit named mutex'
        [regex]::Matches($ioSrc, 'Append').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the Open-AdmanAuditStream seam opens Append'
        [regex]::Matches($ioSrc, 'FileShare\.Read|FileShare\]::Read|\bRead\b').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the Open-AdmanAuditStream seam allows read-share'
    }

    It 'static: this test mocks the seams, NOT raw .NET statics' {
        $testSrc = Get-Content -LiteralPath $PSCommandPath -Raw
        # Mocks the seams.
        [regex]::Matches($testSrc, 'Mock\s+(New-AdmanAuditMutex|Open-AdmanAuditStream|Write-AdmanEventLog)').Count |
            Should -BeGreaterOrEqual 1 -Because 'the test mocks the private wrapper seams'
        # Does NOT mock raw .NET statics. Build the forbidden literals WITHOUT writing them inline
        # (the phase-exit grep requires zero occurrences of these tokens in THIS file).
        $forbidden = @(
            ('[System.IO.' + 'File]::Open'),
            ('[System.Threading.' + 'Mutex]::new')
        )
        foreach ($f in $forbidden) {
            [regex]::Matches($testSrc, [regex]::Escape($f)).Count |
                Should -Be 0 -Because "the test must not mock the raw .NET static '$f' (Pester cannot mock it cleanly)"
        }
    }
}
