#Requires -Version 5.1
Set-StrictMode -Version Latest

function Export-AdmanReportCsv {
    <#
    .SYNOPSIS
        Export-AdmanReportCsv - streaming CSV renderer for D-03 schema objects (RPT-02).
    
    .DESCRIPTION
        Writes a PSCustomObject[] (D-03 schema) to a CSV file using Export-Csv
        -NoTypeInformation -Encoding UTF8.
    
        STREAMING (MEDIUM-4 + Cycle 2/3 finding): the renderer uses a begin/process/end
        structure with explicit first-row handling so memory stays O(1) in the row
        count. Each row is written and released inside process; no intermediate
        collection is built. This is the documented fallback for large result sets
        (e.g., inventory exports of large OUs).
          * begin: validate the parent directory of -Path exists (throw a clear error
            if not); remove any stale file at -Path so reruns do not append onto old
            data; reset the first-row flag.
          * process: the FIRST input object is piped to Export-Csv WITHOUT -Append
            (creates the file with headers). Subsequent objects are piped to
            Export-Csv WITH -Append (appends a data row, no duplicate header).
          * end: when the pipeline yielded zero objects, emit a header-only CSV if
            -Properties was supplied (single UTF8-with-BOM line of joined column
            names via Out-File); otherwise write a zero-byte file and emit a
            verbose message that no schema was provided.
    
        EMPTY-RESULT SCHEMA (Cycle 2/3 finding): callers producing reports that may
        legitimately be empty (e.g., a stale-account report on a clean domain) MUST
        pass -Properties with the D-03 schema column list so the empty output still
        shows the expected headers.
    
        The parent directory is NEVER auto-created (T-04-01): a missing directory
        throws so the operator notices the path.
    
    .EXAMPLE
        Find-AdmanUser -SamAccountName 'alice' | Export-AdmanReportCsv -Path .\alice.csv
    
    .EXAMPLE
        Get-AdmanStaleReport | Export-AdmanReportCsv -Path .\stale.csv -Properties $entry.Properties
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string[]]$Properties
    )

    begin {
        $firstRowSeen = $false

        # Validate the parent directory exists (T-04-01: never auto-create).
        $parent = Split-Path -Path $Path -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            # Relative filename with no directory component -> current location.
            $parent = (Get-Location).Path
        }
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw "Export-AdmanReportCsv: parent directory does not exist: $parent"
        }

        # Remove any stale file so reruns do not append onto old data.
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
    }

    process {
        if ($null -eq $InputObject) { return }

        # Unroll arrays so each row lands as its own Export-Csv call.
        $items = @()
        if ($InputObject -is [System.Collections.IEnumerable] -and
            $InputObject -isnot [string] -and
            $InputObject -isnot [System.Collections.IDictionary] -and
            $InputObject -isnot [pscustomobject]) {
            foreach ($item in $InputObject) {
                if ($null -ne $item) { $items += $item }
            }
        }
        else {
            $items = @($InputObject)
        }

        foreach ($row in $items) {
            if (-not $firstRowSeen) {
                # First row: create the file with headers (no -Append).
                $row | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                $firstRowSeen = $true
            }
            else {
                # Subsequent rows: append a data row (no duplicate header).
                $row | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -Append -ErrorAction Stop
            }
        }
    }

    end {
        if (-not $firstRowSeen) {
            # Empty pipeline: emit a header-only CSV when -Properties was supplied.
            if ($null -ne $Properties -and @($Properties).Count -gt 0) {
                # WR-05: RFC 4180-quote any header name containing a comma, quote, CR, or LF.
                # Doubles embedded quotes per RFC 4180 section 2.
                $header = (@($Properties) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
                    $s = [string]$_
                    if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
                }) -join ','
                if ([string]::IsNullOrWhiteSpace($header)) {
                    # Properties was supplied but contained only whitespace - treat as no schema.
                    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                        New-Item -ItemType File -Path $Path -Force | Out-Null
                    }
                    Write-Verbose 'Export-AdmanReportCsv: no schema provided; wrote an empty file.'
                    return
                }
                # Out-File -Encoding UTF8 on PS 5.1 writes UTF8 with BOM, matching
                # Export-Csv -Encoding UTF8 behavior on 5.1 (Excel-friendly).
                $header | Out-File -FilePath $Path -Encoding UTF8 -ErrorAction Stop
            }
            else {
                # No schema provided: write a zero-byte file so callers can rely on
                # the file existing, and emit a verbose message.
                if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                    New-Item -ItemType File -Path $Path -Force | Out-Null
                }
                Write-Verbose 'Export-AdmanReportCsv: no schema provided; wrote an empty file.'
            }
        }
    }
}
