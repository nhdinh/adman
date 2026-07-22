---
phase: 05-hardening-portability
reviewed: 2026-07-22T06:49:23Z
depth: standard
files_reviewed: 53
files_reviewed_list:
  - .github/workflows/ci.yml
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Add-AdmanGroupMember.ps1
  - Public/Add-AdmanLocalGroupMember.ps1
  - Public/Config/Export-AdmanConfig.ps1
  - Public/Config/Get-AdmanConfig.ps1
  - Public/Config/Import-AdmanConfig.ps1
  - Public/Config/Set-AdmanConfig.ps1
  - Public/Disable-AdmanComputer.ps1
  - Public/Disable-AdmanUser.ps1
  - Public/Enable-AdmanComputer.ps1
  - Public/Enable-AdmanUser.ps1
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
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Move-AdmanComputer.ps1
  - Public/Move-AdmanUser.ps1
  - Public/New-AdmanUser.ps1
  - Public/Remove-AdmanGroupMember.ps1
  - Public/Remove-AdmanLocalGroupMember.ps1
  - Public/Remove-AdmanLocalUser.ps1
  - Public/Reset-AdmanComputerAccount.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Start-Adman.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - Public/Test-AdmanCapability.ps1
  - Public/Unlock-AdmanUser.ps1
  - build/Sign-AdmanModule.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - tests/Audit.EventLog.Tests.ps1
  - tests/Audit.FailClosed.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Schema.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Help.Coverage.Tests.ps1
  - tests/PesterConfiguration.psd1
  - tests/Workflow.OffboardingState.Tests.ps1
findings:
  critical: 2
  warning: 6
  info: 3
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-22T06:49:23Z
**Depth:** standard
**Files Reviewed:** 53
**Status:** issues_found

## Summary

Reviewed the Phase 5 hardening/portability deliverables: dual-edition CI workflow, audit hash-chain/rotation, config loader, offboarding-state restore, all public verbs, report renderers, signing script, defaults/schema, and unit tests.

Two security blockers remain:

1. `Export-AdmanReportHtml` interpolates the caller-supplied `-Title` directly into HTML/CSS without encoding, creating an XSS / HTML-injection vector.
2. `Restore-AdmanQuarantinedUser` reads authoritative restore state from the audit log but never verifies the file's hash-chain integrity, so a tampered audit record can drive an attacker-controlled restore.

The rest of the codebase is consistent with the established safety patterns (fail-closed config, PENDING/OUTCOME audit pairs, managed-OU scope checks, DPAPI-free password display). The warnings below are maintainability and correctness gaps that should be closed before the phase is considered complete.

## Critical Issues

### CR-01: XSS / HTML injection via unescaped `-Title` in `Export-AdmanReportHtml`

**File:** `Public/Export-AdmanReportHtml.ps1:148, 169, 185`
**Issue:** The `-Title` parameter is embedded verbatim into the generated HTML/CSS. A caller can inject arbitrary markup or script (e.g. `</style><script>...</script>`) that executes when the self-contained report is opened in a browser. Because the report is designed to be emailed/shared, this is a stored XSS vulnerability.
**Fix:** HTML-encode `$Title` once and reuse the encoded value:

```powershell
$safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
$css = @"
<style>
...
<title>$safeTitle</title>
"@
...
<h1>$safeTitle</h1>
```

### CR-02: `Restore-AdmanQuarantinedUser` trusts tamperable audit records

**File:** `Public/Restore-AdmanQuarantinedUser.ps1:99` and `Private/Workflow/Get-AdmanOffboardingState.ps1:59-87`
**Issue:** The restore workflow uses `Get-AdmanOffboardingState` to read the latest offboarding record from live and archived audit JSONL files. The codebase already ships `Get-AdmanAuditIntegrity` to detect tampering, but neither `Get-AdmanOffboardingState` nor `Restore-AdmanQuarantinedUser` calls it. An attacker with filesystem write access can modify `originalOU`/`groups` in an archived record and trick the restore into moving the user to an attacker-controlled OU or re-adding attacker-controlled groups. Although the managed-OU scope check blocks an out-of-scope destination, in-scope group membership tampering is not blocked.
**Fix:** Verify the integrity of any audit file before consuming records from it. In `Get-AdmanOffboardingState`, inside the file loop, call `Get-AdmanAuditIntegrity -Path $file.FullName` and throw if `Valid -eq $false`:

```powershell
foreach ($file in $auditFiles) {
    $integrity = Get-AdmanAuditIntegrity -Path $file.FullName
    if (-not $integrity.Valid) {
        throw "Audit integrity check failed for '$($file.FullName)': $($integrity.Reason)"
    }
    foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction Stop)) { ... }
}
```

## Warnings

### WR-01: `Set-AdmanUserPassword` help description contradicts implementation

**File:** `Public/Set-AdmanUserPassword.ps1:16-18` vs. `211-215`
**Issue:** The `.DESCRIPTION` claims the wrapper detects `$Parameters['Unlock']` and calls `Unlock-ADAccount` inside the same gate invocation. The actual code performs three separate `Invoke-AdmanMutation` calls (password reset, `Set-ADUser`, optional `Unlock-ADAccount`), each with its own audit pair and confirmation. The parameter help is correct, but the top-level description is stale and will mislead maintainers.
**Fix:** Rewrite the `.DESCRIPTION` to match the implementation: three distinct gate invocations, each with its own PENDING/OUTCOME audit and confirmation.

### WR-02: `Get-AdmanAuditIntegrity` reports missing files as valid

**File:** `Private/Audit/Rotation.ps1:97-103`
**Issue:** When the audit file does not exist, the function returns `Valid = $true` with `Reason = 'File not found.'`. For a tamper-evident verifier, a missing log is not evidence of integrity; a deleted audit file should be reported as a verification failure.
**Fix:** Return `Valid = $false` for missing files, or add a dedicated `Missing` flag and update callers/tests accordingly.

### WR-03: Redundant `$allowed.Count` guard in `Invoke-AdmanBulkAction`

**File:** `Public/Invoke-AdmanBulkAction.ps1:247`
**Issue:** The inner `if ($Action -in @('AddGroup', 'RemoveGroup') -and $allowed.Count -gt 0)` repeats a condition already guaranteed by the enclosing `if ($allowed.Count -gt 0)` block at line 239. This is harmless but unnecessary noise.
**Fix:** Remove the redundant `-and $allowed.Count -gt 0` clause.

### WR-04: `Initialize-AdmanConfig` reads `adman.defaults.json` repeatedly

**File:** `Private/Config/Initialize-AdmanConfig.ps1:263, 283, 305, 320, 344`
**Issue:** The defaults file is loaded and parsed five separate times during a single config load. This is inefficient and increases the chance that a future change to defaults-loading behavior is applied inconsistently.
**Fix:** Load `$defaults` once near the top of the function and reuse it for seeding timeouts, domain/templates, audit block, and deny-list.

### WR-05: `Get-AdmanInventoryReport` probes remote query even when transport is `Skipped`

**File:** `Public/Get-AdmanInventoryReport.ps1:94-118`
**Issue:** When `Connect-AdmanTarget` returns `'Skipped'`, the code still enters the remote-query branch and calls `Invoke-AdmanRemoteQuery -Transport 'Skipped'` as long as `queryRemaining` is positive. This wastes time and relies on `Invoke-AdmanRemoteQuery` to no-op for the skipped transport.
**Fix:** Skip `Invoke-AdmanRemoteQuery` when `$transport -eq 'Skipped'`:

```powershell
if ($transport -ne 'Skipped' -and $queryRemaining -gt 0) {
    $remote = Invoke-AdmanRemoteQuery ...
    ...
}
```

### WR-06: `Start-AdmanUserOnboarding` does not validate `NamePattern` format

**File:** `Public/Start-AdmanUserOnboarding.ps1:100`
**Issue:** The template `NamePattern` is passed directly to the `-f` format operator. A malformed pattern (e.g. `{2}` or invalid format specifiers) throws before the preflight checks can run, producing a confusing error.
**Fix:** Validate `NamePattern` is a valid two-argument format string during template validation (line 79-90), or wrap the format call in a try/catch with a clear message.

## Info

### IN-01: Plaintext password variables are not cleared after display

**File:** `Public/New-AdmanUser.ps1:220`, `Public/Set-AdmanUserPassword.ps1:238`, `Public/Set-AdmanLocalUser.ps1:223`
**Issue:** After displaying the generated password, the BSTR is zeroed, but the `$plain` string variable remains in managed memory until garbage collection. This weakens the shoulder-surf hygiene the code aims for.
**Fix:** Assign `$plain = $null` after `WriteLine` and before `Read-Host` (or at the end of the `try` block) so the reference is dropped promptly.

### IN-02: SHA256 instances are not disposed

**File:** `Private/Audit/Rotation.ps1:173`, `Private/Audit/Write-AdmanAudit.ps1:183-184`
**Issue:** `[System.Security.Cryptography.SHA256]::Create()` returns an `IDisposable` object that is left for finalization. On Windows this is generally harmless, but it is inconsistent with the careful resource handling elsewhere (stream dispose, mutex dispose, BSTR zeroing).
**Fix:** Wrap the SHA256 in a `try/finally` or use a `using` block and call `Dispose()`.

### IN-03: `Unlock-AdmanUser` `-WhatIf` fallback can use an empty DC

**File:** `Public/Unlock-AdmanUser.ps1:91-95`
**Issue:** Under `-WhatIf`, if the PDCe lookup fails, the verb falls back to `$script:Config.DC`. If the config DC is empty, the preview still renders but the downstream gate will fail with a less clear error than a direct "could not resolve PDC emulator" message.
**Fix:** If the fallback DC is empty/null, throw a clear error instead of passing an empty `-Server` into the gate.

---

_Reviewed: 2026-07-22T06:49:23Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
