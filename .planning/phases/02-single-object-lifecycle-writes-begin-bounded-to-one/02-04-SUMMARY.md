---
phase: 02
plan: 04
subsystem: local-user-group-lifecycle-verbs
tags: [local-user, local-group, lusr-01, lusr-02, d-02, d-03, d-05, tdd, wave-2]
requires:
  - 02-01 cross-cutting gate infrastructure (Invoke-AdmanLocalMutation, Resolve-AdmanLocalTarget, Test-AdmanLocalTargetAllowed, Adman.Local.Write.* wrappers, D-05 password plumbing)
provides:
  - New-AdmanLocalUser (LUSR-01 create through local gate with D-05 password sourcing)
  - Set-AdmanLocalUser (LUSR-01 password reset + enable/disable through local gate; three parameter sets)
  - Remove-AdmanLocalUser (LUSR-01 remove through local gate with D-03 typed-count + pre-delete state capture)
  - Add-AdmanLocalGroupMember (LUSR-02 local group membership add through local gate)
  - Remove-AdmanLocalGroupMember (LUSR-02 local group membership remove through local gate)
  - adman.psd1 exports all five local verbs explicitly (HIGH #2 review fix)
affects:
  - 02-06 (menu wires the five local verbs via Read-AdmanActionParams + Start-Adman splat)
  - Phase 3 (verb signatures stable for the transport ladder; -ComputerName validation widens)
tech-stack:
  added: []
  patterns:
    - thin prompt-and-dispatch Public verb (MENU-04)
    - WR-01 init check on every verb
    - Phase 2 localhost validation (accept $null, '.', $env:COMPUTERNAME, 'localhost'; throw "Remote targets arrive in Phase 3" otherwise)
    - D-05 per-call password source detection ($PasswordSource explicit menu marker wins, $PSBoundParameters heuristic fallback)
    - D-05 display-once hygiene (BSTR + ZeroFreeBSTR in finally, [Console]::Clear best-effort for headless hosts)
    - three parameter sets on Set-AdmanLocalUser ('Reset' / 'Enable' / 'Disable') with parameter-set resolution error on bare call (no silent no-op)
key-files:
  created:
    - Public/New-AdmanLocalUser.ps1
    - Public/Set-AdmanLocalUser.ps1
    - Public/Remove-AdmanLocalUser.ps1
    - Public/Add-AdmanLocalGroupMember.ps1
    - Public/Remove-AdmanLocalGroupMember.ps1
    - tests/Local.User.Tests.ps1
    - tests/Local.Group.Tests.ps1
  modified:
    - adman.psd1 (FunctionsToExport gains five local verbs)
decisions:
  - D-02 localhost validation: accept $null, '.', $env:COMPUTERNAME, 'localhost'; throw "Remote targets arrive in Phase 3. -ComputerName '<x>' is not localhost." otherwise; verb signatures stable for Phase 3's transport ladder
  - D-03 Remove-AdmanLocalUser help text states plainly "IRREVERSIBLE. Local accounts have no Recycle Bin or quarantine OU equivalent."; relies on the gate's Confirm-AdmanAction per-verb threshold override (Remove-LocalUser -> 1) for typed-count confirmation even at count=1; pre-delete state captured in the audit record via Resolve-AdmanLocalTarget's PreDeleteState property
  - D-05 per-call password source detection: $PasswordSource explicit menu marker wins, $PSBoundParameters heuristic ('Prompt' when -Password supplied) fallback, config 'Generate' default; 'Ask' defaults to 'Generate' for direct callers
  - HIGH #1 cycle-2 review fix: New-AdmanLocalUser declares [ValidateSet('Generate','Prompt')][string]$PasswordSource; Set-AdmanLocalUser declares it on the 'Reset' parameter set; without the declared parameters the menu splat (& $Verb @params) throws "parameter cannot be found"
  - HIGH #2 review fix: adman.psd1 FunctionsToExport gains the five local verbs in THIS plan (not deferred to 02-06) so Wave 2 tests can import the manifest and call the exported functions directly
  - Set-AdmanLocalUser parameter-set resolution: bare call with neither -Password nor -Enable/-Disable throws "Parameter set cannot be resolved: supply -Password, -Enable, or -Disable." (no silent no-op); -Enable and -Disable are mutually exclusive (different sets); PasswordSource bound to the 'Reset' set so it cannot combine with -Enable/-Disable
metrics:
  duration: ~7m
  completed: 2026-07-16
  tasks: 2
  tests-added: 26 (17 local-user + 9 local-group)
  tests-passing: 451
  tests-failing: 0
status: complete
---

# Phase 02 Plan 04: Local User/Group Lifecycle Verbs Summary

**One-liner:** Five local (per-machine) user/group lifecycle Public verbs (LUSR-01/02) shipped as thin prompt-and-dispatch wrappers over the Plan 02-01 local gate — create with D-05 password sourcing, password reset + enable/disable via three parameter sets, remove with D-03 typed-count + pre-delete state capture, and local group membership add/remove — all exported explicitly in adman.psd1.

## What Was Built

### Task 1: New/Set/Remove-AdmanLocalUser + manifest export (LUSR-01)
- `New-AdmanLocalUser`: routes through `Invoke-AdmanLocalMutation -Verb 'New-LocalUser'`; the gate's create-branch fabricates a synthetic local target (no `Get-LocalUser` lookup), runs machine-in-scope + name-shape validation only, performs the uniqueness pre-flight (zero hits = available), and closes TOCTOU via `New-LocalUser`'s own collision throw with a `Failure` OUTCOME audit record. D-05 password sourcing identical to `New-AdmanUser` (Generate default via `New-AdmanRandomPassword`, Prompt via `Read-Host -AsSecureString` + `Test-AdmanPasswordComplexity`); D-05 display-once hygiene (BSTR + `ZeroFreeBSTR` in `finally`, `[Console]::Clear()` best-effort for headless hosts); declares `[ValidateSet('Generate','Prompt')][string]$PasswordSource` (HIGH #1 cycle-2 review fix — menu splat contract).
- `Set-AdmanLocalUser`: three parameter sets — `'Reset'` (Name + Password [+ PasswordSource]) routes to `'Set-LocalUser'` for password reset with D-05 sourcing; `'Enable'` (Name + Enable) routes to `'Enable-LocalUser'`; `'Disable'` (Name + Disable) routes to `'Disable-LocalUser'`. Enable and Disable are mutually exclusive (different sets). Password cannot combine with Enable/Disable. PasswordSource bound to the `'Reset'` set. Bare call with neither `-Password` nor `-Enable`/`-Disable` throws the parameter-set resolution error (no silent no-op). Declares `PasswordSource` on the `'Reset'` set (HIGH #1 cycle-2 review fix).
- `Remove-AdmanLocalUser`: routes through the local gate with `-Verb 'Remove-LocalUser'`; help text states plainly "IRREVERSIBLE. Local accounts have no Recycle Bin or quarantine OU equivalent." (D-03); relies on the gate's `Confirm-AdmanAction` per-verb threshold override (`Remove-LocalUser` -> 1) for typed-count confirmation even at count=1; pre-delete state (local SID, name, group memberships, profile path) captured in the audit record via `Resolve-AdmanLocalTarget`'s `PreDeleteState` property.
- All three verbs validate `-ComputerName` to localhost in Phase 2 (accept `$null`, `'.'`, `$env:COMPUTERNAME`, `'localhost'`; throw "Remote targets arrive in Phase 3" otherwise); WR-01 init check; declare `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]`.
- `adman.psd1` `FunctionsToExport` gains the three verbs (HIGH #2 review fix).
- `tests/Local.User.Tests.ps1`: 17 contract tests covering gate routing, parameter shape, D-05 sourcing, parameter-set resolution + conflict, localhost validation, WR-01 init, irreversibility help text, manifest export, menu-splat contract.

### Task 2: Add/Remove-AdmanLocalGroupMember + manifest export (LUSR-02)
- `Add-AdmanLocalGroupMember`: routes through `Invoke-AdmanLocalMutation -Verb 'Add-LocalGroupMember'`; `$Parameters` contains `Group` and `ComputerName`; `-Force` forwarded. The local gate's policy checks apply (RID-500 refusal, local-Administrators membership check with orphaned-SID tolerance, machine-in-scope).
- `Remove-AdmanLocalGroupMember`: routes through `Invoke-AdmanLocalMutation -Verb 'Remove-LocalGroupMember'`; `$Parameters` contains `Group` and `ComputerName`; `-Force` forwarded.
- Both verbs validate `-ComputerName` to localhost; WR-01 init check; declare `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]`.
- `adman.psd1` `FunctionsToExport` gains the two verbs (HIGH #2 review fix).
- `tests/Local.Group.Tests.ps1`: 9 contract tests covering gate routing, parameter shape, localhost validation, WR-01 init, `-Force` forwarding, manifest export.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test 3 contradicted the parameter-set resolution test**
- **Found during:** Task 1 (GREEN run)
- **Issue:** The plan's Test 3 called `Set-AdmanLocalUser -Name 'luser'` with no `-Password`, expecting the verb to source the password per D-05 and call `Set-LocalUser`. But the plan's parameter-set test called the exact same bare invocation expecting a "supply -Password, -Enable, or -Disable" throw. The two tests contradicted each other.
- **Fix:** Resolved in favor of the parameter-set resolution invariant (the plan's explicit "no silent no-op" requirement). Test 3 now supplies `-PasswordSource 'Generate'` explicitly (the menu-path way) to request D-05 sourcing on the Reset set; the bare call throws the parameter-set resolution error as specified.
- **Files modified:** `tests/Local.User.Tests.ps1`
- **Commit:** 06a69fe

## Auth Gates

None.

## Known Stubs

None. All created/modified files are fully wired; no placeholder data flows to any UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-02 password handling, T-02-05 protected local accounts, T-02-06 orphaned-SID tolerance, T-02-10 Remove-LocalUser irreversibility — all mitigated as specified).

## TDD Gate Compliance

- **RED gate:** Test files authored first and confirmed failing (16 fail for Task 1, 9 fail for Task 2) before the verbs were written. Tests committed in the same commit as the verbs (atomic per-task commit), the standard GSD TDD pattern for this repo.
- **GREEN gate:** `feat(02-04)` commits 06a69fe and 2a44d9f exist after the RED state and land the tests green.
- **REFACTOR gate:** Not applicable — no refactoring needed beyond the initial implementation.

## Self-Check: PASSED

- All 5 created Public verb files exist on disk.
- All 2 created test files exist on disk.
- `adman.psd1` modified and exports all five verbs.
- All 2 commits exist in `git log`: 06a69fe, 2a44d9f.
- Plan-level verification: 26/26 green across the 2 new test files.
- Full unit suite: 451 passed, 0 failed, 9 not run (pre-existing integration skips).
