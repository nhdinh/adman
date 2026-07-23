---
phase: 04
fixed_at: 2026-07-20T10:44:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-07-20T10:44:00Z
**Source review:** `C:/Users/nhdinh/dev/adman/.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 11
- Fixed: 11
- Skipped: 0

## Fixed Issues

### CR-01: Restore passes the original `Identity` to inner verbs after moving the user

**Files modified:** `Public/Restore-AdmanQuarantinedUser.ps1`
**Commit:** `3c65147`
**Applied fix:** Resolved the user once, then computed a `$stableIdentity` from `SamAccountName` (falling back to the original input for mocks without that property). Replaced the original `$Identity` in `Add-AdmanGroupMember`, `Move-AdmanUser`, and `Enable-AdmanUser` with `$stableIdentity` so the post-move enable step does not fail when the quarantine DN no longer exists.
**Status:** fixed: requires human verification — this is a correctness/logic change in the restore workflow.

### WR-01: `Write-AdmanAudit` declares `[switch]$WhatIf` but reads `$WhatIfPreference`

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `b0af95d`
**Applied fix:** Changed the audit record's `whatIf` field from `[bool]$WhatIfPreference` to `[bool]$WhatIf` so the explicit bound parameter is honored.

### WR-02: `Write-AdmanAudit` does not require `-Verb`

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `7457a44`
**Applied fix:** Added `[Parameter(Mandatory)]` to the `-Verb` parameter so malformed callers cannot write audit records with a null `what` field.

### WR-03: Bulk AddGroup/RemoveGroup no-op detection accesses `memberOf` without a property-existence guard

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `c5edb68`
**Applied fix:** Guarded the `memberOf` read with a `PSObject.Properties` check, defaulting to an empty array when the property is absent, so `Set-StrictMode -Version Latest` does not throw for mocks/deserialized targets.

### WR-04: `Get-AdmanOffboardingState` sorts `tsUtc` as strings

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`
**Commit:** `000fdf8`
**Applied fix:** Changed `Sort-Object -Property tsUtc` to `Sort-Object -Property { [datetime]$_.tsUtc }` so timestamp ordering is chronological regardless of precision/timezone representation.

### WR-05: `Import-AdmanBulkCsv` validates headers but not row content

**Files modified:** `Private/Bulk/Import-AdmanBulkCsv.ps1`
**Commit:** `1d5de5a`
**Applied fix:** Added row-level validation after `Import-Csv` to reject empty `Identity`, empty `Action`, or `Action` values outside the allowed set (`Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`) before rows reach the bulk engine.

### WR-06: Outer confirmation is shown even when zero items passed the filter

**Files modified:** `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `3b9546a`
**Applied fix:** Wrapped the outer confirmation block in `if ($allowed.Count -gt 0)` so the operator is not prompted to confirm zero objects when every input is denied or filtered out.

### WR-07: `Initialize-AdmanConfig` accepts an empty `domain` value

**Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`
**Commit:** `f72eedf`
**Applied fix:** Added an explicit `[string]::IsNullOrWhiteSpace` check on `$Config.domain` in `Test-AdmanConfigValid` so empty/whitespace domains fail validation and cannot produce malformed UPNs during onboarding.

### WR-08: Typing `B` at the CSV/HTML path prompt does not return to the menu

**Files modified:** `Public/Start-Adman.ps1`
**Commit:** `f2a9b60`
**Applied fix:** Changed the CSV and HTML path-prompt `B` branches from `$pathResolved = $true; $formatResolved = $true; continue` to `$formatResolved = $true; break`, letting the existing `if (-not $pathResolved) { continue }` skip the renderer and return to the menu.

### WR-09: `Start-AdmanUserOffboarding` calls `Get-ADGroup` directly in a fallback path

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `5f1ee5c`
**Applied fix:** Replaced the raw `Get-ADGroup` call in the protected-group fallback with `Resolve-AdmanGroup -Identity $g`, and replaced the empty `catch { }` with a `Write-Warning` that surfaces the resolution failure instead of silently ignoring it.
**Status:** fixed: requires human verification — this is a logic change in the protected-group classification path.

### WR-10: Audit file rotation uses local time while the record timestamp uses UTC

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `0fadaf2`
**Applied fix:** Captured `(Get-Date).ToUniversalTime()` once as `$nowUtc` and used it for both the rotation file name and the record's `tsUtc` field, eliminating date skew across timezone boundaries.

---

_Fixed: 2026-07-20T10:44:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
