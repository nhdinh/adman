---
phase: 01-ad-query-reporting-read-only
verified: 2026-07-15T00:00:00Z
status: passed
score: 13/13 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 1: AD Query & Reporting (read-only) Verification Report

**Phase Goal:** Admins can launch the TUI, search/view users and computers in scope, and run correct read-only reports (console/CSV/HTML) that prove the team reads AD semantics (timestamps, replication, four account states, lockout counters) correctly before any write consumes them.
**Verified:** 2026-07-15T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Admin launches Start-Adman and sees a numbered flat menu with Q. Quit | ✓ VERIFIED | `Public/Start-Adman.ps1` lines 94-113: single `while ($true)` loop, prints numbered items 1..N from `Get-AdmanMenuDefinition`, plus 'Q. Quit'. 20 MENU tests pass. |
| 2 | Selecting a number prompts for the verb's parameters; B returns to the menu and Q exits from any prompt | ✓ VERIFIED | `Private/Menu/Read-AdmanActionParams.ps1`: B returns `$null` (resumes loop), Q throws `ADMAN_QUIT` sentinel caught by Start-Adman. Empty required input re-prompts once, second empty treated as B. |
| 3 | The menu calls the same Public verb a senior would call directly and outputs the returned PSCustomObject[] | ✓ VERIFIED | `Public/Start-Adman.ps1` line 134: `$reportData = & $Verb @params`. No duplicate implementations. MENU-04 contract test pins verb names. |
| 4 | Each menu entry carries a Properties field listing the D-03 schema column names the verb emits | ✓ VERIFIED | `Private/Menu/Get-AdmanMenuDefinition.ps1`: six entries, each with `Properties` [string[]] pinned per plan (user=16, computer=15, userReport=17, computerReport=16, recovery=5). |
| 5 | Find-AdmanUser returns users scoped to ManagedOUs using exact Properties and ResultPageSize 1000 | ✓ VERIFIED | `Public/Find-AdmanUser.ps1` lines 98-106: loops `$script:Config.ManagedOUs`, calls `Get-ADUser -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC -Properties <D-02 list>`. 22 Find.User tests pass. |
| 6 | Find-AdmanComputer returns computers scoped to ManagedOUs using exact Properties and ResultPageSize 1000 | ✓ VERIFIED | `Public/Find-AdmanComputer.ps1`: identical D-02 invariants. 20 Find.Computer tests pass. |
| 7 | Every emitted object is a normalized PSCustomObject produced by ConvertTo-AdmanResult and passes Test-AdmanInManagedScope | ✓ VERIFIED | `Private/Reporting/ConvertTo-AdmanResult.ps1`: fixed D-03 schema per type. `Private/Reporting/Test-AdmanInManagedScope.ps1`: component-boundary anchored scope check. 24 Result.Schema tests pass. |
| 8 | All user input interpolated into AD -Filter strings passes through Escape-AdmanAdFilterLiteral | ✓ VERIFIED | `Public/Find-AdmanUser.ps1` lines 84-93: every parameter escaped before interpolation. `grep -c Escape-AdmanAdFilterLiteral` = 5 (user), 3 (computer). `grep -c Escape-AdmanLdapFilterValue` = 0 in both. 16 EscapeFilter tests pass. |
| 9 | Get-AdmanStaleReport buckets results as Stale or NeverLoggedOn using replicated lastLogonTimestamp and a self-tuning grace buffer; never queries per-DC lastLogon | ✓ VERIFIED | `Public/Get-AdmanStaleReport.ps1`: uses `lastLogonTimestamp` (replicated), `[datetime]::FromFileTimeUtc`, grace window from `$script:Config.LogonSyncGraceDays`. `grep -c "'lastLogon'"` = 0. 9 Stale tests pass. |
| 10 | Get-AdmanAccountStateReport returns Disabled, Expired, Locked, and PasswordExpired as four distinct states via Search-ADAccount switches, never userAccountControl bit math | ✓ VERIFIED | `Public/Get-AdmanAccountStateReport.ps1`: four `Search-ADAccount` calls with `-AccountDisabled`, `-AccountExpired`, `-LockedOut`, `-PasswordExpired`. `grep -c userAccountControl` = 0. 11 AccountState tests pass. |
| 11 | Initialize-Adman caches the domain logon sync interval and recovery posture for banner and reports | ✓ VERIFIED | `Public/Initialize-Adman.ps1`: 8-step startup including `Get-AdmanLogonSyncInterval` (step 5) and `Get-AdmanRecoveryPosture` (step 6). `Private/Foundation/Get-AdmanLogonSyncInterval.ps1`: MEDIUM-1 conversion matrix (TimeSpan/int/zero/negative/null/exception → 14 fallback). 14 Preflight tests pass. |
| 12 | Format-AdmanReport renders a PSCustomObject[] as a console table and degrades to the same table if a grid picker fails | ✓ VERIFIED | `Public/Format-AdmanReport.ps1`: default `Format-Table -AutoSize \| Out-String -Width 4096`; grid picker capability-probed with silent fallback. 27 Render tests pass. |
| 13 | Export-AdmanReportCsv writes UTF8 CSV with -NoTypeInformation; Export-AdmanReportHtml writes a self-contained single-file HTML report; Get-AdmanInventoryReport returns computer objects with OS version | ✓ VERIFIED | `Public/Export-AdmanReportCsv.ps1`: streaming begin/process/end, `Export-Csv -NoTypeInformation -Encoding UTF8`. `Public/Export-AdmanReportHtml.ps1`: `ConvertTo-Html -Head` with embedded CSS, no external links. `Public/Get-AdmanInventoryReport.ps1`: D-02 computer properties + OS/network attributes. 7 Inventory tests pass. |

**Score:** 13/13 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Public/Start-Adman.ps1` | Flat while-loop TUI dispatcher | ✓ VERIFIED | 238 lines, substantive, wired to menu definition + parameter prompter + renderer dispatch |
| `Private/Menu/Get-AdmanMenuDefinition.ps1` | Six-entry menu table with Properties | ✓ VERIFIED | 102 lines, six entries with pinned Properties arrays |
| `Private/Menu/Read-AdmanActionParams.ps1` | B/Q-aware parameter prompter | ✓ VERIFIED | 109 lines, handles B/Q/empty/choices |
| `Public/Find-AdmanUser.ps1` | Scoped AD user search | ✓ VERIFIED | 117 lines, D-02 invariants + HIGH-1 escaping |
| `Public/Find-AdmanComputer.ps1` | Scoped AD computer search | ✓ VERIFIED | D-02 invariants + HIGH-1 escaping |
| `Private/Reporting/ConvertTo-AdmanResult.ps1` | Canonical D-03 schema mapper | ✓ VERIFIED | 89 lines, fixed schema per type |
| `Private/Reporting/Test-AdmanInManagedScope.ps1` | Scope-only boundary check | ✓ VERIFIED | 43 lines, component-boundary anchored |
| `Private/Utility/ConvertTo-AdmanNormalizedDn.ps1` | Shared DN normalization | ✓ VERIFIED | Moved from Test-AdmanTargetAllowed; `grep -c "function ConvertTo-AdmanNormalizedDn"` in Test-AdmanTargetAllowed.ps1 = 0, call sites = 2 |
| `Private/Utility/Escape-AdmanAdFilterLiteral.ps1` | -Filter string-literal escape | ✓ VERIFIED | 53 lines, single-quote + backslash doubling |
| `Public/Get-AdmanStaleReport.ps1` | RPT-04 stale/never-logged-on report | ✓ VERIFIED | 104 lines, lastLogonTimestamp + grace buffer |
| `Public/Get-AdmanAccountStateReport.ps1` | RPT-05 four-state report | ✓ VERIFIED | 94 lines, four Search-ADAccount switches |
| `Public/Get-AdmanRecoveryPostureReport.ps1` | RPT-07 Public wrapper | ✓ VERIFIED | 59 lines, cache-aware with fallback |
| `Private/Foundation/Get-AdmanLogonSyncInterval.ps1` | D-07 sync-interval read | ✓ VERIFIED | 60 lines, MEDIUM-1 conversion matrix |
| `Public/Format-AdmanReport.ps1` | RPT-01 console renderer | ✓ VERIFIED | 138 lines, grid fallback + empty-result schema |
| `Public/Export-AdmanReportCsv.ps1` | RPT-02 streaming CSV export | ✓ VERIFIED | 140 lines, begin/process/end streaming |
| `Public/Export-AdmanReportHtml.ps1` | RPT-03 self-contained HTML export | ✓ VERIFIED | 212 lines, embedded CSS + boolean string conversion |
| `Public/Get-AdmanInventoryReport.ps1` | RPT-06 OS/inventory report | ✓ VERIFIED | 68 lines, D-02 + inventory attributes |
| `adman.psd1` | Manifest exports all Phase 1 verbs | ✓ VERIFIED | FunctionsToExport includes all 10 Phase 1 public functions |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Start-Adman | Get-AdmanMenuDefinition | `$menu = Get-AdmanMenuDefinition` | ✓ WIRED | Line 92 |
| Start-Adman | Read-AdmanActionParams | `Read-AdmanActionParams -PromptSpec $entry.PromptSpec` | ✓ WIRED | Line 119 |
| Start-Adman | Public verb | `& $Verb @params` | ✓ WIRED | Line 134 |
| Start-Adman | Renderer | `& $renderer -InputObject $reportData @rendererParams` with `-Properties $entry.Properties` | ✓ WIRED | Lines 231-232 |
| Find verbs | Escape-AdmanAdFilterLiteral | `Escape-AdmanAdFilterLiteral -Value $X` before -Filter interpolation | ✓ WIRED | Find-AdmanUser.ps1 lines 84, 88, 92; Find-AdmanComputer.ps1 |
| Find verbs | Get-ADUser/Get-ADComputer | `-SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC` | ✓ WIRED | Find-AdmanUser.ps1 lines 100-106 |
| Find verbs | ConvertTo-AdmanResult | `ConvertTo-AdmanResult -ADObject $obj -ObjectType 'User'` | ✓ WIRED | Find-AdmanUser.ps1 line 108 |
| Find verbs | Test-AdmanInManagedScope | `Test-AdmanInManagedScope -DistinguishedName $mapped.DistinguishedName` | ✓ WIRED | Find-AdmanUser.ps1 line 109 |
| Report verbs | Search-ADAccount | Four state switches with shared splat | ✓ WIRED | Get-AdmanAccountStateReport.ps1 lines 53-73 |
| Report verbs | ConvertTo-AdmanResult | Mapped before scope check | ✓ WIRED | Get-AdmanAccountStateReport.ps1 line 84 |
| Initialize-Adman | Get-AdmanLogonSyncInterval | Step 5 of 8-step startup | ✓ WIRED | Initialize-Adman.ps1 line 49 |
| Initialize-Adman | Get-AdmanRecoveryPosture | Step 6 of 8-step startup | ✓ WIRED | Initialize-Adman.ps1 line 56 |
| Test-AdmanInManagedScope | ConvertTo-AdmanNormalizedDn | Shared utility call | ✓ WIRED | Test-AdmanInManagedScope.ps1 line 33 |
| Test-AdmanTargetAllowed | ConvertTo-AdmanNormalizedDn | Shared utility call (write path) | ✓ WIRED | `grep -c "ConvertTo-AdmanNormalizedDn -Dn"` = 2 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| Start-Adman | `$reportData` | `& $Verb @params` (Public verb output) | Yes — verb returns PSCustomObject[] | ✓ FLOWING |
| Format-AdmanReport | `$rows` | Pipeline input / `-InputObject` | Yes — collected from pipeline | ✓ FLOWING |
| Export-AdmanReportCsv | `$InputObject` | Pipeline input | Yes — streamed row-by-row | ✓ FLOWING |
| Export-AdmanReportHtml | `$rows` | Pipeline input / `-InputObject` | Yes — collected from pipeline | ✓ FLOWING |
| Get-AdmanStaleReport | `$results` | `Get-ADUser` query → ConvertTo-AdmanResult → scope check | Yes — real AD query (mocked in tests) | ✓ FLOWING |
| Get-AdmanAccountStateReport | `$results` | `Search-ADAccount` → ConvertTo-AdmanResult → scope check | Yes — real AD query (mocked in tests) | ✓ FLOWING |
| Get-AdmanInventoryReport | `$results` | `Get-ADComputer` query → ConvertTo-AdmanResult → scope check | Yes — real AD query (mocked in tests) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Unit test suite passes | `Invoke-Pester -Path tests -TagFilter Unit` | 323 passed, 0 failed, 9 NotRun (Integration) | ✓ PASS |
| Module manifest exports all Phase 1 verbs | `grep FunctionsToExport adman.psd1` | All 10 functions listed | ✓ PASS |
| No mutation cmdlets in Phase 1 code | `grep -rEn "Set-AD*\|Remove-AD*\|Disable-ADAccount\|New-AD*" Public/ Private/Menu/ Private/Reporting/ Private/Utility/` | 0 matches (write-gate wrappers in `Private/AD/` are Phase 0, not called by Phase 1) | ✓ PASS |
| CR-01: No scriptblock injection in HTML renderer | `grep -n "scriptblock" Public/Export-AdmanReportHtml.ps1` | Only in comment (line 192); no `[scriptblock]::Create` | ✓ PASS |
| CR-02: ObjectSid populated from SID in account-state report | `grep -n "ObjectSid\|SID" Public/Get-AdmanAccountStateReport.ps1` | Lines 75-82: annotates `ObjectSid = $obj.SID` when SID present | ✓ PASS |
| WR-01: Init guard in all query verbs | `grep -n "not initialized" Public/Find-Adman*.ps1 Public/Get-Adman*.ps1` | All 5 files have the guard | ✓ PASS |
| WR-02: DC failure returns refusal, not throw | `grep -n "try\|catch\|protected-membership" Private/Safety/Test-AdmanTargetAllowed.ps1` | Lines 93-100: try/catch adds to reasons list | ✓ PASS |
| WR-03: Recovery posture tolerates uninitialized config | `grep -n "PSObject.Properties\['DC'\]" Private/Foundation/Get-AdmanRecoveryPosture.ps1` | Line 37: safe property access | ✓ PASS |
| WR-04: No script-scope helper leak | `grep -n "function.*Get-AdmanProp" Private/Reporting/ConvertTo-AdmanResult.ps1` | Line 47: local scope (no `script:` modifier) | ✓ PASS |
| WR-05: CSV header quoting | `grep -n "RFC 4180\|Replace" Public/Export-AdmanReportCsv.ps1` | Lines 111-115: RFC 4180 quoting | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MENU-01 | 01-01 | Admin can launch the tool and see a numbered menu | ✓ SATISFIED | Start-Adman.ps1 lines 94-113; 20 MENU tests pass |
| MENU-02 | 01-01 | Admin can select an action by number and be prompted for required inputs with validation | ✓ SATISFIED | Read-AdmanActionParams.ps1; numeric validation + B/Q handling |
| MENU-03 | 01-01 | Admin can navigate back and quit from any prompt | ✓ SATISFIED | B returns `$null`, Q throws ADMAN_QUIT sentinel; output-format prompt also honors B/Q |
| MENU-04 | 01-01 | Every menu action routes to the same parameterized function a senior can call directly | ✓ SATISFIED | `& $Verb @params` dispatch; no duplicate implementations; contract test pins verb names |
| USER-01 | 01-02 | Admin can search/view users by name, sAMAccountName, or display name (scoped to managed OU) | ✓ SATISFIED | Find-AdmanUser.ps1; 22 tests pass |
| COMP-01 | 01-02 | Admin can search/view computers by name (scoped to managed OU) | ✓ SATISFIED | Find-AdmanComputer.ps1; 20 tests pass |
| RPT-01 | 01-04 | Admin can view results as a console table (and via Out-GridView where available) | ✓ SATISFIED | Format-AdmanReport.ps1; grid fallback tested |
| RPT-02 | 01-04 | Admin can export any report to CSV (-NoTypeInformation) | ✓ SATISFIED | Export-AdmanReportCsv.ps1; streaming + encoding tested |
| RPT-03 | 01-04 | Admin can export any report to a self-contained single-file HTML report | ✓ SATISFIED | Export-AdmanReportHtml.ps1; embedded CSS + no external links tested |
| RPT-04 | 01-03 | Stale/inactive report uses replicated lastLogonTimestamp with ≥14-day grace buffer and buckets never-logged-on separately | ✓ SATISFIED | Get-AdmanStaleReport.ps1; 9 tests pass |
| RPT-05 | 01-03 | Account-state reports render Disabled, Expired, Locked, and Password-Expired as four distinct states via Search-ADAccount | ✓ SATISFIED | Get-AdmanAccountStateReport.ps1; 11 tests pass |
| RPT-06 | 01-04 | Inventory report shows OS version and basic computer info | ✓ SATISFIED | Get-AdmanInventoryReport.ps1; 7 tests pass |
| RPT-07 | 01-03 | Startup preflight reports domain recovery posture (Recycle Bin / FFL) | ✓ SATISFIED | Get-AdmanRecoveryPostureReport.ps1 + Initialize-Adman caching; 6 Recovery tests + 14 Preflight tests pass |

**Orphaned requirements:** None. All 13 Phase 1 requirements are accounted for in plans and verified.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No debt markers (TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER), no placeholder language, no empty implementations, no hardcoded empty data flowing to rendering, no console.log-only implementations.

### Human Verification Required

None. All truths are verified by automated tests (323 passing) and structural checks. The phase is read-only; no visual appearance, real-time behavior, or external service integration requires human validation.

### Gaps Summary

No gaps. All 13 must-have truths are verified. All 7 code-review fixes (CR-01, CR-02, WR-01..05) hold in the actual code. The read-only constraint is preserved — no mutation cmdlets exist in Phase 1 shipped code paths. The unit test suite is green (323 passed, 0 failed).

**Note on PSFramework dependency:** The module manifest declares `RequiredModules = @(PSFramework)`. The real PSFramework module is not installed on this dev host, but the Pester tests create a throwaway stub on `$TestDrive` to satisfy the dependency during unit testing. This is a documented test pattern (see `tests/Audit.FailClosed.Tests.ps1` lines 31-48), not a gap. Production deployment requires PSFramework installation per Phase 0 prerequisites.

---

_Verified: 2026-07-15T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
