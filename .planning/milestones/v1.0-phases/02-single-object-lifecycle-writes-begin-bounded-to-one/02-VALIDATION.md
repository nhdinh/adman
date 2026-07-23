---
phase: 2
slug: single-object-lifecycle-writes-begin-bounded-to-one
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-15
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 |
| **Config file** | None — tests use `#Requires -Modules Pester` and standard Describe/It/Should |
| **Quick run command** | `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit` |
| **Full suite command** | `Invoke-Pester -Path tests/ -Tag Unit` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit`
- **After every plan wave:** Run `Invoke-Pester -Path tests/ -Tag Unit`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | USER-02/04, LUSR-01/02, GRP-01/02/03 | T-02-01/02/03/04/05/06/07/08 | Gate infrastructure: D-01 create path, D-02 local gate, D-04 group matrix, D-05 CSPRNG, audit/confirm extensions, config schema | unit | `Invoke-Pester -Path tests/Utility.Password.Tests.ps1, tests/Safety.GateOrder.Tests.ps1, tests/Local.Gate.Tests.ps1, tests/Safety.Gate.Tests.ps1, tests/Audit.Schema.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 2 | USER-02 | T-02-01/02 | Create user through gate with synthetic target; uniqueness pre-flight; D-05 display-once | unit | `Invoke-Pester -Path tests/User.Create.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-02-02 | 02 | 2 | USER-03 | — | Disable/enable user through gate | unit | `Invoke-Pester -Path tests/User.Disable.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-02-03 | 02 | 2 | USER-04 | T-02-02 | Reset password without echo/log; SecureString never marshaled; D-05 display-once; must-change config override | unit | `Invoke-Pester -Path tests/User.Password.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-02-04 | 02 | 2 | USER-05 | — | Unlock pinned to PDCe; reads LockedOut first | unit | `Invoke-Pester -Path tests/User.Unlock.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-02-05 | 02 | 2 | USER-06 | T-02-08 | Move user with destination-OU scope validation | unit | `Invoke-Pester -Path tests/User.Move.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-03-01 | 03 | 2 | COMP-02 | — | Disable/enable computer through gate | unit | `Invoke-Pester -Path tests/Computer.Disable.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-03-02 | 03 | 2 | COMP-03 | T-02-08 | Move computer with destination validation | unit | `Invoke-Pester -Path tests/Computer.Move.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-03-03 | 03 | 2 | COMP-04 | — | Reset computer account with honest guidance | unit | `Invoke-Pester -Path tests/Computer.Reset.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-04-01 | 04 | 2 | LUSR-01 | T-02-05/10 | Local user CRUD through local gate; RID-500 refused; localhost-only -ComputerName; D-03 pre-delete state capture; parameter sets | unit | `Invoke-Pester -Path tests/Local.User.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-04-02 | 04 | 2 | LUSR-02 | T-02-06 | Local group membership; orphaned-SID tolerant enumeration; fail-closed on total failure | unit | `Invoke-Pester -Path tests/Local.Group.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-05-01 | 05 | 2 | GRP-01/02/03 | T-02-03/04 | Add/remove group member; dual resolution; protected-group refusal (direct SID equality); asymmetric remove; audit names both sides | unit | `Invoke-Pester -Path tests/Group.Add.Tests.ps1, tests/Group.Remove.Tests.ps1, tests/Group.Protected.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-06-01 | 06 | 3 | MENU-04 | T-02-02/04 | Menu integration; D-05 prompt engine; manifest exports; separator guard | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1, tests/Start.Adman.Tests.ps1, tests/Module.Manifest.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 02-06-02 | 06 | 3 | SAFE-08/09 | T-02-04 | Phase exit gate: full suite green; AST guard re-proven; lint clean | unit | `Invoke-Pester -Path tests/ -Tag Unit; Invoke-ScriptAnalyzer -Path Public/, Private/ -Settings PSScriptAnalyzerSettings.psd1 -Severity Error` | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/Safety.GateOrder.Tests.ps1` — extend for create path (D-01) and group matrix (D-04)
- [ ] `tests/Safety.Gate.Tests.ps1` — extend AST guard for local verbs (D-02)
- [ ] `tests/Mocks/ActiveDirectory.psm1` — extend with local account mocks (Get-LocalUser, Get-LocalGroupMember, New-LocalUser, etc.)
- [ ] `tests/Utility.Password.Tests.ps1` — D-05 CSPRNG generator + complexity validator tests
- [ ] `tests/Local.Gate.Tests.ps1` — D-02 local gate fixed-order + policy tests
- [ ] `tests/User.Create.Tests.ps1` — USER-02 create path tests (incl. D-05 display-once)
- [ ] `tests/User.Disable.Tests.ps1` — USER-03 disable/enable tests
- [ ] `tests/User.Password.Tests.ps1` — USER-04 password reset tests (incl. D-05 display-once + must-change config override)
- [ ] `tests/User.Unlock.Tests.ps1` — USER-05 PDCe-pinned unlock tests
- [ ] `tests/User.Move.Tests.ps1` — USER-06 move validation tests
- [ ] `tests/Local.User.Tests.ps1` — LUSR-01 local user tests (incl. parameter sets + D-03 pre-delete state)
- [ ] `tests/Local.Group.Tests.ps1` — LUSR-02 local group tests
- [ ] `tests/Computer.Disable.Tests.ps1`, `Computer.Move.Tests.ps1`, `Computer.Reset.Tests.ps1` — COMP-02/03/04 tests
- [ ] `tests/Group.Add.Tests.ps1`, `Group.Remove.Tests.ps1`, `Group.Protected.Tests.ps1` — GRP-01/02/03 tests
- [ ] `tests/Audit.Schema.Tests.ps1` — extended schema tests for group field + local target shape + preDeleteState
- [ ] `tests/Start.Adman.Tests.ps1` — menu separator selectability guard tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real AD write end-to-end against lab OU | USER-02..06, COMP-02..04, GRP-01..03 | Requires live domain (lab reachable only via `runas /netonly` PS7 session on `D:\adman`) | `Invoke-Pester -Path tests/ -Tag Integration` with `ADMAN_TEST_OU` + `ADMAN_TEST_DC` set; verify PENDING→OUTCOME audit pairs on disk |
| Local user lifecycle against localhost SAM | LUSR-01/02 | Touches real local accounts; never run against production machines | Integration tests create throwaway `adman-test-*` local accounts, clean up in AfterAll |
| DPAPI/credential prompt on insufficient rights | CONF-04/06 | Interactive credential prompt | Manual UAT per Phase 0 pattern |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
