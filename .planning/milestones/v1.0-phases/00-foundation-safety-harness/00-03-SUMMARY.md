---
phase: 00-foundation-safety-harness
plan: 03
subsystem: safety
tags: [powershell, dpapi, export-clixml, sid-resolution, fail-closed, capability-probe, orchestration, pester, psscriptanalyzer]

requires:
  - phase: 00-01
    provides: Module loader (dot-source Private/** then Public/**; $ErrorActionPreference='Stop'), explicit FunctionsToExport boundary, Pester 6 + PSScriptAnalyzer 1.25.0 harness, custom SAFE-08 banned-verb rule, $script:Config slot.
  - phase: 00-02
    provides: config/adman.schema.json, fail-closed Initialize-AdmanConfig (-SetupMode exempt), SID-seeded DenyList, $script:Config keys (ManagedOUs, DC, AuditDir, AdmanProtectedGroup, delegatedAdminGroup, credentialPolicy.allowRememberMe, DenyList, transport).
provides:
  - Get-AdmanCredential decision (pass-through default; prompt only when rights insufficient; opt-in DPAPI remember-me; delete-and-reprompt on restore failure).
  - Read-AdmanRememberMeConsent (mockable consent checkbox, default-No).
  - Test-AdmanCapability (Public) read-only RSAT/domain/audit/recycle-bin/rights/transport probe with actionable guidance + fail-closed throws; exported.
  - Initialize-Adman (Public) full six-step startup orchestration replacing the 00-01 stub; -SetupMode for the wizard.
  - Resolve-AdmanDomainSid + Test-AdmanAuditWritable (zero-byte probe) + Get-AdmanProtectedIdentity startup resolver.
  - Session state for the gate: $script:DomainSid, $script:ForestRootSid, $script:ProtectedGroupDns, $script:ProtectedSIDs, $script:DenyRids, $script:Capability, $script:Credential, $script:Initialized.
affects:
  - 00-04 (the gate reads $script:DomainSid/ProtectedGroupDns/DenyRids; Invoke-AdmanMutation relies on this session state)
  - 00-05 (Write-AdmanAudit / Find-AdmanAuditOrphans strict-JSONL contract MUST match the zero-byte open-append+Flush($true) probe here)
  - Phase 1 Start-Adman (invokes Initialize-Adman; consumes $script:Capability for the startup banner)

tech-stack:
  added: []
  patterns:
    - "Rights-first, pass-through-by-default credential decision with opt-in DPAPI + delete-and-reprompt"
    - "Non-destructive rights probing (read managed OU + whoami /groups) feeding both credential decision and capability banner"
    - "Live-SID protected/deny resolution (no hard-coded SIDs); bare-RID deny tokens for fast gate checks"
    - "Fail-closed startup probes with short timeouts that degrade to flags (never hang) and throw only on empty scope / unwritable audit"
    - "Zero-byte audit-writability probe (open-append + Flush($true) + dispose) honoring the 00-05 strict-JSONL contract"
    - "Test-script-scope sequence recorder for asserting Pester mock call order without $global:"

key-files:
  created:
    - Private/Foundation/Get-AdmanCredential.ps1
    - Private/Foundation/Read-AdmanRememberMeConsent.ps1
    - Private/Foundation/Resolve-AdmanDomainSid.ps1
    - Private/Foundation/Test-AdmanAuditWritable.ps1
    - Private/Safety/Get-AdmanProtectedIdentity.ps1
    - Public/Test-AdmanCapability.ps1
    - tests/Credential.Dpapi.Tests.ps1
    - tests/Credential.PassThrough.Tests.ps1
    - tests/Foundation.Capability.Tests.ps1
    - tests/Initialize.Adman.Tests.ps1
  modified:
    - Public/Initialize-Adman.ps1
    - adman.psd1

key-decisions:
  - "Rights-first credential decision (CONF-06): pass-through returns $null when rights sufficient; prompt only when insufficient; stored DPAPI is consumed ONLY when insufficient AND allowRememberMe, and never short-circuits the rights check — this fixes the unreachable-prompt bug where an early allowRememberMe gate made the prompt path dead code."
  - "DPAPI restore-failure signals (CONF-04/D-06): CryptographicException 0x8009000B OR empty/null GetNetworkCredential().Password OR non-PSCredential (keyed-AES/corrupt) => delete the bad file and fall back to Get-Credential; Export-Clixml CurrentUser only (no -EncryptionKey anywhere)."
  - "Rights probed non-destructively (MENU-05/CONF-06/T-00-15): read the managed OU + whoami /groups for delegatedAdminGroup; NEVER an AD write (acceptance grep + Pester assert zero Set-AD*/Disable-AD*/New-AD*/Move-ADObject in Public/Test-AdmanCapability.ps1)."
  - "Protected set from live SIDs (D-02/D-05/T-00-03): DomainSID-512, forest-root-518/519 (A3), S-1-5-32-544/-548/-551/-549, DomainSID-525 (defense-in-depth), + AdmanProtectedGroup; DenyRids {500,501,502} kept as bare RIDs (+ full-SID tokens kept as-is); zero hard-coded domain SIDs."
  - "Initialize-Adman fixed six-step order (D-04): Initialize-AdmanConfig -> Test-AdmanAuditWritable -> Get-AdmanCredential -> Test-AdmanCapability -> Resolve-AdmanDomainSid -> Get-AdmanProtectedIdentity; -SetupMode runs config load only (wizard is mutation-free)."
  - "Test-AdmanAuditWritable writes ZERO bytes (open-append + Flush($true) + dispose; no marker) so 00-05's strict-JSONL Find-AdmanAuditOrphans never sees a non-JSON line (key_link 00-03<->00-05)."

patterns-established:
  - "Pattern: every startup resolver caches into $script:* and is re-resolvable on demand (Get-AdmanProtectedIdentity calls Resolve-AdmanDomainSid when DomainSid is absent), so the gate can read session state without caring about call order."
  - "Pattern: fail-closed probes return bool and let the orchestrator throw, keeping the throwing surface to exactly two sites (empty managed-OU; unwritable audit)."

requirements-completed: [MENU-05, CONF-04, CONF-06]

coverage:
  - id: D1
    description: "Pass-through-by-default credential decision: returns $null when rights sufficient (never prompts), prompts exactly once when rights insufficient even with allowRememberMe=$false (unreachable-prompt regression pinned)."
    requirement: "CONF-06"
    verification:
      - kind: unit
        ref: "tests/Credential.PassThrough.Tests.ps1#Get-AdmanCredential pass-through + rights decision (Tests 1a/1b/2a/2b/8 + rights-helper compute path)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Opt-in DPAPI remember-me (Export-Clixml CurrentUser, consent-gated) with delete-and-reprompt on CryptographicException 0x8009000B or empty/null password, keyed-AES rejected, no secret logged."
    requirement: "CONF-04"
    verification:
      - kind: unit
        ref: "tests/Credential.Dpapi.Tests.ps1#Get-AdmanCredential DPAPI restore + consent + no-secret (Tests 3/4a/4b/5a/5b/6/7)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Read-only startup capability probe (RSAT/domain/audit/recycle-bin/rights/transport) with actionable Write-PSFMessage guidance, short CIM timeout, caught-into-flags (never hangs), and exactly two FAIL-CLOSED throws (empty managed-OU; unwritable audit)."
    requirement: "MENU-05"
    verification:
      - kind: unit
        ref: "tests/Foundation.Capability.Tests.ps1#Test-AdmanCapability probe (Tests 1/2/2-static/3a/3b/4)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Startup protected-SID + deny-RID resolution from the live domain SID (DomainSID-512, forest-root-518/519, S-1-5-32-544/-548/-551/-549, DomainSID-525, AdmanProtectedGroup; DenyRids 500/501/502) with no hard-coded SID."
    requirement: "MENU-05"
    verification:
      - kind: unit
        ref: "tests/Foundation.Capability.Tests.ps1#Test 5 (Get-AdmanProtectedIdentity D-02/D-05/A3)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Initialize-Adman six-step startup orchestration in fixed order with -SetupMode running config load only (wizard mutation-free) and best-effort event-log registration; sets $script:Initialized."
    requirement: "MENU-05"
    verification:
      - kind: unit
        ref: "tests/Initialize.Adman.Tests.ps1#Test 6 (orchestration order) / Test 6 (SetupMode) / Test 6 (static)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Cross-machine / cross-user DPAPI restore re-prompt (CryptographicException 0x8009000B 'Key not valid for use in specified state') deletes the bad file and falls back to Get-Credential on a genuinely different user/machine."
    requirement: "CONF-04"
    verification: []
    human_judgment: true
    rationale: "DPAPI CurrentUser keys are bound to the originating user+machine; the 0x8009000B wrong-key path cannot be triggered on the build host. The plan's <verification> explicitly flags this as the manual end-of-phase human check (confirm on a second machine/user). The delete-and-reprompt code path itself is unit-proven by D2 Test 4a (which injects a CryptographicException with HResult 0x8009000B)."

duration: ~59m
completed: 2026-07-11
status: complete
---

# Phase 00 Plan 03: Credential Decision, Capability Probe & Startup Orchestration Summary

**Rights-first pass-through credential decision with opt-in DPAPI remember-me and delete-and-reprompt on restore failure, a read-only fail-closed startup capability probe with actionable guidance, and a fixed six-step `Initialize-Adman` orchestration that resolves the protected-SID/deny-RID sets from the live domain SID into the session flags the 00-04 gate will read (MENU-05, CONF-04/06, D-02/D-04/D-05).**

## Performance

- **Duration:** ~59 min (first RED 2026-07-10T23:49:10Z -> Task-2 GREEN 2026-07-11T00:48:17Z)
- **Started:** 2026-07-10T23:49:10Z
- **Completed:** 2026-07-11T00:49:18Z
- **Tasks:** 2 (both TDD: RED -> GREEN)
- **Files modified:** 12 (6 implementation + 4 test + Public/Initialize-Adman.ps1 + adman.psd1)

## Accomplishments

- `Get-AdmanCredential` (rights-first): pass-through returns `$null` when rights are sufficient (never prompts); prompts exactly once when insufficient **even with `allowRememberMe=$false`** (unreachable-prompt regression pinned by Test 8); stored DPAPI consumed only when insufficient + remember-me; restore failure (CryptographicException `0x8009000B`, empty/null `GetNetworkCredential().Password`, or non-PSCredential/keyed-AES) deletes the bad file and falls back to `Get-Credential`; `Export-Clixml` CurrentUser only, consent-gated; nothing secret logged. Co-located non-destructive `Test-AdmanRightsSufficient` (read managed OU + `whoami /groups`).
- `Read-AdmanRememberMeConsent` (default-No mockable consent checkbox).
- `Test-AdmanCapability` (Public, exported): read-only RSAT / domain(ADWS 9389) / audit / Recycle-Bin / rights / transport probe; actionable `Write-PSFMessage` guidance per false flag; short CIM timeout (`$probeTimeoutSec = 15`, `-OperationTimeoutSec`); domain/transport failures caught into flags (never hangs); exactly two FAIL-CLOSED throws (empty managed-OU; unwritable audit). **Zero** AD-write cmdlets (verified by grep + Pester).
- `Initialize-Adman` (Public, replaces the 00-01 stub): fixed six-step order `Initialize-AdmanConfig -> Test-AdmanAuditWritable -> Get-AdmanCredential -> Test-AdmanCapability -> Resolve-AdmanDomainSid -> Get-AdmanProtectedIdentity`; `-SetupMode` runs config load only and skips the fail-closed throws + AD-touching resolution (wizard is mutation-free); best-effort event-log source registration; sets `$script:Initialized=$true`.
- `Resolve-AdmanDomainSid` (caches `$script:DomainSid` + `$script:ForestRootSid` from live `Get-ADDomain`/`Get-ADForest`, `-Server`-pinned, fail-closed) and `Get-AdmanProtectedIdentity` (builds `$script:ProtectedGroupDns`/`ProtectedSIDs` from `DomainSID-512`, forest-root `518/519` (A3), `S-1-5-32-544/-548/-551/-549`, `DomainSID-525`, + `AdmanProtectedGroup`; sets `$script:DenyRids = {500,501,502}` + full-SID tokens; **no hard-coded domain SID**).
- `Test-AdmanAuditWritable` zero-byte probe (open-append + `Flush($true)` + dispose, **no marker**) honoring the 00-05 strict-JSONL contract (`Find-AdmanAuditOrphans` / `Write-AdmanAudit`).
- `adman.psd1` `FunctionsToExport` appended with `Test-AdmanCapability` (still excludes `*` and the private `Invoke-AdmanMutation` gate); `Test-ModuleManifest` valid.
- Gates green: **24/24 Pester** (14 credential + 10 Task-2), **0** repo-wide `Invoke-ScriptAnalyzer` findings (incl. the custom SAFE-08 rule), all 16 acceptance greps pass.

## Task Commits

Each task was committed atomically (RED -> GREEN per TDD task):

1. **Task 1 RED: failing credential-decision + DPAPI tests** - `1518edf` (test) — `tests/Credential.Dpapi.Tests.ps1`, `tests/Credential.PassThrough.Tests.ps1` (14 failing tests).
2. **Task 1 GREEN: pass-through credential decision + opt-in DPAPI** - `d627161` (feat) — `Private/Foundation/Get-AdmanCredential.ps1`, `Private/Foundation/Read-AdmanRememberMeConsent.ps1`.
3. **Task 2 RED: failing capability-probe + Initialize-Adman orchestration tests** - `e963b63` (test) — `tests/Foundation.Capability.Tests.ps1`, `tests/Initialize.Adman.Tests.ps1` (10 failing tests).
4. **Task 2 GREEN: capability probe + Initialize-Adman orchestration + startup SID/deny resolution** - `28c3029` (feat) — `Public/Test-AdmanCapability.ps1`, `Public/Initialize-Adman.ps1`, `Private/Foundation/Resolve-AdmanDomainSid.ps1`, `Private/Foundation/Test-AdmanAuditWritable.ps1`, `Private/Safety/Get-AdmanProtectedIdentity.ps1`, `adman.psd1`, `tests/Initialize.Adman.Tests.ps1` (recorder-scope correction).

**Plan metadata (SUMMARY + tracking):** _this commit_ (docs: complete credential/capability/orchestration plan).

_Note: pre-existing dirty files (`.planning/config.json`, `.claude/settings.local.json`, `.gsd/`) were intentionally NOT staged in any task commit._

## Files Created/Modified

- `Private/Foundation/Get-AdmanCredential.ps1` — Rights-first credential decision + co-located `Test-AdmanRightsSufficient` (cheap managed-OU read + optional `whoami /groups`; any failure => `$false`).
- `Private/Foundation/Read-AdmanRememberMeConsent.ps1` — Default-No `Read-Host` consent gate (mockable).
- `Private/Foundation/Resolve-AdmanDomainSid.ps1` — Caches `$script:DomainSid`/`$script:ForestRootSid`; fail-closed throw if unresolvable.
- `Private/Foundation/Test-AdmanAuditWritable.ps1` — Zero-byte `FileStream` open-append + `Flush($true)` + dispose probe.
- `Private/Safety/Get-AdmanProtectedIdentity.ps1` — Startup protected-SID map + deny-RID resolver (placed under `Private/Safety/` per the pattern map; implemented here as startup resolution feeding session flags).
- `Public/Test-AdmanCapability.ps1` — Exported read-only capability probe + actionable guidance + fail-closed throws.
- `Public/Initialize-Adman.ps1` — Full six-step orchestration (replaces the 00-01 stub).
- `adman.psd1` — `FunctionsToExport` += `Test-AdmanCapability`.
- `tests/Credential.Dpapi.Tests.ps1`, `tests/Credential.PassThrough.Tests.ps1`, `tests/Foundation.Capability.Tests.ps1`, `tests/Initialize.Adman.Tests.ps1` — 24 behavior tests (fully mocked; no live domain/network/DPAPI).

## Decisions Made

- **Rights-first ordering (CONF-06):** rights are evaluated BEFORE reading the stored credential or returning; `allowRememberMe` is never an unconditional early `return $null` gate. This is the deliberate fix for the unreachable-prompt bug (Test 8 pins it: `allowRememberMe=$false` + insufficient rights still prompts).
- **DPAPI restore-failure definition (CONF-04/D-06):** `CryptographicException` `0x8009000B` **OR** empty/null `GetNetworkCredential().Password` **OR** a non-`[pscredential]` restore (keyed-AES/corrupt) all collapse to one outcome — delete the bad file + `Get-Credential` fallback. `Export-Clixml` CurrentUser only; no `-EncryptionKey` token anywhere in source.
- **Non-destructive rights probe (MENU-05/CONF-06/T-00-15):** `Get-ADOrganizationalUnit` (read) + `whoami /groups`; the capability probe and the credential decision share `Test-AdmanRightsSufficient` so rights are read exactly once and never via an AD write.
- **Live-SID protected/deny resolution (D-02/D-05/T-00-03):** protected set from `DomainSID-512`, forest-root `518/519` (A3), `S-1-5-32-544/-548/-551/-549`, `DomainSID-525` (defense-in-depth; unresolved pre-2012R2 RIDs are kept as SIDs for SID-based matching), + `AdmanProtectedGroup`; deny tokens kept as bare RIDs `{500,501,502}` for fast gate checks (the gate combines `DomainSid` + RID) with full-SID tokens kept as-is. Zero `S-1-5-21-` literals in source.
- **Transport degradation mirrors the project story:** `Test-WSMan` first; the optional `New-CimSession -Protocol Dcom` leg is attempted **only** when WinRM is unavailable (so a WinRM-up host never opens a DCOM session), with a short `-OperationTimeoutSec` so the menu never hangs.
- **Zero-byte audit probe:** the probe opens today's `audit-<yyyyMMdd>.jsonl` append/write/read-share, `Flush($true)`, dispose — emitting no bytes — so 00-05's strict-JSONL `Find-AdmanAuditOrphans` (which parses every line as JSON) never sees a non-JSON marker. Any positive probe record must go through `Write-AdmanAudit`.
- **Manifest/export discipline:** `FunctionsToExport` stays an explicit list (no `*`); the private gate `Invoke-AdmanMutation` (00-04) remains absent; `Test-AdmanCapability` appended so the runtime export set (loader) and the static boundary (manifest) match.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reworded a doc comment that tripped the no-secret-logging scan (Task 1)**
- **Found during:** Task 1 GREEN verification (Test 7).
- **Issue:** Test 7 scans every source line matching `Write-PSFMessage` for `\$cred|Password` (case-insensitive). A descriptive doc-comment line that mentioned both the diagnostic cmdlet and the word "password" on the same line was caught by the broad scan even though it was a comment, not a logging call.
- **Fix:** Reworded the comment so the literal `Write-PSFMessage` token and `password` never co-occur on one scanned line; the only real `Write-PSFMessage` call remains the static, secret-free "Stored credential unreadable; re-prompting." warning.
- **Files modified:** `Private/Foundation/Get-AdmanCredential.ps1`.
- **Verification:** Test 7 + the acceptance grep (any `Write-PSFMessage` line does not reference `$cred`/`Password`) pass; 14/14 credential tests green.
- **Committed in:** `d627161` (Task 1 GREEN).

**2. [Rule 3 - Blocking] Corrected the orchestration order-recorder scope in the RED test (Task 2)**
- **Found during:** Task 2 GREEN verification (Initialize.Adman Test 6 / SetupMode failed with "You cannot call a method on a null-valued expression").
- **Issue:** The RED test recorded mock call order into a list created in the **adman module scope** via `& (Get-Module adman) { $script:AdmanOrder = ... }`. Empirically verified (isolated probe) that `-ModuleName adman` mock bodies execute in the **test file's script scope**, not the module scope — so the module-scope list was `$null` inside the mocks and `.Add()` threw. The test was therefore failing for the WRONG reason (harness scoping), not the right reason (missing implementation), which breaks TDD RED integrity.
- **Fix:** Moved the recorder to the test file's script scope (`$script:AdmanOrder` in `BeforeAll`; `Reset-AdmanOrder` reassigns it; `Get-AdmanOrder` emits the flat array without the comma-wrap that the old module-boundary version needed). The six-step order assertion, the `-SetupMode` assertion, and the static order guard are byte-for-byte unchanged — only the recorder's scope was corrected so the mocks can actually record. No `$global:` introduced (stays `PSAvoidGlobalVars`-clean).
- **Files modified:** `tests/Initialize.Adman.Tests.ps1` (recorder scope + clarifying comments).
- **Verification:** 24/24 Pester green; repo-wide lint 0 findings (PSAvoidGlobalVars clean).
- **Committed in:** `28c3029` (Task 2 GREEN).

---

**Total deviations:** 2 auto-fixed (1 Rule-1 bug, 1 Rule-3 blocking test-harness fix).
**Impact on plan:** Both were necessary for correctness — the comment fix keeps the no-secret-logging invariant enforceable, and the recorder-scope fix restores TDD RED integrity (RED now fails for the right reason). No scope creep; production behavior is exactly as the plan specified.

## Issues Encountered

- **PSScriptAnalyzer `PSUseShouldProcessForStateChangingFunctions` verb set (verified empirically):** on 1.25.0 the rule flags ONLY `Set`/`New`-verb functions, not `Initialize`/`Resolve`/`Test`/`Get`/`Read`. So `Initialize-Adman` (orchestrator, not an AD write) correctly carries no `SupportsShouldProcess`; the real `-WhatIf` enforcement lands on the 00-04 write verbs/gate. No over/under-decoration needed; repo-wide lint stays at 0.
- **`Test-ModuleManifest` on this host:** the manifest's exact-pinned `RequiredModules` (`PSFramework` `RequiredVersion='1.14.457'`, set in 00-01) is not installed on this machine (the real install is human-gated). Structural validity — including the appended `Test-AdmanCapability` export resolving and `*`/`Invoke-AdmanMutation` remaining excluded — was validated against the build-time-verified `1.14.457` stub that the tests already use. This is environmental, not a defect in the manifest edit.

## Known Stubs

None. All created/modified files are fully wired to live session state and mocked dependencies; no hardcoded empty values flow to UI, no `TODO`/`FIXME`/`placeholder`/`coming soon` markers. The `DomainSID-525` (Protected Users) entry is intentional defense-in-depth (kept as a SID when unresolvable pre-2012R2), not a stub.

## Threat Flags

None beyond the plan's `<threat_model>`. The `FileStream` audit probe (T-00-05 surface), the read-only ADWS/WinRM/CIM probes (T-00-15), and the live-SID resolution (T-00-03) are all enumerated in the plan's STRIDE register; no new network endpoints, auth paths, file-access patterns, or schema changes at trust boundaries were introduced.

## User Setup Required

None for this plan's code paths. The plan's `user_setup` notes that `delegatedAdminGroup` (used only for the startup rights hint/banner) is environment-specific runtime config supplied via `Set-AdmanConfig` / the init wizard — it is never a sole blocker and is not required for any test or for the fail-closed guarantees.

## Next Phase Readiness

- **00-04 (the gate) is unblocked:** `$script:DomainSid`, `$script:ForestRootSid`, `$script:ProtectedGroupDns`, `$script:ProtectedSIDs`, and `$script:DenyRids` are populated by `Initialize-Adman` in the exact order the gate expects; `Test-AdmanTargetAllowed` can read `DomainSid` + bare RIDs `{500,501,502}` directly.
- **00-05 (audit) contract pinned:** the zero-byte open-append + `Flush($true)` probe here is the startup admission that `Write-AdmanAudit`'s fail-closed writer must match, and `Find-AdmanAuditOrphans` will never see a non-JSON line from this probe.
- **Phase 1 `Start-Adman`:** can call `Initialize-Adman` and read `$script:Capability` (+ its per-flag guidance) for the startup banner without re-probing.
- **One manual check carried to end-of-phase (not a blocker):** the cross-machine/user DPAPI `0x8009000B` re-prompt (coverage D6) requires a second machine/user to exercise; the delete-and-reprompt code path is unit-proven (D2 Test 4a).

## Self-Check: PASSED

Verified on disk before state updates:
- Created files exist: `Private/Foundation/Resolve-AdmanDomainSid.ps1`, `Private/Foundation/Test-AdmanAuditWritable.ps1`, `Private/Safety/Get-AdmanProtectedIdentity.ps1`, `Public/Test-AdmanCapability.ps1` — all FOUND.
- Modified files present with expected content: `Public/Initialize-Adman.ps1` (six-step body), `adman.psd1` (`Test-AdmanCapability` in `FunctionsToExport`).
- Commits exist: `1518edf`, `d627161`, `e963b63`, `28c3029` — all FOUND in `git log --oneline --all`.
- Gates: 24/24 Pester; 0 repo-wide PSScriptAnalyzer findings; `Test-ModuleManifest` VALID (PSFramework stub-resolvable); 16/16 acceptance greps pass.

---
*Phase: 00-foundation-safety-harness*
*Plan: 03*
*Completed: 2026-07-11*
