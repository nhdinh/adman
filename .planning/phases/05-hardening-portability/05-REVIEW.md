---
phase: 05-hardening-portability
reviewed: 2026-07-23T15:30:00Z
depth: standard
files_reviewed: 56
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
  - docs/RECOVERY-RUNBOOK.md
  - docs/USAGE.md
  - tests/Audit.EventLog.Tests.ps1
  - tests/Audit.FailClosed.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Schema.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Docs.Coverage.Tests.ps1
  - tests/Help.Coverage.Tests.ps1
  - tests/PesterConfiguration.psd1
  - tests/Workflow.OffboardingState.Tests.ps1
findings:
  critical: 1
  warning: 7
  info: 8
  total: 16
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T15:30:00Z
**Depth:** standard
**Files Reviewed:** 56
**Status:** issues_found

## Summary

Reviewed the full Phase 5 source set: CI workflow, audit/config/workflow internals, all Public verbs, build signing, config schema/defaults, operator docs, and the unit-test suite. The prior fix commits (Ask ValidateSet, timestamp server, PromptSpec assertion, certificate selection) are present. One blocker remains around generated-password display ordering in `Set-AdmanUserPassword`, plus several warnings for parameter/schema drift, restore robustness, onboarding validation, config portability, and test isolation.

## Critical Issues

### CR-01: `Set-AdmanUserPassword` can lose the generated password on partial success

**File:** `Public/Set-AdmanUserPassword.ps1:203-265`
**Issue:** The verb issues three independent gate calls (Set-ADAccountPassword, Set-ADUser for `ChangePasswordAtLogon`, optional Unlock). If the password reset succeeds but the follow-up `Set-ADUser` call fails, the function throws at line 235 before the generated-password display block (lines 251-262) runs. The AD password has already been changed, but the operator never sees the new password, leaving the account stranded until another reset is performed.
**Fix:** Display the generated password immediately after the successful password-reset gate call, before any subsequent sub-operation can fail. Keep the transcript guard before the first mutation.

```powershell
# WR-02 transcript guard stays before the first mutation.
if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $NewPassword) {
    if ((Get-AdmanTranscriptCount) -gt 0) {
        throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
    }
}

$results = @()
$errors  = @()

# Sub-op 1: the password reset itself.
$resetParams = @{ NewPassword = $NewPassword }
try {
    $results += Invoke-AdmanMutation -Verb 'Set-ADAccountPassword' -Targets @($Identity) `
        -Parameters $resetParams -Force:$Force -WhatIf:$WhatIfPreference
} catch { $errors += $_ }

# Display the generated password as soon as the reset succeeded.
if ($errors.Count -eq 0 -and -not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $NewPassword) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Console]::WriteLine("Generated password for ${Identity}: $plain")
        Read-Host -Prompt 'Press Enter when recorded' | Out-Null
        try { [Console]::Clear() } catch [System.IO.IOException] { }
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

# Sub-op 2: apply ChangePasswordAtLogon via Set-ADUser.
if ($errors.Count -eq 0) { ... }

# Sub-op 3: optional Unlock.
if ($Unlock -and $errors.Count -eq 0) { ... }

if ($errors.Count -gt 0) { throw ... }
return $results[0]
```

## Warnings

### WR-01: `ValidateSet` on password-source parameters still blocks the documented `'Ask'` value

**Files:**
- `Public/New-AdmanUser.ps1:113`
- `Public/Set-AdmanUserPassword.ps1:103`
- `Public/Set-AdmanLocalUser.ps1:93`
**Issue:** The schema (`config/adman.schema.json:86`) and each verb's code branch allow `passwordSource = 'Ask'` (defaulting to `'Generate'` for direct callers). However, the `[ValidateSet('Generate', 'Prompt')]` declarations reject `'Ask'` at parameter-binding time, so a direct caller passing `-AccountPasswordSource Ask`, `-NewPasswordSource Ask`, or `-PasswordSource Ask` gets a validation error instead of the documented behavior.
**Fix:** Add `'Ask'` to each `ValidateSet` and update the matching `.PARAMETER` help text:

```powershell
[ValidateSet('Generate', 'Prompt', 'Ask')]
[string]$AccountPasswordSource
```

### WR-02: `Get-AdmanOffboardingState` crashes on malformed `tsUtc`

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:120`
**Issue:** The `Sort-Object` script block casts `$_.tsUtc` directly to `[datetime]`. If a matched archived offboarding record has a corrupted or non-ISO `tsUtc` value, the cast throws and aborts the entire restore workflow.
**Fix:** Defend the cast or skip unparseable records:

```powershell
$latest = $candidates | Sort-Object -Property {
    try { [datetime]$_.tsUtc } catch { [datetime]::MinValue }
} -Descending | Select-Object -First 1
```

### WR-03: `Start-AdmanUserOnboarding` preflight allows AD-invalid `sAMAccountName` characters

**File:** `Public/Start-AdmanUserOnboarding.ps1:126-130`
**Issue:** The validation regex `["\[\]:|<>+=;]` does not reject `@`, `\`, `/`, or `,`, all of which are invalid in an Active Directory `sAMAccountName`. A name pattern or input containing these characters passes preflight and only fails later inside the AD write.
**Fix:** Expand the regex to cover the full invalid character set:

```powershell
if ($sam -match '["\[\]:|<>+=;@\\/,]') {
    throw "Generated sAMAccountName '$sam' contains characters not allowed in AD sAMAccountName."
}
```

### WR-04: `Export-AdmanConfig` writes absolute paths, breaking cross-machine import

**File:** `Public/Config/Export-AdmanConfig.ps1:37-53`
**Issue:** `Initialize-AdmanConfig` converts `AuditDir`/`ReportDir` to absolute paths before publishing `$script:Config`. `Export-AdmanConfig` serializes that in-memory object, so the backup file contains machine-specific absolute paths. Importing that backup on another host preserves those paths (`ConvertTo-AdmanAbsolutePath` leaves rooted paths unchanged), so the audit/report directories no longer resolve under the new module root.
**Fix:** Export a clone with paths relativized against the module root before serialization:

```powershell
$exportCfg = $script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($key in @('AuditDir', 'ReportDir')) {
    $p = $exportCfg.$key
    if ($p -is [string] -and $p.StartsWith($moduleRoot)) {
        $exportCfg.$key = $p.Substring($moduleRoot.Length).TrimStart('\', '/')
    }
}
$json = ConvertTo-Json -InputObject $exportCfg -Depth 5
```

### WR-05: `tests/Workflow.OffboardingState.Tests.ps1` pollutes the global function table

**File:** `tests/Workflow.OffboardingState.Tests.ps1:38`
**Issue:** The test defines `function global:Resolve-AdmanTarget`, which shadows the module's real resolver for every subsequent test file in the same Pester process. Later tests that rely on the real resolver may pass for the wrong reason.
**Fix:** Use a module-scoped `Mock Resolve-AdmanTarget -ModuleName adman { ... }`, or remove the global stub in `AfterAll`:

```powershell
AfterAll {
    Remove-Item -Path Function:\Resolve-AdmanTarget -ErrorAction SilentlyContinue
}
```

### WR-06: `Export-AdmanConfig` does not mirror the PSFramework config

**File:** `Public/Config/Export-AdmanConfig.ps1:47-52`
**Issue:** The function writes a `.psf.json` mirror for the PSFramework backbone, but `Import-AdmanConfig` only imports its own plain-JSON mirror. The round-trip behavior between Export and Import is inconsistent, and a stale PSFramework mirror could be misread by tooling that expects it to stay in sync.
**Fix:** Either remove the PSFramework mirror write (since it is not consumed) or ensure `Import-AdmanConfig` deletes/ignores stale `.psf.json` siblings and rewrites the mirror on every save.

### WR-07: `Start-Adman.ps1` output-path prompt treats partial input as reserved commands

**File:** `Public/Start-Adman.ps1:228, 252`
**Issue:** The path prompt uses `$outPath -match '^[Bb]$'` and `$outPath -match '^[Qq]$'` without an end anchor. Inputs such as `"Backups\file.csv"` or `"Quote.csv"` match the `B`/`Q` class and are interpreted as Back/Quit instead of file paths.
**Fix:** Anchor the patterns:

```powershell
if ($outPath -match '^(?i)[Bb]$') { ... }
if ($outPath -match '^(?i)[Qq]$') { ... }
```

## Info

### IN-01: Source comments contain mojibake (corrupted em-dashes)

**Files:**
- `Public/Add-AdmanGroupMember.ps1:19`
- `Public/Reset-AdmanComputerAccount.ps1:13, 27, 31`
- `Public/Unlock-AdmanUser.ps1:33`
**Issue:** The byte sequence `â€”` appears where an em-dash was intended, indicating these files were saved with an inconsistent encoding. This hurts readability and may confuse reviewers.
**Fix:** Re-save the files as UTF-8 (with or without BOM) and replace `â€”` with `—`, or remove the em-dashes entirely.

### IN-02: Local password-source variables shadow their parameters

**Files:**
- `Public/New-AdmanLocalUser.ps1:106`
- `Public/Set-AdmanLocalUser.ps1:142`
**Issue:** `$passwordSource` differs from the parameter `$PasswordSource` only by case. PowerShell variables are case-insensitive, so the assignment overwrites the bound parameter value. The code works, but the naming is fragile for future refactors.
**Fix:** Rename the local variable to `$resolvedPasswordSource`.

### IN-03: Parameter help text omits the `'Ask'` password-source value

**Files:**
- `Public/New-AdmanUser.ps1:69-71`
- `Public/Set-AdmanUserPassword.ps1:65-67`
- `Public/Set-AdmanLocalUser.ps1:50-52`
**Issue:** The `.PARAMETER` help blocks describe only `Generate` and `Prompt`, while the `.DESCRIPTION` and code also handle `Ask`.
**Fix:** Update each `.PARAMETER` block to read "Generate, Prompt, or Ask (direct callers default to Generate)."

### IN-04: `docs/USAGE.md` password-source descriptions omit `'Ask'`

**File:** `docs/USAGE.md:31, 34, 43, 44`
**Issue:** The menu-reference table describes password-source choices as "Generate (recommended) or Prompt", missing the `Ask` sub-choice that the config schema and menu path support.
**Fix:** Add `Ask` to each password-source description, e.g., "Generate (recommended), Prompt, or Ask".

### IN-05: Several tests modify `$env:PSModulePath` without restoring it

**Files:**
- `tests/Audit.EventLog.Tests.ps1:32`
- `tests/Audit.FailClosed.Tests.ps1:49`
- `tests/Audit.Integrity.Tests.ps1:37`
- `tests/Audit.Rotation.Tests.ps1:32`
- `tests/Audit.Schema.Tests.ps1:48`
- `tests/Config.Load.Tests.ps1:35`
- `tests/Docs.Coverage.Tests.ps1:33`
- `tests/Help.Coverage.Tests.ps1:46`
- `tests/Workflow.OffboardingState.Tests.ps1:32`
**Issue:** `BeforeAll` prepends a stub module path to `$env:PSModulePath`, but `AfterAll` only removes the `adman` module. The modified path persists for later test files, which can cause ordering-dependent test behavior.
**Fix:** Save the original path and restore it in `AfterAll`:

```powershell
BeforeAll { $script:OriginalPSModulePath = $env:PSModulePath; ... }
AfterAll  { $env:PSModulePath = $script:OriginalPSModulePath; ... }
```

### IN-06: `docs/RECOVERY-RUNBOOK.md` signing example uses HTTP and signs transient directories

**File:** `docs/RECOVERY-RUNBOOK.md:78-89`
**Issue:** The runbook example uses `http://timestamp.digicert.com` (the build script uses HTTPS) and excludes only `tests`, `.github`, and `.githooks` from signing. It would also sign files under `.store/`, `.planning/`, or `.claude/` if PowerShell files exist there.
**Fix:** Switch to `https://timestamp.digicert.com` and broaden the exclusion:

```powershell
Where-Object FullName -notmatch '\\(tests|\.github|\.githooks|\.planning|\.store|\.claude)\\'
```

### IN-07: `Initialize-AdmanConfig.ps1` reassigns `$moduleRoot` redundantly

**File:** `Private/Config/Initialize-AdmanConfig.ps1:422`
**Issue:** `$moduleRoot` is already resolved at line 312 and is reassigned at line 422 immediately before path absolutization. This is harmless but unnecessary duplication.
**Fix:** Remove the duplicate assignment at line 422 or use the existing variable consistently.

### IN-08: `Get-AdmanRecoveryPostureReport.ps1` mixes UTC and unspecified-time freshness inputs

**File:** `Public/Get-AdmanRecoveryPostureReport.ps1:42-60`
**Issue:** `Generated` is emitted as `[datetime]::UtcNow`, while `Freshness` is built from config values with no explicit time-zone context. The mismatch is minor but could confuse consumers comparing timestamps.
**Fix:** Build the freshness string from the same UTC base or document that `Generated` is UTC in the help.

---

_Reviewed: 2026-07-23T15:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
