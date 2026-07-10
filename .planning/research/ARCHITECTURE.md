# Architecture Research

**Domain:** Menu-driven (TUI) PowerShell toolkit for on-prem Active Directory user & computer administration (adman working name)
**Researched:** 2026-07-10
**Confidence:** HIGH overall (module layout, safety primitive, remoting ladder verified against Microsoft docs / PSFramework Gallery / official repos). MEDIUM for specific PSFramework cmdlet signatures and community scaffolding conventions (verify exact names at build time).

> Reader note: this file is written for the **roadmap**. It names components, draws hard boundaries, fixes the direction of data through a non-bypassable safety gate, and gives a dependency-ordered build sequence. Where the project brief contradicts itself, the contradiction is surfaced as a decision the roadmap must resolve (see "Configuration" and "Open contradictions in the brief").

---

## Verified facts that drive the design

These are the load-bearing, current facts the architecture rests on. Everything else is conventional PowerShell engineering.

| Fact | What it means for the design | Confidence |
|------|------------------------------|------------|
| **PSFramework** is at **1.14.457** (published 2026-07-02), requires **PowerShell 3.0+**, supports **both Desktop (5.1) and Core (7+)**, has **no dependencies**, and is actively maintained (changelog through 2026). | Safe to adopt as the cross-cutting backbone (configuration + logging + messaging/runspaces) without breaking the hard PS 5.1 requirement and without adding a dependency tree. | HIGH (PowerShell Gallery + official changelog) |
| **ConsoleGuiTools / Terminal.Gui** (`Out-ConsoleGridView`) is **PowerShell 7.2+ only**, was archived **read-only on 2026-06-24** ("feature complete", last feature release v0.7.7 / 2024-05-01); the older Avalonia `Microsoft.PowerShell.GraphicalTools` is deprecated; community successor is `tui-cs/PSTui`. | Must NOT be the v1 menu foundation — incompatible with PS 5.1 and unmaintained. Build the menu as a custom Read-Host dispatcher in v1; optional built-in `Out-GridView` (5.1, Windows) for selection; defer a rich TUI (PSTui on 7.x) to v2. | HIGH (official GitHub) |
| **CIM is the no-WinRM fallback.** `New-CimSessionOption -Protocol` accepts `Wsman`, `Dcom`, `Default`; a CIM session over **DCOM** uses a *different transport/firewall profile* than WinRM and defaults to `PacketIntegrity` + `PacketPrivacy` (integrity + encryption on by default). CIM cmdlets are Windows-only. | The auto-detect ladder is really **PSRemoting(WinRM) → CIM/WSMan → CIM/DCOM → skip**, and each hop has distinct firewall/permission needs (WinRM 5985/5986 vs DCOM 135 + RPC dynamic range). Isolate this behind one connector. | HIGH (Microsoft Learn, doc updated 2025-07-24) |
| **`SupportsShouldProcess`** (`[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]` + `$PSCmdlet.ShouldProcess($target,$action)`) is the engine-level primitive that makes `-WhatIf`/`-Confirm` flow automatically and consistently. | It is the *mechanism* of the safety gate, but it is only non-bypassable if there is exactly **one** code path that performs mutations. See "The Single Mutation Gate." | HIGH (Microsoft `about_*` docs) |
| **DPAPI encryption is user- AND machine-bound** (`ConvertTo/From-SecureString`, `Export-Clixml` for SecureString). Ciphertext cannot be decrypted on a different machine or by a different user. | Directly conflicts with "single encrypted config file for easy backup/restore." Resolved below (Configuration). | HIGH (Microsoft DPAPI/SecureString docs) |

---

## The central design rule: The Single Mutation Gate

Every destructive or state-changing operation in the toolkit — disable, enable, move, reset password, unlock, group change, quarantine — is required to pass through **exactly one** internal function. New features are forbidden from calling `Set-ADUser`, `Disable-ADAccount`, `Move-ADObject`, `Set-ADAccountPassword`, `Add/Remove-ADGroupMember`, etc. directly. They build a *request* and hand it to the gate.

This is the one decision that makes the safety property ("if everything else fails, this must hold") actually hold: there is **no second code path** a future contributor can add that forgets the preview, the deny-list, or the audit line.

```
            ┌──────────────────────────────────────────────────────────────┐
            │                  Invoke-AdmanMutation  (THE GATE)              │
            │  private — the ONLY function allowed to call AD write cmdlets  │
            ├──────────────────────────────────────────────────────────────┤
            │  1. Resolve target(s)        → AD read layer                   │
            │  2. Test-AdmanTargetAllowed  → scope + deny-list + protection  │
            │  3. Bulk policy              → cap + typed-confirm threshold   │
            │  4. ShouldProcess            → -WhatIf preview / -Confirm      │
            │  5. Execute                  → the one real AD write call      │
            │  6. Write-AdmanAudit         → append-only structured log      │
            └──────────────────────────────────────────────────────────────┘
                          ▲
                          │  every public verb funnels here
   Disable-AdmanUser ─────┤  Move-AdmanComputer ─────┤  Reset-AdmanPassword ─┤
   (Public verbs are thin: validate input → build request → call the gate)
```

Steps 2, 4, and 6 are the non-negotiables. If any step throws or the operator declines, the function returns a structured result (`Skipped`/`Denied`/`WhatIf`) and still writes an audit line (so refusals are visible). Preview (`-WhatIf`) and execution share steps 1–3 so the preview is guaranteed to describe the same action the execution would take — no "preview said X, did Y" drift.

---

## Standard Architecture

### System Overview (layers)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PRESENTATION  (menu/dispatch, prompts, formatting)                     │
│  Start-Adman ▸ Menu table ▸ Read-Host ▸ object pickers ▸ table/color out │
├─────────────────────────────────────────────────────────────────────────┤
│  PUBLIC VERBS  (thin orchestration — the "feature" surface)             │
│  New-/Disable-/Enable-/Move-/Reset-/Unlock-User/Computer ▸ workflows    │
│        │                                                                │
│        ▼  ALL writes funnel down; reads may bypass the gate             │
├─────────────────────────────────────────────────────────────────────────┤
│  SAFETY CORE  (cross-cutting, non-bypassable)                           │
│  Invoke-AdmanMutation(Gate) ▸ Test-AdmanTargetAllowed ▸ ShouldProcess   │
│  ▸ Bulk policy ▸ Confirm-AdmanAction ▸ Write-AdmanAudit                 │
├─────────────────────────────────────────────────────────────────────────┤
│  ACCESS / EXECUTION                                                     │
│  AD Access layer (Get-/Set-AD* wrappers) │ Remoting layer (connector)   │
│                                          │ WinRM ▸ CIM/WSMan ▸ CIM/DCOM  │
├─────────────────────────────────────────────────────────────────────────┤
│  FOUNDATION  (loaded once at startup)                                   │
│  Configuration (PSFramework) ▸ Logging/Audit (PSFramework) ▸ Credential │
│  ▸ Capability probe (RSAT present? admin rights? domain reachability?)  │
└─────────────────────────────────────────────────────────────────────────┘
        ▲ cross-cutting: Config + Logging + Safety are defined ONCE here
        │ and consumed by every layer above — never re-implemented per feature
```

### Component Responsibilities & boundaries

| Component | Owns | Talks to | Must NOT talk to |
|-----------|------|----------|------------------|
| **Presentation / Menu** | Render menus, read/validate operator input, format output (table/CSV/HTML via the Output layer), route a chosen action to a public verb. Never touches AD. | Public verbs, Output | AD cmdlets, Remoting, the Gate's internals |
| **Public verbs** (`Disable-AdmanUser`, `Move-AdmanComputer`, …) | Parameter shape, input validation, help. Thin: build a mutation *request* → call the Gate. Read-only verbs call the AD read layer directly. | The Gate (writes), AD read layer (reads), Output | AD write cmdlets directly (forbidden), Remoting (except remote-ops verbs) |
| **Workflows** (onboarding/offboarding) | Sequence several public verbs into one guided, atomic-ish procedure with a single preview + confirm. | Public verbs only | AD cmdlets, the Gate directly (go through verbs) |
| **Safety Core** — `Invoke-AdmanMutation` | The single mutation pipeline (resolve → allow → bulk → ShouldProcess → execute → audit). | AD read+write, Target-allow, Confirm, Audit, Config (for caps) | Presentation (returns results; never prompts on its own except the typed-confirm) |
| **Safety Core** — `Test-AdmanTargetAllowed` | Pure(ish) policy: in managed OU? on deny-list? protected (admin-group/service/built-in)? Returns allow/deny + reason. Used by both preview and execute. | Config (managed OU, deny-list), AD read (group/SID resolution) | AD writes, Remoting |
| **Safety Core** — `Confirm-AdmanAction` | `-WhatIf`/`-Confirm` via ShouldProcess + the typed "type the count" confirmation for bulk. | ShouldProcess engine, Presentation | AD writes |
| **Safety Core** — `Write-AdmanAudit` | Append one structured record (who/what/when/targets/whatif/result/correlation-id). The only writer of the audit log. | Logging sink (file) | — |
| **AD Access layer** | Thin, consistent wrappers over RSAT `*-AD*` cmdlets: read wrappers (public-read use) and the write calls used *only* by the Gate. Centralizes `-Server`, error handling, and the live credential. | RSAT ActiveDirectory module, Credential | Presentation, Output |
| **Remoting / connector** | Per-target transport selection with probe + cache: WinRM → CIM/WSMan → CIM/DCOM → skip. Returns a session/handle or a `Skipped` result. Isolated so the rest of the tool never branches on transport. | Target hosts (WinRM/RPC/DCOM), Config (timeouts, order) | AD cmdlets, the Gate |
| **Output** | One place that turns result objects into console tables, CSV, or self-contained HTML. | Presentation, public verbs | AD, Remoting, the Gate |
| **Foundation — Config** | Load/validate/hold managed OU, deny-list, caps, paths, transport order. Encryption boundary for the optional saved credential. | PSFramework config + DPAPI (for the secret file) | AD writes |
| **Foundation — Logging/Audit** | The single logging sink; operational messages vs immutable audit records. | PSFramework logging (+ file provider) | — |
| **Foundation — Credential** | Decide pass-through vs prompt; hold a `PSCredential` only for the session. | AD access, Config | Presentation (except the prompt) |
| **Foundation — Capability probe** | At startup: RSAT present? domain reachable? current user rights sufficient? Sets session flags the menu reads to enable/disable verbs. | AD read (cheap), RSAT | writes |

---

## Recommended Project Structure (script module, PS 5.1-safe)

A real PowerShell **module** (manifest + root module + Public/Private split), dot-sourced in the `.psm1`. No compile/build step required for v1 (so a junior can edit a file and re-run); add **ModuleBuilder** later if a single-file distributable is wanted.

```
adman/
├── adman.psd1                 # manifest: RootModule, PS 5.1+, RequiredModules=(ActiveDirectory, PSFramework),
│                              #   FunctionsToExport = public verbs only (explicit, never '*')
├── adman.psm1                 # root: dot-source Private/* then Public/*; run Initialize-Adman (config+log+probe)
├── Start-Adman.ps1            # optional launcher (sets execution policy scope, imports module, opens menu)
│
├── Public/                    # exported verbs — one function per file, name == verb
│   ├── Start-Adman.ps1        # the menu/dispatch entry point
│   ├── User/                  # Disable/Enable/Move/Reset/Unlock/New-AdmanUser, *-AdmanGroupMembership
│   ├── Computer/              # Disable/Enable/Move-AdmanComputer, Get-AdmanComputerInventory
│   ├── Reporting/             # Get-Adman* report verbs (read-only; bypass the Gate, hit AD read layer)
│   ├── Remote/                # Invoke-AdmanRemoteQuery/Action (use the Remoting connector)
│   ├── Workflow/              # New-AdmanOnboarding, Invoke-AdmanOffboarding
│   └── Config/                # Get/Set/Protect/Export-AdmanConfig
│
├── Private/                   # NOT exported — the machinery
│   ├── Safety/
│   │   ├── Invoke-AdmanMutation.ps1      # THE GATE (only caller of AD write cmdlets)
│   │   ├── Test-AdmanTargetAllowed.ps1   # scope + deny-list + protection policy
│   │   ├── Confirm-AdmanAction.ps1       # ShouldProcess + typed bulk confirm
│   │   └── Get-AdmanProtectedIdentity.ps1# resolve built-in/admin/service SIDs at runtime
│   ├── AD/
│   │   ├── Adman.AD.Read.ps1             # Get-* wrappers (public-read use)
│   │   └── Adman.AD.Write.ps1            # the raw Set-/Disable-/Move- calls (Gate-only)
│   ├── Remoting/
│   │   ├── Connect-AdmanTarget.ps1       # probe + ladder, returns session or Skipped
│   │   └── Get-AdmanTransportCache.ps1   # per-host remembered transport for the session
│   ├── Output/
│   │   ├── Write-AdmanTable.ps1 / Export-AdmanCsv.ps1 / Export-AdmanHtml.ps1
│   │   └── Format-AdmanResult.ps1        # canonical result object shape
│   ├── Audit/
│   │   └── Write-AdmanAudit.ps1          # append-only JSONL audit writer
│   ├── Config/
│   │   └── Initialize-AdmanConfig.ps1    # register defaults, load+validate, wire encryption
│   ├── Foundation/
│   │   ├── Initialize-Adman.ps1          # startup: config → logging → credential → probe
│   │   ├── Test-AdmanCapability.ps1      # RSAT/domain/rights probe
│   │   └── Get-AdmanCredential.ps1       # pass-through vs prompt decision
│   └── UI/
│       ├── Show-AdmanMenu.ps1            # numbered menu renderer + Read-Host loop
│       ├── Read-AdmanConfirmation.ps1    # generic prompt helpers
│       └── Select-AdmanObject.ps1        # Out-GridView (5.1) fallback to numbered pick
│
├── config/
│   ├── adman.defaults.json               # shipped defaults (managed OU placeholder, caps, transport order)
│   └── adman.schema.json                 # validation schema for the config file
├── en-US/about_adman.help.txt            # inline help / about topics
├── tests/                                # Pester: policy tests (deny-list, scope, gate coverage), WhatIf tests
└── build/                                # (optional, later) ModuleBuilder / Sampler pipeline
```

### Structure rationale

- **Public/ vs Private/ + explicit `FunctionsToExport`:** the only way to guarantee the Gate is the sole writer is to *not export* `Invoke-AdmanMutation` or the raw write wrappers, and to keep `FunctionsToExport` explicit (never `'*'`) so a new private helper can never accidentally become callable. This is a structural enforcement of the safety rule, not just convention.
- **One function per file, file named after the function:** the dominant community convention; makes a mixed-skill team able to find things, and plays well with the dot-source loader and with Pester.
- **`Private/Safety` is its own folder** so code review can watch it specially; changes here are high-blast-radius.
- **No build step in v1:** lowers the barrier for the team and matches "ship as script/module first" in the brief. ModuleBuilder/Sampler are opt-in later (single-file distribution, signing) — named here so the roadmap can place them.

---

## Architectural Patterns

### Pattern 1: The Single Mutation Gate (command/request object)

**What:** Public verbs never mutate. They build a small request (`Verb`, `Targets[]`, `Parameters`, `CorrelationId`) and call `Invoke-AdmanMutation`. The Gate is the only function marked to call AD write cmdlets, and it runs the fixed pipeline resolve → allow → bulk → ShouldProcess → execute → audit.

**When:** Always. This is the load-bearing pattern for the whole tool.

**Trade-offs:** A little more boilerplate per verb; in exchange, safety, preview, and audit are provably uniform and cannot be skipped by a future feature.

```powershell
# Public verb — thin. No Set-AD* here.
function Disable-AdmanUser {
    [CmdletBinding(SupportsShouldProcess)]   # surfaces -WhatIf/-Confirm to the caller/menu
    param([Parameter(Mandatory)][string[]]$Identity)
    Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $Identity `
        -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
}
```

```powershell
# Private — the only place that is allowed to write.
function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Verb, [string[]]$Targets, [hashtable]$Parameters, [switch]$WhatIf, [switch]$Confirm)
    $cid = [guid]::NewGuid()
    $resolved = Resolve-AdmanTarget -Targets $Targets                 # read layer
    foreach ($t in $resolved) {
        $decision = Test-AdmanTargetAllowed -Object $t                # scope/deny/protect
        if (-not $decision.Allowed) { Write-AdmanAudit ... 'Denied'; continue }
    }
    Assert-AdmanBulkPolicy -Count ($resolved.Count)                   # cap + typed-confirm
    if ($PSCmdlet.ShouldProcess(($resolved -join ','), $Verb)) {      # -WhatIf/-Confirm
        & "Adman.AD.Write.$Verb" -Objects $resolved @Parameters       # the ONE real write
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Result 'Done'
    } else {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Result 'WhatIf/Cancelled'
    }
}
```

### Pattern 2: Capability-based menu (probe once, render honestly)

**What:** At startup `Test-AdmanCapability` records: RSAT present, domain reachable, current-user rights sufficient, transport reachability. The menu reads these flags to gray out or annotate verbs (e.g. hide remote-ops verbs when neither WinRM nor DCOM is reachable) rather than failing at click time.

**When:** Startup, and re-probe on demand (`Refresh-AdmanCapability`).

**Trade-offs:** A couple of seconds at launch; repaid by not dead-ending a junior into a verb that cannot work.

### Pattern 3: Transport ladder with a session-scoped cache (isolated remoting)

**What:** `Connect-AdmanTarget -ComputerName X` probes in order **PSRemoting (WinRM) → CIM/WSMan → CIM/DCOM → skip**, caches the winning transport per host for the session, and returns either a usable handle or a structured `Skipped($reason)`. Remote verbs consume the handle and never branch on which transport won.

**When:** Every remote operation. The order and per-hop timeouts come from Config so an environment can prefer CIM-first.

**Trade-offs:** First contact with a host pays probe latency; the cache makes repeats cheap. The fallback from CIM/WSMan to CIM/DCOM is essential because "no WinRM" also breaks WSMan-CIM — DCOM is the real fallback (distinct firewall profile: 135 + RPC dynamic range vs 5985/5986).

```powershell
function Connect-AdmanTarget {
    param([string]$ComputerName)
    if ($cached = $script:TransportCache[$ComputerName]) { return $cached }
    foreach ($proto in $script:Config.Remoting.Order) {        # e.g. WinRM,CimWsman,CimDcom
        $h = switch ($proto) {
            'WinRM'   { New-PSSession  $ComputerName -ErrorAction SilentlyContinue }
            'CimWsman'{ New-CimSession $ComputerName -ErrorAction SilentlyContinue }
            'CimDcom' { $o=New-CimSessionOption -Protocol Dcom
                        New-CimSession $ComputerName -SessionOption $o -ErrorAction SilentlyContinue }
        }
        if ($h) { return ($script:TransportCache[$ComputerName] = @{Transport=$proto; Handle=$h}) }
    }
    return @{Transport='Skip'; Reason='No reachable transport (WinRM/CIM/DCOM all failed)'}
}
```

### Pattern 4: Runtime protection resolution (never trust a static list)

**What:** `Get-AdmanProtectedIdentity` resolves the protected set at check time using **well-known SIDs**, not names: built-in `Administrator` (RID 500 / `S-1-5-…-500`), `krbtgt`, `Guest`, plus members of Domain Admins (`<domain>-512`), Enterprise Admins (`<forest>-519`), Schema Admins (`<forest>-518`), and the local `Administrators` (`S-1-5-32-544`). Service/gMSA accounts are matched by a configured naming pattern or a designated "protected" group/OU. Results are cached for the session but re-resolvable.

**When:** Inside `Test-AdmanTargetAllowed`, for every target, on both preview and execute.

**Trade-offs:** An extra group-membership lookup per target; repaid by protection that stays correct when group membership changes and across locales (SIDs are language-independent).

### Pattern 5: Canonical result object + single Output layer

**What:** Every verb returns the same shape (`Action, Targets, Requested, Skipped, Denied, Succeeded, Failed, WhatIf, CorrelationId, Timestamp`). The Output layer turns that into a console table, CSV (`Export-Csv`), or self-contained HTML (`ConvertTo-Html` with embedded CSS) — never `Format-*` at the end of a function (keep objects until the boundary).

**When:** Always. Lets the menu preview identically to the audit/CSV and keeps reports reproducible.

---

## Data Flow

### Destructive action (the spine)

```
Operator picks "Disable user" in the menu
        │
        ▼
Presentation: prompt for identity, validate shape (not empties/wildcards unless allowed)
        │
        ▼
Public verb Disable-AdmanUser  ── builds request {Verb, Targets, CorrelationId}
        │
        ▼
Invoke-AdmanMutation (THE GATE)
   1. Resolve-AdmanTarget  ──► AD read layer  ──► returns directory objects
   2. Test-AdmanTargetAllowed ──► Config(managed OU, deny-list) + runtime SIDs
        │  Denied? ──► Write-AdmanAudit('Denied') ──► result.Skipped ──► (stop for that target)
   3. Assert-AdmanBulkPolicy ──► Config(MaxBulkTargets, PromptThreshold)
        │  Over cap? ──► refuse (audit)  │  Over threshold? ──► typed confirmation
   4. ShouldProcess ──► -WhatIf? show preview, audit('WhatIf'), stop
        │             ──► -Confirm? prompt; declined? audit('Cancelled'), stop
   5. Adman.AD.Write.Disable ──► the single real AD write
        │
        ▼
   6. Write-AdmanAudit('Done') ──► append-only JSONL (who/what/when/targets/cid)
        │
        ▼
Canonical result object ──► Output layer ──► console table (and CSV/HTML on request)
```

Key invariants this flow guarantees:
- **Preview ≡ execution:** steps 1–3 run identically for `-WhatIf` and for real, so the preview cannot describe a different action than the one that would run.
- **Refusals are logged:** deny-list / out-of-scope / over-cap are audited, not silent.
- **One correlation id** links preview → confirm → execute → result across the menu screen, the audit log, and any exported report.

### Read / report flow (may bypass the Gate, never bypasses scope)

```
Report verb ──► AD read layer (still scoped to managed OU by default) ──► Output (table/CSV/HTML)
```
Reports are read-only, so they skip the Gate's ShouldProcess/audit-of-mutation — but they still read through the scoped read layer so inventory defaults to the managed OU, and they emit their own (lighter) audit line for "report generated."

### Startup flow

```
Import-Module adman
   └─► Initialize-Adman
        1. Initialize-AdmanConfig   (defaults → load file → validate → wire DPAPI for secret file)
        2. Initialize logging/audit sink (PSFramework file provider)
        3. Get-AdmanCredential      (pass-through if rights suffice; else prompt once; hold in memory)
        4. Test-AdmanCapability     (RSAT? domain? rights? transports?) → session flags
   └─► Menu reads flags and renders enabled/disabled verbs accordingly
```

### Configuration flow (load + enforce)

```
config/adman.defaults.json ──► register defaults (PSFramework)
        │
operator's config file ──► Import/validate against schema ──► in-memory $script:Config
        │
        ├─► read by Test-AdmanTargetAllowed  (ManagedOUs, DenyList, ProtectedPatterns)
        ├─► read by Assert-AdmanBulkPolicy   (MaxBulkTargets, PromptThreshold)
        ├─► read by Connect-AdmanTarget      (Remoting.Order, timeouts)
        └─► read by Output/Audit             (ReportPath, AuditPath)

Optional saved credential: separate per-user file, DPAPI-encrypted, read only by Get-AdmanCredential
```

**Enforcement is structural:** policy values live in one place (`$script:Config`) and are *consumed* by `Test-AdmanTargetAllowed` and `Assert-AdmanBulkPolicy`, which sit inside the Gate. There is no per-feature copy of the deny-list to drift or forget.

---

## Configuration & encryption — resolving a contradiction in the brief

The brief both says **"configuration MUST BE encrypted"** *and* **"single config file for easy backup and restore"** *and* (in Context) **"no credential storage in v1."** These conflict: DPAPI encryption (the only cred encryption available without a vault) is **machine- and user-bound**, so an encrypted config does **not** survive backup/restore to another machine/user.

Recommended resolution (make the roadmap pick explicitly):

1. **Split the file in two.**
   - `adman.config.json` — **portable, non-secret**: managed OU(s), deny-list, caps, paths, transport order. Plain JSON, trivially backed up / restored / diffed / code-reviewed. *Restore works anywhere.*
   - `adman.credential.xml` — **optional, per-user, DPAPI-encrypted** (`Export-Clixml` of a `PSCredential`), written *only* if the operator explicitly chooses "remember me." Not portable; on restore to a new machine/user the tool detects decrypt failure and **re-prompts** rather than failing closed-open.
2. **Default to pass-through** (no saved credential). Saving a credential is opt-in and clearly labeled as machine-bound. This satisfies "least privilege / no stored secrets by default" while still offering the convenience the brief asks for.
3. **Validate on load** against `adman.schema.json`; refuse to start (fail closed) if the managed OU is empty/unset or the deny-list failed to load — a tool with no scope configured is more dangerous than no tool.

> Flag for requirements: reconcile "no credential storage in v1" vs "credentials stored encrypted in a single config file." Recommendation above keeps both intents by making storage opt-in, separate, and machine-bound, with backup/restore applying to the non-secret config.

---

## Suggested build order (dependency-ordered, foundation first)

Sequence phases so each phase is runnable and testable on its own, and so the safety spine exists *before* any real write lands.

1. **Foundation skeleton** — module scaffold (`.psd1/.psm1`, Public/Private loader), `Initialize-Adman`, PSFramework config + logging wired, `Test-AdmanCapability` probe. *Exit: tool starts, loads config, reports capabilities, logs. No AD writes.*
2. **Configuration + encryption** — defaults + schema + load/validate, managed-OU/deny-list/caps readable, DPAPI credential file (opt-in). *Exit: config round-trips, fails closed on bad/empty scope.*
3. **AD Access read layer + Credential** — read wrappers, pass-through/prompt decision, scoped queries. *Exit: can list users/computers in the managed OU.*
4. **Safety Core (THE GATE)** — `Test-AdmanTargetAllowed` (scope/deny/runtime-SID protection), `Confirm-AdmanAction` (ShouldProcess + typed bulk confirm), `Assert-AdmanBulkPolicy`, `Write-AdmanAudit`, and `Invoke-AdmanMutation` wiring them in order. **Pester here: prove every deny/cap/WhatIf path and that no exported function calls AD write cmdlets.** *Exit: the gate denies/logs correctly against fixtures; `-WhatIf` works end-to-end against a test OU.*
5. **First write verbs through the Gate** — disable/enable/move user + computer, reset password, unlock, group membership. *Exit: lifecycle verbs work with preview + confirm + audit, all via the Gate.*
6. **Menu/dispatch (Presentation)** — capability-aware numbered menu, prompts, `Select-AdmanObject` (Out-GridView with numbered fallback), routing to verbs. *Exit: a junior can drive phase-5 verbs from the menu.*
7. **Reporting + Output** — canonical result object, console/CSV/self-contained HTML, inventory (stale/last-logon/OS). *Exit: reports render and export.*
8. **Remoting connector + remote verbs** — the WinRM→CIM/WSMan→CIM/DCOM→skip ladder with cache; remote query then remote action. *Exit: remote ops degrade gracefully per host.*
9. **Workflows** — onboarding/offboarding composed from existing verbs (one preview + confirm over the whole procedure). *Exit: end-to-end guided flows.*
10. **Packaging (optional, later)** — ModuleBuilder/Sampler single-file build, signing, docs polish.

**Why this order:** 1–4 build the non-bypassable spine before any mutation exists (so no phase can ever ship a write that forgets the gate). 5 proves the spine with the simplest verbs. 6–9 add reach (UI, reports, remoting, workflows) as consumers of an already-correct core. 10 is pure ergonomics.

**Phase research flags:**
- Phase 4 (Safety Core) and Phase 2 (config encryption): **likely need deeper research** — exact PSFramework config cmdlet signatures, DPAPI/Clixml behaviour across PS 5.1 vs 7, and the precise well-known-SID set for the environment's protected groups.
- Phases 5–7, 9: standard patterns, unlikely to need fresh research.
- Phase 8 (remoting): medium — confirm the environment's firewall reality for DCOM (135 + RPC dynamic range) vs WinRM; the ladder is correct, but the *usable order* depends on what's actually open.

---

## Anti-Patterns

### Anti-Pattern 1: Calling `Set-AD*` directly from a feature verb

**What people do:** A new "rename user" feature calls `Set-ADUser` inline because it's quick.
**Why it's wrong:** It bypasses the Gate — no preview, no deny-list, no scope check, no audit. One such verb silently destroys the tool's core safety guarantee.
**Do this instead:** Every write goes through `Invoke-AdmanMutation`. Enforce by not exporting the raw write wrappers, keeping `FunctionsToExport` explicit, and adding a Pester test that greps `Public/` for bare `Set-AD*|Disable-AD*|Move-AD*|Remove-AD*|Add-ADGroupMember|Set-ADAccountPassword`.

### Anti-Pattern 2: Building the menu on ConsoleGuiTools / Terminal.Gui

**What people do:** Reach for `Out-ConsoleGridView`/`Microsoft.PowerShell.ConsoleGuiTools` for a "real TUI."
**Why it's wrong:** It is **PowerShell 7.2+ only** and the repo was **archived read-only on 2026-06-24** — incompatible with the hard PS 5.1 requirement and unmaintained. It also fails in non-interactive/remote contexts.
**Do this instead:** A custom numbered menu over `Read-Host` (zero deps, 5.1-safe, works over PSRemoting). Use the built-in `Out-GridView` (5.1, Windows) only as an optional object picker with a numbered fallback. Defer a rich TUI (community `PSTui`, 7.x) to v2.

### Anti-Pattern 3: Assuming "CIM works when WinRM doesn't" (without DCOM)

**What people do:** Treat `Get-CimInstance` as the WinRM fallback.
**Why it's wrong:** Default CIM uses WSMan (WinRM) — if WinRM is off, default CIM fails too. The actual fallback is CIM over **DCOM** (`-Protocol Dcom`), which is a different firewall profile (135 + RPC dynamic) and may also be blocked.
**Do this instead:** Implement the full ladder (WinRM → CIM/WSMan → CIM/DCOM → skip), probe+cache per host, and surface `Skipped` gracefully rather than erroring.

### Anti-Pattern 4: Trusting a static deny-list for protection

**What people do:** Hard-code account/group names to protect.
**Why it's wrong:** Names are locale-dependent and membership changes; a stale list either misses a newly-added admin or blocks a renamed built-in.
**Do this instead:** Resolve protection at check time via well-known SIDs (RID 500, `-512/-518/-519`, `S-1-5-32-544`) and configured patterns/groups, cached per session.

### Anti-Pattern 5: DPAPI-encrypting the whole portable config

**What people do:** Encrypt the single config file with DPAPI and expect backup/restore to work on another machine.
**Why it's wrong:** DPAPI ciphertext is user+machine bound; it will not decrypt after restore elsewhere, locking the tool out (or tempting plaintext fallback).
**Do this instead:** Keep non-secret config portable (plain JSON) and isolate the optional credential in a separate DPAPI file that re-prompts on restore.

### Anti-Pattern 6: `Format-Table` / `Out-Host` inside functions

**What people do:** Format output at the end of a verb.
**Why it's wrong:** It destroys the object pipeline, so the same verb can't feed CSV/HTML/audit and can't be tested for its data.
**Do this instead:** Return canonical result objects; let the Output layer format at the boundary.

---

## Scaling Considerations

This is a small-team admin tool, not a service — "scaling" here means *target-set size* and *operator skill*, not concurrent users.

| Concern | Small (≤25 targets) | Medium (hundreds) | Large (thousands) |
|---------|---------------------|-------------------|-------------------|
| Bulk mutation | Synchronous through the Gate; typed-confirm above threshold | Add progress + streaming audit; keep cap | Defer / require explicit override + chunked runs; consider runspace fan-out (PSFramework) |
| Remoting fan-out | Sequential probe+cache | Parallel connect with throttle (runspaces) | Mandatory chunking + transport cache persisted across runs |
| Reports | In-memory, single CSV/HTML | Stream to CSV; paginate HTML | Server-side filters (`-Filter`/LDAP) so objects never all load client-side |
| Audit log | One JSONL file | Daily rotation | Rotation + shipped to a central store |

**Scaling priorities:**
1. **First thing that bites:** unfiltered AD reads (`Get-ADUser -Filter *`). Always scope with `-SearchBase` (managed OU) and server-side `-Filter`.
2. **Next:** synchronous remoting over many hosts. Keep the connector sequential until it hurts, then add throttled runspaces (PSFramework already in the stack).

---

## Integration Points

### External

| Service | Integration | Gotchas |
|---------|-------------|---------|
| **ActiveDirectory module (RSAT)** | `RequiredModules` in the manifest; used only by the AD access layer | Must be present where the tool runs — document the install (RSAT / `Add-WindowsCapability`), do not bundle. Probe at startup (capability flags). |
| **WinRM / PSRemoting** | `New-PSSession`/`Invoke-Command` (remoting connector, hop 1) | 5985/5986; not guaranteed on targets — must fall back. |
| **CIM (WSMan + DCOM)** | `New-CimSession` (hops 2–3) | Windows-only. DCOM = 135 + RPC dynamic range; defaults to integrity+encryption. |
| **File system (config/audit/reports)** | JSON config, JSONL audit, CSV/HTML reports | Audit path must be writable; fail closed if the audit cannot be written for a mutation. |

### Internal boundaries

| Boundary | Communication | Note |
|----------|---------------|------|
| Presentation ↔ Public verbs | Direct calls, canonical result objects back | No AD types cross up into the menu. |
| Public verbs ↔ Gate | Request object in, result object out | The only write path. |
| Gate ↔ AD write | Direct (private) | Confined to `Adman.AD.Write.*`. |
| Gate/Reports ↔ AD read | Direct (private read wrappers) | Scoped by managed OU. |
| Remote verbs ↔ Remoting | Handle/`Skipped` result | Verbs never branch on transport. |
| Everything ↔ Config/Logging/Audit | Read config; write through the single sink | Defined once, never duplicated per feature. |

---

## Open contradictions in the brief (resolve at requirements)

1. **"No credential storage in v1" (Constraints/Context) vs "credentials stored encrypted in a single config file" (Requirements).** Recommended: pass-through by default; credential save is opt-in, separate, DPAPI, machine-bound (see Configuration).
2. **"Configuration MUST BE encrypted" vs "single config file for easy backup and restore."** DPAPI is not portable. Recommended: split into portable non-secret config + separate optional encrypted credential file.
3. **Built-in critical accounts baseline-protected (krbtgt/Guest/Administrator) — flagged "confirm at requirements."** Recommended: protect by well-known SID by default (Pattern 4); make it configurable but on by default.

---

## Sources

- PSFramework package (version, PS editions, no deps): https://www.powershellgallery.com/packages/PSFramework — HIGH
- PSFramework changelog (active maintenance through 2026; runspaces/config/logging): https://github.com/PowershellFrameworkCollective/psframework/blob/development/PSFramework/changelog.md — HIGH
- PSFramework logging (process-wide, runspace-aware): https://psframework.org/docs/PSFramework/Logging/basics/logging-providers/ — MEDIUM-HIGH
- ConsoleGuiTools / GraphicalTools status (PS 7.2+ only, archived 2026-06-24, feature-complete, successor PSTui): https://github.com/PowerShell/GraphicalTools — HIGH
- CIM session protocols (`-Protocol Dcom|Wsman|Default`; DCOM integrity/privacy defaults; Windows-only): https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/new-cimsessionoption — HIGH
- ShouldProcess / `-WhatIf` / `-Confirm` primitive: https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_cmdletbindingattribute and …/about/about_supportsshouldprocess — HIGH
- Module layout (Public/Private, manifest, explicit export), ModuleBuilder / Sampler: community convention (K. Marquette; Rambling Cookie Monster; github.com/PoshCode/ModuleBuilder; github.com/gaelcolas/Sampler) — MEDIUM (verify at build)
- DPAPI / SecureString machine+user binding (Export-Clixml / ConvertFrom-SecureString): Microsoft SecureString/DPAPI docs — HIGH

> Note: built-in web search/fetch findings are rated LOW by the project confidence seam unless cross-checked; the HIGH ratings above rest on official Microsoft/GitHub/Gallery sources and were corroborated across at least two of them.

---
*Architecture research for: adman (menu-driven PowerShell AD administration toolkit)*
*Researched: 2026-07-10*
