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
        $Target,
        [Parameter(Mandatory)]
        [ValidateSet('PENDING', 'Success', 'Failure', 'Refused', 'Cancelled')]
        [string]$Result,
        [string]$Reason,
        [string]$Group,
        [switch]$WhatIf
    )

    # Acquire the named mutex via the seam (the cross-writer serialization point).
    # CR-04 fix: New-AdmanAuditMutex may itself throw (returning $null); guard the
    # WaitOne/ReleaseMutex/Dispose calls against $null so a mutex-acquisition failure
    # surfaces the original error rather than a secondary NullReferenceException.
    $mutex = New-AdmanAuditMutex
    if ($null -eq $mutex) {
        throw "AUDIT FAIL-CLOSED: cannot acquire audit mutex; refusing $Verb."
    }
    [void]$mutex.WaitOne()
    try {
        $path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
        if (-not (Test-Path -LiteralPath $script:Config.AuditDir)) {
            $null = New-Item -ItemType Directory -Path $script:Config.AuditDir -Force -ErrorAction Stop
        }

        # Normalize targets. Accept either -Targets (array) or -Target (single). Local
        # targets carry Machine+Name+SID (no DistinguishedName) and emit "MACHINE\username"
        # plus a @{machine,name,sid} detail shape; AD targets carry DistinguishedName and
        # emit the DN plus a @{dn,sid,objectClass} detail shape. The optional preDeleteState
        # field is emitted on local targets when the resolved object carries PreDeleteState
        # (D-03).
        $targetObjs = @()
        if ($PSBoundParameters.ContainsKey('Targets') -and $null -ne $Targets) { $targetObjs = @($Targets) }
        elseif ($PSBoundParameters.ContainsKey('Target') -and $null -ne $Target) { $targetObjs = @($Target) }

        $targetStrings = @()
        $targetDetail = @()
        foreach ($t in $targetObjs) {
            if ($t.PSObject.Properties['DistinguishedName'] -and $t.DistinguishedName) {
                # AD target shape.
                $targetStrings += $t.DistinguishedName
                $targetDetail += @{
                    dn          = $t.DistinguishedName
                    sid         = ($t.objectSid.Value)
                    objectClass = ($t.objectClass -join ',')
                }
            } elseif ($t.PSObject.Properties['Machine'] -and $t.PSObject.Properties['Name']) {
                # Local target shape.
                $targetStrings += ("{0}\{1}" -f $t.Machine, $t.Name)
                $detail = @{
                    machine = $t.Machine
                    name    = $t.Name
                    sid     = if ($null -ne $t.SID) { ([System.Security.Principal.SecurityIdentifier]$t.SID).Value } else { $null }
                }
                if ($t.PSObject.Properties['PreDeleteState'] -and $null -ne $t.PreDeleteState) {
                    $detail['preDeleteState'] = $t.PreDeleteState
                }
                $targetDetail += $detail
            } else {
                # Fallback: string-form target.
                $targetStrings += ([string]$t)
                $targetDetail += @{ value = ([string]$t) }
            }
        }

        $rec = [ordered]@{
            tsUtc         = (Get-Date).ToUniversalTime().ToString('o')
            who           = "$env:USERDOMAIN\$env:USERNAME"
            userSid       = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            what          = $Verb
            scope         = ($script:Config.ManagedOUs -join '|')
            target        = ($targetStrings -join '|')
            targets       = $targetDetail
            count         = $targetObjs.Count
            whatIf        = [bool]$WhatIf
            result        = $Result
            reason        = $Reason
            correlationId = $CorrelationId
            host          = $env:COMPUTERNAME
            psEdition     = $PSEdition
            moduleVersion = (Get-Module adman).Version.ToString()
        }
        # D-04: emit the group field ONLY when -Group is supplied (preserves the exact-key-set
        # Test 1 invariant for non-group records).
        if (-not [string]::IsNullOrEmpty($Group)) {
            $rec['group'] = $Group
        }
        $rec = $rec | ConvertTo-Json -Compress -Depth 5

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
        # CR-04 fix: capture the original error BEFORE reading .Exception.Message — under
        # StrictMode, accessing properties on a malformed $_ can itself throw, masking the
        # original audit failure. Pass the original exception as InnerException so the
        # diagnosis trail is preserved.
        $originalError = $_
        if ($Result -eq 'PENDING') {
            # SAFE-04: the pre-write reservation failed -> REFUSE the destructive action. This throw
            # happens BEFORE the gate's AD write (the 00-04 gate test proves the write never runs).
            $msg = 'AUDIT FAIL-CLOSED: cannot write audit record'
            $inner = $null
            if ($null -ne $originalError -and
                $originalError.PSObject.Properties['Exception'] -and
                $null -ne $originalError.Exception) {
                $inner = $originalError.Exception
                if ($inner.PSObject.Properties['Message'] -and -not [string]::IsNullOrEmpty($inner.Message)) {
                    $msg = "$msg ($($inner.Message))"
                }
            }
            $msg = "$msg; refusing $Verb."
            if ($null -ne $inner) {
                throw [System.InvalidOperationException]::new($msg, $inner)
            }
            throw $msg
        }
        # OUTCOME failure after a successful mutation -> escalate, do NOT roll back AD (D-03).
        Write-AdmanEventLog -EventId 9001 -EntryType Error `
            -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
        Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId - see Event Log."
        $script:AuditDegraded = $true
    } finally {
        # CR-04 fix: guard against $null mutex (New-AdmanAuditMutex threw above) and
        # tolerate ReleaseMutex/Dispose failures so a secondary exception in finally
        # does not mask the original audit error.
        if ($null -ne $mutex) {
            try { $mutex.ReleaseMutex() } catch { }
            try { $mutex.Dispose() } catch { }
        }
    }
}
