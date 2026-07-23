---
phase: 01-ad-query-reporting-read-only
plan: 04
subsystem: reporting
tags: [rpt-01, rpt-02, rpt-03, rpt-06, renderer, csv, html, inventory, wave-3]
dependency_graph:
  requires:
    - Private/Menu/Get-AdmanMenuDefinition.ps1 (Plan 01-01, per-entry Properties schema)
    - Private/Reporting/ConvertTo-AdmanResult.ps1 (Plan 01-02, D-03 schema mapper)
    - Private/Reporting/Test-AdmanInManagedScope.ps1 (Plan 01-02, scope check)
    - Public/Get-AdmanStaleReport.ps1 / Get-AdmanAccountStateReport.ps1 (Plan 01-03, report verbs)
  provides:
    - Public/Format-AdmanReport.ps1 (RPT-01 console renderer + optional grid picker)
    - Public/Export-AdmanReportCsv.ps1 (RPT-02 streaming CSV export)
    - Public/Export-AdmanReportHtml.ps1 (RPT-03 self-contained HTML export)
    - Public/Get-AdmanInventoryReport.ps1 (RPT-06 OS/inventory report)
    - tests/Render.Tests.ps1 (renderer contract)
    - tests/Report.Inventory.Tests.ps1 (inventory contract)
  affects:
    - Phase 2+ (any report verb can now render to console/CSV/HTML via the menu)
tech_stack:
  added: []
  patterns:
    - RPT-01: Format-Table -AutoSize | Out-String -Width 4096; grid picker capability-probed with silent fallback
    - RPT-02: begin/process/end streaming with explicit first-row handling (first row creates file, subsequent rows append)
    - RPT-03: ConvertTo-Html -Head with embedded CSS fragment; boolean columns emitted as 'True'/'False' strings
    - RPT-06: D-02 computer properties + OS/network attributes; Bucket column = 'Inventory'
    - Cycle 4: Start-Adman reads $entry.Properties and passes it as -Properties to the renderer for zero-row header-only output
key_files:
  created:
    - Public/Format-AdmanReport.ps1
    - Public/Export-AdmanReportCsv.ps1
    - Public/Export-AdmanReportHtml.ps1
    - Public/Get-AdmanInventoryReport.ps1
    - tests/Render.Tests.ps1
    - tests/Report.Inventory.Tests.ps1
  modified:
    - Public/Start-Adman.ps1
    - tests/Menu.Tests.ps1
    - adman.psd1
decisions:
  - CSV renderer uses begin/process/end with explicit first-row handling (first row creates file without -Append, subsequent rows use -Append) to keep memory O(1)
  - HTML renderer collects full input because ConvertTo-Html requires it; documents ~10,000-row soft bound and directs callers to CSV for larger sets
  - Boolean columns rendered as literal strings 'True'/'False' via calculated properties before ConvertTo-Html (LOW finding resolution; .true/.false CSS rules remain as forward-compatible hooks)
  - Empty-result schema: callers pass -Properties with D-03 column list so zero-row reports still render headers (Cycle 2/3 finding)
  - Start-Adman uses labeled break (:menuLoop) instead of break 2/3 for reliable loop exit from nested output-format/path-validation loops
  - Start-Adman calls renderer with -InputObject explicit parameter instead of pipeline to ensure the renderer executes even when the report data array is empty
metrics:
  duration: 25m
  completed_date: 2026-07-15
  tasks: 3
  files_created: 6
  files_modified: 3
  tests_added: 62
status: complete
---

# Phase 01 Plan 04: Output Layer & Inventory Report Summary

**One-liner:** Three pure D-03 renderers (console, streaming CSV, self-contained HTML) plus the OS/inventory report verb, wired into the Start-Adman menu with per-entry Properties propagation for zero-row header-only output — 62 green Pester 6 contract tests proving RPT-01, RPT-02, RPT-03, and RPT-06.

## What Was Built

### Public/Format-AdmanReport.ps1 (new)

RPT-01 console renderer. Accepts pipeline input, an optional `-UseGridView` switch, and an optional `-Properties` string array used only when the pipeline is empty.

- **Default:** `Format-Table -AutoSize | Out-String -Width 4096` emitted as a single string.
- **Grid picker:** capability-probed. Desktop edition + interactive + `Out-GridView` available -> `Out-GridView`. Core edition + `Microsoft.PowerShell.ConsoleGuiTools` -> `Out-ConsoleGridView`. Any failure silently degrades to the console table.
- **Memory bound (MEDIUM-4):** bounded by host display buffer; documents ~10,000-row soft bound and directs callers to `Export-AdmanReportCsv` for larger sets.
- **Empty-result schema (Cycle 2/3 finding):** zero rows + `-Properties` -> header-only table built from the property list (one row of column names, no data rows). Zero rows + no `-Properties` -> literal string `'(no results)'`.

### Public/Export-AdmanReportCsv.ps1 (new)

RPT-02 streaming CSV renderer. Accepts pipeline input, mandatory `-Path`, and optional `-Properties`.

- **Streaming (MEDIUM-4 + Cycle 2/3 finding):** begin/process/end structure with explicit first-row handling. Memory stays O(1) in the row count.
  - `begin`: validates parent directory exists (throws if not); removes stale file at `-Path` so reruns do not append onto old data; resets first-row flag.
  - `process`: first input object -> `Export-Csv -NoTypeInformation -Encoding UTF8` (creates file with headers). Subsequent objects -> `Export-Csv -Append -NoTypeInformation -Encoding UTF8` (appends data row, no duplicate header).
  - `end`: empty pipeline + `-Properties` -> single header line via `Out-File -Encoding UTF8` (UTF8 with BOM). Empty pipeline + no `-Properties` -> zero-byte file + verbose message.
- **T-04-01:** parent directory is NEVER auto-created; a missing directory throws so the operator notices the path.

### Public/Export-AdmanReportHtml.ps1 (new)

RPT-03 self-contained HTML renderer. Accepts pipeline input, mandatory `-Path`, optional `-Title` (default `'adman report'`), and optional `-Properties`.

- **Embedded CSS:** single here-string fragment passed to `ConvertTo-Html -Head`. Matches UI-SPEC contract (body, h1, .metadata, table, th, td, zebra striping, .true/.false classes). No external CSS, no JavaScript, no PS6+ parameters (`-CssUri`, `-Charset`, `-Meta`, `-Transitional` are NOT used).
- **Boolean cells (LOW finding resolution):** `Enabled`, `LockedOut`, `PasswordExpired`, `RecycleBinEnabled` are emitted as literal strings `'True'`/`'False'` via calculated properties BEFORE piping to `ConvertTo-Html`. The `.true`/`.false` CSS rules remain as forward-compatible hooks but are not load-bearing in v1.
- **Memory bound (MEDIUM-4):** MUST collect full input because `ConvertTo-Html` requires it. Documents ~10,000-row soft bound and directs callers to CSV for larger sets.
- **Empty-result schema (Cycle 2/3 finding):** zero rows + `-Properties` -> single-row "header prototype" PSCustomObject piped to `ConvertTo-Html`, then post-processed to remove the single `<tr>` data row (leaving `<table>` with header row and zero data rows). Zero rows + no `-Properties` -> minimal HTML document with title and `'(no results)'` inside a `<p>` tag, no `<table>` element.
- **T-04-01:** parent directory validated before writing.

### Public/Get-AdmanInventoryReport.ps1 (new)

RPT-06 computer OS/inventory report.

- **D-02 invariants:** loops `$script:Config.ManagedOUs`; `Get-ADComputer -Filter * -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC -Properties <D-02 list + OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack, IPv4Address, DNSHostName>`.
- **Scope re-check:** every object passes through `Test-AdmanInManagedScope`; out-of-scope dropped.
- **D-03 mapping:** each object mapped through `ConvertTo-AdmanResult -ObjectType Computer` and annotated with `Bucket = 'Inventory'` via `Add-Member -Force`.

### Public/Start-Adman.ps1 (modified)

Renderer dispatch separated from parameter prompting per D-04.

- After the selected Public verb returns its `PSCustomObject[]`, presents an inline output-format prompt (1=console, 2=CSV, 3=HTML, 4=grid if available, B=back, Q=quit).
- For CSV/HTML, prompts for the output path and validates the parent directory exists before invoking the renderer; on invalid path, re-prompts once then treats a second failure as 'B'.
- **Properties propagation (Cycle 4 finding):** reads the selected menu entry's `Properties` field (from `Get-AdmanMenuDefinition`) and passes it as `-Properties` to the chosen renderer. Guarantees zero-row reports render headers from the D-03 schema.
- Dispatches via `& $renderer -InputObject $reportData @rendererParams`.
- Honors 'B' to return to the top-level menu and 'Q' to exit `Start-Adman` from the output-format prompt.

### tests/Render.Tests.ps1 (new)

27 Pester 6 assertions covering:
- Console table output (headers + row values), multiple rows, grid-view fallback on failure.
- CSV encoding/NoTypeInformation, multi-row streaming (exactly one header row + three data rows), stale-file removal, parent-directory validation.
- CSV empty-result with `-Properties` (exactly one header line, zero data rows) and without `-Properties` (zero-byte file, no exception).
- Console empty-result with `-Properties` (header-only table) and without `-Properties` (literal `'(no results)'`).
- HTML embedded style block, no external stylesheet link, report title, populated table for non-empty input, boolean columns as `'True'`/`'False'` strings.
- HTML empty-result with `-Properties` (`<table>` with header row, zero `<tr>` data rows) and without `-Properties` (`'(no results)'` text, no `<table>`).
- PS 5.1/7 parity: no `-AsHashtable`, no `??`/`?.` operators, no PS6+ `ConvertTo-Html` parameters.

### tests/Report.Inventory.Tests.ps1 (new)

7 Pester 6 assertions covering:
- D-02 computer properties plus inventory attributes requested.
- `-Filter *` with `-SearchScope Subtree` and `-ResultPageSize 1000`.
- Returns computer objects with `OperatingSystem`, `OperatingSystemVersion`, `IPv4Address`, `DNSHostName`.
- `Bucket` column set to `'Inventory'` on every row.
- Out-of-scope objects dropped via `Test-AdmanInManagedScope`.
- D-03 schema objects with no raw AD property leakage.

### tests/Menu.Tests.ps1 (modified)

Added MENU-05 and MENU-06 Describe blocks (8 new tests, 28 total):
- **MENU-05:** B at output-format prompt returns to top-level menu; Q exits `Start-Adman`; invalid input re-prompts with standard copy.
- **MENU-06 (Cycle 4 finding):** zero-row dispatch tests proving `Start-Adman` passes the menu entry's `-Properties` to CSV/HTML/Console renderers.
  - CSV: zero-row verb -> file with exactly one header row matching menu entry Properties, zero data rows.
  - HTML: zero-row verb -> file with header row matching menu entry Properties, no data rows.
  - Console: zero-row verb -> header-only table (not `'(no results)'` literal).
  - Mock-capture test asserts renderer received `-Properties` equal to the menu entry's Properties.

### adman.psd1 (modified)

`FunctionsToExport` extended with `Format-AdmanReport`, `Export-AdmanReportCsv`, `Export-AdmanReportHtml`, `Get-AdmanInventoryReport`.

## Verification

- `Invoke-Pester -Path tests/Render.Tests.ps1,tests/Report.Inventory.Tests.ps1,tests/Menu.Tests.ps1 -Output Detailed` -> **62 passed, 0 failed** (Pester 6.0.0).
- `Invoke-Pester -Path tests -Output Normal -TagFilter Unit` -> **322 passed, 0 failed** (full unit suite; 9 NotRun are Integration-tagged).
- `Invoke-ScriptAnalyzer` on all new/modified implementation files -> **clean** (PSScriptAnalyzer 1.25.0).
- `grep -c "Export-Csv.*-Append" Public/Export-AdmanReportCsv.ps1` -> **3** (>= 1).
- `grep -c "\$InputObject\s*\|\s*Export-Csv" Public/Export-AdmanReportCsv.ps1` -> **0**.
- `grep -c "-Properties" Public/Start-Adman.ps1` -> **1** (>= 1 in dispatch path).
- `grep -c "\$entry\.Properties" Public/Start-Adman.ps1` -> **1**.
- `adman.psd1` exports all four new public functions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `break 2` / `break 3` caused infinite hang in output-format prompt**
- **Found during:** Task 3 verification (MENU-05 Q test hung).
- **Issue:** PowerShell's `break <count>` did not reliably exit the nested `while` loops in `Start-Adman`. The `break 2` inside the output-format loop and `break 3` inside the CSV/HTML path-validation loops caused the function to hang when the operator typed Q.
- **Fix:** Replaced numeric breaks with a labeled break `:menuLoop while ($true)` and `break menuLoop` at all three exit points.
- **Files modified:** Public/Start-Adman.ps1
- **Commit:** 5f884c9

**2. [Rule 1 - Bug] Pipeline dispatch to renderer skipped execution on empty report data**
- **Found during:** Task 3 verification (MENU-06 mock-capture test failed with `$null` captured Properties).
- **Issue:** `$reportData | & $renderer @rendererParams` uses pipeline binding. When `$reportData` is an empty array, PowerShell does not execute the renderer's `process` block, so the mock/scriptblock body never ran and `-Properties` was never captured.
- **Fix:** Changed dispatch to `& $renderer -InputObject $reportData @rendererParams`. Explicit parameter binding ensures the renderer executes even when the input array is empty.
- **Files modified:** Public/Start-Adman.ps1
- **Commit:** 5f884c9

**3. [Rule 1 - Bug] Format-Table -AutoSize truncated columns in empty-result header-only table**
- **Found during:** Task 3 verification (MENU-06 Console test failed: expected `PasswordExpired` in output but it was truncated).
- **Issue:** `Format-Table -AutoSize` on a single empty-string prototype object calculated column widths from the data and dropped columns that didn't fit.
- **Fix:** Added `-Property @($proto.Keys)` to force `Format-Table` to include all specified columns.
- **Files modified:** Public/Format-AdmanReport.ps1
- **Commit:** 5f884c9

**4. [Rule 1 - Bug] Mock Read-Host scope mismatch in Menu.Tests.ps1**
- **Found during:** Task 3 verification (MENU-05/06 tests hung or failed).
- **Issue:** Tests used `$script:answers` and `$script:answerIdx` for the `Read-Host` mock. When the mock executed inside the `adman` module scope, `$script:` resolved to the module's script scope, not the test file's scope, so the mock returned `$null` and `Start-Adman` hung waiting for input.
- **Fix:** Changed all mock answer variables to `$global:answers` and `$global:answerIdx` (and `$global:capturedProperties` for the mock-capture test).
- **Files modified:** tests/Menu.Tests.ps1
- **Commit:** 5f884c9

**5. [Rule 1 - Bug] Static dispatch-pattern test broke after -InputObject fix**
- **Found during:** Task 3 verification (MENU-04 dispatch test failed).
- **Issue:** The test asserted `& $renderer @rendererParams` but the fix for empty-array dispatch changed the call to `& $renderer -InputObject $reportData @rendererParams`.
- **Fix:** Updated the test regex to match the new dispatch pattern.
- **Files modified:** tests/Menu.Tests.ps1
- **Commit:** 5f884c9

### Out-of-Scope Discoveries (logged, not fixed)

None.

## Authentication Gates

None.

## Known Stubs

None. All four renderers and the inventory report are fully implemented and return real output. The menu dispatches to them with `-Properties` propagated from the menu entry.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan's `<threat_model>` already covers (T-04-01..T-04-04 mitigated as designed; T-04-SC accepted — zero new dependencies).

## Self-Check: PASSED

- [x] `Public/Format-AdmanReport.ps1` exists — created.
- [x] `Public/Export-AdmanReportCsv.ps1` exists — created.
- [x] `Public/Export-AdmanReportHtml.ps1` exists — created.
- [x] `Public/Get-AdmanInventoryReport.ps1` exists — created.
- [x] `tests/Render.Tests.ps1` exists — created.
- [x] `tests/Report.Inventory.Tests.ps1` exists — created.
- [x] `Public/Start-Adman.ps1` modified — renderer dispatch + Properties propagation.
- [x] `tests/Menu.Tests.ps1` modified — MENU-05/06 tests.
- [x] `adman.psd1` exports all four new public functions.
- [x] Commit `441befa` (Task 1 console + CSV renderers) — found in `git log`.
- [x] Commit `2f64bc5` (Task 2 HTML renderer) — found in `git log`.
- [x] Commit `5f884c9` (Task 3 inventory + menu wiring + manifest) — found in `git log`.
- [x] All 62 plan tests green under Pester 6.0.0.
- [x] Full unit suite green (322 passed, 0 failed).
- [x] PSScriptAnalyzer 1.25.0 clean on all new/modified implementation files.
