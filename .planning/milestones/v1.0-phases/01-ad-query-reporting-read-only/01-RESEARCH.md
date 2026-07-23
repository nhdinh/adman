# Phase 1: AD Query & Reporting (read-only) - Research

**Researched:** 2026-07-14
**Domain:** PowerShell (5.1 + 7.6 LTS) read-only AD query, scoped search wrappers, canonical result-object schema, three-renderer output layer, and correct AD semantics (timestamps, four account states, recovery posture) for an on-prem Active Directory admin TUI
**Confidence:** HIGH (all load-bearing cmdlet parameter sets and AD semantics verified live against Microsoft Learn / AD schema docs this session; one CONTEXT.md path correction flagged)

> **Tooling note:** the `gsd-tools` research-plan/research-store seam is not executable in this environment (no `node` runtime on PATH), so research used the built-in `WebFetch`/`WebSearch` fallback providers (allowed per tool strategy). Confidence tiers classified per the source hierarchy: Microsoft Learn cmdlet reference + AD schema docs = HIGH; TechNet Wiki / AskDS (Microsoft-authored, archived) = HIGH. No cached digests written to the seam. No new packages are introduced this phase (zero-dependency output layer), so the Package Legitimacy Audit is a no-op confirmation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: `Start-Adman` uses a single flat `while` loop with numbered `Read-Host` input.** No nested submenus, no stack, no state machine, no `$Host.UI.PromptForChoice`. Every action is one keystroke from the top-level list. `Q` at the top-level exits `Start-Adman`; inside an action's input prompts, `B` returns to the top-level menu and `Q` exits the tool entirely (the ONLY reserved single-letter inputs; everything else is numeric). MENU-04: each numbered menu action routes to the same parameterized function a senior calls directly (menu item "Find user" calls `Find-AdmanUser` with parameters prompted interactively; senior runs `Find-AdmanUser -SamAccountName jdoe` directly). The menu NEVER contains read/write logic — it is a thin prompt-and-dispatch layer only. The menu reads one line at a time via `Read-Host`, validates against the current menu item count plus `Q`, and re-prompts on anything else. No hotkey accelerators in v1.
- **D-02: Two typed Public verbs — `Find-AdmanUser` and `Find-AdmanComputer`** — each wraps `Get-ADUser`/`Get-ADComputer -Filter` (NOT `-Identity`) and emits a normalized `[pscustomobject]` result. `Find-AdmanUser` accepts `-Name`, `-SamAccountName`, `-DisplayName` (any one, at least one required); `Find-AdmanComputer` accepts `-Name`. Per-type exact `-Properties` (planner may extend but MUST NOT shrink below the CONTEXT.md starting sets). Both verbs MUST loop over every root in `$script:Config.ManagedOUs` and call `Get-ADUser`/`Get-ADComputer -Filter ... -SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC`. SAFE-07 managed-OU scope on reads: every returned object MUST pass through the existing `Test-AdmanTargetAllowed` step (c) component-boundary scope check before being emitted (deny-list and protected-account checks are NOT applied to reads — those gate mutations — but the DN-under-managed-OU check IS). `-Server $script:Config.DC` on every AD call.
- **D-03: Result-object schema = normalized flat `[pscustomobject]` with a fixed superset of columns, produced by a single Private `ConvertTo-AdmanResult` mapper.** Fixed identity/scope columns (always present, both types): `ObjectType` (`User`|`Computer`), `Name`, `SamAccountName`, `Enabled`, `DistinguishedName`, `ObjectSid`, `ObjectGuid`. Nullable type-specific extras: `DisplayName`, `UserPrincipalName`, `LockedOut`, `PasswordExpired`, `PasswordLastSet`, `AccountExpirationDate` (user-only); `OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`, `IPv4Address`, `DNSHostName` (computer-only); shared: `LastLogonDate`, `whenCreated`, `whenChanged`. All timestamps emitted as `[datetime]`. Never-logged-on sentinel handling lives in the report layer (D-06), NOT the mapper. A Pester contract test pins the emitted property set per type. Renderers consume ONLY this schema — never raw `ADUser`/`ADComputer` types.
- **D-04: Single canonical result-object → three thin renderers.** One `PSCustomObject[]` stream per report; three pure renderers (`Format-AdmanReport` / `Export-AdmanReportCsv` / `Export-AdmanReportHtml`). Zero new dependencies — in-box `Format-Table`/`Out-String`, `Export-Csv -NoTypeInformation`, `ConvertTo-Html`. HTML renderer: static table with embedded CSS via `ConvertTo-Html -Head $cssFragment`. **No JavaScript. No `-CssUri`. No `-Charset`/`-Meta`/`-Transitional`** (PS6+ only, omitted for 5.1 parity). CSV: `Export-Csv -NoTypeInformation -Encoding UTF8`. Console: `Format-Table -AutoSize | Out-String -Width 4096`. Report verbs return raw `PSCustomObject[]`; the MENU or caller decides which renderer to invoke (preserves MENU-04). Optional capability-probed picker: `Out-GridView` on Desktop/interactive, `Out-ConsoleGridView` on Core when the module is present; the hand-rolled console table is the primary renderer and the grid MUST degrade to `Format-Table` on any failure (try/catch).
- **D-05: Single stale/inactive report with two buckets** (RPT-04). Buckets: `Stale` (`lastLogonTimestamp` older than `graceThresholdDays`, but not never-logged-on) and `NeverLoggedOn` (raw `lastLogonTimestamp` of `0`/1601-01-01, cross-checked against `whenCreated` so an account created within the grace window is excluded). One report, one menu entry, one CSV/HTML output; buckets distinguished by a `Bucket` column (`Stale`|`NeverLoggedOn`). Replicated `lastLogonTimestamp` only — never per-DC `lastLogon`.
- **D-06: `Search-ADAccount` for the four account-state renderings (RPT-05).** Disabled, Expired, Locked, PasswordExpired are FOUR distinct states via `Search-ADAccount -AccountDisabled` / `-AccountExpired` / `-LockedOut` / `-PasswordExpired` — NEVER `userAccountControl` bit math. Each state gets its own `Bucket` value on the result object. All `Search-ADAccount` parameter sets accept `-SearchBase`/`-SearchScope`/`-ResultPageSize`/`-Server`/`-UsersOnly`/`-ComputersOnly`.
- **D-07: Self-tuning grace buffer = `max(14, msDS-LogonTimeSyncInterval) + 1 day`.** Preflight read at `Initialize-Adman` time; cache on `$script:Config`; on read failure fall back to 14. Report header states the actual freshness window ("fresh to within N days (sync interval = X)"). Epsilon +1 day (planner may tune to +2; document the choice).
- **D-08: Recovery-posture preflight (RPT-07) at startup.** The existing `Private/Foundation/Get-AdmanRecoveryPosture.ps1` (Phase 0) is invoked during `Initialize-Adman`; its result (Recycle Bin enabled/disabled, FFL, `ms-DS-Logon-Time-Sync-Interval`) is surfaced in the startup capability banner AND cached for the stale report. A `Get-AdmanRecoveryPostureReport` Public verb is also exposed so a senior can call it directly (MENU-04).

### Claude's Discretion

- Concrete Public verb names for the four RPT report types (stale/inactive, account-state, OS/inventory, recovery-posture) — idiomatic names within `Get-Adman*Report` / `Find-Adman*` conventions; lock in `FunctionsToExport`.
- Exact CSS fragment content (colors, typography, zebra striping).
- Whether to add a `-Properties` override / `-AdditionalProperties` additive-only parameter on the Find verbs (default NO).
- Menu item ordering within the flat list (no hotkeys in v1).
- Whether `Find-AdmanUser`/`Find-AdmanComputer` support pipeline input (default NO for v1).
- Exact structure of the `Bucket` column values.

### Deferred Ideas (OUT OF SCOPE)

- Opt-in per-DC `lastLogon` aggregation report (forensic-grade) — deferred; would need RPT-04 amended (currently "never per-DC lastLogon"). **NOTE: the ROADMAP 01-03 plan suggestion mentions an "all-DC `lastLogon` aggregation helper (built once)" — this is SUPERSEDED by D-05/RPT-04 and must NOT be built in Phase 1.** See the Conflict note in Open Questions.
- Hierarchical / hybrid menu with single-letter hotkeys — rejected for Phase 1 (flat while-loop, D-01).
- HTML with inline sortable/filterable JavaScript (e.g., sorttable.js) — rejected (D-04).
- CSS "cards" / dashboard layout for HTML reports — rejected (D-04).
- Templating library (PSHTML / EPS / custom here-string templates) — rejected (zero new dependencies).
- Read-side audit hook — SAFE-03 audits mutations, not reads; discretionary only.
- Pipeline input on the Find verbs — deferred.
- `-AdditionalProperties` additive-only parameter on the Find verbs — deferred.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-01 | Launch `Start-Adman`, see a numbered menu of actions | §Pattern 1 (flat while-loop menu); D-01; `Read-Host` numbered dispatch; Phase 0 `Start-Adman` stub is the file to fill |
| MENU-02 | Select action by number; prompted for required inputs with validation | §Pattern 1 (prompt-and-dispatch; per-action prompt spec); D-01 reserved-input contract (`B`/`Q`) |
| MENU-03 | Navigate back and quit from any prompt | §Pattern 1 (`B` back / `Q` quit reserved inputs); D-01 |
| MENU-04 | Every menu action routes to the same parameterized function a senior calls directly | §Pattern 1 (thin dispatch) + §Pattern 2 (Public read verbs callable directly); D-01/D-04 renderer dispatch |
| USER-01 | Search/view users by name/`sAMAccountName`/displayName, scoped to managed OU | §Pattern 2 (`Find-AdmanUser`); verified `Get-ADUser -Filter` parameter set (accepts `-SearchBase`/`-ResultPageSize`/`-Properties`/`-Server`); SAFE-07 scope re-check |
| COMP-01 | Search/view computers by name, scoped to managed OU | §Pattern 2 (`Find-AdmanComputer`); verified `Get-ADComputer -Filter` parameter set; OS/DNS/IPv4 require `-Properties` |
| RPT-01 | View results as console table (and `Out-GridView` where available) | §Pattern 4 (`Format-AdmanReport`); `Format-Table -AutoSize \| Out-String -Width 4096`; capability-probed grid picker (D-04) |
| RPT-02 | Export any report to CSV (`-NoTypeInformation`) | §Pattern 4 (`Export-AdmanReportCsv`); `Export-Csv -NoTypeInformation -Encoding UTF8` |
| RPT-03 | Export any report to self-contained single-file HTML | §Pattern 4 (`Export-AdmanReportHtml`); verified `ConvertTo-Html -Head` (embedded CSS); NO `-CssUri`/`-Charset`/`-Meta`/`-Transitional` (5.1 parity) |
| RPT-04 | Stale/inactive via replicated `lastLogonTimestamp` + ≥14-day grace + never-logged-on (`0`/1601) bucket; never per-DC `lastLogon` | §Pattern 3 (stale report); verified `lastLogonTimestamp` replication + `msDS-LogonTimeSyncInterval` semantics; D-05/D-07 self-tuning grace |
| RPT-05 | Disabled/Expired/Locked/Password-Expired as four distinct states via `Search-ADAccount` | §Pattern 3 (account-state report); verified `Search-ADAccount` parameter sets all accept `-SearchBase`/`-Server`/`-UsersOnly`/`-ComputersOnly`; D-06 |
| RPT-06 | Inventory report shows OS version + basic computer info (AD attributes) | §Pattern 3 (inventory report); `Get-ADComputer -Properties OperatingSystem,OperatingSystemVersion,...`; D-02 computer property set |
| RPT-07 | Startup preflight reports domain recovery posture (Recycle Bin / FFL) | §Pattern 5 (preflight); existing Phase 0 `Get-AdmanRecoveryPosture`; D-08; **CORRECTION**: sync-interval read location (see §Pattern 5) |
</phase_requirements>

## Summary

Phase 1 builds the **read-only query and reporting surface** of `adman` on top of the Phase 0 safety spine. It ships zero AD writes: every Public verb is either a scoped AD query (`Find-AdmanUser`, `Find-AdmanComputer`, the four `Get-Adman*Report` verbs) or a pure renderer (`Format-AdmanReport`, `Export-AdmanReportCsv`, `Export-AdmanReportHtml`). The architectural contract is a single canonical result-object schema (D-03) produced by one Private mapper (`ConvertTo-AdmanResult`) and consumed by three thin renderers (D-04), so no renderer ever touches a raw `ADUser`/`ADComputer` object and no report verb duplicates formatting logic.

The two areas that carry real AD-semantics risk — and where this research concentrates — are **(a) stale/inactive detection** and **(b) the four account states**. For (a), the correct source is the *replicated* `lastLogonTimestamp` attribute (never per-DC `lastLogon`), gated by a self-tuning grace window derived from `msDS-LogonTimeSyncInterval` (D-05/D-07). For (b), the four states (Disabled, Expired, Locked, PasswordExpired) MUST come from `Search-ADAccount`'s dedicated switches (D-06), never from `userAccountControl` bit math — `Search-ADAccount` already encodes the correct multi-attribute logic (e.g. "locked" is `lockoutTime > 0`, not a UAC bit). All load-bearing cmdlet parameter sets were verified live against Microsoft Learn this session at HIGH confidence.

Two corrections surface for the planner. **First**, CONTEXT.md D-07 states the sync-interval is read from the Configuration partition `Directory Service` object; the AD schema places `msDS-LogonTimeSyncInterval` on the **domain NC head** (`Sam-Domain` class), so the correct read is `(Get-ADDomain).LastLogonReplicationInterval` — see §Pattern 5 and Open Questions. **Second**, ROADMAP 01-03's suggested "all-DC `lastLogon` aggregation helper" directly conflicts with D-05/RPT-04 ("never per-DC lastLogon") and must NOT be built. Both are flagged in Open Questions.

**Primary recommendation:** Implement the four reports as thin query verbs that emit the D-03 schema, route all output through the three D-04 renderers, and keep the menu (D-01) a pure prompt-and-dispatch layer — no read logic in the menu, no formatting logic in the query verbs.

## Architectural Responsibility Map

Phase 1 is a single-tier (client-side PowerShell) tool; there is no browser/SSR/API/CDN split. The meaningful separation is **query layer vs. presentation layer vs. dispatch layer**, all inside the one PowerShell process. The map below assigns each capability to its owning layer so the planner does not blur them (the most likely misassignment is putting formatting in a query verb or read logic in the menu).

| Capability | Primary Layer | Secondary Layer | Rationale |
|------------|---------------|-----------------|-----------|
| Scoped AD user query (USER-01) | Query (`Find-AdmanUser`) | — | Wraps `Get-ADUser -Filter`; loops ManagedOUs; emits D-03 schema only |
| Scoped AD computer query (COMP-01) | Query (`Find-AdmanComputer`) | — | Wraps `Get-ADComputer -Filter`; OS/DNS/IPv4 need `-Properties` |
| Result-object normalization (D-03) | Query (Private `ConvertTo-AdmanResult`) | — | Single mapper; the ONLY producer of the canonical schema |
| SAFE-07 scope re-check on reads | Query (calls `Test-AdmanTargetAllowed` step (c)) | — | Component-boundary DN check per emitted object; deny/protected NOT applied to reads |
| Stale/inactive report (RPT-04) | Query (`Get-AdmanStaleReport`) | — | Replicated `lastLogonTimestamp` + self-tuning grace; two buckets |
| Four account-state report (RPT-05) | Query (`Get-AdmanAccountStateReport`) | — | `Search-ADAccount` switches; never UAC bit math |
| OS/inventory report (RPT-06) | Query (`Get-AdmanInventoryReport`) | — | `Get-ADComputer -Properties OperatingSystem,...` |
| Recovery-posture report (RPT-07) | Query (`Get-AdmanRecoveryPostureReport`) | — | Thin Public wrapper over Phase 0 `Get-AdmanRecoveryPosture` |
| Console rendering (RPT-01) | Presentation (`Format-AdmanReport`) | — | `Format-Table -AutoSize \| Out-String -Width 4096`; capability-probed grid |
| CSV export (RPT-02) | Presentation (`Export-AdmanReportCsv`) | — | `Export-Csv -NoTypeInformation -Encoding UTF8` |
| HTML export (RPT-03) | Presentation (`Export-AdmanReportHtml`) | — | `ConvertTo-Html -Head $cssFragment`; embedded CSS, no JS |
| Menu dispatch (MENU-01..04) | Dispatch (`Start-Adman`) | — | Flat while-loop; thin prompt-and-dispatch; NEVER contains read/format logic |
| Sync-interval + posture preflight (D-07/D-08) | Startup (`Initialize-Adman`) | — | Read once at init, cache on `$script:Config` |

## Standard Stack

Phase 1 introduces **zero new dependencies**. Every capability is met by the in-box PowerShell 5.1/7.6 surface plus the already-pinned Phase 0 stack. This is a hard constraint from D-04 and the project CLAUDE.md ("Console tables / CSV / HTML reports … no packages").

### Core (already present — no install this phase)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Windows PowerShell | 5.1 | Primary runtime (required baseline) | Ships on every supported Windows workstation/server; the language subset Phase 1 writes to [CITED: project CLAUDE.md] |
| PowerShell | 7.6.3 LTS | Modern runtime (supported) | Current LTS (support to 2028-11-14); AD module natively compatible on 1809+ [CITED: project CLAUDE.md] |
| ActiveDirectory module (RSAT) | ships with Windows/RSAT | All AD queries (`Get-ADUser`, `Get-ADComputer`, `Search-ADAccount`, `Get-ADDomain`) | The only Microsoft-supported cmdlet surface for on-prem AD; prerequisite, never bundled [CITED: project CLAUDE.md] |
| PSFramework | 1.14.457 (exact-pinned) | Config + diagnostic/ops logging (`Write-PSFMessage`) | Adopted Phase 0; audit sink stays hand-rolled [VERIFIED: adman.psd1 RequiredModules] |

### Supporting (in-box cmdlets used by the renderers — no install)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Format-Table` / `Out-String` | in-box | Console table renderer | `Format-AdmanReport` (RPT-01) |
| `Export-Csv` | in-box | CSV renderer | `Export-AdmanReportCsv` (RPT-02) |
| `ConvertTo-Html` | in-box | HTML renderer | `Export-AdmanReportHtml` (RPT-03) |
| `Out-GridView` / `Out-ConsoleGridView` | in-box / optional module | Capability-probed picker | Optional sugar on top of `Format-AdmanReport`; MUST degrade to `Format-Table` on any failure (D-04) |

### Alternatives Considered (all rejected — see CONTEXT.md Deferred Ideas)

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ConvertTo-Html -Head $css` (embedded CSS) | PSHTML / EPS / here-string templating | Rejected: adds a dependency for zero safety benefit (D-04) |
| Hand-rolled console table | `Out-ConsoleGridView` as primary | Rejected: Core-only, breaks 5.1 parity (D-04); optional picker only |
| Static HTML table | sorttable.js / inline JS | Rejected: no JavaScript (D-04) |

**Installation:**

```bash
# No new packages this phase. Phase 0 stack already present:
#   PSFramework 1.14.457 (RequiredModules, exact-pinned)
#   ActiveDirectory (RSAT) — prerequisite, installed via Windows Optional Features / Server feature
# Dev/test toolchain (already present from Phase 0): Pester 6.0.0, PSScriptAnalyzer 1.25.0
```

**Version verification:** No new packages to verify. The Phase 0 versions above were confirmed in `adman.psd1` (`RequiredVersion = '1.14.457'` for PSFramework) and the project CLAUDE.md (Pester 6.0.0, PSScriptAnalyzer 1.25.0) this session.

## Package Legitimacy Audit

> Phase 1 installs **no external packages**. The output layer is explicitly zero-dependency (D-04). This audit is therefore a no-op confirmation.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none introduced) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*No packages were discovered via WebSearch or training data for installation this phase. The phase relies entirely on in-box PowerShell cmdlets and the already-verified Phase 0 stack (PSFramework 1.14.457, ActiveDirectory/RSAT), so there is nothing to gate behind a `checkpoint:human-verify`.*

## Architecture Patterns

### System Architecture Diagram

Data flow for a single report (e.g. "Find stale users"). Trace the arrows from the admin's keystroke to the rendered output — every report follows this same pipeline; only the query verb and the renderer change.

```
 Admin keystroke (number)          Startup (once per session)
        |                                    |
        v                                    v
 +--------------+   prompt params    +--------------------+
 | Start-Adman  | -----------------> | Initialize-Adman   |
 | (flat while  |   (Read-Host;      |  - load config     |
 |  loop menu;  |    B=back Q=quit)  |  - sync-interval   |
 |  dispatch    |                    |    preflight (D-07)|
 |  ONLY)       |                    |  - recovery posture|
 +--------------+                    |    (D-08)          |
        |                            +--------------------+
        |  calls the SAME Public verb a senior calls directly (MENU-04)
        v
 +----------------------+   loops over $script:Config.ManagedOUs
 | Query verb           | --------------------------------------+
 | Find-AdmanUser /     |                                       |
 | Find-AdmanComputer / |                                       v
 | Get-Adman*Report     |                         +-------------------------+
 | (read-only; -Server  |                         | AD (RSAT) via DC        |
 |  $script:Config.DC)  |                         | Get-ADUser/Get-ADComputer|
 +----------------------+                         | -Filter -SearchBase $root|
        | raw ADUser/ADComputer                    |  -SearchScope Subtree    |
        v                                          |  -ResultPageSize 1000    |
 +----------------------+                          | Search-ADAccount (states)|
 | ConvertTo-AdmanResult|                          +-------------------------+
 | (Private mapper;     |
 |  D-03 schema ONLY)   |
 +----------------------+
        | canonical [pscustomobject]
        v
 +----------------------+   step (c) component-boundary DN check ONLY
 | Test-AdmanTargetAllowed|  (deny-list / protected NOT applied to reads)
 |  scope re-check (SAFE-07)|
 +----------------------+
        | in-scope PSCustomObject[]
        v
 +---------------------------------------------+
 |  ONE PSCustomObject[] stream per report      |
 +---------------------------------------------+
        |                    |                    |
        v                    v                    v
 +--------------+   +----------------+   +------------------+
 | Format-      |   | Export-        |   | Export-          |
 | AdmanReport  |   | AdmanReportCsv |   | AdmanReportHtml  |
 | (console)    |   | (CSV UTF8)     |   | (embedded CSS)   |
 +--------------+   +----------------+   +------------------+
   RPT-01               RPT-02               RPT-03
```

The menu or the senior caller decides which renderer to invoke (D-04); report verbs return raw `PSCustomObject[]` and never format.

### Recommended Project Structure

Phase 1 adds files under the existing Phase 0 layout (source at repo root, not `src/`):

```
Public/
├── Start-Adman.ps1                    # FILL IN (currently a stub) — flat while-loop menu
├── Find-AdmanUser.ps1                 # NEW — USER-01
├── Find-AdmanComputer.ps1             # NEW — COMP-01
├── Get-AdmanStaleReport.ps1           # NEW — RPT-04 (Stale + NeverLoggedOn buckets)
├── Get-AdmanAccountStateReport.ps1    # NEW — RPT-05 (four states via Search-ADAccount)
├── Get-AdmanInventoryReport.ps1       # NEW — RPT-06 (OS/inventory)
├── Get-AdmanRecoveryPostureReport.ps1 # NEW — RPT-07 (thin wrapper over Phase 0)
├── Format-AdmanReport.ps1             # NEW — RPT-01 console renderer
├── Export-AdmanReportCsv.ps1          # NEW — RPT-02 CSV renderer
└── Export-AdmanReportHtml.ps1         # NEW — RPT-03 HTML renderer
Private/
├── Reporting/
│   ├── ConvertTo-AdmanResult.ps1      # NEW — D-03 single canonical mapper
│   └── Get-AdmanLogonSyncInterval.ps1 # NEW — D-07 sync-interval preflight read
└── Safety/
    └── Test-AdmanTargetAllowed.ps1    # EXISTING (Phase 0) — reuse step (c) for reads
tests/
├── Mocks/ActiveDirectory.psm1         # EXTEND — add Search-ADAccount state switches + -SearchBase/-UsersOnly/-ComputersOnly
├── Find.User.Tests.ps1                # NEW — USER-01 contract + scope
├── Find.Computer.Tests.ps1            # NEW — COMP-01 contract + scope
├── Result.Schema.Tests.ps1            # NEW — D-03 Pester contract test (pins property set per type)
├── Report.Stale.Tests.ps1             # NEW — RPT-04 bucket logic + grace math
├── Report.AccountState.Tests.ps1      # NEW — RPT-05 four states
├── Render.Tests.ps1                   # NEW — RPT-01/02/03 renderer parity (5.1 vs 7)
└── Menu.Tests.ps1                     # NEW — MENU-01..04 dispatch + B/Q reserved inputs
```

### Pattern 1: Flat while-loop menu with thin prompt-and-dispatch (D-01, MENU-01..04)

**What:** A single `while` loop prints a numbered list, reads one line via `Read-Host`, validates against the item count plus the reserved inputs `B`/`Q`, and dispatches to the same Public verb a senior would call directly. The menu contains NO read logic and NO formatting logic — it prompts for parameters, calls the verb, then hands the returned `PSCustomObject[]` to a renderer.

**When to use:** The entire `Start-Adman` entry point. This is the only UI pattern in v1 (no submenus, no `$Host.UI.PromptForChoice`, no hotkeys).

**Example:**

```powershell
# Source: project pattern (D-01); control-flow is standard PowerShell
function Start-Adman {
    [CmdletBinding()]
    param()
    Initialize-Adman   # runs sync-interval + recovery-posture preflight (D-07/D-08)

    $menu = [ordered]@{
        'Find user'            = { param($p) Find-AdmanUser @p }
        'Find computer'        = { param($p) Find-AdmanComputer @p }
        'Stale/inactive report'= { param($p) Get-AdmanStaleReport @p }
        'Account-state report' = { param($p) Get-AdmanAccountStateReport @p }
        'Inventory report'     = { param($p) Get-AdmanInventoryReport @p }
        'Recovery posture'     = { param($p) Get-AdmanRecoveryPostureReport @p }
    }

    while ($true) {
        $i = 1
        foreach ($label in $menu.Keys) { Write-Host ("{0}. {1}" -f $i, $label); $i++ }
        Write-Host 'Q. Quit'
        $choice = (Read-Host 'Select').Trim()
        if ($choice -eq 'Q') { return }                       # top-level Q exits Start-Adman
        $n = 0
        if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $menu.Count) {
            Write-Host 'Invalid selection.'; continue         # re-prompt on anything else
        }
        $label = @($menu.Keys)[$n - 1]
        $params = Read-AdmanActionParams -Action $label       # per-action prompt; B=back, Q=quit
        if ($null -eq $params) { continue }                   # B pressed -> back to top-level
        $results = & $menu[$label] $params                    # SAME verb a senior calls directly
        # renderer chosen by caller (D-04); default console table
        Format-AdmanReport -InputObject $results
    }
}
```

**Reserved-input contract (MENU-03):** `B` and `Q` are the ONLY reserved single-letter inputs. Inside an action's parameter prompts, `B` returns to the top-level menu and `Q` exits the tool entirely; at the top level only `Q` is meaningful. Everything else is numeric.

### Pattern 2: Scoped read wrappers over `Get-ADUser`/`Get-ADComputer -Filter` (D-02, USER-01, COMP-01)

**What:** `Find-AdmanUser` and `Find-AdmanComputer` wrap the `-Filter` parameter set (NOT `-Identity`), loop over every root in `$script:Config.ManagedOUs`, and emit the D-03 schema. Every AD call carries `-SearchBase $root -SearchScope Subtree -ResultPageSize 1000 -Server $script:Config.DC`.

**Why `-Filter` and not `-Identity`:** the `-Identity` parameter set does NOT accept `-SearchBase`/`-SearchScope`/`-ResultPageSize` — it resolves a single object. The `-Filter` set is the one that supports scoped, paged, multi-root search. [VERIFIED: Microsoft Learn Get-ADUser / Get-ADComputer parameter sets — the Filter and LdapFilter sets accept `-SearchBase`, `-SearchScope`, `-ResultPageSize`, `-Properties`, `-Server`; the Identity set does not.]

**Why `-ResultPageSize 1000`:** `Get-ADUser`/`Get-ADComputer` default `-ResultPageSize` is **256**; a managed OU subtree with more than 256 objects would silently page. Setting 1000 (a common AD page size) makes the read deterministic. [VERIFIED: Microsoft Learn — default ResultPageSize is 256 for Get-ADUser/Get-ADComputer.]

**Example:**

```powershell
# Source: project pattern (D-02) + verified Get-ADUser -Filter parameter set
function Find-AdmanUser {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SamAccountName,
        [string]$DisplayName
    )
    if (-not ($Name -or $SamAccountName -or $DisplayName)) {
        throw 'Find-AdmanUser requires at least one of -Name, -SamAccountName, -DisplayName.'
    }

    $filter = if ($SamAccountName) { "sAMAccountName -eq '$SamAccountName'" }
              elseif ($DisplayName) { "displayName -eq '$DisplayName'" }
              else { "Name -like '$Name'" }   # or -eq per planner; document choice

    $results = foreach ($root in @($script:Config.ManagedOUs)) {
        Get-ADUser -Filter $filter `
            -SearchBase $root -SearchScope Subtree `
            -ResultPageSize 1000 -Server $script:Config.DC `
            -Properties DisplayName,UserPrincipalName,LockedOut,PasswordExpired,
                        PasswordLastSet,AccountExpirationDate,LastLogonDate,whenCreated,whenChanged
    }

    foreach ($u in $results) {
        $obj = ConvertTo-AdmanResult -ADObject $u -ObjectType User
        # SAFE-07 scope re-check: step (c) component-boundary DN check ONLY
        $scope = Test-AdmanTargetAllowed -Object $u
        if ($scope.Allowed) { $obj }   # deny-list/protected reasons are NOT applied to reads
    }
}
```

**Note on the scope re-check:** `Test-AdmanTargetAllowed` returns `Allowed = $false` if ANY reason accumulates (gMSA, deny-listed RID, out-of-scope, protected-member). For reads the planner must apply ONLY the step (c) managed-OU boundary — the cleanest implementation is a dedicated `Test-AdmanInManagedScope` helper that runs the DN-boundary logic without the deny/protected checks, rather than reusing the full mutation gate (which would wrongly drop in-scope protected accounts from a read report). Flagged in Open Questions.

### Pattern 3: The four report verbs (RPT-04, RPT-05, RPT-06)

**What:** Each report is a thin query verb that produces the D-03 schema plus a `Bucket` column. No report formats its own output.

**Stale/inactive report (RPT-04, D-05/D-07):** Replicated `lastLogonTimestamp` only — NEVER per-DC `lastLogon`. Two buckets:
- `Stale` — `lastLogonTimestamp` older than the grace threshold, but not never-logged-on.
- `NeverLoggedOn` — raw `lastLogonTimestamp` of `0` (which surfaces as the 1601-01-01 epoch), cross-checked against `whenCreated` so an account created within the grace window is excluded.

The grace threshold is the self-tuning buffer from D-07: `max(14, msDS-LogonTimeSyncInterval) + 1 day`, read once at `Initialize-Adman` and cached on `$script:Config`.

```powershell
# Source: project pattern (D-05/D-07) + verified lastLogonTimestamp semantics
$graceDays = $script:Config.LogonSyncGraceDays   # set at Initialize-Adman (Pattern 5)
$threshold = (Get-Date).AddDays(-$graceDays)
$createdGrace = (Get-Date).AddDays(-$graceDays)

foreach ($u in $allUsers) {
    $raw = $u.lastLogonTimestamp          # Int64 FILETIME; 0 = never logged on
    if ($raw -eq 0 -or $null -eq $raw) {
        if ($u.whenCreated -lt $createdGrace) {   # exclude accounts created inside grace window
            $obj = ConvertTo-AdmanResult -ADObject $u -ObjectType User
            $obj | Add-Member -NotePropertyName Bucket -NotePropertyValue 'NeverLoggedOn' -PassThru
        }
    }
    else {
        $lastLogon = [datetime]::FromFileTimeUtc($raw)
        if ($lastLogon -lt $threshold) {
            $obj = ConvertTo-AdmanResult -ADObject $u -ObjectType User
            $obj | Add-Member -NotePropertyName Bucket -NotePropertyValue 'Stale' -PassThru
        }
    }
}
```

**Why `lastLogonTimestamp` and not `lastLogon`:** `lastLogon` is per-DC and never replicated, so a correct value requires querying every DC and taking the max — exactly the "all-DC aggregation helper" the ROADMAP 01-03 note suggests but D-05/RPT-04 forbids. `lastLogonTimestamp` IS replicated (with the 9–14 day lag the grace window absorbs), so a single-DC read is sufficient and deterministic. [VERIFIED: Microsoft AD schema / TechNet Wiki (Microsoft-authored) — lastLogonTimestamp is replicated; lastLogon is not.]

**Account-state report (RPT-05, D-06):** Four distinct states via `Search-ADAccount` switches — NEVER `userAccountControl` bit math. Each state gets its own `Bucket` value.

```powershell
# Source: project pattern (D-06) + verified Search-ADAccount parameter sets
$common = @{
    SearchBase     = $root
    SearchScope    = 'Subtree'
    ResultPageSize = 1000
    Server         = $script:Config.DC
    UsersOnly      = $true          # or ComputersOnly; both switches exist on all state sets
}
Search-ADAccount -AccountDisabled  @common   # -> Bucket 'Disabled'
Search-ADAccount -AccountExpired   @common   # -> Bucket 'Expired'
Search-ADAccount -LockedOut        @common   # -> Bucket 'Locked'
Search-ADAccount -PasswordExpired  @common   # -> Bucket 'PasswordExpired'
```

All four `Search-ADAccount` state-switch parameter sets accept `-SearchBase`, `-SearchScope`, `-ResultPageSize`, `-Server`, `-UsersOnly`, and `-ComputersOnly`. [VERIFIED: Microsoft Learn Search-ADAccount — each state switch (-AccountDisabled/-AccountExpired/-LockedOut/-PasswordExpired) has a parameter set that includes -SearchBase, -SearchScope, -ResultPageSize, -Server, -UsersOnly, -ComputersOnly. Default ResultPageSize is 256, so set 1000 explicitly.]

**Why not UAC bit math:** "locked out" is not a `userAccountControl` bit — it is `lockoutTime > 0` (the UAC `LOCKOUT` bit 0x10 is famously unreliable and not set by the DC). `Search-ADAccount -LockedOut` encodes the correct `lockoutTime` logic. Similarly "expired" is `accountExpires` vs now, and "password expired" is `pwdLastSet` vs max-password-age — all multi-attribute logic that `Search-ADAccount` already implements correctly. [VERIFIED: Microsoft AD schema — lockoutTime attribute; AskDS (Microsoft-authored) on the unreliable LOCKOUT UAC bit.]

**Inventory report (RPT-06):** `Get-ADComputer -Properties OperatingSystem,OperatingSystemVersion,OperatingSystemServicePack,IPv4Address,DNSHostName` — these are NOT in the default property set and MUST be requested explicitly. [VERIFIED: Microsoft Learn Get-ADComputer — extended properties require -Properties.]

### Pattern 4: Three thin renderers over one schema (D-04, RPT-01/02/03)

**What:** One `PSCustomObject[]` stream per report; three pure renderers. Zero new dependencies.

- **Console (RPT-01):** `Format-Table -AutoSize | Out-String -Width 4096`. The `-Width 4096` prevents column truncation/wrapping on narrow consoles. Optional capability-probed picker: `Out-GridView` on Desktop/interactive, `Out-ConsoleGridView` on Core when `Microsoft.PowerShell.ConsoleGuiTools` is present; the hand-rolled table is primary and the grid MUST degrade to `Format-Table` on any failure (try/catch).
- **CSV (RPT-02):** `Export-Csv -NoTypeInformation -Encoding UTF8`.
- **HTML (RPT-03):** `ConvertTo-Html -Head $cssFragment` with the CSS embedded in the `-Head` fragment. **No JavaScript. No `-CssUri`** (that writes an external `<link>`, breaking the "self-contained single file" requirement). **No `-Charset`/`-Meta`/`-Transitional`** — those parameters are PS6+ only and would break 5.1 parity.

```powershell
# Source: project pattern (D-04) + verified ConvertTo-Html 5.1 parameter surface
function Export-AdmanReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [string]$Title = 'adman report'
    )
    begin {
        $rows = [System.Collections.Generic.List[object]]::new()
        $css = @'
<style>
  body{font-family:Segoe UI,Arial,sans-serif;font-size:13px}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #ccc;padding:4px 8px;text-align:left}
  th{background:#2b579a;color:#fff}
  tr:nth-child(even){background:#f2f2f2}
</style>
'@
    }
    process { $rows.Add($InputObject) }
    end {
        $rows | ConvertTo-Html -Head $css -Title $Title |
            Out-File -FilePath $Path -Encoding UTF8
    }
}
```

[VERIFIED: Microsoft Learn ConvertTo-Html (Windows PowerShell 5.1) — parameters are -Head, -Body, -Title, -CssUri, -As, -Property, -Fragment, -PreContent, -PostContent; there is NO -Charset/-Meta/-Transitional in 5.1 (those are PS6+). -CssUri emits an external stylesheet link, so embedded -Head CSS is the correct self-contained approach.]

### Pattern 5: Startup preflight — sync-interval + recovery posture (D-07, D-08, RPT-07)

**What:** At `Initialize-Adman`, read the logon sync interval once and cache it; invoke the existing Phase 0 `Get-AdmanRecoveryPosture` and surface its result in the startup banner.

**D-07 sync-interval read — CORRECTION to CONTEXT.md path:** CONTEXT.md D-07 states the interval is read from `CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,...`. The AD schema places `msDS-LogonTimeSyncInterval` on the **`Sam-Domain` class = the domain NC head**, NOT the Configuration partition. The correct, simplest read is:

```powershell
# Source: VERIFIED Microsoft AD schema (msDS-LogonTimeSyncInterval is on Sam-Domain / domain NC head)
try {
    $interval = (Get-ADDomain -Server $script:Config.DC).LastLogonReplicationInterval
    # Get-ADDomain.LastLogonReplicationInterval maps to msDS-LogonTimeSyncInterval (days)
} catch {
    $interval = 14   # D-07 fallback on read failure
}
$script:Config.LogonSyncIntervalDays = $interval
$script:Config.LogonSyncGraceDays    = [math]::Max(14, $interval) + 1   # epsilon +1 (planner may tune to +2)
```

[VERIFIED: Microsoft AD schema reference — `msDS-LogonTimeSyncInterval` is an attribute of the `Sam-Domain` class (the domain naming-context head), exposed by `Get-ADDomain` as `LastLogonReplicationInterval`. When "NOT SET", the effective default is 14 days. The update condition is `currentTime - lastLogonTimestamp > (syncInterval - random%of5days)`, producing the documented 9–14 day replication window.] The Configuration-partition `Directory Service` object holds `tombstoneLifetime` (which `Get-AdmanRecoveryPosture` already reads) — that is a different attribute on a different object; do not conflate the two.

**D-08 recovery posture:** `Get-AdmanRecoveryPosture` (Phase 0) returns `{ RecycleBinEnabled, ForestFunctionalLevel, TombstoneLifetime }`, is read-only, and degrades to `$null` on failure (non-blocking). Phase 1 adds a thin Public wrapper `Get-AdmanRecoveryPostureReport` so a senior can call it directly (MENU-04), and surfaces the cached result in the startup banner. The report header should state the actual freshness window: `"fresh to within N days (sync interval = X)"`.

### Anti-Patterns to Avoid

- **Per-DC `lastLogon` aggregation:** Building a helper that queries every DC and maxes `lastLogon`. Forbidden by D-05/RPT-04 (the ROADMAP 01-03 suggestion is superseded). Use replicated `lastLogonTimestamp` + grace window instead.
- **`userAccountControl` bit math for account state:** The `LOCKOUT` bit (0x10) is not set by the DC and is unreliable; "expired"/"password expired" are multi-attribute. Use `Search-ADAccount` switches (D-06).
- **Formatting inside a query verb:** A report verb that calls `Format-Table` or `Export-Csv` itself. Violates D-04 — report verbs return raw `PSCustomObject[]`; the caller picks the renderer.
- **Read logic inside the menu:** `Start-Adman` calling `Get-ADUser` directly. Violates D-01/MENU-04 — the menu is a thin prompt-and-dispatch layer.
- **`ConvertTo-Html -CssUri` for "self-contained" HTML:** Emits an external `<link>`, not an embedded stylesheet. Use `-Head` with inline `<style>` (D-04).
- **Applying deny-list/protected checks to reads:** Dropping in-scope protected accounts from a report. SAFE-07 on reads is the managed-OU boundary (step (c)) ONLY; deny/protected gate mutations, not reads (D-02).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Account-state detection (disabled/expired/locked/pwd-expired) | `userAccountControl` bit math, manual `lockoutTime`/`accountExpires`/`pwdLastSet` comparisons | `Search-ADAccount -AccountDisabled`/`-AccountExpired`/`-LockedOut`/`-PasswordExpired` | The states are multi-attribute and the UAC LOCKOUT bit is unreliable; `Search-ADAccount` encodes the correct logic [VERIFIED: Microsoft AD schema / AskDS] |
| "Last logon" for stale detection | Per-DC `lastLogon` aggregation across all DCs | Replicated `lastLogonTimestamp` + grace window | `lastLogon` never replicates; the aggregation is the forbidden ROADMAP 01-03 helper. `lastLogonTimestamp` replicates and one DC read suffices [VERIFIED: Microsoft AD schema] |
| Console table | Hand-padded column string builder | `Format-Table -AutoSize \| Out-String -Width 4096` | In-box; handles width/alignment; `-Width 4096` prevents wrap [CITED: project CLAUDE.md] |
| CSV export | Manual quoting/escaping of commas/quotes/newlines | `Export-Csv -NoTypeInformation -Encoding UTF8` | Correct RFC-4180 quoting is deceptively hard; in-box cmdlet handles it [CITED: project CLAUDE.md] |
| HTML report | String-concatenated `<table>` builder, templating library | `ConvertTo-Html -Head $cssFragment` | In-box; embedded CSS keeps it self-contained; no dependency [CITED: project CLAUDE.md] |
| DN normalization for scope check | Ad-hoc lowercase/trim | Reuse Phase 0 `ConvertTo-AdmanNormalizedDn` (inside `Test-AdmanTargetAllowed.ps1`) | Already handles unescaping + RDN trimming; component-boundary anchored [VERIFIED: existing Phase 0 code] |

**Key insight:** Every deceptively complex problem in this phase (account state, last-logon staleness, CSV/HTML encoding, DN comparison) is already solved correctly by an in-box cmdlet or an existing Phase 0 helper. The phase's risk is NOT in building these — it is in *reaching for the wrong primitive* (UAC bits, per-DC lastLogon, hand-rolled CSV). The correct move in every case is to call the blessed cmdlet.

## Common Pitfalls

### Pitfall 1: Trusting the `userAccountControl` LOCKOUT bit
**What goes wrong:** A report flags accounts as locked (or not) based on UAC bit 0x10, producing wrong results.
**Why it happens:** The `LOCKOUT` bit is documented but the DC does not reliably set/clear it; real lockout state is `lockoutTime > 0`.
**How to avoid:** Use `Search-ADAccount -LockedOut` (D-06), which reads `lockoutTime`. Never bit-test UAC for lockout.
**Warning signs:** Locked accounts missing from the report, or unlocked accounts flagged.

### Pitfall 2: Per-DC `lastLogon` for stale detection
**What goes wrong:** Stale report shows wildly different "last logon" depending on which DC answered, or requires querying every DC.
**Why it happens:** `lastLogon` is never replicated — each DC holds only the logons it authenticated.
**How to avoid:** Use replicated `lastLogonTimestamp` + the self-tuning grace window (D-05/D-07). Do NOT build the all-DC aggregation helper (superseded ROADMAP 01-03 note).
**Warning signs:** The same account appears stale on one run and fresh on the next; a plan task that enumerates DCs.

### Pitfall 3: Never-logged-on accounts misclassified as stale
**What goes wrong:** Brand-new accounts (never logged on, `lastLogonTimestamp = 0`) flood the "Stale" bucket.
**Why it happens:** A raw `0`/1601-01-01 timestamp is older than any threshold, so a naive age check buckets it as stale.
**How to avoid:** Separate `NeverLoggedOn` bucket; cross-check `whenCreated` so accounts created within the grace window are excluded entirely (D-05).
**Warning signs:** The stale report is dominated by recently-created service/test accounts.

### Pitfall 4: Silent paging at 256 objects
**What goes wrong:** A managed OU with >256 objects returns only the first page; the report silently under-counts.
**Why it happens:** `Get-ADUser`/`Get-ADComputer`/`Search-ADAccount` default `-ResultPageSize` is 256.
**How to avoid:** Set `-ResultPageSize 1000` on every AD read (D-02). [VERIFIED: Microsoft Learn — default ResultPageSize is 256.]
**Warning signs:** Report counts that plateau at a round number; missing objects in large OUs.

### Pitfall 5: Extended computer/user properties come back null
**What goes wrong:** Inventory report shows blank OS/DNS/IPv4 columns.
**Why it happens:** `OperatingSystem`, `OperatingSystemVersion`, `IPv4Address`, `DNSHostName`, `LockedOut`, `PasswordExpired`, `PasswordLastSet`, `LastLogonDate`, `whenCreated`, `whenChanged` are NOT in the default property set.
**How to avoid:** Pass the exact D-02 property list via `-Properties` on every read. [VERIFIED: Microsoft Learn Get-ADComputer/Get-ADUser — extended properties require -Properties.]
**Warning signs:** Empty columns in CSV/HTML that are populated in AD.

### Pitfall 6: `ConvertTo-Html` 5.1/7 parity break
**What goes wrong:** HTML export works on PS7 but throws on 5.1 (or vice versa).
**Why it happens:** `-Charset`, `-Meta`, `-Transitional` are PS6+ only; `-CssUri` writes an external link.
**How to avoid:** Use only the 5.1-safe surface: `-Head $cssFragment -Title`. No `-CssUri`, no PS6+ switches (D-04). [VERIFIED: Microsoft Learn ConvertTo-Html 5.1 parameter list.]
**Warning signs:** `A parameter cannot be found that matches parameter name 'Charset'` on 5.1.

### Pitfall 7: Applying the full mutation gate to reads
**What goes wrong:** In-scope protected accounts (e.g. a nested admin-group member) silently vanish from read reports.
**Why it happens:** Reusing `Test-AdmanTargetAllowed` wholesale applies deny-list + protected-membership reasons, which are meant to gate *mutations*, not reads.
**How to avoid:** On reads apply ONLY the step (c) managed-OU component-boundary check (D-02/SAFE-07). Implement a dedicated scope-only helper rather than the full gate (see Open Questions).
**Warning signs:** A report that omits accounts known to be in the managed OU.

## Code Examples

Verified patterns from official sources (all AD cmdlet parameter sets confirmed against Microsoft Learn this session):

### Scoped, paged AD read (the D-02 primitive)
```powershell
# Source: Microsoft Learn Get-ADUser (Filter parameter set) + project D-02
Get-ADUser -Filter "sAMAccountName -eq 'jdoe'" `
    -SearchBase $root -SearchScope Subtree `
    -ResultPageSize 1000 -Server $script:Config.DC `
    -Properties DisplayName,UserPrincipalName,LockedOut,PasswordExpired,PasswordLastSet,LastLogonDate,whenCreated,whenChanged
```

### Four account states (the D-06 primitive)
```powershell
# Source: Microsoft Learn Search-ADAccount (state-switch parameter sets) + project D-06
Search-ADAccount -LockedOut -SearchBase $root -SearchScope Subtree `
    -ResultPageSize 1000 -Server $script:Config.DC -UsersOnly
```

### Sync-interval preflight (the D-07 corrected read)
```powershell
# Source: Microsoft AD schema (msDS-LogonTimeSyncInterval on Sam-Domain / domain NC head)
$interval = (Get-ADDomain -Server $script:Config.DC).LastLogonReplicationInterval   # days; NOT SET -> 14
$script:Config.LogonSyncGraceDays = [math]::Max(14, $interval) + 1
```

### Self-contained HTML (the D-04 primitive)
```powershell
# Source: Microsoft Learn ConvertTo-Html (5.1 parameter surface) + project D-04
$rows | ConvertTo-Html -Head $cssFragment -Title 'adman report' | Out-File $Path -Encoding UTF8
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `userAccountControl` bit math for account state | `Search-ADAccount` dedicated switches | Long-standing best practice | Correct multi-attribute state logic; avoids the unreliable LOCKOUT bit [VERIFIED: AskDS/Microsoft AD schema] |
| Per-DC `lastLogon` for "last logon" reporting | Replicated `lastLogonTimestamp` + grace window | Long-standing best practice | Single-DC deterministic read; no all-DC fan-out [VERIFIED: Microsoft AD schema] |
| `Get-WmiObject` for any inventory | `Get-CimInstance` / AD attributes | `Get-WmiObject` removed in PS7 | Dual-edition compatibility (not needed this phase — inventory is AD attributes, RPT-06) [CITED: project CLAUDE.md] |
| External CSS file / `-CssUri` for HTML | Embedded `-Head` CSS fragment | D-04 (this phase) | Self-contained single-file HTML; 5.1/7 parity [VERIFIED: Microsoft Learn ConvertTo-Html] |

**Deprecated/outdated:**
- Per-DC `lastLogon` aggregation: superseded by `lastLogonTimestamp` for staleness; the ROADMAP 01-03 "all-DC helper" suggestion is explicitly NOT to be built (D-05/RPT-04).
- `userAccountControl` LOCKOUT bit (0x10) as a lockout signal: unreliable; use `lockoutTime` via `Search-ADAccount -LockedOut`.
- `ConvertTo-Html -CssUri` for "self-contained" reports: emits an external link, not embedded CSS.

## Assumptions Log

> Claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this to identify decisions needing user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Find-AdmanUser` `-Name` matching uses `-like` (wildcard) rather than `-eq` | §Pattern 2 | Low — planner picks; either is defensible. Document the choice; affects whether users must type exact names |
| A2 | The grace-window epsilon is `+1 day` (D-07 allows planner to tune to `+2`) | §Pattern 5 | Low — a 1-day boundary difference in stale classification; D-07 explicitly leaves it to the planner |
| A3 | `Get-ADDomain.LastLogonReplicationInterval` returns the interval in **days** as an integer | §Pattern 5 | Low — if it returns a different unit/type, the `max(14, interval)` math needs a cast; the attribute is documented in days |
| A4 | The `Bucket` column values are the literal strings `Stale`/`NeverLoggedOn`/`Disabled`/`Expired`/`Locked`/`PasswordExpired` | §Pattern 3 | Low — CONTEXT.md leaves exact Bucket values to Claude's discretion; these are the natural names |

**Note:** All load-bearing AD-semantics and cmdlet-parameter claims in this research are `[VERIFIED]` or `[CITED]` — the four `[ASSUMED]` items above are low-risk implementation details within Claude's documented discretion, not architectural choices.

## Open Questions (RESOLVED)

1. **RESOLVED — ROADMAP 01-03 "all-DC `lastLogon` aggregation helper" conflicts with D-05/RPT-04.**
   - What we know: ROADMAP's suggested 01-03 plan mentions building an "all-DC `lastLogon` aggregation helper (built once)". CONTEXT.md D-05 and RPT-04 both state "never per-DC `lastLogon`" and mandate replicated `lastLogonTimestamp` only. The Deferred Ideas list explicitly calls this out as superseded.
   - What's unclear: Nothing technical — the two documents conflict and CONTEXT.md (the later, decision-locking artifact) wins.
   - Recommendation: **Do NOT build the per-DC aggregation helper.** The planner must ignore that ROADMAP line. If a forensic-grade per-DC report is ever wanted, it is a v2 deferred idea requiring an RPT-04 amendment.

2. **RESOLVED — D-07 sync-interval read location (Configuration partition vs. domain NC head).**
   - What we know: CONTEXT.md D-07 says read `msDS-LogonTimeSyncInterval` from `CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,...`. The AD schema places this attribute on the `Sam-Domain` class (domain NC head), exposed by `Get-ADDomain.LastLogonReplicationInterval`. The Configuration-partition `Directory Service` object holds `tombstoneLifetime`, a different attribute.
   - What's unclear: Whether the CONTEXT.md path was a deliberate choice or a slip. The schema is unambiguous that the attribute lives on the domain NC head.
   - Recommendation: Read via `(Get-ADDomain -Server $script:Config.DC).LastLogonReplicationInterval` (domain NC head), fall back to 14 on failure (D-07). Flag the CONTEXT.md path as a documentation correction; the intent (read the sync interval, self-tune the grace) is unchanged.

3. **RESOLVED — Scope-only re-check helper for reads (SAFE-07 step (c) in isolation).**
   - What we know: D-02 mandates the managed-OU boundary check on reads but NOT the deny-list/protected checks. `Test-AdmanTargetAllowed` (Phase 0) accumulates ALL reasons (gMSA, deny-RID, out-of-scope, protected-member) and returns `Allowed = $false` if any is present — so calling it wholesale on reads would wrongly drop in-scope protected accounts.
   - What's unclear: Whether to (a) extract the step (c) DN-boundary logic into a dedicated `Test-AdmanInManagedScope` helper, or (b) add a switch to `Test-AdmanTargetAllowed` that runs only step (c).
   - Recommendation: Option (a) — a small `Test-AdmanInManagedScope` private helper reusing `ConvertTo-AdmanNormalizedDn`, so the read path never invokes the mutation gate. Keeps the mutation gate's semantics untouched (Phase 0 tests stay green). Planner should confirm; either satisfies D-02.

4. **RESOLVED — Existing `Search-ADAccount` mock is insufficient for Phase 1.**
   - What we know: `tests/Mocks/ActiveDirectory.psm1` currently mocks `Search-ADAccount` with signature `param($Identity, $Server)` — it does not accept the state switches (`-AccountDisabled`/`-AccountExpired`/`-LockedOut`/`-PasswordExpired`) or `-SearchBase`/`-UsersOnly`/`-ComputersOnly`.
   - What's unclear: Nothing — the mock must be extended for the RPT-05 unit tests to run offline.
   - Recommendation: Planner adds a Wave 0 task to extend the `Search-ADAccount` mock with the four state switches and the scoping parameters, returning `AdmanMock.*`-tagged objects per state.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| **Framework** | Pester 6.0.0 (project target; dev host currently has 3.4.0) |
| **Config file** | `tests/PesterConfiguration.psd1` or `pester.config.psd1` if present; otherwise none (Wave 0 creates if missing) |
| **Quick run command** | `Invoke-Pester -Path tests/Unit -Output Detailed` |
| **Full suite command** | `Invoke-Pester -Path tests -Output Detailed -ExcludeTag Integration` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MENU-01 | Start-Adman shows numbered menu | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ Wave 0 |
| MENU-02 | Numeric selection + validated prompts | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ Wave 0 |
| MENU-03 | B/Q reserved inputs navigate back/quit | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ Wave 0 |
| MENU-04 | Menu dispatches same Public verbs as senior path | unit | `Invoke-Pester -Path tests/Menu.Tests.ps1` | ❌ Wave 0 |
| USER-01 | Find-AdmanUser scoped to ManagedOUs with exact Properties | unit | `Invoke-Pester -Path tests/Find.User.Tests.ps1` | ❌ Wave 0 |
| COMP-01 | Find-AdmanComputer scoped to ManagedOUs with exact Properties | unit | `Invoke-Pester -Path tests/Find.Computer.Tests.ps1` | ❌ Wave 0 |
| RPT-01 | Console table + Out-GridView fallback | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ Wave 0 |
| RPT-02 | CSV export `-NoTypeInformation` UTF8 | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ Wave 0 |
| RPT-03 | Self-contained single-file HTML | unit | `Invoke-Pester -Path tests/Render.Tests.ps1` | ❌ Wave 0 |
| RPT-04 | Stale/never-logged-on buckets from lastLogonTimestamp | unit | `Invoke-Pester -Path tests/Report.Stale.Tests.ps1` | ❌ Wave 0 |
| RPT-05 | Four account states via Search-ADAccount | unit | `Invoke-Pester -Path tests/Report.AccountState.Tests.ps1` | ❌ Wave 0 |
| RPT-06 | Inventory OS/computer attributes | unit | `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1` | ❌ Wave 0 |
| RPT-07 | Recovery posture preflight | unit | `Invoke-Pester -Path tests/Report.Recovery.Tests.ps1` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `Invoke-Pester -Path tests/Unit -Output Detailed` (fast unit subset; skip Integration)
- **Per wave merge:** Full unit suite against mocked AD (`-ExcludeTag Integration`)
- **Phase gate:** Full unit suite green before `/gsd-verify-work`; integration tests only run in lab

### Wave 0 Gaps

- [ ] `tests/Mocks/ActiveDirectory.psm1` — extend `Search-ADAccount` mock with four state switches and scoping parameters
- [ ] `tests/Find.User.Tests.ps1` — USER-01 contract + scope
- [ ] `tests/Find.Computer.Tests.ps1` — COMP-01 contract + scope
- [ ] `tests/Result.Schema.Tests.ps1` — D-03 Pester contract test pinning property set per type
- [ ] `tests/Report.Stale.Tests.ps1` — RPT-04 bucket logic + grace math
- [ ] `tests/Report.AccountState.Tests.ps1` — RPT-05 four states
- [ ] `tests/Report.Inventory.Tests.ps1` — RPT-06 OS/inventory
- [ ] `tests/Report.Recovery.Tests.ps1` — RPT-07 recovery posture
- [ ] `tests/Render.Tests.ps1` — RPT-01/02/03 renderer parity (5.1 vs 7)
- [ ] `tests/Menu.Tests.ps1` — MENU-01..04 dispatch + B/Q reserved inputs

### Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Interactive `Out-GridView` picker on Desktop edition | RPT-01 | Requires interactive Windows PowerShell Desktop session and GUI | Run `Start-Adman` on a Windows workstation with Desktop edition; select a report and verify grid opens |
| Interactive `Out-ConsoleGridView` picker on PS7 Core | RPT-01 | Requires PS7 Core + ConsoleGuiTools module + interactive session | Run `Start-Adman` in PS7 with `Microsoft.PowerShell.ConsoleGuiTools` installed; verify picker opens |
| Live AD lastLogonTimestamp semantics on multi-DC domain | RPT-04 | Requires a real domain with ≥2 DCs and controlled logon events | Log on as a test user, wait for replication, compare `lastLogonTimestamp` across DCs; verify grace window absorbs lag |

All other Phase 1 behaviors have automated verification via mocked AD unit tests.

## Security Domain

> Required when `security_enforcement` is enabled (absent = enabled). This phase is read-only, so the threat surface is limited to **scope leakage** and **information disclosure**.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth changes this phase |
| V3 Session Management | no | No session state |
| V4 Access Control | yes | Managed-OU scope enforcement (D-02/SAFE-07 step (c)) on every read |
| V5 Input Validation | yes | Filter literal escaping; `Read-Host` input validated against menu item count + reserved letters |
| V6 Cryptography | no | No cryptographic operations |

### Known Threat Patterns for PowerShell/AD read layer

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Read scope leakage (out-of-scope object returned) | Information Disclosure | `-SearchBase` per root + `Test-AdmanInManagedScope` re-check on every emitted object (D-02) |
| Filter injection in `-Filter` string | Tampering | Avoid user input in filters where possible; use LDAP-escaped literals when unavoidable |
| Reporting protected/deny-listed objects | Information Disclosure | Deny-list and protected checks are mutation-only; scope check is the only read gate (D-02) |
| HTML/CSV output contains sensitive paths | Information Disclosure | Renderers consume D-03 schema only; no raw DN/attribute leakage beyond schema columns |

## Sources

### Primary (HIGH confidence)
- Microsoft Learn — `Get-ADUser` / `Get-ADComputer` parameter sets (Filter/Identity), `-ResultPageSize` default 256, extended properties require `-Properties` [CITED]
- Microsoft Learn — `Search-ADAccount` state-switch parameter sets (`-AccountDisabled`, `-AccountExpired`, `-LockedOut`, `-PasswordExpired`) all accept `-SearchBase`/`-SearchScope`/`-ResultPageSize`/`-Server`/`-UsersOnly`/`-ComputersOnly` [CITED]
- Microsoft AD schema reference — `msDS-LogonTimeSyncInterval` on `Sam-Domain` class (domain NC head), replicated `lastLogonTimestamp` semantics, `lastLogon` non-replicated [CITED]
- AskDS (Microsoft-authored) — UAC `LOCKOUT` bit (0x10) is unreliable; real lockout is `lockoutTime > 0` [CITED]

### Secondary (MEDIUM confidence)
- Project CLAUDE.md — PowerShell 5.1/7.6 LTS strategy, CIM-not-WMI, Pester 6.0.0, PSScriptAnalyzer 1.25.0, PlatyPS 1.0.2, zero-dependency renderers [CITED]
- Phase 0 artifacts (00-CONTEXT.md, 00-PATTERNS.md, 00-SUMMARY.md) — established safety spine and patterns to mirror [VERIFIED: repo files]

### Tertiary (LOW confidence)
- None this phase. All load-bearing claims are backed by official Microsoft documentation or existing project decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — PowerShell/RSAT/PSFramework versions already pinned by Phase 0; no new dependencies
- Architecture: HIGH — single-tier PowerShell module with clear query/presentation/dispatch separation
- Pitfalls: HIGH — AD semantics (lastLogonTimestamp replication, Search-ADAccount states, ConvertTo-Html 5.1 parity) verified against Microsoft Learn

**Research date:** 2026-07-14
**Valid until:** 2026-08-14 (stable Microsoft APIs; refresh only if AD module behavior changes or new PowerShell LTS supersedes 7.6)

---

## RESEARCH COMPLETE

**Phase:** 01 - AD Query & Reporting (read-only)
**Confidence:** HIGH

### Key Findings
- Verified `Get-ADUser`/`Get-ADComputer -Filter` parameter sets support scoped, paged, server-pinned reads; `-Identity` does not (D-02).
- Verified `Search-ADAccount` state-switch parameter sets all accept `-SearchBase`/`-Server`/`-UsersOnly`/`-ComputersOnly` (D-06/RPT-05).
- `lastLogonTimestamp` is the only correct source for stale detection; per-DC `lastLogon` aggregation is forbidden by D-05/RPT-04 and the ROADMAP 01-03 suggestion is superseded.
- `msDS-LogonTimeSyncInterval` lives on the domain NC head (`Sam-Domain`), exposed as `(Get-ADDomain).LastLogonReplicationInterval`; the CONTEXT.md Configuration-partition path is a documentation correction.
- `ConvertTo-Html -Head $cssFragment` is the 5.1-safe self-contained HTML approach; `-CssUri`/`-Charset`/`-Meta`/`-Transitional` are disallowed for parity (D-04).

### File Created
`.planning/phases/01-ad-query-reporting-read-only/01-RESEARCH.md`

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | In-box PowerShell/RSAT + Phase 0 stack; zero new dependencies |
| Architecture | HIGH | Clear query/presentation/dispatch layers with D-03 canonical schema |
| Pitfalls | HIGH | Microsoft Learn + AD schema verification for all load-bearing semantics |

### Open Questions (all RESOLVED)
1. RESOLVED — ROADMAP 01-03 all-DC `lastLogon` helper conflicts with D-05/RPT-04 — planner must ignore.
2. RESOLVED — D-07 sync-interval read location — use `(Get-ADDomain).LastLogonReplicationInterval` (domain NC head) instead of Configuration-partition path.
3. RESOLVED — Scope-only helper — planner chooses `Test-AdmanInManagedScope` extraction vs. adding a switch to `Test-AdmanTargetAllowed`.
4. RESOLVED — `Search-ADAccount` mock must be extended in Wave 0 for RPT-05 unit tests.

### Ready for Planning
Research complete. Planner can now create PLAN.md files.
