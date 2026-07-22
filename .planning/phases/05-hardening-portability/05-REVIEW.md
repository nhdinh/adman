---
phase: 05-hardening-portability
reviewed: 2026-07-22T22:45:00Z
depth: standard
files_reviewed: 48
files_reviewed_list:
  - .github/workflows/ci.yml
  - Private/AD/Adman.AD.Write.ps1
  - Private/Audit/AdmanAuditIO.ps1
  - Private/Audit/Rotation.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Bulk/ConvertTo-AdmanBulkInput.ps1
  - Private/Bulk/Import-AdmanBulkCsv.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Foundation/Test-AdmanAuditWritable.ps1
  - Private/Local/Adman.Local.Write.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Menu/Read-AdmanActionParams.ps1
  - Private/Remoting/Connect-AdmanTarget.ps1
  - Private/Remoting/Invoke-AdmanRemoteQuery.ps1
  - Private/Reporting/ConvertTo-AdmanResult.ps1
  - Private/Reporting/Test-AdmanInManagedScope.ps1
  - Private/Safety/Assert-AdmanBulkPolicy.ps1
  - Private/Safety/Confirm-AdmanAction.ps1
  - Private/Safety/Escape-AdmanLdapFilterValue.ps1
  - Private/Safety/Get-AdmanProtectedIdentity.ps1
  - Private/Safety/Invoke-AdmanLocalMutation.ps1
  - Private/Safety/Invoke-AdmanMutation.ps1
  - Private/Safety/Resolve-AdmanCreateTarget.ps1
  - Private/Safety/Resolve-AdmanGroup.ps1
  - Private/Safety/Resolve-AdmanIdentity.ps1
  - Private/Safety/Resolve-AdmanLocalTarget.ps1
  - Private/Safety/Resolve-AdmanTarget.ps1
  - Private/Safety/Test-AdmanGroupAllowed.ps1
  - Private/Safety/Test-AdmanLocalTargetAllowed.ps1
  - Private/Safety/Test-AdmanTargetAllowed.ps1
  - Private/Utility/ConvertTo-AdmanNormalizedDn.ps1
  - Private/Utility/ConvertTo-AdmanParentDn.ps1
  - Private/Utility/Escape-AdmanAdFilterLiteral.ps1
  - Private/Utility/New-AdmanRandomPassword.ps1
  - Private/Utility/Test-AdmanPasswordComplexity.ps1
  - Private/Workflow/Get-AdmanOffboardingState.ps1
  - Public/Config/Import-AdmanConfig.ps1
  - Public/Config/Set-AdmanConfig.ps1
  - Public/Disable-AdmanUser.ps1
  - Public/Export-AdmanReportCsv.ps1
  - Public/Initialize-Adman.ps1
  - Public/Invoke-AdmanBulkAction.ps1
  - Public/Move-AdmanUser.ps1
  - Public/New-AdmanLocalUser.ps1
  - Public/New-AdmanUser.ps1
  - Public/Restore-AdmanQuarantinedUser.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Start-Adman.ps1
  - Public/Start-AdmanUserOffboarding.ps1
  - Public/Start-AdmanUserOnboarding.ps1
  - build/Sign-AdmanModule.ps1
findings:
  critical: 2
  warning: 7
  info: 4
  total: 13
status: issues_found
---

# Phase 05-hardening-portability: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 48
**Status:** issues_found

## Summary

Fresh adversarial review of the Phase 5 hardening/portability surface and the private helpers the public verbs depend on. The core mutation gate, audit writer, and config loader are well-structured and most prior safety invariants hold, but two Critical gaps remain that can bypass the deny-list/protected-group checks or the managed-OU scope boundary. Seven Warnings and four Info items were also found around initialization validation, identity resolution, bulk no-op logic, local-account portability, and redundant/failing guards.

## Critical Issues

### CR-01: Public verbs accept a half-initialized session and silently bypass protected-account checks

**Files:**
- `Public/Disable-AdmanUser.ps1:47-51`
- `Public/Enable-AdmanUser.ps1:47-51`
- `Public/Move-AdmanUser.ps1:64-68`
- `Public/Set-AdmanUserPassword.ps1:118-122`
- `Public/Unlock-AdmanUser.ps1:47-51`
- `Public/Add-AdmanGroupMember.ps1:47-51`
- `Public/Remove-AdmanGroupMember.ps1:47-51`
- `Public/New-AdmanUser.ps1:120-124`
- `Public/Start-AdmanUserOffboarding.ps1:54-58`
- `Public/Start-AdmanUserOnboarding.ps1:64-68`
- `Public/Restore-AdmanQuarantinedUser.ps1:56-60`
- `Public/Invoke-AdmanBulkAction.ps1:78-82`
- `Public/New-AdmanLocalUser.ps1:89-93`
- `Public/Set-AdmanLocalUser.ps1:108-112`
- `Public/Remove-AdmanLocalUser.ps1:47-51`
- `Public/Add-AdmanLocalGroupMember.ps1:47-51`
- `Public/Remove-AdmanLocalGroupMember.ps1:47-51`

**Issue:** Every public verb checks only `$script:Config.ManagedOUs` to decide whether initialization has run. `Initialize-Adman` sets `$script:Initialized = $true` only after `Initialize-AdmanConfig`, audit writability, capability, domain-SID resolution, and protected-identity caching have all succeeded. If `Initialize-Adman` fails after `Initialize-AdmanConfig` (for example, DC unreachable during `Get-AdmanProtectedIdentity`, audit path not writable, or `Resolve-AdmanDomainSid` throwing), `$script:Config` is populated but `$script:ProtectedSIDs`, `$script:DenyRids`, and `$script:ProtectedGroupDns` are not.

`Test-AdmanTargetAllowed` then runs with null caches:
- Step (b) builds `$denyStrings = @($script:DenyRids | ForEach-Object { [string]$_ })`, which becomes `@('')` rather than the configured deny RIDs, so the RID deny-list is silently bypassed.
- Step (d) iterates `@($script:ProtectedGroupDns)`. When the variable is `$null` this becomes `@($null)` and the loop skips the only iteration because `[string]::IsNullOrWhiteSpace($null)` is true, so recursive protected-group membership is never checked.

A caller that catches the `Initialize-Adman` throw and continues can therefore disable, move, or reset protected accounts without any refusal.

**Fix:** Centralize the initialization guard in a single helper and call it from every public verb. The guard must require both `$script:ConfigLoaded` and `$script:Initialized` (or explicitly verify that the protected caches are non-null).

```powershell
function Assert-AdmanInitialized {
    if (-not $script:Initialized -or
        -not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs -or
        -not $script:ProtectedSIDs -or
        -not $script:DenyRids -or
        -not $script:ProtectedGroupDns) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }
}
```

Then replace the duplicated init check in each public verb with `Assert-AdmanInitialized`.

### CR-02: DN normalization corrupts uppercase hex escapes and can break the managed-OU scope boundary

**File:** `Private/Utility/ConvertTo-AdmanNormalizedDn.ps1:27-30`

**Issue:** The hex-unescape regex is case-sensitive: `[0-9a-f]{2}` matches only lowercase hex. A DN containing an uppercase hex escape such as `CN=Foo\2CBar,OU=Managed,DC=contoso,DC=com` (where `\2C` represents a literal comma) is not unescaped by the first regex. The second `-replace '\\(.)', '$1'` then strips the backslash and the first hex digit, leaving `CN=Foo2CBar,...` instead of the canonical `CN=Foo,Bar,...`.

Because the scope tests in `Test-AdmanTargetAllowed`, `Test-AdmanInManagedScope`, and the Move/Offboarding/Restore verbs rely on normalized DNs for the component-boundary anchor, this corruption can:
- Falsely allow an object outside managed scope (if the corrupted DN happens to end with a managed root).
- Falsely refuse an in-scope object (if the corrupted DN no longer matches the expected structure).

**Fix:** Make the hex regex case-insensitive and anchor it to exactly two hex digits.

```powershell
$s = [regex]::Replace($s, '\\([0-9a-fA-F]{2})', {
    param($m) [char][Convert]::ToInt32($m.Groups[1].Value, 16)
})
```

Add a unit test covering `\2C`, `\2c`, `\5C`, and multi-escape values such as `CN=A\2CB\2CC`.

## Warnings

### WR-01: `Write-AdmanAudit` hard-codes the module name and crashes when the module is not loaded as `adman`

**File:** `Private/Audit/Write-AdmanAudit.ps1:153`

**Issue:** The audit record builds `moduleVersion` with `(Get-Module adman).Version.ToString()`. If the module is dot-sourced, loaded under an alias, or exercised in a test harness where it is not imported as `adman`, `Get-Module adman` returns `$null` and `.ToString()` throws. A PENDING-write failure is correctly fail-closed, but the refusal reason becomes a confusing null-reference error rather than the intended audit failure. An OUTCOME-write failure degrades the audit sink and sets `$script:AuditDegraded = $true`.

**Fix:** Resolve the version from the function's own module context and degrade to `'unknown'` when no module context exists.

```powershell
$module = $ExecutionContext.SessionState.Module
$moduleVersion = if ($module) { $module.Version.ToString() } else { 'unknown' }
```

### WR-02: `Set-AdmanLocalUser` rejects password resets that rely on the configured password source

**File:** `Public/Set-AdmanLocalUser.ps1:145-148`

**Issue:** The default `Reset` parameter set throws when neither `-Password` nor `-PasswordSource` is supplied, even though the inline help example on line 68 (`Set-AdmanLocalUser -Name 'luser-fake' # password reset (D-05 sourced)`) implies the configured `security.passwordSource` fallback works. The fallback code at lines 157-159 is unreachable because the guard above it throws first. This breaks parity with `New-AdmanUser`, `New-AdmanLocalUser`, and `Set-AdmanUserPassword`, all of which fall back to the config source.

**Fix:** Remove the hard throw and let the existing source-resolution fallback run.

```powershell
# Remove this block:
if (-not $passwordSupplied -and -not $passwordSourceSupplied) {
    throw 'Parameter set cannot be resolved: supply -Password, -Enable, or -Disable.'
}
```

If a silent no-op is the concern, note that the fallback either generates a password or prompts; it never performs a no-op reset.

### WR-03: Bulk no-op skip misses already-disabled/enabled accounts because `Resolve-AdmanTarget` does not fetch `Enabled`

**Files:**
- `Public/Invoke-AdmanBulkAction.ps1:267-274`
- `Private/Safety/Resolve-AdmanTarget.ps1:37-38`

**Issue:** `Invoke-AdmanBulkAction` checks `$rec.ResolvedTarget.PSObject.Properties['Enabled']` to skip already-disabled or already-enabled accounts. However, `Resolve-AdmanTarget` requests only `objectSid, objectClass, DistinguishedName, memberOf`; it does not request `Enabled`. The resolved raw AD object therefore lacks the `Enabled` property, the guard is false, and the no-op skip branch never fires.

The result is redundant PENDING/Success audit records and redundant AD writes for accounts that were already in the desired state. It also makes the `PerItem` output less useful because every row reports `Success` instead of `Success / already disabled`.

**Fix:** Add `Enabled` to the `-Properties` list in `Resolve-AdmanTarget`.

```powershell
Get-ADObject -Identity $id -Server $script:Config.DC `
    -Properties objectSid, objectClass, DistinguishedName, memberOf, Enabled -ErrorAction Stop
```

### WR-04: `Resolve-AdmanIdentity` AdComputer branch can return a user object

**File:** `Private/Safety/Resolve-AdmanIdentity.ps1:104-111`

**Issue:** For `Kind='AdComputer'`, the resolver tries the exact sAMAccountName first, then the trailing-dollar form. It does not filter the exact match by `objectClass -eq 'computer'`. If an operator types the bare computer name `PC01` and a user account with `sAMAccountName='PC01'` exists, the exact match returns the user object. The menu then dispatches a computer verb against a user account. While the gate still applies scope/protected checks, the wrong object class is mutated.

**Fix:** Add an objectClass filter to the exact match branch, or verify the returned `objectClass` contains `computer` before returning.

```powershell
$exactHits = @(Get-ADObject -Filter "sAMAccountName -eq '$esc'" -Server $script:Config.DC `
    -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop |
    Where-Object { $_.objectClass -contains 'computer' })
```

### WR-05: Local Administrator detection relies on the English group name "Administrators"

**File:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1:80`

**Issue:** The local admin-group check calls `Get-LocalGroupMember -Name 'Administrators'`. On non-English Windows installations the built-in administrators group is localized (for example, `Administrateurs`, `Administratoren`). The cmdlet will throw, `$enumFailed` becomes `$true`, and the function adds `local Administrators enumeration failed (fail-closed)` as a refusal reason. This fail-closed behavior is safe, but it also refuses legitimate operations on non-admin local accounts on non-English systems.

**Fix:** Resolve the well-known SID `S-1-5-32-544` to the localized group name first, then query membership by that name.

```powershell
$adminGroup = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value -replace '^.*\\',''
$members = @(Get-LocalGroupMember -Name $adminGroup -ErrorAction Stop)
```

### WR-06: Generated-password transcript guard can throw on Windows PowerShell 5.1 or non-interactive runspaces

**Files:**
- `Public/New-AdmanUser.ps1:209-211, 228-230`
- `Public/Set-AdmanUserPassword.ps1:193-196, 254-256`
- `Public/New-AdmanLocalUser.ps1:168-171, 228-233`
- `Public/Set-AdmanLocalUser.ps1:212-216, 231-233`

**Issue:** The transcript check uses `[System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count`. In some runspace configurations (Windows PowerShell 5.1 under certain hosts, constrained runspaces, or test harnesses), `InitialSessionState` may be `$null` or may not expose a `Transcripts` property. This causes a null-reference or property-not-found exception instead of the intended guard behavior.

**Fix:** Use a guarded helper that returns 0 when the property is unavailable.

```powershell
function Get-AdmanTranscriptCount {
    try {
        $iss = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState
        if ($null -eq $iss) { return 0 }
        $prop = $iss.PSObject.Properties['Transcripts']
        if ($null -eq $prop) { return 0 }
        return @($prop.Value).Count
    } catch { return 0 }
}
```

### WR-07: `Invoke-AdmanBulkAction` resolves targets twice per allowed item

**File:** `Public/Invoke-AdmanBulkAction.ps1:203-230, 262-321`

**Issue:** The bulk engine resolves each target once for filtering and no-op detection, then calls `Invoke-AdmanMutation` per item, which resolves the same target again. Between the two resolutions the target's OU, enabled state, or group memberships could change, so the no-op decision and the actual mutation may disagree. For example, an account that was `already disabled` at filter time may no longer be disabled at execution time, causing an unexpected state change.

**Fix:** Pass the resolved object through to `Invoke-AdmanMutation` so the same AD snapshot is used for both preview and execution. This requires adding an optional `-ResolvedObjects` parameter to the gate or adding a wrapper that accepts resolved objects directly.

## Info

### IN-01: `Import-AdmanConfig` and `Set-AdmanConfig` silently swallow PSFramework backbone errors

**Files:**
- `Public/Config/Import-AdmanConfig.ps1:73`
- `Public/Config/Set-AdmanConfig.ps1:92`

**Issue:** Both verbs call `Import-PSFConfig` / `Set-PSFConfig` inside an empty `catch { }`. The comments correctly note that PSFramework is not the safety source, but swallowing all errors hides install/permission/registration problems that can make diagnostics difficult.

**Fix:** Log the swallowed exception at Verbose level instead of discarding it.

```powershell
try { Import-PSFConfig -Path $target -ErrorAction SilentlyContinue } catch { Write-Verbose "PSFramework config mirror failed: $_" }
```

### IN-02: Redundant post-mutation transcript guards in password verbs

**Files:**
- `Public/New-AdmanUser.ps1:228-230`
- `Public/Set-AdmanUserPassword.ps1:254-256`
- `Public/New-AdmanLocalUser.ps1:228-233`
- `Public/Set-AdmanLocalUser.ps1:231-233`

**Issue:** Each password verb now has a pre-mutation transcript guard that throws before the account is created or its password is changed. The post-mutation guard inside the display-once block checks the same condition again, but it can never fire because the pre-mutation guard already refused the operation. These paths are dead code.

**Fix:** Remove the inner `Transcripts.Count` check from the display-once block in each verb; rely solely on the pre-mutation guard.

### IN-03: `@()` array builders remain in hot-path writers

**Files:**
- `Private/Audit/Write-AdmanAudit.ps1:90-92, 94-95, 114-130`
- `Public/Export-AdmanReportCsv.ps1:81-92`

**Issue:** The audit writer and CSV renderer still build collections with `@()` and `+=`, which reallocates on every addition. While the collections are small in normal use, the pattern is a maintainability/performance smell in code paths that are explicitly designed to be hot or streaming. Other parts of the codebase already use `System.Collections.Generic.List[object]`.

**Fix:** Replace the `@()` builders with `New-Object System.Collections.Generic.List[object]` and `.Add()`, as already done in `Invoke-AdmanMutation`.

### IN-04: `Start-AdmanUserOffboarding` uses `Write-Host` outside the TUI renderer

**File:** `Public/Start-AdmanUserOffboarding.ps1:186-190`

**Issue:** The offboarding workflow prints its cleanup checklist with `Write-Host`, which writes to the Information stream. This is not the TUI-rendering module (where `PSAvoidUsingWriteHost` is legitimately suppressed), and it can surprise callers who pipe or redirect output.

**Fix:** Use `Write-Information` with a tagged message, or return the checklist as structured output that the caller can render. If console-only output is required, wrap the `Write-Host` usage in a `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]` attribute and document why this verb is an exception.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
