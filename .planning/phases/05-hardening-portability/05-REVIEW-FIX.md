---
phase: 05-hardening-portability
fixed_at: 2026-07-22T00:00:00Z
review_path: .planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 14
fixed: 14
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-22T00:00:00Z
**Source review:** `.planning/phases/05-hardening-portability/05-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 14
- Fixed: 14
- Skipped: 0

## Fixed Issues

### BL-01: ConvertTo-AdmanCleanConfig corrupts arrays and can fail-open the scope gate

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `e896bf5`
**Applied fix:** Removed the unary commas in the array branch so cleaned arrays are returned directly instead of wrapped in a one-element array.

### BL-02: Set-AdmanConfig and Import-AdmanConfig do not absolutize AuditDir/ReportDir

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`, `Public/Config/Set-AdmanConfig.ps1`, `Public/Config/Import-AdmanConfig.ps1`
**Commit:** `59b8b8e`
**Applied fix:** Extracted path absolutization into a new `ConvertTo-AdmanAbsolutePath` helper and invoked it for `AuditDir`/`ReportDir` before publishing `$script:Config` in `Set-AdmanConfig` and `Import-AdmanConfig`.

### BL-03: Explicit password combined with `-AccountPasswordSource 'Generate'` is displayed as generated

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** `622c952`
**Applied fix:** Reordered per-call password-source resolution so an explicitly supplied password forces the effective source to `Prompt`, preventing the caller-supplied secret from being displayed as a generated password.

### BL-04: Restore-AdmanQuarantinedUser uses the raw caller identity for offboarding-state lookup

**Files modified:** `Public/Restore-AdmanQuarantinedUser.ps1`
**Commit:** `f4b4715`
**Applied fix:** Changed the `Get-AdmanOffboardingState` call to use the stable `$stableIdentity` already computed from `sAMAccountName` instead of the original caller input.

### BL-05: Start-Adman treats "B" at CSV/HTML path prompt as "Quit"

**Files modified:** `Public/Start-Adman.ps1`
**Commit:** `c814ee9`
**Applied fix:** Replaced `break menuLoop` with `continue` for the CSV and HTML path prompts so `B` returns to the format menu instead of exiting the entire TUI.

### WR-01: Null-result enumeration can pass `$null` into `ConvertTo-AdmanResult`

**Files modified:** `Public/Find-AdmanUser.ps1`, `Public/Find-AdmanComputer.ps1`, `Public/Get-AdmanAccountStateReport.ps1`, `Public/Get-AdmanInventoryReport.ps1`, `Public/Get-AdmanStaleReport.ps1`
**Commit:** `5ec880c`
**Applied fix:** Replaced `@($raw)` enumeration with `$raw | Where-Object { $null -ne $_ }` in each report/search verb and removed the redundant inner null guard in `Get-AdmanAccountStateReport`.

### WR-02: Generated password is displayed (or throws) after the AD/local account already exists

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** `e08174c`
**Applied fix:** Added a pre-mutation transcript guard so that when a generated password would need to be displayed but a transcript is active, the verb throws before mutating the account.

**Verification note:** This is a logic-order fix. Syntax checks pass; human review is recommended to confirm the ordering matches the intended safety semantics.

### WR-03: Get-AdmanRecoveryPostureReport dereferences a potentially null posture object

**Files modified:** `Public/Get-AdmanRecoveryPostureReport.ps1`
**Commit:** `2ff8df9`
**Applied fix:** Guarded `RecycleBinEnabled`, `ForestFunctionalLevel`, and `TombstoneLifetime` with an `if ($posture)` test, returning `$null` for each property when posture cannot be determined.

### WR-04: Inventory remote-cap budget truncates fractional seconds to zero

**Files modified:** `Public/Get-AdmanInventoryReport.ps1`
**Commit:** `5dc3689`
**Applied fix:** Removed the `[int]` casts from `$totalRemaining` and `$queryRemaining` so fractional seconds are preserved in the budget calculations.

### WR-05: Find-AdmanUser silently ignores multiple search criteria

**Files modified:** `Public/Find-AdmanUser.ps1`
**Commit:** `bc70457`
**Applied fix:** Added an explicit guard that throws when more than one of `-Name`, `-SamAccountName`, or `-DisplayName` is supplied.

### WR-06: Export-AdmanReportHtml uses a fragile regex to remove the empty prototype row

**Files modified:** `Public/Export-AdmanReportHtml.ps1`
**Commit:** `4d00abd`
**Applied fix:** Replaced the regex-based empty-row removal with direct construction of a header-only HTML table, HTML-encoding property names.

### WR-07: build/Sign-AdmanModule.ps1 can hang on password-protected PFX in non-interactive CI

**Files modified:** `build/Sign-AdmanModule.ps1`
**Commit:** `a77127b`
**Applied fix:** Added an optional `[SecureString]$CertificatePassword` parameter to the `ByFile` parameter set; when supplied, the PFX is loaded with the `X509Certificate2` constructor to avoid the interactive `Get-PfxCertificate` prompt.

### WR-08: Invoke-AdmanAuditRotation uses hard-coded backslashes in the archive path

**Files modified:** `Private/Audit/Rotation.ps1`
**Commit:** `cdacebc`
**Applied fix:** Replaced the hard-coded `archive\{0}` format with nested `Join-Path` calls for cross-platform path construction.

### WR-09: Audit schema test source-hygiene regex differs from its documented banned-token list

**Files modified:** `tests/Audit.Schema.Tests.ps1`
**Commit:** `aad9d3a`
**Applied fix:** Narrowed `$script:SecretNameRegex` to match the actual source-code scan regex (`password|secret|credential|apiKey|privateKey`) and removed the now-unmatched `token` entry from the positive-control fixture and assertion list.

## Skipped Issues

None — all findings were fixed.

---

_Fixed: 2026-07-22T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
