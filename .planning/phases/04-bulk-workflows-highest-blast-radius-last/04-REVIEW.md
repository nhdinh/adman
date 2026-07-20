---
phase: 04-bulk-workflows-highest-blast-radius-last
reviewed: 2026-07-20T00:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Bulk/ConvertTo-AdmanBulkInput.ps1
  - Private/Bulk/Import-AdmanBulkCsv.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Safety/Confirm-AdmanAction.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Start-Adman.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - tests/Bulk.Csv.Tests.ps1
  - tests/Bulk.Engine.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Menu.BulkWorkflow.Tests.ps1
  - tests/Module.Manifest.Tests.ps1
  - tests/Safety.Confirm.Tests.ps1
  - tests/Safety.NoHardDelete.Tests.ps1
  - tests/Workflow.Offboarding.Tests.ps1
  - tests/Workflow.Onboarding.Tests.ps1
  - tests/Workflow.Restore.Tests.ps1
findings:
  critical: 1
  warning: 10
  info: 2
  total: 13
status: issues_found
---

# Phase 04: Bulk Workflows (Highest Blast Radius Last) — Code Review Report

**Reviewed:** 2026-07-20
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed the Phase 4 bulk engine, onboarding/offboarding/restore workflows, menu integration, audit writer, config loader, schema/defaults, and their unit tests. The code follows the established safety patterns (outer confirmation, inner `-Force:$true`, fail-closed config, no hard-delete). However, one critical correctness defect in `Restore-AdmanQuarantinedUser` can leave a restored account partially disabled in quarantine, and several warnings affect robustness, audit fidelity, or UI correctness.

## Critical Issues

### CR-01: Restore passes the original `Identity` to inner verbs after moving the user

**File:** `Public/Restore-AdmanQuarantinedUser.ps1:106-113`
**Issue:** `Restore-AdmanQuarantinedUser` resolves the user at line 66, validates quarantine, reads offboarding state, then calls `Add-AdmanGroupMember`, `Move-AdmanUser`, and `Enable-AdmanUser` all with `-Identity $Identity` (the original caller input). After `Move-AdmanUser` changes the DN, any subsequent re-resolution by DN in `Enable-AdmanUser` fails because the quarantine DN no longer exists. If the operator invoked restore with the original pre-offboarding DN, resolution at line 66 already fails. If they invoked it with the quarantine DN, the final enable step fails. Only `sAMAccountName` works reliably. This violates the documented invariant that a partial restore leaves the account disabled — the account is left disabled in quarantine with groups re-added and original OU restored.
**Fix:** Resolve once and use a stable identifier for the composed verbs. Prefer the resolved user's `SamAccountName`; fall back to the original `Identity` only when `SamAccountName` is unavailable (keeps mock tests working without a SamAccountName property).

```powershell
$stableIdentity = if ($user.PSObject.Properties['SamAccountName'] -and $user.SamAccountName) {
    $user.SamAccountName
} else {
    $Identity
}

foreach ($g in @($state.Groups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $null = Add-AdmanGroupMember -Identity $stableIdentity -GroupIdentity $g `
        -Force:$true -WhatIf:$WhatIfPreference
}
$null = Move-AdmanUser -Identity $stableIdentity -TargetPath $state.OriginalOU `
    -Force:$true -WhatIf:$WhatIfPreference
$null = Enable-AdmanUser -Identity $stableIdentity -Force:$true -WhatIf:$WhatIfPreference
```

## Warnings

### WR-01: `Write-AdmanAudit` declares `[switch]$WhatIf` but reads `$WhatIfPreference`

**File:** `Private/Audit/Write-AdmanAudit.ps1:51, 145`
**Issue:** The function accepts an explicit `-WhatIf` switch but never references it. The `whatIf` field is populated from the automatic `$WhatIfPreference` variable. In practice the caller always passes `-WhatIf:$WhatIfPreference` from a `SupportsShouldProcess` function, so preference-variable inheritance masks the issue, but the parameter is effectively unused and the behavior is fragile if called differently.
**Fix:** Use the bound parameter directly: `whatIf = [bool]$WhatIf`.

### WR-02: `Write-AdmanAudit` does not require `-Verb`

**File:** `Private/Audit/Write-AdmanAudit.ps1:41`
**Issue:** Only `-Result` is marked `[Parameter(Mandatory)]`. `-Verb` is optional, so a malformed caller could write an audit record whose `what` field is null, making the record useless for forensics.
**Fix:** Mark `[Parameter(Mandatory)]` on `-Verb` as well.

### WR-03: Bulk AddGroup/RemoveGroup no-op detection accesses `memberOf` without a property-existence guard

**File:** `Public/Invoke-AdmanBulkAction.ps1:258, 264`
**Issue:** Under `Set-StrictMode -Version Latest`, `$rec.ResolvedTarget.memberOf` throws `PropertyNotFoundException` if the resolved object lacks a `memberOf` property. Production AD objects normally have it, but mocks, deserialized objects, or non-user/computer targets can crash the per-item loop.
**Fix:** Guard the property read:

```powershell
$memberOf = if ($rec.ResolvedTarget.PSObject.Properties['memberOf']) { @($rec.ResolvedTarget.memberOf) } else { @() }
if ($memberOf -contains $groupDn) { ... }
```

### WR-04: `Get-AdmanOffboardingState` sorts `tsUtc` as strings

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:79`
**Issue:** `Sort-Object -Property tsUtc -Descending` sorts ISO-8601 strings lexicographically. For the current uniform `.ToString('o')` format this happens to match chronological order, but the code relies on an implicit contract and will break if timestamp precision or timezone representation varies.
**Fix:** Sort on parsed DateTime:

```powershell
$latest = $candidates | Sort-Object -Property { [datetime]$_.tsUtc } -Descending | Select-Object -First 1
```

### WR-05: `Import-AdmanBulkCsv` validates headers but not row content

**File:** `Private/Bulk/Import-AdmanBulkCsv.ps1:59-70`
**Issue:** The loader rejects unknown/duplicate/missing columns but does not check that `Identity` or `Action` rows are non-empty or that `Action` values are in the allowed set. Empty identities propagate to the bulk engine and are recorded as per-item failures rather than rejected at load time.
**Fix:** Add row-level validation after `Import-Csv` and throw a terminating error before returning rows with empty `Identity` or invalid `Action`.

### WR-06: Outer confirmation is shown even when zero items passed the filter

**File:** `Public/Invoke-AdmanBulkAction.ps1:214-232`
**Issue:** If every input is denied or filtered out, `$allowed.Count` is 0 but `Confirm-AdmanAction` is still invoked (with `Group` set to `"0 distinct groups"` for group operations). The operator is prompted to confirm zero objects.
**Fix:** Skip confirmation when `$allowed.Count -eq 0`; return the summary immediately.

### WR-07: `Initialize-AdmanConfig` accepts an empty `domain` value

**File:** `Private/Config/Initialize-AdmanConfig.ps1:85-88, 156-158`
**Issue:** `Test-AdmanConfigValid` checks that `domain` exists but not that it is non-empty. An empty `domain` passes validation and produces malformed UPNs (`user@`) during onboarding.
**Fix:** Reject empty/whitespace `domain` in `Test-AdmanConfigValid`.

### WR-08: Typing `B` at the CSV/HTML path prompt does not return to the menu

**File:** `Public/Start-Adman.ps1:224, 249`
**Issue:** The path-prompt `B` branch sets `$pathResolved = $true` and `$formatResolved = $true`, then `continue`s the inner path loop. Because `$pathResolved` becomes `$true`, the subsequent `if (-not $pathResolved) { continue }` does not fire, so execution falls through to `& $renderer -InputObject $reportData @rendererParams` with an empty `Path`. The renderer is invoked unexpectedly instead of returning to the menu.
**Fix:** Do not set `$pathResolved = $true` on `B`; break the path loop and let the existing `continue` skip the renderer:

```powershell
if ($outPath -match '^[Bb]$') { $formatResolved = $true; break }
```

### WR-09: `Start-AdmanUserOffboarding` calls `Get-ADGroup` directly in a fallback path

**File:** `Public/Start-AdmanUserOffboarding.ps1:128-144`
**Issue:** The protected-group fallback invokes the raw `Get-ADGroup` cmdlet rather than the project's `Resolve-AdmanGroup` seam, and swallows all errors with an empty `catch { }`. This duplicates resolution logic, bypasses mocks in tests, and can silently misclassify a group if the server is unreachable.
**Fix:** Route the fallback through `Resolve-AdmanGroup` and log a warning when resolution fails instead of silently ignoring it.

### WR-10: Audit file rotation uses local time while the record timestamp uses UTC

**File:** `Private/Audit/Write-AdmanAudit.ps1:77, 137`
**Issue:** The daily rotation file is named with `(Get-Date)` (local time), but the JSON record uses `ToUniversalTime()`. On a timezone boundary, an audit record written shortly after local midnight can land in a file whose date does not match the record's UTC date, complicating log searches and retention.
**Fix:** Name the file from the same UTC timestamp used for the record:

```powershell
$nowUtc = (Get-Date).ToUniversalTime()
$path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f $nowUtc)
# ...
tsUtc = $nowUtc.ToString('o')
```

## Info

### IN-01: `Write-AdmanAudit` contains a redundant audit-stream throw

**File:** `Private/Audit/Write-AdmanAudit.ps1:169-172, 180-204`
**Issue:** The function throws "AUDIT FAIL-CLOSED: cannot open audit stream..." when `Open-AdmanAuditStream` returns `$null`, but that throw is inside the same `try` block whose `catch` already decides behavior based on `$Result`. For `PENDING` the catch rethrows anyway; for non-`PENDING` it degrades. The explicit throw is dead code with a misleading message.
**Fix:** Remove the redundant throw and rely on the catch block, or move the stream-open logic outside the main `try` so a genuine open failure can propagate as intended.

### IN-02: Shared empty `[string[]]` reference across write-menu entries

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:89, 99-101`
**Issue:** `$emptyProperties = [string[]]@()` is a single array instance assigned to every write/report separator entry. If any downstream code mutates `$entry.Properties`, the change would affect all entries that share the reference.
**Fix:** Return a new array for each entry (`Properties = [string[]]@()`) or make `$emptyProperties` read-only in practice by never mutating it.

---

_Reviewed: 2026-07-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
