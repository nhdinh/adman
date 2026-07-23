---
phase: 05-hardening-portability
fixed_at: 2026-07-23T17:45:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-23T17:45:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: Audit writer does not catch mutex-acquisition failures

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `4419909`
**Applied fix:** Moved `New-AdmanAuditMutex`, the `$null` check, and the `WaitOne` timeout logic inside the same `try` block as the record write so a mutex-acquisition failure is caught by the SAFE-04 fail-closed handler instead of propagating as a raw seam error.
**Verification:** Syntax check passed; `Audit.FailClosed.Tests.ps1` passed (7/7).

### CR-02: Stale-report grace-window comparison mixes UTC and local-kind DateTime values

**Files modified:** `Public/Get-AdmanStaleReport.ps1`
**Commit:** `26e7cf5`
**Applied fix:** Normalized `$created` with `$created.ToUniversalTime()` before comparing against the UTC `$staleCutoff` in the never-logged-on bucket.
**Verification:** Syntax check passed. No dedicated stale-report unit tests exist; this is a logic change requiring human verification.

### WR-01: Code-signing build script does not timestamp signatures

**Files modified:** `build/Sign-AdmanModule.ps1`
**Commit:** `1c94d50`
**Applied fix:** Added `-TimestampServer 'http://timestamp.digicert.com'` to `Set-AuthenticodeSignature` so signatures remain valid after the signing certificate expires.
**Verification:** Syntax check passed.

### WR-02: Write-Host used outside the TUI-rendering module

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `b40a288`
**Applied fix:** Replaced `Write-Host` with `Write-PSFMessage -Level Host` for the manual cleanup checklist and removed the `PSAvoidUsingWriteHost` suppression.
**Verification:** Syntax check passed.

### WR-03: SHA256 hash instances are not disposed

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`, `Private/Audit/Rotation.ps1`
**Commit:** `3ac7c4c`
**Applied fix:** Wrapped SHA256 creation in `try/finally` with explicit `Dispose()` in both the audit writer and integrity verifier.
**Verification:** Syntax check passed; `Audit.Integrity.Tests.ps1` and `Audit.Rotation.Tests.ps1` passed (5/5).

### WR-04: Config validator casts integer keys without type guards

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `e87b2e2`
**Applied fix:** Added explicit type guards before casting `safety.bulkConfirmThreshold`, `bulk.maxCount`, `transport.timeouts.perHostProbeCap`, and `transport.timeouts.totalInventoryRemoteCap`. Also enforced `bulk.maxCount >= 1`.
**Verification:** Syntax check passed; timeout-config validator tests passed. Note: `Config.Load.Tests.ps1` has 11 pre-existing failures in `Initialize-AdmanConfig` integration-style cases caused by PowerShell 5.1's `ConvertFrom-Json` unwrapping single-element `ManagedOUs` arrays to strings. These failures exist on the unmodified `master` branch and are unrelated to WR-04.

### WR-05: Audit rotation can move a file before its archive directory is created

**Files modified:** `Private/Audit/Rotation.ps1`
**Commit:** `ee11d32`
**Applied fix:** Folded archive-directory/marker creation and the file move under a single `ShouldProcess` confirmation so confirming the move guarantees the archive directory exists.
**Verification:** Syntax check passed; `Audit.Rotation.Tests.ps1` passed (1/1).

### WR-06: Usage docs contain out-of-scope move examples

**Files modified:** `docs/USAGE.md`
**Commit:** `94e3c5e`
**Applied fix:** Updated `Move-AdmanUser` and `Move-AdmanComputer` examples to use destination OUs under `OU=Managed,DC=contoso,DC=local`.
**Verification:** Markdown section re-read and confirmed.

## Skipped Issues

None — all in-scope findings were fixed.

## Notes

- `CR-02` is a logic-only change (DateTime normalization). Tier 1/Tier 2 verification confirms syntax and structure, not semantic correctness; human verification is recommended before the verification phase.
- `Config.Load.Tests.ps1` failures observed during WR-04 verification are pre-existing on `master` and unrelated to the changes in this report.

---

_Fixed: 2026-07-23T17:45:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
