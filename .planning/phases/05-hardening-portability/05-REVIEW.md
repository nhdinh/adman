---
phase: 05-hardening-portability
reviewed: 2026-07-22T03:45:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - docs/USAGE.md
  - docs/RECOVERY-RUNBOOK.md
  - tests/Docs.Coverage.Tests.ps1
  - README.md
  - Private/Workflow/Get-AdmanOffboardingState.ps1
findings:
  critical: 0
  warning: 7
  info: 3
  total: 10
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-07-22T03:45:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 5 Plan 01b refreshed operator-facing documentation and added a Pester contract test that keeps docs in sync with the module manifest and menu definition. The docs coverage test passes (16/16), and the parse error in `Private/Workflow/Get-AdmanOffboardingState.ps1` has been fixed. However, the reviewed files still contain correctness, robustness, and documentation-accuracy defects: the offboarding-state reader lacks initialization and object-class guards, the runbook misstates the default AD tombstone lifetime, and the contract-test regexes are fragile against future doc examples.

## Critical Issues

No critical issues identified in the reviewed files.

## Warnings

### WR-01: `Get-AdmanOffboardingState` does not validate resolved object class

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:27`
**Issue:** `Resolve-AdmanTarget` can resolve users, computers, groups, or OUs. The function selects the first result and assumes it is a user without checking `objectClass`. For a non-user identity the function will normally return `$null` because the audit records it searches are always for `Start-AdmanUserOffboarding`, but the missing guard makes the function less self-documenting and could match inappropriate state if the audit schema ever broadens.
**Fix:** Add an explicit object-class check after resolution:
```powershell
$resolved = Resolve-AdmanTarget -Targets @($Identity) | Select-Object -First 1
if ($null -eq $resolved) {
    throw "Identity '$Identity' could not be resolved to a single user."
}
if ($resolved.objectClass -ne 'user') {
    throw "Identity '$Identity' resolved to a $($resolved.objectClass), not a user."
}
```

### WR-02: `Get-AdmanOffboardingState` reads `$script:Config.AuditDir` without initialization guard

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:42`
**Issue:** The function directly accesses `$script:Config.AuditDir`. If `Initialize-Adman` has not run, `$script:Config` is `$null` and the property access throws a low-level null-reference error instead of the clear "adman is not initialized" message used by exported functions. This is especially likely if the private function is invoked directly during testing or debugging.
**Fix:** Mirror the WR-01 guard from `Restore-AdmanQuarantinedUser`:
```powershell
if (-not $script:Config -or -not $script:Config.PSObject.Properties['AuditDir']) {
    throw 'adman is not initialized. Run Initialize-Adman first.'
}
$auditDir = $script:Config.AuditDir
```

### WR-03: Unhandled `[datetime]` cast when `tsUtc` is malformed

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:98`
**Issue:** The function catches JSON parse errors per line but does not catch `InvalidCastException` from `[datetime]$_.tsUtc`. A corrupted or manually edited audit line with a non-date `tsUtc` string will terminate the entire restore lookup instead of being skipped like other malformed records.
**Fix:** Convert the timestamp inside the per-record try block and skip on failure:
```powershell
try {
    $rec = $line | ConvertFrom-Json -ErrorAction Stop
    $rec | Add-Member -NotePropertyName 'tsUtcDate' -NotePropertyValue ([datetime]$rec.tsUtc) -ErrorAction Stop
} catch {
    Write-Warning "Skipping corrupt offboarding audit line in '$($file.FullName)': $_"
    continue
}
# ... later ...
$latest = $candidates | Sort-Object -Property tsUtcDate -Descending | Select-Object -First 1
```

### WR-04: RECOVERY-RUNBOOK.md states incorrect default tombstone lifetime

**File:** `docs/RECOVERY-RUNBOOK.md:38`
**Issue:** The runbook says "default 180 days" for tombstone lifetime. Since Windows Server 2003 SP1 the default tombstone lifetime (and therefore the default deleted-object lifetime when the AD Recycle Bin is enabled) is 60 days, not 180. Operators relying on this figure may delay recovery actions and find objects have already been garbage-collected.
**Fix:** Change the sentence to:
```markdown
If the object has passed the deleted object lifetime (which defaults to the tombstone lifetime, 60 days on modern forests), it is no longer in the Recycle Bin and an authoritative restore from backup is the only option.
```

### WR-05: RECOVERY-RUNBOOK.md shows unescaped LDAP wildcard in filter example

**File:** `docs/RECOVERY-RUNBOOK.md:31`
**Issue:** The example `Get-ADObject -Filter "Name -like 'jdoe*'"` embeds a literal value into an LDAP filter without escaping. If an operator copies the pattern with a name containing `*`, `(`, `)`, `\`, or NUL, the filter can match unintended objects or become malformed.
**Fix:** Add a note immediately after the example:
```markdown
Replace `jdoe` with the actual name. If the name contains LDAP filter special characters (`*`, `(`, `)`, `\`), escape them first or identify the object by GUID/DN.
```

### WR-06: Docs coverage test regex can match PowerShell comment lines as headings

**File:** `tests/Docs.Coverage.Tests.ps1:173`
**Issue:** The next-heading regex `(?m)^###?\s+` matches any line beginning with one to three hashes followed by whitespace. A future function example that includes a commented PowerShell line such as `# This is a comment` would be mistaken for the next heading, truncating the function section and causing false test failures.
**Fix:** Track fenced-code-block state while scanning, or simplify by splitting on lines and only testing heading patterns outside code fences. A minimal improvement is to look for the next function heading (`^### \`) specifically rather than any heading pattern, because every function in the Exported functions section uses an `###` heading.

### WR-07: Docs coverage test enumerates exported commands too broadly

**File:** `tests/Docs.Coverage.Tests.ps1:48`
**Issue:** `(Get-Command -Module adman).Name` collects all command types exported by the module. The manifest currently restricts aliases and cmdlets to empty lists, but if a future manifest change exports an alias or if command discovery order shifts, the contract could include non-function commands or miss functions.
**Fix:** Be explicit about the command type:
```powershell
$script:ExportedFunctions = @((Get-Command -Module adman -CommandType Function).Name | Sort-Object)
```

## Info

### IN-01: Docs coverage test does not restore `$env:PSModulePath`

**File:** `tests/Docs.Coverage.Tests.ps1:33`
**Issue:** The test prepends a stub directory to `$env:PSModulePath` in `BeforeAll` and never restores the original value in `AfterAll`. In a long test run this can affect subsequent test files that rely on module path ordering.
**Fix:** Save and restore the original path:
```powershell
BeforeAll {
    $script:OriginalPSModulePath = $env:PSModulePath
    # ... stub setup ...
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
}
AfterAll {
    $env:PSModulePath = $script:OriginalPSModulePath
    Remove-Module -Name adman -Force -ErrorAction SilentlyContinue
}
```

### IN-02: Docs coverage test uses unqualified `Get-Command` for parameter lookup

**File:** `tests/Docs.Coverage.Tests.ps1:205`
**Issue:** `Get-Command $func -ErrorAction Stop` resolves the command through normal discovery order. If another loaded module exports a function with the same name, the test could inspect the wrong command's parameters.
**Fix:** Qualify by module:
```powershell
$cmd = Get-Command -Module adman -Name $func -CommandType Function -ErrorAction Stop
```

### IN-03: Certificate naming inconsistency between README and RECOVERY-RUNBOOK

**File:** `docs/RECOVERY-RUNBOOK.md:95`
**Issue:** The runbook refers to "old certificate (`adman-signing-v1.cer`)" but `README.md:153` exports `adman-signing.cer` without a version suffix. This inconsistency could confuse operators during rotation.
**Fix:** Align the filenames. Either update the README example to export `adman-signing-v1.cer` or update the runbook to refer to "the previously exported `.cer` file" instead of a specific v1 name.

---

_Reviewed: 2026-07-22T03:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
