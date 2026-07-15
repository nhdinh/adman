---
phase: 1
reviewers: [codex]
reviewed_at: 2026-07-15T01:35:09Z
plans_reviewed: [01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md, 01-04-PLAN.md]
cycles:
  - cycle: 1
    reviewed_at: 2026-07-15T01:35:09Z
    reviewers: [codex]
  - cycle: 2
    reviewed_at: 2026-07-15T02:00:00Z
    reviewers: [codex]
  - cycle: 3
    reviewed_at: 2026-07-15T03:00:00Z
    reviewers: [codex]
---

# Cross-AI Plan Review — Phase 1

## Cycle 1 (2026-07-15T01:35:09Z)

## Codex Review

## Summary

Overall, the four-plan split is coherent and mostly aligned with the Phase 1 goal. The sequencing is sensible, the menu/query/report/render layers are separated, and most plans explicitly preserve Phase 0's read/write boundary. The main risks are not in the broad architecture; they are in a few execution details that can break security or the existing test harness: unsafe `-Filter` string construction in `01-02`, existing `Initialize-Adman` orchestration tests that `01-03` will invalidate unless updated, and some AD semantic/type ambiguities around `LastLogonReplicationInterval`.

## 01-01-PLAN.md — Menu Shell

### Strengths

- The plan correctly starts from the existing stub: `Public/Start-Adman.ps1:12` currently only calls `Initialize-Adman`, then returns at `Public/Start-Adman.ps1:14`, so this is the right place to add the TUI loop.
- The menu is intentionally pure dispatch: plan lines `01-01-PLAN.md:98-105` require one loop, prompt helper, public verb invocation, no AD read logic, and no renderer logic. That matches the Phase 1 context contract that the menu "NEVER contains read/write logic" at `01-CONTEXT.md:22-24`.
- Private menu helpers will load automatically because `adman.psm1:17-22` dot-sources `Private/**/*.ps1` before `Public/**/*.ps1`.
- The plan preserves direct senior-call parity by invoking the public verb name via `& $Verb @params` at `01-01-PLAN.md:104`.

### Concerns

- LOW: Top-level invalid-input copy includes `B`, but the top-level contract only reserves `Q`. `01-01-PLAN.md:102` says invalid input should say "Enter a number, B, or Q," while `01-CONTEXT.md:22-24` and `01-UI-SPEC.md:161-165` reserve `B` only inside action prompts. This is not a security issue, but it may confuse tests and users.
- LOW: `Start-Adman` currently has `[CmdletBinding(SupportsShouldProcess)]` at `Public/Start-Adman.ps1:9`. The plan does not explicitly remove it. Since Phase 1 is read-only and the function is a TUI launcher, keeping `SupportsShouldProcess` is harmless but misleading.

### Suggestions

- Make top-level prompt validation explicitly accept only `1..N` and `Q`; reserve `B` for action/output prompts.
- Remove `SupportsShouldProcess` from `Start-Adman` unless a later phase gives the launcher a real ShouldProcess responsibility.
- Keep the "no AD calls in `Start-Adman`" static assertion from `01-01-PLAN.md:165`; it is high-value.

### Risk Assessment

LOW. The plan fits the current module loader and stub structure. Main risk is test/copy drift, not architecture.

## 01-02-PLAN.md — Scoped Read Layer

### Strengths

- It correctly uses the existing managed-scope invariant instead of trusting `-SearchBase` alone. The mutation-side scope check is component-boundary anchored in `Private/Safety/Test-AdmanTargetAllowed.ps1:66-77`, and the plan mirrors that in a read-only helper at `01-02-PLAN.md:111`.
- It preserves the Phase 0 export boundary by updating `adman.psd1` instead of relying on wildcard exports; the manifest currently has an explicit list at `adman.psd1:50-53`.
- It correctly extends the AD mock, which currently only accepts minimal read parameters: `tests/Mocks/ActiveDirectory.psm1:39-46`. The planned scoped/paged mock support at `01-02-PLAN.md:77-82` is necessary for meaningful tests.
- The D-03 schema contract is well placed. Current context pins the exact schema at `01-CONTEXT.md:37-42`, and the plan adds `tests/Result.Schema.Tests.ps1` at `01-02-PLAN.md:112`.

### Concerns

- HIGH: The LDAP injection mitigation is underspecified and likely wrong for `-Filter`. The task says to build `Get-ADUser -Filter` strings at `01-02-PLAN.md:136-137`, while the threat mitigation says to use `Escape-AdmanLdapFilterValue` at `01-02-PLAN.md:169`. That helper is explicitly RFC4515 LDAP assertion escaping (`Private/Safety/Escape-AdmanLdapFilterValue.ps1:3-17`) and does not escape single quotes (`Private/Safety/Escape-AdmanLdapFilterValue.ps1:32-42`), which are significant in AD PowerShell `-Filter` string literals. A name like `O'Brien` can break the filter or alter semantics.
- MEDIUM: Copying `ConvertTo-AdmanNormalizedDn` into a new file (`01-02-PLAN.md:111`) creates a drift risk from the safety implementation at `Private/Safety/Test-AdmanTargetAllowed.ps1:104-127`. If scope semantics are later fixed in one place, reads and writes can diverge.
- MEDIUM: The plan says "exact `-Properties`" but also says the plan "may extend" via D-02 context (`01-CONTEXT.md:30`). Tests should pin the final property arrays exactly, otherwise the success criterion can silently weaken.

### Suggestions

- Either use `-LDAPFilter` everywhere with `Escape-AdmanLdapFilterValue`, or add a separate escape helper for AD PowerShell `-Filter` string literals, including single quote handling. Do not reuse the LDAP helper for `-Filter`.
- Prefer extracting the DN normalization helper into a shared private safety/utility file rather than copying it.
- Add tests with input containing `'`, `*`, `(`, `)`, `\`, and NUL-equivalent cases, and assert the constructed filter cannot broaden scope.

### Risk Assessment

MEDIUM-HIGH. The layer is architecturally sound, but query filter construction is a real security-sensitive edge.

## 01-03-PLAN.md — AD Semantics

### Strengths

- The stale report correctly avoids per-DC `lastLogon` and uses `lastLogonTimestamp`; the plan states this at `01-03-PLAN.md:114-118`, matching the phase decision at `01-CONTEXT.md:55-60`.
- The four-state account report correctly uses `Search-ADAccount` switches instead of UAC bit math at `01-03-PLAN.md:119-124`, matching `01-CONTEXT.md:61`.
- It composes with the existing recovery posture helper, which already returns `RecycleBinEnabled`, `ForestFunctionalLevel`, and `TombstoneLifetime` at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:83-87`.
- The plan corrects a dangerous research/context ambiguity by saying not to read the Configuration partition for the logon sync interval at `01-03-PLAN.md:84`.

### Concerns

- HIGH: Existing initialization tests will fail unless updated. `Initialize.Adman.Tests.ps1` currently asserts the exact six-step order at `tests/Initialize.Adman.Tests.ps1:99-106` and static source order at `tests/Initialize.Adman.Tests.ps1:128-144`. Plan `01-03` inserts `Get-AdmanLogonSyncInterval` and `Get-AdmanRecoveryPosture` into `Initialize-Adman` at `01-03-PLAN.md:84-89`, but does not list `tests/Initialize.Adman.Tests.ps1` as modified.
- MEDIUM: `LastLogonReplicationInterval` type handling is underspecified. The current mock `Get-ADDomain` has no such property (`tests/Mocks/ActiveDirectory.psm1:48-57`), and AD commonly exposes interval-like values as time spans or nullable values. Plan line `01-03-PLAN.md:84` says "returns the integer value" but does not define conversion from `[TimeSpan]`, `$null`, or malformed values.
- MEDIUM: Context still says D-07 reads the Configuration partition at `01-CONTEXT.md:63-65`, while the plan says to use `Get-ADDomain` at `01-03-PLAN.md:84`. The plan is likely the corrected version, but leaving the contradiction increases implementation drift.
- LOW: `Get-AdmanRecoveryPosture` calls `Get-ADForest` twice (`Private/Foundation/Get-AdmanRecoveryPosture.ps1:47` and `:59`). Caching its result in `Initialize-Adman` mitigates repeated report calls, but the helper itself still does duplicate reads when called directly.

### Suggestions

- Update `tests/Initialize.Adman.Tests.ps1` in this plan and adjust the expected startup sequence.
- Define sync interval conversion explicitly: handle integer days, `[TimeSpan]`, `$null`, zero/negative values, and fallback.
- Amend `01-CONTEXT.md` or add a prominent note that `01-03-PLAN.md` supersedes the old D-07 source text.
- Add a static test forbidding `lastLogon` property reads except `lastLogonTimestamp`.

### Risk Assessment

MEDIUM. The semantics are mostly right, but existing test contracts and type conversion details need tightening before execution.

## 01-04-PLAN.md — Output Layer

### Strengths

- The renderer split is clean and matches D-04: raw report objects flow to `Format-AdmanReport`, `Export-AdmanReportCsv`, or `Export-AdmanReportHtml`; see `01-CONTEXT.md:46-51` and plan lines `01-04-PLAN.md:80-90`, `:113-120`.
- HTML portability is well handled: the plan forbids `-CssUri`, `-Charset`, `-Meta`, and `-Transitional` at `01-04-PLAN.md:117-119`, matching the PS 5.1 parity warning at `01-CONTEXT.md:47`.
- The inventory report composes with the normalized schema and scope helper at `01-04-PLAN.md:145-148`, which is consistent with D-03 and D-02.
- The optional grid picker degrades to console output at `01-04-PLAN.md:83-84`, matching `01-UI-SPEC.md:188-193`.

### Concerns

- MEDIUM: `01-04` depends directly on `01-01` and `01-03` (`01-04-PLAN.md:6-8`), but `Get-AdmanInventoryReport` uses `ConvertTo-AdmanResult` and `Test-AdmanInManagedScope` from `01-02` at `01-04-PLAN.md:146-147`. This is transitive through `01-03`, but making `01-02` explicit would reduce scheduling mistakes.
- MEDIUM: All renderers collect pipeline input into memory (`01-04-PLAN.md:82`, `:115`). The threat model accepts this as low at `01-04-PLAN.md:190`, but large OUs and inventory exports are exactly where memory pressure will show first.
- LOW: The HTML plan relies on `ConvertTo-Html` output, but it also references `.true/.false` CSS classes at `01-UI-SPEC.md:309-315`. `ConvertTo-Html` will not automatically add those classes to boolean cells. If colored booleans are required, the plan needs explicit calculated/preformatted properties or post-processing.

### Suggestions

- Add `01-02` as an explicit dependency for `01-04`.
- Keep console formatting as collected output, but consider streaming CSV export directly to `Export-Csv` if memory becomes an issue.
- Clarify whether boolean CSS classes are required or aspirational. If required, add a test that fails until boolean cells get the expected classing.
- Add tests for empty result sets so console/CSV/HTML outputs are still predictable.

### Risk Assessment

MEDIUM-LOW. The output design is practical and PS 5.1-safe; the main risks are scale and minor UI-spec overpromises.

## Cross-Plan Suggestions

- Fix the `-Filter` escaping design before implementation. This is the most important issue.
- Update existing Phase 0 tests when modifying `Initialize-Adman`; do not only add new Phase 1 tests.
- Reconcile `01-CONTEXT.md` D-07/D-08 wording with the corrected sync-interval source in `01-03-PLAN.md`.
- Add static tests for forbidden semantics: no per-DC `lastLogon`, no `userAccountControl`, no full `Test-AdmanTargetAllowed` on read paths, no direct AD calls in `Start-Adman`.

Overall phase risk: MEDIUM. The architecture is solid, but the read-query layer and preflight integration need sharper implementation constraints before this is safe to execute.

---

## Consensus Summary

Only one reviewer (Codex) was invoked for this cycle, so this section reflects that single reviewer's findings, organized by theme for the planner.

### Agreed Strengths

- **Layer separation is clean.** Menu (dispatch) / query (scoped reads) / semantics (AD-correct reports) / renderers (output) are properly isolated; no layer crosses into another's responsibility. Matches D-01..D-04.
- **Phase 0 spine is reused, not reinvented.** Managed-scope check, `-Server $script:Config.DC` pinning, export boundary via `FunctionsToExport`, and the existing `Get-AdmanRecoveryPosture` helper are all composed rather than duplicated.
- **AD semantics are correct at the design level.** `lastLogonTimestamp` (never per-DC `lastLogon`), `Search-ADAccount` switches (never UAC bit math), and the corrected sync-interval source (`Get-ADDomain`, not Configuration partition) all match Microsoft-documented behavior.
- **PS 5.1/7.6 parity is explicitly protected.** HTML renderer forbids `-CssUri`/`-Charset`/`-Meta`/`-Transitional`; no 7-only syntax; the optional grid picker degrades to `Format-Table` on any failure.

### Agreed Concerns

- **HIGH — LDAP `-Filter` injection mitigation is wrong (01-02).** `Escape-AdmanLdapFilterValue` is RFC4515 assertion escaping and does NOT escape single quotes, which are significant in AD PowerShell `-Filter` string literals. A name like `O'Brien` will break the filter or alter semantics. Must either switch to `-LDAPFilter` (where the helper IS correct) or add a separate `-Filter`-specific escape helper.
- **HIGH — `Initialize-Adman` test breakage not accounted for (01-03).** `tests/Initialize.Adman.Tests.ps1` asserts the exact six-step startup order; inserting `Get-AdmanLogonSyncInterval` + `Get-AdmanRecoveryPosture` invalidates those tests, but the plan does not list the test file as modified.
- **MEDIUM — Type conversion for `LastLogonReplicationInterval` underspecified (01-03).** Plan says "returns the integer value" but AD may surface this as `[TimeSpan]`, `$null`, or other shapes; conversion rules (incl. zero/negative fallback) are not defined.
- **MEDIUM — CONTEXT.md D-07 contradicts 01-03-PLAN.md.** CONTEXT still says read from Configuration partition; plan correctly says `Get-ADDomain`. The contradiction will drift implementation.
- **MEDIUM — DN normalization copied, not shared (01-02).** Drift risk between read-side and write-side scope checks.
- **MEDIUM — Renderer memory pressure on large OUs (01-04).** All renderers collect pipeline input into memory; threat model accepts as low but inventory exports are exactly where this will surface first.
- **MEDIUM — 01-04 dependency on 01-02 is implicit.** `Get-AdmanInventoryReport` uses `ConvertTo-AdmanResult` + `Test-AdmanInManagedScope` from 01-02 but only 01-01 and 01-03 are listed as `depends_on`.

### Divergent Views

(Single-reviewer cycle — no divergence to record.)

### Top Actions for /gsd-plan-phase 1 --reviews

1. **Fix `-Filter` escaping (01-02).** Decide between `-LDAPFilter` + existing helper, or new `-Filter`-aware escape helper that handles `'`. Add tests with `'`, `*`, `(`, `)`, `\` inputs.
2. **Update `tests/Initialize.Adman.Tests.ps1` in 01-03.** Add to `files_modified` and adjust the expected startup sequence to include the two new preflight steps.
3. **Pin down `LastLogonReplicationInterval` conversion (01-03).** Specify handling for `[TimeSpan]`/`$null`/zero/negative; extend the `Get-ADDomain` mock to cover these.
4. **Reconcile CONTEXT.md D-07 with 01-03-PLAN.md.** Add a note that the plan supersedes the old D-07 source text (or amend CONTEXT).
5. **Extract DN normalization to a shared helper (01-02).** Do not copy `ConvertTo-AdmanNormalizedDn`; move it to a common private location and reuse from both read and write paths.
6. **Add `01-02` to `01-04.depends_on` (01-04).** Make the transitive dependency explicit.

---

## Cycle 2 (2026-07-15T02:00:00Z) — Replan Verification

Single-reviewer cycle (Codex). Reviewer was given the Cycle 1 finding list and asked to verify resolution + catch regressions.

### Codex Review

## 01-01 Menu Shell

**Cycle 1 Finding Resolution Status**

No Cycle 1 findings were assigned to 01-01.

**Strengths**

- The plan preserves the flat menu contract from context: top-level `Q` only, with `B/Q` inside prompts, matching `01-CONTEXT.md:20-24`.
- It explicitly keeps AD read logic and formatting out of `Start-Adman`, matching the UI dispatch contract at `01-UI-SPEC.md:179-186`.
- It accounts for the current source stub: `Public/Start-Adman.ps1` currently only calls `Initialize-Adman` and logs a placeholder at `Public/Start-Adman.ps1:12-14`, so the plan is scoped to replacing that stub.

**Concerns**

- **LOW:** The threat register still says input validation rejects everything except `1..N`, `B`, and `Q` at `01-01-PLAN.md:160`, while the task text correctly says top-level `B` is not reserved at `01-01-PLAN.md:103`. This is documentation drift that could confuse implementation.

**Suggestions**

- Tighten T-01-02 to say top-level allows only `1..N/Q`; action prompts allow `B/Q`.

## 01-02 Scoped Read Layer

**Cycle 1 Finding Resolution Status**

- **HIGH-1: RESOLVED.** The plan adds `Escape-AdmanAdFilterLiteral` specifically for AD PowerShell `-Filter` string literals at `01-02-PLAN.md:131-164`, including single-quote doubling at line 141 and backslash doubling at line 142. It also requires both Find verbs to use that helper and never use `Escape-AdmanLdapFilterValue` at `01-02-PLAN.md:210-229`. This is necessary because the current LDAP helper escapes RFC4515 assertion characters but does not escape single quotes, as shown in `Private/Safety/Escape-AdmanLdapFilterValue.ps1:35-41`.
- **MEDIUM-3: RESOLVED.** The plan explicitly moves, not copies, `ConvertTo-AdmanNormalizedDn` from `Private/Safety/Test-AdmanTargetAllowed.ps1` into `Private/Utility/ConvertTo-AdmanNormalizedDn.ps1` at `01-02-PLAN.md:106-127`. Current source has the local implementation at `Private/Safety/Test-AdmanTargetAllowed.ps1:104-127` and call sites at `Private/Safety/Test-AdmanTargetAllowed.ps1:68-71`, so the migration target is real and correctly identified. The module loader dot-sources all private files before public files at `adman.psm1:17-22`.

**Strengths**

- The plan correctly distinguishes `-Filter` escaping from `-LDAPFilter` escaping, which is the important security fix.
- The scope re-check is deliberately read-only and avoids invoking the mutation gate, matching context that deny/protected checks are mutation-only while scope applies to reads at `01-CONTEXT.md:34`.
- The mock extension is grounded in current source: `tests/Mocks/ActiveDirectory.psm1:39-46` currently lacks the scoped read parameters the plan adds.

**Concerns**

- **LOW:** `depends_on` is empty at `01-02-PLAN.md:6`, while 01-01's menu definition lists verbs that 01-02 creates. This can work if menu tests mock the verbs, but the wave plan should make clear that 01-01 must not execute real menu selections against absent verbs.

**Suggestions**

- Add a sentence to 01-01/01-02 wave coordination that 01-01 menu tests use mocked public verbs until 01-02 lands.

## 01-03 AD Semantics

**Cycle 1 Finding Resolution Status**

- **HIGH-2: RESOLVED.** The plan now lists `tests/Initialize.Adman.Tests.ps1` in `files_modified` at `01-03-PLAN.md:14-15` and explicitly updates both the orchestration-order test and static source-order test to eight steps at `01-03-PLAN.md:109-123`. This matches the current source problem: the existing test asserts only six steps at `tests/Initialize.Adman.Tests.ps1:99-106`, and the static test checks only six ordered names at `tests/Initialize.Adman.Tests.ps1:128-144`.
- **MEDIUM-1: RESOLVED.** The plan defines conversion rules for `$null`, `TimeSpan`, numeric zero/negative, other types, and exceptions at `01-03-PLAN.md:89-96`, and requires mock/test coverage for those shapes at `01-03-PLAN.md:101-108`. Current `Get-ADDomain` mock has no `LastLogonReplicationInterval` at `tests/Mocks/ActiveDirectory.psm1:48-58`, so the planned mock change is necessary.
- **MEDIUM-2: RESOLVED.** `01-CONTEXT.md` now includes the supersession note and points to `(Get-ADDomain).LastLogonReplicationInterval` as authoritative at `01-CONTEXT.md:63-65`. The research file supports the same source at `01-RESEARCH.md:433-447`.

**Strengths**

- The plan correctly avoids per-DC `lastLogon` and UAC bit math, matching requirements at `REQUIREMENTS.md:74-75`.
- It identifies that `Search-ADAccount` mock support is currently insufficient: source has `Search-ADAccount { param($Identity, $Server) }` at `tests/Mocks/ActiveDirectory.psm1:46`, and the plan extends it at `01-03-PLAN.md:150-151`.
- The existing `Get-AdmanRecoveryPosture` helper is read-only and field-failure tolerant, as shown by try/catch blocks at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:35-42`, `:46-51`, and `:58-77`.

**Concerns**

- **LOW:** 01-03 still says the context "should be amended in a future pass" at `01-03-PLAN.md:88`, but the context already has the supersession note at `01-CONTEXT.md:63-65`. This is harmless but stale.
- **LOW:** The plan says to use `Write-PSFMessage -Level Verbose` for non-fatal recovery posture read failures at `01-03-PLAN.md:100`, while the existing helper logs warnings for read failures at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:41`, `:50`, and `:76`. If "Verbose only" is intentional, the helper also needs modification.

**Suggestions**

- Remove the stale "future pass" note from 01-03.
- Decide whether recovery posture read failures should remain warnings or become verbose messages, then state that explicitly.

## 01-04 Output Layer

**Cycle 1 Finding Resolution Status**

- **MEDIUM-4: PARTIALLY RESOLVED.** The plan documents the ~10,000-row soft bound for console and HTML at `01-04-PLAN.md:83` and `01-04-PLAN.md:118`. It also intends CSV streaming at `01-04-PLAN.md:87-90`. However, the instruction to call `Export-Csv -Path $Path` "inside the process block" is unsafe/incomplete: repeated `Export-Csv` calls without a first-row/header strategy plus `-Append` can overwrite or mishandle headers. Empty pipeline "headers only" is also underspecified because no input object means no schema can be inferred.
- **MEDIUM-5: RESOLVED.** 01-04 now explicitly depends on all earlier plans at `01-04-PLAN.md:6-9`.

**Strengths**

- The plan keeps renderers separated from report/query verbs, matching `01-UI-SPEC.md:179-186`.
- It uses only 5.1-safe `ConvertTo-Html` parameters at `01-04-PLAN.md:121-122`, matching the UI spec at `01-UI-SPEC.md:190-193`.
- It correctly wires output-format prompting after verb execution, matching `01-UI-SPEC.md:140-153`.

**Concerns**

- **MEDIUM:** CSV streaming design is not implementation-safe as written. `01-04-PLAN.md:89` says to pipe each `$InputObject` directly to `Export-Csv` inside `process`, but robust streaming needs a "first row writes headers, later rows append" pattern or a single pipeline into `Export-Csv`. The current acceptance grep at `01-04-PLAN.md:99` would not catch overwrite/header bugs.
- **MEDIUM:** Empty-result CSV/HTML tests are underspecified. The plan expects "empty CSV with headers only" at `01-04-PLAN.md:91`, but the renderer cannot infer headers from an empty pipeline unless callers pass an explicit schema/property list or a typed empty object prototype.

**Suggestions**

- Specify a concrete CSV streaming algorithm: first input object writes `Export-Csv -NoTypeInformation`; subsequent objects use `Export-Csv -Append -NoTypeInformation`, with file existence controlled in `begin`.
- Add an optional `-Properties` or `-Schema` parameter for renderers if empty-result files must include headers.

### Risk Assessment

Overall phase risk: **MEDIUM**.

The Cycle 1 high-risk items are materially addressed in the replan. The main remaining risk is 01-04 CSV/empty-result behavior: it is a real implementation trap and the current tests/acceptance criteria would not reliably catch it. The rest of the plan aligns well with current Phase 0 source constraints.

### Top Actions For The Next Planning Pass

1. Fix 01-04 CSV streaming details and add tests that prove multi-row output is not overwritten and headers appear exactly once.
2. Define how renderers get schema for empty result sets.
3. Clean up the stale 01-03 context-amendment note and the recovery-posture warning-vs-verbose mismatch.
4. Clarify 01-01/01-02 wave coordination so menu tests do not depend on not-yet-created real verbs.

---

## Cycle 2 Consensus Summary

Single-reviewer cycle (Codex). Verdicts below reflect that one reviewer's findings.

### Cycle 1 Finding Verdicts

| Finding | Plan | Verdict | Evidence |
|---------|------|---------|----------|
| HIGH-1 (`-Filter` escaping) | 01-02 | RESOLVED | `01-02-PLAN.md:131-164` (helper), `:210-229` (usage mandate); `Private/Safety/Escape-AdmanLdapFilterValue.ps1:35-41` confirms the LDAP helper does NOT escape `'` |
| HIGH-2 (`Initialize.Adman.Tests.ps1` not modified) | 01-03 | RESOLVED | `01-03-PLAN.md:14-15` (files_modified), `:109-123` (eight-step order); `tests/Initialize.Adman.Tests.ps1:99-106,128-144` confirms current six-step assertions |
| MEDIUM-1 (`LastLogonReplicationInterval` conversion) | 01-03 | RESOLVED | `01-03-PLAN.md:89-96` (rules), `:101-108` (mock shapes); `tests/Mocks/ActiveDirectory.psm1:48-58` confirms current mock lacks the property |
| MEDIUM-2 (CONTEXT D-07 contradiction) | 01-03 | RESOLVED | `01-CONTEXT.md:63-65` (supersession note); `01-RESEARCH.md:433-447` (corrected source) |
| MEDIUM-3 (DN normalization copied) | 01-02 | RESOLVED | `01-02-PLAN.md:106-127` (MOVE, not copy); `Private/Safety/Test-AdmanTargetAllowed.ps1:104-127` (current local impl), `:68-71` (call sites) |
| MEDIUM-4 (renderer memory) | 01-04 | PARTIALLY RESOLVED | `01-04-PLAN.md:83,118` (soft bound documented), `:87-90` (streaming intent) — BUT `:89` pipes `$InputObject` directly to `Export-Csv` inside `process`, which is unsafe (overwrite/header bugs); `:91` "headers only" for empty pipeline is underspecified |
| MEDIUM-5 (01-04 depends_on 01-02) | 01-04 | RESOLVED | `01-04-PLAN.md:6-9` (depends_on: 01-01, 01-02, 01-03) |

### Agreed Strengths (Cycle 2)

- All Cycle 1 HIGH findings are verifiably resolved with `path:line` evidence in the replan.
- The replan introduces no new HIGH-severity issues.
- Plan-to-source traceability is strong: every replan claim was verified against actual repo files.

### Agreed Concerns (Cycle 2)

- **MEDIUM — CSV streaming design is not implementation-safe (01-04).** Piping `$InputObject` directly to `Export-Csv` inside `process` without a first-row/header strategy will overwrite or mishandle headers. The acceptance grep would not catch this.
- **MEDIUM — Empty-result CSV/HTML underspecified (01-04).** "Empty CSV with headers only" cannot be inferred from an empty pipeline; the renderer needs an explicit schema or property list.
- **LOW — Threat register drift in 01-01.** T-01-02 still mentions `B` at top level; task text correctly reserves `B` for action prompts only.
- **LOW — Stale "future pass" note in 01-03.** CONTEXT.md is already amended; the note is redundant.
- **LOW — Recovery-posture warning-vs-verbose mismatch (01-03).** Plan says verbose; existing helper logs warnings.
- **LOW — Wave coordination between 01-01 and 01-02.** Menu tests must mock verbs until 01-02 lands; not stated explicitly.

### Divergent Views

(Single-reviewer cycle — no divergence to record.)

### Top Actions for /gsd-plan-phase 1 --reviews (Cycle 2)

1. **Fix 01-04 CSV streaming (MEDIUM).** Specify a concrete algorithm: first input object writes `Export-Csv -NoTypeInformation`; subsequent objects use `Export-Csv -Append -NoTypeInformation`, with file existence controlled in `begin`. Add tests that prove multi-row output is not overwritten and headers appear exactly once.
2. **Define empty-result schema strategy (MEDIUM).** Add an optional `-Properties` or `-Schema` parameter to renderers so empty-result files can include headers.
3. **Tighten T-01-02 threat register (LOW).** Top-level allows only `1..N/Q`; action prompts allow `B/Q`.
4. **Clean up stale notes (LOW).** Remove the "future pass" note from 01-03; reconcile recovery-posture warning-vs-verbose.
5. **Clarify 01-01/01-02 wave coordination (LOW).** State explicitly that 01-01 menu tests use mocked public verbs until 01-02 lands.

---

## Cycle 3 (2026-07-15T03:00:00Z) — Replan Verification

Single-reviewer cycle (Codex). Reviewer was given the Cycle 2 finding list and asked to verify resolution + catch regressions.

### Codex Review

### Cycle 2 Finding Verdicts

| Finding | Plan | Verdict | Evidence |
|---------|------|---------|----------|
| CSV streaming design is not implementation-safe | 01-04 | UNRESOLVED | `.planning/phases/01-ad-query-reporting-read-only/01-04-PLAN.md:89` still says to pipe `$InputObject` directly to `Export-Csv` inside `process`; it does not specify first-row header creation plus subsequent `-Append`. `.planning/phases/01-ad-query-reporting-read-only/01-04-PLAN.md:99` keeps the grep-only acceptance check, which would not catch overwrite/header behavior. |
| Empty-result CSV/HTML underspecified | 01-04 | UNRESOLVED | `.planning/phases/01-ad-query-reporting-read-only/01-04-PLAN.md:91` requires "empty CSV with headers only" and empty HTML table from an empty pipeline, but the renderer signatures at `.planning/phases/01-ad-query-reporting-read-only/01-04-PLAN.md:82`, `:88`, and `:117` have no `-Schema`, `-Properties`, or explicit empty-result schema source. |
| Threat register drift in 01-01 | 01-01 | UNRESOLVED | The task text is corrected at `.planning/phases/01-ad-query-reporting-read-only/01-01-PLAN.md:103`, but the threat register still says "reject everything except 1..N, B, and Q" at `.planning/phases/01-ad-query-reporting-read-only/01-01-PLAN.md:160`. |
| Stale "future pass" note in 01-03 | 01-03 | UNRESOLVED | The stale note remains at `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:88` and again at `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:258`, despite `.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md:64` already containing the superseded-source amendment. |
| Recovery-posture warning-vs-verbose mismatch | 01-03 | UNRESOLVED | `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:100` says to use `Write-PSFMessage -Level Verbose` for posture read failures, but the existing helper documents and emits warnings at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:13`, `:14`, `:41`, `:50`, `:76`, and `:80`. The plan does not state that the helper will be changed or that warnings are accepted. |
| Wave coordination between 01-01 and 01-02 | 01-01 | RESOLVED | `.planning/phases/01-ad-query-reporting-read-only/01-01-PLAN.md:76` tells menu tests to use an in-memory function table instead of real AD calls, and `.planning/phases/01-ad-query-reporting-read-only/01-01-PLAN.md:133` explicitly says not to add real AD cmdlets under `Public/` for this plan. That covers mocking/stubbing verbs until 01-02 lands. |

### New Issues

**LOW — 01-CONTEXT D-08 still conflicts with the recovery posture helper's actual shape.**
`.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md:69` says recovery posture includes `ms-DS-Logon-Time-Sync-Interval`, but the existing helper returns `RecycleBinEnabled`, `ForestFunctionalLevel`, and `TombstoneLifetime` at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:83`. The current 01-03 plan aligns with the helper at `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:121`, so the remaining context drift can mislead implementers reading D-08.

### Strengths

- 01-01 now clearly separates top-level menu inputs from action-prompt inputs in the task body, especially `.planning/phases/01-ad-query-reporting-read-only/01-01-PLAN.md:103`.
- 01-01 correctly coordinates Wave 1 menu tests with not-yet-created verbs by using in-memory functions, avoiding RSAT/live-domain coupling.
- 01-03's preflight plan is concrete about updating both dynamic and static startup-order tests at `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:109` through `:112`, matching the current six-step assertions in `tests/Initialize.Adman.Tests.ps1:99` through `:106` and `:128` through `:144`.
- 01-03 has strong AD semantics for stale and account-state reports: `lastLogonTimestamp` only, `whenCreated` grace check, and four separate `Search-ADAccount` switches at `.planning/phases/01-ad-query-reporting-read-only/01-03-PLAN.md:141` through `:149`.

### Risk Assessment

Overall phase risk: **MEDIUM**.

The AD semantics plans are mostly specific and source-aware, but the renderer plan still has two implementation-level holes: streaming CSV headers and empty-result schemas. Those are likely to produce broken Phase 1 output even if tests exist, because the current acceptance criteria can pass while the implementation is wrong. The remaining 01-01 and 01-03 drift is lower risk but should be cleaned up before execution to avoid contradictory instructions.

### Top Actions for the Next Planning Pass

1. Rewrite 01-04 CSV streaming to use a concrete first-row strategy: first object writes headers normally, later objects use `Export-Csv -Append`, with tests proving multi-row output is not overwritten and headers appear exactly once.
2. Add an explicit schema mechanism for empty results, such as `-Properties` or `-Schema`, and require CSV/HTML/console empty-result tests to pass that schema.
3. Fix 01-01 threat register T-01-02 so top-level input allows only `1..N/Q`; reserve `B` only for action/output prompts.
4. Remove the stale 01-03 "CONTEXT.md should be amended in a future pass" notes.
5. Reconcile recovery-posture logging: either change the helper to verbose or state that the existing warning behavior is intentional.
6. Amend 01-CONTEXT D-08 so recovery posture consistently means `RecycleBinEnabled`, `ForestFunctionalLevel`, and `TombstoneLifetime`.

---

## Cycle 3 Consensus Summary

Single-reviewer cycle (Codex). Verdicts below reflect that one reviewer's findings.

### Cycle 2 Finding Verdicts

| Finding | Plan | Verdict | Evidence |
|---------|------|---------|----------|
| CSV streaming design is not implementation-safe (MEDIUM) | 01-04 | UNRESOLVED | `01-04-PLAN.md:89` still pipes `$InputObject` directly to `Export-Csv` inside `process` without first-row/`-Append` strategy; `:99` grep-only acceptance check would not catch overwrite/header bugs |
| Empty-result CSV/HTML underspecified (MEDIUM) | 01-04 | UNRESOLVED | `01-04-PLAN.md:91` requires "empty CSV with headers only" but renderer signatures at `:82`, `:88`, `:117` have no `-Schema`/`-Properties` parameter |
| Threat register drift in 01-01 (LOW) | 01-01 | UNRESOLVED | Task text corrected at `01-01-PLAN.md:103` but T-01-02 at `:160` still says "reject everything except 1..N, B, and Q" |
| Stale "future pass" note in 01-03 (LOW) | 01-03 | UNRESOLVED | Note remains at `01-03-PLAN.md:88` and `:258` despite `01-CONTEXT.md:64` already amended |
| Recovery-posture warning-vs-verbose mismatch (LOW) | 01-03 | UNRESOLVED | `01-03-PLAN.md:100` says verbose; helper emits warnings at `Private/Foundation/Get-AdmanRecoveryPosture.ps1:13,14,41,50,76,80`; plan does not reconcile |
| Wave coordination between 01-01 and 01-02 (LOW) | 01-01 | RESOLVED | `01-01-PLAN.md:76` (in-memory function table) and `:133` (no real AD cmdlets under Public/) cover mocking until 01-02 lands |

### Agreed Strengths (Cycle 3)

- 01-01 task body now correctly separates top-level (`1..N/Q`) from action-prompt (`B/Q`) reserved inputs.
- 01-01 menu tests use in-memory function tables, avoiding RSAT/live-domain coupling during Wave 1.
- 01-03 preflight plan concretely updates both dynamic and static startup-order tests to the eight-step sequence.
- 01-03 AD semantics are correct: `lastLogonTimestamp` only, `whenCreated` grace check, four `Search-ADAccount` switches.

### Agreed Concerns (Cycle 3)

- **MEDIUM — CSV streaming design is not implementation-safe (01-04).** Still unresolved from Cycle 2. Piping `$InputObject` directly to `Export-Csv` inside `process` without a first-row/header strategy will overwrite or mishandle headers. The acceptance grep would not catch this.
- **MEDIUM — Empty-result CSV/HTML underspecified (01-04).** Still unresolved from Cycle 2. "Empty CSV with headers only" cannot be inferred from an empty pipeline; the renderer needs an explicit schema or property list.
- **LOW — Threat register drift in 01-01.** Still unresolved from Cycle 2. T-01-02 still mentions `B` at top level; task text correctly reserves `B` for action prompts only.
- **LOW — Stale "future pass" note in 01-03.** Still unresolved from Cycle 2. CONTEXT.md is already amended; the note is redundant.
- **LOW — Recovery-posture warning-vs-verbose mismatch (01-03).** Still unresolved from Cycle 2. Plan says verbose; existing helper logs warnings.
- **LOW — 01-CONTEXT D-08 conflicts with helper shape (NEW).** CONTEXT says recovery posture includes `ms-DS-Logon-Time-Sync-Interval`, but the helper returns `RecycleBinEnabled`, `ForestFunctionalLevel`, `TombstoneLifetime`.

### Divergent Views

(Single-reviewer cycle — no divergence to record.)

### Top Actions for /gsd-plan-phase 1 --reviews (Cycle 3)

1. **Fix 01-04 CSV streaming (MEDIUM).** Specify a concrete algorithm: first input object writes `Export-Csv -NoTypeInformation`; subsequent objects use `Export-Csv -Append -NoTypeInformation`, with file existence controlled in `begin`. Add tests that prove multi-row output is not overwritten and headers appear exactly once.
2. **Define empty-result schema strategy (MEDIUM).** Add an optional `-Properties` or `-Schema` parameter to renderers so empty-result files can include headers.
3. **Tighten T-01-02 threat register (LOW).** Top-level allows only `1..N/Q`; action prompts allow `B/Q`.
4. **Clean up stale notes (LOW).** Remove the "future pass" note from 01-03; reconcile recovery-posture warning-vs-verbose.
5. **Amend 01-CONTEXT D-08 (LOW, NEW).** Recovery posture consistently means `RecycleBinEnabled`, `ForestFunctionalLevel`, `TombstoneLifetime`.
