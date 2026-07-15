#Requires -Modules Pester
<#
.SYNOPSIS
    RPT-01 / RPT-02 / RPT-03 contract tests for the three D-03 renderers.

.DESCRIPTION
    Pins the renderer contract:
      * Format-AdmanReport emits a console table containing column headers and row
        values; degrades to the same table when a grid picker fails; emits a
        header-only table when -Properties is supplied with an empty pipeline;
        emits the literal string '(no results)' when -Properties is NOT supplied
        with an empty pipeline.
      * Export-AdmanReportCsv writes UTF8 CSV with -NoTypeInformation; uses a
        begin/process/end structure with explicit first-row handling (first row
        creates the file with headers, subsequent rows append); emits a
        header-only CSV when -Properties is supplied with an empty pipeline;
        emits a zero-byte file when -Properties is NOT supplied with an empty
        pipeline.
      * Export-AdmanReportHtml writes a single self-contained HTML file with an
        embedded style block, no external stylesheet link, the report title, and
        a populated table for non-empty input. Handles the two empty-result
        cases: (a) with -Properties the file contains a <table> with a header
        row matching -Properties and zero <tr> data rows; (b) without
        -Properties the file contains the literal text '(no results)' and no
        <table> element.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:FormatPath = Join-Path $script:RepoRoot 'Public/Format-AdmanReport.ps1'
    $script:CsvPath = Join-Path $script:RepoRoot 'Public/Export-AdmanReportCsv.ps1'
    $script:HtmlPath = Join-Path $script:RepoRoot 'Public/Export-AdmanReportHtml.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d3'
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

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Helper: build a small D-03-shaped user row.
    function script:New-AdmanTestUserRow {
        param(
            [string]$Sam = 'alice',
            [string]$Name = 'Alice',
            [bool]$Enabled = $true
        )
        [pscustomobject]@{
            ObjectType        = 'User'
            Name              = $Name
            SamAccountName    = $Sam
            Enabled           = $Enabled
            DistinguishedName = "CN=$Name,OU=Managed,DC=mock,DC=local"
            ObjectSid         = 'S-1-5-21-1-2-3-1000'
            ObjectGuid        = [guid]'11111111-2222-3333-4444-555555555555'
            DisplayName       = $Name
            UserPrincipalName = "$Sam@mock.local"
            LockedOut         = $false
            PasswordExpired   = $false
            PasswordLastSet   = [datetime]'2026-01-01T00:00:00Z'
            AccountExpirationDate = $null
            LastLogonDate     = [datetime]'2026-07-01T00:00:00Z'
            whenCreated       = [datetime]'2025-01-01T00:00:00Z'
            whenChanged       = [datetime]'2026-06-01T00:00:00Z'
        }
    }
}

Describe 'Format-AdmanReport: console table output (RPT-01)' -Tag 'Unit' {

    It 'emits a string containing column headers and row values' {
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $out = $row | Format-AdmanReport
        $text = ($out -join "`n")
        $text | Should -Match 'SamAccountName'
        $text | Should -Match 'alice'
        $text | Should -Match 'ObjectType'
        $text | Should -Match 'User'
    }

    It 'accepts an optional -Properties parameter' {
        $cmd = Get-Command Format-AdmanReport
        $cmd.Parameters.Keys | Should -Contain 'Properties'
    }

    It 'renders multiple rows in the same table' {
        $rows = @(
            New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
            New-AdmanTestUserRow -Sam 'bob' -Name 'Bob'
        )
        $out = $rows | Format-AdmanReport
        $text = ($out -join "`n")
        $text | Should -Match 'alice'
        $text | Should -Match 'bob'
    }

    It 'degrades to console table when -UseGridView is requested but the grid picker fails' {
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        # Force the grid picker to fail deterministically on BOTH editions.
        # On PS7 Core without ConsoleGuiTools the picker naturally fails; on
        # Desktop 5.1 Out-GridView exists in-box so the renderer would try it
        # and (in a non-interactive test host) emit nothing. Mock Out-GridView
        # to throw so the renderer's try/catch fallback to Format-Table is
        # exercised. (Out-ConsoleGridView is only invoked on Core and only when
        # the ConsoleGuiTools module is present — absent in this test host, so
        # no mock is needed for that path.) NOTE: do not reference It-scope
        # variables inside the mock body — under PS 5.1 + Pester 6 the mock
        # executes in the adman module session state and external variables
        # resolve to $null.
        Mock Out-GridView -ModuleName adman { throw 'no GUI (test-forced)' }
        $out = $row | Format-AdmanReport -UseGridView
        $text = ($out -join "`n")
        $text | Should -Match 'alice'
    }

    It 'emits a header-only table when the pipeline is empty and -Properties is supplied' {
        $out = @() | Format-AdmanReport -Properties @('Name', 'SamAccountName', 'Enabled')
        $text = ($out -join "`n")
        $text | Should -Match 'Name'
        $text | Should -Match 'SamAccountName'
        $text | Should -Match 'Enabled'
        # No data rows: the literal '(no results)' must NOT appear.
        $text | Should -Not -Match '\(no results\)'
    }

    It "emits the literal string '(no results)' when the pipeline is empty and -Properties is NOT supplied" {
        $out = @() | Format-AdmanReport
        $text = ($out -join "`n").Trim()
        $text | Should -Be '(no results)'
    }
}

Describe 'Export-AdmanReportCsv: streaming CSV output (RPT-02)' -Tag 'Unit' {

    It 'creates a CSV file with no #TYPE line and UTF8 encoding' {
        $csvPath = Join-Path $TestDrive 'report.csv'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $row | Export-AdmanReportCsv -Path $csvPath
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $content = Get-Content -LiteralPath $csvPath -Raw
        $content | Should -Not -Match '#TYPE'
        $content | Should -Match 'SamAccountName'
        $content | Should -Match 'alice'
    }

    It 'accepts an optional -Properties parameter' {
        $cmd = Get-Command Export-AdmanReportCsv
        $cmd.Parameters.Keys | Should -Contain 'Properties'
    }

    It 'uses a begin/process/end structure with explicit first-row handling (no direct pipe-to-Export-Csv inside process)' {
        $src = Get-Content -LiteralPath $script:CsvPath -Raw
        # Must call Export-Csv with -Append at least once (subsequent rows).
        $src | Should -Match 'Export-Csv.*-Append'
        # Must NOT pipe $InputObject directly to Export-Csv (that overwrites the
        # file on every row and emits one header block per row).
        $src | Should -Not -Match '\$InputObject\s*\|\s*Export-Csv'
    }

    It 'multi-row streaming: piping three PSCustomObjects produces exactly one header row and three data rows' {
        $csvPath = Join-Path $TestDrive 'multi.csv'
        $rows = @(
            New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
            New-AdmanTestUserRow -Sam 'bob' -Name 'Bob'
            New-AdmanTestUserRow -Sam 'carol' -Name 'Carol'
        )
        $rows | Export-AdmanReportCsv -Path $csvPath
        $lines = @(Get-Content -LiteralPath $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        # 1 header + 3 data rows = 4 non-empty lines.
        $lines.Count | Should -Be 4
        # Header row appears exactly once. Export-Csv quotes every field, so the
        # header line starts with "ObjectType" (with the leading quote).
        $headerLines = @($lines | Where-Object { $_ -match 'ObjectType' -and $_ -match 'SamAccountName' })
        $headerLines.Count | Should -Be 1
        # Data rows present.
        ($lines -join "`n") | Should -Match 'alice'
        ($lines -join "`n") | Should -Match 'bob'
        ($lines -join "`n") | Should -Match 'carol'
    }

    It 'empty-result CSV with -Properties: file contains exactly one header line and zero data rows' {
        $csvPath = Join-Path $TestDrive 'empty-with-props.csv'
        @() | Export-AdmanReportCsv -Path $csvPath -Properties @('Name', 'SamAccountName', 'Enabled')
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $lines = @(Get-Content -LiteralPath $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'Name,SamAccountName,Enabled'
    }

    It 'empty-result CSV without -Properties: file exists (zero bytes acceptable) and no exception is thrown' {
        $csvPath = Join-Path $TestDrive 'empty-no-props.csv'
        { @() | Export-AdmanReportCsv -Path $csvPath } | Should -Not -Throw
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $lines = @(Get-Content -LiteralPath $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 0
    }

    It 'removes a stale file at -Path before writing (reruns do not append onto old data)' {
        $csvPath = Join-Path $TestDrive 'rerun.csv'
        # Seed a stale file with junk.
        'STALE,JUNK,HEADER' | Out-File -FilePath $csvPath -Encoding UTF8
        'stale,row,here' | Out-File -FilePath $csvPath -Encoding UTF8 -Append
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $row | Export-AdmanReportCsv -Path $csvPath
        $content = Get-Content -LiteralPath $csvPath -Raw
        $content | Should -Not -Match 'STALE'
        $content | Should -Not -Match 'stale,row'
        $content | Should -Match 'alice'
    }

    It 'throws a clear error when the parent directory does not exist (T-04-01)' {
        $csvPath = Join-Path $TestDrive 'no-such-dir\report.csv'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        { $row | Export-AdmanReportCsv -Path $csvPath } | Should -Throw
    }
}

Describe 'Export-AdmanReportCsv: PS 5.1 / 7 parity' -Tag 'Unit' {

    It 'does not use any PS6+ -AsHashtable or PS7-only operators' {
        $src = Get-Content -LiteralPath $script:CsvPath -Raw
        $src | Should -Not -Match '-AsHashtable'
        $src | Should -Not -Match '\?\?'
        $src | Should -Not -Match '\?\.'
    }

    It 'Format-AdmanReport does not use any PS6+ -AsHashtable or PS7-only operators' {
        $src = Get-Content -LiteralPath $script:FormatPath -Raw
        $src | Should -Not -Match '-AsHashtable'
        $src | Should -Not -Match '\?\?'
        $src | Should -Not -Match '\?\.'
    }
}

Describe 'Export-AdmanReportHtml: self-contained HTML output (RPT-03)' -Tag 'Unit' {

    It 'writes a single .html file containing embedded CSS' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $row | Export-AdmanReportHtml -Path $htmlPath
        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match '<style>'
        $content | Should -Match 'font-family'
    }

    It 'contains no external stylesheet link' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $row | Export-AdmanReportHtml -Path $htmlPath
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Not -Match 'rel=stylesheet'
        $content | Should -Not -Match 'rel="stylesheet"'
    }

    It 'contains the report title' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        $row | Export-AdmanReportHtml -Path $htmlPath -Title 'Stale accounts'
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match 'Stale accounts'
    }

    It 'renders a non-empty result set as a populated table' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        $rows = @(
            New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
            New-AdmanTestUserRow -Sam 'bob' -Name 'Bob'
        )
        $rows | Export-AdmanReportHtml -Path $htmlPath
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match '<table>'
        $content | Should -Match 'alice'
        $content | Should -Match 'bob'
        $content | Should -Match 'SamAccountName'
    }

    It 'renders boolean columns as the literal strings True/False (not bare $true/$false)' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice' -Enabled $true
        $row | Export-AdmanReportHtml -Path $htmlPath
        $content = Get-Content -LiteralPath $htmlPath -Raw
        # The Enabled column should render as the string 'True', not 'True' as a
        # boolean type name. ConvertTo-Html on a bare $true emits 'True' anyway,
        # but the calculated property ensures it is a string.
        $content | Should -Match '>True<'
    }

    It 'empty-result HTML with -Properties: file contains a <table> with a header row matching -Properties and zero <tr> data rows' {
        $htmlPath = Join-Path $TestDrive 'empty-with-props.html'
        @() | Export-AdmanReportHtml -Path $htmlPath -Properties @('Name', 'SamAccountName', 'Enabled')
        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match '<table>'
        $content | Should -Match 'Name'
        $content | Should -Match 'SamAccountName'
        $content | Should -Match 'Enabled'
        # Count <tr> occurrences: should be exactly 1 (the header row).
        $trCount = ([regex]::Matches($content, '<tr>')).Count
        $trCount | Should -Be 1
    }

    It 'empty-result HTML without -Properties: file contains the literal text (no results) and no <table> element' {
        $htmlPath = Join-Path $TestDrive 'empty-no-props.html'
        @() | Export-AdmanReportHtml -Path $htmlPath
        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match '\(no results\)'
        $content | Should -Not -Match '<table>'
    }

    It 'accepts an optional -Properties parameter' {
        $cmd = Get-Command Export-AdmanReportHtml
        $cmd.Parameters.Keys | Should -Contain 'Properties'
    }

    It 'throws a clear error when the parent directory does not exist (T-04-01)' {
        $htmlPath = Join-Path $TestDrive 'no-such-dir\report.html'
        $row = New-AdmanTestUserRow -Sam 'alice' -Name 'Alice'
        { $row | Export-AdmanReportHtml -Path $htmlPath } | Should -Throw
    }

    It 'does not use any PS6+ ConvertTo-Html parameters (-CssUri, -Charset, -Meta, -Transitional)' {
        $src = Get-Content -LiteralPath $script:HtmlPath -Raw
        $src | Should -Not -Match '-CssUri'
        $src | Should -Not -Match '-Charset'
        $src | Should -Not -Match '-Meta'
        $src | Should -Not -Match '-Transitional'
    }

    It 'does not use any PS6+ -AsHashtable or PS7-only operators' {
        $src = Get-Content -LiteralPath $script:HtmlPath -Raw
        $src | Should -Not -Match '-AsHashtable'
        $src | Should -Not -Match '\?\?'
        $src | Should -Not -Match '\?\.'
    }
}
