---
phase: 03-remote-computer-operations-isolated
reviewed: 2026-07-17T00:00:00Z
depth: standard
files_reviewed: 22
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
  critical: 2
  warning: 2
  info: 5
  total: 9
status: issues_found
---

# Phase 03: Remote Computer Operations - Code Review Report

**Reviewed:** 2026-07-17
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

Reviewed the Phase 03 implementation for isolated per-target remoting, WinRM/CIM fallback ladder, cache/timecap handling, inventory reporting, and double-hop/CredSSP guardrails. The transport ladder, CIM allow-list guard, and timeout wrappers are well-structured and covered by tests. However, two fail-closed safety invariants in `Initialize-AdmanConfig` can be bypassed with `null` config values, and the inventory report's menu metadata uses the wrong property set. Several minor quality items were also noted.

## Critical Issues

### CR-01: Null `ManagedOUs` bypasses the fail-closed scope gate

**File:** `Private/Config/Initialize-AdmanConfig.ps1:278-281`
**Issue:** When `ManagedOUs` is present in the config but set to `null`, the empty-scope gate does not throw. The validator explicitly allows `null` at line 96 (`$null -ne $Config.ManagedOUs`), and the gate computes `$scopeCount = @($config.ManagedOUs).Count`. In PowerShell `@($null).Count` returns `1`, so `$scopeCount -lt 1` is false and the throw is skipped. This violates the CONF-02 fail-closed contract.
**Fix:** Reject `null` `ManagedOUs` in `Test-AdmanConfigValid`, or change the gate to test the actual array contents:

```powershell
$scopeCount = @($config.ManagedOUs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
if ($scopeCount -lt 1) { throw ... }
```

### CR-02: Null `DenyList` bypasses deny-list seeding and validation

**File:** `Private/Config/Initialize-AdmanConfig.ps1:104-118,267-273`
**Issue:** `Test-AdmanConfigValid` only validates `DenyList` when it is non-null, so a config with `"DenyList": null` passes validation. The seed step at line 267 only runs when the `DenyList` property is *absent*, not when it is present but null. As a result, `$script:Config.DenyList` remains `$null`, `Get-AdmanProtectedIdentity` produces an empty `$script:DenyRids` set, and the deny-list hard floor in `Test-AdmanTargetAllowed` is silently disabled. This bypasses D-05 protection for RID 500/501/502 and well-known SIDs.
**Fix:** Treat a present-but-null `DenyList` as a validation failure (or re-seed it). In `Test-AdmanConfigValid`, require `DenyList` to be a non-null array:

```powershell
if (-not ($Config.PSObject.Properties.Name -contains 'DenyList') -or $null -eq $Config.DenyList) {
    throw "Config validation failed: 'DenyList' is required and must be an array."
}
```

## Warnings

### WR-01: Inventory report menu metadata uses user properties instead of computer properties

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:83`
**Issue:** `$computerReportProperties` is built from `$userProperties` rather than `$computerProperties`. The current line produces headers for `DisplayName`, `UserPrincipalName`, `LockedOut`, etc., and omits computer-specific columns such as `OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`, `IPv4Address`, and `DNSHostName`. This corrupts zero-row or header-driven renders of the fleet inventory report.
**Fix:** Use the computer property set:

```powershell
$computerReportProperties = [string[]]($computerProperties + 'Bucket' + 'Transport' + 'RemoteOS' + 'Uptime' + 'LoggedOnUser')
```

### WR-02: Timeout wrappers may misclassify array job output as success

**File:** `Private/Remoting/Test-AdmanWsmanTimeout.ps1:33-34`, `Private/Remoting/Test-AdmanCimSessionTimeout.ps1:36-37`
**Issue:** Both wrappers check whether `Receive-Job` output is an `ErrorRecord`. If a job emits an array containing both data and an error (or any non-ErrorRecord object), the `-isnot [System.Management.Automation.ErrorRecord]` test is true and the wrapper treats the probe as successful. A dead or misbehaving host could be classified as reachable, causing `Get-AdmanInventoryReport` to spend time and budget on it.
**Fix:** Inspect the output collection explicitly. For example, in `Test-AdmanCimSessionTimeout`:

```powershell
$output = Receive-Job -Job $job -ErrorAction SilentlyContinue
if ($output -is [System.Management.Automation.ErrorRecord]) { return $false }
if ($output -is [array] -and $output.Where({ $_ -is [System.Management.Automation.ErrorRecord] }, 'First')) { return $false }
$success = $true
```

## Info

### IN-01: Unit tests depend on a real local CIM session

**File:** `tests/Remoting.Query.Tests.ps1:50`, `tests/Remoting.DoubleHop.Tests.ps1:51`
**Issue:** To satisfy `Get-CimInstance` parameter binding, these tests create an actual `New-CimSession -ComputerName localhost -Protocol Dcom` session. This makes the tests dependent on local CIM/DCOM being available and can fail in locked-down, headless, or CI environments even though the tests are labeled as offline unit tests.
**Fix:** Return a real `Microsoft.Management.Infrastructure.CimSession` object from a mock without creating a live session, or isolate this dependency behind a test fixture with a clear skip/guard.

### IN-02: Empty catch block swallows PSFramework import errors

**File:** `Private/Config/Initialize-AdmanConfig.ps1:313`
**Issue:** `try { Import-PSFConfig -Path $path -ErrorAction SilentlyContinue } catch { }` silently discards all errors. While the comment correctly notes that safety decisions do not depend on this import, an empty catch makes diagnostics difficult when PSFramework is missing, mismatched, or the path is unreadable.
**Fix:** Write at least a verbose diagnostic message inside the catch block, e.g. `Write-Verbose "PSFramework config import skipped: $_"`.

### IN-03: WinRM unreachable error code not matched in hex form

**File:** `Private/Remoting/Convert-AdmanRemoteError.ps1:35`
**Issue:** The regex matches the decimal error code `2150859046` but not its common hexadecimal representation `0x80338012` (`WS-MAN cannot complete the operation`). Messages containing the hex form will fall through to the generic "Remote error" translation.
**Fix:** Extend the pattern to match both forms:

```powershell
if ($msg -match 'WinRM cannot complete the operation|2150859046|0x80338012') { ... }
```

### IN-04: `[int]` casts silently truncate non-integer numeric config values

**File:** `Private/Config/Initialize-AdmanConfig.ps1:124,139,145,168`
**Issue:** Config values such as `bulkConfirmThreshold` and `perHostProbeCap` are validated with `[int]$value`. This silently truncates decimals (e.g., `1.9` becomes `1`) and allows values the schema declares as integers. The validator is therefore less strict than the JSON schema.
**Fix:** Add an explicit integer/type check before casting, for example by rejecting values that are not already `[int]` or `[long]`.

### IN-05: Default config path is recomputed multiple times

**File:** `Private/Config/Initialize-AdmanConfig.ps1:225,245,268`
**Issue:** `$defaultsPath = Join-Path $moduleRoot 'config🔘defaults.json'` is built three times within the same function. This is redundant and slightly increases the risk of future drift if the path construction changes.
**Fix:** Compute `$defaultsPath` once near the top of the function and reuse it.

---

_Reviewed: 2026-07-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
