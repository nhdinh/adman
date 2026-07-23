# Phase 0: Foundation & Safety Harness - Context

**Gathered:** 2026-07-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Build and prove the **non-bypassable safety spine** — one internal (non-exported) mutation gate `Invoke-AdmanMutation`, the split config/credential store, the fail-closed audit, and the startup capability probe — **in isolation, before any real AD write exists.** Every future mutation (Phases 2–5) funnels through this one gate with truthful preview, scaled confirmation, scope/deny-list/protected-account enforcement, and fail-closed audit.

This phase delivers the gate and its supporting substrate; it ships **no AD write verbs** (those arrive in Phase 2). Success is measured by the proof artifacts in ROADMAP Phase 0 (Pester + lint guard showing no exported function calls AD write cmdlets directly; end-to-end `-WhatIf` against a test OU; refusals logged for deny-listed / protected / out-of-scope targets).

The safety *principles* are locked (PROJECT.md / REQUIREMENTS.md / ROADMAP.md). The decisions below pin down the **mechanisms and defaults** the researcher and planner need.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Logging & configuration backbone (resolves CLAUDE.md ↔ ROADMAP 00-01 conflict)

- **D-01: Hybrid — PSFramework (pinned) for config + diagnostic logging; audit stays a synchronous, hand-rolled, throw-on-failure writer.**
  - Adopt **PSFramework 1.14.457** (pin the version in the manifest/CI) for validated config (`Set-PSFConfig`/`Register-PSFConfigValidation`) and leveled diagnostic/ops logging (`Write-PSFMessage`).
  - The **audit writer (00-05) is NOT routed through PSFramework.** It remains an in-process, synchronous function that throws on failure so SAFE-04 fail-closed ("refuse the action if the record can't be written") is enforceable. PSFramework's durable logging is asynchronous (background runspace; first-record loss; process-exit-before-drain) — using it for audit would break fail-closed.
  - **Reconcile the two source docs so they agree:** amend ROADMAP 00-01 to "PSFramework config + diagnostic-logging backbone; audit writer stays synchronous/hand-rolled per 00-05"; update CLAUDE.md "Alternatives Considered" to record PSFramework adopted for config/ops-logging in Phase 0 with an explicit audit exception.
  - **Load-bearing caveats:** PS 5.1 `ConvertFrom-Json` has no `-AsHashtable` (read config as `PSCustomObject`, index by property); `ConvertTo-Json` defaults to `-Depth 2` and silently truncates nested config → pass `-Depth` explicitly on every save. Pin the config path with `Export-PSFConfig`/`Import-PSFConfig` — do NOT rely on PSFramework's magic per-user/per-machine default locations, or a stray config could override the portable file (fail-open). Fail-closed semantics ("refuse writes if managed-OU empty or config/deny-list fails to load") are implemented in `Initialize-Adman` regardless of framework. PSFramework becomes the second mandatory module (after RSAT) on every host.

### Area 2 — Safety-core enforcement

- **D-02: Protected-account detection (SAFE-06) = runtime-SID resolution + one `LDAP_MATCHING_RULE_IN_CHAIN` query over (7 protected groups ∪ `adman-Protected`); gMSA blocked by `objectClass` pre-filter; flat deny-list as the hard floor.**
  - Resolve the protected set at startup (never hard-code a domain SID): `DomainSID` from `(Get-ADDomain).DomainSID` + RIDs **512** (Domain Admins), **519** (Enterprise Admins), **518** (Schema Admins); builtin constants **`S-1-5-32-544`** (Administrators), **`-548`** (Account Operators), **`-551`** (Backup Operators), **`-549`** (Server Operators). Add **525** (Protected Users) / **526-527** (Key/Enterprise Key Admins) as defense-in-depth where present.
  - For each target, evaluate ONE DC-side filter: `memberOf:1.2.840.113556.1.4.1941:=<DN>` across the 7 protected groups **and** the admin-maintained `adman-Protected` group. No client-side member-list materialization; immune to orphaned/foreign SIDs.
  - **Service accounts (no reliable SID):** protection = membership in `adman-Protected` (explicit, recursive, AD-audited). A `svc_`-style naming heuristic is **warning-only** (never a sole blocker) to avoid false positives/negatives.
  - **gMSA:** refuse any target whose `objectClass` contains `msDS-GroupManagedServiceAccount` or legacy `msDS-ManagedServiceAccount` (run the objectClass pre-filter first so the refusal reason is precise; gMSAs can also nest in protected groups, so still run the IN_CHAIN check).
  - `adminCount` is explicitly NOT used as the signal: it is stamped while protected but **never cleared on removal** (false positives forever) and a freshly-added admin is not stamped until the next SDProp cycle (≤60 min) (false negatives in-window). Live membership is the only trustworthy test.

- **D-03: Fail-closed audit (SAFE-03/04) = write-ahead reservation.** Audit record must be durably on disk and verified **before** the mutation is sent to AD.
  - Per action: take named mutex `Global\adman-audit` → open daily-rotated `.store/audit/audit-YYYYMMDD.jsonl` (Append/Write/Read-share) → write **PENDING** `{correlationId}` → `Flush(true)` → **on ANY exception, throw before touching AD (this is the refusal)** → perform mutation → append **OUTCOME** (Success/Failure/Refused) best-effort.
  - Failures that trip refusal: path missing (and startup auto-create failed), ACL denial, disk full (`ERROR_DISK_FULL` 112), sharing violation, unreachable configured path.
  - **OUTCOME-write failure** (after a successful mutation): escalate to Windows Event Log + loud UI + session flag; **never fake an AD rollback** (object-state rollback is unreliable and can compound damage). Refusal is gated on the **pre-write only**; outcome gaps are a monitoring/escalation problem, detected by `correlationId` PENDING↔OUTCOME pairing and a startup orphan sweep.
  - Default location local `.store/audit/` (gitignored) for reliability; overridable in non-secret config — but flag that a UNC/collector primary target adds a network-failure mode (halt-all-work vs silent-drop), so keep primary local and forward a copy (Event Log / SIEM) as a **secondary** sink (see deferred).
  - **Schema (no secrets, ever):** `tsUtc, who(user+domain+SID), what(verb+function), scope(managed-OU root), target(DN+SID+objectClass), count, whatIf, result, reason, correlationId, host, psEdition, moduleVersion`.

### Area 3 — First-run setup & scope seed

- **D-04: First-run (CONF-01/02/03) = both an annotated `config.example.json` AND an optional `init`/wizard that emits the SAME JSON, plus `doctor`/`validate`.**
  - One shared JSON schema is used by **both** the writer (wizard) and the loader, so the two entry points can never drift and CONF-03 backup/restore stays portable/diff-friendly.
  - The wizard is a pure **emitter** of flat, machine-independent JSON — never a parallel/GUI blob. Strict JSON has no comments: the "annotated example" is a sibling file/README section (or `_comment` keys the loader strips), **not JSONC/JSON5** (breaks the zero-dep plain-JSON constraint).
  - On true first run the wizard/`init` runs in a **setup mode** that writes `.store/config.json` but performs **no AD mutation**; the fail-closed gate (empty managed-OU, or config/deny-list fails to load) applies only to AD-mutating operations and must NOT block the wizard that creates the config.
  - **Validation timing:** DN *syntax* validated cheaply at input; OU *existence/reachability* best-effort at setup (offer save-and-retry if the domain is unreachable — never fabricate) and re-validated authoritatively at every startup load (the real safety gate).

- **D-05: Starter deny-list (SAFE-05) = minimal SID-based core seed, matched by `objectSid`/RID.**
  - Seed three entries: **krbtgt (RID-502), Guest (RID-501), built-in Administrator (RID-500)**. Match on `objectSid`/RID, **never `sAMAccountName`** (RID-500 is routinely renamed via GPO).
  - Store as portable tokens: RID suffix `500/501/502` resolved against `(Get-ADDomain).DomainSID` at match time; truly domain-independent well-known SIDs (e.g. `S-1-5-32-544`) as literals. No baked-in full domain SIDs (portability).
  - The seed is written **into the JSON file** (visible/editable/diffable), labeled "starter, not exhaustive" — code holds only the default used to populate a fresh file; thereafter the file is the single source of truth.
  - Rationale: an empty deny-list is silently dangerous — CONF-02 fails closed only on empty *managed-OU* or a *failed-to-load* config, so a valid-but-empty deny-list loads fine and writes proceed with no SAFE-05 guard.

### Area 4 — Human-in-the-loop UX

- **D-06: Credential "remember me" (CONF-04/06) = `Export-Clixml` CurrentUser + `credentialPolicy.allowRememberMe` config flag + checkbox on first capture.**
  - Pass-through is the default (use the logged-in admin; check rights before each task and prompt for domain-admin creds only when insufficient). The stored credential is consumed ONLY when pass-through rights are insufficient — "remember me" never short-circuits the per-task rights check.
  - On explicit consent (checkbox at first credential capture, offered only when `credentialPolicy.allowRememberMe` is true), write the credential via `Export-Clixml` (DPAPI CurrentUser) to `.store/`. DPAPI CurrentUser behavior is identical on PS 5.1 and 7.6 on Windows.
  - **Restore failure handling (the re-prompt):** wrap `Import-Clixml` in try/catch for `CryptographicException` ("Key not valid for use in specified state" / "data is invalid") AND guard the empty-password case (bad restore often returns null/empty → `$cred.GetNetworkCredential().Password` throws). On EITHER signal: **delete the bad credential file and fall back to `Get-Credential`.** Never proceed with an empty credential (it would auth-fail against AD and masquerade as a rights problem).
  - **Do NOT use `Export-Clixml -EncryptionKey` (PS7-only)** for anything that must run on 5.1. **Reject a keyed-AES file (A4)** — it reintroduces the mini secret-vault v1 explicitly excludes; portability is "no code changes between workstation and jump host," not credential roaming.
  - **LocalMachine scope (A3)** is offered ONLY as a documented opt-in for a dedicated, ACL-locked admin jump host where several admins share one service profile — flag that any local process/admin can unwrap; never on a general workstation.

- **D-07: Confirmation scaled to blast radius (SAFE-02) = type the exact count, with a configurable threshold (default 5).**
  - **Below threshold:** one `ShouldProcess` y/n that **names the count** ("Disable 3 accounts?"), default-No.
  - **At/above threshold:** demand the **exact count typed** (case-sensitive, no Enter-to-accept). This proves the operator saw the result-set size and defeats y-y-y muscle memory.
  - Threshold lives in the non-secret config as `safety.bulkConfirmThreshold` (default 5). A stricter `>1` rule is allowed ONLY as a per-OU override for high-risk containers.
  - **ShouldProcess interaction:** resolve the target set FIRST, run the gate ONCE, then execute inner destructive cmdlets with `-Confirm:$false` (no per-object re-prompt). `ShouldContinue` ignores `-Confirm:$false`, so the automation escape hatch is a deliberate **`-Force` switch** (plus honoring `-Confirm:$false`), mirroring Azure's `-Confirm:$false -Force` idiom — keeps the junior menu path gated while letting seniors/automation skip the prompt.
  - **Non-bypassable (any flag, menu or direct-call):** the deny-list, protected-account block, managed-OU scope, and the Phase-4 max-count CAP. `-Force`/`-Confirm:$false` skip ONLY the prompt.
  - Log the confirmation (who, verb, count, token-type) to the JSON-lines audit — never the credential.

### Claude's Discretion

- Concrete **managed-OU roots, domain name, report/audit paths, transport order/timeouts, and the exact bulk CAP value** are runtime configuration captured by the first-run wizard / `config.example.json` — not hard-coded constants. The schema + validation are in scope; the values are environment-specific and supplied by the team.
- Internal function/file names under `Public/`/`Private/` and the exact module-manifest fields are planner discretion within the ROADMAP 00-01 scaffold (`adman.psd1/.psm1`, Public/Private loader, explicit `FunctionsToExport`, `$ErrorActionPreference='Stop'`, `-Server`-pinning helper).
- Whether to add Protected Users (525) / Key Admins (526-527) to the default protected set is planner discretion (recommended where present).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value (safety property must hold), Active requirements, Out-of-scope, Constraints (config/credential split; gitignored `.store/`; pass-through default; RSAT prereq not bundled), and Key Decisions (config/credential split ✓; no hard-coded RID baseline ✓).
- `.planning/REQUIREMENTS.md` — 58 v1 requirements. **Phase 0 owns 17:** `MENU-05`, `CONF-01`–`CONF-06`, `SAFE-01`–`SAFE-10`. Traceability table is authoritative.
- `.planning/ROADMAP.md` — Phase 0 goal, the 5 success criteria, and the suggested 5-plan split (`00-01` scaffold, `00-02` config + capability probe, `00-03` credential decision, `00-04` safety core/gate, `00-05` fail-closed audit + lint guard). **Amend 00-01 wording per D-01.**

### Research artifacts (the de-facto design basis — greenfield, no code yet)
- `.planning/research/SUMMARY.md` — the 6-phase blast-radius-ordered skeleton the roadmap adopted.
- `.planning/research/STACK.md` — PowerShell 5.1/7.6 strategy; AD module (RSAT) as prereq; CIM-not-WMI; Pester 6; PSScriptAnalyzer 1.25.0; PlatyPS 1.0.2; PSResourceGet.
- `.planning/research/ARCHITECTURE.md` — module/gate architecture, Public/Private loader, export model.
- `.planning/research/PITFALLS.md` — AD/PowerShell gotchas that inform this phase: **`adminCount` staleness** (why D-02 rejects it), **RID-500 rename** (why D-05 matches by SID), **gMSA objectClass detection**, **`LDAP_MATCHING_RULE_IN_CHAIN`**, **DPAPI/`Export-Clixml` behavior**, and **Pitfall 12 which already sketches a synchronous hand-rolled `Write-Audit`** (supports the D-01 audit exception).
- `.planning/research/FEATURES.md` — feature breakdown cross-check.

### State & open research flags
- `.planning/STATE.md` §Blockers — **Phase 0 HIGH research flags:** verify exact PSFramework 1.14.457 config/logging cmdlet signatures (resolved in D-01: config+diagnostics only, audit stays synchronous); DPAPI/`Export-Clixml` 5.1↔7.6 behavior (resolved in D-06: consistent across editions; failure modes = wrong user/machine, profile/SID change, non-interactive); precise well-known-SID set for this environment (resolved in D-02); RSAT server feature name vs target SKUs (still open — confirm in Phase 0/5 research).

### Project rules & guardrails
- `.claude/CLAUDE.md` — tech-stack rules and the **"What NOT to Use"** list (no `Get-WmiObject`/`wmic.exe`; no `Set-AD*` without `-WhatIf`/functions without `SupportsShouldProcess`; no plaintext/vault creds; no ps2exe), the PSScriptAnalyzer rule set (`PSUseShouldProcessForStateChangingFunctions`, `PSAvoidUsingPlainTextForPassword`, `PSUsePSCredentialType`, etc.), DPAPI/JSON-lines/signing guidance. **Reconcile "Alternatives Considered" re PSFramework per D-01.**

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — portable plain-JSON **non-secret** config (managed-OU roots, deny-list, bulk cap, audit/report paths, transport order/timeouts, `safety.bulkConfirmThreshold`, `credentialPolicy.allowRememberMe`).
- `.store/config.example.json` — shipped annotated example (D-04).
- `.store/audit/audit-YYYYMMDD.jsonl` — fail-closed append-only audit (D-03).
- `.store/<credential>.xml` — DPAPI `Export-Clixml` credential file, written only on explicit "remember me" (D-06).

</canonical_refs>

<code_context>
## Existing Code Insights

This is a **greenfield** project — no `.ps1`/`.psm1`/`.psd1` exists yet. The "codebase" at this point is the research corpus under `.planning/research/` and the rules in `.claude/CLAUDE.md`, which together define the target shape.

### Reusable Assets
- **Research corpus (`.planning/research/`)** — acts as the design spec the planner implements against; `PITFALLS.md` in particular pre-solves several Phase-0 traps (adminCount, RID-500 rename, gMSA objectClass, IN_CHAIN, DPAPI, synchronous audit sketch).
- **`.store/` directory** — already present and gitignored; the runtime home for config, audit, and credential files (D-03/D-04/D-06).

### Established Patterns (to create, not yet present)
- **Single non-exported gate `Invoke-AdmanMutation`** (SAFE-08) — every destructive function routes through it; a Pester + PSScriptAnalyzer guard proves no exported function calls AD write cmdlets directly. The lint rule `PSUseShouldProcessForStateChangingFunctions` enforces `SupportsShouldProcess`/`ConfirmImpact='High'`.
- **Identical preview/execute resolution** (SAFE-10) — preview and execute call the same target-resolution function so `-WhatIf` cannot lie.
- **Public/Private module layout** with explicit `FunctionsToExport` (ROADMAP 00-01) — the gate is `Private/` and NOT exported.
- **Audit-before-act write-ahead reservation** (D-03) — the only ordering that is actually fail-closed.

### Integration Points
- `Initialize-Adman` (called by `Start-Adman`) — loads/validates config, runs the startup capability probe (`Test-AdmanCapability` → MENU-05), resolves the protected-SID set and deny-list into the session, verifies the audit dir, and sets fail-closed session flags. Phase 1's `Start-Adman` consumes this.
- Phase 1 (read-only reporting) consumes the config + capability probe + read wrappers; Phase 2 (single-object writes) is the first consumer of the gate; Phases 3–5 compose on top. The gate contract defined here is the integration point for every later mutation.

</code_context>

<specifics>
## Specific Ideas

- **Resolve the conflict by editing both source docs** (D-01) — do not leave ROADMAP 00-01 ("PSFramework backbone") and CLAUDE.md ("defer PSFramework") disagreeing; the planner should not have to guess which wins.
- **Honor the mixed-skill split everywhere:** a guided safe path for juniors (wizard + menu + gated prompts) AND a fast path for seniors (parameterized functions + `-Force`/`-Confirm:$false` automation bypass) — "one code path, two speeds" (MENU-04) starts with how the gate and confirmation are built (D-07).
- **Make the safe path the easy path:** seed the deny-list (D-05), fail closed on empty managed-OU (D-04), type-the-count for bulk (D-07), and never let any flag bypass deny-list/protected/scope/cap (D-07).
- **Match by SID/RID, never by name** (D-02/D-05) — the recurring theme (RID-500 rename, localized group names, forest-vs-domain scope) is that names lie and SIDs don't.

</specifics>

<deferred>
## Deferred Ideas

Items surfaced during discussion that belong to a later phase or are explicitly out of v1 scope — preserved, not acted on here.

- **Expanded Tier-0 / AdminSDHolder deny-list seed** (DA 512 / EA 519 / Schema 518 / Protected Users 525 + `adminCount` guard) — a clearly-delimited **second layer** to add once group/lifecycle operations near Tier-0 exist (Phase 2+). Documented as defense-in-depth behind OU scoping, rights checks, and ShouldProcess — never an exhaustive boundary.
- **`tokenGroups`-based effective-membership report (A2)** — only if a read-only "effective access" report is later wanted (Phase 1/5); not the SAFE-06 enforcement primitive (D-02 uses IN_CHAIN).
- **LocalMachine DPAPI credential scope (A3)** — available as a documented opt-in for a dedicated ACL-locked jump host; not the default (D-06).
- **Event Log / SIEM forwarding as a primary audit sink (B4)** — keep audit **local** for fail-closed reliability (D-03); forwarding/rotation/tamper-evidence is **Phase 5 hardening** (ROADMAP 05-03).
- **Keyed-AES portable credential file (A4)** — rejected for v1 (reintroduces a secret vault; `Export-Clixml -EncryptionKey` is PS7-only). Revisit only if credential roaming becomes an explicit v2 requirement.
- **Write-after "refuse on failure" audit (B3)** — never for destructive actions; acceptable only for pure reads/dry-runs (already covered because dry-runs append but do not mutate).
- **Bulk-starts-at-`>1` confirmation (B4)** — rejected as the global default; allowed only as a per-OU override for high-risk containers (D-07).
- **Bulk max-count CAP value, transport order/timeouts, managed-OU roots, domain name, report/audit paths** — runtime configuration captured by the first-run wizard / `config.example.json`; the **schema** is Phase 0, the **values** are environment-specific (CAP enforcement itself is Phase 4 / BULK-02).
- **RSAT server feature-name vs target-SKU nuance** — confirm during Phase 0/5 research (STATE.md HIGH flag); affects the prerequisite installer, not the gate design.

</deferred>

---

*Phase: 0-Foundation & Safety Harness*
*Context gathered: 2026-07-10*
