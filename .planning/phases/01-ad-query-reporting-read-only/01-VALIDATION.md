---
phase: 01
slug: ad-query-reporting-read-only
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-14
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 (project target; dev host currently has 3.4.0 installed) |
| **Config file** | `tests/PesterConfiguration.psd1` if present; otherwise none — Wave 0 installs/configures if missing |
| **Quick run command** | `Invoke-Pester -Path tests/Unit -Output Detailed` |
| **Full suite command** | `Invoke-Pester -Path tests -Output Detailed -ExcludeTag Integration` |
| **Estimated runtime** | ~15 seconds unit-only; ~60 seconds with integration tag against lab OU |

---

## Sampling Rate

- **After every task commit:** Run `Invoke-Pester -Path tests/Unit -Output Detailed`
- **After every plan wave:** Run `Invoke-Pester -Path tests -Output Detailed -ExcludeTag Integration`
- **Before `/gsd-verify-work`:** Full unit suite must be green; integration tests run only in the lab environment
- **Max feedback latency:** 30 seconds for unit-only

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | MENU-01 | T-01-01 | Menu renders with numbered items | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01-01 | 1 | MENU-02 | T-01-02 | Numeric input validated; prompts supply required params | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01-01 | 1 | MENU-03 | T-01-03 | `B` returns to menu; `Q` exits from any prompt | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01-01 | 1 | MENU-04 | T-01-04 | Menu dispatches same verb as senior direct call | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-02-01 | 01-02 | 1 | USER-01 | T-02-01 | `Find-AdmanUser` loops ManagedOUs, exact Properties, page size 1000 | unit | `Invoke-Pester -Path tests/Find.User.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-02-02 | 01-02 | 1 | COMP-01 | T-02-02 | `Find-AdmanComputer` loops ManagedOUs, exact Properties, page size 1000 | unit | `Invoke-Pester -Path tests/Find.Computer.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-02-03 | 01-02 | 1 | D-03 schema | T-02-03 | `ConvertTo-AdmanResult` emits fixed property set per type | unit | `Invoke-Pester -Path tests/Result.Schema.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-03-01 | 01-03 | 2 | RPT-04 | T-03-01 | Stale report buckets Stale vs NeverLoggedOn; never per-DC lastLogon | unit | `Invoke-Pester -Path tests/Report.Stale.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-03-02 | 01-03 | 2 | RPT-05 | T-03-02 | Account-state report uses Search-ADAccount four switches; never UAC bit math | unit | `Invoke-Pester -Path tests/Report.AccountState.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-03-03 | 01-03 | 2 | RPT-07 | T-03-03 | Recovery posture preflight caches interval + posture | unit | `Invoke-Pester -Path tests/Report.Recovery.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-04-01 | 01-04 | 2 | RPT-01 | T-04-01 | Console table + Out-GridView/ConsoleGridView fallback | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-04-02 | 01-04 | 2 | RPT-02 | T-04-02 | CSV export `-NoTypeInformation` UTF8 | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-04-03 | 01-04 | 2 | RPT-03 | T-04-03 | HTML self-contained single file; no `-CssUri`/`-Charset`/`-Meta`/`-Transitional` | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ W0 | ⬜ pending |
| 01-04-04 | 01-04 | 2 | RPT-06 | T-04-04 | Inventory report includes OS version + computer attributes | unit | `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/Mocks/ActiveDirectory.psm1` — extend `Search-ADAccount` mock with state switches and scoping parameters
- [ ] `tests/Find.User.Tests.ps1` — USER-01 contract + scope
- [ ] `tests/Find.Computer.Tests.ps1` — COMP-01 contract + scope
- [ ] `tests/Result.Schema.Tests.ps1` — D-03 Pester contract test
- [ ] `tests/Report.Stale.Tests.ps1` — RPT-04 bucket logic + grace math
- [ ] `tests/Report.AccountState.Tests.ps1` — RPT-05 four states
- [ ] `tests/Report.Inventory.Tests.ps1` — RPT-06 OS/inventory
- [ ] `tests/Report.Recovery.Tests.ps1` — RPT-07 recovery posture
- [ ] `tests/Render.Tests.ps1` — RPT-01/02/03 renderer parity
- [ ] `tests/Menu.Tests.ps1` — MENU-01..04 dispatch + B/Q reserved inputs

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Interactive `Out-GridView` picker on Desktop edition | RPT-01 | Requires interactive Windows PowerShell Desktop session and GUI | Run `Start-Adman` on a Windows workstation with Desktop edition; select a report and verify grid opens |
| Interactive `Out-ConsoleGridView` picker on PS7 Core | RPT-01 | Requires PS7 Core + ConsoleGuiTools module + interactive session | Run `Start-Adman` in PS7 with `Microsoft.PowerShell.ConsoleGuiTools` installed; verify picker opens |
| Live AD lastLogonTimestamp semantics on multi-DC domain | RPT-04 | Requires a real domain with ≥2 DCs and controlled logon events | Log on as a test user, wait for replication, compare `lastLogonTimestamp` across DCs; verify grace window absorbs lag |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
