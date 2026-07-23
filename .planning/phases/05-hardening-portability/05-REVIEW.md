---
phase: 05-hardening-portability
reviewed: 2026-07-23T20:45:00Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - Private/Safety/Invoke-AdmanMutation.ps1
  - Private/Safety/Invoke-AdmanLocalMutation.ps1
  - Private/Safety/Confirm-AdmanAction.ps1
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Remoting/Test-AdmanWsmanTimeout.ps1
  - Private/Remoting/Test-AdmanCimSessionTimeout.ps1
  - Public/New-AdmanUser.ps1
  - Public/New-AdmanLocalUser.ps1
  - Public/Test-AdmanCapability.ps1
  - Public/Get-AdmanStaleReport.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - docs/USAGE.md
  - tests/Safety.GateOrder.Tests.ps1
  - tests/Local.Gate.Tests.ps1
  - tests/Safety.ConfirmationRestored.Tests.ps1
  - tests/Bulk.Engine.Tests.ps1
  - build/Sign-AdmanModule.ps1
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T20:45:00Z
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

This is a fresh review of the Phase 05 hardening/portability source set. The previous `05-REVIEW.md` findings (CR-01 through WR-06) have already been addressed in commits `3ac7c4c` through `94e3c5e`, so this report focuses on the current HEAD state.

The most severe gap is in the two mutation gates: `Invoke-AdmanMutation` and `Invoke-AdmanLocalMutation` forward `-WhatIf:$WhatIfPreference` to almost every downstream call except the one that decides whether the run is a dry-run. Because `Confirm-AdmanAction` relies on its own `[switch]$WhatIf` parameter, a caller-level `-WhatIf` is silently ignored and real mutations execute. This breaks the project's first core safety guardrail (`-WhatIf`/dry-run on every destructive action).

Secondary issues are a startup-probe hang risk, test mocks that mask the propagation bug, documentation/scope mismatches, and minor code-quality items.

## Critical Issues

### CR-01: AD mutation gate drops caller `-WhatIf`, executing real AD writes during dry-run

**File:** `Private/Safety/Invoke-AdmanMutation.ps1:212-217`
**Issue:** The gate passes `-WhatIf:$WhatIfPreference` to the audit writes and the wrapper, but not to `Confirm-AdmanAction`. `Confirm-AdmanAction` has its own `[switch]$WhatIf` (line 44 of `Confirm-AdmanAction.ps1`) and determines dry-run vs. real execution from that parameter. When it is not bound, it defaults to `$false`, so a caller-level `-WhatIf` is treated as a real run. The wrapper then receives `-WhatIf:$false` and performs the AD mutation, while the audit is still written as a real (non-whatIf) record.

This affects every AD write that flows through the gate: `Disable-AdmanUser`, `Enable-AdmanUser`, `Move-AdmanUser`, `Set-AdmanUserPassword`, `Unlock-AdmanUser`, `Add-AdmanGroupMember`, `Remove-AdmanGroupMember`, `New-AdmanUser`, and bulk actions.
**Fix:** Bind `-WhatIf:$WhatIfPreference` on both `Confirm-AdmanAction` call sites in the AD gate.

```powershell
if ($groupObj) {
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() `
        -Group $groupObj.DistinguishedName -Force:$Force -WhatIf:$WhatIfPreference
} else {
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() `
        -Force:$Force -WhatIf:$WhatIfPreference
}
```

### CR-02: Local mutation gate drops caller `-WhatIf`, executing real local writes during dry-run

**File:** `Private/Safety/Invoke-AdmanLocalMutation.ps1:105-106`
**Issue:** Same defect as CR-01 in the local-account gate. `Confirm-AdmanAction` is invoked without `-WhatIf:$WhatIfPreference`, so `New-AdmanLocalUser`, `Set-AdmanLocalUser`, `Remove-AdmanLocalUser`, and local group membership changes run for real when the operator requests `-WhatIf`.
**Fix:** Bind `-WhatIf:$WhatIfPreference` to the single `Confirm-AdmanAction` call in the local gate.

```powershell
$confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() `
    -Force:$Force -WhatIf:$WhatIfPreference
```

## Warnings

### WR-01: `Test-AdmanCapability` bypasses the project's hard-timeout wrappers

**File:** `Public/Test-AdmanCapability.ps1:87-92, 96-108`
**Issue:** The capability probe calls `Test-WSMan` directly and creates a `New-CimSession` with only `-OperationTimeoutSec`. On Windows PowerShell 5.1, `Test-WSMan` has no timeout parameter and can hang on a silently-dropped DC; `New-CimSession` connection setup can also outlast the intended 15-second probe budget. The project already provides `Test-AdmanWsmanTimeout` and `Test-AdmanCimSessionTimeout` (`Private/Remoting/Test-AdmanWsmanTimeout.ps1` and `Private/Remoting/Test-AdmanCimSessionTimeout.ps1`) for exactly this reason, and the function's own comment promises "Transport timeouts are kept short (<= 30s) so the menu never hangs."
**Fix:** Replace the direct calls with the timeout wrappers so the probe always returns within the configured cap.

```powershell
$winrm = [bool](Test-AdmanWsmanTimeout -ComputerName $dc -TimeoutSeconds $probeTimeoutSec)

$cimDcom = $false
if (-not $winrm) {
    $cimDcom = Test-AdmanCimSessionTimeout -ComputerName $dc -Protocol Dcom -TimeoutSeconds $probeTimeoutSec
}
```

### WR-02: Gate tests mask the `-WhatIf` propagation bug

**File:** `tests/Safety.GateOrder.Tests.ps1:59, 211-234`; `tests/Local.Gate.Tests.ps1:64`; `tests/Safety.ConfirmationRestored.Tests.ps1:74`; `tests/Bulk.Engine.Tests.ps1:188`
**Issue:** The test stubs and mocks for `Confirm-AdmanAction` do not declare a `[switch]$WhatIf` parameter, and the existing "-WhatIf flow" test (`Safety.GateOrder.Tests.ps1:211-234`) only proves behavior when the mock *returns* `Outcome='DryRun'; WhatIf=$true`. No test asserts that the gate actually forwards the caller's `-WhatIf` value into `Confirm-AdmanAction`, or that a real `-WhatIf` invocation causes the wrapper to receive `-WhatIf:$true`. This is why CR-01/CR-02 pass the current suite.
**Fix:**
1. Update the global stub definitions to accept `[switch]$WhatIf`.
2. Add a test that invokes `Invoke-AdmanMutation`/public verbs with `-WhatIf` and asserts either:
   - `Confirm-AdmanAction` was called with `-WhatIf:$true`, or
   - the inner `Adman.AD.Write.*` wrapper received `-WhatIf:$true` and no mutation occurred.
3. Assert that the PENDING and Success audit records in that test carry `whatIf=$true`.

### WR-03: `docs/USAGE.md` mislabels password and move parameters

**File:** `docs/USAGE.md:43-46, 332-352`
**Issue:** The usage guide marks `Password`/`AccountPassword` as required for `New-AdmanLocalUser`, `Set-AdmanLocalUser`, `New-AdmanUser`, and `Set-AdmanUserPassword`. The corresponding cmdlet parameters are optional; when omitted the configured password source (`Generate`/`Prompt`) is used. Mislabeling them as required contradicts the parameter definitions and the D-05 password-sourcing design.
**Fix:** Change the menu reference entries to show `Password`/`AccountPassword` as optional, and add a short note that omitted passwords use `$script:Config.security.passwordSource`.

### WR-04: Stale report scope mismatch between docs and implementation

**File:** `docs/USAGE.md:156-165`; `Public/Get-AdmanStaleReport.ps1:10`
**Issue:** `Get-AdmanStaleReport` is documented as reporting "stale or inactive user and computer accounts," but the implementation only queries `Get-ADUser`. Either the documentation over-promises or the report is missing computer accounts. Operators relying on the report for computer lifecycle decisions will not see stale computers.
**Fix:** Update `docs/USAGE.md` (and the function's synopsis if desired) to state the report covers user accounts only, and open a follow-up to add computer stale detection or an `-ObjectType` parameter.

## Info

### IN-01: Config loader computes `$moduleRoot` twice

**File:** `Private/Config/Initialize-AdmanConfig.ps1:312, 422`
**Issue:** `$moduleRoot` is assigned with the same `Split-Path -Parent (Split-Path -Parent $PSScriptRoot)` expression at line 312 and again at line 422. The duplicate is harmless but violates DRY.
**Fix:** Remove the second assignment and reuse the existing `$moduleRoot` variable.

### IN-02: Signing build script uses HTTP timestamp URL

**File:** `build/Sign-AdmanModule.ps1:94`
**Issue:** The timestamp server is `http://timestamp.digicert.com`. DigiCert supports the same endpoint over HTTPS. Using HTTP exposes the timestamp response to trivial network tampering, which is unnecessary for a trust-anchor operation.
**Fix:** Change the URL to `https://timestamp.digicert.com`.

### IN-03: Usage guide last-updated line is stale

**File:** `docs/USAGE.md:447`
**Issue:** The footer reads "Last updated: 2026-07-22 for adman Phases 0-4." Phase 05 functionality is now present in the document.
**Fix:** Update the footer to reference Phase 05 and the current review date.

---

_Reviewed: 2026-07-23T20:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
