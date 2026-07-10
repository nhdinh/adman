---
phase: 00-foundation-safety-harness
plan: 01
subsystem: foundation
tags: [powershell, powershell-5.1, pester-6, psscriptanalyzer, psframework, active-directory, safe-08, lint, ast-guard, offline-mocks]

# Dependency graph
requires: []   # wave 1; depends_on: [] in PLAN
provides:
  - "Load-bearing module skeleton: adman.psd1 (explicit FunctionsToExport, exact-pinned PSFramework RequiredVersion, Desktop-only CompatiblePSEditions) + adman.psm1 (ErrorActionPreference=Stop, dot-source Private/** then Public/**, side-effect-free import)"
  - "SAFE-08 export boundary: only Initialize-Adman/Start-Adman exported; the single mutation gate Invoke-AdmanMutation is deliberately ABSENT from exports (enforced by tests)"
  - "Static-analysis spine: PSScriptAnalyzerSettings.psd1 (7 CLAUDE.md rules incl. PSUseShouldProcessForStateChangingFunctions) + custom rule rules/AdmanSafetyRules.psm1 with a single-sourced banned-verb set"
  - "Test harness: Pester 6 config + offline AD/CIM/remoting mocks (zero network, T-00-11) + AST guard test that proves no Public/ verb calls a banned AD write cmdlet directly"
  - "Build-time re-verification of PSFramework 1.14.457 provenance/signatures (A1, T-00-SC) with the human approval gate preserved"
affects: [00-02, 00-03, phase-01-menu, all-mutation-verbs, phase-05-ci-matrix]

# Tech tracking
tech-stack:
  added:
    - "Pester 6.0.0 (dev/test; CurrentUser) — profiler-based coverage schema declared"
    - "PSScriptAnalyzer 1.25.0 (dev/lint; CurrentUser) — repo-wide recurse gate + custom rule"
    - "PSFramework 1.14.457 (declared via RequiredVersion in adman.psd1; REAL install pending human approval gate T-00-SC)"
  patterns:
    - "Explicit FunctionsToExport (never '*') == the exact set adman.psm1 passes to Export-ModuleMember (drift => SAFE-08 bypass; test-guarded)"
    - "Single non-exported mutation gate (Invoke-AdmanMutation, Private/, not exported) — boundary established here; body lands in 00-02"
    - "Single-sourced banned-verb set ($script:AdmanBannedWriteVerbs) drives BOTH the PSSA custom rule and the Pester AST guard (no divergent lists)"
    - "Scope-gated custom rule: real module Public\\ tree only, tests\\ excluded by path (positive-control fixtures are lint-excluded yet directly testable)"
    - "Root-AST-only emission (PSScriptAnalyzer invokes a ScriptBlockAst rule once per node; guard emits only when $Ast.Parent -eq $null to avoid duplicate diagnostics)"
    - "Offline alias resolution via Get-Alias (in-session table only) — the guard NEVER auto-loads the real RSAT ActiveDirectory module"
    - "Exact-pin via RequiredVersion (not ModuleVersion, which is only a minimum floor) for PSFramework"
    - "Honest dual-edition claim: CompatiblePSEditions=@('Desktop') until the Phase 5 CI matrix passes on 7.6"

key-files:
  created:
    - ".planning/phases/00-foundation-safety-harness/00-01-PSFramework-verified.md"
    - "adman.psd1"
    - "adman.psm1"
    - "Public/Initialize-Adman.ps1"
    - "Public/Start-Adman.ps1"
    - "PSScriptAnalyzerSettings.psd1"
    - "rules/AdmanSafetyRules.psm1"
    - "tests/PesterConfiguration.psd1"
    - "tests/Mocks/ActiveDirectory.psm1"
    - "tests/Module.Manifest.Tests.ps1"
    - "tests/Harness.Tests.ps1"
    - "tests/Safety.Gate.Tests.ps1"
    - "tests/Fixtures/Public/BadDirectWrite.ps1"
    - "tests/Fixtures/Private/GoodWrapper.ps1"
    - "tests/Fixtures/Public/DynamicInvoke.ps1"
  modified:
    - ".claude/CLAUDE.md"
    - "tests/Module.Manifest.Tests.ps1"

key-decisions:
  - "D-01 reconciliation: PSFramework 1.14.457 IS adopted in Phase 0 for config + diagnostic/ops logging; the audit writer stays hand-rolled/synchronous (the audit exception). .claude/CLAUDE.md edited (2 rows) so downstream agents read ONE consistent story — no stale 'defer PSFramework to v2' framing (C2-M2)."
  - "CompatiblePSEditions=@('Desktop') + PowerShellVersion='5.1' until the Phase 5 CI matrix passes on 7.6 — refuse to claim dual-edition support before it is proven."
  - "PSFramework pinned with EXACT RequiredVersion='1.14.457' (ModuleVersion is only a minimum floor); ActiveDirectory is NOT in RequiredModules (RSAT is a prerequisite, never bundled)."
  - "Banned-verb set is a single source imported by both guards (SAFE-08/09; includes Remove-ADObject hard-delete with no wrapper)."
  - "Custom PSSA rule emits diagnostics on the root AST only (Parent-null guard) — one record per offending line, no per-nested-block duplicates."
  - "Alias resolution uses Get-Alias (no module auto-load) instead of Get-Command, so the lint/guard path never pulls in RSAT as a side effect (T-00-11)."

patterns-established:
  - "Every state-changing function declares [CmdletBinding(SupportsShouldProcess)] (enforced by PSUseShouldProcessForStateChangingFunctions); read stubs and pure helpers do not."
  - "Guards parse with [System.Management.Automation.Language.Parser] and detect banned calls via CommandAst.GetCommandName() with an L304 fallback (CommandElements[0].Extent.Text + token-grep for Invoke-Expression / '& $cmd')."
  - "All AD/CIM/remoting cmdlets are mocked with canned PSCustomObjects tagged AdmanMock.* so tests can prove the mock — not a live domain — answered (project constraint)."

requirements-completed: [MENU-05, SAFE-08]

# Coverage metadata (#1602) — deterministic UAT routing
coverage:
  - id: D1
    description: "Module loads on Windows PowerShell 5.1 with ErrorActionPreference=Stop and dot-sources Private/** then Public/**"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Module.Manifest.Tests.ps1#imports on Windows PowerShell 5.1 and sets ErrorActionPreference=Stop inside the module scope"
        status: pass
    human_judgment: false
  - id: D2
    description: "Explicit FunctionsToExport equals the loader's Export-ModuleMember set and excludes Invoke-AdmanMutation (no SAFE-08 bypass)"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Module.Manifest.Tests.ps1#exports exactly the manifest FunctionsToExport and does NOT export the gate (Invoke-AdmanMutation)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Manifest exact-pins PSFramework (RequiredVersion) and excludes ActiveDirectory and the export wildcard"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Module.Manifest.Tests.ps1#manifest pins PSFramework (exact) and excludes ActiveDirectory and the export wildcard"
        status: pass
    human_judgment: false
  - id: D4
    description: "Module import is side-effect-free (no domain touch; real RSAT ActiveDirectory not loaded)"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Module.Manifest.Tests.ps1#import is side-effect-free (no domain touch; ActiveDirectory not loaded)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Repo-wide PSScriptAnalyzer lint is clean with PSUseShouldProcessForStateChangingFunctions enabled"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Harness.Tests.ps1#lint is clean with PSUseShouldProcessForStateChangingFunctions enabled (SAFE-01)"
        status: pass
      - kind: other
        ref: "Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1 -> 0 findings"
        status: pass
    human_judgment: false
  - id: D6
    description: "Custom SAFE-08 rule flags a direct AD write in a Public/ fixture but not a Private/ wrapper; AST guard over real Public/ is clean"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Harness.Tests.ps1#custom rule flags a direct AD write in a Public fixture but not a Private wrapper (SAFE-08)"
        status: pass
      - kind: unit
        ref: "tests/Safety.Gate.Tests.ps1#positive control fixture IS flagged (guard fires)"
        status: pass
      - kind: unit
        ref: "tests/Safety.Gate.Tests.ps1#negative control (Private wrapper) is out of Public/ scope"
        status: pass
    human_judgment: false
  - id: D7
    description: "L304 token-grep flags a dynamic/Invoke-Expression AD write in a Public fixture"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Harness.Tests.ps1#token-grep flags a dynamic/Invoke-Expression AD write in a Public fixture (L304)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Offline AD/CIM/remoting mocks supply canned objects with zero network (no live domain)"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Harness.Tests.ps1#AD/CIM/remoting mocks supply canned objects with zero network"
        status: pass
    human_judgment: false
  - id: D9
    description: "PSFramework 1.14.457 provenance/signatures re-verified at build time; real install awaits explicit human approval"
    requirement: MENU-05
    verification:
      - kind: manual_procedural
        ref: ".planning/phases/00-foundation-safety-harness/00-01-PSFramework-verified.md (verdict [OK]; Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser)"
        status: unknown
    human_judgment: true
    rationale: "Package-legitimacy seam (T-00-SC): the first install of PSFramework requires explicit human approval/end-of-phase check. The re-verification artifact is machine-generated; the install itself is a deliberate human gate, not automatable."

# Metrics
duration: ~1h 5m recorded commit span (active execution longer across a context-resume)
completed: 2026-07-11
status: complete
---

# Phase 0 Plan 01: Foundation & Safety Harness Summary

**Load-bearing module skeleton with an explicit SAFE-08 export boundary plus a static-analysis spine (PSScriptAnalyzer custom rule + Pester AST guard over a single-sourced banned-verb set) and offline AD/CIM/remoting mocks — proven on Windows PowerShell 5.1 with a clean repo-wide lint and a 12/12 green test suite, while the PSFramework 1.14.457 install remains a deliberate human-approval gate.**

## Performance

- **Duration:** ~1h 5m recorded commit span (03:17→04:20 +07); active execution longer across a context-resume
- **Started:** 2026-07-10T20:17:08Z
- **Completed:** 2026-07-10T21:20:20Z
- **Tasks:** 3 (Task 1 read-only verification; Tasks 2 & 3 TDD)
- **Files modified:** 15 created, 2 modified

## Accomplishments

- Module skeleton that the safety spine hangs on: `adman.psd1` (explicit `FunctionsToExport`, exact-pinned `PSFramework` `RequiredVersion='1.14.457'`, `CompatiblePSEditions=@('Desktop')`, `PowerShellVersion='5.1'`, NO `ActiveDirectory` dependency) + `adman.psm1` (`$ErrorActionPreference='Stop'`, dot-sources `Private/**` then `Public/**`, side-effect-free import).
- SAFE-08 boundary enforced two independent ways from ONE source of truth: a PSScriptAnalyzer custom rule (lint gate) and a Pester AST guard, both driven by `Get-AdmanBannedWriteVerbs` over the real `Public/` tree — green, with the mutation gate `Invoke-AdmanMutation` provably NOT exported.
- Offline test foundation: `tests/Mocks/ActiveDirectory.psm1` stubs every Get/Set/Disable/Enable/Unlock/Move/New AD cmdlet plus CIM/remoting with canned `AdmanMock.*` objects — proven zero-network (no live domain, project constraint / T-00-11).
- PSFramework 1.14.457 re-verified at build time (provenance + signatures) with the human approval gate intact (verdict **[OK]**, install command printed, install NOT executed).
- `.claude/CLAUDE.md` reconciled to D-01 (two surgical row edits): PSFramework adopted in Phase 0 for config + diagnostic/ops logging; audit stays hand-rolled/synchronous.

## Task Commits

Each task was committed atomically; TDD tasks have RED → GREEN commits:

1. **Task 1: Re-verify PSFramework 1.14.457 signatures (read-only)** — `759d292` (docs)
2. **Task 2 RED: failing manifest/export-boundary tests** — `e41c4b4` (test)
3. **Task 2 GREEN: module skeleton with explicit export boundary** — `54e384d` (feat)
4. **Task 3 RED: failing harness + SAFE-08 AST-guard tests (+ fixtures)** — `5e170f0` (test)
5. **Deviation fix: side-effect assertion excludes the ActiveDirectory mock module** — `4dd8f23` (fix)
6. **Task 3 GREEN: Pester/PSScriptAnalyzer harness, SAFE-08 custom rule, offline AD mocks** — `1ff2926` (feat)

**Plan metadata (SUMMARY/STATE/ROADMAP/REQUIREMENTS):** committed next (docs).

## Files Created/Modified

- `adman.psd1` — manifest: explicit export list, exact PSFramework pin, Desktop-only, no AD dependency.
- `adman.psm1` — loader: `ErrorActionPreference='Stop'`, dot-source Private/** then Public/**, export by basename, side-effect-free.
- `Public/Initialize-Adman.ps1`, `Public/Start-Adman.ps1` — exported stubs (real bodies land in 00-03 / Phase 1); `SupportsShouldProcess` on the state-changing verbs.
- `PSScriptAnalyzerSettings.psd1` — 7 CLAUDE.md rules + `CustomRulePath`; documented forward-declared `PSAvoidUsingWriteHost` suppression (Phase-1 TUI) and fixtures scope note.
- `rules/AdmanSafetyRules.psm1` — single-sourced banned set, scope gate, pure AST detection (+ L304 token-grep), PSSA rule (root-AST-only emission), `Get-Alias`-based alias resolution (no RSAT auto-load).
- `tests/PesterConfiguration.psd1` — Pester 6 schema (Unit tag, profiler coverage → JaCoCo, JUnit results).
- `tests/Mocks/ActiveDirectory.psm1` — canned AD/CIM/remoting stubs, zero network.
- `tests/Module.Manifest.Tests.ps1`, `tests/Harness.Tests.ps1`, `tests/Safety.Gate.Tests.ps1` — behavior/AST tests (12/12 green).
- `tests/Fixtures/{Public/BadDirectWrite.ps1, Private/GoodWrapper.ps1, Public/DynamicInvoke.ps1}` — lint-clean positive/negative controls.
- `.planning/phases/00-foundation-safety-harness/00-01-PSFramework-verified.md` — build-time signature/provenance dump.
- `.claude/CLAUDE.md` — D-01 reconciliation (2 rows).

## Decisions Made

- **D-01 reconciliation (CLAUDE.md):** PSFramework 1.14.457 adopted in Phase 0 for config + diagnostic/ops logging; audit writer stays hand-rolled/synchronous. Two rows edited; no stale "defer PSFramework to v2" framing.
- **Honest edition claim:** `CompatiblePSEditions=@('Desktop')` + `PowerShellVersion='5.1'` until the Phase 5 CI matrix passes on 7.6.
- **Exact pin:** `RequiredVersion='1.14.457'` (not `ModuleVersion`, a floor). ActiveDirectory is a prerequisite, never a `RequiredModules` entry.
- **Single-sourced banned list** drives both guards; includes `Remove-ADObject` (SAFE-09 hard-delete, no wrapper).
- **Root-AST-only PSSA emission** (Parent-null guard) → one diagnostic per offending line.
- **Get-Alias over Get-Command** for alias resolution so the guard never auto-loads RSAT (T-00-11).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pester 6.0.0 / PSScriptAnalyzer 1.25.0 not discoverable on the host**
- **Found during:** Task 2 RED / Task 3 (running the gates)
- **Issue:** Only Pester 3.4.0 was system-wide; the host MUST NOT run Pester-6 tests under 3.4. CurrentUser installs landed on `OneDrive\Documents\WindowsPowerShell\Modules`, which is NOT on this host's `$env:PSModulePath`, so `Import-Module ... -MinimumVersion` misreported INSTALL_FAILED.
- **Fix:** Installed Pester 6.0.0 + PSScriptAnalyzer 1.25.0 (CurrentUser) and prepended the OneDrive WindowsPowerShell\Modules path to `$env:PSModulePath` in every out-of-repo harness/probe before importing.
- **Files modified:** none in-repo (tooling scripts live under `%TEMP%/adman-gsd/`, outside the repo so repo-wide lint stays clean).
- **Verification:** `Invoke-Pester` reports `Pester v6.0.0`; repo-wide lint returns 0 findings.
- **Committed in:** n/a (environment/tooling; not committed).

**2. [Rule 3 - Blocking] Manifest `RequiredModules=PSFramework` would break test-time manifest import**
- **Found during:** Task 2 RED
- **Issue:** `adman.psd1` declares `RequiredModules=@(@{ ModuleName='PSFramework'; RequiredVersion='1.14.457' })`, but the real PSFramework install is human-gated (T-00-SC) and absent, so `Test-ModuleManifest`/`Import-Module` would fail to resolve the dependency in tests.
- **Fix:** In `tests/Module.Manifest.Tests.ps1`, build a throwaway PSFramework 1.14.457 stub module on `$TestDrive/Modules` and prepend it to `$env:PSModulePath` for the test run, so the boundary tests resolve the exact-pinned dependency WITHOUT performing the gated real install.
- **Files modified:** `tests/Module.Manifest.Tests.ps1`
- **Verification:** Test 2/3 pass against the stub; the real install remains a human gate (D9).
- **Committed in:** `e41c4b4` (Task 2 RED).

**3. [Rule 1 - Bug] Custom PSSA rule emitted duplicate diagnostics (one per ScriptBlockAst node)**
- **Found during:** Task 3 GREEN
- **Issue:** PSScriptAnalyzer invokes a `[ScriptBlockAst]` rule once for the root AST AND once for every nested function body; with `FindAll(...,$true)` already recursing, the same banned line produced 2+ diagnostics.
- **Fix:** Guard `Measure-AdmanPublicWriteSafety` to emit only on the root AST: `if ($null -ne $Ast.Parent) { return @() }`.
- **Files modified:** `rules/AdmanSafetyRules.psm1`
- **Verification:** Standalone rule probe emits exactly 1 diagnostic for a single banned call; Harness custom-rule test passes.
- **Committed in:** `1ff2926` (Task 3 GREEN).

**4. [Rule 1 - Bug] Alias resolution via `Get-Command` auto-loaded the real RSAT ActiveDirectory module**
- **Found during:** Task 3 GREEN (integration: full-suite run failed only when Harness ran before Module.Manifest)
- **Issue:** `Find-AdmanBannedHit` used `Get-Command -Name $name` for best-effort alias resolution. On hosts where RSAT is installed, that auto-imports the real `ActiveDirectory` module as a side effect — breaking offline/RSAT-agnostic behavior (T-00-11) and the "import must not load ActiveDirectory" invariant. (A `$PSModuleAutoLoadingPreference='None'` override set inside the module-scoped function did NOT suppress the engine's auto-load, confirmed by replay.)
- **Fix:** Replaced `Get-Command` alias resolution with `Get-Alias -Name $name`, which reads only the in-session alias table (name → target-name string) and NEVER loads the target module. Name-based matching (`$Banned -contains $name`) remains the primary signal; alias resolution stays best-effort for operator-defined aliases (e.g. `sau -> Set-ADUser`). Removed the fragile preference juggling.
- **Files modified:** `rules/AdmanSafetyRules.psm1`
- **Verification:** Harness replay shows `REAL=0` loaded ActiveDirectory at every step (only the mock loads); full suite 12/12 green.
- **Committed in:** `1ff2926` (Task 3 GREEN).

**5. [Rule 1 - Bug] Side-effect test matched the offline mock module named `ActiveDirectory`**
- **Found during:** Task 3 GREEN (full-suite integration)
- **Issue:** `tests/Module.Manifest.Tests.ps1` test 4 asserted `Get-Module 'ActiveDirectory' | Should -BeNullOrEmpty`, but `Harness.Tests.ps1` imports `tests/Mocks/ActiveDirectory.psm1` (filename-derived module name `ActiveDirectory`) earlier in the same Pester run, so the bare name matched the MOCK (and, after fix #4 was first attempted, the real RSAT module too).
- **Fix:** Filter by `ModuleBase` to exclude any module under the repo `tests/` tree, so the assertion targets only the genuine RSAT module (`...\system32\...\ActiveDirectory`), which is now never loaded (fix #4).
- **Files modified:** `tests/Module.Manifest.Tests.ps1`
- **Verification:** Module.Manifest.Tests.ps1 passes 4/4 alone AND inside the full 12-test run.
- **Committed in:** `4dd8f23` (deviation fix).

**6. [Rule 2 - Missing Critical] State-changing stubs/mocks need `SupportsShouldProcess` to keep the lint gate honest**
- **Found during:** Task 2 GREEN / Task 3 GREEN
- **Issue:** `PSUseShouldProcessForStateChangingFunctions` (SAFE-01) is enabled repo-wide. The exported stubs `Initialize-Adman`/`Start-Adman` (state-changing verbs) and the mock write-stubs (`Set-AD*`, `Disable-ADAccount`, `Move-ADObject`, etc.) would be flagged, breaking the lint-clean invariant — WITHOUT weakening the rule by suppression.
- **Fix:** Added `[CmdletBinding(SupportsShouldProcess)]` (and `$PSCmdlet.ShouldProcess(...)` bodies in the mocks) so the lint gate passes by construction, not by exclusion.
- **Files modified:** `Public/Initialize-Adman.ps1`, `Public/Start-Adman.ps1`, `tests/Mocks/ActiveDirectory.psm1`, `tests/Fixtures/**`
- **Verification:** Repo-wide `Invoke-ScriptAnalyzer -Recurse` = 0 findings with the rule enabled.
- **Committed in:** `54e384d` (Task 2 GREEN) and `1ff2926` (Task 3 GREEN).

---

**Total deviations:** 6 auto-fixed (2× Rule 3 blocking, 3× Rule 1 bug, 1× Rule 2 missing-critical).
**Impact on plan:** All auto-fixes were necessary for correctness (the guard must not load RSAT), honest lint gating, and deterministic tests across hosts. No scope creep; the PSFramework install remains a human gate by design.

## Issues Encountered

- **`Import-PowerShellDataFile` is unavailable on Windows PowerShell 5.1** — Module.Manifest test 3 reads the manifest as raw text + `-Match` regex (not the PSD1 parser), and the full-suite load of `tests/PesterConfiguration.psd1` is a PS7/CI-only path. The 5.1 runs use `Test-ModuleManifest` / raw-text assertions and `Invoke-Pester -Path` defaults. Documented as a 5.1 limitation; no behavior loss for the 5.1 gate.
- **Cosmetic:** `tests/Safety.Gate.Tests.ps1` `It`-name `"Public/<file> contains no direct AD write call"` renders as `Public/$null` (Pester `<...>` interpolation without `-ForEach`). The assertion body is correct and passes; the label is cosmetic only and can be converted to `-ForEach`/`TestCases` in a follow-up.
- **bash → PowerShell quoting:** inlined `-Command "..."` hit `$`/`"` expansion and single-quote conflicts; resolved by writing `*.ps1` harness scripts under `%TEMP%/adman-gsd/` and invoking `powershell -File`.

## Known Stubs

- `Public/Initialize-Adman.ps1` — intentional exported stub (`Write-PSFMessage ... 'not implemented'; return`); real body lands in **00-03** (per PLAN `must_haves.artifacts`).
- `Public/Start-Adman.ps1` — intentional exported stub for the Phase 1 menu; calls `Initialize-Adman`; real body lands in **Phase 1**.
- `Invoke-AdmanMutation` (the single non-exported gate) is **intentionally absent** in this plan — the boundary (its exclusion from exports) is enforced here; the gate body is created in **00-02**. Tests assert it is NOT exported, which is correct for this plan.

None of these stubs prevent this plan's goal (the load-bearing skeleton + boundary + harness); each is explicitly owned by a named future plan.

## Threat Flags

None identified. This plan adds no network endpoints, auth paths, file-trust-boundary access, or schema changes beyond the plan's threat model (T-00-01 export boundary, T-00-SC PSFramework legitimacy gate, T-00-11 offline/no-live-domain, T-00-12 audit-writer exception). The custom PSSA rule and AST guard are static (parse-only); the mocks are offline; the PSFramework install stays behind the human-approval gate.

## User Setup Required

**One human-approval step is intentionally deferred (not auto-run):**
- Approve and run the first PSFramework install: `Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser` (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0 for dev), after confirming the package is legitimate (T-00-SC). Provenance/signatures were re-verified in `00-01-PSFramework-verified.md` (verdict **[OK]**).
- Note: on this host, CurrentUser installs land on `OneDrive\Documents\WindowsPowerShell\Modules`, which is not on `$env:PSModulePath` by default — prepend it (or install to a path already on PSModulePath) so `Import-Module Pester -MinimumVersion 6.0.0` / `PSScriptAnalyzer -MinimumVersion 1.25.0` resolve.

## Next Phase Readiness

- The export boundary and single-sourced banned-verb set are ready for **00-02** to implement `Invoke-AdmanMutation` (Private/, non-exported) and route all writes through it — the guards will immediately catch any Public/ verb that bypasses the gate.
- **00-03** fills `Initialize-Adman`; Phase 1 fills `Start-Adman`/menu (MENU-05 scaffolded).
- The harness (lint + AST guard + mocks) is reusable as-is by every later plan; the `PSAvoidUsingWriteHost` suppression is forward-declared for the Phase-1 TUI module.
- Blockers: none technical. The only open gate is the human PSFramework install approval (D9 / T-00-SC), which is expected and tracked.

## Self-Check: PASSED

- Files verified present (16/16): `adman.psd1`, `adman.psm1`, `Public/Initialize-Adman.ps1`, `Public/Start-Adman.ps1`, `PSScriptAnalyzerSettings.psd1`, `rules/AdmanSafetyRules.psm1`, `tests/PesterConfiguration.psd1`, `tests/Mocks/ActiveDirectory.psm1`, `tests/Module.Manifest.Tests.ps1`, `tests/Harness.Tests.ps1`, `tests/Safety.Gate.Tests.ps1`, `tests/Fixtures/Public/BadDirectWrite.ps1`, `tests/Fixtures/Private/GoodWrapper.ps1`, `tests/Fixtures/Public/DynamicInvoke.ps1`, `.planning/phases/00-foundation-safety-harness/00-01-PSFramework-verified.md`, `.claude/CLAUDE.md`.
- Commits verified present (6/6): `759d292` (Task 1), `e41c4b4` (Task 2 RED), `54e384d` (Task 2 GREEN), `5e170f0` (Task 3 RED), `4dd8f23` (deviation fix), `1ff2926` (Task 3 GREEN).
- Gates: full suite 12/12 passed (Pester v6.0.0); repo-wide `Invoke-ScriptAnalyzer -Recurse` = 0 findings.
- Missing: 0.

---
*Phase: 00-foundation-safety-harness*
*Completed: 2026-07-11*
