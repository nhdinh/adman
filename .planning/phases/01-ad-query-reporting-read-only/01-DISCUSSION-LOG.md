# Phase 1: AD Query & Reporting (read-only) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-14
**Phase:** 1-ad-query-reporting-read-only
**Areas discussed:** Menu navigation model, Read wrapper shape + result-object schema, Report output layer (console/CSV/HTML), Stale/inactive semantics + DC coverage

---

## Menu navigation model

| Option | Description | Selected |
|--------|-------------|----------|
| Flat numbered menu, single `while` loop | Simplest to ship; one keystroke from top; identical 5.1 + 7.6 | ✓ |
| Grouped/hierarchical, stack-based push/pop, `B`/`Q` reserved | Matches four-job mental model; scales to Phase 2/3 nested write flows | |
| `$Host.UI.PromptForChoice`, flat | Native PowerShell look; accelerator collisions past ~9 items; no back concept | |
| State machine (`$state` enum + `switch`) | Explicit transitions; over-engineered for 2-level menu | |
| Hybrid: grouped hierarchy + numeric + single-letter hotkeys | Seniors one-keystroke; hotkey/number ambiguity | |

**User's choice:** Flat numbered menu, single `while` loop.
**Notes:** User accepted that the list will grow (~12+ items in Phase 1, more in Phase 2/3) and that menu shape may need redesign when nested write/confirm flows arrive — that is a Phase 2 concern. MENU-03 (back/quit) under a flat menu: `Q` at top-level exits; `B` inside an action's prompts returns to top; `Q` inside an action's prompts exits the tool. These are the only reserved single-letter inputs.

---

## Read wrapper shape + result-object schema

| Option | Description | Selected |
|--------|-------------|----------|
| A + D: Two typed verbs (`Find-AdmanUser`, `Find-AdmanComputer`) + normalized `[pscustomobject]` schema | 1:1 map to USER-01/COMP-01; per-type exact `-Properties`; trivial MENU-04 | ✓ |
| B + D: Single generic `Find-AdmanObject -Type user\|computer` + normalized schema | One export; conditional validation | |
| C: Thin pass-through verbs returning raw `ADUser`/`ADComputer` | No schema; renderers branch on objectClass | |

**User's choice:** A + D (typed verbs + normalized schema).
**Notes:** Scope and paging invariants enforced structurally — loop every `$script:Config.ManagedOUs` root with `-SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC`. SAFE-07 enforced via the existing `Test-AdmanTargetAllowed` step (c) on every emitted object. Schema contract test pins the emitted property set so renderers cannot silently read raw AD properties. `-Server` pinning reuses the Phase 0 pattern.

---

## Report output layer (console/CSV/HTML)

**Question 1 — HTML design:**

| Option | Description | Selected |
|--------|-------------|----------|
| Static HTML, embedded CSS via `-Head`, no JS | Self-contained; opens offline; paste-into-ticket safe; 5.1 + 7.x identical | ✓ |
| Static HTML + inline sort/filter JS | Click-to-sort; adds untested JS surface and CSP risk in a security tool | |
| CSS cards / dashboard layout | Manager-facing polish; far more code; over-engineering for function-first tool | |

**User's choice:** Static HTML + embedded CSS, no JS.
**Notes:** `-CssUri` forbidden (writes only an external `<link>`). `-Charset`/`-Meta`/`-Transitional` are PS6+ only — MUST be omitted for 5.1 parity. CSS lives in a single here-string constant.

**Question 2 — Picker:**

| Option | Description | Selected |
|--------|-------------|----------|
| Capability-probed picker, optional sugar | `Out-GridView` on Desktop, `Out-ConsoleGridView` on Core; hand-rolled menu primary | ✓ |
| No picker in v1 | All results via numbered console menu | |

**User's choice:** Capability-probed picker, optional sugar.
**Notes:** Picker wraps in try/catch and silently degrades to `Format-Table` on Server Core, remoting, SSH, or headless sessions. Never a hard dependency.

---

## Stale/inactive semantics + DC coverage

**Question 1 — Report structure:**

| Option | Description | Selected |
|--------|-------------|----------|
| A: Single report, two buckets (`lastLogonTimestamp` only) | Matches RPT-04 verbatim; one CSV/HTML; fast single-DC query | ✓ |
| B: Two separate reports (stale + never-logged-on) | Cleaner separation; never-logged-on is a filter on the same dataset | |

**User's choice:** A — single report, two buckets.
**Notes:** `Bucket` column on result object (`Stale` | `NeverLoggedOn`). Never-logged-on cross-checked against `whenCreated` so a 2-day-old account that simply hasn't logged on yet is NOT flagged.

**Question 2 — Grace buffer:**

| Option | Description | Selected |
|--------|-------------|----------|
| D + E: Preflight read `ms-DS-Logon-Time-Sync-Interval` + grace = `max(14, interval) + 1` | Self-tuning; report header states actual freshness window | ✓ |
| Hard-coded 14-day grace | Simpler; silently wrong if interval tuned upward | |
| D only: read interval for display, keep 14-day grace | Informational only | |

**User's choice:** D + E — preflight read + self-tuning grace.
**Notes:** Microsoft-verified semantic: `lastLogonTimestamp` updates only when `current_time - lastLogonTimestamp > msDS-LogonTimeSyncInterval` (default 14 days), with initial post-DFL-raise randomization of "14 days minus random percentage of 5 days". Epsilon of +1 day absorbs edge-of-window timing skew.

**Question 3 — Per-DC fan-out:**

| Option | Description | Selected |
|--------|-------------|----------|
| No per-DC report in v1 | Defer to future requirement | ✓ |
| Add opt-in per-DC `lastLogon` report now | Forensic-grade accuracy; requires RPT-04 amendment; fragile when a DC is down | |

**User's choice:** No per-DC report in v1.
**Notes:** Deferred as a future requirement. Would need RPT-04 amended to carve out the exception (currently "never per-DC lastLogon").

---

## Claude's Discretion

- Concrete Public verb names for the four RPT report types (stale/inactive, account-state, OS/inventory, recovery-posture) within `Get-Adman*Report` / `Find-Adman*` conventions.
- Exact CSS fragment content (colors, typography, zebra striping).
- Whether to add a `-Properties` override or `-AdditionalProperties` additive-only parameter on the Find verbs (default: NO).
- Menu item ordering within the flat list.
- Whether `Find-AdmanUser` / `Find-AdmanComputer` support pipeline input (default: NO for v1).
- Exact `Bucket` column value names.

## Deferred Ideas

- Opt-in per-DC `lastLogon` aggregation report — needs RPT-04 amendment.
- Hierarchical / hybrid menu with single-letter hotkeys — revisit after Phase 2.
- HTML with inline sortable/filterable JavaScript — revisit only if a specific large report proves unusable static.
- CSS "cards" / dashboard layout — revisit only for a dedicated executive-summary report.
- Templating library (PSHTML / EPS) — violates PROJECT.md zero-new-deps constraint.
- Read-side audit hook — SAFE-03 is mutation-only; revisit if a specific read is deemed sensitive.
- Pipeline input on Find verbs — defer until a concrete use case emerges.
- `-AdditionalProperties` additive-only parameter — defer.
