---
phase: 05-hardening-portability
reviewed: 2026-07-22T00:00:00Z
depth: standard
files_reviewed: 52
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
  critical: 5
  warning: 9
  info: 2
  total: 16
status: issues_found
---

# Phase 05-hardening-portability: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 52
**Status:** issues_found

## Summary

Reviewed the Phase 5 hardening/portability surface at standard depth: audit hash-chain + rotation, fail-closed config load/validation/edit/restore, the offboarding restore workflow, the full public cmdlet surface, Authenticode signing, JSON schema/defaults, operator docs, and unit tests. The implementation keeps the project's core safety invariants intact (write-ahead audit, PDCe pinning, managed-OU scope, no secrets in audit), but five blocker-level defects remain, plus nine warnings and two info items. The blockers cover a fail-open scope gate, an audit-directory path divergence, a password-disclosure bug, a restore-workflow identity bug, and a TUI "Back" input that quits the menu.

## Critical Issues

### BL-01: ConvertTo-AdmanCleanConfig corrupts arrays and can fail-open the scope gate

**File:** `Private/Config/Initialize-AdmanConfig.ps1:41-46`
**Classification:** BLOCKER
**Issue:** The array branch returns `,$arr` (unary comma). The caller therefore receives a one-element array whose single element is the intended cleaned array. Config arrays such as `ManagedOUs`, `DenyList`, and `BaselineGroups` become `@(@(...))` after cleaning.

For an empty `ManagedOUs` array, the downstream scope-count check `@($config.ManagedOUs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count` sees one element (the inner empty array), `Where-Object` keeps it because an array object is not whitespace, and `@($innerArray).Count` evaluates to 1, causing the fail-closed scope gate to pass when it should throw. For non-empty arrays, `Test-AdmanConfigValid` iterates the wrapped outer array once and throws because the inner array lacks expected object properties, breaking existing config loads.
**Fix:** Return the array directly; remove both unary commas.
```powershell
if ($Node -is [array]) {
    $arr = @()
    foreach ($item in $Node) { $arr += (ConvertTo-AdmanCleanConfig -Node $item) }
    return $arr
}
```

### BL-02: Set-AdmanConfig and Import-AdmanConfig do not absolutize AuditDir/ReportDir

**Files:**
- `Public/Config/Set-AdmanConfig.ps1:75-84`
- `Public/Config/Import-AdmanConfig.ps1:57-65`
**Classification:** BLOCKER
**Issue:** `Initialize-AdmanConfig` absolutizes relative `AuditDir`/`ReportDir` values against the module root (`Private/Config/Initialize-AdmanConfig.ps1:374-399`) so audit/report writes always land in the intended location regardless of the process current directory. `Set-AdmanConfig` and `Import-AdmanConfig` publish the validated config to `$script:Config` without re-running that absolutization. If an operator imports a portable backup with relative paths, or uses `Set-AdmanConfig -Key AuditDir -Value '.store/audit'`, subsequent audit records are written to `$PWD\.store\audit` instead of the module-root `.store\audit`. This breaks audit integrity, can bypass the fail-closed audit-writable check, and risks audit data loss.
**Fix:** Extract the absolutization logic from `Initialize-AdmanConfig` into a helper (e.g., `ConvertTo-AdmanAbsolutePath`) and call it from `Set-AdmanConfig` and `Import-AdmanConfig` before publishing `$script:Config`.
```powershell
function ConvertTo-AdmanAbsolutePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $joined = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $moduleRoot $Path }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($joined)
}
```

### BL-03: Explicit password combined with `-AccountPasswordSource 'Generate'` is displayed as generated

**Files:**
- `Public/New-AdmanUser.ps1:133-142, 216-235`
- `Public/Set-AdmanUserPassword.ps1:125-133, 241-257`
- `Public/Set-AdmanLocalUser.ps1:151-159, 219-234`
**Classification:** BLOCKER
**Issue:** The per-call password-source resolution gives the explicit source marker priority over the explicit password. A caller who supplies both `-AccountPassword $sec` and `-AccountPasswordSource 'Generate'` (or the analogous `-NewPassword`/`-Password` pairs) skips password generation because a password is already present, but the display-once hygiene later sees source == 'Generate' and prints the caller-supplied secret to the console as "Generated password".
**Fix:** When an explicit password is supplied, force the effective source to 'Prompt' regardless of any source override.
```powershell
$passwordSource = if ($PSBoundParameters.ContainsKey('AccountPassword') -and $null -ne $AccountPassword) {
    'Prompt'
} elseif ($PSBoundParameters.ContainsKey('AccountPasswordSource') -and $AccountPasswordSource) {
    $AccountPasswordSource
} else {
    ...
}
```

### BL-04: Restore-AdmanQuarantinedUser uses the raw caller identity for offboarding-state lookup

**File:** `Public/Restore-AdmanQuarantinedUser.ps1:99`
**Classification:** BLOCKER
**Issue:** The function computes a stable `sAMAccountName`-based identity at line 85 for the composed verbs (`Add-AdmanGroupMember`, `Move-AdmanUser`, `Enable-AdmanUser`), but calls `Get-AdmanOffboardingState -Identity $Identity` using the original caller input. If the caller supplied the user's original DN and the account has since been moved to the quarantine OU, `Get-AdmanOffboardingState` may fail to resolve the stale DN and the restore cannot proceed, even though the same DN resolved successfully earlier in the function.
**Fix:** Use the stable identity for the state lookup.
```powershell
$state = Get-AdmanOffboardingState -Identity $stableIdentity
```

### BL-05: Start-Adman treats "B" at CSV/HTML path prompt as "Quit"

**File:** `Public/Start-Adman.ps1:228, 253`
**Classification:** BLOCKER
**Issue:** Inside the CSV and HTML output-path prompts, if the operator types `B` (back), the code executes `break menuLoop`, which exits the entire `:menuLoop` and therefore terminates `Start-Adman`. The top-level format prompt handles `B` correctly (returns to the menu), so the path prompt behavior is inconsistent and surprising.
**Fix:** Make `B` return to the format-choice loop instead of breaking the outer menu. Label the inner `while` loop and `continue` it, or set `$formatResolved = $true` and `continue` the outer `menuLoop`.
```powershell
if ($outPath -match '^[Bb]$') { $formatResolved = $true; continue }
```

## Warnings

### WR-01: Null-result enumeration can pass `$null` into `ConvertTo-AdmanResult`

**Files:**
- `Public/Find-AdmanUser.ps1:116`
- `Public/Find-AdmanComputer.ps1:85`
- `Public/Get-AdmanAccountStateReport.ps1:92`
- `Public/Get-AdmanInventoryReport.ps1:70`
- `Public/Get-AdmanStaleReport.ps1:75`
**Classification:** WARNING
**Issue:** Each function wraps AD cmdlet output in `@($raw)` and enumerates it. When an AD cmdlet returns no objects, `$raw` is `$null`, `@($null)` has `Count == 1`, and the loop iterates once with `$obj = $null`, passing `$null` to `ConvertTo-AdmanResult`. The downstream behavior with a null input depends on the converter implementation; the pattern is a known PowerShell pitfall and has produced null-reference errors in similar codebases.
**Fix:** Filter nulls out of the enumeration, or guard the loop with `if ($raw) { foreach ($obj in $raw) { ... } }`.
```powershell
foreach ($obj in ($raw | Where-Object { $null -ne $_ })) { ... }
```

### WR-02: Generated password is displayed (or throws) after the AD/local account already exists

**Files:**
- `Public/New-AdmanUser.ps1:216-235`
- `Public/Set-AdmanUserPassword.ps1:241-257`
- `Public/Set-AdmanLocalUser.ps1:219-234`
**Classification:** WARNING
**Issue:** The transcript check and password display run **after** `Invoke-AdmanMutation` has already mutated the account. If a transcript is active, the verb throws at this point, leaving the account with an unknown generated password. This is an operational hazard: a freshly created account can be stranded with a password the operator never sees.
**Fix:** Move the transcript probe and password-source decision earlier, or ensure that when a transcript blocks display the generated password is securely re-offered rather than leaving the operator locked out.

### WR-03: Get-AdmanRecoveryPostureReport dereferences a potentially null posture object

**File:** `Public/Get-AdmanRecoveryPostureReport.ps1:56-58`
**Classification:** WARNING
**Issue:** The function falls back to `Get-AdmanRecoveryPosture` when `$script:Config.RecoveryPosture` is absent. If `Get-AdmanRecoveryPosture` returns `$null` (e.g., the Active Directory web service is unreachable, or the function is run without RSAT), the subsequent property accesses `$posture.RecycleBinEnabled`, `$posture.ForestFunctionalLevel`, and `$posture.TombstoneLifetime` throw a terminating null-reference error.
**Fix:** Guard the property accesses and emit a graceful, annotated result when posture cannot be determined.
```powershell
[pscustomobject]@{
    RecycleBinEnabled     = if ($posture) { $posture.RecycleBinEnabled } else { $null }
    ForestFunctionalLevel = if ($posture) { $posture.ForestFunctionalLevel } else { $null }
    TombstoneLifetime     = if ($posture) { $posture.TombstoneLifetime } else { $null }
    Generated             = [datetime]::UtcNow
    Freshness             = $freshness
}
```

### WR-04: Inventory remote-cap budget truncates fractional seconds to zero

**File:** `Public/Get-AdmanInventoryReport.ps1:88, 101`
**Classification:** WARNING
**Issue:** The remaining-time calculations cast to `[int]`, which truncates toward zero. With a `totalInventoryRemoteCap` of 1 second and `Elapsed.TotalSeconds` of 0.9, the computed `$totalRemaining` is 0, so the host is skipped even though nearly a full second remains. The same truncation applies to `$queryRemaining`.
**Fix:** Compare the fractional value directly, or use `[math]::Floor` only where intentional.
```powershell
$totalRemaining = $totalCap - $totalStopwatch.Elapsed.TotalSeconds
if ($totalRemaining -le 0) { ... }
```

### WR-05: Find-AdmanUser silently ignores multiple search criteria

**File:** `Public/Find-AdmanUser.ps1:92-103`
**Classification:** WARNING
**Issue:** If the caller supplies more than one of `-SamAccountName`, `-DisplayName`, and `-Name`, only `-SamAccountName` is used. The other parameters are silently ignored, which can return unexpected results without any warning.
**Fix:** Either combine the criteria into a compound `-Filter` (AND semantics), or throw when more than one is supplied so the caller must disambiguate.

### WR-06: Export-AdmanReportHtml uses a fragile regex to remove the empty prototype row

**File:** `Public/Export-AdmanReportHtml.ps1:185`
**Classification:** WARNING
**Issue:** The regex `(?s)<tr>(\s*<td></td>)+\s*</tr>` assumes `ConvertTo-Html` emits exactly `<td></td>` with no attributes or whitespace variations. Future PowerShell versions, `-CssUri` output, or property names containing HTML-special characters could change the emitted markup, causing the prototype row to remain in the output or, worse, matching and removing legitimate data rows.
**Fix:** Build the header-only HTML explicitly with `ConvertTo-Html -Fragment` for the header, or construct the `<table>` markup directly instead of post-processing generated HTML.

### WR-07: build/Sign-AdmanModule.ps1 can hang on password-protected PFX in non-interactive CI

**File:** `build/Sign-AdmanModule.ps1:63`
**Classification:** WARNING
**Issue:** `Get-PfxCertificate -FilePath $resolvedPath` prompts interactively for a PFX password when one is required. In a non-interactive CI pipeline this call will block indefinitely.
**Fix:** Accept a `CertificatePassword` parameter and use `Get-PfxData` or `X509Certificate2` constructor with the password, then pass the loaded certificate to `Set-AuthenticodeSignature`.

### WR-08: Invoke-AdmanAuditRotation uses hard-coded backslashes in the archive path

**File:** `Private/Audit/Rotation.ps1:233`
**Classification:** WARNING
**Issue:** The archive path is built with `Join-Path $AuditDir ('archive\{0}' -f $archiveMonth)`. While the project targets Windows, hard-coded path separators make cross-platform behavior fragile and are inconsistent with the rest of the codebase, which uses `Join-Path`.
**Fix:** Use nested `Join-Path` calls or `[System.IO.Path]::Combine`.
```powershell
$archiveDir = Join-Path (Join-Path $AuditDir 'archive') $archiveMonth
```

### WR-09: Audit schema test source-hygiene regex differs from its documented banned-token list

**File:** `tests/Audit.Schema.Tests.ps1:63, 255`
**Classification:** WARNING
**Issue:** The test comment and the `$script:SecretNameRegex` variable include `key` and `token` as banned tokens, but the actual source-code scan at line 255 only checks for `password|secret|credential|apiKey|privateKey`. The test therefore does not enforce the documented invariant for `key`/`token` and could miss source comments or parameter names that contain those tokens.
**Fix:** Align the source scan regex with `$script:SecretNameRegex`, or update the test comment to reflect the actual banned-token list.

## Info

### IN-01: CI runs `Help.Coverage.Tests.ps1` twice

**File:** `.github/workflows/ci.yml:112-113`
**Classification:** INFO
**Issue:** The workflow explicitly invokes `tests/Help.Coverage.Tests.ps1` and then runs the full Pester configuration, which also includes that file. The redundant run adds CI time without adding coverage.
**Fix:** Remove the explicit `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1` line; the configuration-driven run is sufficient.

### IN-02: Multiple verbs use `@()` and `+=` to build collections

**Files:**
- `Public/Export-AdmanReportCsv.ps1:81-92`
- `Public/Invoke-AdmanBulkAction.ps1:93-107, 198-200`
- `Private/Audit/Write-AdmanAudit.ps1:90-136`
**Classification:** INFO
**Issue:** Using `@(); $list += $item` causes array reallocation on every addition. For small collections this is harmless, but for bulk/report workloads it is a maintainability/performance smell.
**Fix:** Replace `@()` builders with `New-Object System.Collections.Generic.List[object]` and `.Add()`.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
