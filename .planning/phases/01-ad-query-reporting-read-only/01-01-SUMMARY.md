---
phase: 01-ad-query-reporting-read-only
plan: 01
subsystem: menu
tags: [menu, tui, dispatch, d-01, wave-1]
dependency_graph:
  requires:
    - Public/Initialize-Adman.ps1 (Phase 0 startup orchestration)
    - Private/Foundation/Get-AdmanRecoveryPosture.ps1 (Phase 0, banner data)
    - $script:Config / $script:Capability (Phase 0 session state)
  provides:
    - Public/Start-Adman.ps1 (flat while-loop TUI dispatcher)
    - Private/Menu/Get-AdmanMenuDefinition.ps1 (menu-item table + Properties schema)
    - Private/Menu/Read-AdmanActionParams.ps1 (B/Q-aware parameter prompter)
    - tests/Menu.Tests.ps1 (MENU-01..04 contract)
  affects:
    - Plan 01-02 (Find-AdmanUser / Find-AdmanComputer / ConvertTo-AdmanResult) — menu dispatches to these verbs
    - Plan 01-03 (report verbs) — menu dispatches to these verbs; Bucket column added to report Properties
    - Plan 01-04 (renderer dispatch) — consumes $entry.Properties for empty-result header-only output
tech_stack:
  added: []
  patterns:
    - Flat while-loop TUI with Read-Host 'Select' (D-01)
    - Thin prompt-and-dispatch layer (MENU-04) — no AD logic in menu body
    - ADMAN_QUIT sentinel throw/catch for Q-reserved-input propagation
    - Per-entry Properties [string[]] as D-03 schema source for renderers (Cycle 4 finding)
key_files:
  created:
    - Private/Menu/Get-AdmanMenuDefinition.ps1
    - Private/Menu/Read-AdmanActionParams.ps1
    - tests/Menu.Tests.ps1
  modified:
    - Public/Start-Adman.ps1
decisions:
  - Removed SupportsShouldProcess from Start-Adman (read-only TUI; review LOW)
  - Top-level reserved inputs are 1..N and Q only; B is reserved inside action prompts per UI-SPEC
  - Q inside action prompts throws ADMAN_QUIT sentinel; Start-Adman catches and breaks
  - Empty required input re-prompts once; second consecutive empty treated as B
  - Menu metadata schema carries Properties field per entry (NOT a separate Get-AdmanReportProperties helper) — co-locates output schema with verb entry, avoids drift
  - Recovery/freshness banner lines render only when $script:Config keys already present (Wave 1 safe; Plan 01-03 adds the keys)
metrics:
  duration: 15m
  completed_date: 2026-07-15
  tasks: 3
  files_created: 3
  files_modified: 1
  tests_added: 20
status: complete
---

# Phase 01 Plan 01: Read-Only Menu Shell Summary

**One-liner:** Flat while-loop TUI dispatcher (D-01) with six-entry menu definition carrying per-verb D-03 Properties schema, B/Q-aware parameter prompter, and 20 green Pester 6 contract tests proving MENU-01..04.

## What Was Built

### Public/Start-Adman.ps1 (modified)

Replaced the Phase 0 stub with the real flat while-loop menu:

- Removed `[CmdletBinding(SupportsShouldProcess)]` → plain `[CmdletBinding()]`. The launcher is a read-only TUI dispatcher; `SupportsShouldProcess` was misleading on a function that never mutates state (review LOW).
- Calls `Initialize-Adman` once before the loop.
- Prints the startup banner (Domain, DC, capability flags from `$script:Capability`). Recovery posture and freshness lines render only when those keys are already present on `$script:Config` — Plan 01-03 adds them, so the banner never throws during Wave 1.
- Single `while ($true)` loop: prints numbered items 1..N from `Get-AdmanMenuDefinition` plus `Q. Quit`, reads `Read-Host 'Select'`, validates integer 1..N or Q. Top-level invalid-input copy is exactly `Invalid selection. Enter a number or Q.` (B is NOT reserved at the top level per UI-SPEC §Reserved inputs).
- For a valid choice, calls `Read-AdmanActionParams -PromptSpec $entry.PromptSpec`. Catches the `ADMAN_QUIT` sentinel and breaks cleanly. `$null` return (B or second-empty) resumes the loop.
- Dispatches via `& $Verb @params` and emits the returned `PSCustomObject[]` directly. No call to `Format-AdmanReport` / `Export-AdmanReport*` — renderer dispatch belongs to Plan 01-04.
- No AD read logic, no formatting logic beyond the banner.
- Per-file `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]` on the function (PSScriptAnalyzerSettings.psd1 disables the rule globally for the TUI module; the attribute pairs with that forward-declared suppression).

### Private/Menu/Get-AdmanMenuDefinition.ps1 (new)

Returns the ordered six-entry menu-item table. Each entry carries `Label`, `Verb`, `PromptSpec`, and `Properties` ([string[]] of D-03 schema column names). Properties arrays pinned per the plan:

- `Find-AdmanUser` → 16 D-03 user columns (no Bucket).
- `Find-AdmanComputer` → 15 D-03 computer columns (no Bucket).
- `Get-AdmanStaleReport` / `Get-AdmanAccountStateReport` → user columns + Bucket (17).
- `Get-AdmanInventoryReport` → computer columns + Bucket (16).
- `Get-AdmanRecoveryPostureReport` → five-field shape (RecycleBinEnabled, ForestFunctionalLevel, TombstoneLifetime, Generated, Freshness).

**Decision (Cycle 4):** extended the menu metadata schema with a `Properties` field per verb entry rather than introducing a separate `Get-AdmanReportProperties` helper. The menu definition is already the single table Start-Adman reads for dispatch; co-locating the output schema with the verb entry keeps the schema discoverable, avoids a second lookup table that can drift from the menu, and lets Plan 01-04 read `$entry.Properties` directly with no extra function call.

### Private/Menu/Read-AdmanActionParams.ps1 (new)

Per-action parameter prompter. Reads the PromptSpec and returns a hashtable for splatting:

- `B` / `b` → returns `$null` (Start-Adman resumes the top-level loop).
- `Q` / `q` → throws an error whose message is the reserved `ADMAN_QUIT` sentinel; Start-Adman catches and breaks.
- Empty required input → re-prompts once; second consecutive empty treated as `B` (returns `$null`).
- Numeric sub-choice validation when the PromptSpec entry carries a `Choices` array; invalid input re-prompts with `Invalid selection. Enter a number, B, or Q.`
- Free-text inputs trimmed and passed through; the underlying verb validates semantics.
- Returns ONLY the parameters declared in the PromptSpec — no free-form code execution (T-01-03).

### tests/Menu.Tests.ps1 (new)

20 Pester 6 assertions across four Describe blocks (MENU-01..04). Mix of static AST checks (single while loop, `Read-Host 'Select'`, `& $Verb @params` dispatch, no `SupportsShouldProcess`, no direct `Get-AD*`/`Search-ADAccount` calls, no `Format-AdmanReport` call) and behavioral checks (B/Q/empty-input handling in `Read-AdmanActionParams`, six-entry menu definition contract, pinned Properties arrays). Runs offline; no RSAT, no live domain.

## Verification

- `Invoke-Pester -Path tests/Menu.Tests.ps1 -Output Detailed` → **20 passed, 0 failed** (Pester 6.0.0).
- `Invoke-Pester -Path tests -Output Normal -ExcludeTag Integration` → **162 passed, 0 failed** (5 Integration-tagged NotRun as designed).
- `Invoke-ScriptAnalyzer -Path <three files> -Settings PSScriptAnalyzerSettings.psd1` → **clean** (PSScriptAnalyzer 1.25.0).
- `grep -c SupportsShouldProcess Public/Start-Adman.ps1` → **0**.
- `grep -c Format-AdmanReport Public/Start-Adman.ps1` → **0**.
- AST: exactly one `while` loop, exactly one `Read-Host 'Select'`, dispatches via `& $Verb @params`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SuppressMessage attribute placed at script scope (parse error)**
- **Found during:** Task 2 verification (parse check).
- **Issue:** Initial draft placed `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]` at script scope above `param()`, which is invalid PowerShell — parser reported "Unexpected attribute" / "Unexpected token 'param'".
- **Fix:** Moved the attribute onto the `function Start-Adman` declaration, directly above `[CmdletBinding()]`.
- **Files modified:** Public/Start-Adman.ps1
- **Commit:** 5825ed7 (Task 2 commit; fix applied before commit).

**2. [Rule 1 - Bug] Docstring mentions of `SupportsShouldProcess` and `Format-AdmanReport` broke literal grep acceptance criteria**
- **Found during:** Task 2 verification (grep acceptance checks).
- **Issue:** The plan's acceptance criteria require `grep -c SupportsShouldProcess` and `grep -c Format-AdmanReport` to return 0 in `Public/Start-Adman.ps1`. The initial docstring legitimately referenced both strings to explain the design (e.g., "declares plain [CmdletBinding()] WITHOUT SupportsShouldProcess"), producing non-zero grep counts.
- **Fix:** Reworded the docstring to avoid the literal strings ("ShouldProcess attribute", "Renderer dispatch is Plan 01-04") while preserving the design intent.
- **Files modified:** Public/Start-Adman.ps1
- **Commit:** 5825ed7 (Task 2 commit; fix applied before commit).

**3. [Rule 1 - Bug] Test file used `. $path` to load menu definition but never invoked the function**
- **Found during:** Task 3 (first Pester run — 5 failures).
- **Issue:** `$def = . $script:MenuDefPath` dot-sources the file (defining `Get-AdmanMenuDefinition`) but captures the dot-source's return value, which is `$null`. Tests then asserted on `$null` and failed.
- **Fix:** Changed to `. $script:MenuDefPath; $def = Get-AdmanMenuDefinition` in all four affected tests.
- **Files modified:** tests/Menu.Tests.ps1
- **Commit:** 918b7a1

**4. [Rule 1 - Bug] AD-cmdlet regex false-flagged `Get-AdmanMenuDefinition` as a direct `Get-AD*` call**
- **Found during:** Task 3 (first Pester run).
- **Issue:** The MENU-04 pure-dispatch test used regex `^(Get|Search|...)-AD` which matched `Get-AdmanMenuDefinition` (the menu's own internal helper), failing the "no direct AD calls" assertion.
- **Fix:** Added negative lookahead `(?!man)` to the regex: `^(Get|Set|New|Remove|Move|Enable|Disable|Rename)-AD(?!man)`. Real AD cmdlets (`Get-ADUser`, `Get-ADComputer`, `Search-ADAccount`) still match; `Get-AdmanMenuDefinition` does not.
- **Files modified:** tests/Menu.Tests.ps1
- **Commit:** 918b7a1

### Out-of-Scope Discoveries (logged, not fixed)

**Dev-host toolchain gap (pre-existing):** Pester 3.4.0 and no PSScriptAnalyzer were the only modules installed system-wide on this dev host. The plan and VALIDATION.md target Pester 6.0.0 + PSScriptAnalyzer 1.25.0. Installed both CurrentUser-scope via PSResourceGet to run verification. This is a pre-existing environment gap, not caused by this plan. The user's lab environment (D:\ checkout) already has the correct toolchain per the memory note. No action needed beyond the CurrentUser install.

## Authentication Gates

None.

## Known Stubs

None. The menu dispatches to Public verbs (`Find-AdmanUser`, `Find-AdmanComputer`, `Get-Adman*Report`) that do not yet exist — they land in Plans 01-02 and 01-03. This is intentional Wave 1 behavior: the menu is a thin dispatch layer and the verbs are the next wave's deliverable. The MENU-04 contract test pins the verb names so any drift is caught.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-01-01..T-01-03 mitigated as designed; T-01-SC accepted — zero new dependencies).

## Self-Check: PASSED

- [x] `Public/Start-Adman.ps1` exists — modified.
- [x] `Private/Menu/Get-AdmanMenuDefinition.ps1` exists — created.
- [x] `Private/Menu/Read-AdmanActionParams.ps1` exists — created.
- [x] `tests/Menu.Tests.ps1` exists — created.
- [x] Commit `6ab558c` (Task 1 RED tests) — found in `git log`.
- [x] Commit `5825ed7` (Task 2 implementation) — found in `git log`.
- [x] Commit `918b7a1` (Task 3 green tests) — found in `git log`.
- [x] All 20 MENU-01..04 tests green under Pester 6.0.0.
- [x] Full unit suite green (162 passed, 0 failed).
- [x] PSScriptAnalyzer 1.25.0 clean on the three implementation files.
