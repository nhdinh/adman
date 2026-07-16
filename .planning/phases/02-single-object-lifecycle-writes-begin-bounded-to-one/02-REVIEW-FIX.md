---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
fixed_at: 2026-07-16T04:24:41Z
review_path: .planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-REVIEW.md
iteration: 1
findings_in_scope: 17
fixed: 17
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-07-16T04:24:41Z
**Source review:** .planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 17 (4 critical, 9 warning, 4 info)
- Fixed: 17
- Skipped: 0

## Fixed Issues

### CR-01: Set-ADAccountPassword wrapper bypasses the per-verb allow-list

**Files modified:** `Private/AD/Adman.AD.Write.ps1`, `Public/Set-AdmanUserPassword.ps1`, `tests/User.Password.Tests.ps1`
**Commit:** f522db9
**Applied fix:** Chose review option (c). Stripped the composite follow-up calls (Set-ADUser for ChangePasswordAtLogon, Unlock-ADAccount) out of the `Adman.AD.Write.Set-ADAccountPassword` wrapper. The wrapper now invokes ONLY `Set-ADAccountPassword`. Updated `Set-AdmanUserPassword` to invoke the gate three separate times (Set-ADAccountPassword, Set-ADUser, optionally Unlock-ADAccount), giving each sub-operation its own PENDING/OUTCOME audit pair and its own confirmation. Updated User.Password.Tests to assert the new call shape (separate ParameterFilter for each gate invocation).

### CR-02: Resolve-AdmanLocalTarget orphaned-SID tolerance regex too broad

**Files modified:** `Private/Safety/Resolve-AdmanLocalTarget.ps1`
**Commit:** f04cf40
**Applied fix:** Replaced the substring regex `'0x80070534|0x534'` (which would also swallow unrelated errors like `0x5340`) with a structured check on the exception's `HResult` (`-2147023564` == `0x80070534` signed int32) or `NativeErrorCode` (`1332` == `ERROR_NONE_MAPPED`).

### CR-03: Test-AdmanLocalTargetAllowed forces AD dependency for ALL local verbs

**Files modified:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1`, `tests/Local.Gate.Tests.ps1`
**Commit:** 990bf40
**Applied fix:** Combined review options (a) and (c). Introduced `Get-AdmanLocalMachineScope` helper that (a) caches the machine-in-scope decision per machine per session (the machine$ computer object does not move between OUs mid-session, so the N identical AD lookups in a batch collapse to 1), and (c) degrades to "warn but allow" when the AD lookup throws AND the target is the local machine (the operator's own workstation is trivially in scope for local operations on it). Remote targets remain fail-closed. Updated `Set-AdmanLocalSafetyState` test helper to clear the cache between tests so mock expectations do not leak.

### CR-04: Write-AdmanAudit catch block can throw a secondary exception

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** c9e6e17
**Applied fix:** Three hardening changes. (1) PENDING-failure throw now captures `$_` once, guards property access under StrictMode, and passes the original exception as `InnerException` so the diagnosis trail is preserved. (2) The `finally` block now guards `ReleaseMutex`/`Dispose` against a `$null` mutex (when `New-AdmanAuditMutex` itself threw) and wraps each call in try/catch so a secondary exception in `finally` does not mask the original audit error. (3) Added an explicit `$null` check after `New-AdmanAuditMutex` with a clear `AUDIT FAIL-CLOSED` throw at the acquisition site.

### WR-01: Set-AdmanLocalUser Enable/Disable menu entries bypass the password-source code path

**Files modified:** `Public/Set-AdmanLocalUser.ps1`
**Commit:** 4989872
**Applied fix:** Wrapped the entire Reset-only block (password sourcing + gate call + display-once) in an explicit `if ($PSCmdlet.ParameterSetName -eq 'Reset')` guard. The early returns already made the block unreachable on Enable/Disable, but the explicit guard prevents a future maintainer adding code between dispatch and the gate from accidentally running password-sourcing logic on the Enable path.

### WR-02: Confirm-AdmanAction hardcodes Remove-LocalUser threshold override

**Files modified:** `Private/Safety/Confirm-AdmanAction.ps1`, `config/adman.schema.json`, `config/adman.defaults.json`
**Commit:** 1d7b95d
**Applied fix:** Added `safety.typedCountVerbs` to the config schema (default `['Remove-LocalUser']`) and read it in `Confirm-AdmanAction`. Adding a new irreversible verb no longer requires a code change in the confirm function — it is now a config change.

### WR-03: Unlock-AdmanUser pre-reads LockedOut on PDCe but does NOT pass -WhatIf

**Files modified:** `Public/Unlock-AdmanUser.ps1`
**Commit:** c149c7a
**Applied fix:** Under `-WhatIf`, skip the `LockedOut` pre-read entirely and let the gate produce the dry-run preview. Still resolve the PDCe for `$Parameters['Server']` so the preview line names the PDCe the write WOULD target; fall back to the configured DC if the PDCe lookup itself fails under `-WhatIf`.

### WR-04: Read-AdmanActionParams GeneratedPassword Prompt path stores $first but never disposes $second

**Files modified:** `Private/Menu/Read-AdmanActionParams.ps1`
**Commit:** 9b2e9cc
**Applied fix:** Wrapped the prompt-and-validate block in try/finally. Always `Dispose()` `$second`. `Dispose()` `$first` only when it was NOT consumed (stored into `$params`). The BSTR zeroing is unchanged. This covers all three exit paths: mismatch, complexity failure, and success-with-consume.

### WR-05: Display-once plaintext via Write-Host

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/New-AdmanLocalUser.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** 970ad24
**Applied fix:** Chose review option (b). Corrected the factually incorrect "Plaintext never touches any stream" claim in all four verbs. The new comment explicitly states: plaintext never touches the Success/Error/Warning/Verbose streams or any audit field, but DOES go to the host display via Write-Host. Documented the Start-Transcript caveat so operators know not to run password-generating verbs under transcription.

### WR-06: Invoke-AdmanMutation New-ADUser uniqueness pre-flight lacks DN in error

**Files modified:** `Private/Safety/Invoke-AdmanMutation.ps1`
**Commit:** 6294f1c
**Applied fix:** Added `-Properties DistinguishedName` to both pre-flight `Get-ADObject` calls and included the conflicting DN in the thrown error for both sAMAccountName and CN collisions. The operator can now locate the collision even when it lives in an unmanaged OU they cannot browse.

### WR-07: Test-AdmanGroupAllowed deny-RID check uses string comparison without type coercion

**Files modified:** `Private/Safety/Test-AdmanGroupAllowed.ps1`, `Private/Safety/Test-AdmanTargetAllowed.ps1`
**Commit:** 4f32698
**Applied fix:** Coerced both sides of the `-in` comparison to string explicitly at both check sites. If `$script:DenyRids` was loaded from JSON as integers (e.g. `[512]` rather than `['512']`), the previous case-sensitive string `-in` comparison would have failed silently and bypassed the deny-list.

### WR-08: Resolve-AdmanCreateTarget fabricates DN by naive string interpolation

**Files modified:** `Private/Safety/Resolve-AdmanCreateTarget.ps1`
**Commit:** 3d3c025
**Applied fix:** Added `ConvertTo-AdmanRdnEscaped` helper implementing RFC 4514 section 2.4 RDN escaping (backslash first, then `,` `=` `+` `"` `<` `>` `;`, plus leading `#` and leading/trailing space). Applied it to the CN before interpolating into the DistinguishedName.

### WR-09: Start-Adman menu dispatches to $Verb via string name; no validation

**Files modified:** `Public/Start-Adman.ps1`
**Commit:** 812b332
**Applied fix:** Validated with `Get-Command -Name $Verb -ErrorAction SilentlyContinue` before dispatch. On failure, prints the menu entry label and the missing verb name with a "Contact the adman maintainer" message, then continues to the next iteration.

### IN-01: AdmanWriteVerbs.ps1 comment says "9-verb" but the list contains 10 verbs

**Files modified:** `Private/Safety/AdmanWriteVerbs.ps1`
**Commit:** b81b2b8
**Applied fix:** Dropped the count from the synopsis and `.DESCRIPTION` (now just "the AD write allow-list") so the comments cannot drift again when the list changes.

### IN-02: Read-AdmanActionParams has unused `$required` variable for Choices/GeneratedPassword paths

**Files modified:** `Private/Menu/Read-AdmanActionParams.ps1`
**Commit:** 8a018d6
**Applied fix:** Chose the "document" option. Added a comment explaining that `$required` is consulted ONLY by the free-text branch; the Choices and GeneratedPassword branches always loop until a valid selection or B/Q (implicitly always required).

### IN-03: Magic number 20 (default password length) repeated in 5 places

**Files modified:** `adman.psm1`, `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/New-AdmanLocalUser.ps1`, `Public/Set-AdmanLocalUser.ps1`, `Private/Menu/Read-AdmanActionParams.ps1`, `Private/Utility/New-AdmanRandomPassword.ps1`
**Commit:** cc6a236
**Applied fix:** Defined `$script:DefaultPasswordLength = 20` in `adman.psm1` and referenced it everywhere the literal `20` appeared as a fallback (10 sites) plus as the default in `New-AdmanRandomPassword -Length`. The parameter default is evaluated at call time, so tests that override the script variable see the new default.

### IN-04: tests/Mocks/ActiveDirectory.psm1 Search-ADAccount mock does not honor -SearchBase for out-of-scope row

**Files modified:** `tests/Mocks/ActiveDirectory.psm1`
**Commit:** 9215614
**Applied fix:** Derived the out-of-scope row's DN from a sibling of `$sb`: strip the leftmost RDN from `$sb` and prepend `OU=NotManaged` so the row is always outside whatever base the caller searched. A future test that searches a DIFFERENT base (e.g. `OU=NotManaged,...`) will no longer receive a row that is accidentally IN scope.

---

_Fixed: 2026-07-16T04:24:41Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
