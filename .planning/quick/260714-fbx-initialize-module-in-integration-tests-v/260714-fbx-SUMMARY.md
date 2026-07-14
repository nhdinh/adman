---
phase: quick-260714-fbx
plan: 01
subsystem: testing
tags: [pester, integration-tests, active-directory, safety-gate, lab-only]

# Dependency graph
requires:
  - phase: quick-260714-ek6
    provides: module-scope `& (Get-Module adman) { Invoke-AdmanMutation ... }` wrappers in the two lab integration tests (left unchanged by this task)
  - phase: 00-foundation-safety-harness
    provides: Initialize-Adman startup orchestration, Initialize-AdmanConfig (StorePath-honoring loader + DenyList seed), Get-AdmanProtectedIdentity, Test-AdmanTargetAllowed
provides:
  - Both lab integration tests now initialize the adman module via Initialize-Adman against a $TestDrive lab config in their gated path
  - Non-vacuous protected-account refusal: AdmanProtectedGroup is the live lab Domain Admins DN, so ProtectedGroupDns is populated and the nested-admin IN_CHAIN check actually runs
  - Skip gate extended to require BOTH ADMAN_TEST_OU and ADMAN_TEST_DC
affects: [phase-00-verification, lab-uat, safety-harness]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lab-config bootstrap: write a schema-valid config.json under $TestDrive, inject $script:StorePath before Initialize-Adman so the loader reads the lab config instead of the operator's .store/"
    - "Non-vacuous safety test: seed AdmanProtectedGroup with a LIVE DN so derived protected state is non-empty and the refusal path is genuinely exercised"

key-files:
  created: []
  modified:
    - tests/Safety.WhatIf.Integration.Tests.ps1
    - tests/Safety.Protected.Integration.Tests.ps1

key-decisions:
  - "Factored the init into a single BeforeAll-scoped Initialize-AdmanLab helper per file (called in each gated It block) to avoid duplicating the 6-step bootstrap"
  - "Omitted DenyList from the lab config so Initialize-AdmanConfig seeds RID 500/501/502 from config/adman.defaults.json (single source of truth, D-05)"
  - "Extended the skip gate to require ADMAN_TEST_DC as well as ADMAN_TEST_OU, since the init path pins -Server to a DC"

patterns-established:
  - "Initialize-AdmanLab helper: $TestDrive store dir + audit/reports subdirs, live Domain Admins DN, schema-valid lab config, StorePath injection, Initialize-Adman — reusable for any future lab integration test"

requirements-completed: [SAFE-01, SAFE-06, SAFE-10]

# Coverage metadata — both deliverables are LAB-ONLY; the real run is a manual step from the
# operator's interactive runas /netonly session, so human_judgment is true. Static/parse
# verification (automated) passed and is recorded as a supporting ref.
coverage:
  - id: D1
    description: "Safety.WhatIf.Integration.Tests.ps1 initializes the module via Initialize-Adman against a $TestDrive lab config in its gated path (SAFE-01/10 end-to-end -WhatIf)"
    requirement: SAFE-01
    verification:
      - kind: other
        ref: "parse + content grep (Initialize-Adman, $script:StorePath, ADMAN_TEST_DC, AdmanProtectedGroup, config.json, >=2 Integration tags) — PASS"
        status: pass
      - kind: unit
        ref: "Invoke-Pester -Path tests -TagFilter Unit — 138 passed, 0 failed (Integration files excluded by tag filter, collection unbroken)"
        status: pass
    human_judgment: true
    rationale: "The actual -WhatIf end-to-end run requires a live lab domain reachable only from the operator's interactive runas /netonly session; automation cannot reach the lab DC. Static/parse checks pass but the functional assertion is manual."
  - id: D2
    description: "Safety.Protected.Integration.Tests.ps1 initializes the module with AdmanProtectedGroup = live lab Domain Admins DN so the nested-admin refusal is NON-vacuous (SAFE-06)"
    requirement: SAFE-06
    verification:
      - kind: other
        ref: "parse + content grep (Initialize-Adman, $script:StorePath, ADMAN_TEST_DC, AdmanProtectedGroup, config.json, >=3 Integration tags) — PASS"
        status: pass
      - kind: unit
        ref: "Invoke-Pester -Path tests -TagFilter Unit — 138 passed, 0 failed (Integration files excluded by tag filter, collection unbroken)"
        status: pass
    human_judgment: true
    rationale: "The non-vacuous nested-admin refusal must be observed against a live lab with the lab-nested-admin fixture provisioned; reachable only from the operator's interactive runas /netonly session. Static/parse checks pass but the functional assertion is manual."

# Metrics
duration: 12min
completed: 2026-07-14
status: complete
---

# Quick Task 260714-fbx: Initialize Module in Integration Tests Summary

**Both lab integration tests now bootstrap the adman module via Initialize-Adman against a $TestDrive lab config, making the protected-account refusal non-vacuous (live Domain Admins DN) and eliminating the StrictMode `$script:Config.DC` throw.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-14
- **Completed:** 2026-07-14
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added a `BeforeAll`-scoped `Initialize-AdmanLab` helper to each integration test that writes a schema-valid lab `config.json` under `$TestDrive`, injects `$script:StorePath`, and calls `Initialize-Adman` — so the gate has the config + derived safety state it needs.
- Set `AdmanProtectedGroup` to the LIVE lab Domain Admins DN, so `Get-AdmanProtectedIdentity` populates `$script:ProtectedGroupDns` and `Test-AdmanTargetAllowed` step (d) actually runs the IN_CHAIN query — the nested-admin refusal is now genuinely exercised, not a false green.
- Extended the skip gate to require BOTH `ADMAN_TEST_OU` and `ADMAN_TEST_DC`; both tests still skip cleanly when either is unset.
- Unit suite remains green (138 passed, 0 failed); both files parse with zero errors; all `-Tag 'Integration'` markers intact.

## Task Commits

Both tasks were committed together atomically (test files only, per the quick-task constraint):

1. **Task 1: Add gated Initialize-Adman startup to Safety.WhatIf.Integration.Tests.ps1** - `259f4d9` (test)
2. **Task 2: Add gated Initialize-Adman startup to Safety.Protected.Integration.Tests.ps1** - `259f4d9` (test)

**Plan metadata:** committed separately by the orchestrator (docs artifacts not committed here).

## Files Created/Modified
- `tests/Safety.WhatIf.Integration.Tests.ps1` - added `Initialize-AdmanLab` helper + call in the gated `-WhatIf` It block; extended gate to require `ADMAN_TEST_DC`; updated skip messages.
- `tests/Safety.Protected.Integration.Tests.ps1` - added `Initialize-AdmanLab` helper + calls in BOTH gated It blocks (nested-admin and gMSA/RID-500); extended gate to require `ADMAN_TEST_DC`; updated skip messages.

## Decisions Made
- **Helper over duplication (Protected file):** the Protected test has two gated It blocks; factored the 6-step init into a single `Initialize-AdmanLab` function in `BeforeAll` and called it in each block, per the plan's stated preference.
- **Omit DenyList from the lab config:** `Initialize-AdmanConfig` seeds RID 500/501/502 from `config/adman.defaults.json` when `DenyList` is absent (D-05), so the lab config stays minimal and the deny-list remains the single source of truth.
- **Require ADMAN_TEST_DC in the gate:** the init path pins `-Server` to a DC for the `Get-ADGroup 'Domain Admins'` lookup and the config's `DC` key, so a DC must be configured — the gate now reflects that.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- **Bash shell-escaping of inline PowerShell:** the per-task verify one-liners and the Pester invocation were mangled by bash double-quoting (`$ErrorActionPreference`, `$env:PSModulePath`, `$script:StorePath` regex). Resolved by writing the verify script and the Unit-run script to temp `.ps1` files under `.gsd/` and invoking them with `powershell.exe -NoProfile -File`, then deleting them. No impact on the committed artifacts.

## User Setup Required
None - no external service configuration required. (Lab execution itself is a manual step from the operator's interactive `runas /netonly` session with `ADMAN_TEST_OU` + `ADMAN_TEST_DC` set; the executor correctly did NOT attempt to run the Integration-tagged tests.)

## Next Phase Readiness
- Both lab integration tests are ready for a manual lab run: set `$env:ADMAN_TEST_OU` and `$env:ADMAN_TEST_DC`, then `Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration` (and the Protected file likewise) from a `runas /netonly` session with lab-admin rights.
- No production code changed; the ek6 module-scope `Invoke-AdmanMutation` wrappers are unchanged.
- No blockers. Phase 00 remains complete/verifying; this quick task only hardened the two lab tests.

## Self-Check: PASSED

- SUMMARY.md exists at `.planning/quick/260714-fbx-initialize-module-in-integration-tests-v/260714-fbx-SUMMARY.md` with `status: complete` in frontmatter.
- Commit `259f4d9` exists in git history (`git log --oneline --all`).
- Both test files committed cleanly (`git status --short tests/` is empty).
- No file deletions in the commit (`git diff --diff-filter=D HEAD~1 HEAD` empty).

---
*Phase: quick-260714-fbx*
*Completed: 2026-07-14*
