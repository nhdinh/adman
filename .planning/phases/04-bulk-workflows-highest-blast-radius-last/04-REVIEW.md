---
phase: 04-bulk-workflows-highest-blast-radius-last
reviewed: 2026-07-20T00:00:00Z
depth: standard
files_reviewed: 22
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
  critical: 2
  warning: 8
  info: 2
  total: 12
status: issues_found
---

# Phase 04: Bulk & Workflows — Code Review Report

**Reviewed:** 2026-07-20
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

Reviewed the Phase 4 bulk/workflow implementation (bulk engine, CSV loader, onboarding/offboarding/restore workflows, menu integration, and supporting config/audit changes). The code generally follows the established safety patterns: single outer confirmation, inner verbs forced, WhatIf propagation, audit logging, and managed-OU scope checks. However, two correctness defects in the offboarding/restore path can crash the workflow or make a quarantined user unrestorable. Several other quality issues around null handling, DN parsing, and state initialization need attention before ship.

## Critical Issues

### CR-01: Offboarding crashes when the user has no `memberOf` property

**File:** `Public/Start-AdmanUserOffboarding.ps1:95`

**Issue:**
`foreach ($g in @($user.memberOf))` iterates once with `$g = $null` when the resolved user object has a null `memberOf`. The loop body calls `Resolve-AdmanGroup -Identity $null`, catches, then adds the null entry to `$groupsToRemove`. Later, `Remove-AdmanGroupMember -GroupIdentity $null` throws, aborting the workflow after the account has already been disabled. The Failure audit is written, but the account is left in an inconsistent state (disabled, not moved, groups untouched).

**Fix:**
Filter null/empty entries before iterating:

```powershell
foreach ($g in @($user.memberOf | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    # existing classification logic
}
```

### CR-02: Restore fails for offboarded users with no removable groups

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:74-76`

**Issue:**
`Write-AdmanAudit` intentionally omits the `groups` field when the removed-group list is empty. `Get-AdmanOffboardingState` returns `Groups = @($latest.groups)`, which becomes `@($null)` (a one-element array containing `$null`) when the field is absent. `Restore-AdmanQuarantinedUser` then iterates once and calls `Add-AdmanGroupMember -GroupIdentity $null`, which fails. Any user whose offboarding stripped zero groups is effectively unrestorable.

**Fix:**
Treat a missing/null `groups` field as an empty array in the state reader, and defensively filter the restore loop:

```powershell
# In Get-AdmanOffboardingState
return [pscustomobject]@{
    OriginalOU = $latest.originalOU
    Groups     = if ($null -ne $latest.groups) { @($latest.groups) } else { @() }
}

# In Restore-AdmanQuarantinedUser
foreach ($g in @($state.Groups | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $null = Add-AdmanGroupMember -Identity $Identity -GroupIdentity $g -Force:$true -WhatIf:$WhatIfPreference
}
```

## Warnings

### WR-01: Parent-DN extraction uses a regex that breaks on escaped commas

**Files:**
- `Public/Start-AdmanUserOffboarding.ps1:89`
- `Public/Restore-AdmanQuarantinedUser.ps1:72`
- `Public/Invoke-AdmanBulkAction.ps1:244`

**Issue:**
`[string]$dn -replace '^[^,]+,'` splits at the first literal comma. A CN with an escaped comma such as `CN=Doe\, John,OU=Users,DC=mock,DC=local` yields an invalid parent OU (`John,OU=Users,...`). This corrupts the recorded `originalOU` in the offboarding audit, breaks the "already in place" skip check for bulk moves, and can cause the restore quarantine check to fail.

**Fix:**
Replace the regex with a DN-aware parser that respects RFC 4514 escaping, or add a helper that walks the DN components from the right.

### WR-02: `$script:AuditDegraded` is never initialized

**Files:**
- `adman.psm1`
- `Private/Audit/Write-AdmanAudit.ps1:206`

**Issue:**
`Write-AdmanAudit` writes `$script:AuditDegraded = $true` on OUTCOME audit-write failures, but the variable is never initialized in `adman.psm1`. The assignment itself is safe, but any downstream reader (e.g. a status banner or health check) will throw under `Set-StrictMode -Version Latest` because the variable does not exist.

**Fix:**
Add `$script:AuditDegraded = $false` to `adman.psm1` alongside the other module-level slots.

### WR-03: `Get-AdmanOffboardingState` aborts on corrupt audit records

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:59-66`

**Issue:**
The inner `try/catch` only wraps `ConvertFrom-Json`. A malformed line with `targets = $null` or a missing `tsUtc` causes a `PropertyNotFoundStrict` or null-property-access exception that propagates out and aborts the restore. Because the audit log is the authoritative restore source, the reader should be tolerant of individual corrupt lines.

**Fix:**
Wrap the entire per-record evaluation in a `try/catch` and `continue` on malformed records, optionally writing a warning.

### WR-04: `Invoke-AdmanBulkAction` ignores per-row `TargetPath` in CSV Move jobs

**File:** `Public/Invoke-AdmanBulkAction.ps1:97-104, 276`

**Issue:**
The CSV loader parses `TargetPath` on each row, but the per-item execution always uses the outer `-TargetPath` parameter. The menu comment says Move is whole-job in v1, but the CSV schema still advertises a per-row `TargetPath` column. An operator who supplies per-row destinations will silently have them ignored.

**Fix:**
Use `$rec.TargetPath` when present, falling back to `$TargetPath`; document the whole-job default when the column is omitted.

### WR-05: `Write-AdmanAudit` mixes `$WhatIf` parameter and `$WhatIfPreference`

**File:** `Private/Audit/Write-AdmanAudit.ps1:145, 183, 186`

**Issue:**
The persisted `whatIf` field is set from `[bool]$WhatIf` (the bound parameter), while the actual audit writes use `-WhatIf:$WhatIfPreference`. Callers currently bind `-WhatIf:$WhatIfPreference`, so the values match, but the inconsistency is latent: if the function is invoked inside a `-WhatIf` context without explicitly binding `-WhatIf`, the record flag and write behavior can disagree.

**Fix:**
Use `[bool]$WhatIfPreference` for the record field to match the rest of the function.

### WR-06: Redundant/confusing SID check against the DN protected-group list

**File:** `Public/Start-AdmanUserOffboarding.ps1:115`

**Issue:**
`$script:ProtectedGroupDns` is documented and named as a DN list, yet line 115 checks whether the resolved group SID is contained in it. This branch is effectively dead unless the list contains SIDs, in which case the variable name is misleading. The DN check already follows at lines 119-122.

**Fix:**
Remove the SID-against-DN-list check, or rename the variable and document that it may hold either SIDs or DNs.

### WR-07: `Import-AdmanBulkCsv` returns a phantom row for header-only files

**File:** `Private/Bulk/Import-AdmanBulkCsv.ps1:51-56`

**Issue:**
An empty file returns an empty array, but a file containing only the header line returns one row whose properties are all empty strings. That row can propagate into the bulk engine and produce a confusing failure (or, depending on downstream behavior, an attempted mutation on an empty identity).

**Fix:**
After `Import-Csv`, return an empty array if the file contains no data rows, or explicitly document that header-only is treated as one empty row.

### WR-08: `Initialize-AdmanConfig` saves an unvalidated intermediate config

**File:** `Private/Config/Initialize-AdmanConfig.ps1:272-286, 299`

**Issue:**
The Phase 4 additive migration writes the config to disk at line 285 before `Test-AdmanConfigValid` runs at line 299. If the shipped defaults drift or the on-disk file is concurrently modified, an invalid config can be persisted.

**Fix:**
Apply additive migrations in memory, validate once, and then save. Avoid intermediate disk writes before validation succeeds.

## Info

### IN-01: Duplicate `Describe` block name in menu tests

**File:** `tests/Menu.BulkWorkflow.Tests.ps1:132, 176`

**Issue:**
Two `Describe` blocks share the exact name `'Phase 4 workflow entries skip the generic output-format prompt'`. Pester will run both, but overlapping names make reports harder to read and can confuse test tooling.

**Fix:**
Rename the second block to something like `'Phase 4 workflow entries skip the output-format prompt via Start-Adman'`.

### IN-02: `Write-AdmanAudit` does not declare an output type

**File:** `Private/Audit/Write-AdmanAudit.ps1:37`

**Issue:**
The function emits no pipeline output on success. Declaring `[OutputType([void])]` would make the contract explicit for readers and static analysis.

**Fix:**
Add `[OutputType([void])]` to the `CmdletBinding` attribute block.

---

_Reviewed: 2026-07-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
