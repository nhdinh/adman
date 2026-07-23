---
phase: 05-hardening-portability
plan: 01b
subsystem: docs

tags:
  - powershell
  - documentation
  - pester
  - active-directory
  - authenticode

requires: []

provides:
  - Refreshed README.md reflecting Phases 0-4 shipped state
  - docs/USAGE.md with menu reference and one example per exported function
  - docs/RECOVERY-RUNBOOK.md covering quarantine restore, Recycle Bin, authoritative restore, and certificate rotation
  - tests/Docs.Coverage.Tests.ps1 contract test enforcing docs-to-code sync

affects:
  - 05-hardening-portability

tech-stack:
  added: []
  patterns:
    - Documentation stays in sync with manifest and menu definition via Pester contract tests
    - Operator docs use contoso.local placeholders; no live OU paths or plaintext secrets

key-files:
  created:
    - docs/USAGE.md
    - docs/RECOVERY-RUNBOOK.md
    - tests/Docs.Coverage.Tests.ps1
  modified:
    - README.md
    - Private/Workflow/Get-AdmanOffboardingState.ps1

key-decisions:
  - "Represented menu PromptSpec fields as a table so the contract test can verify Name/Prompt/Required coverage deterministically."
  - "Grouped exported-function examples by operational category rather than strict manifest order to keep the guide readable while still covering every function."

patterns-established:
  - "docs/USAGE.md is the operator-facing source of truth for menu entries and exported functions."
  - "tests/Docs.Coverage.Tests.ps1 imports adman.psd1 and reaches Get-AdmanMenuDefinition through module scope, mirroring tests/Menu.Tests.ps1."

requirements-completed:
  - DOC-01
  - DOC-02

coverage:
  - id: D1
    description: "README.md reflects Phases 0-4 shipped state and documents prerequisites, first run, safe usage, code signing, commit guard, and DPAPI credential portability."
    requirement: DOC-01
    verification:
      - kind: unit
        ref: "tests/Docs.Coverage.Tests.ps1#README.md coverage contract"
        status: pass
    human_judgment: false
  - id: D2
    description: "docs/USAGE.md documents every non-separator menu entry from Get-AdmanMenuDefinition and every exported function from adman.psd1 FunctionsToExport."
    requirement: DOC-02
    verification:
      - kind: unit
        ref: "tests/Docs.Coverage.Tests.ps1#docs/USAGE.md menu coverage contract + exported-function coverage contract"
        status: pass
    human_judgment: false
  - id: D3
    description: "docs/RECOVERY-RUNBOOK.md documents quarantine restore, AD Recycle Bin restore, authoritative restore escalation, and certificate renewal/trust-anchor rotation."
    requirement: DOC-01
    verification:
      - kind: unit
        ref: "tests/Docs.Coverage.Tests.ps1#docs/RECOVERY-RUNBOOK.md coverage contract"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-07-22
status: complete
---

# Phase 5 Plan 01b: Documentation and Recovery Runbook Summary

**Refreshed operator docs (README, USAGE, RECOVERY-RUNBOOK) and a Pester contract test that pins docs-to-code coverage against the manifest and menu definition.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-07-22T03:00:00Z
- **Completed:** 2026-07-22T03:36:00Z
- **Tasks:** 1
- **Files modified:** 5

## Accomplishments

- Refreshed `README.md` to reflect Phases 0-4 shipped state, including installation, first-run, safe-usage, code-signing trust-anchor deployment via GPO Trusted Publishers, commit-guard installation command, and DPAPI credential portability note.
- Created `docs/USAGE.md` with a complete menu reference for `Start-Adman` and one fenced PowerShell example per exported function.
- Created `docs/RECOVERY-RUNBOOK.md` covering quarantine restore, AD Recycle Bin restore, authoritative restore escalation, and Authenticode certificate renewal/trust-anchor rotation.
- Created `tests/Docs.Coverage.Tests.ps1` to enforce the contract between documentation and the module manifest/menu definition.

## Task Commits

Each task was committed atomically:

1. **Task 3: Refresh README.md, create docs/USAGE.md, docs/RECOVERY-RUNBOOK.md, and the docs coverage contract test**
   - RED: `024f362` `test(05-01b): add failing docs coverage contract test`
   - GREEN: `62e58a8` `feat(05-01b): implement README, usage guide, recovery runbook, and docs coverage`

## Files Created/Modified

- `README.md` — Refreshed operator landing page for Phases 0-4.
- `docs/USAGE.md` — Menu reference and exported-function examples.
- `docs/RECOVERY-RUNBOOK.md` — Recovery procedures and certificate rotation.
- `tests/Docs.Coverage.Tests.ps1` — Pester contract test for docs coverage.
- `Private/Workflow/Get-AdmanOffboardingState.ps1` — Fixed parse error (extra closing brace) blocking module import.

## Decisions Made

- Used a markdown table for the menu reference so PromptSpec Name/Prompt/Required values are easy for operators to read and deterministic for the contract test to verify.
- Organized exported-function examples by operational category (foundation, search/reports, writes, bulk/workflows) rather than strict manifest order to improve readability while still covering every function.
- Documented certificate renewal as an overlap-and-retire rotation: add the new cert to Trusted Publishers, keep the old cert until all signed instances are retired, then remove the old cert.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed parse error in Get-AdmanOffboardingState.ps1**
- **Found during:** Task 3 (docs coverage test import)
- **Issue:** `Private/Workflow/Get-AdmanOffboardingState.ps1` contained a syntax error (extra closing brace) that prevented `Import-Module adman.psd1` from succeeding, blocking the docs coverage test.
- **Fix:** Removed the extra closing brace and corrected indentation so the nested `foreach` blocks close correctly.
- **Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`
- **Verification:** `Invoke-Pester -Path tests/Docs.Coverage.Tests.ps1 -Tag Unit` now passes.
- **Committed in:** `62e58a8` (GREEN task commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The parse fix was necessary to import the module and run the contract test. No scope creep.

## Issues Encountered

- Initial test run hit a Pester discovery error because `-ForEach` was populated in `BeforeAll` rather than `BeforeDiscovery`. Rewrote the parameter-coverage test as a single `It` with an inner `foreach` to keep the test deterministic and avoid discovery ordering issues.
- PowerShell regex pattern for function headings needed literal backtick handling; switched to single-quoted pattern concatenation with `[regex]::Escape`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Documentation requirements DOC-01 and DOC-02 are complete.
- The docs-to-code contract test will fail the build if future menu or export changes are not reflected in `docs/USAGE.md`.
- Remaining Phase 5 work continues in sibling plans (audit integrity, rotation, CI, signing utility, git hooks, etc.).

## Self-Check: PASSED

- `README.md` exists and contains required headings.
- `docs/USAGE.md` exists and is verified by `tests/Docs.Coverage.Tests.ps1`.
- `docs/RECOVERY-RUNBOOK.md` exists and contains required headings.
- `tests/Docs.Coverage.Tests.ps1` passes: 16 tests, 0 failures.
- Commits `024f362` and `62e58a8` exist on `master`.

---
*Phase: 05-hardening-portability*
*Completed: 2026-07-22*
