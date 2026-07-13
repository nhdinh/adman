---
phase: 00-foundation-safety-harness
plan: 04
subsystem: safety
tags: [powershell, active-directory, pester, psscriptanalyzer, whatif, audit, tdd]

# Dependency graph
requires:
  - phase: 00-foundation-safety-harness
    provides: "00-01 module scaffold + manifest + FunctionsToExport boundary; 00-02 config loader (safety.bulkConfirmThreshold, bulk.maxCount, ManagedOUs, DenyList); 00-03 credential decision + capability probe + startup orchestration ($script:Config, $script:ProtectedGroupDns, $script:DenyRids)"
provides:
  - "Resolve-AdmanTarget — single resolver (preview ≡ execute, SAFE-10)"
  - "Test-AdmanTargetAllowed — accumulating target policy (gMSA pre-filter, deny-RID, managed-OU scope, IN_CHAIN protected membership; SAFE-05/06/07)"
  - "Escape-AdmanLdapFilterValue — RFC-4515 assertion-value escaping (C2-L1)"
  - "Get-AdmanAllowedWriteVerbs — 9-verb allow-list (Remove-ADObject absent, SAFE-09)"
  - "Confirm-AdmanAction — scaled confirmation returning Outcome shape (SAFE-01/02, C3-H1)"
  - "Assert-AdmanBulkPolicy — cap placeholder (Phase 4 enforces, BULK-02)"
  - "Adman.AD.Write.* — 9 gate-only AD write wrappers (sole callers of real AD cmdlets, SAFE-08/09)"
  - "Invoke-AdmanMutation — THE GATE: single non-exported mutation funnel (SAFE-08)"
affects: [all future phases — every destructive action flows through Invoke-AdmanMutation; Phase 4 bulk enforcement; any plan that mutates AD]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single non-exported mutation gate (SAFE-08): all destructive verbs funnel through Invoke-AdmanMutation"
    - "Gate-only AD write wrappers (Adman.AD.Write.<Verb>) are the SOLE callers of real AD cmdlets"
    - "confirm-first audit (C3-H1): a declined action writes ZERO records — no orphan PENDING"
    - "Write-ahead audit reservation (SAFE-04): PENDING-write failure refuses BEFORE the mutation"
    - "preview ≡ execute via ONE resolver, same array reference (SAFE-10)"
    - "-WhatIf detection is [bool]$WhatIfPreference (boolean cast), NEVER the string 'Simulate' (C3-H1/C4-H1)"
    - "Token-count confirmation guards use -cne (refuse on mismatch), NEVER inverted -ceq (SAFE-02)"
    - "Component-boundary-anchored DN suffix test for scope (SAFE-07), never -like substring"
    - "Deny-list by objectSid RID (SAFE-05), never sAMAccountName (RID-500 rename)"
    - "RFC-4515 LDAP escaping before any DN/value interpolation into a filter (C2-L1)"

key-files:
  created:
    - Private/Safety/Resolve-AdmanTarget.ps1
    - Private/Safety/Test-AdmanTargetAllowed.ps1
    - Private/Safety/Escape-AdmanLdapFilterValue.ps1
    - Private/Safety/AdmanWriteVerbs.ps1
    - Private/Safety/Confirm-AdmanAction.ps1
    - Private/Safety/Assert-AdmanBulkPolicy.ps1
    - Private/Safety/Invoke-AdmanMutation.ps1
    - Private/AD/Adman.AD.Write.ps1
    - tests/Safety.Scope.Tests.ps1
    - tests/Safety.DenyList.Tests.ps1
    - tests/Safety.Protected.Tests.ps1
    - tests/Safety.PreviewEqualsExecute.Tests.ps1
    - tests/Safety.Confirm.Tests.ps1
    - tests/Safety.NoHardDelete.Tests.ps1
    - tests/Safety.GateOrder.Tests.ps1
  modified: []

key-decisions:
  - "-WhatIf detection is the boolean cast [bool]$WhatIfPreference, NEVER a string comparison to 'Simulate' — the engine sets a SwitchParameter $true under a real -WhatIf and never produces the string 'Simulate', so a string compare misclassifies every dry-run as a decline (C3-H1/C4-H1)"
  - "Confirm-AdmanAction checks -WhatIf FIRST and returns Outcome='DryRun'/WhatIf=$true without prompting or throwing; the GATE owns the decline throw and all audit writes (confirm-first → no orphan PENDING)"
  - "Genuine decline writes ZERO audit records (no PENDING, no abort/cancel-style record) so a declined action leaves no orphan reservation"
  - "Resolve-AdmanTarget Identity parameter set has NO -SearchBase/-SearchScope (it has -Partition); scope is enforced downstream in Test-AdmanTargetAllowed step (c) — mixing parameter sets throws 'Parameter set cannot be resolved' (C2-H1)"
  - "Cap enforcement is deferred to Phase 4 (BULK-02); Phase 0 Assert-AdmanBulkPolicy only reads bulk.maxCount + safety.bulkConfirmThreshold and exposes a forward-compat -EnforceCap switch"

patterns-established:
  - "Pester 6 mocking: Mock <cmdlet> -ModuleName adman; mock bodies run in the test file's script scope, so a $script:-scoped recorder list is visible to the mocks (00-03 Deviation 2)"
  - "Named binding into the module-scope scriptblock: & (Get-Module adman) { param($p) ... } -p $val (positional -ArgumentList does not bind object args on PS 5.1)"
  - "PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive so the exact-pinned manifest dependency resolves (real install is human-gated)"
  - "Static source scans check comments too: doc comments must avoid literal banned tokens (sAMAccountName, adminCount, 'Simulate', $Confirm)"
  - "Select-String over a -Raw string returns ONE MatchInfo per pattern, not per occurrence — use [regex]::Matches for occurrence counts"
  - "Mock Resolve-AdmanTarget must output a FLAT array (no unary comma) or the gate's @(...) wraps it into a nested array and per-target iteration breaks"

requirements-completed: [SAFE-01, SAFE-02, SAFE-05, SAFE-06, SAFE-07, SAFE-08, SAFE-09, SAFE-10]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Managed-OU scope uses a component-boundary-anchored DN suffix test (SAFE-07)"
    requirement: SAFE-07
    verification:
      - kind: unit
        ref: "tests/Safety.Scope.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D2
    description: "Deny-list matches by objectSid RID, not sAMAccountName (SAFE-05)"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "tests/Safety.DenyList.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D3
    description: "Protected-account detection: gMSA pre-filter + ONE DC-side IN_CHAIN query, RFC-4515 escaped, never adminCount (SAFE-06)"
    requirement: SAFE-06
    verification:
      - kind: unit
        ref: "tests/Safety.Protected.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D4
    description: "Preview ≡ execute via ONE resolver; 9-verb allow-list excludes Remove-ADObject (SAFE-10/09)"
    requirement: SAFE-10
    verification:
      - kind: unit
        ref: "tests/Safety.PreviewEqualsExecute.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D5
    description: "Scaled confirmation returns Outcome shape; -WhatIf is a dry-run not a decline (SAFE-01/02, C3-H1)"
    requirement: SAFE-01
    verification:
      - kind: unit
        ref: "tests/Safety.Confirm.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D6
    description: "Gate-only AD write wrappers (9, no hard-delete) + bulk-policy cap placeholder (SAFE-09/02)"
    requirement: SAFE-09
    verification:
      - kind: unit
        ref: "tests/Safety.NoHardDelete.Tests.ps1"
        status: pass
    human_judgment: false
  - id: D7
    description: "THE GATE: fixed order, PENDING-before-write, confirm-first decline, -WhatIf flow (SAFE-08/04, C3-H1)"
    requirement: SAFE-08
    verification:
      - kind: unit
        ref: "tests/Safety.GateOrder.Tests.ps1"
        status: pass
    human_judgment: false

# Metrics
duration: 38min
completed: 2026-07-13
status: complete
---

# Phase 00 Plan 04: The Safety Core Summary

**Single non-exported mutation gate (Invoke-AdmanMutation) funneling every destructive AD action through one resolver, an accumulating target policy, scaled confirmation, and a write-ahead audit reservation — with 9 gate-only AD write wrappers as the sole callers of real AD cmdlets and the hard-delete verb deliberately absent.**

## Performance

- **Duration:** 38 min
- **Started:** 2026-07-13T01:24:26Z
- **Completed:** 2026-07-13T02:02:29Z
- **Tasks:** 3
- **Files modified:** 15 (8 source + 7 test)

## Accomplishments

- **THE GATE (SAFE-08):** `Invoke-AdmanMutation` is the single, non-exported mutation funnel. Every destructive verb flows through the fixed order: Resolve → Allow(per target) → BulkPolicy → Confirm → Audit(PENDING) → Write → Audit(Success). It is excluded from `FunctionsToExport` and never calls a real AD cmdlet directly — only via `& "Adman.AD.Write.$Verb"`.
- **confirm-first + write-ahead (C3-H1 / SAFE-04):** `Confirm-AdmanAction` checks `[bool]$WhatIfPreference` FIRST and returns an `Outcome` shape; a genuine decline throws in the gate and writes ZERO audit records (no orphan PENDING). The PENDING reservation is written BEFORE the mutation, so a PENDING-write failure refuses the action before any AD change.
- **preview ≡ execute (SAFE-10):** ONE resolver materializes the target array once; the same array feeds both the `-WhatIf` preview and the execute loop, so the preview cannot lie.
- **No hard delete (SAFE-09):** exactly 9 `Adman.AD.Write.*` wrappers (the sole callers of real AD cmdlets); the wrapper set EQUALS `Get-AdmanAllowedWriteVerbs`; `Remove-ADObject` has no wrapper — "delete" is a reversible disable+quarantine.
- **Target policy (SAFE-05/06/07):** accumulating refusals — gMSA objectClass pre-filter FIRST, deny-list by objectSid RID (not sAMAccountName), component-boundary-anchored managed-OU scope, and ONE DC-side IN_CHAIN protected-membership query with RFC-4515 escaping (never adminCount).
- **68/68 Pester 6 tests GREEN** across 7 Safety test files; repo-wide PSScriptAnalyzer (standard + custom safety rule) clean.

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1: Resolver + target policy (SAFE-05/06/07/09/10)**
   - RED `299d433` (test) → GREEN `9d9f3f8` (feat)
2. **Task 2: Confirmation + bulk-policy + gate-only AD write wrappers (SAFE-01/02/09)**
   - RED `6db2625` (test) → GREEN `cf3a043` (feat)
3. **Task 3: The mutation gate Invoke-AdmanMutation (SAFE-08)**
   - RED `0d1ed84` (test) → GREEN `f1b2388` (feat)

**Plan metadata:** _pending_ (docs: complete plan)

## Files Created/Modified

- `Private/Safety/Resolve-AdmanTarget.ps1` — single resolver; `Get-ADObject -Identity` with no `-SearchBase`/`-SearchScope` (C2-H1); scope enforced downstream.
- `Private/Safety/Test-AdmanTargetAllowed.ps1` — accumulating policy: gMSA pre-filter → deny-RID → managed-OU scope (component-boundary) → IN_CHAIN protected membership (RFC-4515 escaped, `-LDAPFilter` only).
- `Private/Safety/Escape-AdmanLdapFilterValue.ps1` — RFC-4515 assertion-value escaping (`\` `*` `(` `)` NUL).
- `Private/Safety/AdmanWriteVerbs.ps1` — `Get-AdmanAllowedWriteVerbs` returns the 9-verb allow-list.
- `Private/Safety/Confirm-AdmanAction.ps1` — scaled confirmation returning `@{Outcome; WhatIf}`; `-WhatIf` first; never writes audit, never throws the decline.
- `Private/Safety/Assert-AdmanBulkPolicy.ps1` — reads cap + threshold; throws only with `-EnforceCap` (Phase 4 forward-compat).
- `Private/Safety/Invoke-AdmanMutation.ps1` — THE GATE (see Accomplishments).
- `Private/AD/Adman.AD.Write.ps1` — 9 gate-only wrappers; pin `-Server`, forward `-WhatIf:$WhatIfPreference -Confirm:$false`.
- `tests/Safety.{Scope,DenyList,Protected,PreviewEqualsExecute,Confirm,NoHardDelete,GateOrder}.Tests.ps1` — 7 Pester 6 test files (68 tests).

## Decisions Made

- **`[bool]$WhatIfPreference`, never `'Simulate'`:** the engine sets a SwitchParameter `$true` under a real `-WhatIf` and never produces the string `'Simulate'`; a string compare would misclassify every dry-run as a decline (C3-H1/C4-H1). Verified: `Simulate` literal count = 0 in the gate.
- **confirm-first:** `Confirm-AdmanAction` never writes audit and never throws the decline; the gate owns both. A declined action writes ZERO records so there is no orphan PENDING.
- **Scope enforced downstream, not in the resolver:** `Resolve-AdmanTarget` uses the Identity parameter set (no `-SearchBase`/`-SearchScope`); mixing parameter sets throws `'Parameter set cannot be resolved'` (C2-H1). Managed-OU scope is step (c) of `Test-AdmanTargetAllowed`.
- **Cap enforcement deferred:** Phase 0 `Assert-AdmanBulkPolicy` only reads `bulk.maxCount` + `safety.bulkConfirmThreshold` and exposes `-EnforceCap` for Phase 4 (BULK-02); it does not enforce in Phase 0.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Doc-comment tokens tripped static source scans (Task 1)**
- **Found during:** Task 1 (resolver + target policy)
- **Issue:** Static scans check comments too; doc comments in `Test-AdmanTargetAllowed.ps1` contained the literal tokens `sAMAccountName` and `adminCount`, failing the "never used" assertions.
- **Fix:** Reworded comments to "never matched by account name" and "the stale-on-removal admin-count attribute is NEVER read".
- **Files modified:** `Private/Safety/Test-AdmanTargetAllowed.ps1`
- **Verification:** 36/36 Task 1 tests GREEN.
- **Committed in:** `9d9f3f8` (Task 1 GREEN)

**2. [Rule 1 - Bug] `Select-String` over a `-Raw` string under-counts occurrences (Task 2)**
- **Found during:** Task 2 (confirmation + wrappers)
- **Issue:** `Select-String` over a `-Raw` string returns ONE MatchInfo per pattern, not per occurrence — `SupportsShouldProcess` counted 1 instead of ≥9.
- **Fix:** Switched occurrence counts to `[regex]::Matches($src, 'pattern').Count`.
- **Files modified:** `tests/Safety.NoHardDelete.Tests.ps1`
- **Verification:** Task 2 tests GREEN.
- **Committed in:** `cf3a043` (Task 2 GREEN)

**3. [Rule 1 - Bug] Doc-comment literals tripped Task 2 static scans (Task 2)**
- **Found during:** Task 2
- **Issue:** Doc comments contained the literal `'Simulate'` comparison and the automatic `$Confirm` variable name, matching forbidden patterns.
- **Fix:** Reworded to "NEVER a string comparison against the literal word 'Simulate'" and "automatic confirm-flag variable". Verified SIMULATE=0 / BOOL_CAST=3 via a file-based script (shell-quoting of `\`/`\[` in double-quoted `-Command` produced false 0s).
- **Files modified:** `Private/Safety/Confirm-AdmanAction.ps1`
- **Verification:** Task 2 tests GREEN.
- **Committed in:** `cf3a043` (Task 2 GREEN)

**4. [Rule 1 - Bug] Nested-array mock broke per-target iteration in the gate (Task 3)**
- **Found during:** Task 3 (the gate)
- **Issue:** `Mock Resolve-AdmanTarget { , @($t1) }` returns a unary-comma-wrapped array; the gate's `$resolved = @(Resolve-AdmanTarget ...)` then produced a NESTED array `@(@($t1))`. The `foreach` iterated once over the blob, so `$t.DistinguishedName` was an array, the conditional `Test-AdmanTargetAllowed` mock refused the whole blob, and the write wrapper ran 0 times.
- **Fix:** Removed the unary comma so mocks output a FLAT array (`{ $t1 }`, `{ $tAllowed; $tDenied }`). Diagnosed via 4 throwaway debug scripts (deleted after).
- **Files modified:** `tests/Safety.GateOrder.Tests.ps1`
- **Verification:** Test 3 (refused target) and all gate tests pass.
- **Committed in:** `f1b2388` (Task 3 GREEN)

**5. [Rule 1 - Bug] Static gate-order assertions matched doc comments, not code (Task 3)**
- **Found during:** Task 3
- **Issue:** `IndexOf("'PENDING'")` and the "no direct AD write cmdlet" regex matched doc-comment / ValidateSet occurrences first, not the actual call sites — PENDING-precedes-write and the banned-verb count both failed.
- **Fix:** Anchored PENDING/write on the real statements (`-Result 'PENDING'` and `& "Adman.AD.Write.$Verb" -Objects`); required a banned verb be followed by whitespace + `-` (a real call) so ValidateSet string literals and comments don't match.
- **Files modified:** `tests/Safety.GateOrder.Tests.ps1`
- **Verification:** 8/8 gate tests GREEN.
- **Committed in:** `f1b2388` (Task 3 GREEN)

---

**Total deviations:** 5 auto-fixed (all Rule 1 - Bug)
**Impact on plan:** All auto-fixes were test-harness correctness fixes (mock shape, regex occurrence counting, comment-token hygiene) — no scope creep, no change to the safety design. The gate implementation itself required no deviation.

## Issues Encountered

- **Pester 3.4 vs 6.0.0:** the default `powershell` scope resolves Pester 3.4 (which rejects `BeforeAll` outside `Describe`). Pester 6.0.0 is a PSResourceGet user-scope install not on the default `$env:PSModulePath`; tests must be run via `Import-Module '...\Pester\6.0.0\Pester.psd1' -Force` before `Invoke-Pester`. Same for PSScriptAnalyzer 1.25.0. Resolved by importing the explicit module paths.
- **Shell-quoting artifacts:** bash→PowerShell double-quoted `-Command` mangled regex escapes (`\`/`\[`/`\$`), producing false 0 counts. Resolved by using file-based `.ps1` scripts (in `.gsd/`, deleted after) for discriminator verification.

## User Setup Required

None - no external service configuration required. (PSFramework real install remains human-gated; tests use a throwaway stub.)

## Next Phase Readiness

- **The safety core is complete and load-bearing.** Every future destructive action MUST flow through `Invoke-AdmanMutation`; the 9 `Adman.AD.Write.*` wrappers are the only permitted callers of real AD cmdlets.
- **Ready for 00-05** (the audit writer that the gate's PENDING/OUTCOME calls depend on — currently mocked in tests) and Phase 4 bulk-cap enforcement (BULK-02) via the `-EnforceCap` forward-compat switch.
- **No blockers.** The `Assert-AdmanBulkPolicy` cap is intentionally a Phase-0 placeholder.

## Self-Check: PASSED

- Created files exist: `Private/Safety/Invoke-AdmanMutation.ps1`, `Private/AD/Adman.AD.Write.ps1`, all 7 `tests/Safety.*.Tests.ps1` — FOUND.
- Commits exist: `299d433`, `9d9f3f8`, `6db2625`, `cf3a043`, `0d1ed84`, `f1b2388` — FOUND in `git log`.
- All 7 Safety test files: 68/68 GREEN. Repo-wide lint clean.

---
*Phase: 00-foundation-safety-harness*
*Completed: 2026-07-13*
