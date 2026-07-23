# Phase 4: Bulk & Workflows (highest blast radius, last) - Context

**Gathered:** 2026-07-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 ships **gated bulk actions and reversible onboarding/offboarding workflows** that compose the proven Phase 0–2 single-object verbs under the same preview+confirm+audit gate. A configurable max-count cap and typed count confirmation bound blast radius (BULK-01/02). CSV ingestion flows only through the gated path with schema validation and the same cap (BULK-04). Onboarding guides new-user setup through a single template (FLOW-01). Offboarding disables, strips non-protected groups, moves to a quarantine OU, and records state for restore (FLOW-02/03). Mid-workflow failure stops later steps for that target and logs FAIL (FLOW-04).

The Phase 0/1/2/3 safety spine (gate, config, audit, menu, resolver, scope/protected checks) is locked and reused unchanged. The decisions below pin down the **bulk public surface, input normalization, onboarding template shape, offboarding quarantine/restore data model, and CSV/idempotency semantics** the researcher and planner need.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Bulk input source & action scope (BULK-01/02/04)

- **D-01:** Phase 4 supports both search-based and CSV bulk input, normalized to one bulk input shape. Both paths produce the same internal object before validation, cap checking, and gate invocation.
- **D-02:** Search-based bulk accepts any `Find-AdmanUser`/`Find-AdmanComputer`/report output. Pipeline input is supported so seniors can chain commands; the menu offers a bulk entry point that uses the same Public verb.
- **D-03:** Bulkable actions in v1: `Disable`, `Enable`, `Move`, and AD group-membership `Add`/`Remove`. **Bulk password reset is out of v1 scope** (high blast radius, hard to make idempotent, not required).
- **D-04:** Public bulk surface is a generic engine: `Invoke-AdmanBulkAction -Action <verb> -InputObject <targets>` (plus `-Path` for CSV ingestion). Not per-action bulk verbs.
- **D-05:** Bulk Move uses a single destination OU supplied via `-TargetPath` for the entire job, not per-row destinations.
- **D-06:** Bulk supports AD users and AD computers where an equivalent single-object verb exists.
- **D-07:** The max-count cap applies after gate filtering. The operator confirms the count of objects that will actually be touched, not the raw input count.

### Area 2 — Onboarding template design (FLOW-01)

- **D-08:** The v1 onboarding template is stored as a non-secret config key (`templates.onboarding`). Portable, diffable, and validated by the existing schema.
- **D-09:** Template fields: target OU (`ParentOuDn`), baseline AD group list (`BaselineGroups`), and a name-derivation pattern string.
- **D-10:** Menu flow prompts for First Name and Last Name only; the default template is applied automatically. (v2 may add template choice.)
- **D-11:** Naming pattern produces `sAMAccountName`; UPN is built as `sAMAccountName@domain`. One pattern string is sufficient.
- **D-12:** sAMAccountName/CN uniqueness pre-flight runs before confirmation, reusing the same logic as `New-AdmanUser`.
- **D-13:** Mid-workflow failure stops later steps for that target and logs FAIL (per FLOW-04). If a baseline group add fails, no subsequent group adds run for that user.
- **D-14:** Generated password is surfaced with the same display-once hygiene as `New-AdmanUser` (Read-Host "Press Enter when recorded" + `[Console]::Clear()` best-effort).
- **D-15:** The operator cannot override the template OU at runtime in v1. The template OU is the authority.
- **D-16:** Public surface: `Start-AdmanUserOnboarding -FirstName -LastName`.
- **D-17:** All baseline groups are validated through `Test-AdmanGroupAllowed` before the workflow starts. Protected groups cannot be baseline groups.
- **D-18:** Onboarding creates the user enabled. The generated password is single-use because `mustChangeAtNextLogon` is on by default.

### Area 3 — Offboarding quarantine & restore (FLOW-02/03)

- **D-19:** The quarantine OU is a single DN stored in config (`templates.offboarding.quarantineOU`).
- **D-20:** Original OU and stripped non-protected groups are recorded in the audit record as structured fields (`OriginalOU`, `Groups`). The audit log is already fail-closed and authoritative; no separate state file is needed.
- **D-21:** Offboarding strips membership from all non-protected groups. Protected-group membership is left intact and recorded.
- **D-22:** Restore is a single Public verb: `Restore-AdmanQuarantinedUser -Identity`. It reads the latest offboarding audit record for that user, re-enables the account, restores the recorded groups, and moves the user back to the original OU.

### Area 4 — CSV schema & resume/idempotency (BULK-03/04)

- **D-23:** CSV uses a fixed schema: `ObjectType`, `Identity`, `Action`, plus optional `TargetPath` (Move) and `GroupIdentity` (group ops). Unknown columns are rejected.
- **D-24:** CSV `Action` values are user-friendly: `Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`. Mapped internally to gate verbs.
- **D-25:** CSV schema validation is strict; unknown/misspelled columns cause the import to fail before any gate invocation.
- **D-26:** v1 bulk has no persisted job state. Bulk returns a per-item result array; operators manually re-run after failures. "Idempotent/resume-safe where cheap" means the engine skips no-op cases (e.g., disabling an already-disabled account) and reports them as success/no-change.

### Claude's Discretion

- **Exact fixed CSV column order** and exact user-friendly action value strings — planner picks the canonical names and documents them.
- **Bulk result object shape:** return a summary object with total/succeeded/failed/denied counts plus a `PerItem` array naming each target and result.
- **Audit record extensions for offboarding:** add `OriginalOU` and `Groups` fields to `Write-AdmanAudit` schema or use the existing `Details`/`Reason` extension pattern. Planner chooses the least-invasive approach that preserves the no-secret-key invariant.
- **Offboarding post-action cleanup checklist** (mailbox/home-dir/GPO) is surfaced as plain text/help output only, not automated.
- **Quarantine OU scope validation:** the configured quarantine OU must pass the managed-OU scope check; planner wires the validation.
- **No-op result reporting:** already-correct state can be reported as `Success` with a `Note` like "already disabled" rather than introducing a new result enum.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value, constraints (PowerShell 5.1 baseline + 7.6 LTS, RSAT prereq, config/credential split, `.store/` gitignored, no hard-delete).
- `.planning/REQUIREMENTS.md` — **Phase 4 owns 8:** `FLOW-01`–`FLOW-04`, `BULK-01`–`BULK-04`. Traceability table is authoritative.
- `.planning/ROADMAP.md` §Phase 4 — Goal, 4 success criteria, suggested 4-plan split.

### Phase 0/1/2/3 artifacts (the spine this phase composes on)
- `.planning/phases/00-foundation-safety-harness/00-CONTEXT.md` — Gate fixed order, write-ahead audit, deny-list, protected-account detection, DPAPI credential, confirmation scaling, bulk cap placeholder.
- `.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md` — `Find-AdmanUser`/`Find-AdmanComputer`, `ConvertTo-AdmanResult` D-03 schema, flat menu + PromptSpec pattern.
- `.planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-CONTEXT.md` — Synthetic pre-create target, dual-resolution group matrix, local gate, password sourcing, per-verb threshold override.
- `.planning/phases/03-remote-computer-operations-isolated/03-CONTEXT.md` — Remote enrichment pattern (not directly used, but shows how Phase 3 stays isolated from workflows).

### Research corpus
- `.planning/research/SUMMARY.md` — 6-phase blast-radius-ordered skeleton.
- `.planning/research/STACK.md` — Dual-edition strategy, CIM-not-WMI, Pester 6, PSScriptAnalyzer 1.25.0.

### Project rules & guardrails
- `.claude/CLAUDE.md` — "What NOT to Use" list, PSScriptAnalyzer rules, hand-rolled menu guidance, dual-edition constraints.
- `PSScriptAnalyzerSettings.psd1` — Lint gate; state-changing functions must declare `SupportsShouldProcess`.

### Existing code that changes (read before planning)
- `Private/Safety/Invoke-AdmanMutation.ps1` — THE GATE; bulk engine invokes it per item.
- `Private/Safety/Confirm-AdmanAction.ps1` — Scaled confirmation engine; typed-count logic reused for bulk.
- `Private/Safety/Assert-AdmanBulkPolicy.ps1` — Reads `bulk.maxCount`; Phase 4 adds `-EnforceCap` invocation.
- `Private/Safety/Test-AdmanGroupAllowed.ps1` — Reused for onboarding baseline-group validation.
- `Private/Safety/Resolve-AdmanCreateTarget.ps1` / `Resolve-AdmanTarget.ps1` — Reused by onboarding create and restore.
- `Private/Menu/Get-AdmanMenuDefinition.ps1` — Adds bulk, onboarding, offboarding, restore menu entries.
- `Private/Menu/Read-AdmanActionParams.ps1` — PromptSpec engine; may need a `Type` for CSV path or template name.
- `Public/New-AdmanUser.ps1` — Reused by onboarding workflow.
- `Public/Add-AdmanGroupMember.ps1`, `Disable-AdmanUser.ps1`, `Move-AdmanUser.ps1`, etc. — Reused by workflows and bulk.
- `config/adman.schema.json` + `config/adman.defaults.json` — Add `templates.onboarding`, `templates.offboarding.quarantineOU`, confirm `bulk.maxCount` default.
- `Private/Audit/Write-AdmanAudit.ps1` — May need `OriginalOU`/`Groups` fields or an extension pattern for offboarding restore state.

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — gains `templates.onboarding`, `templates.offboarding.quarantineOU`.
- `.store/audit/audit-YYYYMMDD.jsonl` — offboarding restore state recorded here.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Invoke-AdmanMutation`** — already accepts arrays, runs the fixed gate order, supports `-WhatIf`, and writes PENDING/Success/Failure audit. The bulk engine calls it once per item.
- **`Confirm-AdmanAction`** — typed-count confirmation and threshold override already implemented; bulk invokes it once for the whole filtered set.
- **`Assert-AdmanBulkPolicy`** — reads `bulk.maxCount` and `safety.bulkConfirmThreshold`; Phase 4 finally passes `-EnforceCap`.
- **`Get-AdmanMenuDefinition` + `Read-AdmanActionParams`** — data-driven menu table and prompt engine absorb the new menu entries without a new menu engine.
- **`New-AdmanUser`** — onboarding workflow reuses the existing create path and display-once password hygiene.
- **`Test-AdmanGroupAllowed`** — onboarding validates baseline groups before the workflow starts.
- **`Find-AdmanUser` / `Find-AdmanComputer` / report verbs** — emit the D-03 schema objects that feed search-based bulk via pipeline.
- **`ConvertTo-AdmanResult`** — fixed-schema mapper; bulk input normalizer can accept these objects directly.

### Established Patterns (mirror these)
- **Public/Private boundary:** bulk and workflow internals are Private; Public verbs are thin prompt-and-dispatch wrappers callable by seniors.
- **One code path, two speeds (MENU-04):** every menu action routes to the same Public verb a senior calls directly.
- **Gate fixed order, single resolver, write-ahead audit:** bulk per-item calls preserve this; workflows compose the existing verbs rather than adding new AD primitives.
- **Config-driven values with schema validation:** new keys must land in `config/adman.schema.json` + `config/adman.defaults.json`.
- **`-Server $script:Config.DC` pinning** on every AD call.
- **`$ErrorActionPreference='Stop'` module-wide;** expected bulk/workflow failures (per-item errors) are caught and recorded, not thrown out of the whole job.
- **Pipeline-friendly where possible:** `Invoke-AdmanBulkAction` accepts `InputObject` from `Find-Adman*` verbs.

### Integration Points
- **Config loader ↔ new keys:** `Initialize-AdmanConfig` validates via `config/adman.schema.json`; add `templates.onboarding` and `templates.offboarding.quarantineOU`.
- **Menu ↔ new verbs:** `Get-AdmanMenuDefinition` adds entries for bulk action, onboard user, offboard user, restore quarantined user.
- **Bulk engine ↔ gate:** `Invoke-AdmanBulkAction` normalizes input, validates CSV/schema, applies cap/confirm, then loops calling `Invoke-AdmanMutation` per item.
- **Onboarding workflow ↔ single-object verbs:** `Start-AdmanUserOnboarding` calls `New-AdmanUser` then `Add-AdmanGroupMember` for each baseline group.
- **Offboarding workflow ↔ single-object verbs:** `Start-AdmanUserOffboarding` calls `Disable-AdmanUser`, captures group list, calls `Remove-AdmanGroupMember` for non-protected groups, then `Move-AdmanUser` to quarantine OU.
- **Restore verb ↔ audit log:** `Restore-AdmanQuarantinedUser` queries the audit log for the latest offboarding record and reverses the steps.
- **Audit writer ↔ offboarding state:** `Write-AdmanAudit` records `OriginalOU` and `Groups` for offboarding, either as new fields or via an extension pattern.

</code_context>

<specifics>
## Specific Ideas

- Normalizing search output and CSV to the same bulk input shape keeps validation and cap logic in one place.
- Applying the cap after gate filtering means the typed confirmation reflects real blast radius, not noise from out-of-scope or protected objects.
- The onboarding template is intentionally non-secret; it contains no credentials and can live in the portable config.
- Offboarding restore state lives in the audit log because it is already synchronous, fail-closed, and authoritative. A separate state file would duplicate the source of truth.
- "Cheap idempotency" means no persisted job state in v1; skip no-ops (already disabled/enabled/in-place) and let the operator re-run the same CSV after fixing failures.
- Bulk group-membership actions reuse the existing dual-resolution gate path; the bulk engine just passes arrays of member identities and one group identity per row.
- CSV user-friendly action values (`Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`) are easier for operators than internal gate verb names.

</specifics>

<deferred>
## Deferred Ideas

- **Full persisted/resume-safe bulk job state** (`BULK-V01`) — v2 scope; needs durable job tracking and partial-failure proven pain before investing.
- **HR-CSV-driven provisioning with multi-column templates** (`FLOW-V02`) — v2 scope; v1 CSV is action-oriented, not full provisioning.
- **Multiple onboarding templates per role** (`FLOW-V01`) — v2 scope; v1 ships a single default template.
- **Bulk password reset** — not required in v1; high blast radius and poor idempotency.
- **Auto-compensation for offboarding partial failures** — v2 scope; v1 logs FAIL and expects manual remediation.
- **Remote live actions** (`RMT-V01`) — v2 scope; Phase 3 kept read-only.
- **Read-side audit for reports/bulk previews** — not required by SAFE-03; revisit if compliance asks.

</deferred>

---

*Phase: 4-Bulk & Workflows (highest blast radius, last)*
*Context gathered: 2026-07-17*
