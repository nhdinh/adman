---
phase: 04-bulk-workflows-highest-blast-radius-last
plan: 03
subsystem: workflow
tags: [powershell, active-directory, audit, workflow, offboarding, restore]

requires:
  - phase: 00-foundation-safety-harness
    provides: Write-AdmanAudit, Confirm-AdmanAction, Resolve-AdmanTarget, managed-OU scope checks
  - phase: 02-single-object-lifecycle
    provides: Disable/Enable-AdmanUser, Move-AdmanUser, Add/Remove-AdmanGroupMember
  - phase: 04-bulk-workflows-highest-blast-radius-last
    plan: 01
    provides: config template keys (templates.offboarding.quarantineOU)

provides:
  - Reversible offboarding workflow (Start-AdmanUserOffboarding) with SID-based protected-group classification.
  - Restore verb (Restore-AdmanQuarantinedUser) that reverses offboarding from the authoritative audit log.
  - Private state reader (Get-AdmanOffboardingState) with exact DN/SID matching and no arbitrary lookback cutoff.
  - Extended audit schema that emits originalOU/groups only for offboarding records, preserving D-03 invariants.

affects:
  - 04-04-menu-integration-manifest
  - 05-hardening-portability

tech-stack:
  added: []
  patterns:
    - Workflow verbs compose single-object verbs under one outer Confirm-AdmanAction; inner calls use -Force:$true.
    - Restore state is sourced from the fail-closed audit log, not a separate database.
    - Ordering invariant: restore re-adds groups and moves back to original OU before enabling the account last.

key-files:
  created:
    - Private/Workflow/Get-AdmanOffboardingState.ps1
    - Public/Start-AdmanUserOffboarding.ps1
    - Public/Restore-AdmanQuarantinedUser.ps1
    - tests/Workflow.Offboarding.Tests.ps1
    - tests/Workflow.Restore.Tests.ps1
  modified:
    - Private/Audit/Write-AdmanAudit.ps1
    - adman.psd1

key-decisions:
  - "Restore state is read from the authoritative audit log (no separate store), keeping one source of truth and leveraging the existing fail-closed write path."
  - "Protected-group classification resolves memberOf groups to SIDs and checks ProtectedSIDs, DenyRids, and ProtectedGroupDns (including unresolved SID strings)."
  - "Restore ordering is groups -> move -> enable-last so a partial failure leaves the account disabled."

patterns-established:
  - "Workflow outer confirmation: one Confirm-AdmanAction per target workflow; composed verbs run with -Force:$true."
  - "Audit-driven restore: workflow state is the latest successful, non-dry-run audit record matched by exact DN/SID."
  - "Schema-preserving audit extension: optional keys emitted only when supplied."

requirements-completed: [FLOW-02, FLOW-03, FLOW-04]

coverage:
  - id: D1
    description: "Audit writer emits originalOU and groups keys only when supplied, preserving exact D-03 key set for all other records."
    requirement: FLOW-04
    verification:
      - kind: unit
        ref: "tests/Audit.Schema.Tests.ps1#Test 1b/1c"
        status: pass
    human_judgment: false
  - id: D2
    description: "Offboarding workflow disables user, strips only non-protected groups, moves to quarantine OU, and records originalOU/groups."
    requirement: FLOW-02
    verification:
      - kind: unit
        ref: "tests/Workflow.Offboarding.Tests.ps1#happy path + composition"
        status: pass
    human_judgment: false
  - id: D3
    description: "Protected-group classification uses resolved SIDs and covers unresolved-SID entries stored in ProtectedGroupDns."
    requirement: FLOW-02
    verification:
      - kind: unit
        ref: "tests/Workflow.Offboarding.Tests.ps1#protected-group classification"
        status: pass
    human_judgment: false
  - id: D4
    description: "Offboarding presents one outer confirmation before any destructive step and propagates -WhatIf to composed verbs."
    requirement: FLOW-02
    verification:
      - kind: unit
        ref: "tests/Workflow.Offboarding.Tests.ps1#confirmation / -WhatIf tests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Mid-offboarding failure stops later steps and writes a Failure audit."
    requirement: FLOW-04
    verification:
      - kind: unit
        ref: "tests/Workflow.Offboarding.Tests.ps1#Failure audit on step throw"
        status: pass
    human_judgment: false
  - id: D6
    description: "Restore reads the latest successful, non-dry-run offboarding record by exact DN/SID match, with no 30-day cutoff."
    requirement: FLOW-03
    verification:
      - kind: unit
        ref: "tests/Workflow.Restore.Tests.ps1#exact-match state reader"
        status: pass
    human_judgment: false
  - id: D7
    description: "Restore refuses when the user is not currently in the configured quarantine OU."
    requirement: FLOW-03
    verification:
      - kind: unit
        ref: "tests/Workflow.Restore.Tests.ps1#not-in-quarantine refusal"
        status: pass
    human_judgment: false
  - id: D8
    description: "Restore re-adds groups and moves back to the original OU before enabling the account last."
    requirement: FLOW-03
    verification:
      - kind: unit
        ref: "tests/Workflow.Restore.Tests.ps1#reverse offboarding ordering"
        status: pass
    human_judgment: false
  - id: D9
    description: "Mid-restore failure writes a Failure audit and leaves the account disabled when enable has not run."
    requirement: FLOW-04
    verification:
      - kind: unit
        ref: "tests/Workflow.Restore.Tests.ps1#partial failure leaves disabled"
        status: pass
    human_judgment: false

# Metrics
duration: 45min
completed: 2026-07-20
status: complete
---

# Phase 4 Plan 3: Offboarding + Restore Summary

**Reversible offboarding workflow and restore verb with audit-log-sourced state, SID-based protected-group classification, and enable-last ordering invariant.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-07-20T14:37:00Z
- **Completed:** 2026-07-20T15:22:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Extended `Write-AdmanAudit` with optional `OriginalOU`/`Groups` keys while preserving the D-03 exact-key-set invariant for non-offboarding records.
- Implemented `Start-AdmanUserOffboarding` with one outer confirmation, SID/RID/DN protected-group classification, quarantine-OU scope validation, and manual-only cleanup checklist.
- Implemented `Get-AdmanOffboardingState` to read the latest successful non-dry-run offboarding record by exact user DN/SID from all available audit files.
- Implemented `Restore-AdmanQuarantinedUser` to reverse offboarding in the safer order (groups -> move -> enable last) with quarantine-OU and original-OU scope checks.
- Added 31 unit tests across audit schema, offboarding, and restore; all pass. PSScriptAnalyzer reports no violations on the two new Public functions.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend Write-AdmanAudit with optional OriginalOU and Groups fields** - `0bc5452` (feat)
2. **Task 2: Implement offboarding workflow with SID-based protected-group classification** - `57f6749` (feat)
3. **Task 3: Implement exact-match offboarding state reader and restore verb** - `3b32225` (feat)

## Files Created/Modified
- `Private/Audit/Write-AdmanAudit.ps1` - Conditionally emits `originalOU` and `groups` keys.
- `Private/Workflow/Get-AdmanOffboardingState.ps1` - Reads authoritative restore state from audit JSONL.
- `Public/Start-AdmanUserOffboarding.ps1` - Reversible offboarding workflow (FLOW-02).
- `Public/Restore-AdmanQuarantinedUser.ps1` - Restore-from-quarantine workflow (FLOW-03).
- `tests/Workflow.Offboarding.Tests.ps1` - Offboarding unit tests.
- `tests/Workflow.Restore.Tests.ps1` - Restore/state-reader unit tests.
- `adman.psd1` - Exported `Start-AdmanUserOffboarding` and `Restore-AdmanQuarantinedUser`.

## Decisions Made
- Restore state is sourced from the audit log rather than a separate store, keeping one authoritative source of truth and reusing the existing fail-closed write path.
- Protected-group classification resolves `memberOf` entries to SIDs and checks `ProtectedSIDs`, `DenyRids`, and `ProtectedGroupDns` (including unresolved SID strings), matching the review finding.
- Restore ordering is groups first, then OU move, then enable last, so a partial failure leaves the account disabled.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 4 plan 04-04 (menu integration + manifest exports + phase exit gate) can now wire the new offboarding/restore verbs into `Get-AdmanMenuDefinition` and run the recursive lint/full-suite gate.
- All FLOW-02/03/04 acceptance criteria are satisfied and covered by passing unit tests.

## Self-Check: PASSED
- All created files exist on disk.
- Task commits `0bc5452`, `57f6749`, `3b32225` exist in git history.
- Combined unit suite passed 31/31 tests.
- PSScriptAnalyzer reported no violations on the two new Public functions.

---
*Phase: 04-bulk-workflows-highest-blast-radius-last*
*Completed: 2026-07-20*
