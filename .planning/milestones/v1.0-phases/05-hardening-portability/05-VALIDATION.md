---
phase: 05
slug: hardening-portability
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-21
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 |
| **Config file** | `tests/PesterConfiguration.psd1` |
| **Quick run command** | `Invoke-Pester -Path tests -Output Normal -Tag Unit` |
| **Full suite command** | `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)` |
| **Estimated runtime** | ~60 seconds (unit), ~5 minutes (full suite + integration) |

---

## Sampling Rate

- **After every task commit:** Run `Invoke-Pester -Path tests -Tag Unit`
- **After every plan wave:** Run full suite via `tests/PesterConfiguration.psd1` plus `Invoke-ScriptAnalyzer`
- **Before `/gsd-verify-work`:** Full suite green on Windows PowerShell 5.1 and PowerShell 7.6 LTS, PSScriptAnalyzer clean, help-coverage test green, and `AllSigned` CI leg passing
- **Max feedback latency:** 60 seconds for quick run

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | DOC-01 | — | README accurately describes install, first-run, and safe usage | manual review + smoke | `Invoke-Pester -Path tests -Tag Unit` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 1 | DOC-02 | — | USAGE.md covers every menu action and exported function | manual review + contract | markdown lint / docs coverage script | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 | 1 | DOC-03 | — | Every public function has SYNOPSIS, DESCRIPTION, PARAMETER, EXAMPLE | unit | `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 05-04-01 | 04 | 2 | (success criterion 2) | T-05-01 | Module runs under `AllSigned` | integration | CI leg with `Set-ExecutionPolicy AllSigned` | ❌ W0 | ⬜ pending |
| 05-04-02 | 04 | 2 | (success criterion 2) | T-05-02 | `CompatiblePSEditions` claim is honest | integration | CI matrix on 5.1 and 7.6 | ❌ W0 | ⬜ pending |
| 05-05-01 | 05 | 2 | (D-05) | T-05-03 | Audit hash-chain verifies correctly | unit | `Invoke-Pester -Path tests/Audit.Integrity.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 05-05-02 | 05 | 2 | (D-05) | T-05-04 | OUTCOME-write failure escalates to Event Log | unit | `Invoke-Pester -Path tests/Audit.EventLog.Tests.ps1 -Tag Unit` | ❌ W0 | ⬜ pending |
| 05-06-01 | 06 | 2 | (D-08) | T-05-05 | `.store/` cannot be committed | integration | `.githooks/pre-commit` + CI checkout scan | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/Help.Coverage.Tests.ps1` — covers DOC-03
- [ ] `tests/Audit.Integrity.Tests.ps1` — covers D-05 hash chain
- [ ] `tests/Audit.EventLog.Tests.ps1` — covers D-05 event-log escalation on OUTCOME failure
- [ ] `.github/workflows/ci.yml` — covers dual-edition matrix and AllSigned
- [ ] `build/Sign-AdmanModule.ps1` — covers Authenticode signing
- [ ] `.githooks/pre-commit` — covers `.store/` commit guard
- [ ] CI checkout scan step — defense in depth for `.store/`
- [ ] `docs/USAGE.md` — covers DOC-02
- [ ] `docs/RECOVERY-RUNBOOK.md` — covers D-07
- [ ] Add `audit.retentionDays` to `config/adman.schema.json` and `config/adman.defaults.json`

*(Existing test infrastructure covers all prior phases; Phase 5 introduces the gaps above.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| README readability and accuracy | DOC-01 | Human judgment on prose | Review `README.md` for install, first-run, and safe-usage instructions |
| USAGE.md completeness against live menu | DOC-02 | Menu actions may shift during execution | Compare exported commands and menu choices against USAGE.md sections |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
