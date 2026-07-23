---
phase: 04-bulk-workflows-highest-blast-radius-last
plan: 04
subsystem: menu-manifest
status: complete
tags: [powershell, active-directory, menu, manifest, safety-gate, pester]

requires:
  - phase: 00-foundation-safety-harness
    provides: Start-Adman dispatcher, Invoke-AdmanMutation gate, Write-AdmanAudit
  - phase: 04-bulk-workflows-highest-blast-radius-last
    plan: 01
    provides: Invoke-AdmanBulkAction engine
  - phase: 04-bulk-workflows-highest-blast-radius-last
    plan: 02
    provides: Start-AdmanUserOnboarding
  - phase: 04-bulk-workflows-highest-blast-radius-last
    plan: 03
    provides: Start-AdmanUserOffboarding, Restore-AdmanQuarantinedUser

provides:
  - Menu entries for all four Phase 4 verbs reachable from Start-Adman.
  - SkipOutputPrompt contract so workflow/checklist verbs bypass the generic output-format prompt.
  - Manifest export contract tests verifying the four Phase 4 verbs are explicitly exported and the gate is not.
  - Repo-wide hard-delete literal scan over Public/ and Private/ source trees.

affects:
  - 05-hardening-portability

tech-stack:
  added: []
  patterns:
    - "Menu entries carry a SkipOutputPrompt flag; Start-Adman checks it before the generic renderer."
    - "Hard-delete guard covers all .ps1 source under Public/ and Private/, not just the wrapper file."

key-files:
  created:
    - tests/Menu.BulkWorkflow.Tests.ps1
  modified:
    - Private/Menu/Get-AdmanMenuDefinition.ps1
    - Public/Start-Adman.ps1
    - tests/Module.Manifest.Tests.ps1
    - tests/Safety.NoHardDelete.Tests.ps1
    - adman.psd1 (already exported from prior 04-0x plans; contract re-verified)

key-decisions:
  - "Bulk action in the TUI is CSV-only in v1; search-based bulk remains a direct PowerShell pipeline workflow."
  - "SkipOutputPrompt is explicit only on workflow entries; absent/null is tolerated on pre-Phase 4 entries."
  - "Hard-delete source scan is repo-wide over Public/ and Private/, not scoped to new Phase 4 files."

requirements-completed:
  - FLOW-01
  - FLOW-02
  - FLOW-03
  - FLOW-04
  - BULK-01
  - BULK-02
  - BULK-03
  - BULK-04

coverage:
  - id: D1
    description: "Menu contains entries for Invoke-AdmanBulkAction, Start-AdmanUserOnboarding, Start-AdmanUserOffboarding, and Restore-AdmanQuarantinedUser."
    requirement: MENU-04
    verification:
      - kind: unit
        ref: "tests/Menu.BulkWorkflow.Tests.ps1#Phase 4 bulk and workflow menu entries exist"
        status: pass
    human_judgment: false
  - id: D2
    description: "Bulk menu entry is CSV-scoped (Path required, Action choices) and does not expose search-based bulk in the TUI."
    requirement: BULK-04
    verification:
      - kind: unit
        ref: "tests/Menu.BulkWorkflow.Tests.ps1#Phase 4 bulk entry is CSV-scoped in v1"
        status: pass
    human_judgment: false
  - id: D3
    description: "Onboarding, offboarding, and restore entries set SkipOutputPrompt = $true."
    requirement: FLOW-01
    verification:
      - kind: unit
        ref: "tests/Menu.BulkWorkflow.Tests.ps1#Phase 4 workflow entries skip the generic output-format prompt"
        status: pass
    human_judgment: false
  - id: D4
    description: "Start-Adman returns to the top-level menu without rendering the output-format prompt for workflow entries."
    requirement: FLOW-02
    verification:
      - kind: unit
        ref: "tests/Menu.BulkWorkflow.Tests.ps1#behavioral skip tests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Phase 4 verbs are explicitly exported and Invoke-AdmanMutation remains private."
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Module.Manifest.Tests.ps1#Phase 4 export assertion"
        status: pass
    human_judgment: false
  - id: D6
    description: "No literal Remove-ADObject appears in any Public or Private source file."
    requirement: SAFE-09
    verification:
      - kind: unit
        ref: "tests/Safety.NoHardDelete.Tests.ps1#repo-wide SAFE-09"
        status: pass
    human_judgment: false

metrics:
  duration: 35min
  completed: 2026-07-20
  status: complete
---

# Phase 04 Plan 04: Menu Integration + Manifest Exports + Phase Exit Gate Summary

**Wired the Phase 4 bulk and workflow verbs into the Start-Adman TUI, verified manifest exports, enforced a repo-wide hard-delete guard, and passed the recursive lint + full unit suite.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-07-20T15:30:00Z
- **Completed:** 2026-07-20T16:05:00Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Extended `Get-AdmanMenuDefinition` with a `--- Bulk & workflows ---` section containing:
  - CSV-scoped `Invoke-AdmanBulkAction` entry (Action choices, required Path, optional TargetPath/GroupIdentity).
  - `Start-AdmanUserOnboarding` entry (FirstName, LastName).
  - `Start-AdmanUserOffboarding` entry (AdIdentity prompt).
  - `Restore-AdmanQuarantinedUser` entry (AdIdentity prompt).
- Added the `SkipOutputPrompt` contract: workflow entries set it to `$true`; the bulk entry and pre-Phase 4 entries leave it absent/null.
- Updated `Start-Adman` to check `SkipOutputPrompt` after dispatch and `continue` the menu loop, so workflow/checklist text is not forced through the generic output renderer.
- Added `tests/Menu.BulkWorkflow.Tests.ps1` with 17 unit tests covering menu presence, CSV scope, SkipOutputPrompt contract, parameter resolution, and behavioral proof that workflow entries bypass the output-format prompt.
- Extended `tests/Module.Manifest.Tests.ps1` to assert the four Phase 4 verbs are explicitly exported and `Invoke-AdmanMutation` is not.
- Extended `tests/Safety.NoHardDelete.Tests.ps1` with a recursive source scan over `Public/` and `Private/` for the literal `Remove-ADObject`.
- Ran recursive `Invoke-ScriptAnalyzer` with `PSScriptAnalyzerSettings.psd1` — zero diagnostics.
- Ran the full unit suite (`Invoke-Pester -Path tests -Tag Unit`) — 678 passed, 0 failed.

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED):** `198739a` — test(04-04): add failing menu contract tests for bulk and workflow entries
2. **Task 1 (GREEN):** `7e60748` — feat(04-04): wire bulk and workflow verbs into menu definition with output-prompt skip
3. **Task 2:** `db45d7a` — test(04-04): assert Phase 4 bulk/workflow verbs are explicitly exported
4. **Task 3:** `cf70e9e` — feat(04-04): honor SkipOutputPrompt, extend hard-delete guard, and add workflow behavioral tests

## Files Created/Modified

- `Private/Menu/Get-AdmanMenuDefinition.ps1` — Added Phase 4 menu entries and section separator.
- `Public/Start-Adman.ps1` — Added `SkipOutputPrompt` check after verb dispatch.
- `tests/Menu.BulkWorkflow.Tests.ps1` (created) — 17 unit tests for menu integration and skip contract.
- `tests/Module.Manifest.Tests.ps1` — Added Phase 4 export assertion.
- `tests/Safety.NoHardDelete.Tests.ps1` — Added repo-wide `Remove-ADObject` literal scan.
- `adman.psd1` — Already exported the four Phase 4 verbs from prior plans; contract re-verified.

## Decisions Made

- Kept the TUI bulk entry CSV-only in v1. Search-based bulk remains a direct PowerShell pipeline to `Invoke-AdmanBulkAction`, matching the review finding and the menu dispatcher's single-verb + prompted-parameter design.
- Made `SkipOutputPrompt` an opt-in property: workflow entries set it explicitly; older entries may leave it absent without breaking contract tests.
- Scoped the hard-delete source scan to `Public/` and `Private/` recursively so future source additions are covered automatically.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- `Import-PowerShellDataFile` is not available in the Windows PowerShell 5.1 test host, so the planned `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)` invocation was replaced with the documented fallback `Invoke-Pester -Path tests -Tag Unit`. The same tests run; only the configuration-load path differed.
- Initial behavioral tests for `SkipOutputPrompt` under-supplied scripted `Read-Host` answers for the workflow prompts. Fixed by extending the answer sequences and mocking `Resolve-AdmanIdentity` for the `AdIdentity` prompts.

## User Setup Required

None — no external service configuration required.

## Known Stubs

None.

## Threat Flags

No security-relevant surface beyond the planned menu/manifest boundaries was introduced. The plan's threat register was implemented as specified:

| Threat ID | Mitigation implemented |
|-----------|------------------------|
| T-04-17 | Bulk menu entry dispatches to the same `Invoke-AdmanBulkAction` engine that enforces cap-after-filter and typed-count confirmation. |
| T-04-18 | `FunctionsToExport` is explicit; contract test verifies the four new verbs are present and `Invoke-AdmanMutation` is absent. |
| T-04-19 | Accepted — parameter names are public API surface. |
| T-04-20 | Repo-wide source scan over `Public/` and `Private/` plus the existing wrapper allow-list test. |

## Next Phase Readiness

- Phase 4 is complete. All 8 Phase 4 requirements (FLOW-01..04, BULK-01..04) are satisfied and covered by passing unit tests.
- Phase 5 (Hardening & Portability) can proceed: documentation, dual-edition CI matrix, Authenticode signing, credential restore, and audit hardening.

## Self-Check: PASSED

- [x] `Private/Menu/Get-AdmanMenuDefinition.ps1` updated with Phase 4 entries
- [x] `Public/Start-Adman.ps1` honors `SkipOutputPrompt`
- [x] `tests/Menu.BulkWorkflow.Tests.ps1` exists and passes (17/17)
- [x] `tests/Module.Manifest.Tests.ps1` Phase 4 assertion passes
- [x] `tests/Safety.NoHardDelete.Tests.ps1` repo-wide scan passes
- [x] Commits `198739a`, `7e60748`, `db45d7a`, `cf70e9e` exist
- [x] PSScriptAnalyzer reports zero diagnostics
- [x] Full unit suite passes: 678 passed, 0 failed

---
*Phase: 04-bulk-workflows-highest-blast-radius-last*
*Completed: 2026-07-20*
