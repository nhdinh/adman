---
phase: 04
reviewers:
  - codex
reviewed_at: 2026-07-20T09:56:00Z
plans_reviewed:
  - 04-01-PLAN.md
  - 04-02-PLAN.md
  - 04-03-PLAN.md
  - 04-04-PLAN.md
---

# Cross-AI Plan Review — Phase 04

## Codex Review

## Summary

The Phase 4 plans are directionally strong and align with the project’s safety-first architecture: they reuse the private mutation gate, preserve the public-verb menu contract, and put bulk/workflow behavior behind preview, confirmation, cap, and audit. The biggest risks are not conceptual; they are integration details where the plans assume a guarantee the current code does not provide, especially config migration depth, fail-closed restore-state recording, StrictMode-safe menu property access, and onboarding password generation.

## 04-01 — Config Template Keys + Gated Bulk Engine

### Strengths

- Good fit with the existing gate model. `Invoke-AdmanMutation` already resolves, filters, confirms, writes PENDING audit, executes, and writes outcome audit in one path (`Private/Safety/Invoke-AdmanMutation.ps1:64`, `:172`, `:202`, `:229`).
- Cap-after-filter is supported by the existing `Assert-AdmanBulkPolicy -EnforceCap` switch (`Private/Safety/Assert-AdmanBulkPolicy.ps1:16`, `:29`).
- Extending `Confirm-AdmanAction` is the right place for forced typed-count confirmation; today it only types at threshold or configured verb override (`Private/Safety/Confirm-AdmanAction.ps1:57`, `:93`).

### Concerns

- **MEDIUM:** Top-level-only config migration is insufficient for partial existing `templates`. The plan seeds `domain` and `templates` only when the whole top-level key is missing/null, but current loader patterns already show nested additive migration for Phase 3 timeouts (`Private/Config/Initialize-AdmanConfig.ps1:268-281`). A config with `templates = { onboarding = {} }` would survive the proposed top-level check and fail later in workflows.
- **MEDIUM:** The plan says bulk supports `-WhatIf`, but the Task 3 action does not explicitly require `[CmdletBinding(SupportsShouldProcess)]`. Existing write verbs consistently declare it (`Public/New-AdmanUser.ps1:61-63`, `Public/Add-AdmanGroupMember.ps1:38-40`).
- **LOW:** CSV `Action` ownership is ambiguous. The plan requires a public `-Action` parameter and also a CSV `Action` column. Current menu choice handling returns the selected choice as the splatted `Action` value (`Private/Menu/Read-AdmanActionParams.ps1:222-240`), so mixed-action CSV behavior needs to be nailed down.

### Suggestions

- Add nested additive migration for `templates.onboarding.*` and `templates.offboarding.quarantineOU`, not just top-level `templates`.
- Extend `Test-AdmanConfigValid` with explicit type/required checks for `domain` and template fields; current validation is manual, not full JSON Schema validation (`Private/Config/Initialize-AdmanConfig.ps1:91-185`).
- Specify CSV precedence: either CSV `Action` must match `-Action`, or CSV mode does not accept `-Action`.

### Risk Assessment

**MEDIUM.** The architecture is sound, but config migration and CSV/action semantics need tightening before implementation.

## 04-02 — Onboarding Workflow

### Strengths

- Composes the existing single-object verbs rather than duplicating AD writes. `New-AdmanUser` already routes through `Invoke-AdmanMutation` (`Public/New-AdmanUser.ps1:179-180`), and group adds do the same (`Public/Add-AdmanGroupMember.ps1:61-62`).
- The plan correctly adds an outer workflow confirmation and uses `-Force` on inner verbs to avoid prompt fatigue.
- The sAMAccountName preflight is appropriate; the underlying `New-AdmanUser` already enforces length and wildcard safety (`Public/New-AdmanUser.ps1:99-102`, `Private/Safety/Invoke-AdmanMutation.ps1:91-97`).

### Concerns

- **HIGH:** “Generated single-use password” is not guaranteed. The planned call to `New-AdmanUser` omits `-AccountPasswordSource Generate`; current `New-AdmanUser` falls back to `$script:Config.security.passwordSource` (`Public/New-AdmanUser.ps1:104-115`). If the site config is `Prompt`, onboarding will prompt instead of generating.
- **MEDIUM:** Workflow Failure audit is not fail-closed. `Write-AdmanAudit` only throws on PENDING write failure (`Private/Audit/Write-AdmanAudit.ps1:173-190`); outcome writes such as `Failure` degrade and warn (`:192-196`). If the workflow-level failure audit cannot be written, FLOW-04’s “logs FAIL” is not guaranteed.
- **LOW:** `New-AdmanUser` displays the generated password immediately after user creation (`Public/New-AdmanUser.ps1:189-194`), before baseline group additions in the planned workflow. If a later group add fails, the password may already have been shown for a partially onboarded account.

### Suggestions

- Call `New-AdmanUser ... -AccountPasswordSource Generate` from onboarding.
- Consider a workflow-level PENDING audit before create if FLOW-04 requires guaranteed workflow-level failure/success records.
- Make tests cover config `security.passwordSource = Prompt` to prove onboarding still generates.

### Risk Assessment

**MEDIUM.** Mostly solid, but the password-source bug directly contradicts FLOW-01/D-18.

## 04-03 — Offboarding + Restore

### Strengths

- The restore-state design correctly uses audit `targets[].dn` / `targets[].sid`; current audit records already emit structured target details (`Private/Audit/Write-AdmanAudit.ps1:109-114`, `:134-142`).
- Restore enabling last is a good safety choice; existing public verbs can compose that order through the gate.
- Protected-group classification by SID is the right direction. Protected identity state currently includes `$script:ProtectedGroupDns`, `$script:ProtectedSIDs`, and `$script:DenyRids` (`Private/Safety/Get-AdmanProtectedIdentity.ps1:69-82`).

### Concerns

- **HIGH:** Restore state is recorded too late and not fail-closed. The plan writes `OriginalOU`/`Groups` only in the final Success audit after disable/group removals/move. But `Write-AdmanAudit` fail-closes only for PENDING (`Private/Audit/Write-AdmanAudit.ps1:173-190`); Success write failure only degrades (`:192-196`). Result: the account can be fully offboarded with no restore metadata.
- **MEDIUM:** Workflow Failure audit has the same guarantee gap. A `Result='Failure'` write is an outcome write, not a PENDING reservation, so it can fail without throwing (`Private/Audit/Write-AdmanAudit.ps1:192-196`).
- **MEDIUM:** Parent OU extraction is underspecified. “Strip the first RDN” can break on escaped commas in CN values. Existing code normalizes DNs (`Public/Move-AdmanUser.ps1:57-68`) but does not provide a parent-DN parser.

### Suggestions

- Write a workflow PENDING audit containing `OriginalOU` and `Groups` before any destructive step, then write Success/Failure outcome after. Restore should read the latest completed Success, but the PENDING record prevents total state loss.
- Add a small DN parent helper that handles escaped separators, and use it in offboarding, restore, and bulk move no-op detection.
- Add tests for audit outcome write failure during offboarding.

### Risk Assessment

**HIGH.** The core reversible-offboarding promise depends on restore metadata, and the current proposed write timing can lose it.

## 04-04 — Menu Integration + Manifest Exports + Exit Gate

### Strengths

- Manifest export update matches the existing explicit export boundary (`adman.psd1:50-53`).
- The menu plan respects the existing `PromptSpec` to parameter-name contract, which is already tested (`tests/Menu.Tests.ps1:799-823`).
- Skipping generic output prompts for workflow verbs is the right UX fix; current `Start-Adman` always renders output-format choices after any verb (`Public/Start-Adman.ps1:172-188`).

### Concerns

- **HIGH:** `SkipOutputPrompt` access must be StrictMode-safe. `Start-Adman` has `Set-StrictMode -Version Latest` (`Public/Start-Adman.ps1:37`), and existing menu entries only have the five current fields (`Private/Menu/Get-AdmanMenuDefinition.ps1:96-102`, `:107-115`). Direct `$entry.SkipOutputPrompt` on old entries can throw if the property is absent.
- **MEDIUM:** The repo-wide hard-delete literal guard will fail on current source unless comments are rewritten. `Remove-ADObject` appears in existing Private source comments (`Private/AD/Adman.AD.Write.ps1:15`, `Private/Safety/Invoke-AdmanMutation.ps1:20`). A literal scan over all `Public/` and `Private/` needs either comment cleanup or AST command-name scanning.
- **LOW:** Bulk TUI is intentionally CSV-only, but the phase goal says search → preview → bulk. The plan explains why search-based bulk remains direct PowerShell, which is acceptable, but it should be reflected clearly in docs and UAT.

### Suggestions

- Implement skip as: check `PSObject.Properties.Name -contains 'SkipOutputPrompt'` before reading it.
- Prefer AST command scanning for forbidden hard-delete calls, plus optional comment cleanup if the product requirement truly means the literal must appear nowhere.
- Add a menu test for old entries without `SkipOutputPrompt` under StrictMode.

### Risk Assessment

**MEDIUM.** Good integration plan, but StrictMode property access and the hard-delete guard can break the exit gate.

## Overall Risk

**MEDIUM-HIGH.** The phase plan is well structured and mostly composes the right existing primitives. The main issue is that the most important safety guarantee, reversible offboarding, depends on restore metadata written only after destructive steps and through a non-fail-closed outcome audit path. Fix that before execution. The other issues are implementation-contract gaps that are straightforward to address in the plans.

---

## Consensus Summary

Only Codex was invoked for this review cycle. The findings below are therefore the consensus view for this cycle.

### Agreed Strengths

- Plans correctly reuse the existing `Invoke-AdmanMutation` gate and compose existing Public verbs rather than introducing new AD primitives.
- Bulk engine design follows the locked decisions: cap after filtering, typed-count confirmation, per-item continue-on-failure.
- Menu integration respects the existing PromptSpec-to-parameter contract and adds `SkipOutputPrompt` for workflow UX.

### Agreed Concerns

- **HIGH (04-03):** Offboarding restore metadata (`OriginalOU`/`Groups`) is written only in the final Success audit, which is not fail-closed. A PENDING workflow audit with restore state should be written before any destructive step.
- **HIGH (04-02):** Onboarding does not explicitly force `-AccountPasswordSource Generate`, so a site config of `Prompt` would break the “generated single-use password” requirement.
- **HIGH (04-04):** `SkipOutputPrompt` property access in `Start-Adman` must be StrictMode-safe because existing menu entries lack the property.
- **MEDIUM (04-01):** Config migration is top-level only; partial existing `templates` objects can slip through and fail later.
- **MEDIUM (04-03):** Workflow Failure audit is an outcome write, not fail-closed.
- **MEDIUM (04-03):** Parent-OU extraction is underspecified and can break on escaped commas.
- **MEDIUM (04-04):** Repo-wide literal scan for `Remove-ADObject` will flag existing comments; AST command scanning or comment cleanup is needed.

### Divergent Views

None — only one reviewer was available.

---

*Review generated by Codex CLI for Phase 04 — bulk-workflows-highest-blast-radius-last*
