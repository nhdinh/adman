---
phase: 02
plan: 05
subsystem: ad-group-membership-verbs
tags: [group-membership, d-04, dual-resolution, protected-group, asymmetric-remediation, tdd, wave-2]
requires:
  - 02-01 cross-cutting gate infrastructure (Resolve-AdmanGroup, Test-AdmanGroupAllowed, dual-resolution group path in Invoke-AdmanMutation, Write-AdmanAudit -Group field)
provides:
  - Add-AdmanGroupMember (GRP-01 add member to group through gate with D-04 dual resolution)
  - Remove-AdmanGroupMember (GRP-02 remove member from group through gate with D-04 dual resolution)
  - GRP-03 protected-group refusal enforced by the gate (direct SID equality, NOT IN_CHAIN)
  - D-04 asymmetric remediation (Remove skips protected-SID check; member-side checks still apply)
  - adman.psd1 exports both group verbs explicitly (HIGH #2 review fix)
affects:
  - 02-06 (menu wires all verbs via Read-AdmanActionParams + Start-Adman splat)
tech-stack:
  added: []
  patterns:
    - thin prompt-and-dispatch Public verb (MENU-04)
    - WR-01 init check on every verb
    - D-04 dual-resolution group path (member via Resolve-AdmanTarget, group via Resolve-AdmanGroup)
    - direct SID equality for protected-group adds (NOT IN_CHAIN)
    - asymmetric remediation (Remove skips protected-SID check)
key-files:
  created:
    - Public/Add-AdmanGroupMember.ps1
    - Public/Remove-AdmanGroupMember.ps1
    - tests/Group.Add.Tests.ps1
    - tests/Group.Remove.Tests.ps1
    - tests/Group.Protected.Tests.ps1
  modified:
    - adman.psd1 (FunctionsToExport gains the two group verbs)
decisions:
  - D-04 dual-resolution policy matrix enforced by the gate; the Public verbs are thin prompt-and-dispatch wrappers that build $Parameters['GroupIdentity'] and call Invoke-AdmanMutation
  - GRP-03 protected-group refusal is a gate-side invariant (Test-AdmanGroupAllowed direct SID equality), not a Public-verb check — direct gate callers cannot bypass it
  - D-04 asymmetry: Remove skips the group-side protected-SID check (remediation allowed); deny-RID and gMSA checks still apply on both Add and Remove; member-side checks unchanged
metrics:
  duration: ~4m
  completed: 2026-07-16
  tasks: 1
  tests-added: 11 (4 add + 4 remove + 3 protected/asymmetry/audit-shape)
  tests-passing: 462
  tests-failing: 0
status: complete
---

# Phase 02 Plan 05: AD Group Membership Verbs Summary

**One-liner:** Two AD group-membership Public verbs (GRP-01/02/03) shipped as thin prompt-and-dispatch wrappers over the Plan 02-01 D-04 dual-resolution gate path — Add refuses protected groups by direct SID equality, Remove allows protected-group remediation (asymmetry), the audit record names both member DN and group DN, and both verbs are exported explicitly in adman.psd1.

## What Was Built

### Task 1: Add/Remove-AdmanGroupMember (GRP-01/02/03) + manifest export
- `Add-AdmanGroupMember`: thin prompt-and-dispatch Public verb. WR-01 init check; builds `$params = @{ GroupIdentity = $GroupIdentity }`; calls `Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @($Identity) -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false`. Comment-based help documents the D-04 dual-resolution matrix (member-side checks unchanged; group-side refuses protected/deny-listed/gMSA groups on Add).
- `Remove-AdmanGroupMember`: identical shape but `-Verb 'Remove-ADGroupMember'`; `.DESCRIPTION` documents the D-04 asymmetry — removing a principal FROM a protected group is allowed as remediation (member-side checks still apply; group-side protected check is skipped).
- `adman.psd1` `FunctionsToExport` gains `'Add-AdmanGroupMember'` and `'Remove-AdmanGroupMember'` explicitly (HIGH #2 review fix — Wave 2 tests import the manifest and call the exported functions directly).
- `tests/Group.Add.Tests.ps1` (4 tests): gate routing with `-Verb 'Add-ADGroupMember'` + `$Parameters['GroupIdentity']`; WR-01 init throw; `-Force` forwarding; manifest export.
- `tests/Group.Remove.Tests.ps1` (4 tests): gate routing with `-Verb 'Remove-ADGroupMember'` + `$Parameters['GroupIdentity']`; WR-01 init throw; `-Force` forwarding; manifest export.
- `tests/Group.Protected.Tests.ps1` (3 tests): end-to-end gate dual-resolution path with module-scope mocks —
  - Test 3 (GRP-03): mocks `Resolve-AdmanGroup` to return a group whose `objectSid` is in `$script:ProtectedSIDs`, mocks `Test-AdmanGroupAllowed` to return `Allowed=$false` with reason matching 'protected identity'; asserts the gate throws, writes a `'Refused'` audit record, and NEVER calls the write wrapper.
  - Test 4 (D-04 asymmetry): mocks `Test-AdmanGroupAllowed` to return `Allowed=$true` (protected check skipped on Remove); asserts the write wrapper IS called exactly once.
  - Test 5 (audit shape): asserts the `Write-AdmanAudit` mock receives `-Group 'CN=Mock Group,...'` alongside `-Targets` carrying the member DN.

## Deviations from Plan

None — plan executed exactly as written.

## Auth Gates

None.

## Known Stubs

None. All created/modified files are fully wired; no placeholder data flows to any UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-03 protected-group add refusal is implemented as specified; T-02-04 dual-side audit naming is implemented as specified).

## TDD Gate Compliance

- **RED gate:** Test files authored first and confirmed failing (11 fail: `CommandNotFoundException` for both verbs) before the verbs were written. Tests were committed in the same commit as the verbs (atomic per-task commit), which is the standard GSD TDD pattern for this repo.
- **GREEN gate:** `feat(02-05)` commit `56fbf0d` lands the verbs and the tests pass (11/11 green).
- **REFACTOR gate:** Not applicable — no refactoring needed beyond the initial implementation.

## Self-Check: PASSED

- All 2 created Public verb files exist on disk: `Public/Add-AdmanGroupMember.ps1`, `Public/Remove-AdmanGroupMember.ps1`.
- All 3 created test files exist on disk: `tests/Group.Add.Tests.ps1`, `tests/Group.Remove.Tests.ps1`, `tests/Group.Protected.Tests.ps1`.
- `adman.psd1` modified and exports both verbs explicitly.
- Commit `56fbf0d` exists in `git log`.
- Plan-level verification: 11/11 green across the 3 new test files.
- Full unit suite: 462 passed, 0 failed, 9 not run (pre-existing integration skips).
