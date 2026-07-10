# Stack Research

**Domain:** Menu-driven (interactive TUI) PowerShell toolkit for on-prem Active Directory administration (AD object lifecycle, reporting/inventory, remote computer ops, provisioning/offboarding) with strong safety guardrails.
**Project:** adman (greenfield)
**Researched:** 2026-07-10
**Confidence:** HIGH (primary Microsoft Learn + PowerShell Gallery sources verified live; see Confidence Assessment)

## Recommendation in one paragraph

Target **Windows PowerShell 5.1 as the guaranteed-on-box baseline** and **PowerShell 7.6 LTS as the supported modern runtime**, writing to the **5.1 language subset** so the same module loads on both. Ship a single **root module (`adman.psd1`/`adman.psm1`) with dot-sourced `Public`/`Private` functions**. Treat the **ActiveDirectory module (RSAT) as a documented prerequisite, never bundled** (it is *natively compatible* with PS7 on Win10 1809+/Server 1809+ per Microsoft's compatibility list, so dual-edition is genuinely achievable). Use **CIM (`Get-CimInstance`/`New-CimSession`) for all inventory and as the no-WinRM fallback** (it is built into PS7 and replaces the removed `Get-WmiObject`), and **PSRemoting (`Invoke-Command`/`New-PSSession`) for live remote actions with CIM/DCOM fallback**. Build the **TUI by hand** (`$Host.UI.PromptForChoice` / `Read-Host`) so it is identical on 5.1 and 7 and works over remoting and on Server Core; offer `Out-ConsoleGridView` only as an optional Core-only enhancement. Test with **Pester 6.0.0**, lint with **PSScriptAnalyzer 1.25.0**, document with inline comment-based help plus **Microsoft.PowerShell.PlatyPS 1.0.2** for external help, and distribute as a signed module via **Microsoft.PowerShell.PSResourceGet 1.2.0** to an internal repository.

## PowerShell version targeting strategy (the #1 decision)

| Runtime | Role | Verdict |
|---------|------|---------|
| **Windows PowerShell 5.1** (Aug-2016, OS component) | **Primary baseline / required** | Ships on every supported Windows workstation and server; the AD module, `Microsoft.PowerShell.LocalAccounts`, and `CimCmdlets` are all present. Supported under the Windows OS support lifecycle (no separate EOL). |
| **PowerShell 7.6.3 (LTS, .NET 10)** | **Supported modern runtime** | Current LTS, released 2026-03-18, supported to **2028-11-14**. Run here when installed; the `ActiveDirectory` module is *natively compatible* on 1809+ builds. |
| PowerShell 7.5 (.NET 9) | Don't optimize for it | STS/current release, **EOL 2026-11-10**. It will run the tool, but do not target or test primarily against it. |
| PowerShell 7.4 (LTS, .NET 8) | Don't optimize for it | Previous LTS, **EOL 2026-11-10**. Same guidance as 7.5. |
| PowerShell 7.7-preview | Ignore | Preview/unsupported for production. |

**Authoring discipline (load-bearing):** write to the **PowerShell 5.1 language subset**. Do **not** use 7-only syntax/features unless guarded by `$PSEdition`/`$PSVersionTable`: the ternary operator `?:`, null-coalescing `??`/`??=`, pipeline chain operators `&&`/`||`, `-parallel` `ForEach-Object -Parallel`, `.NET` APIs not present in .NET Framework, or `ConvertFrom-Json -AsHashtable` (5.1 lacks `-AsHashtable`). Declare `PowerShellVersion = '5.1'` and `CompatiblePSEditions = @('Desktop','Core')` in the manifest **only after** the CI matrix actually passes on both 5.1 and 7.6 — otherwise claim `Desktop` only and be honest. Confidence: HIGH.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Windows PowerShell** | **5.1** | Primary runtime | It is what is guaranteed present on admin workstations and servers; the team's current scripts already target it. Writing to the 5.1 subset maximizes portability ("no code changes" between workstation and jump host). HIGH. |
| **PowerShell** | **7.6.3 LTS** | Modern runtime (optional, supported) | Current LTS (support to 2028-11-14). The AD module is natively compatible here on supported Windows builds, so the same module runs unchanged. Avoid 7.4/7.5 (EOL Nov 2026) as targets. HIGH. |
| **ActiveDirectory module (RSAT)** | ships with Windows/RSAT | AD user/computer/group/OU lifecycle | The only Microsoft-supported cmdlet surface for on-prem AD. Treated as a **prerequisite, never bundled** (per project constraint). **Natively compatible** with PS7 on Win10 1809+/Server 1809+ (Microsoft module-compatibility list). Note: `ADDSDeployment` (DC promo) still needs the compatibility layer — out of scope here. HIGH. |
| **CimCmdlets** | built-in (5.1) / built-in (PS7) | Inventory + no-WinRM remote fallback | `Get-CimInstance`, `Invoke-CimMethod`, `New-CimSession`. Present in both editions and *built into* PS7; the supported replacement for `Get-WmiObject` (removed in PS7). Use `New-CimSessionOption -Protocol Dcom` for the DCOM fallback when WinRM is absent — this is the modern, dual-edition equivalent of `Get-WmiObject -ComputerName`. HIGH. |
| **PSRemoting / WinRM (`Microsoft.PowerShell.Core`)** | built-in | Live remote computer operations | `Invoke-Command`/`New-PSSession`/`Enter-PSSession` for actions where WinRM is enabled; the tool auto-detects and falls back WinRM → CIM(DCOM) → skip per host. HIGH. |
| **Microsoft.PowerShell.LocalAccounts** | built-in | Local user lifecycle requirement | Natively compatible with PS7; covers the "AD/Local user lifecycle" requirement for local accounts on managed machines. HIGH. |

### Supporting Libraries / Modules

| Library / Module | Version | Purpose | When to Use |
|------------------|---------|---------|-------------|
| **Microsoft.PowerShell.ConsoleGuiTools** (`Out-ConsoleGridView`, `Show-ObjectTree`) | **0.7.7** (2024-05-01) | Optional graphical object-picker | **Optional enhancement only**, and only when `$PSEdition -eq 'Core'` and the module is present. **Core-only (min PS 7.2) — does not load on 5.1**, and it has had no release since 2024-05 (dormant). Never a hard dependency; the hand-rolled menu is the primary UI. Facts HIGH; recommending it at all MEDIUM (it is sugar, not infrastructure). |
| **Pester** | **6.0.0** | Unit/integration test + mock framework | The standard PowerShell test framework. v6 supports **Windows PowerShell 5.1 and PS 7.4+**, matching our dual target. Mock every AD/CIM/remoting cmdlet; unit tests must never touch a live domain. HIGH. |
| **PSScriptAnalyzer** | **1.25.0** | Static analysis + formatting | Min PS 5.1; the de-facto linter. Ships `Invoke-ScriptAnalyzer`, `Get-ScriptAnalyzerRule`, `Invoke-Formatter`. Enforce rules that map directly to this project's guardrails (see below). HIGH. |
| **Microsoft.PowerShell.PlatyPS** | **1.0.2** (2026-07-09) | External Markdown/MAML help | The **GA successor** to legacy `platyPS 0.14.2`; tagged **Core + Desktop**. Generates `Update-Help`-able external help from Markdown. Note the cmdlet surface is *different* from 0.x (see "What NOT to mix"). HIGH. |
| **Microsoft.PowerShell.PSResourceGet** | **1.2.0** (2026-03-11; 1.3.0-preview1 prerelease) | Package/module management + publishing | Microsoft **replaces PowerShellGet + PackageManagement** with this module; "for best results, use the latest version." Min PS 5.1. Use `Register-PSResourceRepository` + `Install-PSResource`/`Publish-PSResource` against an internal feed. HIGH. |

### Built-in capabilities to prefer over new dependencies

| Capability | Built-in cmdlet/API | Why not add a dependency |
|------------|--------------------|--------------------------|
| **Encrypted config** (project requirement) | `ConvertTo-SecureString`/`ConvertFrom-SecureString` (Windows **DPAPI**, user- or machine-scoped) | No extra module, works on 5.1+7 on Windows. Scope to the installing user for a single-admin config, or machine key for shared jump hosts. DPAPI is Windows-only and key-bound — fine for on-prem. HIGH. |
| **Audit log** | hand-rolled `Write-Log` writing **JSON-lines** (`ConvertTo-Json -Compress` per entry, append) | Structured, parseable, zero deps. Defer a logging framework (e.g. PSFramework) to a later milestone. MEDIUM. |
| **Credential capture** | `Get-Credential` → `[pscredential]`; pass via `-Credential` to AD/CIM/remoting cmdlets | Never store plaintext; never log credentials; only momentarily marshal a `SecureString` when an API requires it. HIGH. |
| **Console tables / CSV / HTML reports** | `Format-Table`/`Out-String`, `Export-Csv`, `ConvertTo-Html` (with an embedded CSS fragment for "self-contained" HTML) | Covers the "console + CSV + HTML" reporting requirement with no packages. HIGH. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **VS Code + PowerShell extension** | Authoring/debugging | Reference implementation for the "PowerShell" profile; enable `powershell.scriptAnalysis.settingsPath` → repo `PSScriptAnalyzerSettings.psd1`. Works for both 5.1 and 7 sessions. HIGH. |
| **PSScriptAnalyzer** settings file | Lint gate | Commit `PSScriptAnalyzerSettings.psd1`. Enable: `PSUseShouldProcessForStateChangingFunctions` (directly enforces the `-WhatIf`/dry-run guardrail), `PSAvoidUsingPlainTextForPassword`, `PSUsePSCredentialType`, `PSAvoidGlobalVars`, `PSUseApprovedVerbs`, `PSAvoidUsingCmdletAliases`, `PSUseConsistentIndentation`. Add a *documented* suppression for `PSAvoidUsingWriteHost` **only** in the TUI-rendering module (the menu legitimately paints the console). HIGH. |
| **Pester** config | Test gate | `Invoke-Pester -Configuration` with code coverage (v6 uses the profiler-based coverage by default), CI exit on failure. Separate `*.Tests.ps1` (unit, fully mocked) from `*.Integration.Tests.ps1` (run only against a disposable test OU/lab). HIGH. |
| **platyPS** | Help authoring | Author `docs/*.md`, generate external help XML into `en-US/` for `Update-Help`. Keep inline **comment-based help** as the source of truth for v1 (works everywhere, zero build); add platyPS external help once the cmdlet surface stabilizes. HIGH (version) / MEDIUM (timing). |
| **Authenticode signing** (`Set-AuthenticodeSignature`) | Trust under `AllSigned` | Sign `.psd1`/`.psm1`/`.ps1` with an enterprise code-signing cert so the tool runs under `AllSigned`/`RemoteSigned` without prompts — appropriate for a security-sensitive admin tool. HIGH. |
| **PSake / Invoke-Build** (optional) | Build automation | Either is fine for `build`/`test`/`publish` tasks. `Invoke-Build` is lighter and dependency-free-ish; pick one, standardize. LOW (either works; not load-bearing). |

## Installation

```powershell
# --- Prerequisite: ActiveDirectory module (RSAT). Document, do NOT bundle. ---
# Windows 10 1809+ / Windows 11 (Pro/Enterprise/Education only — NOT Home/Standard):
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
# Windows Server (the PowerShell AD tools feature):
Install-WindowsFeature -Name RSAT-AD-PowerShell   # then: Import-Module ActiveDirectory

# --- Supported package manager (the in-box PowerShellGet 1.0.0.1 on 5.1 is UNSUPPORTED) ---
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope CurrentUser -Force   # 1.2.0

# --- Dev toolchain (CurrentUser scope) ---
Install-PSResource -Name Pester            -Version 6.0.0  -Scope CurrentUser -TrustRepository
Install-PSResource -Name PSScriptAnalyzer  -Version 1.25.0 -Scope CurrentUser
Install-PSResource -Name Microsoft.PowerShell.PlatyPS -Version 1.0.2 -Scope CurrentUser

# --- Optional, Core-only picker enhancement (PS 7.2+ only) ---
Install-PSResource -Name Microsoft.PowerShell.ConsoleGuiTools -Version 0.7.7 -Scope CurrentUser

# --- Install the tool itself from the internal repository ---
Register-PSResourceRepository -Name 'AdmanInternal' -Uri '\\fileshare\psrepo' -Trusted
Install-PSResource -Name adman -Repository AdmanInternal -Scope CurrentUser
Import-Module adman
```

## Module layout

```
adman/
  adman.psd1            # manifest: RootModule='adman.psm1', ModuleVersion (SemVer),
                        # PowerShellVersion='5.1', CompatiblePSEditions=@('Desktop','Core'),
                        # RequiredModules=@()   # <- ActiveDirectory is a PREREQ, not a dependency
                        # FunctionsToExport explicit (never '*'); GUID; Author; CompanyName
  adman.psm1            # dot-sources Private/* then Public/*; exports Public
  Public/               # one file per exported Verb-Noun function (Get-AdmanUser, Set-AdmanUser, ...)
  Private/              # helpers: guardrails (Assert-ManagedOu, Test-ProtectedAccount),
                        #   Invoke-AdmanSafeguard (ShouldProcess wrapper), Write-AdmanAudit,
                        #   Connect-AdmanRemote (WinRM->CIM->skip), Read-AdmanMenu (TUI)
  en-US/                # external help XML generated by platyPS (about_adman*.txt here too)
  config.schema.json    # schema for the encrypted config file
  tests/                # *.Tests.ps1 (mocked) + *.Integration.Tests.ps1 (lab-only)
  PSScriptAnalyzerSettings.psd1
```

Authoritative pattern references: Microsoft Learn "How to write a PowerShell script module" and "How to write a PowerShell module manifest". Confidence: HIGH.

## Alternatives Considered

| Recommended | Alternative | When to Use the Alternative |
|-------------|-------------|------------------------------|
| Hand-rolled menu (`$Host.UI.PromptForChoice`/`Read-Host`) | **Terminal.Gui** / Spectre.Console-style rich TUI | If a future GUI-grade dashboard becomes in-scope. For v1 the rich TUI adds .NET/edition friction and over-remoting flakiness for no safety benefit. |
| Hand-rolled menu | `Out-ConsoleGridView` as the *primary* UI | Only if the project drops 5.1 (it won't — 5.1 is required). ConsoleGuiTools is Core-only. |
| CIM over WSMan, DCOM fallback | Plain `Get-WmiObject` everywhere | Only on a pure-5.1-forever, never-PS7 environment — which contradicts the "ideally 7.x" goal. |
| Microsoft.PowerShell.PlatyPS **1.0.2** | legacy **platyPS 0.14.2** | If the team already has a large 0.x Markdown corpus and a working `New-MarkdownHelp` pipeline, stay on 0.14.2 temporarily. Greenfield should start on 1.0.2. |
| `Microsoft.PowerShell.PSResourceGet` 1.2.0 | `PowerShellGet` 2.2.5 / `PackageManagement` | Only on a locked-down image where PSResourceGet cannot be installed; PowerShellGet 2.2.5 still functions but is the legacy line. |
| JSON-lines audit log (hand-rolled) | **PSFramework** logging/config | When the tool grows to need runspaces, centralized config schema, and logging providers — a natural v2 upgrade. |

## What NOT to Use

| Avoid | Why (specific) | Use Instead |
|-------|----------------|-------------|
| **`Get-WmiObject`** | Deprecated since PS 3.0 and **removed entirely from PowerShell 7**; using it breaks the dual-edition goal outright. | `Get-CimInstance` / `Invoke-CimMethod` (present in 5.1, built into 7). |
| **`wmic.exe`** | Being **removed from Windows (Win11 25H2)**. Only the `wmic.exe` wrapper is removed (WMI infrastructure stays), but scripts calling it will break. | CIM cmdlets (`Get-CimInstance`) or .NET `System.Management`/`Microsoft.Management.Infrastructure`. |
| **`-ComputerName` on CIM for the no-WinRM path** | Works but opens a fresh DCOM connection each call (slow, dynamic RPC ports, hard to firewall). | A reusable `New-CimSession` with `New-CimSessionOption -Protocol Dcom` for the fallback leg. |
| **Legacy `platyPS 0.14.2` mixed with `Microsoft.PowerShell.PlatyPS 1.0.x`** | Different cmdlet names: 0.x uses `New-MarkdownHelp`/`Update-MarkdownHelp`/`New-ExternalHelp`; 1.0.x uses `New-MarkdownCommandHelp`/`Update-MarkdownCommandHelp`/`New-HelpCabinetFile` and a new Markdown schema. Mixing breaks builds. | Pick **one** module (1.0.2 for greenfield) and standardize. |
| **In-box `PowerShellGet 1.0.0.1`** (ships in WinPS 5.1) | **No longer supported** per Microsoft. | Update to `Microsoft.PowerShell.PSResourceGet` 1.2.0 (or at least PowerShellGet 2.2.5). |
| **`ps2exe` / `PS2EXE-GUI` to ship an `.exe`** | Out of scope for v1 per PROJECT.md; it **wraps** the `.ps1` in a .NET host (does **not** compile), still needs PowerShell on target, and the script is extractable — so it is **not** a code-hiding/security boundary. `PS2EXE-GUI` is usable but stalled. | Ship a signed module; revisit `Invoke-PS2EXE` (~1.0.17) only if a compiled artifact is explicitly approved in v2. |
| **`Set-AD*`-without-`-WhatIf` / functions without `SupportsShouldProcess`** | Defeats the core safety property (dry-run on every destructive action). PSScriptAnalyzer can flag this. | Every state-changing function: `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` + `$PSCmdlet.ShouldProcess(...)`. Enforced by `PSUseShouldProcessForStateChangingFunctions`. |
| **Storing credentials in plaintext / a secret vault in v1** | Out of scope and an audit risk per PROJECT.md; DPAPI-scoped `SecureString` in the encrypted config is sufficient. | `Get-Credential` at runtime + `ConvertFrom-SecureString` (DPAPI) for the saved config only. |
| **Cmdlet aliases / positional params in module code** | Breaks in strict profiles and hurts readability/review. | Full cmdlet names + named parameters (lint: `PSAvoidUsingCmdletAliases`). |

## Stack Patterns by Variant (PowerShell edition)

**If running on Windows PowerShell 5.1 (the common case):**
- Hand-rolled TUI only (ConsoleGuiTools is unavailable).
- All AD/CIM/remoting cmdlets run natively.
- `ConvertFrom-Json` has **no `-AsHashtable`** — convert JSON to `PSCustomObject` and index by property, or shim.
- Because: 5.1 is the required baseline and the only edition guaranteed present.

**If running on PowerShell 7.6 LTS:**
- Same module, same code paths; `ActiveDirectory` loads natively (1809+).
- `Out-ConsoleGridView` *may* be offered for picker screens after a capability probe (`$PSEdition -eq 'Core' -and (Get-Module -ListAvailable Microsoft.PowerShell.ConsoleGuiTools)`).
- Because: 7.6 is current LTS and the only 7.x line with support past Nov 2026.

**If running over an interactive PSRemoting session or on Server Core:**
- The hand-rolled menu still works (it uses `$Host.UI`, not WinForms/WPF).
- Any `Out-ConsoleGridView`/graphical picker must be auto-suppressed (no GUI over remoting/Core).
- Because: discoverability must survive headless and remoted contexts.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| PowerShell 7.6.3 LTS | .NET 10; Win10 1809+/Win11/Server 2019–2025 | Support to 2028-11-14. AD module natively compatible on 1809+. |
| Windows PowerShell 5.1 | .NET Framework 4.x; in-box on all supported Windows | Supported via Windows OS lifecycle; no separate EOL. |
| ActiveDirectory (RSAT) | Win10 1809+/Win11 (Pro/Ent/Edu) + Server 1809+ | Natively compatible with PS7; `ADDSDeployment` still needs the compat layer (out of scope). |
| CimCmdlets | 5.1 (in-box) + PS7 (built-in) | The cross-edition remoting/inventory backbone. |
| Microsoft.PowerShell.LocalAccounts | 5.1 + PS7 (natively compatible) | Local user lifecycle. |
| Pester 6.0.0 | WinPS 5.1 **and** PS 7.4+ | Matches the dual target. v6 dropped `Assert-MockCalled`/`Assert-VerifiableMock` (use `Should -Invoke`) and uses profiler-based coverage by default — mind when reading older examples. |
| PSScriptAnalyzer 1.25.0 | Min PS 5.1 (Desktop + Core) | Single version serves both editions. |
| Microsoft.PowerShell.PlatyPS 1.0.2 | Core + Desktop | GA successor to `platyPS 0.14.2`; do not mix the two. |
| Microsoft.PowerShell.PSResourceGet 1.2.0 | Min PS 5.1 | Replaces PowerShellGet/PackageManagement. |
| Microsoft.PowerShell.ConsoleGuiTools 0.7.7 | **PS 7.2+ Core only** | Not loadable on 5.1; last release 2024-05. Optional only. |

## Confidence Assessment

| Area | Level | Why |
|------|-------|-----|
| PowerShell version targeting (5.1 + 7.6 LTS; avoid 7.4/7.5) | HIGH | Verified against Microsoft Learn Support Lifecycle (ms.date 2026-06-13). |
| ActiveDirectory module = prereq; natively PS7-compatible on 1809+ | HIGH | Microsoft Learn Windows module-compatibility list (Server 2025) explicitly marks `ActiveDirectory` "Natively Compatible"; RSAT install path from Microsoft Learn RSAT page (ms.date 2026-02-24). |
| CIM over WMI; `Get-WmiObject` removed in PS7; `wmic.exe` retiring | HIGH | Microsoft Support WMIC-removal article + broad corroboration; CimCmdlets "built into PS7" per compatibility list. |
| TUI: hand-rolled primary; ConsoleGuiTools optional/Core-only | HIGH (facts) / MEDIUM (whether to ship the optional picker) | Gallery confirms ConsoleGuiTools 0.7.7 is Core-only (min 7.2), last released 2024-05. The "hand-rolled for 5.1 parity" conclusion follows directly. |
| Pester 6.0.0 / PSScriptAnalyzer 1.25.0 / PlatyPS 1.0.2 / PSResourceGet 1.2.0 | HIGH | PowerShell Gallery + Microsoft Learn PSGet overview (ms.date 2026-05-20). |
| DPAPI for encrypted config; JSON-lines audit; Authenticode signing | HIGH | Built-in Windows/PowerShell capabilities; standard enterprise practice. |
| ps2exe "not a security boundary / out of scope" | MEDIUM | Version (~1.0.17) from secondary sources; the architectural facts (wraps, doesn't compile, extractable) are well established. |

## Sources

- [PowerShell Support Lifecycle — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle) — 7.6.3 current LTS (2026-03-18 → 2028-11-14, .NET 10), 7.5/7.4 EOL 2026-11-10, 5.1 via Windows lifecycle; AD module supported under Windows lifecycle. HIGH.
- [PowerShell 7 module compatibility in Windows Server 2025 — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/windows/module-compatibility) — `ActiveDirectory`, `CimCmdlets`, `LocalAccounts`, `DnsServer`, `BitLocker` "Natively Compatible"; `ADDSDeployment` "Works with Compatibility Layer"; `GroupPolicy` "Untested"; `PSScheduledJob` not supported. HIGH.
- [Remote Server Administration Tools — Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools) — RSAT Pro/Ent/Edu only (not Home); Win10 1809+/Win11 install via Optional Features/Capabilities. HIGH.
- [Package management for PowerShell — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/overview) — PSResourceGet 1.2.0 replaces PowerShellGet/PackageManagement; in-box PowerShellGet 1.0.0.1 unsupported. HIGH.
- [Microsoft.PowerShell.ConsoleGuiTools — PowerShell Gallery](https://www.powershellgallery.com/packages/Microsoft.PowerShell.ConsoleGuiTools) — 0.7.7, 2024-05-01, Core-only (min 7.2), exports `Out-ConsoleGridView`/`Show-ObjectTree`. HIGH.
- [Pester — PowerShell Gallery](https://www.powershellgallery.com/packages/Pester) — 6.0.0; [Pester v5→v6 migration](https://pester.dev/docs/v6/migrations/v5-to-v6). HIGH.
- [PSScriptAnalyzer — PowerShell Gallery](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0) — 1.25.0, min PS 5.1. HIGH.
- [Microsoft.PowerShell.PlatyPS — PowerShell Gallery](https://www.powershellgallery.com/packages/Microsoft.PowerShell.PlatyPS) — 1.0.2 (2026-07-09), Core+Desktop, new cmdlet surface (`New-MarkdownCommandHelp`…). HIGH.
- [Microsoft.PowerShell.PSResourceGet — PowerShell Gallery](https://www.powershellgallery.com/packages/Microsoft.PowerShell.PSResourceGet) — 1.2.0 (2026-03-11), min PS 5.1. HIGH.
- [WMIC removal from Windows — Microsoft Support](https://support.microsoft.com/en-us/topic/windows-management-instrumentation-command-line-wmic-removal-from-windows-e9e83c7f-4992-477f-ba1d-96f694b8665d) — only `wmic.exe` wrapper removed; migrate to CIM/PowerShell. HIGH.
- PS2EXE status (≈1.0.17, wraps-not-compiles) — secondary sources (e.g. [4sysops PS2EXE/Win-PS2EXE](https://4sysops.com/archives/convert-a-powershell-script-into-an-exe-with-ps2exe-and-win-ps2exe/), [PS2EXE-GUI status](https://hope-it-works.github.io/PS2EXE-GUI/)). MEDIUM.

## Gaps / items to confirm at requirements or phase research

- **Server feature name nuance:** the compatibility doc's example `Install-WindowsFeature -Name ActiveDirectory` installs role bits; the AD *PowerShell tools* feature on Server is `RSAT-AD-PowerShell`. Confirm target-server SKUs in Phase research before hard-coding the prereq installer. (Does not change the recommendation.)
- **Whether to ship `Out-ConsoleGridView` pickers at all in v1:** defensible either way; default to "hand-rolled only" for the MVP and add the picker as a PS7 nicety once the core is stable.
- **External (platyPS) help vs. comment-based help only in v1:** comment-based help is sufficient for MVP; adopt `Microsoft.PowerShell.PlatyPS 1.0.2` when the cmdlet surface freezes.
- **Code-signing cert availability:** enterprise PKI vs. self-signed for the internal repo — confirm in the security/packaging phase.

---
*Stack research for: menu-driven PowerShell on-prem AD administration toolkit (adman)*
*Researched: 2026-07-10*
