#Requires -Version 5.1
<#
.SYNOPSIS
    Audit hash-chain helpers and rotation (D-05).

.DESCRIPTION
    Provides tamper-evident hash-chain primitives for the audit JSONL log:

      * Get-AdmanAuditPreviousHash - returns the stored SHA-256 hash of the last
        record in a daily audit file, or the 64-zero sentinel when the file does
        not yet exist or its last line is empty/whitespace. Throws on any read or
        parse error so Write-AdmanAudit cannot silently substitute a zero/empty
        prevHash.

      * Get-AdmanAuditIntegrity    - verifies each record's own hash and the
        per-day prevHash chain, reporting the first broken link.

      * Invoke-AdmanAuditRotation  - moves audit-*.jsonl files older than
        audit.retentionDays into .store/audit/archive/YYYYMM/.

    The hash chain is tamper-evident, not tamper-proof: anyone with filesystem
    write access can rewrite the files, but the integrity verifier will detect
    that the chain no longer validates.
#>

Set-StrictMode -Version Latest

function Get-AdmanAuditPreviousHash {
    <#
    .SYNOPSIS
        Return the stored hash of the last audit record in $Path, or the 64-zero
        sentinel for an empty/missing file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return '0' * 64
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    if ($lines.Count -eq 0) {
        return '0' * 64
    }

    $last = $lines[-1]
    if ([string]::IsNullOrWhiteSpace($last)) {
        return '0' * 64
    }

    $rec = $null
    try {
        $rec = $last | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Get-AdmanAuditPreviousHash: cannot parse last audit record as JSON: $_"
    }

    if (-not ($rec.PSObject.Properties.Name -contains 'hash')) {
        throw "Get-AdmanAuditPreviousHash: last audit record is missing the 'hash' field."
    }

    $hash = [string]$rec.hash
    if (-not ($hash -match '^[0-9a-fA-F]{64}$')) {
        throw "Get-AdmanAuditPreviousHash: last audit record 'hash' is not a 64-character hex string."
    }

    return $hash.ToLower()
}

function Get-AdmanAuditIntegrity {
    <#
    .SYNOPSIS
        Verify the SHA-256 hash chain of an audit JSONL file.

    .DESCRIPTION
        Parses each non-empty line as JSON and verifies:
          1. The record's own $rec.hash equals the lowercase hex SHA-256 of the
             canonical record bytes. The canonical record is built by removing
             only the 'hash' key, serializing with ConvertTo-Json -Compress -Depth 5,
             and UTF8-encoding the result.
          2. The record's $rec.prevHash equals the stored 'hash' of the immediately
             previous record; the first record uses the 64-zero sentinel.

        Returns a PSCustomObject with Valid, Lines, BrokenAtLine, and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Valid        = $false
            Lines        = 0
            BrokenAtLine = 0
            Reason       = 'File not found.'
        }
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $records = @()

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $records += ($line | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            return [pscustomobject]@{
                Valid        = $false
                Lines        = $records.Count
                BrokenAtLine = ($records.Count + 1)
                Reason       = "Cannot parse line as JSON: $_"
            }
        }
    }

    $zeroHash = '0' * 64

    # First pass: verify the prevHash chain. Tampering a record breaks the NEXT link,
    # so this reports the first downstream inconsistency.
    for ($i = 0; $i -lt $records.Count; $i++) {
        $rec = $records[$i]

        if (-not ($rec.PSObject.Properties.Name -contains 'prevHash')) {
            return [pscustomobject]@{
                Valid        = $false
                Lines        = $records.Count
                BrokenAtLine = ($i + 1)
                Reason       = "Record is missing the 'prevHash' field."
            }
        }

        $expectedPrevHash = if ($i -eq 0) { $zeroHash } else { ([string]$records[$i - 1].hash).ToLower() }
        $storedPrevHash = ([string]$rec.prevHash).ToLower()

        if ($storedPrevHash -ne $expectedPrevHash) {
            return [pscustomobject]@{
                Valid        = $false
                Lines        = $records.Count
                BrokenAtLine = ($i + 1)
                Reason       = "prevHash mismatch at line $($i + 1) (stored '$storedPrevHash', expected '$expectedPrevHash')."
            }
        }
    }

    # Second pass: verify each record's own hash against its canonical bytes.
    for ($i = 0; $i -lt $records.Count; $i++) {
        $rec = $records[$i]

        if (-not ($rec.PSObject.Properties.Name -contains 'hash')) {
            return [pscustomobject]@{
                Valid        = $false
                Lines        = $records.Count
                BrokenAtLine = ($i + 1)
                Reason       = "Record is missing the 'hash' field."
            }
        }

        $canonical = [ordered]@{}
        foreach ($prop in $rec.PSObject.Properties) {
            if ($prop.Name -eq 'hash') { continue }
            $canonical[$prop.Name] = $prop.Value
        }

        $canonicalJson = $canonical | ConvertTo-Json -Compress -Depth 5
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalJson)
        $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $computedHash = -join ($sha | ForEach-Object { $_.ToString('x2') })
        $storedHash = ([string]$rec.hash).ToLower()

        if ($computedHash -ne $storedHash) {
            return [pscustomobject]@{
                Valid        = $false
                Lines        = $records.Count
                BrokenAtLine = ($i + 1)
                Reason       = "Self-hash mismatch at line $($i + 1) (stored '$storedHash', computed '$computedHash')."
            }
        }
    }

    return [pscustomobject]@{
        Valid        = $true
        Lines        = $records.Count
        BrokenAtLine = 0
        Reason       = ''
    }
}

function Invoke-AdmanAuditRotation {
    <#
    .SYNOPSIS
        Archive audit JSONL files older than audit.retentionDays.

    .DESCRIPTION
        Enumerates audit-*.jsonl files in the audit directory. For each file whose
        embedded date is older than $RetentionDays from today, moves it into
        $AuditDir\archive\YYYYMM\ and writes an archive-YYYYMM.marker file with the
        rotation timestamp.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$AuditDir = $script:Config.AuditDir,
        [int]$RetentionDays = $script:Config.audit.retentionDays
    )

    if (-not (Test-Path -LiteralPath $AuditDir)) {
        return
    }

    $cutoff = (Get-Date).Date.AddDays(-$RetentionDays)

    foreach ($file in (Get-ChildItem -LiteralPath $AuditDir -Filter 'audit-*.jsonl' -File -ErrorAction Stop)) {
        # WR-05: the regex intentionally checks only the 8-digit date shape; calendar
        # validity (month/day ranges) is enforced by the ParseExact call below, which
        # skips any file whose embedded date is not a real calendar date.
        if ($file.Name -notmatch '^audit-(\d{8})\.jsonl$') { continue }
        $dateString = $Matches[1]
        try {
            $fileDate = [datetime]::ParseExact($dateString, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            Write-Warning "Skipping audit file '$($file.Name)': embedded date '$dateString' is not a valid calendar date."
            continue
        }

        if ($fileDate -lt $cutoff) {
            $archiveMonth = $fileDate.ToString('yyyyMM')
            $archiveDir = Join-Path $AuditDir ('archive\{0}' -f $archiveMonth)
            if (-not (Test-Path -LiteralPath $archiveDir)) {
                $null = New-Item -ItemType Directory -Path $archiveDir -Force -ErrorAction Stop
            }

            $marker = Join-Path $archiveDir ('archive-{0}.marker' -f $archiveMonth)
            if (-not (Test-Path -LiteralPath $marker)) {
                ('{0:yyyy-MM-ddTHH:mm:ssZ}' -f (Get-Date).ToUniversalTime()) | Set-Content -LiteralPath $marker -Encoding UTF8 -ErrorAction Stop
            }

            $destination = Join-Path $archiveDir $file.Name
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Move to archive')) {
                Move-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
            }
        }
    }
}
