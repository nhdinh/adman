---
status: testing
phase: 00-foundation-safety-harness
source: [00-VERIFICATION.md]
started: 2026-07-13T00:00:00.000Z
updated: 2026-07-14T00:00:00.000Z
---

## Current Test

number: 2
name: Optionally run the -Tag Integration tests against a disposable lab OU (set ADMAN_TEST_OU) to confirm SAFE-01/06/10 end-to-end -WhatIf and protected-account refusal
expected: |
  AD is unchanged after a gated -WhatIf; the audit target list equals the resolved list; nested-DA / gMSA / renamed-RID-500 fixtures are Refused with precise reasons.
awaiting: user response

## Tests

### 1. Approve and run the PSFramework/Pester/PSScriptAnalyzer install on a real workstation (00-01 user_setup / T-00-SC)
expected: Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0) installs cleanly; the module still imports and the Unit suite stays green against the REAL PSFramework (tests currently use a throwaway stub).
why_human: The package-legitimacy seam did not run in this environment; the first PSFramework install is a deliberate human-approved supply-chain gate, never auto-approved.
result: pass

### 2. Optionally run the -Tag Integration tests against a disposable lab OU (set ADMAN_TEST_OU) to confirm SAFE-01/06/10 end-to-end -WhatIf and protected-account refusal
expected: AD is unchanged after a gated -WhatIf; the audit target list equals the resolved list; nested-DA / gMSA / renamed-RID-500 fixtures are Refused with precise reasons.
why_human: Lab-only by design (T-00-18); requires a real disposable domain/OU. Excluded from the default Unit run and cannot be auto-proven on a host with no live AD (VALIDATION manual-only).
result: issue
reported: "Lab DC reachable via runas /netonly (host is joined to pgs.ptsc.com.vn, not lab.local; needed lab creds). After installing pinned PSFramework 1.14.457 and provisioning the lab OU + fixtures, both integration files fail with CommandNotFoundException: Invoke-AdmanMutation not recognized (WhatIf line 58; Protected lines 64/95/107). Root cause: the gate is deliberately NOT exported (adman.psd1 FunctionsToExport excludes it per SAFE-08), but the Integration tests call it directly instead of via & (Get-Module adman){ Invoke-AdmanMutation ... } — the pattern the passing Unit tests use (Safety.GateOrder.Tests.ps1). Latent defect in the TEST files, surfaced only on the first real lab run (test was blocked on all prior runs). gMSA/RID-500 case correctly returns Inconclusive (fixtures not provisioned)."
severity: major

### 3. Confirm DPAPI cross-machine/cross-user re-prompt (CONF-04)
expected: A stored credential restored on a different machine/user throws CryptographicException 0x8009000B (or yields an empty password); the bad file is deleted and Get-Credential is invoked as fallback.
why_human: DPAPI is key-bound to user/machine; the cross-machine restore failure cannot be exercised on a single host and needs a second machine/user.
result: [pending]

## Summary

total: 3
passed: 1
issues: 1
pending: 1
skipped: 0
blocked: 0

## Gaps

- truth: "Integration tests execute the mutation gate against a disposable lab OU and assert SAFE-01/06/10 end-to-end"
  status: failed
  reason: "User reported: CommandNotFoundException - Invoke-AdmanMutation not recognized in both Integration test files. The gate is deliberately not exported (FunctionsToExport, SAFE-08) but the tests call it directly instead of via & (Get-Module adman){ ... } as the passing Unit tests do."
  severity: major
  test: 2
  root_cause: "tests/Safety.WhatIf.Integration.Tests.ps1:58 and tests/Safety.Protected.Integration.Tests.ps1:64,95,107 call Invoke-AdmanMutation directly; the function is internal-only (not in FunctionsToExport), so it is not visible in the test scope after Import-Module. Latent until the first real lab run (test was blocked on all prior runs)."
  artifacts:
    - path: "tests/Safety.WhatIf.Integration.Tests.ps1"
      issue: "line 58 calls Invoke-AdmanMutation directly instead of via module scope"
    - path: "tests/Safety.Protected.Integration.Tests.ps1"
      issue: "lines 64, 95, 107 call Invoke-AdmanMutation directly instead of via module scope"
  missing:
    - "Wrap each Invoke-AdmanMutation call in & (Get-Module adman) { param($t) Invoke-AdmanMutation ... } $targets, passing the test-scope target DNs in as a param (the $script: test vars are not visible inside module scope)"
  debug_session: ""
  resolution: "FIXED in quick task 260714-ek6 (commits feac682 + bc3c6d7). All 4 call sites wrapped in module scope. Unit suite green (138 passed)."

- truth: "Integration tests initialize the module (config + derived safety state) before invoking the gate, so the gate can resolve targets and enforce scope/protected policy"
  status: failed
  reason: "User reported (after issue #1 fixed): PropertyNotFoundException 'The property DC cannot be found on this object' at Resolve-AdmanTarget.ps1:37. The gate resolves now, but $script:Config is empty."
  severity: major
  test: 2
  root_cause: "The integration tests only Import-Module -Force; they never run Initialize-Adman NOR inject $script:Config. adman.psm1:14 sets $script:Config=@{} and import is side-effect-free by design, so $script:Config.DC (Resolve-AdmanTarget:37, Test-AdmanTargetAllowed:82), $script:Config.ManagedOUs (Test-AdmanTargetAllowed:61), $script:DenyRids (step b) and $script:ProtectedGroupDns (step d) are all unset. Initialize-Adman (Public/Initialize-Adman.ps1) is the fixed startup that populates ALL of these (config load + Resolve-AdmanDomainSid + Get-AdmanProtectedIdentity). Without it the gate cannot function and the Protected test's nested-admin refusal (step d) would silently pass for the wrong reason."
  artifacts:
    - path: "tests/Safety.WhatIf.Integration.Tests.ps1"
      issue: "BeforeAll imports the module but never initializes it"
    - path: "tests/Safety.Protected.Integration.Tests.ps1"
      issue: "same; also needs ProtectedGroupDns populated or the nested-admin refusal is vacuous"
  missing:
    - "Initialize the module in each integration test before invoking the gate. Two options: (A) call Initialize-Adman against a lab .store/config.json (DC=lab-dc01.lab.local, ManagedOUs=[lab OU], AdmanProtectedGroup=Domain Admins, writable AuditDir/ReportDir) — true end-to-end, also covers the init path; (B) inject $script:Config + $script:DenyRids + $script:ProtectedGroupDns + $script:DomainSid via module scope like the unit tests' Set-AdmanSafetyState — no config file but does not exercise Initialize-Adman."
  debug_session: ""
  resolution: "FIXED in quick task 260714-fbx (commits 259f4d9 + 385db4e). Tests now Initialize-Adman against a $TestDrive lab config; AdmanProtectedGroup resolved to the live Domain Admins DN (non-vacuous). PARTIAL PASS on re-run: Safety.Protected.Integration.Tests.ps1 PASSES (nested-admin refused + Refused audit record = SAFE-06 proven live; gMSA/RID-500 Inconclusive, acceptable). Safety.WhatIf.Integration.Tests.ps1 still fails — see gap #3."

- truth: "A gated -WhatIf against the lab OU leaves AD unchanged; audit target list == resolved list; operator-shown count == resolved count (SAFE-01/10)"
  status: failed
  reason: "User reported (after issues #1/#2 fixed): PropertyNotFoundException 'The property Value cannot be found on this object' at Test-AdmanTargetAllowed.ps1:52. Protected test passes; only the WhatIf file fails."
  severity: major
  test: 2
  root_cause: "TWO layered problems. (1) CRASH: the WhatIf test targets the OU DN directly (@($TestOu)); Resolve-AdmanTarget binds -Identity and resolves the OU OBJECT itself, and an OU has no objectSid, so step (b) line 52 `[SecurityIdentifier]$Object.objectSid).Value` throws under StrictMode (null .Value). (2) SEMANTIC MISMATCH: the gate resolves the given identity as-is and does NOT enumerate OU children, yet the test asserts `$result.Succeeded -eq @($before).Count` where $before is the OU's child objects — expecting OU expansion the gate does not do. The Protected test passes precisely because it targets user DNs (which have objectSid), not the OU."
  artifacts:
    - path: "tests/Safety.WhatIf.Integration.Tests.ps1"
      issue: "targets the OU DN (@($script:TestOu)) and expects Succeeded == child-object count, but the gate resolves the OU object (no objectSid, no child enumeration)"
    - path: "Private/Safety/Test-AdmanTargetAllowed.ps1"
      issue: "line 52 assumes every resolved object has objectSid; non-security-principals (OU/container) have none -> null .Value throws under StrictMode"
  missing:
    - "DESIGN DECISION NEEDED: either (a) the WhatIf test should target the child USER fixtures under the OU (matching gate semantics: resolve identity as-is), or (b) the gate should expand OU targets into child objects. Option (a) is the minimal correct fix; (b) is a product-scope change. Separately, harden Test-AdmanTargetAllowed step (b) to skip RID-deny when objectSid is absent (robustness for non-principal targets)."
  debug_session: ""
