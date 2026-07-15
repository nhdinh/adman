---
phase: 01-ad-query-reporting-read-only
reviewed: 2026-07-15T00:00:00Z
depth: standard
files_reviewed: 33
files_reviewed_list:
  - Private/Foundation/Get-AdmanLogonSyncInterval.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Menu/Read-AdmanActionParams.ps1
  - Private/Reporting/ConvertTo-AdmanResult.ps1
  - Private/Reporting/Test-AdmanInManagedScope.ps1
  - Private/Safety/Test-AdmanTargetAllowed.ps1
  - Private/Utility/ConvertTo-AdmanNormalizedDn.ps1
  - Private/Utility/Escape-AdmanAdFilterLiteral.ps1
  - Public/Export-AdmanReportCsv.ps1
  - Public/Export-AdmanReportHtml.ps1
  - Public/Find-AdmanComputer.ps1
  - Public/Find-AdmanUser.ps1
  - Public/Format-AdmanReport.ps1
  - Public/Get-AdmanAccountStateReport.ps1
  - Public/Get-AdmanInventoryReport.ps1
  - Public/Get-AdmanRecoveryPostureReport.ps1
  - Public/Get-AdmanStaleReport.ps1
  - Public/Initialize-Adman.ps1
  - Public/Start-Adman.ps1
  - adman.psd1
  - tests/Find.Computer.Tests.ps1
  - tests/Find.User.Tests.ps1
  - tests/Initialize.Adman.Tests.ps1
  - tests/Menu.Tests.ps1
  - tests/Mocks/ActiveDirectory.psm1
  - tests/Preflight.Tests.ps1
  - tests/Render.Tests.ps1
  - tests/Report.AccountState.Tests.ps1
  - tests/Report.Inventory.Tests.ps1
  - tests/Report.Recovery.Tests.ps1
  - tests/Report.Stale.Tests.ps1
  - tests/Result.Schema.Tests.ps1
  - tests/Utility.EscapeFilter.Tests.ps1
findings:
  critical: 2
  warning: 5
  info: 3
  total: 10
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-07-15T00:00:00Z
**Depth:** standard
**Files Reviewed:** 33
**Status:** issues_found

## Summary

Reviewed the Phase 1 read-only AD query/reporting surface: Find verbs, report verbs, renderers, menu dispatcher, schema mapper, scope checker, escape helpers, and the full Pester test suite. The code is generally well-structured and the safety invariants (LDAP filter escaping, scope re-check, no UAC bit math, no per-DC lastLogon) are correctly implemented and pinned by tests. However, two defects can produce incorrect behavior or a runtime failure in realistic conditions, and several warnings degrade robustness or maintainability.

## Critical Issues

### CR-01: Scriptblock injection via property name in Export-AdmanReportHtml

**File:** `Public/Export-AdmanReportHtml.ps1:199`
**Issue:** The boolean-column conversion builds a calculated property with `[scriptblock]::Create("if (`$_.$prop) { 'True' } else { 'False' }")`. The `$prop` value is taken from `$rows[0].PSObject.Properties.Name`. While the D-03 schema produced by `ConvertTo-AdmanResult` uses hard-coded safe names, `Export-AdmanReportHtml` is a Public exported function that accepts ANY piped object. A caller (or a future code path) that pipes an object with a crafted property name such as `x) { evil(); }` achieves arbitrary code execution inside the renderer. This is a code-injection sink in a security-sensitive admin tool.
**Fix:**
```powershell
# Do NOT use [scriptblock]::Create on a property name.
# Instead, project the rows with a loop that reads the property value directly:
$converted = foreach ($row in $rows) {
    $h = [ordered]@{}
    foreach ($prop in $row.PSObject.Properties.Name) {
        if ($prop -in $booleanColumns) {
            $h[$prop] = if ($row.$prop) { 'True' } else { 'False' }
        } else {
            $h[$prop] = $row.$prop
        }
    }
    [pscustomobject]$h
}
$htmlResult = $converted | ConvertTo-Html -Head $css -Title $Title
```

### CR-02: Search-ADAccount does not return ObjectSid; D-03 schema column is always $null

**File:** `Public/Get-AdmanAccountStateReport.ps1:65-70`
**Issue:** `Search-ADAccount` has no `-Properties` parameter and returns a fixed property set (`Name`, `SamAccountName`, `DistinguishedName`, `Enabled`, `SID`, `ObjectGUID`, `UserPrincipalName`, `LastLogonDate`, `LockedOut`, `PasswordExpired`, `PasswordLastSet`, `AccountExpirationDate`, `whenCreated`, `whenChanged`). It returns `SID`, not `ObjectSid`. `ConvertTo-AdmanResult` reads `ObjectSid`, so every account-state report row has `$null` in the `ObjectSid` column. The mock in `tests/Mocks/ActiveDirectory.psm1` supplies `ObjectSid`, so the tests pass while the real cmdlet produces a null column. The D-03 schema contract (fixed identity/scope columns always present) is silently broken for this report.
**Fix:**
```powershell
# After Search-ADAccount, re-fetch the full object with Get-ADUser/Get-ADComputer
# to obtain the D-02 property set, or map SID -> ObjectSid before ConvertTo-AdmanResult.
# Minimal fix: annotate the raw object so ConvertTo-AdmanResult sees ObjectSid.
foreach ($obj in @($raw)) {
    if ($obj.PSObject.Properties['SID'] -and -not $obj.PSObject.Properties['ObjectSid']) {
        $obj | Add-Member -MemberType NoteProperty -Name 'ObjectSid' -Value $obj.SID -Force
    }
    $mapped = ConvertTo-AdmanResult -ADObject $obj -ObjectType $ObjectType
    ...
}
```

## Warnings

### WR-01: Uninitialized $script:Config throws under StrictMode in every query verb

**File:** `Public/Get-AdmanStaleReport.ps1:54`, `Public/Find-AdmanUser.ps1:90`, `Public/Find-AdmanComputer.ps1:65`, `Public/Get-AdmanInventoryReport.ps1:41`, `Public/Get-AdmanAccountStateReport.ps1:42`
**Issue:** `adman.psm1` initializes `$script:Config = @{}`. Under `Set-StrictMode -Version Latest`, accessing `$script:Config.ManagedOUs` or `$script:Config.DC` on an empty hashtable throws `PropertyNotFoundException`. Every query verb loops `foreach ($root in @($script:Config.ManagedOUs))` and pins `-Server $script:Config.DC` without first verifying that `Initialize-Adman` has run. A senior admin who imports the module and calls `Get-AdmanStaleReport` directly (the exact scenario MENU-04 promises) gets a StrictMode throw instead of a useful error.
**Fix:**
```powershell
# At the top of each Public query verb, fail with a clear message:
if (-not $script:Config -or -not $script:Config.PSObject.Properties['ManagedOUs'] -or -not $script:Config.ManagedOUs) {
    throw 'adman is not initialized. Run Initialize-Adman first.'
}
```

### WR-02: Test-AdmanTargetAllowed throws on DC failure instead of returning a refusal

**File:** `Private/Safety/Test-AdmanTargetAllowed.ps1:91-92`
**Issue:** The recursive protected-membership check calls `Get-ADObject -ErrorAction Stop` without a try/catch. If the DC is unreachable, the function throws a terminating error instead of returning `@{ Allowed = $false; Reason = '...' }`. The documented contract is a hashtable return; the throw propagates through `Invoke-AdmanMutation` and surfaces as an unhandled exception rather than a logged refusal.
**Fix:**
```powershell
try {
    $hit = Get-ADObject -Server $script:Config.DC -LDAPFilter "(&(distinguishedName=$dnEsc)(|$or))" -ErrorAction Stop
    if ($hit) { $reasons.Add('recursive member of protected group') }
} catch {
    $reasons.Add("protected-membership check failed: $($_.Exception.Message)")
}
```

### WR-03: Get-AdmanRecoveryPostureReport throws when $script:Config is uninitialized

**File:** `Public/Get-AdmanRecoveryPostureReport.ps1:34`
**Issue:** The fallback path calls `Get-AdmanRecoveryPosture`, which reads `$script:Config.DC` at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:31`. When `$script:Config` is the empty hashtable `@{}`, StrictMode throws. The report verb promises to work "pre-init" but does not.
**Fix:**
```powershell
# In Get-AdmanRecoveryPostureReport, guard the fallback:
if (-not $script:Config -or -not $script:Config.PSObject.Properties['DC']) {
    throw 'adman is not initialized. Run Initialize-Adman first.'
}
# Or make Get-AdmanRecoveryPosture tolerate a missing DC by using a parameter default.
```

### WR-04: ConvertTo-AdmanResult leaks a script-scope helper function

**File:** `Private/Reporting/ConvertTo-AdmanResult.ps1:45`
**Issue:** `function script:Get-AdmanProp` is defined inside `ConvertTo-AdmanResult` but scoped to `script:`, so it persists in the module's script scope after the function returns. Every call redefines it. This is unnecessary scope pollution and can shadow a future module-level helper of the same name.
**Fix:**
```powershell
# Use a local function (no scope modifier) or inline the logic:
function Get-AdmanProp { ... }  # local to ConvertTo-AdmanResult
```

### WR-05: Header-only CSV writes unquoted property names

**File:** `Public/Export-AdmanReportCsv.ps1:111`
**Issue:** The empty-pipeline header path joins `$Properties` with `,` and writes the line raw. If a future schema column ever contains a comma, quote, or newline, the CSV is malformed. The current D-03 names are safe, but the renderer should not rely on that invariant.
**Fix:**
```powershell
$header = (@($Properties) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
    $s = [string]$_
    if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
}) -join ','
```

## Info

### IN-01: Get-AdmanLogonSyncInterval accesses $script:Config.DC without existence check

**File:** `Private/Foundation/Get-AdmanLogonSyncInterval.ps1:42`
**Issue:** Same uninitialized-config pattern as WR-01, but the function is wrapped in a blanket `try/catch` that returns the default 14 on any error. The throw is therefore swallowed and the function silently returns 14 when the real cause is "not initialized." This masks a configuration error as a benign default.
**Fix:** Add an explicit guard before the `Get-ADDomain` call so the "not initialized" case is distinguishable from an AD read failure, or at least log it.

### IN-02: Menu.Tests.ps1 uses $global: for answer queue

**File:** `tests/Menu.Tests.ps1:327-329, 357-359, 383-385, 417-419, 448-450, 480-482, 509-511`
**Issue:** The behavioral menu tests store the Read-Host answer queue in `$global:answers` / `$global:answerIdx`. The project lint gate (`PSAvoidGlobalVars`) is documented as enforced; the tests contradict that rule. The Initialize.Adman.Tests.ps1 file already demonstrates the correct pattern (`$script:` scope inside the test file).
**Fix:** Replace `$global:answers` / `$global:answerIdx` with `$script:answers` / `$script:answerIdx` in Menu.Tests.ps1.

### IN-03: Read-AdmanActionParams throws a bare string sentinel

**File:** `Private/Menu/Read-AdmanActionParams.ps1:67, 84`
**Issue:** `throw 'ADMAN_QUIT'` throws a string, not an ErrorRecord or Exception. The caller (`Start-Adman`) catches it by matching `$_.Exception.Message -match 'ADMAN_QUIT'`. Throwing a string works but produces a less useful error record and is inconsistent with PowerShell best practice.
**Fix:**
```powershell
throw [System.Management.Automation.RuntimeException]::new('ADMAN_QUIT')
```

---

_Reviewed: 2026-07-15T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
