---
phase: 00-foundation-safety-harness
verified: 2026-07-11T00:00:00Z
status: human_needed
score: 17/17 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Approve and run the PSFramework/Pester/PSScriptAnalyzer install on a real workstation (00-01 user_setup / T-00-SC)"
    expected: "Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0) installs cleanly; the module still imports and the Unit suite stays green against the REAL PSFramework (tests currently use a throwaway stub)."
    why_human: "The package-legitimacy seam did not run in this environment; the first PSFramework install is a deliberate human-approved supply-chain gate, never auto-approved."
  - test: "Optionally run the -Tag Integration tests against a disposable lab OU (set ADMAN_TEST_OU) to confirm SAFE-01/06/10 end-to-end -WhatIf and protected-account refusal"
    expected: "AD is unchanged after a gated -WhatIf; the audit target list equals the resolved list; nested-DA / gMSA / renamed-RID-500 fixtures are Refused with precise reasons."
    why_human: "Lab-only by design (T-00-18); requires a real disposable domain/OU. Excluded from the default Unit run and cannot be auto-proven on a host with no live AD (VALIDATION manual-only)."
  - test: "Confirm DPAPI cross-machine/cross-user re-prompt (CONF-04)"
    expected: "A stored credential restored on a different machine/user throws CryptographicException 0x8009000B (or yields an empty password); the bad file is deleted and Get-Credential is invoked as fallback."
    why_human: "DPAPI is key-bound to user/machine; the cross-machine restore failure cannot be exercised on a single host and needs a second machine/user."
---

# Phase 00: Foundation & Safety Harness — Verification Report

**Phase Goal:** Build the Foundation & Safety Harness — the load-bearing safety spine (config substrate, credential/capability, the mutation gate, the audit writer) that the project's core value depends on, proven before any real write can merge.
**Verified:** 2026-07-11
**Status:** human_needed (all automated checks green; 3 deliberate end-of-phase human gates remain)
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal is **achieved in code**. Every load-bearing safety invariant the goal names was independently re-confirmed against the actual source (not SUMMARY claims), and the phase exit gate was re-run in my own process: **Unit suite 138 passed / 0 failed, repo-wide PSScriptAnalyzer 0 findings, SAFE-08 AST guard 4 passed / 0 failed**. The only open items are the three deliberate human gates the phase itself deferred (PSFramework real-install approval, optional lab integration run, DPAPI cross-machine check) — these route to `human_needed`, not `gaps_found`.

### Observable Truths (phase-goal level)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Config substrate is portable, plain-JSON, non-secret, and fails closed on empty scope | VERIFIED | `Private/Config/Initialize-AdmanConfig.ps1` loads via `Import-PSFConfig -Path` (L231), zero `Register-PSFConfig`, `ConvertTo-Json -Depth 5` (L164), no `-AsHashtable`; throws `FAIL-CLOSED: managed-OU scope (ManagedOUs) is empty` (L224); `-SetupMode` exempts only the empty-scope gate |
| 2 | Credential is pass-through by default; DPAPI only on consent; restore failure deletes + re-prompts | VERIFIED | `Get-AdmanCredential.ps1` rights-first ordering; `Export-Clixml` with no `-EncryptionKey`; empty-password guard `GetNetworkCredential().Password`; `Remove-Item` on bad file; zero secret logging |
| 3 | The mutation gate is the ONLY AD-write path, non-exported, fixed order | VERIFIED | `Invoke-AdmanMutation.ps1` order Resolve→Allow→BulkPolicy→Confirm→PENDING→Write→OUTCOME (L51-100); absent from `adman.psd1` FunctionsToExport; zero direct AD write cmdlets in gate; ValidateSet = 9-verb allow-list |
| 4 | The audit writer is the ONLY sink, synchronous, write-ahead, fail-closed | VERIFIED | `Write-AdmanAudit.ps1` throws `AUDIT FAIL-CLOSED` on PENDING failure (L94) before AD; `Flush($true)` (L86); zero `Write-PSFMessage`/PSFramework routing; zero AD rollback cmdlets; mutex `Global\adman-audit` + Append + FileShare.Read in `AdmanAuditIO.ps1` seam |
| 5 | Preview ≡ execute via one resolver | VERIFIED | `Resolve-AdmanTarget` called once (L51), same array feeds preview + execute; Identity parameter set without `-SearchBase`/`-SearchScope` (C2-H1) |
| 6 | -WhatIf discriminator is `[bool]$WhatIfPreference`, never `'Simulate'` | VERIFIED | `Confirm-AdmanAction.ps1` L52 `$isWhatIf = [bool]$WhatIfPreference`; the only two `'Simulate'` matches are comments documenting that the engine never produces that string (negative documentation, not the discriminator) |
| 7 | Remove-ADObject absent from the 9 gate-only wrappers | VERIFIED | `Adman.AD.Write.ps1` has exactly 9 functions (Disable/Enable/Move/Set-User/Set-Computer/Set-Password/Unlock/Add-Member/Remove-Member); `Remove-ADObject` count = 0 in Public/ and Private/AD/ |
| 8 | Fail-closed write-ahead audit: declined action writes zero records | VERIFIED | Gate branches on `$confirm.Outcome`; `Outcome='Declined'` throws `Operator declined.` writing nothing (confirm-first, no orphan PENDING); `Confirm-AdmanAction` has zero `Write-AdmanAudit` calls |

### Phase Exit Gate (independently re-run by verifier)

| Gate | Command | Result | Status |
|------|---------|--------|--------|
| Unit suite | `Invoke-Pester -Path tests -TagFilter Unit` | Tests Passed: 138, Failed: 0 | PASS |
| Repo-wide lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` | 0 findings | PASS |
| SAFE-08 AST guard | `Invoke-Pester -Path tests/Safety.Gate.Tests.ps1` | Tests Passed: 4, Failed: 0 | PASS |
| AD write verbs in Public/ | grep Public/ for banned AD write cmdlet set | 0 matches | PASS |
| Hard-delete verb in Public/ + Private/AD | grep for `Remove-ADObject` | 0 matches | PASS |

### Requirements Coverage (all 17 — cross-referenced against REQUIREMENTS.md)

| Req | Source Plan | Status | Evidence |
|-----|------------|--------|----------|
| MENU-05 | 00-01, 00-03 | SATISFIED | `Test-AdmanCapability.ps1` probes RSAT/domain/rights/transport/audit; actionable guidance; fail-closed throws; no real write to test rights |
| CONF-01 | 00-02 | SATISFIED | Portable plain-JSON config from pinned `.store/config.json` via `Import-PSFConfig -Path` |
| CONF-02 | 00-02 | SATISFIED | Fail-closed on empty ManagedOUs / failed load / failed deny-list (setup-mode exempt) |
| CONF-03 | 00-02 | SATISFIED | Save+reload lossless (`ConvertTo-Json -Depth 5`, 5.1-safe PSCustomObject indexing); one shared schema |
| CONF-04 | 00-03 | SATISFIED | DPAPI CurrentUser on consent only; 0x8009000B/empty-password deletes + re-prompts; keyed-AES rejected |
| CONF-05 | 00-02, 00-03, 00-05 | SATISFIED | `.store/` gitignored; no-secret schema (both-directions test); credential never logged |
| CONF-06 | 00-03 | SATISFIED | Pass-through default; rights-first; prompts only when insufficient |
| SAFE-01 | 00-04 | SATISFIED | SupportsShouldProcess ConfirmImpact='High'; `-WhatIf:$WhatIfPreference -Confirm:$false`; dry-run no mutation |
| SAFE-02 | 00-04 | SATISFIED | Scaled confirmation (default-No single; typed-count `-cne` bulk); `-Force` skips only prompt; no `$Confirm` read |
| SAFE-03 | 00-05 | SATISFIED | D-03 schema JSON-lines record; no secret fields (both-directions proof) |
| SAFE-04 | 00-05 | SATISFIED | Write-ahead PENDING throws before AD; OUTCOME escalates without rollback; orphan sweep detects gaps |
| SAFE-05 | 00-04 | SATISFIED | Deny-list by objectSid RID (`Split('-')[-1]`), never sAMAccountName; renamed RID-500 refused |
| SAFE-06 | 00-04 | SATISFIED | gMSA objectClass pre-filter + IN_CHAIN `1.2.840.113556.1.4.1941` + RFC-4515 escaping; zero `adminCount`; no hard-coded `S-1-5-21-` |
| SAFE-07 | 00-04 | SATISFIED | Component-boundary `$t -eq $root -or $t.EndsWith(',' + $root)`; zero `-like "*"` substring |
| SAFE-08 | 00-01, 00-04, 00-05 | SATISFIED | Explicit FunctionsToExport (gate absent); AST guard + custom PSSA rule single-sourced; 0 AD write verbs in Public/ |
| SAFE-09 | 00-04, 00-05 | SATISFIED | 9-verb allow-list excludes hard-delete; no Remove-ADObject wrapper; ValidateSet rejects it |
| SAFE-10 | 00-04 | SATISFIED | One resolver, one array, preview ≡ execute |

**Orphaned requirements:** none. All 17 IDs declared across the 5 PLAN frontmatters are present in REQUIREMENTS.md and all map to Phase 0 = Complete. No REQUIREMENTS.md Phase-0 ID is unclaimed by a plan.

### Anti-Patterns Found

None blocking. The two `'Simulate'` string matches in `Confirm-AdmanAction.ps1` are comments explaining why the string comparison is wrong (negative documentation reinforcing the `[bool]$WhatIfPreference` discriminator) — not the discriminator itself. No TBD/FIXME/XXX, no empty returns flowing to output, no placeholder handlers in the safety spine.

### Deviations (from 00-05 SUMMARY — verified as legitimate)

1. Named-mutex literal `Global\adman-audit` lives in the `New-AdmanAuditMutex` seam (not the writer body) — the plan's own seam mandate governs; the named mutex IS used and test-proven. Acceptable.
2. StrictMode-safe `.PSObject.Properties[name]` reads in `Get-AdmanRecoveryPosture` — correctness fix. Acceptable.
3-4. Pester 6 naming/result-parsing hygiene in test tooling — harness-only. Acceptable.

### Human Verification Required

The three end-of-phase human gates listed in frontmatter (PSFramework real-install approval; optional lab integration run; DPAPI cross-machine re-prompt). These are deliberate phase-level deferrals (`workflow.human_verify_mode=end-of-phase`), not gaps — the automated spine is fully green.

### Gaps Summary

No gaps. Every must-have truth is VERIFIED against the codebase, all 17 requirements are SATISFIED, and the phase exit gate was independently re-run green (138/0 Unit, 0 lint, AST guard 4/0). Status is `human_needed` solely because the phase intentionally defers three checks to a human (a supply-chain install approval and two checks that require a second machine / live lab domain). The safety spine the goal depends on is present, wired, and proven.

---

_Verified: 2026-07-11_
_Verifier: Claude (gsd-verifier)_

## Verification Complete

**Status:** human_needed
**Score:** 17/17 must-haves verified
**Report:** C:\Users\nhdinh\dev\adman\.planning\phases\00-foundation-safety-harness\00-VERIFICATION.md

All automated checks passed. The phase goal — the load-bearing safety spine proven before any real write can merge — is achieved in code and independently re-verified:
- Unit suite **138 passed / 0 failed**; repo-wide PSScriptAnalyzer **0 findings** (incl. custom SAFE-08 rule); SAFE-08 AST guard **4 passed / 0 failed**.
- **0** AD write verbs in `Public/`; **0** `Remove-ADObject` anywhere in `Public/` + `Private/AD/`; exactly **9** gate-only wrappers.
- `-WhatIf` discriminator is `[bool]$WhatIfPreference` (the two `'Simulate'` matches are negative-documentation comments only).
- Preview≡execute via one resolver; fail-closed write-ahead audit (declined action writes zero records; PENDING-throw before AD).

### Human Verification Required
3 deliberate end-of-phase gates (not gaps):
1. **PSFramework real-install approval** (T-00-SC supply-chain gate) — tests use a throwaway stub; the real install stays a human-approved action.
2. **Optional lab integration run** (SAFE-01/06/10 end-to-end) — requires a disposable lab domain (`ADMAN_TEST_OU`); excluded from the default Unit run by design.
3. **DPAPI cross-machine re-prompt** (CONF-04) — needs a second machine/user to exercise the 0x8009000B restore-failure path.

Awaiting human verification of those three items; the automated safety spine is green.
