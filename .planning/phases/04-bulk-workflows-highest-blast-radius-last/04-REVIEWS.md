---
phase: 04
reviewers:
  - codex
reviewed_at: 2026-07-20T02:01:53Z
plans_reviewed:
  - 04-01-PLAN.md
  - 04-02-PLAN.md
  - 04-03-PLAN.md
  - 04-04-PLAN.md
---

# Cross-AI Plan Review — Phase 04

## Codex Review

## Summary

Phase 4 is directionally strong: it correctly treats bulk/workflows as composition over existing single-object verbs and keeps the mutation gate private. The main risks are around confirmation semantics, audit-derived restore state, and assumptions that do not match the current code. Most issues are fixable in the plans before implementation, but I would not execute these plans as-is for a high-blast-radius AD phase.

## Plan 04-01: Config Template Keys + Gated Bulk Engine

### Strengths

- Reuses existing safety primitives instead of adding new AD write paths. The current gate centralizes resolution, policy checks, confirmation, write-ahead audit, and wrapper dispatch in `Private/Safety/Invoke-AdmanMutation.ps1:59`, `Private/Safety/Invoke-AdmanMutation.ps1:160`, `Private/Safety/Invoke-AdmanMutation.ps1:191`, `Private/Safety/Invoke-AdmanMutation.ps1:209`, and `Private/Safety/Invoke-AdmanMutation.ps1:222`.
- Cap enforcement can reuse the existing forward-compatible switch: `Assert-AdmanBulkPolicy -EnforceCap` already throws when count exceeds cap at `Private/Safety/Assert-AdmanBulkPolicy.ps1:29`.
- CSV schema restriction is the right control for `BULK-04`; the plan calls out unknown-header rejection before gate invocation at `.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-01-PLAN.md:126`.

### Concerns

- **HIGH:** The plan says typed-count confirmation runs once for every filtered bulk set via `Confirm-AdmanAction` (`04-01-PLAN.md:25`, `04-01-PLAN.md:174`), but current `Confirm-AdmanAction` only uses typed count when count is at or above `safety.bulkConfirmThreshold`, or when the verb is in `typedCountVerbs` (`Private/Safety/Confirm-AdmanAction.ps1:45`, `Private/Safety/Confirm-AdmanAction.ps1:58`, `Private/Safety/Confirm-AdmanAction.ps1:82`). A two-user bulk disable below threshold would get normal ShouldProcess confirmation, not typed-count confirmation.
- **HIGH:** The plan introduces an outer confirm and then calls `Invoke-AdmanMutation` per item (`04-01-PLAN.md:174`, `04-01-PLAN.md:175`). The gate itself confirms every call (`Private/Safety/Invoke-AdmanMutation.ps1:194`, `Private/Safety/Invoke-AdmanMutation.ps1:200`). Unless the plan explicitly forces inner gate confirmation after the outer typed-count confirmation, operators may see N additional prompts or tests may pass only by suppressing confirmation globally.
- **MEDIUM:** Group bulk actions are filtered only with `Test-AdmanTargetAllowed` in the planned engine (`04-01-PLAN.md:171`), but group-side policy is enforced separately by `Resolve-AdmanGroup` and `Test-AdmanGroupAllowed` inside the gate (`Private/Safety/Invoke-AdmanMutation.ps1:131`, `Private/Safety/Invoke-AdmanMutation.ps1:134`). This means a protected destination group can survive the preview/cap/confirm stage and then fail per item after confirmation.
- **MEDIUM:** The plan says CSV headers are “exactly” the five allowed fields but also says order-independent and unknown headers throw (`04-01-PLAN.md:126`). It should explicitly reject missing required headers too, otherwise a CSV missing `Action` or `Identity` can normalize late or fail inconsistently.

### Suggestions

- Add a bulk-only typed-count path, or extend `Confirm-AdmanAction` with an explicit `-RequireTypedCount` switch.
- After outer bulk confirmation, call inner `Invoke-AdmanMutation` with `-Force:$true` while still allowing inner gate policy/audit to run.
- Resolve and validate `GroupIdentity` once before cap/confirm for `AddGroup` and `RemoveGroup`.
- Make CSV validation reject unknown, duplicate, and missing headers before returning rows.

### Risk Assessment

**HIGH.** The bulk engine is the phase’s highest-blast-radius component, and the current plan’s confirmation behavior does not actually satisfy typed-count-on-bulk for small batches.

## Plan 04-02: Onboarding Workflow

### Strengths

- Good dependency choice: it composes `New-AdmanUser` and `Add-AdmanGroupMember`, both already thin wrappers over the mutation gate (`Public/New-AdmanUser.ps1:179`, `Public/Add-AdmanGroupMember.ps1:61`).
- Baseline group pre-validation is well-placed before user creation (`04-02-PLAN.md:87`), and `Test-AdmanGroupAllowed` checks protected SIDs, deny RIDs, and service-account object classes (`Private/Safety/Test-AdmanGroupAllowed.ps1:42`, `Private/Safety/Test-AdmanGroupAllowed.ps1:55`).

### Concerns

- **HIGH:** The plan builds UPN from `$script:Config.Domain` (`04-02-PLAN.md:86`), but `Domain` is not in the schema/defaults (`config/adman.schema.json:7`, `config/adman.schema.json:21`, `config/adman.defaults.json:45`) and `Initialize-Adman` does not add it (`Public/Initialize-Adman.ps1:47`, `Public/Initialize-Adman.ps1:61`). `Start-Adman` treats Domain as optional display-only (`Public/Start-Adman.ps1:52`).
- **MEDIUM:** The phase says onboarding is “one gated, audited flow,” but the plan calls multiple public verbs, each of which gates and audits independently (`04-02-PLAN.md:88`; `Public/New-AdmanUser.ps1:179`; `Public/Add-AdmanGroupMember.ps1:61`). That may be acceptable composition, but it is not one preview+confirm+audit unless the plan adds an outer workflow gate and forces inner confirmations.
- **LOW:** The plan assumes empty `FirstName`/`LastName` are rejected by mandatory parameters (`04-02-PLAN.md:26`). In PowerShell, mandatory does not reject empty strings for direct callers; existing public verbs use `[ValidateNotNullOrEmpty()]` for this reason (`Public/New-AdmanUser.ps1:64`).

### Suggestions

- Add a non-secret config key for UPN suffix, or derive it from `Get-ADDomain -Server $script:Config.DC` during initialization.
- Add `[ValidateNotNullOrEmpty()]` to `FirstName` and `LastName`.
- Decide explicitly whether onboarding has one outer confirmation or several composed single-verb confirmations; tests should pin that behavior.

### Risk Assessment

**MEDIUM.** The workflow is mostly sound, but the missing domain/UPN source is a concrete implementation blocker.

## Plan 04-03: Offboarding + Restore

### Strengths

- Correctly validates quarantine OU before writes (`04-03-PLAN.md:125`), matching the existing managed-OU destination pattern in `Move-AdmanUser` (`Public/Move-AdmanUser.ps1:57`, `Public/Move-AdmanUser.ps1:66`).
- Extending audit state conditionally is compatible with the current writer’s optional-key pattern for `group` (`Private/Audit/Write-AdmanAudit.ps1:151`).
- Restore re-checks current quarantine location and original OU scope before reversing (`04-03-PLAN.md:174`, `04-03-PLAN.md:176`), which is the right safety posture.

### Concerns

- **HIGH:** Restore state lookup filters audit records with `target contains the identity string` (`04-03-PLAN.md:169`). Audit `target` is a pipe-joined string built from DNs (`Private/Audit/Write-AdmanAudit.ps1:139`), so substring matching can select the wrong user or a stale similarly named target.
- **HIGH:** Restore state lookup does not exclude `whatIf=true` records (`04-03-PLAN.md:169`). The audit writer records `whatIf` on every record (`Private/Audit/Write-AdmanAudit.ps1:143`), and the workflow plan writes offboarding Success with `-WhatIf:$WhatIfPreference` (`04-03-PLAN.md:133`). A dry-run offboarding could become restore state.
- **MEDIUM:** The plan limits audit search to the last 30 days (`04-03-PLAN.md:168`), but the requirement says restore via latest offboarding audit record. A user quarantined longer than 30 days becomes unrestorable by design without that being a stated product decision.
- **MEDIUM:** Group removal uses `$user.memberOf | Where-Object { $_ -notin @($script:ProtectedGroupDns) }` (`04-03-PLAN.md:128`). `ProtectedGroupDns` can contain unresolved SID strings when `Get-ADGroup` fails (`Private/Safety/Get-AdmanProtectedIdentity.ps1:52`, `Private/Safety/Get-AdmanProtectedIdentity.ps1:60`, `Private/Safety/Get-AdmanProtectedIdentity.ps1:69`), so DN-only comparison is not a complete protected-group test.

### Suggestions

- Resolve the user first, then match audit `targets[].dn` or `targets[].sid` exactly.
- Filter restore state to `result='Success'` and `whatIf=false`.
- Remove the 30-day limit or make retention/config behavior explicit.
- Resolve each `memberOf` group and classify protected groups by SID against `$script:ProtectedSIDs`, not only DN string membership.

### Risk Assessment

**HIGH.** Restore correctness depends on audit record selection. Substring matching plus accepting dry-run records is too risky for reversible offboarding.

## Plan 04-04: Menu Integration + Manifest Exports + Phase Exit Gate

### Strengths

- Export plan matches the explicit manifest boundary. The manifest currently uses an explicit `FunctionsToExport` list and excludes `Invoke-AdmanMutation` (`adman.psd1:54`), while the module runtime exports public files only (`adman.psm1:31`, `adman.psm1:43`).
- PromptSpec/parameter drift is already tested generically (`tests/Menu.Tests.ps1:799`), so adding Phase 4 verbs to that contract is a good fit.
- Keeping `Invoke-AdmanMutation` private aligns with the existing gate boundary (`Private/Safety/Invoke-AdmanMutation.ps1:43`; `tests/Module.Manifest.Tests.ps1:51`).

### Concerns

- **MEDIUM:** `Start-Adman` always sends returned data into the output-format prompt after any verb (`Public/Start-Adman.ps1:172`, `Public/Start-Adman.ps1:177`). For offboarding/restore workflows that print checklist/status text, this may create awkward or misleading report-render prompts unless the plan defines useful returned objects or a menu-level skip.
- **LOW:** The exit-gate read list references `pester.config.json` (`04-04-PLAN.md:151`), but the repo has `tests/PesterConfiguration.psd1` instead. The plan has a fallback, but the concrete command should match the repo.
- **LOW:** The no-hard-delete check is scoped to “new Phase 4 source file” (`04-04-PLAN.md:157`). The phase success criteria says `Remove-ADObject` appears nowhere; existing tests only prove no wrapper exists for hard delete (`tests/Safety.NoHardDelete.Tests.ps1:100`), not a full source-tree ban.

### Suggestions

- Add a menu contract for write/workflow verbs: either return structured summary objects that render cleanly, or allow entries to skip the output-format prompt.
- Use `Invoke-Pester -Configuration tests/PesterConfiguration.psd1` if that remains the repo’s test config.
- Add a repo-wide source AST/text guard for `Remove-ADObject` in `Public/` and `Private/`, excluding planning/docs/tests as appropriate.

### Risk Assessment

**MEDIUM.** Export/menu wiring is straightforward, but UX and phase-exit verification need tightening.

## Overall Risk

**HIGH until plan fixes land.** The architecture is good, but Phase 4 touches bulk mutation and restore. The main blockers are confirmation semantics in 04-01 and audit-state correctness in 04-03. Fix those before implementation; the rest are manageable refinements.

---

## Consensus Summary

Only Codex was invoked for this review cycle. The review is source-grounded and cites concrete file:line evidence.

### Agreed Strengths

- Phase 4 correctly composes existing single-object verbs through the existing mutation gate rather than inventing new AD write paths.
- Config/template keys, CSV schema restriction, quarantine OU validation, and manifest export boundary are well-aligned with existing patterns.

### Agreed Concerns

- **HIGH — 04-01 bulk confirmation semantics:** The current `Confirm-AdmanAction` does not guarantee typed-count confirmation for small filtered sets; the plan must either add a bulk-only typed-count path or extend the confirmation helper.
- **HIGH — 04-01 double-confirmation risk:** Without forcing the inner `Invoke-AdmanMutation` calls after outer confirmation, operators may receive per-item prompts.
- **HIGH — 04-02 onboarding UPN source:** `$script:Config.Domain` does not exist in the config schema/defaults; a UPN-suffix source must be added or derived.
- **HIGH — 04-03 restore audit lookup:** Substring matching against the pipe-joined `target` field can select the wrong record, and `whatIf=true` records are not excluded from restore state.
- **MEDIUM — 04-01 group destination policy:** `GroupIdentity` should be resolved/validated before cap/confirm to avoid failing after confirmation.
- **MEDIUM — 04-01 CSV header validation:** Missing required headers (`Action`, `Identity`) should be rejected explicitly, not just unknown headers.
- **MEDIUM — 04-02 single vs. composed confirmations:** The plan should explicitly decide whether onboarding presents one outer confirmation or several, and tests should pin that behavior.
- **MEDIUM — 04-03 audit lookback window:** The 30-day limit should be justified or removed, otherwise long-quarantined accounts become unrestorable.
- **MEDIUM — 04-03 protected-group classification:** DN-only comparison against `ProtectedGroupDns` is incomplete when unresolved SIDs are present; classify by SID.
- **MEDIUM — 04-04 menu output rendering:** Workflow/checklist text output may conflict with the generic output-format prompt in `Start-Adman`; define return objects or a menu skip.
- **LOW — 04-02 empty string validation:** Add `[ValidateNotNullOrEmpty()]` to `FirstName`/`LastName`.
- **LOW — 04-04 test config reference:** Use `tests/PesterConfiguration.psd1` instead of `pester.config.json`.
- **LOW — 04-04 hard-delete guard scope:** Extend the `Remove-ADObject` check repo-wide (source AST/text), not only to new Phase 4 files.

### Divergent Views

None — only one reviewer executed successfully.

## Next Step

Incorporate the findings above into the Phase 4 plans via `/gsd-plan-phase 04 --reviews` before beginning implementation.
