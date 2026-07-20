---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 04
current_phase_name: bulk-workflows-highest-blast-radius-last
status: executing
stopped_at: Completed 04-02-PLAN.md
last_updated: "2026-07-20T07:20:43.944Z"
last_activity: 2026-07-20
last_activity_desc: Phase 04 execution started
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 27
  completed_plans: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-14)

**Core value:** Any admin on the team can perform common AD/local-user & computer tasks correctly and safely — every destructive action is previewed (`-WhatIf`), confirmed, scoped to a managed OU, blocked from protected accounts, and written to an audit log.
**Current focus:** Phase 04 — bulk-workflows-highest-blast-radius-last

## Current Position

Phase: 04 (bulk-workflows-highest-blast-radius-last) — EXECUTING
Plan: 2 of 4
Status: Ready to execute
Last activity: 2026-07-20 — Phase 04 execution started

Progress: [█████████░] 93% (Phase 1 of 6, 4 of 4 Phase 1 plans executed)

## Performance Metrics

**Velocity:**

- Total plans completed: 13
- Average duration: -
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 00 | 6 | - | - |
| 01 | 4 | - | - |
| 03 | 3 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 00 P01 | ~1h5m | 3 tasks | 17 files |
| Phase 00-foundation-safety-harness P02 | 1h13m | 3 tasks | 12 files |
| Phase 00-foundation-safety-harness P03 | 59m | 2 tasks | 12 files |
| Phase 00 P04 | 38min | 3 tasks | 15 files |
| Phase 00-foundation-safety-harness P05 | 24min | 3 tasks | 10 files |
| Phase 00-foundation-safety-harness P06 | 18min | 3 tasks | 2 files |
| Phase 01 P01 | 15m | - tasks | - files |
| Phase 01 P02 | 20m | - tasks | - files |
| Phase 01 P02 | 20m | 5 tasks | 13 files |
| Phase 01 P03 | 14m | 3 tasks | 13 files |
| Phase 01 P04 | 25m | - tasks | - files |
| Phase 02 P01 | 3h | 3 tasks | 27 files |
| Phase 02 P02 | 45m | 2 tasks | 11 files |
| Phase 02 P03 | 4m | 2 tasks | 8 files |
| Phase 02 P04 | 7m | 2 tasks | 8 files |
| Phase 02 P05 | 4m | 1 tasks | 6 files |
| Phase 02 P06 | 10m | - tasks | - files |
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 02 P07 | 10m | 2 tasks | 18 files |
| Phase 02 P08 | ~7m | 2 tasks | 2 files |
| Phase 02 P09 | ~11m | 3 tasks | 5 files |
| Phase 02 P10 | ~12m | 3 tasks | 4 files |
| Phase 03-remote-computer-operations-isolated P01 | 35min | 3 tasks | 15 files |
| Phase 03-remote-computer-operations-isolated P02 | 42min | 3 tasks | 6 files |
| Phase 03-remote-computer-operations-isolated P03 | 18min | 3 tasks | 2 files |
| Phase 04-bulk-workflows-highest-blast-radius-last P01 | 45m | 3 tasks | 11 files |
| Phase 04-bulk-workflows-highest-blast-radius-last P04-02 | 5m | 2 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- Roadmap: Adopted research SUMMARY.md 6-phase blast-radius-ordered skeleton (0 Foundation/Safety → 1 Read-only reporting → 2 Single-object writes → 3 Remoting → 4 Bulk/workflows → 5 Hardening) as-is; it maps all 58 requirements.
- Roadmap: Governing principle locked — the safety spine (Phase 0) must exist and be proven (incl. a Pester test that no exported function calls AD write cmdlets directly) before any real write can merge.
- Roadmap: Config/credential split (Decided in PROJECT.md) — portable plain-JSON non-secret config + separate opt-in DPAPI-encrypted credential file, both in gitignored `.store/`; pass-through by default; no built-in RID baseline (protection via recursive admin-group membership + custom deny-list only).
- Roadmap: TUI is the product — `**UI hint**: no` for all phases (no browser frontend; `/gsd-ui-phase` not applicable).
- [Phase ?]: D-01: PSFramework 1.14.457 adopted in Phase 0 for config + diagnostic/ops logging; audit writer stays hand-rolled/synchronous (CLAUDE.md reconciled, C2-M2).
- [Phase ?]: SAFE-08: explicit FunctionsToExport; single non-exported gate Invoke-AdmanMutation; one banned-verb source drives both the PSScriptAnalyzer rule and the Pester AST guard.
- [Phase ?]: PSFramework exact-pinned via RequiredVersion='1.14.457'; ActiveDirectory is a prerequisite (never in RequiredModules); CompatiblePSEditions=@('Desktop') until the Phase 5 CI matrix passes on 7.6.
- [Phase ?]: Guard alias resolution uses Get-Alias (no module auto-load) so lint/tests never pull in RSAT (T-00-11); the custom PSSA rule emits on the root AST only (no duplicate diagnostics).
- [Phase ?]: Fail-closed is framework-independent (D-01/T-00-07)
- [Phase ?]: Single validator Test-AdmanConfigValid + single save Save-AdmanConfig -Depth 5 reused by Initialize/Set/Import (D-04/T-00-13)
- [Phase ?]: Deny-list seeded once (RID 500/501/502); file is source of truth thereafter (D-05)
- [Phase ?]: Export/Import keep plain-JSON safety file authoritative; PSFramework mirror path .psf.json (CONF-03)
- [Phase ?]: credentialPolicy.allowRememberMe allow-listed as non-secret; no-secret rule bans only real secret names/values (C2-M1)
- [Phase 00-03]: Rights-first credential decision (CONF-06): pass-through when rights sufficient, prompt only when insufficient; stored DPAPI only when insufficient+allowRememberMe.
- [Phase 00-03]: DPAPI restore-failure (CONF-04/D-06): CryptographicException 0x8009000B OR empty/null password OR non-PSCredential => delete bad file + Get-Credential; Export-Clixml CurrentUser only.
- [Phase 00-03]: Rights probed non-destructively (read managed OU + whoami /groups); never an AD write (MENU-05/CONF-06/T-00-15).
- [Phase 00-03]: Protected set from live SIDs (DomainSID-512, forest-root-518/519 A3, S-1-5-32-544/-548/-551/-549, DomainSID-525, +AdmanProtectedGroup); DenyRids {500,501,502}; no hard-coded SID (D-02/D-05).
- [Phase 00-03]: Initialize-Adman fixed six-step order; -SetupMode runs config load only (wizard mutation-free) (D-04).
- [Phase 00-03]: Test-AdmanAuditWritable writes ZERO bytes (open-append+Flush(true)+dispose) so 00-05 strict-JSONL Find-AdmanAuditOrphans never sees a non-JSON line.
- [Phase 00]: 00-04: -WhatIf detection is [bool]$WhatIfPreference (boolean cast), NEVER the string 'Simulate' (C3-H1/C4-H1)
- [Phase 00]: 00-04: confirm-first audit — a declined action writes ZERO records (no orphan PENDING); the GATE owns the decline throw + all audit writes
- [Phase 00]: 00-04: bulk-cap enforcement deferred to Phase 4 (BULK-02); Phase 0 Assert-AdmanBulkPolicy only reads values + exposes -EnforceCap forward-compat
- [Phase ?]: 00-05: Write-AdmanAudit is the ONLY audit sink (D-01); fail-closed throw gated on the PENDING pre-write only, OUTCOME failure escalates without rollback (D-03)
- [Phase ?]: 00-05: audit I/O via three private seams (mutex/file/eventlog) so fail-closed is test-provable without mocking raw .NET statics; named-mutex literal lives in the New-AdmanAuditMutex seam
- [Phase ?]: 00-05: integration tests doubly gated (-Tag Integration + ADMAN_TEST_OU); SAFE-08/09 guard passes trivially now (no Public write verbs) and is re-proven in Phase 2 when write verbs land
- [Phase 00]: UAT gap #3 resolved via option (a): WhatIf test targets child USER fixtures under the lab OU; gate keeps resolve-identity-as-is semantics (no OU-expansion product change).
- [Phase 00]: Test-AdmanTargetAllowed step (b) skips RID-deny ONLY when objectSid is absent/null; any object WITH an objectSid runs the exact prior deny check (renamed RID-500 still refused).
- [Phase ?]: Phase 01-02: HIGH-1 resolved via dedicated Escape-AdmanAdFilterLiteral helper for -Filter string literals (single-quote doubling + backslash doubling); Escape-AdmanLdapFilterValue remains RFC4515-only for -LDAPFilter. The two are structurally independent and NOT interchangeable.
- [Phase ?]: Phase 01-02: MEDIUM-3 resolved — ConvertTo-AdmanNormalizedDn extracted from Test-AdmanTargetAllowed into Private/Utility/ as the single source for DN normalization; both write path (Test-AdmanTargetAllowed step (c)) and read path (Test-AdmanInManagedScope) call it with no logic duplication.
- [Phase ?]: Phase 01-02: D-03 schema contract pinned — ConvertTo-AdmanResult emits fixed-schema PSCustomObject per type (User: 16 columns, Computer: 15 columns); timestamps as [datetime] or $null; never-logged-on sentinel deferred to report layer.
- [Phase 01-03]: D-07 sync-interval source: (Get-ADDomain).LastLogonReplicationInterval (domain NC head), NOT the Configuration partition Directory Service object (that attribute is tombstoneLifetime).
- [Phase 01-03]: MEDIUM-1 conversion matrix: TimeSpan -> .Days; numeric -> truncate toward zero; zero/negative/null/other -> 14 fallback; any exception -> 14.
- [Phase 01-03]: Grace buffer: LogonSyncGraceDays = [math]::Max(14, interval) + 1 (epsilon +1 per RESEARCH).
- [Phase 01-03]: D-08: Initialize-Adman wraps Get-AdmanRecoveryPosture in try/catch so a posture read failure NEVER blocks startup.
- [Phase 01-03]: Get-AdmanRecoveryPostureReport reads from $script:Config.RecoveryPosture when initialized; falls back to direct call pre-init.
- [Phase 01-03]: Bucket column added via Add-Member -Force on D-03 schema objects (not a schema change; renderers see it as an extra NoteProperty).
- [Phase ?]: D-01 synthetic pre-create target carries IsSynthetic=true and ParentOuDn; create-branch runs ONLY managed-OU scope against parent OU DN
- [Phase ?]: D-02 local gate mirrors AD gate byte-for-byte; create-branch + uniqueness pre-flight + TOCTOU closure strictly parallel to D-01
- [Phase ?]: D-04 protected-group add refused by DIRECT SID equality (not IN_CHAIN); Remove skips the check (asymmetric remediation)
- [Phase ?]: HIGH #1: both gates write Failure outcome audit on wrapper throw before rethrowing (no PENDING orphan)
- [Phase ?]: [Phase 02-02]: D-05 display-once [Console]::Clear() wrapped in try/catch IOException for headless hosts; shoulder-surf shrink is UX nicety, not security boundary (BSTR already zeroed)
- [Phase ?]: [Phase 02-02]: Unlock-AdmanUser PDCe resolver note — Resolve-AdmanTarget intentionally NOT extended with -Server pass-through; DN/SID identity stable across DCs, only lockout STATE is PDCe-authoritative and read explicitly on PDCe before gate
- [Phase ?]: [Phase 02-05]: D-04 dual-resolution policy matrix enforced by the gate; the Public verbs are thin prompt-and-dispatch wrappers that build $Parameters['GroupIdentity'] and call Invoke-AdmanMutation
- [Phase ?]: [Phase 02-05]: GRP-03 protected-group refusal is a gate-side invariant (Test-AdmanGroupAllowed direct SID equality), not a Public-verb check — direct gate callers cannot bypass it
- [Phase ?]: [Phase 02-05]: D-04 asymmetry — Remove skips the group-side protected-SID check (remediation allowed); deny-RID and gMSA checks still apply on both Add and Remove; member-side checks unchanged
- [Phase ?]: [Phase 02-06]: PromptSpec items are hashtables; Read-AdmanActionParams uses shape-agnostic key detection (.Contains() for IDictionary, PSObject.Properties.Name otherwise) so Choices/Type probe works for both shapes
- [Phase ?]: [Phase 02-06]: Set-AdmanLocalUser appears THREE times in the menu (Reset/Enable/Disable parameter sets); Enable/Disable entries carry FixedParameters so the operator picks the action by picking the menu item
- [Phase ?]: Phase 02-07: Test 2 uses real Confirm-AdmanAction (not mock) because Pester -ModuleName mock bodies do not preserve caller $ConfirmPreference via dynamic scope
- [Phase ?]: [Phase 02-10]: Test-AdmanTargetAllowed -Operation ValidateSet spans all 10 gate verbs (copied verbatim from Invoke-AdmanMutation.ps1:47-49); consulted ONLY for the Remove-ADGroupMember skip (D-04 remediation asymmetry); Reset-ADComputerPassword deliberately excluded (not a gate verb)
- [Phase ?]: [Phase 02-10]: Group-refusal audit restructured to per-member records (member DN in target field, group DN in group field) so forensics can tell which member the add was attempted on (G-02-9)
- [Phase ?]: [Phase 02-10]: Write-Warning emitted AFTER Write-AdmanAudit on member-refusal and BEFORE throw on group-refusal; audit is authoritative log, warning is operator-visible surface (G-02-6)
- [Phase ?]: Pester 6 requires BeforeEach inside a Describe block; existing test stubs were restructured to comply.
- [Phase ?]: C# Add-Type synthetic Job subclass is used in timeout-wrapper tests because System.Management.Automation.Job parameter binding rejects PSCustomObject stand-ins.
- [Phase ?]: Timeout wrappers stop+remove jobs on any non-success path and remove-only on success, keeping cleanup centralized in a single finally block.
- [Phase ?]: Invoke-AdmanRemoteQuery intentionally does not call Invoke-AdmanRemoteCimQuery so one transient session serves both allowed CIM classes, avoiding double session-setup cost.
- [Phase ?]: Per-host cap is enforced by starting a stopwatch before Connect-AdmanTarget and passing the remaining budget into Invoke-AdmanRemoteQuery, which recomputes before New-CimSession and each Get-CimInstance.
- [Phase ?]: CIM errors and budget exhaustion return Transport='Skipped' so the skipped-host count stays accurate for operators.
- [Phase ?]: Operator guidance is the canonical reference for why adman Phase 3 is local-on-target only and what to do if second-hop live actions are needed later.
- [Phase ?]: CredSSP is explicitly excluded from v1; any future second-hop work must go through RBCD/JEA design review.
- [Phase ?]: Static parser for -ClassName literals is intentionally simple; the real enforcement is the runtime allow-list in Invoke-AdmanRemoteCimQuery.
- [Phase ?]: Bulk engine uses DistinguishedName as canonical Identity in bulk records
- [Phase ?]: Invoke-AdmanBulkAction -Force skips only the outer typed-count confirmation; per-item policy/audit still run via Invoke-AdmanMutation -Force:
- [Phase ?]: Group destination policy is validated before cap/confirm for AddGroup/RemoveGroup
- [Phase ?]: Password display-once hygiene remains inside New-AdmanUser; the workflow does not duplicate it
- [Phase ?]: Workflow passes -Force: to composed verbs so the outer confirmation is the only operator prompt
- [Phase ?]: Baseline group validation runs before user creation so a protected destination fails the entire job early

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 0 research flag (HIGH): verify exact PSFramework 1.14.457 config/logging cmdlet signatures; DPAPI/`Export-Clixml` behavior across 5.1 vs 7.6; precise well-known-SID set for this environment's protected groups; RSAT server feature name vs target SKUs. Run `/gsd-plan-phase 0 --research-phase 0` if deeper research is needed.
- Phase 3 research flag (MEDIUM): confirm environment firewall reality for DCOM (135 + RPC dynamic) vs WinRM (5985/5986) before defaulting the ladder order.
- Phase 4 research flag (MEDIUM): confirm exact protected-group set, break-glass override policy, managed-OU roots, default max-count cap, and which offboarding cleanup items are checklist-only vs automated.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260714-ek6 | Fix Invoke-AdmanMutation module-scope invocation in the two lab integration test files | 2026-07-14 | feac682 | [260714-ek6-fix-invoke-admanmutation-module-scope-in](./quick/260714-ek6-fix-invoke-admanmutation-module-scope-in/) |
| 260714-fbx | Initialize module in integration tests via Initialize-Adman against a lab config | 2026-07-14 | 259f4d9 | [260714-fbx-initialize-module-in-integration-tests-v](./quick/260714-fbx-initialize-module-in-integration-tests-v/) |
| 260714-n4w | Generate a README.md for the project | 2026-07-14 | 341a79c | [260714-n4w-generate-a-readme-md-for-the-project](./quick/260714-n4w-generate-a-readme-md-for-the-project/) |

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 scope | Saved queries/favorites (RPT-V01), remote live actions (RMT-V01), multi-role templates (FLOW-V01), full idempotent/resume-safe bulk (BULK-V01), HR-CSV provisioning (FLOW-V02), read-only GPO reporting (RPT-V02), scheduling (PLAT-V01), ps2exe `.exe` (PLAT-V02), stored-privileged-cred/elevation (PLAT-V03), multi-domain/cross-forest (PLAT-V04) | Deferred to v2 | 2026-07-10 |

## Session Continuity

Last session: 2026-07-20T07:20:43.935Z
Stopped at: Completed 04-02-PLAN.md
Resume file: None
Next action (when user approves): /gsd-execute-phase 01 — execute plan 01-04 (renderer dispatch).
