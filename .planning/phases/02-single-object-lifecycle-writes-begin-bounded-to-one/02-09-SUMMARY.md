---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
plan: 09
subsystem: menu
tags: [menu, prompt-time-validation, identity-resolution, gap-closure, rev-3]
gap_closure: true
closes_gaps: [G-02-2, G-02-4]
requirements: [USER-02, USER-03, USER-04, USER-05, USER-06, COMP-02, COMP-03, COMP-04, GRP-01, GRP-02]
dependency_graph:
  requires:
    - Private/Safety/Resolve-AdmanTarget.ps1 (file header pattern, -Server pinning)
    - Private/Utility/Escape-AdmanAdFilterLiteral.ps1 (sAMAccountName -Filter escaping)
    - Private/Utility/ConvertTo-AdmanNormalizedDn.ps1 (DN shape heuristic reference)
    - Private/Menu/Read-AdmanActionParams.ps1 (free-text branch, B/Q reserved-input contract)
    - Private/Menu/Get-AdmanMenuDefinition.ps1 (PromptSpec entries)
  provides:
    - Resolve-AdmanIdentity (Private, not exported) — single prompt-time resolver for sAMAccountName / DN / OU-DN input
    - AdComputer Kind tries both NAME and NAME$ sAMAccountName forms (REV-3)
    - Read-AdmanActionParams Type dispatch for AdIdentity and AdOuDn with re-prompt on failure
    - 11 identity PromptSpec entries carry Type='AdIdentity' (4 computer prompts also carry Kind='AdComputer' + updated prompt text)
    - 3 OU-DN PromptSpec entries carry Type='AdOuDn'
    - 8-test Pester suite proving resolver contract + menu re-prompt behavior
  affects:
    - All menu-driven identity prompts (Disable/Enable/Reset/Unlock/Move user, Disable/Enable/Move/Reset computer, Add/Remove AD group) — resolve sAMAccountName at prompt time
    - Create user ParentOuDn prompt — validates DN shape and resolves to an existing OU at prompt time
    - Move user / Move computer TargetPath prompts — validates destination OU DN at prompt time
    - UAT Test 2 (non-DN at parent-OU prompt) — now re-prompts instead of crashing
    - UAT Test 4 (sAMAccountName at identity prompt) — now resolves instead of crashing
tech_stack:
  added: []
  patterns:
    - Prompt-time resolver pattern (catches malformed input at the menu layer, not deep in the gate)
    - DN shape heuristic (contains '=' AND ',') for distinguishing DN from sAMAccountName
    - Trailing-dollar fallback for computer sAMAccountName (REV-3)
    - Type dispatch on PromptSpec (mirrors the existing GeneratedPassword dispatch)
key_files:
  created:
    - Private/Safety/Resolve-AdmanIdentity.ps1
    - tests/Menu.IdentityResolver.Tests.ps1
  modified:
    - Private/Menu/Read-AdmanActionParams.ps1
    - Private/Menu/Get-AdmanMenuDefinition.ps1
    - tests/Mocks/ActiveDirectory.psm1
decisions:
  - "Resolve-AdmanIdentity is a prompt-time resolver operating at the menu layer; it does NOT replace the gate's Resolve-AdmanTarget — both resolvers run in sequence (menu resolves to DN at prompt time, gate re-resolves the DN for preview/execute)"
  - "DN shape detection uses a simple heuristic (contains '=' AND ','); the resolver does NOT call ConvertTo-AdmanNormalizedDn — normalization is a scope-check concern handled downstream by Test-AdmanTargetAllowed step (c)"
  - "AdComputer Kind tries the exact sAMAccountName form first, then the trailing-dollar form (REV-3); operators habitually type the bare 'PC01' form but computer sAMAccountName is conventionally 'PC01$'"
  - "Resolution failures Write-Host the typed error message and 'continue' the while loop (re-prompt); the B/Q reserved-input contract is preserved because the B/Q/empty checks run BEFORE the Type dispatch"
  - "The resolved DistinguishedName (not the raw sAMAccountName) is stored in `$params[`$name] — the downstream verbs expect a DN or an identity the gate can resolve; storing the DN is the truthful, already-resolved form"
metrics:
  duration: "~11m"
  completed: 2026-07-16
status: complete
---

# Phase 02 Plan 09: Prompt-Time Identity/OU-DN Resolver (G-02-2 / G-02-4) Summary

**One-liner:** Introduced a shared `Resolve-AdmanIdentity` prompt-time resolver and wired it into the menu prompt engine via a new `Type` dispatch (`AdIdentity` / `AdOuDn`), so malformed operator input re-prompts at the menu layer instead of crashing deep in the gate with a raw `Get-ADObject` error.

## Objective

UAT Test 2 showed entering `adman-test` (not a DN) at the Create user parent-OU prompt crashed at `Invoke-AdmanMutation.ps1:90` with a raw `Get-ADObject` error. UAT Test 4 showed entering `uat-reset1` (sAMAccountName) at the Disable user identity prompt crashed the app. Both are the same defect class: no prompt-time validation/resolution of identity input. The guided TUI must catch malformed input at prompt time and re-prompt, not crash deep in the gate — this was a BLOCKER for the menu path (the core UX for the junior admin persona).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Private/Safety/Resolve-AdmanIdentity.ps1 | b9fb603 | Private/Safety/Resolve-AdmanIdentity.ps1 |
| 2 | Wire Type dispatch into Read-AdmanActionParams + update Get-AdmanMenuDefinition PromptSpec entries | 021e5ab | Private/Menu/Read-AdmanActionParams.ps1, Private/Menu/Get-AdmanMenuDefinition.ps1 |
| 3 | Pester test for resolver + menu re-prompt behavior (TDD) | 2dd0a8b | tests/Menu.IdentityResolver.Tests.ps1, tests/Mocks/ActiveDirectory.psm1 |

## Verification Results

**Task 1 automated check (source assertion):**
- File exists with `function Resolve-AdmanIdentity`, `ValidateSet('AdUser','AdComputer','AdOuDn')`, `Set-StrictMode -Version Latest`: PASS
- NOT added to adman.psd1 FunctionsToExport (Private/): PASS

**Task 2 automated check (source assertion):**
- `Read-AdmanActionParams.ps1` contains `AdIdentity`, `AdOuDn`, `Resolve-AdmanIdentity`: PASS
- `Get-AdmanMenuDefinition.ps1` Type='AdIdentity' count: 11 (>= 11 required): PASS
- `Get-AdmanMenuDefinition.ps1` Type='AdOuDn' count: 3 (>= 3 required): PASS
- `Get-AdmanMenuDefinition.ps1` Kind='AdComputer' count: 4 (>= 4 required): PASS
- `Get-AdmanMenuDefinition.ps1` 'NAME or NAME' count: 4 (>= 4 required): PASS

**Task 3 Pester test:**
- All 8 tests pass: PASS
  - Test 1: AdUser resolves sAMAccountName to ADObject with correct DN
  - Test 2: AdUser passes full DN through to Get-ADObject -Identity (passthrough)
  - Test 3: AdUser throws 'No AD object found' for unresolvable sAMAccountName
  - Test 4: AdOuDn throws 'is not a distinguished name' for non-DN input
  - Test 5: AdOuDn returns the OU object for a valid OU DN
  - Test 6: Type='AdIdentity' stores the resolved DN (not the raw sAMAccountName)
  - Test 7: Type='AdOuDn' re-prompts on non-DN input and stores the valid DN
  - Test 8 (REV-3): AdComputer bare 'PC01' resolves via trailing-dollar fallback 'PC01$'; both forms tried in order

**Full unit suite (`Invoke-Pester -Path tests/ -Tag 'Unit'`):**
- 455 passed, 4 failed, 1 container failed (Menu.Tests parse error)
- All 4 failures + Menu.Tests container failure are pre-existing (matches the plan's verification expectation: "no new failures beyond the 4 pre-existing + Menu.Tests parse error")
- No new failures introduced by this plan

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extended tests/Mocks/ActiveDirectory.psm1 parameter signatures**
- **Found during:** Task 3 (first Pester run)
- **Issue:** The existing `Get-ADObject` mock accepted only `$Identity, $Properties, $Server, $LDAPFilter` — no `$Filter` parameter. The existing `Get-ADOrganizationalUnit` mock accepted only `$Identity, $Filter, $Server` — no `$Properties` parameter. Pester's `Mock ... -ModuleName adman` wraps the original function; when the resolver called `Get-ADObject -Filter ...` or `Get-ADOrganizationalUnit -Properties ...`, parameter binding failed with "A parameter cannot be found that matches parameter name 'Filter'/'Properties'" before the mock body could run.
- **Fix:** Added `$Filter` to the `Get-ADObject` mock signature and `$Properties` to the `Get-ADOrganizationalUnit` mock signature. No behavioral change to the default mock bodies (they still return the canned New-AdmanMockObject); the new parameters are simply bindable so Pester Mock parameter filters can interrogate them.
- **Files modified:** tests/Mocks/ActiveDirectory.psm1
- **Commit:** 2dd0a8b (bundled with the new test file)

**2. [Rule 1 - Bug] Restructured Tests 6-7 to dot-source Read-AdmanActionParams**
- **Found during:** Task 3 (second Pester run)
- **Issue:** Initial draft called `Read-AdmanActionParams` via `& (Get-Module adman) { ... }` and relied on `Mock Get-ADObject -ModuleName adman` to intercept the resolver's AD calls. The mock fired, but the test asserted on the resolved DN stored in `$params` — and the call returned `$null`. Root cause: `Read-AdmanActionParams` is a Private function (not exported from adman.psd1), and the `Mock Read-Host` (no `-ModuleName`) did not apply inside the module scope.
- **Fix:** Switched to the established `tests/Menu.Tests.ps1` MENU-08 pattern: dot-source `Private/Menu/Read-AdmanActionParams.ps1` in the test's `BeforeAll` and stub `Resolve-AdmanIdentity` as a `script:`-scoped function. This isolates the menu dispatch logic (the thing Tests 6-7 are proving) from the resolver itself (already proven by Tests 1-5, 8). The resolver stub returns a canned ADObject for the good input and throws the typed error for the bad input.
- **Files modified:** tests/Menu.IdentityResolver.Tests.ps1
- **Commit:** 2dd0a8b

**3. [Rule 1 - Bug] Fixed Test 3 and Test 8 mock bodies returning `$null` instead of empty array**
- **Found during:** Task 3 (second Pester run)
- **Issue:** `Mock Get-ADObject { $null }` returns `$null`, but the resolver wraps the call in `@(...)` — and `@($null)` has `.Count -eq 1`, not 0. The resolver's "zero hits" branch never fired, so the 'No AD object found' throw never happened.
- **Fix:** Changed the mock bodies to `Mock Get-ADObject { @() }` so the resolver sees a genuine empty result set.
- **Files modified:** tests/Menu.IdentityResolver.Tests.ps1
- **Commit:** 2dd0a8b

## Authentication Gates

None.

## Threat Surface Scan

No new security-relevant surface introduced beyond what the plan's `<threat_model>` already covers:

- **T-02-09-01 (DoS via unvalidated input):** Mitigated by this plan — the resolver validates at prompt time and re-prompts, keeping the TUI alive. Tests 3, 4, 7 prove the re-prompt path.
- **T-02-09-02 (Injection via sAMAccountName -Filter):** Mitigated — sAMAccountName is escaped via `Escape-AdmanAdFilterLiteral` before interpolation into the `-Filter` string (existing pattern from Find-AdmanUser). DN path uses `-Identity` (no filter injection surface).
- **T-02-09-03 (Information disclosure via error messages):** Accepted — error messages name the input value and the AD error; no secret material disclosed.

The mocks file extension (adding `$Filter` / `$Properties` parameter signatures) is test-only surface, not production surface.

## Known Stubs

None. All PromptSpec entries wired to the resolver; all 8 tests prove real resolution behavior (no placeholder data flowing to the operator).

## Self-Check: PASSED

- `Private/Safety/Resolve-AdmanIdentity.ps1` exists: FOUND
- `tests/Menu.IdentityResolver.Tests.ps1` exists: FOUND
- Commit b9fb603 (Task 1): FOUND
- Commit 021e5ab (Task 2): FOUND
- Commit 2dd0a8b (Task 3): FOUND
- All 8 new Pester tests pass: CONFIRMED
- Full unit suite shows no new failures beyond the 4 pre-existing + Menu.Tests parse error: CONFIRMED
