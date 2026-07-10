# Project Research Summary

**Project:** adman (working name — confirm/rename at requirements)
**Domain:** Menu-driven (interactive TUI) PowerShell toolkit for on-prem Active Directory user/computer + local (per-machine) user administration, for a small mixed-skill IT team, with strong safety guardrails
**Researched:** 2026-07-10
**Confidence:** HIGH

## Executive Summary

adman consolidates four everyday jobs — AD object lifecycle, reporting/inventory, remote computer operations, and provisioning/offboarding — behind one guided TUI so that **any admin on a mixed-skill team can do common AD/local-user tasks correctly and safely**. The research is unusually convergent: all four threads (stack, features, architecture, pitfalls) independently arrive at the same load-bearing conclusion — **safety is the product, and it is only real if there is exactly one, non-bypassable code path that performs every mutation.** Every write (disable, move, reset, unlock, group change, quarantine, local-user change) must funnel through a single internal gate (`Invoke-AdmanMutation`) that resolves targets, enforces managed-OU scope + deny-list + protected-object detection, applies bulk policy, runs `ShouldProcess` (`-WhatIf`/`-Confirm`), executes the one real write, and appends an audit record — in that fixed order, with preview and execute sharing the same target set so the preview can never lie.

The recommended approach is a **Windows PowerShell 5.1 / PowerShell 7.6 LTS dual-target script module** (manifest + Public/Private, dot-sourced, no build step in v1), **RSAT/ActiveDirectory as a documented prerequisite (never bundled)**, **CIM over WSMAN with a DCOM fallback instead of `Get-WmiObject`**, a **hand-rolled `Read-Host` menu** (ConsoleGuiTools/Terminal.Gui is Core-only and was archived 2026-06-24 — out), and a **transport ladder of WinRM → CIM/WSMan → CIM/DCOM → skip** isolated behind one connector. **PSFramework 1.14.457 is adopted as the cross-cutting config + logging backbone** (verified PS 3.0+, no dependencies, both editions) — this is the one place the synthesis overrides the stack researcher's "hand-roll JSONL, defer PSFramework" leaning, because the architecture researcher verified it is 5.1-safe and dependency-free, and a hand-rolled logger would re-implement what PSFramework already gives (fail-closed audit, runspace-safe messaging) for no benefit.

The dominant risks are all high-blast-radius and all mitigated by building the safety spine **before any write lands**: (1) the unfiltered `Get-AD* -Filter * | Disable-ADAccount` mass-change accident — killed by the gate's count cap + typed confirmation + mandatory `-SearchBase`; (2) touching protected objects (`krbtgt`, RID-500 Administrator, Domain/Enterprise/Schema Admins via *nested* membership, DCs, gMSA) and AdminSDHolder/SDProp reversion — killed by runtime well-known-SID resolution (never `adminCount` alone); (3) stale-object misidentification from `lastLogon` (per-DC) vs `lastLogonTimestamp` (replicated, ~9–14 day lag) and the four conflated states (disabled/expired/locked/password-expired) — killed by read-only reporting proving the semantics before any action uses them; (4) remoting traps (CIM-defaults-to-WSMan, double-hop, DCOM firewall) — isolated behind the connector; and (5) PowerShell's foot-guns (`$ErrorActionPreference='Continue'`, `try/catch` not catching non-terminating errors, `-WhatIf` theater) — killed by a Phase-0 convention enforced by lint + Pester. **One contradiction in the brief must be resolved at requirements (see "Decision required" below): DPAPI encryption is machine+user-bound, so a fully-encrypted single config file is not portable — the recommended split is portable plain-JSON non-secret config + a separate opt-in DPAPI credential file, both in the gitignored `.store/` folder.**

## Key Findings

### Recommended Stack

Write to the **PowerShell 5.1 language subset** so the same module loads on 5.1 (guaranteed on-box) and 7.6.3 LTS (support to 2028-11-14); do not target 7.4/7.5 (EOL 2026-11-10). Declare `PowerShellVersion='5.1'` and `CompatiblePSEditions=@('Desktop','Core')` **only after the CI matrix passes on both** — until then claim `Desktop` only and be honest. No 7-only syntax (ternary, `??`, `&&`/`||`, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`) unless guarded by `$PSEdition`. Details in `STACK.md`.

**Core technologies:**
- **Windows PowerShell 5.1**: primary runtime — guaranteed present; the AD module, `LocalAccounts`, and `CimCmdlets` are all in-box.
- **PowerShell 7.6.3 LTS**: supported modern runtime — current LTS; `ActiveDirectory` is natively compatible on Win10 1809+/Server 1809+.
- **ActiveDirectory module (RSAT)**: AD user/computer/group/OU lifecycle — prerequisite, never bundled; document install, probe at startup.
- **CimCmdlets** (`Get-CimInstance`/`New-CimSession`): inventory + no-WinRM fallback — built into both editions; replaces removed `Get-WmiObject` and retiring `wmic.exe`.
- **PSRemoting/WinRM** (`Invoke-Command`/`New-PSSession`): live remote actions — first hop of the ladder.
- **Microsoft.PowerShell.LocalAccounts**: local (per-machine) user lifecycle — natively PS7-compatible.
- **Microsoft.PowerShell.PSResourceGet 1.2.0**: package/publish to an internal repo — replaces unsupported in-box PowerShellGet 1.0.0.1.
- **Pester 6.0.0 / PSScriptAnalyzer 1.25.0 / PlatyPS 1.0.2**: test / lint / external help — all 5.1+Core; lint rule `PSUseShouldProcessForStateChangingFunctions` directly enforces the dry-run guardrail; do not mix PlatyPS 1.0.x with legacy 0.14.2 (different cmdlet surface).
- **PSFramework 1.14.457** (reconciled — see Exec Summary): configuration + logging/audit + messaging backbone; PS 3.0+, no deps, both editions. Supersedes the stack researcher's hand-rolled JSONL scaffolding.
- **Authenticode signing** (`Set-AuthenticodeSignature`): sign `.psd1/.psm1/.ps1` so the tool runs under `AllSigned`/`RemoteSigned` without prompts — appropriate for a security-sensitive admin tool.
- **No `ps2exe`/`.exe` in v1**: it wraps (does not compile), still needs PowerShell on target, and the script is extractable — not a security boundary; defer to v2.

### Expected Features

The space is mature (ADUC baseline; ManageEngine ADManager Plus, SystemTools Hyena as the long-standing commercial consoles). adman's wedge is **safety-by-construction + discoverability + zero license cost**. Details in `FEATURES.md`.

**Must have (table stakes):**
- Search/view users & computers; single create/disable/enable/move/reset-password/unlock; group add/remove; computer disable/enable/move + reset-computer-account — admins give no credit for these but leave if absent.
- Read-mostly inventory: stale/last-logon (via `lastLogonTimestamp`, **never `lastLogon`**), OS version, reachability detection; console table + CSV export.
- Pass-through of the logged-in admin's credentials (least-privilege baseline); clear actionable errors (RSAT missing, host unreachable, access denied).

**Should have (differentiators — the reason to standardize on this):**
- Unified guided TUI over the same parameterized functions seniors call directly (one code path, two speeds).
- The safety system as one shared layer every write calls (dry-run, scaled confirmation, append-only audit, startup deny-list, protected-account guard, managed-OU scoping).
- Gated bulk: search → preview → max-count cap → typed confirm → per-item continue-on-failure.
- Onboarding (role/OU template) and offboarding (disable + strip-recorded-groups + quarantine OU + cleanup **checklist**) workflows — reversible "delete" by design.
- Remote ops with the WinRM → CIM/DCOM → skip ladder; self-contained HTML reports; idempotent/resume-safe bulk.

**Defer (v1.x / v2+):**
- v1.x: HTML reports (cheap once console+CSV share the data layer), remote live actions, saved queries/favorites, multi-role templates, read-only GPO reporting.
- v2+: scheduling of approved workflows (never unattended destructive bulk), compiled `.exe`, HR-CSV-driven provisioning (only with full validation + preview + cap), stored-privileged-cred/elevation model (needs a real secret store + redesign), multi-domain/cross-forest.

**Anti-features (deliberately refused):** hard-delete; acting on protected/out-of-scope objects; Entra/M365/cloud; RBAC-delegation/approval-workflow engine (conflicts with pass-through least-privilege); credential vault in v1; GPO authoring; Exchange/mailbox/home-dir cleanup automation; raw `Import-Csv | Set-ADUser` with no validation; schema extension; autonomous "decide which accounts to disable" remediation (removes human-in-the-loop — directly conflicts with the safety property).

### Architecture Approach

A layered module with one hard rule: **the Single Mutation Gate.** Public verbs are thin (validate input → build a request → call the gate); the gate is the only function allowed to call AD write cmdlets, and it is *not exported*, with explicit `FunctionsToExport` (never `'*'`) so no future helper can accidentally become a writer. Reads may bypass the gate (but still read through the managed-OU-scoped read layer); writes never do. Details in `ARCHITECTURE.md`.

**Major components:**
1. **Presentation / Menu** — `Start-Adman`, numbered `Read-Host` menu, prompts, `Out-GridView` (5.1) with numbered fallback; routes to verbs, never touches AD.
2. **Public verbs** — `Disable-/Enable-/Move-/New-/Reset-/Unlock-AdmanUser`, computer + reporting + remote + workflow verbs; thin orchestration that builds requests.
3. **Safety Core** — `Invoke-AdmanMutation` (THE GATE), `Test-AdmanTargetAllowed` (scope + deny-list + runtime-SID protection), `Confirm-AdmanAction` (ShouldProcess + typed bulk confirm), `Assert-AdmanBulkPolicy`, `Write-AdmanAudit` (append-only, fail-closed).
4. **AD Access layer** — thin wrappers over RSAT `*-AD*`; centralizes `-Server` pinning, error handling, the live credential; read wrappers for public reads, write wrappers used *only* by the gate.
5. **Remoting connector** — `Connect-AdmanTarget` probe+cache ladder (WinRM → CIM/WSMan → CIM/DCOM → skip); verbs never branch on transport.
6. **Output layer** — canonical result object → console/CSV/self-contained HTML at the boundary (no `Format-*` inside functions).
7. **Foundation** (loaded once) — PSFramework config + logging/audit, credential decision (pass-through vs prompt), capability probe (RSAT? domain? rights? transports?) setting session flags the menu reads.

### Critical Pitfalls

Top of the 12 in `PITFALLS.md` — each owned by a specific phase:

1. **Unfiltered mass-change pipeline** (`Get-ADUser -Filter * | Disable-ADAccount`) — materialize the target set, scope to managed OU, deny-list/protected filter, preview, count cap, typed confirm; the gate enforces this for *every* verb. (Phase 0 + re-enforced Phase 4)
2. **Touching protected objects / AdminSDHolder-SDProp** — refuse built-in RIDs (500/501/502), recursive members of Domain/Enterprise/Schema Admins + local Administrators, DCs, gMSA; resolve via well-known SIDs at check time; treat `adminCount=1` as a hint, never proof (it goes stale when an admin is removed). (Phase 0; surfaced Phase 1)
3. **`lastLogon` vs `lastLogonTimestamp`; disabled/expired/locked/password-expired conflation** — use replicated `lastLogonTimestamp` with a ≥14-day grace buffer, bucket never-logged-on (`0`/1601) separately, aggregate `lastLogon` from all DCs only for borderline pre-action checks; render the four account states as distinct columns via `Search-ADAccount`, never raw `userAccountControl` bit math. (Phase 1 logic; consumed Phase 2/4)
4. **`-WhatIf` theater + PowerShell error handling** — one path for preview and execute, `ConfirmImpact='High'` on every destructive function, guardrails run in both modes, dry-runs are audit-logged; set `$ErrorActionPreference='Stop'` + per-call `-ErrorAction Stop`, `try/catch/finally` per target with `continue` so a failure never falls through to later steps. (Phase 0; enforced by lint+Pester every write phase)
5. **Tamper-resistant, fail-closed audit** — structured append-only JSONL written *only* by the gate (who/what/when/dry-run/target/count/result; never passwords); if the audit can't be written, refuse the destructive action rather than run unaudited. (Phase 0; tamper-evidence/forwarding Phase 5)

Also load-bearing: **replication/read-after-write** (pin `-Server` to one DC — PDCe for password/lockout — across a whole sequence), **Recycle Bin is a prerequisite not a recovery step** (enabling it wipes existing tombstones; preflight reports posture), **double-hop** (eliminate the second hop where possible; RBCD/JEA over CredSSP; never for "sensitive, cannot be delegated" accounts), and the **CIM-is-WSMan trap** (default CIM uses WinRM — the real fallback is `-Protocol Dcom`, a different firewall profile: 135 + RPC dynamic vs 5985/5986).

## Implications for Roadmap

The three research files propose build orders that collapse cleanly into one blast-radius-ordered skeleton. Adopt the **6-phase skeleton below** (it mirrors PITFALLS.md's Phase 0–5 and nests ARCHITECTURE.md's finer 10-step build inside it). The governing principle: **the safety spine must exist and be proven before any real write can be merged** — no phase may ship a mutation that bypasses the gate, and read-only work comes before writes, single-object before bulk, remoting isolated, workflows last.

### Phase 0 — Foundation & Safety Harness
**Rationale:** Must exist before *any* AD write; everything composes on it. This is where the safety property is made structurally true rather than aspirational.
**Delivers:** Module scaffold (`adman.psd1/.psm1`, Public/Private loader, explicit `FunctionsToExport`); `Initialize-Adman` (PSFramework config+logging → credential decision → `Test-AdmanCapability` probe); config defaults + schema + load/validate (fail closed on empty managed-OU / failed deny-list); the DPAPI credential-file decision; `Invoke-AdmanMutation` + `Test-AdmanTargetAllowed` + `Confirm-AdmanAction` + `Assert-AdmanBulkPolicy` + `Write-AdmanAudit`; `$ErrorActionPreference='Stop'` + `-Server`-pinning helper; Recycle-Bin/recovery-posture preflight.
**Addresses:** Safety guardrails (full set), portability scaffold, save/load config, documentation foundation.
**Avoids:** Pitfalls 1, 2, 6, 7, 10, 11, 12 (the whole harness), and sets the conventions that make later phases safe by construction.
**Exit gate:** tool starts, loads+validates config, reports capabilities, logs; the gate denies/logs correctly against fixtures; `-WhatIf` works end-to-end against a test OU; **a Pester test proves no exported function calls AD write cmdlets directly.**

### Phase 1 — AD Query & Reporting (read-only)
**Rationale:** Lowest blast radius; proves the team reads AD semantics (timestamps, replication, expired-vs-disabled, lockout counters) correctly *before* acting on them. Shared read layer + data layer render to console/CSV here so HTML is cheap later.
**Delivers:** Scoped read wrappers (`-SearchBase` always set, exact `-Properties`, `-ResultPageSize`); search/view users & computers; stale/inactive detection (`lastLogonTimestamp` + grace buffer + never-logged-on bucket; all-DC `lastLogon` aggregation helper built once); lockout-source (per-DC counters + PDCe 4740 path); OS/inventory; protected-object + stale-`adminCount` inventory; console + CSV from the canonical result object.
**Addresses:** Reporting & inventory, read-side of lifecycle, protected-object visibility.
**Avoids:** Pitfalls 3 (timestamps), 4 (four states), 5 (lockout wrong-DC), 7 (recovery posture reported) — by surfacing the correct semantics before any verb consumes them.
**Exit gate:** reports render Disabled/Expired/Locked/Password-Expired distinctly; never-logged-on bucketed; ≥14-day buffer present; recovery posture shown at startup.

### Phase 2 — Single-Object Lifecycle (writes begin, bounded to one)
**Rationale:** First mutations, but bounded to one object so the gate is exercised on real writes with minimal blast radius; unlock/enable/disable/reset each target exactly one state.
**Delivers:** User create/disable/enable/move/reset-password/unlock + group add/remove; computer disable/enable/move + reset-computer-account; local (per-machine) user lifecycle via `LocalAccounts` — **all routed through `Invoke-AdmanMutation`**, preview+confirm+audit, unlock pinned to PDCe, `-Server` pinned per sequence.
**Addresses:** AD/local user lifecycle, AD computer lifecycle, single-object operations.
**Avoids:** Pitfalls 1 (no unfiltered pipe), 2 (protected refusal incl. nesting), 4 (one verb per state), 5 (PDCe-pinned unlock), 6 (read-your-writes on same DC), 10/11 (error handling + ShouldProcess), 12 (audit).
**Exit gate:** lifecycle verbs work with preview ≡ execute + confirm + audit; protected/out-of-scope targets refused and logged; no verb bypasses the gate (lint + Pester).

### Phase 3 — Remote Computer Operations (isolated)
**Rationale:** Remoting complexity (WinRM/DCOM/firewall/double-hop) is quarantined behind one connector so it cannot destabilize the AD core; read queries first, live actions only after query path is proven.
**Delivers:** `Connect-AdmanTarget` ladder (WinRM → CIM/WSMan → CIM/DCOM → skip) with per-host session cache + short timeouts + `Skipped` as a first-class non-error outcome; remote query (online/OS/uptime/logged-on user) enriching inventory; documented double-hop strategy (no-second-hop preferred; RBCD/JEA; CredSSP last resort); local-on-target action design.
**Addresses:** Remote computer operations, inventory enrichment, local-account operations on member machines.
**Avoids:** Pitfalls 8 (double-hop), 9 (CIM-is-WSMan/DCOM firewall/timeouts/cache).
**Exit gate:** probe distinguishes WSMAN vs DCOM; offline hosts = `Skipped` (not error); menu never hangs on dead hosts; double-hop works by design or is eliminated.

### Phase 4 — Bulk & Workflows (highest blast radius, last)
**Rationale:** Only safe once single-object writes and the gate are proven; bulk is "search → preview → cap → typed confirm → per-item continue-on-failure"; workflows compose existing verbs (no new AD primitives) under one preview+confirm.
**Delivers:** Gated bulk (max-count cap + typed count confirmation + per-item error capture + idempotent/resume-safe where cheap); onboarding workflow (name-format → role/OU template → create → password → groups → audit); offboarding workflow (disable → strip non-protected groups **recorded for restore** → move to quarantine OU → cleanup **checklist only**; reversible, with a restore-from-quarantine path); stale-detect → gated-action pipeline.
**Addresses:** Bulk operations, provisioning/onboarding, offboarding, reversible delete.
**Avoids:** Pitfalls 1 (cap + typed confirm re-enforced), 6 (no flapping), 7 (never hard-delete; quarantine restore works), 10 (a mid-workflow failure stops later steps for that target + logs FAIL), 12 (per-item audit + summary).
**Exit gate:** bulk `-WhatIf` shows truthful count; count cap trips; offboarding is reversible with prior groups/expiry recorded; no `Remove-ADObject` anywhere.

### Phase 5 — Hardening & Portability
**Rationale:** Cross-cutting operational readiness after the functional spine is correct; gates the dual-edition claim on a real matrix.
**Delivers:** RSAT prerequisite guidance + startup fail-fast; PS 5.1/7.6 CI matrix (only then claim `CompatiblePSEditions=@('Desktop','Core')`); workstation-vs-jump-host portability; encrypted credential-file backup/restore (re-prompt on DPAPI restore failure); audit tamper-evidence/forwarding + rotation; HTML reports (v1.x candidate pulled forward if cheap); Authenticode signing; README/usage-guide/inline-help polish; out-of-tool Recycle-Bin recovery runbook.
**Addresses:** Portability, documentation, dual-edition support, audit hardening.
**Avoids:** Pitfall 12 hardening (tamper-evidence), signing/trust, PS7-only-syntax regressions.
**Exit gate:** runs under `AllSigned`; passes on both 5.1 and 7.6; `.store/` never committed; restore to a new machine re-prompts for the credential and keeps the non-secret config.

### Phase Ordering Rationale

- **Safety spine first (Phase 0):** the safety property only holds if no write path can bypass the gate — so the gate is built and tested in isolation before any verb exists. This is the single most important sequencing decision in the project.
- **Reads before writes (Phase 1 before 2):** reporting is read-only (low blast radius) and forces correct handling of the AD semantics (timestamps, four states, replication, lockout counters) that the writes will later depend on; building the all-DC aggregation and `-Server`-pinning helpers once here prevents reimplementation bugs later.
- **Single-object before bulk (Phase 2 before 4):** exercise the gate on the smallest real mutations; bulk and workflows are compositions of proven single verbs, not new primitives.
- **Remoting isolated (Phase 3):** transport/firewall/double-hop risk is quarantined so it cannot destabilize the AD core; local-user lifecycle spans Phase 2 (local cmdlet surface) and Phase 3 (on remote member machines).
- **Workflows last (Phase 4):** onboarding/offboarding orchestrate existing verbs through the same gate; they add ordering, templates, and the cleanup checklist — highest blast radius, safest when everything underneath is correct.
- **Hardening closes the loop (Phase 5):** the dual-edition and signing claims are only honest after a real matrix and real-host delegation tests.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase <N>`):
- **Phase 0 (Safety Harness):** HIGH — exact PSFramework 1.14.457 config/logging cmdlet signatures; DPAPI/`Export-Clixml` behavior across 5.1 vs 7.6; the precise well-known-SID set for this environment's protected groups (RID 500/501/502, domain-512, forest-518/519, `S-1-5-32-544`); RSAT server feature name (`RSAT-AD-PowerShell`) vs target SKUs.
- **Phase 3 (Remoting):** MEDIUM — the environment's firewall reality for DCOM (135 + RPC dynamic range) vs WinRM 5985/5986 determines the *usable* ladder order; the ladder itself is correct, but confirm what's actually open before defaulting.
- **Phase 4 (Workflows):** MEDIUM — confirm exact protected-group set, break-glass override policy, managed-OU roots, default max-count cap, and which offboarding cleanup items are checklist-only vs automated.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Reporting):** well-documented AD query patterns; the semantics are settled in PITFALLS.md.
- **Phase 2 (Single-object lifecycle):** thin wrappers over stable RSAT cmdlets through the proven gate.
- **Phase 5 (Hardening):** signing/packaging/docs are conventional; the only novel piece (audit tamper-evidence) is small.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against Microsoft Learn lifecycle (ms.date 2026-06-13), module-compatibility list, RSAT page, and PowerShell Gallery (PSResourceGet 1.2.0, Pester 6.0.0, PSScriptAnalyzer 1.25.0, PlatyPS 1.0.2, ConsoleGuiTools 0.7.7/archived, PSFramework 1.14.457). |
| Features | HIGH | Mature, slow domain; competitor sets (ADUC, ADManager Plus, Hyena) verified against vendor/4sysops pages. Scope opinions (what fits a small team) are labeled as such. |
| Architecture | HIGH overall | Single-gate pattern, module layout, remoting ladder verified against Microsoft docs / PSFramework Gallery / official GraphicalTools repo (archived 2026-06-24). MEDIUM only for exact PSFramework cmdlet signatures and community scaffolding conventions (verify at build). |
| Pitfalls | HIGH | Core AD/PowerShell semantics verified against Microsoft Docs / TechNet Wiki / AskDS / TechCommunity; default values and attribute names cross-checked. |

**Overall confidence:** HIGH

### Gaps to Address

- **Decision required at requirements (the credential/config contradiction):** PROJECT.md simultaneously requires "configuration MUST BE encrypted," "single config file for easy backup/restore," and "no credential storage in v1" — but DPAPI is **machine+user-bound**, so a fully-encrypted config does not survive backup/restore to another machine/user. **Recommended decision (confirm with user):** split into (a) a **portable plain-JSON NON-SECRET config** (`adman.config.json`: managed OU, deny-list, caps, paths, transport order — backup/restore/diff friendly) and (b) a **separate, opt-in, DPAPI-encrypted credential file** (`adman.credential.xml`, written only on explicit "remember me," re-prompts on restore failure). **Both live in the gitignored `.store/` folder** (PROJECT.md mandate: never commit `.store/`). **Pass-through by default; saving a credential is opt-in and labeled machine-bound.** This relaxes the literal "configuration MUST BE encrypted" to "secrets MUST BE encrypted; non-secret config is portable" — needs explicit user sign-off because it changes a written requirement. Fail closed if managed-OU is empty or deny-list fails to load.
- **Built-in critical-account baseline protection:** PROJECT.md flags `krbtgt`/`Guest`/built-in `Administrator` as "⚠️ confirm at requirements." Research recommends **on by default via well-known SIDs** (RID 500/501/502), configurable but enabled out of the box — confirm at requirements.
- **Protected-group set + break-glass policy:** exact group list (Domain/Enterprise/Schema Admins + Account/Backup/Server Operators + local Administrators) and whether an audited break-glass override is permitted — confirm at requirements.
- **Configuration values to set at requirements:** managed-OU roots, default max-count cap, deny-list seed, audit-log path/retention, report path, transport order/timeouts.
- **Code-signing cert source:** enterprise PKI vs self-signed for the internal repo — confirm in the packaging/hardening phase.
- **Research seam note:** the PITFALLS researcher reported the `gsd-tools` research-plan/store seam was not installed and used the built-in web-search fallback; confidence tiers were classified directly per the source hierarchy. No cached digests were written to the seam — does not affect conclusions (all HIGH claims rest on Microsoft/GitHub/Gallery sources corroborated across ≥2 of them).

## Sources

### Primary (HIGH confidence)
- Microsoft Learn — PowerShell Support Lifecycle (7.6.3 LTS to 2028-11-14; 7.4/7.5 EOL 2026-11-10; 5.1 via Windows lifecycle)
- Microsoft Learn — PowerShell 7 module compatibility in Windows Server 2025 (`ActiveDirectory`, `CimCmdlets`, `LocalAccounts` "Natively Compatible"; `ADDSDeployment` compat layer; `GroupPolicy` untested)
- Microsoft Learn — Remote Server Administration Tools (Pro/Ent/Edu only; 1809+ install)
- Microsoft Learn — Package management for PowerShell (PSResourceGet replaces PowerShellGet/PackageManagement; in-box 1.0.0.1 unsupported)
- Microsoft Learn — `New-CimSessionOption` (`-Protocol Dcom|Wsman`; DCOM integrity/privacy defaults; Windows-only)
- Microsoft Learn — `about_Functions_CmdletBindingAttribute` / `SupportsShouldProcess`; `about_Error_Handling`; `about_Preference_Variables`
- TechNet Wiki — LastLogon / LastLogonTimeStamp / LastLogonDate (per-DC vs replicated; sync interval)
- AskDS / TechCommunity — AD Recycle Bin (FFL 2008 R2; irreversible enable wipes tombstones; lifetimes); AdminSdHolder/SDProp (PDCe re-stamp; `adminCount` insufficient alone)
- PowerShell Gallery — PSResourceGet 1.2.0, Pester 6.0.0, PSScriptAnalyzer 1.25.0, Microsoft.PowerShell.PlatyPS 1.0.2, ConsoleGuiTools 0.7.7 (Core-only), PSFramework 1.14.457 (PS 3.0+, no deps)
- GitHub PowerShell/GraphicalTools — archived read-only 2026-06-24 (feature-complete; successor PSTui)
- Vendor docs — ManageEngine ADManager Plus; SystemTools Hyena (Active Editor/Task, reporting)

### Secondary (MEDIUM confidence)
- 4sysops — ADManager Plus review; SystemTools Hyena review; CredSSP second-hop
- Adam the Automator / TechTarget — PowerShell double-hop (RBCD/JEA/`$using:cred`; sensitive-and-cannot-be-delegated)
- Petri — AD Recycle Bin setup/restore (`IsDisableable: False`; lifetime attributes; `Restore-ADObject`)
- windows-active-directory.com — Disabled vs Expired vs Locked; ServerFault/WOSHub — non-replicated counters, PDCe authoritative, Event 4740
- Progress / SS64 — `Get-CimInstance` vs `Get-WmiObject`; CIM defaults to WSMAN; DCOM RPC/135 + dynamic range (`0x800706BA`)
- Community conventions (K. Marquette; Rambling Cookie Monster; PoshCode/ModuleBuilder; gaelcolas/Sampler) — module layout; verify at build

### Tertiary (LOW confidence)
- PS2EXE status (~1.0.17; wraps-not-compiles, extractable) — secondary blogs; architectural facts well established, version approximate
- Built-in web-search/fetch findings not cross-checked against official sources — rated LOW by the confidence seam unless corroborated

---
*Research completed: 2026-07-10*
*Ready for roadmap: yes — pending one explicit user decision at requirements (credential/config split; built-in account baseline protection).*
