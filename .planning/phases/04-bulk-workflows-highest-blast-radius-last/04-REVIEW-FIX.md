---
phase: 04
fixed_at: 2026-07-20T11:10:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 7
skipped: 1
status: partial
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-07-20T11:10:00Z
**Source review:** `C:/Users/nhdinh/dev/adman/.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 7
- Skipped: 1

## Fixed Issues

### CR-01: Start-AdmanUserOnboarding rejects a valid empty `BaselineGroups` array

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`
**Commit:** `348757e`
**Applied fix:** Replaced whitespace-only validation with type-aware checks: `BaselineGroups` is validated for presence (`$null` check) while `ParentOuDn` and `NamePattern` keep the whitespace check. This allows the default empty array `@()` to pass.

### WR-01: Write-AdmanAudit does not null-check the audit file stream

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `246896e`
**Applied fix:** Added an explicit `$null` guard on the stream returned by `Open-AdmanAuditStream`; throws `AUDIT FAIL-CLOSED` before any write/flush/dispose so a `$null` seam does not mask the real open failure.

### WR-03: Bulk group-operation confirmation only shows the first group

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `81c47e3`
**Applied fix:** Built a distinct list of resolved group DNs and shows either the single DN or `"N distinct groups"` in the confirmation prompt instead of only `$allowed[0]`.

### WR-04: Offboarding protected-group fallback compares DN against a list that may contain SIDs

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `e568275`
**Applied fix:** Extended the catch fallback to compare the unresolved `memberOf` token against `ProtectedGroupDns`, `ProtectedSIDs`, and `DenyRids` (for SID-like tokens), and added a last-ditch `Get-ADGroup` lookup for DN-like tokens to translate them to a SID before comparing. **Status: fixed, requires human verification** — this is a logic change in the protected-group path.

### WR-05: `AuditDegraded` flag is not set if event-log escalation itself throws

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `5969971`
**Applied fix:** Moved `$script:AuditDegraded = $true` before the best-effort `Write-AdmanEventLog` call so the degraded state is recorded even if event-log escalation fails.

### WR-06: Default config store path is relative to the process working directory

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `644535b`
**Applied fix:** Defaulted `$script:StorePath` to `Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.store'` so the `.store` directory is anchored to the module root regardless of the invocation working directory.

### WR-07: CSV header parser does not honor quoted commas

**Files modified:** `Private/Bulk/Import-AdmanBulkCsv.ps1`
**Commit:** `5a5e67a`
**Applied fix:** Replaced the naive `$headerLine.Split(',')` with a regex CSV splitter that respects double-quoted fields and escaped quotes, keeping the manual header checks in sync with `Import-Csv`.

## Skipped Issues

### WR-02: Computer inventory report properties are built from user properties

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:82-83`
**Reason:** Code context differs from review. The current source already builds `$computerReportProperties` from `$computerProperties` (line 83), not from `$userProperties`, so the reported issue does not apply to the checked-in code.
**Original issue:** `$computerReportProperties` was reported as constructed from `$userProperties`, omitting computer-specific columns.

---

_Fixed: 2026-07-20T11:10:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
