---
phase: 01-ad-query-reporting-read-only
plan: 02
subsystem: ad-query
tags: [find, user, computer, d-02, d-03, high-1, medium-3, wave-1]
dependency_graph:
  requires:
    - Private/Safety/Test-AdmanTargetAllowed.ps1 (Phase 0, source of ConvertTo-AdmanNormalizedDn)
    - Private/Safety/Escape-AdmanLdapFilterValue.ps1 (Phase 0, RFC4515 helper — NOT used for -Filter)
    - tests/Mocks/ActiveDirectory.psm1 (Phase 0, extended in Task 1)
    - $script:Config.ManagedOUs / $script:Config.DC (Phase 0 session state)
  provides:
    - Public/Find-AdmanUser.ps1 (scoped read-only AD user search, USER-01)
    - Public/Find-AdmanComputer.ps1 (scoped read-only AD computer search, COMP-01)
    - Private/Reporting/ConvertTo-AdmanResult.ps1 (canonical D-03 schema mapper)
    - Private/Reporting/Test-AdmanInManagedScope.ps1 (SAFE-07 step (c) scope-only boundary check)
    - Private/Utility/ConvertTo-AdmanNormalizedDn.ps1 (shared DN normalization, MEDIUM-3)
    - Private/Utility/Escape-AdmanAdFilterLiteral.ps1 (HIGH-1 -Filter string-literal escape)
    - tests/Find.User.Tests.ps1 / tests/Find.Computer.Tests.ps1 / tests/Result.Schema.Tests.ps1 / tests/Utility.EscapeFilter.Tests.ps1
  affects:
    - Plan 01-03 (report verbs) — consumes Find-AdmanUser/Find-AdmanComputer and ConvertTo-AdmanResult
    - Plan 01-04 (renderer dispatch) — consumes the D-03 schema via $entry.Properties
tech_stack:
  added: []
  patterns:
    - HIGH-1: dedicated -Filter-aware escape helper (single-quote doubling + backslash doubling) distinct from RFC4515 Escape-AdmanLdapFilterValue
    - D-02: loop ManagedOUs with -SearchBase/-SearchScope Subtree/-ResultPageSize 1000/-Server pinned
    - D-03: fixed-schema PSCustomObject per type; renderers never touch raw AD objects
    - MEDIUM-3: single shared ConvertTo-AdmanNormalizedDn for both read and write paths
    - SAFE-07 step (c) on reads: scope-only boundary check; deny/protected checks remain mutation-only
key_files:
  created:
    - Public/Find-AdmanUser.ps1
    - Public/Find-AdmanComputer.ps1
    - Private/Reporting/ConvertTo-AdmanResult.ps1
    - Private/Reporting/Test-AdmanInManagedScope.ps1
    - Private/Utility/Escape-AdmanAdFilterLiteral.ps1
    - tests/Find.User.Tests.ps1
    - tests/Find.Computer.Tests.ps1
    - tests/Result.Schema.Tests.ps1
    - tests/Utility.EscapeFilter.Tests.ps1
  modified:
    - tests/Mocks/ActiveDirectory.psm1 (Task 1, commit 2a29a03)
    - Private/Safety/Test-AdmanTargetAllowed.ps1 (Task 2, commit ea6e986 — local ConvertTo-AdmanNormalizedDn removed)
    - Private/Utility/ConvertTo-AdmanNormalizedDn.ps1 (Task 2, commit ea6e986 — moved verbatim from Test-AdmanTargetAllowed)
    - adman.psd1 (FunctionsToExport += Find-AdmanUser, Find-AdmanComputer)
decisions:
  - HIGH-1 resolved via option (b): dedicated Escape-AdmanAdFilterLiteral helper for -Filter string literals; Escape-AdmanLdapFilterValue remains RFC4515-only for -LDAPFilter. The two are structurally independent and NOT interchangeable.
  - Wildcards (* and ?) are NOT escaped by Escape-AdmanAdFilterLiteral — the Find verbs intentionally use -like semantics on -Name (D-02); callers needing exact-match use -eq and must not pass user-controlled wildcards.
  - Find-AdmanUser parameter sets removed in favor of plain optional parameters — PowerShell parameter-set resolution throws before the function body when no args are supplied, preventing the custom "at least one required" error from surfacing.
  - ConvertTo-AdmanResult does NOT handle the never-logged-on sentinel (1601-01-01 FILETIME epoch) — that is a report-layer concern per D-03/D-06.
  - Test-AdmanInManagedScope applies ONLY the SAFE-07 step (c) boundary; deny-list and protected-group checks are NOT applied to reads (D-02, RESEARCH Pitfall 7).
metrics:
  duration: 20m
  completed_date: 2026-07-15
  tasks: 5
  files_created: 9
  files_modified: 4
  tests_added: 82
status: complete
---

# Phase 01 Plan 02: Scoped Read-Only AD Query Layer Summary

**One-liner:** Scoped, read-only AD query layer with two Public Find verbs, a canonical D-03 result mapper, a scope-only boundary helper, and a dedicated -Filter escape helper — 82 green Pester 6 contract tests proving USER-01, COMP-01, D-02, D-03, HIGH-1, and MEDIUM-3.

## What Was Built

### Public/Find-AdmanUser.ps1 (new)

USER-01 scoped read-only AD user search. Accepts `-Name`, `-SamAccountName`, or `-DisplayName` (at least one required; plain optional parameters — parameter sets were removed because PowerShell's parameter-set resolution throws before the function body when no args are supplied, preventing the custom validation error from surfacing).

- **Filter construction (HIGH-1):** every user-supplied value passes through `Escape-AdmanAdFilterLiteral` before interpolation. `-SamAccountName` and `-DisplayName` use `-eq`; `-Name` uses `-like` (D-02 wildcard semantics). A name like `O'Brien` produces `"sAMAccountName -eq 'O''Brien'"`.
- **D-02 invariants:** loops every `$script:Config.ManagedOUs` root; calls `Get-ADUser -Filter ... -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC -Properties <hard-coded D-02 list>`.
- **Scope re-check:** every returned object passes through `Test-AdmanInManagedScope` on its DistinguishedName; out-of-scope objects are dropped.
- **D-03 mapping:** each raw AD object is mapped through `ConvertTo-AdmanResult -ObjectType User`.

### Public/Find-AdmanComputer.ps1 (new)

COMP-01 scoped read-only AD computer search. Accepts mandatory `-Name` with `-like` semantics. Identical D-02 invariants, HIGH-1 escaping, scope re-check, and D-03 mapping (`-ObjectType Computer`).

### Private/Reporting/ConvertTo-AdmanResult.ps1 (new)

Canonical D-03 schema mapper. Takes `-ADObject` and `-ObjectType ('User'|'Computer')` and returns a fixed-schema PSCustomObject:

- **Always present (both types):** ObjectType, Name, SamAccountName, Enabled, DistinguishedName, ObjectSid, ObjectGuid.
- **User-only nullable:** DisplayName, UserPrincipalName, LockedOut, PasswordExpired, PasswordLastSet, AccountExpirationDate.
- **Computer-only nullable:** OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack, IPv4Address, DNSHostName.
- **Shared nullable timestamps:** LastLogonDate, whenCreated, whenChanged — emitted as `[datetime]` when present, `$null` when absent. The never-logged-on sentinel is NOT handled here (report-layer concern per D-03/D-06).
- **No raw AD property leakage:** properties like `MemberOf`, `objectClass`, `PropertyNames` are dropped.

### Private/Reporting/Test-AdmanInManagedScope.ps1 (new)

SAFE-07 step (c) scope-only boundary check for reads. Returns `$true` only when the normalized DN equals a normalized ManagedOUs root or ends with `',<root>'` (component-boundary anchored; NEVER a `-like` substring). Calls the shared `ConvertTo-AdmanNormalizedDn` (MEDIUM-3 — no logic duplication). Does NOT check deny-list or protected-group membership — those are mutation-only gates (D-02, RESEARCH Pitfall 7).

### Private/Utility/Escape-AdmanAdFilterLiteral.ps1 (new)

HIGH-1 dedicated -Filter string-literal escape helper. Single quotes are doubled (`'` -> `''`), backslashes are doubled (`\` -> `\\`). Wildcards (`*` and `?`) are NOT escaped (preserved for `-like` semantics on `-Name`). Parentheses and NUL pass through unchanged (NOT special in -Filter string literals, unlike RFC4515). Comment-based help explicitly distinguishes it from `Escape-AdmanLdapFilterValue` — the two are NOT interchangeable.

### Private/Utility/ConvertTo-AdmanNormalizedDn.ps1 (moved, Task 2)

Extracted verbatim from `Private/Safety/Test-AdmanTargetAllowed.ps1` lines 104-127 into a shared utility. Lowercases, hex-unescapes `\XX`, backslash-unescapes `\X`, splits on comma, trims each RDN, rejoins. Both the write path (`Test-AdmanTargetAllowed` step (c)) and the read path (`Test-AdmanInManagedScope`) call this single source — no logic duplication (MEDIUM-3).

### tests/Mocks/ActiveDirectory.psm1 (extended, Task 1)

Extended so `Get-ADUser` and `Get-ADComputer` accept the scoped paged-read parameter set (`-Filter`, `-SearchBase`, `-SearchScope`, `-ResultPageSize`, `-Properties`, `-Server`). Returns AdmanMock-tagged PSCustomObjects whose properties include the requested `-Properties` list. Honors `-SearchBase` by returning objects whose DistinguishedName ends with the supplied DN. Always includes at least one object whose DistinguishedName is OUTSIDE the ManagedOUs scope so the scope re-check can be tested. Captures call arguments on `$script:CapturedCalls` so tests can assert exact filter construction.

### Test files (4 new, 82 tests total)

- **tests/Utility.EscapeFilter.Tests.ps1** (16 tests) — pins the HIGH-1 escaping contract: single-quote doubling, backslash doubling, combined, pass-through (alphanumerics, parentheses, wildcards), empty/null, and structural independence from `Escape-AdmanLdapFilterValue`.
- **tests/Result.Schema.Tests.ps1** (24 tests) — pins the D-03 property set per type (User: 16 columns, Computer: 15 columns), timestamp types, no raw AD property leakage, and the `Test-AdmanInManagedScope` boundary semantics (in-scope, out-of-scope, component-boundary anchored, escaped commas, empty/null).
- **tests/Find.User.Tests.ps1** (22 tests) — pins USER-01: ManagedOUs loop, ResultPageSize 1000, Server pinning, SearchScope Subtree, D-02 Properties list, -eq vs -like filter construction, O'Brien doubled-quote, backslash doubling, wildcard preservation, out-of-scope dropping, D-03 schema, and structural invariants (no `Escape-AdmanLdapFilterValue`, no `Test-AdmanTargetAllowed`).
- **tests/Find.Computer.Tests.ps1** (20 tests) — pins COMP-01 with the same invariants.

### adman.psd1 (modified)

`FunctionsToExport` extended with `Find-AdmanUser` and `Find-AdmanComputer`.

## Verification

- `Invoke-Pester -Path tests/Find.User.Tests.ps1,tests/Find.Computer.Tests.ps1,tests/Result.Schema.Tests.ps1,tests/Utility.EscapeFilter.Tests.ps1 -Output Normal` → **82 passed, 0 failed** (Pester 6.0.0).
- `Invoke-Pester -Path tests -Output Normal -ExcludeTag Integration` → **243 passed, 1 failed** (the 1 failure is the pre-existing SAFE-01 lint test failing on a spike file — see Deviations).
- `Invoke-ScriptAnalyzer` on all 5 new implementation files → **clean** (PSScriptAnalyzer 1.25.0).
- `grep -c Escape-AdmanAdFilterLiteral Public/Find-AdmanUser.ps1` → **5** (≥1 per parameter).
- `grep -c Escape-AdmanAdFilterLiteral Public/Find-AdmanComputer.ps1` → **3**.
- `grep -c Escape-AdmanLdapFilterValue Public/Find-AdmanUser.ps1` → **0**.
- `grep -c Escape-AdmanLdapFilterValue Public/Find-AdmanComputer.ps1` → **0**.
- `grep -c Test-AdmanTargetAllowed Public/Find-AdmanUser.ps1` → **0**.
- `grep -c Test-AdmanTargetAllowed Public/Find-AdmanComputer.ps1` → **0**.
- `grep -c "function ConvertTo-AdmanNormalizedDn" Private/Safety/Test-AdmanTargetAllowed.ps1` → **0** (moved to shared utility).
- `grep -c "ConvertTo-AdmanNormalizedDn -Dn" Private/Safety/Test-AdmanTargetAllowed.ps1` → **2** (call sites still resolve).
- All existing Phase 0 safety tests (`tests/Safety.Gate.Tests.ps1`) still pass — the Task 2 move is behavior-preserving.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `$Args` is a reserved automatic variable in PowerShell**
- **Found during:** Task 4 (first Pester run — 20 of 24 tests failed with `PSInvalidCastException: Cannot convert System.Object[] to System.Collections.Hashtable`).
- **Issue:** The test helper `Invoke-AdmanPrivate` declared `param([hashtable]$Args)`. `$Args` is a reserved automatic variable containing unbound arguments; assigning to it causes PowerShell to unroll the hashtable into an Object[].
- **Fix:** Renamed the parameter to `$Params` throughout the test file.
- **Files modified:** tests/Result.Schema.Tests.ps1
- **Commit:** bd508b2 (Task 4 commit; fix applied before commit).

**2. [Rule 1 - Bug] Docstring mentions of `Escape-AdmanLdapFilterValue` and `Test-AdmanTargetAllowed` broke literal grep acceptance criteria**
- **Found during:** Task 5 (first Pester run — structural invariant tests failed).
- **Issue:** The plan's acceptance criteria require `grep -c Escape-AdmanLdapFilterValue` and `grep -c Test-AdmanTargetAllowed` to return 0 in the Find verb files. The initial docstrings legitimately referenced both strings to explain the design (e.g., "Escape-AdmanLdapFilterValue is NEVER used here"), producing non-zero grep counts.
- **Fix:** Reworded the docstrings to avoid the literal strings ("The RFC4515 LDAP assertion escape helper is NEVER used here", "deny/protected checks are mutation-only") while preserving the design intent.
- **Files modified:** Public/Find-AdmanUser.ps1, Public/Find-AdmanComputer.ps1, Private/Reporting/Test-AdmanInManagedScope.ps1
- **Commit:** 693be32 (Task 5 commit; fix applied before commit).

**3. [Rule 1 - Bug] `Import-PowerShellDataFile` not available in PowerShell 5.1**
- **Found during:** Task 5 (first Pester run — manifest export test failed with `CommandNotFoundException`).
- **Issue:** The test used `Import-PowerShellDataFile` to verify `FunctionsToExport` in `adman.psd1`, but that cmdlet is PS7+ only. The project requires PS 5.1 compatibility.
- **Fix:** Replaced with `Get-Content $manifest -Raw | Should -Match 'Find-AdmanUser'` plus a `Get-Command -Module adman` check to verify the function is actually exported.
- **Files modified:** tests/Find.User.Tests.ps1, tests/Find.Computer.Tests.ps1
- **Commit:** 693be32 (Task 5 commit; fix applied before commit).

**4. [Rule 1 - Bug] Parameter sets prevented custom validation error from surfacing**
- **Found during:** Task 5 (first Pester run — "throws when no search criterion is supplied" failed with `Parameter set cannot be resolved`).
- **Issue:** `Find-AdmanUser` used `[Parameter(ParameterSetName = 'ByName')]` etc. on all three parameters. When called with no arguments, PowerShell's parameter-set resolution throws before the function body executes, so the custom `throw 'at least one of...'` never runs.
- **Fix:** Removed parameter sets; all three parameters are now plain optional strings. The function body validates that at least one is supplied and throws the custom error.
- **Files modified:** Public/Find-AdmanUser.ps1
- **Commit:** 693be32 (Task 5 commit; fix applied before commit).

**5. [Rule 1 - Bug] Syntax error in Find-AdmanUser foreach loop**
- **Found during:** Task 5 (file write).
- **Issue:** Initial draft had `foreach $obj in @($raw))` — missing opening parenthesis and extra closing parenthesis.
- **Fix:** Corrected to `foreach ($obj in @($raw))`.
- **Files modified:** Public/Find-AdmanUser.ps1
- **Commit:** 693be32 (Task 5 commit; fix applied before commit).

### Out-of-Scope Discoveries (logged, not fixed)

**Pre-existing lint failure (SAFE-01):** `Invoke-ScriptAnalyzer -Path . -Recurse` reports two parse errors in `.planning/spikes/005-dpapi-vault-roundtrip/Test-CrossUser.ps1` (missing string terminator, missing closing curly brace). This causes the SAFE-01 lint-clean test in `tests/Harness.Tests.ps1` to fail. The spike file was committed in `934c38a` and is not valid PowerShell. This is a pre-existing issue not caused by this plan's changes — confirmed by stashing changes and re-running the test (still fails). Logged to `.planning/phases/01-ad-query-reporting-read-only/deferred-items.md`.

## Authentication Gates

None.

## Known Stubs

None. The Find verbs are fully implemented and return real D-03 schema objects. The menu (`Start-Adman`) already dispatches to these verbs (Plan 01-01); the renderer dispatch (Plan 01-04) will consume the D-03 schema via `$entry.Properties`.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-02-01..T-02-03 mitigated as designed; T-02-SC accepted — zero new dependencies).

## Self-Check: PASSED

- [x] `Public/Find-AdmanUser.ps1` exists — created.
- [x] `Public/Find-AdmanComputer.ps1` exists — created.
- [x] `Private/Reporting/ConvertTo-AdmanResult.ps1` exists — created.
- [x] `Private/Reporting/Test-AdmanInManagedScope.ps1` exists — created.
- [x] `Private/Utility/ConvertTo-AdmanNormalizedDn.ps1` exists — moved from Test-AdmanTargetAllowed.
- [x] `Private/Utility/Escape-AdmanAdFilterLiteral.ps1` exists — created.
- [x] `tests/Find.User.Tests.ps1` exists — created.
- [x] `tests/Find.Computer.Tests.ps1` exists — created.
- [x] `tests/Result.Schema.Tests.ps1` exists — created.
- [x] `tests/Utility.EscapeFilter.Tests.ps1` exists — created.
- [x] `tests/Mocks/ActiveDirectory.psm1` extended — Task 1.
- [x] `adman.psd1` exports Find-AdmanUser and Find-AdmanComputer.
- [x] Commit `2a29a03` (Task 1 mock extension) — found in `git log`.
- [x] Commit `ea6e986` (Task 2 DN normalization extraction) — found in `git log`.
- [x] Commit `08c603b` (Task 3 Escape-AdmanAdFilterLiteral) — found in `git log`.
- [x] Commit `bd508b2` (Task 4 ConvertTo-AdmanResult + Test-AdmanInManagedScope) — found in `git log`.
- [x] Commit `693be32` (Task 5 Find verbs + tests + manifest) — found in `git log`.
- [x] All 82 plan tests green under Pester 6.0.0.
- [x] Full unit suite green (243 passed, 1 pre-existing failure).
- [x] PSScriptAnalyzer 1.25.0 clean on all new implementation files.
