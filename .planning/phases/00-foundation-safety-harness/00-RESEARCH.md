# Phase 0: Foundation & Safety Harness - Research

**Researched:** 2026-07-10
**Domain:** PowerShell (5.1 + 7.6 LTS) safety spine for on-prem Active Directory administration
**Confidence:** HIGH (mechanisms corroborated against Microsoft Learn / PowerShell Gallery / official GitHub; PSFramework exact signatures MEDIUM — verify at build)

> **Tooling note:** The `gsd-tools` research-plan/research-store seam is **not executable in this environment** (`gsd-core/bin/gsd-tools.cjs` is present but no `node` runtime is on PATH, so the binary cannot run). Research therefore used the built-in `WebSearch`/`WebFetch` fallback providers (allowed per tool strategy); confidence tiers were classified directly per the source hierarchy (Microsoft-authored docs + PowerShell Gallery + official GitHub = HIGH; vendor/community corroboration = HIGH–MEDIUM). No cached digests were written to the seam — consistent with the prior `.planning/research/` corpus. The `package-legitimacy` seam check likewise could not run; see the Package Legitimacy Audit for the manual Gallery-based verdicts and the build-time re-verification command.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Hybrid — PSFramework (pinned) for config + diagnostic logging; audit stays a synchronous, hand-rolled, throw-on-failure writer.** Adopt **PSFramework 1.14.457** (pin in manifest/CI) for validated config (`Set-PSFConfig`/`Register-PSFConfigValidation`) + leveled diagnostic logging (`Write-PSFMessage`). The audit writer (00-05) is NOT routed through PSFramework — it remains in-process, synchronous, throws on failure (SAFE-04 fail-closed). Reconcile ROADMAP 00-01 wording + CLAUDE.md "Alternatives Considered" accordingly. Caveats: PS 5.1 `ConvertFrom-Json` has no `-AsHashtable`; `ConvertTo-Json` defaults `-Depth 2` (truncates nested config → pass `-Depth` explicitly); pin config path with `Export-PSFConfig`/`Import-PSFConfig -Path`, do NOT rely on PSFramework magic per-user/per-machine default locations (fail-open risk). Fail-closed semantics live in `Initialize-Adman` regardless of framework. PSFramework becomes the **second mandatory module** (after RSAT) on every host.
- **D-02: Protected-account detection (SAFE-06) = runtime-SID resolution + one `LDAP_MATCHING_RULE_IN_CHAIN` query over (7 protected groups ∪ `adman-Protected`); gMSA blocked by `objectClass` pre-filter; flat deny-list as the hard floor.** DomainSID from `(Get-ADDomain).DomainSID` + RIDs 512/519/518; builtin `S-1-5-32-544/-548/-551/-549`; defense-in-depth 525/526-527. One DC-side filter `memberOf:1.2.840.113556.1.4.1941:=<DN>` across the 7 protected groups + `adman-Protected`; no client-side member materialization. Service accounts = membership in `adman-Protected` only; `svc_` naming heuristic is warning-only. gMSA: refuse `objectClass` in `msDS-GroupManagedServiceAccount`/`msDS-ManagedServiceAccount` (run pre-filter first; still run IN_CHAIN after). `adminCount` explicitly NOT used.
- **D-03: Fail-closed audit (SAFE-03/04) = write-ahead reservation.** Named mutex `Global\adman-audit` → open daily-rotated `.store/audit/audit-YYYYMMDD.jsonl` (Append/Write/Read-share) → write **PENDING** `{correlationId}` → `Flush(true)` → **on ANY exception throw before touching AD (the refusal)** → mutate → append **OUTCOME** best-effort. Refusal triggers: path missing + auto-create failed, ACL denial, disk full (112), sharing violation, unreachable path. OUTCOME failure after a successful mutation → escalate to Event Log + loud UI + session flag; never fake AD rollback. Default local `.store/audit/` (gitignored); UNC/collector primary adds network-failure mode — keep primary local, forward copy as secondary. Schema (no secrets): `tsUtc, who(user+domain+SID), what(verb+function), scope(managed-OU root), target(DN+SID+objectClass), count, whatIf, result, reason, correlationId, host, psEdition, moduleVersion`.
- **D-04: First-run (CONF-01/02/03) = annotated `config.example.json` AND optional `init`/wizard emitting the SAME JSON, plus `doctor`/`validate`.** One shared JSON schema used by both writer + loader. Wizard is a pure emitter of flat, machine-independent JSON (no JSONC/JSON5; "annotated example" is a sibling/README or `_comment` keys the loader strips). First-run wizard runs in **setup mode** (writes `.store/config.json`, no AD mutation) — the fail-closed gate must NOT block the wizard that creates the config. DN syntax validated at input; OU existence/reachability best-effort at setup, re-validated authoritatively at every startup (the real gate).
- **D-05: Starter deny-list (SAFE-05) = minimal SID-based core seed, matched by `objectSid`/RID.** Seed krbtgt (RID-502), Guest (RID-501), built-in Administrator (RID-500). Match on `objectSid`/RID, never `sAMAccountName` (RID-500 renamed via GPO). Store as portable tokens (RID suffix `500/501/502` resolved against `(Get-ADDomain).DomainSID` at match time; well-known SIDs like `S-1-5-32-544` as literals). Seed written INTO the JSON file (visible/editable/diffable), labeled "starter, not exhaustive"; code holds only the default used to populate a fresh file; thereafter the file is the single source of truth.
- **D-06: Credential "remember me" (CONF-04/06) = `Export-Clixml` CurrentUser + `credentialPolicy.allowRememberMe` flag + checkbox on first capture.** Pass-through default; stored credential consumed ONLY when pass-through rights insufficient (never short-circuits the per-task rights check). On explicit consent (checkbox, offered only when `allowRememberMe` true), write via `Export-Clixml` (DPAPI CurrentUser) to `.store/`; identical on 5.1 + 7.6 on Windows. Restore failure handling: wrap `Import-Clixml` in try/catch for `CryptographicException` ("Key not valid for use in specified state"/"data is invalid") AND guard empty-password case (`$cred.GetNetworkCredential().Password` throws) → on EITHER signal delete the bad file and fall back to `Get-Credential`. Do NOT use `Export-Clixml -EncryptionKey` (PS7-only); reject a keyed-AES file. LocalMachine scope is a documented opt-in ONLY for a dedicated ACL-locked jump host (any local process/admin can unwrap); never on a general workstation.
- **D-07: Confirmation scaled to blast radius (SAFE-02) = type the exact count, configurable threshold (default 5).** Below threshold: one `ShouldProcess` y/n that names the count, default-No. At/above: demand exact count typed (case-sensitive, no Enter-to-accept). Threshold = `safety.bulkConfirmThreshold` (default 5); stricter `>1` allowed only as a per-OU override. ShouldProcess interaction: resolve target set FIRST, run gate ONCE, execute inner destructive cmdlets with `-Confirm:$false` (no per-object re-prompt); automation escape hatch = deliberate `-Force` switch (plus honoring `-Confirm:$false`), mirroring Azure's `-Confirm:$false -Force` idiom. Non-bypassable (any flag): deny-list, protected-account block, managed-OU scope, Phase-4 max-count CAP. Log the confirmation (who/verb/count/token-type) — never the credential.

### Claude's Discretion

- Concrete managed-OU roots, domain name, report/audit paths, transport order/timeouts, and exact bulk CAP value are runtime configuration captured by the wizard/`config.example.json` — not hard-coded. Schema + validation in scope; values environment-specific.
- Internal function/file names under `Public/`/`Private/` and exact manifest fields are planner discretion within the ROADMAP 00-01 scaffold.
- Whether to add Protected Users (525)/Key Admins (526-527) to the default protected set is planner discretion (recommended where present).

### Deferred Ideas (OUT OF SCOPE)

- Expanded Tier-0/AdminSDHolder deny-list seed (DA 512/EA 519/Schema 518/Protected Users 525 + `adminCount` guard) — second layer for Phase 2+.
- `tokenGroups`-based effective-membership report — read-only Phase 1/5, not the SAFE-06 primitive.
- LocalMachine DPAPI credential scope — documented opt-in only (D-06).
- Event Log/SIEM forwarding as a PRIMARY audit sink — keep audit local (D-03); forwarding is Phase 5 hardening (ROADMAP 05-03).
- Keyed-AES portable credential file — rejected for v1 (`Export-Clixml -EncryptionKey` is PS7-only).
- Write-after "refuse on failure" audit — never for destructive actions.
- Bulk-starts-at-`>1` confirmation — rejected as global default; per-OU override only.
- Bulk CAP value, transport order/timeouts, managed-OU roots, domain name, report/audit paths — runtime config; CAP enforcement is Phase 4/BULK-02.
- RSAT server feature-name vs target-SKU nuance — confirm during Phase 0/5 research (affects prereq installer, not gate design).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-05 | Startup probes capabilities (RSAT, domain, rights, transport) + actionable guidance | §Pattern: Capability probe; §Pitfall: probe design; `Test-WSMan`/`Get-ADDomain`/ADWS 9389; PSFramework `Write-PSFMessage` for guidance |
| CONF-01 | Load portable plain-JSON non-secret config at startup | §D-01/D-04; PSFramework `Import-PSFConfig -Path`; PS 5.1 `ConvertFrom-Json` (no `-AsHashtable`); JSON schema shared by wizard+loader |
| CONF-02 | Fail closed if managed-OU empty or deny-list/config fails to load | §Pattern: fail-closed `Initialize-Adman`; §Pitfall: empty/valid-but-empty deny-list; DN syntax vs authoritative OU re-validation |
| CONF-03 | Save/reload config (portable, diff-friendly) | §D-04; single shared schema; `Export-PSFConfig -Path`; `-Depth` on save |
| CONF-04 | Opt-in DPAPI credential file in `.store/`; re-prompt on cross-machine/user restore | §Pattern: DPAPI credential file (D-06); `Export-Clixml`/`Import-Clixml` CurrentUser; `CryptographicException` 0x8009000B handling |
| CONF-05 | Both files in gitignored `.store/`; no secrets in repo/logs | `.store/` already gitignored (verified); audit schema has no secret fields; PSSA `PSAvoidUsingPlainTextForPassword` |
| CONF-06 | Pass-through default; rights checked each task; prompt only when insufficient | §Pattern: rights probe (non-destructive); `Get-AdmanCredential` decision; D-06 |
| SAFE-01 | Every destructive action supports `-WhatIf`/dry-run, per object | §Pattern: gate + ShouldProcess; PSSA `PSUseShouldProcessForStateChangingFunctions`; AD provider `-WhatIf` caveat (§Pitfall) |
| SAFE-02 | Confirmation scaled to blast radius (y/n single; typed token+count bulk) | §Pattern: `Confirm-AdmanAction`; ShouldProcess vs ShouldContinue + `-Force` idiom (verified); D-07 |
| SAFE-03 | Every action incl. dry-runs appends structured audit record, no secrets | §Pattern: fail-closed audit; JSON-lines `ConvertTo-Json -Compress`; schema D-03 |
| SAFE-04 | Audit fail-closed — refuse destructive action if record can't be written | §Pattern: write-ahead reservation (PENDING→Flush(true)→throw→mutate→OUTCOME); §Pitfall: ordering |
| SAFE-05 | Startup-loaded deny-list hard-blocks matching targets | §D-05; SID/RID matching; §Pitfall: DN canonicalization |
| SAFE-06 | Protected-account guard (recursive admin groups + gMSA/service) via runtime well-known SIDs, never `adminCount` | §Pattern: runtime protection resolution; `LDAP_MATCHING_RULE_IN_CHAIN` OID; gMSA objectClass; well-known RID/SID set |
| SAFE-07 | Managed-OU scoping refuses DN outside a managed-OU root | §Pattern: DN subtree scope check; §Pitfall: component-boundary-anchored suffix (no substring spoof) |
| SAFE-08 | All writes through one non-exported gate; lint+Pester prove no exported function calls AD write cmdlets | §Pattern: Single Mutation Gate + SAFE-08 guard (AST `Parser.ParseFile`/`FindAll`/`CommandAst`); explicit `FunctionsToExport` |
| SAFE-09 | "Delete" = reversible disable+quarantine; no hard-delete verb | §Pattern: gate verb allow-list (no `Remove-ADObject`); SAFE-08 guard bans `Remove-ADObject`/`Remove-ADGroupMember` from Public/ |
| SAFE-10 | Identical preview/execute target resolution (preview cannot lie) | §Pattern: single `Resolve-AdmanTarget` shared by preview+execute; Pester "preview==execute" invariant |
</phase_requirements>

## Summary

Phase 0 builds the **non-bypassable safety spine** in isolation, before any real AD write exists: one non-exported gate `Invoke-AdmanMutation`, the split config/credential store, fail-closed audit, and the startup capability probe. The design basis is unusually well-settled — the `.planning/research/` corpus (STACK/ARCHITECTURE/PITFALLS/SUMMARY) and the CONTEXT.md decisions (D-01…D-07) independently converge on the same load-bearing rule: **safety is the product, and it is only real if exactly one code path performs every mutation.** This research fills the gaps the corpus flagged (PSFramework exact signatures, the AST-parse approach for the SAFE-08 guard, `LDAP_MATCHING_RULE_IN_CHAIN` corroboration, DPAPI restore-failure behavior, ShouldProcess/ShouldContinue + `-Force` semantics) so the planner can write concrete, verifiable tasks.

Every mechanism in CONTEXT.md D-02…D-07 is corroborated at HIGH confidence by Microsoft/protocol sources: well-known-SID resolution, `1.2.840.113556.1.4.1941` recursive-membership matching, `adminCount` staleness, `Export-Clixml` CurrentUser DPAPI binding and the 0x8009000B restore failure, and the `ShouldProcess`-vs-`ShouldContinue`/`-Confirm:$false`/`-Force` prompting matrix. The one residual MEDIUM area is **exact PSFramework 1.14.457 cmdlet signatures** (verified to exist, but `-Value`/`-Initialize`/`Register-PSFConfigValidation` parameter names must be confirmed at build against the installed module) and the **PSFramework auto-import default-locations caveat**, which is REAL and load-bearing for fail-closed (mitigated by pinning config with `-Path`, never relying on auto-import).

**Primary recommendation:** Implement the gate as a `Private/`-only, non-exported function called by thin `Public/` verbs; prove SAFE-08 with an AST-based Pester test (`[Parser]::ParseFile` → `FindAll({ CommandAst },$true)` → `GetCommandName()`) over `Public/*.ps1` against a fixed deny-list of AD write cmdlets, plus a PSScriptAnalyzer custom rule; make `Initialize-Adman` fail closed on empty managed-OU / failed config / failed deny-list / unwritable audit dir; and treat the audit write as a **write-ahead reservation** (PENDING flushed before the mutation) so SAFE-04 is structurally impossible to violate.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Config load/validate/save (CONF-01/02/03) | **Foundation (module load)** | — | Runs once in `Initialize-Adman`; feeds every later layer; fail-closed lives here. |
| Capability probe (MENU-05) | **Foundation** | Presentation (surfacing guidance) | Probe is logic at startup; the menu only renders the resulting flags + guidance. |
| Credential decision (CONF-04/06) | **Foundation** | Presentation (the `Get-Credential` prompt) | Pass-through/prompt decision + DPAPI file are foundation; only the interactive prompt crosses to presentation. |
| Target resolution (SAFE-10) | **Safety Core** | AD Access (read layer) | One resolver, used by both preview and execute; reads AD via the scoped read layer. |
| Scope/deny/protected policy (SAFE-05/06/07) | **Safety Core** | Foundation (config) + AD Access (SID/group reads) | `Test-AdmanTargetAllowed` is pure policy consuming config + runtime SID/group reads; no writes. |
| Confirmation scaling (SAFE-02) | **Safety Core** | Presentation (`Read-Host`) | `Confirm-AdmanAction` owns the ShouldProcess/typed-token logic; only the keystroke crosses to presentation. |
| The mutation itself (SAFE-08/09) | **Safety Core (the gate)** | AD Access (write wrappers, gate-only) | `Invoke-AdmanMutation` is the sole caller of AD write cmdlets; raw writes confined to `Private/AD/Adman.AD.Write.*`. |
| Fail-closed audit (SAFE-03/04) | **Safety Core** | File system | `Write-AdmanAudit` is the only writer; write-ahead reservation before mutate. |
| Startup fail-closed orchestration | **Foundation** | Safety Core (consumes its flags) | `Initialize-Adman` sets session flags the gate reads; gate enforces them at call time. |

## Standard Stack

### Core
| Library / Module | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| **Windows PowerShell** | **5.1** | Primary runtime (required baseline) | Guaranteed present on admin workstations/servers; AD module + `LocalAccounts` + `CimCmdlets` in-box. Write to the 5.1 language subset. HIGH. |
| **PowerShell** | **7.6.3 LTS** | Supported modern runtime | Current LTS (support to 2028-11-14); `ActiveDirectory` natively compatible on 1809+. Avoid 7.4/7.5 (EOL 2026-11-10). HIGH. |
| **ActiveDirectory module (RSAT)** | ships with Windows/RSAT | AD user/computer/group/OU read+write | The only supported on-prem AD cmdlet surface; **prerequisite, never bundled**; natively PS7-compatible on 1809+. HIGH. |
| **PSFramework** | **1.14.457** (pin) | Validated config + diagnostic logging backbone | Adopted per D-01: `Set-PSFConfig`/`Register-PSFConfigValidation`/`Export-PSFConfig`/`Import-PSFConfig`/`Write-PSFMessage`; PS 3.0+, **no dependencies**, Desktop+Core. **Second mandatory module** on every host. HIGH (existence/version) / MEDIUM (exact signatures — verify at build). |
| **CimCmdlets** | built-in (5.1 + PS7) | No-WinRM transport probe/fallback leg | `New-CimSession` + `New-CimSessionOption -Protocol Dcom`; replaces removed `Get-WmiObject`. HIGH. |
| **PSScriptAnalyzer** | **1.25.0** | Static analysis + the SAFE-08 custom rule | Min PS 5.1; ships `PSUseShouldProcessForStateChangingFunctions` (enforces SAFE-01) and the AST API used by the SAFE-08 guard. HIGH. |
| **Pester** | **6.0.0** | Unit/integration tests + the SAFE-08 gate-coverage proof | Supports WinPS 5.1 + PS 7.4+; mock every AD/CIM cmdlet so unit tests never touch a live domain. HIGH. |

### Supporting
| Capability | Built-in cmdlet/API | When to Use |
|------------|--------------------|-------------|
| Encrypted credential file (CONF-04) | `Export-Clixml`/`Import-Clixml` (DPAPI CurrentUser) on a `[pscredential]` | Opt-in "remember me" only; CurrentUser scope by default (D-06). HIGH. |
| Audit log (SAFE-03/04) | hand-rolled synchronous `Write-AdmanAudit` → JSON-lines (`ConvertTo-Json -Compress`) via `FileStream` + `Flush(true)` | Always; the ONLY audit writer; synchronous so fail-closed is enforceable (D-03, PITFALLS Pitfall 12). HIGH. |
| Console output / guidance | `Write-PSFMessage` (leveled) for diagnostics; hand-rolled `Read-Host`/`$Host.UI.PromptForChoice` for the menu | Diagnostics via PSFramework; the TUI itself is hand-rolled (ConsoleGuiTools is Core-only/archived). HIGH. |
| JSON (de)serialization | `ConvertFrom-Json`/`ConvertTo-Json` (5.1: no `-AsHashtable`; always pass `-Depth` on save) | Config + audit; index JSON as `PSCustomObject` by property on 5.1. HIGH. |
| Concurrency for audit append | `[System.Threading.Mutex]` (`Global\adman-audit`) + `[System.IO.FileStream]` (Append, FileShare.Read) | SAFE-04 durable, ordered, cross-process-safe append. HIGH. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PSFramework config+diagnostics (D-01) | hand-rolled JSON + `Write-Log` | PSFramework gives validated config + runspace-safe messaging for free; but **audit must NOT use it** (async/first-record-loss/exit-drain breaks fail-closed) — keep audit hand-rolled + synchronous. |
| `Get-ADGroupMember -Recursive` client-side | `LDAP_MATCHING_RULE_IN_CHAIN` DC-side | The OID resolves nesting on the DC without materializing member lists client-side; immune to orphaned/foreign SIDs; one query per target. Use the OID (D-02). |
| `ShouldContinue` for bulk typed-count | custom `Read-Host` token check | `ShouldContinue` ignores `-Confirm:$false`/`-WhatIf` and can't carry a typed-token prompt — use ShouldProcess for the single y/n and a custom `Read-Host` exact-count check for bulk, gated by `-Force` (D-07). HIGH (verified). |
| LocalMachine DPAPI scope | CurrentUser DPAPI scope | LocalMachine lets ANY local process/admin unwrap — offer only as a documented opt-in for a dedicated ACL-locked jump host (D-06). |

**Installation (document, do not bundle RSAT):**
```powershell
# Prerequisite (document; SKU-dependent — confirm RSAT-AD-PowerShell vs Add-WindowsCapability at Phase 0/5)
# Windows 10 1809+/11 Pro/Ent/Edu:
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
# Windows Server:
Install-WindowsFeature -Name RSAT-AD-PowerShell

# PSFramework (second mandatory module) — pin version
Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser -TrustRepository
# Dev toolchain
Install-PSResource -Name Pester -Version 6.0.0 -Scope CurrentUser
Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -Scope CurrentUser
```

**Version verification (PowerShell Gallery is the registry — NOT npm/PyPI/crates):**
```powershell
Find-PSResource -Name PSFramework -Version 1.14.457   # confirm version + publish date
Find-Module -Name PSFramework -AllVersions            # legacy PowerShellGet fallback
```
Document the verified version + publish date in the plan. The corpus verified PSFramework **1.14.457** (published 2026-07-02), Pester **6.0.0**, PSScriptAnalyzer **1.25.0** against the Gallery on 2026-07-10.

## Package Legitimacy Audit

> The seam-based `package-legitimacy check` could not run in this environment (no `node` runtime for `gsd-tools.cjs`), and these are **PowerShell Gallery** modules — the correct ecosystem registry is the **PowerShell Gallery**, not npm/PyPI/crates (cross-ecosystem confusion is a documented hallucination vector). Verdicts below are from the Gallery evidence already gathered in the research corpus (versions + publish dates + maintenance), classified per the source hierarchy. **The planner MUST add a build-time re-verification task** running `Find-PSResource`/`Find-Module` for each before pinning in the manifest/CI.

| Package | Registry | Age | Maintenance | Source Repo | Verdict | Disposition |
|---------|----------|-----|-------------|-------------|---------|-------------|
| PSFramework 1.14.457 | PowerShell Gallery | mature (changelog through 2026; pub. 2026-07-02) | active (PowershellFrameworkCollective) | github.com/PowershellFrameworkCollective/psframework | [OK] | Approved — **pin** in manifest; re-verify signatures at build |
| Pester 6.0.0 | PowerShell Gallery | mature | active (pester/Pester) | github.com/pester/Pester | [OK] | Approved — dev dependency |
| PSScriptAnalyzer 1.25.0 | PowerShell Gallery | mature | active (PowerShell org) | github.com/PowerShell/PSScriptAnalyzer | [OK] | Approved — dev dependency + SAFE-08 rule host |
| ActiveDirectory (RSAT) | in-box / Windows feature | OS-bound | Microsoft | n/a (OS component) | [OK] | Prerequisite, never bundled; probe at startup |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.
*No packages were discovered via training data alone — every Phase-0 module is corroborated against the PowerShell Gallery / official GitHub / Microsoft Learn. The planner must still gate the first install of PSFramework behind a `checkpoint:human-verify` because the automated legitimacy seam did not run in this environment.*

## Architecture Patterns

### System Architecture Diagram

```
Start-Adman (menu, Phase 1)  ──calls──►  Initialize-Adman (Phase 0, this phase)
                                              │
        ┌─────────────────────────────────────┴─────────────────────────────────────┐
        ▼                                                                             ▼
  FOUNDATION (load once)                                                       SESSION FLAGS
  1. Initialize-AdmanConfig  ──► Import-PSFConfig -Path .store/config.json     • ConfigLoaded (bool)
     • validate schema         ──► FAIL-CLOSED if managed-OU empty /            • ManagedOUs[] (DN roots)
     • pin with -Path (no auto-import)        deny-list/config failed to load   • DenyList[] (SID tokens)
     • seed deny-list (D-05)                                                   • ProtectedSIDs (resolved)
  2. Write-AdmanAudit probe  ──► verify .store/audit writable → FAIL-CLOSED     • AuditWritable (bool)
  3. Get-AdmanCredential     ──► pass-through | prompt | Import-Clixml(opt-in)  • PSCredential (in-mem)
  4. Test-AdmanCapability    ──► RSAT? domain/ADWS? rights? transport?          • Capability flags (MENU-05)
                                              │
                                              ▼
   PUBLIC VERB (thin) ──builds {Verb, Targets, Params, CorrelationId}──►
                                              │
                                              ▼
   ╔══════════════════════════════ Invoke-AdmanMutation (THE GATE, Private/, NOT exported) ══════════════════════════════╗
   ║  1. Resolve-AdmanTarget       → AD read layer (scoped)        ┐                                                     ║
   ║  2. Test-AdmanTargetAllowed   → scope(SAFE-07)+deny(05)+prot(06) │  ← run IDENTICALLY for -WhatIf and execute       ║
   ║  3. Assert-AdmanBulkPolicy    → cap + typed-confirm threshold   │     (SAFE-10: preview cannot lie)                 ║
   ║  4. Write-AdmanAudit PENDING  → Flush(true); THROW on failure (SAFE-04 write-ahead reservation)                     ║
   ║  5. Confirm-AdmanAction       → ShouldProcess (-WhatIf/-Confirm) + typed-count (SAFE-02); -Force bypass             ║
   ║  6. Adman.AD.Write.<Verb>     → the ONE real AD write (allow-listed verbs; NO Remove-ADObject → SAFE-09)            ║
   ║  7. Write-AdmanAudit OUTCOME  → Success/Failure/Refused (best-effort)                                              ║
   ╚═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
                                              │
                                              ▼
   Canonical result object (Action/Targets/Denied/Succeeded/Failed/WhatIf/CorrelationId) → Output (Phase 1)
```

### Recommended Project Structure (this phase)

```
adman/
├── adman.psd1                 # RootModule='adman.psm1'; PowerShellVersion='5.1';
│                              # CompatiblePSEditions=@('Desktop') until CI passes on 7.6;
│                              # RequiredModules=@('PSFramework')   (ActiveDirectory is a PREREQ, not a dependency);
│                              # FunctionsToExport = explicit list (NEVER '*')
├── adman.psm1                 # dot-source Private/* then Public/*; Export-ModuleMember -Function $public; runs Initialize-Adman
├── Public/                    # Phase 0 ships only Start-Adman stub + config verbs; write verbs arrive Phase 2
│   ├── Initialize-Adman.ps1   # exported; entry used by Start-Adman (Phase 1)
│   ├── Test-AdmanCapability.ps1
│   └── Config/ Get|Set|Export|Import-AdmanConfig.ps1
├── Private/
│   ├── Safety/
│   │   ├── Invoke-AdmanMutation.ps1      # THE GATE (only caller of AD write cmdlets)
│   │   ├── Resolve-AdmanTarget.ps1       # single resolver for preview+execute (SAFE-10)
│   │   ├── Test-AdmanTargetAllowed.ps1   # scope+deny+protected policy (SAFE-05/06/07)
│   │   ├── Confirm-AdmanAction.ps1       # ShouldProcess + typed-count + -Force (SAFE-02)
│   │   ├── Assert-AdmanBulkPolicy.ps1    # cap placeholder (enforcement Phase 4/BULK-02)
│   │   ├── Get-AdmanProtectedIdentity.ps1# resolve well-known SIDs at startup (D-02)
│   │   └── AdmanWriteVerbs.ps1           # allow-list of gate-callable verbs (SAFE-09: no Remove-*)
│   ├── Audit/
│   │   └── Write-AdmanAudit.ps1          # synchronous write-ahead JSONL (SAFE-03/04)
│   ├── Config/
│   │   └── Initialize-AdmanConfig.ps1    # defaults + schema + load/validate + deny-list seed
│   ├── Foundation/
│   │   ├── Get-AdmanCredential.ps1       # pass-through vs prompt vs Import-Clixml (CONF-04/06)
│   │   └── Resolve-AdmanDomainSid.ps1    # (Get-ADDomain).DomainSID + forest-root SID helper
│   └── AD/
│       └── Adman.AD.Write.ps1            # raw Set-/Disable-/Move- wrappers (gate-only)
├── config/
│   ├── adman.defaults.json               # shipped defaults (schema source-of-truth)
│   └── adman.schema.json                 # shared by wizard emitter + loader (D-04)
├── tests/
│   ├── Safety.Gate.Tests.ps1             # AST guard (SAFE-08) + WhatIf/deny/scope/protected/cap
│   └── *.Integration.Tests.ps1           # lab-only, against a disposable test OU
├── PSScriptAnalyzerSettings.psd1         # enables PSUseShouldProcessForStateChangingFunctions etc.
└── rules/ AdmanSafetyRules.psm1          # custom PSSA rule: banned AD-write cmdlets in Public/
```

### Pattern 1: The Single Mutation Gate (SAFE-08)

**What:** `Public/` verbs are thin (validate input → build a request → call the gate). `Invoke-AdmanMutation` is the only function allowed to call AD write cmdlets; it lives in `Private/`, is **not exported**, and `FunctionsToExport` is explicit. The fixed pipeline is resolve → allow → bulk-policy → audit-PENDING → ShouldProcess → execute → audit-OUTCOME.

**When to use:** Always. This is the load-bearing pattern for the whole project.

```powershell
# Public verb — thin. No Set-AD* here. (Phase 0 ships the gate; verbs like this land in Phase 2.)
function Disable-AdmanUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string[]]$Identity)
    Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $Identity
}
```

```powershell
# Private — the only place allowed to write.
function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateSet('Disable-ADAccount','Enable-ADAccount','Move-ADObject',
            'Set-ADUser','Set-ADComputer','Set-ADAccountPassword','Unlock-ADAccount',
            'Add-ADGroupMember','Remove-ADGroupMember')]   # SAFE-09: Remove-ADObject deliberately ABSENT
        [string]$Verb,
        [Parameter(Mandatory)][string[]]$Targets,
        [hashtable]$Parameters = @{}
    )
    $cid = [guid]::NewGuid().ToString()
    $resolved = Resolve-AdmanTarget -Targets $Targets                       # SAFE-10: ONE resolver
    foreach ($t in $resolved) {
        $decision = Test-AdmanTargetAllowed -Object $t                       # SAFE-05/06/07
        if (-not $decision.Allowed) {
            Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' -Reason $decision.Reason
            continue
        }
    }
    Assert-AdmanBulkPolicy -Count $resolved.Count                            # cap (Phase 4) + threshold
    Confirm-AdmanAction -Verb $Verb -Targets $resolved -CorrelationId $cid   # SAFE-02 (+ShouldProcess)
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $resolved -Result 'PENDING' -WhatIf:$WhatIfPreference
    # ^ Write-AdmanAudit THROWS on PENDING-write failure → SAFE-04 refusal happens BEFORE the write below
    & "Adman.AD.Write.$Verb" -Objects $resolved @Parameters -WhatIf:$WhatIfPreference -Confirm:$false
    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $resolved -Result 'Success' -WhatIf:$WhatIfPreference
}
```

**SAFE-08 enforcement — the AST guard (cite the parse approach):** parse every `Public/**/*.ps1` with the PowerShell language AST and assert no `CommandAst` resolves to a banned AD write cmdlet. This is the same technique PSScriptAnalyzer's own rules use.

```powershell
# tests/Safety.Gate.Tests.ps1  (Pester 6) — proves no exported writer bypasses the gate
Describe 'SAFE-08: no exported function calls AD write cmdlets directly' {
    $banned = @(
        'Set-ADUser','Set-ADComputer','Set-ADObject','Set-ADAccountPassword',
        'Disable-ADAccount','Enable-ADAccount','Unlock-ADAccount',
        'Move-ADObject','New-ADUser','New-ADComputer',
        'Add-ADGroupMember','Remove-ADGroupMember','Add-ADPrincipalGroupMembership',
        'Remove-ADObject'   # SAFE-09: hard-delete verb must appear NOWHERE in Public/
    )
    $publicFiles = Get-ChildItem -Path "$PSScriptRoot/../Public" -Filter *.ps1 -Recurse
    It 'Public/<file> contains no direct AD write call' -ForEach ($publicFiles | ForEach-Object {@{File=$_}}) {
        param($File)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] },
            $true)                                  # $true = recurse into nested scriptblocks
        $names = $calls | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        $hits  = $names | Where-Object { $_ -in $banned }
        $hits | Should -BeNullOrEmpty -Because "$($File.Name) must route writes through Invoke-AdmanMutation"
    }
}
```

Source: PSScriptAnalyzer rule-writing convention (github.com/PowerShell/PSScriptAnalyzer) + Microsoft `System.Management.Automation.Language.Parser` / `CommandAst` API. [CITED: github.com/PowerShell/PSScriptAnalyzer] Confidence HIGH. **Caveat (verified):** `CommandAst.GetCommandName()` returns `$null` for dynamic invocations (`& $cmd`); fall back to `$cmd.CommandElements[0].Extent.Text`, and also grep `$tokens` for `&`/`<Invoke-Expression>` to catch string-built calls. Resolve aliases via `Get-Command` so an aliased `sadu`-style call can't slip through.

### Pattern 2: Identical Preview/Execute Resolution (SAFE-10)

**What:** one `Resolve-AdmanTarget` function materializes the target set; BOTH the `-WhatIf` preview and the execute loop consume that exact same array. No re-query between preview and execute. `Test-AdmanTargetAllowed` also runs in both modes so a refused target is refused in the preview too.

```powershell
function Resolve-AdmanTarget {
    param([Parameter(Mandatory)][string[]]$Targets)
    foreach ($id in $Targets) {
        # scoped read: -SearchBase always set, exact -Properties, -Server pinned (Pitfall 1/6)
        Get-ADObject -Identity $id -Server $script:Config.DC `
            -Properties objectSid,objectClass,DistinguishedName,memberOf -ErrorAction Stop
    }
}
# Pester invariant: the array passed to the preview formatter is reference-equal to the array the loop acts on.
```

**Pester proof:** a test that runs the gate with `-WhatIf` against a lab test OU and asserts (a) AD is unchanged AND (b) the audit record's `target` list equals the resolved list AND (c) the count shown to the operator equals `$resolved.Count`.

### Pattern 3: Runtime Protected-Account Resolution (SAFE-06, never adminCount)

**What:** resolve the protected set at startup from well-known SIDs; at check time run ONE DC-side `LDAP_MATCHING_RULE_IN_CHAIN` query per target; pre-filter gMSA by `objectClass`.

```powershell
# Startup: build protected-group DN list from well-known SIDs (names lie, SIDs don't)
$dom   = Get-ADDomain -Server $script:Config.DC
$domSid= $dom.DomainSID.Value
# Forest-root SID for 518/519 (Schema/Enterprise Admins live in the forest ROOT domain)
$rootSid = (Get-ADDomain -Identity ((Get-ADForest).RootDomain) -Server $script:Config.DC).DomainSID.Value
$protectedRids = @{
    'Domain Admins'      = "$domSid-512";   'Schema Admins'      = "$rootSid-518"
    'Enterprise Admins'  = "$rootSid-519";  'Administrators'     = 'S-1-5-32-544'
    'Account Operators'  = 'S-1-5-32-548';  'Backup Operators'   = 'S-1-5-32-551'
    'Server Operators'   = 'S-1-5-32-549';  'Protected Users'    = "$domSid-525"  # defense-in-depth
}
$protectedGroupDns = foreach ($sid in $protectedRids.Values) {
    (Get-ADGroup -Identity $sid -Server $script:Config.DC -ErrorAction SilentlyContinue).DistinguishedName
}
if ($script:Config.AdmanProtectedGroup) { $protectedGroupDns += $script:Config.AdmanProtectedGroup }  # adman-Protected
$script:ProtectedGroupDns = $protectedGroupDns | Where-Object { $_ } | Select-Object -Unique
```

```powershell
# Check-time: ONE DC-side filter — is THIS target recursively in any protected group?
function Test-AdmanProtectedAccount {
    param([Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADObject]$Object)
    # (a) gMSA / legacy sMSA pre-filter — precise refusal reason, run FIRST (D-02)
    if ($Object.objectClass -contains 'msDS-GroupManagedServiceAccount' -or
        $Object.objectClass -contains 'msDS-ManagedServiceAccount') {
        return @{ Protected = $true; Reason = 'gMSA/service account (objectClass)' }
    }
    # (b) flat deny-list by SID/RID — the hard floor (D-05); match objectSid, never sAMAccountName
    $rid = ([System.Security.Principal.SecurityIdentifier]$Object.objectSid).Value.Split('-')[-1]
    if ($rid -in $script:DenyRids) { return @{ Protected = $true; Reason = "deny-listed RID $rid" } }
    # (c) recursive protected-group membership — single IN_CHAIN query over all protected groups
    $or = ($script:ProtectedGroupDns | ForEach-Object {
        "(memberOf:1.2.840.113556.1.4.1941:=$_)" }) -join ''
    $hit = Get-ADObject -Identity $Object.DistinguishedName -Server $script:Config.DC `
        -LDAPFilter "(|$or)" -ErrorAction Stop
    if ($hit) { return @{ Protected = $true; Reason = 'recursive member of protected group' } }
    return @{ Protected = $false }
}
```

Source: OID `1.2.840.113556.1.4.1941` (`LDAP_MATCHING_RULE_IN_CHAIN`) — AD/AD LDS extensible match, DN-attributes only, available WS2003 SP2/WS2008+; `memberOf:...:=<groupDN>` finds members of a group recursively. [CITED: support.atlassian.com/crowd; ldapwiki.com; Microsoft LDAP matching-rule docs] HIGH. **Direction matters:** to test "is target T in any protected group," bind the search to T and filter on `memberOf:1.2.840.113556.1.4.1941:=<groupDN>` ORed across groups — do NOT enumerate group members client-side.

### Pattern 4: Fail-Closed Audit — Write-Ahead Reservation (SAFE-03/04)

**What & why ordering:** the audit record must be **durably on disk and verified BEFORE the mutation is sent to AD.** This is the only ordering that is actually fail-closed: a write-after pattern would, on any audit failure, have already mutated AD unaudited (and AD object-state rollback is unreliable — D-03 explicitly forbids faking one). Recommendation: **audit-before-mutate (PENDING reservation), OUTCOME best-effort after.**

```powershell
function Write-AdmanAudit {
    param([string]$CorrelationId,[string]$Verb,$Targets,[string]$Result,[string]$Reason,[switch]$WhatIf)
    $mutex = [System.Threading.Mutex]::new($false, 'Global\adman-audit')
    [void]$mutex.WaitOne()
    try {
        $path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
        if (-not (Test-Path $script:Config.AuditDir)) {
            New-Item -ItemType Directory -Path $script:Config.AuditDir -Force -ErrorAction Stop | Out-Null
        }
        $rec = [ordered]@{
            tsUtc=(Get-Date).ToUniversalTime().ToString('o'); who="$env:USERDOMAIN\$env:USERNAME"
            userSid=([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            what=$Verb; scope=($script:Config.ManagedOUs -join '|')
            target=(($Targets | ForEach-Object { $_.DistinguishedName }) -join '|')
            count=@($Targets).Count; whatIf=[bool]$WhatIf; result=$Result; reason=$Reason
            correlationId=$CorrelationId; host=$env:COMPUTERNAME; psEdition=$PSEdition
            moduleVersion=(Get-Module adman).Version.ToString()
        } | ConvertTo-Json -Compress -Depth 5
        # Append, allow readers, DURABLY flush to disk
        $fs = [System.IO.File]::Open($path,
            [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($rec + "`n")
            $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true)   # $true = flush to disk (not just OS cache)
        } finally { $fs.Dispose() }
    } catch {
        if ($Result -eq 'PENDING') {
            # SAFE-04: pre-write reservation failed → REFUSE the destructive action
            throw "AUDIT FAIL-CLOSED: cannot write audit record ($($_.Exception.Message)); refusing $Verb."
        }
        # OUTCOME failure after a successful mutation → escalate, do NOT roll back AD (D-03)
        Write-EventLog -LogName Application -Source adman -EventId 9001 -EntryType Error `
            -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
        Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId — see Event Log."
        $script:AuditDegraded = $true
    } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
```

**Note:** `Write-EventLog -Source` requires the source to be registered (one-time admin `New-EventLog`). For Phase 0, register the source in `Initialize-Adman` (best-effort) and degrade to a console warning if registration is unavailable — flag this as environment-specific (admin rights to create the event source).

### Pattern 5: DPAPI Credential File + Re-Prompt-on-Restore (CONF-04/06)

**Scope trade-off for a small admin team on shared jump hosts:**
- **CurrentUser (default):** ciphertext decryptable only by the same Windows user on the same machine. On a shared jump host each admin keeps their own file under their own profile — correct least-privilege, but a stolen-profile or SID/profile rebuild invalidates it (handled by re-prompt). Recommended default.
- **LocalMachine (documented opt-in only):** any local process / any local admin can unwrap — weaker, only acceptable on a dedicated, ACL-locked jump host where several admins share one service profile. Never on a general workstation.

```powershell
function Get-AdmanCredential {
    if (-not $script:Config.credentialPolicy.allowRememberMe) { return $null }   # pass-through
    $file = Join-Path $script:StorePath 'adman.credential.xml'
    if (Test-Path $file) {
        try {
            $cred = Import-Clixml -Path $file -ErrorAction Stop
            [void]$cred.GetNetworkCredential().Password   # guard: bad restore → null/empty throws
            return $cred
        } catch {
            # CryptographicException 0x8009000B ("Key not valid for use in specified state") OR empty-password
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue      # delete bad file (D-06)
            Write-PSFMessage -Level Warning -Message "Stored credential unreadable; re-prompting."
        }
    }
    if ($script:RightsInsufficient) {            # only prompt when pass-through rights insufficient (CONF-06)
        $cred = Get-Credential -Message 'Domain credentials required for this task'
        if ($script:Config.credentialPolicy.allowRememberMe -and (Read-AdmanRememberMeConsent)) {
            $cred | Export-Clixml -Path $file -Force                            # DPAPI CurrentUser
        }
        return $cred
    }
    return $null
}
```

Source: `Export-Clixml`/`Import-Clixml` protect `SecureString`/`PSCredential` via DPAPI CurrentUser; same-user + same-machine binding; wrong user/machine/lost profile keys → `CryptographicException` "Key not valid for use in specified state" (0x8009000B); identical behavior on PS 5.1 and 7 on Windows. [CITED: github.com/MicrosoftDocs/PowerShell-Docs Import-Clixml; powershellisfun.com; forums.powershell.org] HIGH.

### Pattern 6: Scaled Confirmation Without Double-Prompting (SAFE-02)

**What:** resolve → gate once → prompt once. Single-object uses `$PSCmdlet.ShouldProcess` (so `-WhatIf` + `-Confirm:$false` behave correctly, default-No). Bulk uses a custom `Read-Host` exact-count check (NOT `ShouldContinue`, which ignores `-Confirm:$false` and can't carry a typed-token). `-Force` short-circuits the prompt for automation but **never** skips scope/deny/protected/cap. Inner destructive cmdlets run with `-Confirm:$false` so there is no per-object re-prompt.

```powershell
function Confirm-AdmanAction {
    param([string]$Verb,$Targets,[string]$CorrelationId)
    $count = @($Targets).Count
    $threshold = [int]$script:Config.safety.bulkConfirmThreshold   # default 5 (D-07)
    # -Force / -Confirm:$false bypass ONLY the prompt — scope/deny/protected/cap already ran above (non-bypassable)
    if (-not $Force -and -not ($ConfirmPreference -eq 'None')) {
        if ($count -ge $threshold) {
            $token = Read-Host "Type the exact count ($count) to $Verb these $count objects"
            if ($token -ceq "$count") { throw "Confirmation failed: expected $count, got '$token'. Refused." }
        } elseif (-not $PSCmdlet.ShouldProcess("$count object(s)", $Verb)) {   # default-No, honors -WhatIf
            Write-AdmanAudit -CorrelationId $CorrelationId -Verb $Verb -Targets $Targets -Result 'Cancelled'
            throw "Operator declined."
        }
    }
}
```

Source: `ShouldProcess` honors `-WhatIf`/`-Confirm`/`ConfirmImpact` and is bypassed by `-Confirm:$false`; `ShouldContinue` prompts every time and ignores `-Confirm:$false`/`-WhatIf` — reserve it for a mandatory second prompt and always pair with `-Force` short-circuit (`if ($Force -or $PSCmdlet.ShouldContinue(...))`). [CITED: powershellexplained.com ShouldProcess deep-dive; thesysadminchannel.com ShouldContinue-vs-ShouldProcess; PowerShell issue #13229 (`-Confirm:$false` ignores ConfirmImpact)] HIGH. **Pitfall:** the automatic `$Confirm` variable is not "set" under `Set-StrictMode -Version Latest` (PowerShell issue #14294) — test the threshold via `$ConfirmPreference`, not by reading `$Confirm`.

### Pattern 7: Startup Capability Probe (MENU-05)

**What to check + how to surface actionable guidance.** Probe cheaply at startup; store flags the menu reads; never let a probe hang (short timeouts).

| Probe | How | Actionable guidance if missing |
|-------|-----|-------------------------------|
| RSAT present | `Get-Module -ListAvailable ActiveDirectory` | "Install RSAT: `Add-WindowsCapability …Rsat.ActiveDirectory…` (client) or `Install-WindowsFeature RSAT-AD-PowerShell` (server). Tool cannot run AD tasks until present." |
| Domain reachable / ADWS | `Get-ADDomain -Server <dc>` with `-ErrorAction Stop` + short timeout; note AD module talks to ADWS on a DC (TCP 9389) | "Cannot reach a domain controller / AD Web Services. Check VPN/network and that a DC runs ADWS." |
| Current rights (non-destructive) | read the managed OU (`Get-ADOrganizationalUnit`) + check `whoami /groups` for the delegated admin group; **do not** perform a real write to test rights | "Logged in as X; rights appear insufficient for `<managed OU>`. Re-run as a delegated admin or provide credentials (CONF-06)." |
| Transport availability | `Test-WSMan -ComputerName <self or sample>` + optional `New-CimSession -Protocol Dcom` probe | "WinRM unavailable; will use CIM/DCOM where possible; remote ops may be Skipped per host (Phase 3)." |
| Audit dir writable | open `audit-<date>.jsonl` Append + `Flush(true)` | FAIL-CLOSED: "Audit path `<x>` not writable — refusing to start mutating operations." |
| Recovery posture (RPT-07 carried) | `Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin*"'` + `(Get-ADForest).ForestMode` | Warn if Recycle Bin not enabled — out-of-tool hard deletes are tombstone-only. |

```powershell
function Test-AdmanCapability {
    $flags = [ordered]@{}
    $flags.RsatPresent = [bool](Get-Module -ListAvailable ActiveDirectory)
    $flags.DomainReachable = $false
    if ($flags.RsatPresent) {
        try { $null = Get-ADDomain -ErrorAction Stop; $flags.DomainReachable = $true } catch { }
    }
    $flags.AuditWritable = Test-AdmanAuditWritable
    $flags.RecycleBinEnabled = [bool](Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"' |
        Where-Object { $_.EnabledScopes.Count -gt 0 })
    $script:Capability = [pscustomobject]$flags
    foreach ($k in $flags.Keys) {
        if (-not $flags[$k]) { Write-PSFMessage -Level Warning -Message (Get-AdmanCapabilityGuidance $k) }
    }
    # FAIL-CLOSED: refuse mutating operations if scope empty or audit unwritable
    if (-not $script:Config.ManagedOUs) { throw 'FAIL-CLOSED: managed-OU is empty.' }
    if (-not $flags.AuditWritable)     { throw 'FAIL-CLOSED: audit path not writable.' }
}
```

### Anti-Patterns to Avoid

- **Calling `Set-AD*` directly from a `Public/` verb** — bypasses the gate; killed by the AST guard (Pattern 1) + explicit `FunctionsToExport`.
- **Relying on PSFramework auto-import default locations for config** — `Register-PSFConfig` writes a per-user default that auto-loads at module import and can seed/override config (fail-open). Pin with `Import-PSFConfig -Path`/`Export-PSFConfig -Path`; never depend on the magic locations (D-01). [CITED: psframework.org persistence-basics]
- **Using `ShouldContinue` for the bulk typed-count** — it ignores `-Confirm:$false` and can't carry a typed-token; use ShouldProcess (single) + custom `Read-Host` (bulk) + `-Force` (D-07). [CITED: powershellexplained.com]
- **Trusting `adminCount=1`** — stamped while protected, never cleared on removal (false positives forever), and a new admin isn't stamped until the next SDProp cycle (≤60 min, false negatives). Use live IN_CHAIN membership (D-02). [CITED: TechCommunity AskDS AdminSDHolder]
- **Matching deny-list/protection by `sAMAccountName`** — RID-500 is routinely renamed via GPO; match by `objectSid`/RID (D-05). [CITED: PITFALLS Pitfall 2]
- **Write-after "refuse on audit failure"** — would mutate AD unaudited; use write-ahead reservation (Pattern 4). [CITED: PITFALLS Pitfall 12]
- **Substring managed-OU match** (`$dn -like "*$root*"`) — spoofable across DN component boundaries; anchor at component boundaries (§Pitfall: DN subtree).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config validation + persistence | a custom schema validator + file watcher | PSFramework `Set-PSFConfig`/`Register-PSFConfigValidation`/`Export-PSFConfig` -Path | PS 3.0+, no deps, runspace-safe; but pin with `-Path` (no auto-import). |
| Recursive protected-group test | client-side `Get-ADGroupMember -Recursive` over N groups | one `LDAP_MATCHING_RULE_IN_CHAIN` filter on the target | DC-side, no member-list materialization, immune to orphaned SIDs. |
| Credential encryption | a custom AES/key store | `Export-Clixml`/`Import-Clixml` (DPAPI CurrentUser) | Built-in, 5.1+7 on Windows, no vault; machine+user bound by design. |
| Durable ordered audit append | `Add-Content` + hope | `Mutex` + `FileStream`(Append, FileShare.Read) + `Flush(true)` | Cross-process ordering + durability for fail-closed. |
| AST lint for SAFE-08 | regex over source | `[Parser]::ParseFile` → `FindAll({ CommandAst },$true)` → `GetCommandName()` | Regex misses comments/strings/aliases; the AST is what PSScriptAnalyzer uses. |
| Confirmation primitive | bespoke y/n + bulk prompt | `ShouldProcess` (single) + `Read-Host` typed-count (bulk) + `-Force` | Engine-level `-WhatIf`/`-Confirm`/ConfirmImpact handling; `-Confirm:$false`/`-Force` automation idiom is standard. |

**Key insight:** The tempting custom pieces (audit logger, config validator, recursive-group walker, credential store) are exactly where fail-closed, DPAPI-binding, and SID-correctness bugs hide. The only thing worth hand-rolling is the synchronous audit writer — and that is deliberate, because PSFramework's async logging would break fail-closed.

## Common Pitfalls

### Pitfall 1: `-WhatIf` with the ActiveDirectory provider / composite actions
**What goes wrong:** Most `*-AD*` write cmdlets honor `-WhatIf`, but composite operations (e.g., offboarding = disable + strip-groups + move) and any helper that doesn't forward `-WhatIf` silently drop it — dry-run "works" for disable but not for the move. Also `$WhatIfPreference` set globally in a profile can no-op the tool's own internal reads/writes unexpectedly.
**Why it happens:** `-WhatIf` is a switch trivially dropped across a function boundary; `SupportsShouldProcess` is opt-in boilerplate.
**How to avoid:** every destructive function declares `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` and forwards `-WhatIf:$WhatIfPreference`/` -Confirm:$false` explicitly to the inner AD cmdlet; never set `$WhatIfPreference` globally; the gate runs `Test-AdmanTargetAllowed` in BOTH modes so the preview is truthful (Pattern 2).
**Warning signs:** a `-WhatIf` run and a real run show different target counts; a helper with no `SupportsShouldProcess`; `-Confirm` never prompts (ConfirmImpact too low).

### Pitfall 2: ShouldProcess behavior differs under StrictMode and across 5.1 vs 7
**What goes wrong:** reading the automatic `$Confirm` variable under `Set-StrictMode -Version Latest` throws (PowerShell issue #14294) on both editions; assuming `-Confirm:$false` respects `ConfirmImpact` (it doesn't — it bypasses the prompt entirely, issue #13229).
**Why it happens:** `$Confirm` is conditionally created by `SupportsShouldProcess`; StrictMode treats the unset read as an error.
**How to avoid:** test suppression via `$ConfirmPreference -eq 'None'` and an explicit `-Force` switch; never read `$Confirm`; keep `ConfirmImpact='High'` so the default `$ConfirmPreference='High'` prompts when neither `-Force` nor `-Confirm:$false` is set.
**Warning signs:** StrictMode tests failing on `$Confirm`; automation still prompting (forgot `-Confirm:$false`) or skipping prompts that should fire (ConfirmImpact below preference).

### Pitfall 3: gMSA / legacy sMSA resolution edge cases
**What goes wrong:** checking only `msDS-GroupManagedServiceAccount` misses the legacy standalone `msDS-ManagedServiceAccount` (WS2008R2); relying on the gMSA's `memberOf` misses ones that are NOT nested in a protected group (they're still service accounts and must be refused); a gMSA can ALSO be nested in a protected group, so skipping IN_CHAIN after the objectClass hit loses the precise reason layering.
**Why it happens:** two objectClasses; gMSAs don't always sit in protected groups.
**How to avoid:** pre-filter `objectClass -in 'msDS-GroupManagedServiceAccount','msDS-ManagedServiceAccount'` FIRST (precise refusal), THEN still run IN_CHAIN (D-02). Service accounts without a reliable SID are protected only via explicit `adman-Protected` membership; `svc_` naming is warning-only.
**Warning signs:** a gMSA that slips the protected check because it isn't in any admin group; refusing only the current objectClass.

### Pitfall 4: Deny-list DN canonicalization & RID-500 rename
**What goes wrong:** matching the deny-list by `sAMAccountName` or a literal DN string — RID-500 (built-in Administrator) is routinely renamed, and DNs differ in escaping/case; a target slips through because the string doesn't byte-match.
**Why it happens:** names and stringified DNs are unstable; SIDs are not.
**How to avoid:** store deny-list entries as SID/RID tokens (D-05); resolve the target to `objectSid` and compare SIDs (or RIDs against `(Get-ADDomain).DomainSID`). If a deny-list entry must be a DN, canonicalize by re-reading from AD and comparing `objectSid`, else compare lowercased/trimmed DNs with component-boundary awareness.
**Warning signs:** a renamed built-in Administrator not blocked; deny-list "works" in en-US but not under a localized group name.

### Pitfall 5: Managed-OU scope check via DN substring (SAFE-07 spoof)
**What goes wrong:** `$targetDN -like "*$managedRoot*"` is a substring match that a crafted DN can spoof — e.g. root `OU=Managed,DC=contoso,DC=com` incorrectly matches `OU=NotManaged,OU=Managed,DC=contoso,DC=com` or fails to anchor at a component boundary.
**Why it happens:** DNs are ordered, comma-joined RDNs; only a suffix at a component boundary is a real subtree test.
**How to avoid:** normalize both DNs (lowercase, trim, unescape), then accept only if `$t -eq $root` OR `$t.EndsWith(",$root")` (component-boundary anchored); reject the root DN itself if root mutation is out of policy. Prefer resolving the target and reading its canonical `DistinguishedName` from AD rather than trusting caller input.
**Warning signs:** an object in a sibling/same-prefix OU treated as in-scope; tests with a deliberately out-of-scope but prefix-sharing DN passing.

### Pitfall 6: Credential-file ACLs & LocalMachine unwrap
**What goes wrong:** treating the DPAPI file as "encrypted ⇒ safe regardless of ACL/scope." CurrentUser DPAPI is unwrap by any process running as that user (and any local admin who can become that user); LocalMachine scope is unwrap by ANY local process. A loose `.store/` ACL or a shared profile leaks the credential.
**Why it happens:** DPAPI binds to keys derived from the user/machine context — it is not an access-control boundary by itself.
**How to avoid:** ACL `.store/` to the admin user + SYSTEM only (defense-in-depth; DPAPI remains the real control); default to CurrentUser; document LocalMachine as opt-in only for a dedicated ACL-locked jump host (D-06); never log the credential (audit schema has no secret fields — SAFE-03/CONF-05).
**Warning signs:** `.store/` readable by `Users`/`Authenticated Users`; a LocalMachine-scope file on a general workstation.

### Pitfall 7: PSFramework auto-import overriding the portable config (fail-open)
**What goes wrong:** using `Register-PSFConfig` (writes the per-user default location that auto-loads at every module import) for the managed-OU/deny-list — a stale or per-user setting can seed/override the portable `.store/config.json`, silently weakening scope.
**Why it happens:** PSFramework's persistence has magic default locations that auto-import at module load (confirmed: "loaded automatically each time the PSFramework module is imported").
**How to avoid:** pin config to the explicit file with `Import-PSFConfig -Path .store/config.json`/`Export-PSFConfig -Path`; never call `Register-PSFConfig` for safety-critical values; implement fail-closed in `Initialize-Adman` regardless of framework (D-01).
**Warning signs:** config differing between a fresh machine and one where the tool ran before; `Get-PSFConfig` showing values not present in `.store/config.json`.

### Pitfall 8: `ConvertTo-Json` truncation + 5.1 `-AsHashtable` absence
**What goes wrong:** `ConvertTo-Json` defaults `-Depth 2` and silently truncates nested config/audit; on 5.1 `ConvertFrom-Json -AsHashtable` doesn't exist, so a 7-only save/load breaks on 5.1.
**How to avoid:** always pass `-Depth` (≥5) on every save; on 5.1 read config as `PSCustomObject` and index by property (D-01).
**Warning signs:** nested keys vanishing on round-trip; `-AsHashtable` appearing in shared code.

## Code Examples

Verified patterns from official/authoritative sources:

### Recursive protected-membership check (one DC-side filter)
```powershell
# Source: LDAP_MATCHING_RULE_IN_CHAIN OID docs (support.atlassian.com/crowd; ldapwiki.com; Microsoft LDAP matching rules)
# Is $userDn recursively in any of the protected groups?
$or = ($protectedGroupDns | ForEach-Object { "(memberOf:1.2.840.113556.1.4.1941:=$_)" }) -join ''
$hit = Get-ADObject -Identity $userDn -Server $DC -LDAPFilter "(|$or)"
```

### AST scan for banned AD write cmdlets (SAFE-08)
```powershell
# Source: PSScriptAnalyzer rule-writing convention + System.Management.Automation.Language API
$ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
    ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -in $banned }
```

### Durable JSON-lines append (fail-closed pre-write)
```powershell
# Source: PITFALLS Pitfall 12 + .NET FileStream Flush(bool) docs
$fs = [System.IO.File]::Open($path, 'Append', 'Write', 'Read')
try { $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
```

### DPAPI credential restore with re-prompt
```powershell
# Source: Microsoft Import-Clixml docs + DPAPI behavior (powershellisfun.com; forums.powershell.org)
try { $cred = Import-Clixml $file -ErrorAction Stop; [void]$cred.GetNetworkCredential().Password }
catch { Remove-Item $file -Force -EA SilentlyContinue; $cred = Get-Credential }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Get-WmiObject` / `wmic.exe` | `Get-CimInstance` / `New-CimSession` (+`-Protocol Dcom`) | `Get-WmiObject` removed in PS7; `wmic.exe` retiring (Win11 25H2) | Dual-edition inventory + DCOM fallback; used by the transport probe (MENU-05/Phase 3). |
| Hand-rolled JSON config + ad-hoc logging | PSFramework 1.14.457 config + diagnostics; audit stays hand-rolled synchronous | D-01 (this phase) | Validated config + runspace-safe diagnostics without a dependency tree; audit kept synchronous for fail-closed. |
| `adminCount=1` as protection signal | runtime well-known-SID + `LDAP_MATCHING_RULE_IN_CHAIN` | D-02 | Eliminates stale-`adminCount` false positives and SDProp-window false negatives. |
| Matching built-ins by name | match by `objectSid`/RID | D-05 | Survives RID-500 rename and localized group names. |
| `ShouldContinue` for bulk confirm | `ShouldProcess` (single) + `Read-Host` typed-count (bulk) + `-Force` | D-07 | Correct `-Confirm:$false`/`-WhatIf` behavior + automation bypass. |

**Deprecated/outdated:**
- **`adminCount` alone** for protection — stale-on-removal + SDProp-window lag; replaced by live IN_CHAIN membership.
- **`Get-WmiObject`/`wmic.exe`** — removed/retiring; CIM only.
- **`Export-Clixml -EncryptionKey`** for portable creds — PS7-only; reintroduces a secret vault (rejected for v1).
- **PSFramework for the audit sink** — async first-record-loss/exit-drain breaks fail-closed; use it for config+diagnostics only.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | PSFramework 1.14.457 exposes `Set-PSFConfig -Value -Initialize`, `Register-PSFConfigValidation`, `Export-PSFConfig -Path`, `Import-PSFConfig -Path` with those exact parameter names. | Standard Stack / Pattern 1 | MEDIUM — cmdlet existence verified; exact parameter names not fully confirmed from the persistence page. **Verify at build** against the installed module (`Get-Command Set-PSFConfig | Select -Expand Parameters`). If a name differs, only the call sites change — the policy (D-01) is unaffected. |
| A2 | `Write-EventLog -Source adman` can be created at runtime for OUTCOME-failure escalation. | Pattern 4 | LOW — creating an event source needs admin; mitigate by best-effort registration in `Initialize-Adman` + console-warning fallback. Confirm whether the tool runs elevated or must pre-register via installer. |
| A3 | Schema Admins (518) / Enterprise Admins (519) should be resolved against the **forest-root-domain** SID, not the current domain SID. | Pattern 3 | LOW for v1 single-domain (same SID); matters only if the forest later adds domains. Documented as a comment in the resolver; no v1 behavior change. |
| A4 | The environment's DCs support `LDAP_MATCHING_RULE_IN_CHAIN` (WS2003 SP2+/WS2008+). | Pattern 3 | VERY LOW — universally true for any supported AD; flag only if a pre-2008 DC exists (none expected). |
| A5 | Recursive IN_CHAIN over ~8 groups per target is acceptably fast for the target-set sizes in scope (single-object in Phase 2; capped bulk in Phase 4). | Pattern 3 | LOW-MEDIUM — IN_CHAIN can be expensive on very large/deep AD; Phase 4 bulk is capped, and Phase 2 is single-object, so per-target cost is bounded. Re-evaluate only if bulk target sets grow. |

**User confirmation recommended for:** A1 (build-time `Get-Command` check — mechanical, not a design decision). A2–A5 are documented behaviors, not decisions; no user sign-off needed, but A2 (event-source registration) may affect packaging.

## Open Questions

1. **Rights probe without a real write (MENU-05/CONF-06).**
   - What we know: pass-through default; prompt only when rights insufficient.
   - What's unclear: the cheapest reliable non-destructive rights signal — reading the managed OU proves read, not write. Options: (a) check `whoami /groups` for a configured delegated-admin group; (b) an AD ACL effective-permissions read on the managed OU (heavier); (c) attempt the operation and catch `UnauthorizedAccessException` (rights verified at action time, not startup).
   - Recommendation: combine (a) a configured `delegatedAdminGroup` SID check at startup for the MENU-05 banner, with (c) authoritative per-action handling inside the gate (the gate already catches and audits failures). **Confirm the delegated-admin group name/SID at plan time** (environment-specific).

2. **Audit file share/ACL model on a jump host (SAFE-04).**
   - What we know: default local `.store/audit/`; ACL to admin + SYSTEM (Pitfall 6).
   - What's unclear: whether the team wants a secondary forward to a central share/SIEM from day one (deferred to Phase 5 per D-03/deferred list) or a local-only v1.
   - Recommendation: local-only in Phase 0; design `Write-AdmanAudit` so a secondary sink can be added in Phase 5 without changing the call sites (the OUTCOME-escalation hook is the seam).

3. **Event-source elevation for OUTCOME-failure escalation (Pattern 4).**
   - What's unclear: does the tool run elevated (can `New-EventLog` create the `adman` source) or must the installer pre-register it?
   - Recommendation: best-effort `New-EventLog` in `Initialize-Adman`, degrade to console warning; document pre-registration as an installer/Phase-5 option if the tool runs non-elevated.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows PowerShell 5.1 | whole phase | assumed ✓ (in-box on Windows) | 5.1 | — (required baseline) |
| PowerShell 7.6.3 LTS | dual-edition support | unknown (install if testing 7.x) | — | Phase 5 CI matrix; claim `Desktop`-only until then |
| ActiveDirectory module (RSAT) | all AD calls | **must verify on target** | — | Document install; probe at startup (MENU-05); fail fast with guidance |
| PSFramework 1.14.457 | config + diagnostics (D-01) | **must install/pin** | — | Second mandatory module; `Install-PSResource PSFramework -Version 1.14.457` |
| Pester 6.0.0 | tests / SAFE-08 proof | **must install** (dev) | — | `Install-PSResource Pester -Version 6.0.0` |
| PSScriptAnalyzer 1.25.0 | lint / SAFE-08 custom rule | **must install** (dev) | — | `Install-PSResource PSScriptAnalyzer -Version 1.25.0` |
| AD Web Services (ADWS, TCP 9389) on a DC | AD module connectivity | environment-specific | — | surface "no reachable DC/ADWS" guidance in the probe |
| `node` (for gsd-tools seam) | research/package-legitimacy seam | ✗ (not on PATH in this env) | — | used WebSearch/WebFetch fallback; **planner must re-run package legitimacy via `Find-PSResource`** |

**Missing dependencies with no fallback:**
- `ActiveDirectory` (RSAT) — Phase 0/5 must document + probe; the tool cannot run AD tasks without it (no in-tool substitute).

**Missing dependencies with fallback:**
- `node` (research seam) — used built-in web providers; does not block Phase 0 implementation.
- PowerShell 7.6 — optional for v1 development; required for the Phase 5 dual-edition CI claim.

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is included. `security_enforcement` is `true`, ASVS level 1.

**Dimension-8 (sampling/validation) stance for the safety guarantees.** The safety invariants in this phase (SAFE-01…10) are **discrete and adversarial, not stochastic** — they are proven by **exhaustive fixture enumeration** (each invariant has at least one positive + one negative fixture) rather than random sampling. The two places where property-style coverage adds value — DN canonicalization (scope/deny matching) and confirmation token handling — get a small generated-input matrix (case/escaping/component-boundary/spoof DNs; threshold ±1, wrong token, empty token). "Sampling" here means: run the full fixture matrix per task commit (fast, mocked) and the lab-integration subset (real test OU) per wave merge. A safety guarantee is considered proven only when BOTH the mocked unit proof AND the lab integration proof are green.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Pester **6.0.0** (WinPS 5.1 + PS 7.4+) |
| Config file | `tests/PesterConfiguration.psd1` (Wave 0 — none exists yet) |
| Quick run command | `Invoke-Pester -Path tests -Output Normal -TagFilter Unit` |
| Full suite command | `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MENU-05 | Probe surfaces RSAT/domain/rights/transport + guidance | unit (mocked) | `Invoke-Pester -Path tests/Foundation.Capability.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-01 | Loads portable JSON config | unit | `tests/Config.Load.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-02 | Fails closed on empty managed-OU / failed deny-list | unit | `tests/Config.FailClosed.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-03 | Save+reload round-trips identically | unit | `tests/Config.RoundTrip.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-04 | DPAPI file written only on consent; restore-failure re-prompts | unit (mock Import-Clixml) | `tests/Credential.Dpapi.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-05 | `.store/` gitignored; no secret fields in audit schema | unit (static) | `tests/Config.NoSecrets.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| CONF-06 | Pass-through default; prompt only when rights insufficient | unit (mock) | `tests/Credential.PassThrough.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-01 | `-WhatIf` changes nothing; AD unchanged + dry-run audited | integration (lab) | `tests/Safety.WhatIf.Integration.Tests.ps1 -Tag Integration` | ❌ Wave 0 |
| SAFE-02 | y/n single; typed-count bulk; `-Force` bypasses prompt only | unit (mock Read-Host) | `tests/Safety.Confirm.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-03 | Every action incl. dry-run appends structured record, no secrets | unit | `tests/Audit.Schema.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-04 | Audit pre-write failure refuses the mutation | unit (mock FileStream throw) | `tests/Audit.FailClosed.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-05 | Deny-listed target refused + logged | unit | `tests/Safety.DenyList.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-06 | Recursive protected + gMSA refused; not `adminCount` | unit + integration | `tests/Safety.Protected.Tests.ps1` (Unit) + lab (nested DA, gMSA, RID-500 rename) | ❌ Wave 0 |
| SAFE-07 | DN outside managed-OU refused; spoof-DN refused | unit (DN matrix) | `tests/Safety.Scope.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-08 | No exported function calls AD write cmdlets (AST) | unit (static) | `Invoke-Pester -Path tests/Safety.Gate.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-09 | `Remove-ADObject` absent from `Public/`; gate allow-list has no hard-delete | unit (static) | `tests/Safety.NoHardDelete.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-10 | Preview array ≡ execute array (reference/count equal) | unit + integration | `tests/Safety.PreviewEqualsExecute.Tests.ps1` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `Invoke-Pester -Path tests -TagFilter Unit -Output Minimal` (mocked; must run in <30s; never touches a domain).
- **Per wave merge:** full suite incl. `-Tag Integration` against the disposable lab test OU (SAFE-01/06/10 end-to-end `-WhatIf`).
- **Phase gate:** full suite green (Unit + Integration) + `Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1 -Recurse` clean before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tests/PesterConfiguration.psd1` — Run/Filter/CodeCoverage (profiler-based, Pester 6 default) + Output.
- [ ] `tests/Safety.Gate.Tests.ps1` — AST guard (SAFE-08/09) — covers SAFE-08, SAFE-09.
- [ ] `tests/Safety.WhatIf.Integration.Tests.ps1` — end-to-end `-WhatIf` vs disposable test OU — covers SAFE-01, SAFE-10.
- [ ] `tests/Safety.Protected.Tests.ps1` (+ lab nested-DA/gMSA/RID-500 fixtures) — covers SAFE-06.
- [ ] `tests/Audit.FailClosed.Tests.ps1` — pre-write throw ⇒ refusal — covers SAFE-04.
- [ ] `tests/Mocks/ActiveDirectory.psm1` — mocked `Get-AD*/Set-AD*/Disable-AD*/Move-ADObject` so Unit tests never touch AD.
- [ ] `PSScriptAnalyzerSettings.psd1` — enable `PSUseShouldProcessForStateChangingFunctions`, `PSAvoidUsingPlainTextForPassword`, `PSUsePSCredentialType`, `PSAvoidUsingCmdletAliases`; documented `PSAvoidUsingWriteHost` suppression for the TUI module only.
- [ ] `rules/AdmanSafetyRules.psm1` — custom PSSA rule mirroring the AST guard (banned AD write cmdlets in `Public/`).
- [ ] Lab test OU + a delegated-admin test group — prerequisite for Integration tests (environment setup; document in README).

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` in `.planning/config.json`.

### Applicable ASVS Categories (Level 1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture / Threat Model | yes | Single Mutation Gate + tier map (this document); deny-list/protected/scope as structural boundaries |
| V2 Authentication | yes | Pass-through Windows auth (CONF-06); optional DPAPI `Export-Clixml` CurrentUser (CONF-04); never store plaintext; re-prompt on restore failure |
| V3 Session Management | partial | Credential held in-memory only for the session (`[pscredential]`, never serialized to logs); no long-lived tokens |
| V4 Access Control | yes | Managed-OU scope (SAFE-07) + deny-list (SAFE-05) + protected-account guard (SAFE-06) — refuse-by-default, logged |
| V5 Input Validation | yes | DN syntax validation at input; authoritative OU re-validation at startup (D-04); `ValidateSet` on the gate verb (SAFE-09); schema-validated config |
| V6 Stored Cryptography | yes | DPAPI via `Export-Clixml`/`ConvertFrom-SecureString` — **never hand-roll crypto**; no keyed-AES vault in v1 (D-06) |
| V7 Error Handling & Logging | yes | Fail-closed JSON-lines audit (SAFE-03/04), no secrets (schema), `$ErrorActionPreference='Stop'` + per-call `-ErrorAction Stop` (Pitfall 10) |
| V8 Data Protection | yes | `.store/` gitignored + ACL'd (admin+SYSTEM); audit never logs passwords/reset values; config split (secrets vs portable) |
| V10 Malicious Code | partial | Authenticode signing (Phase 5) so the tool runs under `AllSigned`; `RequiredModules`/`FunctionsToExport` explicit; no `Invoke-Expression` |

### Known Threat Patterns for PowerShell + AD

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unfiltered mass-change (`Get-AD* -Filter * \| Disable-ADAccount`) | Tampering / DoS | Gate count cap (Phase 4) + typed-count confirm (SAFE-02) + mandatory `-SearchBase`; AST guard bans direct AD writes (SAFE-08) |
| Touching protected/Tier-0 accounts (incl. via nesting) | Elevation of Privilege | Runtime well-known-SID + IN_CHAIN (SAFE-06); gMSA objectClass pre-filter; never `adminCount` |
| Stale `adminCount` trusted as protection proof | Tampering | Live membership only (D-02) |
| Credential theft from config/logs | Information Disclosure | DPAPI `Export-Clixml` CurrentUser (CONF-04); `.store/` gitignored+ACL'd; audit schema has no secret fields (SAFE-03/CONF-05); PSSA `PSAvoidUsingPlainTextForPassword` |
| Audit tampering / silent skip | Repudiation | Append-only JSONL, fail-closed pre-write (SAFE-04); OUTCOME-failure escalates to Event Log; Phase 5 tamper-evidence |
| DN spoof to escape managed-OU scope | Tampering | Component-boundary-anchored subtree suffix match; resolve canonical DN from AD (Pitfall 5) |
| RID-500 rename to bypass deny-list | Tampering | Match by `objectSid`/RID, never `sAMAccountName` (D-05) |
| Audit-before-mutate bypassed (write unaudited on failure) | Repudiation | Write-ahead PENDING reservation; throw before AD call (Pattern 4) |
| `Invoke-Expression` / dynamic cmdlet names to evade the AST guard | Tampering | Guard also greps `$tokens` for `&`/`Invoke-Expression`; resolve aliases via `Get-Command` (Pattern 1 caveat) |
| PSFramework auto-import overriding scope config (fail-open) | Tampering | Pin config with `-Path`; fail-closed in `Initialize-Adman` independent of framework (Pitfall 7) |

## Sources

### Primary (HIGH confidence)
- Microsoft Learn — `System.Management.Automation.Language.Parser` / `CommandAst` API (AST parse approach for SAFE-08) — https://learn.microsoft.com/dotnet/api/system.management.automation.language.parser
- PSScriptAnalyzer rule-writing (canonical AST `FindAll`+`CommandAst` pattern; custom rules) — https://github.com/PowerShell/PSScriptAnalyzer
- MicrosoftDocs/PowerShell-Docs — `Import-Clixml`/`Export-Clixml` (DPAPI CurrentUser binding) — https://github.com/MicrosoftDocs/PowerShell-Docs/blob/main/reference/5.1/Microsoft.PowerShell.Utility/Import-Clixml.md
- PSFramework configuration persistence basics (auto-import default locations; `-Path`/`-Scope`/`-ModuleName`) — https://psframework.org/docs/PSFramework/Configuration/Core/persistence-basics
- PowerShell Gallery — PSFramework 1.14.457 (pub. 2026-07-02), Pester 6.0.0, PSScriptAnalyzer 1.25.0 — https://www.powershellgallery.com/packages/PSFramework
- TechNet Wiki / AskDS — AdminSDHolder/SDProp + `adminCount` staleness (PDCe re-stamp ≤60 min) — corroborates D-02
- `LDAP_MATCHING_RULE_IN_CHAIN` OID `1.2.840.113556.1.4.1941` (DN attributes; `memberOf:...:=<groupDN>` recursive members) — https://ldapwiki.com/wiki/Wiki.jsp?page=Active%20Directory%20Group%20Related%20Searches ; https://support.atlassian.com/crowd/kb/active-directory-user-filter-does-not-search-nested-groups/

### Secondary (MEDIUM confidence)
- PowerShell Explained — ShouldProcess/ShouldContinue/`-Confirm:$false`/`-Force` deep dive — https://powershellexplained.com/2020-03-15-Powershell-shouldprocess-whatif-confirm-shouldcontinue-everything/
- The SysAdmin Channel — ShouldContinue vs ShouldProcess — https://thesysadminchannel.com/shouldcontinue-vs-shouldprocess-whats-the-difference/
- PowerShell GitHub issue #13229 (`-Confirm:$false` ignores ConfirmImpact) and #14294 (`$Confirm` unset under StrictMode)
- powershellisfun.com / forums.powershell.org — `Export-Clixml` same-user/same-machine binding + `0x8009000B` on wrong user/machine — https://powershellisfun.com/2024/08/09/using-export-clixml-and-import-clixml-for-credentials-in-powershell-scripts/

### Tertiary (LOW confidence)
- PSFramework exact parameter names for `Set-PSFConfig -Value/-Initialize` and `Register-PSFConfigValidation` — existence verified, exact signatures to be confirmed at build via `Get-Command` (Assumption A1).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions + publish dates verified against PowerShell Gallery / Microsoft Learn; PSFramework exact signatures MEDIUM (A1).
- Architecture: HIGH — single-gate, Public/Private, fail-closed audit, AST guard all corroborated by Microsoft/GitHub/Gallery sources; AST code pattern CITED to PSScriptAnalyzer + Language API.
- Pitfalls: HIGH — AD/PowerShell semantics (adminCount, RID-500, gMSA, ShouldProcess, DPAPI, IN_CHAIN, JSON depth) verified against Microsoft/protocol sources and the PITFALLS corpus.
- Mechanisms (D-02…D-07): HIGH — `1.2.840.113556.1.4.1941`, well-known RIDs/SIDs, DPAPI 0x8009000B, ShouldProcess/ShouldContinue matrix all cross-corroborated.

**Research date:** 2026-07-10
**Valid until:** 2026-08-09 (30 days — stable domain; re-verify PSFramework/Pester/PSScriptAnalyzer versions at build)

## RESEARCH COMPLETE
