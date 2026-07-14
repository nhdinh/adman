---
phase: 00-foundation-safety-harness
plan: 06
subsystem: testing
tags: [powershell, pester, active-directory, safety-gate, whatif, integration-test, strictmode]

# Dependency graph
requires:
  - phase: 00-foundation-safety-harness
    provides: the safety mutation gate (Invoke-AdmanMutation), Test-AdmanTargetAllowed scope/deny/protected policy, and the doubly-gated lab integration test harness (Initialize-AdmanLab + module-scope invocation) built in plans 00-01..00-05 and quick tasks 260714-ek6/260714-fbx
provides:
  - "A WhatIf integration test that targets non-protected child USER fixtures (resolve-identity-as-is) and proves SAFE-01/10 end-to-end against the lab OU"
  - "A hardened Test-AdmanTargetAllowed step (b) that skips the RID-deny check for objectSid-absent (non-principal) targets without weakening principal RID denial"
affects: [verify-work, uat, phase-00-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Integration tests target dedicated non-protected fixtures (lab-whatif-*) provisioned idempotently in the gated path, never the OU DN, matching the gate's resolve-identity-as-is semantics"
    - "Defensive objectSid read via $Object.PSObject.Properties['objectSid'] before a StrictMode-sensitive SecurityIdentifier cast"

key-files:
  created: []
  modified:
    - tests/Safety.WhatIf.Integration.Tests.ps1
    - Private/Safety/Test-AdmanTargetAllowed.ps1

key-decisions:
  - "UAT gap #3 resolved via option (a): the WhatIf test targets child USER fixtures under the lab OU; the gate keeps resolve-identity-as-is semantics (no OU-expansion product change)"
  - "Step-(b) hardening skips the RID-deny check ONLY when objectSid is absent/null; any object WITH an objectSid runs the exact prior deny check (renamed RID-500 still refused)"

patterns-established:
  - "Non-principal-target robustness: guard every StrictMode-sensitive cast on a possibly-absent AD attribute; skip the check, never silently allow (scope + membership still apply)"

requirements-completed: [SAFE-01, SAFE-10]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "WhatIf integration test targets non-protected child USER fixtures and asserts AD-unchanged (Enabled state), Succeeded == fixture count, Denied == 0, and audit target DN set == resolved set (SAFE-01/10)"
    requirement: SAFE-01
    verification:
      - kind: unit
        ref: "powershell -NoProfile -Command Invoke-Pester -Path tests -TagFilter Unit -Output Minimal (138 passed, 0 failed; Integration files excluded)"
        status: pass
      - kind: integration
        ref: "tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration (LAB-ONLY; manual run on D:\\adman via runas /netonly)"
        status: unknown
    human_judgment: true
    rationale: "The end-to-end lab run requires a reachable lab DC (lab-dc01.lab.local) from the operator's interactive runas /netonly PS7 session; the agent cannot reach the lab. Automated proof is limited to file parse + Unit-suite green + source-pattern assertions; the live SAFE-01/10 proof is the operator's manual lab re-run (UAT test 2)."
  - id: D2
    description: "Test-AdmanTargetAllowed step (b) skips RID-deny for objectSid-absent (non-principal) targets without weakening principal RID denial (SAFE-05/06 unregressed)"
    requirement: SAFE-10
    verification:
      - kind: unit
        ref: "tests/Safety.DenyList.Tests.ps1 + tests/Safety.Protected.Tests.ps1 + tests/Safety.Scope.Tests.ps1 (29 passed, 0 failed; renamed RID-500 still refused)"
        status: pass
      - kind: other
        ref: "Invoke-ScriptAnalyzer -Path Private/Safety/Test-AdmanTargetAllowed.ps1 -Settings PSScriptAnalyzerSettings.psd1 (0 findings)"
        status: pass
    human_judgment: false

# Metrics
duration: 18min
completed: 2026-07-14
status: complete
---

# Phase 00 Plan 06: UAT Gap #3 Closure (WhatIf Test Retarget + Step-(b) Hardening) Summary

**Retargeted the WhatIf integration test at non-protected child user fixtures (resolve-identity-as-is) and hardened Test-AdmanTargetAllowed step (b) to skip RID-deny for objectSid-absent targets — closing UAT gap #3 without weakening principal RID denial.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-14T07:36:07Z
- **Completed:** 2026-07-14T07:54:10Z
- **Tasks:** 3 (Task 3 automated steps 1-3 complete; steps 4-5 recorded as pending operator action)
- **Files modified:** 2

## Accomplishments
- WhatIf integration test now provisions two dedicated non-protected `lab-whatif-*` user fixtures idempotently and targets them (not the OU DN), matching the gate's resolve-identity-as-is semantics; asserts AD-unchanged via fixture Enabled state (SAFE-01), Succeeded == fixture count + Denied == 0 (SAFE-10), and audit target DN set == resolved set.
- Test-AdmanTargetAllowed step (b) hardened: the objectSid→RID cast is null-guarded so a non-security-principal target (OU/container) skips the RID-deny check instead of throwing under StrictMode; principal RID denial unchanged (renamed RID-500 still refused).
- Full Unit suite green (138 passed, 0 failed) and lint clean (0 findings) on the edited production file; Integration files correctly excluded from the Unit run (9 NotRun).

## Task Commits

Each task was committed atomically:

1. **Task 1: Retarget the WhatIf integration test at non-protected child user fixtures (option a)** - `ad3cb9f` (test)
2. **Task 2: Harden Test-AdmanTargetAllowed step (b) to skip RID-deny when objectSid is absent** - `6624974` (fix)
3. **Task 3: Verify — full Unit suite green + lint clean (automated steps 1-3)** - no code commit (verification only; lab steps 4-5 pending operator)

**Plan metadata:** `43c4478` (docs: complete plan)

## Files Created/Modified
- `tests/Safety.WhatIf.Integration.Tests.ps1` - Gated -WhatIf It block retargeted at two provisioned non-protected `lab-whatif-*` user fixtures; assertions match gate semantics (AD-unchanged via fixture Enabled state; Succeeded == fixture count; Denied == 0; audit targets == resolved set). Initialize-AdmanLab init + module-scope invocation + Integration gate unchanged.
- `Private/Safety/Test-AdmanTargetAllowed.ps1` - Step (b) hardened: objectSid→RID cast null-guarded; RID-deny skipped only for objectSid-absent (non-principal) targets; principal RID denial preserved.

## Decisions Made
- **UAT gap #3 → option (a)** (user decision 2026-07-14): the WhatIf test targets child USER fixtures under the lab OU; the gate keeps resolve-identity-as-is semantics. OU-expansion (option b) rejected as product scope creep — not a phase-00 requirement.
- **Step-(b) guard semantics**: skip the RID-deny check ONLY when objectSid is absent/null. An objectSid-absent target is NOT silently allowed — it remains subject to step (c) managed-OU scope and step (d) protected membership. Any object WITH an objectSid runs the exact prior deny check.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed un-pipeable foreach statement in fixture-DN resolution**
- **Found during:** Task 1 (parse verification)
- **Issue:** Initial edit wrote `$targets = @(foreach (...) { ... } | Where-Object { $_ })` — a `foreach` *statement* cannot be piped inside `@()`; the PowerShell parser rejected it ("An empty pipe element is not allowed" at line 135).
- **Fix:** Rewrote to accumulate into `$targets = @()` with an explicit `foreach` loop and `if ($dn) { $targets += $dn }`.
- **Files modified:** tests/Safety.WhatIf.Integration.Tests.ps1
- **Verification:** `Parser.ParseFile` returns PARSE OK (0 errors).
- **Committed in:** `ad3cb9f` (Task 1 commit)

**2. [Rule 1 - Bug] Corrected audit-target comparison to extract `.dn` from target detail objects**
- **Found during:** Task 1 (audit record shape review)
- **Issue:** The audit record's `targets` field is an array of `{dn,sid,objectClass}` objects (per Write-AdmanAudit), not plain DN strings; comparing `@($_.targets)` directly to the DN-string `$targets` array would always fail.
- **Fix:** Extract `.dn` from each target detail object before the set comparison: `@($cidRecords | ForEach-Object { @($_.targets) | ForEach-Object { $_.dn } } | ...)`.
- **Files modified:** tests/Safety.WhatIf.Integration.Tests.ps1
- **Verification:** Source review against Write-AdmanAudit schema (targets[].dn); parse clean.
- **Committed in:** `ad3cb9f` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - Bug, both in the Task 1 test file)
**Impact on plan:** Both auto-fixes necessary for correctness (parse validity + truthful audit assertion). No scope creep; no production-code change beyond the planned step-(b) hardening.

## Issues Encountered
- **Pester version on PS 5.1:** The default `powershell` (5.1) resolves Pester 3.4.0 (in-box), where `-Output` is ambiguous. Resolved by prepending `C:\Users\nhdinh\OneDrive\Documents\WindowsPowerShell\Modules` (Pester 6.0.0) to `$env:PSModulePath` and `Import-Module Pester -MinimumVersion 6.0.0 -Force` before `Invoke-Pester`, matching the continue-here infrastructure note. `pwsh` is not installed on this host.
- **Bash `$`-escaping in inline verification:** Several `Select-String` acceptance checks returned false 0-counts due to `$` being mangled through bash→PowerShell inline `-Command`. Re-verified all such patterns with the Grep tool directly against the files; all acceptance patterns confirmed present.

## Manual Lab Validation (Pending Operator Action)

The agent cannot reach the lab DC (`lab-dc01.lab.local`) or `D:\adman` — these are reachable ONLY from the operator's interactive `runas /netonly /user:LAB\Administrator` PS7 session. The following steps are recorded as `human_judgment` / pending operator action (Task 3 steps 4-5):

- **Step 4 (operator):** From the runas /netonly PS7 session on `D:\adman` (after `git pull`), with `$env:ADMAN_TEST_OU='OU=Adman-test,DC=lab,DC=local'` and `$env:ADMAN_TEST_DC='lab-dc01.lab.local'` set and the WindowsPowerShell Modules path prepended to `$env:PSModulePath`:
  - `Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration -Output Detailed` => the gated -WhatIf It block PASSES (AD unchanged; Succeeded == 2; Denied == 0; audit targets == resolved).
  - `Invoke-Pester -Path tests/Safety.Protected.Integration.Tests.ps1 -TagFilter Integration -Output Detailed` => still PASSES (nested-admin refused + Refused audit record; gMSA/RID-500 may be Inconclusive if fixtures absent — acceptable, not a failure).
- **Step 5 (operator):** On a green WhatIf run, flip UAT test 2 from `issue` to `pass` in `00-UAT.md` and record gap #3 as FIXED.

## User Setup Required
None - no external service configuration required. (Lab integration validation is the operator's manual step above.)

## Next Phase Readiness
- UAT gap #3 code-side closure complete: both edited files parse clean, full Unit suite green (138/0), lint clean, principal RID denial unweakened.
- **Blocker to full UAT close:** the operator's manual lab re-run (steps 4-5 above) must confirm both integration files green before UAT test 2 flips to `pass` and phase 00 UAT closes.
- Once the lab re-run is green, phase 00 UAT can close (status complete) and the phase advances.

---
*Phase: 00-foundation-safety-harness*
*Completed: 2026-07-14*

## Self-Check: PASSED
- FOUND: tests/Safety.WhatIf.Integration.Tests.ps1
- FOUND: Private/Safety/Test-AdmanTargetAllowed.ps1
- FOUND: .planning/phases/00-foundation-safety-harness/00-06-SUMMARY.md
- FOUND commit: ad3cb9f (Task 1)
- FOUND commit: 6624974 (Task 2)
