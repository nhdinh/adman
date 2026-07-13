#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED) - SAFE-04 audit-integrity orphan sweep (Find-AdmanAuditOrphans).

    Proves the PENDING<->OUTCOME correlation sweep that detects an OUTCOME-write gap (D-03):
      * Test 1 (orphan detection): a .jsonl with a PENDING record whose correlationId has NO later
        OUTCOME record is returned as an orphan; a PENDING with a matching OUTCOME is NOT flagged.
      * Test 2 (no silent drop): orphans are surfaced (returned + Write-PSFMessage Warning) so
        monitoring can detect an OUTCOME-write gap; the function NEVER deletes or rewrites records.
      * Static: the sweep correlates by correlationId, checks the OUTCOME result set, and is
        read-only (no Remove-Item / Set-Content / Out-File on the audit files).

    The sweep is the detection seam for an OUTCOME-write gap from Task 1: it surfaces the gap, it
    does not "fix" it (D-03).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. The sweep reads
    real TestDrive .jsonl files (no AD, no live domain). Write-PSFMessage mocked to observe the
    warning.
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
    $script:SweepPath = Join-Path $script:RepoRoot 'Private\Audit\Find-AdmanAuditOrphans.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stub so Pester's Mock resolver finds the module-private sweep at RED.
    function global:Find-AdmanAuditOrphans { param($AuditDir, $LookbackDays) }
    function global:Write-PSFMessage { param($Level, $Message) }

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

    # Write one JSONL audit record line to today's file under $AuditDir.
    function Write-AdmanJsonlLine {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$AuditDir,
            [Parameter(Mandatory)][string]$CorrelationId,
            [Parameter(Mandatory)][string]$Result,
            [string]$Verb = 'Disable-ADAccount',
            [string]$Target = 'CN=Alice,OU=Managed,DC=mock,DC=local'
        )
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $AuditDir $name
        $rec = [ordered]@{
            tsUtc         = (Get-Date).ToUniversalTime().ToString('o')
            who           = 'DOMAIN\admin'
            userSid       = 'S-1-5-21-1-2-3-1000'
            what          = $Verb
            scope         = 'OU=Managed,DC=mock,DC=local'
            target        = $Target
            targets       = @(@{ dn = $Target; sid = 'S-1-5-21-1-2-3-1000'; objectClass = 'user' })
            count         = 1
            whatIf        = $false
            result        = $Result
            reason        = ''
            correlationId = $CorrelationId
            host          = 'TESTHOST'
            psEdition     = 'Desktop'
            moduleVersion = '0.0.0'
        } | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $path -Value $rec -Encoding UTF8
    }
}

Describe 'SAFE-04: Find-AdmanAuditOrphans PENDING to OUTCOME correlation sweep' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:AuditDir -Force | Out-Null
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
        Mock Write-PSFMessage -ModuleName adman { }
    }

    It 'Test 1 (orphan detection): a PENDING with no matching OUTCOME is flagged; a paired PENDING is not' {
        $orphanCid = [guid]::NewGuid().ToString()
        $pairedCid = [guid]::NewGuid().ToString()
        # Orphan: PENDING only.
        Write-AdmanJsonlLine -AuditDir $script:AuditDir -CorrelationId $orphanCid -Result 'PENDING'
        # Paired: PENDING + Success OUTCOME.
        Write-AdmanJsonlLine -AuditDir $script:AuditDir -CorrelationId $pairedCid -Result 'PENDING'
        Write-AdmanJsonlLine -AuditDir $script:AuditDir -CorrelationId $pairedCid -Result 'Success'

        $orphans = & (Get-Module adman) { Find-AdmanAuditOrphans }

        $orphanIds = @($orphans | ForEach-Object { $_.correlationId })
        $orphanIds | Should -Contain $orphanCid `
            -Because 'a PENDING with no OUTCOME in the window is an orphan (an OUTCOME-write gap)'
        $orphanIds | Should -Not -Contain $pairedCid `
            -Because 'a PENDING with a matching OUTCOME is NOT an orphan'
    }

    It 'Test 2 (no silent drop): orphans are surfaced via Write-PSFMessage Warning and records are never rewritten' {
        $orphanCid = [guid]::NewGuid().ToString()
        Write-AdmanJsonlLine -AuditDir $script:AuditDir -CorrelationId $orphanCid -Result 'PENDING'

        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $script:AuditDir $name
        $before = Get-Content -LiteralPath $path -Raw

        $orphans = & (Get-Module adman) { Find-AdmanAuditOrphans }

        # Surfaced (returned) AND a Warning emitted so monitoring can detect the gap.
        @($orphans).Count | Should -BeGreaterOrEqual 1 -Because 'the orphan is returned'
        Should -Invoke Write-PSFMessage -ModuleName adman -Times 1 -ParameterFilter {
            $Level -eq 'Warning'
        } -Because 'an OUTCOME-write gap is surfaced as a Warning, never silently dropped (D-03)'

        # Read-only: the audit file is byte-identical after the sweep (never deleted/rewritten).
        $after = Get-Content -LiteralPath $path -Raw
        $after | Should -Be $before -Because 'the orphan sweep is read-only; it never rewrites audit records'
    }

    It 'static: correlates by correlationId, checks the OUTCOME result set, and is read-only' {
        Test-Path -LiteralPath $script:SweepPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:SweepPath -Raw

        [regex]::Matches($src, 'correlationId').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the sweep correlates PENDING<->OUTCOME by correlationId'
        [regex]::Matches($src, 'PENDING').Count | Should -BeGreaterOrEqual 1 `
            -Because 'the sweep identifies PENDING records'
        [regex]::Matches($src, "Success|Failure|Refused|Cancelled").Count | Should -BeGreaterOrEqual 1 `
            -Because 'the sweep checks for a matching OUTCOME result'

        # Read-only: never deletes or rewrites audit records.
        [regex]::Matches($src, 'Remove-Item|Set-Content|Out-File').Count |
            Should -Be 0 -Because 'the orphan sweep is read-only; it never modifies audit records'
    }
}
