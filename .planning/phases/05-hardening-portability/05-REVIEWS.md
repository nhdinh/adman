---
phase: 5
cycle: 5
reviewers: [codex]
reviewed_at: 2026-07-22T07:00:00Z
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

## Summary

Overall, the six Phase 5 plans are coherent and mostly well-scoped: they harden the already-implemented functional spine rather than adding AD capability. The strongest parts are the incremental help slices, the manifest/menu-driven docs coverage, and the audit hardening plan. The main risks are around CI/AllSigned proving too little or failing for dependency reasons, documentation tests not proving parameter coverage, and audit hash/rotation edge cases needing sharper contracts.

## 05-01a1: Help Scaffold + Config/Read/Report Help

**Strengths**

- The plan correctly targets the explicit export boundary in `adman.psd1:53`, which currently lists 38 public functions.
- Category-scoped help coverage is a good fit because the public help work is split across three slices.
- The "inside/adjacent to function, not above `Set-StrictMode`" requirement is important. Current files place help before `Set-StrictMode`, e.g. `Public/Find-AdmanUser.ps1:2`, `Public/Find-AdmanUser.ps1:46`, `Public/Find-AdmanUser.ps1:48`, so the plan addresses a real binding risk.

**Concerns**

- **MEDIUM**: Current public files mostly have `.SYNOPSIS`, `.DESCRIPTION`, and examples, but almost none have `.PARAMETER` blocks. For example, `Public/Find-AdmanUser.ps1:50-56` declares three parameters, while the help block has no `.PARAMETER` entries at `Public/Find-AdmanUser.ps1:2-44`. The plan should frame this as parameter-help completion and relocation, not wholesale help creation.
- **LOW**: Standalone `Invoke-Pester` for the new help test may fail on a clean dev box unless PSFramework is installed or stubbed. Existing tests often create a PSFramework stub before importing the manifest, e.g. `tests/Module.Manifest.Tests.ps1:12-32`.

**Suggestions**

- Parse parameters from `Get-Command` after module import and exclude common/ShouldProcess parameters explicitly.
- Use a helper in the test for PSFramework stubbing or document that this test assumes the CI bootstrap has installed PSFramework.

**Risk Assessment: MEDIUM**

Mostly straightforward, but comment-based help placement and parameter comparison need careful implementation to avoid false positives/negatives.

## 05-01a2: AD User/Computer Lifecycle Help

**Strengths**

- The slice targets the right lifecycle surface: the manifest exports AD user/computer verbs at `adman.psd1:53`.
- The help content requirement is aligned with behavior. For example, `Disable-AdmanUser` routes through `Invoke-AdmanMutation` and propagates `-WhatIf` via `$WhatIfPreference` at `Public/Disable-AdmanUser.ps1:42-43`.

**Concerns**

- **LOW**: Requiring the words `WhatIf`, `confirm`, and `audit` in `.DESCRIPTION` is useful but brittle. It can pass even if the help omits important parameter-specific behavior like `-Force`, declared at `Public/Disable-AdmanUser.ps1:32`.

**Suggestions**

- Keep the keyword assertion, but also require `.PARAMETER Force` for functions declaring `Force`.
- Add one negative assertion that state-changing help must not claim `-Force` bypasses safety/audit gates.

**Risk Assessment: LOW**

Good scope and dependency ordering. Main risk is test brittleness, not implementation complexity.

## 05-01a3: Local/Group/Bulk/Workflow Help

**Strengths**

- The dependency on `05-03` is correct because restore help must describe rotated audit/archive lookup.
- Bulk help has concrete behavior to document: cap enforcement happens after filtering at `Public/Invoke-AdmanBulkAction.ps1:209-210`, and typed confirmation is built at `Public/Invoke-AdmanBulkAction.ps1:212-229`.

**Concerns**

- **MEDIUM**: The restore plan depends on archive lookup that does not exist today. Current restore state search only reads live top-level `audit-*.jsonl` files under `AuditDir` at `Private/Workflow/Get-AdmanOffboardingState.ps1:45-47`.

**Suggestions**

- Gate the restore-help assertion on the actual helper/function added by `05-03`, not just text mentioning archives.
- Include examples for both direct calls and TUI-driven workflows where applicable.

**Risk Assessment: MEDIUM**

Good plan, but it is coupled to `05-03`; if archive discovery changes shape, this slice must adapt.

## 05-01b: README, Usage Guide, Recovery Runbook

**Strengths**

- The plan uses the right sources of truth: menu labels and verbs live in `Private/Menu/Get-AdmanMenuDefinition.ps1:105-420`, and exported functions live in `adman.psd1:53`.
- The README is clearly stale today: it says only Phase 0 works at `README.md:27-39`, while the project context says Phases 1-4 are validated.

**Concerns**

- **MEDIUM**: The proposed `Docs.Coverage.Tests.ps1` only asserts menu labels and exported function names appear. DOC-02 requires coverage of parameterized functions with examples, and parameters are real contracts, e.g. `Find-AdmanUser` declares `Name`, `SamAccountName`, and `DisplayName` at `Public/Find-AdmanUser.ps1:50-56`.
- **LOW**: Accessing private `Get-AdmanMenuDefinition` through module scope is viable, but the plan should use the established pattern shown in tests like `tests/Audit.Schema.Tests.ps1:80-84`.

**Suggestions**

- Extend docs coverage to assert every non-common public parameter name appears near that function's section in `docs/USAGE.md`.
- Assert `.store/` portability and DPAPI-bound credential limitations separately, since `.gitignore` only blocks `.store/` by convention today at `.gitignore:1-2`.

**Risk Assessment: MEDIUM**

The docs work is necessary and well-targeted, but the tests as described under-prove DOC-02.

## 05-02: Dual Edition + Signing + CI

**Strengths**

- The plan correctly preserves the "honest Core claim" rule. Today the manifest is Desktop-only at `adman.psd1:18-19`.
- The AllSigned approach matches the loader: `adman.psm1` dot-sources every private/public `.ps1` file at `adman.psm1:40-45`, so signing all module `.ps1/.psm1/.psd1` files is necessary.
- Removing the stale Pester comment is valid; `tests/PesterConfiguration.psd1:6-8` currently says 5.1 should use the quick run.

**Concerns**

- **MEDIUM**: The AllSigned smoke test may be affected by external required modules. `adman.psd1:43-48` requires PSFramework 1.14.457, but the signing plan signs files under this module root, not PSFramework. CI should explicitly prove the dependency import path is signed/trusted or handle it intentionally.
- **MEDIUM**: The plan says the workflow runs "identical lint/help/unit suite" in both legs, but AllSigned must be reverted before unsigned tests run. That sequencing needs to be explicit in the workflow because tests are excluded from signing.

**Suggestions**

- Add a CI assertion that `Import-Module ./adman.psd1` under AllSigned imports both adman and PSFramework successfully.
- Keep `CompatiblePSEditions=@('Desktop','Core')` as the final file edit in the slice, after workflow/signing script validation.

**Risk Assessment: MEDIUM**

This is the most environment-sensitive plan. It can achieve the phase goal, but CI/signing details need exact sequencing.

## 05-03: Audit Hardening + Commit Guard

**Strengths**

- The plan builds on a solid audit writer: writes already occur under the `Global\adman-audit` mutex at `Private/Audit/Write-AdmanAudit.ps1:59-76`, record construction is centralized at `Private/Audit/Write-AdmanAudit.ps1:138-168`, and durable flush happens at `Private/Audit/Write-AdmanAudit.ps1:176-178`.
- Event Log escalation already exists for OUTCOME write failure at `Private/Audit/Write-AdmanAudit.ps1:207-211`, and current tests prove that path via mocking at `tests/Audit.FailClosed.Tests.ps1:178-196`.
- The `.store/` pre-commit guard addresses a real bypass gap: `.gitignore` ignores `.store/` at `.gitignore:1-2`, but forced adds are still possible.

**Concerns**

- **HIGH**: Archive restore behavior is a real implementation dependency. Current `Get-AdmanOffboardingState` only scans live audit files directly under `AuditDir` and does not recurse into archives at `Private/Workflow/Get-AdmanOffboardingState.ps1:45-47`. The plan covers this, but it should specify the exact archive search helper/path ordering to avoid restore regressions.
- **MEDIUM**: Adding `audit.retentionDays` requires schema/default/config migration changes in three places. Today defaults have no `audit` block at `config/adman.defaults.json:29-30`, schema has no `audit` property at `config/adman.schema.json:107-116`, and validation has no retention check at `Private/Config/Initialize-AdmanConfig.ps1:131-188`.
- **MEDIUM**: Hash canonicalization must be nailed down. Current records are `[ordered]` before `ConvertTo-Json -Compress -Depth 5` at `Private/Audit/Write-AdmanAudit.ps1:138` and `Private/Audit/Write-AdmanAudit.ps1:168`; integrity verification must use the same canonicalization rule or valid records may fail verification.

**Suggestions**

- Define one private helper that returns audit search roots: live `AuditDir` plus `AuditDir/archive/*`, and use it from both integrity and offboarding-state code.
- Add tests for empty file, first record of day, corrupt line in archive, and tampered `prevHash`.
- Make `.githooks/pre-commit` check `git diff --cached --name-only -- .store/` so it catches forced staged paths.

**Risk Assessment: HIGH**

This touches safety-critical audit records and restore behavior. The plan is directionally right, but correctness depends on precise canonicalization, migration, and archive discovery semantics.

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

- **HIGH — 05-03:** `Get-AdmanAuditIntegrity` must verify each record's own `hash` against the canonical record bytes, not only the `prevHash` chain. Otherwise tampering the last record of the day goes undetected. *(Plan 05-03 already requires self-hash verification and a final-line tampering test; the concern is acknowledged and the plan should ensure the verifier contract is implemented exactly as specified.)*
- **MEDIUM — 05-01b:** The proposed `Docs.Coverage.Tests.ps1` only asserts menu labels and exported function names appear. DOC-02 requires parameterized functions to be documented with examples, and the test should also verify that every non-common public parameter name appears near that function's section in `docs/USAGE.md`.
- **MEDIUM — 05-01a3:** Restore help depends on archive-search behavior implemented in `05-03`. The plan already lists `05-03` as a dependency, but the exact archive search helper/path ordering should be spelled out to avoid restore regressions.
- **MEDIUM — 05-02:** AllSigned smoke testing must explicitly handle the unsigned/trusted status of the `PSFramework` required module, and the workflow must clearly sequence the AllSigned smoke step before reverting execution policy for unsigned Pester tests. *(Plan 05-02 already addresses both with a signed CI stub and explicit policy revert; confirm during implementation.)*
- **LOW — 05-01a2:** The `.DESCRIPTION` keyword assertion (`WhatIf`, `confirm`, `audit`) is useful but brittle; consider also requiring `.PARAMETER Force` help for functions that declare `Force`, and add a negative assertion that help text must not claim `-Force` bypasses safety or audit gates.
- **LOW — 05-01b:** Accessing private `Get-AdmanMenuDefinition` through module scope is viable; ensure the test uses the same `& (Get-Module adman) { ... }` pattern already used elsewhere in the test suite.

### Divergent Views

None — only Codex provided a review in this cycle.

### Verification coverage

Reviewer had read-only sandbox access to `C:/Users/nhdinh/dev/adman` and cited specific file/line evidence.
