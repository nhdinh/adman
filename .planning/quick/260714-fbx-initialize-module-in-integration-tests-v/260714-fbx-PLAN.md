---
phase: quick-260714-fbx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - tests/Safety.WhatIf.Integration.Tests.ps1
  - tests/Safety.Protected.Integration.Tests.ps1
autonomous: true
requirements:
  - SAFE-01
  - SAFE-06
  - SAFE-10
must_haves:
  truths:
    - "Each integration test, when ADMAN_TEST_OU (and ADMAN_TEST_DC) are set, initializes the module via Initialize-Adman against a lab config written under $TestDrive BEFORE invoking the mutation gate."
    - "The lab config's AdmanProtectedGroup is the live DN of the lab Domain Admins group, so the nested-admin refusal in the Protected test is NON-vacuous (ProtectedGroupDns is populated)."
    - "When ADMAN_TEST_OU is unset, both tests still SKIP cleanly (init logic lives inside the lab-configured branch only)."
    - "The Unit suite (Invoke-Pester -TagFilter Unit) remains green and both files still parse; -Tag 'Integration' markers are intact."
  artifacts:
    - "tests/Safety.WhatIf.Integration.Tests.ps1 (gated init added)"
    - "tests/Safety.Protected.Integration.Tests.ps1 (gated init added)"
  key_links:
    - "$script:StorePath injected to $TestDrive BEFORE Initialize-Adman so Initialize-AdmanConfig reads the lab config.json, not the operator's .store/."
    - "Lab config.json satisfies config/adman.schema.json required keys exactly (ManagedOUs, DenyList, safety, bulk, AuditDir, ReportDir, transport, credentialPolicy, AdmanProtectedGroup, DC, delegatedAdminGroup)."
    - "AdmanProtectedGroup = (Get-ADGroup 'Domain Admins').DistinguishedName -> Get-AdmanProtectedIdentity adds it to $script:ProtectedGroupDns -> Test-AdmanTargetAllowed step (d) IN_CHAIN filter refuses the nested-admin fixture."
---

<objective>
Initialize the adman module inside the two lab integration tests by calling `Initialize-Adman` against a lab config written under `$TestDrive`, so the mutation gate has the config + derived safety state (`$script:Config`, `$script:ProtectedGroupDns`, `$script:DenyRids`) it needs. This is the true end-to-end path (option A).

Purpose: The two tests currently only `Import-Module` and never run `Initialize-Adman`, so `$script:Config` is the empty `@{}` and every `$script:Config.*` access throws under Set-StrictMode (observed: PropertyNotFoundException 'DC' at Resolve-AdmanTarget.ps1:37). `$script:DenyRids`/`$script:ProtectedGroupDns` are never derived, which would make the Protected test's nested-admin refusal pass VACUOUSLY (a false green). Initializing the module fixes both.

Output: Both integration test files initialize the module in their gated (lab-configured) path; test-code only, no production changes.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@tests/Safety.GateOrder.Tests.ps1
@Public/Initialize-Adman.ps1
@Private/Config/Initialize-AdmanConfig.ps1
@Private/Safety/Get-AdmanProtectedIdentity.ps1
@Private/Safety/Test-AdmanTargetAllowed.ps1
@Private/Foundation/Get-AdmanCredential.ps1
@config/adman.schema.json
@config/adman.defaults.json
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add gated Initialize-Adman startup to Safety.WhatIf.Integration.Tests.ps1</name>
  <files>tests/Safety.WhatIf.Integration.Tests.ps1</files>
  <action>
In `tests/Safety.WhatIf.Integration.Tests.ps1`, add module initialization inside the lab-configured path of the `-WhatIf` It block, immediately AFTER the existing `Import-Module $script:ManifestPath -Force -ErrorAction Stop` line and BEFORE the "Snapshot the lab OU state" step. Do NOT touch any existing assertion, the `-Tag 'Integration'` markers, or the `ADMAN_TEST_OU` skip-guard.

Extend the gate to also require a DC. In `BeforeAll`, add `$script:TestDc = $env:ADMAN_TEST_DC` and change `$script:LabConfigured` to require BOTH: `-not [string]::IsNullOrWhiteSpace($script:TestOu) -and -not [string]::IsNullOrWhiteSpace($script:TestDc)`. Update the two skip messages to mention `ADMAN_TEST_OU and ADMAN_TEST_DC`.

Inside the gated It block (after Import-Module), insert an init step that:
1. Creates a per-test store dir under `$TestDrive`: `$testStore = Join-Path $TestDrive 'adman-store'` then `New-Item -ItemType Directory -Path $testStore -Force | Out-Null`. Create `audit` and `reports` subdirs the same way.
2. Resolves the lab Domain Admins DN: `$daDn = (Get-ADGroup -Identity 'Domain Admins' -Server $script:TestDc -ErrorAction Stop).DistinguishedName`. This is the value that makes the protected-group set non-empty.
3. Builds a lab config object (a `[pscustomobject]`) satisfying config/adman.schema.json exactly, with these values:
   - ManagedOUs = `@($script:TestOu)`
   - DC = `$script:TestDc`
   - AdmanProtectedGroup = `$daDn`  (a DN string; Get-AdmanProtectedIdentity adds it verbatim to ProtectedGroupDns, and Test-AdmanTargetAllowed interpolates it into a memberOf IN_CHAIN LDAP filter)
   - AuditDir = the `$testStore\audit` path; ReportDir = the `$testStore\reports` path
   - safety = `[pscustomobject]@{ bulkConfirmThreshold = 5 }`
   - bulk = `[pscustomobject]@{ maxCount = 50 }`
   - transport = `[pscustomobject]@{ order = @('WinRM','CimWsman','CimDcom','Skip'); timeouts = [pscustomobject]@{ WinRM = 15; CIM = 20 } }`
   - credentialPolicy = `[pscustomobject]@{ allowRememberMe = $false }`
   - delegatedAdminGroup = `''`
   - Omit DenyList entirely (Initialize-AdmanConfig seeds 500/501/502 from config/adman.defaults.json when DenyList is absent).
4. Serializes the config with `ConvertTo-Json -Depth 5` and writes it to `Join-Path $testStore 'config.json'` via `Set-Content -Encoding UTF8`.
5. Injects `$script:StorePath` into the module BEFORE calling Initialize-Adman, using the module-scope idiom from GateOrder.Tests.ps1: `& (Get-Module adman) { param($p) $script:StorePath = $p } -p $testStore`. Initialize-AdmanConfig honors a pre-set `$script:StorePath` (it only defaults to '.store' when unset), so it will read the lab config.json from `$testStore`.
6. Calls `& (Get-Module adman) { Initialize-Adman }`. Under `runas /netonly` with lab-admin rights, Get-AdmanCredential takes the rights-first pass-through path (Test-AdmanRightsSufficient reads the managed OU successfully) and returns `$null` WITHOUT prompting; allowRememberMe=$false also disables the stored-credential path. No interactive prompt occurs in a non-interactive Pester run.

Keep the rest of the It block (snapshot, gated -WhatIf Invoke-AdmanMutation, AD-unchanged assertion, audit-record assertions) unchanged. The existing `$auditDir = & (Get-Module adman) { $script:Config.AuditDir }` line now resolves to the `$testStore\audit` path, which is correct.
  </action>
  <verify>
    <automated>pwsh -NoProfile -Command "$ErrorActionPreference='Stop'; $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('tests/Safety.WhatIf.Integration.Tests.ps1',[ref]$tokens,[ref]$errors) | Out-Null; if($errors.Count){throw ('parse errors: '+$errors.Count)}; $src=Get-Content 'tests/Safety.WhatIf.Integration.Tests.ps1' -Raw; if($src -notmatch 'Initialize-Adman'){throw 'missing Initialize-Adman call'}; if($src -notmatch '\$script:StorePath'){throw 'missing StorePath injection'}; if($src -notmatch 'ADMAN_TEST_DC'){throw 'missing ADMAN_TEST_DC gate'}; if($src -notmatch 'AdmanProtectedGroup'){throw 'missing AdmanProtectedGroup'}; if($src -notmatch 'config\.json'){throw 'missing config.json write'}; if(($src | Select-String -Pattern "-Tag 'Integration'" -AllMatches).Matches.Count -lt 2){throw 'Integration tags missing'}; 'OK'"</automated>
  </verify>
  <done>
File parses with zero errors; contains an Initialize-Adman call, a $script:StorePath injection, an ADMAN_TEST_DC gate, an AdmanProtectedGroup assignment, and a config.json write under $TestDrive; at least two `-Tag 'Integration'` markers remain; all original assertions and the ADMAN_TEST_OU skip-guard are intact.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add gated Initialize-Adman startup to Safety.Protected.Integration.Tests.ps1</name>
  <files>tests/Safety.Protected.Integration.Tests.ps1</files>
  <action>
In `tests/Safety.Protected.Integration.Tests.ps1`, apply the SAME initialization pattern as Task 1. This file has TWO gated It blocks that each call `Import-Module $script:ManifestPath -Force -ErrorAction Stop` (the nested-admin It and the gMSA/RID-500 It). Add the init step after Import-Module in BOTH blocks (or factor the init into a single `BeforeAll`-scoped helper function `Initialize-AdmanLab` defined in `BeforeAll` and call it in each gated block — prefer the helper to avoid duplication).

Extend the gate identically: in `BeforeAll`, add `$script:TestDc = $env:ADMAN_TEST_DC` and require BOTH ADMAN_TEST_OU and ADMAN_TEST_DC for `$script:LabConfigured`; update skip messages to mention both env vars.

The init step (whether inlined twice or via a helper) is IDENTICAL to Task 1:
1. `$testStore = Join-Path $TestDrive 'adman-store'`; create it plus `audit` and `reports` subdirs.
2. `$daDn = (Get-ADGroup -Identity 'Domain Admins' -Server $script:TestDc -ErrorAction Stop).DistinguishedName`. CRITICAL: this is what makes the nested-admin refusal NON-vacuous. Without it, `$script:ProtectedGroupDns` would be empty and Test-AdmanTargetAllowed step (d) would build an empty `$or` filter, skip the IN_CHAIN query, and the nested-admin fixture would be allowed (false green). With the Domain Admins DN present, the fixture's transitive membership is detected and refused.
3. Build the lab config `[pscustomobject]` with the exact same keys/values as Task 1 (ManagedOUs=@($script:TestOu), DC=$script:TestDc, AdmanProtectedGroup=$daDn, AuditDir/ReportDir under $testStore, safety.bulkConfirmThreshold=5, bulk.maxCount=50, transport.order/timeouts, credentialPolicy.allowRememberMe=$false, delegatedAdminGroup='', DenyList omitted).
4. `ConvertTo-Json -Depth 5` -> `Set-Content -Encoding UTF8` to `Join-Path $testStore 'config.json'`.
5. Inject `$script:StorePath`: `& (Get-Module adman) { param($p) $script:StorePath = $p } -p $testStore`.
6. `& (Get-Module adman) { Initialize-Adman }`.

If using a helper, define it in `BeforeAll` AFTER the existing variable setup, e.g. `function Initialize-AdmanLab { ... }` containing steps 1-6, and call `Initialize-AdmanLab` in each gated It block right after `Import-Module`. Note: the helper runs in the test script scope, so `$TestDrive`, `$script:TestOu`, `$script:TestDc` are all visible to it.

Keep all existing assertions, fixture lookups (lab-nested-admin, gMSA, RID-500), `-Force` on the mutation calls, the Refused-audit-record assertions, and all `-Tag 'Integration'` markers unchanged. The existing `$auditDir = & (Get-Module adman) { $script:Config.AuditDir }` lines now resolve to the `$testStore\audit` path.
  </action>
  <verify>
    <automated>pwsh -NoProfile -Command "$ErrorActionPreference='Stop'; $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('tests/Safety.Protected.Integration.Tests.ps1',[ref]$tokens,[ref]$errors) | Out-Null; if($errors.Count){throw ('parse errors: '+$errors.Count)}; $src=Get-Content 'tests/Safety.Protected.Integration.Tests.ps1' -Raw; if($src -notmatch 'Initialize-Adman'){throw 'missing Initialize-Adman call'}; if($src -notmatch '\$script:StorePath'){throw 'missing StorePath injection'}; if($src -notmatch 'ADMAN_TEST_DC'){throw 'missing ADMAN_TEST_DC gate'}; if($src -notmatch 'AdmanProtectedGroup'){throw 'missing AdmanProtectedGroup'}; if($src -notmatch 'config\.json'){throw 'missing config.json write'}; if(($src | Select-String -Pattern "-Tag 'Integration'" -AllMatches).Matches.Count -lt 3){throw 'Integration tags missing'}; 'OK'"</automated>
  </verify>
  <done>
File parses with zero errors; contains an Initialize-Adman call (or Initialize-AdmanLab helper that calls it), a $script:StorePath injection, an ADMAN_TEST_DC gate, an AdmanProtectedGroup assignment set to the Domain Admins DN, and a config.json write under $TestDrive; at least three `-Tag 'Integration'` markers remain; all original assertions, fixture lookups, and skip-guards are intact.
  </done>
</task>

</tasks>

<verification>
Overall checks (all runnable WITHOUT a lab):
- Both files parse with zero errors (per-task verify).
- `-Tag 'Integration'` markers intact (2+ in WhatIf, 3+ in Protected).
- Unit suite still green: `Invoke-Pester -Path tests -TagFilter Unit` passes (these files are excluded by the Unit tag filter, so they must not break collection; the parse check above guarantees that).
- Static confirmation each file writes a $TestDrive config.json, injects $script:StorePath, and calls Initialize-Adman in the gated path (per-task verify greps).

Lab execution is a MANUAL/human step (the lab is reachable only from the operator's interactive `runas /netonly` session). The executor MUST NOT attempt to run the Integration-tagged tests; they require a live lab domain and the ADMAN_TEST_OU/ADMAN_TEST_DC env vars.
</verification>

<success_criteria>
- Both integration test files initialize the module via Initialize-Adman against a $TestDrive lab config in their gated path.
- AdmanProtectedGroup is set to the live lab Domain Admins DN, making the Protected test's nested-admin refusal non-vacuous.
- Both tests still SKIP cleanly when ADMAN_TEST_OU (or ADMAN_TEST_DC) is unset.
- Unit suite remains green; both files parse; Integration tags intact.
- No production code changed (adman.psm1/psd1, Private/, Public/ untouched); the module-scope Invoke-AdmanMutation wrappers from quick task 260714-ek6 are unchanged.
</success_criteria>

<output>
Create `.planning/quick/260714-fbx-initialize-module-in-integration-tests-v/260714-fbx-SUMMARY.md` when done.
</output>
