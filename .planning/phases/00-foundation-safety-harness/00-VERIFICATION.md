---
phase: 00-foundation-safety-harness
verified: 2026-07-14T00:00:00Z
status: passed
score: 17/17 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 17/17
  trigger: "Gap-closure plan 00-06 (UAT gap #3): retarget tests/Safety.WhatIf.Integration.Tests.ps1 at non-protected child user fixtures + harden Private/Safety/Test-AdmanTargetAllowed.ps1 step (b) to skip RID-deny when objectSid is absent"
  gaps_closed:

    - "UAT gap #3 code-side closure: WhatIf integration test no longer crashes on the OU-DN target and now matches the gate's resolve-identity-as-is semantics (targets lab-whatif-* user fixtures, asserts Succeeded == fixture count / Denied == 0 / audit targets == resolved)"
    - "Test-AdmanTargetAllowed step (b) no longer throws under StrictMode on a non-security-principal target (OU/container); RID-deny skipped only when objectSid is absent, principal RID denial unweakened"
  gaps_remaining: []
  regressions: []
  automated_recheck:
    unit_suite: "138 passed / 0 failed (9 NotRun = Integration files correctly excluded)"
    principal_denial_regression: "Safety.DenyList + Safety.Protected + Safety.Scope = 29 passed / 0 failed (renamed RID-500 still refused)"
    lint_edited_file: "Invoke-ScriptAnalyzer on Private/Safety/Test-AdmanTargetAllowed.ps1 = 0 findings"
    files_changed_in_00_06: "tests/Safety.WhatIf.Integration.Tests.ps1, Private/Safety/Test-AdmanTargetAllowed.ps1 (ONLY these two; Safety.Protected.Integration.Tests.ps1 untouched)"
human_verification:

  - test: "Approve and run the PSFramework/Pester/PSScriptAnalyzer install on a real workstation (00-01 user_setup / T-00-SC)"
    expected: "Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0) installs cleanly; the module still imports and the Unit suite stays green against the REAL PSFramework (tests currently use a throwaway stub)."
    why_human: "The package-legitimacy seam did not run in this environment; the first PSFramework install is a deliberate human-approved supply-chain gate, never auto-approved."

  - test: "Run the -Tag Integration tests against the disposable lab OU (set ADMAN_TEST_OU + ADMAN_TEST_DC) from the operator's runas /netonly PS7 session on D:\\adman — this is the 00-06 Task 3 steps 4-5 manual lab re-run that closes UAT gap #3 end-to-end"
    expected: "Safety.WhatIf.Integration.Tests.ps1 gated -WhatIf It block PASSES: AD unchanged (both lab-whatif-* users still Enabled), Succeeded == 2, Denied == 0, audit target DN set == resolved set (SAFE-01/10). Safety.Protected.Integration.Tests.ps1 still PASSES (nested-admin refused + Refused audit record; gMSA/RID-500 may be Inconclusive if fixtures absent — acceptable). On green, flip UAT test 2 to pass and mark gap #3 FIXED in 00-UAT.md."
    why_human: "Lab-only by design (T-00-18); requires a reachable lab DC (lab-dc01.lab.local) from the operator's interactive runas /netonly session — the agent cannot reach the lab. The 00-06 code-side closure is automated-only until this live run confirms SAFE-01/10 against real AD."

  - test: "Confirm DPAPI cross-machine/cross-user re-prompt (CONF-04)"
    expected: "A stored credential restored on a different machine/user throws CryptographicException 0x8009000B (or yields an empty password); the bad file is deleted and Get-Credential is invoked as fallback."
    why_human: "DPAPI is key-bound to user/machine; the cross-machine restore failure cannot be exercised on a single host and needs a second machine/user."
---

# Phase 00: Foundation & Safety Harness — Verification Report

**Phase Goal:** Build the Foundation & Safety Harness — the load-bearing safety spine (config substrate, credential/capability, the mutation gate, the audit writer) that the project's core value depends on, proven before any real write can merge.
**Verified:** 2026-07-11 (initial); re-verified 2026-07-14 after gap-closure plan 00-06
**Status:** human_needed (all automated checks green; 3 deliberate end-of-phase human gates remain — one is the 00-06 manual lab re-run)
**Re-verification:** Yes — after gap closure (plan 00-06, UAT gap #3)

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
| SAFE-01 | 00-04, 00-06 | SATISFIED | SupportsShouldProcess ConfirmImpact='High'; `-WhatIf:$WhatIfPreference -Confirm:$false`; dry-run no mutation. 00-06: WhatIf integration test retargeted at non-protected user fixtures to prove AD-unchanged end-to-end (lab-only, pending operator re-run) |
| SAFE-02 | 00-04 | SATISFIED | Scaled confirmation (default-No single; typed-count `-cne` bulk); `-Force` skips only prompt; no `$Confirm` read |
| SAFE-03 | 00-05 | SATISFIED | D-03 schema JSON-lines record; no secret fields (both-directions proof) |
| SAFE-04 | 00-05 | SATISFIED | Write-ahead PENDING throws before AD; OUTCOME escalates without rollback; orphan sweep detects gaps |
| SAFE-05 | 00-04 | SATISFIED | Deny-list by objectSid RID (`Split('-')[-1]`), never sAMAccountName; renamed RID-500 refused. 00-06 step-(b) guard preserves this exactly for principals (see Re-Verification below) |
| SAFE-06 | 00-04 | SATISFIED | gMSA objectClass pre-filter + IN_CHAIN `1.2.840.113556.1.4.1941` + RFC-4515 escaping; zero `adminCount`; no hard-coded `S-1-5-21-` |
| SAFE-07 | 00-04 | SATISFIED | Component-boundary `$t -eq $root -or $t.EndsWith(',' + $root)`; zero `-like "*"` substring |
| SAFE-08 | 00-01, 00-04, 00-05 | SATISFIED | Explicit FunctionsToExport (gate absent); AST guard + custom PSSA rule single-sourced; 0 AD write verbs in Public/ |
| SAFE-09 | 00-04, 00-05 | SATISFIED | 9-verb allow-list excludes hard-delete; no Remove-ADObject wrapper; ValidateSet rejects it |
| SAFE-10 | 00-04, 00-06 | SATISFIED | One resolver, one array, preview ≡ execute. 00-06: WhatIf test asserts Succeeded == resolved fixture count and audit target DN set == resolved set (lab-only, pending operator re-run) |

**Orphaned requirements:** none. All 17 IDs declared across the 6 PLAN frontmatters (00-01..00-06) are present in REQUIREMENTS.md and all map to Phase 0 = Complete. Plan 00-06 declared SAFE-01 + SAFE-10; both are present in REQUIREMENTS.md (Phase 0 = Complete) and are accounted for above. No REQUIREMENTS.md Phase-0 ID is unclaimed by a plan.

### Anti-Patterns Found

None blocking. The two `'Simulate'` string matches in `Confirm-AdmanAction.ps1` are comments explaining why the string comparison is wrong (negative documentation reinforcing the `[bool]$WhatIfPreference` discriminator) — not the discriminator itself. No TBD/FIXME/XXX, no empty returns flowing to output, no placeholder handlers in the safety spine. The two files changed by 00-06 (`tests/Safety.WhatIf.Integration.Tests.ps1`, `Private/Safety/Test-AdmanTargetAllowed.ps1`) were re-scanned: zero TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers, no empty-return stubs.

### Deviations (from 00-05 SUMMARY — verified as legitimate)

1. Named-mutex literal `Global\adman-audit` lives in the `New-AdmanAuditMutex` seam (not the writer body) — the plan's own seam mandate governs; the named mutex IS used and test-proven. Acceptable.
2. StrictMode-safe `.PSObject.Properties[name]` reads in `Get-AdmanRecoveryPosture` — correctness fix. Acceptable.

3-4. Pester 6 naming/result-parsing hygiene in test tooling — harness-only. Acceptable.

---

## Re-Verification: Gap-Closure Plan 00-06 (UAT gap #3)

**Trigger:** Plan 00-06 closed UAT gap #3 (the only unfixed UAT gap) with two targeted edits. This re-verification confirms the closure preserves the phase's safety invariants and introduces no regressions. All checks below were re-run in the verifier's own process on 2026-07-14.

### Files changed (exactly two — confirmed via `git diff 6db55f1..6624974 --name-only`)

- `tests/Safety.WhatIf.Integration.Tests.ps1` (commit `ad3cb9f`)
- `Private/Safety/Test-AdmanTargetAllowed.ps1` (commit `6624974`)

`tests/Safety.Protected.Integration.Tests.ps1` is **untouched** (not in the 00-06 diff) — the SAFE-06 sibling cannot have regressed from this plan.

### Safety-invariant check (a): step-(b) hardening does NOT weaken RID denial for principals

| Check | Result | Status |
|-------|--------|--------|
| Unguarded `$Object.objectSid).Value` cast removed | grep for `objectSid\)\.Value` / `\$Object\.objectSid\)\.Value` = **0 matches** | PASS |
| Cast is null-guarded | L58 reads `$sid` via `$Object.PSObject.Properties['objectSid']`; L59 `if ($null -ne $sid)` wraps the L60 `([System.Security.Principal.SecurityIdentifier]$sid).Value.Split('-')[-1]` cast | PASS |
| Deny check preserved for principals | L61-63 `if ($rid -in $script:DenyRids) { $reasons.Add("deny-listed RID $rid") }` intact, runs for any object WITH a sid | PASS |
| No early return added | accumulate-reasons pattern intact; single `return @{ Allowed ... }` at L98 | PASS |
| Principal-denial regression suite | `Safety.DenyList + Safety.Protected + Safety.Scope` = **29 passed / 0 failed** (renamed RID-500 still refused; RID 500/501/502 all refused; non-deny RID 1000 allowed) | PASS |

The guard skips the RID-deny check ONLY when objectSid is absent/null (non-security-principals such as OUs/containers). Such a target is NOT silently allowed — it remains subject to step (c) managed-OU scope and step (d) protected-membership. Any object WITH an objectSid runs the exact prior deny check. **SAFE-05 is unweakened.**

### Safety-invariant check (b): WhatIf test retargeting matches gate semantics

| Check | Result | Status |
|-------|--------|--------|
| OU DN no longer the mutation target | `@($script:TestOu)` grep = only L55 (the lab *config* `ManagedOUs`, not the mutation call); the `Invoke-AdmanMutation` call passes `-Targets $t` where `$t` = the `$targets` fixture-DN array | PASS |
| Dedicated non-protected fixtures provisioned | `lab-whatif-1` / `lab-whatif-2` created idempotently via `New-ADUser` in the gated path (L113-129); explicitly NOT lab-nested-admin / gMSA / RID-500 | PASS |
| Succeeded asserted against fixture count | L169 `$result.Succeeded \| Should -Be $targets.Count`; L171 `$result.Denied \| Should -Be 0` | PASS |
| AD-unchanged asserted via fixture Enabled state | L159-165 re-reads each fixture's `Enabled` and asserts `Should -BeTrue` (not OU child-object count) | PASS |
| Audit targets == resolved set | L187-190 extracts `.dn` from each audit `targets[]` detail object and set-compares to `$targets` | PASS |
| Init + invocation patterns preserved | `Initialize-AdmanLab` (L104) + `& (Get-Module adman) { ... Invoke-AdmanMutation ... }` module-scope invocation (L152-155) intact; `-Tag 'Integration'` markers present | PASS |

The retargeting matches the gate's resolve-identity-as-is semantics (option (a), user decision 2026-07-14): the gate resolves each given identity as-is and does NOT enumerate OU children, so the test now targets child USER fixtures and asserts a truthful Succeeded count.

### Automated re-check (independently re-run by verifier, 2026-07-14)

| Gate | Command | Result | Status |
|------|---------|--------|--------|
| Full Unit suite | `Invoke-Pester -Path tests -TagFilter Unit` | Tests Passed: **138**, Failed: **0**, NotRun: 9 (Integration files correctly excluded) | PASS |
| Principal-denial regression | `Invoke-Pester Safety.DenyList + Safety.Protected + Safety.Scope` | Tests Passed: **29**, Failed: **0** | PASS |
| Lint on edited production file | `Invoke-ScriptAnalyzer Private/Safety/Test-AdmanTargetAllowed.ps1` | **0 findings** | PASS |

### Anti-pattern scan (00-06 changed files)

Zero TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers in either changed file. No empty returns flowing to output, no placeholder handlers. The two auto-fixed deviations recorded in 00-06-SUMMARY (un-pipeable foreach → explicit accumulate loop; audit-target comparison extracts `.dn` from `{dn,sid,objectClass}` objects) are correctness fixes verified against the Write-AdmanAudit schema — legitimate, no scope creep.

### Re-verification conclusion

Gap #3 code-side closure is **verified**: both edits are present, substantive, and wired; the step-(b) hardening preserves principal RID denial (29/0 regression green); the WhatIf retargeting matches gate semantics; the full Unit suite stays green (138/0) and lint is clean. **No new gaps, no regressions.** The closure is automated-only until the operator runs the manual lab re-run (00-06 Task 3 steps 4-5), which is the lab-integration human_verification item above. Status remains `human_needed`.

---

### Human Verification Required

The three end-of-phase human gates listed in frontmatter (PSFramework real-install approval; lab integration run — now the 00-06 manual re-run; DPAPI cross-machine re-prompt). These are deliberate phase-level deferrals (`workflow.human_verify_mode=end-of-phase`), not gaps — the automated spine is fully green. The lab-integration gate is the one that closes UAT gap #3 end-to-end: on a green WhatIf run the operator flips UAT test 2 to `pass` and marks gap #3 FIXED in `00-UAT.md`.

### Gaps Summary

No gaps. Every must-have truth is VERIFIED against the codebase, all 17 requirements are SATISFIED, and the phase exit gate was independently re-run green (138/0 Unit, 0 lint, AST guard 4/0). Gap-closure plan 00-06 was re-verified on 2026-07-14: its two edits preserve the safety invariants (principal RID denial unweakened, 29/0 regression green) and introduce no regressions. Status is `human_needed` solely because the phase intentionally defers three checks to a human (a supply-chain install approval, the lab integration re-run that closes UAT gap #3 end-to-end, and a DPAPI cross-machine check). The safety spine the goal depends on is present, wired, and proven.

---

_Verified: 2026-07-11 (initial); re-verified 2026-07-14 (post-00-06)_
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

**Gap-closure plan 00-06 re-verified (2026-07-14):** UAT gap #3 code-side closure confirmed — the WhatIf test now targets non-protected `lab-whatif-*` user fixtures (resolve-identity-as-is) and `Test-AdmanTargetAllowed` step (b) skips RID-deny only for objectSid-absent targets. Principal RID denial is **unweakened** (Safety.DenyList/Protected/Scope regression **29 passed / 0 failed**; renamed RID-500 still refused). Full Unit suite **138/0**, lint **0 findings**. Only the two intended files changed; `Safety.Protected.Integration.Tests.ps1` untouched. No new anti-patterns.

### Human Verification Required

3 deliberate end-of-phase gates (not gaps):

1. **PSFramework real-install approval** (T-00-SC supply-chain gate) — tests use a throwaway stub; the real install stays a human-approved action.
2. **Lab integration re-run** (SAFE-01/06/10 end-to-end; 00-06 Task 3 steps 4-5) — from the operator's runas /netonly PS7 session on `D:\adman` with `ADMAN_TEST_OU` + `ADMAN_TEST_DC` set, run both `-Tag Integration` files; on a green WhatIf run flip UAT test 2 to `pass` and mark gap #3 FIXED in `00-UAT.md`. This is the gate that closes UAT gap #3 end-to-end.
3. **DPAPI cross-machine re-prompt** (CONF-04) — needs a second machine/user to exercise the 0x8009000B restore-failure path.

Awaiting human verification of those three items; the automated safety spine is green and the 00-06 gap closure is verified regression-free.
