---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
plan: 07
subsystem: safety
tags: [safety, confirmation, shouldprocess, regression-test, gap-closure]
requires:
  - 02-01 (mutation gate Invoke-AdmanMutation)
  - 02-02 (Public mutation verbs)
  - 02-06 (menu wiring)
provides:
  - SAFE-01/SAFE-02 confirmation prompt restored on the cmdlet path
  - G-02-5 gap closure
  - Regression test suite preventing re-introduction of -Confirm:$false forwarding
affects:
  - All 17 Public mutation verb files (20 call sites)
  - tests/Safety.ConfirmationRestored.Tests.ps1 (new)
tech-stack:
  added: []
  patterns:
    - AST-based source assertion (REV-4) for robust regression testing
    - Real Confirm-AdmanAction used in Test 2/4 to prove end-to-end behavior
key-files:
  created:
    - tests/Safety.ConfirmationRestored.Tests.ps1
  modified:
    - Public/Disable-AdmanUser.ps1
    - Public/Enable-AdmanUser.ps1
    - Public/Move-AdmanUser.ps1
    - Public/Set-AdmanUserPassword.ps1
    - Public/Unlock-AdmanUser.ps1
    - Public/Disable-AdmanComputer.ps1
    - Public/Enable-AdmanComputer.ps1
    - Public/Move-AdmanComputer.ps1
    - Public/Reset-AdmanComputerAccount.ps1
    - Public/New-AdmanUser.ps1
    - Public/New-AdmanLocalUser.ps1
    - Public/Set-AdmanLocalUser.ps1
    - Public/Remove-AdmanLocalUser.ps1
    - Public/Add-AdmanLocalGroupMember.ps1
    - Public/Remove-AdmanLocalGroupMember.ps1
    - Public/Add-AdmanGroupMember.ps1
    - Public/Remove-AdmanGroupMember.ps1
decisions:
  - Test 2 uses the real Confirm-AdmanAction (not a mock) because Pester -ModuleName mock bodies do not preserve the caller's $ConfirmPreference via dynamic scope (verified by probe). The test proves the behavior (mutation proceeds without prompt) rather than capturing the inherited value.
  - Test 5 is AST-based (REV-4) so it is robust to line-continuation formatting changes.
  - Test 6 counter-asserts that Private wrappers still carry -Confirm:$false, proving Task 1 did not touch them.
metrics:
  duration: "~10m (Task 1 pre-existing; Task 2 test fix + validation)"
  completed: 2026-07-16
status: complete
---

# Phase 02 Plan 07: Restore ShouldProcess Confirmation on the Cmdlet Path Summary

**One-liner:** Removed unconditional `-Confirm:$false` forwarding from all 20 Public mutation call sites and added a 6-test Pester regression suite proving the ShouldProcess prompt is restored.

## Objective

Restore the core safety property (SAFE-01/SAFE-02) on the cmdlet path by removing the unconditional `-Confirm:$false` forwarding at every Public mutation verb call site. The forwarding set `$ConfirmPreference='None'` inside the gate via dynamic scope, collapsing the prompt condition at `Confirm-AdmanAction.ps1:81` and silently disarming confirmation for all 20 mutation call sites — including the typed-count branch for `Remove-LocalUser` (D-03).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Remove `-Confirm:$false` from all 17 Public mutation verb files (20 call sites) | `9b0e5a6` | 17 Public/*.ps1 files |
| 2 | Pester regression test proving plain-cmdlet invocation prompts | `d01c8f4` | tests/Safety.ConfirmationRestored.Tests.ps1 |

## Verification Results

### Task 1: AST-based source assertion (REV-4)

```
CLEAN: no -Confirm:$false on Invoke-AdmanMutation/Invoke-AdmanLocalMutation in Public/*.ps1 (excluding Public/Config/*)
```

Counter-assertion: `Private/AD/Adman.AD.Write.ps1` (11 occurrences) and `Private/Local/Adman.Local.Write.ps1` (8 occurrences) still contain `-Confirm:$false` — the post-confirm suppression is intact.

### Task 2: Pester regression suite

```
Tests Passed: 6, Failed: 0
```

All 6 tests pass:
- Test 1: Disable-AdmanUser plain invocation -> Confirm-AdmanAction sees $ConfirmPreference -ne 'None'
- Test 2: caller-side -Confirm:$false still bypasses the prompt (dynamic scope inheritance preserved)
- Test 3: caller-side -Force still bypasses the prompt
- Test 4: Remove-AdmanLocalUser plain invocation reaches the typed-count branch (D-03); exact-count token accepted
- Test 5 (REV-4, AST): no Public verb forwards -Confirm:$false into Invoke-AdmanMutation / Invoke-AdmanLocalMutation
- Test 6 (REV-4 counter-assertion): Private wrappers STILL carry -Confirm:$false (post-confirm suppression intact)

### Full unit suite

```
Tests Passed: 442, Failed: 4, NotRun: 10
Container failed: 1 (Menu.Tests.ps1 — pre-existing parse error)
```

The 4 failures are pre-existing and documented in `.continue-here.md`:
1. SAFE-04: Write-AdmanAudit fail-closed write-ahead behavior.static
2. adman safety harness (SAFE-01 / SAFE-08).lint is clean
3. D-02/D-03: Invoke-AdmanLocalMutation.Test 12
4. SAFE-08: Invoke-AdmanMutation.Test 18 (HIGH #4)

No new failures introduced by this plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test 2 mock captured wrong $ConfirmPreference value**
- **Found during:** Task 2 validation
- **Issue:** The original Test 2 mocked `Confirm-AdmanAction` and captured `$ConfirmPreference` in the mock body. The mock body saw 'High' instead of the expected 'None' because Pester's `-ModuleName` mock machinery runs the mock body in a fresh scope that does NOT preserve the caller's `$ConfirmPreference` via dynamic scope (verified by independent probe).
- **Fix:** Rewrote Test 2 to use the REAL `Confirm-AdmanAction` (not mocked). The test now proves the behavior — the mutation completes without prompting and the wrapper is called exactly once — rather than capturing the inherited value. This is a stronger end-to-end proof.
- **Files modified:** tests/Safety.ConfirmationRestored.Tests.ps1
- **Commit:** d01c8f4

## Threat Model Mitigations Applied

| Threat ID | Mitigation |
|-----------|------------|
| T-02-07-01 (Tampering) | This plan IS the mitigation. Removed `-Confirm:$false` forwarding; Test 5 prevents re-introduction. |
| T-02-07-02 (Elevation of Privilege) | Restored dynamic-scope inheritance re-arms the prompt condition. Tests 1-3 prove the three states. |
| T-02-07-03 (Repudiation) | Test 4 proves the typed-count branch (D-03) is reachable again for Remove-AdmanLocalUser. |

## Known Stubs

None.

## Threat Flags

None — no new security-relevant surface introduced.

## Self-Check: PASSED

- [x] FOUND: 9b0e5a6 (Task 1 commit)
- [x] FOUND: d01c8f4 (Task 2 commit)
- [x] FOUND: tests/Safety.ConfirmationRestored.Tests.ps1
- [x] All 6 regression tests pass
- [x] Full unit suite: no new failures (442 passed, 4 pre-existing failed, 1 pre-existing container failure)
