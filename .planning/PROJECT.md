# adman (working name)

## What This Is

A menu-driven (interactive TUI) PowerShell toolkit that lets a small, mixed-skill IT team manage users and computers in an on-prem Active Directory domain. It consolidates the four everyday jobs — AD object lifecycle (create/disable/move/reset), reporting & inventory, remote computer operations, and provisioning/offboarding — behind one guided interface with strong safety guardrails so a less-experienced admin cannot accidentally damage the directory.

> The name `adman` ("AD manager") is a placeholder taken from the project folder. Confirm or rename at requirements.

## Core Value

**Any admin on the team can perform common AD user/computer tasks correctly and safely** — every destructive action is previewed (`-WhatIf`/dry-run), confirmed, scoped to a managed OU, blocked from protected accounts, and written to an audit log. If everything else fails, this safety property must hold.

## Requirements

### Validated (shipped in v1.0)

- Interactive menu (TUI) entry point — flat `while`-loop shell, numbered menu, validated prompts, routes every selection to the same Public verbs seniors call directly (MENU-01..04). Validated in Phase 01.
- Reporting & inventory (read-only) — console/CSV/self-contained-HTML renderers (RPT-01/02/03), OS/inventory report (RPT-06), scoped user/computer search (USER-01, COMP-01), stale/account-state/recovery-posture reports with correct AD semantics (RPT-04/05/07). Validated in Phase 01.
- AD / Local user lifecycle — create, disable, enable, move OU, reset password, unlock, manage group membership (USER-02..06, LUSR-01/02). Validated in Phase 02.
- AD computer lifecycle — disable, enable, move OU, reset computer account / secure channel (COMP-02..04). Validated in Phase 02.
- Remote computer operations — query/live-action on remote machines with auto-detect fallback (WinRM → CIM/WSMan → CIM/DCOM → skip) (RMT-01..04). Validated in Phase 03.
- Provisioning & onboarding workflow — standardized new-user setup (FLOW-01). Validated in Phase 04.
- Offboarding workflow — disable + move to quarantine OU, strip groups, restore from audit state (FLOW-02/03/04). Validated in Phase 04.
- Safety guardrails (v1 must-have) — `-WhatIf`/dry-run, confirmation prompts, structured audit log, startup-loaded deny-list, protection of admin-group members & service accounts, managed-OU scoping, bulk preview + typed confirmation + max-count cap (SAFE-01..10, BULK-01..04). Validated across Phases 00–04.
- Documentation — README, usage guide, inline help for every command/parameter, recovery runbook (DOC-01/02/03). Validated in Phase 05.
- Authenticode signing + dual-edition CI — `AllSigned` proof on Windows PowerShell 5.1 and PowerShell 7.6 LTS, honest `CompatiblePSEditions = @('Desktop','Core')`. Validated in Phase 05.
- Audit hardening — SHA-256 hash chain, rotation, event-log escalation on OUTCOME failure, `.store/` commit guard. Validated in Phase 05.

### Active (next milestone)

- [ ] Saved queries / favorites (RPT-V01)
- [ ] Remote live actions (restart service, trigger `gpupdate`, etc.) behind the identical gate (RMT-V01)
- [ ] Multiple onboarding templates per role (FLOW-V01)
- [ ] Full idempotent/resume-safe bulk with persisted job state (BULK-V01)
- [ ] HR-CSV-driven provisioning with full schema validation + preview + cap (FLOW-V02)
- [ ] Read-only GPO reporting (RPT-V02)

### Out of Scope

- Entra ID / Azure AD / M365 / cloud directory — environment is on-prem AD only
- Hard-delete of directory objects — delete means disable + quarantine by design (reversible)
- Modifying protected accounts (admin-group members, service/gMSA accounts, deny-listed) or objects outside the managed OU — refused by design for blast-radius control
- Compiled `.exe` distribution (ps2exe) — defer to v2; ship as script/module first
- GUI desktop app or web UI — TUI only for v1
- Exchange / mailbox / home-directory cleanup during offboarding — defer; out of on-prem-AD scope, surface as a checklist only
- Group Policy (GPO) authoring/deployment — read/report at most; not a management target in v1
- Elevation / stored-privileged-credential model — only if delegation becomes a real requirement; needs a proper secret store + redesign
- Multi-domain / cross-forest support — only if the environment grows to need it
- Scheduling of reports / approved workflows — only after human-in-the-loop is proven; never unattended destructive bulk

## Context

- **Environment:** Single on-prem Active Directory domain. Team administers users and computers today via ADUC and a loose collection of personal `.ps1` scripts — inconsistent, no audit trail, and risky in less-experienced hands.
- **Team:** Small IT team, mixed skill levels. The tool must be discoverable (menu) for juniors and fast for seniors, and must make the safe path the easy path.
- **Runtime:** Windows PowerShell 5.1 (primary baseline) and PowerShell 7.6 LTS. Relies on the **ActiveDirectory module (RSAT)** for AD cmdlets; **CIM/WMI** for inventory; **PSRemoting/WinRM** where enabled for remote ops. Remote operations auto-detect and fall back (WinRM → CIM/WSMan → CIM/DCOM → skip gracefully).
- **Execution location:** Runs on an admin workstation with RSAT or on a management server/jump host, with no code changes between the two.
- **Credential model:** Pass-through by default. If the logged-in user lacks sufficient rights, the tool prompts for credentials. An opt-in DPAPI-encrypted credential file can be written with explicit "remember me"; restore to a different machine/user re-prompts. No credentials are stored in plaintext or in a secret vault in v1.
- **Current state:** v1.0 shipped 2026-07-23. 58/58 v1 requirements complete. ~51,260 lines of PowerShell across 811 files. Dual-edition CI matrix green. SECURITY.md verifies 23/23 Phase 5 threats closed.

## Constraints

- **Tech stack**: PowerShell — team standard and the native AD admin tooling on Windows; PowerShell 5.1 compatibility required because that's what ships on servers/workstations by default.
- **Directory**: On-prem Active Directory only — current environment has no Entra/cloud dependency.
- **Remoting**: Cannot assume WinRM on targets — must degrade to CIM/WMI or skip per host.
- **Security**: Pass-through by default — rights checked each task; prompt for domain-admin creds only when insufficient. **Config is split:** a portable plain-JSON **non-secret** config plus a **separate, opt-in** DPAPI-encrypted **credential** file. Secrets encrypted; non-secret config portable. Both files live in the gitignored `.store/` folder — **NEVER** push `.store/` to source control. No separate secret vault in v1.
- **Dependency**: ActiveDirectory module (RSAT) must be present where the tool runs — document the install/prerequisite, don't bundle it.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Interactive menu (TUI) as the primary interface | Mixed-skill team; discoverability and guided input reduce mistakes | ✓ Shipped v1.0 |
| Full guardrails in v1 (dry-run, confirm, audit log) | AD writes are high-blast-radius and the team is mixed-skill | ✓ Shipped v1.0 |
| Remote ops auto-detect WinRM → CIM/WSMan → CIM/DCOM → skip | WinRM not guaranteed on every host; portability matters | ✓ Shipped v1.0 |
| "Delete" = disable + move to quarantine OU | Reversible, safe default; no accidental hard-deletes | ✓ Shipped v1.0 |
| Managed-OU scoping + deny-list + admin/service-account protection | Bounds blast radius; protects high-value/break-glass accounts | ✓ Shipped v1.0 |
| Bulk via preview + typed confirmation + max-count cap | Allows efficiency without unbounded mass-change risk | ✓ Shipped v1.0 |
| Pass-through by default; prompt for domain-admin creds only when rights insufficient | Least-privilege with a recoverable fallback for junior admins | ✓ Shipped v1.0 |
| Config/credential split: portable plain-JSON **non-secret** config + separate opt-in DPAPI-encrypted **credential** file, both in gitignored `.store/` | DPAPI is machine+user-bound; split keeps secrets encrypted AND config backup/restore/diff-friendly; re-prompt on restore | ✓ Shipped v1.0 |
| Local (per-machine) user management in addition to AD users | Remote-computer-ops pillar needs local-account lifecycle on member machines | ✓ Shipped v1.0 |
| Documentation as a first-class deliverable (README, usage guide, inline help) | Mixed-skill team; safe, correct usage must be obvious | ✓ Shipped v1.0 |
| Reports: console + CSV + HTML | Interactive use, Excel handoff, and shareable management reports | ✓ Shipped v1.0 |
| No hard-coded built-in RID baseline; protection via recursive admin-group membership + custom deny-list only | User decision: rely on group/deny-list rather than hard-coding RID 500/501/502; `krbtgt`/Guest/RID-500 covered implicitly via deny-list seed | ✓ Shipped v1.0 |
| Dual PowerShell edition support: Windows PowerShell 5.1 + PowerShell 7.6 LTS | Primary baseline (5.1) + modern LTS (7.6) with honest `CompatiblePSEditions` claim | ✓ Shipped v1.0 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After v1.0 milestone:**
1. All v1 requirements moved to Validated.
2. v2 requirements moved to Active.
3. Out of Scope audited and updated with v2 candidates.
4. Context updated with current shipped state.
5. All key decisions marked shipped.

---
*Last updated: 2026-07-23 after v1.0 milestone*
