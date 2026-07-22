---
phase: 05
fixed_at: 2026-07-22T08:26:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-22T08:26:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 11
- Fixed: 11
- Skipped: 0

## Fixed Issues

### CR-01: Third-party CI action pinned to floating major version

**Files modified:** `.github/workflows/ci.yml`
**Commit:** ba173e6
**Applied fix:** Replaced `mchave3/setup-pwsh@v1` with the verified v1.0.0 commit SHA `c1a3d09904f9431d0fc1e079a11e49c11e8b0151` and added a comment documenting the supply-chain rationale.

### CR-02: Unguarded `[datetime]::ParseExact` can crash audit rotation

**Files modified:** `Private/Audit/Rotation.ps1`
**Commit:** fb885f3
**Applied fix:** Wrapped the `ParseExact` call in a try/catch so filenames matching the regex but containing invalid calendar dates are skipped with a warning instead of aborting rotation.

### CR-03: Config validator lacks type guard for `security.passwordGeneration.length`

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** 06544c7
**Applied fix:** Added the same numeric-or-digit-string guard used for `audit.retentionDays` before casting `security.passwordGeneration.length` to `[int]`.

### WR-01: Relative config paths are not normalized consistently with absolute paths

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** fec5f10
**Applied fix:** Built a single `$joined` path for both relative and absolute `AuditDir`/`ReportDir` values, then resolved it through `GetUnresolvedProviderPathFromPSPath` in both branches.

### WR-02: CI imports self-signed certificate into the machine Root store

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 041538a
**Applied fix:** Removed the `Cert:\LocalMachine\Root` import from the AllSigned smoke test; only `Cert:\LocalMachine\TrustedPublisher` is used for the CI ephemeral certificate.

### WR-03: Generated passwords are captured by `Start-Transcript`

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** d6117d9
**Applied fix:** Added a transcript-active check before displaying generated plaintext in all three password-generating verbs; throws a clear message telling the operator to stop the transcript and retry.

### WR-04: Bulk engine resolves each group twice

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** f8ffcc9
**Applied fix:** Introduced a `$groupCache` hashtable populated during pre-confirmation validation; the per-record filter and execution phases now reuse the cached group objects instead of calling `Resolve-AdmanGroup` again.

### WR-05: Rotation regex only validates digit count, not calendar date

**Files modified:** `Private/Audit/Rotation.ps1`
**Commit:** 322b764
**Applied fix:** Added a comment documenting that the regex checks only the 8-digit date shape and that calendar validity is enforced by the `ParseExact` call (which skips invalid dates).

### WR-06: `ManagedOUs` element types are not validated

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** 17e73c1
**Applied fix:** Added a loop over `ManagedOUs` that rejects any element that is not a `[string]` or is whitespace-only.

### WR-07: `Start-Adman` path prompt `B` returns to format selection, not the top-level menu

**Files modified:** `Public/Start-Adman.ps1`
**Commit:** 2112130
**Applied fix:** Changed both CSV and HTML path-prompt `B` handlers from `break` to `break menuLoop` so they return to the top-level menu instead of the format-selection loop.

### WR-08: Onboarding sAMAccountName pre-flight validation is incomplete

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`
**Commit:** 0b026a2
**Applied fix:** Added checks for leading/trailing whitespace and for AD-invalid characters (`"`, `[`, `]`, `:`, `|`, `<`, `>`, `+`, `=`, `;`) before the wildcard check.

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-07-22T08:26:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
