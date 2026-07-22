---
phase: 05-hardening-portability
reviewed: 2026-07-22T04:00:00Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - .github/workflows/ci.yml
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/New-AdmanUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Start-Adman.ps1
  - build/Sign-AdmanModule.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - docs/USAGE.md
  - docs/RECOVERY-RUNBOOK.md
  - tests/Audit.Hash.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Workflow.OffboardingState.Tests.ps1
  - adman.psd1
  - adman.psm1
findings:
  critical: 3
  warning: 8
  info: 1
  total: 12
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-22T04:00:00Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Phase 05 (hardening-portability) added the dual-edition CI matrix, Authenticode signing, fail-closed config loading, the audit hash-chain and rotation, and the offboarding restore workflow. The code generally implements the documented safety invariants (write-ahead audit, hash-chain integrity, PDCe pinning, preview=execute resolver reuse, fail-closed scope), but several defects remain: a supply-chain risk in the CI workflow, an unguarded date parser that can crash rotation, a missing type guard in config validation, and a handful of robustness/quality warnings in config path handling, certificate trust, password display, bulk resolution, and validation coverage.

## Critical Issues

### CR-01: Third-party CI action pinned to floating major version

**File:** `.github/workflows/ci.yml:24`
**Issue:** The workflow consumes `mchave3/setup-pwsh@v1`. A floating major tag can be retargeted to any commit by the action maintainer, so a supply-chain compromise or breaking change in the action would immediately affect adman's CI without a code change on this side. For a security-sensitive admin tool whose CI gates code-signing trust, the action should be pinned to a specific SHA-256 commit hash and verified before updates.
**Fix:** Pin to a commit hash and add a comment with the human-readable version:
```yaml
- name: Install PowerShell 7.6 LTS
  if: matrix.edition == 'core'
  uses: mchave3/setup-pwsh@<commit-sha>  # v1.2.3
  with:
    version: '7.6.4'
```

### CR-02: Unguarded `[datetime]::ParseExact` can crash audit rotation

**File:** `Private/Audit/Rotation.ps1:219-221`
**Issue:** The file-name regex `^audit-(\d{8})\.jsonl$` only guarantees eight digits, not a valid calendar date. A file named `audit-20231301.jsonl` (month 13) or `audit-20230230.jsonl` will pass the regex and then cause `[datetime]::ParseExact` to throw an unhandled `FormatException`, aborting the entire rotation run and leaving old logs in the live directory past the retention cutoff.
**Fix:** Wrap `ParseExact` in a try/catch and skip invalid date filenames:
```powershell
$dateString = $Matches[1]
try {
    $fileDate = [datetime]::ParseExact($dateString, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
} catch {
    Write-Warning "Skipping audit file '$($file.Name)': embedded date '$dateString' is not a valid calendar date."
    continue
}
```

### CR-03: Config validator lacks type guard for `security.passwordGeneration.length`

**File:** `Private/Config/Initialize-AdmanConfig.ps1:200-204`
**Issue:** `Test-AdmanConfigValid` checks that `passwordGeneration.length` is not null and then immediately casts it with `[int]$Config.security.passwordGeneration.length -lt 8`. If the value is a non-numeric string (e.g. `"twenty"` or `""` coerced from a typo), the cast throws a raw `InvalidCastException` or `FormatException` instead of the intended clean validation message. Config load is supposed to be fail-closed with clear diagnostics; an unhandled cast leaks a low-level runtime error.
**Fix:** Add the same numeric-or-string-digits guard used for `audit.retentionDays` at lines 184-186:
```powershell
$length = $Config.security.passwordGeneration.length
if ($length -isnot [int] -and $length -isnot [long] -and -not ($length -is [string] -and $length -match '^\d+$')) {
    throw "Config validation failed: 'security.passwordGeneration.length' must be an integer >= 8."
}
if ([int]$length -lt 8) {
    throw "Config validation failed: 'security.passwordGeneration.length' must be >= 8."
}
```

## Warnings

### WR-01: Relative config paths are not normalized consistently with absolute paths

**File:** `Private/Config/Initialize-AdmanConfig.ps1:372-386`
**Issue:** Relative `AuditDir`/`ReportDir` values are joined directly to the module root, but absolute paths are passed through `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath`. Relative paths containing `..` or PowerShell drives are therefore not normalized the same way as absolute paths, so two config files can end up pointing at different physical directories even when they describe the same intent. This also means relative paths are not validated to exist.
**Fix:** Normalize both branches through the same resolver:
```powershell
if ($config.AuditDir -is [string] -and -not [string]::IsNullOrWhiteSpace($config.AuditDir)) {
    $joined = if ([System.IO.Path]::IsPathRooted($config.AuditDir)) {
        $config.AuditDir
    } else {
        Join-Path $moduleRoot $config.AuditDir
    }
    $config.AuditDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($joined)
}
```

### WR-02: CI imports self-signed certificate into the machine Root store

**File:** `.github/workflows/ci.yml:52`
**Issue:** The AllSigned smoke test imports the ephemeral CI certificate into `Cert:\LocalMachine\Root`. This is a privileged trust-store mutation for a temporary, unaudited certificate. While the runner is disposable, the pattern is risky to copy into production runbooks and requires admin elevation that may not be available in all CI environments. The module's own `Sign-AdmanModule.ps1` does not need a Root-trusted cert for signing; only execution policy verification needs it in the TrustedPublisher store.
**Fix:** Remove the `Cert:\LocalMachine\Root` import and rely on `Cert:\LocalMachine\TrustedPublisher` for the AllSigned smoke, or document that the CI step is runner-scoped only and must never be used with a production signing certificate.

### WR-03: Generated passwords are captured by `Start-Transcript`

**File:** `Public/New-AdmanUser.ps1:220`, `Public/Set-AdmanUserPassword.ps1:245`, `Public/Set-AdmanLocalUser.ps1:223`
**Issue:** The display-once hygiene uses `[Console]::WriteLine` to show the generated password. The comment in each file correctly notes that `Start-Transcript` captures console output to disk, but the code does not detect or block that scenario. An operator running under `Start-Transcript` will persist the plaintext password to the transcript file, violating the project's "secrets encrypted; non-secret config portable" security model.
**Fix:** Detect an active transcript and refuse to display the password, or redirect to a secure one-time display path. A minimal fix:
```powershell
if ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count -gt 0) {
    throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
}
```
Alternatively, write the password to a temporary file with restrictive ACLs and display only the file path.

### WR-04: Bulk engine resolves each group twice

**File:** `Public/Invoke-AdmanBulkAction.ps1:185-191` and `218-222`
**Issue:** Distinct groups are resolved and validated before the cap/confirmation, then every allowed record resolves the same group again. This is inefficient and creates a TOCTOU window: a group's properties could change between the two resolutions, so the pre-confirmation policy decision may no longer match the object used during execution. The mutation gate re-resolves the target, but the bulk engine's own audit and skip-detection rely on the second resolution.
**Fix:** Cache the resolved group object from the pre-confirmation loop in a hashtable keyed by identity, then reuse the cached object when attaching `ResolvedGroup` to each record:
```powershell
$groupCache = @{}
foreach ($gid in $distinctGroupIds) {
    $groupCache[$gid] = Resolve-AdmanGroup -Identity $gid
    # ... validation ...
}
# later ...
$rec | Add-Member -MemberType NoteProperty -Name 'ResolvedGroup' -Value $groupCache[$gid] -Force
```

### WR-05: Rotation regex only validates digit count, not calendar date

**File:** `Private/Audit/Rotation.ps1:219`
**Issue:** The regex `^audit-(\d{8})\.jsonl$` accepts impossible dates such as `audit-00000000.jsonl` or `audit-20239999.jsonl`. Even after CR-02 is fixed, the regex itself remains overly permissive and could mask misnamed files or manual audit copies.
**Fix:** Tighten the regex to reject impossible month/day combinations, or combine the regex with the `ParseExact` validation so that only files whose embedded date parses successfully are considered for rotation (see CR-02 fix).

### WR-06: `ManagedOUs` element types are not validated

**File:** `Private/Config/Initialize-AdmanConfig.ps1:102-104`
**Issue:** The validator confirms that `ManagedOUs` is an array but never checks that each element is a non-empty string. A config with `"ManagedOUs": [123, {}]` passes validation and later causes cryptic DN-normalization errors when scope checks run.
**Fix:** Iterate the array and reject non-string or empty elements:
```powershell
if ($null -ne $Config.ManagedOUs) {
    foreach ($ou in $Config.ManagedOUs) {
        if (-not ($ou -is [string]) -or [string]::IsNullOrWhiteSpace($ou)) {
            throw "Config validation failed: every 'ManagedOUs' entry must be a non-empty DN string."
        }
    }
}
```

### WR-07: `Start-Adman` path prompt `B` returns to format selection, not the top-level menu

**File:** `Public/Start-Adman.ps1:228, 253`
**Issue:** After a report verb returns, the operator can choose output format `2` (CSV) or `3` (HTML). If the operator then types `B` at the path prompt, control returns to the format-selection loop (line 206), not the top-level menu. The comment-based help says `B` is reserved inside action prompts and resumes the top-level loop, but the path prompt is nested one level deeper and behaves differently. This is inconsistent and can trap an operator in a loop they expected to exit.
**Fix:** Treat `B` at the CSV/HTML path prompt as a request to return to the top-level menu, matching the behavior documented for action prompts:
```powershell
if ($outPath -match '^[Bb]$') { $formatResolved = $true; break menuLoop }
```

### WR-08: Onboarding sAMAccountName pre-flight validation is incomplete

**File:** `Public/Start-AdmanUserOnboarding.ps1:116-124`
**Issue:** The generated sAMAccountName is checked for emptiness, length <= 20, and wildcard characters, but not for leading/trailing whitespace or other characters invalid in AD sAMAccountName values (e.g. `"[]:|<>+=;?*"`). A `NamePattern` like `'{0} {1}'` could produce a value with spaces that `New-ADUser` will reject after confirmation.
**Fix:** Reject leading/trailing whitespace and known invalid characters before confirmation:
```powershell
if ($sam -match '^\s|\s$') {
    throw "Generated sAMAccountName '$sam' has leading or trailing whitespace."
}
if ($sam -match '["\\[\\]:|<>+=;]') {
    throw "Generated sAMAccountName '$sam' contains characters not allowed in AD sAMAccountName."
}
```

## Info

### IN-01: Password sourcing logic is duplicated across three public verbs

**File:** `Public/New-AdmanUser.ps1:131-184`, `Public/Set-AdmanUserPassword.ps1:124-174`, `Public/Set-AdmanLocalUser.ps1:150-200`
**Issue:** The per-call password source resolution, Generate/Prompt switch, BSTR comparison, complexity check, and display-once hygiene are copy-pasted with only parameter-name differences. This makes future changes (e.g. adding a new source, changing complexity rules) error-prone and increases the chance that one verb diverges from the others.
**Fix:** Extract a private helper such as `Resolve-AdmanPasswordInput` that returns a `[pscustomobject]@{ Password = $secureString; Source = 'Generate'|'Prompt' }`, then call it from each verb. Keep the display-once code in one place as well.

---

_Reviewed: 2026-07-22T04:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
