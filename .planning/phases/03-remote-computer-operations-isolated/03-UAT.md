---
status: testing
phase: 03-remote-computer-operations-isolated
source:
  - 03-01-SUMMARY.md
  - 03-02-SUMMARY.md
  - 03-03-SUMMARY.md
started: 2026-07-17T08:25:00Z
updated: 2026-07-17T08:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Confirm 03-01 automated coverage (transport connector)
expected: |
  All six 03-01 deliverables are covered by passing unit tests:
  - Fixed WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped ladder + uppercase cache key (Remoting.Ladder, Remoting.Cache)
  - Skipped outcome for unreachable/cap-exceeded hosts (Remoting.Skipped, Remoting.TimeCaps)
  - Test-AdmanWsmanTimeout hard-timeout wrapper (Remoting.WsmanTimeout)
  - Test-AdmanCimSessionTimeout hard-timeout wrapper (Remoting.CimSessionTimeout)
  - Convert-AdmanRemoteError HRESULT translator (Remoting.Skipped)
  - transport.timeouts.perHostProbeCap / totalInventoryRemoteCap config keys (Config.Load)
result: pass

### 2. Confirm 03-02 automated coverage (query layer / inventory enrichment)
expected: |
  All four 03-02 deliverables are covered by passing unit tests:
  - Invoke-AdmanRemoteCimQuery allow-list + session cleanup (Remoting.Query)
  - Invoke-AdmanRemoteQuery enrichment with one session and shrinking budget (Remoting.Query)
  - Get-AdmanInventoryReport remote enrichment, caps, and skipped-host summary (Report.Inventory)
  - Menu label and renderer columns include remote fields (Report.Inventory)
result: pass

### 3. Verify docs/REMOTE-OPS.md operator guidance
expected: |
  docs/REMOTE-OPS.md exists and contains guidance covering:
  - The double-hop problem and adman's local-on-target stance
  - Explicit CredSSP exclusion from v1
  - RBCD/JEA as future paths if second-hop live actions are needed
  - Sensitive accounts unaffected by Phase 3 reads
  - Pass-through credential behavior
  - Hard-timeout behavior for dead hosts
  - WinRM vs DCOM firewall ports
result: pass

### 4. Connect-AdmanTarget fixed ladder and cache
expected: Connect-AdmanTarget fixed ladder (WinRM -> CIM/WSMan -> CIM/DCOM -> Skipped) with process-only cache keyed by uppercase computer name
result: pass
source: automated
coverage_id: D1

### 5. Skipped outcome for unreachable or cap-exceeded hosts
expected: Unreachable or cap-exceeded hosts return 'Skipped' as a first-class non-error outcome without throwing
result: pass
source: automated
coverage_id: D2

### 6. Test-AdmanWsmanTimeout hard-timeout wrapper
expected: Test-AdmanWsmanTimeout wraps Test-WSMan in a hard-timeout Start-Job and cleans up jobs
result: pass
source: automated
coverage_id: D3

### 7. Test-AdmanCimSessionTimeout hard-timeout wrapper
expected: Test-AdmanCimSessionTimeout wraps New-CimSession setup in a hard-timeout Start-Job and supports Wsman/Dcom protocols
result: pass
source: automated
coverage_id: D4

### 8. Convert-AdmanRemoteError translation
expected: Convert-AdmanRemoteError maps RPC-unavailable, access-denied, and double-hop HRESULTs to short operator strings
result: pass
source: automated
coverage_id: D5

### 9. Timeout config keys with defaults and additive merge
expected: transport.timeouts.perHostProbeCap and totalInventoryRemoteCap config keys exist with shipped defaults and additive merge
result: pass
source: automated
coverage_id: D6

### 10. Invoke-AdmanRemoteCimQuery allow-list and session cleanup
expected: Invoke-AdmanRemoteCimQuery allow-lists only Win32_OperatingSystem/Win32_ComputerSystem, maps transport to Wsman/Dcom protocol, forwards TimeoutSeconds, and removes the transient session
result: pass
source: automated
coverage_id: D1

### 11. Invoke-AdmanRemoteQuery enrichment
expected: Invoke-AdmanRemoteQuery returns RemoteOS/Uptime/LoggedOnUser for reachable hosts, short-circuits Skipped transport, creates exactly one CIM session, probes with Test-AdmanCimSessionTimeout, forwards a shrinking timeout budget, and returns Skipped on CIM errors
result: pass
source: automated
coverage_id: D2

### 12. Get-AdmanInventoryReport remote enrichment
expected: Get-AdmanInventoryReport enriches every row with Transport/RemoteOS/Uptime/LoggedOnUser, preserves AD OS columns, enforces per-host + total caps, counts CIM errors as Skipped, and emits a single Write-Warning summary
result: pass
source: automated
coverage_id: D3

### 13. Inventory report menu label and renderer columns
expected: Menu inventory report label reads 'Fleet inventory report (with remote enrichment)' and the renderer property list includes the four new columns
result: pass
source: automated
coverage_id: D4

### 14. Invoke-AdmanRemoteCimQuery structural guard
expected: Invoke-AdmanRemoteCimQuery rejects any class outside {Win32_OperatingSystem, Win32_ComputerSystem} with the D-07 guard message
result: pass
source: automated
coverage_id: D2

### 15. Private/Remoting references to CredSSP/Invoke-Command/New-PSSession
expected: Private/Remoting/*.ps1 contains zero case-insensitive references to CredSSP, Invoke-Command, or New-PSSession
result: pass
source: automated
coverage_id: D3

### 16. Private/Remoting -ClassName values
expected: Private/Remoting/*.ps1 contains exactly two distinct -ClassName values: Win32_OperatingSystem and Win32_ComputerSystem
result: pass
source: automated
coverage_id: D4

### 17. Invoke-AdmanRemoteQuery runtime second-hop guard
expected: Invoke-AdmanRemoteQuery never calls Invoke-Command or New-PSSession at runtime
result: pass
source: automated
coverage_id: D5

## Summary

total: 17
passed: 17
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
