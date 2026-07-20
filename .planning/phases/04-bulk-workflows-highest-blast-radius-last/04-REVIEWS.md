---
phase: 04
reviewers:
  - codex
reviewed_at: 2026-07-20T09:15:00Z
plans_reviewed:
  - 04-01-PLAN.md
  - 04-02-PLAN.md
  - 04-03-PLAN.md
  - 04-04-PLAN.md
---

# Cross-AI Plan Review — Phase 04

## Codex Review

## Summary

The Phase 4 plans are mostly well-structured and correctly lean on the existing safety spine: public verbs are thin wrappers over `Invoke-AdmanMutation`, the gate already owns resolve → policy → confirmation → audit → AD write, and the plans generally compose those pieces instead of inventing parallel mutation paths. The biggest gaps are around migration and workflow confirmation: 04-01 makes new config keys required without updating the loader's additive-default migration, and 04-03 offboarding forces inner destructive verbs without adding an outer confirmation, which breaks the phase's "one preview+confirm+audit" safety promise.

## 04-01 — Config Template Keys + Gated Bulk Engine

### Strengths

- The bulk engine design fits the existing gate contract. `Invoke-AdmanMutation` already resolves targets, filters denied/protected/out-of-scope objects, confirms, writes PENDING audit, invokes the wrapper, and writes outcome audit in one funnel: `Private/Safety/Invoke-AdmanMutation.ps1:157`, `Private/Safety/Invoke-AdmanMutation.ps1:191`, `Private/Safety/Invoke-AdmanMutation.ps1:194`, `Private/Safety/Invoke-AdmanMutation.ps1:209`.
- Cap-after-filter is supported by the existing `Assert-AdmanBulkPolicy -EnforceCap` switch, which currently only throws when explicitly requested: `Private/Safety/Assert-AdmanBulkPolicy.ps1:29`.
- Group pre-validation is consistent with the existing group-side policy helper, including protected-SID refusal on add and deny-RID checks: `Private/Safety/Test-AdmanGroupAllowed.ps1:42`, `Private/Safety/Test-AdmanGroupAllowed.ps1:55`.

### Concerns

- **HIGH**: The plan says existing configs continue to validate, but it adds top-level `domain` to schema `required` without planning a loader migration. Current validation checks every schema-required top-level key before load completes: `Private/Config/Initialize-AdmanConfig.ps1:89`, `Private/Config/Initialize-AdmanConfig.ps1:281`. The loader only seeds missing transport timeout keys and `DenyList`, not arbitrary new defaults: `Private/Config/Initialize-AdmanConfig.ps1:247`, `Private/Config/Initialize-AdmanConfig.ps1:270`. Existing configs would fail once `domain` becomes required.
- **MEDIUM**: Bulk pre-filtering plus per-item `Invoke-AdmanMutation` means targets are resolved and policy-checked twice. The gate currently guarantees one resolver per gate invocation: `Private/Safety/Invoke-AdmanMutation.ps1:59`. The plan's outer resolve/filter/confirm followed by inner per-item gate calls could make the confirmed blast radius stale if an object moves or changes protected status between the outer confirmation and inner execution.
- **LOW**: `-Force` can bypass typed-count confirmation. Existing `Confirm-AdmanAction` skips all prompts when `-Force` is set: `Private/Safety/Confirm-AdmanAction.ps1:80`. That may be acceptable for senior direct callers, but it weakens the BULK-02 wording unless explicitly documented.

### Suggestions

- Add a Phase 4 migration block in `Initialize-AdmanConfig` to seed missing `domain` and `templates` from defaults before `Test-AdmanConfigValid`.
- In bulk tests, assert behavior when a target changes between outer filter and inner mutation. At minimum, document that the inner gate is authoritative and the summary may reflect per-item revalidation.
- Decide whether `Invoke-AdmanBulkAction -Force` is allowed to bypass typed-count confirmation. If yes, call it out as an intentional senior escape hatch.

### Risk Assessment

**MEDIUM**. The bulk architecture is sound, but config migration is a release blocker for installed configs.

## 04-02 — Onboarding Workflow

### Strengths

- The workflow correctly composes existing public verbs. `New-AdmanUser` already handles generated passwords and display-once hygiene after a successful gate result: `Public/New-AdmanUser.ps1:179`, `Public/New-AdmanUser.ps1:189`.
- Baseline group validation before creation is the right order. The group policy helper already refuses protected add destinations by SID: `Private/Safety/Test-AdmanGroupAllowed.ps1:55`.
- Passing `-Force:$true` to inner verbs after one outer confirmation matches the existing gate behavior, where `-Force` only skips confirmation and does not bypass policy: `Private/Safety/Invoke-AdmanMutation.ps1:33`, `Private/Safety/Confirm-AdmanAction.ps1:80`.

### Concerns

- **MEDIUM**: The plan relies on `NamePattern` but does not specify validation for malformed or overlong generated `sAMAccountName`. `New-AdmanUser` catches length over 20 and wildcards later: `Public/New-AdmanUser.ps1:99`, `Private/Safety/Invoke-AdmanMutation.ps1:83`, but the operator experience would be better if onboarding preflighted this before confirmation.
- **LOW**: Onboarding writes an extra workflow Failure audit only on catch, while inner verbs also write their own Failure audit through the gate: `Private/Safety/Invoke-AdmanMutation.ps1:225`. That is defensible, but tests should assert the correlation/wording is clear enough for operators to distinguish workflow failure from step failure.

### Suggestions

- Add explicit pre-confirm validation for generated `sAMAccountName`: non-empty after formatting, length <= 20, and no wildcard characters.
- Include a test where first group add succeeds and second fails, verifying the workflow failure audit plus no later group calls.

### Risk Assessment

**LOW to MEDIUM**. The plan is aligned with existing primitives; main risk is edge-case identity generation.

## 04-03 — Offboarding + Restore

### Strengths

- Restore state can be safely matched by exact DN/SID because audit records already include `targets[].dn` and `targets[].sid`: `Private/Audit/Write-AdmanAudit.ps1:110`, `Private/Audit/Write-AdmanAudit.ps1:141`.
- The plan respects the current audit schema invariant by adding optional fields only when supplied. Current tests assert exact keys for ordinary records: `tests/Audit.Schema.Tests.ps1:116`, `tests/Audit.Schema.Tests.ps1:128`.
- Protected identity source is already SID/RID-based, which supports the plan's group classification direction: `Private/Safety/Get-AdmanProtectedIdentity.ps1:69`, `Private/Safety/Get-AdmanProtectedIdentity.ps1:70`, `Private/Safety/Get-AdmanProtectedIdentity.ps1:82`.

### Concerns

- **HIGH**: Offboarding has no outer confirmation. The plan calls `Disable-AdmanUser`, `Remove-AdmanGroupMember`, and `Move-AdmanUser` with `-Force:$true`: `.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-03-PLAN.md:141`. Existing `-Force` suppresses the gate confirmation: `Private/Safety/Confirm-AdmanAction.ps1:80`, and `Invoke-AdmanMutation` forwards that force to confirmation: `Private/Safety/Invoke-AdmanMutation.ps1:197`. This means offboarding can execute destructive steps with no confirmation at all unless the caller manually omits nothing, violating the phase goal.
- **MEDIUM**: Restore re-enables the user before restoring groups and moving back: `.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-03-PLAN.md:196`. `Enable-AdmanUser` immediately routes to the mutation gate: `Public/Enable-AdmanUser.ps1:42`. If group restore or move fails afterward, the account is enabled while still partially restored.
- **MEDIUM**: The plan extends `Write-AdmanAudit` with `OriginalOU` and `Groups`, but existing source-hygiene tests scan the writer source for sensitive-name tokens: `tests/Audit.Schema.Tests.ps1:196`, `tests/Audit.Schema.Tests.ps1:211`. The plan mentions avoiding banned tokens, but the new tests must also update exact-key expectations only for offboarding-specific records.

### Suggestions

- Add `Confirm-AdmanAction -Verb 'Start-AdmanUserOffboarding' -Targets @($user)` before any destructive step, then keep inner calls forced.
- Restore in the safer order: add groups, move to original OU, then enable last. If enable fails, the account remains disabled but otherwise restored.
- Add tests proving offboarding confirmation occurs exactly once and that inner verbs are forced only after that confirmation.

### Risk Assessment

**HIGH** until the offboarding confirmation gap is fixed. This is the highest-blast-radius workflow.

## 04-04 — Menu Integration + Manifest Exports

### Strengths

- Exporting the four public verbs fits the explicit manifest boundary. Current manifest uses a fixed `FunctionsToExport` list and keeps `Invoke-AdmanMutation` private: `adman.psd1:50`, `adman.psd1:53`.
- The loader dot-sources public/private files recursively, so new `Private/Bulk` and `Private/Workflow` directories will be loaded without extra module-loader work: `adman.psm1:35`, `adman.psm1:39`.
- Extending the hard-delete guard is appropriate. Existing tests already assert no `Remove-ADObject` wrapper exists: `tests/Safety.NoHardDelete.Tests.ps1:100`.

### Concerns

- **MEDIUM**: The menu plan exposes bulk mainly as a CSV path flow, not a search → bulk workflow. `Start-Adman` dispatches exactly one public verb with prompted params: `Public/Start-Adman.ps1:130`, `Public/Start-Adman.ps1:172`. `Read-AdmanActionParams` only builds a hashtable from prompts: `Private/Menu/Read-AdmanActionParams.ps1:77`, `Private/Menu/Read-AdmanActionParams.ps1:296`. A menu entry with required `Path` does not let a junior admin run "search → preview → bulk action" from the TUI.
- **LOW**: Existing menu entries do not have `SkipOutputPrompt`, so tests should tolerate absent/null on older entries. Current menu object shape has fixed fields only: `Private/Menu/Get-AdmanMenuDefinition.ps1:96`.

### Suggestions

- Either scope the TUI bulk entry explicitly to CSV in v1, or add a guided menu flow that first prompts for target type/search criteria, calls `Find-AdmanUser` or `Find-AdmanComputer`, then pipes the result into `Invoke-AdmanBulkAction`.
- Update menu contract tests to allow optional `SkipOutputPrompt` on old entries and require it only for workflow entries.
- Add a behavioral test proving workflow entries return to the menu without rendering prompts after execution.

### Risk Assessment

**MEDIUM**. Manifest/export wiring is straightforward, but the TUI does not yet satisfy the search-based bulk workflow promised in the phase goal.

## Overall Risk

**MEDIUM-HIGH**. The implementation direction is strong and mostly composes proven primitives, but Phase 4 is the highest blast-radius phase. Fix the offboarding confirmation gap and config migration before execution; clarify the menu's bulk story before calling the phase complete.

---

## Consensus Summary

Only Codex was invoked for this review cycle. The following is a synthesis of its findings.

### Agreed Strengths

- Phase 4 correctly composes existing single-object verbs through the existing `Invoke-AdmanMutation` gate rather than inventing parallel AD write paths.
- Cap-after-filter, group pre-validation, and audit-backed restore state align with the established safety spine.
- Manifest exports and recursive hard-delete guard extension are appropriate for the phase exit gate.

### Agreed Concerns

- **HIGH**: Offboarding workflow lacks an outer confirmation before forced inner destructive verbs. This breaks the phase's preview+confirm+audit promise.
- **HIGH**: Adding `domain` to schema `required` without a loader migration will break existing installed configs.
- **MEDIUM**: The TUI bulk entry is CSV-only and does not expose the promised search → bulk workflow for junior admins.
- **MEDIUM**: Restore enables the account before re-adding groups and moving back to the original OU, risking a partially-restored enabled account.

### Divergent Views

None — only one reviewer was available.

---

*Review generated by Codex CLI for Phase 04 — bulk-workflows-highest-blast-radius-last*
