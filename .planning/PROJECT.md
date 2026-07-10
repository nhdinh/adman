# adman (working name)

## What This Is

A menu-driven (interactive TUI) PowerShell toolkit that lets a small, mixed-skill IT team manage users and computers in an on-prem Active Directory domain. It consolidates the four everyday jobs — AD object lifecycle (create/disable/move/reset), reporting & inventory, remote computer operations, and provisioning/offboarding — behind one guided interface with strong safety guardrails so a less-experienced admin cannot accidentally damage the directory.

> The name `adman` ("AD manager") is a placeholder taken from the project folder. Confirm or rename at requirements.

## Core Value

**Any admin on the team can perform common AD user/computer tasks correctly and safely** — every destructive action is previewed (`-WhatIf`/dry-run), confirmed, scoped to a managed OU, blocked from protected accounts, and written to an audit log. If everything else fails, this safety property must hold.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. Hypotheses until shipped. -->

- [ ] Interactive menu (TUI) entry point — discoverable, guided prompts, usable by mixed-skill admins
- [ ] AD/ Local user lifecycle — create, disable, enable, move OU, reset password, unlock, manage group membership
- [ ] AD computer lifecycle — disable, enable, move OU; report last-logon / stale / OS version
- [ ] Reporting & inventory — console tables, CSV export, and self-contained HTML reports
- [ ] Remote computer operations — query/live-action on remote machines with auto-detect fallback (WinRM → CIM/WMI → skip)
- [ ] Provisioning & onboarding workflow — standardized new-user / new-computer setup
- [ ] Offboarding workflow — disable + move to quarantine OU, strip groups, surface related cleanup
- [ ] Safety guardrails (v1 must-have) — `-WhatIf`/dry-run on every destructive action, confirmation prompts, structured audit log (who/what/when), startup-loaded deny-list, protection of admin-group members & service accounts, managed-OU scoping, bulk operations gated by preview + typed confirmation + max-count cap
- [ ] Portability — runs on an admin workstation with RSAT or on a management server, asking for domain admin credentials only if the logged-in user lacks sufficient rights.
- [ ] Save & load configuration — logged in admin credentials,managed OU, deny-list, audit log path, report path, etc. stored in a single config file for easy backup and restore. Configuration MUST BE encrypted.
- [ ] Documentation — README, usage guide, and inline help for every command/parameter

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Entra ID / Azure AD / M365 / cloud directory — environment is on-prem AD only
- Hard-delete of directory objects — delete means disable + quarantine by design (reversible)
- Modifying protected accounts (admin-group members, service/gMSA accounts, deny-listed) or objects outside the managed OU — refused by design for blast-radius control
- Compiled `.exe` distribution (ps2exe) — defer to v2; ship as script/module first
- GUI desktop app or web UI — TUI only for v1
- Exchange / mailbox / home-directory cleanup during offboarding — defer; out of on-prem-AD scope, surface as a checklist only
- Group Policy (GPO) authoring/deployment — read/report at most; not a management target in v1

## Context

- **Environment:** Single on-prem Active Directory domain. Team administers users and computers today via ADUC and a loose collection of personal `.ps1` scripts — inconsistent, no audit trail, and risky in less-experienced hands.
- **Team:** Small IT team, mixed skill levels. The tool must be discoverable (menu) for juniors and fast for seniors, and must make the safe path the easy path.
- **Runtime:** Windows PowerShell 5.1 (and ideally PowerShell 7.x). Relies on the **ActiveDirectory module (RSAT)** for AD cmdlets; **WMI/CIM** for inventory; **PSRemoting/WinRM** where enabled for remote ops. Because WinRM is not guaranteed on every target, remote operations must **auto-detect and fall back** (WinRM → CIM → skip gracefully).
- **Execution location:** Must be portable — runs on an admin workstation that has RSAT, or on a management server/jump host, with no code changes between the two.
- **Credential model:** Domain admin must be logged in to use this tool. If the logged-in user lacks sufficient rights, the tool prompts for credentials. Credentials are stored encrypted in a single config file for easy backup/restore. On each script task run, check the logged-in user’s rights and prompt for credentials if needed. No credentials are stored in plaintext or in a secret vault in v1.

## Constraints

- **Tech stack**: PowerShell — team standard and the native AD admin tooling on Windows; PowerShell 5.1 compatibility is required because that's what ships on servers/workstations by default.
- **Directory**: On-prem Active Directory only — current environment has no Entra/cloud dependency.
- **Remoting**: Cannot assume WinRM on targets — must degrade to CIM/WMI or skip per host.
- **Security**: Pass-through by default — rights checked each task; prompt for domain-admin creds only when insufficient. **Config is split:** a portable plain-JSON **non-secret** config (managed OU, deny-list, caps, paths — diff/backup friendly) plus a **separate, opt-in** DPAPI-encrypted **credential** file (written only on explicit "remember me"; re-prompts on restore failure). Secrets encrypted; non-secret config portable. Both files live in the gitignored `.store/` folder — **NEVER** push `.store/` to source control. No separate secret vault in v1.
- **Dependency**: ActiveDirectory module (RSAT) must be present where the tool runs — document the install/prerequisite, don't bundle it.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Interactive menu (TUI) as the primary interface | Mixed-skill team; discoverability and guided input reduce mistakes | — Pending |
| Full guardrails in v1 (dry-run, confirm, audit log) | AD writes are high-blast-radius and the team is mixed-skill | — Pending |
| Remote ops auto-detect WinRM → CIM → skip | WinRM not guaranteed on every host; portability matters | — Pending |
| "Delete" = disable + move to quarantine OU | Reversible, safe default; no accidental hard-deletes | — Pending |
| Managed-OU scoping + deny-list + admin/service-account protection | Bounds blast radius; protects high-value/break-glass accounts | — Pending |
| Bulk via preview + typed confirmation + max-count cap | Allows efficiency without unbounded mass-change risk | — Pending |
| Pass-through by default; prompt for domain-admin creds only when rights insufficient | Least-privilege with a recoverable fallback for junior admins | — Pending |
| Config/credential split: portable plain-JSON **non-secret** config + separate opt-in DPAPI-encrypted **credential** file, both in gitignored `.store/` | DPAPI is machine+user-bound, so fully-encrypted config cannot be portable; split keeps secrets encrypted AND config backup/restore/diff-friendly; re-prompt on restore | ✓ Decided |
| Local (per-machine) user management in addition to AD users | Remote-computer-ops pillar needs local-account lifecycle on member machines | — Pending |
| Documentation as a first-class deliverable (README, usage guide, inline help) | Mixed-skill team; safe, correct usage must be obvious | — Pending |
| Reports: console + CSV + HTML | Interactive use, Excel handoff, and shareable management reports | — Pending |
| No hard-coded built-in RID baseline; protection via recursive admin-group membership + custom deny-list only | User decision: rely on group/deny-list rather than hard-coding RID 500/501/502; `krbtgt`/Guest/RID-500 covered implicitly via deny-list seed | ✓ Decided |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-10 after initialization*
