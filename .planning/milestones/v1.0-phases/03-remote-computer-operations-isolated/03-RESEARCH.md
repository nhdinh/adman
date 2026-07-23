# Phase 3: Remote Computer Operations (isolated) - Research

**Researched:** 2026-07-16
**Domain:** PowerShell remoting (WinRM/WSMan/CIM/DCOM), cross-edition 5.1/7.6
**Confidence:** HIGH (core cmdlet signatures verified against local Windows PowerShell 5.1 help; transport/firewall behavior cross-checked against Microsoft docs and established community sources)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Remote queries auto-enrich `Get-AdmanInventoryReport`.** No separate remote report verb in Phase 3.
- **D-02: Fleet probes run serially with a per-host timeout cap and a total report time cap.**
  - Add config key `transport.timeouts.perHostProbeCap` (default **10 seconds**).
  - Add config key `transport.timeouts.totalInventoryRemoteCap` (default **120 seconds**).
- **D-03: Skipped-host summary is a single `Write-Warning`.**
- **D-04: Cache only the winning transport name per host, process-only, keyed by uppercase computer name.**
  - Cache values: `'WinRM'`, `'CimWsman'`, `'CimDcom'`, `'Skipped'`.
  - Do not reuse live `CimSession` or `PSSession` objects.
- **D-05: Ladder order is fixed:**
  1. `Test-WSMan` → `'WinRM'`.
  2. `New-CimSessionOption -Protocol Wsman` + `New-CimSession` → `'CimWsman'`.
  3. `New-CimSessionOption -Protocol Dcom` + `New-CimSession` → `'CimDcom'`.
  4. Else `'Skipped'`.
- **D-06: `Skipped` is a first-class non-error outcome.**
- **D-07: Phase 3 operations are local-on-target by design; no second hop is attempted.**
  - No CredSSP.
  - RBCD and JEA are documented as future alternatives only.
  - Accounts flagged *"Account is sensitive and cannot be delegated"* are unaffected.

### Claude's Discretion

- Exact Public verb surface: `Get-AdmanInventoryReport` keeps its existing signature; remote enrichment is automatic. Thin Private `Connect-AdmanTarget` + `Invoke-AdmanRemoteQuery` are the new internals.
- Menu item text update.
- Caching implementation detail (hashtable vs. PSFramework config cache).
- Uptime representation as `[TimeSpan]`.
- Error translation strings.
- Integration with existing capability probe: `Test-AdmanCapability` unchanged.

### Deferred Ideas (OUT OF SCOPE)

- Remote live actions (`RMT-V01`).
- Parallel fleet probes (Phase 5 if needed).
- Persistent transport cache.
- CredSSP transport option.
- RBCD/JEA implementation.
- Read-side audit for inventory reports.
- Separate remote report verb / dashboard.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RMT-01 | Tool probes each target with a WinRM → CIM/WSMan → CIM/DCOM → skip ladder and caches the working transport per host. | Ladder implemented with `Test-WSMan`, `New-CimSessionOption -Protocol Wsman`, and `New-CimSessionOption -Protocol Dcom`; process-only hashtable cache keyed by uppercase computer name. |
| RMT-02 | Unreachable hosts are reported as `Skipped` (first-class non-error); menu never hangs on dead hosts (short timeouts). | Per-host cap (`perHostProbeCap`) + total report cap (`totalInventoryRemoteCap`); serial probes are the cross-edition baseline; `Test-WSMan` in 5.1 has no native timeout and must be wrapped. |
| RMT-03 | Admin can run read-only remote queries (online/OS/uptime/logged-on user) that enrich inventory. | `Win32_OperatingSystem` (Caption, Version, CSDVersion, LastBootUpTime) and `Win32_ComputerSystem` (UserName) queried via `Get-CimInstance -CimSession`. |
| RMT-04 | Remote operations handle the double-hop by design (avoid second hop preferred; RBCD/JEA over CredSSP; never for "sensitive, cannot be delegated" accounts). | Queries are local-on-target CIM only; no CredSSP; structural guard refuses second-hop operations; RBCD/JEA documented for future live-action second-hop needs. |
</phase_requirements>

## Summary

Phase 3 adds a read-only remote-enrichment pass to the existing `Get-AdmanInventoryReport` fleet view. The work is quarantined behind one connector: a **WinRM → CIM/WSMan → CIM/DCOM → skip** transport ladder that probes each host, caches only the winning transport name for the process, and never lets a dead host hang the menu. The ladder must behave identically on **Windows PowerShell 5.1** and **PowerShell 7.6 LTS**, which means writing to the lowest common denominator: 5.1 has no `ForEach-Object -Parallel`, no `Test-WSMan` timeout parameters, and no ternary/null-coalescing operators.

The most important implementation facts are:

1. **`Test-WSMan` on Windows PowerShell 5.1 has no timeout parameters** [VERIFIED: local PS 5.1 help]. A per-host cap must be enforced with an external timeout wrapper (e.g., `Start-Job` + `Wait-Job -Timeout` or a runspace with `AsyncWaitHandle.WaitOne`).
2. **CIM cmdlets default to WSMAN when `-ComputerName` is used** [VERIFIED: local PS 5.1 help]. The "CIM fallback" trap is real: without `New-CimSessionOption -Protocol Dcom`, a failed WinRM path will fail CIM too. The ladder must explicitly create Wsman and Dcom sessions.
3. **Serial probing with per-host + total caps is the correct Phase 3 design.** Parallel can be revisited in Phase 5 if fleet size demands it; premature runspace complexity is a deferred idea.
4. **All Phase 3 queries are local-on-target CIM reads** (`Win32_OperatingSystem`, `Win32_ComputerSystem`). This avoids the double-hop by design. No CredSSP. RBCD/JEA are documented for future live-action second-hop needs only.

**Primary recommendation:** Implement the connector as two Private functions — `Connect-AdmanTarget` (ladder + cache, returns transport name or `'Skipped'`) and `Invoke-AdmanRemoteQuery` (runs the two CIM queries via a transient session, returns remote-enrichment data). Extend `Get-AdmanInventoryReport` to call them per row after the AD mapping. Add the two timeout keys to `config/adman.{schema,defaults}.json`. Update the menu label. No new external dependencies are required.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Transport ladder (WinRM/CIM/DCOM probe) | Connector (`Private/Remoting/Connect-AdmanTarget.ps1`) | `Get-AdmanInventoryReport` | Isolated so AD/report code never branches on transport. |
| Per-host transport cache | Connector module scope (`$script:TransportCache`) | — | Process-only, keyed by uppercase computer name; not a session pool. |
| Remote query execution | Connector (`Private/Remoting/Invoke-AdmanRemoteQuery.ps1`) | — | Runs local-on-target CIM classes only; structural second-hop guard lives here. |
| Inventory report enrichment | `Public/Get-AdmanInventoryReport.ps1` | Connector | AD rows are mapped first, then remote columns are merged in. |
| Timeout policy | Config (`transport.timeouts.*`) | Connector | Caps read from `$script:Config`; defaults in `adman.defaults.json`. |
| Error translation | Connector | — | Raw WinRM/CIM/DCOM exceptions converted to short operator strings. |
| Menu surfacing | `Private/Menu/Get-AdmanMenuDefinition.ps1` | — | Label update only; no new menu item. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Microsoft.WSMan.Management` (`Test-WSMan`) | built-in (5.1) / built-in (PS7) | WinRM service reachability probe | Native cmdlet; distinguishes WinRM availability before CIM attempts. [VERIFIED: local PS 5.1 help] |
| `CimCmdlets` (`New-CimSession`, `New-CimSessionOption`, `Get-CimInstance`, `Remove-CimSession`) | built-in (5.1) / built-in (PS7) | Transient CIM sessions and queries | Cross-edition; replaces removed `Get-WmiObject`; explicit `-Protocol Dcom` is the real no-WinRM fallback. [VERIFIED: local PS 5.1 help] |
| `Microsoft.PowerShell.Utility` (`Write-Warning`, `Start-Job`, `Wait-Job`) | built-in | Timeout wrapper for `Test-WSMan` on 5.1; skipped-host summary | No dependencies; works on both editions. [VERIFIED: local PS 5.1 help] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `[runspacefactory]` / `[powershell]` | .NET runtime | Optional low-level timeout/cancellation | Only if `Start-Job` overhead proves unacceptable in Phase 5; Phase 3 uses serial + job wrapper. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Serial probes + `Start-Job` timeout wrapper | `ForEach-Object -Parallel` | Core-only (PS 7+); breaks 5.1 baseline. Defer to Phase 5. |
| `Test-WSMan` | `Test-NetConnection -Port 5985` | Faster, but only tests TCP reachability, not the WS-Management Identify request; may falsely report WinRM ready. Keep `Test-WSMan` as the authoritative probe. |
| Cache live `CimSession` objects | Cache transport name only | Live sessions are fragile across firewall/sleep/trust changes and require reconnect logic. User explicitly rejected this (D-04). |
| `Get-WmiObject` | `Get-CimInstance` | `Get-WmiObject` is removed in PS7 and deprecated in 5.1; violates CLAUDE.md "What NOT to Use." |

**Installation:**

```powershell
# No new external packages required. Verify built-in modules are present:
Get-Command Test-WSMan, New-CimSession, New-CimSessionOption, Get-CimInstance, Remove-CimSession
```

**Version verification:**

```powershell
# These cmdlets ship with Windows/RSAT; no gallery install needed.
Get-Help Test-WSMan -Parameter *          # Windows PowerShell 5.1: no timeout params
Get-Help New-CimSession -Parameter *      # confirms -OperationTimeoutSec, -SessionOption
Get-Help New-CimSessionOption -Parameter * # confirms -Protocol Dcom|Wsman|Default
Get-Help Get-CimInstance -Parameter *     # confirms -CimSession, -OperationTimeoutSec
```

## Package Legitimacy Audit

> Required whenever this phase installs external packages. Phase 3 uses only built-in PowerShell/OS modules; no new gallery or binary dependencies are introduced.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `CimCmdlets` | OS component | N/A | N/A | Microsoft Windows | N/A | Built-in; no install action. |
| `Microsoft.WSMan.Management` | OS component | N/A | N/A | Microsoft Windows | N/A | Built-in; no install action. |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
Operator selects "Fleet inventory report (with remote enrichment)"
            │
            ▼
Public: Get-AdmanInventoryReport
   ├── AD read loop (existing): Get-ADComputer per ManagedOU
   ├── ConvertTo-AdmanResult -ObjectType Computer (existing)
   └── For each computer row:
            │
            ▼
Private: Connect-AdmanTarget -ComputerName <name>
   ├── Cache hit? → return cached transport name
   ├── Cache miss:
   │     1. Test-WSMan (with per-host timeout wrapper on 5.1)
   │     2. New-CimSessionOption -Protocol Wsman + New-CimSession
   │     3. New-CimSessionOption -Protocol Dcom + New-CimSession
   │     4. All fail → 'Skipped'
   └── Cache and return transport name ('WinRM' | 'CimWsman' | 'CimDcom' | 'Skipped')
            │
            ▼
Private: Invoke-AdmanRemoteQuery -ComputerName <name> -Transport <name>
   ├── If transport == 'Skipped' → return empty remote fields
   ├── Build transient CimSession for the cached transport
   ├── Get-CimInstance Win32_OperatingSystem (Caption, Version, CSDVersion, LastBootUpTime)
   ├── Get-CimInstance Win32_ComputerSystem (UserName)
   ├── Compute Uptime = (Get-Date) - LastBootUpTime
   └── Remove-CimSession
            │
            ▼
Public: Get-AdmanInventoryReport merges remote fields into row
   ├── Transport, RemoteOS, Uptime, LoggedOnUser
   └── Tracks skipped count
            │
            ▼
Single Write-Warning: "Remote enrichment skipped for N of M hosts."
```

### Recommended Project Structure

```
Private/
└── Remoting/
    ├── Connect-AdmanTarget.ps1        # ladder + cache
    ├── Invoke-AdmanRemoteQuery.ps1    # local-on-target CIM queries
    └── Test-AdmanTransportError.ps1   # raw exception → operator string (optional helper)
Public/
└── Get-AdmanInventoryReport.ps1       # extended with remote-enrichment pass
```

### Pattern 1: Transport Ladder with Explicit Protocol Options

**What:** Probe each target in fixed order, explicitly forcing WSMAN vs DCOM so the fallback is genuine and not "CIM defaulting to WSMAN again."

**When to use:** Every remote target in Phase 3.

**Example:**

```powershell
# Source: Microsoft Learn New-CimSessionOption + local PS 5.1 help verification
function Connect-AdmanTarget {
    param([string]$ComputerName)

    $key = $ComputerName.ToUpperInvariant()
    if ($script:TransportCache.ContainsKey($key)) { return $script:TransportCache[$key] }

    $cap = $script:Config.transport.timeouts.perHostProbeCap
    $transport = 'Skipped'

    # Step 1: WinRM (Test-WSMan). On 5.1 this has no timeout parameter;
    # wrap in a job with Wait-Job -Timeout $cap.
    try {
        $result = Test-WSManWithTimeout -ComputerName $ComputerName -TimeoutSeconds $cap
        if ($result) { $transport = 'WinRM' }
    } catch { $transport = 'Skipped' }

    # Step 2: CIM over WSMAN (explicit protocol)
    if ($transport -eq 'Skipped') {
        try {
            $opt = New-CimSessionOption -Protocol Wsman
            $sess = New-CimSession -ComputerName $ComputerName -SessionOption $opt `
                -OperationTimeoutSec $cap -ErrorAction Stop
            Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue
            $transport = 'CimWsman'
        } catch { }
    }

    # Step 3: CIM over DCOM (explicit protocol)
    if ($transport -eq 'Skipped') {
        try {
            $opt = New-CimSessionOption -Protocol Dcom
            $sess = New-CimSession -ComputerName $ComputerName -SessionOption $opt `
                -OperationTimeoutSec $cap -ErrorAction Stop
            Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue
            $transport = 'CimDcom'
        } catch { }
    }

    $script:TransportCache[$key] = $transport
    return $transport
}
```

### Pattern 2: Local-on-Target Query Only

**What:** Every Phase 3 CIM query reads classes that live only on the target (`Win32_OperatingSystem`, `Win32_ComputerSystem`). No query reaches a third machine.

**When to use:** All Phase 3 remote reads.

**Example:**

```powershell
# Source: Win32_OperatingSystem / Win32_ComputerSystem WMI class docs
function Invoke-AdmanRemoteQuery {
    param(
        [string]$ComputerName,
        [ValidateSet('WinRM','CimWsman','CimDcom','Skipped')][string]$Transport
    )

    if ($Transport -eq 'Skipped') {
        return [pscustomobject]@{
            RemoteOS       = $null
            Uptime         = $null
            LoggedOnUser   = $null
        }
    }

    $protocol = if ($Transport -eq 'WinRM') { 'Wsman' } else { ($Transport -replace '^Cim','') }
    $opt = New-CimSessionOption -Protocol $protocol
    $cap = $script:Config.transport.timeouts.perHostProbeCap
    $sess = New-CimSession -ComputerName $ComputerName -SessionOption $opt `
        -OperationTimeoutSec $cap -ErrorAction Stop

    try {
        $os  = Get-CimInstance -CimSession $sess -ClassName Win32_OperatingSystem `
            -OperationTimeoutSec $cap -ErrorAction Stop
        $cs  = Get-CimInstance -CimSession $sess -ClassName Win32_ComputerSystem `
            -OperationTimeoutSec $cap -ErrorAction Stop

        $remoteOS = @($os.Caption, $os.Version, $os.CSDVersion) -join ' '
        $uptime   = if ($os.LastBootUpTime) { (Get-Date) - $os.LastBootUpTime } else { $null }

        return [pscustomobject]@{
            RemoteOS     = $remoteOS.Trim()
            Uptime       = $uptime          # [TimeSpan]
            LoggedOnUser = $cs.UserName     # DOMAIN\User or empty
        }
    }
    finally {
        Remove-CimSession -CimSession $sess -ErrorAction SilentlyContinue
    }
}
```

### Pattern 3: Per-Host + Total Cap Enforcement

**What:** Two independent timers bound the report: each host may consume at most `transport.timeouts.perHostProbeCap` seconds, and the whole remote-enrichment pass may consume at most `transport.timeouts.totalInventoryRemoteCap` seconds.

**When to use:** Inside `Get-AdmanInventoryReport` remote-enrichment loop.

**Example:**

```powershell
$perHostCap = $script:Config.transport.timeouts.perHostProbeCap
$totalCap   = $script:Config.transport.timeouts.totalInventoryRemoteCap
$stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
$skipped    = 0

foreach ($row in $results) {
    if ($stopwatch.Elapsed.TotalSeconds -ge $totalCap) {
        $skipped++
        $row | Add-Member -NotePropertyName Transport -NotePropertyValue 'Skipped' -Force
        continue
    }

    $transport = Connect-AdmanTarget -ComputerName $row.Name
    if ($transport -eq 'Skipped') { $skipped++ }

    $remote = Invoke-AdmanRemoteQuery -ComputerName $row.Name -Transport $transport
    $row | Add-Member -NotePropertyName Transport      -NotePropertyValue $transport       -Force
    $row | Add-Member -NotePropertyName RemoteOS       -NotePropertyValue $remote.RemoteOS -Force
    $row | Add-Member -NotePropertyName Uptime         -NotePropertyValue $remote.Uptime   -Force
    $row | Add-Member -NotePropertyName LoggedOnUser   -NotePropertyValue $remote.LoggedOnUser -Force
}

if ($skipped -gt 0) {
    Write-Warning "Remote enrichment skipped for $skipped of $($results.Count) hosts."
}
```

### Anti-Patterns to Avoid

- **Reusing live `CimSession`/`PSSession` objects across queries:** User explicitly rejected this (D-04). Session lifetime across firewall/sleep/trust changes is fragile; reconnect logic is out of scope.
- **`Get-CimInstance -ComputerName` without an explicit protocol:** Defaults to WSMAN, making the "CIM fallback" silently identical to the WinRM path. [CITED: Microsoft Learn / PowerShell Team CIM tips]
- **`Test-WSMan` without a timeout wrapper on 5.1:** The cmdlet has no timeout parameter in 5.1 and can hang for minutes on dead hosts. [VERIFIED: local PS 5.1 help]
- **Using `Get-WmiObject` or `wmic.exe`:** Removed in PS7 / being removed from Windows; violates CLAUDE.md.
- **Trying CredSSP to "fix" double-hop:** Explicitly rejected for v1 due to credential-theft risk (D-07).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Protocol detection | Custom socket probes | `Test-WSMan` + `New-CimSession` with explicit `-Protocol` | Microsoft already implements WS-Management Identify and CIM protocol negotiation; a raw TCP check lies about WinRM readiness. |
| OS/uptime/logged-on-user query | Direct registry / event-log parsing | `Get-CimInstance Win32_OperatingSystem` / `Win32_ComputerSystem` | Standard WMI/CIM classes with stable schemas since Windows XP; parsing is OS-version-fragile. |
| Uptime calculation | `Get-Date` minus boot time with manual string formatting | `(Get-Date) - $os.LastBootUpTime` → `[TimeSpan]` | CIM returns `DateTime`; subtraction yields a `TimeSpan` automatically, which renderers can format. |
| Timeout wrapper for `Test-WSMan` on 5.1 | Complex runspace pool in Phase 3 | `Start-Job` + `Wait-Job -Timeout` | Sufficient for serial probes; keeps the phase focused. Runspace pools can be revisited in Phase 5 if fleet size demands it. |
| Second-hop credential forwarding | CredSSP client/server config | Local-on-target queries (Phase 3); RBCD/JEA documented for future live actions | CredSSP exposes reusable credentials on the hop host. RBCD/JEA require Active Directory or endpoint configuration that is out of Phase 3 scope. |

**Key insight:** The connector should be a thin orchestrator over built-in cmdlets. The hard part is not the cmdlet calls; it is the timeout discipline, the explicit protocol distinction, and treating `Skipped` as a first-class outcome.

## Common Pitfalls

### Pitfall 1: `Test-WSMan` hangs on dead hosts in PowerShell 5.1

**What goes wrong:** `Test-WSMan -ComputerName deadhost` can block for a long time (default WinHTTP/WS-Man timeouts, not abortable by cmdlet parameter).

**Why it happens:** Windows PowerShell 5.1's `Test-WSMan` has no `-ConnectionTimeout` or `-OperationTimeout` parameter [VERIFIED: local PS 5.1 help]. The underlying WinRM stack retries and waits.

**How to avoid:** Wrap the call in a job with a hard timeout:

```powershell
function Test-WSManWithTimeout {
    param([string]$ComputerName, [int]$TimeoutSeconds = 10)
    $job = Start-Job -ScriptBlock {
        param($cn)
        Test-WSMan -ComputerName $cn -ErrorAction SilentlyContinue
    } -ArgumentList $ComputerName

    $completed = $job | Wait-Job -Timeout $TimeoutSeconds
    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job -ErrorAction SilentlyContinue
        return $result
    }
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -ErrorAction SilentlyContinue
    return $null
}
```

**Warning signs:** Menu appears frozen during inventory report; long gaps between host probes; CPU idle but prompt unresponsive.

### Pitfall 2: "CIM fallback" silently uses WSMAN again

**What goes wrong:** After WinRM fails, a naive `Get-CimInstance -ComputerName` or `New-CimSession -ComputerName` still fails with the same WSMAN error.

**Why it happens:** CIM cmdlets default to the WSMAN protocol for remote targets. The real fallback is DCOM, but it must be requested explicitly with `New-CimSessionOption -Protocol Dcom`. [CITED: Microsoft Learn New-CimSessionOption; PowerShell Team CIM tips]

**How to avoid:** Always pair `New-CimSession` with a `New-CimSessionOption` object whose `-Protocol` matches the ladder step: `Wsman` for step 2, `Dcom` for step 3.

**Warning signs:** WinRM failure and CIM failure produce identical WSMAN error text; no `0x800706BA` (RPC unavailable) appears on the DCOM step.

### Pitfall 3: `New-CimSession -OperationTimeoutSec` is per-operation, not per-host total

**What goes wrong:** Setting `OperationTimeoutSec = 10` on `New-CimSession` does not bound the entire ladder; each query inside the session can take up to 10 seconds, so a host could consume 20+ seconds.

**Why it happens:** `-OperationTimeoutSec` applies to each CIM operation, not the sum of operations. [VERIFIED: local PS 5.1 help]

**How to avoid:** Use the per-host cap as the ceiling for the entire ladder. Keep CIM queries to the minimum two classes; do not chain multiple queries per transport. Better: measure elapsed time per host in the caller and mark `Skipped` if the cap is exceeded.

**Warning signs:** Report takes longer than `perHostProbeCap * hostCount`; individual hosts spend time on multiple CIM classes.

### Pitfall 4: Double-hop accidentally introduced by a future query

**What goes wrong:** A later developer adds a query like `Get-CimInstance -ClassName Win32_Share` or invokes AD cmdlets inside the remote script block, and it fails with `ANONYMOUS LOGON` / `Access is denied`.

**Why it happens:** Kerberos does not forward credentials to a third machine from the first hop. [CITED: PITFALLS.md Pitfall 8; community double-hop guidance]

**How to avoid:** Add a structural guard in `Invoke-AdmanRemoteQuery` that accepts only an allow-list of local-only CIM classes. If a query would reach a third machine, throw `"Second-hop operation not supported in adman remote queries."`

**Warning signs:** A remote query works locally on the operator's machine but fails through the tool; Security logs show `NT AUTHORITY\ANONYMOUS LOGON`.

### Pitfall 5: `Win32_ComputerSystem.UserName` is console-only and often empty

**What goes wrong:** Servers accessed only via RDP show an empty `UserName`; operators think the query failed.

**Why it happens:** `Win32_ComputerSystem.UserName` returns the user logged into the interactive console session (session 0). It does not enumerate RDP or other sessions. [CITED: community sources; GitHub PowerShell issue #17371]

**How to avoid:** Document the limitation in help text and emit `$null`/`''` gracefully. Do not fall back to `quser` or `qwinsta` in Phase 3 (out of scope; also adds parsing fragility).

**Warning signs:** Most workstations show a user but most servers show blank `LoggedOnUser`; no error is reported.

### Pitfall 6: Treating "RPC server is unavailable" as a code bug instead of a firewall fact

**What goes wrong:** Operators report `0x800706BA` / "RPC server is unavailable" as a tool failure when DCOM is simply blocked.

**Why it happens:** DCOM requires TCP 135 plus a dynamic RPC range (49152-65535 by default). Host firewalls commonly block this. [CITED: Microsoft Learn / community DCOM port guidance]

**How to avoid:** Translate the error to an actionable string: `"RPC server unavailable (DCOM firewall — ports 135 + dynamic RPC)"`. Treat the host as `Skipped`.

**Warning signs:** WinRM-probed hosts succeed; DCOM-probed hosts produce `0x800706BA` consistently.

## Code Examples

### Test-WSMan with timeout wrapper (PowerShell 5.1)

```powershell
# Source: local PS 5.1 help (no native timeout) + community pattern
function Test-WSManWithTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [int]$TimeoutSeconds = 10
    )

    $job = Start-Job -ScriptBlock {
        param($cn)
        Test-WSMan -ComputerName $cn -ErrorAction SilentlyContinue
    } -ArgumentList $ComputerName

    $completed = $job | Wait-Job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
    if ($completed) {
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -ErrorAction SilentlyContinue
        return $result
    }

    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -ErrorAction SilentlyContinue
    return $null
}
```

### Explicit WSMAN and DCOM CIM sessions

```powershell
# Source: Microsoft Learn New-CimSessionOption + local PS 5.1 help
$cap = 10

# WSMAN
$wsmanOpt = New-CimSessionOption -Protocol Wsman
$wsmanSess = New-CimSession -ComputerName 'PC01' -SessionOption $wsmanOpt `
    -OperationTimeoutSec $cap -ErrorAction Stop

# DCOM
$dcomOpt = New-CimSessionOption -Protocol Dcom
$dcomSess = New-CimSession -ComputerName 'PC01' -SessionOption $dcomOpt `
    -OperationTimeoutSec $cap -ErrorAction Stop

Remove-CimSession -CimSession $wsmanSess, $dcomSess -ErrorAction SilentlyContinue
```

### Uptime as TimeSpan

```powershell
# Source: Win32_OperatingSystem class docs
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
# $uptime is [System.TimeSpan], e.g., 7.12:34:56
```

### Error translation helper

```powershell
# Source: community CIM exception handling
function Convert-AdmanRemoteError {
    param([System.Exception]$Exception)

    $msg = $Exception.Message
    if ($msg -match '0x800706BA|RPC server is unavailable') {
        return 'RPC server unavailable (DCOM firewall)'
    }
    if ($msg -match '0x80070005|Access is denied') {
        return 'Access denied'
    }
    if ($msg -match '0x8009030e|ANONYMOUS LOGON') {
        return 'Double-hop blocked'
    }
    if ($msg -match 'WinRM cannot complete the operation|2150859046') {
        return 'WinRM unreachable'
    }
    if ($msg -match 'The RPC server is unavailable') {
        return 'RPC server unavailable (DCOM firewall)'
    }
    return "Remote error: $($msg.Split([Environment]::NewLine)[0])"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Get-WmiObject` / `wmic.exe` | `Get-CimInstance` + `New-CimSession` | PowerShell 3.0+ / Windows 11 25H2 removes `wmic.exe` | Cross-edition code; `Get-WmiObject` is removed in PS7. |
| Implicit CIM/WSMAN fallback | Explicit `New-CimSessionOption -Protocol Wsman|Dcom` | Phase 3 design | Avoids the "CIM fallback is still WinRM" trap. |
| Live session caching | Process-only transport-name cache | Phase 3 decision (D-04) | Eliminates session-lifetime fragility. |
| CredSSP for second-hop | Local-on-target queries + RBCD/JEA docs | Phase 3 decision (D-07) | Prevents credential exposure on hop hosts. |
| Parallel runspace pools | Serial probes with caps | Phase 3 decision (D-02) | Simpler, 5.1-safe; parallel deferred to Phase 5. |

**Deprecated/outdated:**
- `Get-WmiObject`: removed in PS7; use `Get-CimInstance`.
- `wmic.exe`: being removed from Windows; use CIM cmdlets.
- `Get-CimInstance -ComputerName` as a "DCOM fallback": it defaults to WSMAN.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Test-WSMan` on Windows PowerShell 5.1 has no timeout parameters. | Pitfall 1, Standard Stack | If wrong and a timeout parameter exists, the wrapper is unnecessary but harmless. Verified locally. |
| A2 | `Win32_ComputerSystem.UserName` returns only the console session user and may be empty for RDP-only servers. | Pitfall 5 | If wrong, the field might still be blank on headless servers; handling remains the same. |
| A3 | The DCOM dynamic RPC port range on modern Windows is 49152-65535. | Firewall/port reality | If the environment uses a restricted/custom range, operator guidance must be updated; the tool itself does not hard-code ports. |
| A4 | The ActiveDirectory module and CimCmdlets are natively compatible with PowerShell 7.6 on Windows 10 1809+/Server 1809+. | Summary, Standard Stack | If Microsoft compatibility list changes, Phase 5 CI matrix will catch it. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

## Open Questions (RESOLVED)

Resolved during `/gsd-plan-phase 3`; implemented across `03-01-PLAN.md`, `03-02-PLAN.md`, and `03-03-PLAN.md`.

1. **Should the inventory report show a partial row immediately when the total cap is exceeded, or should it mark all remaining rows `Skipped` without probing?**
   - Resolution: Already-probed rows keep their results; all remaining rows get `Transport='Skipped'` with no further network attempts (D-02). Implemented in `03-02-PLAN.md` Task 2.

2. **What is the exact string format for `RemoteOS`?**
   - Resolution: Single trimmed string built from `@($os.Caption, $os.Version, $os.CSDVersion) -join ' '`; AD-side `OperatingSystem*` columns are never overwritten (D-01). Implemented in `03-02-PLAN.md` Task 1.

3. **Should `Test-AdmanCapability` startup probe use the same `perHostProbeCap` or keep its existing defaults?**
   - Resolution: Leave `Test-AdmanCapability` unchanged; it tests the DC, not fleet hosts. The new `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap` keys are separate from the startup `WinRM`/`CIM` defaults (D-02). Implemented in `03-01-PLAN.md` Task 1.

4. **How should the connector behave when the operator runs `Get-AdmanInventoryReport` before `Initialize-Adman`?**
   - Resolution: Rely on the report verb's existing `$script:Config.ManagedOUs` guard; connector helpers assume `$script:Config` is populated, consistent with other Private helpers. Implemented implicitly in `03-02-PLAN.md` Task 2.

## Environment Availability

> Skip this section if the phase has no external dependencies (code/config-only changes). Phase 3 depends on built-in PowerShell/OS modules only.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows PowerShell 5.1 | Module baseline | ✓ (in-box) | 5.1 | — |
| PowerShell 7.6 LTS | Supported modern runtime | ✗ (not installed on this host) | — | Develop/test on 5.1; Phase 5 CI matrix covers 7.6. |
| `Microsoft.WSMan.Management` (`Test-WSMan`) | WinRM probe | ✓ (in-box) | OS-provided | — |
| `CimCmdlets` | CIM sessions/queries | ✓ (in-box) | OS-provided | — |
| ActiveDirectory module (RSAT) | `Get-AdmanInventoryReport` AD read | ✗ on this host | — | Existing tests use mocks; integration tests require lab domain. |
| Target computers with WinRM/CIM/DCOM | Real remote enrichment | ✗ (no lab targets on this host) | — | Unit tests mock transport; integration tests require lab. |

**Missing dependencies with no fallback:**
- PowerShell 7.6 LTS on this host — must be installed or CI-run elsewhere for dual-edition verification (Phase 5).
- ActiveDirectory module / lab domain — required for integration testing; existing unit tests use mocks.

**Missing dependencies with fallback:**
- None for implementation. All Phase 3 code can be authored and unit-tested on 5.1 with mocks.

## Validation Architecture

> `workflow.nyquist_validation` is absent in `.planning/config.json`, so validation is treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Pester 6.0.0 |
| Config file | none — tests use `#Requires -Modules Pester` |
| Quick run command | `Invoke-Pester -Path tests/Report.Inventory.Tests.ps1 -Tag Unit` |
| Full suite command | `Invoke-Pester -Path tests/ -Tag Unit` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RMT-01 | Ladder order: WinRM → CimWsman → CimDcom → skip; explicit protocol options used. | unit | `Invoke-Pester tests/Remoting.Ladder.Tests.ps1` | ❌ Wave 0 |
| RMT-01 | Transport name cached per host, keyed uppercase, process-only. | unit | `Invoke-Pester tests/Remoting.Cache.Tests.ps1` | ❌ Wave 0 |
| RMT-02 | Dead/timeout hosts return `Transport='Skipped'` and empty remote fields. | unit | `Invoke-Pester tests/Remoting.Skipped.Tests.ps1` | ❌ Wave 0 |
| RMT-02 | Per-host cap and total cap are enforced. | unit | `Invoke-Pester tests/Remoting.TimeCaps.Tests.ps1` | ❌ Wave 0 |
| RMT-03 | Inventory rows gain `Transport`, `RemoteOS`, `Uptime`, `LoggedOnUser`. | unit | `Invoke-Pester tests/Report.Inventory.Tests.ps1` | ❌ needs extension |
| RMT-03 | Uptime emitted as `[TimeSpan]`. | unit | `Invoke-Pester tests/Remoting.Query.Tests.ps1` | ❌ Wave 0 |
| RMT-04 | Second-hop operations are structurally refused; no CredSSP option. | unit + static | `Invoke-Pester tests/Remoting.DoubleHop.Tests.ps1` | ❌ Wave 0 |
| cross | No new external packages required; no AD write cmdlets in Public remoting code. | static | `Invoke-ScriptAnalyzer -Path Public/ -Settings PSScriptAnalyzerSettings.psd1` | ✅ harness |

### Sampling Rate

- **Per task commit:** `Invoke-Pester -Path tests/Remoting.*.Tests.ps1 -Tag Unit`
- **Per wave merge:** `Invoke-Pester -Path tests/ -Tag Unit`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/Remoting.Ladder.Tests.ps1` — covers RMT-01 ladder order and protocol options.
- [ ] `tests/Remoting.Cache.Tests.ps1` — covers RMT-01 process-only cache behavior.
- [ ] `tests/Remoting.Skipped.Tests.ps1` — covers RMT-02 `Skipped` first-class outcome.
- [ ] `tests/Remoting.TimeCaps.Tests.ps1` — covers RMT-02 per-host + total caps.
- [ ] `tests/Remoting.Query.Tests.ps1` — covers RMT-03 CIM classes and `[TimeSpan]` uptime.
- [ ] `tests/Remoting.DoubleHop.Tests.ps1` — covers RMT-04 structural guard.
- [ ] Extend `tests/Report.Inventory.Tests.ps1` — assert new `Transport`, `RemoteOS`, `Uptime`, `LoggedOnUser`, `Bucket='Inventory'` columns.
- [ ] Extend `config/adman.schema.json` + `config/adman.defaults.json` — add `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap`.

## Security Domain

> `security_enforcement` is enabled (absent = enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Pass-through Kerberos/NTLM via OS; no custom auth. |
| V3 Session Management | yes | Transient CIM sessions only; no live session reuse; cache is transport name only. |
| V4 Access Control | yes | CIM/WinRM auth controlled by OS Kerberos/NTLM and target DCOM/WinRM ACLs; tool does not elevate. |
| V5 Input Validation | yes | Computer name sanitized via uppercasing/cache key; CIM class allow-list prevents second-hop injection. |
| V6 Cryptography | no | No custom crypto; OS handles Kerberos/NTLM. |
| V8 Data Protection | yes | DPAPI credential file remains separate and opt-in; Phase 3 is read-only and writes no audit record. |
| V10 Malicious Code | no | Built-in modules only; no new dependencies. |

### Known Threat Patterns for WinRM/CIM/DCOM

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Credential theft via CredSSP | Information Disclosure | Reject CredSSP in Phase 3; document RBCD/JEA for future live actions. |
| Double-hop leakage to third machine | Information Disclosure / Elevation | Local-on-target CIM only; structural class allow-list; refuse second-hop operations. |
| DCOM/RPC exposure through firewall | Tampering / Denial of Service | Tool does not open ports; operator guidance documents 135 + dynamic RPC. |
| Session hijacking/replay | Spoofing | No persistent sessions; transport cache is name-only. |
| Overly verbose error disclosure | Information Disclosure | Translate raw HRESULTs/stack traces to short operator strings. |

## Sources

### Primary (HIGH confidence)

- Local Windows PowerShell 5.1 help verification (`Get-Help Test-WSMan -Parameter *`, `Get-Help New-CimSession -Parameter *`, `Get-Help New-CimSessionOption -Parameter *`, `Get-Help Get-CimInstance -Parameter *`) — confirms parameter availability, `-Protocol` values, `-OperationTimeoutSec`, and absence of `Test-WSMan` timeout parameters on 5.1.
- [Microsoft Learn — New-CimSessionOption](https://learn.microsoft.com/powershell/module/cimcmdlets/new-cimsessionoption) — `-Protocol Dcom|Wsman|Default`, DCOM/WSMan-specific options, Windows-only.
- [Microsoft Learn — New-CimSession](https://learn.microsoft.com/powershell/module/cimcmdlets/new-cimsession) — `-OperationTimeoutSec`, `-SessionOption`, `-ComputerName` defaults to WSMAN.
- [Microsoft Learn — Get-CimInstance](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance) — `-CimSession`, `-ComputerName` creates temporary WSMAN session, `-OperationTimeoutSec`.
- `Win32_OperatingSystem` and `Win32_ComputerSystem` WMI class property sets — `Caption`, `Version`, `CSDVersion`, `LastBootUpTime` (DateTime), `UserName`.

### Secondary (MEDIUM confidence)

- [PowerShell Team — CIM Cmdlets: Some Tips & Tricks](https://devblogs.microsoft.com/powershell/cim-cmdlets-some-tips-tricks/) — CIM default-to-WSMAN behavior.
- [Mike F Robbins — CimSession with Fallback to DCOM](https://mikefrobbins.com/2014/08/28/powershell-function-to-create-cimsessions-to-remote-computers-with-fallback-to-dcom/) — practical ladder pattern.
- [Adam the Automator / 4sysops — PowerShell Double-Hop](https://adamtheautomator.com/powershell-double-hop-fix/) — RBCD/JEA/CredSSP alternatives.
- [TechTarget — Avoid the double-hop problem](https://www.techtarget.com/searchwindowsserver/tutorial/How-to-avoid-the-double-hop-problem-with-PowerShell) — session configuration / RunAs workaround.

### Tertiary (LOW confidence)

- Community sources on `Test-WSMan` `-ConnectionTimeout`/`-OperationTimeout` parameters on PowerShell 7.x — not verified locally because PS 7.6 is not installed on this host; Phase 5 CI matrix should confirm.
- Community sources on DCOM dynamic RPC port range — environment-specific; operator guidance should be validated against the target fleet.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against local PowerShell 5.1 help and Microsoft Learn docs.
- Architecture: HIGH — directly derived from locked decisions in 03-CONTEXT.md and existing codebase patterns.
- Pitfalls: HIGH — core timeout/protocol traps are well-documented and verified locally.

**Research date:** 2026-07-16
**Valid until:** 2026-10-16 (90 days for stable built-in PowerShell/OS modules)
