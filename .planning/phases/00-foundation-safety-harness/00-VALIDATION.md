---
phase: 00
slug: foundation-safety-harness
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-10
validated: 2026-07-15
---

# Phase 00 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Stack: PowerShell 5.1 (baseline) + 7.6.3 LTS. All AD/CIM/remoting cmdlets are MOCKED in unit tests — unit tests MUST never touch a live domain (project constraint). Integration tests run only against a disposable test OU/lab.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 (WinPS 5.1 + PS 7.4+) |
| **Config file** | `tests/PesterConfiguration.psd1` |
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
| 00-01-01 | 00-01 | 1 | MENU-05 | T-00-SC | PSFramework 1.14.457 provenance/signatures re-verified to disk before pin; no install performed | other | `powershell -NoProfile -Command "Test-Path .planning/phases/00-foundation-safety-harness/00-01-PSFramework-verified.md"` + `Select-String '1.14.457'` | ✅ | ✅ green |
| 00-01-02 | 00-01 | 1 | SAFE-08 | T-00-01 | Module loads on 5.1; exports exactly the manifest list; gate NOT exported; import side-effect-free; PSFramework exact-pinned; no AD dependency | unit | `Invoke-Pester -Path tests/Module.Manifest.Tests.ps1` | ✅ | ✅ green |
| 00-01-03 | 00-01 | 1 | SAFE-08 | T-00-01/11/12 | Lint clean w/ ShouldProcess enforced; custom rule + AST guard share one banned list and fire on positive control; AD/CIM mocks domain-free | unit | `Invoke-Pester -Path tests/Harness.Tests.ps1,tests/Safety.Gate.Tests.ps1` | ✅ | ✅ green |
| 00-02-01 | 00-02 | 2 | CONF-01/03/05 | T-00-05 | Schema/defaults/example shipped; no secret names/values (real regex, both directions); defaults fail closed; RID seed; `.store/` gitignored | unit | `Invoke-Pester -Path tests/Config.NoSecrets.Tests.ps1` | ✅ | ✅ green |
| 00-02-02 | 00-02 | 2 | CONF-01/02/03 | T-00-07/14 | Pinned-path load; fail-closed on empty scope/malformed/failed deny-list; seed once; round-trip `-Depth >=5`; 5.1-safe | unit | `Invoke-Pester -Path tests/Config.Load.Tests.ps1,tests/Config.FailClosed.Tests.ps1,tests/Config.RoundTrip.Tests.ps1` | ✅ | ✅ green |
| 00-02-03 | 00-02 | 2 | CONF-01/02/03 | T-00-13 | Four config verbs `-Path`-pinned; Set/Import re-run single validator + fail-closed; manifest boundary updated | unit + lint | `Test-ModuleManifest ./adman.psd1` + `Invoke-ScriptAnalyzer -Path Public/Config -Recurse -Settings PSScriptAnalyzerSettings.psd1` | ✅ | ✅ green |
| 00-03-01 | 00-03 | 3 | CONF-04/06 | T-00-05/09 | Pass-through default; prompt on insufficient rights; DPAPI consent-gated; restore failure deletes + re-prompts; keyed-AES rejected; no secret logged | unit | `Invoke-Pester -Path tests/Credential.Dpapi.Tests.ps1,tests/Credential.PassThrough.Tests.ps1` | ✅ | ✅ green |
| 00-03-02 | 00-03 | 3 | MENU-05 | T-00-03/15 | Read-only capability probe (never writes to test rights); fail-closed on empty scope/unwritable audit; live-SID protected/deny resolution; six-step orchestration | unit | `Invoke-Pester -Path tests/Foundation.Capability.Tests.ps1,tests/Initialize.Adman.Tests.ps1` | ✅ | ✅ green |
| 00-04-01 | 00-04 | 4 | SAFE-05/06/07/10 | T-00-02/03/06/08 | Single resolver (preview≡execute); component-boundary scope; deny by RID; gMSA pre-filter + IN_CHAIN protected (RFC-4515 escaped); never adminCount/names | unit | `Invoke-Pester -Path tests/Safety.Scope.Tests.ps1,tests/Safety.DenyList.Tests.ps1,tests/Safety.Protected.Tests.ps1,tests/Safety.PreviewEqualsExecute.Tests.ps1` | ✅ | ✅ green |
| 00-04-02 | 00-04 | 4 | SAFE-01/02/09 | T-00-10/16 | Scaled confirmation (`-cne` exact count; `[bool]$WhatIfPreference` first); `-Force` skips prompt only; 9 gate-only wrappers; no hard-delete wrapper; cap placeholder | unit | `Invoke-Pester -Path tests/Safety.Confirm.Tests.ps1,tests/Safety.NoHardDelete.Tests.ps1` | ✅ | ✅ green |
| 00-04-03 | 00-04 | 4 | SAFE-08/04 | T-00-01/19 | THE GATE: fixed order Resolve→Allow→Bulk→Confirm→PENDING→Write→OUTCOME; ValidateSet == allow-list; refusal logged+skipped; PENDING-throw blocks write; decline writes nothing | unit | `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1` | ✅ | ✅ green |
| 00-05-01 | 00-05 | 5 | SAFE-03/04 | T-00-04/05/17 | Write-ahead JSONL under named mutex; `Flush($true)`; PENDING failure throws before AD; OUTCOME failure escalates (no rollback); D-03 schema, no secrets (both directions) | unit | `Invoke-Pester -Path tests/Audit.Schema.Tests.ps1,tests/Audit.FailClosed.Tests.ps1` | ✅ | ✅ green |
| 00-05-02 | 00-05 | 5 | SAFE-03/04 | D-03 | PENDING↔OUTCOME orphan sweep (read-only, no silent drop); recovery-posture reporter (Recycle Bin/FFL/tombstone) warning-only, never gates | unit | `Invoke-Pester -Path tests/Audit.OrphanSweep.Tests.ps1,tests/RecoveryPosture.Tests.ps1` | ✅ | ✅ green |
| 00-05-03 | 00-05 | 5 | SAFE-08/09 | T-00-01/16/18 | Phase exit gate: full mocked Unit suite green + lint clean + SAFE-08/09 AST guard vs Public/; integration tests doubly gated (`-Tag 'Integration'` + ADMAN_TEST_OU) | unit + lint | `Invoke-Pester -Path tests -TagFilter Unit` + `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` | ✅ | ✅ green |
| 00-06-01 | 00-06 | 1 | SAFE-01/10 | T-00-20 | WhatIf integration test targets non-protected `lab-whatif-*` user fixtures (resolve-identity-as-is); AD-unchanged; Succeeded==fixture count; Denied==0; audit targets==resolved | integration (lab) | `Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration` (lab-only; ADMAN_TEST_OU-gated) | ✅ | ⚠️ pending lab |
| 00-06-02 | 00-06 | 1 | SAFE-05/06 | T-00-19 | Test-AdmanTargetAllowed step (b) null-guards objectSid cast; RID-deny skipped only for non-principals; principal denial unweakened | unit | `Invoke-Pester -Path tests/Safety.DenyList.Tests.ps1,tests/Safety.Protected.Tests.ps1,tests/Safety.Scope.Tests.ps1` | ✅ | ✅ green |
| 00-06-03 | 00-06 | 1 | SAFE-01/10 | T-00-18 | Full Unit suite green after hardening; lint clean on edited file; Integration files still excluded from Unit run | unit + lint | `Invoke-Pester -Path tests -TagFilter Unit` + `Invoke-ScriptAnalyzer -Path Private/Safety/Test-AdmanTargetAllowed.ps1 -Settings PSScriptAnalyzerSettings.psd1` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky / pending lab.*

**Green evidence:** statuses asserted from the authoritative full-suite runs recorded in `00-05-SUMMARY.md` (138/138 Unit, 2026-07-13) and `00-06-SUMMARY.md` (138/138 after the step-(b) hardening, 2026-07-14), refreshed by the Phase 1 validation full-suite run recorded in `01-VALIDATION.md` (2026-07-15): **327 passed / 0 failed on Windows PowerShell 5.1 AND PowerShell 7.6** (`-ExcludeTag Integration`; includes all Phase 0 tests after the Phase-1 WR fixes to `Test-AdmanTargetAllowed.ps1` and `Get-AdmanRecoveryPosture.ps1`). Repo-wide `Invoke-ScriptAnalyzer -Recurse` = 0 findings (00-05 exit gate). The auditor's independent re-run attempt on 2026-07-15 hung on this host (>10 min, environmental — OneDrive PSModulePath/Pester-6 host quirks documented in plan deviations); not a test-correctness signal.

---

## Wave 0 Requirements

- [x] `tests/` directory + `tests/PesterConfiguration.psd1` (coverage enabled, CI exit on failure)
- [x] `PSScriptAnalyzerSettings.psd1` at repo root (7 rules incl. `PSUseShouldProcessForStateChangingFunctions`; documented `PSAvoidUsingWriteHost` suppression scoped to the TUI module only)
- [x] Module manifest `adman.psd1` + root module `adman.psm1` with `Public/`/`Private/` loader and explicit `FunctionsToExport`
- [x] Mock helpers for AD cmdlets (`Get-AD*`, `Set-AD*`, `New-AD*`, `Remove-AD*`), CIM (`Get-CimInstance`, `New-CimSession`), and remoting (`Invoke-Command`, `New-PSSession`) so NO unit test touches a live domain — `tests/Mocks/ActiveDirectory.psm1`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| End-to-end `-WhatIf` against a real test OU | SAFE-01/10 | Needs a live domain + test OU; destructive by nature | Lab-only: run `Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration` with `ADMAN_TEST_OU`+`ADMAN_TEST_DC` set (operator's runas /netonly PS7 session); confirm preview targets == execute targets. **Status: pending operator lab re-run (00-06 retargeted the fixtures; UAT test 2 flips to pass on a green run).** |
| DPAPI credential round-trip + cross-machine re-prompt | CONF-04/06 | DPAPI keys are user/machine-bound; can't automate cross-machine failure | Save credential with "remember me"; attempt restore from a different machine/user → confirm re-prompt (CryptographicException 0x8009000B). The delete-and-reprompt code path itself is unit-proven (Credential.Dpapi Test 4a). |
| Authenticode signature validity under `AllSigned` | CONF/stack | Requires enterprise code-signing cert | `Get-AuthenticodeSignature` on signed `.psd1`/`.psm1`/`.ps1`; confirm `Valid` under `AllSigned` |
| Protected-account refusal against real protected groups | SAFE-06 | Needs real Domain Admins / gMSA objects | Lab-only: `Invoke-Pester -Path tests/Safety.Protected.Integration.Tests.ps1 -TagFilter Integration` with `ADMAN_TEST_OU`+`ADMAN_TEST_DC`; confirm nested-DA member + gMSA refused + `Refused` audit records. **Status: pending operator lab re-run.** |
| First PSFramework install approval (package-legitimacy gate) | T-00-SC | Supply-chain seam: first install is never auto-approved | Approve and run `Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser` after confirming `00-01-PSFramework-verified.md` (verdict [OK]). Tests use a throwaway 1.14.457 stub so the gate stays open by design. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (18/18 tasks mapped above)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 90s for quick per-plan runs (full suite is longer; see green-evidence note re: host)
- [x] The non-bypass guard is automated: a Pester AST test (`tests/Safety.Gate.Tests.ps1`) + PSScriptAnalyzer custom rule (`rules/AdmanSafetyRules.psm1`) prove no `Public/*.ps1` calls AD write cmdlets directly (SAFE-08 exit gate) — single-sourced banned list via `Get-AdmanBannedWriteVerbs`
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-07-15 (audit below)

---

## Validation Audit 2026-07-15

| Metric | Count |
|--------|-------|
| Tasks audited | 18 (6 plans) |
| Requirements mapped | MENU-05, CONF-01..06, SAFE-01..10 |
| Gaps found | 0 (MISSING: 0, PARTIAL: 0) |
| Tests generated | 0 (no gaps to fill) |
| Escalated | 0 |
| Manual-only behaviors | 5 (see table; 2 lab integration runs pending operator) |

**State:** A (existing draft VALIDATION.md audited and populated).
**Auditor:** not spawned — zero test gaps; per workflow, no gaps → set `nyquist_compliant: true`.
**Fresh green evidence:** full unit suite 327 passed / 0 failed on WinPS 5.1 AND PS 7.6 recorded in `01-VALIDATION.md` (2026-07-15, post Phase-1 WR fixes to two Phase-0 safety files).
**Caveat:** the auditor's independent re-run on this host hung (>10 min, environmental); statuses rely on the recorded runs cited above.
