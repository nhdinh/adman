---
phase: 01-ad-query-reporting-read-only
fixed_at: 2026-07-15T00:00:00Z
review_path: .planning/phases/01-ad-query-reporting-read-only/01-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Fixed at:** 2026-07-15T00:00:00Z
**Source review:** .planning/phases/01-ad-query-reporting-read-only/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (2 Critical + 5 Warning; fix_scope=critical_warning)
- Fixed: 7
- Skipped: 0

**Unit test suite:** 323 passed / 0 failed / 9 not-run (was 322 passed pre-fix; +1 from new CR-02 ObjectSid assertion). All green.

## Fixed Issues

### CR-01: Scriptblock injection via property name in Export-AdmanReportHtml

**Files modified:** `Public/Export-AdmanReportHtml.ps1`
**Commit:** f4f5cee
**Applied fix:** Replaced `[scriptblock]::Create("if (`$_.$prop) { 'True' } else { 'False' }")` calculated-property projection with a safe per-row loop that reads each property value via `$row.PSObject.Properties[$prop].Value` and writes 'True'/'False' for boolean columns. No string-built scriptblocks anywhere; a crafted property name in piped input can no longer achieve code injection.

### CR-02: Search-ADAccount does not return ObjectSid; D-03 schema column is always $null

**Files modified:** `Public/Get-AdmanAccountStateReport.ps1`, `tests/Mocks/ActiveDirectory.psm1`, `tests/Report.AccountState.Tests.ps1`
**Commit:** 681e990
**Applied fix:**
- Production: after `Search-ADAccount`, annotate each raw object with `ObjectSid = $obj.SID` when `SID` is present and `ObjectSid` is absent, so `ConvertTo-AdmanResult` populates the D-03 column.
- Mock: rebuilt `Search-ADAccount` mock to return the real cmdlet's fixed property set (`Name`, `SamAccountName`, `DistinguishedName`, `Enabled`, `SID`, `ObjectGUID`, `UserPrincipalName`, `LastLogonDate`, `LockedOut`, `PasswordExpired`, `PasswordLastSet`, `AccountExpirationDate`, `whenCreated`, `whenChanged`) — exposes `SID`, NOT `ObjectSid`. The mock no longer masks the production bug.
- Test: added `populates ObjectSid on every row` assertion that pins the realistic shape (would have failed before the production fix).

### WR-01: Uninitialized $script:Config throws under StrictMode in every query verb

**Files modified:** `Public/Get-AdmanStaleReport.ps1`, `Public/Find-AdmanUser.ps1`, `Public/Find-AdmanComputer.ps1`, `Public/Get-AdmanInventoryReport.ps1`, `Public/Get-AdmanAccountStateReport.ps1`
**Commit:** dd79060
**Applied fix:** Added a uniform guard at the top of each query verb: `if (-not $script:Config -or -not $script:Config.PSObject.Properties['ManagedOUs'] -or -not $script:Config.ManagedOUs) { throw 'adman is not initialized. Run Initialize-Adman first.' }`. Works against both the initial `@{}` hashtable and the post-init `[pscustomobject]` shape (verified `PSObject.Properties[...]` returns `$null` for missing keys on both).

### WR-02: Test-AdmanTargetAllowed throws on DC failure instead of returning a refusal

**Files modified:** `Private/Safety/Test-AdmanTargetAllowed.ps1`
**Commit:** c45a2aa
**Applied fix:** Wrapped the recursive protected-membership `Get-ADObject` call in try/catch. On DC failure, adds `"protected-membership check failed: <message>"` to the reasons list (so the function returns `@{ Allowed = $false; Reason = '...' }`) instead of letting the exception propagate as an unhandled error.

### WR-03: Get-AdmanRecoveryPostureReport throws when $script:Config is uninitialized

**Files modified:** `Private/Foundation/Get-AdmanRecoveryPosture.ps1`
**Commit:** 52a005e
**Applied fix:** Made the foundation function tolerate an uninitialized `$script:Config` by reading `DC` via `$script:Config.PSObject.Properties['DC']` (yields `$null` instead of StrictMode `PropertyNotFoundException`). Each AD read below was already wrapped in try/catch and degrades to `$null` + `Write-PSFMessage` warning, so a `$null` DC simply produces an all-null posture with warnings — never a throw. The report verb's "works pre-init" promise now holds.

### WR-04: ConvertTo-AdmanResult leaks a script-scope helper function

**Files modified:** `Private/Reporting/ConvertTo-AdmanResult.ps1`
**Commit:** 7c526d9
**Applied fix:** Changed `function script:Get-AdmanProp` to `function Get-AdmanProp` (local scope). The helper no longer persists in the module's script scope after `ConvertTo-AdmanResult` returns; each call defines a fresh local.

### WR-05: Header-only CSV writes unquoted property names

**Files modified:** `Public/Export-AdmanReportCsv.ps1`
**Commit:** a3250f5
**Applied fix:** RFC 4180-quote any header name containing a comma, quote, CR, or LF in the empty-pipeline header path. Embedded quotes are doubled per RFC 4180 section 2. The renderer no longer relies on the D-03 schema invariant that column names are CSV-safe.

## Skipped Issues

None — all 7 in-scope findings were fixed.

## Out-of-Scope Findings (Info, not in fix_scope)

- IN-01: Get-AdmanLogonSyncInterval accesses $script:Config.DC without existence check
- IN-02: Menu.Tests.ps1 uses $global: for answer queue
- IN-03: Read-AdmanActionParams throws a bare string sentinel

---

_Fixed: 2026-07-15T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
