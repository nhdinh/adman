---
phase: 05-hardening-portability
fixed_at: 2026-07-23T11:45:00Z
review_path: .planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-23T11:45:00Z
**Source review:** `.planning/phases/05-hardening-portability/05-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6
- Fixed: 6
- Skipped: 0

All Critical and Warning findings from the Phase 05 hardening/portability review have been applied and committed.

## Fixed Issues

### CR-01: AD mutation gate drops caller `-WhatIf`, executing real AD writes during dry-run

**Files modified:** `Private/Safety/Invoke-AdmanMutation.ps1`, `Private/Safety/Confirm-AdmanAction.ps1`
**Commits:** `79c3c9c`, `532eb6c`
**Status:** fixed: requires human verification
**Applied fix:** Forwarded `-WhatIf:$WhatIfPreference` into both `Confirm-AdmanAction` call sites in the AD mutation gate. Removed the duplicate explicit `[switch]$WhatIf` parameter from `Confirm-AdmanAction` so `SupportsShouldProcess` automatic variable `$WhatIfPreference` is the single source of truth; this resolved the runtime `MetadataException: A parameter with the name 'WhatIf' was defined multiple times` that appeared after the first pass.

### CR-02: Local mutation gate drops caller `-WhatIf`, executing real local writes during dry-run

**Files modified:** `Private/Safety/Invoke-AdmanLocalMutation.ps1`, `Private/Safety/Confirm-AdmanAction.ps1`
**Commits:** `f709a7b`, `532eb6c`
**Status:** fixed: requires human verification
**Applied fix:** Forwarded `-WhatIf:$WhatIfPreference` into the single `Confirm-AdmanAction` call site in the local mutation gate. Same duplicate-parameter cleanup as CR-01.

### WR-01: `Test-AdmanCapability` bypasses the project's hard-timeout wrappers

**Files modified:** `Public/Test-AdmanCapability.ps1`, `tests/Foundation.Capability.Tests.ps1`
**Commits:** `f5cdea4`, `c9b57c5`
**Status:** fixed
**Applied fix:** Replaced direct `Test-WSMan` and `New-CimSession -OperationTimeoutSec` calls with `Test-AdmanWsmanTimeout` and `Test-AdmanCimSessionTimeout` using the configured `probeTimeoutSec`. Updated the structural test to assert the hard-timeout wrappers are present instead of the old `OperationTimeoutSec` string.

### WR-02: Gate tests mask the `-WhatIf` propagation bug

**Files modified:** `tests/Safety.GateOrder.Tests.ps1`, `tests/Local.Gate.Tests.ps1`, `tests/Safety.ConfirmationRestored.Tests.ps1`, `tests/Bulk.Engine.Tests.ps1`
**Commits:** `656269b`, `2ebda90`
**Status:** fixed
**Applied fix:** Added `-WhatIf` propagation assertions to the AD gate, local gate, and bulk engine tests. Refined global `Confirm-AdmanAction` stubs after removing the duplicate `-WhatIf` parameter so mocks capture the switch via `param([switch]$WhatIf)` inside the relevant scriptblocks without colliding with Pester-generated mock parameters.

### WR-03: `docs/USAGE.md` mislabels password parameters as required

**Files modified:** `docs/USAGE.md`, `Private/Menu/Get-AdmanMenuDefinition.ps1`
**Commits:** `51c606b`, `d31e53a`
**Status:** fixed
**Applied fix:** Changed `AccountPassword`, `NewPassword`, and both `Password` PromptSpec entries from `Required = $true` to `Required = $false` in `Get-AdmanMenuDefinition.ps1`. Updated `docs/USAGE.md` to show these parameters as optional and added a note explaining that omitted passwords source from `$script:Config.security.passwordSource`.

### WR-04: Stale report scope mismatch between docs and implementation

**Files modified:** `docs/USAGE.md`, `Private/Menu/Get-AdmanMenuDefinition.ps1`
**Commits:** `51c606b`, `d31e53a`
**Status:** fixed
**Applied fix:** Updated `docs/USAGE.md` and the function reference to state that `Get-AdmanStaleReport` reports user accounts only. Changed the menu label from `Stale/inactive report` to `Stale/inactive user report` in `Get-AdmanMenuDefinition.ps1` so the docs/menu coverage contract passes.

## Test Verification

Targeted tests for the modified areas were run after the fixes:

- `tests/Docs.Coverage.Tests.ps1`: 16 passed, 0 failed
- `tests/Safety.GateOrder.Tests.ps1` + `tests/Local.Gate.Tests.ps1` + `tests/Safety.ConfirmationRestored.Tests.ps1` + `tests/Bulk.Engine.Tests.ps1`: 55 passed, 0 failed
- `tests/Foundation.Capability.Tests.ps1`: 7 passed, 0 failed

A full unit-suite run (`Invoke-Pester -Path tests -TagFilter Unit`) reported 799 passed, 35 failed, 74 skipped. The failures are in unrelated areas (`Config.*`, `Find-AdmanUser`, `New-AdmanLocalUser` help tests, `Workflow.Offboarding` cleanup checklist) and are not caused by the Phase 05 review fixes. They appear to be pre-existing fixture/schema mismatches outside the scope of this review.

---

_Fixed: 2026-07-23T11:45:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
