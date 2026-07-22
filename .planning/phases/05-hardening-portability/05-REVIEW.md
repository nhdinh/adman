---
phase: 05-hardening-portability
reviewed: 2026-07-22T21:00:00Z
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
  - Public/New-AdmanLocalUser.ps1
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
  warning: 6
  info: 3
  total: 10
status: issues_found
---

# Phase 05-hardening-portability: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 53
**Status:** issues_found

## Summary

Re-reviewed the full Phase 5 hardening/portability surface at standard depth, including the new uncommitted work in `Public/New-AdmanLocalUser.ps1`. The earlier blocker fixes (BL-01 through BL-05) remain resolved, and the follow-up fixes for WR-06 through WR-09 are intact. However, ten new or remaining issues were found: one critical password-disclosure regression, six warnings spanning dry-run side effects, timezone comparison, Windows PowerShell 5.1 portability, and a fail-open protected-identity check, plus three info items.

## Critical Issues

### CR-01: New-AdmanLocalUser reintroduces the BL-03 password-disclosure bug

**File:** `Public/New-AdmanLocalUser.ps1:106-113`
**Classification:** CRITICAL
**Issue:** The per-call password-source resolution gives the explicit `PasswordSource` marker priority over an explicitly supplied `Password`. When a caller supplies both `-Password $sec` and `-PasswordSource 'Generate'`, the verb skips generation because a password is present, but the display-once hygiene later sees `passwordSource -eq 'Generate'` and prints the caller-supplied secret to the console as "Generated password". This is the exact bug fixed in `New-AdmanUser`, `Set-AdmanUserPassword`, and `Set-AdmanLocalUser` (BL-03).

**Fix:** Force the effective source to `Prompt` whenever an explicit password is supplied, matching the fixed pattern in the sibling verbs.
```powershell
$passwordSource = if ($PSBoundParameters.ContainsKey('Password') -and $null -ne $Password) {
    'Prompt'
} elseif ($PSBoundParameters.ContainsKey('PasswordSource') -and $PasswordSource) {
    $PasswordSource
} else {
    $src = $script:Config.security.passwordSource
    if ([string]::IsNullOrWhiteSpace([string]$src)) { 'Generate' } else { [string]$src }
}
```

## Warnings

### WR-01: Set-AdmanConfig and Import-AdmanConfig bypass the CONF-02 fail-closed scope gate when ManagedOUs is $null

**Files:**
- `Public/Config/Set-AdmanConfig.ps1:71-73`
- `Public/Config/Import-AdmanConfig.ps1:52-54`
**Classification:** WARNING
**Issue:** Both scope-count checks use `@($proposed.ManagedOUs).Count` / `@($config.ManagedOUs).Count`. When `ManagedOUs` is `$null`, `@($null).Count` evaluates to `1`, so the gate passes instead of throwing the intended `FAIL-CLOSED: managed-OU scope` message. `Initialize-AdmanConfig` is safe because it filters through `Where-Object` before wrapping (a null pipeline produces Count 0), but the edit/restore verbs can publish a config with no managed scope.

**Fix:** Filter null/whitespace entries before counting, or guard the null case explicitly.
```powershell
$scopeCount = if ($null -eq $proposed.ManagedOUs) { 0 } else { @($proposed.ManagedOUs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count }
if ($scopeCount -lt 1) {
    throw "FAIL-CLOSED: managed-OU scope (ManagedOUs) is empty; refusing to import a config with no managed-OU root."
}
```

### WR-02: New-AdmanLocalUser lacks a pre-mutation transcript guard for generated passwords

**File:** `Public/New-AdmanLocalUser.ps1:166-187`
**Classification:** WARNING
**Issue:** `New-AdmanUser`, `Set-AdmanUserPassword`, and `Set-AdmanLocalUser` were fixed to throw **before** mutating the account when a generated password would have to be displayed while `Start-Transcript` is active. `New-AdmanLocalUser` only checks for an active transcript inside the post-mutation display block. If a transcript is running, the local account is created with a generated password and then the verb throws, leaving the operator with an account whose password is unknown.

**Fix:** Add the same pre-mutation transcript guard before `Invoke-AdmanLocalMutation`.
```powershell
if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $Password) {
    if ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count -gt 0) {
        throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
    }
}
```

### WR-03: Invoke-AdmanAuditRotation mutates the filesystem under -WhatIf

**File:** `Private/Audit/Rotation.ps1:234-241`
**Classification:** WARNING
**Issue:** The function declares `[CmdletBinding(SupportsShouldProcess)]`, but the archive directory and marker file are created **outside** the `$PSCmdlet.ShouldProcess(...)` block. Only the final `Move-Item` is guarded. Running `Invoke-AdmanAuditRotation -WhatIf` therefore still creates `archive/YYYYMM/` directories and writes `.marker` files, violating the project's core dry-run safety invariant.

**Fix:** Move directory creation and marker writing inside the `ShouldProcess` scope, or use a separate `ShouldProcess` call for the archive preparation.
```powershell
if ($PSCmdlet.ShouldProcess($archiveDir, 'Create archive directory and marker')) {
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        $null = New-Item -ItemType Directory -Path $archiveDir -Force -ErrorAction Stop
    }
    $marker = Join-Path $archiveDir ('archive-{0}.marker' -f $archiveMonth)
    if (-not (Test-Path -LiteralPath $marker)) {
        ('{0:yyyy-MM-ddTHH:mm:ssZ}' -f (Get-Date).ToUniversalTime()) | Set-Content -LiteralPath $marker -Encoding UTF8 -ErrorAction Stop
    }
}
if ($PSCmdlet.ShouldProcess($file.FullName, 'Move to archive')) {
    Move-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
}
```

### WR-04: Get-AdmanStaleReport compares a UTC lastLogonTimestamp against a local-time cutoff

**File:** `Public/Get-AdmanStaleReport.ps1:63, 93-94`
**Classification:** WARNING
**Issue:** `$staleCutoff` is built with `(Get-Date).AddDays(-$graceDays)`, which is in the machine's local time. `lastLogonTimestamp` is converted via `[datetime]::FromFileTimeUtc(...)`, which is UTC. Although .NET compares absolute instants, the interpretation of the cutoff shifts with the host timezone: an account logged on at "midnight UTC today" is classified differently on a UTC-5 host than on a UTC+5 host for the same `graceDays`. The report should compare UTC against UTC.

**Fix:** Compute the cutoff in UTC.
```powershell
$staleCutoff = (Get-Date).ToUniversalTime().AddDays(-$graceDays)
```

### WR-05: build/Sign-AdmanModule.ps1 uses a 3-argument Join-Path incompatible with Windows PowerShell 5.1

**File:** `build/Sign-AdmanModule.ps1:43`
**Classification:** WARNING
**Issue:** The default parameter value `[string]$ModulePath = (Join-Path $PSScriptRoot '..' 'adman.psd1')` passes three positional arguments to `Join-Path`. Windows PowerShell 5.1's `Join-Path` accepts only two positional path arguments, so binding this parameter throws `A positional parameter cannot be found that accepts argument 'adman.psd1'`. The CI desktop leg invokes this script under Windows PowerShell 5.1, so signing fails on the required baseline runtime.

**Fix:** Nest `Join-Path` calls for 5.1 compatibility.
```powershell
[string]$ModulePath = (Join-Path (Join-Path $PSScriptRoot '..') 'adman.psd1')
```

### WR-06: Start-AdmanUserOffboarding relies on uninitialized protected-identity caches

**File:** `Public/Start-AdmanUserOffboarding.ps1:114, 118, 123`
**Classification:** WARNING
**Issue:** The function checks `$script:Config.ManagedOUs` but never verifies that `$script:ProtectedSIDs`, `$script:DenyRids`, and `$script:ProtectedGroupDns` are populated. Those caches are loaded only by `Initialize-Adman` step 8 (`Get-AdmanProtectedIdentity`). A caller who runs `Initialize-AdmanConfig` directly and then calls `Start-AdmanUserOffboarding` will have empty caches, causing every group membership to be treated as removable, including protected groups such as Domain Admins.

**Fix:** Fail closed when the protected-identity caches have not been initialized.
```powershell
if (-not $script:ProtectedSIDs -or -not $script:DenyRids -or -not $script:ProtectedGroupDns) {
    throw 'Protected identity caches are not initialized. Run Initialize-Adman first.'
}
```

## Info

### IN-01: CI workflow still runs Help.Coverage.Tests.ps1 twice

**File:** `.github/workflows/ci.yml:112-113`
**Classification:** INFO
**Issue:** The lint-and-test step explicitly invokes `tests/Help.Coverage.Tests.ps1` and then runs the full Pester configuration, which also includes that file. The redundant run adds CI time without adding coverage.

**Fix:** Remove the explicit `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1 -Tag Unit` line; the configuration-driven run is sufficient.

### IN-02: @() += array builders remain in Export-AdmanReportCsv and Write-AdmanAudit

**Files:**
- `Public/Export-AdmanReportCsv.ps1:81-88`
- `Private/Audit/Write-AdmanAudit.ps1:94-95, 114-130`
**Classification:** INFO
**Issue:** Using `@(); $list += $item` causes array reallocation on every addition. For small collections this is harmless, but for bulk/report workloads and the audit writer it is a maintainability/performance smell.

**Fix:** Replace `@()` builders with `New-Object System.Collections.Generic.List[object]` and `.Add()`.

### IN-03: docs/USAGE.md local-user examples show remote ComputerName rejected by Phase 2 code

**File:** `docs/USAGE.md:339, 349, 361, 371, 381`
**Classification:** INFO
**Issue:** The examples for `New-AdmanLocalUser`, `Set-AdmanLocalUser`, `Remove-AdmanLocalUser`, `Add-AdmanLocalGroupMember`, and `Remove-AdmanLocalGroupMember` pass `-ComputerName 'WKSTN-42'`. In Phase 2, those verbs explicitly throw for any non-localhost ComputerName. The examples are forward-looking but currently misleading to operators.

**Fix:** Update the examples to use `'.'`, `'localhost'`, or `$env:COMPUTERNAME` until Phase 3 remote transport lands, or add a note that remote targets are not yet supported.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
