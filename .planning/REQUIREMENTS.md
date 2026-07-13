# Requirements: adman

**Defined:** 2026-07-10
**Core Value:** Any admin on the team can perform common AD/local-user & computer tasks correctly and safely — every destructive action is previewed (`-WhatIf`), confirmed, scoped to a managed OU, blocked from protected accounts, and written to an audit log.

> Phase assignments in Traceability are the **final** mapping — validated by the roadmapper on 2026-07-10 against the research SUMMARY.md skeleton; 58/58 v1 requirements mapped, 0 unmapped, 0 duplicates.

## v1 Requirements

Requirements for initial release. Guardrails (SAFE) are first-class — they ARE the product.

### Menu & Navigation (MENU)

- [ ] **MENU-01**: Admin can launch the tool (`Start-Adman`) and see a numbered menu of available actions
- [ ] **MENU-02**: Admin can select an action by number and be prompted for required inputs with validation
- [ ] **MENU-03**: Admin can navigate back and quit from any prompt
- [ ] **MENU-04**: Every menu action routes to the same parameterized function a senior can call directly (one code path, two speeds)
- [x] **MENU-05**: On startup the tool probes capabilities (RSAT present, domain reachable, current rights, transport availability) and shows actionable guidance if something is missing

### Configuration & Credential Store (CONF)

- [x] **CONF-01**: Tool loads a portable plain-JSON **non-secret** config (managed-OU roots, deny-list, bulk cap, audit/report paths, transport order/timeouts) at startup
- [x] **CONF-02**: Tool fails closed (refuses writes) if managed-OU is empty or the deny-list/config fails to load
- [x] **CONF-03**: Admin can save and reload the config for backup/restore (portable, diff-friendly across machines)
- [x] **CONF-04**: On explicit "remember me," the tool writes a **separate** DPAPI-encrypted credential file in `.store/`; restore on a different machine/user re-prompts for the credential
- [x] **CONF-05**: Both config and credential files live in the gitignored `.store/` folder; the tool never writes secrets to the repo or to logs
- [x] **CONF-06**: Tool uses the logged-in admin's credentials by default (pass-through); checks rights before each task and prompts for domain-admin creds only when rights are insufficient

### Safety Guardrails (SAFE) — cross-cutting, v1 must-have

- [x] **SAFE-01**: Every destructive action supports `-WhatIf`/dry-run that previews exactly what would change, per object
- [x] **SAFE-02**: Every destructive action requires confirmation scaled to blast radius (y/n for single; typed token + count for bulk)
- [ ] **SAFE-03**: Every action (including dry-runs) appends a structured audit record (who/what/when/scope/target/count/WhatIf/result); never logs passwords/secrets
- [ ] **SAFE-04**: Audit logging is fail-closed — if the audit record cannot be written, the destructive action is refused rather than run unaudited
- [x] **SAFE-05**: A startup-loaded deny-list hard-blocks matching targets before any action
- [x] **SAFE-06**: Protected-account guard refuses targets that are (recursively) members of Domain/Enterprise/Schema Admins, Account/Backup/Server Operators, or local Administrators, plus gMSA/service accounts — via runtime well-known-SID resolution, never `adminCount` alone
- [x] **SAFE-07**: Managed-OU scoping refuses any target whose DN is not under a configured managed-OU root
- [x] **SAFE-08**: All write verbs route through one **non-exported** mutation gate (`Invoke-AdmanMutation`); no public/exported function calls AD write cmdlets directly (enforced by a lint + Pester guard)
- [x] **SAFE-09**: "Delete" is reversible — disable + move to quarantine OU + record original location/groups for restore; the tool ships **no** hard-delete verb
- [x] **SAFE-10**: The gate uses identical target resolution for preview and execute, so the preview cannot lie

### AD User Lifecycle (USER)

- [ ] **USER-01**: Admin can search/view users by name, `sAMAccountName`, or display name (scoped to managed OU)
- [ ] **USER-02**: Admin can create a single user with required attributes (name, `sAMAccountName`, UPN, OU, password, must-change-at-next-logon, enabled)
- [ ] **USER-03**: Admin can disable and enable a user (through the gate)
- [ ] **USER-04**: Admin can reset a user's password (optionally force change at next logon and unlock) without ever echoing or logging the password
- [ ] **USER-05**: Admin can unlock a locked account (reads `LockedOut` first; pinned to the PDC emulator)
- [ ] **USER-06**: Admin can move a user to another OU within managed scope

### Local (Per-Machine) User Lifecycle (LUSR)

- [ ] **LUSR-01**: Admin can create/disable/enable/reset-password/remove a local user on a target machine via the `LocalAccounts` module (mutations through the gate)
- [ ] **LUSR-02**: Admin can manage local group membership (e.g., local Administrators) on a target machine

### AD Computer Lifecycle (COMP)

- [ ] **COMP-01**: Admin can search/view computers by name (scoped to managed OU)
- [ ] **COMP-02**: Admin can disable/enable a computer (through the gate)
- [ ] **COMP-03**: Admin can move a computer to another OU within managed scope
- [ ] **COMP-04**: Admin can reset a computer account / repair the secure channel (with guidance on which method applies)

### Group Membership (GRP)

- [ ] **GRP-01**: Admin can add a user to one or more groups (through the gate)
- [ ] **GRP-02**: Admin can remove a user from a group (through the gate)
- [ ] **GRP-03**: Tool refuses adding any principal to a protected group (Domain Admins etc.) per SAFE-06

### Reporting & Inventory (RPT)

- [ ] **RPT-01**: Admin can view results as a console table (and via `Out-GridView` where available)
- [ ] **RPT-02**: Admin can export any report to CSV (`-NoTypeInformation`) for Excel/tickets
- [ ] **RPT-03**: Admin can export any report to a self-contained single-file HTML report
- [ ] **RPT-04**: Stale/inactive report uses replicated `lastLogonTimestamp` with a ≥14-day grace buffer and buckets never-logged-on (`0`/1601) separately — never per-DC `lastLogon`
- [ ] **RPT-05**: Account-state reports render Disabled, Expired, Locked, and Password-Expired as four distinct states (via `Search-ADAccount`, not raw `userAccountControl` bit math)
- [ ] **RPT-06**: Inventory report shows OS version and basic computer info (AD attributes; enriched when remote reachable)
- [ ] **RPT-07**: Startup preflight reports domain recovery posture (Recycle Bin / FFL) rather than assuming it

### Remote Computer Operations (RMT)

- [ ] **RMT-01**: Tool probes each target with a WinRM → CIM/WSMan → CIM/DCOM → skip ladder and caches the working transport per host
- [ ] **RMT-02**: Unreachable hosts are reported as `Skipped` (a first-class non-error outcome), not failures; the menu never hangs on dead hosts (short timeouts)
- [ ] **RMT-03**: Admin can run read-only remote queries (online/OS/uptime/logged-on user) that enrich inventory
- [ ] **RMT-04**: Remote operations handle the double-hop by design (avoid second hop preferred; RBCD/JEA over CredSSP; never for "sensitive, cannot be delegated" accounts)

### Onboarding / Offboarding Workflows (FLOW)

- [ ] **FLOW-01**: Onboarding workflow guides new-user setup (name format → role/OU template → create → password → baseline groups → audit) as one gated, audited flow
- [ ] **FLOW-02**: Offboarding workflow disables the user, strips non-protected groups (recorded for restore), moves to quarantine OU, and surfaces related cleanup (mailbox/home-dir/GPO) as a **checklist only**
- [ ] **FLOW-03**: Offboarding is reversible — admin can restore a quarantined user with recorded groups/original location
- [ ] **FLOW-04**: Workflows compose existing single-object verbs through the same gate (no new AD primitives); a mid-workflow failure stops later steps for that target and logs FAIL

### Bulk Operations (BULK)

- [ ] **BULK-01**: Admin can run a gated bulk action: build target set from search → preview → max-count cap check → typed count confirmation → per-item execution
- [ ] **BULK-02**: Bulk enforces a configurable max-count cap and a typed confirmation of the count before executing
- [ ] **BULK-03**: Bulk continues on single-item failure, captures per-item results, and is idempotent/resume-safe where cheap
- [ ] **BULK-04**: No raw `Import-Csv | Set-ADUser` path exists — CSV ingestion flows only through the gated bulk path with schema validation + preview + cap

### Documentation (DOC)

- [ ] **DOC-01**: A README explains install (RSAT prereq), first-run config, and safe usage
- [ ] **DOC-02**: A usage guide covers every menu action and parameterized function with examples
- [ ] **DOC-03**: Every public command/parameter has inline comment-based help (`Get-Help`), enforced by a lint gate

## v2 Requirements

Deferred to a future release. Tracked but not in the current roadmap.

### Reporting & Remote

- **RPT-V01**: Saved queries / favorites (Hyena Query Library-lite) for senior fast-path
- **RMT-V01**: Remote **live actions** (restart service, trigger `gpupdate`, etc.) behind the identical gate — only after the read-only query path is proven safe

### Workflows & Bulk

- **FLOW-V01**: Multiple onboarding templates per role (single-template flow ships in v1)
- **BULK-V01**: Full idempotent/resume-safe bulk (persisted job state) once real bulk jobs show partial-failure pain
- **FLOW-V02**: HR-CSV-driven provisioning — only with full schema validation + preview + cap (never autonomous)

### Directory / Platform

- **RPT-V02**: Read-only GPO reporting (audit/compliance ask)
- **PLAT-V01**: Scheduling of reports / approved workflows — only after human-in-the-loop is proven; never unattended destructive bulk
- **PLAT-V02**: Compiled `.exe` distribution (ps2exe) — packaging convenience, not capability
- **PLAT-V03**: Elevation / stored-privileged-credential model — only if delegation becomes a real requirement; needs a proper secret store + redesign
- **PLAT-V04**: Multi-domain / cross-forest support — only if the environment grows to need it

## Out of Scope

Explicitly excluded in v1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Hard-delete of AD objects | Irreversible; breaks the safety property — disable + quarantine instead (SAFE-09) |
| Entra ID / Azure AD / M365 / cloud directory | Environment is on-prem AD only |
| Modifying protected accounts or objects outside the managed OU | Refused by design for blast-radius control (SAFE-06/07) |
| RBAC-delegation / approval-workflow engine | Conflicts with pass-through least-privilege; becomes an IGA project |
| Credential vault / stored privileged creds (v1) | Secret-management + audit risk; pass-through + opt-in DPAPI only |
| GPO authoring / deployment | High blast radius, different skill domain; read/report at most (v2) |
| Exchange / mailbox / home-directory cleanup automation | Out of on-prem-AD scope; surfaced as a cleanup **checklist** (FLOW-02) |
| Raw `Import-Csv \| Set-ADUser` with no validation | Classic mass-change foot-gun; only the gated bulk path exists (BULK-04) |
| Schema extension / custom AD attributes | Irreversible forest-wide change; out of team-tool scope |
| Autonomous "decide which accounts to disable" remediation | Removes the human from high-blast-radius decisions; conflicts with the safety property |
| GUI desktop app / web UI | TUI only for v1 |
| Cross-forest / multi-domain (v1) | Trust/credential complexity the single-domain environment doesn't need |

## Traceability

Final mapping (validated 2026-07-10). Phases follow the research skeleton: **0 Foundation/Safety → 1 Read-only reporting → 2 Single-object writes → 3 Remoting → 4 Bulk/workflows → 5 Hardening**.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MENU-01 | Phase 1 | Pending |
| MENU-02 | Phase 1 | Pending |
| MENU-03 | Phase 1 | Pending |
| MENU-04 | Phase 1 | Pending |
| MENU-05 | Phase 0 | Complete |
| CONF-01 | Phase 0 | Complete |
| CONF-02 | Phase 0 | Complete |
| CONF-03 | Phase 0 | Complete |
| CONF-04 | Phase 0 | Complete |
| CONF-05 | Phase 0 | Complete |
| CONF-06 | Phase 0 | Complete |
| SAFE-01 | Phase 0 | Complete |
| SAFE-02 | Phase 0 | Complete |
| SAFE-03 | Phase 0 | Pending |
| SAFE-04 | Phase 0 | Pending |
| SAFE-05 | Phase 0 | Complete |
| SAFE-06 | Phase 0 | Complete |
| SAFE-07 | Phase 0 | Complete |
| SAFE-08 | Phase 0 | Complete |
| SAFE-09 | Phase 0 | Complete |
| SAFE-10 | Phase 0 | Complete |
| USER-01 | Phase 1 | Pending |
| USER-02 | Phase 2 | Pending |
| USER-03 | Phase 2 | Pending |
| USER-04 | Phase 2 | Pending |
| USER-05 | Phase 2 | Pending |
| USER-06 | Phase 2 | Pending |
| LUSR-01 | Phase 2 | Pending |
| LUSR-02 | Phase 2 | Pending |
| COMP-01 | Phase 1 | Pending |
| COMP-02 | Phase 2 | Pending |
| COMP-03 | Phase 2 | Pending |
| COMP-04 | Phase 2 | Pending |
| GRP-01 | Phase 2 | Pending |
| GRP-02 | Phase 2 | Pending |
| GRP-03 | Phase 2 | Pending |
| RPT-01 | Phase 1 | Pending |
| RPT-02 | Phase 1 | Pending |
| RPT-03 | Phase 1 | Pending |
| RPT-04 | Phase 1 | Pending |
| RPT-05 | Phase 1 | Pending |
| RPT-06 | Phase 1 | Pending |
| RPT-07 | Phase 1 | Pending |
| RMT-01 | Phase 3 | Pending |
| RMT-02 | Phase 3 | Pending |
| RMT-03 | Phase 3 | Pending |
| RMT-04 | Phase 3 | Pending |
| FLOW-01 | Phase 4 | Pending |
| FLOW-02 | Phase 4 | Pending |
| FLOW-03 | Phase 4 | Pending |
| FLOW-04 | Phase 4 | Pending |
| BULK-01 | Phase 4 | Pending |
| BULK-02 | Phase 4 | Pending |
| BULK-03 | Phase 4 | Pending |
| BULK-04 | Phase 4 | Pending |
| DOC-01 | Phase 5 | Pending |
| DOC-02 | Phase 5 | Pending |
| DOC-03 | Phase 5 | Pending |

**Coverage (validated 2026-07-10):**

- v1 requirements: 58 total
- Mapped to phases: 58
- Unmapped: 0 ✓
- Duplicates (any req in >1 phase): 0 ✓
- Per-phase counts: P0=17, P1=13, P2=13, P3=4, P4=8, P5=3

---
*Requirements defined: 2026-07-10*
*Last updated: 2026-07-10 — traceability finalized during roadmap creation*
