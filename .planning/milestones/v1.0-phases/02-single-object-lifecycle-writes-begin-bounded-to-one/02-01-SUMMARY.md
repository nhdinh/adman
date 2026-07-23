---
phase: 02
plan: 01
subsystem: safety-gate-infrastructure
tags: [gate, mutation-funnel, d-01, d-02, d-03, d-04, d-05, safe-08, safe-09, safe-10, tdd]
requires:
  - 00-01 module scaffold + AST guard
  - 00-03 Pester 6 mock patterns
  - 00-04 Invoke-AdmanMutation fixed order
  - 00-05 Write-AdmanAudit fail-closed writer
provides:
  - New-AdmanRandomPassword (CSPRNG generator, D-05)
  - Test-AdmanPasswordComplexity (prompt-path validator, D-05)
  - Resolve-AdmanCreateTarget (synthetic pre-create target, D-01)
  - Resolve-AdmanGroup (single-shot group resolver, D-04)
  - Test-AdmanGroupAllowed (group-side policy, D-04)
  - Resolve-AdmanLocalTarget (local target materialization + create-branch + pre-delete state, D-02/D-03)
  - Test-AdmanLocalTargetAllowed (local policy, D-02)
  - Invoke-AdmanLocalMutation (local gate, D-02)
  - Adman.Local.Write.* (seven local wrappers, D-02)
  - Adman.AD.Write.New-ADUser (create wrapper, D-01)
  - Get-AdmanBannedLocalWriteVerbs (AST guard single source, D-02)
affects:
  - 02-02 (New-AdmanUser consumes New-ADUser + password plumbing)
  - 02-03 (Set-AdmanUserPassword consumes Set-ADAccountPassword split)
  - 02-04 (Unlock-AdmanUser consumes Unlock-ADAccount Server override)
  - 02-05 (group verbs consume dual-resolution group path)
  - 02-06 (local verbs consume local gate)
tech-stack:
  added:
    - Microsoft.PowerShell.LocalAccounts stubs (tests/Mocks)
  patterns:
    - synthetic pre-create target (IsSynthetic=$true) for create verbs
    - uniqueness pre-flight + TOCTOU closure via the create cmdlet's own throw
    - dual-resolution group path (member via Resolve-AdmanTarget, group via Resolve-AdmanGroup)
    - direct SID equality for protected-group adds (NOT IN_CHAIN)
    - asymmetric remediation (Remove skips protected-SID check)
    - per-verb Parameters validator inside the gate (Move-ADObject TargetPath)
    - try/catch Failure outcome audit on wrapper throw (HIGH #1)
    - splat-copy strip pattern for parameter collisions (HIGH #3, HIGH #4, B3, B5)
key-files:
  created:
    - Private/Utility/New-AdmanRandomPassword.ps1
    - Private/Utility/Test-AdmanPasswordComplexity.ps1
    - Private/Safety/Resolve-AdmanCreateTarget.ps1
    - Private/Safety/Resolve-AdmanGroup.ps1
    - Private/Safety/Test-AdmanGroupAllowed.ps1
    - Private/Safety/Resolve-AdmanLocalTarget.ps1
    - Private/Safety/Test-AdmanLocalTargetAllowed.ps1
    - Private/Safety/Invoke-AdmanLocalMutation.ps1
    - Private/Local/Adman.Local.Write.ps1
    - tests/Local.Gate.Tests.ps1
  modified:
    - config/adman.schema.json
    - config/adman.defaults.json
    - config/adman.example.json
    - Private/Config/Initialize-AdmanConfig.ps1
    - Private/Safety/Test-AdmanTargetAllowed.ps1
    - Private/Safety/AdmanWriteVerbs.ps1
    - Private/Safety/Invoke-AdmanMutation.ps1
    - Private/Safety/Confirm-AdmanAction.ps1
    - Private/AD/Adman.AD.Write.ps1
    - Private/Audit/Write-AdmanAudit.ps1
    - rules/AdmanSafetyRules.psm1
    - tests/Mocks/ActiveDirectory.psm1
    - tests/Safety.GateOrder.Tests.ps1
    - tests/Safety.NoHardDelete.Tests.ps1
    - tests/Safety.PreviewEqualsExecute.Tests.ps1
    - tests/Config.Load.Tests.ps1
    - tests/Config.FailClosed.Tests.ps1
    - tests/Config.RoundTrip.Tests.ps1
decisions:
  - D-01 synthetic pre-create target carries IsSynthetic=$true and ParentOuDn; the create-branch in Test-AdmanTargetAllowed runs ONLY managed-OU scope against the parent OU DN
  - D-02 local gate mirrors the AD gate byte-for-byte; create-branch + uniqueness pre-flight + TOCTOU closure strictly parallel to D-01
  - D-03 Remove-LocalUser forces typed-count confirmation at count=1 (threshold override); pre-delete state captured into the audit record
  - D-04 protected-group add refused by DIRECT SID equality (not IN_CHAIN); Remove skips the check (asymmetric remediation); deny-RID applies on both
  - D-05 CSPRNG generator uses rejection sampling + Fisher-Yates over a 76-char unambiguous alphabet; complexity validator uses case-sensitive -cnotmatch
  - HIGH #1: both gates write a Failure outcome audit record on wrapper throw before rethrowing (no PENDING orphan)
  - HIGH #3: Unlock-ADAccount honors $Parameters['Server'] via splat-copy strip (no duplicate-parameter collision)
  - HIGH #4: Set-ADAccountPassword splits ChangePasswordAtLogon to a follow-up Set-ADUser call after the reset
metrics:
  duration: ~3h (across two sessions)
  completed: 2026-07-16
  tasks: 3
  tests-added: 40 (13 password + 12 gate-order + 14 local-gate + 1 parse-fix)
  tests-passing: 366
  tests-failing: 0
status: complete
---

# Phase 02 Plan 01: Cross-Cutting Gate Infrastructure Summary

**One-liner:** Built the complete mutation-gate infrastructure for AD and local-account writes — D-01 create path with synthetic targets, D-02 local gate mirroring the AD gate, D-03 Remove-LocalUser typed-count override with pre-delete state capture, D-04 dual-resolution group policy with direct SID equality, and D-05 CSPRNG password plumbing — all behind the SAFE-08/09/10 fixed-order gate with fail-closed audit.

## What Was Built

### Task 1: Config schema + D-05 password plumbing + mocks
- `New-AdmanRandomPassword`: CSPRNG generator (`RandomNumberGenerator` + rejection sampling + Fisher-Yates) over a 76-char unambiguous alphabet (no `0 O o l 1 I`). Returns read-only `SecureString`.
- `Test-AdmanPasswordComplexity`: prompt-path validator holding typed passwords to the same bar as the generator. Uses **case-sensitive** `-cnotmatch` for `[A-Z]`/`[a-z]` class checks (default `-match` is case-insensitive and would false-pass a no-uppercase sample). Transient BSTR + `ZeroFreeBSTR` in `finally`.
- Config schema: `security` block required (`passwordSource` enum `[Generate, Prompt, Ask]`, `passwordGeneration.length` integer min 8 default 20); optional `mustChangeAtNextLogon` boolean default `$true`; `safety.requireManagedGroupOU` boolean default `$false`.
- `tests/Mocks/ActiveDirectory.psm1`: 9 LocalAccounts stubs with `SupportsShouldProcess`.
- Existing config fixtures updated with the `security` block (MEDIUM #5 no-regression).

### Task 2: D-01 create path + D-04 group policy + gate ValidateSet/wrapper extension
- `Resolve-AdmanCreateTarget`: fabricates a synthetic pre-create target (`IsSynthetic=$true`, `objectSid=$null`, `memberOf=@()`, `ParentOuDn`) **without** calling `Get-ADObject -Identity`.
- `Test-AdmanTargetAllowed` create-branch: skips gMSA/deny-RID/protected-membership; runs ONLY managed-OU scope against `ParentOuDn`.
- `Invoke-AdmanMutation`: `New-ADUser` resolver swap; uniqueness pre-flight (`sAMAccountName` + `cn` with `-SearchScope OneLevel`) refuses BEFORE confirm; `Move-ADObject` `TargetPath` managed-OU validator inside the gate; dual-resolution group path (member via `Resolve-AdmanTarget`, group via `Resolve-AdmanGroup`); `-Group` forwarded to `Confirm-AdmanAction` and `Write-AdmanAudit`; try/catch `Failure` audit on wrapper throw (HIGH #1).
- `Resolve-AdmanGroup` + `Test-AdmanGroupAllowed`: direct SID equality for protected-group adds (skipped on Remove — asymmetric remediation); deny-RID applies on both; gMSA objectClass check.
- `Adman.AD.Write.New-ADUser`: consumes `$Parameters['ChangePasswordAtLogon']` with config fallback (no hardcoded `$true`).
- `Adman.AD.Write.Add/Remove-ADGroupMember`: swap `Identity`/`Members`; strip `GroupIdentity` from splat; `ShouldProcess` names both sides.
- `Adman.AD.Write.Set-ADAccountPassword`: splits `ChangePasswordAtLogon` to a follow-up `Set-ADUser` call after the reset (HIGH #4); `Unlock` flag honored after the reset (B5).
- `Adman.AD.Write.Unlock-ADAccount`: honors `$Parameters['Server']` via splat-copy strip (HIGH #3).
- Allow-list drifted 9 → 10 verbs (`New-ADUser`); drift tests updated.

### Task 3: D-02 local gate + D-03 Remove-LocalUser override + audit/confirm extensions + AST guard extension
- `Invoke-AdmanLocalMutation`: mirrors the AD gate byte-for-byte; seven-verb `ValidateSet`; `Resolve-AdmanLocalTarget` swap; `Test-AdmanLocalTargetAllowed` policy; `Adman.Local.Write.*` namespace; uniqueness pre-flight for `New-LocalUser`; TOCTOU closure via `New-LocalUser` throw → `Failure` OUTCOME; HIGH #1 try/catch `Failure` audit.
- `Resolve-AdmanLocalTarget`: localhost-only validation (throws "Remote targets arrive in Phase 3"); `Get-LocalUser` materialization with `LocalRid`; create-branch fabricates synthetic target; D-03 pre-delete state capture (group memberships + profile path) for `Remove-LocalUser`.
- `Test-AdmanLocalTargetAllowed`: (a) RID-500 refuse; (b) local Administrators membership with `Get-LocalGroupMember` + WMI `Win32_GroupUser` fallback on `0x80070534`, fail-closed on total failure; (c) machine-in-scope via `Resolve-AdmanTarget` on `MACHINE$` + `Test-AdmanTargetAllowed`; create-branch skips SID-dependent checks, runs machine-in-scope + name-shape validation.
- `Adman.Local.Write`: seven wrappers; B3 fix strips `ComputerName` from splat; `Add/Remove-LocalGroupMember` strip `Group` and pass explicitly.
- `Confirm-AdmanAction`: threshold override to 1 for `Remove-LocalUser` (typed-count even at count=1); `-Group` parameter renders group in prompt.
- `Write-AdmanAudit`: `-Group` parameter (emitted conditionally, preserving the exact-key-set Test 1 invariant); `-Target` single-object parameter; `MACHINE\username` target shape + `@{machine,name,sid}` detail for local targets; optional `preDeleteState` field; zero banned tokens preserved (Test 2c).
- `rules/AdmanSafetyRules.psm1`: `AdmanBannedLocalWriteVerbs` + `Get-AdmanBannedLocalWriteVerbs`; `Export-ModuleMember` extended.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Case-sensitive password class validation**
- **Found during:** Task 1 (Tests 5c/5d)
- **Issue:** PowerShell `-match` is case-insensitive by default, so `[A-Z]` matched lowercase letters and the no-uppercase test false-passed.
- **Fix:** `Test-AdmanPasswordComplexity` uses `-cnotmatch` for the `[A-Z]`/`[a-z]` class checks, with an explanatory comment.
- **Files modified:** `Private/Utility/Test-AdmanPasswordComplexity.ps1`
- **Commit:** 95ebed9

**2. [Rule 1 - Bug] DenyList fixture type in password tests**
- **Found during:** Task 1 (Test 8)
- **Issue:** `@{ token = '500'; note = '...' }` hashtable entries lack `PSObject.Properties` that the validator checks via `$entry.PSObject.Properties.Name -contains 'token'`.
- **Fix:** Changed the test fixture to `@([pscustomobject]@{ token = '500'; note = 'starter, not exhaustive' })`.
- **Files modified:** `tests/Utility.Password.Tests.ps1`
- **Commit:** 95ebed9

**3. [Rule 3 - Blocking] Module-scope variable visibility in tests**
- **Found during:** Task 1 (Tests 7/8)
- **Issue:** `$script:RepoRoot` inside `& (Get-Module adman) { }` scriptblock couldn't see the test scope.
- **Fix:** Pass as a parameter: `& (Get-Module adman) { param($C, $MR) Test-AdmanConfigValid -Config $C -ModuleRoot $MR } -C $cfg -MR $script:RepoRoot`.
- **Files modified:** `tests/Utility.Password.Tests.ps1`
- **Commit:** 95ebed9

**4. [Rule 1 - Bug] Allow-list drift 9 → 10 verbs**
- **Found during:** Task 2 (full-suite regression)
- **Issue:** `Safety.NoHardDelete.Tests` and `Safety.PreviewEqualsExecute.Tests` asserted exactly 9 verbs/wrappers; adding `New-ADUser` broke the count.
- **Fix:** Updated both assertions to 10 and added `New-ADUser` to the expected set. This is the intended drift — the tests exist to catch *unintentional* drift.
- **Files modified:** `tests/Safety.NoHardDelete.Tests.ps1`, `tests/Safety.PreviewEqualsExecute.Tests.ps1`
- **Commit:** 776f689

**5. [Rule 3 - Blocking] ActiveDirectory mock stubs missing new parameters**
- **Found during:** Task 2 (full-suite regression)
- **Issue:** `New-ADUser` stub lacked `UserPrincipalName`/`Path`/`AccountPassword`/`Enabled`/`ChangePasswordAtLogon`; `Set-ADAccountPassword` stub lacked `Reset`; `Set-ADUser` stub lacked `ChangePasswordAtLogon`. The wrappers pass these, so the stubs threw `ParameterBindingException`.
- **Fix:** Extended the three stubs with the new parameter shapes.
- **Files modified:** `tests/Mocks/ActiveDirectory.psm1`
- **Commit:** 776f689

**6. [Rule 1 - Bug] Test 11 over-mocked Get-LocalUser**
- **Found during:** Task 3 (Local.Gate Test 11)
- **Issue:** The test mocked `Get-LocalUser` to throw ("must NOT run for the create-branch resolver"), but the gate's uniqueness pre-flight *does* call `Get-LocalUser` by design (D-02). The mock was too broad — it conflated the resolver (which must not call it) with the pre-flight (which may).
- **Fix:** Mock returns `$null` (no collision) so the gate proceeds; the assertion targets the create-branch signal on the resolver mock (`-Create` / `-Verb New-LocalUser`) instead of `Get-LocalUser -Times 0`.
- **Files modified:** `tests/Local.Gate.Tests.ps1`
- **Commit:** 6a6d525

**7. [Rule 1 - Bug] Parse error in Local.Gate.Tests.ps1**
- **Found during:** Task 3 (RED run)
- **Issue:** `foreach $cn in ...` missing parentheses.
- **Fix:** `foreach ($cn in ...)`.
- **Files modified:** `tests/Local.Gate.Tests.ps1`
- **Commit:** 601d323

## Auth Gates

None.

## Known Stubs

None. All created/modified files are fully wired; no placeholder data flows to any UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-03 group-membership-add mitigation is implemented as specified).

## Self-Check: PASSED

- All 10 created files exist on disk.
- All 6 commits exist in `git log`: 92d3e74, 95ebed9, 3ab45b3, 776f689, 601d323, 6a6d525.
- Full test suite: 366 passed, 0 failed, 5 skipped (pre-existing skips).
