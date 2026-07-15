---
phase: 02
reviewers: [codex]
reviewed_at: 2026-07-15T20:30:10Z
plans_reviewed: [02-01-PLAN.md, 02-02-PLAN.md, 02-03-PLAN.md, 02-04-PLAN.md, 02-05-PLAN.md, 02-06-PLAN.md]
cycle: 2
---

# Cross-AI Plan Review — Phase 02 (Cycle 2)

## Codex Review

## Summary

The revised Phase 02 plan set is much stronger than cycle 1. The seven prior issues are materially addressed in the plan text, with tests added around the critical paths. I would mark the cycle-1 fixes resolved. The main new risk is in Plan 02-06's menu/password wiring: the prompt parameter names and generated `*Source` markers do not line up with the Public verb signatures, so several menu password actions can fail even though direct senior calls work.

## Strengths

- Plan 02-01 now puts failure-outcome auditing at the actual enforcement point: the gate wrapper call is wrapped and writes `Result 'Failure'` before rethrowing (`02-01-PLAN.md:183`, `02-01-PLAN.md:188`, `02-01-PLAN.md:223`, `02-01-PLAN.md:226`).
- Manifest export sequencing is fixed. Wave 2 plans now update `adman.psd1` in the same plan that creates each Public verb, instead of deferring exports to 02-06 (`02-02-PLAN.md:109`, `02-03-PLAN.md:89`, `02-03-PLAN.md:118`, `02-04-PLAN.md:99`, `02-04-PLAN.md:127`, `02-05-PLAN.md:89`).
- The Set-ADAccountPassword wrapper fix is correctly placed in Plan 02-01, where the actual bad splat exists today at `Private/AD/Adman.AD.Write.ps1:101` (`02-01-PLAN.md:185`, `02-01-PLAN.md:188`).
- The menu `FixedParameters` fix is now explicit and tested, matching the current dispatcher gap at `Public/Start-Adman.ps1:119` and `Public/Start-Adman.ps1:134` (`02-06-PLAN.md:102`, `02-06-PLAN.md:106`, `02-06-PLAN.md:109`).

## Concerns

- **HIGH: Menu password PromptSpec names and generated source markers do not match Public verb signatures.**
  Plan 02-06 says menu entries use a `Password` prompt for `New-AdmanUser` and `Set-AdmanUserPassword` (`02-06-PLAN.md:106`), while those verbs are planned with `AccountPassword` and `NewPassword` parameters (`02-02-PLAN.md:109`, `02-02-PLAN.md:146`). `Read-AdmanActionParams` will also add `${name}Source` markers (`02-06-PLAN.md:106`), but the Public verb parameter lists do not include `AccountPasswordSource`, `NewPasswordSource`, or `PasswordSource` (`02-02-PLAN.md:109`, `02-02-PLAN.md:146`, `02-04-PLAN.md:99`). Since `Start-Adman` dispatches via splat today (`Public/Start-Adman.ps1:134`), wrong or extra keys will produce "parameter cannot be found" failures from the menu path. Direct-call tests may pass while MENU-04 is broken.

- **MEDIUM: Failure result naming is inconsistent between `Failure` and `Failed`.**
  The current audit writer only accepts `Failure`, not `Failed` (`Private/Audit/Write-AdmanAudit.ps1:37`). The revised fix correctly uses `Failure` in key action text (`02-01-PLAN.md:188`, `02-01-PLAN.md:226`), but several behavior/threat lines still say `Result='Failed'` (`02-01-PLAN.md:222`, `02-01-PLAN.md:304`, `02-02-PLAN.md:146`, `02-04-PLAN.md:95`). This is likely documentation drift, but it can mislead implementers or produce tests expecting the wrong value.

- **MEDIUM: New-ADUser CN uniqueness pre-flight may over-refuse because the CN search lacks `-SearchScope OneLevel`.**
  Plan 02-01 checks `cn -eq '<escaped>'` with `-SearchBase <ParentOuDn>` (`02-01-PLAN.md:188`). AD requires CN uniqueness within the immediate parent container, not every descendant OU. Without an explicit one-level scope, this can refuse a valid create because a same-CN object exists in a child OU.

## Cycle 1 Fix Verification

- **HIGH #1: Gate failure-audit try/catch missing — RESOLVED.**
  AD gate fix is specified at `02-01-PLAN.md:183` and implemented action text at `02-01-PLAN.md:188`. Local gate mirror is specified at `02-01-PLAN.md:223` and `02-01-PLAN.md:226`.

- **HIGH #2: Wave 2 manifest export sequencing — RESOLVED.**
  User verbs export in `02-02-PLAN.md:109` and `02-02-PLAN.md:146`; computer verbs in `02-03-PLAN.md:89` and `02-03-PLAN.md:118`; local verbs in `02-04-PLAN.md:99` and `02-04-PLAN.md:127`; group verbs in `02-05-PLAN.md:89`. Plan 02-06 re-verifies rather than owning the first export (`02-06-PLAN.md:100`, `02-06-PLAN.md:106`).

- **HIGH #3: Unlock-ADAccount Server-splat collision — RESOLVED.**
  Plan 02-01 requires computing `$server`, stripping `Server` from the splat, and passing one `-Server` (`02-01-PLAN.md:184`, `02-01-PLAN.md:188`).

- **HIGH #4: ChangePasswordAtLogon routed to wrong cmdlet — RESOLVED.**
  Plan 02-01 requires stripping `ChangePasswordAtLogon` before `Set-ADAccountPassword` and applying it with `Set-ADUser` after reset (`02-01-PLAN.md:185`, `02-01-PLAN.md:188`).

- **MEDIUM #5: Existing config fixtures need `security` block — RESOLVED.**
  Plan 02-01 lists all four config test fixtures to update (`02-01-PLAN.md:134`-`02-01-PLAN.md:137`) and explicitly adds the block in action text (`02-01-PLAN.md:151`).

- **MEDIUM #6: FixedParameters menu field missing — RESOLVED.**
  Plan 02-06 adds `FixedParameters`, injects `Enable=$true` / `Disable=$true`, and tests merge order/no collisions (`02-06-PLAN.md:102`, `02-06-PLAN.md:103`, `02-06-PLAN.md:106`).

- **LOW #7: `Start.Adman.Tests.ps1` missing from verify command — RESOLVED.**
  Plan 02-06 now includes the file in `files_modified` (`02-06-PLAN.md:12`), task files (`02-06-PLAN.md:86`), and the verify command (`02-06-PLAN.md:109`).

## Suggestions

- In Plan 02-06, make every password PromptSpec `Name` exactly match the target Public parameter: `AccountPassword`, `NewPassword`, or `Password`.
- Add hidden optional Public parameters for the source markers, e.g. `AccountPasswordSource`, `NewPasswordSource`, `PasswordSource`, or have `Start-Adman` strip marker keys before splatting and pass source another way.
- Normalize every plan reference from `Failed` to `Failure` to match `Write-AdmanAudit`'s current `ValidateSet`.
- Add `-SearchScope OneLevel` to the CN uniqueness pre-flight under the parent OU.
- Make the group dual-resolution path explicitly overwrite or clone `$Parameters['GroupIdentity'] = $group.DistinguishedName` before wrapper invocation, so execution uses the resolved group DN that preview/audit named.

## Risk Assessment

Overall risk is **MEDIUM**. The safety-critical cycle-1 issues are now covered at the right layer, and the test plan is broad. The remaining menu/password mismatch is high-impact but localized to Plan 02-06 and fixable before execution. Once that wiring is corrected and `Failure` naming is normalized, the phase plan is coherent enough to execute.

---

## Consensus Summary

Single-reviewer cycle (Codex only). Consensus section reflects Codex's findings; no cross-reviewer agreement available.

### Agreed Strengths

- All 7 cycle-1 fixes verified as RESOLVED with concrete plan-file:line evidence
- Failure-outcome auditing now correctly placed at the gate enforcement point (both AD and local gates)
- Manifest export sequencing fixed by landing exports in the same plan as each Wave 2 verb
- FixedParameters mechanism explicit and tested for menu dispatcher

### Agreed Concerns

- **1 NEW HIGH severity issue**: Menu password PromptSpec name mismatch — `Password` vs `AccountPassword`/`NewPassword`, plus unhandled `${name}Source` markers, will break menu-path password actions (MENU-04) even though direct calls work
- **2 NEW MEDIUM severity issues**: `Failure`/`Failed` documentation drift; missing `-SearchScope OneLevel` on CN uniqueness pre-flight

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
- `Write-AdmanAudit` ValidateSet is `'PENDING', 'Success', 'Failure', 'Refused', 'Cancelled'` — `'Failed'` is NOT accepted (Private/Audit/Write-AdmanAudit.ps1:37). Confirms MEDIUM #2.
- `Start-Adman` dispatches via `& $Verb @params` (Public/Start-Adman.ps1:134). Confirms HIGH #1 mechanism — splatting wrong/extra keys will throw "parameter cannot be found".
- `Get-AdmanMenuDefinition` entries currently have only Label/Verb/PromptSpec/Properties (Private/Menu/Get-AdmanMenuDefinition.ps1:10-15). Confirms FixedParameters is a new field this phase introduces.
- `Read-AdmanActionParams` has no Type dispatch today (Private/Menu/Read-AdmanActionParams.ps1:33). Confirms the GeneratedPassword Type handling is new this phase.

**Symbols excluded (artifacts this phase produces):** All `Adman.Local.Write.*` wrappers, `Resolve-AdmanCreateTarget`, `Resolve-AdmanLocalTarget`, `Resolve-AdmanGroup`, `Test-AdmanLocalTargetAllowed`, `Test-AdmanGroupAllowed`, `Invoke-AdmanLocalMutation`, `New-AdmanRandomPassword`, `Test-AdmanPasswordComplexity`, `Get-AdmanCsprngIndex`, `Adman.AD.Write.New-ADUser`, `Get-AdmanBannedLocalWriteVerbs`, all Public verb names (`New-AdmanUser`, `Disable-AdmanUser`, etc.), all new config keys (`security.passwordSource`, etc.), all new test files, the `FixedParameters` menu field, the GeneratedPassword Type dispatch.

**UNCHECKABLE items:**
- Specific line numbers cited in `read_first` blocks (e.g., "Confirm-AdmanAction.ps1 line 45", "Invoke-AdmanMutation.ps1 lines 48-112") — line numbers shift as files are edited; the symbolic reference is what matters and the functions exist.
- Behavior claims about Phase 0/1 invariants (e.g., "the 00-05 writer already supports non-Success outcomes") — verified at the schema level (`ValidateSet` includes `'Failure'` at Write-AdmanAudit.ps1:37), but the *gate-side* emission of `Failure` is a code change this phase must make (covered by Codex cycle-1 HIGH #1, now RESOLVED in plan text).
- The Spike 004 recipe line range (lines 37-92 of Invoke-Spike.ps1) — file exists; exact line range not re-verified against the recipe content.
- The exact menu PromptSpec `Name` values that Plan 02-06 will use for each password entry — the plan text says "Password with Type='GeneratedPassword'" but does not pin the exact `Name` key per entry; the HIGH finding assumes the worst case (literal `Password`) and the fix requires per-verb alignment.

**Severity classification (via `gsd_run drift-guard severity`):**
- VERIFIED → severity:none, hardBlock:false
- MISSING → severity:needs-acknowledgement, hardBlock:false
- UNCHECKABLE → severity:INFO, hardBlock:false

No MISSING symbols. No hardBlock. Plan may proceed once Codex's cycle-2 HIGH concern (menu password PromptSpec name mismatch) is incorporated.
