---
phase: 05-hardening-portability
plan: 01a2
subsystem: documentation
tags: [powershell, help, comment-based-help, pester, doc-03]

requires:
  - phase: 05-01a1
    provides: tests/Help.Coverage.Tests.ps1 scaffold and manifest-driven help coverage gate

provides:
  - Complete comment-based help blocks for all AD user/computer lifecycle exported functions
  - SupportsShouldProcess description assertion scoped to the 05-01a2 function list
  - Get-Help-discoverable help placement inside function bodies

affects:
  - 05-01a3

tech-stack:
  added: []
  patterns:
    - Comment-based help placed inside the function body or immediately adjacent to the function keyword
    - State-changing function descriptions document -WhatIf, confirmation, and audit behavior
    - Incremental help coverage enforcement via Pester -Data FunctionName slices

key-files:
  created: []
  modified:
    - Public/New-AdmanUser.ps1
    - Public/Disable-AdmanUser.ps1
    - Public/Enable-AdmanUser.ps1
    - Public/Set-AdmanUserPassword.ps1
    - Public/Unlock-AdmanUser.ps1
    - Public/Move-AdmanUser.ps1
    - Public/Disable-AdmanComputer.ps1
    - Public/Enable-AdmanComputer.ps1
    - Public/Move-AdmanComputer.ps1
    - Public/Reset-AdmanComputerAccount.ps1
    - tests/Help.Coverage.Tests.ps1

key-decisions:
  - "Moved help blocks inside function bodies for the eight files that had them above Set-StrictMode, restoring Get-Help discovery."
  - "Added a single standard safety paragraph to every state-changing AD lifecycle description so each mentions at least two of -WhatIf, confirmation, and audit."
  - "Scoped the SupportsShouldProcess description assertion to the hard-coded 05-01a2 function list so 05-01a3 functions are not evaluated before that plan runs."

patterns-established:
  - "Public function help block: inside function body, includes .SYNOPSIS, .DESCRIPTION, .PARAMETER per declared parameter, and .EXAMPLE."
  - "SupportsShouldProcess functions: .DESCRIPTION must mention at least two of -WhatIf, confirmation, and audit logging."

requirements-completed:
  - DOC-03

coverage:
  - id: D1
    description: "Complete comment-based help blocks on AD user lifecycle functions (New-AdmanUser, Disable-AdmanUser, Enable-AdmanUser, Set-AdmanUserPassword, Unlock-AdmanUser, Move-AdmanUser)."
    requirement: DOC-03
    verification:
      - kind: unit
        ref: "tests/Help.Coverage.Tests.ps1#adman public help coverage"
        status: pass
    human_judgment: false
  - id: D2
    description: "Complete comment-based help blocks on AD computer lifecycle functions (Disable-AdmanComputer, Enable-AdmanComputer, Move-AdmanComputer, Reset-AdmanComputerAccount)."
    requirement: DOC-03
    verification:
      - kind: unit
        ref: "tests/Help.Coverage.Tests.ps1#adman public help coverage"
        status: pass
    human_judgment: false
  - id: D3
    description: "Scoped SupportsShouldProcess description assertion requiring at least two of -WhatIf/confirm/audit terms for the 05-01a2 function list."
    requirement: DOC-03
    verification:
      - kind: unit
        ref: "tests/Help.Coverage.Tests.ps1#<_> .Description mentions at least two of -WhatIf/confirm/audit when state-changing"
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-07-22
status: complete
---

# Phase 05 Plan 01a2: AD Lifecycle Comment-Based Help Summary

**Complete, Get-Help-discoverable comment-based help for all AD user and computer lifecycle exported functions, enforced by a scoped Pester SupportsShouldProcess description gate.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-07-22T04:58:44Z
- **Completed:** 2026-07-22T05:05:48Z
- **Tasks:** 1
- **Files modified:** 11

## Accomplishments

- Moved comment-based help blocks inside function bodies for eight AD lifecycle Public/*.ps1 files where they had been placed above `Set-StrictMode`, restoring `Get-Help` discovery.
- Added `.PARAMETER` documentation for every declared parameter on New-AdmanUser, Set-AdmanUserPassword, Unlock-AdmanUser, Move-AdmanUser, Disable-AdmanComputer, Enable-AdmanComputer, Move-AdmanComputer, and Reset-AdmanComputerAccount.
- Updated descriptions on all ten AD lifecycle state-changing functions to mention at least two of the safety terms `-WhatIf`, `confirmation`, and `audit`.
- Extended `tests/Help.Coverage.Tests.ps1` with a scoped assertion that checks SupportsShouldProcess functions in the 05-01a2 list for the required safety-term coverage.
- Verified with both the scoped 05-01a2 Pester invocation and the unscoped run (111 passed, 0 failed).

## Task Commits

1. **Task 2b: Add comment-based help to AD user and computer lifecycle functions** - `c4db547` (feat)

## Files Created/Modified

- `Public/New-AdmanUser.ps1` - Moved help inside function; added .PARAMETER blocks for Name, SamAccountName, UserPrincipalName, ParentOuDn, AccountPassword, AccountPasswordSource, Force; added safety paragraph.
- `Public/Set-AdmanUserPassword.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, NewPassword, NewPasswordSource, ChangePasswordAtLogon, Unlock, Force; added safety paragraph.
- `Public/Unlock-AdmanUser.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, Force; added safety paragraph.
- `Public/Move-AdmanUser.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, TargetPath, Force; added safety paragraph.
- `Public/Disable-AdmanComputer.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, Force; added safety paragraph.
- `Public/Enable-AdmanComputer.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, Force; added safety paragraph.
- `Public/Move-AdmanComputer.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, TargetPath, Force; added safety paragraph.
- `Public/Reset-AdmanComputerAccount.ps1` - Moved help inside function; added .PARAMETER blocks for Identity, Force; added safety paragraph.
- `Public/Disable-AdmanUser.ps1` - Added safety paragraph to .DESCRIPTION.
- `Public/Enable-AdmanUser.ps1` - Added safety paragraph to .DESCRIPTION.
- `tests/Help.Coverage.Tests.ps1` - Added `$script:AdLifecycleFunctions` slice list and SupportsShouldProcess description assertion.

## Decisions Made

- Moved help blocks inside function bodies rather than leaving them at script scope, because `Get-Help` only discovers help that is inside the function or immediately adjacent to the `function` keyword.
- Used a hard-coded 05-01a2 function list in the test so the new assertion does not fail on 05-01a3 functions before that plan runs.
- Chose a single reusable safety paragraph rather than custom wording per function to keep the safety contract consistent and avoid accidentally weakening claims.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Initial test run showed `Get-Help` returning empty `.Description` and `.Examples` for eight functions. Root cause: their comment-based help blocks were placed above `Set-StrictMode` at script scope, so PowerShell did not associate them with the function. Fixed by moving help inside each function body.
- Pre-existing unrelated modifications to `Public/New-AdmanLocalUser.ps1`, `.planning/config.json`, and `.planning/phases/05-hardening-portability/05-01b-PLAN.md` were present in the working tree and were left unstaged/out of scope for this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 05-01a2 complete. The AD lifecycle help slice is enforced and the unscoped `Help.Coverage.Tests.ps1` run already passes, indicating the remaining exported functions also satisfy the base help contract.
- Ready for 05-01a3 to add any remaining category-scoped help or to rely on the unscoped gate.

## Self-Check: PASSED

- [x] All modified files exist and are readable.
- [x] Task commit `c4db547` exists in git history.
- [x] `Invoke-Pester` scoped run passes (30 passed, 0 failed).
- [x] `Invoke-Pester` unscoped run passes (111 passed, 0 failed).
- [x] `Invoke-ScriptAnalyzer -Path Public -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse` returns no issues.

---
*Phase: 05-hardening-portability*
*Completed: 2026-07-22*
