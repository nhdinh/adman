---
phase: 04-bulk-workflows-highest-blast-radius-last
reviewed: 2026-07-20T10:02:13Z
depth: standard
files_reviewed: 25
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
  - adman.psd1
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
  warning: 7
  info: 4
  total: 12
status: issues_found
---

# Phase 04: Bulk Workflows Code Review Report

**Reviewed:** 2026-07-20T10:02:13Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Reviewed the Phase 4 bulk engine, onboarding/offboarding/restore workflows, audit writer, config loader, menu definition, and their unit tests. The bulk engine correctly gates moves/group destinations before the cap/confirm, propagates `-WhatIf`/`-Force` to inner verbs, and skips no-ops. However, one critical correctness bug breaks the default onboarding path, and several warnings concern incomplete confirmation scope, audit-stream null safety, report-property drift, and CSV header parsing.

## Critical Issues

### CR-01: Start-AdmanUserOnboarding rejects a valid empty `BaselineGroups` array

**File:** `Public/Start-AdmanUserOnboarding.ps1:71-76`
**Issue:** The template validation loop treats every required key as a string and uses `[string]::IsNullOrWhiteSpace([string]$template.$key)`. For `BaselineGroups`, an empty array `@()` casts to an empty string, so the default config (`"BaselineGroups": []`) fails validation with "Onboarding template is missing required key 'BaselineGroups'." This blocks new-user onboarding out of the box.
**Fix:** Type-aware validation. Treat `BaselineGroups` as an array presence check, not a whitespace check:

```powershell
foreach ($key in @('ParentOuDn', 'BaselineGroups', 'NamePattern')) {
    if (-not $template.PSObject.Properties[$key]) {
        throw "Onboarding template is missing required key '$key'."
    }
    if ($key -eq 'BaselineGroups') {
        if ($null -eq $template.$key) {
            throw "Onboarding template is missing required key '$key'."
        }
    } elseif ([string]::IsNullOrWhiteSpace([string]$template.$key)) {
        throw "Onboarding template is missing required key '$key'."
    }
}
```

## Warnings

### WR-01: Write-AdmanAudit does not null-check the audit file stream

**File:** `Private/Audit/Write-AdmanAudit.ps1:169-176`
**Issue:** `Open-AdmanAuditStream` returns a stream via the IO seam, but the code immediately calls `$fs.Write(...)` and `$fs.Flush($true)` without verifying `$fs` is not `$null`. A seam returning `$null` would produce a secondary `NullReferenceException` that masks the real audit-open failure.
**Fix:** Guard the stream before writing:

```powershell
$fs = Open-AdmanAuditStream -Path $path
if ($null -eq $fs) {
    throw "AUDIT FAIL-CLOSED: cannot open audit stream for '$path'."
}
try { ... }
finally { $fs.Dispose() }
```

### WR-02: Computer inventory report properties are built from user properties

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:82-83`
**Issue:** `$computerReportProperties` is constructed from `$userProperties` rather than `$computerProperties`. As a result, the fleet inventory report header set omits computer-specific columns such as `OperatingSystem`, `OperatingSystemVersion`, `IPv4Address`, and `DNSHostName`, while including user-only columns such as `PasswordExpired` and `UserPrincipalName`.
**Fix:** Use the computer base array:

```powershell
$computerReportProperties = [string[]]($computerProperties + 'Bucket' + 'Transport' + 'RemoteOS' + 'Uptime' + 'LoggedOnUser')
```

### WR-03: Bulk group-operation confirmation only shows the first group

**File:** `Public/Invoke-AdmanBulkAction.ps1:221-223`
**Issue:** When a CSV or pipeline contains records targeting multiple different groups, the typed-count confirmation renders only `$allowed[0].ResolvedGroup.DistinguishedName`. The operator may confirm a scope that does not match all groups actually being modified, although the inner gate still validates each item.
**Fix:** Build a distinct group list for the prompt, or fall back to a generic "N group destination(s)" message when more than one group is present:

```powershell
$groupDns = @($allowed | ForEach-Object { $_.ResolvedGroup.DistinguishedName } | Select-Object -Unique)
if ($groupDns.Count -eq 1) { $confirmArgs['Group'] = $groupDns[0] }
else { $confirmArgs['Group'] = "$($groupDns.Count) distinct groups" }
```

### WR-04: Offboarding protected-group fallback compares DN against a list that may contain SIDs

**File:** `Public/Start-AdmanUserOffboarding.ps1:121-123`
**Issue:** In the catch fallback, `$g` is a `memberOf` DN string, but it is compared with `$script:ProtectedGroupDns`, which the codebase also uses to store SID strings (see `Workflow.Offboarding.Tests.ps1:234`). A DN will never equal a SID, so the fallback does not protect unresolved groups identified only by SID.
**Fix:** Normalize the comparison: resolve the DN to a SID where possible, and compare both DN and SID forms against the protected sets. Alternatively, keep `ProtectedGroupDns` strictly as DNs and use a separate `ProtectedGroupSids` list for SID-based protection.

### WR-05: `AuditDegraded` flag is not set if event-log escalation itself throws

**File:** `Private/Audit/Write-AdmanAudit.ps1:203-206`
**Issue:** In the OUTCOME-write failure path, `Write-AdmanEventLog` is invoked before `$script:AuditDegraded = $true`. If `Write-AdmanEventLog` throws, the flag is never set and the original audit-failure context is replaced by the event-log exception.
**Fix:** Set the degraded flag before the best-effort escalation:

```powershell
$script:AuditDegraded = $true
Write-AdmanEventLog -EventId 9001 -EntryType Error -Message "..."
Write-Warning "AUDIT OUTCOME WRITE FAILED ..."
```

### WR-06: Default config store path is relative to the process working directory

**File:** `Private/Config/Initialize-AdmanConfig.ps1:221`
**Issue:** When `$script:StorePath` is unset, it defaults to `'.store'`. `Join-Path` then resolves this against the current directory at invocation time, which can change depending on how adman is launched (e.g., `runas /netonly` from `C:\Windows\System32`).
**Fix:** Default to a path resolved against the module root:

```powershell
if (-not $script:StorePath) {
    $script:StorePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.store'
}
```

### WR-07: CSV header parser does not honor quoted commas

**File:** `Private/Bulk/Import-AdmanBulkCsv.ps1:30-34`
**Issue:** The manual header check splits on literal commas (`$headerLine.Split(',')`). If a header field is quoted and contains a comma, the split produces more fields than `Import-Csv` will, causing a false positive for duplicate/unknown columns. The row parser (`Import-Csv`) handles RFC-4180 quoting correctly, so the two parsers disagree.
**Fix:** Parse the header with the same semantics as `Import-Csv`. The simplest robust approach is to let `Import-Csv` parse the header and then inspect `$rows[0].PSObject.Properties.Name`, or use a regex CSV splitter that respects quotes.

## Info

### IN-01: Shared empty `[string[]]` reference across all write-menu entries

**File:** `Private/Menu/Get-AdmanMenuDefinition.ps1:89, 99-101`
**Issue:** `$emptyProperties = [string[]]@()` is a single array instance assigned to every write/report separator entry. If any downstream code mutates `$entry.Properties`, the change would affect all entries that share the reference.
**Fix:** Return a new array for each entry (`Properties = [string[]]@()`) or make `$emptyProperties` read-only in practice by never mutating it.

### IN-02: Initialize-AdmanConfig reads `adman.defaults.json` multiple times

**File:** `Private/Config/Initialize-AdmanConfig.ps1:230-231, 250-253, 272-274, 289-290`
**Issue:** The defaults file is read up to four times during a single load. This is redundant and increases the chance of inconsistent state if the file changes mid-load.
**Fix:** Read the defaults once at the top of the function and reuse the cleaned object for seeding, additive merges, and deny-list seeding.

### IN-03: Initialization check is duplicated in every public mutating function

**Files:** `Public/Invoke-AdmanBulkAction.ps1:55-59`, `Public/Start-AdmanUserOffboarding.ps1:49-53`, `Public/Start-AdmanUserOnboarding.ps1:55-59`, `Public/Restore-AdmanQuarantinedUser.ps1:45-49`
**Issue:** The same `ManagedOUs` existence check is copy-pasted into each public function. A private helper (`Assert-AdmanInitialized`) would reduce drift and make the gate easier to update.
**Fix:** Extract `Assert-AdmanInitialized` in `Private/Safety` and call it from each public entry point.

### IN-04: Audit file name uses local time while the record timestamp uses UTC

**File:** `Private/Audit/Write-AdmanAudit.ps1:77, 137`
**Issue:** The daily rotation file is named with `(Get-Date)` (local time), but the JSON record uses `ToUniversalTime()`. On a timezone boundary, an audit record written shortly after local midnight can land in a file whose date does not match the record's UTC date.
**Fix:** Name the file from the same UTC timestamp used for the record:

```powershell
$nowUtc = (Get-Date).ToUniversalTime()
$path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f $nowUtc)
# ...
tsUtc = $nowUtc.ToString('o')
```

---

_Reviewed: 2026-07-20T10:02:13Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
