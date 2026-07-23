---
phase: 05
reviewed: 2026-07-23T17:00:00Z
depth: standard
files_reviewed: 56
files_reviewed_list:
  - .github/workflows/ci.yml
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Add-AdmanGroupMember.ps1
  - Public/Add-AdmanLocalGroupMember.ps1
  - Public/Config/Export-AdmanConfig.ps1
  - Public/Config/Get-AdmanConfig.ps1
  - Public/Config/Import-AdmanConfig.ps1
  - Public/Config/Set-AdmanConfig.ps1
  - Public/Disable-AdmanComputer.ps1
  - Public/Disable-AdmanUser.ps1
  - Public/Enable-AdmanComputer.ps1
  - Public/Enable-AdmanUser.ps1
  - Public/Export-AdmanReportCsv.ps1
  - Public/Export-AdmanReportHtml.ps1
  - Public/Find-AdmanComputer.ps1
  - Public/Find-AdmanUser.ps1
  - Public/Format-AdmanReport.ps1
  - Public/Get-AdmanAccountStateReport.ps1
  - Public/Get-AdmanInventoryReport.ps1
  - Public/Get-AdmanRecoveryPostureReport.ps1
  - Public/Get-AdmanStaleReport.ps1
  - Public/Initialize-Adman.ps1
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Move-AdmanComputer.ps1
  - Public/Move-AdmanUser.ps1
  - Public/New-AdmanUser.ps1
  - Public/Remove-AdmanGroupMember.ps1
  - Public/Remove-AdmanLocalGroupMember.ps1
  - Public/Remove-AdmanLocalUser.ps1
  - Public/Reset-AdmanComputerAccount.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Start-Adman.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - Public/Test-AdmanCapability.ps1
  - Public/Unlock-AdmanUser.ps1
  - build/Sign-AdmanModule.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - docs/RECOVERY-RUNBOOK.md
  - docs/USAGE.md
  - tests/Audit.EventLog.Tests.ps1
  - tests/Audit.FailClosed.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Schema.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Docs.Coverage.Tests.ps1
  - tests/Help.Coverage.Tests.ps1
  - tests/PesterConfiguration.psd1
  - tests/Workflow.OffboardingState.Tests.ps1
findings:
  critical: 2
  warning: 6
  info: 3
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T17:00:00Z
**Depth:** standard
**Files Reviewed:** 56
**Status:** issues_found

## Summary

Reviewed the Phase 05 hardening/portability source set: CI workflow, audit writer/rotation/integrity, config loader, offboarding state reader, all Public verbs, build signing script, config/schema JSON, operator docs, and unit tests. The module shows strong fail-closed discipline around audit, config validation, and scope checks, and the tests mock the right seams. The remaining issues are concentrated in three areas:

1. **Audit fail-closed edge cases** - the audit writer's catch block does not cover mutex-acquisition failures, and SHA256 instances are leaked.
2. **Operational correctness** - stale-report date comparison ignores timezone kind, and the signing script omits timestamping.
3. **Project-convention drift** - `Write-Host` is used outside the TUI module, config validation lacks type guards, and operator docs contain misleading examples.

## Critical Issues

### CR-01: Audit writer does not catch mutex-acquisition failures

**File:** `Private/Audit/Write-AdmanAudit.ps1:55-76` and `206-229`
**Issue:** The centralized `catch` block that implements the SAFE-04 fail-closed contract starts at line 77, *after* `New-AdmanAuditMutex` is called at line 59. The function's own comment says the mutex seam may throw, but if it does, the exception propagates out of `Write-AdmanAudit` without being mapped to `AUDIT FAIL-CLOSED` (PENDING) or to Event Log escalation / `$script:AuditDegraded = $true` (OUTCOME). The `$null -eq $mutex` guard only protects the `$null` return path, not the throw path. The mutation is still blocked, but the refusal/escalation contract is broken and the caller sees a raw seam error instead of a controlled audit failure.
**Fix:** Enclose the mutex acquisition inside the same `try` block so the existing catch/finally logic applies.

```powershell
$mutex = $null
try {
    $mutex = New-AdmanAuditMutex
    if ($null -eq $mutex) {
        throw "AUDIT FAIL-CLOSED: cannot acquire audit mutex; refusing $Verb."
    }
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne([timespan]::FromSeconds(30))
    } catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) { ... }
    # existing record-building logic
} catch { ... }
finally {
    if ($null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
        try { $mutex.Dispose() } catch { }
    }
}
```

### CR-02: Stale-report grace-window comparison mixes UTC and local-kind DateTime values

**File:** `Public/Get-AdmanStaleReport.ps1:62, 82-86`
**Issue:** `$staleCutoff` is built with `(Get-Date).ToUniversalTime()` (UTC), but `$created` comes directly from `$obj.whenCreated` and is compared without normalization. `DateTime` comparison ignores `Kind`, so the server's timezone offset can push accounts incorrectly in or out of the "never logged on" bucket near the grace-window boundary. This produces incorrect stale/never-logged-on classification, which drives offboarding and cleanup decisions.
**Fix:** Convert the creation time to UTC before comparing.

```powershell
$created = $null
if ($obj.PSObject.Properties['whenCreated']) { $created = $obj.whenCreated }
if ($null -ne $created -and $created -is [datetime] -and $created.ToUniversalTime() -lt $staleCutoff) {
    $bucket = 'NeverLoggedOn'
}
```

## Warnings

### WR-01: Code-signing build script does not timestamp signatures

**File:** `build/Sign-AdmanModule.ps1:89`
**Issue:** `Set-AuthenticodeSignature` is invoked without a `-TimestampServer`. Once the signing certificate expires, the signature becomes invalid, causing `AllSigned` execution policy to reject the module even though the certificate was trusted at signing time. This undermines the trust-anchor rotation documented in `docs/RECOVERY-RUNBOOK.md`.
**Fix:** Add a timestamp server. Use an internal timestamp server if available; otherwise a public RFC 3161 endpoint.

```powershell
$result = Set-AuthenticodeSignature `
    -FilePath $file.FullName `
    -Certificate $cert `
    -HashAlgorithm SHA256 `
    -TimestampServer 'http://timestamp.digicert.com'
```

### WR-02: `Write-Host` used outside the TUI-rendering module

**File:** `Public/Start-AdmanUserOffboarding.ps1:44-45, 187-190`
**Issue:** The function suppresses `PSAvoidUsingWriteHost` and uses `Write-Host` to emit the manual cleanup checklist. The project convention explicitly restricts `Write-Host` suppression to the TUI-rendering module (`Start-Adman`). A workflow verb should either return structured output or use `Write-PSFMessage -Level Host` (the pattern already used by `Reset-AdmanComputerAccount`).
**Fix:** Replace `Write-Host` with `Write-PSFMessage -Level Host` and remove the `SuppressMessageAttribute`.

```powershell
Write-PSFMessage -Level Host -Message "Offboarding complete for '$Identity'. Manual cleanup checklist:"
Write-PSFMessage -Level Host -Message "  - Mailbox: archive or convert to shared mailbox (manual only)"
```

### WR-03: SHA256 hash instances are not disposed

**File:** `Private/Audit/Write-AdmanAudit.ps1:188-190` and `Private/Audit/Rotation.ps1:171-174`
**Issue:** Both files create a `SHA256` instance with `[System.Security.Cryptography.SHA256]::Create()` and never call `Dispose()`. These objects implement `IDisposable` and hold unmanaged crypto provider handles; leaking them under high audit volume can exhaust handles and degrade performance.
**Fix:** Dispose the instance explicitly.

```powershell
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalJson))
} finally {
    $sha.Dispose()
}
$rec['hash'] = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
```

### WR-04: Config validator casts integer keys without type guards

**File:** `Private/Config/Initialize-AdmanConfig.ps1:156-183`
**Issue:** `Test-AdmanConfigValid` casts `safety.bulkConfirmThreshold`, `transport.timeouts.perHostProbeCap`, and `transport.timeouts.totalInventoryRemoteCap` directly with `[int]`. If the config contains a non-numeric string, the cast throws a generic `Cannot convert` error instead of the intended validation message. Additionally, `bulk.maxCount` is required but never validated as `>= 1`.
**Fix:** Add explicit type guards before the integer casts, mirroring the pattern already used for `audit.retentionDays` and `security.passwordGeneration.length`.

```powershell
$bt = $Config.safety.bulkConfirmThreshold
if ($bt -isnot [int] -and $bt -isnot [long] -and -not ($bt -is [string] -and $bt -match '^\d+$')) {
    throw "Config validation failed: 'safety.bulkConfirmThreshold' must be an integer >= 1."
}
if ([int]$bt -lt 1) { throw "Config validation failed: 'safety.bulkConfirmThreshold' must be >= 1." }
```

### WR-05: Audit rotation can move a file before its archive directory is created

**File:** `Private/Audit/Rotation.ps1:236-246`
**Issue:** Directory/marker creation and the file move are guarded by two independent `ShouldProcess` prompts. If a user confirms the move but declines the directory creation, `Move-Item` fails because `$archiveDir` does not exist. Automated callers typically use `-Confirm:$false`, but the interactive contract is still wrong.
**Fix:** Create the archive directory idempotently before the move confirmation, or fold both actions under a single `ShouldProcess`.

```powershell
if (-not (Test-Path -LiteralPath $archiveDir)) {
    $null = New-Item -ItemType Directory -Path $archiveDir -Force -ErrorAction Stop
}
if ($PSCmdlet.ShouldProcess($file.FullName, 'Move to archive')) {
    Move-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
}
```

### WR-06: Usage docs contain out-of-scope move examples

**File:** `docs/USAGE.md:289, 319`
**Issue:** The `Move-AdmanUser` and `Move-AdmanComputer` examples use destination OUs such as `OU=Disabled,DC=contoso,DC=local` and `OU=Workstations,DC=contoso,DC=local`. The shipped default managed-OU root is `OU=Managed,DC=contoso,DC=local`, so these examples fail with "TargetPath is outside managed OU scope" if copied verbatim.
**Fix:** Update the examples to use OUs under the managed root, e.g. `OU=Disabled,OU=Managed,DC=contoso,DC=local`.

## Info

### IR-01: Usage docs mislabel password parameters as required

**File:** `docs/USAGE.md:227-240, 262-270, 332-340`
**Issue:** The guide marks `AccountPassword`, `NewPassword`, and `Password` as required, but the corresponding function parameters are optional. When omitted, the configured password source (`Generate`/`Prompt`) is used. This contradicts the parameter definitions and may confuse operators.
**Fix:** Change the documentation to indicate these parameters are optional and sourced from config when omitted.

### IR-02: Stale report documented as covering computers as well as users

**File:** `docs/USAGE.md:156-165`
**Issue:** `Get-AdmanStaleReport` is documented as reporting "stale or inactive user and computer accounts", but the implementation only queries `Get-ADUser`. Either the docs or the implementation needs to match.
**Fix:** Update the description to "stale or inactive user accounts", or extend `Get-AdmanStaleReport` to support an `-ObjectType` parameter.

### IR-03: Redundant `$moduleRoot` assignment in config loader

**File:** `Private/Config/Initialize-AdmanConfig.ps1:287, 397`
**Issue:** `$moduleRoot` is computed at line 287 and then recomputed with the same expression at line 397 before path absolutization. The duplicate assignment is harmless but unnecessary.
**Fix:** Remove line 397 and reuse the existing `$moduleRoot` variable.

---

_Reviewed: 2026-07-23T17:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
