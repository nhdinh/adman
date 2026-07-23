---
phase: 00-foundation-safety-harness
plan: 02
subsystem: config
tags: [powershell, powershell-5.1, psframework, json, json-schema, config, fail-closed, plain-json, non-secret, conf-01, conf-02, conf-03, conf-05, d-01, d-04, d-05, pester-6, psscriptanalyzer]

# Dependency graph
requires:
  - phase: 00-01
    provides: "adman.psd1 explicit export boundary + exact-pinned PSFramework RequiredVersion; adman.psm1 loader with the $script:Config slot and ErrorActionPreference=Stop; Pester 6 / PSScriptAnalyzer harness + offline mocks; PSFramework-stub-on-$TestDrive pattern for the human-gated dependency"
provides:
  - "One shared non-secret JSON Schema (config/adman.schema.json) consumed by BOTH the wizard emitter (00-03) and the loader so they cannot drift (D-04/CONF-03)"
  - "Shipped defaults (config/adman.defaults.json): empty ManagedOUs so a fresh install fails closed; RID 500/501/502 deny-list seed; safety.bulkConfirmThreshold=5; credentialPolicy.allowRememberMe=false (non-secret metadata); transport order/timeouts; bulk.maxCount placeholder"
  - "TRACKED annotated example (config/adman.example.json) with _comment keys, reconciling CONF-05 gitignore vs D-04 shipped-example"
  - "Initialize-AdmanConfig: pinned-path load + fail-closed validate + one-time deny-list seed (Private/, non-exported)"
  - "Test-AdmanConfigValid: the SINGLE config validator reused by Initialize-/Set-/Import-AdmanConfig (a config edit can never weaken scope/deny-list - T-00-13)"
  - "Save-AdmanConfig: the SINGLE save path (ConvertTo-Json -Depth 5, SupportsShouldProcess) reused by the seed + Set/Export - nested keys can never be silently truncated (T-00-14)"
  - "Four exported config verbs: Get-/Set-/Export-/Import-AdmanConfig (CONF-01/03)"
  - "Config keys established for 00-03/00-04: ManagedOUs, DenyList (RID/SID tokens), safety.bulkConfirmThreshold, bulk.maxCount, AuditDir, ReportDir, transport.order/timeouts, credentialPolicy.allowRememberMe (consumed as-is by 00-03 Get-AdmanCredential), AdmanProtectedGroup, DC, delegatedAdminGroup"
affects: [00-03, 00-04, phase-01-menu, all-mutation-verbs]

# Tech tracking
tech-stack:
  added:
    - "JSON Schema (draft-07) for the non-secret config (config/adman.schema.json) - no new runtime module; PSFramework 1.14.457 is consumed via -Path pinning only (carried over from 00-01; real install still the human gate D9)"
  patterns:
    - "Pinned-path config backbone: Import-PSFConfig/Export-PSFConfig WITH -Path only, NEVER the per-user/per-machine auto-import registration cmdlet (Pitfall 7 / T-00-07)"
    - "Framework-independent fail-closed: safety values are parsed directly from the plain JSON (Get-Content | ConvertFrom-Json); the PSFramework call is best-effort and never safety-bearing, so a non-envelope/plain file cannot fail-open"
    - "Single validator (Test-AdmanConfigValid) + single save path (Save-AdmanConfig) shared by every config entry point (D-04 one-source-of-truth)"
    - "Annotated-example strip: keys prefixed '_comment' are removed before validation so the shipped example validates without polluting runtime config (D-04)"
    - "Recursive cleaner is array/leaf-safe: explicit array -> IDictionary -> pscustomobject -> leaf ordering preserves one-element arrays AND primitive leaf values (int/bool) under ConvertFrom-Json output"
    - "StrictMode-safe optional-key access: membership-test ($Config.PSObject.Properties.Name -contains 'DenyList') instead of property access where a key may be absent (Set-StrictMode -Version Latest would otherwise throw)"
    - "Module-scope test invocation uses NAMED binding (& (Get-Module adman) { param($p) } -p $store); positional -ArgumentList into a module-scope scriptblock does not bind object args on Windows PowerShell 5.1"

key-files:
  created:
    - "config/adman.schema.json"
    - "config/adman.defaults.json"
    - "config/adman.example.json"
    - "Private/Config/Initialize-AdmanConfig.ps1"
    - "Public/Config/Get-AdmanConfig.ps1"
    - "Public/Config/Set-AdmanConfig.ps1"
    - "Public/Config/Export-AdmanConfig.ps1"
    - "Public/Config/Import-AdmanConfig.ps1"
    - "tests/Config.NoSecrets.Tests.ps1"
    - "tests/Config.Load.Tests.ps1"
    - "tests/Config.FailClosed.Tests.ps1"
    - "tests/Config.RoundTrip.Tests.ps1"
  modified:
    - "adman.psd1 (FunctionsToExport appended with the four *-AdmanConfig verbs; '*' and Invoke-AdmanMutation still excluded)"
    - "tests/Config.Load.Tests.ps1 / Config.FailClosed.Tests.ps1 / Config.RoundTrip.Tests.ps1 (Rule-1 test-harness fix: positional -ArgumentList -> named binding)"

key-decisions:
  - "Fail-closed is framework-independent (D-01): safety values come from a direct plain-JSON parse (Get-Content | ConvertFrom-Json); exactly ONE guarded Import-PSFConfig -Path is called for the backbone and its result is never used for a safety decision - so the human-gated PSFramework install (00-01 D9) cannot be a fail-open seam, and a plain/non-envelope file cannot weaken scope (Pitfall 7 / T-00-07)."
  - "One validator + one save path (D-04): Test-AdmanConfigValid and Save-AdmanConfig are the single functions reused by Initialize-/Set-/Import-AdmanConfig; the wizard emitter (00-03) shares config/adman.schema.json so the two entry points cannot drift."
  - "Deny-list seed written ONCE into the JSON from defaults (RID 500/501/502, 'starter, not exhaustive'); thereafter the file is the single source of truth (no re-seed on a second load) (D-05). Tokens are the contract 00-04 Test-AdmanTargetAllowed resolves against (Get-ADDomain).DomainSID (SAFE-05)."
  - "SetupMode (-SetupMode) bypasses ONLY the empty-ManagedOUs fail-closed gate (first-run wizard creating the config) and still validates structure + performs NO AD mutation (D-04)."
  - "Export-/Import-AdmanConfig keep the CONF-03 plain-JSON safety file authoritative (ConvertTo-Json -Depth 5 / ConvertFrom-Json) and route the PSFramework call to a MIRROR path (<name>.psf.json) / best-effort import - never overwriting the file the loader parses. The literal Export-PSFConfig -Path / Import-PSFConfig -Path tokens (acceptance) are present. (Resolves the plan's internal tension between 'Export-PSFConfig -Path .store/config.json' and CONF-03 lossless round-trip.)"
  - "credentialPolicy.allowRememberMe is non-secret metadata (boolean + consent flag, no secret value) and is explicitly allow-listed by the no-secret rule; the rule bans ONLY password/secret/apiKey/privateKey names and secret VALUES, and does NOT ban the bare substring 'credential' or the DenyList[].token RID/SID field (C2-M1)."

patterns-established:
  - "Every state-changing config verb (Set-/Export-/Import-AdmanConfig) declares [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')] and re-runs the single validator + fail-closed before persisting; read-only Get-AdmanConfig does not."
  - "All config writes go through ConvertTo-Json -Depth 5 (or higher); all 5.1 reads use ConvertFrom-Json into a PSCustomObject indexed by property (no Core-only hashtable switch)."
  - "Named-parameter binding only (no aliases/positional) in module-scope test helpers and in the verbs (lint PSAvoidUsingCmdletAliases)."

requirements-completed: [CONF-01, CONF-02, CONF-03, CONF-05]

# Coverage metadata (#1602) - deterministic UAT routing
coverage:
  - id: D1
    description: "Non-secret config artifacts ship under config/: schema (with credentialPolicy.allowRememberMe allow-listed + no secret names/values), defaults (empty ManagedOUs fail-closed; RID 500/501/502 seed; safety.bulkConfirmThreshold=5), tracked annotated example with _comment keys, and .store/ gitignored + untracked"
    requirement: CONF-05
    verification:
      - kind: unit
        ref: "tests/Config.NoSecrets.Tests.ps1 (10/10) - ships artifacts; schema allow-list; no secret values; positive-control secret key IS flagged (real regex, no -SimpleMatch); defaults fail closed + seed; example valid JSON with _comment + path reconciliation; .gitignore + git ls-files .store empty"
        status: pass
    human_judgment: false
  - id: D2
    description: "Initialize-AdmanConfig loads a valid config from a pinned path (Import-PSFConfig -Path, never the auto-import registration), populates $script:Config, seeds the deny-list once, and never re-seeds on a second load"
    requirement: CONF-01
    verification:
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#loads a valid config from a pinned path and populates $script:Config (CONF-01)"
        status: pass
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#seeds the deny-list once on a truly fresh file and never re-seeds on a second load (D-05)"
        status: pass
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#static source invariants: pinned -Path, no per-user auto-import, strips _comment, 5.1-safe"
        status: pass
    human_judgment: false
  - id: D3
    description: "Fail-closed (CONF-02): empty ManagedOUs / malformed JSON / wrong-typed deny-list THROW before any mutation; -SetupMode bypasses ONLY the empty-scope gate"
    requirement: CONF-02
    verification:
      - kind: unit
        ref: "tests/Config.FailClosed.Tests.ps1#throws a terminating error on empty ManagedOUs mentioning managed-OU/ManagedOUs (CONF-02 scope)"
        status: pass
      - kind: unit
        ref: "tests/Config.FailClosed.Tests.ps1#throws on malformed JSON and never returns a half-valid config (CONF-02 load failure)"
        status: pass
      - kind: unit
        ref: "tests/Config.FailClosed.Tests.ps1#throws on a failed deny-list load (wrong type) and never returns a half-valid config (CONF-02)"
        status: pass
      - kind: unit
        ref: "tests/Config.Load.Tests.ps1#setup-mode (-SetupMode) bypasses the empty-scope fail-closed gate and performs no AD mutation (D-04)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Round-trip (CONF-03): every save uses ConvertTo-Json -Depth >=5; nested keys survive save+reload; 5.1-safe PSCustomObject read (no Core-only hashtable switch)"
    requirement: CONF-03
    verification:
      - kind: unit
        ref: "tests/Config.RoundTrip.Tests.ps1#save uses ConvertTo-Json -Depth >=5 and round-trips nested keys losslessly"
        status: pass
      - kind: unit
        ref: "tests/Config.RoundTrip.Tests.ps1#Initialize-AdmanConfig reload preserves nested keys and yields a PSCustomObject"
        status: pass
      - kind: unit
        ref: "tests/Config.RoundTrip.Tests.ps1#static: every ConvertTo-Json save carries -Depth >=5; no Core-only hashtable switch"
        status: pass
    human_judgment: false
  - id: D5
    description: "Set-/Import-AdmanConfig are state-changing (SupportsShouldProcess ConfirmImpact='High') and re-run the single validator + fail-closed, so a config edit/restore cannot bypass CONF-02 (T-00-13)"
    requirement: CONF-02
    verification:
      - kind: other
        ref: "source assertion: Select-String 'Test-AdmanConfigValid' >=1 in Public/Config/Set-AdmanConfig.ps1 AND Import-AdmanConfig.ps1; both contain [CmdletBinding(SupportsShouldProcess + ConfirmImpact"
        status: pass
      - kind: other
        ref: "smoke (adman-run-t3.ps1): Set-AdmanConfig persisted safety.bulkConfirmThreshold=9; Set fail-closed on ManagedOUs=@() with message matching managed-OU|ManagedOUs; Import round-tripped transport.timeouts.CIM=20"
        status: pass
    human_judgment: false
  - id: D6
    description: "Four verbs exported; manifest valid; zero Register-PSFConfig + zero Core-only hashtable switch under Private/Config + Public/Config; Export-PSFConfig -Path / Import-PSFConfig -Path present; repo-wide lint clean"
    requirement: CONF-01
    verification:
      - kind: other
        ref: "Test-ModuleManifest ./adman.psd1 (with PSFramework stub resolvable) -> valid; Get-Command -Module adman lists exactly Initialize-Adman, Start-Adman, Get/Set/Export/Import-AdmanConfig (no '*', no Invoke-AdmanMutation)"
        status: pass
      - kind: other
        ref: "Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1 -> 0 findings; source assertions zero Register-PSFConfig / zero -AsHashtable / every ConvertTo-Json -Depth >=5 under Private+Public"
        status: pass
    human_judgment: false

# Metrics
duration: ~1h 13m recorded commit span (04:57->06:09 +07) across a context-resume; active execution longer (deep PowerShell binding/cleaner diagnosis in Task 2 GREEN)
completed: 2026-07-11
status: complete
---

# Phase 0 Plan 02: Non-Secret Config Substrate Summary

**Fail-closed, plain-JSON, non-secret configuration substrate: one shared JSON Schema (wizard + loader), shipped defaults that fail closed on a fresh install (empty ManagedOUs), a one-time RID 500/501/502 deny-list seed, and four `-Path`-pinned config verbs - all funneled through ONE reusable validator (`Test-AdmanConfigValid`) and ONE save path (`Save-AdmanConfig -Depth 5`) so a Set/Import can never weaken scope or the deny-list (CONF-01/02/03/05, D-01/D-04/D-05; T-00-07/05/13/14 mitigated).**

## Performance

- **Duration:** ~1h 13m recorded commit span (04:57→06:09 +07); active execution longer across a context-resume (the binding/cleaner diagnosis for Task 2 GREEN was the bulk of it)
- **Started (this segment):** 2026-07-10T22:5x:xxZ (continuation; Task 1 GREEN + Task 2 RED were committed in the prior session)
- **Completed:** 2026-07-10T23:12:15Z
- **Tasks:** 3 (Task 1 TDD; Task 2 TDD; Task 3 non-TDD) — REDs for Task 1/2 landed in the prior session; this session completed Task 2 GREEN + Task 3 + full verification
- **Files:** 12 created, 4 modified (adman.psd1 + the 3 Task-2 test files for a Rule-1 harness fix)

## Accomplishments

- **Non-secret config artifacts (Task 1):** `config/adman.schema.json` (draft-07, `additionalProperties:true`, required top-level keys, `credentialPolicy.allowRememberMe` explicitly allow-listed as non-secret metadata — the no-secret rule does NOT ban the bare substring 'credential' nor `DenyList[].token`), `config/adman.defaults.json` (`ManagedOUs=[]` fail-closed; RID 500/501/502 deny-list seed note 'starter, not exhaustive'; `safety.bulkConfirmThreshold=5`; `bulk.maxCount=50` placeholder; transport order/timeouts; `credentialPolicy.allowRememberMe=false`), `config/adman.example.json` (TRACKED, first `_comment` documents the CONF-05 tracked-not-.store reconciliation). Verified by `tests/Config.NoSecrets.Tests.ps1` (10/10) using a REAL regex (`-match`/`Where-Object`, never `-SimpleMatch`) that passes on the shipped schema AND fails on a positive-control secret-bearing schema.
- **Fail-closed loader/validator/saver (Task 2):** `Private/Config/Initialize-AdmanConfig.ps1` — `Initialize-AdmanConfig` (pinned-path load `Join-Path $script:StorePath 'config.json'`, seed-from-defaults if absent, direct plain-JSON parse, `_comment` strip, one-time deny-list seed, schema-driven validate, CONF-02 scope gate with `-SetupMode` bypass, exactly ONE guarded `Import-PSFConfig -Path`), plus the single `Test-AdmanConfigValid` validator and single `Save-AdmanConfig -Depth 5` save path. Verified by `Config.Load`/`Config.FailClosed`/`Config.RoundTrip` (10/10).
- **Four config verbs (Task 3):** `Public/Config/{Get,Set,Export,Import}-AdmanConfig.ps1` — read-only `Get` (dotted-key access); state-changing `Set`/`Export`/`Import` with `SupportsShouldProcess ConfirmImpact='High'`; `Set`/`Import` re-run `Test-AdmanConfigValid` + CONF-02 fail-closed before persisting (T-00-13); all writes `ConvertTo-Json -Depth 5`. `adman.psd1` `FunctionsToExport` appended (still explicit; `'*'` and `Invoke-AdmanMutation` excluded).
- **Gates green:** 20/20 Config tests pass; `Test-ModuleManifest` valid (PSFramework stub resolvable); repo-wide `Invoke-ScriptAnalyzer -Recurse -Settings` = 0 findings; source assertions zero `Register-PSFConfig` + zero `-AsHashtable` under Private/Config + Public/Config + every `ConvertTo-Json` save `-Depth >=5`.

## Task Commits

Each task was committed atomically; TDD tasks have RED → GREEN commits. (Task 1 RED `da7a395`, Task 1 GREEN `64e35b1`, Task 2 RED `5ff7019` were committed in the prior session and verified present at resume.)

1. **Task 1 RED: failing no-secret config-artifact tests** — `da7a395` (test)
2. **Task 1 GREEN: ship non-secret config schema, defaults, tracked example** — `64e35b1` (feat)
3. **Task 2 RED: failing config load/fail-closed/round-trip tests** — `5ff7019` (test)
4. **Task 2 GREEN: implement fail-closed config load/validate/seed (Initialize-AdmanConfig)** — `c62e701` (feat) — also carries the bundled Rule-1 cleaner/StrictMode fixes and the test-harness named-binding correction
5. **Task 3: add Get/Set/Export/Import-AdmanConfig verbs (CONF-01/03) + manifest export** — `23c441c` (feat)

**Plan metadata (SUMMARY/STATE/ROADMAP/REQUIREMENTS):** committed next (docs).

## Files Created/Modified

- `config/adman.schema.json` — single shared draft-07 schema (additionalProperties:true; required keys; `credentialPolicy.allowRememberMe` non-secret; `DenyList[].token`).
- `config/adman.defaults.json` — source-of-truth defaults; empty ManagedOUs (fail-closed); RID 500/501/502 seed; safety/bulk/transport/credentialPolicy.
- `config/adman.example.json` — TRACKED annotated example with `_comment` keys (path-reconciliation `_comment` first).
- `Private/Config/Initialize-AdmanConfig.ps1` — `ConvertTo-AdmanCleanConfig` (array/leaf-safe `_comment` strip), `Test-AdmanConfigValid` (single schema-driven validator), `Save-AdmanConfig` (single `-Depth 5` save path), `Initialize-AdmanConfig` (fail-closed load/seed/validate).
- `Public/Config/Get-AdmanConfig.ps1` — read-only `$script:Config` accessor (dotted `-Key`).
- `Public/Config/Set-AdmanConfig.ps1` — validated/fail-closed single-key edit (clone → validate → fail-closed → save).
- `Public/Config/Export-AdmanConfig.ps1` — plain-JSON `-Depth 5` export + best-effort PSFramework mirror at `<name>.psf.json`.
- `Public/Config/Import-AdmanConfig.ps1` — plain-JSON parse → strip → validate → fail-closed → save → publish (restore, CONF-03).
- `tests/Config.NoSecrets.Tests.ps1`, `Config.Load.Tests.ps1`, `Config.FailClosed.Tests.ps1`, `Config.RoundTrip.Tests.ps1` — 20 behavior + static-invariant tests (20/20 green).
- `adman.psd1` — `FunctionsToExport` appended with the four verbs (explicit list preserved).

## Decisions Made

- **Framework-independent fail-closed (D-01):** safety values come from a direct plain-JSON parse; the single `Import-PSFConfig -Path` is guarded/best-effort and never safety-bearing. Rationale: the real PSFramework install is the human gate from 00-01 (D9) and a non-envelope/plain file must never fail-open (Pitfall 7 / T-00-07).
- **One validator + one save path (D-04):** `Test-AdmanConfigValid` + `Save-AdmanConfig` are the single functions reused by every config entry point; the schema file is shared with the 00-03 wizard emitter.
- **Seed once, file is truth thereafter (D-05):** RID 500/501/502 written into the JSON only when DenyList is absent; a second load never re-seeds. Token contract documented for 00-04 (`Test-AdmanTargetAllowed` vs `DomainSID`).
- **`-SetupMode` bypasses ONLY the empty-scope gate** (wizard creating the config); still validates structure, no AD mutation (D-04).
- **PSFramework mirror path for Export/Import:** the plain-JSON safety file stays authoritative; the framework call targets `<name>.psf.json` / best-effort so an envelope can never corrupt the CONF-03 round-trip file (see Deviation 7).
- **`credentialPolicy.allowRememberMe` allow-listed** as non-secret metadata; no-secret rule bans only real secret names/values (C2-M1).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Cleaner collapsed primitive leaf values into empty PSCustomObjects**
- **Found during:** Task 2 GREEN (`Config.Load`/`Config.RoundTrip` failing on `safety.bulkConfirmThreshold`/`bulk.maxCount` validation).
- **Issue:** `ConvertTo-AdmanCleanConfig`'s object-branch guard was `$Node.PSObject -and $Node.PSObject.Properties`, which is TRUE for value types (Int32/bool): the engine supplies a (possibly empty) Properties collection, so a leaf like `5` entered the object branch, iterated zero properties, and returned an EMPTY `[pscustomobject]@{}` — silently turning `bulkConfirmThreshold=5` into `{}`. (A diagnostic repro confirmed `parsed.safety.bulkConfirmThreshold=5 (Int32)` but `clean.safety.bulkConfirmThreshold=[] (PSCustomObject)`.)
- **Fix:** Replaced the broad guard with explicit, ordered type checks — `array` → `System.Collections.IDictionary` → `pscustomobject` → leaf (return unchanged). The array branch keeps `return ,$arr` (unary comma) so a one-element array is not unrolled to a scalar.
- **Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`.
- **Verification:** repro shows `clean.safety.bulkConfirmThreshold=5 (Int32)`; ManagedOUs/DenyList/transport.order all stay arrays.
- **Committed in:** `c62e701` (Task 2 GREEN).

**2. [Rule 1 - Bug] `Set-StrictMode -Version Latest` made `$config.DenyList` throw on a NoDenyList file**
- **Found during:** Task 2 GREEN (`Config.Load` seed-once test: `PropertyNotFoundException: The property 'DenyList' cannot be found`).
- **Issue:** The seed guard `if ($null -eq $config.DenyList)` (and the validator's `$null -ne $Config.DenyList`) accessed a property that does not exist on a NoDenyList config; under `Set-StrictMode -Version Latest` that is a terminating error, not `$null`.
- **Fix:** Membership-test instead of property-access: seed guard `if (-not ($config.PSObject.Properties.Name -contains 'DenyList'))`; validator guard `if ($Config.PSObject.Properties.Name -contains 'DenyList' -and $null -ne $Config.DenyList)`. (Validator is shared by Set/Import, which validate directly without seeding, so the robustness is required there too — Rule 2.)
- **Files modified:** `Private/Config/Initialize-AdmanConfig.ps1`.
- **Verification:** seed-once test passes (3 tokens, no re-seed on second load); full Task-2 set 10/10.
- **Committed in:** `c62e701` (Task 2 GREEN).

**3. [Rule 1 - Bug] Task-2 RED tests passed `$null` to the module-scope scriptblock (positional `-ArgumentList` does not bind object args on PS 5.1)**
- **Found during:** Task 2 GREEN (`Config.RoundTrip`: `Cannot bind argument to parameter 'Config' because it is null`; `Config.Load` reading the wrong path).
- **Issue:** The RED tests used `& (Get-Module adman) { param($c, $p) Save-AdmanConfig -Config $c -Path $p } -ArgumentList $cfg, $path`. On Windows PowerShell 5.1, positional `-ArgumentList` into a module-scope scriptblock does NOT bind the parameters (a binding probe proved forms `-ArgumentList $cfg, $path` and `-ArgumentList @($cfg,$path)` both yield `$c=$p=$null`; named `-c $cfg -p $path` binds correctly). The harness therefore delivered `$null` and could not exercise the implementation — a test bug, not an implementation bug.
- **Fix:** Switched every wrapper to NAMED binding (`-p $store`; `-c $cfg -p $path`). Assertions and the contract are byte-for-byte unchanged; only the argument-delivery idiom changed.
- **Files modified:** `tests/Config.Load.Tests.ps1`, `tests/Config.FailClosed.Tests.ps1`, `tests/Config.RoundTrip.Tests.ps1`.
- **Verification:** with named binding + fixes #1/#2, all three Task-2 files pass 10/10; a named-binding repro under Pester confirmed `Save-AdmanConfig` writes and `Initialize-AdmanConfig` loads from the correct store.
- **Committed in:** `c62e701` (Task 2 GREEN).

**4. [Rule 3 - Blocking] A corrupted, gitignored `.store/config.json` poisoned the default-store fallback**
- **Found during:** Task 2 GREEN diagnosis (a repro fell back to `$script:StorePath='.store'` and read a repo-root `.store/config.json` whose leaves were all `{}` empty objects — `ManagedOUs={}`, `safety.bulkConfirmThreshold={}`, etc.).
- **Issue:** A stray `.store/config.json` (left over from earlier in-process probing in this execution) existed in the repo working tree. It is gitignored (`.gitignore: .store/`) and untracked, but any code path that resolved to the default `.store` would parse this malformed file and throw misleading validation errors.
- **Fix:** Deleted the repo-root `.store/` directory (untracked/gitignored → nothing to commit; safe environmental cleanup). Tests use per-test `$TestDrive` stores, never the repo `.store`.
- **Files modified:** none tracked (`.store/` is gitignored).
- **Verification:** after removal + named binding, Initialize-AdmanConfig reads the intended per-test store; full suite green.
- **Committed in:** n/a (environmental; not committed).

**5. [Rule 1 - Bug] Static source-invariant scans check the WHOLE file (incl. comments) for banned tokens**
- **Found during:** Task 2 GREEN (`-AsHashtable` static count Expected 0 got 1) and Task 3 (acceptance `Register-PSFConfig` count in Public/Config).
- **Issue:** The acceptance greps (`Select-String -Pattern '\-AsHashtable'` → 0; `Select-String -Pattern 'Register-PSFConfig'` → 0 across Public/Config) scan comments too. Doc comments in `Initialize-AdmanConfig.ps1` literally said `-AsHashtable`, and `Set-/Export-AdmanConfig.ps1` comments literally said `Register-PSFConfig` — which would fail the "=0" checks even though no CODE uses them.
- **Fix:** Reworded the comments to keep the meaning without the literal tokens (e.g., "the Core-only hashtable switch is not used"; "the per-user auto-import persistence-registration cmdlet is never called"). The REQUIRED code tokens `Export-PSFConfig -Path` / `Import-PSFConfig -Path` were preserved in the code bodies.
- **Files modified:** `Private/Config/Initialize-AdmanConfig.ps1` (`c62e701`); `Public/Config/Set-AdmanConfig.ps1`, `Public/Config/Export-AdmanConfig.ps1` (`23c441c`).
- **Verification:** repo grep confirms zero `-AsHashtable` and zero `Register-PSFConfig` under Private/Config + Public/Config; `Export-PSFConfig -Path` / `Import-PSFConfig -Path` present in Export/Import code.
- **Committed in:** `c62e701` and `23c441c`.

**6. [Rule 2 - Missing Critical] Export/Import must not let a PSFramework envelope overwrite the CONF-03 safety file**
- **Found during:** Task 3 design.
- **Issue:** The plan both (a) requires the literal tokens `Export-PSFConfig -Path` / `Import-PSFConfig -Path` and (b) requires CONF-03 lossless round-trip of the plain safety file that `Initialize-AdmanConfig` parses directly with `ConvertFrom-Json`. If `Export-PSFConfig -Path .store/config.json` overwrote that file with a PSFramework envelope, the next load's plain-JSON parse would break → fail-closed (or worse). A correctness/safety conflict, not a stylistic one.
- **Fix:** `Export-AdmanConfig` writes the authoritative plain file via `ConvertTo-Json -Depth 5` AND a best-effort PSFramework MIRROR at `<name>.psf.json` (`Export-PSFConfig -Path`); `Import-AdmanConfig` parses the plain file directly (`ConvertFrom-Json`) and treats `Import-PSFConfig -Path` as best-effort/backbone-only. The safety source is never the framework file. (Within the plan's latitude; the literal tokens are present.)
- **Files modified:** `Public/Config/Export-AdmanConfig.ps1`, `Public/Config/Import-AdmanConfig.ps1`.
- **Verification:** smoke shows Export wrote nested key (`timeouts.WinRM=15`) and Import round-tripped (`timeouts.CIM=20`); the safety file stays plain JSON.
- **Committed in:** `23c441c` (Task 3).

---

**Total deviations:** 6 (3× Rule 1 bug, 1× Rule 2 missing-critical, 1× Rule 3 blocking environmental, 1× design-within-plan-latitude) — plus the cross-context resume (Task 1 GREEN + Task 2 RED pre-committed; verified via `git log` and not re-done).
**Impact on plan:** All auto-fixes were necessary for correctness (the cleaner must not destroy leaf values; StrictMode must not throw on optional keys; tests must actually deliver their arguments; the safety file must not be overwritten). No scope creep — every fix serves the stated must-haves/acceptance criteria.

## Issues Encountered

- **PowerShell module-scope argument binding is subtle on 5.1:** `& (Get-Module adman) { param($p) } -ArgumentList $value` does not bind `$p` for object (and in some scalar) arguments; NAMED binding (`-p $value`) is required. Resolved for the tests (Deviation 3) and documented as a pattern for future plans.
- **`Set-StrictMode -Version Latest` is module-wide** once set in a dot-sourced file: optional-key reads must use `-contains` membership tests everywhere (applied to the validator/seed guard; carried into the verbs).
- **bash → PowerShell quoting:** inlined `-Command "..."` repeatedly mangled `$env:`/`$()`/quotes; resolved by writing `*.ps1` harness/probe scripts under `%TEMP%` and invoking `powershell -File`.
- **PSFramework 1.14.457 absent (human-gated):** `Test-ModuleManifest`/`Import-Module` only resolve the `RequiredModules` entry when a 1.14.457 stub is on `$env:PSModulePath` (the 00-01 pattern). The config's SAFETY does not depend on the real install (framework-independent fail-closed), so this is not a functional blocker.

## Known Stubs

- **`bulk.maxCount` is a placeholder** carried in the schema/defaults (default 50) but NOT enforced here — enforcement is Phase 4 / BULK-02 (per the plan). Present so the key is established; no behavior yet.
- **PSFramework backbone calls (`Set-PSFConfig` / `Import-PSFConfig` / `Export-PSFConfig`) are best-effort mirrors**, not the safety source. They are fully functional once the human-gated real install (00-01 D9) lands; until then the config works entirely via the plain-JSON path. This is intentional and not a functional stub — the safety properties hold without it.

None of these prevent this plan's goal (a correct, provable, fail-closed config layer); each is explicitly owned by a named later plan/gate.

## Threat Flags

None identified beyond the plan's threat model. T-00-07 (PSFramework auto-import fail-open) is mitigated by `-Path`-only pinning + framework-independent fail-closed (zero `Register-PSFConfig`; empty ManagedOUs throws); T-00-05 (secret in config) by the no-secret schema + real-regex test + `.store/` gitignore + tracked-outside-.store example (CONF-05, C2-M1); T-00-13 (Set/Import bypass) by the shared `Test-AdmanConfigValid` + fail-closed + `SupportsShouldProcess ConfirmImpact='High'`; T-00-14 (lossy save) by `ConvertTo-Json -Depth >=5` on every save + round-trip test. No new network endpoints, auth paths, file-trust-boundary access, or schema changes were introduced.

## User Setup Required

None new for this plan. The one open human gate is inherited from 00-01 (D9 / T-00-SC): approve and run `Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser` (the config layer is safe without it; the backbone mirror calls become fully functional once installed). On this host, CurrentUser installs land on `OneDrive\Documents\WindowsPowerShell\Modules` (not on `$env:PSModulePath` by default) — prepend it so `Import-Module Pester -MinimumVersion 6.0.0` / `PSScriptAnalyzer` resolve.

## Next Phase Readiness

- **00-03** can fill `Initialize-Adman` and implement `Get-AdmanCredential` consuming `credentialPolicy.allowRememberMe` as-is (key name/shape stable; the encrypted-DPAPI credential file is a separate, opt-in artifact per project constraints).
- **00-04** consumes `ManagedOUs` (managed-OU scope) and the `DenyList` RID/SID tokens — `Test-AdmanTargetAllowed` resolves `DenyList[].token` against `(Get-ADDomain).DomainSID` (SAFE-05); the token contract (500/501/502 'starter, not exhaustive') is established.
- All mutation verbs (Phase 1+) inherit the CONF-02 gate: they run only after `Initialize-AdmanConfig` succeeds (non-empty scope), and any config edit goes through `Set-AdmanConfig` (validated) — the bypass seam is closed.
- Blockers: none technical. The only open gate is the inherited human PSFramework install approval (expected, tracked in 00-01).

## Self-Check: PASSED

- Files verified present (12/12 created): `config/adman.schema.json`, `config/adman.defaults.json`, `config/adman.example.json`, `Private/Config/Initialize-AdmanConfig.ps1`, `Public/Config/Get-AdmanConfig.ps1`, `Public/Config/Set-AdmanConfig.ps1`, `Public/Config/Export-AdmanConfig.ps1`, `Public/Config/Import-AdmanConfig.ps1`, `tests/Config.NoSecrets.Tests.ps1`, `tests/Config.Load.Tests.ps1`, `tests/Config.FailClosed.Tests.ps1`, `tests/Config.RoundTrip.Tests.ps1`.
- Files verified modified (4/4): `adman.psd1`, `tests/Config.Load.Tests.ps1`, `tests/Config.FailClosed.Tests.ps1`, `tests/Config.RoundTrip.Tests.ps1`.
- Commits verified present (5/5 on HEAD): `da7a395` (Task 1 RED), `64e35b1` (Task 1 GREEN), `5ff7019` (Task 2 RED), `c62e701` (Task 2 GREEN), `23c441c` (Task 3).
- Gates: full Config suite 20/20 passed (Pester v6.0.0); `Test-ModuleManifest` valid (PSFramework stub resolvable); repo-wide `Invoke-ScriptAnalyzer -Recurse -Settings PSScriptAnalyzerSettings.psd1` = 0 findings; source assertions zero `Register-PSFConfig` / zero `-AsHashtable` / every `ConvertTo-Json` `-Depth >=5` under Private/Config + Public/Config; exported set exactly `{Initialize-Adman, Start-Adman, Get/Set/Export/Import-AdmanConfig}` (no `'*'`, no `Invoke-AdmanMutation`).
- Pre-existing dirty files (`.planning/config.json` M, `.claude/settings.local.json` ??, `.gsd/` ??) confirmed NOT swept into any task commit (scoped staging only).
- Missing: 0.

---
*Phase: 00-foundation-safety-harness*
*Completed: 2026-07-11*
