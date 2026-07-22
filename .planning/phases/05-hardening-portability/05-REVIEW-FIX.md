---
phase: 05-hardening-portability
fixed_at: 2026-07-22T07:15:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-22T07:15:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: XSS / HTML injection via unescaped `-Title` in `Export-AdmanReportHtml`

**Files modified:** `Public/Export-AdmanReportHtml.ps1`, `tests/Render.Tests.ps1`
**Commit:** e798c18
**Applied fix:** Added `$safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)` in the `end` block and replaced all raw `$Title` interpolations in the embedded CSS `<title>`, the empty-result raw HTML strings, and the properties-only empty-result branch with `$safeTitle`. Added a unit test that injects a `<script>` tag via `-Title` and asserts it is encoded.

### CR-02: `Restore-AdmanQuarantinedUser` trusts tamperable audit records

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`, `tests/Workflow.Restore.Tests.ps1`, `tests/Workflow.OffboardingState.Tests.ps1`
**Commit:** 3676bd1
**Applied fix:** `Get-AdmanOffboardingState` now calls `Get-AdmanAuditIntegrity -Path $file.FullName` before reading any line from an audit file and throws with the integrity reason if `Valid` is `$false`. Updated existing restore tests to emit valid hash-chain records and added a new test proving a tampered file causes a clear throw.

### WR-01: `Set-AdmanUserPassword` help description contradicts implementation

**Files modified:** `Public/Set-AdmanUserPassword.ps1`
**Commit:** 85ee38d
**Applied fix:** Rewrote the `.DESCRIPTION` to describe the actual three gate invocations (`Set-ADAccountPassword`, `Set-ADUser`, optional `Unlock-ADAccount`), each with its own PENDING/OUTCOME audit pair and confirmation, and the failure aggregation behavior.

### WR-02: `Get-AdmanAuditIntegrity` reports missing files as valid

**Files modified:** `Private/Audit/Rotation.ps1`, `tests/Audit.Integrity.Tests.ps1`
**Commit:** 90b2189
**Applied fix:** Changed the missing-file return value from `Valid = $true` to `Valid = $false`. Added a unit test asserting a missing audit file is reported as invalid.

### WR-03: Redundant `$allowed.Count` guard in `Invoke-AdmanBulkAction`

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** 5898239
**Applied fix:** Removed the redundant `-and $allowed.Count -gt 0` clause inside the already-guaranteed `$allowed.Count -gt 0` block.

### WR-04: `Initialize-AdmanConfig` reads `adman.defaults.json` repeatedly

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** 1c2fbbf
**Applied fix:** Loaded `adman.defaults.json` once near the top of `Initialize-AdmanConfig` into `$defaults` and reused it for the fresh-file bootstrap, timeout merge, domain/templates merge, audit merge, and deny-list seed steps.

### WR-05: `Get-AdmanInventoryReport` probes remote query even when transport is `Skipped`

**Files modified:** `Public/Get-AdmanInventoryReport.ps1`, `tests/Report.Inventory.Tests.ps1`
**Commit:** 5619b94
**Applied fix:** Changed the remote-query branch from `else { Invoke-AdmanRemoteQuery ... }` to `elseif ($transport -ne 'Skipped') { ... }` so skipped hosts never trigger a wasted remote query. Updated the skipped-transport test to assert `Invoke-AdmanRemoteQuery` is invoked zero times.

### WR-06: `Start-AdmanUserOnboarding` does not validate `NamePattern` format

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`, `tests/Workflow.Onboarding.Tests.ps1`
**Commit:** 7308386
**Applied fix:** Added a two-argument format-string trial (`$template.NamePattern -f 'First', 'Last'`) during onboarding template validation, throwing a clear message before preflight checks run. Added a unit test for an invalid `{2}` pattern.

## Skipped Issues

None — all findings were applied.

---

_Fixed: 2026-07-22T07:15:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
