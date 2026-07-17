---
phase: 03-remote-computer-operations-isolated
plan: 01
subsystem: remoting
tags: [powershell, winrm, cim, dcom, remoting, pester]

requires:
  - phase: 00-foundation-safety-harness
    provides: config loader, $script:Config, $script:TransportCache slot, fail-closed patterns
  - phase: 01-ad-query-reporting-read-only
    provides: Get-AdmanInventoryReport integration point (enrichment happens in 03-02)

provides:
  - Private/Remoting/Connect-AdmanTarget.ps1 with fixed WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped ladder
  - Private/Remoting/Test-AdmanWsmanTimeout.ps1 hard-timeout wrapper for Test-WSMan on PowerShell 5.1
  - Private/Remoting/Test-AdmanCimSessionTimeout.ps1 hard-timeout wrapper for New-CimSession setup
  - Private/Remoting/Convert-AdmanRemoteError.ps1 operator-facing error translator
  - transport.timeouts.perHostProbeCap and totalInventoryRemoteCap config keys with additive merge
  - Unit-test suite covering ladder order, cache, skipped outcomes, caps, and both timeout wrappers

affects:
  - 03-02-PLAN.md (remote query verbs will call Connect-AdmanTarget)
  - Get-AdmanInventoryReport.ps1 (enrichment loop in 03-02)

tech-stack:
  added: []
  patterns:
    - Module-scoped process-only cache keyed by uppercase computer name, never holding live sessions
    - Start-Job + Wait-Job hard timeout wrappers for cmdlets without native timeout parameters on 5.1
    - First-class 'Skipped' outcome for unreachable targets instead of exceptions
    - C# synthetic Job subclass in tests to satisfy strict cmdlet parameter binding

key-files:
  created:
    - Private/Remoting/Connect-AdmanTarget.ps1
    - Private/Remoting/Test-AdmanWsmanTimeout.ps1
    - Private/Remoting/Test-AdmanCimSessionTimeout.ps1
    - Private/Remoting/Convert-AdmanRemoteError.ps1
    - tests/Remoting.Ladder.Tests.ps1
    - tests/Remoting.Cache.Tests.ps1
    - tests/Remoting.Skipped.Tests.ps1
    - tests/Remoting.TimeCaps.Tests.ps1
    - tests/Remoting.WsmanTimeout.Tests.ps1
    - tests/Remoting.CimSessionTimeout.Tests.ps1
  modified:
    - config/adman.schema.json (timeout keys already present from Task 1 GREEN)
    - config/adman.defaults.json (timeout defaults already present from Task 1 GREEN)
    - config/adman.example.json (timeout annotations already present from Task 1 GREEN)
    - Private/Config/Initialize-AdmanConfig.ps1 (timeout additive merge already present from Task 1 GREEN)
    - adman.psm1 ($script:TransportCache already present from Task 1 GREEN)

key-decisions:
  - "Pester 6 requires BeforeEach inside a Describe block; existing test stubs were restructured to comply."
  - "C# Add-Type synthetic Job subclass is used in timeout-wrapper tests because System.Management.Automation.Job parameter binding rejects PSCustomObject stand-ins."
  - "Timeout wrappers stop+remove jobs on any non-success path and remove-only on success, keeping cleanup centralized in a single finally block."

patterns-established:
  - "Transport detection quarantined in Private/Remoting/Connect-AdmanTarget; no Public verb branches on protocol."
  - "Hard-timeout wrappers use Start-Job + Wait-Job so PowerShell 5.1 cannot hang on dead hosts."
  - "Process-only cache stores transport name strings only, never live CimSession/PSSession objects."

requirements-completed:
  - RMT-01
  - RMT-02

coverage:
  - id: D1
    description: "Connect-AdmanTarget fixed ladder (WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped) with process-only cache keyed by uppercase computer name"
    requirement: RMT-01
    verification:
      - kind: unit
        ref: "tests/Remoting.Ladder.Tests.ps1#Connect-AdmanTarget ladder order"
        status: pass
      - kind: unit
        ref: "tests/Remoting.Cache.Tests.ps1#Connect-AdmanTarget process-only cache"
        status: pass
    human_judgment: false

  - id: D2
    description: "Unreachable or cap-exceeded hosts return 'Skipped' as a first-class non-error outcome without throwing"
    requirement: RMT-02
    verification:
      - kind: unit
        ref: "tests/Remoting.Skipped.Tests.ps1#Connect-AdmanTarget Skipped outcome"
        status: pass
      - kind: unit
        ref: "tests/Remoting.TimeCaps.Tests.ps1#Connect-AdmanTarget per-host time cap"
        status: pass
    human_judgment: false

  - id: D3
    description: "Test-AdmanWsmanTimeout wraps Test-WSMan in a hard-timeout Start-Job and cleans up jobs"
    requirement: RMT-02
    verification:
      - kind: unit
        ref: "tests/Remoting.WsmanTimeout.Tests.ps1#Test-AdmanWsmanTimeout hard-timeout wrapper"
        status: pass
    human_judgment: false

  - id: D4
    description: "Test-AdmanCimSessionTimeout wraps New-CimSession setup in a hard-timeout Start-Job and supports Wsman/Dcom protocols"
    requirement: RMT-02
    verification:
      - kind: unit
        ref: "tests/Remoting.CimSessionTimeout.Tests.ps1#Test-AdmanCimSessionTimeout hard-timeout wrapper"
        status: pass
    human_judgment: false

  - id: D5
    description: "Convert-AdmanRemoteError maps RPC-unavailable, access-denied, and double-hop HRESULTs to short operator strings"
    requirement: RMT-02
    verification:
      - kind: unit
        ref: "tests/Remoting.Skipped.Tests.ps1#Convert-AdmanRemoteError translation"
        status: pass
    human_judgment: false

  - id: D6
    description: "transport.timeouts.perHostProbeCap and totalInventoryRemoteCap config keys exist with shipped defaults and additive merge"
    requirement: RMT-02
    verification:
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#Initialize-AdmanConfig Phase 3 timeout config"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-07-17
status: complete
---

# Phase 03 Plan 01: Remote Transport Connector Summary

**Built the per-host transport probe and process-only cache that Phase 3 remote enrichment depends on: a WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped ladder with hard-timeout wrappers and first-class Skipped outcomes.**

## Performance

- **Duration:** 35min (current execution session covering Tasks 2 and 3; Task 1 completed in prior session)
- **Started:** 2026-07-17T10:45:00Z (estimated)
- **Completed:** 2026-07-17T11:20:00Z (estimated)
- **Tasks:** 3 (Task 1 completed prior; Tasks 2 and 3 executed in this session)
- **Files modified:** 10 created + 5 inherited from Task 1

## Accomplishments
- Implemented `Connect-AdmanTarget` with the fixed transport ladder and uppercase-keyed process-only cache.
- Implemented `Test-AdmanWsmanTimeout` and `Test-AdmanCimSessionTimeout` using `Start-Job` + `Wait-Job` so PowerShell 5.1 cannot hang on dead hosts.
- Implemented `Convert-AdmanRemoteError` to translate RPC/access/double-hop HRESULTs into operator-facing strings.
- Inherited Task 1 deliverables: `transport.timeouts.perHostProbeCap` / `totalInventoryRemoteCap` config keys, additive merge, and `$script:TransportCache` initialization.
- Delivered 25 unit tests covering ladder order, caching, skipped outcomes, per-host cap, both timeout wrappers, and error translation; all pass.
- Verified `Invoke-ScriptAnalyzer -Path Private/Remoting/` returns zero findings.

## Task Commits

Each task was committed atomically (TDD RED/GREEN for Task 1; combined RED/GREEN for Tasks 2 and 3):

1. **Task 1: Add timeout config keys and module cache slot** - `753eddb` (test), `5a879e7` (feat)
2. **Task 2/3: Implement ladder + timeout wrappers and unit-test suite** - `d27931a` (test), `f8c2c88` (feat)

## Files Created/Modified
- `Private/Remoting/Connect-AdmanTarget.ps1` - Fixed ladder + cache
- `Private/Remoting/Test-AdmanWsmanTimeout.ps1` - Test-WSMan hard-timeout wrapper
- `Private/Remoting/Test-AdmanCimSessionTimeout.ps1` - New-CimSession hard-timeout probe
- `Private/Remoting/Convert-AdmanRemoteError.ps1` - HRESULT/error translator
- `tests/Remoting.Ladder.Tests.ps1` - Ladder-order unit tests
- `tests/Remoting.Cache.Tests.ps1` - Cache behavior unit tests
- `tests/Remoting.Skipped.Tests.ps1` - Skipped outcome + error-translation tests
- `tests/Remoting.TimeCaps.Tests.ps1` - Per-host cap unit tests
- `tests/Remoting.WsmanTimeout.Tests.ps1` - Test-WSMan wrapper tests
- `tests/Remoting.CimSessionTimeout.Tests.ps1` - New-CimSession wrapper tests
- `config/adman.schema.json` - timeout keys (Task 1)
- `config/adman.defaults.json` - timeout defaults (Task 1)
- `config/adman.example.json` - timeout annotations (Task 1)
- `Private/Config/Initialize-AdmanConfig.ps1` - additive timeout merge (Task 1)
- `adman.psm1` - `$script:TransportCache` slot (Task 1)

## Decisions Made
- Followed TDD RED/GREEN order: tests committed before implementation, even though the plan text lists implementation before tests.
- Used a C# `AdmanTestJob` subclass in timeout-wrapper tests because `System.Management.Automation.Job` parameter binding rejects PSCustomObject stand-ins.
- Restructured all Remoting test files to place `BeforeEach` inside `Describe` blocks, as Pester 6 does not support root-level `BeforeEach`.

## Deviations from Plan

None - plan executed as specified. The task ordering was interpreted through the TDD lens (RED tests before GREEN implementation), which is consistent with the `tdd="true"` flags on each task.

## Issues Encountered
- **Pester 6 root-level BeforeEach rejected:** Existing untracked test stubs placed `BeforeEach` at file root. Fixed by moving setup inside `Describe` blocks.
- **Synthetic job parameter binding:** Initial PSCustomObject stand-ins failed `Wait-Job`/`Receive-Job` parameter binding. Fixed with a C# `AdmanTestJob` subclass created via `Add-Type` in the test files.
- **Stop-Job called on success:** First GREEN implementation always stopped jobs in `finally`, causing success tests to fail. Fixed by tracking `$success` and only stopping on non-success paths.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `Connect-AdmanTarget` is ready for `Get-AdmanInventoryReport` enrichment in 03-02.
- `Convert-AdmanRemoteError` is ready for the query layer in 03-02.
- No blockers; RMT-01 and RMT-02 are satisfied by this plan.

---
*Phase: 03-remote-computer-operations-isolated*
*Completed: 2026-07-17*
