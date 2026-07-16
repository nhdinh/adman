---
phase: 3
reviewers: [claude]
reviewed_at: 2026-07-16T22:05:00+00:00
plans_reviewed:
  - 03-01-PLAN.md
  - 03-02-PLAN.md
  - 03-03-PLAN.md
self_review_note: |
  This review was performed by the only available AI CLI (claude) while running inside Claude Code.
  It therefore lacks cross-AI independence. The findings are still source-grounded and cite file:line evidence,
  but should be treated as a single-reviewer review rather than adversarial consensus.
---

# Cross-AI Plan Review — Phase 3: Remote Computer Operations (isolated)

## Claude Review

The three plans form a coherent, security-first implementation of a read-only remote-enrichment layer. They correctly quarantine transport detection in `Private/Remoting/`, enforce the WinRM → CIM/WSMan → CIM/DCOM ladder with explicit protocol options, treat `Skipped` as a first-class non-error outcome, and avoid CredSSP/live-session caching. The biggest execution risks are (1) the per-host cap bounds the **probe** ladder but not the two subsequent CIM queries, which each open a fresh session; (2) `Start-Job` per host is correct for 5.1 but expensive; and (3) the config-seed/validation changes must not break existing `.store/config.json` files. Overall the design is sound but needs tighter timeout discipline around the query phase.

### Strengths

- **Clean architecture.** `Connect-AdmanTarget` returns only a transport name, `Invoke-AdmanRemoteQuery` is transport-agnostic, and `Get-AdmanInventoryReport` owns enrichment — matching the existing Public/Private boundary (`adman.psm1:32-49`).
- **5.1-safe ladder.** Using `Test-AdmanWsmanTimeout` with `Start-Job` correctly addresses the verified fact that `Test-WSMan` has no timeout parameters on Windows PowerShell 5.1.
- **Explicit protocol options.** Step 2/3 use `New-CimSessionOption -Protocol Wsman|Dcom`, avoiding the "CIM fallback silently uses WSMAN" trap documented in `03-RESEARCH.md` Pitfall 2.
- **Process-only cache.** Caching only the transport name string (never live `CimSession`/`PSSession` objects) matches `D-04` and avoids session-lifetime fragility.
- **Config-driven with upgrade path.** Adding `perHostProbeCap`/`totalInventoryRemoteCap` and mirroring the existing deny-list seed pattern in `Initialize-AdmanConfig.ps1:232-238` keeps existing configs working.
- **Security posture is explicit.** No CredSSP, static proof against `Invoke-Command`/`New-PSSession`, and a structural CIM class allow-list directly enforce `D-07`/`RMT-04`.
- **Renderer compatibility.** Extending `$computerReportProperties` in `Get-AdmanMenuDefinition.ps1:83` (and the inventory item label at line 140) means zero-row reports still get the new headers, consistent with the Cycle 4 finding documented in that file.

### Concerns

#### HIGH — Per-host cap does not bound the query phase

- **Evidence:** `03-02-PLAN.md` Task 1 creates `Invoke-AdmanRemoteCimQuery` with `-OperationTimeoutSec $script:Config.transport.timeouts.perHostProbeCap` and `Invoke-AdmanRemoteQuery` calls it **twice** (OS + ComputerSystem), each creating a fresh transient session.
- **Risk:** A reachable-but-slow host can spend up to ~20s in queries after the 10s probe, violating the intent of the per-host cap. The total cap (`120s`) is the only backstop, but it degrades the whole report rather than skipping the slow host.
- **Mechanism gap:** `Connect-AdmanTarget` enforces `$cap` for the ladder, but `Invoke-AdmanRemoteQuery` has no stopwatch and no caller-provided remaining budget.

#### MEDIUM — Start-Job overhead and orphan job edge cases

- **Evidence:** `03-01-PLAN.md` Task 2 specifies `Test-AdmanWsmanTimeout` uses `Start-Job` + `Wait-Job -Timeout $TimeoutSeconds`.
- **Risk:** One child process per host is heavy for large fleets; on a 200-host inventory this is 200 short-lived jobs. Also, if `Receive-Job` itself hangs (rare but possible with frozen job output), the wrapper's cleanup may not run.
- **Note:** The plan's cleanup logic (`Stop-Job`/`Remove-Job` on timeout/failure) is correct, but integration tests should verify no orphaned jobs remain under `Get-Job`.

#### MEDIUM — `Test-AdmanWsmanTimeout` success criterion is loose

- **Evidence:** `03-01-PLAN.md` Task 2 says "any non-null object is treated as success by the caller."
- **Risk:** If `Test-WSMan` returns a non-terminating error record under some network condition, the ladder will classify the host as `WinRM` when it should be `Skipped`. `Test-WSMan -ErrorAction SilentlyContinue` generally returns `$null` on failure, but the wrapper should explicitly check for a valid `WSManConfigContainerElement` or at least exclude `[System.Management.Automation.ErrorRecord]`.

#### MEDIUM — Config seeding pattern conflates one-time and additive seeds

- **Evidence:** `03-01-PLAN.md` Task 1 instructs seeding missing timeout keys "mirroring the DenyList seed pattern" (`Initialize-AdmanConfig.ps1:232-238`).
- **Risk:** The DenyList seed is intentionally one-time ("seed once, file is source of truth"). Timeout keys should be re-seeded on every load if missing (to apply new defaults after upgrade), but **not** overwrite existing user values. The plan needs to distinguish these two seed semantics clearly; otherwise a future "seed" refactor might wipe user timeout edits.

#### LOW — `Test-AdmanTransportError` naming is misleading

- **Evidence:** `03-01-PLAN.md` Task 2 defines `Test-AdmanTransportError` as a translator returning strings.
- **Risk:** `Test-*` verb convention implies boolean output. This will likely trigger reviewer confusion and may conflict with approved-verb expectations in `PSScriptAnalyzerSettings.psd1:18` (`PSUseApprovedVerbs`). `Convert-AdmanRemoteError` or `Resolve-AdmanRemoteError` would be clearer.

#### LOW — Credential handling for remote CIM is unspecified

- **Evidence:** Neither plan mentions passing `-Credential` to `New-CimSession` / `Test-WSMan`.
- **Risk:** The project constraints say "prompt for domain-admin creds only when insufficient." For Phase 3 read-only remote ops, pass-through Kerberos/NTLM may suffice, but if the operator runs with delegated-admin rights that are **not** local administrators on target workstations, every host will return `Skipped` rather than prompting. This is acceptable for Phase 3 but should be documented in `REMOTE-OPS.md` so operators do not expect credential elevation during inventory reads.

#### LOW — Static class-name parsing test is brittle

- **Evidence:** `03-03-PLAN.md` Task 2 proposes parsing `-ClassName` arguments from source files.
- **Risk:** If a future refactor moves class names into variables (e.g., `$ClassName = 'Win32_OperatingSystem'`), the static test fails even though the allow-list still enforces the policy. Document the intent so maintainers know to update the test.

### Suggestions

1. **Pass a remaining-time budget into `Invoke-AdmanRemoteQuery`.**
   - Add an optional `[int]$TimeoutSeconds` parameter to `Invoke-AdmanRemoteQuery` and `Invoke-AdmanRemoteCimQuery`. `Get-AdmanInventoryReport` computes `$remaining = $totalCap - $stopwatch.Elapsed.TotalSeconds` and passes it down. This closes the per-host/query timeout gap.

2. **Reuse one CIM session for both classes.**
   - Refactor `Invoke-AdmanRemoteQuery` to open a single session, call `Get-CimInstance` twice, then remove it in a `finally`. This halves session setup overhead and keeps the per-host time predictable. The `Invoke-AdmanRemoteCimQuery` allow-list can still enforce the class guard.

3. **Tighten `Test-AdmanWsmanTimeout` success check.**
   - Return `$null` if the received object is an `ErrorRecord`; otherwise return the object. Add a unit test for this case.

4. **Clarify seed semantics in `Initialize-AdmanConfig`.**
   - Implement timeout seeding as "merge missing defaults on every load, never overwrite present values" and add a test that proves an existing `perHostProbeCap: 42` is preserved while a missing `totalInventoryRemoteCap` is defaulted.

5. **Rename `Test-AdmanTransportError` to `Convert-AdmanRemoteError`.**
   - Avoids verb-confusion and aligns with `ConvertTo-AdmanResult`/`ConvertTo-AdmanCleanConfig` naming conventions in the codebase.

6. **Document remote credential behavior in `REMOTE-OPS.md`.**
   - Add a paragraph stating Phase 3 inventory enrichment uses pass-through credentials only; if targets reject the current token, they are reported as `Skipped`. Future live-action phases may add explicit credential forwarding via RBCD/JEA.

7. **Add an integration smoke test (deferred to Phase 5 is fine).**
   - A test that runs against `localhost` with a short cap would catch real WinRM/CIM/DCOM environment differences that mocks cannot.

### Risk Assessment: MEDIUM

The plans will achieve the phase goals: transport detection, `Skipped` handling, inventory enrichment, and double-hop documentation are all well-defined and testable. The MEDIUM rating reflects two implementation-time risks that could degrade production behavior: (1) the query phase lacks a per-host time budget, and (2) `Start-Job` per host may be slow at scale. Both are addressable within the planned file set before execution. No HIGH risk design flaws are present.

---

## Consensus Summary

Only one reviewer (Claude CLI) was available and invoked. Because the review was run from inside Claude Code, this is effectively a self-review and lacks cross-AI independence. The review is source-grounded (cites `adman.psm1:32-49`, `Initialize-AdmanConfig.ps1:232-238`, `Get-AdmanMenuDefinition.ps1:83`, etc.) and did not report inability to read the repo.

### Agreed Strengths

- Clean separation of transport detection, query execution, and inventory enrichment.
- Correct 5.1-compatible timeout wrapper for `Test-WSMan`.
- Explicit protocol options avoid the CIM/WSMan fallback trap.
- Process-only transport cache aligns with the locked decision D-04.
- Strong security posture: no CredSSP, no live session reuse, structural class allow-list.

### Agreed Concerns

- **HIGH:** The per-host cap governs the probe ladder but not the two CIM queries that follow; a slow host can exceed its budget.
- **MEDIUM:** `Start-Job` per host adds overhead and possible orphan-job risk at scale.
- **MEDIUM:** `Test-AdmanWsmanTimeout` treats any non-null result as success, which may misclassify error records as WinRM reachable.
- **MEDIUM:** Timeout config seeding must not overwrite existing user values; the plan should distinguish one-time vs additive seed semantics.
- **LOW:** `Test-AdmanTransportError` naming conflicts with the boolean convention of `Test-*` verbs.
- **LOW:** Remote credential behavior (pass-through only) should be documented for operators.
- **LOW:** Static parsing of `-ClassName` values in source is brittle to refactoring.

### Divergent Views

None — only one reviewer participated.

---

## Next Step

To incorporate this feedback into planning, run:

```
/gsd-plan-phase 03 --reviews
```

or manually update `03-01-PLAN.md`, `03-02-PLAN.md`, and `03-03-PLAN.md` to address the HIGH per-host/query timeout gap and the actionable MEDIUM/LOW items above.
