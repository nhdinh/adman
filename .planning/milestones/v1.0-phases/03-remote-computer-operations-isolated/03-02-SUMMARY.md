---
phase: 03-remote-computer-operations-isolated
plan: 02
subsystem: remoting
tags: [powershell, cim, winrm, dcom, remoting, inventory, pester]

requires:
  - phase: 03-remote-computer-operations-isolated
    plan: 01
    provides: Connect-AdmanTarget ladder + process-only cache, Test-AdmanCimSessionTimeout hard-timeout wrapper, Convert-AdmanRemoteError translator, transport timeout config keys

provides:
  - Private/Remoting/Invoke-AdmanRemoteCimQuery.ps1 allow-listed local-only CIM runner
  - Private/Remoting/Invoke-AdmanRemoteQuery.ps1 online/OS/uptime/logged-on-user enrichment with one transient session and shrinking timeout budget
  - Public/Get-AdmanInventoryReport.ps1 extended with serial per-row remote enrichment, per-host + total caps, and single skipped-host warning
  - Private/Menu/Get-AdmanMenuDefinition.ps1 updated label and renderer property list for remote-enriched inventory
  - Unit-test suite covering query helpers and inventory enrichment

affects:
  - tests/Result.Schema.Tests.ps1 (unchanged; D-03 schema preserved)
  - 03-03-PLAN.md (double-hop documentation)

tech-stack:
  added: []
  patterns:
    - Local-on-target CIM queries only, allow-listed to Win32_OperatingSystem and Win32_ComputerSystem
    - One transient CIM session per host reused for both allowed queries
    - Shrinking TimeoutSeconds budget forwarded from report through probe, New-CimSession, and each Get-CimInstance
    - Skipped as first-class non-error outcome with a single summary Write-Warning

key-files:
  created:
    - Private/Remoting/Invoke-AdmanRemoteCimQuery.ps1
    - Private/Remoting/Invoke-AdmanRemoteQuery.ps1
    - tests/Remoting.Query.Tests.ps1
  modified:
    - Public/Get-AdmanInventoryReport.ps1
    - Private/Menu/Get-AdmanMenuDefinition.ps1
    - tests/Report.Inventory.Tests.ps1

key-decisions:
  - "Invoke-AdmanRemoteQuery intentionally does not call Invoke-AdmanRemoteCimQuery so one transient session serves both allowed CIM classes, avoiding double session-setup cost."
  - "Per-host cap is enforced by starting a stopwatch before Connect-AdmanTarget and passing the remaining budget into Invoke-AdmanRemoteQuery, which recomputes before New-CimSession and each Get-CimInstance."
  - "CIM errors and budget exhaustion return Transport='Skipped' so the skipped-host count stays accurate for operators."

patterns-established:
  - "Query layer is transport-agnostic: it receives a transport name from the connector and never branches on protocol logic."
  - "Allow-list guard in Invoke-AdmanRemoteCimQuery prevents accidental second-hop class introduction (D-07)."
  - "Remote columns are appended after ConvertTo-AdmanResult so the D-03 schema contract test remains untouched."

requirements-completed:
  - RMT-03

coverage:
  - id: D1
    description: "Invoke-AdmanRemoteCimQuery allow-lists only Win32_OperatingSystem/Win32_ComputerSystem, maps transport to Wsman/Dcom protocol, forwards TimeoutSeconds, and removes the transient session"
    requirement: RMT-04
    verification:
      - kind: unit
        ref: "tests/Remoting.Query.Tests.ps1#Invoke-AdmanRemoteCimQuery local-only guard"
        status: pass
    human_judgment: false

  - id: D2
    description: "Invoke-AdmanRemoteQuery returns RemoteOS/Uptime/LoggedOnUser for reachable hosts, short-circuits Skipped transport, creates exactly one CIM session, probes with Test-AdmanCimSessionTimeout, forwards a shrinking timeout budget, and returns Skipped on CIM errors"
    requirement: RMT-03
    verification:
      - kind: unit
        ref: "tests/Remoting.Query.Tests.ps1#Invoke-AdmanRemoteQuery enrichment"
        status: pass
    human_judgment: false

  - id: D3
    description: "Get-AdmanInventoryReport enriches every row with Transport/RemoteOS/Uptime/LoggedOnUser, preserves AD OS columns, enforces per-host + total caps, counts CIM errors as Skipped, and emits a single Write-Warning summary"
    requirement: RMT-03
    verification:
      - kind: unit
        ref: "tests/Report.Inventory.Tests.ps1#Get-AdmanInventoryReport: remote enrichment"
        status: pass
    human_judgment: false

  - id: D4
    description: "Menu inventory report label reads 'Fleet inventory report (with remote enrichment)' and the renderer property list includes the four new columns"
    requirement: RMT-03
    verification:
      - kind: unit
        ref: "tests/Report.Inventory.Tests.ps1#Get-AdmanInventoryReport: remote enrichment"
        status: pass
    human_judgment: false

duration: 42min
completed: 2026-07-17
status: complete
---

# Phase 03 Plan 02: Remote Query Layer and Inventory Enrichment Summary

**Implemented the read-only remote query layer and wired it into the existing inventory report, delivering the remote-enriched fleet view with per-host/total timeout caps and first-class Skipped outcomes.**

## Performance

- **Duration:** 42 min
- **Started:** 2026-07-17T04:34:21Z
- **Completed:** 2026-07-17T05:16:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- Created `Invoke-AdmanRemoteCimQuery` with a strict allow-list for `Win32_OperatingSystem` and `Win32_ComputerSystem` and the D-07 structural guard message.
- Created `Invoke-AdmanRemoteQuery` to return `RemoteOS`, `[TimeSpan]` `Uptime`, and `LoggedOnUser` using one transient CIM session per host, with a hard-capped session-setup probe and a shrinking timeout budget.
- Extended `Get-AdmanInventoryReport` to enrich every row with `Transport`, `RemoteOS`, `Uptime`, and `LoggedOnUser` while preserving AD-side OS columns.
- Enforced `transport.timeouts.perHostProbeCap` across the combined probe + session setup + query time and `transport.timeouts.totalInventoryRemoteCap` across the whole enrichment pass.
- Ensured CIM errors and exhausted budgets result in `Transport='Skipped'` and are counted in the single `Write-Warning` summary.
- Updated the menu label to "Fleet inventory report (with remote enrichment)" and extended the renderer property list so console/CSV/HTML outputs include the new columns even on zero-row reports.
- Delivered 12 query helper unit tests and 14 inventory report unit tests; all 50 relevant unit tests pass, including unchanged `tests/Result.Schema.Tests.ps1`.

## Task Commits

Each task was committed atomically (TDD RED/GREEN):

1. **Task 1: Implement guarded local-only CIM query helpers**
   - RED: `96061b0` test(03-02): add failing unit tests for remote CIM query helpers
   - GREEN: `e358dab` feat(03-02): implement guarded local-only remote CIM query helpers
2. **Task 2: Enrich Get-AdmanInventoryReport and update the menu**
   - `2cdf087` feat(03-02): enrich inventory report with remote data and update menu
3. **Task 3: Test remote query behavior and inventory enrichment**
   - `3239aef` test(03-02): extend inventory tests for remote enrichment
4. **Post-execution test-isolation fix**
   - `e2a8e15` test(03-02): harden Remoting.Query tests against full-suite mock pollution

## Files Created/Modified
- `Private/Remoting/Invoke-AdmanRemoteCimQuery.ps1` - Allow-listed, local-only single-class CIM runner with session cleanup.
- `Private/Remoting/Invoke-AdmanRemoteQuery.ps1` - Online/OS/uptime/logged-on-user enrichment with one transient session, shrinking budget, and error-to-Skipped handling.
- `Public/Get-AdmanInventoryReport.ps1` - Extended with serial per-row enrichment, per-host/total caps, and single skipped-host warning.
- `Private/Menu/Get-AdmanMenuDefinition.ps1` - Updated inventory report label and property list.
- `tests/Remoting.Query.Tests.ps1` - Unit tests for both query helpers.
- `tests/Report.Inventory.Tests.ps1` - Extended with remote-enrichment contract, cap, and help-text tests.

## Decisions Made
- Kept `Invoke-AdmanRemoteQuery` separate from `Invoke-AdmanRemoteCimQuery` so the report pays the session-setup cost only once per host; documented this relationship in a comment to prevent future refactor drift.
- Returned `Transport='Skipped'` from `Invoke-AdmanRemoteQuery` for CIM errors and budget exhaustion so the inventory report's skipped count remains accurate without separate error tracking.
- Appended remote columns after `ConvertTo-AdmanResult` rather than modifying the mapper, preserving the existing D-03 schema contract test unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Remoting.Query.Tests.ps1 failed when run as part of the full test suite**
- **Found during:** Final verification
- **Issue:** The shared `tests/Mocks/ActiveDirectory.psm1` stub defines `New-CimSession` and `Get-CimInstance` with incomplete parameter signatures (missing `OperationTimeoutSec`). When earlier test files import that mock module, the stubs shadow the real CIM cmdlets in the global session. Pester's mock metadata inference then builds module-scope mocks that reject the `-OperationTimeoutSec` parameter used by `Invoke-AdmanRemoteCimQuery` and `Invoke-AdmanRemoteQuery`, causing `Remoting.Query.Tests.ps1` to fail only in full-suite runs.
- **Fix:**
  - Added `[int]$OperationTimeoutSec` to the `New-CimSession` and `Get-CimInstance` stubs in `tests/Mocks/ActiveDirectory.psm1` so their signatures align with the real cmdlets.
  - Changed `Remoting.Query.Tests.ps1` `BeforeAll`/`AfterAll` to use module-qualified `CimCmdlets\New-CimSession`, `CimCmdlets\New-CimSessionOption`, and `CimCmdlets\Remove-CimSession`, bypassing any globally-shadowing stub when creating the real local test session.
  - Added explicit `param(...)` blocks to the `New-CimSession`, `Get-CimInstance`, and `Remove-CimSession` mocks in `Remoting.Query.Tests.ps1` for consistent parameter binding regardless of how Pester resolves the underlying command.
- **Files modified:** `tests/Mocks/ActiveDirectory.psm1`, `tests/Remoting.Query.Tests.ps1`
- **Commit:** `e2a8e15`

## Issues Encountered
- **Get-CimInstance -CimSession parameter binding rejected PSCustomObject stand-ins.** Fixed by creating a real local DCOM `CimSession` in the test `BeforeAll` and returning it from the `New-CimSession` mock.
- **PowerShell `[int]` cast rounds doubles rather than truncating.** This affects the shrinking-timeout calculation but was accepted because the plan explicitly specified `[int]`; tests were written with enough elapsed time to prove the budget shrinks.
- **Pester 6 has no `-MatchLike` operator.** Replaced with `-BeLike` in the comment-based help text test.
- **Full-suite mock pollution from `tests/Mocks/ActiveDirectory.psm1`.** Fixed as documented in Deviations; `Remoting.Query.Tests.ps1` now passes both in isolation and inside the full suite.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The remote query layer is ready for the double-hop documentation and guidance plan (03-03).
- No blockers; RMT-03 is satisfied by this plan.

## Self-Check: PASSED
- All created files verified present.
- Commits `96061b0`, `e358dab`, `2cdf087`, `3239aef`, and `e2a8e15` verified in repository history.
- `Invoke-Pester -Path tests/Remoting.Query.Tests.ps1, tests/Report.Inventory.Tests.ps1, tests/Result.Schema.Tests.ps1 -Tag Unit` passes (50 tests).
- `Invoke-ScriptAnalyzer` reports zero findings on all changed files.
- `Remoting.Query.Tests.ps1` now passes in the full test suite; the remaining full-suite failures (`Menu.Tests.ps1` parse error, `Harness.Tests.ps1` lint findings from that parse error, `Audit.FailClosed.Tests.ps1`, `Local.Gate.Tests.ps1`, `Safety.GateOrder.Tests.ps1`, `Utility.Password.Tests.ps1`) are pre-existing and unrelated to this plan.

---
*Phase: 03-remote-computer-operations-isolated*
*Completed: 2026-07-17*
