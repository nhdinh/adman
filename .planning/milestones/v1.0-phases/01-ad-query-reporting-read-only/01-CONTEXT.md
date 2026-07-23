# Phase 1: AD Query & Reporting (read-only) - Context

**Gathered:** 2026-07-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 ships the **read-only half** of the tool: the `Start-Adman` menu becomes real, admins can search/view users and computers scoped to the managed OU, and they can run correct read-only reports (console / CSV / self-contained HTML) that prove the team reads AD semantics (timestamps, four account states, recovery posture) **before** any write consumes them (Phase 2). **No AD writes are shipped in this phase** — every verb is a query or a render. Success is measured by the ROADMAP Phase 1 criteria: MENU-01..04 live in the TUI, USER-01/COMP-01 scoped reads work, RPT-01..07 reports render correctly.

The safety *principles* and the Phase 0 spine (gate, config, audit, deny-list, protected-account resolution, capability probe) are locked and reused here unchanged. The decisions below pin down the **read-side API surface, the canonical result-object schema, the output layer, and the stale/inactive report semantics** the researcher and planner need.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Menu navigation model

- **D-01: `Start-Adman` uses a single flat `while` loop with numbered `Read-Host` input.** No nested submenus, no stack, no state machine, no `$Host.UI.PromptForChoice`. Every action is one keystroke from the top-level list.
  - **Why the user chose flat over hierarchical/hybrid:** simplest to ship in Phase 1, easiest to Pester-test, identical behavior on PS 5.1 and 7.6, no nested state to debug. The user explicitly accepted that the list will grow (~12+ items in Phase 1 alone, more in Phase 2/3) and that the menu shape may need to be redesigned in Phase 2 when nested write/confirm flows arrive — that is a Phase 2 concern, not a Phase 1 one.
  - **MENU-03 (navigate back/quit from any prompt) under a flat menu:** `Q` at the top-level menu exits `Start-Adman`. Inside an action's input prompts (e.g., "Enter sAMAccountName"), typing `B` returns to the top-level menu and `Q` exits the tool entirely. These are the ONLY reserved single-letter inputs; everything else is numeric. Planner must document this convention in the menu-render code.
  - **MENU-04 (one code path, two speeds):** each numbered menu action routes to the same parameterized function a senior calls directly (e.g., menu item "Find user" calls `Find-AdmanUser` with parameters prompted interactively; senior runs `Find-AdmanUser -SamAccountName jdoe` directly). The menu NEVER contains read/write logic — it is a thin prompt-and-dispatch layer only.
  - **Reserved input contract:** the menu reads one line at a time via `Read-Host`, validates it against the current menu item count plus `Q`, and re-prompts on anything else. No hotkey accelerators in v1 (deferred to a later phase once the menu shape stabilizes).

### Area 2 — Read wrapper shape + result-object schema

- **D-02: Two typed Public verbs — `Find-AdmanUser` and `Find-AdmanComputer`** — each wraps `Get-ADUser`/`Get-ADComputer -Filter` (NOT `-Identity`) and emits a normalized `[pscustomobject]` result. Mirrors the Phase 0 one-wrapper-per-verb discipline in `Private/AD/Adman.AD.Write.ps1`.
  - **Per-type search attributes:** `Find-AdmanUser` accepts `-Name`, `-SamAccountName`, `-DisplayName` (any one, at least one required). `Find-AdmanComputer` accepts `-Name`. No `-Type` switch; no generic `Find-AdmanObject` in v1.
  - **Per-type exact `-Properties` (ROADMAP success criterion 2):** each verb hard-codes its own property list. Suggested starting sets (planner may extend but MUST NOT shrink below these):
    - `Find-AdmanUser`: `Name, SamAccountName, DisplayName, Enabled, DistinguishedName, ObjectSid, ObjectGuid, UserPrincipalName, LastLogonDate, PasswordLastSet, PasswordExpired, LockedOut, AccountExpirationDate, whenCreated, whenChanged, MemberOf` (Microsoft docs confirm the `Filter`/`LdapFilter` parameter sets accept `-SearchBase`/`-ResultPageSize`/`-Properties`/`-Server`; the `Identity` set does not).
    - `Find-AdmanComputer`: `Name, SamAccountName, Enabled, DistinguishedName, ObjectSid, ObjectGuid, OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack, LastLogonDate, whenCreated, whenChanged, IPv4Address, DNSHostName`.
  - **Scope & paging invariants (enforced structurally, not conventionally):** both verbs MUST loop over every root in `$script:Config.ManagedOUs` and call `Get-ADUser`/`Get-ADComputer -Filter ... -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC`. `-ResultPageSize 1000` per the PITFALLS performance trap (default is 256). `-Server` pinning reuses the Phase 0 `$script:Config.DC` pattern.
  - **SAFE-07 managed-OU scope on reads:** every returned object MUST pass through the existing `Test-AdmanTargetAllowed` step (c) component-boundary scope check before being emitted. Reads are subject to the same scope as writes — the deny-list and protected-account checks are NOT applied to reads (they gate mutations), but the DN-under-managed-OU check IS applied (defense in depth; the `-SearchBase` already enforces it but the post-filter re-check is the structural invariant).
  - **`-Server` pinning:** `-Server $script:Config.DC` on every AD call (Phase 0 pattern, RESEARCH Pitfall 1/6).

- **D-03: Result-object schema = normalized flat `[pscustomobject]` with a fixed superset of columns, produced by a single Private `ConvertTo-AdmanResult` mapper.**
  - **Fixed identity/scope columns (always present, both types):** `ObjectType` (`User` | `Computer`), `Name`, `SamAccountName`, `Enabled`, `DistinguishedName`, `ObjectSid`, `ObjectGuid`.
  - **Nullable type-specific extras:** `DisplayName`, `UserPrincipalName`, `LockedOut`, `PasswordExpired`, `PasswordLastSet`, `AccountExpirationDate` (user-only); `OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`, `IPv4Address`, `DNSHostName` (computer-only); shared: `LastLogonDate`, `whenCreated`, `whenChanged`. Empty cells are acceptable in CSV/HTML.
  - **Timestamp normalization:** all `LastLogonDate`/`whenCreated`/`whenChanged`/`PasswordLastSet`/`AccountExpirationDate` values are emitted as `[datetime]` (UTC where the source is UTC) so renderers can format consistently. Never-logged-on sentinel handling lives in the report layer (see D-06), NOT in the mapper.
  - **Schema contract test:** a Pester contract test pins the emitted property set per type so no renderer can silently read a raw AD property and no future refactor can drift the schema.
  - **Renderers consume ONLY this schema.** They never touch `Microsoft.ActiveDirectory.Management.ADUser`/`ADComputer` types directly.

### Area 3 — Report output layer

- **D-04: Single canonical result-object → three thin renderers.** One `PSCustomObject[]` stream per report; three pure renderers (`Format-AdmanReport` / `Export-AdmanReportCsv` / `Export-AdmanReportHtml`) consume it. Zero new dependencies — uses in-box `Format-Table`/`Out-String`, `Export-Csv -NoTypeInformation`, and `ConvertTo-Html`.
  - **HTML renderer (RPT-03):** static table with embedded CSS injected via `ConvertTo-Html -Head $cssFragment`. **No JavaScript. No `-CssUri`** (which only writes an external `<link>` and breaks self-containment). The CSS fragment lives in a single here-string constant (table typography + zebra striping + optional status colors for Enabled/LockedOut). `-Charset`/`-Meta`/`-Transitional` are PS6+ only and MUST be omitted for 5.1 parity.
  - **CSV renderer (RPT-02):** `Export-Csv -NoTypeInformation -Encoding UTF8`. UTF8 (not ASCII) so DisplayName values with diacritics survive; on PS 5.1 this writes UTF8-with-BOM which Excel opens correctly.
  - **Console renderer (RPT-01):** `Format-Table -AutoSize | Out-String -Width 4096` (the `-Width 4096` is a defensive cap against `Out-String` truncating wide tables on narrow consoles).
  - **Renderer dispatch:** each report verb (e.g., `Get-AdmanStaleAccountReport`, `Get-AdmanRecoveryPosture`) returns the raw `PSCustomObject[]`; the MENU or the caller decides which renderer to invoke. This preserves MENU-04 (senior gets objects; junior gets a rendered view).
  - **Picker (optional sugar, capability-probed):** when `$PSEdition -eq 'Desktop'` AND `Get-Command Out-GridView` resolves AND the session is interactive (not remoted, not headless), offer `Out-GridView -PassThru:$false` as a display option. When `$PSEdition -eq 'Core'` AND `Get-Module -ListAvailable Microsoft.PowerShell.ConsoleGuiTools` finds the module, offer `Out-ConsoleGridView`. **The hand-rolled console table is the primary renderer**; the grid picker is offered only when probed available and MUST degrade to `Format-Table` on any failure (Server Core, remoting, SSH, headless). Wrap the grid call in try/catch.

### Area 4 — Stale/inactive semantics + DC coverage

- **D-05: Single stale/inactive report with two buckets**, per RPT-04. Buckets are:
  - **Stale:** `lastLogonTimestamp` older than `graceThresholdDays` (see D-07), but not never-logged-on.
  - **Never-logged-on:** raw `lastLogonTimestamp` value of `0` (which `Get-ADUser` returns as `1601-01-01 00:00:00 UTC`, the FILETIME epoch). Cross-checked against `whenCreated` so an account created within the grace window is excluded from "never-logged-on" (a 2-day-old account that simply hasn't logged on yet is NOT flagged).
  - **One report, one menu entry, one CSV/HTML output.** The two buckets are distinguished by a `Bucket` column on the result object (`Stale` | `NeverLoggedOn`), not by two separate reports.
  - **Replicated `lastLogonTimestamp` only — never per-DC `lastLogon`.** This matches RPT-04 verbatim. An opt-in per-DC `lastLogon` aggregation is deferred (see Deferred Ideas).

- **D-06: `Search-ADAccount` for the four account-state renderings (RPT-05).** Disabled, Expired, Locked, PasswordExpired are FOUR distinct states, surfaced via `Search-ADAccount -AccountDisabled` / `-AccountExpired` / `-LockedOut` / `-PasswordExpired` — NEVER via `userAccountControl` bit math. Each state gets its own `Bucket` value on the result object. Microsoft docs confirm each state switch is its own parameter set and ALL sets accept `-SearchBase`/`-SearchScope`/`-ResultPageSize`/`-Server`/`-UsersOnly`/`-ComputersOnly`, so managed-OU scoping applies cleanly.

- **D-07: Self-tuning grace buffer = `max(14, msDS-LogonTimeSyncInterval) + 1 day`.**
  - **Preflight read (RPT-07 territory):** at `Initialize-Adman` time, read the logon sync interval and cache it on `$script:Config`. On read failure, fall back to 14 (the AD default). **SUPERSEDED SOURCE TEXT (MEDIUM-2, 2026-07-15):** the original D-07 wording said to read `ms-DS-Logon-Time-Sync-Interval` from the domain NC head via the Configuration partition path (`CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,...`). That path is incorrect — the Configuration-partition Directory Service object holds `tombstoneLifetime`, not the sync interval. The corrected source is `(Get-ADDomain).LastLogonReplicationInterval`, which surfaces the domain NC head attribute directly via the cmdlet. **01-03-PLAN.md is the authoritative source** for the implementation; this D-07 entry is preserved for historical context.
  - **Report header states the actual freshness window:** "this domain's `lastLogonTimestamp` is fresh to within N days (sync interval = X)". This removes the "assume 14 days" smell and catches domains where an admin has tuned the interval.
  - **Why self-tuning (Microsoft-verified semantics):** `lastLogonTimestamp` updates only when `current_time - lastLogonTimestamp > msDS-LogonTimeSyncInterval` (default 14 days), with initial post-DFL-raise randomization of "14 days minus random percentage of 5 days" — that's the source of the commonly-cited 9-14 day window. A hard-coded 14-day grace would produce false "stale" hits on any domain where the interval has been tuned upward.
  - **Epsilon:** +1 day to absorb edge-of-window timing skew. Planner may tune this to +2 if testing reveals boundary false positives; document the choice in code.

- **D-08: Recovery-posture preflight (RPT-07) at startup.** The existing `Private/Foundation/Get-AdmanRecoveryPosture.ps1` (Phase 0) is invoked during `Initialize-Adman` and its result — the three fields the helper actually returns: `RecycleBinEnabled`, `ForestFunctionalLevel`, and `TombstoneLifetime` — is surfaced in the startup capability banner AND cached for the stale report. **AMENDED (Cycle 3, 2026-07-15):** the original D-08 wording listed `ms-DS-Logon-Time-Sync-Interval` as part of recovery posture; that attribute is NOT returned by `Get-AdmanRecoveryPosture` and is instead read separately by `Get-AdmanLogonSyncInterval` (D-07). Recovery posture consistently means the three fields above. RPT-07 is a *report the preflight produces*, not a separate menu item — but a `Get-AdmanRecoveryPostureReport` Public verb is also exposed so a senior can call it directly (MENU-04).

### Claude's Discretion

- **Concrete Public verb names for the four RPT report types** (stale/inactive, account-state, OS/inventory, recovery-posture) — planner picks idiomatic names within `Get-Adman*Report` / `Find-Adman*` conventions. Lock in `FunctionsToExport`.
- **Exact CSS fragment content** (colors, typography, zebra striping) — planner picks a clean, professional default; users can override by editing the here-string.
- **Whether to add a `-Properties` override parameter on the Find verbs** — planner discretion; default is NO (exact `-Properties` is a ROADMAP invariant) but a `-AdditionalProperties` additive-only parameter is acceptable if a concrete use case emerges.
- **Menu item ordering within the flat list** — planner picks a sensible grouping (e.g., search first, then reports, then exit); no hotkeys in v1.
- **Whether `Find-AdmanUser` / `Find-AdmanComputer` support pipeline input** — planner discretion; default is NO for v1 (keep the surface minimal until a real use case emerges).
- **Exact structure of the `Bucket` column values** (e.g., `Stale`/`NeverLoggedOn` vs `Stale`/`NeverLoggedOnRecent`) — planner picks names that read well in CSV/HTML.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value (safety property must hold), Active requirements, Out-of-scope, Constraints (PowerShell 5.1 baseline + 7.6 LTS, RSAT prereq, config/credential split, gitignored `.store/`), Key Decisions table (config/credential split ✓, no hard-coded RID baseline ✓).
- `.planning/REQUIREMENTS.md` — 58 v1 requirements. **Phase 1 owns 13:** `MENU-01`–`MENU-04`, `USER-01`, `COMP-01`, `RPT-01`–`RPT-07`. Traceability table is authoritative.
- `.planning/ROADMAP.md` §Phase 1 — Goal, 4 success criteria, suggested 4-plan split (`01-01` menu shell, `01-02` scoped read layer, `01-03` AD semantics, `01-04` output layer).

### Phase 0 artifacts (the spine this phase composes on)
- `.planning/phases/00-foundation-safety-harness/00-CONTEXT.md` — Phase 0 decisions (D-01 PSFramework for config/ops, D-02 protected-account detection, D-03 fail-closed audit, D-04 first-run wizard, D-05 deny-list seed, D-06 DPAPI credential, D-07 confirmation scaling).
- `.planning/phases/00-foundation-safety-harness/00-PATTERNS.md` — established patterns the planner should mirror.
- `.planning/phases/00-foundation-safety-harness/00-SUMMARY.md` (and per-plan `00-0X-SUMMARY.md`) — what shipped and where.
- `.planning/phases/00-foundation-safety-harness/00-VERIFICATION.md` — what was proven.

### Research corpus (the de-facto design basis)
- `.planning/research/SUMMARY.md` — 6-phase blast-radius-ordered skeleton.
- `.planning/research/STACK.md` — PS 5.1/7.6 strategy, CIM-not-WMI, Pester 6, PSScriptAnalyzer 1.25.0, PlatyPS 1.0.2, PSResourceGet.
- `.planning/research/PITFALLS.md` — AD/PowerShell gotchas directly relevant to Phase 1: `lastLogonTimestamp` replication lag, never-logged-on sentinel, `adminCount` staleness, `ResultPageSize 1000` performance trap, Filter vs LDAPFilter escaping, `ConvertTo-Html -Charset`/`-Meta` PS6+ only, `-CssUri` breaks self-containment.
- `.planning/research/FEATURES.md` — shared-data-layer → three renderers contract.

### Project rules & guardrails
- `.claude/CLAUDE.md` — tech-stack rules and the **"What NOT to Use"** list (no `Get-WmiObject`/`wmic.exe`; no `Set-AD*` without `-WhatIf`/functions without `SupportsShouldProcess`; no plaintext/vault creds; no ps2exe), the PSScriptAnalyzer rule set, the hand-rolled menu guidance (`$Host.UI.PromptForChoice`/`Read-Host`; `Out-ConsoleGridView` optional on PS7 only), RPT-04 (`lastLogonTimestamp` + ≥14-day grace), RPT-05 (`Search-ADAccount`).
- `PSScriptAnalyzerSettings.psd1` — lint gate. `PSUseShouldProcessForStateChangingFunctions` is enforced; new Public verbs that are pure reads do NOT need `SupportsShouldProcess`, but any new state-changing helper does.

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — portable plain-JSON non-secret config; this phase reads `ManagedOUs`, `safety.bulkConfirmThreshold` (for future Phase 4), and the cached `msDSLogonTimeSyncInterval` value.
- `.store/audit/audit-YYYYMMDD.jsonl` — audit log; read-only actions in this phase do NOT need to audit (SAFE-03 audits mutations), but if a read is considered sensitive (e.g., a stale-account report that enumerates disabled users) the planner MAY add a read-audit hook — this is discretionary.

### External Microsoft docs (verified during advisor research)
- `Get-ADUser` / `Get-ADComputer` (ActiveDirectory) — `Filter`/`LdapFilter` parameter sets accept `-SearchBase`/`-ResultPageSize`/`-Properties`/`-Server`; `Identity` set does NOT (only `-Partition`). `ResultPageSize` default is 256.
- `Search-ADAccount` (ActiveDirectory) — each state switch is its own parameter set; ALL sets accept `-SearchBase`/`-SearchScope`/`-ResultPageSize`/`-Server`/`-UsersOnly`/`-ComputersOnly`.
- `ConvertTo-Html` (Microsoft.PowerShell.Utility) — supports `-Head` (embedded CSS via `<style>`), `-Fragment`, `-PreContent`/`-PostContent`, `-Property` (calculated), `-As Table/List`. **No built-in JavaScript/sorting.** `-CssUri` writes an external `<link>` (NOT self-contained). `-Charset`/`-Meta`/`-Transitional` are PS6+ only.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 0 — already in place)

- **`Public/Start-Adman.ps1`** — currently a stub that calls `Initialize-Adman` and returns. **This is the file Phase 1 fills in** with the flat while-loop menu.
- **`Public/Initialize-Adman.ps1`** — loads config, runs `Test-AdmanCapability`, resolves protected SIDs / deny-list, sets fail-closed session flags. Phase 1 adds: preflight read of `ms-DS-Logon-Time-Sync-Interval` (D-07) + surface `Get-AdmanRecoveryPosture` (D-08) in the startup banner.
- **`Public/Test-AdmanCapability.ps1`** — startup probe (RSAT present, domain reachable, current rights, transport availability). Already exported.
- **`Private/Safety/Test-AdmanTargetAllowed.ps1`** — the SAFE-05/06/07 enforcement. Phase 1 reuses step (c) component-boundary scope check on every read (D-02). Do NOT call the full chain on reads (deny-list and protected-account gates are mutation-only), but DO call the scope check.
- **`Private/Safety/Resolve-AdmanTarget.ps1`** — the Phase 0 resolver. Not used by read verbs (they query by Filter, not by Identity), but the `-Server $script:Config.DC` pinning pattern carries over.
- **`Private/Foundation/Get-AdmanRecoveryPosture.ps1`** — already exists (Phase 0). Phase 1 exposes it via a thin Public `Get-AdmanRecoveryPostureReport` wrapper (D-08).
- **`Private/Config/Initialize-AdmanConfig.ps1`** + **`Public/Config/Get-AdmanConfig.ps1`** — config loader. `$script:Config.ManagedOUs` is the read-side source for `-SearchBase` loops.
- **`Private/Audit/Write-AdmanAudit.ps1`** — synchronous fail-closed audit. Phase 1 does NOT audit reads by default (SAFE-03 is about mutations), but the seam exists if a discretionary read-audit is wanted.
- **`rules/AdmanSafetyRules.psm1`** + **`tests/`** — the SAFE-08/09 AST guard + Pester harness. Phase 1 adds: a contract test pinning the `ConvertTo-AdmanResult` schema, integration tests against a lab OU for `Find-AdmanUser`/`Find-AdmanComputer`, and a lint-pass on the new Public verbs.
- **Module loader (`adman.psm1`)** — dot-sources Private then Public, exports per `FunctionsToExport`. Phase 1 appends new Public verbs to `FunctionsToExport` in `adman.psd1` (the export boundary is the SAFE-08 control; the gate `Invoke-AdmanMutation` stays absent).

### Established Patterns (mirror these, don't reinvent)

- **One thin wrapper per concern** (`Adman.AD.Write.ps1` pattern): each Public verb is a thin wrapper that pins `-Server $script:Config.DC`, sets `-ErrorAction Stop`, and delegates. Read verbs follow the same shape.
- **`-Server` pinning:** every AD cmdlet call uses `-Server $script:Config.DC` (RESEARCH Pitfall 1/6).
- **`$ErrorActionPreference = 'Stop'` module-wide** (set in `adman.psm1`): do NOT locally override to `SilentlyContinue` to hide errors; use explicit `try/catch` for expected failure modes (e.g., domain unreachable during preflight).
- **Public/Private boundary:** read verbs and renderers go in `Public/`; the `ConvertTo-AdmanResult` mapper and the menu-dispatch helper go in `Private/`.
- **PSFramework for diagnostic logging:** `Write-PSFMessage -Level Verbose` for ops messages; the audit sink stays the hand-rolled synchronous writer (D-01 of Phase 0).

### Integration Points

- **Menu → verb dispatch:** the flat menu (in `Start-Adman`) reads a menu-item table (label, verb name, prompt spec) and dispatches. The menu-item table is a Private helper so the menu body stays thin.
- **Renderers consume result-objects only:** `Format-AdmanReport` / `Export-AdmanReportCsv` / `Export-AdmanReportHtml` take `PSCustomObject[]` and never touch AD types.
- **Preflight → config cache:** `Initialize-Adman` reads `ms-DS-Logon-Time-Sync-Interval` and stashes it on `$script:Config` so the stale report uses the same value without re-querying.
- **Capability probe → picker:** `Test-AdmanCapability` (or a sibling) probes `$PSEdition` + interactive-session + `Out-GridView`/`Out-ConsoleGridView` availability; the result is cached so the picker decision is O(1).

</code_context>

<specifics>
## Specific Ideas

- **Reuse the existing scope-check, don't reinvent it.** `Test-AdmanTargetAllowed` step (c) is the structural SAFE-07 invariant; read verbs must call it on every emitted object so a future refactor of `-SearchBase` handling can't silently broaden scope.
- **Render the four account states via `Search-ADAccount`, never bit math.** `userAccountControl` bit-twiddling is a classic source of bugs (e.g., `ACCOUNTDISABLE=0x2`, `LOCKOUT=0x10` interplay); the cmdlet encapsulates the correct semantics.
- **Make the report headers self-documenting.** The stale report's HTML/CSV header should state "fresh to within N days (sync interval = X, grace = Y)" so a reader knows exactly what the numbers mean without reading the code.
- **MENU-04 is the senior/junior split.** Every Public read verb must be callable directly with named parameters (senior path) AND be reachable via the menu (junior path); the menu is a thin prompt-and-dispatch layer, never a parallel implementation.

</specifics>

<deferred>
## Deferred Ideas

Items surfaced during discussion that belong to a later phase or are explicitly out of v1 scope — preserved, not acted on here.

- **Opt-in per-DC `lastLogon` aggregation report** — forensic-grade accuracy when a specific account's "did they really not log on for N days" must be verified before disable. Requires `Get-ADDomainController -Filter *` + per-DC `Get-ADUser -Server` loop + try/catch per DC. Fragile when a DC is down; 5-10x slower on multi-DC domains. Would need RPT-04 amended to carve out the exception (currently "never per-DC lastLogon"). Revisit only if a concrete forensic/compliance use case materializes in a later phase.
- **Hierarchical / hybrid menu with single-letter hotkeys (`U`/`C`/`R`/`P`)** — rejected for Phase 1 in favor of the flat while-loop (D-01). Revisit when the menu shape stabilizes (probably after Phase 2) and hotkey/number ambiguity is worth solving for the senior fast-path.
- **HTML with inline sortable/filterable JavaScript (e.g., sorttable.js)** — rejected for v1 (D-04) because it adds an untested JS surface and CSP risk in a security tool. Revisit only if a specific large report proves unusable as a static table.
- **CSS "cards" / dashboard layout for HTML reports** — rejected for v1 (D-04) as over-engineering for a function-first admin tool. Revisit only for a dedicated executive-summary report.
- **Templating library (PSHTML / EPS / custom here-string templates)** — rejected (violates PROJECT.md "zero new dependencies"). Revisit only if v2 adds dashboard-style reports.
- **Read-side audit hook** — SAFE-03 audits mutations, not reads. If a specific read (e.g., "export all stale accounts") is later deemed sensitive, add a discretionary read-audit via the existing `Write-AdmanAudit` seam.
- **Pipeline input on `Find-AdmanUser` / `Find-AdmanComputer`** — deferred until a concrete use case emerges; v1 keeps the surface minimal.
- **`-AdditionalProperties` additive-only parameter on the Find verbs** — deferred; default is exact `-Properties` per ROADMAP criterion 2.

</deferred>

---

*Phase: 1-AD Query & Reporting (read-only)*
*Context gathered: 2026-07-14*
