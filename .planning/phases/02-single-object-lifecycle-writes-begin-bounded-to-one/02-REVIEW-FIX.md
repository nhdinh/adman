---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
fixed_at: 2026-07-16T11:56:00Z
review_path: .planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-REVIEW.md
iteration: 1
findings_in_scope: 16
fixed: 13
reverted: 1
already_addressed: 2
skipped: 0
status: partial
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-07-16T11:56:00Z
**Source review:** .planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-REVIEW.md (commit f5b544a)
**Iteration:** 1 (no --auto)

**Summary:**
- Findings in scope: 16 (4 critical, 8 warning, 4 info)
- Fixed: 13
- Reverted (finding was incorrect): 1 (WR-07)
- Already addressed in prior run: 2 (IN-02, IN-03)
- Test status: 469 passed / 4 failed (pre-existing on master) / 5 skipped / 1 container failure (pre-existing Menu.Tests.ps1 parse error). Zero regressions introduced by this fix pass.

> **Note on prior report:** The first version of this file (commit 4bb8f98) described an
> earlier Set-A fix run's findings and cited commits (f522db9, f04cf40, …) that predate
> the current REVIEW.md. This version accurately reflects the Set-B fix run against
> REVIEW.md commit f5b544a.

## Fixed Issues

### CR-01: Set-AdmanUserPassword swallows follow-up gate failures and mislabels audit

**Files modified:** `Public/Set-AdmanUserPassword.ps1`
**Commits:** f0eca86, b7c87f8
**Applied fix:** Captured all three gate invocation results (Set-ADAccountPassword, Set-ADUser for ChangePasswordAtLogon, Unlock-ADAccount) instead of only the first. Aggregated errors so a follow-up failure throws a correlated exception that names every sub-operation that failed, rather than surfacing an uncorrelated error after the reset already succeeded. Hardened the results array access against an empty-array return from a mocked gate.

### CR-02: Test-AdmanLocalTargetAllowed orphaned-SID regex not actually fixed

**Files modified:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1`
**Commit:** c97d450
**Applied fix:** Replaced the substring regex `'0x80070534|0x534'` with structured detection on the exception's `HResult` (`-2147023564` == `0x80070534` signed int32) or `NativeErrorCode` (`1332` == `ERROR_NONE_MAPPED`). Unrelated error codes whose hex happens to contain `0x534` (e.g. `0x5340`) no longer misclassify as orphaned-SID and no longer trigger the WMI fallback path.

### CR-03: Read-AdmanActionParams GeneratedPassword Prompt path can dispose a stored SecureString

**Files modified:** `Private/Menu/Read-AdmanActionParams.ps1`
**Commit:** f58d98e
**Applied fix:** Set `$firstConsumed = $true` BEFORE storing `$first` into `$params`, closing the exception window where a throw between the two statements would leave a disposed SecureString referenced in `$params` (downstream `ObjectDisposedException`).

### CR-04: New-ADUser uniqueness pre-flight does not escape wildcards in CN check

**Files modified:** `Private/Safety/Invoke-AdmanMutation.ps1`
**Commit:** 966884f
**Applied fix:** Added wildcard validation to the New-ADUser uniqueness pre-flight. `Name` / `sAMAccountName` inputs containing `*` or `?` are rejected before the `Get-ADObject -Filter` call, closing the wildcard-injection gap that `Escape-AdmanAdFilterLiteral` deliberately does not cover.

### WR-01: Invoke-AdmanMutation group-refusal path writes N refused records but throws on first

**Files modified:** `Private/Safety/Invoke-AdmanMutation.ps1`
**Commit:** 56cafb4
**Applied fix:** The group-refusal throw now names the affected member DNs. Operators can see exactly which members were refused without having to re-run the gate per member or dig through the audit file.

### WR-02: Write-AdmanAudit mutex WaitOne has no timeout

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** 39e5b80
**Applied fix:** Bounded the audit mutex `WaitOne()` with a 30-second timeout. Acquisition failure now throws a distinguishable `AUDIT FAIL-CLOSED` error rather than deadlocking the caller when another process holds the mutex orphaned.

### WR-03: Initialize-AdmanConfig absolutizes AuditDir/ReportDir against process CWD, not module root

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** 84a2758
**Applied fix:** Relative `AuditDir` / `ReportDir` paths are now resolved against the module root, not the process's current working directory. The config behaves identically regardless of where the operator invoked `Start-Adman` from.

### WR-04: Resolve-AdmanIdentity AdComputer trailing-dollar lookup can false-positive on user accounts

**Files modified:** `Private/Safety/Resolve-AdmanIdentity.ps1`, `tests/Menu.IdentityResolver.Tests.ps1`
**Commits:** 6137f95, 5822175
**Applied fix:** The trailing-dollar fallback lookup now wraps the sAMAccountName filter in `(&(sAMAccountName -eq 'NAME$')(objectClass -eq 'computer'))`. A user account whose sAMAccountName happens to end in `$` no longer false-positives as a computer target. Test mock parameter filters updated to match the new LDAP filter shape.

### WR-05: Test-AdmanTargetAllowed protected-membership check swallows DC-unreachable as refusal

**Files modified:** `Private/Safety/Test-AdmanTargetAllowed.ps1`
**Commit:** 8bdaf46
**Applied fix:** Distinguished DC-unreachable / query-failure outcomes from actual policy refusal. Both still fail closed (the safe direction), but the audit record and the operator-visible reason now categorize the cause correctly, so a DC outage isn't misreported as a protected-group policy violation.

### WR-06: Menu FixedParameters merge can silently overwrite prompted values

**Files modified:** `Private/Menu/Read-AdmanActionParams.ps1`
**Commit:** 0a168a7
**Applied fix:** When a `FixedParameters` entry collides with a parameter the operator was prompted for, a warning is now emitted naming the parameter and which value won. The merge remains fixed-wins (the menu author's explicit choice) but is no longer silent.

### WR-08: Display-once plaintext via Write-Host

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/New-AdmanLocalUser.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** d698225
**Applied fix:** Switched the display-once password output from `Write-Host` to `[Console]::WriteLine`. The previous comment claimed plaintext "never touches any stream," which was factually incorrect — `Write-Host` writes to the Information stream in PS 5+. `[Console]::WriteLine` bypasses all PowerShell streams, making the comment accurate. The Start-Transcript capture caveat is unchanged and still documented (transcription records the console buffer regardless of stream).

### IN-01: Resolve-AdmanCreateTarget RDN escape does not handle leading/trailing spaces correctly

**Files modified:** `Private/Safety/Resolve-AdmanCreateTarget.ps1`
**Commit:** ec9d8c8
**Applied fix:** RDN escape now handles ALL leading and trailing spaces per RFC 4514 section 2.4, not just a single leading/trailing space.

### IN-04: Test-AdmanPasswordComplexity MinLength default diverges from config default

**Files modified:** `Private/Utility/Test-AdmanPasswordComplexity.ps1`
**Commit:** 6993b1c
**Applied fix:** The default minimum length is now sourced from a single script-level constant rather than being redeclared inline, so the function default stays in lockstep with `security.passwordGeneration.length` in `config/adman.defaults.json`.

## Reverted (finding was incorrect)

### WR-07: Mock New-ADUser accepts ChangePasswordAtLogon, masking real parameter mismatch

**Files touched:** `tests/Mocks/ActiveDirectory.psm1`
**Commits:** 46b6cf2 (initial fix), fc217e8 (revert)
**Outcome:** The review claimed the real `New-ADUser` does not accept `-ChangePasswordAtLogon` and that the mock was masking a parameter mismatch. Verification against the actual ActiveDirectory module showed the real cmdlet DOES have `-ChangePasswordAtLogon`. The initial fix was reverted; the mock and production code are correct as originally written. The review finding itself was incorrect.

## Already Addressed (prior run)

### IN-02: AdmanWriteVerbs.ps1 comment says "9-verb" but list contains 10 verbs

**Resolved by:** b81b2b8 (prior fix pass) — the "9-verb" count was dropped from the comment entirely; the current comment no longer mentions a number.

### IN-03: Magic number 20 (default password length) repeated in multiple places

**Resolved by:** cc6a236 (prior fix pass) — default password length was single-sourced. Remaining `20` literals in the codebase are the unrelated sAMAccountName 20-character limit (a hard AD constraint, not a tunable default).

## Notes

- 17 fix commits total: 13 findings resolved with single commits, plus 2-commit chains for CR-01 (f0eca86 + b7c87f8 hardening), WR-04 (6137f95 + 5822175 test update), and WR-07 (46b6cf2 + fc217e8 revert).
- All commits are on `master`. The fixer worked in an isolated worktree (`sv-02-reviewfix-3VG1ET`) which was cleaned up after merge.
- Reviewer initially applied a fix for WR-07 based on the finding's claim; on verifying against the real ActiveDirectory module, the finding was found to be incorrect and the fix was reverted in the same pass.
