---
phase: 0
reviewers: [codex]
reviewed_at: 2026-07-10T13:24:32Z
plans_reviewed: [00-01-PLAN.md, 00-02-PLAN.md, 00-03-PLAN.md, 00-04-PLAN.md, 00-05-PLAN.md]
reviewer_outcomes:
  codex:
    status: failed
    reason: "OpenAI ChatGPT OAuth access token expired and refresh token rejected (refresh_token_reused); every API call returned HTTP 401. Re-authentication (interactive `codex login` or an API key) is required and could not be performed in this headless run."
    invocations: 2
    empty_output: true
---

# Cross-AI Plan Review — Phase 0 (Foundation & Safety Harness)

**Status: PARTIAL — the only requested reviewer (Codex) failed to produce a review (auth). The source-grounding pass ran independently and is the substantive content below.**

This run invoked `--codex` only. Codex (`codex-cli 0.144.1`) started a session (`model: gpt-5.5`, `sandbox: read-only`, workdir `C:\Users\nhdinh\dev\adman`) but produced **0 bytes** of review output on two attempts. Per the review workflow, the stderr was captured (not silently swallowed) and is recorded below. No review content was fabricated.

---

## Reviewer Status

| Reviewer | Requested | Detected | Outcome |
|----------|-----------|----------|---------|
| codex    | yes (`--codex`) | available (`codex-cli 0.144.1`) | **FAILED — auth (HTTP 401 token_expired / refresh_token_reused)** |

Environment verified before invocation: `codex` (0.144.1), `node` (v25.8.2), and `gsd-tools` were all on PATH; `codex login status` reported "Logged in using ChatGPT" (stale OAuth). A second clean invocation reproduced the identical 401 pattern, so this is a persistent auth failure, not a transient race.

---

## Codex Review

**Codex review failed or returned empty output.** Captured stderr digest (full raw stderr retained at run time; the 287 KB blob is dominated by codex echoing the 278 KB prompt — only the diagnostic lines are reproduced here):

```
OpenAI Codex v0.144.1  |  workdir: C:\Users\nhdinh\dev\adman  |  model: gpt-5.5  |  provider: openai  |  sandbox: read-only

invocation#1 error histogram:  4× token_expired · 3× 401 Unauthorized · 4× responses_websocket failed(401) · 1× refresh_token_reused
invocation#2 error histogram:  5× token_expired · 3× 401 Unauthorized · 4× responses_websocket failed(401) · 1× refresh_token_reused

Final fatal line (both invocations):
  ERROR: Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again.

Representative raw line:
  codex_api::endpoint::responses_websocket: failed to connect to websocket: HTTP error: 401 Unauthorized,
    url: wss://chatgpt.com/backend-api/codex/responses
```

**Root cause:** the ChatGPT-account OAuth access token in `~/.codex/auth.json` is expired, and the stored refresh token has already been consumed by another client/rotation (`refresh_token_reused`), so codex cannot mint a new access token and the Responses websocket 401s before any completion is produced.

**Remediation (operator action required — not automatable headlessly):**
- Re-authenticate interactively: `codex login` (browser/device flow), OR
- API-key path: `printenv OPENAI_API_KEY | codex login --with-api-key` (no `OPENAI_API_KEY` is set in this environment), OR
- `printenv CODEX_ACCESS_TOKEN | codex login --with-access-token`.
- Then re-run: `/gsd-review --phase 0 --codex`.

No Codex model opinion is available for this cycle. The substantive, evidence-backed content of this review therefore comes from the independent source-grounding pass below.

---

## Source-Grounding Verification (independent pass)

Because Codex could not review, each symbol/mechanism the five plans cite was checked against the actual repo. This is a **greenfield** phase: `Glob **/*.{ps1,psm1,psd1}` over the whole repo returns **0 files** — every function/file/config the plans reference is a *forward reference* the plans will CREATE. Those are reported as **UNCHECKABLE/new** (not MISSING), and their behavior is cross-checked against the reference bodies in `00-PATTERNS.md` and `00-RESEARCH.md` that the plans lift.

### VERIFIED (checked against repo artifacts)

- **`.store/` gitignored (CONF-05)** — `.gitignore:2` lists `.store/`. ✓
- **The one latent code bug is real AND already fixed in the plan.** `00-RESEARCH.md:464` and `00-PATTERNS.md:252` both contain `if ($token -ceq "$count") { throw "Confirmation failed … Refused." }` — this **inverts** SAFE-02 (it *refuses* when the operator types the correct count and *accepts* a wrong count). PLAN `00-04-PLAN.md:144` (action) and `:150-151` (acceptance) explicitly flag this and prescribe/verify `-cne` ("refuse on mismatch; the inverted `-ceq` throw form is NOT present"). → The inversion is **RESOLVED at the code level** by the plan. ✓ (Residual doc-hygiene note: the two source snippets themselves are not amended — see "Open observations" below.)
- **Recursive protected-membership OID correct** — `1.2.840.113556.1.4.1941` (`LDAP_MATCHING_RULE_IN_CHAIN`) present and bound to the *target* with ORed group DNs: `00-RESEARCH.md:361,369,589`, `00-PATTERNS.md:149`. ✓
- **gMSA/sMSA pre-filter-first** — `msDS-GroupManagedServiceAccount` and legacy `msDS-ManagedServiceAccount` checked first: `00-RESEARCH.md:352-353`, `00-PATTERNS.md:140-141`. ✓
- **Fail-closed audit primitives present** — mutex `Global\adman-audit` (`00-RESEARCH.md:378`), `Flush($true)` (`:399`), `AUDIT FAIL-CLOSED` throw inside the PENDING branch (`:402-404`), OUTCOME escalation without AD rollback (`:406-410`); mirrors in `00-PATTERNS.md:197-231`. Matches PLAN 00-05. ✓
- **DPAPI restore-failure path** — empty-password guard `GetNetworkCredential().Password` (`00-RESEARCH.md:430,611`), `Remove-Item` on catch (`:434,612`), `Export-Clixml` with **no `-EncryptionKey`** (`:441`); matches PLAN 00-03 (keyed-AES rejected). ✓
- **SAFE-09 allow-list / banned-list** — 9-verb `ValidateSet` excludes `Remove-ADObject` (`00-RESEARCH.md:251-253`); the 14-entry banned list includes `Remove-ADObject` (`:281-286`). ✓
- **Capability fail-closed throws** — `'FAIL-CLOSED: managed-OU is empty.'` / `'FAIL-CLOSED: audit path not writable.'` at `00-RESEARCH.md:504-505`; matches PLAN 00-03. ✓
- **Forest-root SID for 518/519** — Schema Admins (518) / Enterprise Admins (519) resolved against the forest-root SID, documented as Assumption A3 (`00-RESEARCH.md:333,336-337,637`; `00-PATTERNS.md:171,173,185`). ✓

### AMBIGUOUS / inconsistent (in source artifacts; the plans resolve correctly)

- **Gate ordering prose vs. code.** `00-RESEARCH.md:233` *prose* states the pipeline as `… → audit-PENDING → ShouldProcess → execute …` (audit-PENDING **before** confirmation), but the reference *code* (`00-RESEARCH.md:258-272`, `00-PATTERNS.md:86-102`) and **all five plans** place `Confirm-AdmanAction` (ShouldProcess) **before** the PENDING audit write. The plans follow the code (Confirm → PENDING → write), which is the *better* order (a declined confirmation produces no orphan PENDING record). Net: plans are internally consistent and correct; `00-RESEARCH.md:233` prose is a documentation inconsistency, not a plan defect. **Severity: LOW (informational).**

### MISSING

- None. No cited artifact that should already exist is absent. (The phase produces no pre-existing code by design.)

### UNCHECKABLE / new (forward references — verified absent by Glob; expected for a foundation phase)

- **Functions the plans create (all NEW):** `Invoke-AdmanMutation`, `Resolve-AdmanTarget`, `Test-AdmanTargetAllowed`, `Confirm-AdmanAction`, `Assert-AdmanBulkPolicy`, `Get-AdmanAllowedWriteVerbs` (`AdmanWriteVerbs.ps1`), `Write-AdmanAudit`, `Find-AdmanAuditOrphans`, `Get-AdmanRecoveryPosture`, `Initialize-AdmanConfig`/`Test-AdmanConfigValid`, `Get/Set/Export/Import-AdmanConfig`, `Get-AdmanCredential`/`Read-AdmanRememberMeConsent`, `Resolve-AdmanDomainSid`, `Test-AdmanAuditWritable`, `Get-AdmanProtectedIdentity`, `Test-AdmanCapability`, `Initialize-Adman`/`Start-Adman`, `Get-AdmanBannedWriteVerbs`, and the nine `Adman.AD.Write.*` wrappers. Verified **not present** (Glob = 0). Behavior is grounded indirectly via the VERIFIED reference bodies above, which the plans adapt.
- **File paths the plans create (all NEW):** `adman.psd1`, `adman.psm1`, `Public/**`, `Private/Safety/**`, `Private/Audit/**`, `Private/Foundation/**`, `Private/Config/**`, `Private/AD/**`, `config/adman.{schema,defaults,example}.json`, `rules/AdmanSafetyRules.psm1`, `PSScriptAnalyzerSettings.psd1`, `tests/**`. Verified not present.
- **Config keys (defined in CONTEXT/plan; no live config yet):** `ManagedOUs`, `DenyList`, `safety.bulkConfirmThreshold`, `bulk.maxCount`, `AuditDir`, `ReportDir`, `transport.order`/`transport.timeouts`, `credentialPolicy.allowRememberMe`, `AdmanProtectedGroup`, `DC`, `delegatedAdminGroup`. `.store/config.json` does not yet exist (`.store/` is empty + gitignored).
- **External surfaces (not re-verifiable from the repo; well-established):** AD cmdlet set (`Get-ADObject`, `Set-ADUser`, `Disable-ADAccount`, …), CIM (`New-CimSession -Protocol Dcom`), `Export-Clixml`/`Import-Clixml` DPAPI semantics, and **PSFramework 1.14.457 parameter names** — the latter is correctly handled by the plans as **Assumption A1**, with PLAN 00-01 Task 1 doing a *build-time* `Get-Command` re-verification before pinning. This is the right treatment; do not assert the parameter names from this review.

### Open observations (non-blocking; recorded for completeness)

- **LOW — stale source snippet (re-introduction risk, not execution-affecting).** `00-RESEARCH.md:464` and `00-PATTERNS.md:252` still carry the inverted `-ceq` confirmation snippet. PLAN 00-04 correctly implements `-cne`, so Phase-0 execution is safe; the only risk is a *future* phase re-copying the snippet from RESEARCH/PATTERNS. A one-line correction to both snippets (or a small PLAN task) would close it. Not incorporated into any current PLAN and not deferred/rejected there.
- **LOW — unrelated config hygiene.** `gsd-tools` warns that `.planning/config.json` contains unknown keys `tavily_search, ref_search, perplexity, jina` (research-tool keys). Not part of the Phase-0 plan set; informational only.

---

## Verification coverage

- **Symbols checked:** all plan-cited functions, AD/CIM cmdlets, the IN_CHAIN OID, gMSA objectClasses, the audit mutex/flush/throw/escalation primitives, the DPAPI restore path, the 9-verb allow-list and 14-entry banned list, the capability fail-closed throws, the SID/RID resolution, and the `.store/` gitignore.
- **UNCHECKABLE / skipped (forward references, by design):** every PowerShell function, file path, and config key the five plans will CREATE (full enumeration in the "UNCHECKABLE / new" subsection above) — verified absent via `Glob **/*.{ps1,psm1,psd1}` = 0. These were treated as new, not as missing-implementation defects.
- **Skipped by environment (could not review):** Codex's independent model assessment of plan quality, completeness, and risk — unavailable this cycle due to the auth failure above. Re-run `/gsd-review --phase 0 --codex` after re-authentication to obtain it.

---

## Consensus Summary

Only one reviewer was requested (`--codex`) and it failed (auth), so there is **no cross-AI consensus** this cycle. The evidence below is from the independent source-grounding pass against the repo.

### Agreed Strengths (grounded)
- The safety invariants (SAFE-01..10) map to concrete, *traceable* mechanisms with real `file:line` evidence in the design artifacts (component-boundary DN scope, RID deny-match, single IN_CHAIN query, write-ahead audit, scaled confirmation, DPAPI re-prompt) — all VERIFIED above.
- The plans are unusually self-correcting: PLAN 00-04 detects and fixes the inverted `-ceq` confirmation bug present in both source artifacts, with an acceptance test that forbids the buggy form.
- Cross-plan `key_links` (allow-list == gate ValidateSet == AD-wrapper set; protected-SID/deny-RID contract shared 00-02↔00-03↔00-04; audit writer/probe contract 00-03↔00-05) are explicit and testable.
- PSFramework parameter uncertainty (A1) is correctly deferred to a build-time `Get-Command` re-verification rather than asserted.

### Agreed Concerns (grounded)
- **No unresolved HIGH.** The single verified code-level defect (the `-ceq` inversion) is already corrected and test-gated in PLAN 00-04.
- **LOW (informational / doc-hygiene):** `00-RESEARCH.md:233` ordering prose contradicts the code the plans use; `00-RESEARCH.md:464` + `00-PATTERNS.md:252` still carry the stale `-ceq` snippet (re-copy risk for a later phase). Neither affects Phase-0 execution.

### Divergent Views
- n/a — single reviewer, and it failed.

### Risk Assessment
**LOW** for the plan set as written: the plans, if executed, would enforce SAFE-01..10 via mechanisms that trace to verified design artifacts, and the one real logic bug is already corrected in PLAN 00-04. Residual risk is documentation hygiene (stale snippets) and the inability to obtain Codex's independent model review this cycle.

---

## Appendix — re-running the Codex review

After re-authenticating Codex (`codex login`, or `--with-api-key` / `--with-access-token`), re-run:
```
/gsd-review --phase 0 --codex
```
The assembled prompt is reproducible from PROJECT.md (project context), the ROADMAP Phase-0 section, REQUIREMENTS.md, `00-CONTEXT.md`, `00-RESEARCH.md`, and the five `00-0x-PLAN.md` files (≈278 KB / ≈70 K tokens), with a "verify-against-source" instruction block.
