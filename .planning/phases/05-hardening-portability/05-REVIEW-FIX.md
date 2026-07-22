---
phase: 05-hardening-portability
fixed_at: 2026-07-22T23:55:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 2
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-22T23:55:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 9
- Fixed: 9
- Skipped: 0

## Fixed Issues

### CR-01: Public verbs accept a half-initialized session and silently bypass protected-account checks

**Files modified:** `Private/Foundation/Assert-AdmanInitialized.ps1`, `Private/Safety/Invoke-AdmanMutation.ps1`, `Private/Safety/Invoke-AdmanLocalMutation.ps1`, plus the init check in all public mutation/report verbs.
**Commits:** a4bf6b2, 5ff82e6, 7779fe9, a1419fe, 697bd2d, 65e99f3
**Applied fix:** Centralized the initialization guard in `Assert-AdmanInitialized`, which verifies `$script:Initialized`, `$script:Config.ManagedOUs`, and the protected-identity caches (`$script:ProtectedSIDs`, `$script:DenyRids`, `$script:ProtectedGroupDns`) using `Get-Variable` so empty arrays are allowed and `StrictMode` does not throw. The fail-closed guard is invoked at the top of both mutation gates (`Invoke-AdmanMutation` and `Invoke-AdmanLocalMutation`), so no write path can run with null caches. Public verbs retain a UX-only `$script:Config.ManagedOUs` fail-fast check so callers get the original clear error message. Unit tests were updated to seed the full init state so the gate guard passes.

### CR-02: DN normalization corrupts uppercase hex escapes and can break the managed-OU scope boundary

**Files modified:** `Private/Utility/ConvertTo-AdmanNormalizedDn.ps1`, `tests/Utility.NormalizedDn.Tests.ps1`
**Commit:** 49ef029
**Applied fix:** Made the hex-unescape regex case-insensitive (`[0-9a-fA-F]{2}`) and added a negative lookbehind so `\\` is treated as a literal backslash rather than an escape prefix. Added unit tests covering lowercase, uppercase, and mixed hex escapes (`\2C`, `\2c`, `\5C`, `CN=A\2CB\2CC`).

### WR-01: `Write-AdmanAudit` hard-codes the module name and crashes when the module is not loaded as `adman`

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** f63f225
**Applied fix:** Replaced `Get-Module adman` with `$ExecutionContext.SessionState.Module` and degrades to `'unknown'` when no module context exists, preventing null-reference failures during dot-sourced or test-harness execution.

### WR-02: `Set-AdmanLocalUser` rejects password resets that rely on the configured password source

**Files modified:** `Public/Set-AdmanLocalUser.ps1`, `tests/Local.User.Tests.ps1`
**Commits:** 673aa46, 6f4725e
**Applied fix:** Removed the throw block that rejected the `Reset` parameter set when neither `-Password` nor `-PasswordSource` was supplied, allowing the existing D-05 config fallback (`security.passwordSource`) to generate or prompt for a password. Updated the Local.User tests to assert the fallback path.

### WR-03: Bulk no-op skip misses already-disabled/enabled accounts because `Resolve-AdmanTarget` does not fetch `Enabled`

**Files modified:** `Private/Safety/Resolve-AdmanTarget.ps1`
**Commit:** dcdf1ef
**Applied fix:** Added `Enabled` to the `-Properties` list passed to `Get-ADObject` so the bulk engine can detect already-disabled/enabled accounts and skip redundant writes.

### WR-04: `Resolve-AdmanIdentity` AdComputer branch can return a user object

**Files modified:** `Private/Safety/Resolve-AdmanIdentity.ps1`
**Commit:** 4e048d9
**Applied fix:** Added a `Where-Object { $_.objectClass -contains 'computer' }` filter to the exact-match branch of the `AdComputer` resolver, so a user account with a matching `sAMAccountName` cannot be returned.

### WR-05: Local Administrator detection relies on the English group name "Administrators"

**Files modified:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1`
**Commit:** caa1af1
**Applied fix:** Resolved the well-known SID `S-1-5-32-544` to its localized NT account name and stripped the domain prefix before calling `Get-LocalGroupMember` and the WMI fallback, so the admin-group check works on non-English Windows installations.

### WR-06: Generated-password transcript guard can throw on Windows PowerShell 5.1 or non-interactive runspaces

**Files modified:** `Private/Foundation/Get-AdmanTranscriptCount.ps1` (created), `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/New-AdmanLocalUser.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** 673aa46
**Applied fix:** Added a guarded helper `Get-AdmanTranscriptCount` that returns `0` when `InitialSessionState` or `Transcripts` is unavailable, and replaced all direct `Transcripts.Count` probes in the password verbs with calls to the helper.

### WR-07: `Invoke-AdmanBulkAction` resolves targets twice per allowed item

**Files modified:** `Private/Safety/Invoke-AdmanMutation.ps1`, `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** a60cbe9
**Applied fix:** Added an optional `[object[]]$ResolvedObjects` parameter to `Invoke-AdmanMutation` so the bulk engine can pass the already-resolved AD object snapshot through to the gate, eliminating the second `Resolve-AdmanTarget` call and preventing race conditions between preview and execution.

---

_Fixed: 2026-07-22T23:55:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
