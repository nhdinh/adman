#Requires -Version 5.1
<#
.SYNOPSIS
    Find-AdmanAuditOrphans - PENDING to OUTCOME correlation sweep (SAFE-04 audit integrity; D-03).

.DESCRIPTION
    Read-only detection seam for an OUTCOME-write gap. Scans the last N days of daily-rotated
    audit-*.jsonl files, parses every line as strict JSON, groups records by correlationId, and
    flags a record as an ORPHAN when it has result='PENDING' and the SAME correlationId has NO
    subsequent record with result in { Success, Failure, Refused, Cancelled } in the scanned
    window.

    An orphan is the observable signature of an OUTCOME-write failure (Task 1): the PENDING
    reservation was durably written but the OUTCOME append never landed. This function SURFACES
    that gap (returns the orphan correlationIds with tsUtc/what/target and emits a
    Write-PSFMessage -Level Warning summary) so monitoring can detect it - it NEVER deletes,
    rewrites, or "repairs" any audit record (D-03). Read-only by construction.

    Runs at startup (Initialize-Adman) and on demand. A clean window returns an empty list.
#>

Set-StrictMode -Version Latest

function Find-AdmanAuditOrphans {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$AuditDir = $script:Config.AuditDir,
        [int]$LookbackDays = 7
    )

    $outcomeResults = @('Success', 'Failure', 'Refused', 'Cancelled')

    # Collect every parseable record from the last N days of daily-rotated files.
    $records = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $LookbackDays; $i++) {
        $day = (Get-Date).AddDays(-$i)
        $name = 'audit-{0}.jsonl' -f $day.ToString('yyyyMMdd')
        $path = Join-Path $AuditDir $name
        if (-not (Test-Path -LiteralPath $path)) { continue }

        foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $records.Add(($line | ConvertFrom-Json -ErrorAction Stop))
            } catch {
                # A non-JSON line is ignored here (the probe writes ZERO bytes; a corrupt line is a
                # separate integrity concern). Strict parse keeps orphan correlation honest.
                continue
            }
        }
    }

    # Group by correlationId; a PENDING with no matching OUTCOME in the window is an orphan.
    $byCid = @{}
    foreach ($r in $records) {
        $cid = $r.correlationId
        if ([string]::IsNullOrEmpty($cid)) { continue }
        if (-not $byCid.ContainsKey($cid)) { $byCid[$cid] = [System.Collections.Generic.List[object]]::new() }
        $byCid[$cid].Add($r)
    }

    $orphans = [System.Collections.Generic.List[object]]::new()
    foreach ($cid in $byCid.Keys) {
        $group = $byCid[$cid]
        $hasPending = $false
        $hasOutcome = $false
        $pendingRec = $null
        foreach ($r in $group) {
            if ($r.result -eq 'PENDING') { $hasPending = $true; $pendingRec = $r }
            if ($outcomeResults -contains $r.result) { $hasOutcome = $true }
        }
        if ($hasPending -and -not $hasOutcome) {
            $orphans.Add([pscustomobject]@{
                correlationId = $cid
                tsUtc         = $pendingRec.tsUtc
                what          = $pendingRec.what
                target        = $pendingRec.target
            })
        }
    }

    if ($orphans.Count -gt 0) {
        Write-PSFMessage -Level Warning -Message ("AUDIT INTEGRITY: {0} PENDING record(s) with no matching OUTCOME (possible OUTCOME-write gap): {1}" -f `
            $orphans.Count, (($orphans | ForEach-Object { $_.correlationId }) -join ', '))
    }

    return $orphans.ToArray()
}
