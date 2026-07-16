---
phase: 3
reviewers: [claude]
reviewed_at: 2026-07-16T22:40:00+00:00
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

The Phase 3 plans are well-scoped and faithful to the locked decisions in `03-CONTEXT.md`. They correctly isolate remoting behind `Private/Remoting/`, keep the cache to a transport-name string only, exclude CredSSP/live actions, and auto-enrich the existing `Get-AdmanInventoryReport` rather than inventing a new report verb. The main execution risks are around **soft timeout enforcement** (the cap may be exceeded by CIM connection/setup time and by multiple CIM operations), **config-upgrade ordering**, and some minor interface drift (help text, query-error handling, and the unused `Skipped` value in the generic CIM helper).

### Strengths

- **Clean isolation.** All remote logic lives in `Private/Remoting/`. No new Public verbs are added, so `adman.psd1:53` `FunctionsToExport` does not need changes and the SAFE-08 export boundary remains intact.
- **5.1-safe timeout wrapper.** Using `Start-Job` + `Wait-Job -Timeout` for `Test-WSMan` directly addresses the verified 5.1 limitation documented in `03-RESEARCH.md` (“Pitfall 1”).
- **Cache is name-only.** `$script:TransportCache = @{}` in `adman.psm1:29` and the plan’s D-04 cache store only the transport string, avoiding session-lifetime fragility.
- **No CredSSP / no second-hop classes.** The allow-list in `Invoke-AdmanRemoteCimQuery` plus static tests for `CredSSP`, `Invoke-Command`, and `New-PSSession` enforce RMT-04/D-07 without relying only on documentation.
- **Upgrade path for existing configs.** The plan seeds missing `transport.timeouts.perHostProbeCap` / `totalInventoryRemoteCap` from `config/adman.defaults.json`, which prevents a fail-closed break on first run after update.
- **Inventory enrichment preserves the D-03 schema.** Remote columns are appended by `Get-AdmanInventoryReport.ps1` after `ConvertTo-AdmanResult`, so `tests/Result.Schema.Tests.ps1:192-196` remains valid.

### Concerns

- **HIGH — `New-CimSession` initial connection is not hard-capped.**
  `OperationTimeoutSec` bounds individual CIM operations, not the initial TCP connect (see `Public/Test-AdmanCapability.ps1:95` for the same pattern already in use). A dead host that silently drops packets can still hang the menu for the OS TCP timeout, even though the per-host stopwatch will mark it `Skipped` afterwards. The `Test-WSMan` job wrapper fixes the WinRM leg, but the CIM/WSMan and CIM/DCOM legs have no equivalent hard interrupt.

- **MEDIUM — per-host cap can be exceeded across the two CIM calls.**
  `Invoke-AdmanRemoteQuery` passes the *same* `TimeoutSeconds` value to `New-CimSession`, `Get-CimInstance Win32_OperatingSystem`, and `Get-CimInstance Win32_ComputerSystem` (`03-02-PLAN.md` Task 1 action). The combined probe + query time can therefore be up to ~3× `perHostProbeCap`, which violates the D-02 intent that the cap is a ceiling for the whole host.

- **MEDIUM — CIM query errors are not surfaced as `Skipped`.**
  The plan says `Invoke-AdmanRemoteQuery` should “catch a CIM query error … and return empty remote fields while preserving the supplied transport.” An access-denied host will therefore show `Transport = 'CimDcom'` with blank fields, not count toward the skipped summary, and not trigger the `Write-Warning`. This is a UX/forensics gap.

- **MEDIUM — config merge must run strictly before validation.**
  Adding `perHostProbeCap` and `totalInventoryRemoteCap` to the schema `required` list (`config/adman.schema.json:127`) means any existing `.store/config.json` without them will fail `Test-AdmanConfigValid` (`Private/Config/Initialize-AdmanConfig.ps1:241`) unless the merge step runs *before* that call. The plan says this, but it is the most brittle point of 03-01; a simple ordering mistake breaks every existing install.

- **LOW — `Invoke-AdmanRemoteCimQuery` accepts `Skipped` in its ValidateSet but cannot handle it.**
  The plan gives it `[ValidateSet('WinRM','CimWsman','CimDcom','Skipped')]`, yet its protocol logic `($Transport -replace '^Cim','')` would produce `Skipped` for `Skipped`, which is invalid for `New-CimSessionOption -Protocol`. The main path short-circuits in `Invoke-AdmanRemoteQuery`, so this is latent, but it is a foot-gun for future callers.

- **LOW — help text not updated.**
  `Public/Get-AdmanInventoryReport.ps1:3-9` still describes the report as “computer OS/inventory report” and says nothing about remote enrichment, the four new columns, or the possibility of `Skipped` hosts. DOC-03 is Phase 5, but the Public function should stay accurate as it changes.

- **LOW — `docs/` does not exist yet.**
  `docs/REMOTE-OPS.md` is the first file in a new directory. The plan notes it will be referenced from README/usage guide in Phase 5, but there is no placeholder in `README.md` today, so the doc could be orphaned.

- **LOW — `Invoke-AdmanRemoteCimQuery` may be dead code on the main path.**
  `Invoke-AdmanRemoteQuery` hardcodes the two allowed classes directly and does not call `Invoke-AdmanRemoteCimQuery`. The allow-list guard is therefore tested but not exercised by normal inventory enrichment, creating a small drift risk.

### Suggestions

- **Wrap `New-CimSession` creation in a hard-timeout job too**, or add a short `Start-Job`-wrapped TCP reachability probe before each CIM leg, so a silently-dropped host cannot exceed `perHostProbeCap` during session setup.
- **Recompute the remaining budget between operations in `Invoke-AdmanRemoteQuery`** (e.g., measure elapsed after session creation and before each `Get-CimInstance`), or explicitly document that the cap is a soft ceiling bounded by the number of CIM operations.
- **Treat query-layer exceptions as `Skipped`** in `Get-AdmanInventoryReport.ps1` rather than preserving the transport on empty fields, or return a failure flag from `Invoke-AdmanRemoteQuery` so the report can count the host as skipped and include the reason in verbose output.
- **Remove `'Skipped'` from `Invoke-AdmanRemoteCimQuery`’s ValidateSet** (or add an early return), since that helper is meant only for actual transports.
- **Update `Get-AdmanInventoryReport.ps1` comment-based help** to describe remote enrichment, the new columns, and the `Skipped` behavior.
- **Keep the config merge idempotent and non-writing:** merge missing defaults into the in-memory config before `Test-AdmanConfigValid` at `Private/Config/Initialize-AdmanConfig.ps1:241`, and avoid re-saving the file unless the user explicitly edits it, so the upgrade is transparent.
- **Add a null guard to `Convert-AdmanRemoteError`** so it never throws if called with a `$null` exception.

### Risk Assessment: MEDIUM

The phase goals (RMT-01 through RMT-04) are achievable with these plans, and the security stance (no CredSSP, no second-hop classes, name-only cache) is correct. The risk is **MEDIUM** rather than LOW because the per-host timeout cap is not reliably enforced for CIM session setup and can be exceeded across multiple CIM operations, and because the config schema upgrade has a single fragile ordering dependency. Neither is a fundamental design flaw; both can be fixed with tighter timeout wrappers and careful loader sequencing.

---

## Consensus Summary

With only one reviewer available, the consensus is the Claude review above. The plans are fundamentally sound and closely follow the locked decisions in `03-CONTEXT.md`. The highest-priority fixes before execution are:

1. Harden the CIM session-setup timeout so a silently-dropped host cannot exceed `perHostProbeCap`.
2. Ensure the remaining per-host budget shrinks between probe and query operations, or document the cap as soft.
3. Verify the config-loader merge runs strictly before schema validation to avoid breaking existing `.store/config.json` files.

### Agreed Strengths

- Remote logic is quarantined in `Private/Remoting/`; no new Public verbs are required.
- `Test-WSMan` timeout wrapper is 5.1-safe.
- Process-only transport-name cache avoids live-session fragility.
- Double-hop stance is enforced structurally (allow-list + static tests) not just documented.
- Existing configs are upgraded transparently via additive defaults.

### Agreed Concerns

- **HIGH:** `New-CimSession` TCP connect is not hard-capped; dead hosts may still hang the menu.
- **MEDIUM:** Per-host cap can be exceeded across multiple CIM operations.
- **MEDIUM:** CIM query errors are returned as empty fields with the original transport rather than counted as `Skipped`.
- **MEDIUM:** Config merge order is brittle; schema validation must happen after default merge.

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
- `.planning/phases/03-remote-computer-operations-isolated/03-VALIDATION.md`
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
