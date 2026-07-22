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
  critical: 2
  warning: 7
  info: 3
  total: 12
status: issues_found
---

# Phase 05-hardening-portability: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 52
**Status:** issues_found

## Summary

Reviewed the complete Phase 5 hardening/portability surface: audit hash-chain + rotation, fail-closed config loading/validation, offboarding restore workflow, the full public cmdlet surface, Authenticode signing, JSON schema/defaults, operator docs, and unit tests. The implementation preserves the project's core safety invariants (write-ahead audit, PDCe pinning, managed-OU scope, no secrets in audit), but two critical defects remain: a config-cleaning helper that corrupts arrays and can fail-open the scope gate, and a TUI path-prompt bug that makes the "Back" input quit the menu entirely. Several warnings around null-safe enumeration, transient AD resolution failures, and parameter splatting were also identified.

## Critical Issues

### CR-01: ConvertTo-AdmanCleanConfig corrupts arrays and can fail-open the scope gate

**File:** `Private/Config/Initialize-AdmanConfig.ps1:41-46`
**Issue:** The array branch returns `,$arr` (unary comma). When the caller captures the return value in a variable, PowerShell does not unwrap it; the result is a one-element array whose single element is the intended array. Config arrays such as `ManagedOUs`, `DenyList`, and `BaselineGroups` therefore become `@(@(...))` after cleaning.

For an empty `ManagedOUs` array, the downstream scope-count check `@($config.ManagedOUs | Where-Object { ... }).Count` sees one element (the inner empty array), `Where-Object` filters it to `$null`, and `@($null).Count` evaluates to `1`, causing the fail-closed scope gate to pass when it should throw. For non-empty arrays, `Test-AdmanConfigValid` iterates the wrapped outer array once and throws because the inner array lacks expected object properties, breaking existing config loads.
**Fix:** Return the array directly; use `Write-Output -NoEnumerate` only if pipeline semantics are required. Remove the unary comma.
```powershell
if ($Node -is [array]) {
    $arr = @()
    foreach ($item in $Node) { $arr += (ConvertTo-AdmanCleanConfig -Node $item) }
    return $arr
}
```

### CR-02: Start-Adman treats "B" at CSV/HTML path prompt as "Quit"

**File:** `Public/Start-Adman.ps1:228, 253`
**Issue:** Inside the CSV and HTML output-path prompts, if the operator types `B` (back), the code executes `break menuLoop`, which exits the entire `:menuLoop` and therefore terminates `Start-Adman`. The top-level format prompt handles `B` correctly (returns to the menu), so the path prompt behavior is inconsistent and surprising.
**Fix:** Make `B` return to the format-choice loop instead of breaking the outer menu.
```powershell
if ($outPath -match '^[Bb]$') { continue formatLoop }   # or equivalent
```

## Warnings

### WR-01: Null-result enumeration can pass `$null` into `ConvertTo-AdmanResult`

**Files:**
- `Public/Find-AdmanUser.ps1:116`
- `Public/Find-AdmanComputer.ps1:85`
- `Public/Get-AdmanAccountStateReport.ps1:92`
- `Public/Get-AdmanInventoryReport.ps1:70`
- `Public/Get-AdmanStaleReport.ps1:75`
**Issue:** Each function wraps AD cmdlet output in `@($raw)` and enumerates it. When an AD cmdlet returns no objects, `$raw` is `$null`, `@($null)` has `Count == 1`, and the loop iterates once with `$obj = $null`, passing `$null` to `ConvertTo-AdmanResult`. The downstream behavior with a null input depends on unreviewed code, but the pattern is a known PowerShell pitfall and has produced null-reference errors in similar codebases.
**Fix:** Filter nulls out of the enumeration, or guard the loop with `if ($raw) { foreach ($obj in $raw) { ... } }`.
```powershell
foreach ($obj in ($raw | Where-Object { $null -ne $_ })) { ... }
```

### WR-02: Protected-group removal may proceed if group resolution fails

**File:** `Public/Start-AdmanUserOffboarding.ps1:99-150`
**Issue:** The classification loop marks a group as protected only when it can be resolved and matched against `ProtectedSIDs`/`DenyRids`/`ProtectedGroupDns`, or when the raw identity string is itself a protected SID/DN. If a protected group is referenced by name (e.g., `Domain Admins`) and `Resolve-AdmanGroup` fails due to a transient ADWS error, the catch block does not retry by name and the group is added to `$groupsToRemove`. This creates a low-probability but real path where a protected group is stripped during offboarding.
**Fix:** In the catch fallback, also check whether `$g` matches any entry in `ProtectedGroupDns` by resolved displayName/RDN, or refuse to remove any group that could not be classified rather than defaulting to removal.

### WR-03: Generated password is displayed (or throws) after the AD/local account already exists

**Files:**
- `Public/New-AdmanUser.ps1:216-235`
- `Public/Set-AdmanUserPassword.ps1:241-257`
- `Public/Set-AdmanLocalUser.ps1:219-234`
**Issue:** The transcript check and password display run **after** `Invoke-AdmanMutation` has already mutated the account. If a transcript is active, the verb throws at this point, leaving the account with an unknown generated password. This is a UX/operational hazard: a freshly created account can be stranded with a password the operator never sees.
**Fix:** Move the transcript probe and password-source decision earlier, or ensure that when a transcript blocks display the generated password is securely re-offered rather than leaving the operator locked out.

### WR-04: `Invoke-AdmanBulkAction` passes `-Force` to `Confirm-AdmanAction` without checking its parameter set

**File:** `Public/Invoke-AdmanBulkAction.ps1:241-252`
**Issue:** The `$confirmArgs` hashtable unconditionally includes `Force = $Force` before splatting to `Confirm-AdmanAction`. If `Confirm-AdmanAction` does not declare a `-Force` switch, this splat will throw a parameter-binding error at confirmation time.
**Fix:** Confirm that `Confirm-AdmanAction` accepts `-Force`; if not, remove the key from `$confirmArgs`.

### WR-05: `Invoke-AdmanAuditRotation` default parameter values depend on unloaded config

**File:** `Private/Audit/Rotation.ps1:207-210`
**Issue:** The default values for `-AuditDir` and `-RetentionDays` reference `$script:Config`. If the function is called before `Initialize-AdmanConfig` has run, these evaluate to `$null`, causing `Test-Path -LiteralPath $AuditDir` to evaluate against the current directory and rotation to behave unexpectedly.
**Fix:** Make the parameters mandatory when called directly, or validate that `$script:Config` is loaded and throw a clear "not initialized" error.

### WR-06: Audit schema test source-hygiene regex differs from its documented banned-token list

**File:** `tests/Audit.Schema.Tests.ps1:63, 255`
**Issue:** The test comment and the `$script:SecretNameRegex` variable include `key` and `token` as banned tokens, but the actual source-code scan at line 255 only checks for `password|secret|credential|apiKey|privateKey`. The test therefore does not enforce the documented invariant for `key`/`token` and could miss source comments or parameter names that contain those tokens.
**Fix:** Align the source scan regex with `$script:SecretNameRegex`, or update the test comment to reflect the actual banned-token list.

### WR-07: `Restore-AdmanQuarantinedUser` uses original `-Identity` for offboarding-state lookup

**File:** `Public/Restore-AdmanQuarantinedUser.ps1:99`
**Issue:** The function computes a stable `sAMAccountName`-based identity on line 85 for the composed verbs, but calls `Get-AdmanOffboardingState -Identity $Identity` using the original caller input. If the caller supplied the user's original DN and the account has since been moved to the quarantine OU, `Get-AdmanOffboardingState` may fail to resolve the stale DN and the restore cannot proceed.
**Fix:** Use the stable identity for the state lookup:
```powershell
$state = Get-AdmanOffboardingState -Identity $stableIdentity
```

## Info

### IN-01: `Move-AdmanUser` and `Move-AdmanComputer` duplicate destination-scope validation

**Files:**
- `Public/Move-AdmanUser.ps1:72-81`
- `Public/Move-AdmanComputer.ps1:72-81`
**Issue:** The component-boundary scope check for `-TargetPath` is implemented identically in both public verbs and again inside the mutation gate. This duplication increases maintenance cost if the normalization or anchoring rules ever change.
**Fix:** Centralize the destination-scope check in a shared helper (e.g., `Test-AdmanTargetPathInScope`) and call it from both the public verbs and the gate.

### IN-02: CI runs `Help.Coverage.Tests.ps1` twice

**File:** `.github/workflows/ci.yml:112-113`
**Issue:** The workflow explicitly invokes `tests/Help.Coverage.Tests.ps1` and then runs the full Pester configuration, which also includes that file. The redundant run adds CI time without adding coverage.
**Fix:** Remove the explicit `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1` line; the configuration-driven run is sufficient.

### IN-03: Multiple public verbs use `@()` and `+=` to build collections

**Files:**
- `Public/Export-AdmanReportCsv.ps1:81-92`
- `Public/Invoke-AdmanBulkAction.ps1:93-107, 198-200`
- `Public/Write-AdmanAudit.ps1:90-136`
**Issue:** Using `@(); $list += $item` causes array reallocation on every addition. For small collections this is harmless, but for bulk/report workloads it is a maintainability/performance smell. Performance is out of scope for v1, but switching to `System.Collections.Generic.List[object]` would make the intent clearer and avoid accidental unrolling.
**Fix:** Replace `@()` builders with `New-Object System.Collections.Generic.List[object]` and `.Add()`.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
