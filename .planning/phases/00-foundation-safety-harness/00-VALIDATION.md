---
phase: 00
slug: foundation-safety-harness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-10
---

# Phase 00 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Stack: PowerShell 5.1 (baseline) + 7.6.3 LTS. All AD/CIM/remoting cmdlets are MOCKED in unit tests — unit tests MUST never touch a live domain (project constraint). Integration tests run only against a disposable test OU/lab.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 (WinPS 5.1 + PS 7.4+) |
| **Config file** | `tests/PesterConfiguration.psd1` (Wave 0 installs) |
| **Quick run command** | `Invoke-Pester -Path tests -Output Detailed` (unit, fully mocked) |
| **Full suite command** | `Invoke-Pester -Configuration tests/PesterConfiguration.psd1` (+ code coverage) |
| **Static analysis** | `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` |
| **Estimated runtime** | ~30–90 seconds (mocked) |

---

## Sampling Rate

- **After every task commit:** Run the affected plan's `*.Tests.ps1` (quick Pester run)
- **After every plan wave:** Run full `Invoke-Pester` suite + `Invoke-ScriptAnalyzer`
- **Before `/gsd-verify-work`:** Full suite green + ScriptAnalyzer clean (incl. `PSUseShouldProcessForStateChangingFunctions`)
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _populated by planner / gsd-nyquist-auditor_ | — | — | — | — | — | — | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky. The planner (§8) lifts SPEC edge cases and SAFE-* truths into each plan's `must_haves`; nyquist-auditor fills this map from the final PLAN.md files.*

---

## Wave 0 Requirements

- [ ] `tests/` directory + `tests/PesterConfiguration.psd1` (coverage enabled, CI exit on failure)
- [ ] `PSScriptAnalyzerSettings.psd1` at repo root (enable `PSUseShouldProcessForStateChangingFunctions`, `PSAvoidUsingPlainTextForPassword`, `PSUsePSCredentialType`, `PSAvoidGlobalVars`, `PSUseApprovedVerbs`, `PSAvoidUsingCmdletAliases`, `PSUseConsistentIndentation`; documented suppression of `PSAvoidUsingWriteHost` in the TUI module only)
- [ ] Module manifest `adman.psd1` + root module `adman.psm1` with `Public/`/`Private/` loader and explicit `FunctionsToExport`
- [ ] Mock helpers for AD cmdlets (`Get-AD*`, `Set-AD*`, `New-AD*`, `Remove-AD*`), CIM (`Get-CimInstance`, `New-CimSession`), and remoting (`Invoke-Command`, `New-PSSession`) so NO unit test touches a live domain

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| End-to-end `-WhatIf` against a real test OU | SAFE-01/10 | Needs a live domain + test OU; destructive by nature | Lab-only: run `*-Adman* -WhatIf` against a disposable test OU; confirm preview targets == execute targets |
| DPAPI credential round-trip + cross-machine re-prompt | CONF-04/06 | DPAPI keys are user/machine-bound; can't automate cross-machine failure | Save credential with "remember me"; attempt restore from a different machine/user → confirm re-prompt (CryptographicException 0x8009000B) |
| Authenticode signature validity under `AllSigned` | CONF/stack | Requires enterprise code-signing cert | `Get-AuthenticodeSignature` on signed `.psd1`/`.psm1`/`.ps1`; confirm `Valid` under `AllSigned` |
| Protected-account refusal against real protected groups | SAFE-06 | Needs real Domain Admins / gMSA objects | Lab-only: attempt disable of a DA member + a gMSA; confirm gate refuses + logs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] The non-bypass guard is automated: a Pester AST test + PSScriptAnalyzer rule prove no `Public/*.ps1` calls AD write cmdlets directly (SAFE-08 exit gate)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
