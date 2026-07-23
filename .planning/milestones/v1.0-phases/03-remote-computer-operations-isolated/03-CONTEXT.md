# Phase 3: Remote Computer Operations (isolated) - Context

**Gathered:** 2026-07-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 ships a **read-only remote query capability quarantined behind one connector**: `Connect-AdmanTarget` probes each target host with a WinRM → CIM/WSMan → CIM/DCOM → skip ladder, caches the winning transport per host, and runs short enough timeouts that the menu never hangs on dead hosts. The queries (online status, OS, uptime, logged-on user) **enrich the existing Phase 1 inventory report** (`Get-AdmanInventoryReport`) rather than creating a new report verb. Every unreachable host is reported as `Skipped` — a first-class non-error outcome — and double-hop risk is eliminated by design (local-on-target queries only). No live remote actions (service restart, gpupdate, etc.) ship in this phase; that is v2 scope (RMT-V01).

The Phase 0/1/2 safety spine (gate, config, audit, menu) and the existing `ConvertTo-AdmanResult` computer schema are locked and reused. The decisions below pin down **how the connector behaves, how the inventory report absorbs enrichment, and how skipped/double-hop cases are handled**.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Result surfacing / inventory enrichment (RMT-03)

- **D-01: Remote queries auto-enrich `Get-AdmanInventoryReport`.** No separate remote report verb in Phase 3.
  - The existing inventory report already emits `ConvertTo-AdmanResult -ObjectType Computer` rows. Phase 3 extends each row with remote-enriched columns after the AD query returns.
  - Remote enrichment runs **automatically** (no opt-in switch) for every inventory report. The inventory report is the canonical "what do we know about the fleet" view; RMT-03 says "enrich inventory" literally.
  - Added columns (all nullable/empty when the host is skipped or unreachable):
    - `Transport` — `'WinRM'`, `'CimWsman'`, `'CimDcom'`, or `'Skipped'`.
    - `RemoteOS` — OS caption/version/service pack from remote CIM, when reachable.
    - `Uptime` — `[TimeSpan]` from `Win32_OperatingSystem.LastBootUpTime`, when reachable.
    - `LoggedOnUser` — `Win32_ComputerSystem.UserName`, when reachable.
  - The existing AD-side OS attributes (`OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`) remain populated from AD; `RemoteOS` may be empty when the host is offline but AD still has stale OS info. This preserves backward compatibility and avoids silently dropping AD data.

- **D-02: Fleet probes run serially with a per-host timeout cap and a total report time cap.**
  - **Serial probes** are the cross-edition baseline (no PS7-only `ForEach-Object -Parallel`; no runspace-pool fallback complexity in Phase 3).
  - Add a new config key `transport.timeouts.perHostProbeCap` (default **10 seconds**) that caps each host's total ladder time. This is separate from `transport.timeouts.WinRM`/`CIM` used by the startup capability probe (`Test-AdmanCapability`) so the startup probe can keep its longer defaults while inventory stays snappy.
  - Implementation: the ladder uses `transport.timeouts.perHostProbeCap` as a ceiling, but internally still respects the per-step semantics (WinRM probe, then CIM/WSMan, then CIM/DCOM). If a host cannot be classified within the cap, it is `Skipped`.
  - **Total report time cap:** a second safety valve (config key `transport.timeouts.totalInventoryRemoteCap`, default **120 seconds**) stops remote enrichment after the cap and returns partial results. The report remains non-terminating; skipped hosts show `Transport='Skipped'`.
  - Rationale: dead hosts are common in a mixed fleet; serial+per-host cap+total cap keeps the menu responsive without requiring parallel infrastructure.

- **D-03: Skipped-host summary is a single `Write-Warning`.**
  - After the report completes, emit one warning: `"Remote enrichment skipped for N of M hosts."`
  - Each skipped host is still present in the result set with `Transport='Skipped'` and empty remote fields, so console/HTML/CSV/JSON consumers can sort/filter/count.
  - No footer row, no renderer-specific summary logic — the warning is produced by the report verb itself so all renderers benefit.

### Area 2 — Transport cache (RMT-01)

- **D-04: Cache only the winning transport name per host, process-only, keyed by uppercase computer name.**
  - Cache value: `'WinRM' | 'CimWsman' | 'CimDcom' | 'Skipped'`.
  - Cache storage: a module-scoped hashtable (`$script:TransportCache`). No persistence across sessions.
  - **Do not reuse live `CimSession` or `PSSession` objects.** Session lifetime across firewalls, sleep/hibernate, and trust changes is fragile; reconnect logic is out of Phase 3 scope. The cache is a lookup table, not a session pool.
  - Cache is consulted before probing; if absent, the ladder runs and writes the result. No explicit invalidation during the process — a host that changes transports mid-session is rare and acceptable.
  - The cache is internal to the connector; Public verbs receive the transport as a read-only property on the result row.

- **D-05: Ladder order is fixed and matches the research/Pitfall 9 guidance.**
  1. `Test-WSMan` → `'WinRM'`.
  2. `New-CimSessionOption -Protocol Wsman` + `New-CimSession` → `'CimWsman'`.
  3. `New-CimSessionOption -Protocol Dcom` + `New-CimSession` → `'CimDcom'`.
  4. Else `'Skipped'`.
  - Each step uses the per-host probe cap. The probe distinguishes WSMAN vs DCOM explicitly (RMT-01).
  - If WinRM answers, prefer it; otherwise try CIM/WSMan (in case WSMAN works but the WinRM service doesn't expose the management service), then CIM/DCOM. The research Pitfall 9 warns that "CIM fallback" often silently uses WSMAN; the ladder avoids that trap by using explicit `-Protocol` options.

### Area 3 — Skipped hosts (RMT-02)

- **D-06: `Skipped` is a first-class non-error outcome.**
  - Unreachable/offline/timeout hosts are **not** exceptions. They appear in the result set with `Transport='Skipped'` and null/empty remote fields.
  - The report verb does not throw when some hosts are skipped; it returns the full result set plus the warning summary (D-03).
  - Downstream callers (menu, renderers, CSV export) treat `Skipped` as ordinary data. No special error UI.
  - Audit: because Phase 3 is read-only, SAFE-03 does not require an audit record for inventory reads. If a future phase adds read-audit for sensitive reports, skipped hosts are captured as read results, not failures.

### Area 4 — Double-hop stance (RMT-04)

- **D-07: Phase 3 operations are local-on-target by design; no second hop is attempted.**
  - Queries read only local CIM classes (`Win32_OperatingSystem`, `Win32_ComputerSystem`) on the target host. These classes do not reach a third machine.
  - Add a structural guard in the connector: if a query implementation would require a second hop (e.g., querying a remote share, another host, or AD cmdlets inside the remote session), the connector refuses with a clear error: `"Second-hop operation not supported in adman remote queries."`
  - **No CredSSP.** CredSSP is explicitly excluded as a transport option in Phase 3 (and v1 generally) because it ships reusable credentials to the hop host.
  - RBCD and JEA are documented in the operator guidance as the preferred paths for any future live-action second-hop need, but they are not implemented in Phase 3.
  - Accounts flagged *"Account is sensitive and cannot be delegated"* are unaffected because no delegation is requested.

### Claude's Discretion

- **Exact Public verb surface:** `Get-AdmanInventoryReport` keeps its existing signature; remote enrichment is automatic. A thin Private `Connect-AdmanTarget` + `Invoke-AdmanRemoteQuery` are the new internals.
- **Menu item text:** update the existing inventory report menu label to indicate remote enrichment (e.g., "Fleet inventory report (with remote enrichment)").
- **Caching implementation detail:** hashtable vs. PSFramework config cache — planner picks; the decision is "process-only transport name cache," not the storage mechanism.
- **Uptime representation:** emit `[TimeSpan]` so renderers can format as `7.12:34:56` or round to days.
- **Error translation:** wrap raw WinRM/CIM errors into short, actionable strings (e.g., "RPC server unavailable (DCOM firewall)"). The menu never shows a stack trace.
- **Integration with existing capability probe:** `Test-AdmanCapability` already probes WinRM and CIM/DCOM against the DC at startup. Phase 3 does **not** change that probe; it adds per-host probing at report time.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value, constraints (PowerShell 5.1 baseline + 7.6 LTS, RSAT prereq, config/credential split, no WinRM assumption, `.store/` gitignored).
- `.planning/REQUIREMENTS.md` — **Phase 3 owns 4:** `RMT-01`–`RMT-04`. Traceability table is authoritative.
- `.planning/ROADMAP.md` §Phase 3 — Goal, 3 success criteria, suggested 3-plan split (`03-01` connector, `03-02` remote queries, `03-03` double-hop docs).

### Phase 0/1/2 artifacts (the spine this phase extends)
- `.planning/phases/00-foundation-safety-harness/00-CONTEXT.md` — D-02 protected set, D-03 write-ahead audit, D-06 DPAPI credential, transport config shape (transport.order/timeouts).
- `.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md` — D-02/D-03 `ConvertTo-AdmanResult` schema, D-04 renderer contract, `Get-AdmanInventoryReport` exists and owns RPT-06.
- `.planning/phases/02-single-object-lifecycle-writes-begin-bounded-to-one/02-CONTEXT.md` — local gate pattern, group matrix pattern, audit field extensions. Not directly used by Phase 3 but establishes module conventions.

### Research corpus
- `.planning/research/SUMMARY.md` — 6-phase skeleton; Phase 3 scope and remoting ladder.
- `.planning/research/PITFALLS.md` — **Pitfall 8 (double-hop)** and **Pitfall 9 (WinRM/CIM/DCOM transport and firewall reality)** are the primary design drivers for the ladder and double-hop stance.
- `.planning/research/STACK.md` — CIM-not-WMI, dual-edition constraints, `New-CimSessionOption -Protocol Dcom`.

### Existing code that changes (read before planning)
- `Public/Get-AdmanInventoryReport.ps1` — extended with remote enrichment columns and the probe loop.
- `Public/Test-AdmanCapability.ps1` — already probes WinRM/CIM/DCOM against the DC; not modified in behavior but is the reference probe pattern.
- `Private/Reporting/ConvertTo-AdmanResult.ps1` — may need to accept additional NoteProperties for remote columns, or enrichment happens after conversion.
- `Private/Config/Initialize-AdmanConfig.ps1` + `config/adman.schema.json` + `config/adman.defaults.json` — add `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap`.
- `Private/Menu/Get-AdmanMenuDefinition.ps1` — update the inventory report menu label.

### Project rules & guardrails
- `.claude/CLAUDE.md` — "What NOT to Use" list (no `Get-WmiObject`/`wmic.exe`; CIM cmdlets only), PSScriptAnalyzer rules, dual-edition constraints.

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — gains `transport.timeouts.perHostProbeCap` and `transport.timeouts.totalInventoryRemoteCap`.
- `.store/audit/audit-YYYYMMDD.jsonl` — Phase 3 is read-only, so no new audit records are written for inventory reads.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Get-AdmanInventoryReport`** — already loops `ManagedOUs`, calls `Get-ADComputer`, maps through `ConvertTo-AdmanResult`, and adds a `Bucket` column. Phase 3 injects a per-row remote-enrichment pass after the AD mapping.
- **`ConvertTo-AdmanResult`** — fixed-schema mapper for Computer/User. Phase 3 can either extend its output NoteProperties or append them after mapping; either way the schema contract test must be updated.
- **`Test-AdmanCapability`** — contains a working WinRM + CIM/DCOM probe against the DC that can be generalized into a per-host ladder.
- **`config/adman.schema.json` / `config/adman.defaults.json`** — config schema is centralized; adding timeout keys is a schema + defaults change only.
- **`Get-AdmanMenuDefinition`** — menu item table is data-driven; update the inventory report label there.

### Established Patterns (mirror these)
- **`-Server $script:Config.DC` pinning** on every AD call; remote CIM calls use `-ComputerName <host>` with explicit `-Protocol`.
- **`$ErrorActionPreference='Stop'` module-wide**; expected failure modes (host unreachable) are caught and translated into `Skipped`.
- **Public/Private boundary:** the connector and query helpers are Private; only `Get-AdmanInventoryReport` (already Public) changes behavior.
- **Config-driven timeouts:** hard-coded defaults live only in `config/adman.defaults.json`; code reads `$script:Config.transport.timeouts.*`.
- **Result-object schema contract test:** extend the existing Pester test for `ConvertTo-AdmanResult` or the inventory report to assert the new columns.

### Integration Points
- **Config loader ↔ new timeout keys:** `Initialize-AdmanConfig` validates via `config/adman.schema.json`; new keys must be added there.
- **Inventory report ↔ connector:** `Get-AdmanInventoryReport` calls a new Private `Connect-AdmanTarget` (or equivalent) for each computer and merges the returned transport/query object into the result row.
- **Menu ↔ inventory report:** the existing menu item routes to `Get-AdmanInventoryReport`; only the label changes.
- **Capability probe ↔ connector:** `Test-AdmanCapability` stays DC-focused; the connector is a separate per-host component that may share helper code.

</code_context>

<specifics>
## Specific Ideas

- "Enrich inventory" should be literal — don't hide remote data behind a switch. The inventory report is the fleet view.
- Serial probes + per-host cap + total cap is the safest cross-edition choice; parallel can be revisited if real fleet pain appears in Phase 5.
- Distinguishing `CimWsman` from `CimDcom` matters for forensics and firewall troubleshooting.
- Live session caching was rejected because session lifetime is a support burden Phase 3 doesn't need; caching the transport name gives almost all the speed benefit.
- The double-hop guard should be structural, not just doc — if a future dev adds a query that reaches a third machine, the connector must refuse rather than silently fail with `ANONYMOUS LOGON`.
</specifics>

<deferred>
## Deferred Ideas

- **Remote live actions** (restart service, trigger `gpupdate`, etc.) — v2 scope `RMT-V01`; requires the same connector + gate integration.
- **Parallel fleet probes** — deferred to Phase 5 if fleet size makes serial probes too slow. PS7 `ForEach-Object -Parallel` or a 5.1 runspace pool would be the path.
- **Persistent transport cache** — not needed for read-only queries; revisit if live actions need session reuse.
- **CredSSP transport option** — explicitly rejected for v1 due to credential-theft risk.
- **RBCD/JEA implementation** — documented guidance only in Phase 3; actual delegation configuration is Phase 5 or operational runbook material.
- **Read-side audit for inventory reports** — not required by SAFE-03 (mutations only); revisit if a specific compliance use case emerges.
- **Separate remote report verb / dashboard** — not needed; inventory enrichment is the canonical surface.

</deferred>

---

*Phase: 3-Remote Computer Operations (isolated)*
*Context gathered: 2026-07-16*
