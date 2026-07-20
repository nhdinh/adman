# Roadmap: adman

## Overview

adman is a menu-driven (interactive TUI) PowerShell toolkit that lets a small, mixed-skill IT team manage users and computers in an on-prem Active Directory domain. The journey is governed by one principle: **the safety spine must exist and be proven before any real write can merge.** Phases are sequenced by blast radius — foundation/safety-harness first, then read-only reporting, then single-object writes, then remoting (isolated), then bulk/workflows (highest blast radius, last), then hardening. Reads before writes, single-object before bulk, remoting quarantined, workflows composed last. The 6-phase skeleton (Phase 0–5) is adopted from `research/SUMMARY.md` and maps all 58 v1 requirements.

**Mode:** standard (Horizontal / foundation-first)

## Phases

**Phase Numbering:**

- Integer phases (0, 1, 2, 3, 4, 5): Planned milestone work (follows the research skeleton)
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED), created via `/gsd-phase --insert`

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 0: Foundation & Safety Harness** - Build and prove the non-bypassable mutation gate, config/credential store, and startup capability probe before any AD write exists. (completed 2026-07-13)
- [x] **Phase 1: AD Query & Reporting (read-only)** - Launch the TUI, search/view scoped objects, and render correct read-only reports (console/CSV/HTML) that prove AD semantics before writes consume them. (completed 2026-07-15)
- [x] **Phase 2: Single-Object Lifecycle (writes begin)** - AD/local user, computer, and group-membership lifecycle for one object at a time, every change routed through the gate with truthful preview, scaled confirmation, and audit. (completed 2026-07-16)
- [x] **Phase 3: Remote Computer Operations (isolated)** - Read-only remote queries behind one transport-ladder connector (WinRM → CIM/WSMan → CIM/DCOM → skip) that never hangs on dead hosts and handles double-hop by design. (completed 2026-07-17)
- [ ] **Phase 4: Bulk & Workflows (highest blast radius, last)** - Gated bulk (preview → cap → typed confirm → per-item) and reversible onboarding/offboarding workflows that compose proven single-object verbs under one gate.
- [ ] **Phase 5: Hardening & Portability** - Documentation, Authenticode signing, honest PS 5.1/7.6 dual-edition support via a real CI matrix, workstation/jump-host portability, credential restore, and audit hardening.

## Phase Details

### Phase 0: Foundation & Safety Harness

**Goal**: The non-bypassable safety spine exists and is proven in isolation before any real AD write can merge — every future mutation funnels through one internal gate with truthful preview, scaled confirmation, scope/deny-list/protected-account enforcement, and fail-closed audit.
**Depends on**: Nothing (first phase)
**Requirements**: MENU-05, CONF-01, CONF-02, CONF-03, CONF-04, CONF-05, CONF-06, SAFE-01, SAFE-02, SAFE-03, SAFE-04, SAFE-05, SAFE-06, SAFE-07, SAFE-08, SAFE-09, SAFE-10 (17)
**Success Criteria** (what must be TRUE):

  1. `Initialize-Adman` (invoked by `Start-Adman`) loads and validates the portable plain-JSON non-secret config, fails closed (refuses writes) when the managed-OU is empty or the deny-list/config fails to load, and reports capabilities (RSAT present, domain reachable, current rights, transport availability) with actionable guidance at startup (CONF-01/02/03/05, MENU-05).
  2. A Pester + PSScriptAnalyzer guard proves no exported function calls AD write cmdlets directly — all writes route through the non-exported `Invoke-AdmanMutation` gate (SAFE-08), and every destructive function declares `SupportsShouldProcess`/`ConfirmImpact='High'` (lint-enforced).
  3. `-WhatIf` works end-to-end against a test OU: preview and execute use identical target resolution so the preview cannot lie (SAFE-10), every destructive action supports dry-run (SAFE-01) with confirmation scaled to blast radius (y/n single; typed token + count for bulk) (SAFE-02), and "delete" is reversible disable+quarantine with no hard-delete verb shipped (SAFE-09).
  4. The gate refuses deny-listed targets (SAFE-05), recursive members of protected groups plus gMSA/service accounts resolved via well-known SIDs at check time (never `adminCount` alone) (SAFE-06), and any DN outside a managed-OU root (SAFE-07) — and each refusal is logged.
  5. Every action (including dry-runs) appends a structured audit record (who/what/when/scope/target/count/WhatIf/result) that never contains secrets and refuses the destructive action if the record cannot be written (SAFE-03/04); the DPAPI credential file is written only on explicit "remember me" and re-prompts on cross-machine/user restore (CONF-04/06), with `.store/` never committed and no secrets in the repo or logs (CONF-05).

**Plans:** 6/6 plans complete

- [x] 00-06-PLAN.md

**UI hint**: no

Plans (finalized during `/gsd-plan-phase 0`):

- [x] 00-01-PLAN.md — Module scaffold + PSFramework 1.14.457 build-time re-verification (Assumption A1) + Pester 6 / PSScriptAnalyzer 1.25.0 harness with the custom SAFE-08 rule + AD mocks; `adman.psd1/.psm1`, Public/Private loader, explicit `FunctionsToExport`, `$ErrorActionPreference='Stop'`, `-Server`-pinning helper, PSFramework config+diagnostic-logging backbone (audit stays synchronous/hand-rolled per D-01). (MENU-05, SAFE-08)
- [x] 00-02-PLAN.md — Non-secret config: shared schema + shipped defaults + TRACKED annotated example; fail-closed `Initialize-AdmanConfig` (empty managed-OU / failed deny-list throw; setup-mode exempt) pinned with `Import-PSFConfig -Path`; SID-seeded deny-list; thin `Get/Set/Export/Import-AdmanConfig` verbs; `.store/` gitignored + no secret fields. (CONF-01/02/03/05)
- [x] 00-03-PLAN.md — Credential decision (pass-through default; opt-in DPAPI `Export-Clixml` CurrentUser with delete-and-re-prompt on 0x8009000B/empty; reject keyed-AES) + `Test-AdmanCapability` startup probe (MENU-05) + `Initialize-Adman` orchestration + startup protected-SID/deny-RID resolution. (MENU-05, CONF-04/06)
- [x] 00-04-PLAN.md — Safety core: `Resolve-AdmanTarget` (single shared preview/execute resolver), `Test-AdmanTargetAllowed` (component-boundary scope + RID deny + gMSA pre-filter + IN_CHAIN protected, never adminCount), `Confirm-AdmanAction` (ShouldProcess + typed-count bulk + -Force), `Assert-AdmanBulkPolicy` (cap placeholder), `Invoke-AdmanMutation` (THE GATE, fixed order) + gate-only `Adman.AD.Write.*` wrappers (9-verb allow-list, no hard-delete). (SAFE-01/02/05/06/07/08/09/10)
- [x] 00-05-PLAN.md — Fail-closed append-only audit (`Write-AdmanAudit` write-ahead PENDING→throw→mutate→OUTCOME, `Mutex Global\adman-audit`, JSON-lines, no secrets) + audit-integrity orphan sweep + read-only recovery-posture reporter + phase exit gate (full mocked Unit suite green + ScriptAnalyzer clean + SAFE-08/09 AST guard proven against Public/). (SAFE-03/04/08/09)

### Phase 1: AD Query & Reporting (read-only)

**Goal**: Admins can launch the TUI, search/view users and computers in scope, and run correct read-only reports (console/CSV/HTML) that prove the team reads AD semantics (timestamps, replication, four account states, lockout counters) correctly *before* any write consumes them.
**Depends on**: Phase 0
**Requirements**: MENU-01, MENU-02, MENU-03, MENU-04, USER-01, COMP-01, RPT-01, RPT-02, RPT-03, RPT-04, RPT-05, RPT-06, RPT-07 (13)
**Success Criteria** (what must be TRUE):

  1. Admin launches `Start-Adman`, sees a numbered menu, selects an action by number with validated prompts, navigates back/quits from any prompt, and every menu action routes to the same parameterized function a senior calls directly — one code path, two speeds (MENU-01/02/03/04).
  2. Admin can search/view users by name/`sAMAccountName`/displayName and computers by name, scoped to the managed OU, with read wrappers always setting `-SearchBase`, exact `-Properties`, and `-ResultPageSize` (USER-01, COMP-01).
  3. Reports render Disabled/Expired/Locked/Password-Expired as four distinct states via `Search-ADAccount` (RPT-05); stale/inactive uses replicated `lastLogonTimestamp` with a ≥14-day grace buffer and a separate never-logged-on (`0`/1601) bucket — never per-DC `lastLogon` (RPT-04); and startup shows the domain recovery posture (Recycle Bin / FFL) rather than assuming it (RPT-07).
  4. Any report renders as a console table (and `Out-GridView` where available) (RPT-01), exports to CSV `-NoTypeInformation` (RPT-02), and exports to a self-contained single-file HTML report (RPT-03); inventory shows OS version + basic computer info from AD attributes (RPT-06).

**Plans**: 4/4 plans complete
**UI hint**: no

Plans (finalized during `/gsd-plan-phase 1`):

- [x] 01-01-PLAN.md — Presentation/menu shell: flat `while` loop in `Start-Adman`, numbered `Read-Host` menu, validated prompts, `B`/`Q` reserved inputs, routes to Public verbs, never touches AD (MENU-01/02/03/04).
- [x] 01-02-PLAN.md — Scoped read layer: `Find-AdmanUser`, `Find-AdmanComputer`, `ConvertTo-AdmanResult` D-03 schema mapper, `Test-AdmanInManagedScope` scope-only boundary, exact `-Properties`, `-ResultPageSize 1000` (USER-01, COMP-01).
- [x] 01-03-PLAN.md — Correct AD semantics: stale/inactive report via replicated `lastLogonTimestamp` + self-tuning grace + `NeverLoggedOn` bucket (no per-DC `lastLogon`), four account states via `Search-ADAccount`, recovery-posture preflight + sync-interval cache (RPT-04/05/07).
- [x] 01-04-PLAN.md — Output layer: `Format-AdmanReport`, `Export-AdmanReportCsv`, `Export-AdmanReportHtml`, `Get-AdmanInventoryReport`, capability-probed grid picker with console fallback (RPT-01/02/03/06).

### Phase 2: Single-Object Lifecycle (writes begin, bounded to one)

**Goal**: Admins can perform single-object AD user, AD computer, local (per-machine) user, and group-membership lifecycle changes — every one routed through the gate with truthful preview, scaled confirmation, and audit, exercising the gate on real writes with minimal blast radius.
**Depends on**: Phase 0, Phase 1
**Requirements**: USER-02, USER-03, USER-04, USER-05, USER-06, LUSR-01, LUSR-02, COMP-02, COMP-03, COMP-04, GRP-01, GRP-02, GRP-03 (13)
**Success Criteria** (what must be TRUE):

  1. Admin can create a single user with required attributes, disable/enable, reset a password (optionally force change at next logon and unlock) without ever echoing or logging it, unlock (reads `LockedOut` first, pinned to the PDC emulator), and move within managed scope — all through the gate with preview ≡ execute + confirm + audit (USER-02/03/04/05/06).
  2. Admin can disable/enable/move a computer and reset the computer account / repair the secure channel with guidance on which method applies, through the gate (COMP-02/03/04).
  3. Admin can create/disable/enable/reset-password/remove a local user and manage local group membership (e.g., local Administrators) on a target via the `LocalAccounts` module, mutations through the gate (LUSR-01/02).
  4. Admin can add/remove a user from groups (GRP-01/02), the tool refuses adding any principal to a protected group per SAFE-06 (GRP-03), protected/out-of-scope targets are refused and logged, and no verb bypasses the gate (lint + Pester re-proven against the new verbs).

**Plans**: 10/10 plans executed
**UI hint**: no

Plans (finalized during `/gsd-plan-phase 2`):

- [x] 02-01-PLAN.md — Cross-cutting gate infrastructure: config schema + D-05 CSPRNG password plumbing, D-01 create path (Resolve-AdmanCreateTarget + create-branch + uniqueness pre-flight + New-ADUser wrapper), D-04 group policy (Resolve-AdmanGroup + Test-AdmanGroupAllowed), D-02 sibling local gate (Invoke-AdmanLocalMutation + Resolve-AdmanLocalTarget + Test-AdmanLocalTargetAllowed + Adman.Local.Write.*), D-03 Remove-LocalUser threshold override, audit group field + MACHINE\username shape, AST guard LocalAccounts extension, Wave 0 test scaffolds. (USER-02, USER-04, LUSR-01, LUSR-02, GRP-01, GRP-02, GRP-03)
- [x] 02-02-PLAN.md — AD user lifecycle Public verbs: New-AdmanUser, Disable/Enable-AdmanUser, Set-AdmanUserPassword, Unlock-AdmanUser (PDCe-pinned), Move-AdmanUser (destination validated). (USER-02, USER-03, USER-04, USER-05, USER-06)
- [x] 02-03-PLAN.md — AD computer lifecycle Public verbs: Disable/Enable-AdmanComputer, Move-AdmanComputer, Reset-AdmanComputerAccount (with honest AD-side vs on-machine guidance). (COMP-02, COMP-03, COMP-04)
- [x] 02-04-PLAN.md — Local user/group Public verbs: New/Set/Remove-AdmanLocalUser, Add/Remove-AdmanLocalGroupMember, all through the sibling local gate with localhost-only -ComputerName validation. (LUSR-01, LUSR-02)
- [x] 02-05-PLAN.md — Group membership Public verbs: Add/Remove-AdmanGroupMember through the gate's dual-resolution path; GRP-03 protected-group refusal + D-04 asymmetric remove. (GRP-01, GRP-02, GRP-03)
- [x] 02-06-PLAN.md — Menu integration (section-grouped write entries + D-05 password prompt Type), manifest exports, phase exit gate (full suite green + AST guard re-proof + lint clean). (All 13 Phase 2 requirements)

Gap-closure plans (from UAT 2026-07-16, 8 passed / 4 issues / 6 open gaps):

- [x] 02-07-PLAN.md — G-02-5 BLOCKER: restore confirmation on cmdlet path. Remove `-Confirm:$false` forwarding from all 20 Public mutation call sites; regression test proves plain-cmdlet invocation prompts. (All 13 IDs — confirmation is cross-cutting)
- [x] 02-08-PLAN.md — G-02-3 BLOCKER: unblock create flow. Defensive SID extraction in Write-AdmanAudit AD-target branch (null/type-guarded) so synthetic pre-create targets write PENDING without throwing under StrictMode; fail-closed preserved. (USER-02)
- [x] 02-09-PLAN.md — G-02-2 + G-02-4 BLOCKER: menu identity/DN resolver. New `Resolve-AdmanIdentity` (Private) + Type dispatch in Read-AdmanActionParams + PromptSpec Type='AdIdentity'/'AdOuDn' on 14 prompts; re-prompt on failure. (USER-02..06, COMP-02..04, GRP-01/02)
- [x] 02-10-PLAN.md — G-02-8 + G-02-9 + G-02-6: group remediation asymmetry + audit member DN + refusal surface. Test-AdmanTargetAllowed gains -Operation (skips step d on Remove-ADGroupMember); group-refusal audit names member DN; Write-Warning surfaces refusal reasons. (GRP-01/02/03, USER-03, COMP-02)

### Phase 3: Remote Computer Operations (isolated)

**Goal**: Admins can run read-only remote queries that enrich inventory, with remoting quarantined behind one connector that auto-detects transport, never hangs on dead hosts, treats `Skipped` as a first-class non-error outcome, and handles double-hop by design — so transport/firewall/double-hop risk cannot destabilize the AD core.
**Depends on**: Phase 0, Phase 1
**Requirements**: RMT-01, RMT-02, RMT-03, RMT-04 (4)
**Success Criteria** (what must be TRUE):

  1. Each target is probed with a WinRM → CIM/WSMan → CIM/DCOM → skip ladder and the working transport is cached per host; the probe distinguishes WSMAN vs DCOM (RMT-01).
  2. Unreachable hosts are reported as `Skipped` (a first-class non-error outcome), short timeouts ensure the menu never hangs on dead hosts (RMT-02).
  3. Admin can run read-only remote queries (online/OS/uptime/logged-on user) that enrich inventory (RMT-03), and double-hop is handled by design (avoid the second hop preferred; RBCD/JEA over CredSSP; never for "sensitive, cannot be delegated" accounts) (RMT-04).

**Plans**: 3/3 plans executed
**UI hint**: no

Plans (finalized during `/gsd-plan-phase 3`):

- [x] 03-01-PLAN.md — `Connect-AdmanTarget` probe+cache ladder (WinRM → CIM/WSMan → CIM/DCOM → skip) with per-host cache + short timeouts + `Skipped` as a first-class non-error (RMT-01/02).
- [x] 03-02-PLAN.md — Read-only remote query verbs (online/OS/uptime/logged-on user) enriching inventory; verbs never branch on transport (RMT-03).
- [x] 03-03-PLAN.md — Double-hop strategy (no-second-hop preferred; RBCD/JEA over CredSSP; never for sensitive-cannot-be-delegated accounts) + documented DCOM (135 + RPC dynamic) vs WinRM (5985/5986) firewall notes (RMT-04).

### Phase 4: Bulk & Workflows (highest blast radius, last)

**Goal**: Admins can run gated bulk actions and reversible onboarding/offboarding workflows that compose proven single-object verbs under one preview+confirm+audit, with a max-count cap and typed confirmation bounding blast radius — only safe once single-object writes and the gate are proven.
**Depends on**: Phase 2 (composes single-object verbs through the Phase 0 gate); Phase 3 for remote-enriched inventory where applicable
**Requirements**: FLOW-01, FLOW-02, FLOW-03, FLOW-04, BULK-01, BULK-02, BULK-03, BULK-04 (8)
**Success Criteria** (what must be TRUE):

  1. Gated bulk runs search → preview → max-count cap check → typed count confirmation → per-item execution (BULK-01), enforces the configurable cap and typed count confirm (BULK-02), continues on single-item failure capturing per-item results and is idempotent/resume-safe where cheap (BULK-03), and no raw `Import-Csv | Set-ADUser` path exists — CSV flows only through the gated path with schema validation + preview + cap (BULK-04).
  2. Onboarding guides new-user setup (name format → role/OU template → create → password → baseline groups → audit) as one gated, audited flow (FLOW-01).
  3. Offboarding disables, strips non-protected groups (recorded for restore), moves to quarantine OU, and surfaces related cleanup (mailbox/home-dir/GPO) as a checklist only (FLOW-02), and is reversible via restore-from-quarantine with recorded groups/original location (FLOW-03).
  4. Workflows compose existing single-object verbs through the same gate (no new AD primitives) and a mid-workflow failure stops later steps for that target and logs FAIL (FLOW-04); bulk `-WhatIf` shows a truthful count, the cap trips as configured, and `Remove-ADObject` appears nowhere.

**Plans**: 3/4 plans executed
**UI hint**: no

Plans (finalized during `/gsd-plan-phase 4`):

- [x] 04-01-PLAN.md — Config template keys + gated bulk engine: normalize pipeline/CSV input, resolve + filter, enforce cap after filtering, typed-count confirmation, per-item continue-on-failure + result summary; CSV strict-schema validation (BULK-01/02/03/04).
- [x] 04-02-PLAN.md — Onboarding workflow: apply config template, validate baseline groups, create user via New-AdmanUser, add baseline groups via Add-AdmanGroupMember; mid-step failure stops and logs FAIL (FLOW-01/04).
- [x] 04-03-PLAN.md — Offboarding + restore: extend audit writer with OriginalOU/Groups, disable/strip non-protected groups/move to quarantine, read latest offboarding audit to restore; validate quarantine OU before restore (FLOW-02/03/04).
- [ ] 04-04-PLAN.md — Menu integration + manifest exports + phase exit gate: wire bulk/onboarding/offboarding/restore into Get-AdmanMenuDefinition, update adman.psd1 FunctionsToExport, run recursive PSScriptAnalyzer and full unit suite (FLOW-01..04, BULK-01..04).

### Phase 5: Hardening & Portability

**Goal**: The tool is operationally ready — fully documented, Authenticode-signed, portable across workstation and jump-host, honestly dual-edition (PS 5.1 / 7.6 LTS) backed by a real CI matrix, with encrypted-credential restore and audit tamper-evidence/rotation.
**Depends on**: Phase 0, Phase 1, Phase 2, Phase 3, Phase 4 (hardens the complete functional spine)
**Requirements**: DOC-01, DOC-02, DOC-03 (3)
**Success Criteria** (what must be TRUE):

  1. A README explains install (RSAT prereq), first-run config, and safe usage (DOC-01); a usage guide covers every menu action and parameterized function with examples (DOC-02); every public command/parameter has inline comment-based help (`Get-Help`) enforced by a lint gate (DOC-03).
  2. Runs under `AllSigned` (Authenticode-signed `.psd1/.psm1/.ps1`) and passes the CI matrix on both Windows PowerShell 5.1 and PowerShell 7.6 LTS — only then is `CompatiblePSEditions=@('Desktop','Core')` honestly claimed (no unguarded 7-only syntax).
  3. Portable across workstation and jump-host with no code changes; `.store/` is never committed; encrypted credential-file restore to a new machine re-prompts for the credential while keeping the non-secret config; audit tamper-evidence/forwarding + rotation and an out-of-tool Recycle-Bin recovery runbook are in place.

**Plans**: TBD (suggested 3-plan split below)
**UI hint**: no

Suggested plan split (refined during `/gsd-plan-phase 5`):

- [ ] 05-01: Documentation — README (install/RSAT prereq/first-run/safe usage), usage guide (every menu action + parameterized function with examples), inline comment-based help on every public command (lint-enforced) (DOC-01/02/03).
- [ ] 05-02: Dual-edition CI matrix (5.1 + 7.6) gating the `CompatiblePSEditions` claim; Authenticode signing for `AllSigned`; workstation-vs-jump-host portability verification.
- [ ] 05-03: Audit hardening (tamper-evidence/forwarding + rotation), encrypted credential-file backup/restore with re-prompt on DPAPI restore failure, Recycle-Bin recovery runbook, `.store/` commit guard.

## Progress

**Execution Order:**
Phases execute in numeric order: 0 → 1 → 2 → 3 → 4 → 5 (inserted decimals slot between their surrounding integers).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Foundation & Safety Harness | 6/6 | Complete    | 2026-07-13 |
| 1. AD Query & Reporting (read-only) | 4/4 | Complete    | 2026-07-15 |
| 2. Single-Object Lifecycle (writes begin) | 10/10 | In Progress|  |
| 3. Remote Computer Operations (isolated) | 3/3 | Complete    | 2026-07-17 |
| 4. Bulk & Workflows (highest blast radius, last) | 3/4 | In Progress|  |
| 5. Hardening & Portability | 0/3 | Not started | - |

**Total:** 6 phases, 25 plans (suggested), 58/58 v1 requirements mapped.

## Coverage Validation

| Phase | Requirement Count | Requirement IDs |
|-------|-------------------|-----------------|
| 0 | 17 | MENU-05; CONF-01..06; SAFE-01..10 |
| 1 | 13 | MENU-01..04; USER-01; COMP-01; RPT-01..07 |
| 2 | 13 | USER-02..06; LUSR-01..02; COMP-02..04; GRP-01..03 |
| 3 | 4 | RMT-01..04 |
| 4 | 8 | FLOW-01..04; BULK-01..04 |
| 5 | 3 | DOC-01..03 |

- v1 requirements: 58 total
- Mapped to phases: 58
- Unmapped: 0
- Duplicates (any req in >1 phase): 0

---
*Roadmap created: 2026-07-10 — blast-radius-ordered (safety spine → reads → single writes → remoting → bulk/workflows → hardening)*
