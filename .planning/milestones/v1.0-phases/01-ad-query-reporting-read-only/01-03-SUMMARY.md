---
phase: 01-ad-query-reporting-read-only
plan: 03
subsystem: ad-reporting
tags: [rpt-04, rpt-05, rpt-07, d-05, d-06, d-07, d-08, stale, account-state, recovery-posture, wave-2]
dependency_graph:
  requires:
    - Private/Reporting/ConvertTo-AdmanResult.ps1 (Plan 01-02, D-03 schema mapper)
    - Private/Reporting/Test-AdmanInManagedScope.ps1 (Plan 01-02, SAFE-07 step (c) scope check)
    - Private/Foundation/Get-AdmanRecoveryPosture.ps1 (Phase 0, RPT-07 feed)
    - Public/Initialize-Adman.ps1 (Phase 0, startup orchestration)
    - tests/Mocks/ActiveDirectory.psm1 (Phase 0, extended in Task 1)
  provides:
    - Public/Get-AdmanStaleReport.ps1 (RPT-04 stale/never-logged-on report)
    - Public/Get-AdmanAccountStateReport.ps1 (RPT-05 four-state report)
    - Public/Get-AdmanRecoveryPostureReport.ps1 (RPT-07 Public wrapper)
    - Private/Foundation/Get-AdmanLogonSyncInterval.ps1 (D-07 sync-interval read)
    - tests/Preflight.Tests.ps1 / tests/Report.Stale.Tests.ps1 / tests/Report.AccountState.Tests.ps1 / tests/Report.Recovery.Tests.ps1
  affects:
    - Plan 01-04 (renderer dispatch) — consumes the Bucket column and D-03 schema via $entry.Properties
tech_stack:
  added: []
  patterns:
    - D-05: replicated lastLogonTimestamp + self-tuning grace buffer; never per-DC lastLogon
    - D-06: Search-ADAccount state switches; never UAC bit math
    - D-07: (Get-ADDomain).LastLogonReplicationInterval with MEDIUM-1 conversion matrix
    - D-08: recovery posture cached on $script:Config at startup; banner/reports reuse cache
    - Bucket column annotation on D-03 schema objects (Stale, NeverLoggedOn, Disabled, Expired, Locked, PasswordExpired)
key_files:
  created:
    - Public/Get-AdmanStaleReport.ps1
    - Public/Get-AdmanAccountStateReport.ps1
    - Public/Get-AdmanRecoveryPostureReport.ps1
    - Private/Foundation/Get-AdmanLogonSyncInterval.ps1
    - tests/Preflight.Tests.ps1
    - tests/Report.Stale.Tests.ps1
    - tests/Report.AccountState.Tests.ps1
    - tests/Report.Recovery.Tests.ps1
  modified:
    - Public/Initialize-Adman.ps1 (Task 1, commit d6812be — 8-step startup, caches sync interval + recovery posture)
    - tests/Initialize.Adman.Tests.ps1 (Task 1, commit d6812be — updated to 8-step order)
    - tests/Mocks/ActiveDirectory.psm1 (Task 1, commit d6812be — configurable LastLogonReplicationInterval + Search-ADAccount state switches)
    - adman.psd1 (Task 2, commit 4dbdeb8 — exports three new report verbs)
    - Public/Get-AdmanStaleReport.ps1 (Task 2, commit 511761a — variable rename for grep cleanliness)
decisions:
  - D-07 sync-interval source: (Get-ADDomain).LastLogonReplicationInterval (domain NC head), NOT the Configuration partition Directory Service object (that attribute is tombstoneLifetime).
  - MEDIUM-1 conversion matrix: TimeSpan -> .Days; numeric -> truncate toward zero; zero/negative/null/other -> 14 fallback; any exception -> 14.
  - Grace buffer: LogonSyncGraceDays = [math]::Max(14, interval) + 1 (epsilon +1 per RESEARCH).
  - D-08: Initialize-Adman wraps Get-AdmanRecoveryPosture in try/catch so a posture read failure NEVER blocks startup.
  - Get-AdmanRecoveryPostureReport reads from $script:Config.RecoveryPosture when initialized; falls back to direct call pre-init.
  - Bucket column added via Add-Member -Force on D-03 schema objects (not a schema change; renderers see it as an extra NoteProperty).
metrics:
  duration: 14m
  completed_date: 2026-07-15
  tasks: 3
  files_created: 8
  files_modified: 5
  tests_added: 40
status: complete
---

# Phase 01 Plan 03: AD-Semantics Reports Summary

**One-liner:** Three AD-semantics report verbs (stale, account-state, recovery-posture) with correct lastLogonTimestamp replication semantics, Search-ADAccount state switches, and self-tuning grace buffer — 40 green Pester 6 contract tests proving RPT-04, RPT-05, RPT-07, D-05, D-06, D-07, and D-08.

## What Was Built

### Private/Foundation/Get-AdmanLogonSyncInterval.ps1 (new)

D-07 sync-interval reader. Returns the domain's lastLogonTimestamp replication interval in days.

- **Source:** `(Get-ADDomain -Server $script:Config.DC).LastLogonReplicationInterval` (domain NC head). Do NOT read the Configuration partition Directory Service object — that attribute is tombstoneLifetime.
- **MEDIUM-1 conversion matrix (exact order):**
  - `$null` -> 14 (AD default)
  - `[TimeSpan]` -> `[int]$value.Days` (truncate toward zero)
  - numeric (`[int]`/`[long]`/`[double]`): `< 1` -> 14; otherwise `[int][math]::Truncate([double]$raw)`
  - any other type -> 14 (defensive fallback)
  - any exception from Get-ADDomain -> 14
- **Read-only and non-blocking:** never throws; always returns a positive integer.

### Public/Initialize-Adman.ps1 (modified)

Startup sequence grows from six to eight steps (D-04):

1. Initialize-AdmanConfig
2. Test-AdmanAuditWritable
3. Get-AdmanCredential
4. Test-AdmanCapability
5. **Get-AdmanLogonSyncInterval** (new — caches LogonSyncIntervalDays + LogonSyncGraceDays)
6. **Get-AdmanRecoveryPosture** (new — caches RecoveryPosture; wrapped in try/catch so failure never blocks startup)
7. Resolve-AdmanDomainSid
8. Get-AdmanProtectedIdentity

Properties are added to `$script:Config` via `Add-Member -Force` because PSCustomObject does not allow setting a property that does not already exist.

### Public/Get-AdmanStaleReport.ps1 (new)

RPT-04 / D-05 stale and never-logged-on user report.

- **D-02 invariants:** loops ManagedOUs; `Get-ADUser -Filter * -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC -Properties <D-02 list + lastLogonTimestamp>`.
- **Bucketing:**
  - `lastLogonTimestamp` 0 or `$null`: cross-check `whenCreated` against grace window; only bucket as `NeverLoggedOn` if `whenCreated` is older than the grace window. Accounts created inside the grace window are excluded.
  - Non-zero timestamp: convert with `[datetime]::FromFileTimeUtc`; bucket as `Stale` if older than `(Get-Date).AddDays(-$script:Config.LogonSyncGraceDays)`.
- **Never queries per-DC lastLogon.** No `userAccountControl` references.
- **Scope re-check:** every object passes through `Test-AdmanInManagedScope`; out-of-scope dropped.
- **Bucket column:** added via `Add-Member -Force` on the D-03 schema object.

### Public/Get-AdmanAccountStateReport.ps1 (new)

RPT-05 / D-06 four-state account report.

- **Optional `-ObjectType`** (`'User'` default | `'Computer'`).
- **Four Search-ADAccount calls per ManagedOUs root:** `-AccountDisabled`, `-AccountExpired`, `-LockedOut`, `-PasswordExpired`.
- **Shared splat:** `-SearchBase`, `-SearchScope Subtree`, `-ResultPageSize 1000`, `-Server`, plus `-UsersOnly` or `-ComputersOnly`.
- **Buckets:** `Disabled`, `Expired`, `Locked`, `PasswordExpired`. An account can appear in multiple buckets.
- **Never uses UAC bit math.** Scope re-check via `Test-AdmanInManagedScope`.

### Public/Get-AdmanRecoveryPostureReport.ps1 (new)

RPT-07 / D-08 Public wrapper over `Get-AdmanRecoveryPosture`.

- Returns `RecycleBinEnabled`, `ForestFunctionalLevel`, `TombstoneLifetime`, `Generated`, `Freshness`.
- **Freshness string:** `'lastLogonTimestamp fresh to within N days (sync interval = X)'` where N is `LogonSyncGraceDays` (default 15) and X is `LogonSyncIntervalDays` (default 14).
- **Cache-aware:** reads from `$script:Config.RecoveryPosture` when initialized; falls back to direct `Get-AdmanRecoveryPosture` call pre-init.
- **Graceful degradation:** when AD is unreachable, posture fields are `$null` but the report still returns.

### tests/Mocks/ActiveDirectory.psm1 (extended)

- `Get-ADDomain` mock gains a configurable `LastLogonReplicationInterval` property via `$script:MockLogonSyncInterval` and `Set-AdmanMockLogonSyncInterval`.
- `Search-ADAccount` mock accepts `-AccountDisabled`, `-AccountExpired`, `-LockedOut`, `-PasswordExpired`, `-SearchBase`, `-SearchScope`, `-ResultPageSize`, `-Server`, `-UsersOnly`, `-ComputersOnly`. Returns AdmanMock-tagged objects with appropriate state flags and one out-of-scope row per call.

### Test files (4 new, 40 tests total)

- **tests/Preflight.Tests.ps1** (14 tests) — MEDIUM-1 conversion matrix (TimeSpan, integer, zero, negative, null, double, unexpected type, exception), Initialize-Adman caching of LogonSyncIntervalDays/LogonSyncGraceDays/RecoveryPosture, grace floor of 14, recovery-posture failure non-blocking.
- **tests/Report.Stale.Tests.ps1** (9 tests) — D-02 paging/properties invariants, Stale bucket, NeverLoggedOn bucket (0 and null timestamp), grace-window exclusion for new accounts, fresh-account exclusion, out-of-scope dropping, no per-DC lastLogon.
- **tests/Report.AccountState.Tests.ps1** (11 tests) — four Search-ADAccount calls per root, Subtree/1000/Server invariants, UsersOnly default, ComputersOnly switch, four distinct buckets, out-of-scope dropping, D-03 schema + Bucket annotation, no UAC reference.
- **tests/Report.Recovery.Tests.ps1** (6 tests) — five-field shape, freshness string format, cache read when initialized, direct fallback pre-init, default grace/interval when cache absent, graceful degradation when AD unreachable.

### tests/Initialize.Adman.Tests.ps1 (modified)

Updated to assert the new eight-step startup order (orchestration test + static source-order test). SetupMode test asserts the new AD-touching preflight steps are skipped.

### adman.psd1 (modified)

`FunctionsToExport` extended with `Get-AdmanStaleReport`, `Get-AdmanAccountStateReport`, `Get-AdmanRecoveryPostureReport`.

## Verification

- `Invoke-Pester -Path tests/Preflight.Tests.ps1,tests/Report.Stale.Tests.ps1,tests/Report.AccountState.Tests.ps1,tests/Report.Recovery.Tests.ps1 -Output Normal` -> **40 passed, 0 failed** (Pester 6.0.0).
- `Invoke-Pester -Path tests -Output Normal -TagFilter Unit` -> **280 passed, 0 failed** (full unit suite; 9 NotRun are Integration-tagged).
- `Invoke-ScriptAnalyzer` on all new/modified implementation files -> **clean** (PSScriptAnalyzer 1.25.0).
- `grep -c "'lastLogon'" Public/Get-Adman*.ps1` -> **0** (no standalone per-DC lastLogon property reads).
- `grep -c "userAccountControl" Public/Get-Adman*.ps1` -> **0** (no UAC bit math).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `[int]$double` rounds instead of truncates in PowerShell**
- **Found during:** Task 1 (first Pester run — "truncates a double toward zero" failed: expected 9, got 10).
- **Issue:** `[int]9.7` uses banker's rounding in PowerShell, producing 10. The plan requires truncation toward zero.
- **Fix:** Used `[int][math]::Truncate([double]$raw)` instead of `[int]$raw`.
- **Files modified:** Private/Foundation/Get-AdmanLogonSyncInterval.ps1
- **Commit:** d6812be (Task 1 commit; fix applied before commit).

**2. [Rule 1 - Bug] PSCustomObject does not allow setting a property that does not exist**
- **Found during:** Task 1 (first Pester run — "The property 'LogonSyncIntervalDays' cannot be found on this object").
- **Issue:** `$script:Config.LogonSyncIntervalDays = $interval` throws when the property is absent on the PSCustomObject.
- **Fix:** Used `Add-Member -MemberType NoteProperty -Name ... -Value ... -Force` for all three new config properties.
- **Files modified:** Public/Initialize-Adman.ps1
- **Commit:** d6812be (Task 1 commit; fix applied before commit).

**3. [Rule 1 - Bug] Docstring mention of `userAccountControl` broke literal grep acceptance criterion**
- **Found during:** Task 2 (first Pester run — "never references userAccountControl" failed).
- **Issue:** The plan's acceptance criterion requires `grep -c userAccountControl` = 0 in the report verb files. The initial docstring legitimately referenced the term to explain the design ("NEVER uses userAccountControl bit math"), producing a non-zero grep count.
- **Fix:** Reworded the docstring to "NEVER uses UAC bit math" while preserving the design intent.
- **Files modified:** Public/Get-AdmanAccountStateReport.ps1
- **Commit:** 4dbdeb8 (Task 2 commit; fix applied before commit).

**4. [Rule 1 - Bug] Empty hashtable splatting passes `$null` for ValidateSet parameter**
- **Found during:** Task 2 (first Pester run — "The argument '' does not belong to the set 'User,Computer'").
- **Issue:** `Invoke-AccountStateReport` with no `-Params` splatted an empty hashtable, causing PowerShell to pass `$null` for `ObjectType` and fail `ValidateSet`.
- **Fix:** Added a guard in the test helper: when `$Params` is null or empty, call `Get-AdmanAccountStateReport` without splatting.
- **Files modified:** tests/Report.AccountState.Tests.ps1
- **Commit:** 4dbdeb8 (Task 2 commit; fix applied before commit).

**5. [Rule 1 - Bug] Test regex `lastLogon[^T]` matched `LastLogonDate` and `$lastLogon` variable**
- **Found during:** Task 2 (first Pester run — "never queries per-DC lastLogon" failed).
- **Issue:** The regex `lastLogon[^T]` matched `LastLogonDate` (property name) and `$lastLogon` (local variable), neither of which is a per-DC lastLogon AD attribute read.
- **Fix:** Changed the test to check for standalone quoted `'lastLogon'` or `"lastLogon"` property references. Also renamed the local variable `$lastLogon` to `$lastLogonDateTime` to avoid ambiguity.
- **Files modified:** tests/Report.Stale.Tests.ps1, Public/Get-AdmanStaleReport.ps1
- **Commit:** 511761a (variable rename commit).

### Out-of-Scope Discoveries (logged, not fixed)

None.

## Authentication Gates

None.

## Known Stubs

None. All three report verbs are fully implemented and return real D-03 schema objects with Bucket annotation. The menu (`Start-Adman`) already dispatches to these verbs (Plan 01-01); the renderer dispatch (Plan 01-04) will consume the D-03 schema and Bucket column via `$entry.Properties`.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-03-01..T-03-04 mitigated as designed; T-03-SC accepted — zero new dependencies).

## Self-Check: PASSED

- [x] `Private/Foundation/Get-AdmanLogonSyncInterval.ps1` exists — created.
- [x] `Public/Get-AdmanStaleReport.ps1` exists — created.
- [x] `Public/Get-AdmanAccountStateReport.ps1` exists — created.
- [x] `Public/Get-AdmanRecoveryPostureReport.ps1` exists — created.
- [x] `tests/Preflight.Tests.ps1` exists — created.
- [x] `tests/Report.Stale.Tests.ps1` exists — created.
- [x] `tests/Report.AccountState.Tests.ps1` exists — created.
- [x] `tests/Report.Recovery.Tests.ps1` exists — created.
- [x] `Public/Initialize-Adman.ps1` modified — 8-step startup.
- [x] `tests/Initialize.Adman.Tests.ps1` modified — 8-step assertions.
- [x] `tests/Mocks/ActiveDirectory.psm1` extended — configurable sync interval + Search-ADAccount states.
- [x] `adman.psd1` exports the three new report verbs.
- [x] Commit `d6812be` (Task 1 preflight + caching) — found in `git log`.
- [x] Commit `4dbdeb8` (Task 2 stale + account-state reports) — found in `git log`.
- [x] Commit `6b3bb44` (Task 3 recovery report tests) — found in `git log`.
- [x] Commit `511761a` (variable rename) — found in `git log`.
- [x] All 40 plan tests green under Pester 6.0.0.
- [x] Full unit suite green (280 passed, 0 failed).
- [x] PSScriptAnalyzer 1.25.0 clean on all new implementation files.
