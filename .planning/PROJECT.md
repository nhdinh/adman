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
- [ ] AD user lifecycle — create, disable, enable, move OU, reset password, unlock, manage group membership
- [ ] AD computer lifecycle — disable, enable, move OU; report last-logon / stale / OS version
- [ ] Reporting & inventory — console tables, CSV export, and self-contained HTML reports
- [ ] Remote computer operations — query/live-action on remote machines with auto-detect fallback (WinRM → CIM/WMI → skip)
- [ ] Provisioning & onboarding workflow — standardized new-user / new-computer setup
- [ ] Offboarding workflow — disable + move to quarantine OU, strip groups, surface related cleanup
- [ ] Safety guardrails (v1 must-have) — `-WhatIf`/dry-run on every destructive action, confirmation prompts, structured audit log (who/what/when), startup-loaded deny-list, protection of admin-group members & service accounts, managed-OU scoping, bulk operations gated by preview + typed confirmation + max-count cap
- [ ] Portability — runs on an admin workstation with RSAT or on a management server, using the logged-in admin's own domain credentials (pass-through)

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
- **Credential model:** Pass-through — the tool uses the logged-in admin's own domain account (least-privilege, no stored secrets in v1). Elevation prompts / stored privileged creds are a future consideration, not v1.

## Constraints

- **Tech stack**: PowerShell — team standard and the native AD admin tooling on Windows; PowerShell 5.1 compatibility is required because that's what ships on servers/workstations by default.
- **Directory**: On-prem Active Directory only — current environment has no Entra/cloud dependency.
- **Remoting**: Cannot assume WinRM on targets — must degrade to CIM/WMI or skip per host.
- **Security**: Pass-through credentials (logged-in admin); least-privilege; no credential storage in v1 — avoids secret-management complexity and audit risk.
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
| Pass-through credentials (logged-in admin) | Least-privilege; no stored secrets; simplest audit story | — Pending |
| Reports: console + CSV + HTML | Interactive use, Excel handoff, and shareable management reports | — Pending |
| Built-in critical accounts (`krbtgt`, `Guest`, built-in `Administrator`) baseline-protected | Catastrophic if touched — confirm as a v1 default at requirements | ⚠️ Confirm at requirements |

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
