---
phase: 03
fixed_at: 2026-07-17T00:00:00Z
review_path: .planning/phases/03-remote-computer-operations-isolated/03-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 3
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-07-17
**Source review:** .planning/phases/03-remote-computer-operations-isolated/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 3
- Skipped: 1

## Fixed Issues

### CR-01: Null `ManagedOUs` bypasses the fail-closed scope gate

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`, `tests/Config.Load.Tests.ps1`
**Commit:** `1012479`
**Applied fix:** Replaced `@($config.ManagedOUs).Count` with a `Where-Object` filter that counts only non-whitespace DN strings, so `ManagedOUs: null` and whitespace-only entries cannot satisfy the CONF-02 scope gate. Added regression tests for null and whitespace-only values.

### CR-02: Null `DenyList` bypasses deny-list seeding and validation

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`, `tests/Config.Load.Tests.ps1`
**Commit:** `0bca8d4`
**Applied fix:** Made `DenyList` a required non-null array in `Test-AdmanConfigValid`, and extended `Initialize-AdmanConfig` to re-seed the shipped defaults when `DenyList` is present but `null`. This closes the silent bypass of the D-05 deny-list hard floor.

### WR-02: Timeout wrappers may misclassify array job output as success

**Files modified:** `Private/Remoting/Test-AdmanWsmanTimeout.ps1`, `Private/Remoting/Test-AdmanCimSessionTimeout.ps1`, `tests/Remoting.WsmanTimeout.Tests.ps1`, `tests/Remoting.CimSessionTimeout.Tests.ps1`
**Commit:** `15317ae`
**Applied fix:** Both wrappers now explicitly inspect `Receive-Job` output for `ErrorRecord` values, including inside arrays, before treating a probe as successful. Added regression tests that return an array containing data plus an `ErrorRecord` and assert failure.

## Supporting fix

### Allow null values in `ConvertTo-AdmanCleanConfig`

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `0f9139f`
**Applied fix:** Added `[AllowNull()]` to the `Node` parameter of `ConvertTo-AdmanCleanConfig` so null config values (e.g. `ManagedOUs: null`, `DenyList: null`) are cleaned and reach the fail-closed validators instead of failing during config sanitization. This was required for the CR-01 and CR-02 regression tests to pass.

## Skipped Issues

### WR-01: Inventory report menu metadata uses user properties instead of computer properties

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:83`
**Reason:** Code context differs from review. The current source already builds `$computerReportProperties` from `$computerProperties`, not `$userProperties`, so the reported bug is not present. The existing `Menu.Tests.ps1` contract test (`Get-AdmanInventoryReport` contains `OperatingSystem`) passes.
**Original issue:** `$computerReportProperties` was reported as built from `$userProperties`, which would omit computer-specific columns such as `OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`, `IPv4Address`, and `DNSHostName`.

---

_Fixed: 2026-07-17_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
