---
phase: 03
slug: remote-computer-operations-isolated
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-16
validated: 2026-07-17
---

# Phase 3: Remote Computer Operations (isolated) — Validation Report

**Phase:** 03-remote-computer-operations-isolated  
**Validation date:** 2026-07-17  
**Status:** validated  
**Nyquist compliant:** true

## Scope

Validate that Phase 3 delivers the four requirements `RMT-01` through `RMT-04`:

- `RMT-01`: WinRM → CIM/WSMan → CIM/DCOM → skip transport ladder with per-host process-only cache.
- `RMT-02`: Unreachable hosts reported as `Skipped` (first-class non-error); short timeouts prevent menu hangs.
- `RMT-03`: Read-only remote queries enrich inventory with online/OS/uptime/logged-on-user data.
- `RMT-04`: Double-hop handled by design; no CredSSP; local-on-target queries only.

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | Pester 6.0.0 |
| Config file | none — tests use `#Requires -Modules Pester` |
| Quick run command | `Invoke-Pester -Path tests/Remoting.*.Tests.ps1 -Tag Unit` |
| Full suite command | `Invoke-Pester -Path tests/ -Tag Unit` |
| Estimated runtime | ~20 s (Remoting suite ~11 s; full suite varies) |

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | RMT-01, RMT-02 | T-03-SC | `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap` exist in schema/defaults/loader; missing keys are merged without overwriting user values; `$script:TransportCache` initialized. | unit | `Invoke-Pester -Path tests/Config.Load.Tests.ps1, tests/Config.FailClosed.Tests.ps1, tests/Config.NoSecrets.Tests.ps1, tests/Config.RoundTrip.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-01-02 | 01 | 1 | RMT-01, RMT-02 | T-03-01 .. T-03-04 | `Connect-AdmanTarget` runs fixed WinRM → CIM/WSMan → CIM/DCOM → Skipped ladder; process-only cache keyed by uppercase computer name; no live sessions cached. | unit | `Invoke-Pester -Path tests/Remoting.Ladder.Tests.ps1, tests/Remoting.Cache.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-01-03 | 01 | 1 | RMT-02 | T-03-01, T-03-02 | `Test-AdmanWsmanTimeout`, `Test-AdmanCimSessionTimeout`, `Convert-AdmanRemoteError`, and cap enforcement return Skipped without hanging or leaking stack traces; no orphan jobs remain. | unit | `Invoke-Pester -Path tests/Remoting.WsmanTimeout.Tests.ps1, tests/Remoting.CimSessionTimeout.Tests.ps1, tests/Remoting.Skipped.Tests.ps1, tests/Remoting.TimeCaps.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-02-01 | 02 | 2 | RMT-03, RMT-04 | T-03-05 .. T-03-08 | `Invoke-AdmanRemoteCimQuery` allow-lists only `Win32_OperatingSystem`/`Win32_ComputerSystem`; `Invoke-AdmanRemoteQuery` reuses one transient CIM session and forwards a shrinking timeout budget. | unit | `Invoke-Pester -Path tests/Remoting.Query.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-02-02 | 02 | 2 | RMT-03 | T-03-07 | `Get-AdmanInventoryReport` enriches rows with `Transport`/`RemoteOS`/`Uptime`/`LoggedOnUser`, preserves AD OS columns, enforces per-host + total caps, emits single skipped-host warning. | unit | `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-02-03 | 02 | 2 | RMT-03 | — | Inventory enrichment tests and D-03 schema contract remain green; lint clean on changed files. | unit + static | `Invoke-Pester -Path tests/Remoting.Query.Tests.ps1, tests/Report.Inventory.Tests.ps1, tests/Result.Schema.Tests.ps1 -Tag Unit`; `Invoke-ScriptAnalyzer -Path Private/Remoting/ -Settings PSScriptAnalyzerSettings.psd1`; `Invoke-ScriptAnalyzer -Path Public/Get-AdmanInventoryReport.ps1 -Settings PSScriptAnalyzerSettings.psd1` | ✅ | ✅ green |
| 03-03-01 | 03 | 3 | RMT-04 | T-03-09 .. T-03-12 | `docs/REMOTE-OPS.md` documents double-hop stance, CredSSP exclusion, RBCD/JEA future paths, sensitive accounts, pass-through credentials, timeouts, and WinRM vs DCOM firewall ports. | docs | `Test-Path docs/REMOTE-OPS.md` | ✅ | ✅ green |
| 03-03-02 | 03 | 3 | RMT-04 | T-03-09 .. T-03-11 | `Invoke-AdmanRemoteCimQuery` rejects disallowed classes with D-07 guard; static tests prove no `CredSSP`/`Invoke-Command`/`New-PSSession` in `Private/Remoting/*.ps1`; only two `-ClassName` literals exist. | unit + static | `Invoke-Pester -Path tests/Remoting.DoubleHop.Tests.ps1 -Tag Unit` | ✅ | ✅ green |
| 03-03-03 | 03 | 3 | cross | — | Full Phase 3 remoting suite and lint gates pass. | unit + static | `Invoke-Pester -Path tests/Remoting.Ladder.Tests.ps1, tests/Remoting.WsmanTimeout.Tests.ps1, tests/Remoting.CimSessionTimeout.Tests.ps1, tests/Remoting.Cache.Tests.ps1, tests/Remoting.Skipped.Tests.ps1, tests/Remoting.TimeCaps.Tests.ps1, tests/Remoting.Query.Tests.ps1, tests/Remoting.DoubleHop.Tests.ps1 -Tag Unit`; `Invoke-ScriptAnalyzer -Path Private/Remoting/ -Settings PSScriptAnalyzerSettings.psd1`; `Invoke-ScriptAnalyzer -Path Public/Get-AdmanInventoryReport.ps1 -Settings PSScriptAnalyzerSettings.psd1` | ✅ | ✅ green |

## Requirements → Tests Map

| Req ID | Behavior | Test Type | Automated Command | File Status | Verification Status |
|--------|----------|-----------|-------------------|-------------|---------------------|
| RMT-01 | Ladder order: WinRM → CimWsman → CimDcom → skip; explicit protocol options used. | unit | `Invoke-Pester tests/Remoting.Ladder.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-01 | Transport name cached per host, keyed uppercase, process-only. | unit | `Invoke-Pester tests/Remoting.Cache.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-02 | Dead/timeout hosts return `Transport='Skipped'` and empty remote fields. | unit | `Invoke-Pester tests/Remoting.Skipped.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-02 | Per-host cap and total cap are enforced. | unit | `Invoke-Pester tests/Remoting.TimeCaps.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-02 | `Test-WSMan` timeout wrapper returns result/times out/cleans up jobs. | unit | `Invoke-Pester tests/Remoting.WsmanTimeout.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-03 | Inventory rows gain `Transport`, `RemoteOS`, `Uptime`, `LoggedOnUser`. | unit | `Invoke-Pester tests/Report.Inventory.Tests.ps1 -Tag Unit` | extended | ✅ COVERED |
| RMT-03 | Uptime emitted as `[TimeSpan]`. | unit | `Invoke-Pester tests/Remoting.Query.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| RMT-04 | Second-hop operations are structurally refused; no CredSSP option. | unit + static | `Invoke-Pester tests/Remoting.DoubleHop.Tests.ps1 -Tag Unit` | created | ✅ COVERED |
| cross | No new external packages required; no AD write cmdlets in Public remoting code. | static | `Invoke-ScriptAnalyzer -Path Public/ -Settings PSScriptAnalyzerSettings.psd1` | existing harness | ✅ COVERED |
| cross | Connector code is lint-clean. | static | `Invoke-ScriptAnalyzer -Path Private/Remoting/ -Settings PSScriptAnalyzerSettings.psd1` | existing harness | ✅ COVERED |

## Sampling Rate

- **Per task commit:** `Invoke-Pester -Path tests/Remoting.*.Tests.ps1 -Tag Unit`
- **Per wave merge:** `Invoke-Pester -Path tests/ -Tag Unit`
- **Phase gate:** Full suite green before `/gsd-verify-work`

## Wave 0 Gaps

All Wave 0 gaps were closed during execution:

- [x] `tests/Remoting.Ladder.Tests.ps1` — covers RMT-01 ladder order and protocol options.
- [x] `tests/Remoting.Cache.Tests.ps1` — covers RMT-01 process-only cache behavior.
- [x] `tests/Remoting.Skipped.Tests.ps1` — covers RMT-02 `Skipped` first-class outcome.
- [x] `tests/Remoting.TimeCaps.Tests.ps1` — covers RMT-02 per-host + total caps.
- [x] `tests/Remoting.WsmanTimeout.Tests.ps1` — covers `Test-AdmanWsmanTimeout` job wrapper.
- [x] `tests/Remoting.Query.Tests.ps1` — covers RMT-03 CIM classes and `[TimeSpan]` uptime.
- [x] `tests/Remoting.DoubleHop.Tests.ps1` — covers RMT-04 structural guard.
- [x] Extend `tests/Report.Inventory.Tests.ps1` — asserts new `Transport`, `RemoteOS`, `Uptime`, `LoggedOnUser`, `Bucket='Inventory'` columns and correct skipped-host warning count.
- [x] Extend `config/adman.schema.json` + `config/adman.defaults.json` — add `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap`.

## Manual-Only Verifications

All phase behaviors have automated verification.

## Exit Criteria

All of the following are true:

1. [x] Every requirement `RMT-01`..`RMT-04` has at least one passing unit/static test mapped above.
2. [x] `Invoke-Pester -Path tests/Remoting.*.Tests.ps1 -Tag Unit` passes (51 tests).
3. [x] `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1 -Tag Unit` passes (15 tests).
4. [x] `Invoke-ScriptAnalyzer -Path Private/Remoting/ -Settings PSScriptAnalyzerSettings.psd1` reports zero findings.
5. [x] `Invoke-ScriptAnalyzer -Path Public/Get-AdmanInventoryReport.ps1 -Settings PSScriptAnalyzerSettings.psd1` reports zero findings.
6. [x] No AD write cmdlets appear in Public remoting code (existing AST/ScriptAnalyzer guard).

## Validation Audit 2026-07-17

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Requirements covered | 4 / 4 (RMT-01..RMT-04) |
| Phase 3 remoting unit tests | 51 passed, 0 failed |
| Inventory report unit tests | 15 passed, 0 failed |
| PSScriptAnalyzer findings | 0 |

---
*Validation report for Phase 3 — aligned with 03-RESEARCH.md and the three Phase 3 execution plans.*
