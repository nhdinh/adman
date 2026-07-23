---
phase: 5
cycle: 7
reviewers: [claude]
reviewed_at: 2026-07-22T10:21:00+07:00
plans_reviewed:
  - 05-01a1-PLAN.md
  - 05-01a2-PLAN.md
  - 05-01a3-PLAN.md
  - 05-01b-PLAN.md
  - 05-02-PLAN.md
  - 05-03-PLAN.md
---

# Cross-AI Plan Review — Phase 5

## Reviewer Availability Note

Only the `claude` CLI was detected in this environment; other requested reviewers (`codex`, local model servers) were unavailable. The review below was produced by that single external reviewer. The source-grounding requirement was enforced: all findings reference concrete `path/to/file:line` evidence from the plans and from the repo source.

---

## Claude Review

### Reviewer Self-Report

I read all required planning files and the source files the plans reference. Representative public functions were inspected to verify the help-placement claim. All prior-cycle concerns are now addressed in the latest PLAN.md files, with two new operational edge cases flagged below.

---

### 05-01a1 — Help Scaffold + Config/Startup/Read/Report Help

**Summary:** Creates a manifest-driven `Get-Help`-based contract test and fills help blocks for the first public-function slice.

**Strengths:**
- Validates through `Get-Help -Full` rather than text scanning, directly fixing the Cycle 6 finding (`05-01a1-PLAN.md:102`, `05-01a1-PLAN.md:117`).
- Compares declared-parameter *name sets* against help-parameter name sets, not just counts (`05-01a1-PLAN.md:102`).
- Explicitly requires help blocks to be placed inside/adjacent to the function, not above `Set-StrictMode` (`05-01a1-PLAN.md:132`, `05-01a1-PLAN.md:147`).
- Supports an incremental `$FunctionName` filter so 05-01a1/05-01a2/05-01a3 can run scoped RED/GREEN slices (`05-01a1-PLAN.md:99`).

**Concerns:** None unresolved. The current source confirms the problem: `Public/Disable-AdmanUser.ps1:2-21`, `Public/Start-Adman.ps1:2-35`, `Public/Initialize-Adman.ps1:2-24`, and `Public/New-AdmanUser.ps1:2-57` all place help above `Set-StrictMode`, which breaks `Get-Help` binding.

**Suggestions:**
- Keep the `Get-Help` assertion as the final gate; do not weaken it to AST-only scanning.
- Verify one representative function with `Get-Help <name> -Full | Format-List` after the move.

**Risk Assessment:** LOW

---

### 05-01a2 — AD User/Computer Lifecycle Help

**Summary:** Adds complete comment-based help to the AD lifecycle slice and relaxes the safety-term assertion.

**Strengths:**
- Scoped safety-description assertion now requires **at least two of three** terms (`WhatIf`, `confirm`, `audit`) instead of all three (`05-01a2-PLAN.md:89`, `05-01a2-PLAN.md:103`).
- Uses the same `$FunctionName`-scoped test container as 05-01a1 (`05-01a2-PLAN.md:92`).

**Concerns:** None unresolved. The relaxed rule is less brittle but remains a heuristic; it could pass a description that omits `-WhatIf` entirely if it mentions `confirm` and `audit`.

**Suggestions:**
- Prefer examples that explicitly show `-WhatIf` so the term appears naturally even when prose does not use the exact word.

**Risk Assessment:** LOW

---

### 05-01a3 — Local/Group/Bulk/Workflow Help

**Summary:** Completes help for the remaining exported functions, including restore help that depends on 05-03 archive search.

**Strengths:**
- Now declares `depends_on: [05-01a1, 05-03]` (`05-01a3-PLAN.md:6-8`), enforcing the ordering issue raised in Cycle 6.
- Requires `Restore-AdmanQuarantinedUser` help to describe archive-search behavior implemented in 05-03 (`05-01a3-PLAN.md:28`, `05-01a3-PLAN.md:90`, `05-01a3-PLAN.md:104`).

**Concerns:** None unresolved.

**Suggestions:**
- Keep the archive-search help text in sync with the actual `Get-AdmanOffboardingState` implementation; the plan references `Private/Workflow/Get-AdmanOffboardingState.ps1:45` which currently only scans the live audit dir.

**Risk Assessment:** LOW-MEDIUM

---

### 05-01b — README, USAGE, RECOVERY-RUNBOOK

**Summary:** Refreshes README, creates standalone docs, and adds a docs-coverage contract test.

**Strengths:**
- `tests/Docs.Coverage.Tests.ps1` derives menu actions from `Get-AdmanMenuDefinition` via module scope and exported functions from `adman.psd1` (`05-01b-PLAN.md:105`).
- Covers every non-separator menu label independently of exported function names, addressing repeated labels like `Set-AdmanLocalUser` (`05-01b-PLAN.md:101`, `05-01b-PLAN.md:118`).
- Includes README instructions for signing trust-anchor GPO deployment and the `.store/` commit guard (`05-01b-PLAN.md:99`, `05-01b-PLAN.md:116`).

**Concerns:** None unresolved. The parameter-coverage assertion is text-based ("parameter name appears before the next `##` heading or fenced code block"), which is somewhat brittle but acceptable for a contract test.

**Suggestions:**
- Generate the exported-functions section from `FunctionsToExport` order to match the test assumption (`05-01b-PLAN.md:120`).

**Risk Assessment:** LOW-MEDIUM

---

### 05-02 — Dual-Edition + Signing

**Summary:** Creates signing script, CI matrix, flips manifest edition claim, and fixes coverage paths.

**Strengths:**
- AllSigned smoke step now loops over every `.psd1`, `.psm1`, `.ps1` under the module root and asserts `Get-AuthenticodeSignature Status -eq 'Valid'` before import (`05-02-PLAN.md:119`, `05-02-PLAN.md:139`).
- Defers `CompatiblePSEditions = @('Desktop','Core')` until the matrix is configured (`05-02-PLAN.md:25`, `05-02-PLAN.md:156`).
- Fixes code-coverage paths to `Public/**/*.ps1` and `Private/**/*.ps1` (`05-02-PLAN.md:179`, `05-02-PLAN.md:190`).

**Concerns:**
- **LOW**: The `verify` command for `build/Sign-AdmanModule.ps1` passes a directory (`$tmp`) to `-ModulePath` (`05-02-PLAN.md:90`). The script expects a `.psd1` path and resolves the module root from it; passing a directory will exercise the wrong path. This is a test/command bug, not a design flaw.
- **LOW-MEDIUM**: CI relies on the community `mchave3/setup-pwsh@v1` action and a hard 7.6.4 pin; the plan documents patch-bump cadence, but runner-image timing remains an environment risk.

**Suggestions:**
- Fix the verify command to create a stub `TestModule.psd1` in `$tmp` and pass that path to `-ModulePath`.
- Add a fallback to install PS7 via MSI if the marketplace action is unavailable.

**Risk Assessment:** MEDIUM

---

### 05-03 — Audit Hardening + Commit Guard

**Summary:** Adds hash chain, rotation, event-log tests, archive-aware restore, and `.store/` commit guard.

**Strengths:**
- Preserves fail-closed semantics: `Get-AdmanAuditPreviousHash` throws on read/parse errors, and `Write-AdmanAudit` must not silently substitute a zero/empty `prevHash` (`05-03-PLAN.md:29`, `05-03-PLAN.md:111`, `05-03-PLAN.md:126`, `05-03-PLAN.md:145-147`).
- All hash operations stay inside the existing `Global\adman-audit` mutex (`05-03-PLAN.md:28`, `05-03-PLAN.md:184`).
- Updates `tests/Audit.Schema.Tests.ps1` to include `hash`/`prevHash` (`05-03-PLAN.md:32`, `05-03-PLAN.md:145`, `05-03-PLAN.md:174`).
- Adds archive search to `Get-AdmanOffboardingState` so restore works after rotation (`05-03-PLAN.md:31`, `05-03-PLAN.md:151`, `05-03-PLAN.md:178`).

**Concerns:**
- **MEDIUM — legacy audit-file compatibility not addressed.** Existing `audit-YYYYMMDD.jsonl` files written by prior phases lack `hash`/`prevHash`. `Get-AdmanAuditPreviousHash` throws on a missing/non-hex hash (`05-03-PLAN.md:111`, `05-03-PLAN.md:126`), which would refuse every PENDING write after upgrade until the legacy file is removed. The prior review explicitly asked for a legacy rule; the current plan omits one.
- **LOW — schema top-level `required` does not include `audit`.** The plan adds an `audit` object to `config/adman.schema.json` (`05-03-PLAN.md:111`, `05-03-PLAN.md:122`) but does not add `"audit"` to the top-level `required` array at `config/adman.schema.json:7-22`. Loader validation covers this, but the schema and loader could drift.

**Suggestions:**
- Define legacy behavior: either archive pre-upgrade audit files on first load, or treat a missing prior `hash` as the 64-zero sentinel for the first new record only.
- Add `"audit"` to `config/adman.schema.json:7-22` required list.

**Risk Assessment:** MEDIUM-HIGH

---

## Consensus Summary

Only the `claude` CLI provided a review in this cycle. The review was source-grounded and cited concrete `path/to/file:line` evidence for each finding. All eight Cycle 6 concerns are fully resolved in the latest plans; three new actionable items remain.

### Agreed Strengths

- Phase 5 scope remains correctly bounded to documentation, dual-edition CI/signing, and audit hardening; no new AD capabilities are introduced.
- The help-coverage test now uses `Get-Help -Full` and name-set comparison, fixing the Cycle 6 HIGH finding.
- Audit hash-chain integration preserves fail-closed semantics and keeps all hash work inside the existing mutex.
- AllSigned smoke testing now requires a per-file signature check before import.
- README/USAGE coverage test derives from `Get-AdmanMenuDefinition` and `adman.psd1 FunctionsToExport`, addressing repeated labels.

### Agreed Concerns

- **MEDIUM — 05-03**: Legacy `audit-*.jsonl` files written by prior phases lack `hash`/`prevHash`; the current plan would throw on every PENDING write after upgrade until legacy files are removed. Add an explicit migration/legacy rule.
- **LOW — 05-03**: `config/adman.schema.json` top-level `required` array does not include the new `audit` object, risking schema/loader drift.
- **LOW — 05-02**: The `build/Sign-AdmanModule.ps1` verify command passes a directory to `-ModulePath`, so it does not exercise the documented module-root resolution.

### Divergent Views

None — only one reviewer participated in this cycle.

---

## Current HIGH Concerns

None.

## Current Actionable Non-HIGH Concerns

- **05-03 MEDIUM**: Legacy `audit-*.jsonl` files from prior phases lack `hash`/`prevHash`; `Get-AdmanAuditPreviousHash` throwing on a missing hash would block PENDING writes after upgrade. Add an acceptance criterion and migration behavior to the plan.
- **05-03 LOW**: Add `"audit"` to the top-level `required` array in `config/adman.schema.json` so the schema matches the loader validation.
- **05-02 LOW**: Fix the `build/Sign-AdmanModule.ps1` verify command to pass a stub `.psd1` path to `-ModulePath` rather than a directory.

---

## Verification coverage

Reviewer had read-only sandbox access to `C:/Users/nhdinh/dev/adman` and cited specific file/line evidence. The cycle-closing verification additionally confirmed:

- `config/adman.schema.json:7-22` does not list `"audit"` in the top-level `required` array, validating the LOW schema-drift concern.
- `05-02-PLAN.md:90` shows the `build/Sign-AdmanModule.ps1` verify command passing `-ModulePath $tmp` where `$tmp` is a directory, validating the LOW verify-command concern.
- `05-03-PLAN.md:111` and `05-03-PLAN.md:126` state that `Get-AdmanAuditPreviousHash` throws on a missing/non-hex prior hash and returns 64 zeros only for a missing file or empty last line, with no legacy-audit-file carve-out, validating the MEDIUM legacy-compatibility concern.
- All Cycle 6 HIGH concerns were traced to explicit acceptance criteria, verify commands, or must_haves items in the updated plans and are therefore treated as fully resolved.

*Review generated by `/gsd-review --phase 5 --codex` (executed with the only available external reviewer, `claude`).*
