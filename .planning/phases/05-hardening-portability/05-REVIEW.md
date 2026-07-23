---
phase: 05-hardening-portability
reviewed: 2026-07-23T00:00:00Z
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
  warning: 4
  info: 4
  total: 9
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T00:00:00Z
**Depth:** standard
**Files Reviewed:** 56
**Status:** issues_found

## Summary

Reviewed the full Phase 5 hardening/portability scope (56 files): all Public verbs, Config verbs, Audit privates, Offboarding workflow, CI, tests, docs, schema/defaults, and the signing script. Found one critical safety defect where the public config accessor returns the live in-memory config object by reference, allowing callers to bypass fail-closed validation. Also found warnings around dead transcript guards, global suppression of `PSAvoidUsingWriteHost`, empty catch blocks in config mirror operations, and implicit `-WhatIf` inheritance. Info items cover CI redundancy, disabled coverage target, outdated manifest text, and mojibake in comment blocks.

## Critical Issues

### CR-01: Get-AdmanConfig returns the live config object by reference

**File:** `Public/Config/Get-AdmanConfig.ps1:35`
**Issue:** When called without `-Key`, the function returns `$script:Config` directly. Because `ConvertFrom-Json` produces a mutable `PSCustomObject`, callers receive a reference to the authoritative in-memory safety source. Any script that does `$cfg = Get-AdmanConfig; $cfg.ManagedOUs = @(...)` mutates `$script:Config` without running `Test-AdmanConfigValid`, the empty-ManagedOUs gate, or `Save-AdmanConfig`. This bypasses the fail-closed invariant enforced by `Set-AdmanConfig` and `Import-AdmanConfig` (T-00-13) and can silently widen or empty the managed-OU scope.
**Fix:** Return a deep clone so callers get a read-only snapshot. Keep the dotted-key path (which returns scalar/immutable values) unchanged:

```powershell
if (-not $Key) {
    return ($script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
}
```

For better safety, also consider exposing a non-mutating view or adding a comment-based help warning that the returned object must not be modified.

## Warnings

### WR-01: Dead duplicated transcript guards in password verbs

**Files:**
- `Public/New-AdmanUser.ps1:207-213` and `225-230`
- `Public/Set-AdmanUserPassword.ps1:191-197` and `251-256`
- `Public/Set-AdmanLocalUser.ps1:207-210` and `224-228`
**Issue:** Each password verb checks `Get-AdmanTranscriptCount` twice: once before the gate and once immediately before displaying the generated password. The post-mutation check is unreachable because the pre-mutation check throws the same exception when a transcript is active. The duplicate guard adds no value, increases the attack surface for future edits, and makes the display-once hygiene harder to reason about.
**Fix:** Remove the second check and rely on the single pre-mutation guard. In `New-AdmanUser.ps1` the display block becomes:

```powershell
if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $AccountPassword) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccountPassword)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Console]::WriteLine("Generated password for ${SamAccountName}: $plain")
        Read-Host -Prompt 'Press Enter when recorded' | Out-Null
        try { [Console]::Clear() } catch [System.IO.IOException] { }
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}
```

Apply the same single-guard pattern to `Set-AdmanUserPassword.ps1` and `Set-AdmanLocalUser.ps1`.

### WR-02: Write-Host suppression is global, and offboarding checklist uses Write-Host

**Files:**
- `PSScriptAnalyzerSettings.psd1:29-33`
- `Public/Start-AdmanUserOffboarding.ps1:186-189`
**Issue:** `PSScriptAnalyzerSettings.psd1` disables `PSAvoidUsingWriteHost` globally (`Enable = $false`) with a forward-declared comment that the suppression is "ONLY for the future TUI menu module". The project convention in `CLAUDE.md` is to suppress `PSAvoidUsingWriteHost` only with a per-file `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]` attribute in the TUI-rendering module. `Start-AdmanUserOffboarding.ps1` currently uses `Write-Host` for the cleanup checklist (lines 186-189) without a per-file suppression, which means it neither follows the per-file convention nor trips the lint rule because the rule is globally disabled.
**Fix:** Re-enable `PSAvoidUsingWriteHost` in `PSScriptAnalyzerSettings.psd1` and either:
1. Replace the `Write-Host` calls in `Start-AdmanUserOffboarding.ps1` with `Write-Output`/`Write-Information`, or
2. Add a documented per-file suppression attribute if the checklist is intentionally console-only:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Cleanup checklist is intentionally console-only TUI output.')]
param(...)
```

### WR-03: Empty catch blocks swallow PSFramework mirror failures

**Files:**
- `Public/Config/Set-AdmanConfig.ps1:92`
- `Public/Config/Import-AdmanConfig.ps1:73`
- `Public/Config/Export-AdmanConfig.ps1:47-50`
**Issue:** The config verbs wrap best-effort PSFramework mirror operations in `try { ... } catch { }`. A failure in `Set-PSFConfig`, `Import-PSFConfig`, or `Export-PSFConfig` is silently discarded. While these are documented as non-authoritative mirrors, silently swallowing all exceptions makes it impossible to detect a broken D-01 backbone, misconfigured PSFramework module, or disk/permission failure. It also masks regressions in CI.
**Fix:** Capture the failure in a non-blocking diagnostic channel. The config operations must remain authoritative, but the mirror failures should be visible:

```powershell
try {
    Set-PSFConfig -Module adman -Name $Key -Value $Value -ErrorAction SilentlyContinue
} catch {
    Write-Verbose "PSFramework mirror update failed for '${Key}': $($_.Exception.Message)"
}
```

Use `Write-Verbose` or `Write-Warning` consistently across all three files instead of empty catch blocks.

### WR-04: Confirm-AdmanAction relies on implicit $WhatIfPreference inheritance

**Files:**
- `Public/Start-AdmanUserOnboarding.ps1:143`
- `Public/Start-AdmanUserOffboarding.ps1:157`
- `Public/Restore-AdmanQuarantinedUser.ps1:117`
- `Public/Invoke-AdmanBulkAction.ps1:252`
**Issue:** These workflow/bulk verbs call `Confirm-AdmanAction` without explicitly passing `-WhatIf:$WhatIfPreference`. The called function happens to inspect the automatic `$WhatIfPreference` variable, which is inherited because it also uses `[CmdletBinding(SupportsShouldProcess)]`, but this is implicit and fragile. A future refactor of `Confirm-AdmanAction` (for example, removing `SupportsShouldProcess` or wrapping it in a non-ShouldProcess helper) would silently break dry-run behavior for every workflow.
**Fix:** Pass `-WhatIf` explicitly at every call site for consistency with `Invoke-AdmanMutation` calls:

```powershell
$confirm = Confirm-AdmanAction -Verb 'Start-AdmanUserOnboarding' -Targets @($sam) -Force:$Force -WhatIf:$WhatIfPreference
```

Then update `Confirm-AdmanAction` to accept an explicit `[switch]$WhatIf` parameter and use `[bool]$WhatIf` instead of `[bool]$WhatIfPreference`, eliminating reliance on caller-scoped automatic variables.

## Info

### IN-01: Help.Coverage.Tests.ps1 runs twice in CI

**File:** `.github/workflows/ci.yml:112-113`
**Issue:** The CI job first runs `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1 -Tag Unit` and then runs the full PesterConfiguration, whose `Run.Path = 'tests'` includes the same `Help.Coverage.Tests.ps1`. The duplicate execution wastes CI time and can produce confusing duplicate output.
**Fix:** Remove the explicit `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1 -Tag Unit` line and rely on the configuration-driven run, or exclude `Help.Coverage.Tests.ps1` from the configuration path when running the explicit line.

### IN-02: Coverage gate target is set to zero

**File:** `tests/PesterConfiguration.psd1:26`
**Issue:** `CoveragePercentTarget = 0` disables the coverage gate. While this prevents CI from failing during early phase development, it means coverage regressions are not enforced.
**Fix:** Raise `CoveragePercentTarget` to a project-appropriate minimum (for example, 60 or 70) or document the deliberate zero in a comment so future maintainers know it is a temporary scaffold, not an accepted standard.

### IN-03: Module manifest description is stale

**File:** `adman.psd1:35`
**Issue:** The `Description` still reads "Phase 0 foundation scaffold" even though the module now exports the full Phase 5 surface (workflow verbs, local account verbs, bulk action, reporting, etc.). Stale metadata is misleading when the module is listed with `Get-Module` or published.
**Fix:** Update the description to reflect Phase 5:

```powershell
Description = 'adman - safety-first on-prem AD user/computer administration toolkit (Phase 5 hardened/portable release).'
```

### IN-04: Mojibake in comment-based help

**Files:**
- `Public/Add-AdmanGroupMember.ps1:19-20`
- `Public/Reset-AdmanComputerAccount.ps1:13, 31-32`
- `Public/Unlock-AdmanUser.ps1:25, 33`
**Issue:** Several comment blocks contain `â€”` (UTF-8 em dash mojibake) instead of a clean ASCII or properly encoded em dash. This indicates the files were saved or transformed with an inconsistent encoding and reduces readability of the help text.
**Fix:** Re-save the files as UTF-8 with BOM (or UTF-8 without BOM consistently) and replace `â€”` with either `-` (ASCII hyphen) or `—` (proper em dash). For example, in `Reset-AdmanComputerAccount.ps1`:

```powershell
# Set-ADAccountPassword -Reset resets the machine account password to the default.
```

---

_Reviewed: 2026-07-23T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
