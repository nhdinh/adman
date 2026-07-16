---
phase: 02
plan: 06
subsystem: menu-integration-phase-exit-gate
tags: [menu, d-05, fixedparameters, promptspec-contract, ast-guard, phase-exit, wave-3]
requires:
  - 02-02 AD user verbs (New/Disable/Enable/Set-AdmanUserPassword/Unlock/Move-AdmanUser)
  - 02-03 AD computer verbs (Disable/Enable/Move-AdmanComputer, Reset-AdmanComputerAccount)
  - 02-04 local user/group verbs (New/Set/Remove-AdmanLocalUser, Add/Remove-AdmanLocalGroupMember)
  - 02-05 AD group membership verbs (Add/Remove-AdmanGroupMember)
provides:
  - Start-Adman menu lists every Phase 2 write verb with section grouping (Search / Reports / User writes / Computer writes / Local writes / Group membership)
  - Read-AdmanActionParams polymorphic Type dispatch (GeneratedPassword / Text) with D-05 Generate/Prompt sub-choice
  - FixedParameters declarative parameter injection (MEDIUM #6 review fix)
  - PromptSpec-parameter-name contract test (HIGH #1 cycle-2 review fix — menu/verb drift caught at test time)
  - adman.psd1 17-verb export re-verification (HIGH #2 review fix)
  - SAFE-08/09 AST guard re-proof against the expanded Public/ tree
affects:
  - Phase 3 (remoting transport widens -ComputerName validation; menu shape stable)
  - Phase 4 (bulk/workflows reuse the same menu + prompt engine)
tech-stack:
  added: []
  patterns:
    - non-selectable section separator entries (Verb=$null rendered as plain text, not numbered)
    - polymorphic PromptSpec Type field (GeneratedPassword / Text) consumed by Read-AdmanActionParams
    - FixedParameters declarative parameter injection (operator picked the action by picking the menu item)
    - PromptSpec-parameter-name contract test (every menu key resolves to a declared parameter on the target verb)
key-files:
  created:
    - tests/Start.Adman.Tests.ps1
  modified:
    - Private/Menu/Get-AdmanMenuDefinition.ps1
    - Private/Menu/Read-AdmanActionParams.ps1
    - Public/Start-Adman.ps1
    - tests/Menu.Tests.ps1
    - tests/Module.Manifest.Tests.ps1
decisions:
  - PromptSpec items are hashtables (not PSCustomObjects); Read-AdmanActionParams uses shape-agnostic key detection (.Contains() for IDictionary, PSObject.Properties.Name otherwise) so Choices/Type probe works for both shapes
  - Separator entries carry Verb=$null, PromptSpec=@(), Properties=[string[]]@(), FixedParameters=$null; Start-Adman renders them as plain text lines and excludes them from the numbered selection list
  - Set-AdmanLocalUser appears THREE times in the menu (Reset/Enable/Disable parameter sets); the Enable/Disable entries carry FixedParameters=@{Enable=$true} / @{Disable=$true} so the operator picks the action by picking the menu item (no further prompt)
metrics:
  duration: ~10m
  completed: 2026-07-16
  tasks: 2
  tests-added: 17 (4 MENU-07 + 5 MENU-08 + 4 MENU-09 + 4 MENU-10 + 3 START-01/02 + 1 manifest)
  tests-passing: 485
  tests-failing: 0
status: complete
---

# Phase 02 Plan 06: Menu Integration + Phase Exit Gate Summary

**One-liner:** Wired all 17 Phase 2 write verbs into the Start-Adman menu with section grouping, extended the prompt engine for D-05 GeneratedPassword Type with per-verb PromptSpec names, landed the FixedParameters declarative injection for Set-AdmanLocalUser Enable/Disable, re-verified the 17-verb manifest export, and re-proved the SAFE-08/09 AST guard against the expanded Public/ tree — full unit suite green (485/0), PSScriptAnalyzer clean.

## What Was Built

### Task 1: Menu integration + D-05 prompt engine + FixedParameters dispatcher + manifest re-verification
- `Get-AdmanMenuDefinition`: appended 19 write entries (17 verbs; `Set-AdmanLocalUser` appears three times for its Reset/Enable/Disable parameter sets) + 4 non-selectable section separator entries (`--- User writes ---`, `--- Computer writes ---`, `--- Local writes ---`, `--- Group membership ---`). Gained the `FixedParameters` field (MEDIUM #6 review fix). Password PromptSpec Names are per-verb to match the target verb's parameter name exactly (`AccountPassword` for `New-AdmanUser`, `NewPassword` for `Set-AdmanUserPassword`, `Password` for `New-AdmanLocalUser` and `Set-AdmanLocalUser` — HIGH #1 cycle-2 review fix).
- `Read-AdmanActionParams`: polymorphic `Type` dispatch. `Type='GeneratedPassword'` renders the Choices array as a numeric sub-choice (1=Generate via `New-AdmanRandomPassword`, 2=Prompt via `Read-Host -AsSecureString` + `Test-AdmanPasswordComplexity`); stores the SecureString in `$params[$name]` and sets `$params["${name}Source"]='Generate'|'Prompt'`. B/Q reserved-input contract preserved on the sub-choice. Shape-agnostic key detection for hashtable/PSCustomObject PromptSpec items (Rule 1 bug fix).
- `Start-Adman`: separator skip (Verb=$null rendered as plain text, not numbered) + FixedParameters merge into dispatched params (MEDIUM #6 review fix — the merge happens AFTER prompting so fixed values are always present and never prompted for).
- `tests/Menu.Tests.ps1`: extended with MENU-07 (write entries present + separator contract), MENU-08 (GeneratedPassword Type dispatch + B/Q contract), MENU-09 (FixedParameters presence + no key collision), MENU-10 (PromptSpec-parameter-name contract — every menu key resolves to a declared parameter on the target verb).
- `tests/Start.Adman.Tests.ps1`: NEW — separator selectability (plain text render, no number prefix) + FixedParameters merge assertions (Enable=$true / Disable=$true dispatched without prompting).
- `tests/Module.Manifest.Tests.ps1`: extended with the 17-verb export re-verification (HIGH #2 review fix).

### Task 2: Phase exit gate — full suite green + AST guard re-proof + lint clean
- Full unit suite: 485 passed, 0 failed, 10 not run (pre-existing integration skips).
- AST guard (`tests/Safety.Gate.Tests.ps1`): 12 passed, 0 failed — no Public/ file names a banned AD write or LocalAccounts cmdlet directly.
- No-hard-delete guard (`tests/Safety.NoHardDelete.Tests.ps1`): included in the 12 above — `Remove-ADObject` appears nowhere in Public/.
- PSScriptAnalyzer: zero Error-severity findings against Public/ and Private/ with the repo settings file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hashtable PromptSpec items not detected by PSObject.Properties.Name probe**
- **Found during:** Task 1 (GREEN run)
- **Issue:** The existing `Read-AdmanActionParams` probed for the `Choices` key via `$field.PSObject.Properties.Name -contains 'Choices'`. For hashtables (the menu def's inline PromptSpec shape), `PSObject.Properties.Name` does NOT include the keys — it returns the .NET type's properties (`Keys`, `Values`, `Count`, etc.), so the probe always returned `$false` and the Choices/Type branches never fired.
- **Fix:** Added shape-agnostic key detection: `$field -is [System.Collections.IDictionary]` → use `.Contains($Key)`; otherwise use `PSObject.Properties.Name`. Applied to both the `Choices` and `Type` probes.
- **Files modified:** `Private/Menu/Read-AdmanActionParams.ps1`
- **Commit:** 62f4b4b

**2. [Rule 1 - Bug] StrictMode PropertyNotFoundException on hashtable .Type access in tests**
- **Found during:** Task 1 (GREEN run)
- **Issue:** The menu def file has `Set-StrictMode -Version Latest`; dot-sourcing it in the test's `BeforeAll` enables StrictMode for the rest of the test scope. Under StrictMode, accessing a non-existent key on a hashtable via dot notation (`$spec.Type`) throws `PropertyNotFoundException` instead of returning `$null`.
- **Fix:** Changed all test-side PromptSpec Type probes to `$spec.Contains('Type') -and $spec.Type -eq 'GeneratedPassword'` (StrictMode-safe).
- **Files modified:** `tests/Menu.Tests.ps1`
- **Commit:** 62f4b4b

## Auth Gates

None.

## Known Stubs

None. All created/modified files are fully wired; no placeholder data flows to any UI.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-02 password prompt in menu path mitigated by SecureString + never-echo-or-log; T-02-04 AST guard bypass mitigated by the re-proof in Task 2).

## TDD Gate Compliance

- **RED gate:** The new tests were authored alongside the implementation in a single atomic commit (the standard GSD TDD pattern for this repo when the test file and the implementation are co-created). The tests were confirmed failing before the implementation was complete (9 failures on the first run: Properties shape, GeneratedPassword dispatch, StrictMode hashtable access).
- **GREEN gate:** Commit 62f4b4b lands the tests green (51/51 across the three targeted files; 485/485 full suite).
- **REFACTOR gate:** Not applicable — no refactoring needed beyond the initial implementation.

## Self-Check: PASSED

- All 3 modified source files exist on disk: `Private/Menu/Get-AdmanMenuDefinition.ps1`, `Private/Menu/Read-AdmanActionParams.ps1`, `Public/Start-Adman.ps1`.
- All 3 modified/created test files exist on disk: `tests/Menu.Tests.ps1`, `tests/Start.Adman.Tests.ps1`, `tests/Module.Manifest.Tests.ps1`.
- Commit 62f4b4b exists in `git log`.
- Plan-level verification: 51/51 green across the three targeted test files.
- Full unit suite: 485 passed, 0 failed, 10 not run (pre-existing integration skips).
- AST guard: 12/12 green (SAFE-08 banned AD write + LocalAccounts sets; SAFE-09 no-hard-delete).
- PSScriptAnalyzer: zero Error-severity findings.
