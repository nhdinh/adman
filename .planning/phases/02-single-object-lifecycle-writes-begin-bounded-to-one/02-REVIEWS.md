---
phase: 02
reviewers: [codex]
reviewed_at: 2026-07-15T19:57:55Z
plans_reviewed: [02-01-PLAN.md, 02-02-PLAN.md, 02-03-PLAN.md, 02-04-PLAN.md, 02-05-PLAN.md, 02-06-PLAN.md]
---

# Cross-AI Plan Review — Phase 02

## Codex Review

## Summary

The phase split is directionally strong: Plan 02-01 centralizes the risky shared gate work, and the later plans keep most Public verbs thin. The main risks are implementation-order and mechanism gaps. Several plans rely on behavior the current repo does not yet have: failure outcome auditing around wrapper throws, per-verb `-Server` override handling, manifest exports during Wave 2 tests, fixed menu parameters, and updated existing config fixtures. These are fixable, but they should be addressed in the plans before execution because they affect testability and safety guarantees.

## Strengths

- The plan correctly builds on the existing gate shape. `Invoke-AdmanMutation` already has the fixed resolve → allow → confirm → PENDING audit → wrapper → OUTCOME audit order at [Private/Safety/Invoke-AdmanMutation.ps1](C:/Users/nhdinh/dev/adman/Private/Safety/Invoke-AdmanMutation.ps1:50).
- The existing AD wrappers already follow the intended one-wrapper-per-write pattern with `SupportsShouldProcess`, pinned `-Server`, `-WhatIf`, `-Confirm:$false`, and `-ErrorAction Stop`, e.g. [Private/AD/Adman.AD.Write.ps1](C:/Users/nhdinh/dev/adman/Private/AD/Adman.AD.Write.ps1:23).
- The audit writer already supports `Failure` as a result value, so the desired failure-audit model has a schema foothold at [Private/Audit/Write-AdmanAudit.ps1](C:/Users/nhdinh/dev/adman/Private/Audit/Write-AdmanAudit.ps1:37).
- The menu architecture is a good fit for Phase 2: entries are data-driven in `Get-AdmanMenuDefinition`, and dispatch is generic via `& $Verb @params` at [Public/Start-Adman.ps1](C:/Users/nhdinh/dev/adman/Public/Start-Adman.ps1:133).
- The safety guard is already strong and testable. The banned AD write set includes `New-ADUser`, group membership writes, and hard delete at [rules/AdmanSafetyRules.psm1](C:/Users/nhdinh/dev/adman/rules/AdmanSafetyRules.psm1:21).

## Concerns

- **HIGH: Failure outcome auditing is assumed but not planned into the gate.**
  Plans 02-01 and 02-04 repeatedly rely on "wrapper throws → OUTCOME audit records `Failed`," especially for create TOCTOU closure. The current gate writes PENDING, invokes the wrapper, then writes only `Success`; there is no `try/catch` around the wrapper call at [Private/Safety/Invoke-AdmanMutation.ps1](C:/Users/nhdinh/dev/adman/Private/Safety/Invoke-AdmanMutation.ps1:92). If `New-ADUser`, `New-LocalUser`, or any wrapper throws, the current mechanism leaves a PENDING orphan and never writes `Failure`.

- **HIGH: Wave 2 Public verb tests will likely fail because exports are deferred to Plan 02-06.**
  Existing tests import the manifest before calling public commands at [tests/Find.User.Tests.ps1](C:/Users/nhdinh/dev/adman/tests/Find.User.Tests.ps1:53), then invoke exported functions directly at [tests/Find.User.Tests.ps1](C:/Users/nhdinh/dev/adman/tests/Find.User.Tests.ps1:65). The manifest has an explicit `FunctionsToExport` list at [adman.psd1](C:/Users/nhdinh/dev/adman/adman.psd1:53). Plans 02-02 through 02-05 add Public files but intentionally defer manifest exports to 02-06, so those new commands may not be visible when their own tests run.

- **HIGH: `Unlock-AdmanUser`'s PDCe override will collide with the existing wrapper unless the wrapper is changed.**
  Plan 02-02 passes `$Parameters['Server']` into the gate for PDCe unlock. The current `Adman.AD.Write.Unlock-ADAccount` wrapper already supplies `-Server $script:Config.DC` and then splats `@Parameters` at [Private/AD/Adman.AD.Write.ps1](C:/Users/nhdinh/dev/adman/Private/AD/Adman.AD.Write.ps1:115). Passing `Server` in `$Parameters` will duplicate the parameter and fail unless Plan 02-01 explicitly updates that wrapper too.

- **HIGH: Password reset parameters will be splatted into the wrong AD cmdlet.**
  Plan 02-02 sends `ChangePasswordAtLogon` with the `Set-ADAccountPassword` gate call. The current wrapper blindly splats `@Parameters` into `Set-ADAccountPassword` at [Private/AD/Adman.AD.Write.ps1](C:/Users/nhdinh/dev/adman/Private/AD/Adman.AD.Write.ps1:101). `ChangePasswordAtLogon` belongs on `Set-ADUser`, not `Set-ADAccountPassword`, so this needs a wrapper-level split: set password first, then call `Set-ADUser -ChangePasswordAtLogon`.

- **MEDIUM: Adding required `security` config keys will break existing fixture configs unless the plan updates them.**
  `Test-AdmanConfigValid` enforces every top-level schema `required` key at [Private/Config/Initialize-AdmanConfig.ps1](C:/Users/nhdinh/dev/adman/Private/Config/Initialize-AdmanConfig.ps1:89). Plan 02-01 adds top-level `security`, but many existing test config builders omit it, e.g. [tests/Config.Load.Tests.ps1](C:/Users/nhdinh/dev/adman/tests/Config.Load.Tests.ps1:55). Plan 02-01 does not list the existing config test files as modified, so the full suite will likely regress.

- **MEDIUM: Plan 02-06 says the dispatcher injects fixed `-Enable` / `-Disable` switches, but no mechanism exists or is specified.**
  The current menu contract only has `Label`, `Verb`, `PromptSpec`, and `Properties` at [Private/Menu/Get-AdmanMenuDefinition.ps1](C:/Users/nhdinh/dev/adman/Private/Menu/Get-AdmanMenuDefinition.ps1:10). `Read-AdmanActionParams` returns only parameters declared in `PromptSpec` at [Private/Menu/Read-AdmanActionParams.ps1](C:/Users/nhdinh/dev/adman/Private/Menu/Read-AdmanActionParams.ps1:27), and `Start-Adman` dispatches exactly those params at [Public/Start-Adman.ps1](C:/Users/nhdinh/dev/adman/Public/Start-Adman.ps1:119). The plan needs a `FixedParameters` field or equivalent dispatcher change.

- **LOW: Plan 02-06 verification under-tests the new `Start.Adman.Tests.ps1` in Task 1.**
  The task creates `tests/Start.Adman.Tests.ps1`, but its immediate verify command only names `tests/Menu.Tests.ps1` and `tests/Module.Manifest.Tests.ps1`. The later full-suite gate catches it, but the task-level feedback loop should include the new test file.

## Suggestions

- Add an explicit gate change in Plan 02-01: wrap the raw wrapper invocation in `try/catch`, write `Write-AdmanAudit -Result 'Failure' -Reason $_.Exception.Message`, then rethrow or return a failure result. Mirror this in `Invoke-AdmanLocalMutation`.
- Move manifest export updates into each Public verb plan, or have those tests invoke commands inside module scope deliberately. Given existing test style, updating `adman.psd1` per Wave 2 plan is cleaner.
- Update `Adman.AD.Write.Unlock-ADAccount` to compute `$server = $Parameters['Server'] ?? $script:Config.DC`, remove `Server` from the splat, and pass one `-Server`.
- Update `Adman.AD.Write.Set-ADAccountPassword` to strip non-cmdlet keys like `Unlock` and `ChangePasswordAtLogon`; after a successful reset, call `Set-ADUser -ChangePasswordAtLogon <bool>` when requested, and optionally `Unlock-ADAccount`.
- Add existing config fixture updates to Plan 02-01's file list, especially `tests/Config.*.Tests.ps1` and any helper config builders.
- For menu fixed switches, add a small explicit menu-entry field such as `FixedParameters = @{ Enable = $true }`, merge it with prompted params before `& $Verb @params`, and test that separator entries remain non-selectable.

## Risk Assessment

- **plan-00.md: HIGH risk.** It is the right architectural plan, but it carries the most safety-critical gaps: no failure outcome auditing in the current gate, potential config fixture regressions, and wrapper parameter handling assumptions.
- **plan-01.md: HIGH risk.** User lifecycle is valuable and well scoped, but password reset and PDCe unlock currently depend on wrapper behavior that will fail unless Plan 02-01 is expanded.
- **plan-02.md: MEDIUM risk.** Computer lifecycle is mostly thin reuse. Main risk is `Set-ADAccountPassword -Reset` relying on the same wrapper splat hygiene and guidance return behavior.
- **plan-03.md: MEDIUM-HIGH risk.** The local gate design is solid, but create/delete correctness depends on the missing failure-audit mechanism and on careful LocalAccounts wrapper splat cleanup.
- **plan-04.md: LOW-MEDIUM risk.** Group membership plan is comparatively clean because the hard policy work is in Plan 02-01. Risk is mostly ensuring dual-resolution audit and wrapper parameter swapping are implemented exactly.
- **plan-05.md: MEDIUM risk.** Menu integration is straightforward, but fixed parameter injection and task-level test coverage need tightening.

Overall phase risk: **HIGH until the gate failure-audit path, manifest ordering, and wrapper parameter handling are corrected**. After those plan edits, the phase becomes **MEDIUM**: broad but coherent, with good safety and test scaffolding.

---

## Consensus Summary

Single-reviewer cycle (Codex only). Consensus section reflects Codex's findings; no cross-reviewer agreement available.

### Agreed Strengths

- Gate extension strategy (single cross-cutting plan) prevents file-collision between verb plans
- Existing wrappers, audit writer, and AST guard provide a solid foundation to extend
- Menu architecture (data-driven + generic dispatch) absorbs new write entries without a new engine

### Agreed Concerns

- **4 HIGH severity issues** all rooted in the same pattern: plans assume mechanism behavior that doesn't yet exist in the repo (failure-audit try/catch, manifest export timing, wrapper Server/ChangePasswordAtLogon handling)
- **2 MEDIUM severity issues** around config fixture regression and menu fixed-parameter mechanism
- **1 LOW severity issue** on task-level test verification scope

### Divergent Views

N/A — single reviewer.

---

## Verification coverage

Source-grounding pass performed against the grep authority. All file paths and existing function symbols cited by the plans were verified against the repo. No MISSING symbols detected among pre-existing code.

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

**Symbols excluded (artifacts this phase produces):** All `Adman.Local.Write.*` wrappers, `Resolve-AdmanCreateTarget`, `Resolve-AdmanLocalTarget`, `Resolve-AdmanGroup`, `Test-AdmanLocalTargetAllowed`, `Test-AdmanGroupAllowed`, `Invoke-AdmanLocalMutation`, `New-AdmanRandomPassword`, `Test-AdmanPasswordComplexity`, `Get-AdmanCsprngIndex`, `Adman.AD.Write.New-ADUser`, `Get-AdmanBannedLocalWriteVerbs`, all Public verb names (`New-AdmanUser`, `Disable-AdmanUser`, etc.), all new config keys (`security.passwordSource`, etc.), all new test files.

**UNCHECKABLE items:**
- Specific line numbers cited in `read_first` blocks (e.g., "Confirm-AdmanAction.ps1 line 45", "Invoke-AdmanMutation.ps1 lines 48-112") — line numbers shift as files are edited; the symbolic reference is what matters and the functions exist.
- Behavior claims about Phase 0/1 invariants (e.g., "the 00-05 writer already supports non-Success outcomes") — verified at the schema level (`ValidateSet` includes `'Failure'` at Write-AdmanAudit.ps1:37), but the *gate-side* emission of `Failure` is a code change this phase must make (covered by Codex HIGH #1).
- The Spike 004 recipe line range (lines 37-92 of Invoke-Spike.ps1) — file exists; exact line range not re-verified against the recipe content.

No MISSING symbols. No hardBlock. Plan may proceed once Codex's HIGH concerns are incorporated.
