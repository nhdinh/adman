# Phase 3: Remote Computer Operations (isolated) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-16
**Phase:** 03-Remote Computer Operations (isolated)
**Areas discussed:** Result surfacing, Transport cache, Skipped hosts, Double-hop stance

---

## Result surfacing

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-enrich inventory | Add remote fields directly to `Get-AdmanInventoryReport` so every inventory view shows online/OS/uptime/logged-on when reachable. | ✓ |
| Separate report verb | Ship a dedicated `Get-AdmanRemoteComputerReport` verb/menu item that queries the fleet explicitly. | |
| Both | Inventory gets a cheap `-IncludeRemote` switch plus a dedicated remote report verb. | |

**User's choice:** Auto-enrich inventory
**Notes:** RMT-03 "enrich inventory" interpreted literally. No separate remote report verb in Phase 3.

### Sub-decisions

| Question | Option | Selected |
|----------|--------|----------|
| Always run or opt-in switch? | Always run | ✓ |
| Remote-enriched columns | Transport, RemoteOS, Uptime, LoggedOnUser | ✓ |
| Probe strategy | Serial with time cap | ✓ |
| Per-host timeout | Config defaults | ✓ |
| Reconcile per-host timeouts with time cap | New per-host probe cap key | ✓ |

**Notes:** User confirmed serial probes with a new `transport.timeouts.perHostProbeCap` (default 10s) and a total report time cap. Skipped-host summary chosen as a single `Write-Warning`.

---

## Transport cache

| Option | Description | Selected |
|--------|-------------|----------|
| Cache transport name only | Store only the winning transport per host (`WinRM`, `CimWsman`, `CimDcom`, `Skipped`) in a process-only hashtable. | ✓ |
| Reuse live sessions | Cache `CimSession`/`PSSession` objects for reuse. | |
| Persist cache | Save transport cache across sessions. | |

**User's choice:** Cache transport name only, process-only, keyed by uppercase computer name.
**Notes:** Live session caching rejected due to session-lifetime fragility. No persistence.

---

## Skipped hosts

| Option | Description | Selected |
|--------|-------------|----------|
| First-class `Skipped` rows | Unreachable hosts remain in the result set with `Transport='Skipped'` and empty remote fields. | ✓ |
| Omit from output | Skip unreachable hosts entirely. | |
| Error rows | Return error records alongside results. | |

**User's choice:** First-class `Skipped` rows with a warning summary.
**Notes:** Warning summary: `"Remote enrichment skipped for N of M hosts."`

---

## Double-hop stance

| Option | Description | Selected |
|--------|-------------|----------|
| Structural guard + docs | Refuse any operation that would require a second hop; document RBCD/JEA preference; no CredSSP. | ✓ |
| Documentation only | Surface guidance but allow operations to fail naturally. | |
| Enable CredSSP | Allow CredSSP as a fallback transport. | |

**User's choice:** Structural guard + docs, no CredSSP.
**Notes:** Phase 3 queries are local-on-target (`Win32_OperatingSystem`, `Win32_ComputerSystem`). A connector guard refuses second-hop operations explicitly. RBCD/JEA documented for future live actions; CredSSP excluded.

---

## Claude's Discretion

- Exact Private helper names (`Connect-AdmanTarget`, `Invoke-AdmanRemoteQuery`, etc.).
- Whether remote columns are added inside `ConvertTo-AdmanResult` or appended after.
- Menu label wording for the inventory report.
- Uptime formatting detail (emit `[TimeSpan]`).
- Raw error-to-message translation strings.

## Deferred Ideas

- Remote live actions (restart service, `gpupdate`, etc.) — v2 `RMT-V01`.
- Parallel fleet probes — Phase 5 if performance demands it.
- Persistent/live session cache — revisit with live actions.
- CredSSP transport option — rejected for v1.
- RBCD/JEA implementation — guidance only in Phase 3.
- Read-side audit for inventory reports — not required by SAFE-03.
- Separate remote report verb / dashboard — not needed.
