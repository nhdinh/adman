---
phase: 5
cycle: 2
reviewers: [codex]
reviewed_at: 2026-07-21T11:10:00Z
plans_reviewed:
  - 05-01a1-PLAN.md
  - 05-01a2-PLAN.md
  - 05-01a3-PLAN.md
  - 05-01b-PLAN.md
  - 05-02-PLAN.md
  - 05-03-PLAN.md
---

# Cross-AI Plan Review — Phase 5

## Codex Review (Cycle 1)

### Overall Assessment

The Phase 5 plan set is strong in intent and mostly well-scoped: documentation, help enforcement, dual-edition CI, signing, and audit hardening match the phase goals. The biggest risks are in 05-03 and 05-02: audit rotation can break quarantine restore, the hash-chain schema change conflicts with existing exact audit-schema tests, and the AllSigned CI design may block unsigned Pester test files.

### 05-01a1 — Help Scaffold + Config/Read Help

**Summary**
Good slice boundary and correctly derives the public surface from `adman.psd1:53`. Actual repo state supports this plan: config/startup/report functions are the main remaining help gap, with several missing `.EXAMPLE` blocks.

**Strengths**
- Uses manifest `FunctionsToExport` as source of truth, matching the static export boundary in `adman.psd1:50-53`.
- Covers zero-parameter functions, which exist at `Public/Start-Adman.ps1:42`, `Public/Get-AdmanStaleReport.ps1:36`, and `Public/Test-AdmanCapability.ps1:32`.
- Targets real current gaps: `Public/Config/*.ps1`, `Start-Adman`, `Initialize-Adman`, and several reports lack `.EXAMPLE`.

**Concerns**
- **MEDIUM:** The proposed help test compares only parameter counts, not parameter-name equality. A function could document the wrong parameter names and still pass if counts match. Exported functions have concrete parameter contracts, e.g. `Public/Config/Set-AdmanConfig.ps1:45`.
- **LOW:** The plan says Task 2a makes the whole help test pass. That is only true because many a2/a3 functions already have examples in the current repo; as a reusable plan shape, it is fragile.

**Suggestions**
- Compare sorted parameter-name sets from `Get-Help -Full` and `Get-Command`, not just counts.
- Add one assertion that whitespace-only description/example text fails.

**Risk Assessment:** LOW-MEDIUM. The approach is right, but the parameter coverage gate should be tightened.

### 05-01a2 — AD Lifecycle Help

**Summary**
Low-risk documentation slice. The target functions are real exports and most already have substantial help, so this is mostly verification and polish.

**Strengths**
- Correctly focuses state-changing functions that use `SupportsShouldProcess`, e.g. `Public/Disable-AdmanUser.ps1:26` and `Public/Move-AdmanUser.ps1:37`.
- Keeps function logic unchanged, which is appropriate for DOC-03.
- Explicitly calls out accurate `-WhatIf`/confirm language.

**Concerns**
- **LOW:** Manual review remains the only guard for misleading safety claims. PSScriptAnalyzer proves `SupportsShouldProcess`, but not that help text accurately describes the mutation gate.

**Suggestions**
- Add a lightweight text check for state-changing help requiring terms like `WhatIf`, `confirm`, and `audit`, while keeping final accuracy as manual review.

**Risk Assessment:** LOW. Scope is narrow and aligned with existing code.

### 05-01a3 — Local/Group/Bulk/Workflow Help

**Summary**
Also a solid documentation slice, with more safety-sensitive help because bulk and restore workflows have operational caveats.

**Strengths**
- Targets real exported workflow and bulk functions from `adman.psd1:53`.
- Correctly requires bulk cap/confirmation language and restore dependence on quarantine audit state.
- Matches current restore implementation, which reads audit state through `Get-AdmanOffboardingState`.

**Concerns**
- **MEDIUM:** Restore help must reflect retention/rotation behavior after 05-03. Current restore state reader searches only top-level `AuditDir` files, not archive folders: `Private/Workflow/Get-AdmanOffboardingState.ps1:45-47`.

**Suggestions**
- Coordinate with 05-03: either update restore code to search archived audit files or document that rotated audit archives must be restored before using `Restore-AdmanQuarantinedUser`.

**Risk Assessment:** LOW-MEDIUM. Documentation is straightforward, but restore behavior depends on audit rotation decisions.

### 05-01b — README, USAGE, Recovery Runbook

**Summary**
Well scoped and necessary: the current README is materially stale, claiming Phase 0 only at `README.md:5` and "no destructive verbs" at `README.md:80`, while the manifest exports lifecycle and workflow verbs.

**Strengths**
- Correctly uses `Get-AdmanMenuDefinition` as the menu source of truth; menu entries are data-driven at `Private/Menu/Get-AdmanMenuDefinition.ps1:105-421`.
- Correctly uses `FunctionsToExport` from `adman.psd1:53` for exported function coverage.
- Includes DPAPI portability and signing trust-anchor guidance, both important operational topics.

**Concerns**
- **MEDIUM:** `Docs.Coverage.Tests.ps1` as described only checks that function names appear in `docs/USAGE.md`, not that each has a code example. DOC-02 specifically requires examples.
- **LOW:** The README must not continue to describe `Start-Adman` as a stub; current stale text is at `README.md:69-72`.

**Suggestions**
- Make docs coverage assert each exported function has a fenced PowerShell example after its heading.
- Assert all non-separator menu labels from `Get-AdmanMenuDefinition` appear with their `PromptSpec` fields, not just labels.

**Risk Assessment:** MEDIUM. The content plan is good, but the coverage test is too weak for the stated requirement.

### 05-02 — Dual Edition + Signing + CI

**Summary**
The right goal, but the CI/signing mechanics need adjustment. The current manifest explicitly says Desktop-only until Phase 5 CI passes (`adman.psd1:18-19`, `adman.psd1:68-72`), so this plan is the right place to update it, but the AllSigned proof as written is likely brittle.

**Strengths**
- Correctly delays `CompatiblePSEditions = @('Desktop','Core')` until a matrix exists.
- Includes signing `.psd1`, `.psm1`, and `.ps1`, which is necessary for module import under AllSigned.
- Runs the existing full Pester configuration, which is tagged Unit at `tests/PesterConfiguration.psd1:15-17`.

**Concerns**
- **HIGH:** The plan excludes `tests/` from signing but then runs Pester under `AllSigned`. Pester executes `.ps1` test files from `tests/PesterConfiguration.psd1:10-12`; unsigned test scripts may be blocked by process execution policy.
- **MEDIUM:** The plan says AllSigned proof is for the core leg only, but the phase success criterion says the tool runs under AllSigned and supports both Windows PowerShell 5.1 and PowerShell 7.6. That leaves the 5.1 AllSigned path less proven.
- **LOW:** `PesterConfiguration.psd1` currently says "on 5.1 use the quick run" at `tests/PesterConfiguration.psd1:6-8`, which conflicts with CI using it in the 5.1 leg.

**Suggestions**
- Separate the AllSigned smoke proof from the Pester run: sign module files, set `AllSigned`, import `./adman.psd1`, run a minimal command, then run tests outside AllSigned; or sign tests too in CI.
- Prove AllSigned import in both `powershell` and `pwsh`.
- Update the stale Pester configuration comment once 5.1 CI uses it.

**Risk Assessment:** MEDIUM-HIGH. The objective is correct, but CI can fail for reasons unrelated to module signing.

### 05-03 — Audit Hardening + Commit Guard

**Summary**
This is the highest-risk plan. It addresses real operational gaps, but it changes audit record schema and file location semantics in ways that conflict with existing tests and restore behavior.

**Strengths**
- Builds on the existing single audit sink in `Private/Audit/Write-AdmanAudit.ps1:37`.
- Preserves the current fail-closed PENDING and OUTCOME escalation branches in `Private/Audit/Write-AdmanAudit.ps1:188-211`.
- Adds config defaults in the right files and a simple hook for `.store/`.

**Concerns**
- **HIGH:** Adding `hash`/`prevHash` will break the existing exact audit-schema test. The current expected key set is fixed at `tests/Audit.Schema.Tests.ps1:55-59`, and the test rejects extra fields at `tests/Audit.Schema.Tests.ps1:126-129`.
- **HIGH:** Rotation can break `Restore-AdmanQuarantinedUser` for older offboarding records. The restore state reader says it searches all audit files with no cutoff, but only enumerates top-level `audit-*.jsonl` in `AuditDir`, not `archive/YYYYMM`: `Private/Workflow/Get-AdmanOffboardingState.ps1:12-13` and `:45-47`.
- **MEDIUM:** The plan conflicts with the stated D-05 detail that `prevHash` is omitted on the first record of a day; the task uses a 64-zero sentinel and always adds `prevHash`.
- **MEDIUM:** The event-log test plan says `Open-AdmanAuditStream` throws on the second OUTCOME call, but `Write-AdmanAudit` opens the stream once per invocation at `Private/Audit/Write-AdmanAudit.ps1:171-181`. If the test only calls `Write-AdmanAudit -Result Success` once, the mock may not exercise the failure.
- **MEDIUM:** Adding required `audit.retentionDays` to the schema can break existing configs unless the loader migrates it. The validator rejects missing top-level required keys at `Private/Config/Initialize-AdmanConfig.ps1:89-93`; current migration only seeds transport/domain/templates at `:255-290`.

**Suggestions**
- Update `tests/Audit.Schema.Tests.ps1` deliberately to include `hash`/`prevHash`, or keep `prevHash` omitted on first record and encode that contract in tests.
- Update `Get-AdmanOffboardingState` to search archive folders recursively, or exclude offboarding restore records from rotation.
- Add an additive config migration for `audit.retentionDays`, similar to the domain/templates migration.
- Fix the OUTCOME failure test to throw on the `Success` invocation's stream open, or call PENDING then Success explicitly.

**Risk Assessment:** HIGH. The audit goals are valid, but this plan can regress restore and existing audit invariants unless those dependencies are handled explicitly.

---

## Codex Review (Cycle 2)

### Summary

Phase 5 plans are materially stronger than Cycle 1. The main Cycle 1 findings are addressed in plan intent: audit schema update, archived audit search, AllSigned smoke separated from unsigned Pester, stronger help/docs coverage, and additive config migration. Remaining risk is mostly in execution details: help placement, CI dependency setup under AllSigned, hash-chain concurrency/canonicalization, and config validation gaps.

### Strengths

- 05-01a1/a2/a3 correctly derive public help coverage from the module export boundary. The manifest has an explicit `FunctionsToExport` list, not wildcard exports, at `adman.psd1:53`, and runtime exports are already tested against the manifest at `tests/Module.Manifest.Tests.ps1:51`.
- The parameter-name equality approach fixes the prior weak "count only" help-test issue. Current exported functions have generated/common parameters such as `WhatIf`/`Confirm` from `SupportsShouldProcess`, for example `Public/Disable-AdmanUser.ps1:25`, so excluding common parameters is the right mechanism.
- 05-01b's menu-doc coverage is anchored to the real menu definition, which is a single source of truth. Non-selectable separators are represented by `Verb = $null` at `Private/Menu/Get-AdmanMenuDefinition.ps1:94`, and real menu entries carry `Label`, `Verb`, and `PromptSpec`, e.g. `Private/Menu/Get-AdmanMenuDefinition.ps1:107`.
- 05-03 addresses the Cycle 1 restore/archive issue directly. The current restore reader only searches top-level `audit-*.jsonl` files at `Private/Workflow/Get-AdmanOffboardingState.ps1:45`, so adding recursive archive search is necessary and well-scoped.
- 05-03's additive migration direction matches existing config-loader patterns. The loader already seeds missing timeout keys from defaults before validation at `Private/Config/Initialize-AdmanConfig.ps1:255` and persists only after validation at `Private/Config/Initialize-AdmanConfig.ps1:303`.

### Concerns

- **HIGH — 05-02: AllSigned smoke may fail because PSFramework is not installed/signed/trusted.** The manifest has an exact `RequiredModules` dependency on `PSFramework` 1.14.457 at `adman.psd1:43`. Existing tests solve this by creating a throwaway PSFramework stub before import, e.g. `tests/Preflight.Tests.ps1:26`. The 05-02 CI summary installs Pester and PSScriptAnalyzer, but not PSFramework. Importing `adman.psd1` in the AllSigned smoke will fail unless CI installs PSFramework or creates/signs an equivalent stub.
- **MEDIUM — 05-01a*: help placement must be explicit or coverage will fail.** Current files place comment-based help above `Set-StrictMode`, not immediately inside/before the function. Example: help block at `Public/Disable-AdmanUser.ps1:2`, `Set-StrictMode` at `Public/Disable-AdmanUser.ps1:23`, function starts at `Public/Disable-AdmanUser.ps1:25`. `Get-Help Disable-AdmanUser -Full` currently shows an empty Description despite the header block. The plan should require help blocks inside the function or immediately adjacent to `function`.
- **MEDIUM — 05-03: `audit.retentionDays` minimum must be enforced in the PowerShell validator, not just JSON schema.** `Test-AdmanConfigValid` reads schema `required` keys at `Private/Config/Initialize-AdmanConfig.ps1:87`, but most type/minimum validation is manual, e.g. `Private/Config/Initialize-AdmanConfig.ps1:135`. Adding `"minimum": 1` to `config/adman.schema.json` alone will not reject `retentionDays = 0`; the validator needs an explicit check.
- **MEDIUM — 05-03: hash-chain correctness depends on doing previous-hash lookup inside the existing mutex.** `Write-AdmanAudit` serializes writes through a mutex and appends after record construction at `Private/Audit/Write-AdmanAudit.ps1:168`. If `Get-AdmanAuditPreviousHash` reads before acquiring that mutex, concurrent writers can compute the same `prevHash` and fork the chain. The plan should state that previous-hash lookup, hash computation, and append all occur inside the same critical section.
- **LOW — 05-03: hash computation needs a canonical input definition.** Current records are `[ordered]` and serialized with `ConvertTo-Json -Compress -Depth 5` at `Private/Audit/Write-AdmanAudit.ps1:140` and `Private/Audit/Write-AdmanAudit.ps1:168`. Once `hash` is added, tests should define whether the hash covers the JSON excluding `hash`, and whether property order is fixed.
- **LOW — 05-02: `.store` CI guard should use tracked/staged paths, not just `Test-Path .store/`.** `.gitignore` already excludes `.store/` at `.gitignore:1`, and `git ls-files .store` returned empty in this checkout, but a local untracked `.store` does exist. A raw `Test-Path .store/` can fail developer-like CI jobs that preserve workspace state. Prefer `git ls-files .store` or `git diff --cached --name-only -- .store`.

### Suggestions

- In 05-02, install `PSFramework -RequiredVersion 1.14.457` in both CI legs, then either sign it for the AllSigned smoke or create a signed CI-only stub before importing `adman.psd1`.
- In 05-01a1, make the help test fail on script-level header comments by validating `Get-Help <command> -Full`, then instruct implementers to place help inside each function block.
- In 05-03, add explicit `Test-AdmanConfigValid` checks for `audit.retentionDays`: audit object exists after migration, value is integer-compatible, value is `>= 1`.
- In 05-03, add a concurrency test for two sequential or simulated concurrent writes proving the second record's `prevHash` equals the first record's `hash`.
- In 05-01b, call private menu discovery through module scope in the docs test, e.g. `& (Get-Module adman) { Get-AdmanMenuDefinition }`, since the function is private.

### Risk Assessment

**Overall risk: MEDIUM.** The phase plan is directionally sound and Cycle 1 issues are mostly resolved at the plan level. The remaining risks are not scope problems; they are implementation traps that can make CI fail or make the audit hash chain weaker than advertised. Fixing the PSFramework/AllSigned setup, help placement rule, validator enforcement, and hash critical-section detail would bring this close to LOW.

---

## Consensus Summary

Both cycles used Codex as the sole reviewer. Cycle 2 confirms that the Cycle 1 findings were largely incorporated into the revised plans. The remaining concerns are implementation-level rather than scope-level.

### Agreed Strengths

- Phase scope is correctly bounded to documentation, dual-edition CI/signing, and audit hardening; no new AD capabilities are introduced.
- Plans correctly use existing sources of truth: `adman.psd1 FunctionsToExport`, `Get-AdmanMenuDefinition`, and the existing audit sink.
- The decision to delay `CompatiblePSEditions = @('Desktop','Core')` until CI proves it is sound.
- README refresh is badly needed and correctly scoped.
- Cycle 1 issues were addressed: parameter-name equality in help tests (05-01a1), archived audit search in restore (05-03), AllSigned smoke separated from unsigned Pester run (05-02), audit schema test updated for hash/prevHash (05-03), additive config migration for audit.retentionDays (05-03).

### Agreed Concerns

- **05-02 HIGH (new in Cycle 2): AllSigned smoke may fail because PSFramework is not installed/signed/trusted.** The manifest requires PSFramework 1.14.457 (`adman.psd1:43`), but 05-02 does not install it in CI. Existing tests use a PSFramework stub (`tests/Preflight.Tests.ps1:26`). The AllSigned smoke must either install/sign PSFramework or use a signed CI stub.
- **05-01a MEDIUM (new in Cycle 2): help placement must be explicit.** Current files place header comments above `Set-StrictMode`, which `Get-Help` does not associate with the function. The plan must require help blocks inside the function or immediately adjacent to `function`.
- **05-03 MEDIUM (new in Cycle 2): `audit.retentionDays` minimum must be enforced in the PowerShell validator, not just JSON schema.** The validator mostly uses manual checks (`Private/Config/Initialize-AdmanConfig.ps1:135`); adding `"minimum": 1` to JSON schema alone will not reject `0`.
- **05-03 MEDIUM (new in Cycle 2): hash-chain correctness depends on previous-hash lookup inside the existing mutex.** If `Get-AdmanAuditPreviousHash` reads before acquiring the mutex, concurrent writers can fork the chain. The plan should state that lookup, hash computation, and append all occur inside the same critical section.

### Resolved from Cycle 1

- **05-03 HIGH resolved:** `tests/Audit.Schema.Tests.ps1` expected key set will include `hash` and `prevHash`.
- **05-03 HIGH resolved:** `Get-AdmanOffboardingState` will search archived audit folders recursively.
- **05-02 MEDIUM-HIGH resolved:** AllSigned smoke is separated from the unsigned Pester run.
- **05-01a/05-01b MEDIUM resolved:** Help/docs coverage tests now compare parameter names and verify fenced examples.
- **05-03 MEDIUM resolved:** Additive config migration for `audit.retentionDays` is included.

### Divergent Views

None — only Codex provided a review in both cycles.
