# Phase 5: Hardening & Portability - Context

**Gathered:** 2026-07-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 makes adman operationally ready: refresh the README, add a standalone usage guide, enforce inline comment-based help on every public command/parameter (DOC-01/02/03), honestly claim dual-edition support by passing a real Windows PowerShell 5.1 + PowerShell 7.6 LTS CI matrix, sign the module so it runs under `AllSigned`, verify workstation/jump-host portability, and harden the audit log (rotation, tamper-evidence hash chain, event-log forwarding) plus ship a Recycle-Bin recovery runbook and a `.store/` commit guard.

All functional code (gate, reads, writes, remoting, bulk/workflows) is locked from Phases 0–4. Phase 5 does not add new AD capabilities; it documents, tests, signs, hardens, and packages what already exists.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Documentation deliverables (DOC-01/02)

- **D-01: Split documentation into README + standalone usage guide.**
  - Refresh `README.md` to cover: install prerequisites (RSAT, PSFramework 1.14.457), first-run config wizard, safe-usage summary, and a short "what works today" section that reflects Phases 0–4 shipped state.
  - Add `docs/USAGE.md` as the action-by-action reference: every menu item (label, required inputs, B/Q behavior) and every exported parameterized function with at least one example. The menu table in `Get-AdmanMenuDefinition` is the source of truth for the menu half; the `FunctionsToExport` list in `adman.psd1` is the source of truth for the function half.
  - Keep `docs/REMOTE-OPS.md` in place and reference it from README/USAGE; do not merge it into the usage guide.

### Area 2 — Inline help enforcement (DOC-03)

- **D-02: Pester contract test for comment-based help coverage.**
  - A new test file `tests/Help.Coverage.Tests.ps1` iterates `FunctionsToExport` from `adman.psd1` and asserts each public function has:
    - `.SYNOPSIS` and `.DESCRIPTION` blocks
    - `.PARAMETER` help for every declared parameter
    - `.EXAMPLE` for at least the common parameter set
  - PSScriptAnalyzer already enforces `SupportsShouldProcess` on state-changing functions; no new custom PSSA rule is required for help.
  - The test runs in both 5.1 and 7.6 legs of the CI matrix.

### Area 3 — Dual-edition support and Authenticode signing (success criterion 2)

- **D-03: GitHub Actions CI matrix on Windows PowerShell 5.1 and PowerShell 7.6 LTS.**
  - Add `.github/workflows/ci.yml` that runs on `windows-latest` with two jobs/legs:
    - Windows PowerShell 5.1: `shell: powershell`
    - PowerShell 7.6 LTS: installed via `powershell/psscriptanalyzer-action` or direct MSI/setup action, then `shell: pwsh`
  - Each leg runs: PSScriptAnalyzer recursively, the help-coverage Pester test, and the full unit-test suite (`tests/PesterConfiguration.psd1`).
  - Integration tests remain lab-only (gated by `-Tag Integration` + `$env:ADMAN_TEST_OU`); they do not run in CI.
  - Only after the matrix passes is `CompatiblePSEditions` in `adman.psd1` updated from `@('Desktop')` to `@('Desktop','Core')`.

- **D-04: Sign the module so it runs under `AllSigned` using a self-signed certificate distributed as the trust anchor.**
  - Add `build/Sign-AdmanModule.ps1` that accepts a `-CertificateThumbprint` or `-CertificateFilePath` and signs all `.psd1`, `.psm1`, and `.ps1` files in the module.
  - CI generates a self-signed code-signing cert in a setup step, signs the module, then runs the test leg under `Set-ExecutionPolicy AllSigned -Scope Process` so the "runs under AllSigned" claim is mechanically proven.
  - README documents the self-signed-cert path for a single-company deployment: generate a code-signing cert, export the public key, and deploy it to admin workstations via Group Policy (`Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers`). No paid certificate is required because the company controls all endpoints.
  - Renewal and trust-anchor rotation are documented in the runbook; keep the private key offline/export-restricted where practical.

### Area 4 — Operational hardening (success criterion 3)

- **D-05: Audit log tamper-evidence + rotation + forwarding.**
  - **Append-only daily JSONL files** are preserved; the existing `Write-AdmanAudit` synchronous write path is unchanged.
  - Add a **simple hash chain**: each record includes `prevHash` = SHA-256 of the previous record's JSON bytes (omitted on the first record of a day). A new helper `Get-AdmanAuditIntegrity` verifies the chain and reports the first broken link.
  - Add **rotation**: a daily/background helper `Invoke-AdmanAuditRotation` archives files older than `audit.retentionDays` (default 90, stored in config schema/defaults) to `.store/audit/archive/YYYYMM/` and leaves a marker file.
  - **Event-log forwarding** for OUTCOME-write failures already exists (Event ID 9001); keep it and add a test proving the event-log seam is invoked when `Write-AdmanAudit` throws on OUTCOME.
  - No remote syslog/SIEM forwarding in v1; document the Event Log as the integration point.

- **D-06: Encrypted credential portability is documentation-only.**
  - The DPAPI credential file (`.store/adman.credential.xml`) is intentionally machine/user-bound; cross-machine restore already re-prompts (CONF-04).
  - No "exportable" credential backup feature is added. The README/USAGE explain: back up the plain-JSON config; the credential file must be recreated on a new machine/user via the normal prompt + remember-me flow.

- **D-07: Recycle-Bin recovery runbook.**
  - Add `docs/RECOVERY-RUNBOOK.md` covering:
    - Restoring a quarantined user via `Restore-AdmanQuarantinedUser`
    - Restoring a deleted object from AD Recycle Bin with PowerShell when the tool's quarantine restore is insufficient
    - Authoritative restore warning and when to escalate
  - The runbook is human documentation, not a new command.

- **D-08: `.store/` commit guard.**
  - `.gitignore` already excludes `.store/`; add a `.githooks/pre-commit` hook that refuses the commit if any `.store/` path is staged.
  - Add a CI check that fails if `.store/` contents are present in the checked-out tree (defense against a hook bypass).

### Claude's Discretion

- Exact CI action versions and setup steps for PowerShell 7.6 LTS are left to the planner/executor; the decision is "real GitHub Actions matrix on both editions."
- Exact hash-chain serialization order and archive folder naming are implementation details; the decision is "SHA-256 chain + time-based archive."
- The help-coverage test may use `Get-Help` AST or the `Microsoft.PowerShell.PlatyPS` parser; either is acceptable as long as it asserts the required blocks.
- Self-signed cert lifetime/generation parameters in CI are implementation details.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value, constraints (PS 5.1 baseline + 7.6 LTS, RSAT prereq, config/credential split, `.store/` gitignored).
- `.planning/REQUIREMENTS.md` — **Phase 5 owns 3:** `DOC-01`, `DOC-02`, `DOC-03`. Traceability table is authoritative.
- `.planning/ROADMAP.md` §Phase 5 — Goal, 3 success criteria, suggested 3-plan split (documentation / dual-edition+signing / audit hardening+runbook).

### Phase 0–4 artifacts (the spine this phase hardens)
- `.planning/phases/00-foundation-safety-harness/00-CONTEXT.md` — Gate, config, audit, credential DPAPI decisions.
- `.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md` — Menu, reports, D-03 schema.
- `.planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-CONTEXT.md` — Write verbs, local gate, password sourcing.
- `.planning/phases/03-remote-computer-operations-isolated/03-CONTEXT.md` — Transport ladder, remote enrichment, skipped-host semantics.
- `.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-CONTEXT.md` — Bulk engine, onboarding/offboarding workflows, CSV schema.

### Project rules & guardrails
- `.claude/CLAUDE.md` — "What NOT to Use" list, PSScriptAnalyzer rules, dual-edition constraints, signing recommendation.
- `PSScriptAnalyzerSettings.psd1` — Lint gate; state-changing functions must declare `SupportsShouldProcess`.

### Existing code that changes (read before planning)
- `README.md` — Refresh with current shipped state.
- `adman.psd1` — Update `CompatiblePSEditions` after CI passes; ensure `FunctionsToExport` is current.
- `Private/Audit/Write-AdmanAudit.ps1` — Extend record schema for hash chain; keep fail-closed semantics.
- `Private/Audit/AdmanAuditIO.ps1` — New helper seams for hash/rotation may live here.
- `config/adman.schema.json` + `config/adman.defaults.json` — Add `audit.retentionDays` if not present.
- `Private/Menu/Get-AdmanMenuDefinition.ps1` — Source of truth for usage-guide menu section.
- `docs/REMOTE-OPS.md` — Keep and reference.

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — Plain-JSON config; portable backup/restore.
- `.store/audit/audit-YYYYMMDD.jsonl` — Append-only audit files.
- `.store/adman.credential.xml` — DPAPI-encrypted credential; not portable.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`adman.psd1`** — Explicit `FunctionsToExport` is the source of truth for both the help-coverage test and the usage-guide function list.
- **`Get-AdmanMenuDefinition`** — Data-driven menu table is the source of truth for the usage-guide menu section; labels, PromptSpec, and Properties are all readable programmatically.
- **`Write-AdmanAudit`** — Already synchronous, fail-closed, JSON-lines, with event-log escalation on OUTCOME failure. Hash-chain and rotation are additive.
- **`AdmanAuditIO.ps1`** — Existing private seams (mutex, stream, event log) should host new hash/rotation helpers to keep fail-closed behavior testable.
- **`Get-AdmanCredential`** — DPAPI restore-failure handling already implements the cross-machine re-prompt requirement; no code change needed.
- **`PSScriptAnalyzerSettings.psd1`** — Existing lint gate; help enforcement is better done via Pester than a custom PSSA rule.

### Established Patterns
- **Config-driven values with schema validation:** any new `audit.retentionDays` key must land in both `config/adman.schema.json` and `config/adman.defaults.json`.
- **Explicit `FunctionsToExport` (SAFE-08):** the module boundary is a static list; tests and docs derive from it rather than scanning files.
- **Fail-closed audit:** `Write-AdmanAudit` must remain the single sink; rotation/integrity helpers must not interfere with the PENDING write path.
- **Public/Private boundary:** build/sign scripts are not exported module functions; place them under `build/` or `.github/`.

### Integration Points
- **README/USAGE ↔ menu and export list:** docs are generated/verified from `Get-AdmanMenuDefinition` and `adman.psd1` to avoid drift.
- **CI matrix ↔ module manifest:** `CompatiblePSEditions` is the outward claim; the matrix is the proof.
- **Sign script ↔ CI:** CI calls `build/Sign-AdmanModule.ps1` with a generated self-signed cert; production admins call the same script with an enterprise cert.
- **Audit writer ↔ hash chain:** the hash helper is invoked inside `Write-AdmanAudit` after a successful write to compute `prevHash` for the next record.
- **Audit rotation ↔ config:** `Invoke-AdmanAuditRotation` reads `audit.retentionDays` from `$script:Config`.
- **`.store/` guard ↔ git:** hook lives in `.githooks/pre-commit`; CI check is a separate defensive layer.

</code_context>

<specifics>
## Specific Ideas

- The README currently claims "Phase 0 only" and "no destructive verbs exported" — it must be rewritten to reflect Phases 0–4 shipped state before Phase 5 work is meaningful.
- `docs/USAGE.md` should read like a runbook for a mixed-skill team: menu number, what it does, what the operator types, and what the senior's direct PowerShell equivalent is (one code path, two speeds).
- Help-coverage test should fail the build if a new public function is added without help — this closes the loop on DOC-03.
- Honest dual-edition claim is the core hardening goal: do not flip `CompatiblePSEditions` to `Core` until CI proves it.
- AllSigned signing with a self-signed cert in CI proves the execution-policy path; in production a company-controlled self-signed cert distributed via GPO Trusted Publishers is the trust boundary, not an enterprise PKI.
- Audit hash chain is tamper-evidence, not tamper-proof; the goal is to detect alteration, not prevent an admin with filesystem access from deleting files.
- `.store/` commit guard should be a pre-commit hook plus CI defense in depth; a single `.gitignore` line is not enough for a safety-critical project.
</specifics>

<deferred>
## Deferred Ideas

- **Remote syslog/SIEM forwarding** — out of v1 scope; Event Log is the integration point.
- **Encrypted audit (filesystem encryption / BitLocker policy)** — operational, not code; document in runbook if needed.
- **Automated certificate renewal / HSM-backed signing** — enterprise PKI operations, not the module's responsibility.
- **Multi-domain/cross-forest portability** — v2 scope (`PLAT-V04`).
- **Compiled `.exe` distribution (`PLAT-V02`)** — v2 scope.
- **Persisted/resume-safe bulk job state (`BULK-V01`)** — v2 scope.

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 5-Hardening & Portability*
*Context gathered: 2026-07-20*
