---
phase: 05-hardening-portability
reviewed: 2026-07-22T22:00:00Z
depth: standard
files_reviewed: 53
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
  - Public/New-AdmanLocalUser.ps1
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
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 05-hardening-portability: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 53
**Status:** issues_found

## Summary

Re-reviewed the Phase 5 hardening/portability surface after the fix commits that addressed the prior CR-01 through WR-06 findings. All previously reported Critical issues and the six Warnings are verified fixed in the current working tree:

* `Public/New-AdmanLocalUser.ps1` now forces `Prompt` when an explicit password is supplied and blocks generated-password mutations before the gate when a transcript is active.
* `Public/Config/Set-AdmanConfig.ps1` and `Public/Config/Import-AdmanConfig.ps1` correctly count non-null managed-OU entries.
* `Private/Audit/Rotation.ps1` creates archive directories and marker files only inside `ShouldProcess`.
* `Public/Get-AdmanStaleReport.ps1` computes the cutoff in UTC.
* `build/Sign-AdmanModule.ps1` nests `Join-Path` for Windows PowerShell 5.1 compatibility.
* `Public/Start-AdmanUserOffboarding.ps1` fails closed when protected-identity caches are uninitialized.

Four new or remaining issues were found: two Warnings and two Info items. No new Critical/Blocker issues remain.

## Warnings

### WR-01: `Write-AdmanAudit` crashes on module-version lookup when the module is not loaded as `adman`

**File:** `Private/Audit/Write-AdmanAudit.ps1:153`
**Classification:** WARNING
**Issue:** The audit record builds `moduleVersion` with `(Get-Module adman).Version.ToString()`. If the module is dot-sourced, loaded under a different name, or invoked in a test harness where it is not imported as `adman`, `Get-Module adman` returns `$null` and `.ToString()` throws. A PENDING-write failure is correctly fail-closed (the mutation is refused), but the refusal reason is a confusing "You cannot call a method on a null-valued expression" rather than the intended audit error. An OUTCOME-write failure degrades the audit sink and sets `$script:AuditDegraded = $true`. The lookup also hard-codes the module name, which is a hidden coupling.

**Fix:** Resolve the version from the function's own module context, and degrade gracefully to `'unknown'` when no module context exists.
```powershell
$module = $ExecutionContext.SessionState.Module
$moduleVersion = if ($module) { $module.Version.ToString() } else { 'unknown' }
$rec = [ordered]@{
    # ...
    moduleVersion = $moduleVersion
    # ...
}
```

### WR-02: `Set-AdmanLocalUser` rejects direct password resets that sibling verbs accept

**File:** `Public/Set-AdmanLocalUser.ps1:145-148`
**Classification:** WARNING
**Issue:** The `Reset` parameter set throws `"Parameter set cannot be resolved: supply -Password, -Enable, or -Disable."` when neither `-Password` nor `-PasswordSource` is supplied. This prevents direct callers from relying on the configured `security.passwordSource` fallback, which works in `New-AdmanLocalUser`, `New-AdmanUser`, and `Set-AdmanUserPassword`. The inline help example on line 68 (`Set-AdmanLocalUser -Name 'luser-fake' # password reset (D-05 sourced)`) is therefore misleading and would fail at runtime. The existing source-resolution fallback on lines 152-160 is unreachable because of this guard.

**Fix:** Remove the hard throw and let the existing per-call source resolution fall back to `$script:Config.security.passwordSource`, matching the sibling verbs.
```powershell
# Remove this block:
if (-not $passwordSupplied -and -not $passwordSourceSupplied) {
    throw 'Parameter set cannot be resolved: supply -Password, -Enable, or -Disable.'
}
```
Then ensure the source-resolution fallback runs even when neither value is supplied (it already does). If a silent no-op is the concern, note that the fallback either generates a password or prompts; it never performs a no-op.

## Info

### IN-01: Redundant post-mutation transcript guards in password verbs

**Files:**
- `Public/New-AdmanUser.ps1:228-230`
- `Public/Set-AdmanUserPassword.ps1:254-256`
- `Public/Set-AdmanLocalUser.ps1:228-233`
**Classification:** INFO
**Issue:** Each of these verbs now has a pre-mutation transcript guard that throws before the account is created or its password is changed. The post-mutation guard inside the display-once block checks the same condition again, but it can never fire because the pre-mutation guard already refused the operation. These paths are dead code and add maintenance noise.

**Fix:** Remove the inner `Transcripts.Count` check from the display-once block in each verb; rely solely on the pre-mutation guard.

### IN-02: `@()` array builders remain in hot-path writers

**Files:**
- `Private/Audit/Write-AdmanAudit.ps1:90-92, 94-95, 114-130`
- `Public/Export-AdmanReportCsv.ps1:81-92`
**Classification:** INFO
**Issue:** The audit writer and CSV renderer still build collections with `@()` and `+=`, which reallocates on every addition. While the collections are small in normal use, the pattern is a maintainability/performance smell in code paths that are explicitly designed to be hot or streaming.

**Fix:** Replace `@()` builders with `New-Object System.Collections.Generic.List[object]` and `.Add()`, as already done elsewhere in the codebase (e.g., `Invoke-AdmanMutation`).

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
