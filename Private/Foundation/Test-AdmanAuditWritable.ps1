#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanAuditWritable - lightweight, ZERO-BYTE audit-writability probe (startup admission).

.DESCRIPTION
    Confirms $script:Config.AuditDir is writable by opening today's JSONL file in Append / Write /
    Read-share mode via a disposable stream and calling Flush($true), then disposing - writing NO
    bytes. This mirrors the 00-05 writer's open-append + Flush($true) contract WITHOUT being the
    writer (key_link 00-03 <-> 00-05).

    ZERO-BYTE INVARIANT (do not break): the probe MUST NOT emit any bytes into the JSONL file.
    00-05's strict-JSONL orphan parser Find-AdmanAuditOrphans parses EVERY line as JSON; a single
    non-JSON marker line would break orphan detection. If a positive probe record is ever
    required, it MUST be emitted via Write-AdmanAudit (a valid JSONL record) - never as a raw
    marker. Returns $false on any failure; Initialize-Adman / Test-AdmanCapability throw
    fail-closed on $false.
#>

Set-StrictMode -Version Latest

function Test-AdmanAuditWritable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $dir = $script:Config.AuditDir
    if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
        }
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $dir $name
        $fs = $null
        try {
            $fs = [System.IO.FileStream]::new(
                $path,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::Read
            )
            $fs.Flush($true)
            return $true
        } finally {
            if ($null -ne $fs) { $fs.Dispose() }
        }
    } catch {
        return $false
    }
}
