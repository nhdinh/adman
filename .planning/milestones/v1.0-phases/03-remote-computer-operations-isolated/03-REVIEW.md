---
phase: 03-remote-computer-operations-isolated
reviewed: 2026-07-17T12:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Remoting/Connect-AdmanTarget.ps1
  - Private/Remoting/Convert-AdmanRemoteError.ps1
  - Private/Remoting/Invoke-AdmanRemoteCimQuery.ps1
  - Private/Remoting/Invoke-AdmanRemoteQuery.ps1
  - Private/Remoting/Test-AdmanCimSessionTimeout.ps1
  - Private/Remoting/Test-AdmanWsmanTimeout.ps1
  - Public/Get-AdmanInventoryReport.ps1
  - adman.psm1
  - config/adman.defaults.json
  - config/adman.example.json
  - config/adman.schema.json
  - docs/REMOTE-OPS.md
  - tests/Remoting.Cache.Tests.ps1
  - tests/Remoting.CimSessionTimeout.Tests.ps1
  - tests/Remoting.DoubleHop.Tests.ps1
  - tests/Remoting.Ladder.Tests.ps1
  - tests/Remoting.Query.Tests.ps1
  - tests/Remoting.Skipped.Tests.ps1
  - tests/Remoting.TimeCaps.Tests.ps1
  - tests/Remoting.WsmanTimeout.Tests.ps1
  - tests/Report.Inventory.Tests.ps1
findings:
  critical: 1
  warning: 7
  info: 0
  total: 8
status: issues_found
---

# Phase 03: Remote Computer Operations - Code Review Report

**Reviewed:** 2026-07-17
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed the Phase 03 implementation for isolated per-target remoting, the WinRM/CIM/DCOM fallback ladder, process-only transport cache, hard-timeout wrappers, remote inventory enrichment, and double-hop/CredSSP guardrails. The CIM allow-list guard and timeout-probe structure are sound, but one security gap remains in config validation and several robustness/quality defects weaken the timeout and reliability guarantees.

## Critical Issues

### CR-01 (BLOCKER): Empty `DenyList` array disables the protected-account hard floor

**File:** `Private/Config/Initialize-AdmanConfig.ps1:105-120,270-276`
**Issue:** `Test-AdmanConfigValid` accepts an empty array (`@()`) because it only checks `-is [array]` and iterates over entries. The seed step at line 270 only triggers when the `DenyList` property is absent or `$null`, not when it is an empty array. An operator (or a compromised/mis-edited config) can set `"DenyList": []` and the hard floor that blocks RIDs 500/501/502 and well-known SIDs is silently removed. This bypasses SAFE-05/D-05 and could allow destructive operations against protected identities when they fall under a managed OU.
**Fix:** Treat an empty `DenyList` as fail-closed. Either reject it in validation or re-seed it from defaults:

```powershell
# Option A: reject empty
if ($Config.DenyList.Count -lt 1) {
    throw "Config validation failed: 'DenyList' must contain at least one protected identity entry."
}

# Option B: re-seed empty alongside null/absent
if (-not ($config.PSObject.Properties.Name -contains 'DenyList') -or
    $null -eq $config.DenyList -or
    $config.DenyList.Count -eq 0) {
    # ... seed from defaults ...
}
```

## Warnings

### WR-01 (WARNING): Total fleet remote-enrichment cap is not enforced within a single host

**File:** `Public/Get-AdmanInventoryReport.ps1:84-118`
**Issue:** The `totalInventoryRemoteCap` check runs only at the start of each loop iteration. `Connect-AdmanTarget` and `Invoke-AdmanRemoteQuery` for one host can consume up to `perHostProbeCap` plus query time, so a single slow host can push total elapsed time well beyond the configured total cap before the next row is checked. This undermines the D-02/RMT-02 guarantee that the entire fleet enrichment pass is bounded.
**Fix:** Pass the remaining total budget into the per-host work and abort mid-host when it is exhausted:

```powershell
$hostBudget = [math]::Min($perHostCap, [int]($totalCap - $totalStopwatch.Elapsed.TotalSeconds))
if ($hostBudget -le 0) {
    $transport = 'Skipped'
    $skipped++
}
else {
    $transport = Connect-AdmanTarget -ComputerName $targetName
    $remote = Invoke-AdmanRemoteQuery -ComputerName $targetName -Transport $transport -TimeoutSeconds $hostBudget
    # ...
}
```

### WR-02 (WARNING): Data-path CIM calls rely on `-OperationTimeoutSec`, not the hard `Start-Job` timeout

**File:** `Private/Remoting/Invoke-AdmanRemoteQuery.ps1:59-93`
**Issue:** The function probes session setup with `Test-AdmanCimSessionTimeout` (`Start-Job` + `Wait-Job`), but the real `New-CimSession` and both `Get-CimInstance` calls are direct cmdlet invocations with `-OperationTimeoutSec`. On Windows PowerShell 5.1, `-OperationTimeoutSec` may not cover the initial TCP handshake or a hung provider as reliably as the `Start-Job` wrapper, so a dead or misbehaving host can still hang the menu during data retrieval.
**Fix:** Perform the whole query inside a single `Start-Job` bounded by the remaining timeout, or reuse the probe's timed pattern for the actual data call:

```powershell
$job = Start-Job -ScriptBlock {
    param($cn, $proto, $to)
    $opt = New-CimSessionOption -Protocol $proto
    $sess = New-CimSession -ComputerName $cn -SessionOption $opt -OperationTimeoutSec $to -ErrorAction Stop
    $os = Get-CimInstance -CimSession $sess -ClassName Win32_OperatingSystem -OperationTimeoutSec $to
    $cs = Get-CimInstance -CimSession $sess -ClassName Win32_ComputerSystem -OperationTimeoutSec $to
    Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue
    @{ OS = $os; CS = $cs }
} -ArgumentList $ComputerName, $protocol, $remainingSeconds
```

### WR-03 (WARNING): `transport.order` is required and validated but never consumed

**File:** `Private/Config/Initialize-AdmanConfig.ps1:132-133`, `config/adman.defaults.json:32`, `Private/Remoting/Connect-AdmanTarget.ps1:34-62`
**Issue:** The schema and validator require `transport.order`, but `Connect-AdmanTarget` hardcodes WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped and never reads it. The shipped default also uses `"Skip"` while the code uses `"Skipped"`. This makes the config setting misleading and creates a future footgun if the ladder is made data-driven.
**Fix:** Either consume `transport.order` in the ladder and normalize `"Skip"` to `"Skipped"`, or remove `transport.order` from the required config until it is implemented.

### WR-04 (WARNING): Inventory report uses AD `Name` instead of `DNSHostName` for remote queries

**File:** `Public/Get-AdmanInventoryReport.ps1:93,104`
**Issue:** `Connect-AdmanTarget` and `Invoke-AdmanRemoteQuery` are called with `$row.Name` (the CN/NetBIOS name). The report already retrieves `DNSHostName`, which is the resolvable FQDN. Using `Name` can fail or resolve incorrectly in multi-domain forests or when the CN differs from the host's DNS record, causing reachable hosts to be reported as `Skipped`.
**Fix:** Prefer `DNSHostName` when present:

```powershell
$targetName = if ($row.DNSHostName) { $row.DNSHostName } else { $row.Name }
$transport = Connect-AdmanTarget -ComputerName $targetName
$remote = Invoke-AdmanRemoteQuery -ComputerName $targetName -Transport $transport -TimeoutSeconds $remainingSeconds
```

### WR-05 (WARNING): `Convert-AdmanRemoteError` misses the hex form of the WinRM unreachable code

**File:** `Private/Remoting/Convert-AdmanRemoteError.ps1:35-36`
**Issue:** The regex matches the decimal string `2150859046` but not the common hexadecimal HRESULT `0x80338012` (`WS-MAN cannot complete the operation`). Messages containing the hex form fall through to the generic translation, giving operators less actionable diagnostics.
**Fix:** Extend the pattern:

```powershell
if ($msg -match 'WinRM cannot complete the operation|2150859046|0x80338012') {
    return 'WinRM unreachable'
}
```

### WR-06 (WARNING): Empty catch block swallows PSFramework import failures

**File:** `Private/Config/Initialize-AdmanConfig.ps1:318`
**Issue:** `try { Import-PSFConfig -Path $path -ErrorAction SilentlyContinue } catch { }` silently discards all errors. While safety values are loaded directly first, a failed PSFramework import can mask environment or dependency problems and makes troubleshooting harder.
**Fix:** Write at least a verbose diagnostic inside the catch:

```powershell
catch {
    Write-Verbose "PSFramework config import skipped for '$path': $_"
}
```

### WR-07 (WARNING): Unit tests depend on live local DCOM CIM sessions

**File:** `tests/Remoting.Query.Tests.ps1:50`, `tests/Remoting.DoubleHop.Tests.ps1:51`
**Issue:** To satisfy `Get-CimInstance` parameter binding, these tests create a real `New-CimSession -ComputerName localhost -Protocol Dcom`. This makes the unit suite dependent on local CIM/DCOM being enabled and accessible, causing flaky failures in CI, headless, or locked-down environments even though the tests are tagged as offline unit tests.
**Fix:** Return a real `Microsoft.Management.Infrastructure.CimSession` object from a mock/factory without establishing a live session, or gate the tests with a capability probe and skip when CIM is unavailable.

---

_Reviewed: 2026-07-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
