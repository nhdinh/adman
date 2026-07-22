#Requires -Modules Pester
<#
.SYNOPSIS
    D-05 audit rotation tests (Invoke-AdmanAuditRotation).

.DESCRIPTION
    Proves that audit JSONL files older than audit.retentionDays are moved into
    .store/audit/archive/YYYYMM/ and that a marker file is written, while in-window
    files remain in place.
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
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}

Describe 'D-05: Invoke-AdmanAuditRotation archives old audit files' -Tag 'Unit' {

    It 'moves files older than retentionDays to archive\YYYYMM and leaves recent files in place' {
        $auditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $auditDir -Force | Out-Null

        $today = Get-Date
        $retentionDays = 90

        $recentDate = $today.AddDays(-1).ToString('yyyyMMdd')
        $oldDate1 = $today.AddDays(-($retentionDays + 1)).ToString('yyyyMMdd')
        $oldDate2 = $today.AddDays(-($retentionDays + 30)).ToString('yyyyMMdd')

        $recentFile = Join-Path $auditDir ("audit-{0}.jsonl" -f $recentDate)
        $oldFile1 = Join-Path $auditDir ("audit-{0}.jsonl" -f $oldDate1)
        $oldFile2 = Join-Path $auditDir ("audit-{0}.jsonl" -f $oldDate2)

        'recent' | Set-Content -LiteralPath $recentFile -Encoding UTF8
        'old1' | Set-Content -LiteralPath $oldFile1 -Encoding UTF8
        'old2' | Set-Content -LiteralPath $oldFile2 -Encoding UTF8

        & (Get-Module adman) {
            param($Dir, $Days)
            Invoke-AdmanAuditRotation -AuditDir $Dir -RetentionDays $Days -Confirm:$false
        } -Dir $auditDir -Days $retentionDays

        # Recent file stays.
        Test-Path -LiteralPath $recentFile | Should -BeTrue -Because 'recent files remain in the audit directory'

        # Old files are archived by month.
        $archiveMonth1 = $today.AddDays(-($retentionDays + 1)).ToString('yyyyMM')
        $archiveMonth2 = $today.AddDays(-($retentionDays + 30)).ToString('yyyyMM')
        $archiveDir1 = Join-Path $auditDir ('archive\{0}' -f $archiveMonth1)
        $archiveDir2 = Join-Path $auditDir ('archive\{0}' -f $archiveMonth2)

        Test-Path -LiteralPath (Join-Path $archiveDir1 ("audit-{0}.jsonl" -f $oldDate1)) | Should -BeTrue -Because 'old files are moved to archive\YYYYMM'
        Test-Path -LiteralPath (Join-Path $archiveDir2 ("audit-{0}.jsonl" -f $oldDate2)) | Should -BeTrue -Because 'old files are moved to archive\YYYYMM'

        # Marker files exist.
        Test-Path -LiteralPath (Join-Path $archiveDir1 ("archive-{0}.marker" -f $archiveMonth1)) | Should -BeTrue -Because 'a marker file is written in each archive folder'
        Test-Path -LiteralPath (Join-Path $archiveDir2 ("archive-{0}.marker" -f $archiveMonth2)) | Should -BeTrue -Because 'a marker file is written in each archive folder'
    }
}
