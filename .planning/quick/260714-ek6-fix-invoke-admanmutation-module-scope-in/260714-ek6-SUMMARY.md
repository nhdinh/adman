---
phase: quick-260714-ek6
plan: 01
subsystem: tests/safety
tags: [tests, integration, safety, pester, module-scope]
status: complete
requires:
  - adman module with internal Invoke-AdmanMutation gate (SAFE-08)
provides:
  - Lab integration tests that resolve the non-exported gate via module scope
affects:
  - tests/Safety.WhatIf.Integration.Tests.ps1
  - tests/Safety.Protected.Integration.Tests.ps1
tech-stack:
  added: []
  patterns:
    - "& (Get-Module adman) { param($t) ... } <args> for invoking non-exported module functions from Pester"
key-files:
  created: []
  modified:
    - tests/Safety.WhatIf.Integration.Tests.ps1
    - tests/Safety.Protected.Integration.Tests.ps1
decisions:
  - "Pass target DN(s) into the module-scope scriptblock as param($t) because $script: test variables are not visible inside module scope."
metrics:
  duration: "~5m"
  completed: "2026-07-14"
  tasks: 1
  files: 2
---

# Phase quick-260714-ek6 Plan 01: Fix Invoke-AdmanMutation module scope in integration tests Summary

Wrapped all 4 `Invoke-AdmanMutation` call sites in the two lab-only integration test files in `& (Get-Module adman) { param($t) ... }` module-scope scriptblocks, matching the proven unit-test pattern, so the deliberately non-exported gate (SAFE-08) resolves after `Import-Module`.

## What Was Done

The gate `Invoke-AdmanMutation` is intentionally absent from `FunctionsToExport` in `adman.psd1` (SAFE-08 — internal-only). After `Import-Module $ManifestPath`, the function is invisible in test scope, so the direct calls in the two integration files threw `CommandNotFoundException`. This was latent because the integration tests were blocked (no lab DC) on every prior run; this is the first real lab execution.

Applied 4 edits, test-code-only:

1. **tests/Safety.WhatIf.Integration.Tests.ps1** (1 call site, line 58): wrapped the `-WhatIf` gate call in module scope, passing `@($script:TestOu)` as the trailing `param($t)` argument.
2. **tests/Safety.Protected.Integration.Tests.ps1** (nested-admin call site, line 64): wrapped, passing `@($fixture.DistinguishedName)`.
3. **tests/Safety.Protected.Integration.Tests.ps1** (gMSA call site, line 97): wrapped, passing `@($gmsa.DistinguishedName)`.
4. **tests/Safety.Protected.Integration.Tests.ps1** (RID-500 call site, line 112): wrapped, passing `@($rid500.DistinguishedName)`.

The wrapper is needed because `$script:` test variables (`$script:TestOu`, `$fixture.DistinguishedName`, etc.) are not visible inside the module-scope scriptblock, so the target DN(s) must be passed in as a `param($t)` argument. This `& (Get-Module adman) { param($t) ... } $args` pattern works on both PowerShell 5.1 and 7.6.

## Verification

- **Parse check:** Both files parse with 0 errors (`[System.Management.Automation.Language.Parser]::ParseFile`).
- **Static check:** All 4 `Invoke-AdmanMutation` calls are inside `& (Get-Module adman) { param($t) ... }` scriptblocks; no bare calls remain. `-Tag 'Integration'` intact on every Describe/It in both files. Skip-guards (`ADMAN_TEST_OU`) unchanged.
- **Unit suite:** `Invoke-Pester -Path tests -TagFilter Unit` — **138 passed, 0 failed, 0 skipped** (9 NotRun = the Integration-tagged tests correctly excluded by the Unit filter). Green, unchanged.
- **No production code touched:** `adman.psm1`, `adman.psd1`, `Private/`, `Public/` all untouched. No assertion text changed.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None — test-code-only change; no new network endpoints, auth paths, file access patterns, or schema changes.

## Manual Validation (lab-only, NOT run by executor)

From the user's interactive /netonly session with a reachable lab domain:

```powershell
$env:ADMAN_TEST_OU = 'OU=AdmanLab,DC=lab,DC=local'
Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration
Invoke-Pester -Path tests/Safety.Protected.Integration.Tests.ps1 -TagFilter Integration
```

Expected: no `CommandNotFoundException`; the gate resolves and the SAFE-01/06/10 assertions run against the lab fixtures.

## Self-Check: PASSED

- FOUND: tests/Safety.WhatIf.Integration.Tests.ps1
- FOUND: tests/Safety.Protected.Integration.Tests.ps1
- FOUND commit: feac682
