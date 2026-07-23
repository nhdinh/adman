---
phase: 04-bulk-workflows-highest-blast-radius-last
plan: 01
subsystem: ad-management
tags: [powershell, active-directory, bulk-operations, safety-gate, pester]

requires:
  - phase: 00-foundation-safety-harness
    provides: Invoke-AdmanMutation gate, Test-AdmanTargetAllowed, Test-AdmanGroupAllowed, Confirm-AdmanAction, Assert-AdmanBulkPolicy
  - phase: 01-read-only-reporting
    provides: Find-AdmanUser/Find-AdmanComputer D-03 shaped output used as bulk pipeline input
  - phase: 02-single-object-writes
    provides: Public single-object verbs and their mapped gate verbs

provides:
  - Generic gated bulk engine `Invoke-AdmanBulkAction` accepting pipeline search output and strict-schema CSV
  - Canonical bulk input record `{ObjectType, Identity, Action, TargetPath, GroupIdentity}`
  - `Import-AdmanBulkCsv` with unknown/duplicate/missing-header rejection
  - `ConvertTo-AdmanBulkInput` normalizer for search/report pipeline objects
  - `Confirm-AdmanAction -RequireTypedCount` for mandatory typed-count confirmation
  - Template config keys (`domain`, `templates.onboarding`, `templates.offboarding`) with Phase 4 additive migration

affects:
  - 04-02-onboarding-workflow
  - 04-03-offboarding-workflow

tech-stack:
  added: []
  patterns:
    - Single generic bulk engine for all supported actions (Disable/Enable/Move/AddGroup/RemoveGroup)
    - Cap enforcement after deny/scope/protected filtering (D-07)
    - One typed-count confirmation for the exact filtered set
    - Per-item gate invocation with -Force to suppress N inner confirmations
    - Pre-validation of group destinations before cap/confirm

key-files:
  created:
    - Public/Invoke-AdmanBulkAction.ps1
    - Private/Bulk/Import-AdmanBulkCsv.ps1
    - Private/Bulk/ConvertTo-AdmanBulkInput.ps1
    - tests/Bulk.Engine.Tests.ps1
    - tests/Bulk.Csv.Tests.ps1
  modified:
    - config/adman.schema.json
    - config/adman.defaults.json
    - Private/Config/Initialize-AdmanConfig.ps1
    - Private/Safety/Confirm-AdmanAction.ps1
    - tests/Config.Load.Tests.ps1
    - tests/Safety.Confirm.Tests.ps1
    - adman.psd1

key-decisions:
  - "Identity in the canonical bulk record is the object's DistinguishedName, matching the D-03 schema output from find/report verbs"
  - "-Force on Invoke-AdmanBulkAction skips only the outer typed-count confirmation; per-item policy/audit still run via Invoke-AdmanMutation -Force:$true"
  - "Group destination policy (Test-AdmanGroupAllowed) is resolved and validated before Assert-AdmanBulkPolicy and Confirm-AdmanAction"
  - "Move no-ops are detected by comparing normalized parent DN to TargetPath and skipped with a Success audit note"

patterns-established:
  - "Bulk engine normalizes every input source (pipeline, CSV) to one record shape before cap/confirm/dispatch"
  - "All per-item mutations flow through Invoke-AdmanMutation so the single safety spine owns audit and policy"

requirements-completed:
  - BULK-01
  - BULK-02
  - BULK-03
  - BULK-04

coverage:
  - id: D1
    description: "Template config keys (domain, onboarding/offboarding templates) added to schema, defaults, and loader migration"
    requirement: BULK-04
    verification:
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#Phase 4 template config describe block"
        status: pass
    human_judgment: false
  - id: D2
    description: "Confirm-AdmanAction -RequireTypedCount forces typed-count confirmation regardless of threshold"
    requirement: BULK-02
    verification:
      - kind: unit
        ref: "tests/Safety.Confirm.Tests.ps1#-RequireTypedCount tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Strict-schema CSV loader rejects unknown, duplicate, and missing required headers"
    requirement: BULK-04
    verification:
      - kind: unit
        ref: "tests/Bulk.Csv.Tests.ps1#Import-AdmanBulkCsv strict schema"
        status: pass
    human_judgment: false
  - id: D4
    description: "Generic gated bulk engine dispatches pipeline and CSV input through Invoke-AdmanMutation with cap-after-filter, typed-count confirm, continue-on-failure, and WhatIf"
    requirement: BULK-01
    verification:
      - kind: unit
        ref: "tests/Bulk.Engine.Tests.ps1#Invoke-AdmanBulkAction engine"
        status: pass
    human_judgment: false

duration: 45m (this session; continued from prior work)
completed: 2026-07-20
status: complete
---

# Phase 04 Plan 01: Gated Bulk Engine Summary

**Generic `Invoke-AdmanBulkAction` engine that normalizes pipeline search output and strict-schema CSV into one gated record shape, enforces cap after filtering, prompts once with the exact filtered count, and dispatches per-item mutations through the existing safety spine.**

## Performance

- **Duration:** 45m (this session; continued from prior work)
- **Started:** continuation from prior session
- **Completed:** 2026-07-20T04:11:27Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- Added `domain` and `templates` (onboarding/offboarding) keys to config schema/defaults with a non-destructive Phase 4 migration in `Initialize-AdmanConfig`.
- Extended `Confirm-AdmanAction` with `-RequireTypedCount` so the bulk engine always prompts with the exact filtered count.
- Hardened `Import-AdmanBulkCsv` to reject unknown, duplicate, and missing required headers before any gate call.
- Created `ConvertTo-AdmanBulkInput` to normalize `Find-AdmanUser`/`Find-AdmanComputer`/report output into the canonical bulk record shape.
- Implemented `Invoke-AdmanBulkAction` supporting pipeline and CSV input for Disable/Enable/Move/AddGroup/RemoveGroup.
- Wired cap-after-filter, one typed-count confirmation, group destination pre-validation, per-item `-Force` gate calls, no-op detection, and continue-on-failure summary reporting.
- Added 66 passing unit tests across config load, confirmation, CSV handling, and the bulk engine.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add onboarding/offboarding template keys, top-level domain key, and Phase 4 config migration** - `2441766` (feat)
2. **Task 2: Extend Confirm-AdmanAction with -RequireTypedCount and harden CSV header validation** - `93e29e4` (feat)
3. **Task 3: Implement the generic gated bulk engine** - `cd850e3` (feat)

## Files Created/Modified

- `config/adman.schema.json` - Added `domain` and `templates` properties; `domain` added to `required`.
- `config/adman.defaults.json` - Added `domain` and onboarding/offboarding template defaults.
- `Private/Config/Initialize-AdmanConfig.ps1` - Phase 4 additive migration seeds missing `domain`/`templates` from defaults before validation.
- `Private/Safety/Confirm-AdmanAction.ps1` - Added `-RequireTypedCount` switch and prompt branch.
- `Private/Bulk/Import-AdmanBulkCsv.ps1` - Strict-schema CSV loader with header validation.
- `Private/Bulk/ConvertTo-AdmanBulkInput.ps1` - Pipeline normalizer to canonical bulk record shape.
- `Public/Invoke-AdmanBulkAction.ps1` - Generic gated bulk engine.
- `tests/Config.Load.Tests.ps1` - Phase 4 migration coverage.
- `tests/Safety.Confirm.Tests.ps1` - `-RequireTypedCount` coverage.
- `tests/Bulk.Csv.Tests.ps1` - CSV header and pipeline normalization tests.
- `tests/Bulk.Engine.Tests.ps1` - Bulk engine behavior tests (13 tests).
- `adman.psd1` - Exported `Invoke-AdmanBulkAction`.

## Decisions Made

- Followed the plan's decision to use DistinguishedName as the canonical `Identity` in bulk records; this lets pipeline output from find/report verbs flow directly into the engine.
- `-Force` skips only the outer typed-count confirmation; per-item policy and audit remain active through `Invoke-AdmanMutation -Force:$true`.
- Group destination policy is validated before cap/confirm so a protected destination fails the entire job before any operator confirmation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed comment terminator in Invoke-AdmanBulkAction.ps1**
- **Found during:** Task 3 verification
- **Issue:** File used `#}` instead of `#>` to close the `.EXAMPLE` comment block, causing a parse error on module import.
- **Fix:** Replaced `#}` with `#>`.
- **Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
- **Verification:** `Invoke-Pester -Path tests/Bulk.Engine.Tests.ps1 -Tag Unit` passes.
- **Committed in:** `cd850e3`

**2. [Rule 1 - Bug] Fixed array handling for bound -InputObject**
- **Found during:** Task 3 verification
- **Issue:** When `-InputObject @(...)` was passed as a bound parameter (not via the pipeline), the `process` block stored the entire array as a single item, causing malformed records.
- **Fix:** Enumerate `IEnumerable` (excluding strings) in the `process` block so each element becomes its own record.
- **Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
- **Verification:** Pipeline-input tests pass with multiple objects.
- **Committed in:** `cd850e3`

**3. [Rule 1 - Bug] Fixed strict-mode Count access on single Where-Object results**
- **Found during:** Task 3 verification
- **Issue:** `($perItem | Where-Object { ... }).Count` throws under `Set-StrictMode -Version Latest` in Windows PowerShell 5.1 when the filter returns a single PSCustomObject.
- **Fix:** Wrapped `Where-Object` results in `@(...)` to guarantee an array with a `Count` property.
- **Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
- **Verification:** Summary-object tests pass.
- **Committed in:** `cd850e3`

**4. [Rule 1 - Bug] Fixed -Force behavior on outer confirmation**
- **Found during:** Task 3 verification
- **Issue:** The engine called `Confirm-AdmanAction` even when `-Force` was specified, contradicting the documented senior escape hatch.
- **Fix:** Skip `Confirm-AdmanAction` when `-Force` is set and synthesize a Proceed outcome; per-item gates still run.
- **Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
- **Verification:** `-Force skips outer confirmation but inner policy/audit still run` test passes.
- **Committed in:** `cd850e3`

**5. [Rule 1 - Bug] Fixed test mocks to use DistinguishedName-based Identity**
- **Found during:** Task 3 verification
- **Issue:** Engine tests used short-name (`u1`, `u2`) comparisons in mocks, but the implementation follows the plan and uses full DistinguishedName as Identity.
- **Fix:** Updated `Invoke-AdmanMutation` and `Test-AdmanTargetAllowed` mocks in the failure and denied tests to compare against full DNs; updated `Resolve-AdmanTarget` mock in the denied test to pass through the input DN.
- **Files modified:** `tests/Bulk.Engine.Tests.ps1`
- **Verification:** `continues on single-item failure` and `counts denied items` tests pass.
- **Committed in:** `cd850e3`

---

**Total deviations:** 5 auto-fixed (all Rule 1 bugs)
**Impact on plan:** All fixes were necessary for the engine to import and behave correctly. No scope creep.

## Issues Encountered

- Initial Task 3 test run failed due to a parse error (`#}` comment terminator) introduced when the file was authored. Fixed immediately.
- Windows PowerShell 5.1 strict mode exposed single-object `.Count` access after `Where-Object`. Fixed by array-subexpression `@(...)`.
- Test mocks assumed short-name Identity while the implementation uses DistinguishedName per the plan. Updated tests to match the plan.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

No security-relevant surface beyond the planned bulk engine boundaries was introduced.

## Next Phase Readiness

- Bulk engine is ready for 04-02 (onboarding workflow) and 04-03 (offboarding workflow) to consume `Invoke-AdmanBulkAction`.
- Template config keys (`domain`, `templates.onboarding`, `templates.offboarding`) are loaded and migrated.
- No blockers.

## Self-Check: PASSED

- [x] `Public/Invoke-AdmanBulkAction.ps1` exists
- [x] `Private/Bulk/Import-AdmanBulkCsv.ps1` exists
- [x] `Private/Bulk/ConvertTo-AdmanBulkInput.ps1` exists
- [x] `tests/Bulk.Engine.Tests.ps1` exists
- [x] `tests/Bulk.Csv.Tests.ps1` exists
- [x] Commits `2441766`, `93e29e4`, `cd850e3` exist
- [x] Combined unit tests pass: 66 passed, 0 failed
- [x] PSScriptAnalyzer reports no violations on `Public/Invoke-AdmanBulkAction.ps1` or `Private/Config/Initialize-AdmanConfig.ps1`

---
*Phase: 04-bulk-workflows-highest-blast-radius-last*
*Completed: 2026-07-20*
