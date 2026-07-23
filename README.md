# adman

Menu-driven (interactive TUI) PowerShell toolkit for safely administering users and computers in an on-prem Active Directory domain.

> Status: Phases 0-4 are implemented (foundation, TUI menu, reports, lifecycle verbs, remote inventory, bulk/workflows, and recovery). Phase 5 hardening and portability work is in progress. See `.planning/ROADMAP.md`.

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

- **Foundation (Phase 0):** module scaffold, non-secret config, DPAPI credential file, capability probe, safety core, fail-closed audit writer.
- **TUI (Phase 1):** flat numbered menu (`Start-Adman`) backed by `Get-AdmanMenuDefinition`, with `B`/`Q` navigation and output-format choice (console / CSV / HTML).
- **Reports (Phase 1):** `Find-AdmanUser`, `Find-AdmanComputer`, `Get-AdmanStaleReport`, `Get-AdmanAccountStateReport`, `Get-AdmanRecoveryPostureReport`, `Get-AdmanInventoryReport`.
- **Lifecycle verbs (Phase 2):** user/computer/local/group enable/disable/move/reset/password/unlock verbs.
- **Remote operations (Phase 3):** inventory enrichment via WinRM → CIM/WSMan → CIM/DCOM fallback. See `docs/REMOTE-OPS.md`.
- **Bulk and workflows (Phase 4):** CSV-driven `Invoke-AdmanBulkAction`, `Start-AdmanUserOnboarding`, `Start-AdmanUserOffboarding`, and quarantine restore via `Restore-AdmanQuarantinedUser`.

See `docs/USAGE.md` for the full menu reference and every exported function example. See `docs/RECOVERY-RUNBOOK.md` for quarantine and Recycle Bin restore procedures.

## Installation

- **Windows PowerShell 5.1** (required baseline). PowerShell 7.6 LTS is supported on Windows 10 1809+/Server 2019+ once installed.
- **ActiveDirectory module (RSAT)** — prerequisite, NOT bundled.
  - Windows 10 1809+ / Windows 11 (Pro/Enterprise/Education): install via Optional Features.
  - Windows Server: `Install-WindowsFeature RSAT-AD-PowerShell`.
- **PSFramework 1.14.457** (exact-pinned via `RequiredVersion` in `adman.psd1`):
  ```powershell
  Install-PSResource PSFramework -RequiredVersion 1.14.457 -Scope CurrentUser
  # or, on legacy PowerShellGet:
  Install-Module PSFramework -RequiredVersion 1.14.457 -Scope CurrentUser
  ```

1. Install the ActiveDirectory module (RSAT) — see Prerequisites.
2. Install PSFramework 1.14.457 — see Prerequisites.
3. Clone the repo.
4. From the repo root:
   ```powershell
   Import-Module ./adman.psd1
   ```

The module is not yet published to a feed; install-from-source is the only path today.

## First run

```powershell
Initialize-Adman          # loads + validates config, probes RSAT/domain/rights/audit path
Start-Adman               # interactive menu
```

`Initialize-Adman` also runs the first-run wizard if `.store/config.json` does not exist. The wizard prompts for the managed OU(s) and writes a portable plain-JSON config.

## Safe usage

Every exported write verb supports `SupportsShouldProcess` and defaults to high confirm impact. In the menu path adman always previews the action first (`-WhatIf`) before asking for final confirmation; at the PowerShell prompt you can use `-WhatIf` yourself:

```powershell
Disable-AdmanUser -Identity 'jdoe' -WhatIf
```

Additional guardrails:

- **Managed-OU scoping:** targets outside the configured roots are rejected.
- **Deny-list:** SIDs/groups listed in config are protected from mutation.
- **Protected accounts:** recursive domain-admin membership, gMSA/service accounts, and well-known SIDs are blocked.
- **Audit:** every mutation attempt produces a JSON-lines record before the AD change is applied.

## Project layout

```
adman.psd1                  # Module manifest (Desktop + PSFramework pinned)
adman.psm1                  # Root module / loader
Public/                     # Exported functions
  Initialize-Adman.ps1
  Start-Adman.ps1
  Test-AdmanCapability.ps1
  Config/                   # Get/Set/Export/Import-AdmanConfig
  Find/Report/Write verbs   # Phases 1-4
Private/                    # Internal implementation
  AD/                       # Adman.AD.Write.* wrappers (gate-only, 9-verb allow-list, no hard-delete)
  Audit/                    # Write-AdmanAudit, Find-AdmanAuditOrphans, AdmanAuditIO
  Config/                   # Initialize-AdmanConfig
  Foundation/               # Get-AdmanCredential, Test-AdmanAuditWritable, Resolve-AdmanDomainSid, etc.
  Menu/                     # Get-AdmanMenuDefinition, Read-AdmanActionParams
  Safety/                   # Resolve-AdmanTarget, Test-AdmanTargetAllowed, Confirm-AdmanAction,
                            # Invoke-AdmanMutation, Assert-AdmanBulkPolicy, AdmanWriteVerbs,
                            # Escape-AdmanLdapFilterValue, Get-AdmanProtectedIdentity
config/                     # adman.defaults.json, adman.example.json, adman.schema.json
rules/                      # AdmanSafetyRules.psm1 (custom PSScriptAnalyzer SAFE-08 rule)
tests/                      # Pester 6 tests (unit + integration; integration doubly gated by
                            # -Tag Integration + $env:ADMAN_TEST_OU)
docs/                       # Operator and recovery guides
  USAGE.md
  REMOTE-OPS.md
  RECOVERY-RUNBOOK.md
PSScriptAnalyzerSettings.psd1
.planning/                  # GSD planning artifacts (PROJECT.md, ROADMAP.md, STATE.md, phases/)
.store/                     # GITIGNORED — runtime config + credential files; never commit
```

## Configuration portability

The config is split into two files:

- **Non-secret config** — portable plain-JSON. Managed OU, deny-list, caps, paths. Diff/backup friendly.
  - `config/adman.defaults.json` — shipped defaults (empty `ManagedOUs` so a fresh install fails closed).
  - `config/adman.example.json` — annotated tracked example.
  - `config/adman.schema.json` — schema.
- **Credential file** — separate, opt-in, DPAPI-encrypted (`Export-Clixml` CurrentUser scope). Written only on explicit "remember me"; re-prompts on restore failure.

Both live in `.store/` at runtime. **`.store/` is gitignored — NEVER commit it.** See `.gitignore`.

`.store/config.json` is portable and can be copied between machines or users. `.store/adman.credential.xml` is DPAPI-bound to the Windows user profile that created it and must be recreated on a new machine or user profile through the normal prompt + remember-me flow.

## Basic usage example

```powershell
Initialize-Adman        # loads + validates config, runs capability probe, resolves protected SIDs / deny-list
Start-Adman             # interactive menu entry point; dispatches every read and write verb
Test-AdmanCapability    # re-run the startup probe on demand

Find-AdmanUser -SamAccountName 'jdoe'
Get-AdmanStaleReport | Format-AdmanReport
Get-AdmanInventoryReport | Export-AdmanReportCsv -Path 'C:\Reports\inventory.csv'
```

For the full menu reference and one example per exported function, see `docs/USAGE.md`.

## Code signing and execution policy

For a single-company deployment you can use a self-signed Authenticode code-signing certificate as the trust anchor. The public certificate is distributed to admin workstations through Group Policy; the private key stays on the build/sign host.

Generate a code-signing certificate (on a secure build host):

```powershell
$cert = New-SelfSignedCertificate `
    -Subject 'CN=adman Internal Code Signing' `
    -Type CodeSigningCert `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(3)

Export-Certificate -Cert $cert -FilePath 'C:\adman-certs\adman-signing.cer'
```

Sign the module before distribution:

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq 'CN=adman Internal Code Signing' }
Get-ChildItem -Path . -Include '*.psd1','*.psm1','*.ps1' -Recurse -File |
    Where-Object FullName -notmatch '\\(tests|\.github|\.githooks)\\' |
    Set-AuthenticodeSignature -Certificate $cert -HashAlgorithm SHA256 `
        -TimestampServer 'http://timestamp.digicert.com'
```

Deploy the public `.cer` to admin workstations via Group Policy:

- **Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers**
  - Import `adman-signing.cer`.
- For a self-signed certificate, also import the same `.cer` under **Trusted Root Certification Authorities** so the certificate chain is trusted.

Set the execution policy on admin workstations to run signed scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
# or AllSigned if every script on the host must be signed
```

For certificate renewal and trust-anchor rotation, see `docs/RECOVERY-RUNBOOK.md`.

## Commit guard

The repo includes a `.githooks/pre-commit` hook that blocks any attempt to commit files under `.store/`. Install it once per clone:

```powershell
git config core.hooksPath .githooks
```

Verify the hook is active with `git config core.hooksPath`.

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
