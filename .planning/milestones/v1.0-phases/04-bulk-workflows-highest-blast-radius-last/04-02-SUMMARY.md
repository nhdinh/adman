---
phase: 04-bulk-workflows-highest-blast-radius-last
plan: 02
subsystem: ad-management
tags: [powershell, active-directory, onboarding, workflow, safety-gate, pester]

requires:
  - phase: 00-foundation-safety-harness
    provides: Invoke-AdmanMutation gate, Test-AdmanGroupAllowed, Confirm-AdmanAction, Write-AdmanAudit
  - phase: 02-single-object-writes
    provides: New-AdmanUser, Add-AdmanGroupMember Public verbs
  - phase: 04-bulk-workflows-highest-blast-radius-last
    plan: 01
    provides: templates.onboarding, top-level domain key in config

provides:
  - Public/Start-AdmanUserOnboarding composes create + baseline group adds under one outer confirmation
  - Config-driven onboarding template enforcement (ParentOuDn, BaselineGroups, NamePattern, domain)
  - Generated sAMAccountName preflight (non-empty, <=20, no wildcards)
  - Baseline group policy validation before any AD write
  - Mid-workflow failure audit + stop semantics for FLOW-04

affects:
  - 04-03-offboarding-workflow
  - 04-04-menu-integration

tech-stack:
  added: []
  patterns:
    - Workflow verb = one outer Confirm-AdmanAction + composed single-object verbs with -Force:$true
    - Template config is authority; operator cannot override ParentOuDn at runtime
    - Preflight derived identities before confirmation to catch malformed/overlong patterns early

key-files:
  created:
    - Public/Start-AdmanUserOnboarding.ps1
    - tests/Workflow.Onboarding.Tests.ps1
  modified:
    - adman.psd1

key-decisions:
  - "Password display-once hygiene remains inside New-AdmanUser; the workflow does not duplicate it"
  - "Workflow passes -Force:$true to composed verbs so the outer confirmation is the only operator prompt"
  - "Baseline group validation runs before user creation so a protected destination fails the entire job early"

patterns-established:
  - "Onboarding workflow builds the request from config template, preflights derived identity, validates groups, confirms once, then composes existing verbs"
  - "Mid-workflow failures write a Failure audit and rethrow, stopping later steps for that target"

requirements-completed:
  - FLOW-01
  - FLOW-04

coverage:
  - id: D1
    description: "Start-AdmanUserOnboarding Public verb implementing config-driven new-user onboarding with one outer confirmation and forced inner verbs"
    requirement: FLOW-01
    verification:
      - kind: unit
        ref: "tests/Workflow.Onboarding.Tests.ps1#happy path + composition describe block"
        status: pass
      - kind: unit
        ref: "tests/Workflow.Onboarding.Tests.ps1#parameter + preflight validation describe block"
        status: pass
    human_judgment: false
  - id: D2
    description: "Mid-workflow failure writes Failure audit and stops subsequent baseline group adds"
    requirement: FLOW-04
    verification:
      - kind: unit
        ref: "tests/Workflow.Onboarding.Tests.ps1#mid-workflow failure describe block"
        status: pass
    human_judgment: false
  - id: D3
    description: "Baseline groups validated through Test-AdmanGroupAllowed before user creation or group add"
    requirement: FLOW-01
    verification:
      - kind: unit
        ref: "tests/Workflow.Onboarding.Tests.ps1#baseline group policy describe block"
        status: pass
    human_judgment: false

duration: 5m
completed: 2026-07-20
status: complete
---

# Phase 04 Plan 02: Onboarding Workflow Summary

**Config-driven new-user onboarding workflow that composes `New-AdmanUser` and `Add-AdmanGroupMember` under a single outer confirmation, with preflight identity validation and baseline-group policy enforcement.**

## Performance

- **Duration:** 5m
- **Started:** 2026-07-20T07:13:27Z
- **Completed:** 2026-07-20T07:18:44Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `Public/Start-AdmanUserOnboarding.ps1` with mandatory `[ValidateNotNullOrEmpty()]` parameters for `FirstName` and `LastName`.
- Built sAMAccountName/UPN from `templates.onboarding.NamePattern` and the top-level `domain` config key.
- Added preflight checks for generated sAMAccountName (non-empty, <=20 chars, no wildcards) before confirmation.
- Validated every baseline group through `Resolve-AdmanGroup` + `Test-AdmanGroupAllowed` before creating the user or adding memberships.
- Implemented one outer `Confirm-AdmanAction` and called composed verbs with `-Force:$true` to suppress inner re-prompts.
- Added try/catch around the workflow body to write a `Failure` audit and rethrow on mid-workflow failure (FLOW-04).
- Exported `Start-AdmanUserOnboarding` in `adman.psd1`.
- Added 14 unit tests covering happy path, group policy, failure-stop, partial group-add failure, confirmation behavior, -WhatIf propagation, and parameter/preflight validation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement Start-AdmanUserOnboarding with one outer confirmation** - `ed7afae` (feat)
2. **Task 2: Write onboarding workflow unit tests** - `ee92a35` (test)

## Files Created/Modified

- `Public/Start-AdmanUserOnboarding.ps1` - New Public workflow verb for gated new-user onboarding.
- `tests/Workflow.Onboarding.Tests.ps1` - 14 unit tests covering FLOW-01/FLOW-04 behaviors.
- `adman.psd1` - Added `Start-AdmanUserOnboarding` to `FunctionsToExport`.

## Decisions Made

- Kept password display-once hygiene inside `New-AdmanUser` (D-14); the workflow intentionally does not duplicate it.
- Used `-Force:$true` on composed verbs so the workflow's outer confirmation is the only operator prompt, while inner policy/audit still run.
- Validated baseline groups before user creation so a protected destination fails the entire job before any AD write.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Initial `-WhatIf` propagation test used `$WhatIfPreference` in the `Should -Invoke ParameterFilter`, but Pester binds the mocked parameter as `$WhatIf`. Updated the filter to `$WhatIf -eq $true`; all tests pass.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

No security-relevant surface beyond the planned onboarding workflow boundaries was introduced. The plan's threat register (T-04-08..T-04-11) was implemented as specified:

| Threat ID | Mitigation implemented |
|-----------|------------------------|
| T-04-08 | Baseline groups validated through `Test-AdmanGroupAllowed` before user creation or group add. |
| T-04-09 | Workflow writes a `Failure` audit record on any step failure before rethrowing. |
| T-04-10 | Preflight rejects empty, >20-char, or wildcard-containing generated sAMAccountName. |
| T-04-11 | `[ValidateNotNullOrEmpty()]` rejects empty FirstName/LastName at parameter binding. |

## Next Phase Readiness

- Onboarding workflow is ready for 04-04 menu integration.
- Offboarding workflow (04-03) can follow the same composition pattern.
- No blockers.

## Self-Check: PASSED

- [x] `Public/Start-AdmanUserOnboarding.ps1` exists
- [x] `tests/Workflow.Onboarding.Tests.ps1` exists
- [x] `adman.psd1` exports `Start-AdmanUserOnboarding`
- [x] Commits `ed7afae`, `ee92a35` exist
- [x] Onboarding unit tests pass: 14 passed, 0 failed
- [x] PSScriptAnalyzer reports no violations on `Public/Start-AdmanUserOnboarding.ps1`

---
*Phase: 04-bulk-workflows-highest-blast-radius-last*
*Completed: 2026-07-20*
