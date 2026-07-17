---
phase: 04
slug: bulk-workflows-highest-blast-radius-last
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-17
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 |
| **Config file** | `pester.config.json` (repo root) |
| **Quick run command** | `Invoke-Pester -Path Tests/Unit -Tag Unit -CI` |
| **Full suite command** | `Invoke-Pester -Configuration (Get-Content pester.config.json | ConvertFrom-Json)` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `Invoke-Pester -Path Tests/Unit -Tag Unit -CI`
- **After every plan wave:** Run full Pester suite via `pester.config.json`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | BULK-01 | T-04-01 / — | Cap applied after gate filtering | unit | `Invoke-Pester -Path Tests/Unit/Private/Bulk/Invoke-AdmanBulkAction.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | BULK-02 | T-04-02 / — | Typed count confirmation matches filtered set | unit | `Invoke-Pester -Path Tests/Unit/Private/Safety/Assert-AdmanBulkPolicy.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | BULK-04 | T-04-03 / — | CSV unknown headers rejected before gate | unit | `Invoke-Pester -Path Tests/Unit/Private/Bulk/ConvertFrom-AdmanBulkCsv.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | FLOW-01 | T-04-04 / — | Onboarding creates user via existing New-AdmanUser gate | unit | `Invoke-Pester -Path Tests/Unit/Public/Start-AdmanUserOnboarding.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | FLOW-02 | T-04-05 / — | Offboarding strips only non-protected groups | unit | `Invoke-Pester -Path Tests/Unit/Public/Start-AdmanUserOffboarding.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-03-02 | 03 | 2 | FLOW-03 | T-04-06 / — | Restore reverses offboarding from audit record | unit | `Invoke-Pester -Path Tests/Unit/Public/Restore-AdmanQuarantinedUser.Tests.ps1` | ❌ W0 | ⬜ pending |
| 04-04-01 | 04 | 3 | FLOW-04 | T-04-07 / — | Mid-workflow failure stops later steps for that target | unit | `Invoke-Pester -Path Tests/Unit/Private/Workflows/Invoke-AdmanWorkflowStep.Tests.ps1` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/Unit/Private/Bulk/Invoke-AdmanBulkAction.Tests.ps1` — stubs for BULK-01/02/03/04
- [ ] `Tests/Unit/Private/Bulk/ConvertFrom-AdmanBulkCsv.Tests.ps1` — CSV strict schema tests
- [ ] `Tests/Unit/Public/Start-AdmanUserOnboarding.Tests.ps1` — onboarding flow tests
- [ ] `Tests/Unit/Public/Start-AdmanUserOffboarding.Tests.ps1` — offboarding flow tests
- [ ] `Tests/Unit/Public/Restore-AdmanQuarantinedUser.Tests.ps1` — restore path tests
- [ ] `Tests/Unit/Private/Safety/Assert-AdmanBulkPolicy.Tests.ps1` — cap enforcement tests

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CSV ingestion against live directory | BULK-04 | Requires AD lab with importable objects | In the integration-test lab, run `Invoke-AdmanBulkAction -Path sample.csv -WhatIf` and verify preview count equals filtered input count. |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
