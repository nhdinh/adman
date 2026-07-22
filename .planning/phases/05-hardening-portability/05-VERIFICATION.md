---
phase: 05
phase_name: hardening-portability
status: passed-with-caveats
verified: "2026-07-22T11:15:00Z"
requirements:
  - DOC-01
  - DOC-02
  - DOC-03
---

# Phase 5 Verification

## Goal

The tool is operationally ready — fully documented, Authenticode-signed, portable across workstation and jump-host, honestly dual-edition (PS 5.1 / 7.6 LTS) backed by a real CI matrix, with encrypted-credential restore and audit tamper-evidence/rotation.

## Requirement Traceability

| Requirement | Plan(s) | Evidence | Verdict |
|-------------|---------|----------|---------|
| **DOC-01** — README explains install, first-run config, and safe usage | 05-01b | `README.md` exists, covers RSAT prereq, PSFramework install, `Import-Module ./adman.psd1`, `Initialize-Adman`, `Start-Adman`, `-WhatIf` usage, and project layout. | PASS |
| **DOC-02** — Usage guide covers every menu action and parameterized function with examples | 05-01b, 05-04 | `docs/USAGE.md` exists with menu reference and exported-function examples; `tests/Docs.Coverage.Tests.ps1` enforces that every manifest-exported function and menu entry appears in README/USAGE.md. | PASS |
| **DOC-03** — Every public command/parameter has inline comment-based help enforced by a lint gate | 05-01a1, 05-01a2, 05-01a3 | `tests/Help.Coverage.Tests.ps1` iterates manifest `FunctionsToExport` and asserts each has synopsis, description, parameter help, and examples. All exported functions in `Public/` contain comment-based help blocks inside their function bodies. | PASS |

## Supporting Hardening Artifacts

| Artifact | Location | Status |
|----------|----------|--------|
| Authenticode signing script | `build/Sign-AdmanModule.ps1` | Present |
| Dual-edition CI matrix | `.github/workflows/ci.yml` | Present; tests Windows PowerShell 5.1 (desktop) and PowerShell 7.6 LTS (core), plus AllSigned smoke import |
| Honest edition claim | `adman.psd1` | `CompatiblePSEditions = @('Desktop','Core')` |
| Audit hash chain + rotation | `Private/Audit/Rotation.ps1`, `Private/Audit/Write-AdmanAudit.ps1` | Present; `Get-AdmanAuditIntegrity` verifies chain |
| Offboarding restore from archive | `Private/Workflow/Get-AdmanOffboardingState.ps1` | Searches `audit-*.jsonl` live and under `archive/YYYYMM/`; integrity-checked before read |
| `.store/` commit guard | `.githooks/pre-commit` | Present |
| Recovery runbook | `docs/RECOVERY-RUNBOOK.md` | Present |

## Gap Closure (G-05-1)

Plan 05-04 closed UAT gap G-05-1 with three fixes:

1. `tests/Docs.Coverage.Tests.ps1` — added `'ProgressAction'` to the common-parameter exclusion list so the docs-coverage contract passes under PowerShell 7.6 LTS.
2. `tests/Workflow.OffboardingState.Tests.ps1` — archive test record now carries a valid SHA-256 self-hash (prevHash remains genesis sentinel), satisfying `Get-AdmanAuditIntegrity`.
3. `Private/Config/Initialize-AdmanConfig.ps1` — `Test-AdmanConfigValid` now rejects only non-string ManagedOUs entries; whitespace-only strings are still rejected by the CONF-02 fail-closed scope gate, restoring the expected error message.

Targeted verification (Windows PowerShell 5.1):

- `tests/Docs.Coverage.Tests.ps1 -Tag Unit` — 16 passed, 0 failed
- `tests/Workflow.OffboardingState.Tests.ps1 -Tag Unit` — 1 passed, 0 failed
- `tests/Config.Load.Tests.ps1 -Tag Unit` — 29 passed, 0 failed

## Caveats

1. **PowerShell 7.6 LTS runtime not available locally.** The PS7 leg is exercised only via the CI matrix in `.github/workflows/ci.yml`; the three targeted fixes are designed for cross-edition compatibility and the `ProgressAction` exclusion is specifically a PS7 fix.
2. **Pre-existing unit-test failures unrelated to Phase 5 gap closure.** The full unit suite (`tests/ -Tag Unit`) reports 8 failures in password-generation/display paths:
   - `Local.User.Tests.ps1` — `Set-AdmanLocalUser` password reset (`Transcripts` property)
   - `User.Create.Tests.ps1` — `New-AdmanUser` generated password display (`Transcripts` property)
   - `User.Password.Tests.ps1` — `Set-AdmanUserPassword` generated password paths (`Transcripts` property)
   
   These failures originate from commit `d6117d9` (WR-03 — block generated password display under `Start-Transcript`) and are outside the scope of 05-04. They do not affect the three DOC requirements verified above.

## Verdict

Phase 5 requirement IDs **DOC-01, DOC-02, DOC-03** are satisfied. Gap G-05-1 is closed. The phase is operationally complete; the remaining 8 pre-existing test failures should be addressed in a follow-up gap-closure or code-review fix cycle before shipping.
