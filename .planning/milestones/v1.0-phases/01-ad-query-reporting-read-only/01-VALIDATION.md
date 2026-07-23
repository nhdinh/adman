---
phase: 01
slug: ad-query-reporting-read-only
status: verified
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-14
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 (installed on dev host for both editions) |
| **Config file** | `tests/PesterConfiguration.psd1` |
| **Quick run command** | `Invoke-Pester -Path tests -Output Detailed -ExcludeTag Integration` |
| **Full suite command** | `Invoke-Pester -Path tests -Output Normal -ExcludeTag Integration` — run under BOTH `powershell` (5.1) and `"C:\Program Files\PowerShell\7\pwsh.exe"` (7.6); the project baseline is dual-edition |
| **Estimated runtime** | ~23–28 seconds per edition unit-only; ~60 seconds with integration tag against lab OU |

---

## Sampling Rate

- **After every task commit:** Run `Invoke-Pester -Path tests -Output Normal -ExcludeTag Integration`
- **After every plan wave:** Run the full suite under BOTH `powershell` (5.1) and `pwsh` (7.6) — edition parity is part of the contract (2026-07-15 audit: three defect classes were edition-specific and invisible on a single edition)
- **Before `/gsd-verify-work`:** Full unit suite must be green on both editions; integration tests run only in the lab environment
- **Max feedback latency:** 30 seconds for unit-only

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | MENU-01 | T-01-01 | Menu renders with numbered items | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ✅ | ✅ green |
| 01-01-02 | 01-01 | 1 | MENU-02 | T-01-02 | Numeric input validated; prompts supply required params | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ✅ | ✅ green |
| 01-01-03 | 01-01 | 1 | MENU-03 | T-01-03 | `B` returns to menu; `Q` exits from any prompt | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ✅ | ✅ green |
| 01-01-04 | 01-01 | 1 | MENU-04 | T-01-04 | Menu dispatches same verb as senior direct call | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ✅ | ✅ green |
| 01-02-01 | 01-02 | 1 | USER-01 | T-02-01 | `Find-AdmanUser` loops ManagedOUs, exact Properties, page size 1000 | unit | `Invoke-Pester -Path tests/Find.User.Tests.ps1` | ✅ | ✅ green |
| 01-02-02 | 01-02 | 1 | COMP-01 | T-02-02 | `Find-AdmanComputer` loops ManagedOUs, exact Properties, page size 1000 | unit | `Invoke-Pester -Path tests/Find.Computer.Tests.ps1` | ✅ | ✅ green |
| 01-02-03 | 01-02 | 1 | D-03 schema | T-02-03 | `ConvertTo-AdmanResult` emits fixed property set per type | unit | `Invoke-Pester -Path tests/Result.Schema.Tests.ps1` | ✅ | ✅ green |
| 01-02-04 | 01-02 | 1 | USER-01/COMP-01 | T-02-03 | `Escape-AdmanAdFilterLiteral` doubles `'`/`\`; passes wildcards through | unit | `Invoke-Pester -Path tests/Utility.EscapeFilter.Tests.ps1` | ✅ | ✅ green |
| 01-03-01 | 01-03 | 2 | RPT-04 | T-03-01 | Stale report buckets Stale vs NeverLoggedOn; never per-DC lastLogon | unit | `Invoke-Pester -Path tests/Report.Stale.Tests.ps1` | ✅ | ✅ green |
| 01-03-02 | 01-03 | 2 | RPT-05 | T-03-02 | Account-state report uses Search-ADAccount four switches; never UAC bit math | unit | `Invoke-Pester -Path tests/Report.AccountState.Tests.ps1` | ✅ | ✅ green |
| 01-03-03 | 01-03 | 2 | RPT-07 | T-03-03 | Recovery posture preflight caches interval + posture | unit | `Invoke-Pester -Path tests/Preflight.Tests.ps1` | ✅ | ✅ green |
| 01-03-04 | 01-03 | 2 | RPT-07 | T-03-03 | Recovery posture report wrapper exposes posture + freshness | unit | `Invoke-Pester -Path tests/Report.Recovery.Tests.ps1` | ✅ | ✅ green |
| 01-04-01 | 01-04 | 3 | RPT-01 | T-04-01 | Console table + Out-GridView/ConsoleGridView fallback | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ✅ | ✅ green |
| 01-04-02 | 01-04 | 3 | RPT-02 | T-04-02 | CSV export `-NoTypeInformation` UTF8 | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ✅ | ✅ green |
| 01-04-03 | 01-04 | 3 | RPT-03 | T-04-03 | HTML self-contained single file; no `-CssUri`/`-Charset`/`-Meta`/`-Transitional` | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ✅ | ✅ green |
| 01-04-04 | 01-04 | 3 | RPT-06 | T-04-04 | Inventory report includes OS version + computer attributes | unit | `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `tests/Mocks/ActiveDirectory.psm1` — extend `Search-ADAccount` mock with state switches and scoping parameters
- [x] `tests/Find.User.Tests.ps1` — USER-01 contract + scope
- [x] `tests/Find.Computer.Tests.ps1` — COMP-01 contract + scope
- [x] `tests/Result.Schema.Tests.ps1` — D-03 Pester contract test
- [x] `tests/Report.Stale.Tests.ps1` — RPT-04 bucket logic + grace math
- [x] `tests/Report.AccountState.Tests.ps1` — RPT-05 four states
- [x] `tests/Report.Inventory.Tests.ps1` — RPT-06 OS/inventory
- [x] `tests/Report.Recovery.Tests.ps1` — RPT-07 recovery posture
- [x] `tests/Preflight.Tests.ps1` — D-07/D-08 Initialize-Adman sync-interval and recovery-posture caching
- [x] `tests/Render.Tests.ps1` — RPT-01/02/03 renderer parity
- [x] `tests/Menu.Tests.ps1` — MENU-01..04 dispatch + B/Q reserved inputs

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Interactive `Out-GridView` picker on Desktop edition | RPT-01 | Requires interactive Windows PowerShell Desktop session and GUI | Run `Start-Adman` on a Windows workstation with Desktop edition; select a report and verify grid opens |
| Interactive `Out-ConsoleGridView` picker on PS7 Core | RPT-01 | Requires PS7 Core + ConsoleGuiTools module + interactive session | Run `Start-Adman` in PS7 with `Microsoft.PowerShell.ConsoleGuiTools` installed; verify picker opens |
| Live AD lastLogonTimestamp semantics on multi-DC domain | RPT-04 | Requires a real domain with ≥2 DCs and controlled logon events | Log on as a test user, wait for replication, compare `lastLogonTimestamp` across DCs; verify grace window absorbs lag |

---

## Validation Audit 2026-07-15

| Metric | Count |
|--------|-------|
| Gaps found | 3 (6 failing tests, all PS 5.1-edition-specific; PS 7.6 was 327/0) |
| Resolved | 3 |
| Escalated | 0 |

**Findings and resolutions (all test-infrastructure; no implementation bugs):**

1. **RPT-04 ×4 tests** — `$result.Count` returned `$null` under 5.1 because a lone PSCustomObject has no `.Count` property on Desktop edition (PS 7 auto-adds `.Count` to scalars). Fixed by wrapping report invocations in `@(...)` in tests/Report.Stale.Tests.ps1; mock bodies also inlined to remove It-scope variable references (the two 'excludes…' tests had been false-positives).
2. **RPT-01 ×1 test** — grid-fallback test assumed a Core host (no ConsoleGuiTools); on Desktop 5.1 `Out-GridView` exists in-box and returned empty in the non-interactive host. Fixed by mocking `Out-GridView` to throw so the try/catch console-table fallback is deterministically exercised on both editions.
3. **SAFE-01 lint ×1** — `.planning/spikes/005-dpapi-vault-roundtrip/Test-CrossUser.ps1` contained UTF-8 em-dashes with no BOM; the 5.1 tokenizer read it as ANSI and failed string tokenization at line 62. Fixed by replacing em-dashes with ASCII hyphens; spike behavior unchanged; repo-wide lint gate scope unchanged.

**Final verification (full unit suite, `-ExcludeTag Integration`):**
- Windows PowerShell 5.1: 327 passed / 0 failed (5 NotRun = lab-integration skips)
- PowerShell 7.6: 327 passed / 0 failed (5 NotRun = lab-integration skips)
- Lint gate (5.1, repo-wide recurse): clean

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** verified 2026-07-15
