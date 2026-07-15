---
phase: 02
reviewers: [codex]
reviewed_at: 2026-07-15T20:51:32Z
plans_reviewed: [02-01-PLAN.md, 02-02-PLAN.md, 02-03-PLAN.md, 02-04-PLAN.md, 02-05-PLAN.md, 02-06-PLAN.md]
cycle: 3
---

# Cross-AI Plan Review — Phase 02 (Cycle 3)

## Codex Review

## Summary

The cycle-3 revisions substantially resolve the cycle-2 issues in the current `02-*-PLAN.md` files. The `*Source` markers are now consistently named from the per-verb password parameter names, the marker parameters are declared on the target Public verbs, and the menu contract is explicitly tied to `Start-Adman`'s real `& $Verb @params` dispatch path. I found no regression of the seven cycle-1 fixes. I do have one new MEDIUM concern: the phase-level menu contract test still mostly proves "all splatted keys exist," not "PowerShell can bind every menu-produced splat to the real command," which leaves parameter-set conflicts under-tested, especially for `Set-AdmanLocalUser` fixed-parameter entries.

## Cycle 2 Fix Verification

- **HIGH #1: Menu password PromptSpec names and `${name}Source` markers match verb signatures — RESOLVED**
  - Existing dispatch source confirms why this matters: `Start-Adman` dispatches with `& $Verb @params` at `Public/Start-Adman.ps1:133-134`.
  - AD user plan declares `AccountPasswordSource` and `NewPasswordSource` with `[ValidateSet('Generate','Prompt')]` at `02-02-PLAN.md:50`, with concrete splat tests at lines 108 and 146.
  - Local user plan declares `PasswordSource` on `New-AdmanLocalUser` and on `Set-AdmanLocalUser`'s `Reset` parameter set at `02-04-PLAN.md:102`, with contract tests at lines 98-99.
  - Menu plan aligns PromptSpec names exactly: `AccountPassword`, `NewPassword`, and `Password`, and maps generated markers to declared parameters at `02-06-PLAN.md:48` and `02-06-PLAN.md:108`.
  - Per-call detection correctly prefers explicit menu markers via `$PSBoundParameters.ContainsKey(...)`, then falls back to caller-supplied password detection, then config, at `02-02-PLAN.md:111` and `02-02-PLAN.md:149`.

- **MEDIUM #2: `Failed` normalized to `Failure` — RESOLVED**
  - Current audit writer source accepts `Failure`, not `Failed`, in its ValidateSet at `Private/Audit/Write-AdmanAudit.ps1:37`.
  - Plans now instruct failure-outcome writes with `Result='Failure'` for AD and local wrapper throws at `02-01-PLAN.md:80`, `02-01-PLAN.md:183`, `02-01-PLAN.md:222`, and `02-01-PLAN.md:223`.
  - The remaining `Failed` occurrences are explanatory text or existing result counters, not proposed audit `Result='Failed'` writes.

- **MEDIUM #3: CN uniqueness pre-flight uses `-SearchScope OneLevel` — RESOLVED**
  - Plan 02-01 explicitly requires the CN lookup to use `-SearchBase <ParentOuDn> -SearchScope OneLevel -Server $script:Config.DC` and explains why Subtree would over-refuse valid creates at `02-01-PLAN.md:188`.

## Cycle 1 Regression Check

No regressions found.

- Gate failure-audit try/catch remains specified for AD and local gates: `02-01-PLAN.md:80`, `02-01-PLAN.md:183`, `02-01-PLAN.md:223`.
- Manifest exports still land in the same plans as verbs: `02-02-PLAN.md:111`, `02-04-PLAN.md:102`.
- Unlock server splat collision fix remains: `02-01-PLAN.md:77`, `02-01-PLAN.md:188`.
- `ChangePasswordAtLogon` is still routed through `Set-ADUser`: `02-01-PLAN.md:188`.
- Config fixtures still gain `security`: `02-01-PLAN.md:148`, `02-01-PLAN.md:151`.
- `FixedParameters` is retained: `02-06-PLAN.md:49`, `02-06-PLAN.md:108`.
- `Start.Adman.Tests.ps1` remains in the plan and verify command: `02-06-PLAN.md:12`, `02-06-PLAN.md:111`.

## Strengths

- The per-call source heuristic is now explicit and correct for menu calls: marker first, caller-supplied password second, config last. Evidence: `02-02-PLAN.md:111`, `02-02-PLAN.md:149`.
- `Set-AdmanLocalUser` correctly binds `PasswordSource` only to the `Reset` parameter set, not Enable/Disable. Evidence: `02-04-PLAN.md:102`.
- The menu contract test was broadened to include PromptSpec names, fixed keys, and auto-generated source markers. Evidence: `02-06-PLAN.md:105`.
- The `Failure` audit spelling is aligned with the real writer ValidateSet. Evidence: `Private/Audit/Write-AdmanAudit.ps1:37`.

## Concerns

- **MEDIUM: Menu contract test still does not prove every real menu splat can bind.**
  The plan's broad test introspects `(Get-Command <Verb>).Parameters.Keys` to confirm splatted keys exist, but PowerShell can still throw parameter-set binding errors even when every key is declared. This matters because the real dispatcher uses `& $Verb @params` (`Public/Start-Adman.ps1:134`), and `Set-AdmanLocalUser` relies on mutually exclusive parameter sets plus `FixedParameters` (`02-06-PLAN.md:103-105`). The specific reset splat is tested in Plan 02-04 (`02-04-PLAN.md:99`), but the phase-level menu test should actually invoke each command with synthetic menu params under `-WhatIf`, including Enable/Disable fixed-parameter entries.

- **LOW: `Set-AdmanLocalUser` reset-source behavior is internally ambiguous for direct callers.**
  The behavior says password reset "sources the password per D-05" (`02-04-PLAN.md:89`), but the action later says no switch and no `-Password` should throw, and only "when `-Password` is supplied" should it reset (`02-04-PLAN.md:102`). That is not a menu-path break because the menu supplies `Password`, but it is inconsistent with `Set-AdmanUserPassword`, where omitted password triggers Generate/Prompt sourcing.

## Suggestions

- Add a phase-level menu dispatch contract test that builds a synthetic hashtable from every non-null menu entry, merges `FixedParameters`, adds generated `*Source` markers, then invokes `& $Verb @params -WhatIf`. Assert no `ParameterBindingException`, not just no unknown parameter.
- Clarify `Set-AdmanLocalUser` direct-call reset semantics: either make omitted `-Password` generate/prompt per D-05, or make `-Password` mandatory in the `Reset` set and update Test 3 wording accordingly.
- Add explicit contract rows for the Enable and Disable local-user menu entries: `@{ Name='luser'; Enable=$true }` and `@{ Name='luser'; Disable=$true }` bind to the intended parameter sets.

## Risk Assessment

**LOW to MEDIUM.** The cycle-2 fixes are present and mostly correct, and the prior seven fixes did not regress. Remaining risk is concentrated in test proof strength around real PowerShell parameter binding for menu-generated splats, not in the core design.

---

## Consensus Summary

Single-reviewer cycle (Codex only). Consensus section reflects Codex's findings; no cross-reviewer agreement available.

### Agreed Strengths

- All 3 cycle-2 fixes verified as RESOLVED with concrete plan-file:line evidence
- No regressions of the 7 cycle-1 fixes
- Per-call source heuristic correctly prefers menu marker > caller-supplied password > config
- `Set-AdmanLocalUser` `PasswordSource` correctly bound to 'Reset' parameter set only
- `Failure` audit spelling now aligned with `Write-AdmanAudit` ValidateSet

### Agreed Concerns

- **1 NEW MEDIUM severity issue**: Phase-level menu contract test proves "all keys exist" via `(Get-Command <Verb>).Parameters.Keys` introspection, but does NOT prove "PowerShell can bind every menu-produced splat" — parameter-set binding errors can still throw even when every key is declared. Particularly relevant for `Set-AdmanLocalUser` Enable/Disable entries using `FixedParameters`.
- **1 NEW LOW severity issue**: `Set-AdmanLocalUser` reset-source behavior is internally ambiguous for direct callers — behavior text says "sources the password per D-05" but action text says throw when no `-Password` is supplied. Inconsistent with `Set-AdmanUserPassword` D-05 sourcing.

### Divergent Views

N/A — single reviewer.

---

## Verification coverage

Source-grounding pass performed against the **grep** authority. All file paths and existing function symbols cited by the plans were verified against the repo. No MISSING symbols detected among pre-existing code.

**Authority:** `grep` (via `gsd_run drift-guard authority --raw`)

**Symbols verified (file paths):** 22/22 — all files listed in `files_modified` and `read_first` blocks exist.

**Symbols verified (existing functions):**
- `Invoke-AdmanMutation` (Private/Safety/Invoke-AdmanMutation.ps1:34)
- `Resolve-AdmanTarget` (Private/Safety/Resolve-AdmanTarget.ps1:26)
- `Test-AdmanTargetAllowed` (Private/Safety/Test-AdmanTargetAllowed.ps1:35)
- `Confirm-AdmanAction` (Private/Safety/Confirm-AdmanAction.ps1:34)
- `Get-AdmanAllowedWriteVerbs` (Private/Safety/AdmanWriteVerbs.ps1:19)
- `Assert-AdmanBulkPolicy` (Private/Safety/Assert-AdmanBulkPolicy.ps1:16)
- `Write-AdmanAudit` (Private/Audit/Write-AdmanAudit.ps1:30)
- `Test-AdmanConfigValid`, `Initialize-AdmanConfig` (Private/Config/Initialize-AdmanConfig.ps1:68, 169)
- `ConvertTo-AdmanNormalizedDn` (Private/Utility/ConvertTo-AdmanNormalizedDn.ps1:19)
- `Escape-AdmanAdFilterLiteral` (Private/Utility/Escape-AdmanAdFilterLiteral.ps1:37)
- `Escape-AdmanLdapFilterValue` (Private/Safety/Escape-AdmanLdapFilterValue.ps1:22)
- `Get-AdmanMenuDefinition` (Private/Menu/Get-AdmanMenuDefinition.ps1:33)
- `Read-AdmanActionParams` (Private/Menu/Read-AdmanActionParams.ps1:33)
- `Start-Adman` (Public/Start-Adman.ps1:39)
- 9 existing `Adman.AD.Write.*` wrappers (Private/AD/Adman.AD.Write.ps1:23-148)

**Source-grounding evidence for new findings:**
- `Start-Adman` dispatches via `& $Verb @params` (Public/Start-Adman.ps1:134). Confirms the menu-splat contract is real and the cycle-2 fix mechanism (declared `<name>Source` parameters on verbs) is necessary and sufficient at the dispatch layer.
- `Write-AdmanAudit` ValidateSet is `'PENDING', 'Success', 'Failure', 'Refused', 'Cancelled'` — `'Failed'` is NOT accepted (Private/Audit/Write-AdmanAudit.ps1:37). Confirms cycle-2 MEDIUM #2 fix is correctly aligned.
- `Read-AdmanActionParams` foreach loop at line 44 confirmed — the Type='GeneratedPassword' dispatch is new this phase.
- `Get-AdmanMenuDefinition` entries currently have only Label/Verb/PromptSpec/Properties (4 fields). Confirms FixedParameters is a new 5th field this phase introduces.

**Symbols excluded (artifacts this phase produces):** All `Adman.Local.Write.*` wrappers, `Resolve-AdmanCreateTarget`, `Resolve-AdmanLocalTarget`, `Resolve-AdmanGroup`, `Test-AdmanLocalTargetAllowed`, `Test-AdmanGroupAllowed`, `Invoke-AdmanLocalMutation`, `New-AdmanRandomPassword`, `Test-AdmanPasswordComplexity`, `Get-AdmanCsprngIndex`, `Adman.AD.Write.New-ADUser`, `Get-AdmanBannedLocalWriteVerbs`, all Public verb names (`New-AdmanUser`, `Disable-AdmanUser`, etc.), all new config keys (`security.passwordSource`, etc.), all new test files, the `FixedParameters` menu field, the GeneratedPassword Type dispatch, the `<name>Source` parameters (`AccountPasswordSource`, `NewPasswordSource`, `PasswordSource`).

**UNCHECKABLE items:**
- Specific line numbers cited in `read_first` blocks (e.g., "Confirm-AdmanAction.ps1 line 45", "Invoke-AdmanMutation.ps1 lines 48-112") — line numbers shift as files are edited; the symbolic reference is what matters and the functions exist.
- Behavior claims about Phase 0/1 invariants (e.g., "the 00-05 writer already supports non-Success outcomes") — verified at the schema level (`ValidateSet` includes `'Failure'` at Write-AdmanAudit.ps1:37), but the *gate-side* emission of `Failure` is a code change this phase must make.
- The Spike 004 recipe line range (lines 37-92 of Invoke-Spike.ps1) — file exists; exact line range not re-verified against the recipe content.
- Whether the menu-splat contract tests (02-02 Test 13, 02-04 Tests 12/13, 02-06 Test 9) actually catch parameter-set binding errors vs. just unknown-parameter errors — this is the substance of the new MEDIUM concern; the test as described introspects `(Get-Command <Verb>).Parameters.Keys` which proves "key is declared" but not "key combination binds to a unique parameter set".

**Severity classification (via `gsd_run drift-guard severity`):**
- VERIFIED → severity:none, hardBlock:false
- MISSING → severity:needs-acknowledgement, hardBlock:false
- UNCHECKABLE → severity:INFO, hardBlock:false

No MISSING symbols. No hardBlock. Plan may proceed once Codex's cycle-3 MEDIUM concern (menu contract test does not prove parameter-set binding) is incorporated.
