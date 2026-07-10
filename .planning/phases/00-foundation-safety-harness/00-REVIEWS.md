---
phase: 0
cycle: 4
reviewers: [codex]
reviewed_at: 2026-07-10T17:39:33Z
plans_reviewed: [00-01-PLAN.md, 00-02-PLAN.md, 00-03-PLAN.md, 00-04-PLAN.md, 00-05-PLAN.md]
supersedes: "cycle-3 REVIEWS.md (commit aa9ba0b); cycle-3 content retained as audit history in the Appendix"
reviewer_outcomes:
  codex:
    status: success
    invocations: 1
    empty_output: false
    note: "codex-cli 0.144.1 (ChatGPT OAuth) ran `codex exec --ephemeral --dangerously-bypass-hook-trust --skip-git-repo-check -` against a 346,800-byte prompt (≈86.7K tokens) and emitted a 5,828-byte grounded review (exit 0; elapsed 161s; tokens used 172,086; stderr tool-trace 578,319 bytes captured to a real file). Read-only sandbox; workdir C:\\Users\\nhdinh\\dev\\adman."
cycle_summary:
  current_high: 1
  current_actionable: 1
  convergence: false
  note: "Counts are reviewer-gated (codex status=success, empty_output=false) AND independently source-grounded (reproduced on both Windows PowerShell 5.1.26100.8737 and PowerShell 7.x). The single HIGH is C3-H1 STILL UNRESOLVED: the cycle-4 replan (0e250c1) fixed the STRUCTURE of the -WhatIf disambiguation (check WhatIf first; Outcome shape; gate branching) but chose a discriminator, `$WhatIfPreference -eq 'Simulate'`, that is `$false` under a REAL `-WhatIf` on both 5.1 and 7.x (`$WhatIfPreference` is a SwitchParameter(True), never the string 'Simulate'). Reproduced end-to-end: a nested gate->Confirm-AdmanAction under real `-WhatIf` returns Outcome='Declined' and throws 'Operator declined.' (and at/above threshold would Read-Host-prompt during a dry-run) — exactly the C3-H1 failure the replan aimed to remove. The tests (00-04:148,171) set `$WhatIfPreference='Simulate'` as a STRING, so they pass against a state the engine never produces (green tests / broken prod). C3-L1 is FULLY RESOLVED (00-05:110 real regex, no -SimpleMatch, both directions, positive-control fixture). The four cycle-2 fixes (C2-H1/M1/M2/L1) HOLD. The one actionable item is a NEW, LOW, non-load-bearing wording nit: 00-04:42 must-have still says typed-count uses `(-ceq)` 'refusing on mismatch' while the action (00-04:158) and acceptance (00-04:168) correctly use `-cne` and explicitly warn against the inverted form. The two pre-existing LOW doc-hygiene residuals (00-RESEARCH.md:464 / 00-PATTERNS.md:252 `-ceq`; 00-RESEARCH.md:180,233 PENDING-before-confirm) remain non-counted per instruction. This was the user-authorized +1 extension (cycle 4); it did NOT converge -> escalate: Proceed-anyway / Manual-review (a one-token surgical replan — `'Simulate'` -> `[bool]$WhatIfPreference`/`$true` — would resolve C3-H1)."
---

# Cross-AI Plan Review — Phase 0 (Foundation & Safety Harness) — CYCLE 4 (+1 EXTENSION, DECIDING)

**Status: COMPLETE — Codex (the only requested reviewer, `--codex`) succeeded and produced a grounded review, AND an independent source-grounding pass reproduced the decisive fact on both required runtimes. The cycle-4 replan fixed the SHAPE of the `-WhatIf` disambiguation but its discriminator (`$WhatIfPreference -eq 'Simulate'`) does not detect a real `-WhatIf`, so C3-H1 is NOT resolved. C3-L1 IS resolved; all cycle-1/cycle-2 fixes HOLD. Convergence is FALSE on the +1 extension -> human decision required (Proceed-anyway / Manual-review). The fix is a one-token change (`'Simulate'` -> `[bool]$WhatIfPreference`) plus aligning one must-have phrase.**

This run invoked `--codex` only. Codex (`codex-cli 0.144.1`, ChatGPT OAuth, read-only sandbox, workdir `C:\Users\nhdinh\dev\adman`) read the repo and emitted **5,828 bytes** of structured review (exit 0; 161s; 172,086 tokens). Prompt assembled under `C:\Users\nhdinh\AppData\Local\Temp\gsd-review-0-c4` (this host cannot write literal `/tmp`); stderr captured to a real file (not `/dev/null`) for diagnosability. No content was fabricated. `reviewer_outcomes.codex.status=success empty_output=false`.

---

## Reviewer Status

| Reviewer | Requested | Detected | Outcome |
|----------|-----------|----------|---------|
| codex    | yes (`--codex`) | available (`codex-cli 0.144.1`, logged in via ChatGPT) | **SUCCESS — 5,828-byte review, repo-grounded, exit 0** |

Cycle history: cycle-1 (`ba6e17b`) 2 HIGH + 6 actionable -> all 8 incorporated (`f75734a`; plan-checker PASSED). Cycle-2 (`262b8ee`) 1 NEW HIGH + 3 actionable -> all 4 incorporated (`e39f684`; plan-checker PASSED). Cycle-3 (`aa9ba0b`) 1 NEW HIGH (C3-H1 `-WhatIf` control-flow) + 1 LOW (C3-L1 `-SimpleMatch`) -> surgical replan (`0e250c1`; plan-checker PASSED with the ShouldProcess fact re-derived). This is **cycle 4 (the user-authorized +1 extension after cycle 3 hit the max-3 cap)** — a fresh review to verify C3-H1/C3-L1 are RESOLVED and to catch any NEW issues.

---

## Codex Review (verbatim, this run)

> ## Summary
>
> C3-H1 is **not resolved**. The replan improved the gate shape, but the load-bearing discriminator is wrong for real PowerShell `-WhatIf`.
>
> I verified locally:
>
> | Runtime | Real `-WhatIf` `$WhatIfPreference` type | Value | `$WhatIfPreference -eq 'Simulate'` |
> |---|---:|---:|---:|
> | Windows PowerShell 5.1.26100.8737 | `System.Management.Automation.SwitchParameter` | `True` | `False` |
> | PowerShell 7.6.0 | `System.Management.Automation.SwitchParameter` | `True` | `False` |
>
> When manually set as `$WhatIfPreference = 'Simulate'`, it is a `System.String` and the comparison returns `True`, but that is **not what real `-WhatIf` does**.
>
> C3-L1 appears resolved.
>
> ## Strengths
>
> - C3-L1 is fixed in mechanism, not just prose. [00-05-PLAN.md:83](00-05-PLAN.md) requires a real regex and a positive-control secret fixture; [line 110](00-05-PLAN.md) explicitly bans `-SimpleMatch` and requires both clean and secret-bearing cases.
> - Cycle-2 config no-secret fix still holds: [00-02-PLAN.md:83](00-02-PLAN.md) uses a real regex, whitelists `credentialPolicy.allowRememberMe`, and adds a positive-control schema; [line 113](00-02-PLAN.md) pins the acceptance checks.
> - Cycle-2 AD resolver parameter-set fix still holds: [00-04-PLAN.md:116](00-04-PLAN.md) explicitly removes `-SearchBase/-SearchScope` from the `-Identity` lookup; [line 128](00-04-PLAN.md) adds an AST assertion.
> - Cycle-2 LDAP escaping fix still holds: [00-04-PLAN.md:118](00-04-PLAN.md) requires escaping the target DN and group DNs before building the IN_CHAIN filter; [line 129](00-04-PLAN.md) adds special-character fixtures.
> - Several earlier safety fixes still hold: exact PSFramework pin and no RSAT dependency at [00-01-PLAN.md:130](00-01-PLAN.md), side-effect-free import at [00-01-PLAN.md:131](00-01-PLAN.md), rights-first credential prompting at [00-03-PLAN.md:106](00-03-PLAN.md), and zero-byte audit probe at [00-03-PLAN.md:151](00-03-PLAN.md).
>
> ## Concerns
>
> ### HIGH: C3-H1 remains unresolved because the dry-run discriminator cannot detect real `-WhatIf`
>
> **File**: [00-04-PLAN.md:160](00-04-PLAN.md)
>
> **Issue**: The plan requires:
>
> ```powershell
> $isWhatIf = ($WhatIfPreference -eq 'Simulate')
> ```
>
> But in both Windows PowerShell 5.1 and PowerShell 7.6, real `-WhatIf` sets `$WhatIfPreference` to a `System.Management.Automation.SwitchParameter` with value `True`, not the string `Simulate`.
>
> **Mechanism**: Under real `-WhatIf`, `$PSCmdlet.ShouldProcess()` returns `$false`, but `$WhatIfPreference -eq 'Simulate'` is also `$false`. Therefore the code misses the dry-run branch. Below threshold, the later `ShouldProcess()` false is treated as `Declined`; at/above threshold, the function can still prompt `Read-Host` during a dry-run.
>
> **Tests also encode the wrong state**: [line 148](00-04-PLAN.md) says tests run "with `$WhatIfPreference='Simulate'` (i.e. -WhatIf)", but that is a string fixture, not real engine state. [line 171](00-04-PLAN.md) positively greps for the broken expression, so the test suite would enforce the bug.
>
> **Impact**: Real `-WhatIf` can still be misclassified as an operator decline, so the PENDING audit + inner wrapper `-WhatIf` path is not guaranteed. This fails SAFE-01/03/10 and the specific C3-H1 acceptance claim.
>
> ### LOW: The must-have text still says typed-count uses `-ceq`
>
> **File**: [00-04-PLAN.md:42](00-04-PLAN.md)
>
> The detailed task correctly says to refuse on `$token -cne "$count"` at [line 158](00-04-PLAN.md), but the high-level must-have says "exact count `(-ceq)`, refusing on mismatch." That is confusing but not currently load-bearing because the action and acceptance criteria are correct.
>
> ## Suggestions
>
> - Replace the discriminator with real engine state, e.g. treat dry-run as `[bool]$WhatIfPreference` or compare to `$true`, not `'Simulate'`.
> - Add a test that invokes an actual advanced function with `-WhatIf`, rather than setting `$WhatIfPreference = 'Simulate'` manually.
> - Change the acceptance grep at [00-04-PLAN.md:171](00-04-PLAN.md) so it rejects the string `'Simulate'` discriminator and asserts real-`-WhatIf` behavior.
> - Clean up the `-ceq` wording at [00-04-PLAN.md:42](00-04-PLAN.md).
>
> ## Risk Assessment
>
> **HIGH** until C3-H1 is corrected. The rest of the plan set is materially stronger than cycle 3, and C3-L1 plus the cycle-1/2 fixes appear to hold, but the primary safety-gate dry-run path still fails under real PowerShell `-WhatIf`.
>
> `CYCLE_SUMMARY: current_high=1 current_actionable=1`

---

## Codex-Finding Adjudication (independent source-tracing of each Codex claim)

Codex is a strong reviewer but not infallible (cycle 1 caught a ShouldProcess misread). Each cycle-4 finding was traced against the repo AND against authoritative PowerShell semantics — and, for the HIGH, against a **decisive local experiment reproduced identically on BOTH required runtimes**. Verdicts: **VALID** = confirmed, not incorporated in the current PLAN; **RESOLVED** = confirmed fixed; **MISREAD** = inference does not hold on tracing.

| # | Codex finding | Verdict | Evidence / reasoning |
|---|---------------|---------|----------------------|
| C4-H1 (= C3-H1) | C3-H1 NOT resolved: `$WhatIfPreference -eq 'Simulate'` is `$false` under real `-WhatIf` (SwitchParameter(True), not string) on 5.1 + 7.x, so Confirm-AdmanAction misses the dry-run branch; below threshold -> Declined+throw; at/above threshold -> Read-Host during a dry-run | **VALID — HIGH (confirmed by tracing + empirical PS test on BOTH runtimes)** | **PowerShell fact (decisive, run locally):** a `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` function reading `$WhatIfPreference` under a real `-WhatIf` reports type `System.Management.Automation.SwitchParameter`, value `True`, and `$WhatIfPreference -eq 'Simulate'` == **False**, while `[bool]$WhatIfPreference -eq $true` == **True** and plain truthiness == **True** — reproduced on **Windows PowerShell 5.1.26100.8737 AND PowerShell 7.x** (Codex independently reports 7.6.0). The string `'Simulate'` only matches when `$WhatIfPreference` was *assigned a string* (`$WhatIfPreference='Simulate'`), which is how the plan's TESTS set it (00-04:148,171) but **not** how the engine sets it for `-WhatIf`. **End-to-end reproduction (mirrors production: outer gate called `-WhatIf` -> inner Confirm-AdmanAction):** on BOTH editions, Confirm-AdmanAction prints `wipType=SwitchParameter ... -eq 'Simulate'=False`, falls to the decline branch, returns `Outcome='Declined'`, and the gate throws `Operator declined.` (and at/above threshold it would `Read-Host`-prompt mid-preview). **This is precisely the C3-H1 failure** the replan (0e250c1) aimed to remove — the STRUCTURE is right (check WhatIf first; Outcome shape; gate branches Proceed+DryRun vs Declined) but the DISCRIMINATOR TOKEN is wrong. **Not incorporated; unresolved.** Fix (one token): replace `$WhatIfPreference -eq 'Simulate'` with `[bool]$WhatIfPreference` (or `$WhatIfPreference -eq $true`) at 00-04:160 and the positive-grep anchor at 00-04:171, and make Tests 5/7 drive a REAL advanced function with `-WhatIf` rather than assigning the string. |
| C3-L1 | 00-05:110 no-secret verifier now uses a real regex (no `-SimpleMatch`), asserts both directions, and requires a positive-control secret fixture that must be caught | **RESOLVED — LOW (verified)** | 00-05-PLAN.md:110 reads: `Select-String -Path Private/Audit/Write-AdmanAudit.ps1 -Pattern 'password|secret|credential|apiKey|privateKey'` returns 0 — "REAL regex, NO `-SimpleMatch` ... tests/Audit.Schema.Tests.ps1 proves BOTH directions: (a) a CLEAN parsed record's key set equals the D-03 set ... (PASS); and (b) a POSITIVE-CONTROL fixture containing a banned key/value ... is CAUGHT by the same regex (the test fails if it is not)." This is the same both-directions + positive-control pattern that fixed C2-M1 in 00-02. **Fully resolved.** |
| C4-L1 (NEW) | 00-04:42 must-have still says typed-count uses `(-ceq)` "refusing on mismatch", contradicting the action (00-04:158 `-cne`) and acceptance (00-04:168 `-cne`) | **VALID — LOW (actionable; non-load-bearing wording)** | 00-04-PLAN.md:42 objective/must-have line reads "the operator must type the exact count (-ceq), refusing on mismatch" while 00-04:158 explicitly says "Implement the CORRECT behavior: throw (refuse) when `$token -cne "$count"` ... Do not copy the inverted comparison" and 00-04:168 acceptance requires `-cne`. Codex itself rates this "not currently load-bearing because the action and acceptance criteria are correct." It is a NEWLY-noticed inconsistency surfaced this cycle (not one of the two named doc-hygiene residuals, which live in 00-RESEARCH/00-PATTERNS). It is in a PLAN execution artifact (must_haves) but is overridden, unambiguously, by the operative action + acceptance + an explicit "do not copy the inverted comparison" instruction, so an executor will do the right thing. **Actionable (borderline):** one-line PLAN.md edit to align 00-04:42 to `(-cne)`, OR explicitly defer/reject. Counted as the single actionable non-HIGH; does not by itself block convergence (the HIGH does). |

### Prior fixes re-verified

| Prior finding | Verdict this cycle | Evidence |
|---------------|--------------------|----------|
| C3-L1 (00-05 `-SimpleMatch` no-op verifier) | **FULLY RESOLVED** | 00-05:110 real regex, explicit "NO `-SimpleMatch`", both-directions, positive-control secret fixture that must FAIL (see C3-L1 row above). |
| C2-H1 (`Resolve-AdmanTarget` `-Identity … -SearchBase`) | **HOLDS (FULLY RESOLVED)** | 00-04:116/128 AST assertion that the `-Identity` `Get-ADObject` call binds NO `-SearchBase`/`-SearchScope`; false NOTE gone. Microsoft Learn `Get-ADObject`: Identity set has `-Partition`/`-Properties`/`-Server`, NOT `-SearchBase`/`-SearchScope`. |
| C2-M1 (00-02 no-secret rule vs `credentialPolicy`) | **HOLDS (FULLY RESOLVED)** | 00-02:83 real regex + `credentialPolicy.allowRememberMe` whitelisted + positive-control secret schema; 00-02:113 pins acceptance. |
| C2-M2 (00-01 owns `.claude/CLAUDE.md` D-01 reconciliation) | **HOLDS (FULLY RESOLVED)** | `.claude/CLAUDE.md` in files_modified (00-01:18) + Task 2 (00-01:115); two-row edits (00-01:134-137); positive-grep anchors (00-01:146). |
| C2-L1 (00-04 LDAP-filter DN escaping) | **HOLDS (FULLY RESOLVED)** | `Escape-AdmanLdapFilterValue` (00-04:11/47); applied to target DN + each group DN before IN_CHAIN (00-04:118/129); special-char fixtures `\5c \2a \28 \29 \00`. |
| Cycle-1 (8) fixes | **HOLD** | Codex re-confirmed: PSFramework exact pin + no-RSAT (00-01:130), side-effect-free import (00-01:131), rights-first credential prompting (00-03:106), zero-byte audit probe (00-03:151). 17/17 REQ-IDs, threat_model 5/5, TUI-only remain intact (no edits this cycle touched them). |

---

## Consensus Summary

Only one reviewer (`--codex`) was requested and run, so "consensus" = the codex findings **as independently adjudicated above** (and the adjudication concurs with Codex on every point, including the decisive HIGH). No divergent views to reconcile (no second reviewer this cycle).

### Agreed Strengths
- C3-L1 is fixed in mechanism (real regex + both directions + positive-control fixture), not just prose — matching the 00-02 C2-M1 pattern.
- All four cycle-2 fixes and the cycle-1 set remain incorporated with concrete, grep-verifiable mechanisms.
- The cycle-4 replan got the `-WhatIf` disambiguation STRUCTURE right (WhatIf-first ordering; Outcome shape `{Proceed,DryRun,Declined; WhatIf}`; gate branches Proceed+DryRun -> PENDING+wrapper vs Declined -> throw/nothing).

### Agreed Concerns (highest priority)
- **C4-H1 (HIGH, VALID, unresolved):** the `-WhatIf` discriminator `$WhatIfPreference -eq 'Simulate'` does not detect a real `-WhatIf` on either required runtime (SwitchParameter(True) ≠ string), so Confirm-AdmanAction still misclassifies a dry-run as Declined (below threshold -> throw 'Operator declined.'; at/above threshold -> Read-Host prompt during preview). Tests encode the wrong (string) state and would pass against a condition production never hits (SAFE-01/04/10). One-token fix: `[bool]$WhatIfPreference`.
- **C4-L1 (LOW, VALID, actionable, borderline):** 00-04:42 must-have `-ceq` wording contradicts the operative `-cne` action/acceptance; one-line alignment or explicit deferral.

### Divergent Views
- None (single reviewer). Independent adjudication concurs with Codex on all findings and all HOLDS.

---

## Verification coverage (source-grounding this cycle)

- Repo read directly: `00-04-PLAN.md` (lines 1-279 incl. Tasks 1-3, threat model, verification), `00-05-PLAN.md` (lines 90-149 incl. Task 1 acceptance), the prior `00-REVIEWS.md` (cycle 3) in full, plus the assembled prompt context (PROJECT head, ROADMAP phase-0, REQUIREMENTS, 00-CONTEXT, 00-RESEARCH, 00-PATTERNS, all 5 PLANs).
- Greenfield re-confirmed: `git ls-files '*.ps1' '*.psm1' '*.psd1'` = 0 -> every `Private/` `Public/` `config/` `tests/` `rules/` symbol is a forward reference (UNCHECKABLE/new, hardBlock=false), NOT counted as a defect.
- **Empirical PowerShell reproduction (decisive), run locally on BOTH required runtimes** (`C:\Users\nhdinh\AppData\Local\Temp\gsd-review-0-c4\wip.ps1`, `assign.ps1`, `nested2.ps1`):

  | Probe | WinPS 5.1.26100.8737 | PowerShell 7.x |
  |---|---|---|
  | `$WhatIfPreference` type under real `-WhatIf` | `SwitchParameter` | `SwitchParameter` |
  | `$WhatIfPreference` value under real `-WhatIf` | `True` | `True` |
  | `$WhatIfPreference -eq 'Simulate'` under real `-WhatIf` | **False** | **False** |
  | `[bool]$WhatIfPreference -eq $true` under real `-WhatIf` | **True** | **True** |
  | `$PSCmdlet.ShouldProcess()` under `-WhatIf` | **False** (+ "What if:" line) | **False** |
  | Nested gate(`-WhatIf`)->Confirm-AdmanAction result | Outcome=`Declined` -> gate **throws 'Operator declined.'** | Outcome=`Declined` -> gate **throws 'Operator declined.'** |

  Conclusion: the plan's literal discriminator is the bug; `[bool]$WhatIfPreference` (or `$WhatIfPreference -eq $true`) is the correct, edition-portable discriminator.
- Out-of-scope (not counted, by instruction): the two LOW doc-hygiene residuals — stale `-ceq "$count"` snippets in `00-RESEARCH.md:464` / `00-PATTERNS.md:252`; PENDING-before-confirm diagram/prose wording in `00-RESEARCH.md:180,233` (reference artifacts only, non-execution-affecting).

---

## Appendix — prior-cycle audit history

Full text lives in git history. Retrieve with: `git show aa9ba0b:.planning/phases/00-foundation-safety-harness/00-REVIEWS.md` (cycle 3), `git show 262b8ee:...` (cycle 2), `git show ba6e17b:...` (cycle 1).

### Cycle 3 (commit aa9ba0b) — reviewer_outcomes.codex.status=success, empty_output=false
- `CYCLE_SUMMARY: current_high=1 current_actionable=1` (convergence=false; max-3 cap reached -> escalate).
- C3-H1 (HIGH, VALID): `-WhatIf` control-flow contradiction in 00-04 — `Confirm-AdmanAction` threw 'Operator declined.' on the `$false` `ShouldProcess` that `-WhatIf` produces, before the gate wrote PENDING or reached the inner `-WhatIf` wrapper. -> the cycle-4 replan (`0e250c1`) attempted the fix but chose a discriminator (`-eq 'Simulate'`) that does not detect real `-WhatIf` (see C4-H1 above).
- C3-L1 (LOW, VALID): 00-05:110 `Select-String … -SimpleMatch` pipe-pattern no-op verifier. -> incorporated in `0e250c1` (real regex + both directions + positive-control fixture). RESOLVED this cycle.

### Cycle 2 (commit 262b8ee) — reviewer_outcomes.codex.status=success, empty_output=false
- `CYCLE_SUMMARY: current_high=1 current_actionable=3` -> all 4 incorporated (`e39f684`). HOLD re-verified this cycle (C2-H1/M1/M2/L1).

### Cycle 1 (commit ba6e17b) — reviewer_outcomes.codex.status=success, empty_output=false
- `CYCLE_SUMMARY: current_high=2 current_actionable=6` -> all 8 incorporated (`f75734a`; plan-checker PASSED). HOLD re-confirmed this cycle.
- Note: cycle-1 attempt-1 (commit `2a04e57`) FAILED on codex auth (HTTP 401 token_expired/refresh_token_reused; 0 bytes) and was correctly NOT treated as convergence.

### Cycle-4 outcome (this run)
- reviewer_outcomes.codex.status=success, empty_output=false.
- `CYCLE_SUMMARY: current_high=1 current_actionable=1` (convergence=false).
- **+1 extension did NOT converge -> escalate to the human: Proceed-anyway (acknowledge C4-H1/C4-L1 and execute) vs Manual-review (recommended: one-token surgical replan — `'Simulate'` -> `[bool]$WhatIfPreference` at 00-04:160/171 + drive Tests 5/7 with a real `-WhatIf` invocation + align 00-04:42 to `-cne` — outside the auto-loop).** Per the standing stop-and-review gate, do NOT silently chain into `/gsd-execute-phase 0`.
