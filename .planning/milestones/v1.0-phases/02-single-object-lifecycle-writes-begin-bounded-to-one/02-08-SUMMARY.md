---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
plan: 08
subsystem: audit
tags: [audit, strict-mode, fail-closed, synthetic-target, create-flow, gap-closure]
gap_closure: true
closes_gaps: [G-02-3]
requirements: [USER-02]
dependency_graph:
  requires:
    - Private/Audit/Write-AdmanAudit.ps1 (pre-existing, modified)
    - Private/Safety/Resolve-AdmanCreateTarget.ps1 (synthetic target shape)
    - Private/Audit/AdmanAuditIO.ps1 (I/O seams for fail-closed test)
    - tests/Audit.Schema.Tests.ps1 (BeforeAll pattern reference)
  provides:
    - Write-AdmanAudit AD-target branch tolerates objectSid=$null (synthetic pre-create targets)
    - Write-AdmanAudit AD-target branch tolerates missing objectSid property (mocks/deserialized)
    - Pester regression suite proving G-02-3 closed and D-01 fail-closed preserved
  affects:
    - New-AdmanUser create flow (USER-02) — unblocked; PENDING write no longer throws on null objectSid
    - Any future create-verb using Resolve-AdmanCreateTarget (New-ADComputer, local creates)
tech_stack:
  added: []
  patterns:
    - Property-existence-first guard pattern under Set-StrictMode -Version Latest
    - Null/type-aware SID extraction (null / SecurityIdentifier / string)
key_files:
  created:
    - tests/Audit.CreateFlowStrictMode.Tests.ps1
  modified:
    - Private/Audit/Write-AdmanAudit.ps1
decisions:
  - "Guarded SID extraction uses property-existence-first check (`$t.PSObject.Properties['objectSid']`) BEFORE any `.objectSid` read — under StrictMode Latest, reading a missing property throws before any null check can run"
  - "Three-case value handling: $null -> sid=$null; [SecurityIdentifier] -> .Value; string -> [string] cast (never `.Value` on a string)"
  - "Fix is a defensive null/type guard, NOT a relaxation of fail-closed — genuine I/O failures on the PENDING write still throw 'AUDIT FAIL-CLOSED' and refuse the mutation"
metrics:
  duration: "~7m"
  completed: 2026-07-16
status: complete
---

# Phase 02 Plan 08: Unblock Create Flow — Guarded SID Extraction in Write-AdmanAudit Summary

**One-liner:** Replaced the unguarded `($t.objectSid.Value)` dereference in Write-AdmanAudit's AD-target branch with a property-existence-first, null/type-aware guarded extraction, unblocking New-AdmanUser (G-02-3) while preserving the fail-closed invariant.

## Objective

UAT Test 3 showed `New-AdmanUser` dead: for create-verbs the audit target is fabricated by `Resolve-AdmanCreateTarget` BEFORE the AD object exists, so `objectSid` is `$null`. Under `Set-StrictMode -Version Latest`, the expression `($t.objectSid.Value)` at `Write-AdmanAudit.ps1:78` threw "The property 'Value' cannot be found on this object", the PENDING write failed, and the fail-closed catch refused `New-ADUser`. The fix is a defensive null/type check, NOT a relaxation of fail-closed.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Defensive SID extraction in Write-AdmanAudit AD-target branch | d26cce7 | Private/Audit/Write-AdmanAudit.ps1 |
| 2 | Pester test proving synthetic-target PENDING write succeeds under StrictMode | eb23678 | tests/Audit.CreateFlowStrictMode.Tests.ps1 |

## Verification Results

**Task 1 automated check (source assertion):**
- Literal string `.objectSid.Value` does NOT appear anywhere in the file: PASS
- Property-existence guard `PSObject.Properties['objectSid']` present: PASS

**Task 2 Pester suite (tests/Audit.CreateFlowStrictMode.Tests.ps1):**
```
Tests Passed: 5, Failed: 0
```
- Test 1: synthetic pre-create target (objectSid=$null) writes PENDING without throwing under StrictMode; targets[0].sid is $null — G-02-3 CLOSED
- Test 2: existing-AD-object target (real SecurityIdentifier) still writes PENDING; sid string preserved — no regression
- Test 3: local target (Machine+Name+SID) still writes PENDING; sid string preserved — no regression
- Test 4: fail-closed preserved — Open-AdmanAuditStream throw -> 'AUDIT FAIL-CLOSED' — D-01 invariant intact
- Test 5: AD-shaped target WITHOUT objectSid property writes PENDING without throwing — REV-2 regression guard

**Full unit suite (`Invoke-Pester -Path tests/ -Tag 'Unit'`):**
```
Tests Passed: 447, Failed: 4, NotRun: 10
Container failed: 1 (Menu.Tests.ps1 — pre-existing parse error)
```

The 4 failures are pre-existing and documented in `.continue-here.md` (same set as 02-07):
1. SAFE-04: Write-AdmanAudit fail-closed write-ahead behavior.static
2. adman safety harness (SAFE-01 / SAFE-08).lint is clean
3. D-02/D-03: Invoke-AdmanLocalMutation.Test 12
4. SAFE-08: Invoke-AdmanMutation.Test 18 (HIGH #4)

No new failures introduced by this plan. Pass count rose from 442 (02-07) to 447 (the +5 is the new test file).

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new security-relevant surface introduced. The fix REMOVES a StrictMode throw that was blocking the audit trail for creates (T-02-08-01 mitigated). The fail-closed catch block is byte-identical to before (T-02-08-02 verified by Test 4).

## Known Stubs

None.

## Self-Check: PASSED

- [x] `Private/Audit/Write-AdmanAudit.ps1` modified — FOUND
- [x] `tests/Audit.CreateFlowStrictMode.Tests.ps1` created — FOUND
- [x] Commit d26cce7 (Task 1) — FOUND in git log
- [x] Commit eb23678 (Task 2) — FOUND in git log
- [x] Source assertion: `.objectSid.Value` absent, `PSObject.Properties['objectSid']` present — PASS
- [x] All 5 new tests pass — PASS
- [x] Full unit suite: no new failures beyond 4 pre-existing + Menu.Tests parse error — PASS
