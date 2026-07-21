# Phase 5: Hardening & Portability - Research

**Researched:** 2026-07-21
**Domain:** PowerShell module hardening, Authenticode signing, GitHub Actions CI matrix, comment-based help enforcement, audit tamper-evidence
**Confidence:** MEDIUM

## Summary

Phase 5 makes adman operationally ready without adding new AD capabilities. The work splits into three strands: documentation (README refresh, standalone usage guide, enforced comment-based help), honest dual-edition support (real Windows PowerShell 5.1 + PowerShell 7.6 LTS CI matrix, Authenticode signing for `AllSigned`), and operational hardening (audit hash-chain + rotation, Recycle-Bin recovery runbook, `.store/` commit guard).

Research confirms the standard patterns are well established: GitHub Actions can run both editions side-by-side on `windows-latest` using `shell: powershell` vs `shell: pwsh`, with PowerShell 7.6 LTS installable via community setup actions until GitHub finishes pre-installing it in June 2026 [CITED: github.com/actions/runner-images/issues/14150]. Self-signed Authenticode is a normal internal deployment path: create a code-signing cert with `New-SelfSignedCertificate -Type CodeSigning`, sign with `Set-AuthenticodeSignature`, and deploy the public `.cer` to `Trusted Publishers` (and `Trusted Root Certification Authorities` for self-signed) via GPO [CITED: learn.microsoft.com/about_Signing]. Help coverage is best enforced with a Pester 6 test that iterates `FunctionsToExport` and asserts `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, and `.PARAMETER` per declared parameter [CITED: vexx32.github.io, learn.microsoft.com comment-based-help].

The only material gap discovered is that **none of the 38 currently exported public functions have `.DESCRIPTION` or `.EXAMPLE` blocks** (they only have `.SYNOPSIS` and `.PARAMETER`). Adding these is a real Phase 5 deliverable, not just a test. Audit hash-chain and rotation are additive to the existing synchronous `Write-AdmanAudit`; the chain is tamper-evident, not tamper-proof, which matches the project's safety model.

**Primary recommendation:** Pin CI to the current PowerShell 7.6 LTS patch (7.6.4 as of research date), install it explicitly via `mchave3/setup-pwsh@v1`, run the same lint/help/unit suite under both `powershell` and `pwsh`, and only flip `CompatiblePSEditions` to `@('Desktop','Core')` after both legs pass.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Split documentation into README + standalone usage guide.**
  - Refresh `README.md` to cover: install prerequisites (RSAT, PSFramework 1.14.457), first-run config wizard, safe-usage summary, and a short "what works today" section that reflects Phases 0-4 shipped state.
  - Add `docs/USAGE.md` as the action-by-action reference: every menu item (label, required inputs, B/Q behavior) and every exported parameterized function with at least one example. The menu table in `Get-AdmanMenuDefinition` is the source of truth for the menu half; the `FunctionsToExport` list in `adman.psd1` is the source of truth for the function half.
  - Keep `docs/REMOTE-OPS.md` in place and reference it from README/USAGE; do not merge it into the usage guide.

- **D-02: Pester contract test for comment-based help coverage.**
  - A new test file `tests/Help.Coverage.Tests.ps1` iterates `FunctionsToExport` from `adman.psd1` and asserts each public function has:
    - `.SYNOPSIS` and `.DESCRIPTION` blocks
    - `.PARAMETER` help for every declared parameter
    - `.EXAMPLE` for at least the common parameter set
  - PSScriptAnalyzer already enforces `SupportsShouldProcess` on state-changing functions; no new custom PSSA rule is required for help.
  - The test runs in both 5.1 and 7.6 legs of the CI matrix.

- **D-03: GitHub Actions CI matrix on Windows PowerShell 5.1 and PowerShell 7.6 LTS.**
  - Add `.github/workflows/ci.yml` that runs on `windows-latest` with two jobs/legs:
    - Windows PowerShell 5.1: `shell: powershell`
    - PowerShell 7.6 LTS: installed via `powershell/psscriptanalyzer-action` or direct MSI/setup action, then `shell: pwsh`
  - Each leg runs: PSScriptAnalyzer recursively, the help-coverage Pester test, and the full unit-test suite (`tests/PesterConfiguration.psd1`).
  - Integration tests remain lab-only (gated by `-Tag Integration` + `$env:ADMAN_TEST_OU`); they do not run in CI.
  - Only after the matrix passes is `CompatiblePSEditions` in `adman.psd1` updated from `@('Desktop')` to `@('Desktop','Core')`.

- **D-04: Sign the module so it runs under `AllSigned` using a self-signed certificate distributed as the trust anchor.**
  - Add `build/Sign-AdmanModule.ps1` that accepts a `-CertificateThumbprint` or `-CertificateFilePath` and signs all `.psd1`, `.psm1`, and `.ps1` files in the module.
  - CI generates a self-signed code-signing cert in a setup step, signs the module, then runs the test leg under `Set-ExecutionPolicy AllSigned -Scope Process` so the "runs under AllSigned" claim is mechanically proven.
  - README documents the self-signed-cert path for a single-company deployment: generate a code-signing cert, export the public key, and deploy it to admin workstations via Group Policy (`Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers`). No paid certificate is required because the company controls all endpoints.
  - Renewal and trust-anchor rotation are documented in the runbook; keep the private key offline/export-restricted where practical.

- **D-05: Audit log tamper-evidence + rotation + forwarding.**
  - **Append-only daily JSONL files** are preserved; the existing `Write-AdmanAudit` synchronous write path is unchanged.
  - Add a **simple hash chain**: each record includes `prevHash` = SHA-256 of the previous record's JSON bytes (omitted on the first record of a day). A new helper `Get-AdmanAuditIntegrity` verifies the chain and reports the first broken link.
  - Add **rotation**: a daily/background helper `Invoke-AdmanAuditRotation` archives files older than `audit.retentionDays` (default 90, stored in config schema/defaults) to `.store/audit/archive/YYYYMM/` and leaves a marker file.
  - **Event-log forwarding** for OUTCOME-write failures already exists (Event ID 9001); keep it and add a test proving the event-log seam is invoked when `Write-AdmanAudit` throws on OUTCOME.
  - No remote syslog/SIEM forwarding in v1; document the Event Log as the integration point.

- **D-06: Encrypted credential portability is documentation-only.**
  - The DPAPI credential file (`.store/adman.credential.xml`) is intentionally machine/user-bound; cross-machine restore already re-prompts (CONF-04).
  - No "exportable" credential backup feature is added. The README/USAGE explain: back up the plain-JSON config; the credential file must be recreated on a new machine/user via the normal prompt + remember-me flow.

- **D-07: Recycle-Bin recovery runbook.**
  - Add `docs/RECOVERY-RUNBOOK.md` covering:
    - Restoring a quarantined user via `Restore-AdmanQuarantinedUser`
    - Restoring a deleted object from AD Recycle Bin with PowerShell when the tool's quarantine restore is insufficient
    - Authoritative restore warning and when to escalate
  - The runbook is human documentation, not a new command.

- **D-08: `.store/` commit guard.**
  - `.gitignore` already excludes `.store/`; add a `.githooks/pre-commit` hook that refuses the commit if any `.store/` path is staged.
  - Add a CI check that fails if `.store/` contents are present in the checked-out tree (defense against a hook bypass).

### Claude's Discretion

- Exact CI action versions and setup steps for PowerShell 7.6 LTS are left to the planner/executor; the decision is "real GitHub Actions matrix on both editions."
- Exact hash-chain serialization order and archive folder naming are implementation details; the decision is "SHA-256 chain + time-based archive."
- The help-coverage test may use `Get-Help` AST or the `Microsoft.PowerShell.PlatyPS` parser; either is acceptable as long as it asserts the required blocks.
- Self-signed cert lifetime/generation parameters in CI are implementation details.

### Deferred Ideas (OUT OF SCOPE)

- **Remote syslog/SIEM forwarding** — out of v1 scope; Event Log is the integration point.
- **Encrypted audit (filesystem encryption / BitLocker policy)** — operational, not code; document in runbook if needed.
- **Automated certificate renewal / HSM-backed signing** — enterprise PKI operations, not the module's responsibility.
- **Multi-domain/cross-forest portability** — v2 scope (`PLAT-V04`).
- **Compiled `.exe` distribution (`PLAT-V02`)** — v2 scope.
- **Persisted/resume-safe bulk job state (`BULK-V01`)** — v2 scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-01 | A README explains install (RSAT prereq), first-run config, and safe usage | README refresh derived from shipped Phases 0-4 state; install paths from Microsoft Learn RSAT docs (referenced in CLAUDE.md) |
| DOC-02 | A usage guide covers every menu action and parameterized function with examples | Sources of truth are `Get-AdmanMenuDefinition` (menu) and `adman.psd1 FunctionsToExport` (functions); examples use the actual Public verb signatures |
| DOC-03 | Every public command/parameter has inline comment-based help (`Get-Help`), enforced by a lint gate | Pester 6 contract test pattern iterates exported functions and asserts `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`; Microsoft Learn documents the required blank-line/section structure |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Documentation authoring | Repository / source tree | — | README/USAGE/runbooks are static Markdown under source control; no runtime tier owns them |
| Comment-based help enforcement | CI / test runner (Pester) | Local dev (VS Code lint) | The Pester contract test is the authoritative gate; PSScriptAnalyzer does not enforce help content |
| Dual-edition compatibility | CI matrix (Windows PowerShell 5.1 + PowerShell 7.6 LTS) | Module manifest (`CompatiblePSEditions`) | The claim is proven by running the same suite in both shells; the manifest is only the outward declaration |
| Authenticode signing | Build script + CI | GPO / endpoint trust store | Signing happens at build time; trust is an endpoint/Active Directory responsibility |
| Audit tamper-evidence | Local filesystem (JSONL + hash chain) | Windows Event Log (OUTCOME-failure escalation) | Hash chain is local-file tamper detection; event log is the outward signal when local write fails |
| Audit rotation | Local scheduled task / CI-cleanup | Config-driven retention policy | Moves old JSONL files to archive; retention read from portable config |
| `.store/` commit guard | Git client hook (local) | CI checkout scan (remote) | Defense in depth: hook catches honest mistakes, CI catches bypasses |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| **Windows PowerShell** | **5.1** | Required baseline runtime | Ships on every supported Windows workstation/server; AD/CIM/LocalAccounts modules are native. [VERIFIED: installed on research host] |
| **PowerShell** | **7.6.4 LTS** (current patch as of research date; target the 7.6 LTS line) | Modern supported runtime | Microsoft Learn lists 7.6.4 as current LTS; GitHub runner images are updating to 7.6 LTS by June 22 2026. [CITED: learn.microsoft.com/install-powershell-on-windows, github.com/actions/runner-images/issues/14150] |
| **ActiveDirectory module (RSAT)** | ships with Windows/RSAT | AD cmdlet surface | Prerequisite, never bundled; natively compatible with PS7 on Win10 1809+/Server 1809+ [CITED: CLAUDE.md / Microsoft Learn module-compatibility] |
| **Pester** | **6.0.0** | Unit/integration test + mock framework | Supports Windows PowerShell 5.1 and PowerShell 7; the de-facto PowerShell test framework. [VERIFIED: PowerShell Gallery] |
| **PSScriptAnalyzer** | **1.25.0** | Static analysis + formatting | Min PS 5.1; de-facto linter. [VERIFIED: PowerShell Gallery] |
| **PSFramework** | **1.14.457** | Config + diagnostic/ops logging | Already pinned in `adman.psd1`; no change in Phase 5. [VERIFIED: installed on research host] |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| **GitHub Actions `windows-latest`** | runner image | CI matrix host | Both 5.1 and PS7 legs run here; PS7 must be installed explicitly until the runner image update completes |
| **`mchave3/setup-pwsh@v1`** or **`PSModule/Install-PowerShell@v1`** | marketplace action | Install PowerShell 7.6 LTS in CI | Use when the runner image does not yet have the required 7.6 patch |
| **`New-SelfSignedCertificate`** | PKI module (in-box) | Generate code-signing cert in CI and production | Internal/single-company deployments where GPO distributes the trust anchor |
| **`Set-AuthenticodeSignature`** | Microsoft.PowerShell.Security (in-box) | Sign `.psd1/.psm1/.ps1` | Required for `AllSigned`; accepts `X509Certificate2`, supports `-HashAlgorithm SHA256` and optional `-TimestampServer` [CITED: learn.microsoft.com/Set-AuthenticodeSignature] |
| **DPAPI (`ConvertFrom-SecureString` / `Export-Clixml`)** | in-box | Encrypted credential file | Already implemented in Phase 0; no code change, only documentation |
| **`Write-EventLog`** / **Application log source `adman`** | in-box | OUTCOME-write failure escalation | Already implemented in Phase 0; add a test proving the seam is invoked |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `mchave3/setup-pwsh` | Manual MSI download + `msiexec /quiet` | Manual install is more brittle and slower; setup action handles architecture detection and PATH updates |
| Self-signed cert + GPO Trusted Publishers | Enterprise PKI code-signing cert | PKI cert avoids self-signed root distribution but costs money and requires PKI infrastructure; self-signed is appropriate for a single company that controls all endpoints (per CONTEXT.md D-04) |
| SHA-256 hash chain | HMAC or digital signature over each record | HMAC/signature adds key-management complexity; simple hash chain satisfies tamper-evidence requirement and is easier to verify locally |
| JSON-lines audit rotation | Third-party log shipper/ELK | Adds external dependencies and network failure modes; local rotation + Event Log integration matches v1 scope and fail-closed design |
| Hand-rolled pre-commit hook | `pre-commit` framework (pre-commit.com) | Framework is cross-platform and shareable but adds Python dependency; a simple shell hook is sufficient for a single forbidden path |

**Installation (CI/dev tools):**

```powershell
# Dev toolchain (CurrentUser scope) — already standard in project
Install-PSResource Pester -RequiredVersion 6.0.0 -Scope CurrentUser
Install-PSResource PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser

# CI installs PSFramework automatically via adman.psd1 RequiredModules
# PowerShell 7.6 LTS is installed by the workflow step itself
```

**Version verification:**

```powershell
# PowerShell editions
$PSVersionTable.PSVersion          # 5.1 on Windows PowerShell; 7.6.x on pwsh
$PSVersionTable.PSEdition          # Desktop / Core

# Dev toolchain
Get-Module Pester -ListAvailable
Get-Module PSScriptAnalyzer -ListAvailable
Get-Module PSFramework -ListAvailable

# PowerShell Gallery (cross-check legitimacy)
Find-Module Pester -RequiredVersion 6.0.0
Find-Module PSScriptAnalyzer -RequiredVersion 1.25.0
Find-Module PSFramework -RequiredVersion 1.14.457
```

## Package Legitimacy Audit

> Phase 5 does not introduce new runtime module dependencies, but the CI/dev toolchain reinstalls Pester and PSScriptAnalyzer on ephemeral runners. The table below verifies those packages plus the already-pinned PSFramework.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| Pester 6.0.0 | PowerShell Gallery | published 2026-07-07 | high | github.com/pester/Pester | [OK] | Approved |
| PSScriptAnalyzer 1.25.0 | PowerShell Gallery | published 2026-03-20 | high | github.com/PowerShell/PSScriptAnalyzer | [OK] | Approved |
| PSFramework 1.14.457 | PowerShell Gallery | published 2026-07-02 | moderate | psframework.org / github.com/PowershellFrameworkCollective/PSFramework | [OK] | Approved |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*PowerShell Gallery verification was performed via `Find-Module` and direct gallery page inspection. The gsd-tools `package-legitimacy` seam targets npm/pypi/crates and is not applicable to the PowerShell ecosystem; registry verification was done with the PowerShell Gallery equivalent commands.*

## Architecture Patterns

### System Architecture Diagram

```
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                           Developer workstation / CI runner                  │
 │                                                                              │
 │   ┌──────────────┐    ┌──────────────┐    ┌─────────────────────────────┐   │
 │   │  Source tree │───▶│  build/      │───▶│  Signed module artifacts    │   │
 │   │  (Public/    │    │  Sign-       │    │  .psd1 .psm1 .ps1           │   │
 │   │   Private/)  │    │  AdmanModule │    └────────────┬────────────────┘   │
 │   └──────────────┘    └──────────────┘                 │                    │
 │           │                                            │                    │
 │           ▼                                            ▼                    │
 │   ┌──────────────┐                           ┌──────────────────────┐       │
 │   │  PSScriptA-  │                           │  Test runner         │       │
 │   │  nalyzer     │                           │  - Windows PS 5.1    │       │
 │   │  (lint)      │                           │  - PowerShell 7.6    │       │
 │   └──────────────┘                           │  - Help coverage     │       │
 │           │                                  │  - Unit tests        │       │
 │           ▼                                  └──────────┬───────────┘       │
 │   ┌─────────────────────────────────┐                   │                   │
 │   │  Help.Coverage.Tests.ps1        │◀──────────────────┘                   │
 │   │  (asserts SYNOPSIS/DESCRIPTION/ │                                       │
 │   │   PARAMETER/EXAMPLE)            │                                       │
 │   └─────────────────────────────────┘                                       │
 │                                                                              │
 │   ┌─────────────────────────────────────────────────────────────────────┐   │
 │   │  Audit subsystem (existing Phase 0 + Phase 5 additions)             │   │
 │   │                                                                      │   │
 │   │   Write-AdmanAudit  ──▶  JSONL file (audit-YYYYMMDD.jsonl)          │   │
 │   │        │                           ▲                                │   │
 │   │        │                           │ prevHash (SHA-256 of prior row) │   │
 │   │        ▼                           │                                │   │
 │   │   Get-AdmanAuditIntegrity  ◀──────┘                                │   │
 │   │                                                                      │   │
 │   │   Invoke-AdmanAuditRotation  ──▶  .store/audit/archive/YYYYMM/      │   │
 │   │                                                                      │   │
 │   │   OUTCOME-write failure  ──▶  Windows Event Log (id 9001)            │   │
 │   └─────────────────────────────────────────────────────────────────────┘   │
 │                                                                              │
 │   ┌─────────────────────────────┐    ┌─────────────────────────────┐       │
 │   │  .githooks/pre-commit       │    │  CI checkout scan           │       │
 │   │  (blocks staged .store/*)   │    │  (fails if .store/ present) │       │
 │   └─────────────────────────────┘    └─────────────────────────────┘       │
 └─────────────────────────────────────────────────────────────────────────────┘

                                              │
                                              ▼
                              ┌─────────────────────────────┐
                              │  Target admin workstation   │
                              │  / jump host                │
                              │                              │
                              │  GPO deploys public .cer    │
                              │  to Trusted Publishers +    │
                              │  Trusted Root CAs           │
                              │                              │
                              │  ExecutionPolicy = AllSigned│
                              │  Import-Module ./adman.psd1 │
                              └─────────────────────────────┘
```

### Recommended Project Structure

```
C:\Users\nhdinh\dev\adman/
├── README.md                              # Refreshed install/first-run/safe-usage
├── docs/
│   ├── USAGE.md                           # Every menu action + function with examples
│   ├── REMOTE-OPS.md                      # Existing, referenced from README/USAGE
│   └── RECOVERY-RUNBOOK.md                # Quarantine restore + AD Recycle Bin
├── build/
│   └── Sign-AdmanModule.ps1               # Authenticode signing script
├── .github/
│   └── workflows/
│       └── ci.yml                         # 5.1 + 7.6 matrix
├── .githooks/
│   └── pre-commit                         # Blocks .store/ from being committed
├── .gitignore                             # Already excludes .store/
├── adman.psd1                             # FunctionsToExport + CompatiblePSEditions
├── adman.psm1
├── PSScriptAnalyzerSettings.psd1
├── config/
│   ├── adman.schema.json                  # Add audit.retentionDays
│   └── adman.defaults.json                # Add audit.retentionDays
├── Private/
│   └── Audit/
│       ├── Write-AdmanAudit.ps1           # Extend record with prevHash
│       ├── AdmanAuditIO.ps1               # Existing seams
│       └── Rotation.ps1                   # New: Get-AdmanAuditIntegrity, Invoke-AdmanAuditRotation
├── tests/
│   ├── Help.Coverage.Tests.ps1            # New DOC-03 contract test
│   ├── Audit.Integrity.Tests.ps1          # New hash-chain tests
│   └── Audit.EventLog.Tests.ps1           # New OUTCOME-failure event-log test
└── .store/                                # GITIGNORED — runtime only
```

### Pattern 1: Help-Coverage Contract Test

**What:** A Pester 6 discovery test that reads `FunctionsToExport` from the module manifest and asserts the required comment-based help sections for each public function.

**When to use:** DOC-03 enforcement and as a CI gate before claiming `CompatiblePSEditions`.

**Example:**

```powershell
# Source: vexx32.github.io + Microsoft Learn comment-based-help examples
BeforeDiscovery {
    Import-Module $PSScriptRoot\..\adman.psd1 -Force
    $script:Module = Get-Module adman
    $script:Commands = $script:Module.ExportedFunctions.Keys | Sort-Object
    $script:CommonParams = @('WhatIf', 'Confirm')
}

Describe 'adman public help coverage' -Tag 'Unit' {
    It '<_> has a SYNOPSIS' -ForEach $script:Commands {
        (Get-Help $_ -Full).Synopsis | Should -Not -BeNullOrEmpty
    }

    It '<_> has a DESCRIPTION' -ForEach $script:Commands {
        (Get-Help $_ -Full).Description | Should -Not -BeNullOrEmpty
    }

    It '<_> has at least one EXAMPLE' -ForEach $script:Commands {
        (Get-Help $_ -Full).Examples.Example.Count | Should -BeGreaterOrEqual 1
    }

    It '<_> has help for every parameter' -ForEach $script:Commands {
        $helpParams = (Get-Help $_ -Full).Parameters.Parameter |
            Where-Object Name -NotIn $script:CommonParams
        $astParams = (Get-Command $_ -ErrorAction SilentlyContinue).ScriptBlock.Ast.Body.ParamBlock.Parameters.Name.VariablePath.UserPath |
            Where-Object { $_ -notin $script:CommonParams }
        @($helpParams).Count | Should -Be @($astParams).Count
    }
}
```

### Pattern 2: Authenticode Signing Build Script

**What:** A reusable script that signs every `.psd1`, `.psm1`, and `.ps1` file in the module, usable both in CI and production.

**When to use:** Before any `AllSigned` execution or release.

**Example:**

```powershell
# Source: Microsoft Learn about_Signing + Set-AuthenticodeSignature
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [string]$ModulePath = $PSScriptRoot\..\adman.psd1
)

$moduleRoot = Split-Path -Parent -Path (Resolve-Path $ModulePath).Path
$files = Get-ChildItem -Path $moduleRoot -Include '*.psd1','*.psm1','*.ps1' -Recurse -File |
    Where-Object FullName -notmatch '\\(tests|\.github|\.githooks)\\'

foreach ($file in $files) {
    $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $Certificate -HashAlgorithm SHA256
    if ($result.Status -ne 'Valid') {
        throw "Signing failed for $($file.FullName): $($result.StatusMessage)"
    }
}
```

### Pattern 3: Audit Hash Chain

**What:** Each audit record stores the SHA-256 of the previous record's JSON bytes. Verification recomputes the chain sequentially.

**When to use:** Tamper-evidence for the append-only JSONL audit log.

**Example:**

```powershell
# Source: research synthesis (ASECuritySite hashing + ContextCleaner hash-chain pattern)
function Get-AdmanAuditPreviousHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return ('0' * 64) }
    $last = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($last)) { return ('0' * 64) }
    $record = $last | ConvertFrom-Json
    return $record.prevHash
}

function Get-AdmanAuditIntegrity {
    param([string]$Path)
    $prevHash = '0' * 64
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        $record = $line | ConvertFrom-Json
        if ($record.prevHash -ne $prevHash) {
            return [PSCustomObject]@{ Valid = $false; BrokenAtLine = $lineNo; Reason = 'prevHash mismatch' }
        }
        $computed = $record | Select-Object -ExcludeProperty prevHash |
            ConvertTo-Json -Compress -Depth 5 |
            ForEach-Object { [System.Text.Encoding]::UTF8.GetBytes($_) } |
            ForEach-Object { [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($_)).Replace('-','').ToLower() }
        # ... hash computation pattern
        $prevHash = $record.prevHash
    }
    return [PSCustomObject]@{ Valid = $true; Lines = $lineNo }
}
```

*Note: the exact field-set used for the hash must be stable; consider excluding volatile/round-trip-unsafe fields if any.*

### Pattern 4: `.store/` Commit Guard

**What:** A pre-commit hook and a CI check that both refuse `.store/` paths.

**When to use:** Prevent accidental secret/config commits.

**Example:**

```bash
# Source: community patterns + Git pre-commit hook documentation
#!/bin/sh
BLOCKED='\.store/'
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    AGAINST=HEAD
else
    AGAINST=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

if git diff --cached --name-only "$AGAINST" | grep -qE "^$BLOCKED"; then
    echo "ERROR: Committing .store/ files is not allowed." >&2
    exit 1
fi
exit 0
```

### Anti-Patterns to Avoid

- **Flipping `CompatiblePSEditions` to `Core` before CI passes:** The manifest claim must be the *result* of the matrix, not an assumption. Keep `@('Desktop')` until both legs are green.
- **Signing only `.ps1` files:** PowerShell validates signatures on `.psd1`, `.psm1`, `.ps1`, `.ps1xml`, and `.cdxml` files. The module manifest and root module must also be signed for `AllSigned` import to succeed.
- **Using a timestamp server in CI with a self-signed cert:** Timestamping is valuable for production certs but adds network dependency in CI. CI can omit timestamping; document its use for production certs.
- **Hash chain as tamper-proof:** A hash chain detects alteration; it does not prevent deletion by a filesystem administrator. Document this honestly.
- **Relying only on `.gitignore` for secrets:** `.gitignore` does not block an explicit `git add -f`; use a pre-commit hook plus CI scan.
- **Running help-coverage test without importing the module first:** `Get-Help` returns only syntax for functions that are not loaded; always `Import-Module -Force` in `BeforeDiscovery`/`BeforeAll`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PowerShell 7.6 install in CI | Manual MSI download + `msiexec` | `mchave3/setup-pwsh@v1` or `PSModule/Install-PowerShell@v1` | Handles architecture, PATH, and idempotency; less brittle |
| Authenticode signing | Custom .NET crypto calls | `Set-AuthenticodeSignature` | SIP-aware, produces PowerShell-compatible signature block, reports `Status`/`StatusMessage` |
| Help parsing | Regex over source files | `Get-Help -Full` + `(Get-Command).ScriptBlock.Ast` | `Get-Help` resolves inherited/external help and AST gives exact declared parameters |
| Hash computation | Custom string hashing | `[System.Security.Cryptography.SHA256]::Create().ComputeHash(...)` | FIPS-compliant, well-tested .NET crypto API |
| Log compression | Custom zip writer | `Compress-Archive` | Built-in, handles .NET streams correctly |
| Commit guard | Rely on `.gitignore` alone | Pre-commit hook + CI checkout scan | Defense in depth against `--no-verify` and force-adds |

**Key insight:** Phase 5 is about packaging, proving, and documenting the existing spine. Every custom-built piece here would be a liability; the standard PowerShell/Windows/Git tools already do the work.

## Common Pitfalls

### Pitfall 1: CI Leg Differences Cause False "Dual-Edition" Pass

**What goes wrong:** The Windows PowerShell 5.1 leg and the PowerShell 7.6 leg run different commands or test subsets, so a green matrix does not actually prove edition compatibility.

**Why it happens:** 5.1 lacks some cmdlets (`Import-PowerShellDataFile` availability depends on module load), and `pwsh` default shell behavior differs. Authors may accidentally special-case one leg.

**How to avoid:** Run the identical lint/help/unit commands in both legs, differing only in `shell: powershell` vs `shell: pwsh` and the PS7 install step.

**Warning signs:** Conditional YAML steps keyed to `${{ matrix.edition }}` that skip tests or install different dependency versions.

### Pitfall 2: Self-Signed Cert Not Trusted on Test Runner

**What goes wrong:** CI signs the module but the test leg still prompts or fails under `AllSigned` because the certificate is not in the local `Trusted Root`/`Trusted Publishers` stores.

**Why it happens:** `Set-ExecutionPolicy AllSigned` requires the signing certificate chain to be trusted. Self-signed certs are not trusted by default.

**How to avoid:** In CI, import the self-signed public `.cer` into `Cert:\LocalMachine\Root` and `Cert:\LocalMachine\TrustedPublisher` before running tests.

**Warning signs:** `Get-AuthenticodeSignature` returns `HashMismatch` or `NotTrusted`; test step fails with "cannot be loaded because the execution of scripts is disabled on this system."

### Pitfall 3: Help Test Passes on Empty Content

**What goes wrong:** The help-coverage test counts parameter objects or accepts whitespace-only synopsis as valid.

**Why it happens:** `Get-Help` returns objects even for undocumented functions; `$help.Synopsis` may be an empty string or contain only the function name.

**How to avoid:** Assert non-null **and** non-whitespace, and compare help-parameter count against the AST-declared parameter count.

**Warning signs:** Test reports all green despite every `.DESCRIPTION`/`.EXAMPLE` being blank.

### Pitfall 4: Hash Chain Breaks on Log Rotation

**What goes wrong:** Archiving daily files severs the hash chain because the first record of the new day does not reference the last record of the previous day.

**Why it happens:** The chain is currently scoped per-day file. If an auditor wants cross-day integrity, the archive folder naming or a separate chain-of-heads is needed.

**How to avoid:** Keep per-day chain intact. For cross-day verification, store the last hash of each day in an index file (e.g., `.store/audit/audit-heads.jsonl`) or verify each day's file independently and treat day boundaries as natural audit boundaries.

**Warning signs:** `Get-AdmanAuditIntegrity` reports valid per file but there is no way to prove the sequence across archived files.

### Pitfall 5: `.store/` Accidentally Tracked in a Fresh Clone

**What goes wrong:** A contributor creates `.store/` locally and the pre-commit hook is not installed (clones do not copy `.git/hooks` automatically), so `.store/` is committed.

**Why it happens:** Hooks in `.git/hooks` are local and not versioned; contributors must run `git config core.hooksPath .githooks` or copy the hook.

**How to avoid:** Document hook installation in README and add a CI step that fails if `.store/` exists in the checkout.

**Warning signs:** New contributors report CI failing on the "no .store/ in checkout" check.

### Pitfall 6: PowerShell 7.6 LTS Patch Drift

**What goes wrong:** CI pins to an older 7.6 patch that is no longer available for download, or the runner image preinstalls a newer patch and tests fail due to a breaking change.

**Why it happens:** Microsoft updates the 7.6 LTS line with patch releases; the exact download URL changes.

**How to avoid:** Use a setup action that accepts `lts` or `7.6.x` rather than a hard-coded MSI URL, or pin to the current patch and update it explicitly in the workflow.

**Warning signs:** CI setup step 404s on the MSI URL or `pwsh --version` returns an unexpected patch.

## Code Examples

### Example 1: Comment-Based Help Block

```powershell
# Source: Microsoft Learn - Examples of Comment-based Help
<#
.SYNOPSIS
    Short one-line summary.

.DESCRIPTION
    Longer explanation of what the function does, when to use it,
    and any safety notes.

.PARAMETER Identity
    The sAMAccountName, DN, or GUID of the target user.

.EXAMPLE
    PS> Disable-AdmanUser -Identity 'jdoe'
    Disables the user jdoe after confirmation and audit.
#>
function Disable-AdmanUser { ... }
```

### Example 2: GitHub Actions Matrix Snippet

```yaml
# Source: GitHub Docs matrix strategy + community setup actions
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        edition: [desktop, core]
    steps:
      - uses: actions/checkout@v4

      - name: Install PowerShell 7.6 LTS
        if: matrix.edition == 'core'
        uses: mchave3/setup-pwsh@v1
        with:
          version: '7.6.4'

      - name: Install dependencies
        shell: ${{ matrix.edition == 'desktop' && 'powershell' || 'pwsh' }}
        run: |
          Install-PSResource Pester -RequiredVersion 6.0.0 -Scope CurrentUser
          Install-PSResource PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser

      - name: Set execution policy to AllSigned (Core leg test)
        if: matrix.edition == 'core'
        shell: pwsh
        run: Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope Process -Force

      - name: Run tests
        shell: ${{ matrix.edition == 'desktop' && 'powershell' || 'pwsh' }}
        run: |
          Invoke-ScriptAnalyzer -Path . -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
          Invoke-Pester -Configuration (Import-PowerShellDataFile ./tests/PesterConfiguration.psd1)
```

### Example 3: Self-Signed Cert Generation and Signing

```powershell
# Source: Microsoft Learn about_Signing + Set-AuthenticodeSignature
$cert = New-SelfSignedCertificate `
    -Subject 'CN=adman Code Signing' `
    -Type CodeSigning `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm sha256 `
    -NotAfter (Get-Date).AddYears(3)

Export-Certificate -Cert $cert -FilePath .\adman-signing.cer

# Sign module files
Get-ChildItem .\adman -Include '*.psd1','*.psm1','*.ps1' -Recurse |
    ForEach-Object {
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -HashAlgorithm SHA256
    }
```

### Example 4: Hash-Chain Record Write

```powershell
# Source: research synthesis
$path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date).ToUniversalTime())
$prevHash = if (Test-Path -LiteralPath $path) {
    $last = Get-Content -LiteralPath $path -Tail 1 | ConvertFrom-Json
    $last.prevHash
} else {
    ('0' * 64)
}

# Build record without prevHash, then hash
$rec = [ordered]@{ tsUtc = (Get-Date).ToUniversalTime().ToString('o'); ... }
$canonical = $rec | ConvertTo-Json -Compress -Depth 5
$hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($canonical))
$hash = [System.BitConverter]::ToString($hashBytes).Replace('-','').ToLower()
$rec['prevHash'] = $prevHash
$rec['hash'] = $hash
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PowerShell 7.4 LTS as "modern" target | PowerShell 7.6 LTS (current patch 7.6.4) | 2026-03 (7.6.3 GA) / 2026-07 (7.6.4 current) | 7.4/7.5 EOL November 10 2026; 7.6 is the only supported LTS line past that date |
| GitHub Actions runner preinstalls PS 7.4 | Runner images updating to 7.6 LTS by June 22 2026 | Announcement May/June 2026 | CI may not need explicit install after rollout, but explicit install guarantees version |
| platyPS 0.14.2 | Microsoft.PowerShell.PlatyPS 1.0.x | 2026 (GA) | Not used in Phase 5; comment-based help is the v1 source of truth |
| Manual MSI download in CI | `setup-pwsh` / `Install-PowerShell` actions | 2024-2026 | More maintainable, architecture-aware, handles PATH |

**Deprecated/outdated:**
- `Get-WmiObject`: removed in PowerShell 7; project already uses `CimCmdlets`.
- `wmic.exe`: being removed from Windows; project already avoids it.
- PowerShell 7.4/7.5 as targets: EOL November 10 2026; do not optimize for them.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Pester 6.0.0 supports both Windows PowerShell 5.1 and PowerShell 7.6 LTS | Standard Stack | If false, the CI matrix cannot use a single Pester version; may need separate pins |
| A2 | GitHub Actions `windows-latest` can run `shell: powershell` (5.1) and `shell: pwsh` (7.6) in the same matrix | Architecture Patterns | If false, two separate jobs or runner types are needed |
| A3 | Self-signed code-signing certs distributed via GPO Trusted Publishers satisfy `AllSigned` for a single-company deployment | Standard Stack | If the environment requires a public CA, the deployment path changes significantly |
| A4 | Audit hash-chain verification is acceptable as tamper-evidence (not tamper-proof) | Architecture Patterns | If the requirement is stronger, HMAC/digital signatures per record are needed |
| A5 | All 37 public functions currently lack `.DESCRIPTION` and `.EXAMPLE` | Phase Requirements | If wrong, the help-coverage workload estimate changes |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

## Open Questions (RESOLVED)

1. **Exact PowerShell 7.6 LTS patch to pin in CI** *(RESOLVED by 05-02 Plan)*
   - What we know: Microsoft Learn lists 7.6.4 as current LTS; CLAUDE.md references 7.6.3.
   - What's unclear: Whether the project wants to pin a specific patch or use `lts`/`7.6.x`.
   - Recommendation: Pin the current patch (7.6.4) for reproducibility and update it intentionally; document the update cadence.

2. **Production signing cert source** *(RESOLVED by 05-02 Plan)*
   - What we know: CONTEXT.md D-04 explicitly chooses self-signed + GPO Trusted Publishers.
   - What's unclear: Whether the company already has an internal CA or wants to keep self-signed.
   - Recommendation: Follow CONTEXT.md; document both paths in the runbook and default to self-signed.

3. **Audit retentionDays default** *(RESOLVED by 05-03 Plan)*
   - What we know: CONTEXT.md D-05 proposes default 90 days.
   - What's unclear: Whether organizational policy requires a different retention.
   - Recommendation: Implement 90 as the schema default and make it configurable; adjust at install time.

4. **Help-coverage test scope for parameter-less functions** *(RESOLVED by 05-01 Plan)*
   - What we know: Functions like `Start-Adman` and `Test-AdmanCapability` have no parameters.
   - What's unclear: Whether the test should require `.PARAMETER` when no parameters exist.
   - Recommendation: Skip the parameter-count assertion when the AST param block is absent; still require `.SYNOPSIS`, `.DESCRIPTION`, and `.EXAMPLE`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows PowerShell 5.1 | CI desktop leg, dev baseline | yes | 5.1.22621.x (in-box) | — |
| PowerShell 7 (LTS line) | CI core leg, dev modern runtime | yes | 7.6.0 installed locally | Install 7.6.4 via setup action / MSI |
| Pester 6 | Test framework | yes | 6.0.0 installed | Install via PowerShell Gallery in CI |
| PSScriptAnalyzer 1.25.0 | Lint gate | yes | 1.25.0 installed | Install via PowerShell Gallery in CI |
| PSFramework 1.14.457 | Config/diagnostic logging | yes | 1.14.457 installed | Installed via `adman.psd1` RequiredModules |
| ActiveDirectory module (RSAT) | AD operations (not used in CI unit tests due to mocks) | yes | in-box/RSAT | Lab integration tests only |
| Git | Commit guard, CI | yes | latest | — |
| GitHub Actions | CI matrix | yes (cloud) | windows-latest | — |
| Code-signing certificate | AllSigned execution | must generate | self-signed | Enterprise PKI (not assumed) |

**Missing dependencies with no fallback:**
- None. All Phase 5 deliverables can be built with in-box or Gallery-installable tooling.

**Missing dependencies with fallback:**
- PowerShell 7.6.4 is not installed locally but can be installed via setup action or MSI.
- Self-signed cert is not present but can be generated with `New-SelfSignedCertificate`.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Pester 6.0.0 |
| Config file | `tests/PesterConfiguration.psd1` |
| Quick run command | `Invoke-Pester -Path tests -Output Normal -Tag Unit` |
| Full suite command | `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01 | README accurately describes install, first-run, and safe usage | manual review + smoke | `Invoke-Pester -Path tests -Tag Unit` (ensures no regressions) | ❌ Wave 0 |
| DOC-02 | USAGE.md covers every menu action and exported function | manual review + contract | markdown lint / docs coverage script | ❌ Wave 0 |
| DOC-03 | Every public function has SYNOPSIS, DESCRIPTION, PARAMETER, EXAMPLE | unit | `Invoke-Pester -Path tests/Help.Coverage.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| (success criterion 2) | Module runs under `AllSigned` | integration | CI leg with `Set-ExecutionPolicy AllSigned` | ❌ Wave 0 |
| (success criterion 2) | `CompatiblePSEditions` claim is honest | integration | CI matrix on 5.1 and 7.6 | ❌ Wave 0 |
| (D-05) | Audit hash-chain verifies correctly | unit | `Invoke-Pester -Path tests/Audit.Integrity.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| (D-05) | OUTCOME-write failure escalates to Event Log | unit | `Invoke-Pester -Path tests/Audit.EventLog.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| (D-08) | `.store/` cannot be committed | integration | `.githooks/pre-commit` + CI checkout scan | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `Invoke-Pester -Path tests -Tag Unit` (quick run)
- **Per wave merge:** Full suite via `tests/PesterConfiguration.psd1` plus PSScriptAnalyzer recursive
- **Phase gate:** Full suite green on both Windows PowerShell 5.1 and PowerShell 7.6 LTS, PSScriptAnalyzer clean, help-coverage test green, and `AllSigned` CI leg passing before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/Help.Coverage.Tests.ps1` — covers DOC-03
- [ ] `tests/Audit.Integrity.Tests.ps1` — covers D-05 hash chain
- [ ] `tests/Audit.EventLog.Tests.ps1` — covers D-05 event-log escalation on OUTCOME failure
- [ ] `.github/workflows/ci.yml` — covers dual-edition matrix and AllSigned
- [ ] `build/Sign-AdmanModule.ps1` — covers Authenticode signing
- [ ] `.githooks/pre-commit` — covers `.store/` commit guard
- [ ] CI checkout scan step — defense in depth for `.store/`
- [ ] `docs/USAGE.md` — covers DOC-02
- [ ] `docs/RECOVERY-RUNBOOK.md` — covers D-07
- [ ] Add `audit.retentionDays` to `config/adman.schema.json` and `config/adman.defaults.json`

*(Existing test infrastructure covers all prior phases; Phase 5 introduces the gaps above.)*

## Security Domain

> `security_enforcement` is enabled and ASVS Level 1 is targeted.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Pass-through Windows auth; no custom auth |
| V3 Session Management | no | No sessions |
| V4 Access Control | yes | Managed-OU scoping, deny-list, protected-account guard (existing); GPO restricts signing cert trust |
| V5 Input Validation | yes | Config schema validation, parameter validation, CSV schema validation (existing) |
| V6 Cryptography | yes | SHA-256 for audit hash chain; Authenticode SHA-256 signatures; DPAPI for credential file |
| V7 Error Handling | yes | Fail-closed audit, event-log escalation on OUTCOME failure |
| V8 Data Protection | yes | `.store/` gitignored + pre-commit + CI guard; DPAPI-encrypted credential file; no secrets in logs |
| V9 Communication | no | No external network protocols in v1 |
| V10 Malicious Code | yes | Authenticode signing + AllSigned execution policy; PSScriptAnalyzer lint gate |

### Known Threat Patterns for the Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Accidental commit of secrets/config | Information Disclosure | `.gitignore` + pre-commit hook + CI checkout scan |
| Tampering with audit log after the fact | Tampering | SHA-256 hash chain per record + `Get-AdmanAuditIntegrity` verifier |
| Running untrusted modified module | Tampering / Elevation of Privilege | Authenticode signing + `AllSigned` + GPO Trusted Publishers |
| Credential theft from disk | Information Disclosure | DPAPI encryption (`Export-Clixml` CurrentUser scope), separate from plain-JSON config |
| Audit write failure hides action | Repudiation | Fail-closed PENDING write refuses the action; OUTCOME failure escalates to Event Log |
| Bypass of safety guardrails | Tampering | PSScriptAnalyzer SAFE-08 rule + Pester AST guard prove no exported function calls AD write cmdlets directly |

## Sources

### Primary (HIGH/MEDIUM confidence)

- [Microsoft Learn - about_Signing](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.6) — execution policies, self-signed certs, `Trusted Root Certificates` requirement. [CITED]
- [Microsoft Learn - Set-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-authenticodesignature?view=powershell-7.6) — parameter signatures, `X509Certificate2`, SHA256 default, `Status`/`StatusMessage` output. [CITED]
- [Microsoft Learn - Examples of Comment-based Help](https://learn.microsoft.com/en-us/powershell/scripting/developer/help/examples-of-comment-based-help?view=powershell-7.6) — required blank lines, `.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE` structure. [CITED]
- [Microsoft Learn - Install PowerShell 7 on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6) — current LTS patch (7.6.4), MSI/MSIX install options, side-by-side with 5.1. [CITED]
- [Microsoft Learn - PowerShell Support Lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6) — 7.6 LTS support dates. [CITED]
- [GitHub Actions runner-images issue #14150](https://github.com/actions/runner-images/issues/14150) — runner images updating to PowerShell 7.6 LTS by June 22 2026. [CITED]
- [GitHub Docs - Using a matrix for your jobs](https://docs.github.com/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow) — matrix strategy syntax. [CITED]
- [PowerShell Gallery - Pester 6.0.0](https://www.powershellgallery.com/packages/Pester/6.0.0) — version, 5.1+Core support, published 2026-07-07. [VERIFIED]
- [PowerShell Gallery - PSScriptAnalyzer 1.25.0](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0) — version, min PS 5.1, published 2026-03-20. [VERIFIED]
- [PowerShell Gallery - PSFramework 1.14.457](https://www.powershellgallery.com/packages/PSFramework/1.14.457) — version, min PS 3.0, published 2026-07-02. [VERIFIED]

### Secondary (MEDIUM confidence)

- [Vexx32 - Verify Your Module's Help with Pester v5](https://vexx32.github.io/2020/07/08/Verify-Module-Help-Pester/) — pattern for iterating exported functions and asserting help sections. [CITED]
- [LazyWinAdmin - Using Pester to test your Comment Based Help](https://lazywinadmin.github.io/2016/05/using-pester-to-test-your-comment-based.html) — AST-based parameter help coverage. [CITED]
- [ContextCleaner tamper-evident audit log](https://automatalabs.ca/blog/contextcleaner-tamper-evident-audit-log-hash-chain/) — practical hash-chain design notes and honest threat model. [CITED]
- [pametan/audit-log (GitHub)](https://github.com/pametan/audit-log) — JSON Lines + SHA-256 hash-chain reference architecture. [CITED]

### Tertiary (LOW confidence)

- Web search summaries for JSON-lines log rotation and pre-commit hook patterns (no single authoritative source). [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — versions verified against PowerShell Gallery and Microsoft Learn; tools installed on research host.
- Architecture: **MEDIUM** — patterns drawn from official docs and established community examples; some CI specifics depend on runner image state at execution time.
- Pitfalls: **MEDIUM** — derived from official docs and observed project behavior (e.g., help coverage gap discovered by running `Get-Help` against the module).

**Research date:** 2026-07-21
**Valid until:** 2026-08-21 (stable PowerShell ecosystem; revisit if a new 7.6 LTS patch changes CI URLs or if Pester 6 has a stable release after current 6.0.0)
