---
phase: 5
cycle: 4
reviewers: [codex]
reviewed_at: 2026-07-22T02:31:45.743Z
plans_reviewed:
  - 05-01a1-PLAN.md
  - 05-01a2-PLAN.md
  - 05-01a3-PLAN.md
  - 05-01b-PLAN.md
  - 05-02-PLAN.md
  - 05-03-PLAN.md
---

# Cross-AI Plan Review — Phase 5

## Codex Review

### Summary

Phase 5 is directionally strong: it targets the right operational-readiness work without adding AD capability scope. The best parts are the manifest-derived docs/help gates, dual-edition CI proof before changing `CompatiblePSEditions`, and audit hardening tied back to restore workflows. The main problems are executable-plan consistency: some global tests are expected to pass before all globally-covered functions are fixed, one docs test calls a private function as if it were exported, and the audit integrity verifier needs to prove each record’s own hash, not only the link to the next record.

### 05-01a1: Help Scaffold + Read/Report Help

**Strengths**

- Correctly derives help coverage from `FunctionsToExport`, which is the real public contract: [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:53).
- Correctly identifies existing help-placement risk. Current files place help above `Set-StrictMode`, not adjacent to the function, so `Get-Help` will not associate it reliably: [Public/Disable-AdmanUser.ps1](C:/Users/nhdinh/dev/adman/Public/Disable-AdmanUser.ps1:2), [Public/Disable-AdmanUser.ps1](C:/Users/nhdinh/dev/adman/Public/Disable-AdmanUser.ps1:23), [Public/Disable-AdmanUser.ps1](C:/Users/nhdinh/dev/adman/Public/Disable-AdmanUser.ps1:25).

**Concerns**

- **HIGH:** The plan’s test is global, but Task 2a acceptance expects `Invoke-Pester` to exit with 0 failures before 05-01a2/05-01a3 complete. Since the manifest exports lifecycle, local, group, bulk, and workflow functions too, the test cannot pass after only config/startup/read/report help is fixed: [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:53).
- **MEDIUM:** Existing public write functions omit `.PARAMETER Force` despite declaring it, so the first global RED will include categories outside this plan: [Public/Disable-AdmanUser.ps1](C:/Users/nhdinh/dev/adman/Public/Disable-AdmanUser.ps1:27).

**Suggestions**

- Split the test into two modes: a global contract that is allowed to stay red until 05-01a3, plus category-scoped assertions for each slice.
- Change 05-01a1 acceptance from “0 failures” to “0 failures for the 01a1 command subset; known failures remain for 01a2/01a3.”

**Risk Assessment: MEDIUM**

The implementation goal is good, but the acceptance criteria are internally inconsistent and could block wave completion.

### 05-01a2: AD Lifecycle Help

**Strengths**

- Targets the correct exported AD lifecycle verbs from the manifest: [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:53).
- Safety-language requirement is appropriate for gate-routed write verbs. Current write help already describes the gate/audit path, so this is polishing rather than inventing new behavior: [Public/Disable-AdmanUser.ps1](C:/Users/nhdinh/dev/adman/Public/Disable-AdmanUser.ps1:6).

**Concerns**

- **HIGH:** The plan says to extend `tests/Help.Coverage.Tests.ps1`, but does not list that file in `files_modified`. Since 05-01a2 and 05-01a3 are both wave 2, this creates a hidden cross-plan conflict.
- **MEDIUM:** If 05-01a2 adds a global SupportsShouldProcess description assertion, it may fail on 05-01a3 functions before that sibling plan has run.

**Suggestions**

- Make 05-01a2 depend on 05-01a3 for the global SupportsShouldProcess assertion, or move that assertion into 05-01a1 as a known-red global test.
- Add `tests/Help.Coverage.Tests.ps1` to `files_modified` if this plan edits it.

**Risk Assessment: MEDIUM**

Low functional risk, but medium execution risk from parallel test edits and global assertions.

### 05-01a3: Local/Group/Bulk/Workflow Help

**Strengths**

- Covers the remaining exported write surface, including bulk/workflow verbs: [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:53).
- Correctly calls out restore-state documentation, which matters because restore reads audit records: [Public/Restore-AdmanQuarantinedUser.ps1](C:/Users/nhdinh/dev/adman/Public/Restore-AdmanQuarantinedUser.ps1:88).

**Concerns**

- **MEDIUM:** Restore help is required to describe archive search behavior implemented in 05-03, but this plan depends only on 05-01a1. Wave ordering may cover it, but explicit `depends_on: 05-03` would better reflect the code dependency.
- **LOW:** Bulk examples should avoid live-looking OU paths. Current example uses `OU=Leavers,OU=Managed,DC=contoso,DC=local`, which is a placeholder but can still look deployable: [Public/Invoke-AdmanBulkAction.ps1](C:/Users/nhdinh/dev/adman/Public/Invoke-AdmanBulkAction.ps1:31).

**Suggestions**

- Add explicit dependency on 05-03, or phrase restore archive help as “after Phase 5 audit rotation is installed.”
- Standardize examples on obviously fake `contoso.local` values and no realistic secrets.

**Risk Assessment: LOW-MEDIUM**

The slice is straightforward, with only coordination risk around 05-03 behavior.

### 05-01b: README, Usage, Recovery Runbook

**Strengths**

- Accurately targets stale README content. The current README still says Phase 0 only and `Start-Adman` is a stub: [README.md](C:/Users/nhdinh/dev/adman/README.md:5), [README.md](C:/Users/nhdinh/dev/adman/README.md:71).
- Good source-of-truth choices: menu docs from `Get-AdmanMenuDefinition`, exported function docs from `adman.psd1`.

**Concerns**

- **HIGH:** `Get-AdmanMenuDefinition` is private, and the plan’s docs test says to import the manifest and call it. The module exports Public files only: [adman.psm1](C:/Users/nhdinh/dev/adman/adman.psm1:48). Existing tests dot-source the private menu file before calling it: [tests/Menu.Tests.ps1](C:/Users/nhdinh/dev/adman/tests/Menu.Tests.ps1:115).
- **MEDIUM:** The docs coverage test requirement “every PromptSpec field represented” may be brittle unless it serializes menu entries deterministically. PromptSpec has optional fields like `Type`, `Choices`, and `Kind`: [Private/Menu/Get-AdmanMenuDefinition.ps1](C:/Users/nhdinh/dev/adman/Private/Menu/Get-AdmanMenuDefinition.ps1:18).

**Suggestions**

- In `tests/Docs.Coverage.Tests.ps1`, dot-source `Private/Menu/Get-AdmanMenuDefinition.ps1` like `tests/Menu.Tests.ps1` does.
- Generate or embed a normalized markdown table from the menu definition to reduce drift and test fragility.

**Risk Assessment: MEDIUM**

The docs goals are solid, but the planned test will fail unless it handles private function visibility.

### 05-02: Dual Edition + Signing

**Strengths**

- Correctly keeps `CompatiblePSEditions` Desktop-only until CI proof exists: [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:37).
- Correctly updates stale Pester config comments; current file says 5.1 should use the quick run: [tests/PesterConfiguration.psd1](C:/Users/nhdinh/dev/adman/tests/PesterConfiguration.psd1:8).
- Good `.store` CI scan choice. The repo can have ignored local `.store/` present without it being tracked: `.gitignore` ignores it at [.gitignore](C:/Users/nhdinh/dev/adman/.gitignore:2).

**Concerns**

- **MEDIUM:** `build/Sign-AdmanModule.ps1` excludes tests, but the full Pester configuration includes code coverage over `Public/*.ps1` and `Private/*.ps1`: [tests/PesterConfiguration.psd1](C:/Users/nhdinh/dev/adman/tests/PesterConfiguration.psd1:21). Reverting execution policy before Pester is correct and should be kept non-negotiable.
- **LOW:** The workflow pins `7.6.4`. That is good for reproducibility, but the plan should say how/when the patch pin is updated.

**Suggestions**

- Add a CI syntax validation step for the workflow if available, or at least make the YAML shell selection explicit per step.
- Add a short note that PS 7.6 patch bumps are maintenance changes, not feature work.

**Risk Assessment: MEDIUM**

CI/signing has natural environment risk, but the plan is mostly well-scoped and technically coherent.

### 05-03: Audit Hardening + Commit Guard

**Strengths**

- Correctly integrates with the existing mutex-protected audit writer. Current append path already holds the mutex across path selection, record creation, stream open, write, and flush: [Private/Audit/Write-AdmanAudit.ps1](C:/Users/nhdinh/dev/adman/Private/Audit/Write-AdmanAudit.ps1:59), [Private/Audit/Write-AdmanAudit.ps1](C:/Users/nhdinh/dev/adman/Private/Audit/Write-AdmanAudit.ps1:168).
- Good migration plan: existing config validation is schema-required-key driven, so seeding `audit.retentionDays` before validation is necessary: [Private/Config/Initialize-AdmanConfig.ps1](C:/Users/nhdinh/dev/adman/Private/Config/Initialize-AdmanConfig.ps1:116).
- Correctly extends restore lookup; current implementation only searches top-level `audit-*.jsonl`, not archives: [Private/Workflow/Get-AdmanOffboardingState.ps1](C:/Users/nhdinh/dev/adman/Private/Workflow/Get-AdmanOffboardingState.ps1:45).

**Concerns**

- **HIGH:** The integrity plan verifies `prevHash` links, but does not clearly verify that each record’s own `hash` matches that record’s current canonical bytes. A tamper of the last record would not be detected by a “next record prevHash” check. The current writer serializes one full JSON record per line, so the verifier should check each line’s self-hash directly: [Private/Audit/Write-AdmanAudit.ps1](C:/Users/nhdinh/dev/adman/Private/Audit/Write-AdmanAudit.ps1:168).
- **MEDIUM:** The plan text is inconsistent about canonical JSON: one section says exclude `hash` and `prevHash`; another says exclude only `hash`. Pick one invariant. Best invariant: `hash = SHA256(record excluding hash)`, which includes `prevHash`, and verifier checks both `record.hash` and chain linkage.
- **LOW:** Existing schema tests enforce an exact key set and must be updated carefully. Current expected D-03 keys exclude `hash` and `prevHash`: [tests/Audit.Schema.Tests.ps1](C:/Users/nhdinh/dev/adman/tests/Audit.Schema.Tests.ps1:55).

**Suggestions**

- Define two explicit verifier checks:
  - `record.hash == SHA256(canonical(record without hash))`
  - `record.prevHash == previousRecord.hash`, with zero sentinel on first record
- Add a test that tampers only the final line and expects `Valid = $false`.
- Make archive search deterministic by sorting live and archived audit files before scanning.

**Risk Assessment: HIGH**

This is the highest-risk plan because audit tamper-evidence is a core safety claim. The plan is close, but the verifier must detect last-record tampering.

### Overall Suggestions

- Fix the help-plan dependency model before execution: global contract tests should be either known-red until all slices finish or category-scoped per slice.
- Make private-function test access explicit anywhere tests use `Get-AdmanMenuDefinition`.
- Strengthen audit integrity semantics and tests before implementation.
- Keep phase scope as-is. Do not add AD features in Phase 5.

### Overall Risk Assessment: MEDIUM

The phase goals are achievable and well-aligned with operational readiness. Risk is not from scope creep; it is from a few plan mechanics that would cause false failures or weaker-than-claimed audit verification. The audit verifier issue should be fixed before implementation.

---

## Consensus Summary

Only Codex was invoked for this cycle. Its findings stand as the consensus.

### Agreed Strengths

- Phase 5 scope is correctly bounded to documentation, dual-edition CI/signing, and audit hardening; no new AD capabilities are introduced.
- Plans correctly use existing sources of truth: `adman.psd1 FunctionsToExport`, `Get-AdmanMenuDefinition`, and the existing audit sink.
- The decision to delay `CompatiblePSEditions = @('Desktop','Core')` until CI proves it is sound.
- README refresh is badly needed and correctly scoped.
- Audit hardening correctly preserves the existing fail-closed writer and extends it with hash chain, rotation, and archive-aware restore.

### Agreed Concerns

- **HIGH — 05-01a1:** Global help-coverage test is expected to pass in Task 2a before 05-01a2/05-01a3 have fixed the rest of the exported surface. Acceptance criteria should allow the test to remain red until all help slices complete, or the test should be category-scoped per slice.
- **HIGH — 05-01a2:** The plan edits `tests/Help.Coverage.Tests.ps1` but does not list it in `files_modified`, creating a hidden cross-plan conflict with 05-01a3.
- **HIGH — 05-01b:** `tests/Docs.Coverage.Tests.ps1` is planned to call `Get-AdmanMenuDefinition` after a plain manifest import, but the function is private. The test must dot-source the private file or access it through module scope.
- **HIGH — 05-03:** `Get-AdmanAuditIntegrity` must verify each record’s own `hash` against the canonical record bytes, not only the `prevHash` chain. Otherwise tampering the last record of the day goes undetected.
- **MEDIUM — 05-01a2:** A global SupportsShouldProcess description assertion added here could fail on 05-01a3 functions before that sibling plan runs. Coordinate the assertion scope or dependency ordering.
- **MEDIUM — 05-01a3:** Restore help depends on archive-search behavior implemented in 05-03, but `depends_on` only lists 05-01a1. Add 05-03 to the dependency list or qualify the help text.
- **MEDIUM — 05-01b:** Requiring every PromptSpec field to be represented in the docs test may be brittle because PromptSpec has optional fields (`Type`, `Choices`, `Kind`). Define a deterministic serialization rule or relax the assertion.
- **MEDIUM — 05-03:** The plan text gives two different rules for canonical JSON used in hash computation (exclude `hash` only vs. exclude `hash` and `prevHash`). Pick one invariant and use a shared helper for writer and verifier.
- **LOW — 05-01a3:** Bulk/workflow help examples should use obviously fake placeholders; the current `OU=Leavers,OU=Managed,DC=contoso,DC=local` example can look deployable.
- **LOW — 05-02:** The CI workflow pins PowerShell 7.6.4 but does not document the update cadence for patch bumps.

### Divergent Views

None — only Codex provided a review in this cycle.
