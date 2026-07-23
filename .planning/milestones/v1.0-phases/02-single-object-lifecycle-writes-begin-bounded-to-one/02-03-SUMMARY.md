---
phase: 02
plan: 03
subsystem: ad-computer-lifecycle-verbs
tags: [computer-lifecycle, comp-02, comp-03, comp-04, move-validation, secure-channel-guidance, tdd, wave-2]
requires:
  - 02-01 cross-cutting gate infrastructure (Move-ADObject TargetPath validator, Set-ADAccountPassword wrapper, Disable/Enable-ADAccount wrappers)
provides:
  - Disable-AdmanComputer (COMP-02 disable through gate)
  - Enable-AdmanComputer (COMP-02 enable through gate)
  - Move-AdmanComputer (COMP-03 managed-OU destination validation before gate)
  - Reset-AdmanComputerAccount (COMP-04 AD-side reset with honest guidance on which method applies)
  - adman.psd1 exports all four computer verbs explicitly (HIGH #2 review fix)
affects:
  - 02-04 (group verbs consume same gate + wrapper pattern)
  - 02-05 (local verbs consume local gate)
  - 02-06 (menu wires all verbs via Read-AdmanActionParams + Start-Adman splat)
tech-stack:
  added: []
  patterns:
    - thin prompt-and-dispatch Public verb (MENU-04)
    - WR-01 init check on every verb
    - managed-OU destination validation via ConvertTo-AdmanNormalizedDn with component-boundary anchor (T-02-08)
    - honest guidance text via Write-PSFMessage -Level Host AND return-object Guidance property (COMP-04)
    - guidance suppressed under -WhatIf (no real mutation occurred)
key-files:
  created:
    - Public/Disable-AdmanComputer.ps1
    - Public/Enable-AdmanComputer.ps1
    - Public/Move-AdmanComputer.ps1
    - Public/Reset-AdmanComputerAccount.ps1
    - tests/Computer.Disable.Tests.ps1
    - tests/Computer.Move.Tests.ps1
    - tests/Computer.Reset.Tests.ps1
  modified:
    - adman.psd1 (FunctionsToExport gains four computer verbs)
decisions:
  - Computer objects are AD security principals; Disable/Enable-AdmanComputer reuse the exact same Disable-ADAccount / Enable-ADAccount wrappers as the user path (no computer-specific wrapper needed)
  - Reset-AdmanComputerAccount emits guidance via Write-PSFMessage -Level Host (NOT Write-Host — the CLAUDE.md PSAvoidUsingWriteHost suppression covers ONLY the TUI-rendering module) AND surfaces the same text on the return object's Guidance property so pipeline callers can render it
  - Guidance is suppressed under -WhatIf because no real mutation occurred and there is no broken channel to recover from
  - The return object is a fresh PSCustomObject carrying Target/Verb/WhatIf/GateResult/Guidance; the gate's own return is preserved under GateResult for callers that need it
metrics:
  duration: ~4m
  completed: 2026-07-16
  tasks: 2
  tests-added: 22 (14 disable/move + 8 reset)
  tests-passing: 425
  tests-failing: 0
status: complete
---

# Phase 02 Plan 03: AD Computer Lifecycle Verbs Summary

**One-liner:** Four AD computer lifecycle Public verbs (COMP-02/03/04) shipped as thin prompt-and-dispatch wrappers over the Plan 02-01 gate infrastructure — disable/enable reusing the same Disable-ADAccount / Enable-ADAccount wrappers as the user path (computer objects are AD security principals), move with managed-OU destination validation, and AD-side reset with honest guidance naming both the AD-side "Reset Account" and the on-machine Test-ComputerSecureChannel -Repair runbook step — all exported explicitly in adman.psd1.

## What Was Built

### Task 1: Disable/Enable/Move-AdmanComputer + manifest export (COMP-02, COMP-03)
- `Disable-AdmanComputer` / `Enable-AdmanComputer`: thin prompt-and-dispatch routing through `Invoke-AdmanMutation` with `-Verb Disable-ADAccount` / `Enable-ADAccount`. Computer objects are AD security principals; the same wrappers serve both user and computer targets. `-Force` forwarded; WR-01 init check.
- `Move-AdmanComputer`: validates `-TargetPath` under managed roots BEFORE the gate call via `ConvertTo-AdmanNormalizedDn` with component-boundary anchor (`$t -eq $r -or $t.EndsWith(',' + $r)`); throws precise out-of-scope message (T-02-08 mitigation). Calls `Invoke-AdmanMutation -Verb 'Move-ADObject'` with `$Parameters['TargetPath']` when in scope.
- `adman.psd1` `FunctionsToExport` gains the three verbs (HIGH #2 review fix — Wave 2 tests import the manifest and call the exported functions directly).
- `tests/Computer.Disable.Tests.ps1` + `tests/Computer.Move.Tests.ps1`: 14 contract tests covering gate routing, parameter shape, WR-01 init, destination validation (incl. sibling-OU component-boundary refusal), and manifest export.

### Task 2: Reset-AdmanComputerAccount + manifest export (COMP-04)
- `Reset-AdmanComputerAccount`: routes through `Invoke-AdmanMutation -Verb 'Set-ADAccountPassword'` with `$Parameters['Reset']=$true` (AD-side "Reset Account", the ADUC equivalent). `-Force` forwarded; WR-01 init check.
- Honest guidance (COMP-04 requirement): after the gate call returns (and NOT under `-WhatIf`), emits the guidance text via `Write-PSFMessage -Level Host` (the established diagnostic pattern — `Write-Host` would trip the lint gate; the CLAUDE.md `PSAvoidUsingWriteHost` suppression covers ONLY the TUI-rendering module) AND attaches it to the return object's `Guidance` property so pipeline callers can surface it. The guidance names BOTH methods (AD-side reset AND on-machine `Test-ComputerSecureChannel -Repair`) and states the trade-off (the AD-side reset breaks the secure channel until rejoin/repair).
- Return shape: fresh `PSCustomObject` carrying `Target`, `Verb`, `WhatIf`, `GateResult`, `Guidance`. The gate's own return is preserved under `GateResult`.
- `adman.psd1` `FunctionsToExport` gains the verb (HIGH #2 review fix).
- `tests/Computer.Reset.Tests.ps1`: 8 contract tests covering gate routing, `Reset=$true` shape, `-Force` forward, WR-01 init, guidance content (both `Write-PSFMessage` AND the `Guidance` property), `-WhatIf` suppression, and manifest export.

## Deviations from Plan

None — plan executed exactly as written.

## Auth Gates

None.

## Known Stubs

None. All created/modified files are fully wired; no placeholder data flows to any UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-08 move destination validation implemented as specified; T-02-09 secure-channel break accepted with the COMP-04 guidance text naming the recovery path).

## TDD Gate Compliance

- **RED gate:** Test files were authored first and confirmed failing (14 fail for Task 1, 8 fail for Task 2) before the verbs were written. Tests were committed in the same atomic per-task commit as the verbs (standard GSD TDD pattern for this repo).
- **GREEN gate:** `feat(02-03)` commits b6a9809 and e9e9115 land the tests green.
- **REFACTOR gate:** Not applicable — no refactoring needed beyond the initial implementation.

## Self-Check: PASSED

- All 4 created Public verb files exist on disk: `Public/Disable-AdmanComputer.ps1`, `Public/Enable-AdmanComputer.ps1`, `Public/Move-AdmanComputer.ps1`, `Public/Reset-AdmanComputerAccount.ps1`.
- All 3 created test files exist on disk: `tests/Computer.Disable.Tests.ps1`, `tests/Computer.Move.Tests.ps1`, `tests/Computer.Reset.Tests.ps1`.
- `adman.psd1` modified and exports all four computer verbs.
- Both commits exist in `git log`: b6a9809, e9e9115.
- Plan-level verification: 22/22 green across the 3 new test files.
- Full unit suite: 425 passed, 0 failed, 9 not run (pre-existing integration skips).
