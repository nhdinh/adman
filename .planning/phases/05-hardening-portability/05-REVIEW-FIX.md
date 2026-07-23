---
phase: 05-hardening-portability
fixed_at: 2026-07-23T00:00:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-23T00:00:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

## Fixed Issues

### CR-01: Get-AdmanConfig returns the live config object by reference

**Files modified:** `Public/Config/Get-AdmanConfig.ps1`
**Commit:** 8c68617
**Applied fix:** Changed the no-key code path to return a deep clone via `ConvertTo-Json -Depth 10 | ConvertFrom-Json` instead of the live `$script:Config` reference. Updated comment-based help to describe the returned object as a read-only snapshot.

### WR-01: Dead duplicated transcript guards in password verbs

**Files modified:** `Public/New-AdmanUser.ps1`, `Public/Set-AdmanUserPassword.ps1`, `Public/Set-AdmanLocalUser.ps1`
**Commit:** 0fdcc2c
**Applied fix:** Removed the unreachable post-mutation transcript checks in the three password display blocks, relying on the single pre-mutation guard.

### WR-02: Write-Host suppression is global, and offboarding checklist uses Write-Host

**Files modified:** `PSScriptAnalyzerSettings.psd1`, `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** 4d81753
**Applied fix:** Removed the global `PSAvoidUsingWriteHost` suppression in `PSScriptAnalyzerSettings.psd1` and added a documented per-file `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` on `Start-AdmanUserOffboarding` for the intentionally console-only cleanup checklist.

### WR-03: Empty catch blocks swallow PSFramework mirror failures

**Files modified:** `Public/Config/Set-AdmanConfig.ps1`, `Public/Config/Import-AdmanConfig.ps1`, `Public/Config/Export-AdmanConfig.ps1`
**Commit:** b87b195
**Applied fix:** Replaced empty `catch { }` blocks with `Write-Verbose` diagnostics so PSFramework mirror failures are visible without blocking authoritative config operations.

### WR-04: Confirm-AdmanAction relies on implicit $WhatIfPreference inheritance

**Files modified:** `Private/Safety/Confirm-AdmanAction.ps1`, `Public/Start-AdmanUserOnboarding.ps1`, `Public/Start-AdmanUserOffboarding.ps1`, `Public/Restore-AdmanQuarantinedUser.ps1`, `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** 1beb507
**Applied fix:** Added an explicit `[switch]$WhatIf` parameter to `Confirm-AdmanAction` and switched the internal check from `[bool]$WhatIfPreference` to `[bool]$WhatIf`. Updated all workflow/bulk call sites to pass `-WhatIf:$WhatIfPreference` (or add `WhatIf = $WhatIfPreference` to the bulk-action splat).

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-07-23T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
