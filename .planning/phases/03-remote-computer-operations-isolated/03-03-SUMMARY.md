---
phase: 03-remote-computer-operations-isolated
plan: 03
subsystem: remoting
tags: [powershell, remoting, double-hop, credssp, rbacd, jea, security, documentation, pester]

requires:
  - phase: 03-remote-computer-operations-isolated
    plan: 02
    provides: Invoke-AdmanRemoteCimQuery allow-list guard, Invoke-AdmanRemoteQuery enrichment, Get-AdmanInventoryReport remote enrichment

provides:
  - docs/REMOTE-OPS.md operator guidance for double-hop, CredSSP exclusion, RBCD/JEA preference, and firewall ports
  - tests/Remoting.DoubleHop.Tests.ps1 functional + static proof of the no-second-hop stance

affects:
  - docs/REMOTE-OPS.md
  - tests/Remoting.DoubleHop.Tests.ps1

tech-stack:
  added: []
  patterns:
    - Structural class allow-list guard enforced in Invoke-AdmanRemoteCimQuery
    - Static source tests prove absence of CredSSP / Invoke-Command / New-PSSession in Private/Remoting/*.ps1
    - Runtime mock tests prove Invoke-AdmanRemoteQuery never invokes remote-session cmdlets

key-files:
  created:
    - docs/REMOTE-OPS.md
    - tests/Remoting.DoubleHop.Tests.ps1
  modified: []

key-decisions:
  - "Operator guidance is the canonical reference for why adman Phase 3 is local-on-target only and what to do if second-hop live actions are needed later."
  - "CredSSP is explicitly excluded from v1; any future second-hop work must go through RBCD/JEA design review."
  - "Static parser for -ClassName literals is intentionally simple; the real enforcement is the runtime allow-list in Invoke-AdmanRemoteCimQuery."

patterns-established:
  - "Double-hop stance is documented, tested, and structurally enforced."
  - "Private/Remoting/*.ps1 is kept free of CredSSP, Invoke-Command, and New-PSSession by static tests."

requirements-completed:
  - RMT-04

coverage:
  - id: D1
    description: "docs/REMOTE-OPS.md explains double-hop, local-on-target stance, CredSSP exclusion, RBCD/JEA future paths, sensitive accounts, pass-through credentials, timeout behavior, and WinRM vs DCOM firewall ports"
    requirement: RMT-04
    verification:
      - kind: docs
        ref: "docs/REMOTE-OPS.md"
        status: pass
    human_judgment: false

  - id: D2
    description: "Invoke-AdmanRemoteCimQuery rejects any class outside {Win32_OperatingSystem, Win32_ComputerSystem} with the D-07 guard message"
    requirement: RMT-04
    verification:
      - kind: unit
        ref: "tests/Remoting.DoubleHop.Tests.ps1#Invoke-AdmanRemoteCimQuery structural guard"
        status: pass
    human_judgment: false

  - id: D3
    description: "Private/Remoting/*.ps1 contains zero case-insensitive references to CredSSP, Invoke-Command, or New-PSSession"
    requirement: RMT-04
    verification:
      - kind: unit
        ref: "tests/Remoting.DoubleHop.Tests.ps1#Static proof"
        status: pass
    human_judgment: false

  - id: D4
    description: "Private/Remoting/*.ps1 contains exactly two distinct -ClassName values: Win32_OperatingSystem and Win32_ComputerSystem"
    requirement: RMT-04
    verification:
      - kind: unit
        ref: "tests/Remoting.DoubleHop.Tests.ps1#Static proof"
        status: pass
    human_judgment: false

  - id: D5
    description: "Invoke-AdmanRemoteQuery never calls Invoke-Command or New-PSSession at runtime"
    requirement: RMT-04
    verification:
      - kind: unit
        ref: "tests/Remoting.DoubleHop.Tests.ps1#Invoke-AdmanRemoteQuery runtime"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-07-17
status: complete
---

# Phase 03 Plan 03: Double-Hop Stance Documentation and Verification Summary

**Closed the security-design loop on Phase 3 remoting by documenting the no-second-hop / CredSSP-exclusion / RBCD-JEA-preference strategy and adding functional + static verification that the connector cannot be used for second-hop operations.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-17T04:56:00Z
- **Completed:** 2026-07-17T05:14:00Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Created `docs/REMOTE-OPS.md`, the operator reference for Phase 3 remote reads: what adman does, the double-hop problem, the local-on-target stance, explicit CredSSP exclusion, RBCD/JEA as future paths, unaffected sensitive accounts, pass-through credential behavior, hard-timeout behavior for dead hosts, and the WinRM vs DCOM firewall ports.
- Added `tests/Remoting.DoubleHop.Tests.ps1` with:
  - Functional tests proving `Invoke-AdmanRemoteCimQuery` rejects `Win32_Share` and `Win32_Process` with the D-07 guard message while allowing the two local-only classes.
  - Static tests proving `Private/Remoting/*.ps1` contains no `CredSSP`, `Invoke-Command`, or `New-PSSession` references and only the two allowed `-ClassName` literals.
  - Runtime tests proving `Invoke-AdmanRemoteQuery` never invokes `Invoke-Command` or `New-PSSession` for any transport.
- Ran the full Phase 3 remoting unit-test suite (49 tests across 8 files) and PSScriptAnalyzer on `Private/Remoting/` and `Public/Get-AdmanInventoryReport.ps1`; all green with zero findings.

## Task Commits

1. **Task 1: Write operator guidance for double-hop and firewall strategy** — `aa2757b` docs(03-03): add operator guidance for double-hop and firewall strategy
2. **Task 2: Verify the structural second-hop guard and absence of CredSSP** — `4a469d0` test(03-03): add double-hop guard and CredSSP absence tests
3. **Task 3: Run phase remoting test suite and lint gate** — verification only; no code changes

## Files Created/Modified

- `docs/REMOTE-OPS.md` — operator guidance document
- `tests/Remoting.DoubleHop.Tests.ps1` — double-hop functional + static verification suite

## Decisions Made

- Kept the structural allow-list guard as the enforcement point and the docs as the explanation; no additional code changes were required because the guard was implemented in `03-02`.
- Left CredSSP explicitly excluded from v1; any future live-action second-hop need must be designed around RBCD/JEA, not added to the current ladder or query helpers.
- Used a simple static regex parser for `-ClassName` literals with a maintainer note that the real policy enforcement is the runtime guard.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Allowed-class tests in `tests/Remoting.DoubleHop.Tests.ps1` failed with a null `CimSession`**
- **Found during:** Task 2 verification
- **Issue:** The pre-existing test file mocked `New-CimSession` to return nothing for the allowed-class tests. `Invoke-AdmanRemoteCimQuery` then passed a null session to `Get-CimInstance`, which failed parameter binding with "Cannot bind argument to parameter 'CimSession' because it is null."
- **Fix:** Created a real local DCOM `CimSession` in `BeforeAll` and updated the two allowed-class tests to return it from the `New-CimSession` mock, matching the pattern used in `tests/Remoting.Query.Tests.ps1`.
- **Files modified:** `tests/Remoting.DoubleHop.Tests.ps1`
- **Commit:** `4a469d0`

## Issues Encountered

- None beyond the null-CimSession mock issue above, which was fixed inline.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 3 remoting is complete and verified. RMT-01 through RMT-04 are satisfied.
- Phase 4 (bulk / workflows) can build on the proven connector and safety spine.

## Self-Check: PASSED

- `docs/REMOTE-OPS.md` verified present.
- `tests/Remoting.DoubleHop.Tests.ps1` verified present.
- Commits `aa2757b` and `4a469d0` verified in repository history.
- Full Phase 3 remoting unit-test suite passed (49 tests, 0 failures).
- PSScriptAnalyzer reported zero findings on `Private/Remoting/` and `Public/Get-AdmanInventoryReport.ps1`.

---
*Phase: 03-remote-computer-operations-isolated*
*Completed: 2026-07-17*
