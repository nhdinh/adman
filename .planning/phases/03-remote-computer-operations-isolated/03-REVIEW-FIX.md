---
phase: 03-remote-computer-operations-isolated
fixed_at: 2026-07-17T12:30:00Z
review_path: .planning/phases/03-remote-computer-operations-isolated/03-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-07-17T12:30:00Z
**Source review:** `.planning/phases/03-remote-computer-operations-isolated/03-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: Empty `DenyList` array disables the protected-account hard floor

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `0cad8bb`
**Applied fix:** Added a `DenyList.Count -lt 1` check in `Test-AdmanConfigValid` so an empty array is rejected fail-closed instead of silently bypassing the protected-account floor.

### WR-01: Total fleet remote-enrichment cap is not enforced within a single host

**Files modified:** `Public/Get-AdmanInventoryReport.ps1`
**Commit:** `c277a14` (fix), `255c5d6` (test)
**Applied fix:** Compute `totalRemaining` at the top of each host iteration, derive a `hostBudget = min(perHostCap, totalRemaining)`, pass it to `Connect-AdmanTarget`, and abort the query leg when the remaining query budget is exhausted. Added a unit test covering mid-host abort.

### WR-02: Data-path CIM calls rely on `-OperationTimeoutSec`, not the hard `Start-Job` timeout

**Files modified:** `Private/Remoting/Invoke-AdmanRemoteQuery.ps1`
**Commit:** `c716e1d`
**Applied fix:** Wrapped the real `New-CimSession` + both `Get-CimInstance` calls inside a single `Start-Job` bounded by the remaining timeout. The job extracts only primitive properties so CIM serialization cannot surprise us. Error-record detection mirrors the probe helper.

### WR-03: `transport.order` is required and validated but never consumed

**Files modified:** `Private/Remoting/Connect-AdmanTarget.ps1`, `config/adman.defaults.json`
**Commit:** `c2b51cd`
**Applied fix:** `Connect-AdmanTarget` now iterates `$script:Config.transport.order`, normalizes legacy `Skip` to `Skipped`, and falls back to the fixed ladder when order is missing. Added an optional `-TimeoutSeconds` parameter for caller-supplied budgets. Updated the shipped default to use `Skipped`.

### WR-04: Inventory report uses AD `Name` instead of `DNSHostName` for remote queries

**Files modified:** `Public/Get-AdmanInventoryReport.ps1`, `tests/Mocks/ActiveDirectory.psm1`, `tests/Report.Inventory.Tests.ps1`
**Commit:** `e7f0655`
**Applied fix:** Inventory enrichment now prefers `DNSHostName` when present, falling back to `Name`. Updated the test mock to derive unique DNS hostnames from the computer name and adjusted the timing test accordingly.

### WR-05: `Convert-AdmanRemoteError` misses the hex form of the WinRM unreachable code

**Files modified:** `Private/Remoting/Convert-AdmanRemoteError.ps1`
**Commit:** `2e0d1e4`
**Applied fix:** Extended the regex to match `0x80338012` in addition to the decimal `2150859046` form.

### WR-06: Empty catch block swallows PSFramework import failures

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `8f2886e`
**Applied fix:** Replaced the empty catch with a `Write-Verbose` diagnostic so PSFramework import problems are visible during troubleshooting.

### WR-07: Unit tests depend on live local DCOM CIM sessions

**Files modified:** `tests/Remoting.Query.Tests.ps1`, `tests/Remoting.DoubleHop.Tests.ps1`
**Commit:** `c716e1d`
**Applied fix:** Replaced `New-CimSession -ComputerName localhost -Protocol Dcom` test setup with `[Microsoft.Management.Infrastructure.CimSession]::Create('localhost')`, which yields a validly-typed object without a live DCOM session. Updated `Invoke-AdmanRemoteQuery` tests to mock `Start-Job`, `Wait-Job`, `Receive-Job`, `Stop-Job`, and `Remove-Job` so the suite stays fully offline.

## Skipped Issues

None — all findings were fixed.

---

_Fixed: 2026-07-17T12:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
