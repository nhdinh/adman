---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
plan: 10
subsystem: safety
tags: [safety, gate, group-remediation, refusal-surface, audit, gap-closure]
gap_closure: true
closes_gaps: [G-02-8, G-02-9, G-02-6]
requirements: [GRP-01, GRP-02, GRP-03, USER-03, COMP-02]
dependency_graph:
  requires:
    - Private/Safety/Invoke-AdmanMutation.ps1 (gate fixed order, D-04 dual-resolution path)
    - Private/Safety/Test-AdmanTargetAllowed.ps1 (member-side check steps a-d)
    - Private/Safety/Test-AdmanGroupAllowed.ps1 (group-side asymmetry contract reference)
    - tests/Safety.GateOrder.Tests.ps1 (BeforeAll pattern, mock setup)
  provides:
    - Test-AdmanTargetAllowed gains optional -Operation parameter (ValidateSet spans all 10 gate verbs verbatim from Invoke-AdmanMutation.ps1:47-49); step (d) recursive protected-membership skipped when Operation='Remove-ADGroupMember' (D-04 remediation asymmetry restored)
    - Invoke-AdmanMutation passes -Operation $Verb unconditionally on every member-side call
    - Group-refusal audit restructured to write one Refused record PER MEMBER with member DN in target field and group DN in group field (G-02-9 forensic completeness)
    - Write-Warning emitted on member-refusal and group-refusal paths so the operator sees the precise reason on screen (G-02-6)
    - 5-test Pester suite (Safety.GroupRemediation.Tests.ps1) proving remediation allowed, Add still strict, member DN in audit, deny-RID on Remove, ValidateSet spans all 10 gate verbs
    - 4-test Pester suite (Safety.RefusalSurface.Tests.ps1) proving warnings carry scope/protected/group reasons and the summary object contract is unchanged
  affects:
    - UAT Test 12 Leg 2 (Remove uat-protected1 from Domain Admins) — now SUCCEEDS (remediation)
    - UAT Test 6 (out-of-scope Disable-AdmanUser) — now surfaces the scope reason on screen via Write-Warning
    - UAT Test 7 (protected-account refusal) — now surfaces the protected-identity reason on screen
    - All group-removal workflows targeting protected-group members (Tier-0 cleanup)
tech_stack:
  added: []
  patterns:
    - Operation-aware member-side check (the verb determines which step runs; mirrors the group-side asymmetry in Test-AdmanGroupAllowed)
    - Per-member audit fan-out on group refusal (one Refused record per resolved member instead of one record for the group)
    - Refusal-surface Write-Warning (operator-visible reason in addition to the audit record; warnings are additive, not a behavior change)
key_files:
  created:
    - tests/Safety.GroupRemediation.Tests.ps1
    - tests/Safety.RefusalSurface.Tests.ps1
  modified:
    - Private/Safety/Test-AdmanTargetAllowed.ps1
    - Private/Safety/Invoke-AdmanMutation.ps1
decisions:
  - "The -Operation ValidateSet on Test-AdmanTargetAllowed spans all 10 gate verbs (copied verbatim from Invoke-AdmanMutation.ps1:47-49) so the call-site can pass -Operation `$Verb unconditionally; the parameter is consulted ONLY for the Remove-ADGroupMember skip and ignored for every other verb (no behavior change for non-Remove verbs)"
  - "Reset-ADComputerPassword is deliberately NOT in the -Operation ValidateSet — it is not a gate verb (the gate refuses it at the ValidateSet on `$Verb)"
  - "The group-refusal audit restructures to per-member records (member DN in target field, group DN in group field) so forensics can tell which member the add was attempted on; the throw message is unchanged"
  - "Write-Warning is emitted AFTER the Write-AdmanAudit call on the member-refusal path and BEFORE the throw on the group-refusal path — the audit record is the authoritative log, the warning is the operator-visible surface"
  - "Test 5 Leg B uses direct gate invocation with Verb='Set-ADUser' rather than Disable-AdmanUser (which routes through Verb='Disable-ADAccount'); the plan's reference to Disable-AdmanUser was inaccurate but the regression-guard intent (ValidateSet accepts Set-ADUser) is preserved"
metrics:
  duration: "~12m"
  completed: 2026-07-16
status: complete
---

# Phase 02 Plan 10: Group Remediation Asymmetry + Refusal Surface (G-02-8 / G-02-9 / G-02-6) Summary

**One-liner:** Restored the D-04 remediation asymmetry by making `Test-AdmanTargetAllowed` operation-aware (skipping step (d) recursive protected-membership on `Remove-ADGroupMember`), restructured the group-refusal audit to name the member DN per record, and added `Write-Warning` on refusal paths so the operator sees the precise reason on screen.

## Objective

Close three related gaps in the gate's group-membership and refusal-surface paths:

- **G-02-8 (major):** The D-04 remediation asymmetry was dead code. The gate ran `Test-AdmanTargetAllowed` on the member for ALL group verbs, and the member-side protected-membership check (step d) was not operation-aware. For `Remove-ADGroupMember` from a protected group, the protected-membership refusal should be skipped (the membership IS the state being remediated). UAT Test 12 Leg 2 showed `Remove-AdmanGroupMember` of `uat-protected1` from Domain Admins refused with 'recursive member of protected group' — remediation could never succeed.
- **G-02-9 (minor):** The group-side Refused audit record for Add-ADGroupMember carried the group DN in both target and group fields; the member DN (who was being added) was absent — forensics could not tell which member the add was attempted on.
- **G-02-6 (minor):** Refusal reasons were not surfaced to the operator. The gate early-return path emitted no Write-Warning carrying the aggregated refusal reasons; the operator saw only `Denied: 1` on screen.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Operation-aware member-side check + per-member group-refusal audit + refusal-surface Write-Warning | 41204d4 | Private/Safety/Test-AdmanTargetAllowed.ps1, Private/Safety/Invoke-AdmanMutation.ps1 |
| 2 | Pester test for group remediation asymmetry + audit member DN (TDD) | d01a991 | tests/Safety.GroupRemediation.Tests.ps1 |
| 3 | Pester test for refusal-surface Write-Warning (TDD) | b184874 | tests/Safety.RefusalSurface.Tests.ps1 |

## Verification Results

**Task 1 automated check (source assertion):**
- `Invoke-AdmanMutation.ps1` contains `Test-AdmanTargetAllowed -Object $t -Operation $Verb`: PASS
- `Invoke-AdmanMutation.ps1` contains `Write-Warning "Refused`: PASS
- `Invoke-AdmanMutation.ps1` contains `foreach ($memberObj in $resolved)`: PASS
- `Test-AdmanTargetAllowed.ps1` contains `[string]$Operation`: PASS
- `Test-AdmanTargetAllowed.ps1` contains `$Operation -ne 'Remove-ADGroupMember'`: PASS

**Task 2 Pester test (Safety.GroupRemediation.Tests.ps1):**
- All 5 tests pass: PASS
  - Test 1: Remove-ADGroupMember of a protected-group member FROM a non-protected group is ALLOWED (step (d) skipped)
  - Test 2: Add-ADGroupMember of a protected-group member TO a non-protected group is REFUSED by step (d) with 'recursive member of protected group'
  - Test 3: Add-ADGroupMember TO a protected group writes per-member Refused audit (member DN in target, group DN in group)
  - Test 4: Remove-ADGroupMember with a deny-listed-RID member is still REFUSED (asymmetry skips ONLY step (d), not step (b))
  - Test 5: -Operation ValidateSet spans all 10 gate verbs (REV-1 regression guard) — New-ADUser and Set-ADUser both reach policy/audit without a ParameterBindingException

**Task 3 Pester test (Safety.RefusalSurface.Tests.ps1):**
- All 4 tests pass: PASS
  - Test 1: out-of-scope target refused -> Write-Warning carries scope reason and target DN
  - Test 2: protected-identity target refused -> Write-Warning carries protected reason and target DN
  - Test 3: group refused (Add to protected group) -> Write-Warning carries group-refusal reason before throw
  - Test 4: summary object still returned (Denied=1, Succeeded=0) after warnings — additive, not a behavior change

**Full unit suite (`Invoke-Pester -Path tests/ -Tag 'Unit'`):**
- 464 passed, 4 failed, 1 container failed (Menu.Tests parse error)
- All 4 failures + Menu.Tests container failure are pre-existing (matches the plan's verification expectation: "no new failures beyond the 4 pre-existing + Menu.Tests parse error")
- No new failures introduced by this plan

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test 5 initial Get-ADObject mock lacked -SearchBase/-SearchScope**
- **Found during:** Task 2 (Safety.GroupRemediation.Tests.ps1)
- **Issue:** The initial Pester mock for `Get-ADObject` did not declare `-SearchBase`/`-SearchScope` parameters, but the gate's New-ADUser uniqueness pre-flight calls `Get-ADObject -Filter "cn -eq '$cnEsc'" -SearchBase $parentDn -SearchScope OneLevel ...`. The mock from `tests/Mocks/ActiveDirectory.psm1` (imported in BeforeAll) also lacks these parameters, so the call threw `A parameter cannot be found that matches parameter name 'SearchBase'` before the ValidateSet could be exercised.
- **Fix:** Removed the `Import-Module tests/Mocks/ActiveDirectory.psm1` from BeforeAll (matching the pattern in `tests/Safety.GateOrder.Tests.ps1` which also does not import it), added global stubs for the AD collaborators, and declared the full parameter set on the Pester mock.
- **Files modified:** tests/Safety.GroupRemediation.Tests.ps1
- **Commit:** d01a991

**2. [Rule 3 - Blocking] Test 3 warning capture lost on throw**
- **Found during:** Task 3 (Safety.RefusalSurface.Tests.ps1)
- **Issue:** The initial Test 3 captured warnings via `3>&1` redirection inside a try/catch. When the gate threw after the Write-Warning, the redirect stream was lost and the warning count was 0.
- **Fix:** Switched to `-WarningVariable +script:capturedWarnings` scoped inside the module invocation, which populates the variable BEFORE the throw propagates. The warnings are then read back out of module scope for assertion.
- **Files modified:** tests/Safety.RefusalSurface.Tests.ps1
- **Commit:** b184874

### Plan Inaccuracy (documented, not a code deviation)

**Test 5 Leg B verb routing:** The plan stated "Disable-AdmanUser (which routes through Verb='Set-ADUser')". In the actual codebase, `Disable-AdmanUser` routes through `Verb='Disable-ADAccount'` (see `Public/Disable-AdmanUser.ps1:42`). `Set-AdmanUserPassword` is the Public verb that routes through `Verb='Set-ADUser'` (see `Public/Set-AdmanUserPassword.ps1:167`), but it has complex password-handling logic that would obscure the ValidateSet regression guard. The test uses direct gate invocation with `Verb='Set-ADUser'` to exercise the ValidateSet cleanly. The regression-guard intent (prove Set-ADUser is in the -Operation ValidateSet and reaches policy/audit) is preserved.

## Threat Mitigations Verified

| Threat ID | Mitigation | Verified By |
|-----------|-----------|-------------|
| T-02-10-01 (Tampering) | Operation-aware skip restores D-04 asymmetry; skip is narrow (deny-RID still applies on Remove) | Test 1 (remediation allowed), Test 4 (deny-RID on Remove still refuses) |
| T-02-10-02 (Repudiation) | Per-member audit record names the member DN in the target field | Test 3 (member DN in target, group DN in group) |
| T-02-10-03 (Information Disclosure) | Write-Warning discloses refusal reason + target DN to operator (accepted; no secret material) | Tests 1-3 of Safety.RefusalSurface.Tests.ps1 |

## Self-Check: PASSED

- FOUND: Private/Safety/Test-AdmanTargetAllowed.ps1 (modified)
- FOUND: Private/Safety/Invoke-AdmanMutation.ps1 (modified)
- FOUND: tests/Safety.GroupRemediation.Tests.ps1 (created)
- FOUND: tests/Safety.RefusalSurface.Tests.ps1 (created)
- FOUND: commit 41204d4 (Task 1)
- FOUND: commit d01a991 (Task 2)
- FOUND: commit b184874 (Task 3)
