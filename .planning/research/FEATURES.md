# Feature Research

**Domain:** On-prem Active Directory user/computer administration toolkit (menu-driven PowerShell TUI for a small, mixed-skill IT team)
**Researched:** 2026-07-10
**Confidence:** HIGH

**Confidence basis:** This is a mature, slow-moving domain. The native baseline (ADUC/RSAT), the two long-standing commercial consoles (ManageEngine ADManager Plus, SystemTools Hyena), and the PowerShell `ActiveDirectory` module feature sets are stable and well documented. Current competitor feature sets verified against vendor/4sysops pages (see Sources). Where the recommendation is an opinion about *scope for a small team tool* (rather than a fact about a competitor), it is labeled as such.

---

## Feature Landscape

The tool covers four jobs, bound together by one guided interface and one safety system. Features are listed under the job they serve, but the **Safety & Guardrails** category is cross-cutting and treated as first-class — it is the Core Value from PROJECT.md, not a polish item.

### Table Stakes (Admins Expect These)

These replicate what ADUC already does (badly) and what every tool in the space does. Missing them = "why would I use this instead of ADUC?" Admins give no credit for having them; they leave if they're absent.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Find/search users & computers by name, `samAccountName`, display name | ADUC "Find" / Saved Queries is the first thing an admin opens | LOW | Wrap `Get-ADUser`/`Get-ADComputer -Filter` / `-LDAPFilter`; wildcards; return objects the rest of the tool can act on. Foundation for bulk target sets. |
| View/read object properties (the "Attribute Editor" equivalent) | Admins inspect before they touch | LOW | Read-mostly; expose common props + an "advanced/all attributes" view. Read-only = no guardrails needed, cheap to ship. |
| Create user (single) with required attributes | Core AD job | MEDIUM | Name, `sAMAccountName`, UPN, OU, password, "must change at next logon", enabled. Template-driven variant is a differentiator (below). |
| Disable / Enable user | Constant offboard/rejoin task | LOW | `Disable-ADAccount` / `Enable-ADAccount`. Destructive-adjacent → runs through guardrail core. |
| Reset password | The single most common help-desk task | LOW | `Set-ADAccountPassword` + `Set-ADUser -ChangePasswordAtLogon`. Offer "unlock on reset". Never echo the password; never log it. |
| Unlock account | Lockouts are routine | LOW | `Unlock-ADAccount`. Read `LockedOut` first; only act if locked. |
| Move user/computer between OUs | Reorgs, quarantine | LOW | `Move-ADObject`. Must validate destination is inside managed-OU scope (guardrail). |
| Add/remove group membership | Daily access changes | MEDIUM | `Add-ADGroupMember` / `Remove-ADGroupMember`; support one user→many groups and many users→one group. **Refuse adding to protected groups** (Domain Admins etc.) unless explicitly allowed — see guardrails. |
| Disable / Enable / move computer | Computer lifecycle parity with users | LOW | Same cmdlets, `computer` objectClass. |
| Reset computer account (secure channel) | "Trust relationship failed" fix | MEDIUM | `Reset-ComputerMachinePassword` (local) / `Test-ComputerSecureChannel -Repair` / ADUC "Reset Account". Document when each applies. |
| Last-logon / stale computer report | Hygiene & audits expect it | MEDIUM | Use `lastLogonTimestamp` (replicated, ~9–14 day skew) NOT `lastLogon` (per-DC, not replicated). Flag this gotcha for PITFALLS. |
| OS version / inventory report | Basic fleet visibility | MEDIUM | `operatingSystem`/`operatingSystemVersion` attrs for AD-side; enrich with CIM/WinRM when reachable (see remote ops). |
| Console table output | Immediate readability | LOW | `Format-Table`/`Out-GridView`-style rendering from a shared data layer. |
| CSV export | Universal handoff (Excel, tickets) | LOW | `Export-Csv -NoTypeInformation` from the same shared data layer as console/HTML. |
| Remote reachability detection + basic query | Know if a host is alive before acting | MEDIUM | Online/offline, OS, uptime, logged-on user; auto-detect WinRM→CIM→skip (differentiator below, but the *detect* part is table stakes). |
| Run with logged-in admin's credentials (pass-through) | Least-privilege baseline; no secrets | LOW | Default cmdlet behavior. The absence of a credential store is itself a table-stakes property for v1. |
| Clear, actionable errors (RSAT missing, host unreachable, access denied) | Mixed-skill team; opaque errors cause mistakes | MEDIUM | Detect `ActiveDirectory` module absence at startup with install guidance; translate LDAP/WinRM errors into "what to do." |

### Differentiators (Competitive Advantage / Force Multipliers)

These are why a team would standardize on this tool instead of "ADUC + a folder of personal `.ps1` scripts." They map directly to the Core Value: **any admin can do common tasks correctly and safely.**

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Unified guided TUI menu** (discoverable for juniors, fast for seniors) | The core differentiator vs loose scripts: one entry point, consistent prompts, no "which script was it?" | MEDIUM | Read-host menu loop with numbered actions, breadcrumbs, back/quit, context-aware prompts. Keep senior fast-path (parameterized functions) underneath so the menu calls the same code as direct invocation. |
| **Safety system as a shared layer** (not per-script) | Force multiplier: every write is dry-run/confirm/audit/scope/deny/protected by construction. Loose scripts have none of this; ADUC has minimal. | HIGH | One `Invoke-SafeADChange` wrapper that all write verbs call. Build this FIRST; everything composes on it. |
| **`-WhatIf`/dry-run on every destructive action** | Preview blast radius before committing | MEDIUM | Leverage native `-WhatIf` on AD cmdlets where present; emulate for composite actions (workflows) by printing the planned steps. |
| **Typed confirmation for destructive/bulk ops** | "Type DISABLE 23 to confirm" prevents Enter-key accidents | LOW | Scale confirmation strength to blast radius (single = y/n; bulk = typed token + count). |
| **Structured audit log (who/what/when/scope/result)** | ADUC has none; commercial tools tie it to their platform. We get it free from the shared wrapper. | MEDIUM | Append-only JSONL or CSV: timestamp, invoking user (`$env:USERDOMAIN\$env:USERNAME`), action, target DN, WhatIf?, result, error. Never write passwords. |
| **Startup-loaded deny-list** | Hard "never touch" set survives restarts; obvious safety win | LOW | JSON/CSV config loaded at launch; matched before any action. Built-ins `krbtgt`, `Guest`, default `Administrator` baseline-protected (confirm at requirements). |
| **Protected-account handling** | Catastrophic if a junior disables an admin/service account | MEDIUM | Detect via `AdminCount=1`, membership in protected groups (Domain/Enterprise/Schema Admins, Account/Backup/Server Operators, etc.), and `msDS-GroupManagedServiceAccount`/`msDS-ManagedServiceAccount`. Refuse by default; require explicit break-glass override that is itself audited. Flag `AdminCount`/`adminSDHolder` nuances for PITFALLS. |
| **Managed-OU scoping** | Delegation-by-constraint: tool refuses to act outside configured OUs | MEDIUM | Configured managed OU roots; resolve target DN and reject if not under a root. Bounds blast radius even if the invoking admin has broader rights. |
| **Bulk operations gated by preview + typed confirmation + max-count cap** | Efficiency without unbounded mass-change risk — ADUC has no real bulk; Hyena/ADManager charge/assume skill | HIGH | Target set (from search) → preview report → max-count cap check → typed confirm → per-item execution that continues on single-item failure. |
| **Onboarding workflow (standardized new-user)** | Consistency force multiplier; removes per-admin drift | HIGH | One guided flow: name-format → role template (OU + baseline groups + password policy) → create → set password → add groups → (optional home-dir flag) → audit. Templates per role are a v1.x add. |
| **Offboarding workflow (disable + quarantine + strip groups + checklist)** | Highest-risk everyday task made safe and reversible | HIGH | Disable → strip non-protected groups (record them for restore) → move to quarantine OU → surface related cleanup (mailbox/home-dir/GPO) as a **checklist only** (out of scope to automate). Reversible by design. |
| **Reversible-by-design "delete"** | No accidental hard-deletes; recoverable | LOW | "Delete" verb = disable + move to quarantine OU + record original location/groups. Real deletion is an anti-feature (below). |
| **Remote ops auto-detect WinRM → CIM/WMI → skip** | Portability across hosts where WinRM isn't on; Hyena assumes more, ADManager is agent/web | MEDIUM | A dispatcher: probe WinRM (`Test-WSMan`/PSRemoting) → fall back to CIM (`Get-CimInstance`/`DCOM`) → if both fail, mark host `Skipped` and continue the fleet. Read queries first; live actions v1.x. |
| **Self-contained HTML reports** | Shareable with management; no Excel dependency | MEDIUM | Single-file HTML (embedded CSS) from the shared data layer. ADManager has it; ADUC/Hyena lean on Excel. Cheap if the data layer is shared with CSV/console. |
| **Stale/inactive account detect → gated action pipeline** | "Report then act safely" in one flow | MEDIUM | Find inactive (lastLogonTimestamp / `PasswordLastSet`) → preview → gated disable/move. ADManager does this; we do it guided+safe. |
| **Idempotent / resume-safe bulk** | Re-running a bulk job is safe; partial failures don't corrupt | MEDIUM | Skip already-in-desired-state targets; record per-item results so a re-run resumes. Robustness differentiator seniors will love. |

### Anti-Features (Commonly Requested, Deliberately NOT Built)

These look "enterprise" or convenient but violate the Core Value, explode complexity, or conflict with v1's credential/scope model. Several are already named in PROJECT.md Out of Scope; the rest are traps this space falls into.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Hard-delete of AD objects | "Clean up for real" | Irreversible; one bad filter wipes accounts. Breaks the safety property. | Disable + move to quarantine OU + record state for restore (reversible). |
| Acting on protected accounts or objects outside managed OUs | "Just this once" convenience | The exact blast-radius the tool exists to contain. | Refuse by design; audited break-glass override only. |
| Entra ID / M365 / cloud sync | ADManager-style "one console for everything" | Scope creep into a different product; environment is on-prem only. | Out of scope. If needed later, a separate module — don't let it colonize v1. |
| **Approval-workflow engine / ticketing / multi-level RBAC delegation platform** | "ADManager Professional has it" | Massive complexity for a small team; **conflicts with pass-through least-privilege** (delegation implies the tool holds/assigns rights); becomes an IGA project. | Rely on AD's own ACLs + managed-OU scoping + audit log. Revisit only if team size/regulation demands (v2+). |
| Credential vault / stored privileged creds / elevation broker (v1) | "So juniors can do admin things" | Secret-management + audit risk; undermines least-privilege and the clean audit story. | Pass-through only in v1; defer to v2 with a real secret store if ever. |
| GPO authoring / deployment | "Manage policies too" | High blast radius, different skill domain, easy to break logon. | Read/report GPO at most (Hyena-style); never author in v1. |
| Exchange / mailbox / home-directory cleanup in offboarding | "Finish the leaver cleanup" | Out of on-prem-AD scope; adds Exchange module deps and failure modes. | Surface as an actionable **checklist** in the offboarding report. |
| Compiled `.exe` / GUI / web UI | "Make it look like a product" | Packaging/AV/signing friction; **conflicts with TUI-only v1** and portability. | Ship as script/module; defer `.exe` (ps2exe) to v2. |
| Continuous monitoring / SIEM / change-alerting daemon | "Alert me on changes" | That's ADAudit/IDS territory; persistent service, different threat model. | On-demand reports only. |
| **Unpreviewed bulk from arbitrary CSV with no validation** | "Just import this file HR sent" | The classic foot-gun (`Import-Csv | Set-ADUser`). Hyena's Active Task *has* pre-execution validation — the anti-feature is the raw, unguarded version. | CSV ingestion only through the gated bulk path: schema validation → preview → max-count cap → typed confirm. |
| Schema extension / authoring custom AD attributes | "We need a custom field" | Irreversible forest-wide change; rare; out of team-tool scope. | Don't build. Point admins to official schema tooling if truly needed. |
| Cross-forest / multi-domain (v1) | "Future-proof it" | Trust/credential/discovery complexity the single-domain environment doesn't need. | Single domain only in v1. |
| **Autonomous/AI "decide which accounts to disable" remediation** | "Auto-clean stale accounts" | Removes the human from high-blast-radius decisions; **directly conflicts with the safety property.** | Tool proposes (report + preview); human disposes (typed confirm). Keep human-in-the-loop. |

---

## Safety & Guardrails as First-Class Features

Per the quality gate, these are not afterthoughts — they ARE the product for a mixed-skill team doing high-blast-radius writes. They form one shared layer that every write verb calls.

| Guardrail | What it does | Complexity | Table-stakes for a *team* tool? |
|-----------|--------------|------------|----------------------------------|
| Dry-run / `-WhatIf` | Show exactly what would change, per object | MEDIUM | Yes — non-negotiable |
| Confirmation (scaled) | y/n for single; typed token + count for bulk/destructive | LOW | Yes |
| Audit log (append-only) | who/what/when/scope/WhatIf/result; never logs secrets | MEDIUM | Yes |
| Deny-list (startup-loaded) | Hard blocklist matched before any action | LOW | Yes |
| Protected-account guard | Refuse admin-group/service/gMSA/built-ins | MEDIUM | Yes |
| Managed-OU scoping | Refuse targets outside configured roots | MEDIUM | Yes |
| Bulk max-count cap + preview | Bound mass-change; force explicit ack | MEDIUM | Yes (for any bulk) |
| Least-privilege pass-through | Use invoker's rights; no stored secrets | LOW | Yes |
| Reversible delete | Disable + quarantine, not hard delete | LOW | Yes |

**Design implication:** implement these as a single `Invoke-SafeADChange` (verb, target, scriptblock) that enforces deny-list → protected-check → OU-scope → WhatIf/confirm → execute → audit, in that order. User/computer/workflow features never touch AD write cmdlets directly; they all go through this wrapper. This is the architectural commitment that makes the safety property hold (feeds ARCHITECTURE.md).

---

## Feature Dependencies

```
Guardrail Core (Invoke-SafeADChange: deny-list → protected → OU-scope → WhatIf/confirm → execute → audit)
    └──required by──> EVERY write operation (user, computer, group, workflow, bulk)

Startup prereq check (ActiveDirectory/RSAT module present, domain reachable)
    └──required by──> all AD operations (fail fast with guidance)

Search/Query (Get-ADUser/Computer -Filter, LDAPFilter)
    └──required by──> Bulk target set
    └──required by──> Stale/inactive report
    └──enhances─────> single-object actions (pick from results)

Audit Log
    └──must precede──> first write (so the first change is recorded)

OU-scope + Deny-list + Protected guard
    └──must precede──> Bulk (bulk is N writes; guardrails must compose)

User verbs (create/disable/enable/move/reset/unlock/group)
    └──compose into──> Onboarding workflow (create + set-pw + add-groups + move)
    └──compose into──> Offboarding workflow (disable + strip-groups + move-quarantine)

Reachability dispatcher (WinRM → CIM → skip)
    └──required by──> Remote query
    └──required by──> Remote live action (v1.x)
    └──enhances─────> Inventory report (live fields)

Shared data layer (query → objects)
    └──renders to───> Console table  └── CSV  └── HTML report
        (all three renderers consume the same objects → HTML is cheap once CSV/console exist)

Onboarding/Offboarding workflows
    └──require──────> Guardrail core + Audit + (offboarding) Report-for-checklist
```

### Dependency Notes

- **Guardrail Core precedes all writes:** the safety property only holds if no write path bypasses it. Build and test it in isolation before any write verb.
- **Prereq/startup check fails fast:** detect missing `ActiveDirectory` module and unreachable domain at launch with install guidance (RSAT), not mid-action.
- **Audit before first write:** logging must be wired into the wrapper before any verb uses it, or the earliest changes are unlogged.
- **Bulk composes search + guardrail + report:** bulk is "search to build the set → report to preview → guardrail to gate → execute per item." Each piece must exist first.
- **Workflows are compositions, not new verbs:** onboarding/offboarding orchestrate existing user verbs through the same wrapper; they add ordering, templates, and the cleanup checklist — not new AD primitives.
- **HTML is "free" after CSV/console:** one data layer, three renderers. Ship console+CSV in v1; HTML is a low-cost v1 (or v1.x) add.
- **lastLogonTimestamp vs lastLogon:** stale reports must use the replicated attribute; the per-DC `lastLogon` is a correctness trap (note for PITFALLS.md).
- **Conflicts (don't combine/architect around):**
  - Pass-through least-privilege (v1) **conflicts with** RBAC-delegation/stored-cred elevation — don't leave hooks that assume a credential store.
  - TUI-only **conflicts with** web/GUI — don't pull a front-end framework into the design.
  - Human-in-the-loop confirmations **conflict with** unattended/autonomous bulk scheduling — keep bulk interactive + gated in v1; scheduling is a v2 item to flag.
  - Reversible-only "delete" **conflicts with** hard-delete requests — explicit, documented refusal.

---

## MVP Definition

### Launch With (v1)

Minimum to validate "any admin can do common AD tasks safely." Guardrails are NOT optional — they are the point.

- [ ] **Menu TUI entry** — discoverable, guided; calls parameterized functions (senior fast-path) underneath.
- [ ] **Startup prereq check** — `ActiveDirectory` module + domain reachability, with guidance.
- [ ] **Guardrail Core (`Invoke-SafeADChange`)** — deny-list → protected → OU-scope → WhatIf/confirm → execute → audit, as one wrapper all writes use.
- [ ] **User lifecycle (single + small bulk)** — create, disable, enable, move, reset password, unlock, group add/remove — all through the wrapper.
- [ ] **Computer lifecycle + inventory** — disable, enable, move, reset computer account; stale/last-logon (via `lastLogonTimestamp`) + OS report.
- [ ] **Onboarding workflow** — guided new-user from a role/OU template, audited.
- [ ] **Offboarding workflow** — disable + strip groups (recorded) + move to quarantine OU + cleanup **checklist**, reversible.
- [ ] **Reporting: console + CSV** — shared data layer; stale/inactive detection that feeds gated action.
- [ ] **Remote query with WinRM → CIM → skip fallback** — read-only fleet queries; per-host `Skipped` rather than failure.
- [ ] **Bulk gated by preview + typed confirm + max-count cap** — the only bulk path; no raw CSV-to-cmdlet.

### Add After Validation (v1.x)

- [ ] **HTML reports** — once console+CSV proven; same data layer.
- [ ] **Remote live actions** (restart service, trigger `gpupdate`, etc.) — behind the identical guardrail wrapper; query-first proven safe.
- [ ] **Saved queries / favorites** (Hyena Query Library lite) — if seniors ask for speed.
- [ ] **Idempotent/resume-safe bulk** — if real bulk jobs show partial-failure pain.
- [ ] **Multiple onboarding templates per role** — once the single-template flow is validated.
- [ ] **Read-only GPO reporting** — if audit/compliance asks.

### Future Consideration (v2+)

- [ ] **Scheduling of reports/approved workflows** — only after human-in-the-loop is proven; never unattended destructive bulk.
- [ ] **Compiled `.exe` distribution (ps2exe)** — packaging convenience, not capability.
- [ ] **HR-CSV-driven provisioning** — only with full schema validation + preview + cap (never autonomous).
- [ ] **Elevation / stored-privileged-cred model** — only if delegation becomes a real requirement; needs a proper secret store and redesign.
- [ ] **Multi-domain / cross-forest** — only if the environment grows to need it.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Guardrail Core (`Invoke-SafeADChange`) | HIGH | HIGH | P1 |
| Menu TUI + senior fast-path | HIGH | MEDIUM | P1 |
| Startup prereq check (RSAT/domain) | HIGH | LOW | P1 |
| User lifecycle verbs | HIGH | MEDIUM | P1 |
| Computer lifecycle + stale/OS report | HIGH | MEDIUM | P1 |
| Onboarding workflow | HIGH | HIGH | P1 |
| Offboarding workflow | HIGH | HIGH | P1 |
| Audit log (append-only) | HIGH | MEDIUM | P1 |
| Deny-list + protected-account guard + OU scoping | HIGH | MEDIUM | P1 |
| Bulk: preview + typed confirm + max-count cap | HIGH | HIGH | P1 |
| Console + CSV reporting | HIGH | LOW | P1 |
| Remote query (WinRM→CIM→skip) | MEDIUM | MEDIUM | P1 |
| HTML reports | MEDIUM | MEDIUM | P2 |
| Remote live actions | MEDIUM | MEDIUM | P2 |
| Saved queries/favorites | MEDIUM | LOW | P2 |
| Idempotent/resume-safe bulk | MEDIUM | MEDIUM | P2 |
| Multi-role onboarding templates | MEDIUM | LOW | P2 |
| Read-only GPO reporting | LOW | MEDIUM | P2 |
| Scheduling | LOW | HIGH | P3 |
| Compiled `.exe` | LOW | MEDIUM | P3 |
| HR-CSV-driven provisioning | MEDIUM | HIGH | P3 |
| Elevation / stored creds | LOW | HIGH | P3 (defer) |

**Priority key:** P1 must-have for launch; P2 should-have; P3 future/defer.

---

## Competitor Feature Analysis

| Capability | ADUC (native baseline) | ManageEngine ADManager Plus | SystemTools Hyena | Our Approach |
|------------|------------------------|------------------------------|-------------------|--------------|
| Interface | MMC GUI, single-object focus | Web console (IGA) | Windows GUI, manage by OU or class | **Guided TUI menu** (juniors) over parameterized functions (seniors) |
| Single-object user/computer CRUD | Yes (the baseline) | Yes, cross-platform (AD+M365+GWS) | Yes, rich attribute editor | Yes, via guardrail wrapper |
| Bulk operations | Minimal/poor | CSV bulk create/modify/delete + HRMS integration | **Active Editor** (table) + **Active Task** (CSV, validated, schedulable) | Gated bulk only: search → preview → max-count cap → typed confirm |
| Dry-run / `-WhatIf` | No real dry-run | Partial (simulation in some flows) | Pre-execution validation in Active Task | **`-WhatIf` everywhere** via shared wrapper, incl. emulated for workflows |
| Confirmation | Minimal | Workflow approvals (Pro) | Change indicators / uncommitted counts | **Scaled** y/n (single) + typed token+count (bulk) |
| Audit trail (who/what/when) | None built-in (needs ADAudit/separate) | Built-in, tied to platform | Logging in tasks | **Append-only JSONL/CSV** from the wrapper; no secrets logged |
| Protected-account / deny-list guard | No | Role rules (complex) | No first-class | **First-class**: deny-list + AdminCount/protected-group/gMSA detection |
| OU scoping / delegation | Relies on AD ACLs only | RBAC delegation (Pro) | Relies on AD ACLs | **Managed-OU roots**; refuse outside; uses invoker's ACLs |
| Offboarding workflow | Manual, many steps | Automation rules (Pro) | Manual + tasks | **Guided**: disable + strip (recorded) + quarantine OU + cleanup checklist; reversible |
| Onboarding/templates | Manual | Prefilled templates, CSV | CSV import via Active Task | **Guided role template** (name format + OU + groups + password policy) |
| Reporting/export | Weak (saved queries, no real export) | 200+ reports (CSV/PDF/XLSX/HTML) + scheduler | Export to text/Excel/Access; GPO report | Console + **CSV** + self-contained **HTML** from one data layer |
| Remote computer ops | Limited | Limited (directory-centric) | WMI/inventory, service/event/printer/disk | **WinRM → CIM/WMI → skip** auto-detect; query first, live actions v1.x |
| Cloud/M365 | No | **Yes (creep)** | No (on-prem/Exchange) | **No — on-prem only** (anti-feature) |
| Credential model | Invoker's creds | Service account + delegation | Invoker's creds | **Pass-through only** (least privilege); no stored secrets v1 |
| Pricing/footprint | Free (RSAT) | Paid (Standard/Pro), web app | Paid per-admin (~$115–$329), GUI | Internal module/script; zero license cost |
| Learning curve | Low (familiar) | **Noted as steep/complex** | Moderate | **Low** (menu) + fast (functions) — designed for mixed skill |

**Net positioning:** ADUC is the familiar-but-unsafe baseline; ADManager/Hyena are powerful but paid, GUI/web-bound, and (ADManager) prone to cloud/IGA sprawl and complexity. This tool's wedge is **safety-by-construction + discoverability + zero license cost** for a small on-prem team that currently uses "ADUC + risky personal scripts."

---

## Sources

- ManageEngine ADManager Plus — Active Directory User Management: https://www.manageengine.com/products/ad-manager/active-directory-user-management.html (HIGH — vendor)
- ManageEngine ADManager Plus — AD Automation: https://www.manageengine.com/products/ad-manager/active-directory-management-automation/active-directory-automation.html (HIGH — vendor)
- ManageEngine ADManager Plus — Account Status Reports: https://www.manageengine.com/products/ad-manager/ad-user-account-status-reports.html (HIGH — vendor)
- 4sysops — Automation for AD, M365, Google Workspace with ADManager Plus: https://4sysops.com/archives/automation-for-active-directory-microsoft-365-and-google-workspace-with-manageengine-admanager-plus/ (MEDIUM — third-party review)
- SystemTools Hyena — Active Directory Tools: https://www.systemtools.com/hyena/ad_main.htm (HIGH — vendor)
- SystemTools Hyena — Active Task (CSV import/update): https://www.systemtools.com/hyena/active_task.htm (HIGH — vendor)
- SystemTools Hyena — Reporting: https://systemtools.com/HyenaHelp/adreporting.htm (HIGH — vendor)
- 4sysops — SystemTools Hyena review: https://4sysops.com/archives/systemtools-hyena-simplify-active-directory-management/ (MEDIUM — third-party review)
- Microsoft — ActiveDirectory PowerShell module / RSAT cmdlets (Get-/Set-/New-/Move-/Disable-/Enable-ADObject, Reset-ComputerMachinePassword, Test-ComputerSecureChannel): learn.microsoft.com/powershell/module/activedirectory (HIGH — vendor; prior knowledge, stable API)
- Microsoft — `lastLogonTimestamp` vs `lastLogon` replication behavior (HIGH — documented AD behavior; flagged for PITFALLS)
- Microsoft — `AdminCount` / `adminSDHolder` / protected groups and `msDS-GroupManagedServiceAccount` (HIGH — documented AD security behavior; flagged for PITFALLS)

**Gaps / confirm at requirements:** exact protected-group set and break-glass override policy; whether built-ins (`krbtgt`, `Guest`, default `Administrator`) are baseline-deny-listed (PROJECT.md flags ⚠️); managed-OU roots; max-count cap default; audit-log location/retention; PowerShell 7.x parity target. These are configuration decisions, not feature unknowns.

---
*Feature research for: on-prem AD user/computer administration toolkit (adman)*
*Researched: 2026-07-10*
