#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanOffboardingState - read the authoritative restore state from the audit log (FLOW-03).

.DESCRIPTION
    Returns the latest successful, non-dry-run offboarding record for a user so that
    Restore-AdmanQuarantinedUser can reverse disable, group stripping, and OU move.

    Matching is by exact DN or SID against the audit record's targets[].dn /
    targets[].sid. Dry-run records (whatIf=true) and failure records are excluded.
    All audit-*.jsonl files in the audit directory are searched with no arbitrary
    lookback cutoff.
#>

Set-StrictMode -Version Latest

function Get-AdmanOffboardingState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity
    )

    $resolved = Resolve-AdmanTarget -Targets @($Identity) | Select-Object -First 1
    if ($null -eq $resolved) {
        throw "Identity '$Identity' could not be resolved to a single user."
    }

    $userDn = [string]$resolved.DistinguishedName
    $userSid = $null
    if ($resolved.PSObject.Properties['objectSid'] -and $null -ne $resolved.objectSid) {
        if ($resolved.objectSid -is [System.Security.Principal.SecurityIdentifier]) {
            $userSid = $resolved.objectSid.Value
        } else {
            $userSid = [string]$resolved.objectSid
        }
    }

    $auditDir = $script:Config.AuditDir
    $candidates = [System.Collections.Generic.List[object]]::new()

    $auditFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    if (Test-Path -LiteralPath $auditDir) {
        foreach ($file in (Get-ChildItem -LiteralPath $auditDir -Filter 'audit-*.jsonl' -File -ErrorAction Stop)) {
            $auditFiles.Add($file)
        }
        # D-05 / FLOW-03: rotated records live under archive\YYYYMM\; search them too.
        $archiveDir = Join-Path $auditDir 'archive'
        if (Test-Path -LiteralPath $archiveDir) {
            foreach ($file in (Get-ChildItem -LiteralPath $archiveDir -Filter 'audit-*.jsonl' -File -Recurse -ErrorAction Stop)) {
                $auditFiles.Add($file)
            }
        }
    }

    foreach ($file in $auditFiles) {
        # CR-02: verify audit file integrity before consuming any records from it.
        # A tampered audit file must not drive a restore.
        $integrity = Get-AdmanAuditIntegrity -Path $file.FullName
        if (-not $integrity.Valid) {
            throw "Audit integrity check failed for '$($file.FullName)': $($integrity.Reason)"
        }

        foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction Stop)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $rec = $line | ConvertFrom-Json -ErrorAction Stop
                if ($rec.what -ne 'Start-AdmanUserOffboarding' -or
                    $rec.result -ne 'Success' -or
                    $rec.whatIf -eq $true) {
                    continue
                }
                if (-not $rec.tsUtc) {
                    Write-Warning "Skipping offboarding audit record without tsUtc in '$($file.FullName)'."
                    continue
                }
                foreach ($t in @($rec.targets)) {
                    if ($null -eq $t) { continue }
                    $dnMatch = $t.PSObject.Properties['dn'] -and $t.dn -and $t.dn -eq $userDn
                    $sidMatch = $t.PSObject.Properties['sid'] -and $t.sid -and $t.sid -eq $userSid
                    if ($dnMatch -or $sidMatch) {
                        $candidates.Add($rec)
                        break
                    }
                }
            } catch {
                Write-Warning "Skipping corrupt offboarding audit line in '$($file.FullName)': $_"
                continue
            }
        }
    }

    if ($candidates.Count -eq 0) { return $null }

    $latest = $candidates | Sort-Object -Property { [datetime]$_.tsUtc } -Descending | Select-Object -First 1
    return [pscustomobject]@{
        OriginalOU = $latest.originalOU
        Groups     = if ($null -ne $latest.groups) { @($latest.groups) } else { @() }
    }
}
