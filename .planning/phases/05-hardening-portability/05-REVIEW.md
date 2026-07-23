---
phase: 05-hardening-portability
reviewed: 2026-07-23T19:15:00Z
depth: standard
files_reviewed: 56
files_reviewed_list:
  - .github/workflows/ci.yml
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Add-AdmanGroupMember.ps1
  - Public/Add-AdmanLocalGroupMember.ps1
  - Public/Config/Export-AdmanConfig.ps1
  - Public/Config/Get-AdmanConfig.ps1
  - Public/Config/Import-AdmanConfig.ps1
  - Public/Config/Set-AdmanConfig.ps1
  - Public/Disable-AdmanComputer.ps1
  - Public/Disable-AdmanUser.ps1
  - Public/Enable-AdmanComputer.ps1
  - Public/Enable-AdmanUser.ps1
  - Public/Export-AdmanReportCsv.ps1
  - Public/Export-AdmanReportHtml.ps1
  - Public/Find-AdmanComputer.ps1
  - Public/Find-AdmanUser.ps1
  - Public/Format-AdmanReport.ps1
  - Public/Get-AdmanAccountStateReport.ps1
  - Public/Get-AdmanInventoryReport.ps1
  - Public/Get-AdmanRecoveryPostureReport.ps1
  - Public/Get-AdmanStaleReport.ps1
  - Public/Initialize-Adman.ps1
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Move-AdmanComputer.ps1
  - Public/Move-AdmanUser.ps1
  - Public/New-AdmanUser.ps1
  - Public/Remove-AdmanGroupMember.ps1
  - Public/Remove-AdmanLocalGroupMember.ps1
  - Public/Remove-AdmanLocalUser.ps1
  - Public/Reset-AdmanComputerAccount.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Start-Adman.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - Public/Test-AdmanCapability.ps1
  - Public/Unlock-AdmanUser.ps1
  - build/Sign-AdmanModule.ps1
  - config/adman.defaults.json
  - config/adman.schema.json
  - docs/RECOVERY-RUNBOOK.md
  - docs/USAGE.md
  - tests/Audit.EventLog.Tests.ps1
  - tests/Audit.FailClosed.Tests.ps1
  - tests/Audit.Integrity.Tests.ps1
  - tests/Audit.Rotation.Tests.ps1
  - tests/Audit.Schema.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Docs.Coverage.Tests.ps1
  - tests/Help.Coverage.Tests.ps1
  - tests/PesterConfiguration.psd1
  - tests/Workflow.OffboardingState.Tests.ps1
findings:
  critical: 3
  warning: 8
  info: 0
  total: 11
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-07-23T19:15:00Z
**Depth:** standard
**Files Reviewed:** 56
**Status:** issues_found

## Summary

Reviewed the full Phase 5 hardening/portability scope (56 files): all Public verbs, Config verbs, Audit privates, Offboarding workflow, CI matrix, tests, docs, schema/defaults, and the signing script. The codebase is generally well-guarded, but three critical defects were found: a report that crashes on the real AD attribute type returned by `Get-ADUser`, a CI `AllSigned` smoke job that will fail because the self-signed trust anchor is incomplete, and an interactive menu path that hangs when the operator cancels with `B`. Eight warnings cover portability, test mocks, brittle comparisons, and best-effort error handling.

## Critical Issues

### CR-01: Get-AdmanStaleReport treats `lastLogonTimestamp` as an integer, but AD returns a `DateTime`

**File:** `C:\Users\nhdinh\dev\adman\Public\Get-AdmanStaleReport.ps1:80-92`
**Issue:** `Get-ADUser` returns `lastLogonTimestamp` as a `System.DateTime` (or `$null`), not a file-time `Int64`. The function compares `$llt -eq 0` and then casts `[int64]$llt`, both of which fail at runtime for any account whose `lastLogonTimestamp` is non-null. The stale-account report therefore throws instead of returning results.
**Fix:** Use the derived `LastLogonDate` property (already requested in the D-02 property list) and compare `DateTime` values directly:

```powershell
$llt = $null
if ($obj.PSObject.Properties['LastLogonDate']) { $llt = $obj.LastLogonDate }

if ($null -eq $llt -or $llt -eq [datetime]::MinValue) {
    $created = $null
    if ($obj.PSObject.Properties['whenCreated']) { $created = $obj.whenCreated }
    if ($null -ne $created -and $created -is [datetime] -and $created -lt $staleCutoff) {
        $bucket = 'NeverLoggedOn'
    }
} else {
    if ($llt.ToUniversalTime() -lt $staleCutoff) { $bucket = 'Stale' }
}
```

### CR-02: CI AllSigned smoke imports the self-signed cert only to TrustedPublisher, not the Root store

**File:** `C:\Users\nhdinh\dev\adman\.github\workflows\ci.yml:46-54`
**Issue:** A self-signed code-signing cert must be trusted as a root CA for `Get-AuthenticodeSignature` to report `Valid` under `AllSigned`. The workflow only imports the `.cer` into `Cert:\LocalMachine\TrustedPublisher`, so the signature-verification loop later in the same step is expected to fail.
**Fix:** Import the cert into both stores and surface failures:

```powershell
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher -ErrorAction Stop | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop | Out-Null
```

### CR-03: Start-Adman format-menu `B` cancel loops forever

**File:** `C:\Users\nhdinh\dev\adman\Public\Start-Adman.ps1:228,253`
**Issue:** In the CSV and HTML output path loops, entering `B` executes `$formatResolved = $true; continue`. The `continue` re-enters the *inner* path loop, and because `$pathAttempts` is not incremented for `B`, the loop never exits. The operator is trapped re-prompting for a path.
**Fix:** Change both `continue` statements to `break` so the inner loop exits and the outer `if (-not $pathResolved) { continue }` returns to the format menu:

```powershell
if ($outPath -match '^[Bb]$') { $formatResolved = $true; break }
```

## Warnings

### WR-01: Export-AdmanConfig writes machine-specific absolute paths

**File:** `C:\Users\nhdinh\dev\adman\Public\Config\Export-AdmanConfig.ps1:37-53`
**Issue:** `Initialize-AdmanConfig` absolutizes `AuditDir` and `ReportDir` in memory. `Export-AdmanConfig` serializes those absolute paths, producing backups that are not portable and that import incorrectly on another host.
**Fix:** Relativize the two path keys against the module root before serialization, or keep the on-disk config relative and absolutize on demand:

```powershell
$moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exportClone = $script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
foreach ($key in @('AuditDir','ReportDir')) {
    $v = $exportClone.$key
    if ($v -is [string] -and $v -like "$moduleRoot*") {
        $exportClone.$key = $v.Substring($moduleRoot.Length).TrimStart('\','/')
    }
}
$json = ConvertTo-Json -InputObject $exportClone -Depth 5
```

### WR-02: Initialize-AdmanConfig rewrites the config file on every load

**File:** `C:\Users\nhdinh\dev\adman\Private\Config\Initialize-AdmanConfig.ps1:377-381`
**Issue:** `Save-AdmanConfig` is called unconditionally after validation, even when no migration was necessary. This strips `_comment` annotations, reorders keys, and makes load-time failures (e.g., permissions) block startup even though the file contents are unchanged.
**Fix:** Track whether any additive merge actually changed the config and only save when `$changed` is true, or compare the serialized form of the loaded config against the original file contents before writing.

### WR-03: Get-AdmanOffboardingState uses exact string DN/SID matching

**File:** `C:\Users\nhdinh\dev\adman\Private\Workflow\Get-AdmanOffboardingState.ps1:82-84`
**Issue:** DN and SID matching is case-sensitive and sensitive to whitespace/escaping differences between the audit record and the resolved user. A legitimate restore record can be missed because of case drift in the directory or in the audit JSON.
**Fix:** Normalize before comparing:

```powershell
$dnMatch = $t.PSObject.Properties['dn'] -and $t.dn -and
    ((ConvertTo-AdmanNormalizedDn -Dn $t.dn) -eq (ConvertTo-AdmanNormalizedDn -Dn $userDn))
$sidMatch = $t.PSObject.Properties['sid'] -and $t.sid -and
    ([string]$t.sid).Trim().ToUpper() -eq ([string]$userSid).Trim().ToUpper()
```

### WR-04: Sign-AdmanModule path-exclusion regex can match unrelated parent directories

**File:** `C:\Users\nhdinh\dev\adman\build\Sign-AdmanModule.ps1:80-81`
**Issue:** The regex `\(tests|\.github|\.githooks)\` is applied to the full path, so a module root located under a path that happens to contain `\tests\` would silently exclude every file.
**Fix:** Exclude based on the path relative to `$moduleRoot`:

```powershell
$files = Get-ChildItem -Path $moduleRoot -Include '*.psd1','*.psm1','*.ps1' -Recurse -File |
    Where-Object {
        $rel = $_.FullName.Substring($moduleRoot.Length).TrimStart('\')
        $rel -notmatch '^(tests|\.github|\.githooks)\\'
    }
```

### WR-05: Workflow.OffboardingState test mocks the wrong Resolve-AdmanTarget scope

**File:** `C:\Users\nhdinh\dev\adman\tests\Workflow.OffboardingState.Tests.ps1:38,87`
**Issue:** The test defines a `global:Resolve-AdmanTarget` function, but `Get-AdmanOffboardingState` calls the module-private `Resolve-AdmanTarget`. The global stub is never invoked, so the test will hit the real (AD-dependent) resolver.
**Fix:** Mock the private function inside the module:

```powershell
Mock Resolve-AdmanTarget -ModuleName adman {
    [pscustomobject]@{
        DistinguishedName = $userDn
        objectSid         = [System.Security.Principal.SecurityIdentifier]$userSid
    }
}
```

### WR-06: Invoke-AdmanBulkAction no-op detection assumes memberOf is present on resolved targets

**File:** `C:\Users\nhdinh\dev\adman\Public\Invoke-AdmanBulkAction.ps1:286-294`
**Issue:** The AddGroup/RemoveGroup no-op checks read `$rec.ResolvedTarget.memberOf`. If `Resolve-AdmanTarget` does not populate `memberOf` (it is not in the D-02 read property list by default), the checks will silently perform redundant group writes instead of skipping already-correct memberships.
**Fix:** Either ensure `Resolve-AdmanTarget` requests `memberOf` for group operations, or make the check defensive:

```powershell
$memberOf = if ($rec.ResolvedTarget.PSObject.Properties['memberOf'] -and $null -ne $rec.ResolvedTarget.memberOf) {
    @($rec.ResolvedTarget.memberOf)
} else { @() }
```

### WR-07: Write-AdmanAudit OUTCOME failure can be masked by event-log throw

**File:** `C:\Users\nhdinh\dev\adman\Private\Audit\Write-AdmanAudit.ps1:232-235`
**Issue:** When the audit OUTCOME write fails, the function sets `$script:AuditDegraded = $true` and tries to escalate to the event log. If `Write-AdmanEventLog` throws (e.g., the source is not registered and the session lacks rights), the original audit failure is lost and the caller sees an unrelated exception.
**Fix:** Wrap the event-log call in its own try/catch:

```powershell
$script:AuditDegraded = $true
try {
    Write-AdmanEventLog -EventId 9001 -EntryType Error `
        -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
} catch {
    Write-Warning "Audit event-log escalation also failed: $_"
}
Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId - see Event Log."
```

### WR-08: Unlock-AdmanUser -WhatIf falls back to a non-PDCe DC

**File:** `C:\Users\nhdinh\dev\adman\Public\Unlock-AdmanUser.ps1:91-95`
**Issue:** Under `-WhatIf`, if the PDC emulator lookup fails, the verb silently falls back to `$script:Config.DC`. The dry-run preview then claims the write would target a DC that may not be the PDCe, contradicting the function's own rationale for PDCe pinning.
**Fix:** Either propagate the PDCe lookup error under `-WhatIf` (the operator should know the preview cannot be generated) or omit `Server` from the gate parameters when the PDCe cannot be resolved, rather than pinning to an arbitrary DC.

---

_Reviewed: 2026-07-23T19:15:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
