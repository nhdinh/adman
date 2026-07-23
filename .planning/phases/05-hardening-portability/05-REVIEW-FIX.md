---
phase: 05-hardening-portability
reviewed: 2026-07-23T12:00:00Z
fixed: 6
skipped: 0
findings_in_scope: 6
iteration: 1
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-23T12:00:00Z
**Source review:** `.planning/phases/05-hardening-portability/05-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (0 Critical, 6 Warning, 0 Info)
- Fixed: 6
- Skipped: 0

All Critical and Warning findings from the Phase 05 review were applied. Info findings (IN-01 through IN-05) were out of scope for this fix pass and were not modified.

## Fixed Issues

### WR-01: Empty catch in `Resolve-AdmanLocalTarget` swallows profile-read failures

**Files modified:** `Private/Safety/Resolve-AdmanLocalTarget.ps1`
**Commit:** `69bbe14`
**Applied fix:** Replaced the empty `catch { }` around the `Win32_UserProfile` lookup with a `Write-Warning` that surfaces the CIM/profile-capture failure to the operator instead of silently omitting `ProfilePath`.

### WR-02: Authenticode signing uses an HTTP timestamp server

**Files modified:** `build/Sign-AdmanModule.ps1`
**Commit:** `596ae33`
**Applied fix:** Changed `-TimestampServer` from `http://timestamp.digicert.com` to `https://timestamp.digicert.com` and added a comment documenting the HTTPS preference and the fallback/trust-pinning assumption if HTTPS is rejected in a specific environment.

### WR-03: Workflow-level Failure audits duplicate inner verb Failure audits

**Files modified:** `Public/Start-AdmanUserOnboarding.ps1`, `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** `96915f4`
**Applied fix:** Removed the workflow-level `Write-AdmanAudit -Result 'Failure'` calls from both onboarding and offboarding catch blocks. Inner verbs (`New-AdmanUser`, `Add-AdmanGroupMember`, `Disable-AdmanUser`, `Remove-AdmanGroupMember`, `Move-AdmanUser`) already write their own Failure audit through `Invoke-AdmanMutation`; the workflow-level duplicates were creating a second Failure record with a different correlation ID. Updated comment-based help to reflect that the inner verb owns the Failure audit.

### WR-04: Bulk engine no-op detection depends on an undocumented `memberOf` contract

**Files modified:** `Private/Safety/Resolve-AdmanTarget.ps1`, `Public/Invoke-AdmanBulkAction.ps1`
**Commit:** `fa4ecea`
**Applied fix:** Made the property contract explicit by adding an optional `-Properties` parameter to `Resolve-AdmanTarget` (base set is always returned; requested properties are merged and deduplicated). `Invoke-AdmanBulkAction` now explicitly requests `-Properties @('memberOf')` for `AddGroup`/`RemoveGroup` operations rather than assuming `memberOf` is in the default property set.

### WR-05: Restore fails closed on any tampered audit file, even unrelated ones

**Files modified:** `Private/Workflow/Get-AdmanOffboardingState.ps1`
**Commit:** `53c5125`
**Applied fix:** Restructured the restore scan to read each audit file first, collect candidate records for the target identity, and then run `Get-AdmanAuditIntegrity`. Files that contain a matching offboarding record still fail closed on integrity failure; unrelated files with failed integrity (or that are unreadable) are warned and skipped so a single corrupted archive cannot block all restores.

### WR-06: OUTCOME audit escalation can throw if Event Log write fails

**Files modified:** `Private/Audit/Write-AdmanAudit.ps1`
**Commit:** `ebd884d`
**Applied fix:** Wrapped the OUTCOME-failure escalation path (`$script:AuditDegraded = $true`, `Write-AdmanEventLog`, and the first warning) in its own try/catch. If Event Log escalation itself fails, a second warning is emitted but the exception does not propagate to the caller, preserving the OUTCOME-failure no-throw contract.

## Skipped Issues

None — all in-scope findings were fixed.

## Verification

**Syntax checks:** All modified `.ps1` files were parsed with the PowerShell AST parser; no parse errors were reported.

**Unit tests:** Targeted test execution was attempted but could not complete in this environment because `Import-PowerShellDataFile` is unavailable in the local Windows PowerShell 5.1 installation (`Major 5, Minor 1, Build 26100, Revision 8875`). This cmdlet is normally present in PowerShell 5.0+ and is required by the `adman.psd1` module load path; its absence here is an environment limitation, not a code defect. The modified files are syntactically valid and should be exercised by the following test files when run in a capable environment:
- `tests/Local.Gate.Tests.ps1` (WR-01)
- `tests/Workflow.OffboardingState.Tests.ps1` (WR-05)
- `tests/Bulk.Engine.Tests.ps1` (WR-04)
- `tests/Audit.FailClosed.Tests.ps1` and `tests/Audit.EventLog.Tests.ps1` (WR-06)

---

_Fixed: 2026-07-23T12:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
