#Requires -Version 5.1
<#
.SYNOPSIS
    Import-AdmanBulkCsv - strict-schema CSV loader for the bulk engine (BULK-04, D-23/D-25).

.DESCRIPTION
    Reads a CSV file and validates its header set before returning rows. Only the
    columns ObjectType, Identity, Action, TargetPath, and GroupIdentity are allowed.
    Unknown columns, duplicate columns, or missing required columns (Action, Identity)
    cause a terminating error before any row is returned. Empty files return an empty
    array.
#>

Set-StrictMode -Version Latest

function Import-AdmanBulkCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $allowed = @('ObjectType', 'Identity', 'Action', 'TargetPath', 'GroupIdentity')
    $required = @('Action', 'Identity')

    # Read the header line first so duplicate/unknown/missing checks can throw with
    # adman messages before Import-Csv parses the rows (Import-Csv itself throws on
    # duplicate headers with a less helpful message).
    $headerLine = (Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop) -replace "`r?`n", ''
    if ([string]::IsNullOrWhiteSpace($headerLine)) {
        return @()
    }
    # WR-07: split the header using RFC-4180 quoting rules so a quoted comma is not treated as
    # a field separator (keeps the manual checks in sync with Import-Csv).
    $actual = @([regex]::Matches($headerLine, '(?:^|,)(?:"((?:[^"]|"")*)"|([^,]*))') | ForEach-Object {
        if ($_.Groups[1].Success) {
            ($_.Groups[1].Value -replace '""', '"').Trim()
        } else {
            $_.Groups[2].Value.Trim()
        }
    })

    $duplicates = @($actual | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($duplicates.Count -gt 0) {
        throw "CSV contains duplicate columns: $($duplicates -join ', ')"
    }

    $unknown = @($actual | Where-Object { $_ -notin $allowed })
    if ($unknown.Count -gt 0) {
        throw "CSV contains unknown columns: $($unknown -join ', ')"
    }

    $missing = @($required | Where-Object { $_ -notin $actual })
    if ($missing.Count -gt 0) {
        throw "CSV is missing required columns: $($missing -join ', ')"
    }

    $rows = Import-Csv -LiteralPath $Path -ErrorAction Stop
    if ($null -eq $rows) {
        return @()
    }
    # A header-only file returns one row whose properties are all empty strings.
    # Treat that as no data so the bulk engine does not act on a phantom identity.
    if (@($rows).Count -eq 1 -and
        ($rows[0].PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Value) }).Count -eq 0) {
        return @()
    }
    # Unary comma preserves arrayness when the caller invokes us via a scriptblock.
    return ,@($rows)
}
