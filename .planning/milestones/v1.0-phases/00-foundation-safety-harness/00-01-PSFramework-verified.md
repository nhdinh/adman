---
phase: 00-foundation-safety-harness
plan: 01
task: 1
artifact: psframework-build-time-reverification
assumption: A1
threat: T-00-SC
verified_utc: 2026-07-10T20:12:52Z
status: complete
---

# PSFramework 1.14.457 — Build-Time Re-Verification (Assumption A1)

**Purpose:** Discharge Assumption A1 (RESEARCH L634) and threat T-00-SC before the manifest pin in Task 2. The PowerShell Gallery is the registry of record (NOT npm/PyPI/crates). This probe is **read-only** — it does **not** install the module. The first install of PSFramework is gated behind explicit user approval (user_setup + the end-of-phase human check); `workflow.auto_advance` is ignored for that step because the automated package-legitimacy seam did not run in this environment.

## Verdict

Verdict: **[OK]** — existence, exact version, authorship, and publish date re-confirmed against the PowerShell Gallery at build time. (Exact cmdlet *parameter names* remain **[ASSUMED]** until the module is installed and `Get-Command` is run against the local bits — see "Parameter status" below. Policy D-01 is unaffected either way.)

## Version

Version: **1.14.457**

## Provenance (Gallery — `Find-PSResource -Name PSFramework -Version 1.14.457`)

| Field | Value |
|-------|-------|
| Name | PSFramework |
| Version | 1.14.457 |
| PublishedDate | 2026-07-02 (Gallery: `07/02/2026 09:12:15`) |
| Author | Friedrich Weinmann |
| Company | PowerShell Framework Collective |
| ProjectUri | http://psframework.org/ |
| LicenseUri | https://github.com/PowershellFrameworkCollective/psframework/blob/master/LICENSE |
| Repository | PSGallery |
| Probe source | `Microsoft.PowerShell.PSResourceGet` 1.2.0 → `Find-PSResource` (read-only) |
| Probe error | (none) |

**PublishedDate cross-check:** RESEARCH (L95, L137, L145) records PSFramework 1.14.457 as published **2026-07-02**. The Gallery value returned by this probe is `07/02/2026` → **match, no discrepancy.**

## Local install state (read-only check — Task 1 MUST NOT install)

`Get-Module -ListAvailable PSFramework` → **not installed — install pending user approval (user_setup / end-of-phase human check)**.

Because the module is not present locally, exact parameter sets were **not** dumped from local bits in this task (that dump happens post-approval). This is the documented branch (b) of Task 1.

## Install command (human-approved; run only after explicit approval)

```powershell
Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser
```

> RESEARCH (L126) shows the same pin with `-TrustRepository` appended; that flag is optional repository-trust sugar and does not change the pinned version. The canonical command above is the one surfaced to the end-of-phase human check.
>
> Dev toolchain (also CurrentUser scope, dev-only — distinct from the PSFramework production pin and authorized by the execution environment for the verify steps):
> ```powershell
> Install-PSResource -Name Pester -Version 6.0.0 -Scope CurrentUser
> Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -Scope CurrentUser
> ```

## Parameter status (A1) — confirmed vs expected

The safety-relevant surface consumed by Phase 0 (D-01) and plan 00-02:

| Cmdlet | Status | Expected / required parameters |
|--------|--------|-------------------------------|
| `Set-PSFConfig` | [ASSUMED-pending-local-`Get-Command`] | `-Value`, `-Initialize` (A1) |
| `Register-PSFConfigValidation` | [ASSUMED-pending-local-`Get-Command`] | (A1) |
| `Export-PSFConfig` | [ASSUMED-pending-local-`Get-Command`] | `-Path` (A1; **required** — pins config to the portable `.store/config.json`, disables magic auto-import per Pitfall 7) |
| `Import-PSFConfig` | [ASSUMED-pending-local-`Get-Command`] | `-Path` (A1; **required** — same rationale) |
| `Write-PSFMessage` | [ASSUMED-pending-local-`Get-Command`] | leveled diagnostic logging (D-01) |

**Post-approval re-confirm (run after the human-approved install, before/within plan 00-02 call sites):**

```powershell
Get-Command Set-PSFConfig, Register-PSFConfigValidation, Export-PSFConfig, Import-PSFConfig, Write-PSFMessage |
    ForEach-Object { $_.Name; $_.Parameters.Keys }
```

If a parameter name differs from A1, only the call sites in plan 00-02 change — the policy (D-01: PSFramework for config + diagnostics; audit stays hand-rolled/synchronous) is unaffected (A1 risk = MEDIUM, call-site-only).

## Decision impact

- The manifest in Task 2 pins PSFramework with an **exact** `RequiredVersion = '1.14.457'` (not a `ModuleVersion` floor), citing this artifact as evidence.
- No package was installed by this task; the install remains a human-approved action (T-00-SC).
