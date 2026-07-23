---
phase: 05-hardening-portability
reviewed: 2026-07-23T12:00:00Z
depth: standard
files_reviewed: 71
files_reviewed_list:
  - .github/workflows/ci.yml
  - .githooks/pre-commit
  - adman.psd1
  - build/Sign-AdmanModule.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - docs/RECOVERY-RUNBOOK.md
  - docs/USAGE.md
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Remoting/Test-AdmanCimSessionTimeout.ps1
  - Private/Remoting/Test-AdmanWsmanTimeout.ps1
  - Private/Safety/Confirm-AdmanAction.ps1
  - Private/Safety/Invoke-AdmanLocalMutation.ps1
  - Private/Safety/Invoke-AdmanMutation.ps1
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
  - README.md
  - tests/Audit.EventLog.Tests.ps1
  - tests/Audit.FailClosed.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Schema.Tests.ps1
  - tests/Bulk.Engine.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Docs.Coverage.Tests.ps1
  - tests/Foundation.Capability.Tests.ps1
  - tests/Help.Coverage.Tests.ps1
  - tests/Local.Gate.Tests.ps1
  - tests/PesterConfiguration.psd1
  - tests/Safety.ConfirmationRestored.Tests.ps1
  - tests/Safety.GateOrder.Tests.ps1
  - tests/Workflow.OffboardingState.Tests.ps1
findings:
  critical: 0
  warning: 6
  info: 5
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T12:00:00Z
**Depth:** standard
**Files Reviewed:** 71
**Status:** issues_found

## Summary

Reviewed the Phase 05 hardening/portability surface at standard depth: CI/workflow, signing, config loader/validator, menu definition, audit writer/rotation/integrity, remoting timeout wrappers, the AD and local mutation gates, all Public verbs, and the supporting Pester test suite. The prior review findings (CR-01 through WR-04 from the earlier `05-REVIEW.md`) are resolved in HEAD: `Confirm-AdmanAction` no longer declares a duplicate `-WhatIf` parameter, the timeout wrappers are used consistently, and the menu/docs are aligned.

No Critical issues (real mutations under `-WhatIf`, bypass of scope/deny/protected checks, or audit fail-open paths) were found. The remaining issues are maintainability/correctness warnings and code-quality items.

## Warnings

### WR-01: Empty catch in `Resolve-AdmanLocalTarget` swallows profile-read failures

**File:** `Private/Safety/Resolve-AdmanLocalTarget.ps1:105-109`
**Issue:** The `Win32_UserProfile` lookup uses `Get-CimInstance ... -ErrorAction SilentlyContinue` and then wraps the call in an empty `catch { }`. The `-ErrorAction SilentlyContinue` already suppresses non-terminating errors (e.g., no profile), so the `catch` only fires for terminating errors such as CIM connection failure or an invalid class. An empty catch means the pre-delete `ProfilePath` is silently omitted and the operator never sees that profile capture failed.
**Fix:** Remove the redundant empty catch, or replace it with a warning that logs the exception without failing the gate:

```powershell
catch {
    Write-Warning "Could not capture Win32_UserProfile for '$sidValue': $($_.Exception.Message)"
}
```

### WR-02: Authenticode signing uses an HTTP timestamp server

**File:** `build/Sign-AdmanModule.ps1:90-94`
**Issue:** `Set-AuthenticodeSignature` is called with `-TimestampServer 'http://timestamp.digicert.com'`. HTTP timestamping is standard for Authenticode but is vulnerable to MITM substitution of the timestamp counter-signature. An attacker who can intercept that request could feed a back-dated or bogus timestamp and break signature validity after certificate expiry.
**Fix:** Use the HTTPS endpoint if `Set-AuthenticodeSignature` accepts it in your target environments, or document the trust assumption and pin the expected timestamp server certificate thumbprint in the runbook/CI notes:

```powershell
-TimestampServer 'https://timestamp.digicert.com'
```

If HTTPS is unsupported by the cmdlet in your test matrix, add a code-comment and runbook note explaining the residual MITM risk.

### WR-03: Workflow-level Failure audits duplicate inner verb Failure audits

**Files:** `Public/Start-AdmanUserOnboarding.ps1:159-162`, `Public/Start-AdmanUserOffboarding.ps1:179-182`
**Issue:** When an inner verb such as `New-AdmanUser` or `Disable-AdmanUser` fails, it already writes its own `Failure` outcome audit record through the gate. The workflow catch blocks then write a second `Failure` record for the same logical failure, with a different correlation ID. The audit trail ends up with duplicate Failure entries for a single operation, which complicates forensics and could mislead an operator counting failures.
**Fix:** Either suppress the workflow-level Failure audit when the inner verb has already audited (e.g., inspect `$_.Exception.Message` or restructure so the workflow owns the audit and inner verbs do not), or pass the workflow correlation ID into the inner verbs so both records share a single correlation ID.

### WR-04: Bulk engine no-op detection depends on an undocumented `memberOf` contract

**File:** `Public/Invoke-AdmanBulkAction.ps1:284-296`
**Issue:** The AddGroup/RemoveGroup no-op checks read `$rec.ResolvedTarget.PSObject.Properties['memberOf']` to decide whether a target is already a member. This assumes `Resolve-AdmanTarget` always returns `memberOf` in its default property set. That contract is not visible in the reviewed files; if a future change to `Resolve-AdmanTarget` drops `memberOf` from the default properties, the bulk engine will silently mis-classify every add/remove as a no-op or as not-a-member.
**Fix:** Make the contract explicit. Either have `Resolve-AdmanTarget` document/always return `memberOf`, or have the bulk engine request it explicitly (e.g., call `Resolve-AdmanTarget` with a `-Properties` parameter or re-query `memberOf` after resolution).

### WR-05: Restore fails closed on any tampered audit file, even unrelated ones

**File:** `Private/Workflow/Get-AdmanOffboardingState.ps1:62-65`
**Issue:** `Get-AdmanOffboardingState` verifies the integrity of every audit file it enumerates and throws if **any** file fails, even files that have nothing to do with the requested restore target or time frame. A corrupted or hand-edited old archive file can therefore block all future restores, not just restores depending on that file.
**Fix:** Keep fail-closed behavior for files that actually contain a candidate record, but skip or warn on unrelated corrupted files. At minimum, distinguish "file containing a matching record is tampered" (throw) from "unrelated file is unreadable" (warn and continue).

### WR-06: OUTCOME audit escalation can throw if Event Log write fails

**File:** `Private/Audit/Write-AdmanAudit.ps1:236-240`
**Issue:** In the OUTCOME failure branch, the function sets `$script:AuditDegraded = $true` and calls `Write-AdmanEventLog`. If `Write-AdmanEventLog` itself throws (e.g., the source does not exist and cannot be registered, or the Security log is full), the exception escapes the catch block and propagates to the caller. The design comment and tests state that OUTCOME failures must *not* throw, so this violates the fail-closed/no-rollback contract when the escalation path is broken.
**Fix:** Guard the escalation in its own try/catch so an Event Log failure cannot mask the original OUTCOME audit failure:

```powershell
try {
    $script:AuditDegraded = $true
    Write-AdmanEventLog -EventId 9001 -EntryType Error `
        -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
    Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId - see Event Log."
} catch {
    Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId and Event Log escalation also failed: $($_.Exception.Message)"
}
```

## Info

### IN-01: `Start-Adman` uses `continue` inside a nested switch/while loop

**File:** `Public/Start-Adman.ps1:228, 253`
**Issue:** The CSV/HTML path handlers set `$formatResolved = $true` and then use `continue` inside a `switch` block that is nested in a `while` loop. The current behavior is correct only because `$formatResolved` causes the outer `while` to exit after the `switch` finishes. This is fragile: future refactors could break the intended control flow.
**Fix:** Use `break` to exit the format loop explicitly, or restructure the path prompt into a helper function that returns a result object, eliminating the nested `continue` ambiguity.

### IN-02: Mojibake in comment/help text indicates encoding drift

**Files:** `Public/Add-AdmanGroupMember.ps1:19`, `Public/Reset-AdmanComputerAccount.ps1:13,27`, `Public/Unlock-AdmanUser.ps1:33`
**Issue:** Em-dash characters appear as `â€”` in comment-based help. The code is still ASCII-safe and executes, but the garbled help text degrades operator documentation and may break future help-extraction tooling.
**Fix:** Re-save the affected files as UTF-8 with BOM, or replace the em-dashes with plain ASCII hyphens in the help text.

### IN-03: `transport.order` schema allows invalid transport names

**File:** `config/adman.schema.json:136-140`
**Issue:** The schema defines `transport.order` as an array of unconstrained strings. Values like `"WinRm"` (wrong casing) or arbitrary strings pass validation, even though the runtime only recognizes `WinRM`, `CimWsman`, `CimDcom`, and `Skipped`.
**Fix:** Add an `enum` to the items schema:

```json
"order": {
    "type": "array",
    "items": { "type": "string", "enum": ["WinRM", "CimWsman", "CimDcom", "Skipped"] }
}
```

### IN-04: Test config builder uses `'Skip'` instead of `'Skipped'`

**File:** `tests/Config.Load.Tests.ps1:60`
**Issue:** The helper `New-AdmanTestConfig` sets `transport.order` to `@[... 'Skip']` while the shipped default and runtime recognize `'Skipped'`. The validator does not currently enforce the enum, so the test passes, but it drifts from the canonical value.
**Fix:** Change `'Skip'` to `'Skipped'` in the test helper.

### IN-05: `Start-Adman` accesses config property with inconsistent casing

**File:** `Public/Start-Adman.ps1:59-63`
**Issue:** The banner checks `$script:Config.PSObject.Properties.Name -contains 'Domain'` and then reads `$script:Config.Domain`. The actual config key is lowercase `domain`. PowerShell property access is case-insensitive, so it works, but the inconsistency is confusing and could break if strict case-sensitive comparisons are introduced later.
**Fix:** Use the documented lowercase key consistently: `-contains 'domain'` and `$script:Config.domain`.

---

_Reviewed: 2026-07-23T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
