#Requires -Version 5.1
<#
.SYNOPSIS
    Write-AdmanAudit - the ONLY audit writer: synchronous, write-ahead, fail-closed (SAFE-03/04).

.DESCRIPTION
    Appends ONE JSON-lines record to the daily-rotated audit file under a named mutex, flushing
    durably before returning. This is the single audit sink (D-01): no audit record is ever routed
    through any asynchronous logging framework (async breaks fail-closed). Diagnostics elsewhere
    may use a logging framework; the audit record goes ONLY through this function.

    Write-ahead reservation (SAFE-04): the 00-04 gate writes a PENDING record BEFORE the mutation.
    If that PENDING write fails for ANY reason (path missing + auto-create failed, ACL denial,
    disk full, sharing violation, unreachable path) this function THROWS before AD is touched -
    that throw IS the refusal. An OUTCOME-write failure (after a successful mutation) does NOT roll
    back AD; it escalates to the Windows Event Log (best-effort), a loud UI warning, and
    $script:AuditDegraded=$true, because AD object-state rollback is unreliable (D-03).

    Schema (D-03, fixed field set, no sensitive fields ever): tsUtc, who, userSid, what, scope,
    target, targets[{dn,sid,objectClass}], count, whatIf, result, reason, correlationId, host,
    psEdition, moduleVersion. Never place a sensitive authentication value in any field.

    All mutex / file / event-log operations go through the private seams in AdmanAuditIO.ps1
    (New-AdmanAuditMutex / Open-AdmanAuditStream / Write-AdmanEventLog) so the fail-closed behavior
    is provable under test without mocking raw .NET statics.
#>

Set-StrictMode -Version Latest

function Write-AdmanAudit {
    [CmdletBinding()]
    param(
        [string]$CorrelationId,
        [string]$Verb,
        $Targets,
        [Parameter(Mandatory)]
        [ValidateSet('PENDING', 'Success', 'Failure', 'Refused', 'Cancelled')]
        [string]$Result,
        [string]$Reason,
        [switch]$WhatIf
    )

    # Acquire the named mutex via the seam (the cross-writer serialization point).
    $mutex = New-AdmanAuditMutex
    [void]$mutex.WaitOne()
    try {
        $path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
        if (-not (Test-Path -LiteralPath $script:Config.AuditDir)) {
            $null = New-Item -ItemType Directory -Path $script:Config.AuditDir -Force -ErrorAction Stop
        }

        # Normalize targets to DN list + per-target detail (dn / sid / objectClass).
        $targetObjs = @($Targets)
        $targetDns = $targetObjs | ForEach-Object { $_.DistinguishedName }
        $targetDetail = @($targetObjs | ForEach-Object {
            @{
                dn          = $_.DistinguishedName
                sid         = ($_.objectSid.Value)
                objectClass = ($_.objectClass -join ',')
            }
        })

        $rec = [ordered]@{
            tsUtc         = (Get-Date).ToUniversalTime().ToString('o')
            who           = "$env:USERDOMAIN\$env:USERNAME"
            userSid       = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            what          = $Verb
            scope         = ($script:Config.ManagedOUs -join '|')
            target        = ($targetDns -join '|')
            targets       = $targetDetail
            count         = $targetObjs.Count
            whatIf        = [bool]$WhatIf
            result        = $Result
            reason        = $Reason
            correlationId = $CorrelationId
            host          = $env:COMPUTERNAME
            psEdition     = $PSEdition
            moduleVersion = (Get-Module adman).Version.ToString()
        } | ConvertTo-Json -Compress -Depth 5

        # Open via the seam (Append / Write / Read-share); write UTF8 bytes; flush durably.
        $fs = Open-AdmanAuditStream -Path $path
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($rec + "`n")
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush($true)   # $true = flush to disk (not just the OS cache)
        } finally {
            $fs.Dispose()
        }
    } catch {
        if ($Result -eq 'PENDING') {
            # SAFE-04: the pre-write reservation failed -> REFUSE the destructive action. This throw
            # happens BEFORE the gate's AD write (the 00-04 gate test proves the write never runs).
            throw "AUDIT FAIL-CLOSED: cannot write audit record ($($_.Exception.Message)); refusing $Verb."
        }
        # OUTCOME failure after a successful mutation -> escalate, do NOT roll back AD (D-03).
        Write-AdmanEventLog -EventId 9001 -EntryType Error `
            -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
        Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId - see Event Log."
        $script:AuditDegraded = $true
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
