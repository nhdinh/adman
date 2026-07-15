#Requires -Version 5.1
<#
.SYNOPSIS
    Export-AdmanReportHtml - self-contained HTML renderer for D-03 schema objects (RPT-03).

.DESCRIPTION
    Writes a PSCustomObject[] (D-03 schema) to a single self-contained HTML file
    using ConvertTo-Html -Head with an embedded CSS fragment. No external CSS,
    no JavaScript, no PS6+ parameters (no external stylesheet link, no charset
    override, no metadata block, no transitional DOCTYPE).

    MEMORY BOUND (MEDIUM-4): the HTML renderer MUST collect the full input
    up-front because ConvertTo-Html requires it. For result sets expected to
    exceed ~10,000 rows, the caller should use Export-AdmanReportCsv (which
    streams) instead.

    BOOLEAN CELLS (LOW finding resolution): ConvertTo-Html does NOT automatically
    add .true/.false classes to boolean cells. The UI-SPEC references these
    classes for status coloring. Resolution: boolean columns (Enabled, LockedOut,
    PasswordExpired, RecycleBinEnabled) are emitted as the literal strings
    'True'/'False' via a calculated property BEFORE piping to ConvertTo-Html,
    so the CSS class hooks are not required for v1. The .true/.false CSS rules
    remain in the embedded fragment as forward-compatible hooks but are not
    load-bearing in v1.

    EMPTY-RESULT SCHEMA (Cycle 2/3 finding): when the collected list is empty,
    ConvertTo-Html cannot infer headers.
      * If -Properties is supplied, build a single-row "header prototype"
        PSCustomObject with those property names set to empty strings, pipe ONLY
        that prototype to ConvertTo-Html, then post-process the resulting HTML
        to remove the single <tr> data row (leaving the <table> with a header
        row and zero data rows).
      * If -Properties is NOT supplied, emit a minimal HTML document containing
        the title and the literal text '(no results)' inside a <p> tag - no
        <table> element.

    Callers producing reports that may legitimately be empty MUST pass
    -Properties with the D-03 schema column list.

    The parent directory is NEVER auto-created (T-04-01): a missing directory
    throws so the operator notices the path.

.EXAMPLE
    Find-AdmanUser -SamAccountName 'alice' | Export-AdmanReportHtml -Path .\alice.html

.EXAMPLE
    Get-AdmanStaleReport | Export-AdmanReportHtml -Path .\stale.html -Title 'Stale accounts' -Properties $entry.Properties
#>

Set-StrictMode -Version Latest

function Export-AdmanReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string]$Title = 'adman report',

        [string[]]$Properties
    )

    begin {
        $rows = [System.Collections.Generic.List[object]]::new()

        # Validate the parent directory exists (T-04-01: never auto-create).
        $parent = Split-Path -Path $Path -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = (Get-Location).Path
        }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw "Export-AdmanReportHtml: parent directory does not exist: $parent"
        }
    }

    process {
        if ($null -ne $InputObject) {
            if ($InputObject -is [System.Collections.IEnumerable] -and
                $InputObject -isnot [string] -and
                $InputObject -isnot [System.Collections.IDictionary] -and
                $InputObject -isnot [pscustomobject]) {
                foreach ($item in $InputObject) {
                    if ($null -ne $item) { $rows.Add($item) }
                }
            }
            else {
                $rows.Add($InputObject)
            }
        }
    }

    end {
        # Embedded CSS fragment per UI-SPEC contract. Single here-string passed
        # to ConvertTo-Html -Head. No external files, no JavaScript, no PS6+
        # parameters. The <title> element is included in the fragment because
        # ConvertTo-Html -Head replaces the entire head section (the -Title
        # parameter is ignored when -Head is used).
        $css = @"
<style>
body {
    font-family: Segoe UI, Arial, Helvetica, sans-serif;
    font-size: 13px;
    color: #222;
    background: #fff;
    margin: 24px;
}
h1 {
    font-size: 18px;
    color: #2b579a;
    margin-bottom: 8px;
}
.metadata {
    color: #555;
    font-size: 12px;
    margin-bottom: 16px;
}
table {
    border-collapse: collapse;
    width: 100%;
}
th, td {
    border: 1px solid #ccc;
    padding: 4px 8px;
    text-align: left;
    vertical-align: top;
}
th {
    background: #2b579a;
    color: #fff;
}
tr:nth-child(even) {
    background: #f2f2f2;
}
.false {
    color: #c00000;
    font-weight: bold;
}
.true {
    color: #008000;
}
</style>
<title>$Title</title>
"@

        # Boolean column names that must be rendered as 'True'/'False' strings
        # (LOW finding resolution: ConvertTo-Html does not add .true/.false
        # classes; emitting strings makes the output deterministic).
        $booleanColumns = @('Enabled', 'LockedOut', 'PasswordExpired', 'RecycleBinEnabled')

        # EMPTY-RESULT SCHEMA: zero rows collected.
        if ($rows.Count -eq 0) {
            if ($null -ne $Properties -and @($Properties).Count -gt 0) {
                # Build a single-row "header prototype" with empty-string values,
                # pipe ONLY that prototype to ConvertTo-Html, then post-process
                # to remove the single <tr> data row.
                $proto = [ordered]@{}
                foreach ($p in @($Properties)) {
                    if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
                    $proto[$p] = ''
                }
                if ($proto.Count -eq 0) {
                    # Properties was supplied but contained only whitespace.
                    $html = "<!DOCTYPE html>`n<html>`n<head>`n$css`n<title>$Title</title>`n</head>`n<body>`n<h1>$Title</h1>`n<p>(no results)</p>`n</body>`n</html>"
                    $html | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
                    return
                }
                $headerOnlyHtml = [pscustomobject]$proto | ConvertTo-Html -Head $css -Title $Title
                # Remove the single data row: the prototype produces exactly one
                # <tr> with empty <td> cells. The header row is the first <tr>
                # (with <th> cells); the data row is the second <tr>. Remove
                # the second <tr>...</tr> block.
                $htmlText = ($headerOnlyHtml | Out-String)
                # Match the data row: a <tr> containing only empty <td></td> cells.
                $htmlText = $htmlText -replace '(?s)<tr>(\s*<td></td>)+\s*</tr>', ''
                $htmlText | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
                return
            }
            # No -Properties: minimal HTML document with '(no results)'.
            $html = "<!DOCTYPE html>`n<html>`n<head>`n$css`n<title>$Title</title>`n</head>`n<body>`n<h1>$Title</h1>`n<p>(no results)</p>`n</body>`n</html>"
            $html | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
            return
        }

        # Non-empty: convert boolean columns to 'True'/'False' strings via
        # calculated properties, then pipe to ConvertTo-Html. The Expression
        # scriptblock receives the current pipeline object as $_, not as a
        # named parameter.
        $converted = $rows.ToArray() | Select-Object -Property @(
            foreach ($prop in $rows[0].PSObject.Properties.Name) {
                if ($prop -in $booleanColumns) {
                    @{
                        Name       = $prop
                        Expression = [scriptblock]::Create("if (`$_.$prop) { 'True' } else { 'False' }")
                    }
                }
                else {
                    $prop
                }
            }
        )

        $htmlResult = $converted | ConvertTo-Html -Head $css -Title $Title
        ($htmlResult | Out-String) | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
    }
}
