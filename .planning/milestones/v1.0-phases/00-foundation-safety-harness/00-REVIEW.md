---
phase: 00-foundation-safety-harness
reviewed: 2026-07-14T15:20:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - tests/Safety.WhatIf.Integration.Tests.ps1
  - Private/Safety/Test-AdmanTargetAllowed.ps1
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 00: Code Review Report

**Reviewed:** 2026-07-14T15:20:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the two files changed by gap-closure plan 00-06 (UAT gap #3). Task 1 retargeted the
WhatIf integration test to provision and target two non-protected `lab-whatif-*` user fixtures
(resolve-identity-as-is semantics). Task 2 hardened `Test-AdmanTargetAllowed` step (b) to skip the
RID-deny check when `objectSid` is absent (non-principal targets).

**Task 2 (production safety) is correct.** The `objectSid` null-guard does NOT weaken RID denial
for real principals: `Resolve-AdmanTarget` always requests `-Properties objectSid`, so the property
exists on every resolved object; for a user/group/computer/gMSA the value is a populated byte array
(truthy, non-null) and the exact prior RID check runs. For a non-principal (OU/container) the value
is `$null` and the check is skipped — but the target remains subject to step (c) managed-OU scope and
step (d) protected-membership. No early return was introduced; the `$reasons` accumulator pattern is
preserved. A renamed RID-500 principal is still refused.

**Task 1 (test correctness) is largely sound** — the integration gate (`-Tag 'Integration'` +
`ADMAN_TEST_OU`/`ADMAN_TEST_DC` skip) is preserved, fixture provisioning is idempotent, the OU-DN
targeting regression is genuinely fixed (targets are now child user DNs, not the OU DN), and the
audit-target assertion correctly extracts `.dn` from the `{dn,sid,objectClass}` records and
deduplicates across the PENDING+Success records. Two warnings and two info items below, all in the
test file; none are blocking.

No PS7-only syntax observed; `Set-StrictMode -Version Latest` property access is guarded via
`$Object.PSObject.Properties['objectSid']` membership test. No secrets beyond the throwaway lab
password (acceptable per review scope). No injection vectors (all LDAP values flow through
`Escape-AdmanLdapFilterValue` in the production function).

## Warnings

### WR-01: `Should -BeTrue` hardcodes an enabled-fixture assumption that contradicts the snapshot assertion

**File:** `tests/Safety.WhatIf.Integration.Tests.ps1:163-164`
**Issue:** The post-run loop asserts both `$enabledAfter | Should -Be $before[$dn]` (correct: a
`-WhatIf` must not change state) AND `$enabledAfter | Should -BeTrue` (assumes the fixture is
enabled). Fixture provisioning is idempotent — it skips `New-ADUser` when the fixture already exists.
If a `lab-whatif-*` fixture was left in a disabled state by a prior partial/interrupted run, the
idempotent path reuses it as-is, `$before[$dn]` is `$false`, the `-WhatIf` correctly changes nothing,
the first assertion passes, but the second (`Should -BeTrue`) fails — a false failure for the wrong
reason (the exact failure class this retarget was meant to eliminate). In the happy path the second
assertion is redundant with the first.
**Fix:** Either drop the redundant `Should -BeTrue` (the `-Be $before[$dn]` assertion already proves
SAFE-01 immutability), or normalize the fixture to a known-enabled state before snapshotting so the
assertion is meaningful:
```powershell
# Ensure a known-enabled baseline so the -WhatIf immutability assertion is unambiguous.
foreach ($dn in $targets) {
    Set-ADUser -Identity $dn -Enabled $true -Server $script:TestDc
}
$before = @{}
foreach ($dn in $targets) {
    $before[$dn] = (Get-ADUser -Identity $dn -Server $script:TestDc -Properties Enabled).Enabled
}
```

### WR-02: `Get-ADUser` with `-ErrorAction SilentlyContinue` conflates "not found" with transient lookup failure

**File:** `tests/Safety.WhatIf.Integration.Tests.ps1:115-116,134-135`
**Issue:** Both the provisioning probe (line 115) and the DN-resolution probe (line 134) use
`-ErrorAction SilentlyContinue`. A transient failure (DC unreachable, auth hiccup, referral) is
indistinguishable from "object does not exist": `$u`/`$dn` comes back `$null`, the provisioning path
then attempts `New-ADUser` which throws "already exists" (caught -> Inconclusive, acceptable), but
the resolution path (line 134) silently drops the fixture and falls through to the
`$targets.Count -lt $fixtureNames.Count` Inconclusive branch. The test degrades to Inconclusive
rather than failing, so this is not a correctness bug — but the operator cannot tell a genuine
missing-fixture from a lab-connectivity problem without reading the Inconclusive message.
**Fix:** Distinguish "not found" from other errors. Catch the specific not-found case and rethrow
(or surface) anything else:
```powershell
$u = $null
try {
    $u = Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree `
        -LDAPFilter "(sAMAccountName=$name)" -Server $script:TestDc -ErrorAction Stop
} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    $u = $null   # genuinely absent -> provision below
}
# any other exception propagates and fails the test loudly (lab connectivity, not a fixture gap)
```

## Info

### IN-01: Fixture provisioning runs inside the `It` block on every invocation

**File:** `tests/Safety.WhatIf.Integration.Tests.ps1:113-129`
**Issue:** The idempotent `Get-ADUser`/`New-ADUser` provisioning loop runs inside the single `It`
block. It is correct, but it is setup work that conceptually belongs in a `BeforeAll`/`BeforeEach`
for the Describe, which would also let the "is skipped" gate (line 94-97) guard it once rather than
re-checking `$script:LabConfigured` per `It`. Minor; the current placement is functional and keeps
the fixture logic co-located with the only test that needs it.
**Fix:** Optional — hoist provisioning into a `BeforeAll` guarded by `$script:LabConfigured`, or
leave as-is given there is exactly one consuming `It`.

### IN-02: `Initialize-AdmanLab` re-imports the module manifest inside the `It` after `BeforeAll` already resolved it

**File:** `tests/Safety.WhatIf.Integration.Tests.ps1:99,104`
**Issue:** `Import-Module $script:ManifestPath -Force` (line 99) runs inside the `It`, immediately
before `Initialize-AdmanLab` (line 104). This is intentional (fresh module state per run so the
`$TestDrive` store injection on line 76 takes effect against a clean `$script:StorePath`), and it is
correct — but the `-Force` re-import on every invocation is worth a one-line comment so a future
reader does not "optimize" it away and break the store-path injection ordering.
**Fix:** Add a brief comment at line 99 noting the `-Force` re-import is load-bearing for the
`$TestDrive` store-path injection in `Initialize-AdmanLab`.

---

_Reviewed: 2026-07-14T15:20:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
