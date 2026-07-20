---
phase: 04
fixed_at: 2026-07-20T16:55:00Z
review_path: .planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-07-20T16:55:00Z
**Source review:** `.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 10 (2 Critical, 8 Warning)
- Fixed: 10
- Skipped: 0

All critical and warning findings from the Phase 04 review were fixed. Info findings `IN-01` and `IN-02` were out of scope for this fix pass (`fix_scope: critical_warning`) and were not modified.

**Verification:**
- Every edited file was parsed with the PowerShell AST parser before committing.
- Targeted Pester tests for the changed areas (Bulk, Workflow, Config) passed.
- Full unit suite: 681 passed, 3 pre-existing failures in `Credential.Dpapi.Tests.ps1` caused by the non-interactive PowerShell execution environment (prompting blocked), unrelated to these fixes.

## Fixed Issues

### CR-01: Offboarding crashes when the user has no `memberOf` property

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `9198fb3`
**Applied fix:** Filtered null/empty entries out of `$user.memberOf` before iterating, so a missing or empty group list no longer creates a `$null` group-removal attempt.

### CR-02: Restore fails for offboarded users with no removable groups

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`, `Public/Restore-AdmanQuarantinedUser.ps1`
**Commit:** `6f2f300`
**Applied fix:** `Get-AdmanOffboardingState` now returns an empty array when the audit record omits `groups`, and `Restore-AdmanQuarantinedUser` filters null/empty group values before re-adding.

### WR-01: Parent-DN extraction uses a regex that breaks on escaped commas

**Files modified:** `Private/Utility/ConvertTo-AdmanParentDn.ps1` (new), `Public/Start-AdmanUserOffboarding.ps1`, `Public/Restore-AdmanQuarantinedUser.ps1`, `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `6aa38f3`, `2287eab`
**Applied fix:** Added a shared DN-aware helper `ConvertTo-AdmanParentDn` that splits on the first unescaped comma using a `Regex` instance split, then replaced the brittle `-replace '^[^,]+,'` pattern in the three affected files. The follow-up commit corrected the split count overload so the full parent DN is returned.

### WR-02: `$script:AuditDegraded` is never initialized

**Files modified:** `adman.psm1`
**Commit:** `23242eb`
**Applied fix:** Added `$script:AuditDegraded = $false` alongside the other module-level slots.

### WR-03: `Get-AdmanOffboardingState` aborts on corrupt audit records

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`
**Commit:** `5b98340`
**Applied fix:** Wrapped the entire per-record evaluation in a `try/catch`, skipping malformed lines with a warning. Missing `tsUtc` records are also skipped, and target matching uses defensive property checks to survive `targets = $null`.

### WR-04: `Invoke-AdmanBulkAction` ignores per-row `TargetPath` in CSV Move jobs

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `009a775`
**Applied fix:** Move validation now accepts `-TargetPath` as a whole-job default or requires a `TargetPath` on every CSV row. The per-item skip check and `Invoke-AdmanMutation` call use the row-level path when present, falling back to the outer parameter.

### WR-05: `Write-AdmanAudit` mixes `$WhatIf` parameter and `$WhatIfPreference`

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `fecaf7f`
**Applied fix:** The persisted `whatIf` field now uses `[bool]$WhatIfPreference` to match the actual write behavior.

### WR-06: Redundant/confusing SID check against the DN protected-group list

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `f3b64d4`
**Applied fix:** Removed the dead branch that checked a resolved group SID against `$script:ProtectedGroupDns`; the DN check against the same list still follows.

### WR-07: `Import-AdmanBulkCsv` returns a phantom row for header-only files

**Files modified:** `Private/Bulk/Import-AdmanBulkCsv.ps1`
**Commit:** `cc9e7f7`, `ae7b127`
**Applied fix:** After `Import-Csv`, a single row whose properties are all empty/whitespace is treated as header-only and an empty array is returned. The follow-up commit wrapped `$rows` in `@()` so the scalar one-row case works under `Set-StrictMode -Version Latest`.

### WR-08: `Initialize-AdmanConfig` saves an unvalidated intermediate config

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `9675537`
**Applied fix:** Phase 4 additive migrations and the deny-list seed are now applied in memory only; the single `Save-AdmanConfig` call happens after `Test-AdmanConfigValid` succeeds.

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-07-20T16:55:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
