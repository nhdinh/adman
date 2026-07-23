---
phase: 04-bulk-workflows-highest-blast-radius-last
verified: 2026-07-20T16:30:00Z
status: passed
score: 22/22 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
behavior_unverified_items: []
human_verification: []
---

# Phase 4: Bulk & Workflows Verification Report

**Phase Goal:** Ship the bulk and workflow verbs (onboarding, offboarding, restore) and wire them into the TUI and module manifest, with all phase exit gates passing.

**Verified:** 2026-07-20T16:30:00Z

**Status:** passed

**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1   | Gated bulk engine normalizes pipeline and CSV input to one record shape and dispatches per item through `Invoke-AdmanMutation` | VERIFIED | `Public/Invoke-AdmanBulkAction.ps1`; `Private/Bulk/ConvertTo-AdmanBulkInput.ps1`; `Private/Bulk/Import-AdmanBulkCsv.ps1`; `tests/Bulk.Engine.Tests.ps1` (13 tests pass) |
| 2   | `bulk.maxCount` cap is enforced only after deny/scope/protected filtering | VERIFIED | `Invoke-AdmanBulkAction.ps1` lines 205-206 call `Assert-AdmanBulkPolicy -Count $allowed.Count -EnforceCap` after `Test-AdmanTargetAllowed`; cap-over test passes |
| 3   | Typed-count confirmation runs once for the filtered set via `Confirm-AdmanAction -RequireTypedCount` | VERIFIED | `Private/Safety/Confirm-AdmanAction.ps1` lines 42-43, 83; `Invoke-AdmanBulkAction.ps1` lines 210-226; tests pass |
| 4   | Per-item gate calls run with `-Force` after outer confirmation | VERIFIED | `Invoke-AdmanBulkAction.ps1` line 280 `Invoke-AdmanMutation ... -Force:$true`; confirmation-not-duplicated test passes |
| 5   | Group destination policy is validated before cap/confirm for AddGroup/RemoveGroup | VERIFIED | `Invoke-AdmanBulkAction.ps1` lines 147-165 resolve/test every distinct group before `Assert-AdmanBulkPolicy` |
| 6   | Per-item execution continues on single-item failure and returns a summary | VERIFIED | `Invoke-AdmanBulkAction.ps1` lines 229-286 try/catch per item with `PerItem` result array; continue-on-failure test passes |
| 7   | No raw `Import-Csv | Set-ADUser` path exists; CSV flows only through gated engine with strict schema | VERIFIED | `Import-AdmanBulkCsv.ps1` allow-lists headers; `tests/Bulk.Csv.Tests.ps1` passes; repo-wide search finds no `Set-ADUser` literal in bulk path |
| 8   | Onboarding workflow composes `New-AdmanUser` and `Add-AdmanGroupMember` under one outer confirmation | VERIFIED | `Public/Start-AdmanUserOnboarding.ps1`; `tests/Workflow.Onboarding.Tests.ps1` (14 tests pass) |
| 9   | Onboarding validates baseline groups before user creation | VERIFIED | `Start-AdmanUserOnboarding.ps1` lines 101-109 call `Test-AdmanGroupAllowed` before confirmation/create |
| 10  | Offboarding workflow disables, strips non-protected groups, moves to quarantine OU, records original OU/groups, and surfaces cleanup checklist only | VERIFIED | `Public/Start-AdmanUserOffboarding.ps1`; `tests/Workflow.Offboarding.Tests.ps1` (tests pass) |
| 11  | Protected-group classification uses resolved SIDs/RIDs/DNs (including unresolved SIDs in `ProtectedGroupDns`) | VERIFIED | `Start-AdmanUserOffboarding.ps1` lines 94-128; protected-group classification test passes |
| 12  | Restore reads latest successful non-dry-run offboarding audit record by exact DN/SID and reverses in groups -> move -> enable-last order | VERIFIED | `Private/Workflow/Get-AdmanOffboardingState.ps1`; `Public/Restore-AdmanQuarantinedUser.ps1`; `tests/Workflow.Restore.Tests.ps1` (tests pass) |
| 13  | Restore validates target is currently in configured quarantine OU before reversing | VERIFIED | `Restore-AdmanQuarantinedUser.ps1` lines 71-76 |
| 14  | Mid-workflow failure stops later steps and writes a Failure audit | VERIFIED | Onboarding/offboarding/restore all have try/catch with `Write-AdmanAudit -Result Failure`; tests for partial group-add, disabled-step throw, and partial restore leave-disabled pass |
| 15  | Menu exposes bulk, onboarding, offboarding, and restore entries dispatching to the same Public verbs seniors call directly | VERIFIED | `Private/Menu/Get-AdmanMenuDefinition.ps1` lines 374-420; `tests/Menu.BulkWorkflow.Tests.ps1` (17 tests pass) |
| 16  | Bulk menu entry is CSV-scoped in v1; search-based bulk remains a direct PowerShell pipeline | VERIFIED | Menu entry `Invoke-AdmanBulkAction` requires `Path`; comment documents search-based bulk as direct-PowerShell path |
| 17  | Onboarding, offboarding, and restore menu entries set `SkipOutputPrompt = $true` | VERIFIED | `Get-AdmanMenuDefinition.ps1` lines 399, 409, 419; `Public/Start-Adman.ps1` lines 174-181 honors the flag |
| 18  | `adman.psd1` `FunctionsToExport` explicitly lists the four new Phase 4 verbs and keeps `Invoke-AdmanMutation` private | VERIFIED | `adman.psd1` line 53; `tests/Module.Manifest.Tests.ps1` passes |
| 19  | No hard-delete verb (`Remove-ADObject`) appears anywhere in `Public/` or `Private/` source | VERIFIED | `tests/Safety.NoHardDelete.Tests.ps1` repo-wide scan passes; direct `Select-String` over `Public/` and `Private/` finds no matches |
| 20  | Existing configs without `domain` or `templates` are silently migrated from shipped defaults | VERIFIED | `Private/Config/Initialize-AdmanConfig.ps1` lines 270-286 seeds missing keys; `tests/Config.Load.Tests.ps1` Phase 4 migration tests pass |
| 21  | Phase 4 files pass recursive PSScriptAnalyzer with project settings | VERIFIED | `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` reports 0 diagnostics |
| 22  | Full unit suite is green | VERIFIED | `Invoke-Pester -Path tests -Tag Unit` reports 678 passed, 0 failed |

**Score:** 22/22 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `Public/Invoke-AdmanBulkAction.ps1` | Generic gated bulk engine | VERIFIED | Exists, substantive, exported, wired to menu, tested |
| `Private/Bulk/Import-AdmanBulkCsv.ps1` | Strict-schema CSV loader | VERIFIED | Exists, substantive, called by bulk engine, tested |
| `Private/Bulk/ConvertTo-AdmanBulkInput.ps1` | Pipeline normalizer | VERIFIED | Exists, substantive, called by bulk engine, tested |
| `Public/Start-AdmanUserOnboarding.ps1` | Onboarding workflow | VERIFIED | Exists, substantive, exported, wired to menu, tested |
| `Public/Start-AdmanUserOffboarding.ps1` | Offboarding workflow | VERIFIED | Exists, substantive, exported, wired to menu, tested |
| `Public/Restore-AdmanQuarantinedUser.ps1` | Restore workflow | VERIFIED | Exists, substantive, exported, wired to menu, tested |
| `Private/Workflow/Get-AdmanOffboardingState.ps1` | Audit-log state reader | VERIFIED | Exists, substantive, called by restore verb, tested |
| `Private/Menu/Get-AdmanMenuDefinition.ps1` | Menu entries for Phase 4 verbs | VERIFIED | Extended with Phase 4 section and SkipOutputPrompt flags |
| `Public/Start-Adman.ps1` | Honors SkipOutputPrompt | VERIFIED | Lines 174-181 skip output-format prompt for workflow entries |
| `adman.psd1` | Exports Phase 4 verbs | VERIFIED | FunctionsToExport lists all four verbs; gate absent |
| `config/adman.schema.json` | Requires domain/templates | VERIFIED | domain and templates in required; onboarding/offboarding sub-schema present |
| `config/adman.defaults.json` | Defaults for domain/templates | VERIFIED | Default domain and template values present |
| `Private/Config/Initialize-AdmanConfig.ps1` | Phase 4 additive migration | VERIFIED | Lines 270-286 seed missing domain/templates from defaults |
| `Private/Safety/Confirm-AdmanAction.ps1` | `-RequireTypedCount` switch | VERIFIED | Lines 42-43, 83 implement the switch |
| `Private/Audit/Write-AdmanAudit.ps1` | Optional OriginalOU/Groups fields | VERIFIED | Lines 49-50, 160-165 conditionally emit keys |
| `tests/Bulk.Engine.Tests.ps1` | Bulk engine unit tests | VERIFIED | Passes |
| `tests/Bulk.Csv.Tests.ps1` | CSV loader unit tests | VERIFIED | Passes |
| `tests/Workflow.Onboarding.Tests.ps1` | Onboarding tests | VERIFIED | Passes |
| `tests/Workflow.Offboarding.Tests.ps1` | Offboarding tests | VERIFIED | Passes |
| `tests/Workflow.Restore.Tests.ps1` | Restore tests | VERIFIED | Passes |
| `tests/Menu.BulkWorkflow.Tests.ps1` | Menu integration tests | VERIFIED | Passes |
| `tests/Module.Manifest.Tests.ps1` | Manifest export contract | VERIFIED | Passes |
| `tests/Safety.NoHardDelete.Tests.ps1` | Repo-wide hard-delete scan | VERIFIED | Passes |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `Get-AdmanMenuDefinition` | `Invoke-AdmanBulkAction` | menu entry Verb field | WIRED | Entry present with CSV-scoped PromptSpec |
| `Get-AdmanMenuDefinition` | `Start-AdmanUserOnboarding` | menu entry Verb field | WIRED | Entry present with FirstName/LastName prompts |
| `Get-AdmanMenuDefinition` | `Start-AdmanUserOffboarding` | menu entry Verb field | WIRED | Entry present with AdIdentity prompt |
| `Get-AdmanMenuDefinition` | `Restore-AdmanQuarantinedUser` | menu entry Verb field | WIRED | Entry present with AdIdentity prompt |
| `Start-Adman` | `SkipOutputPrompt` workflow entries | `$entry.SkipOutputPrompt -eq $true` check then `continue` | WIRED | Lines 174-181 |
| `adman.psd1` | runtime export boundary | `FunctionsToExport` explicit list | WIRED | Four Phase 4 verbs listed; gate absent |
| `Invoke-AdmanBulkAction` | `Invoke-AdmanMutation` | per-item `-Force:$true` call | WIRED | Line 280 |
| `Start-AdmanUserOnboarding` | `New-AdmanUser` / `Add-AdmanGroupMember` | direct function calls with `-Force:$true` | WIRED | Lines 119-127 |
| `Start-AdmanUserOffboarding` | `Disable-AdmanUser` / `Remove-AdmanGroupMember` / `Move-AdmanUser` | direct function calls with `-Force:$true` | WIRED | Lines 140-148 |
| `Restore-AdmanQuarantinedUser` | `Get-AdmanOffboardingState` / `Add-AdmanGroupMember` / `Move-AdmanUser` / `Enable-AdmanUser` | direct function calls with `-Force:$true` | WIRED | Lines 79, 105-113 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `Invoke-AdmanBulkAction` | `$records` from CSV/pipeline | `Import-AdmanBulkCsv` / `ConvertTo-AdmanBulkInput` | Yes — reads real CSV file or pipeline objects | FLOWING |
| `Start-AdmanUserOnboarding` | `$template` from config | `$script:Config.templates.onboarding` | Yes — loaded from `.store/config.json` (with migration fallback) | FLOWING |
| `Start-AdmanUserOffboarding` | `$quarantineOu` from config | `$script:Config.templates.offboarding.quarantineOU` | Yes — loaded from config | FLOWING |
| `Restore-AdmanQuarantinedUser` | `$state` | `Get-AdmanOffboardingState` reads `audit-*.jsonl` files | Yes — parses actual audit records | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full unit suite passes | `Invoke-Pester -Path tests -Tag Unit -PassThru` | 678 passed, 0 failed | PASS |
| Phase 4 focused tests pass | `Invoke-Pester -Path tests/Bulk.*.Tests.ps1,tests/Workflow.*.Tests.ps1,tests/Menu.BulkWorkflow.Tests.ps1,tests/Module.Manifest.Tests.ps1,tests/Safety.NoHardDelete.Tests.ps1 -Tag Unit -PassThru` | 88 passed, 0 failed | PASS |
| Recursive lint clean | `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` | 0 diagnostics | PASS |
| No `Remove-ADObject` in source | `Get-ChildItem Public,Private -Recurse -Filter *.ps1 \| Select-String 'Remove-ADObject'` | 0 matches | PASS |
| No debt markers in Phase 4 files | `Select-String` for TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER | 0 matches | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| FLOW-01 | 04-02-PLAN | Onboarding workflow guides new-user setup as one gated, audited flow | SATISFIED | `Start-AdmanUserOnboarding.ps1` + tests |
| FLOW-02 | 04-03-PLAN | Offboarding disables, strips non-protected groups, moves to quarantine, surfaces cleanup checklist | SATISFIED | `Start-AdmanUserOffboarding.ps1` + tests |
| FLOW-03 | 04-03-PLAN | Offboarding is reversible via restore with recorded groups/original location | SATISFIED | `Restore-AdmanQuarantinedUser.ps1` + `Get-AdmanOffboardingState.ps1` + tests |
| FLOW-04 | 04-02/04-03-PLAN | Workflows compose single-object verbs; mid-workflow failure stops later steps and logs FAIL | SATISFIED | All three workflow verbs + tests |
| BULK-01 | 04-01-PLAN | Gated bulk: search → preview → cap → typed confirm → per-item execution | SATISFIED | `Invoke-AdmanBulkAction.ps1` + tests |
| BULK-02 | 04-01-PLAN | Configurable max-count cap and typed confirmation of count | SATISFIED | `Assert-AdmanBulkPolicy -EnforceCap` + `Confirm-AdmanAction -RequireTypedCount` |
| BULK-03 | 04-01-PLAN | Continue on single-item failure, capture per-item results, cheap idempotency | SATISFIED | Per-item try/catch + no-op skip logic + tests |
| BULK-04 | 04-01-PLAN | No raw `Import-Csv \| Set-ADUser`; CSV flows through gated path with schema validation | SATISFIED | `Import-AdmanBulkCsv.ps1` strict schema + tests |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| None | — | — | — | No debt markers, stubs, or hard-delete literals found in Phase 4 source |

### Human Verification Required

None. All Phase 4 behaviors are exercised by automated unit tests; no visual, real-time, or external-service checks are required.

### Gaps Summary

No gaps found. All Phase 4 success criteria are satisfied, all must-haves are verified, the full unit suite passes, and recursive lint reports zero diagnostics.

---

_Verified: 2026-07-20T16:30:00Z_
_Verifier: Claude (gsd-verifier)_
