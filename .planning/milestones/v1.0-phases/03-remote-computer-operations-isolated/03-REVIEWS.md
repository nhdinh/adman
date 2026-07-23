---
phase: 3
reviewers: [claude]
reviewed_at: 2026-07-16T22:55:00+00:00
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

### Summary

The three plans correctly quarantine remoting behind a transport-name cache, keep queries local-on-target, and satisfy all four RMT requirements without touching the AD write path. The ladder order (WinRM → CIM/WSMan → CIM/DCOM → Skip), `Start-Job` timeout wrapper for PowerShell 5.1, and inventory enrichment pass are sound. Main risks are test slowness from real sleeps, a brittle static class-name parser, and the need to place the config-key merge step carefully so user values are preserved.

### Strengths

- **Quarantined connector design**: `Connect-AdmanTarget` lives in `Private/Remoting/` and returns only a transport name, satisfying D-04 (`03-01` task 2).
- **5.1-safe timeout wrapper**: `Test-AdmanWsmanTimeout` uses `Start-Job` + `Wait-Job -Timeout` because `Test-WSMan` has no native timeout on Windows PowerShell 5.1 (`03-RESEARCH.md` Pitfall 1; `03-01` task 2).
- **Explicit protocol options**: The ladder uses `New-CimSessionOption -Protocol Wsman` and `-Protocol Dcom`, avoiding the "CIM fallback is still WSMAN" trap (`03-RESEARCH.md` Pitfall 2).
- **Structural double-hop guard**: `Invoke-AdmanRemoteCimQuery` allow-lists only `Win32_OperatingSystem` and `Win32_ComputerSystem`, which enforces D-07/RMT-04 at runtime (`03-02` task 1).
- **Schema contract preserved**: Remote columns are appended by `Get-AdmanInventoryReport` after `ConvertTo-AdmanResult`, so `tests/Result.Schema.Tests.ps1:187-198` remains untouched (`03-02` task 2).
- **Config upgrade path**: Missing timeout keys are merged from `config/adman.defaults.json` on every load rather than overwriting user values (`03-01` task 1).

### Concerns

- **MEDIUM — Test suite will be slow due to real sleeps**: `03-01` task 3 says "mock `Test-AdmanWsmanTimeout` to sleep slightly longer than 1 second" with `perHostProbeCap=1`, and `03-02` task 3 says "mocks `Connect-AdmanTarget` to sleep part of the budget". Each such test burns at least one second; cap-enforcement tests should manipulate elapsed time via a controllable stopwatch or use millisecond-resolution mocks instead of `Start-Sleep`.
- **MEDIUM — Config merge placement is unspecified**: `03-01` task 1 says to merge missing timeout keys before validation but does not specify exactly where in `Private/Config/Initialize-AdmanConfig.ps1`. It must happen after `ConvertTo-AdmanCleanConfig` (line 228) and before `Test-AdmanConfigValid` (line 241); otherwise user-edited `WinRM`/`CIM` values could be overwritten or the validator could see missing keys.
- **MEDIUM — Skipped-count double-counting risk**: `03-02` task 2 increments `$skipped` when `Connect-AdmanTarget` returns `'Skipped'`, then again if the per-host cap is exceeded "if not already counted". That conditional logic is easy to get wrong; a simpler invariant is to increment once per row whose final `Transport` is `'Skipped'`.
- **MEDIUM — Brittle static class-name parser**: `03-03` task 2 parses `-ClassName` literals in source files to prove only two classes are queried. If class names are later moved into variables or constants (a reasonable refactor), this test breaks even though the runtime allow-list still enforces the policy.
- **LOW — Inaccurate file list in `03-01` task 1**: It says to update "the `New-AdmanTestConfig` builders in `tests/Config.Load.Tests.ps1`, `tests/Config.FailClosed.Tests.ps1`, `tests/Config.NoSecrets.Tests.ps1`, and `tests/Config.RoundTrip.Tests.ps1`". `tests/Config.NoSecrets.Tests.ps1` has no builder; it reads the real `config/adman.defaults.json` directly.
- **LOW — Negative `TimeoutSeconds` can be passed when cap is exceeded**: In `03-02` task 2, `$remainingSeconds` may be `0` or negative when the per-host cap is exhausted. `Invoke-AdmanRemoteQuery` short-circuits on `'Skipped'`, so it is safe, but the parameter should probably be clamped to a minimum of `1` to avoid surprising a future caller.

### Suggestions

- Replace real sleeps in cap-enforcement tests with a test-only stopwatch seam or mock `Test-AdmanWsmanTimeout`/`Connect-AdmanTarget` to record elapsed time without blocking.
- Explicitly state the merge step location in `Private/Config/Initialize-AdmanConfig.ps1` (after line 228, before line 241) and add a unit test proving existing `WinRM`/`CIM` values survive.
- Simplify the skipped-count logic in `Get-AdmanInventoryReport` to increment `$skipped` once, based on the final `$transport` value.
- Make the static class-name test a positive-control complement to the runtime allow-list rather than a hard gate, or add a clear comment that maintainers must update it if class names are refactored into variables.
- Put the new remote-enrichment columns before `Bucket` in `$computerReportProperties` (`Private/Menu/Get-AdmanMenuDefinition.ps1:83`) so `Bucket` remains the rightmost report column.

### Risk Assessment

**MEDIUM**

The plans cover the phase goals and follow the locked D-01 through D-07 decisions. The MEDIUM risks are implementation-detail and test-quality issues, not design flaws. The biggest practical risk is slow tests causing the suite to drag; the biggest correctness risk is the config merge step overwriting user values if placed incorrectly. Both are fixable with tighter plan wording.

---

## Consensus Summary

With only one reviewer available, the consensus is the Claude review above. The plans are fundamentally sound and closely follow the locked decisions in `03-CONTEXT.md`. The highest-priority improvements before execution are:

1. Remove real-time sleeps from cap-enforcement tests to keep the suite fast.
2. Pin the config-merge step to a specific location in `Initialize-AdmanConfig.ps1` and add a regression test.
3. Simplify the skipped-host counting logic in `Get-AdmanInventoryReport`.

### Agreed Strengths

- Remote logic is quarantined in `Private/Remoting/`; no new Public verbs are required.
- `Test-WSMan` timeout wrapper is 5.1-safe.
- Process-only transport-name cache avoids live-session fragility.
- Double-hop stance is enforced structurally (allow-list + static tests) not just documented.
- Existing configs are upgraded transparently via additive defaults.

### Agreed Concerns

- **MEDIUM:** Cap-enforcement tests use real sleeps, which will slow the suite.
- **MEDIUM:** Config merge placement is unspecified; a misplaced merge could overwrite user values or fail validation.
- **MEDIUM:** Skipped-count logic uses a conditional that is easy to get wrong.
- **MEDIUM:** Static class-name parser is brittle against reasonable refactoring.

### Divergent Views

None — single reviewer.

---

## Verification Coverage

Source files referenced or inspected during this review:

- `.planning/phases/03-remote-computer-operations-isolated/03-01-PLAN.md`
- `.planning/phases/03-remote-computer-operations-isolated/03-02-PLAN.md`
- `.planning/phases/03-remote-computer-operations-isolated/03-03-PLAN.md`
- `.planning/phases/03-remote-computer-operations-isolated/03-CONTEXT.md`
- `.planning/phases/03-remote-computer-operations-isolated/03-RESEARCH.md`
- `.planning/PROJECT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `adman.psd1`
- `adman.psm1`
- `Public/Get-AdmanInventoryReport.ps1`
- `Public/Test-AdmanCapability.ps1`
- `Private/Config/Initialize-AdmanConfig.ps1`
- `config/adman.schema.json`
- `config/adman.defaults.json`
- `tests/Result.Schema.Tests.ps1`

Review generated by the only available AI CLI (`claude`) while running inside Claude Code.
