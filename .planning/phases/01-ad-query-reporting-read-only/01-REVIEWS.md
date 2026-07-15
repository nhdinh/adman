---
phase: 1
reviewers: [codex]
reviewed_at: 2026-07-15T01:35:09Z
plans_reviewed: [01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md, 01-04-PLAN.md]
---

# Cross-AI Plan Review — Phase 1

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
