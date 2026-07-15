#Requires -Version 5.1
<#
.SYNOPSIS
    Format-AdmanReport - console renderer for D-03 schema objects (RPT-01).

.DESCRIPTION
    Renders a PSCustomObject[] (D-03 schema) as a console table. Default output is
    Format-Table -AutoSize | Out-String -Width 4096 emitted as a single string.

    Optional grid picker (-UseGridView):
      * Desktop edition + interactive session + Get-Command Out-GridView available
        -> Out-GridView (no -PassThru; display only).
      * Core edition + Get-Module -ListAvailable Microsoft.PowerShell.ConsoleGuiTools
        -> Out-ConsoleGridView.
      * ANY failure inside the grid path silently degrades to the console table.

    MEMORY BOUND (MEDIUM-4): the console renderer is bounded by the host display
    buffer. For result sets expected to exceed ~10,000 rows the caller should use
    Export-AdmanReportCsv (which streams row-by-row) instead.

    EMPTY-RESULT SCHEMA (Cycle 2/3 finding): when the pipeline yields zero objects,
    the renderer cannot infer headers from data.
      * If -Properties is supplied, emit a header-only table built from that
        property list (one row of column names, no data rows).
      * If -Properties is NOT supplied, emit the literal string '(no results)'.

    Callers producing reports that may legitimately be empty (e.g., a stale-account
    report on a clean domain) MUST pass -Properties with the D-03 schema column
    list so the empty output still shows the expected headers.

    This renderer NEVER writes files; it emits strings to the pipeline.

.EXAMPLE
    Find-AdmanUser -SamAccountName 'alice' | Format-AdmanReport

.EXAMPLE
    Get-AdmanStaleReport | Format-AdmanReport -Properties $entry.Properties
#>

Set-StrictMode -Version Latest

function Format-AdmanReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$InputObject,

        [switch]$UseGridView,

        [string[]]$Properties
    )

    begin {
        $rows = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($null -ne $InputObject) {
            # Unroll arrays so each row lands as its own element.
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
        # EMPTY-RESULT SCHEMA: zero rows collected.
        if ($rows.Count -eq 0) {
            if ($null -ne $Properties -and @($Properties).Count -gt 0) {
                # Header-only table built from the property list. Construct a
                # single prototype object with empty-string values so Format-Table
                # emits the column header row, then strip the (empty) data row.
                $proto = [ordered]@{}
                foreach ($p in @($Properties)) {
                    if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
                    $proto[$p] = ''
                }
                if ($proto.Count -eq 0) {
                    Write-Output '(no results)'
                    return
                }
                $headerOnly = ([pscustomobject]$proto | Format-Table -AutoSize | Out-String -Width 4096)
                # Format-Table on a single empty-string row emits:
                #   line 1: header
                #   line 2: dashes
                #   line 3: blank (the empty data row)
                # Strip trailing blank lines so only the header remains.
                $trimmed = $headerOnly -replace "(`r?`n)+$", ''
                Write-Output $trimmed
                return
            }
            Write-Output '(no results)'
            return
        }

        # Grid picker path (optional). Any failure silently degrades to console table.
        if ($UseGridView) {
            $gridUsed = $false
            try {
                if ($PSEdition -eq 'Core') {
                    $cg = Get-Module -ListAvailable -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ErrorAction Stop
                    if ($null -ne $cg -and (Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue)) {
                        $rows.ToArray() | Out-ConsoleGridView -ErrorAction Stop
                        $gridUsed = $true
                    }
                }
                else {
                    # Desktop edition: require interactive session + Out-GridView.
                    $interactive = [Environment]::UserInteractive
                    if ($interactive -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
                        $rows.ToArray() | Out-GridView -ErrorAction Stop
                        $gridUsed = $true
                    }
                }
            }
            catch {
                $gridUsed = $false
            }
            if ($gridUsed) { return }
            # Fall through to console table on any failure.
        }

        # Default: console table.
        $table = ($rows.ToArray() | Format-Table -AutoSize | Out-String -Width 4096)
        Write-Output $table
    }
}
