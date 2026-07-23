---
phase: 05-hardening-portability
fixed_at: 2026-07-23T18:25:00Z
review_path: .planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 11
skipped: 1
status: partial
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-23T18:25:00Z
**Source review:** .planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12
- Fixed: 11
- Skipped: 1

## Fixed Issues

### CR-01: `Set-AdmanUserPassword` can lose the generated password on partial success

**Files modified:** `Public/Set-AdmanUserPassword.ps1`
**Commit:** `ea7e6de`
**Applied fix:** Moved the generated-password display block to immediately after the successful `Set-ADAccountPassword` gate call, before the `Set-ADUser` and optional `Unlock-ADAccount` sub-operations can fail. The transcript guard remains before the first mutation.

### WR-01: `ValidateSet` on password-source parameters still blocks the documented `'Ask'` value

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** `3d1e763`
**Applied fix:** Added `'Ask'` to each `[ValidateSet]` and updated the matching `.PARAMETER` help text for `AccountPasswordSource`, `NewPasswordSource`, and `PasswordSource`.

### WR-02: `Get-AdmanOffboardingState` crashes on malformed `tsUtc`

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`
**Commit:** `9d635c3`
**Applied fix:** Replaced the unguarded `[datetime]$_.tsUtc` cast with a `try/catch` fallback to `[datetime]::MinValue` in the `Sort-Object` script block.

### WR-03: `Start-AdmanUserOnboarding` preflight allows AD-invalid `sAMAccountName` characters

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`
**Commit:** `022c3a3`
**Applied fix:** Expanded the invalid-character regex to also reject `@`, backslash, slash, and comma.

### WR-04: `Export-AdmanConfig` writes absolute paths, breaking cross-machine import

**Files modified:** `Public/Config/Export-AdmanConfig.ps1`
**Commit:** `70df737`
**Applied fix:** Cloned the in-memory config before serialization and relativized `AuditDir` and `ReportDir` against the module root so exported backups remain portable.

### WR-05: `tests/Workflow.OffboardingState.Tests.ps1` pollutes the global function table

**Files modified:** `tests/Workflow.OffboardingState.Tests.ps1`
**Commit:** `ef925f5`
**Applied fix:** Added an `AfterAll` block that removes the global `Resolve-AdmanTarget` stub after the test file runs.

### WR-06: `Export-AdmanConfig` does not mirror the PSFramework config round-trip

**Files modified:** `Public/Config/Export-AdmanConfig.ps1`
**Commit:** `ea09539`
**Applied fix:** Removed the best-effort `.psf.json` mirror write and updated the help text to document that the export surface is plain-JSON only, eliminating stale framework mirrors.

### WR-07: `Start-Adman.ps1` output-path prompt loops forever on `B` (Back)

**Files modified:** `Public/Start-Adman.ps1`
**Commit:** `2f16ee7`
**Applied fix:** Set `$pathResolved = $true` when the operator chooses `B` in the CSV and HTML path-prompt loops so the inner loop exits and rendering is skipped.

### WR-09: `build/Sign-AdmanModule.ps1` uses HTTPS timestamp URL that `Set-AuthenticodeSignature` may reject

**Files modified:** `build/Sign-AdmanModule.ps1`
**Commit:** `e15180b`
**Applied fix:** Switched the timestamp server to `http://timestamp.digicert.com`, matching the runbook and README examples and the cmdlet's traditional RFC 3161 expectation.

### WR-10: CI AllSigned smoke test may fail to establish code-signing trust

**Files modified:** `.github/workflows/ci.yml`
**Commit:** `7834ee5`
**Applied fix:** Changed `New-SelfSignedCertificate -Type` from `CodeSigning` to `CodeSigningCert` and imported the self-signed `.cer` into both `TrustedPublisher` and `Root`.

### WR-11: `Start-AdmanUserOnboarding` does not validate `ParentOuDn` is inside managed scope before confirmation

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`
**Commit:** `54c5d43`
**Applied fix:** Added a boundary-anchored scope check for `templates.onboarding.ParentOuDn` before the workflow confirmation prompt, mirroring the offboarding quarantine-OU check.

## Skipped Issues

### WR-08: `Get-AdmanAccountStateReport` does not pin queries to the configured DC

**File:** `Public/Get-AdmanAccountStateReport.ps1:59-80`
**Reason:** Already fixed in current source. The shared `$splat` already includes `Server = $script:Config.DC` at the cited location.
**Original issue:** The `$splat` passed to `Search-ADAccount` included `-SearchBase`, `-SearchScope`, `-ResultPageSize`, and `-ErrorAction`, but omitted `-Server $script:Config.DC`.

---

_Fixed: 2026-07-23T18:25:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
