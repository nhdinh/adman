---
phase: 0
reviewers: [codex]
reviewed_at: 2026-07-10T14:43:51Z
plans_reviewed: [00-01-PLAN.md, 00-02-PLAN.md, 00-03-PLAN.md, 00-04-PLAN.md, 00-05-PLAN.md]
reviewer_outcomes:
  codex:
    status: success
    invocations: 1
    empty_output: false
    note: "Re-authenticated ChatGPT OAuth (fresh ~/.codex/auth.json) + canary `codex exec` returned OK; this run produced a 14,191-byte substantive review. Prior cycle-1 attempt (commit 2a04e57) failed on auth (HTTP 401 token_expired/refresh_token_reused, 2 invocations, 0 bytes) — retained as audit history below."
---

# Cross-AI Plan Review — Phase 0 (Foundation & Safety Harness)

**Status: COMPLETE — Codex (the only requested reviewer, `--codex`) succeeded this cycle and produced a grounded review. An independent source-grounding pass also ran and was used to ADJUDICATE every Codex HIGH/MEDIUM against the repo (one Codex HIGH is a misread of ShouldProcess/`-WhatIf` semantics; the rest are confirmed).**

This run invoked `--codex` only. Codex (`codex-cli 0.144.1`, `model: gpt-5.5`, `sandbox: read-only`, workdir `C:\Users\nhdinh\dev\adman`) read the repo and emitted **14,191 bytes** of structured review (`/c/Users/nhdinh/AppData/Local/Temp/gsd-review-codex-0.md`, exit 0). Prompt was assembled under `$TMPDIR` (this host cannot write literal `/tmp`); stderr captured to a real file (not `/dev/null`) for diagnosability. No content was fabricated.

---

## Reviewer Status

| Reviewer | Requested | Detected | Outcome |
|----------|-----------|----------|---------|
| codex    | yes (`--codex`) | available (`codex-cli 0.144.1`) | **SUCCESS — 14,191-byte review, repo-grounded, exit 0** |

Auth history: cycle-1 attempt-1 (commit `2a04e57`) failed — ChatGPT OAuth access token expired + refresh token rejected (`refresh_token_reused`); every API call 401'd; 0 bytes across 2 invocations. The user re-authenticated (`codex login`); a canary `codex exec` returned `OK`; this run (attempt-2) succeeded. `codex login status` now reports "Logged in using ChatGPT" with a fresh `~/.codex/auth.json`.

---

## Codex Review (verbatim, this run)

> Repo check: this is greenfield for PowerShell as stated. `git ls-files '*.ps1' '*.psm1' '*.psd1'` returned no files, so Codex treated all PowerShell paths as forward references and reviewed the plans against `.planning/**` and `.claude/CLAUDE.md`.

### 00-01-PLAN.md — Module scaffold + harness
- **Strengths:** SAFE-08 anchored in explicit exports + Public/ AST/PSSA guard (ROADMAP:32; 00-01:33,37); PSFramework 1.14.457 treated as a build-time-verified assumption (RESEARCH:635; 00-01:92).
- **MEDIUM:** `RequiredModules=@(@{ModuleName='PSFramework'; ModuleVersion='1.14.457'})` is a **minimum** version, not the "pinned 1.14.457" the plan claims (00-01:35,128). Use an exact-version field or enforce in import/test.
- **MEDIUM:** The plan both runs `Invoke-ScriptAnalyzer -Path . -Recurse` clean **and** creates a positive-control Public fixture containing `Set-ADUser` (00-01:151,167); unless fixtures are excluded, the custom rule flags the fixture and fails the lint run.
- **Risk:** MEDIUM.

### 00-02-PLAN.md — Non-secret config
- **Strengths:** tracked example vs gitignored `.store/` reconciled (CONTEXT:108 → 00-02:108); fail-closed config invariant with explicit `Import-PSFConfig -Path` (CONTEXT D-01:26; 00-02:32,155).
- **MEDIUM:** the "no secret fields" rule bans `token`, but the schema intentionally defines `DenyList[].token` (00-02:83,97) — the test will false-fail or pressure renaming a correct RID/SID concept.
- **MEDIUM:** `Import-PSFConfig -Path` coexisting with plain-JSON schema validation (00-02:129,146; RESEARCH:47,106) — the division of labor is under-specified (risk of two config representations).
- **Risk:** MEDIUM.

### 00-03-PLAN.md — Credential + capability + Initialize-Adman
- **Strengths:** SID-based protected identity (CONTEXT D-02:30-31; 00-03:148); rights probe reads managed OU + group membership, never writes (RESEARCH:483; 00-03:150).
- **HIGH:** `Get-AdmanCredential` returns `$null` immediately when `credentialPolicy.allowRememberMe` is false (00-03:106), so the `$script:RightsInsufficient` prompt path (00-03:109) is unreachable unless remember-me is enabled — contradicts CONF-06 (prompt when rights insufficient; RESEARCH:52) and D-06 (stored credential is only an opt-in storage policy; RESEARCH:19).
- **MEDIUM:** `Test-AdmanAuditWritable` may write "a zero-length or a benign marker" into `audit-YYYYMMDD.jsonl` (00-03:149), but 00-05 requires JSON-lines records with a fixed schema (00-05:28,81) — a benign non-JSON marker breaks orphan parsing.
- **Risk:** HIGH until credential flow is fixed.

### 00-04-PLAN.md — Safety core (THE GATE)
- **Strengths:** corrects the `-ceq`/`-cne` typed-count bug (RESEARCH:463-464 → 00-04:142); strong adversarial policy tests (spoof DN, RID-500 rename, nested protected, gMSA, preview==execute; RESEARCH:683).
- **HIGH:** `Resolve-AdmanTarget` uses `Get-ADObject -Identity $id ... -SearchBase <ou>` (00-04:108) and the protected check uses `Get-ADObject -Identity $Object.DistinguishedName -LDAPFilter "(|$or)"` (00-04:109), copied from RESEARCH:315,362. AD cmdlets separate identity lookup from search/filter parameter sets — implemented literally, the resolver/protected check fail before enforcing safety.
- **HIGH:** gate order puts `Confirm-AdmanAction` before `Write-AdmanAudit PENDING` (00-04:167,195), while the architecture diagram + pattern text put PENDING before confirmation (RESEARCH:180,233). SAFE-03 requires every dry-run audited, and `ShouldProcess` handles `-WhatIf`, so this needs an explicit `-WhatIf` path or it may throw/cancel before writing PENDING.
- **MEDIUM:** gMSA "pre-filter first and IN_CHAIN still runs afterward" (00-04:96) contradicts the action returning `Allowed=$false` immediately on gMSA (00-04:109) — loses the layering RESEARCH:547,549 says matters.
- **Risk:** HIGH.

### 00-05-PLAN.md — Fail-closed audit + exit gate
- **Strengths:** write-ahead fail-closed audit per D-03 (CONTEXT:37-38; 00-05:28,99); OUTCOME-failure escalates, never fakes rollback (CONTEXT:40; 00-05:84,110).
- **MEDIUM:** tests mock `[System.IO.File]::Open`/FileStream/`[System.Threading.Mutex]` directly (00-05:85,103); Pester mocks functions/cmdlets naturally, but static .NET calls need wrapper seams or the fail-closed tests are brittle.
- **LOW:** audit `what` is only `$Verb` (00-05:99) while D-03 says `what(verb+function)` (CONTEXT:42); function name is useful for investigations.
- **Risk:** LOW–MEDIUM.

### Overall (Codex)
**MEDIUM-HIGH.** Strong architecture and safety intent; main blockers are concentrated in credential prompting when remember-me is disabled, the 00-04 AD resolver/protected-query mechanics, and `-WhatIf` audit semantics. Fix those before implementation or the phase could pass many static tests while missing the "safe path always holds" property.

---

## Codex-Finding Adjudication (independent source-tracing of each Codex claim)

Codex is a strong reviewer but not infallible; each of its findings was traced against the repo and against PowerShell semantics. Verdicts: **VALID** = confirmed defect, not incorporated in the current PLAN; **PARTIAL** = real but narrower than stated; **MISREAD** = Codex's inference does not hold on tracing.

| # | Codex finding | Verdict | Evidence / reasoning |
|---|---------------|---------|----------------------|
| 01-M1 | `ModuleVersion='1.14.457'` is a floor, not a pin | **VALID — actionable** | 00-01:128 literally uses `ModuleVersion` inside `RequiredModules`. In a PS module-spec hashtable `ModuleVersion` = **minimum** version; exact pin requires `RequiredVersion` (and/or `MaximumVersion`). Plan says "pinned 1.14.457" (00-01:35,131) but ships a floor. Not incorporated. |
| 01-M2 | positive-control `Set-ADUser` fixture vs `Invoke-ScriptAnalyzer -Path . -Recurse` | **PARTIAL — actionable (clarity)** | Custom rule scopes to `Public` paths (00-01:164) and fixtures live under `tests/Fixtures/` (00-01:167), so a `-Recurse` lint would NOT flag them — lint stays green. BUT the prose also calls it a "Public fixture" (00-01:152,176) and there is NO explicit fixture exclusion in `PSScriptAnalyzerSettings.psd1` (00-01:163). Net: ambiguous placement + no exclusion → executor-facing risk. Clarify fixture location and/or add an exclusion. |
| 02-M1 | no-secret regex bans `token`, schema has `DenyList[].token` | **VALID — actionable** | 00-02:83 regex `/pass(word)?\|secret\|key\|token\|credential/i` bans `token`; 00-02:97 defines `DenyList{ token:string }`. The automated acceptance (00-02:113) is already narrow (`password\|secret\|credential\|apiKey\|privateKey`, no `token`), so the fix is to align 00-02:83 with :113. |
| 02-M2 | PSFramework `-Path` vs plain-JSON/schema division under-specified | **MISREAD/overstated — not actionable** | 00-02:146 DOES specify the division: `Import-PSFConfig -Path` primary (D-01), `Get-Content\|ConvertFrom-Json` 5.1 fallback (Pitfall 8), JSON file is source of truth, schema validates. This is intentional 5.1/7 parity, not a gap. No PLAN change needed. |
| 03-H1 | `Get-AdmanCredential` returns `$null` when remember-me off → `RightsInsufficient` prompt unreachable | **VALID — HIGH** | 00-03:106 `if (-not allowRememberMe) return $null` short-circuits BEFORE 00-03:109 (`if ($script:RightsInsufficient) { Get-Credential … }`). With remember-me default-false (D-06), a rights-insufficient session gets `$null` and is never prompted → CONF-06/PROJECT "prompt when rights insufficient" broken. (Also: `$script:RightsInsufficient` is produced by `Test-AdmanCapability`, which runs AFTER `Get-AdmanCredential` in 00-03:151 — so the value is unset at prompt time regardless.) Not incorporated. |
| 03-M2 | `Test-AdmanAuditWritable` "benign marker" into JSONL | **VALID (low) — actionable** | 00-03:149 "write+flush a zero-length or a benign marker" into `audit-<date>.jsonl`. 00-05 schema is strict JSONL (00-05:31,81,99) and the orphan sweep parses each line as JSON. A non-JSON marker line breaks parsing. A zero-length write is safe; the plan should commit to open+`Flush($true)`+dispose with NO non-schema bytes (or a valid JSONL probe record via `Write-AdmanAudit`). |
| 04-H1 | `Get-ADObject -Identity … -LDAPFilter …` invalid parameter-set mix | **VALID — HIGH** (scoped to the protected check) | 00-04:109 / RESEARCH:362-363: `Get-ADObject -Identity $Object.DistinguishedName -LDAPFilter "(|$or)"`. `-Identity` (Identity set) and `-LDAPFilter` (LDAPFilter set) are mutually exclusive parameter sets → "Parameter set cannot be resolved." The SAFE-06 check would fail to bind. Correct form: bind via `-LDAPFilter` only, including the target, e.g. `-LDAPFilter "(&(distinguishedName=$($Object.DistinguishedName))(\|$or))"` (drop `-Identity`). NOTE: Codex also flagged 00-04:108 `Resolve-AdmanTarget … -Identity $id -SearchBase <ou>` — that one is **fine** (`-SearchBase` is valid in the Identity set); the real defect is the `-Identity`+`-LDAPFilter` combo in the protected check. Not incorporated. |
| 04-H2 | Confirm-before-PENDING skips audit under `-WhatIf` | **MISREAD — not a HIGH** | Under `-WhatIf`, `$PSCmdlet.ShouldProcess` returns `$true` (WhatIf is affirmative, not a decline), so `Confirm-AdmanAction` does NOT throw and the gate proceeds to write PENDING + the (what-if) write + OUTCOME. The plan explicitly tests this (00-04:171 Test 5: "with -WhatIf … writes PENDING+OUTCOME audit with whatIf=$true"). The Confirm-first order is arguably BETTER (a declined confirmation leaves no orphan PENDING for the 00-05 sweep to tolerate). Residual = documentation inconsistency only: RESEARCH:180 architecture diagram and :233 Pattern-1 prose both say PENDING-before-ShouldProcess, contradicting the PLAN's Confirm-first order → LOW doc-hygiene (see Open observations), not an execution defect. |
| 04-M3 | gMSA pre-filter returns early vs "IN_CHAIN still runs" | **VALID — actionable** | 00-04:96 (Test 5) asserts "the IN_CHAIN query still runs afterward for layering," but 00-04:109 step (a) returns `Allowed=$false` immediately on gMSA and never reaches step (d) IN_CHAIN. Internal contradiction; RESEARCH:547/549 wants layering (precise reason). Either run IN_CHAIN after the gMSA hit (collect layered reasons) or correct Test 5. |
| 05-M1 | mocking static .NET (`[System.IO.File]::Open`/FileStream/Mutex) directly | **VALID — actionable** | 00-05:83,85,86,103 mock .NET static methods/constructors directly. Pester `Mock` targets PowerShell functions/cmdlets, not .NET statics; fail-closed/flush/mutex assertions need small private wrapper seams (e.g. `New-AdmanAuditMutex`, `Open-AdmanAuditStream`, `Write-AdmanEventLog`) that the tests mock. Not incorporated. |
| 05-L1 | audit `what` = `$Verb` only (D-03 wants verb+function) | **LOW — not counted** | 00-05:31 fixes the schema with `what`; 00-05:99 writes `what=$Verb`. D-03 (CONTEXT:42) says `what(verb+function)`. Minor enrichment against a deliberately fixed schema; recorded, not counted as actionable. |

---

## Source-Grounding Verification (independent pass)

Effective authority (deterministic): `node gsd-tools drift-guard authority --raw` → **`grep`**. Severity seam (`drift-guard severity --status <v> --authority grep`):

| verdict | severity | hardBlock |
|---------|----------|-----------|
| VERIFIED | none | false |
| MISSING | needs-acknowledgement | false |
| AMBIGUOUS | MEDIUM | false |
| UNCHECKABLE | INFO | false |

Under `grep` authority nothing hard-blocks; all plan-cited symbols resolve as forward references (greenfield) or verified design-artifact anchors. (The HIGHs above are *functional* plan defects found by Codex + tracing — they are not MISSING-symbol hardBlocks and are independent of this symbol-resolution table.)

This is a **greenfield** phase: `Glob **/*.{ps1,psm1,psd1}` over the repo = **0 files** — every function/file/config the plans reference is a *forward reference* the plans will CREATE (UNCHECKABLE/new, not MISSING). Behavior is cross-checked against the reference bodies in `00-PATTERNS.md` / `00-RESEARCH.md` that the plans lift.

### VERIFIED (file:line against repo artifacts)

- **`.store/` gitignored (CONF-05)** — `.gitignore:2` lists `.store/`. ✓
- **The one latent code bug is real AND already fixed in the plan.** `00-RESEARCH.md:464` and `00-PATTERNS.md:252` carry `if ($token -ceq "$count") { throw … }` — which INVERTS SAFE-02 (refuses the correct count, accepts a wrong one). PLAN `00-04-PLAN.md:144` (action) and `:150-151` (acceptance) prescribe/verify `-cne` ("refuse on mismatch; the inverted `-ceq` throw form is NOT present"). → **RESOLVED at code level by the plan.** ✓ (Residual doc-hygiene: the source snippets themselves are unamended — Open observations.)
- **Recursive protected-membership OID correct** — `1.2.840.113556.1.4.1941` (`LDAP_MATCHING_RULE_IN_CHAIN`) bound to the *target* with ORed group DNs: `00-RESEARCH.md:361,369,589`, `00-PATTERNS.md:149`. ✓ (BUT see 04-H1: the same query is reached via an invalid `-Identity`+`-LDAPFilter` param-set mix — the OID is right, the invocation shape is wrong.)
- **gMSA/sMSA pre-filter-first** — `msDS-GroupManagedServiceAccount` + legacy `msDS-ManagedServiceAccount` checked first: `00-RESEARCH.md:352-353`, `00-PATTERNS.md:140-141`. ✓
- **Fail-closed audit primitives present** — mutex `Global\adman-audit` (`00-RESEARCH.md:378`, `00-05-PLAN.md:96`), `Flush($true)` (`00-RESEARCH.md:399`, `00-05:100`), `AUDIT FAIL-CLOSED` throw inside the PENDING branch (`00-RESEARCH.md:402-404`, `00-05:101`), OUTCOME escalation without AD rollback (`00-RESEARCH.md:406-410`, `00-05:101`); mirrors `00-PATTERNS.md:197-231`. ✓
- **DPAPI restore-failure path** — empty-password guard `GetNetworkCredential().Password` (`00-RESEARCH.md:430,611`, `00-03:108,117`), `Remove-Item` on catch (`00-RESEARCH.md:434,612`, `00-03:108,118`), `Export-Clixml` with NO `-EncryptionKey` (`00-RESEARCH.md:441`, `00-03:116`). ✓ (The restore *path* is correct; the *gating* of when to prompt is the 03-H1 defect.)
- **SAFE-09 allow-list / banned-list** — 9-verb `ValidateSet` excludes the hard-delete verb (`00-RESEARCH.md:251-253`; `00-04:107`); banned list includes the hard-delete verb (`00-RESEARCH.md:281-286`, `00-01:164`). ✓
- **Capability fail-closed throws** — `'FAIL-CLOSED: managed-OU is empty.'` / `'FAIL-CLOSED: audit path not writable.'` (`00-RESEARCH.md:504-505`, `00-03:150,156`). ✓
- **Forest-root SID for 518/519** — Schema Admins (518)/Enterprise Admins (519) resolved against forest-root SID, Assumption A3 (`00-RESEARCH.md:333,336-337,637`; `00-PATTERNS.md:171,173,185`; `00-03:148`). ✓

### AMBIGUOUS / inconsistent (in source artifacts; the plans resolve correctly)

- **Gate-ordering diagram/prose vs the PLAN.** `00-RESEARCH.md:180` (architecture diagram step 4→5) and `00-RESEARCH.md:233` (Pattern-1 prose: `…→ audit-PENDING → ShouldProcess → execute …`) both place audit-PENDING **before** confirmation, while the PLAN (`00-04-PLAN.md:167,190-195`) places `Confirm-AdmanAction` **before** the PENDING write. As adjudicated (04-H2), the PLAN's order is correct-and-tested (dry-runs still audited; no orphan PENDING on decline); the diagram/prose are the stale ones. **Severity: LOW (doc-hygiene in RESEARCH, not a plan defect).**

### MISSING

- None. No cited artifact that should already exist is absent.

### UNCHECKABLE / new (forward references — verified absent by Glob; expected for a foundation phase) → INFO, hardBlock false

- **Functions the plans create (all NEW):** `Invoke-AdmanMutation`, `Resolve-AdmanTarget`, `Test-AdmanTargetAllowed`, `Confirm-AdmanAction`, `Assert-AdmanBulkPolicy`, `Get-AdmanAllowedWriteVerbs`, `Write-AdmanAudit`, `Find-AdmanAuditOrphans`, `Get-AdmanRecoveryPosture`, `Initialize-AdmanConfig`/`Test-AdmanConfigValid`, `Get/Set/Export/Import-AdmanConfig`, `Get-AdmanCredential`/`Read-AdmanRememberMeConsent`, `Resolve-AdmanDomainSid`, `Test-AdmanAuditWritable`, `Get-AdmanProtectedIdentity`, `Test-AdmanCapability`, `Initialize-Adman`/`Start-Adman`, `Get-AdmanBannedWriteVerbs`, and the nine `Adman.AD.Write.*` wrappers. Verified absent (Glob = 0). Grounded indirectly via the VERIFIED reference bodies above.
- **File paths the plans create (all NEW):** `adman.psd1`, `adman.psm1`, `Public/**`, `Private/Safety/**`, `Private/Audit/**`, `Private/Foundation/**`, `Private/Config/**`, `Private/AD/**`, `config/adman.{schema,defaults,example}.json`, `rules/AdmanSafetyRules.psm1`, `PSScriptAnalyzerSettings.psd1`, `tests/**`. Verified absent.
- **Config keys (defined; no live config yet):** `ManagedOUs`, `DenyList[].token/note`, `safety.bulkConfirmThreshold`, `bulk.maxCount`, `AuditDir`, `ReportDir`, `transport.order/timeouts`, `credentialPolicy.allowRememberMe`, `AdmanProtectedGroup`, `DC`, `delegatedAdminGroup`. `.store/config.json` does not yet exist (`.store/` empty + gitignored).
- **External surfaces (not re-verifiable from repo; well-established):** AD cmdlet set, CIM (`New-CimSession -Protocol Dcom`), `Export-/Import-Clixml` DPAPI semantics, **PSFramework 1.14.457** parameter names (Assumption A1 → build-time `Get-Command` re-verification in PLAN 00-01 Task 1 before pinning — correct treatment), and the **`Get-ADObject` parameter-set exclusivity** that underlies 04-H1 (a PowerShell fact, not a repo symbol).

### Open observations (non-blocking)

- **LOW — stale source snippet (re-introduction risk, not execution-affecting).** `00-RESEARCH.md:464` + `00-PATTERNS.md:252` still carry the inverted `-ceq` snippet. PLAN 00-04 implements `-cne`, so Phase-0 execution is safe; risk is a later phase re-copying from RESEARCH/PATTERNS. Lives in reference artifacts (not the executable PLANs); not counted as actionable this cycle — recommend a one-line docs correction (or formal deferral) outside the PLAN set.
- **LOW — gate-order diagram/prose contradict the PLAN.** `00-RESEARCH.md:180,233` say PENDING-before-confirm; the PLAN (correctly) does confirm-before-PENDING (04-H2). Reconcile the diagram/prose to match the PLAN. Doc-hygiene; not counted as actionable.
- **LOW — unrelated config hygiene.** `gsd-tools` warns `.planning/config.json` contains unknown keys `tavily_search, ref_search, perplexity, jina` (research-tool keys). Not part of the Phase-0 plan set; informational only.

---

## Verification coverage

- **Symbols checked:** all plan-cited functions, AD/CIM cmdlets, the IN_CHAIN OID, gMSA objectClasses, the audit mutex/flush/throw/escalation primitives, the DPAPI restore path, the 9-verb allow-list and banned list, the capability fail-closed throws, the SID/RID resolution, the `.store/` gitignore, PLUS (this cycle) the PowerShell-semantics claims Codex made: `RequiredModules ModuleVersion` vs `RequiredVersion`, `Get-ADObject` parameter-set exclusivity (`-Identity` vs `-LDAPFilter`), and `ShouldProcess` behavior under `-WhatIf`.
- **UNCHECKABLE / skipped (forward references, by design → INFO):** every PowerShell function, file path, and config key the five plans will CREATE (enumerated above) — verified absent via `Glob **/*.{ps1,psm1,psd1}` = 0; treated as new, not missing-implementation defects.
- **drift-guard hardBlocks:** none (authority `grep`; all verdicts hardBlock=false). No symbol-level cycle stop.
- **Adjudicated and downgraded:** Codex 04-H2 (`-WhatIf` audit) — traced to a ShouldProcess-semantics misread + an explicit plan test (00-04:171); downgraded from HIGH to a LOW doc-hygiene residual. Codex 02-M2 (PSFramework/JSON division) — found already-specified (00-02:146); not actionable.

---

## Consensus Summary

This cycle has ONE reviewer (Codex) that succeeded, plus an independent source-grounding/adjudication pass. "Consensus" below = where Codex's finding and the source-trace AGREE; "Divergent" = where source-tracing corrected Codex.

### Agreed Strengths (Codex + source-trace concur)
- The safety invariants (SAFE-01..10) map to concrete, traceable mechanisms with real `file:line` evidence (component-boundary DN scope, RID deny-match, single IN_CHAIN query, write-ahead audit, scaled confirmation, DPAPI re-prompt) — all VERIFIED.
- The plans are self-correcting on the one real logic bug: PLAN 00-04 detects and fixes the inverted `-ceq` confirmation bug (RESEARCH:464/PATTERNS:252) with an acceptance test that forbids the buggy form.
- Cross-plan `key_links` (allow-list == gate ValidateSet == AD-wrapper set; protected-SID/deny-RID contract 00-02↔00-03↔00-04; audit writer/probe contract 00-03↔00-05) are explicit and testable.
- A1 (PSFramework parameters) correctly deferred to a build-time `Get-Command` re-verification.

### Agreed Concerns (Codex + source-trace concur) — the work items
- **HIGH — Credential prompting gated by remember-me (00-03:106 vs :109).** The early `return $null` when `allowRememberMe` is false makes the `RightsInsufficient` prompt unreachable under the default (remember-me off), breaking CONF-06/PROJECT pass-through-and-prompt. Fix: check `RightsInsufficient` first; use the stored credential only when remember-me+readable; otherwise prompt (save only on remember-me+consent). Also note `RightsInsufficient` is produced by `Test-AdmanCapability`, which runs AFTER `Get-AdmanCredential` (00-03:151).
- **HIGH — `Get-ADObject -Identity … -LDAPFilter …` parameter-set mix in the SAFE-06 protected check (00-04:109; inherited from RESEARCH:362).** `-Identity` and `-LDAPFilter` are mutually exclusive parameter sets → bind failure. Fix: bind via `-LDAPFilter` only, including the target DN/guid/SID in the filter, drop `-Identity`. (00-04:108 `-Identity`+`-SearchBase` is fine — `-SearchBase` is valid in the Identity set.)

### Divergent Views (source-trace corrected Codex — recorded so the count is trusted)
- **Codex 04-H2 (`-WhatIf` audit ordering) → downgraded.** Codex feared dry-runs would not be audited because Confirm precedes PENDING. Tracing shows `$PSCmdlet.ShouldProcess` returns `$true` under `-WhatIf` and the plan explicitly asserts PENDING+OUTCOME are written under `-WhatIf` (00-04:171). Confirm-first also avoids an orphan PENDING on a declined prompt. Residual = LOW doc-hygiene (RESEARCH:180 diagram + :233 prose say PENDING-first), not an execution defect. **Not counted as HIGH.**
- **Codex 02-M2 (PSFramework vs JSON division) → not actionable.** Already specified (00-02:146): PSFramework `-Path` primary, `ConvertFrom-Json` 5.1 fallback, JSON is source of truth.

### Risk Assessment
**MEDIUM-HIGH** for the plan set as written, concentrated in two load-bearing spots: the credential prompt gating (00-03) and the AD parameter-set mix in the protected check (00-04). Both are real, both are unincorporated, and both would let the phase pass static tests while failing the "safe path always holds" property (Codex's framing, confirmed). Six actionable MEDIUM/LOW items (pin semantics, fixture/lint clarity, `token`-regex alignment, gMSA layering, audit-probe marker, .NET-mock seams) should be folded into the PLANs (or explicitly deferred) before execution. Documentation-only LOW residuals (stale `-ceq` snippets; gate-order diagram/prose) do not affect Phase-0 execution and are flagged for a separate cleanup decision.

---

## Appendix — run provenance

- Prompt: `$TMPDIR/gsd-review-prompt-0.md` (275,654 bytes / 2,544 lines ≈ 70K tokens) = PROJECT.md (L1-80) + ROADMAP Phase-0 (L26-44) + REQUIREMENTS.md + 00-CONTEXT.md + 00-RESEARCH.md + the five 00-0x-PLAN.md, with a "verify-against-source" instruction block + a greenfield note.
- Codex invocation: `codex exec --ephemeral --dangerously-bypass-hook-trust --skip-git-repo-check - < prompt > out 2> err` (bypass flag capability-probed: supported on 0.144.1). Exit 0; out=14,191 bytes; err=850 KB (dominated by prompt echo + tool traces).
- Host constraint honored: this git-bash has no node/codex on default PATH and cannot write `/tmp`; every call exported `PATH="/c/Program Files/nodejs:$HOME/AppData/Roaming/npm:$PATH"` and used `TMPDIR=$HOME/AppData/Local/Temp`.
- Prior cycle-1 attempt (commit `2a04e57`): codex failed on auth (401 token_expired/refresh_token_reused), 0 bytes ×2 — superseded by this successful run; retained above as audit history.
