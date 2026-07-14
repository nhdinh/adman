# adman

Menu-driven (interactive TUI) PowerShell toolkit for safely administering users and computers in an on-prem Active Directory domain.

> Status: Phase 0 (foundation & safety harness) complete. Phases 1–5 (TUI, reports, lifecycle verbs, remoting, bulk/workflows, hardening) are not yet implemented.

## What it is

adman consolidates the four everyday AD jobs — object lifecycle (create/disable/move/reset), reporting & inventory, remote computer operations, and provisioning/offboarding — behind one guided interface with strong safety guardrails, so a less-experienced admin cannot accidentally damage the directory.

The name `adman` ("AD manager") is a working placeholder taken from the project folder.

## Why it exists

Any admin on the team can perform common AD user/computer tasks correctly and safely — every destructive action is previewed (`-WhatIf`/dry-run), confirmed, scoped to a managed OU, blocked from protected accounts, and written to an audit log. If everything else fails, this safety property must hold.

## Safety guarantees

- `-WhatIf` / dry-run on every destructive action. Preview and execute use the same target resolution, so the preview cannot lie. Enforced by Pester + PSScriptAnalyzer.
- Confirmation prompts scaled to blast radius: y/n for a single object; typed token + exact count for bulk.
- Managed-OU scoping — refuses any DN outside configured roots (component-boundary anchored).
- Deny-list + protected-account protection: recursive admin-group membership, gMSA/service accounts, well-known SIDs resolved at check time (never `adminCount` alone).
- Structured append-only audit log: JSON-lines, fail-closed — refuses the action if the record cannot be written.

Enforced by the non-exported `Invoke-AdmanMutation` gate; no exported function calls AD write cmdlets directly (SAFE-08).

## What works today

Phase 0 only. The safety spine is built and proven; no real AD write is exposed yet.

- Module scaffold (`adman.psd1` / `adman.psm1`) with explicit `FunctionsToExport` (the SAFE-08 export boundary).
- Non-secret config: `Initialize-AdmanConfig`, `Get/Set/Export/Import-AdmanConfig`. Fail-closed on empty managed-OU or failed deny-list load.
- Credential decision: pass-through by default; opt-in DPAPI-encrypted credential file written only on explicit "remember me"; re-prompts on restore failure (0x8009000B / empty / non-PSCredential).
- Startup capability probe: `Test-AdmanCapability` (RSAT present, domain reachable, current rights, transport availability).
- Safety core: `Resolve-AdmanTarget`, `Test-AdmanTargetAllowed`, `Confirm-AdmanAction`, `Invoke-AdmanMutation` (private gate), `Assert-AdmanBulkPolicy` (cap placeholder; enforcement is Phase 4).
- Fail-closed audit: `Write-AdmanAudit` (write-ahead PENDING → mutate → OUTCOME; named mutex; JSON-lines; no secrets).
- Test harness: Pester 6 + PSScriptAnalyzer 1.25.0 with a custom SAFE-08 rule.

Phases 1–5 (TUI menu, reports, lifecycle verbs, remoting, bulk, workflows, hardening) are planned but not implemented. See `.planning/ROADMAP.md`.

## Prerequisites

- **Windows PowerShell 5.1** (required baseline). PowerShell 7.6 LTS will be supported once the Phase 5 CI matrix passes; `CompatiblePSEditions` is currently `Desktop` only.
- **ActiveDirectory module (RSAT)** — prerequisite, NOT bundled.
  - Windows 10 1809+ / Windows 11 (Pro/Enterprise/Education): install via Optional Features.
  - Windows Server: `Install-WindowsFeature RSAT-AD-PowerShell`.
- **PSFramework 1.14.457** (exact-pinned via `RequiredVersion` in `adman.psd1`):
  ```powershell
  Install-PSResource PSFramework -RequiredVersion 1.14.457 -Scope CurrentUser
  # or, on legacy PowerShellGet:
  Install-Module PSFramework -RequiredVersion 1.14.457 -Scope CurrentUser
  ```
- Dev toolchain (contributors only): Pester 6.0.0, PSScriptAnalyzer 1.25.0.

## Install

1. Install the ActiveDirectory module (RSAT) — see Prerequisites.
2. Install PSFramework 1.14.457 — see Prerequisites.
3. Clone the repo.
4. From the repo root:
   ```powershell
   Import-Module ./adman.psd1
   ```

The module is not yet published to a feed; install-from-source is the only path today.

## Basic usage

```powershell
Initialize-Adman        # loads + validates config, runs capability probe, resolves protected SIDs / deny-list
Start-Adman             # entry point (currently a stub; full TUI lands in Phase 1)
Test-AdmanCapability    # re-run the startup probe on demand

Get-AdmanConfig         # view the non-secret config
Set-AdmanConfig         # update a value
Export-AdmanConfig      # backup
Import-AdmanConfig      # restore
```

No destructive verbs are exported yet. The gate is private and there are no public write wrappers in Phase 0.

## Configuration

The config is split into two files:

- **Non-secret config** — portable plain-JSON. Managed OU, deny-list, caps, paths. Diff/backup friendly.
  - `config/adman.defaults.json` — shipped defaults (empty `ManagedOUs` so a fresh install fails closed).
  - `config/adman.example.json` — annotated tracked example.
  - `config/adman.schema.json` — schema.
- **Credential file** — separate, opt-in, DPAPI-encrypted (`Export-Clixml` CurrentUser scope). Written only on explicit "remember me"; re-prompts on restore failure.

Both live in `.store/` at runtime. **`.store/` is gitignored — NEVER commit it.** See `.gitignore`.

## Project layout

```
adman.psd1                  # Module manifest (Desktop-only, PSFramework pinned)
adman.psm1                  # Root module / loader
Public/                     # Exported functions
  Initialize-Adman.ps1
  Start-Adman.ps1
  Test-AdmanCapability.ps1
  Config/                   # Get/Set/Export/Import-AdmanConfig
Private/                    # Internal implementation
  AD/                       # Adman.AD.Write.* wrappers (gate-only, 9-verb allow-list, no hard-delete)
  Audit/                    # Write-AdmanAudit, Find-AdmanAuditOrphans, AdmanAuditIO
  Config/                   # Initialize-AdmanConfig
  Foundation/               # Get-AdmanCredential, Test-AdmanAuditWritable, Resolve-AdmanDomainSid, etc.
  Safety/                   # Resolve-AdmanTarget, Test-AdmanTargetAllowed, Confirm-AdmanAction,
                            # Invoke-AdmanMutation, Assert-AdmanBulkPolicy, AdmanWriteVerbs,
                            # Escape-AdmanLdapFilterValue, Get-AdmanProtectedIdentity
config/                     # adman.defaults.json, adman.example.json, adman.schema.json
rules/                      # AdmanSafetyRules.psm1 (custom PSScriptAnalyzer SAFE-08 rule)
tests/                      # Pester 6 tests (unit + integration; integration doubly gated by
                            # -Tag Integration + $env:ADMAN_TEST_OU)
PSScriptAnalyzerSettings.psd1
.planning/                  # GSD planning artifacts (PROJECT.md, ROADMAP.md, STATE.md, phases/)
.store/                     # GITIGNORED — runtime config + credential files; never commit
```

## Contributing / dev setup

- Install dev toolchain (CurrentUser scope):
  ```powershell
  Install-PSResource Pester -RequiredVersion 6.0.0 -Scope CurrentUser
  Install-PSResource PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser
  ```
- Run lint:
  ```powershell
  Invoke-ScriptAnalyzer -Path . -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
  ```
- Run unit tests:
  ```powershell
  Invoke-Pester -Configuration (Import-PowerShellDataFile ./tests/PesterConfiguration.psd1)
  ```
- Run integration tests: requires a lab AD with a disposable test OU. Set `$env:ADMAN_TEST_OU` and run with `-Tag Integration`. Integration tests are doubly gated and will skip without both.

Hard rules:

- No exported function may call AD write cmdlets directly (SAFE-08). All writes route through `Invoke-AdmanMutation`.
- Every state-changing function must declare `SupportsShouldProcess` with `ConfirmImpact='High'`.
- `.store/` must never be committed.
- No secrets in the repo or in logs.

Planning artifacts live in `.planning/`; see `.planning/ROADMAP.md` for phase structure and `.planning/PROJECT.md` for decisions.

## License

License: TBD — no LICENSE file has been added yet. Internal use only until one is chosen.
