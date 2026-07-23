---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
reviewed: 2026-07-16T00:00:00Z
depth: standard
files_reviewed: 70
files_reviewed_list:
  - Private/AD/Adman.AD.Write.ps1
  - Private/Audit/Write-AdmanAudit.ps1
  - Private/Config/Initialize-AdmanConfig.ps1
  - Private/Local/Adman.Local.Write.ps1
  - Private/Menu/Get-AdmanMenuDefinition.ps1
  - Private/Menu/Read-AdmanActionParams.ps1
  - Private/Safety/AdmanWriteVerbs.ps1
  - Private/Safety/Confirm-AdmanAction.ps1
  - Private/Safety/Invoke-AdmanLocalMutation.ps1
  - Private/Safety/Invoke-AdmanMutation.ps1
  - Private/Safety/Resolve-AdmanCreateTarget.ps1
  - Private/Safety/Resolve-AdmanGroup.ps1
  - Private/Safety/Resolve-AdmanIdentity.ps1
  - Private/Safety/Resolve-AdmanLocalTarget.ps1
  - Private/Safety/Test-AdmanGroupAllowed.ps1
  - Private/Safety/Test-AdmanLocalTargetAllowed.ps1
  - Private/Safety/Test-AdmanTargetAllowed.ps1
  - Private/Utility/New-AdmanRandomPassword.ps1
  - Private/Utility/Test-AdmanPasswordComplexity.ps1
  - Public/Add-AdmanGroupMember.ps1
  - Public/Add-AdmanLocalGroupMember.ps1
  - Public/Disable-AdmanComputer.ps1
  - Public/Disable-AdmanUser.ps1
  - Public/Enable-AdmanComputer.ps1
  - Public/Enable-AdmanUser.ps1
  - Public/Move-AdmanComputer.ps1
  - Public/Move-AdmanUser.ps1
  - Public/New-AdmanLocalUser.ps1
  - Public/New-AdmanUser.ps1
  - Public/Remove-AdmanGroupMember.ps1
  - Public/Remove-AdmanLocalGroupMember.ps1
  - Public/Remove-AdmanLocalUser.ps1
  - Public/Reset-AdmanComputerAccount.ps1
  - Public/Set-AdmanLocalUser.ps1
  - Public/Set-AdmanUserPassword.ps1
  - Public/Start-Adman.ps1
  - Public/Unlock-AdmanUser.ps1
  - config/adman.defaults.json
  - config/adman.example.json
  - config/adman.schema.json
  - rules/AdmanSafetyRules.psm1
  - tests/Audit.CreateFlowStrictMode.Tests.ps1
  - tests/Computer.Disable.Tests.ps1
  - tests/Computer.Move.Tests.ps1
  - tests/Computer.Reset.Tests.ps1
  - tests/Config.FailClosed.Tests.ps1
  - tests/Config.Load.Tests.ps1
  - tests/Config.RoundTrip.Tests.ps1
  - tests/Group.Add.Tests.ps1
  - tests/Group.Protected.Tests.ps1
  - tests/Group.Remove.Tests.ps1
  - tests/Local.Gate.Tests.ps1
  - tests/Local.Group.Tests.ps1
  - tests/Local.User.Tests.ps1
  - tests/Menu.IdentityResolver.Tests.ps1
  - tests/Menu.Tests.ps1
  - tests/Mocks/ActiveDirectory.psm1
  - tests/Module.Manifest.Tests.ps1
  - tests/Safety.ConfirmationRestored.Tests.ps1
  - tests/Safety.GateOrder.Tests.ps1
  - tests/Safety.GroupRemediation.Tests.ps1
  - tests/Safety.NoHardDelete.Tests.ps1
  - tests/Safety.PreviewEqualsExecute.Tests.ps1
  - tests/Safety.RefusalSurface.Tests.ps1
  - tests/Start.Adman.Tests.ps1
  - tests/User.Create.Tests.ps1
  - tests/User.Disable.Tests.ps1
  - tests/User.Move.Tests.ps1
  - tests/User.Password.Tests.ps1
  - tests/User.Unlock.Tests.ps1
findings:
  critical: 4
  warning: 8
  info: 4
  total: 16
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-07-16
**Depth:** standard
**Files Reviewed:** 70
**Status:** issues_found

## Summary

Phase 02 implements the single-object lifecycle write surface behind a fixed-order mutation gate. The architecture is sound: one private gate funnels every destructive verb through resolve -> policy -> confirm -> PENDING-audit -> write -> OUTCOME-audit, with a write-ahead fail-closed audit reservation. The allow-list deliberately excludes the hard-delete verb, and the deny-RID/protected-group/managed-OU checks are layered correctly. The audit writer is synchronous and flushes durably.

The adversarial pass surfaced four Critical defects that break the safety contract in reachable paths, plus eight Warnings that degrade robustness or test fidelity. The most consequential findings:

1. **CR-01** — `Set-AdmanUserPassword` invokes the gate three times (reset, Set-ADUser, Unlock) but only returns the first result. If the second or third gate call throws after the first succeeded, the operator sees an unhandled exception with no correlation ID, and the audit log shows `Success` for the reset while the follow-up failure is lost.

2. **CR-02** — `Test-AdmanLocalTargetAllowed`'s orphaned-SID fallback regex `'0x80070534|0x534'` is a substring match against the exception message. The comment at lines 88-93 claims this was fixed to match structured HResult/NativeErrorCode, but the actual code at line 85 still uses the regex. `0x534` is a substring of many unrelated hex error codes (e.g., `0x5340`, `0x15340`), so a non-orphaned-SID error whose message happens to contain `0x534` would be misclassified as orphaned-SID and trigger the WMI fallback instead of failing closed. The comment and the code disagree — the code was not actually fixed.

3. **CR-03** — `Read-AdmanActionParams`'s `GeneratedPassword` Prompt path stores `$first` into `$params[$name]` at line 197, then sets `$firstConsumed = $true` at line 199. If an exception occurs between these two lines (e.g., a StrictMode error on `${name}Source`), the `finally` block sees `$firstConsumed = $false` and disposes `$first` — but `$params[$name]` still holds a reference to the disposed SecureString. The caller will splat a disposed SecureString into the verb, causing an `ObjectDisposedException` deep in the gate.

4. **CR-04** — `Invoke-AdmanMutation`'s `New-ADUser` uniqueness pre-flight interpolates `$Parameters['Name']` (free-text CN input) into `Get-ADObject -Filter "cn -eq '$cnEsc'"` without validating against wildcards. The `Escape-AdmanAdFilterLiteral` helper explicitly documents that it does NOT escape `*` and `?`, and that "callers that need exact-match semantics use -eq and the caller is responsible for not passing user-controlled wildcards into -eq positions." The gate IS the caller, and it does not validate. A CN containing `*` could cause the pre-flight to false-negative (miss a real collision) or throw a parser error.

## Critical Issues

### CR-01: Set-AdmanUserPassword swallows follow-up gate failures and mislabels audit

**File:** `Public/Set-AdmanUserPassword.ps1:159-176`
**Issue:** The verb invokes `Invoke-AdmanMutation` three times (Set-ADAccountPassword, Set-ADUser, Unlock-ADAccount) but only captures the first result. If the Set-ADUser or Unlock gate call throws after the password reset succeeded, the operator sees an unhandled exception with no correlation ID, and the audit log shows `Success` for the reset while the follow-up failure is lost. The three sub-operations are not atomic and there is no compensating action or aggregated error reporting.

Additionally, the second call passes `@{ ChangePasswordAtLogon = $mustChange }` to `Set-ADUser`. The `Adman.AD.Write.Set-ADUser` wrapper splats `@Parameters` directly into `Set-ADUser`. If any future caller adds an unexpected key to `$Parameters`, `Set-ADUser` will throw "parameter cannot be found". The wrapper does not whitelist allowed keys.

**Fix:**
```powershell
# Capture all three results and aggregate failures
$results = @()
$errors = @()
try {
    $results += Invoke-AdmanMutation -Verb 'Set-ADAccountPassword' -Targets @($Identity) `
        -Parameters @{ NewPassword = $NewPassword } -Force:$Force -WhatIf:$WhatIfPreference
} catch { $errors += $_ }

if ($errors.Count -eq 0) {
    try {
        $results += Invoke-AdmanMutation -Verb 'Set-ADUser' -Targets @($Identity) `
            -Parameters @{ ChangePasswordAtLogon = $mustChange } -Force:$Force -WhatIf:$WhatIfPreference
    } catch { $errors += $_ }
}

if ($Unlock -and $errors.Count -eq 0) {
    try {
        $results += Invoke-AdmanMutation -Verb 'Unlock-ADAccount' -Targets @($Identity) `
            -Parameters @{} -Force:$Force -WhatIf:$WhatIfPreference
    } catch { $errors += $_ }
}

if ($errors.Count -gt 0) {
    $msg = "One or more sub-operations failed: $($errors.Exception.Message -join '; ')"
    throw $msg
}
return $results[0]
```

### CR-02: Test-AdmanLocalTargetAllowed orphaned-SID regex not actually fixed

**File:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1:85`
**Issue:** The comment at lines 88-93 claims the code was fixed to match structured HResult/NativeErrorCode instead of a message substring, but the actual code at line 85 still uses:
```powershell
if ($_.Exception.Message -match '0x80070534|0x534') {
```
The `0x534` alternative is a substring match that will false-positive on any error message containing `0x534` (e.g., `0x5340`, `0x15340`, `0x5341`). A non-orphaned-SID error whose message happens to contain this substring would be misclassified as orphaned-SID, triggering the WMI fallback instead of failing closed. The comment and the code disagree — the fix described in the comment was never applied.

**Fix:**
```powershell
} catch {
    $hr = $null
    $native = $null
    if ($null -ne $_.Exception) {
        if ($_.Exception.PSObject.Properties['HResult']) { $hr = $_.Exception.HResult }
        if ($_.Exception.PSObject.Properties['NativeErrorCode']) { $native = $_.Exception.NativeErrorCode }
    }
    $isOrphanedSid = ($hr -eq -2147023564) -or ($hr -eq 2147943732) -or ($native -eq 1332)
    if ($isOrphanedSid) {
        # WMI fallback...
    } else {
        $enumFailed = $true
    }
}
```

### CR-03: Read-AdmanActionParams GeneratedPassword Prompt path can dispose a stored SecureString

**File:** `Private/Menu/Read-AdmanActionParams.ps1:197-206`
**Issue:** In the Prompt path, `$params[$name] = $first` is executed at line 197, then `$firstConsumed = $true` at line 199. The `finally` block at line 201-205 checks `$firstConsumed` to decide whether to dispose `$first`. If an exception occurs between line 197 and line 199 (e.g., a StrictMode error when setting `$params["${name}Source"] = 'Prompt'` at line 198, or a memory pressure exception), the `finally` block sees `$firstConsumed = $false` and disposes `$first`. But `$params[$name]` still holds a reference to the now-disposed SecureString. The caller (`Start-Adman`) will splat this disposed SecureString into the target verb, causing an `ObjectDisposedException` deep in the gate.

**Fix:**
```powershell
# Set the consumed flag BEFORE storing into $params
$firstConsumed = $true
$params[$name] = $first
$params["${name}Source"] = 'Prompt'
$resolved = $true
```
Or wrap the store in a try/catch that nulls the reference on failure:
```powershell
try {
    $params[$name] = $first
    $params["${name}Source"] = 'Prompt'
    $firstConsumed = $true
    $resolved = $true
} catch {
    $params.Remove($name)
    throw
}
```

### CR-04: New-ADUser uniqueness pre-flight does not escape wildcards in CN check

**File:** `Private/Safety/Invoke-AdmanMutation.ps1:76-96`
**Issue:** The `Escape-AdmanAdFilterLiteral` helper explicitly documents that it does NOT escape `*` and `?` wildcards, and that "callers that need exact-match semantics use -eq and the caller is responsible for not passing user-controlled wildcards into -eq positions." The gate IS the caller, and it interpolates `$Parameters['Name']` (free-text CN input) directly into `Get-ADObject -Filter "cn -eq '$cnEsc'"` without validating against wildcards.

A CN containing `*` (e.g., `*admin*`) is not valid in AD, but the pre-flight's behavior is undefined: depending on the AD Web Services parser version, the `-eq` comparison may treat `*` as a literal (causing a false-negative miss of a real collision) or throw a parser error. The sAMAccountName check has the same issue, though sAMAccountName cannot legally contain `*` in AD.

**Fix:**
```powershell
# Validate against wildcards before the pre-flight
if ([string]$Parameters['Name'] -match '[*?]') {
    throw "CN '$($Parameters['Name'])' contains wildcard characters (* or ?), which are not permitted."
}
if ([string]$Parameters['SamAccountName'] -match '[*?]') {
    throw "sAMAccountName '$($Parameters['SamAccountName'])' contains wildcard characters (* or ?), which are not permitted."
}
```

## Warnings

### WR-01: Invoke-AdmanMutation group-refusal path writes N refused records but throws on first

**File:** `Private/Safety/Invoke-AdmanMutation.ps1:126-134`
**Issue:** When `Test-AdmanGroupAllowed` refuses a group, the gate writes one `Refused` audit record per member in `$resolved`, then throws. If there are multiple members, the operator sees N identical `Write-Warning` messages (one per member) followed by a single throw. The per-member audit is correct for forensics, but the warning spam is noisy. More importantly, the throw message is generic ("Group refused: <reason>") and does not name the members — the operator must scroll back through the warnings to see which members were affected.

**Fix:** Collect the member DNs into the throw message, or emit a single warning summarizing the refusal with the member list.

### WR-02: Write-AdmanAudit mutex WaitOne has no timeout

**File:** `Private/Audit/Write-AdmanAudit.ps1:60`
**Issue:** `[void]$mutex.WaitOne()` blocks indefinitely. If another adman process crashes while holding the mutex (or a zombie process holds it), this call hangs forever. The named mutex is a kernel object, so it should be abandoned on process death, but a hung process would block all subsequent audit writes.

**Fix:** Use `$mutex.WaitOne([timespan]::FromSeconds(30))` and throw a fail-closed error on timeout.

### WR-03: Initialize-AdmanConfig absolutizes AuditDir/ReportDir against process CWD, not module root

**File:** `Private/Config/Initialize-AdmanConfig.ps1:256-261`
**Issue:** `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($config.AuditDir)` resolves relative paths against the process's current working directory, not the module root. If the operator launches adman from a different directory (e.g., `runas /netonly` from `C:\Windows\System32`), the audit directory resolves to `C:\Windows\System32\.store\audit` instead of the intended `<module-root>\.store\audit`. The comment acknowledges this but claims the resolution makes "every downstream consumer agree" — it does, but on the wrong base.

**Fix:** Resolve relative paths against the module root:
```powershell
$moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not [System.IO.Path]::IsPathRooted($config.AuditDir)) {
    $config.AuditDir = Join-Path $moduleRoot $config.AuditDir
}
```

### WR-04: Resolve-AdmanIdentity AdComputer trailing-dollar lookup can false-positive on user accounts

**File:** `Private/Safety/Resolve-AdmanIdentity.ps1:112-120`
**Issue:** The trailing-dollar lookup `sAMAccountName -eq '$esc`$'` searches for ANY object class with that sAMAccountName. A user account named `PC01$` (unusual but possible) would match. The resolver does not filter by `objectClass -eq 'computer'`, so a user with a trailing-dollar sAMAccountName would be returned as a "computer" target.

**Fix:** Add `(objectClass -eq 'computer')` to the filter, or verify the returned object's class after the lookup.

### WR-05: Test-AdmanTargetAllowed protected-membership check swallows DC-unreachable as refusal

**File:** `Private/Safety/Test-AdmanTargetAllowed.ps1:134-142`
**Issue:** The `try/catch` around the IN_CHAIN query catches ALL exceptions and adds a refusal reason. If the DC is unreachable, the target is refused with "protected-membership check failed: <error>". This is fail-closed, which is correct for safety, but it means a transient DC outage blocks ALL mutations, not just protected-group checks. The error message is also logged as a refusal reason, which could leak internal DC topology information into the audit log.

**Fix:** Distinguish between "DC unreachable" (retry or escalate) and "query malformed" (fail closed). Consider a separate error category for infrastructure failures.

### WR-06: Menu FixedParameters merge can silently overwrite prompted values

**File:** `Public/Start-Adman.ps1:150-154`
**Issue:** The FixedParameters merge happens AFTER `Read-AdmanActionParams` returns, and it unconditionally overwrites any key in `$params` that collides with a FixedParameters key. The menu definition claims a Pester test enforces that FixedParameters keys must not collide with PromptSpec names, but if that test is bypassed or a future menu entry adds a colliding key, the operator's prompted input is silently discarded.

**Fix:** Add a runtime guard:
```powershell
foreach ($key in $entry.FixedParameters.Keys) {
    if ($params.ContainsKey($key)) {
        Write-Warning "FixedParameters key '$key' collides with prompted parameter; using fixed value."
    }
    $params[$key] = $entry.FixedParameters[$key]
}
```

### WR-07: Mock New-ADUser accepts ChangePasswordAtLogon, masking real parameter mismatch

**File:** `tests/Mocks/ActiveDirectory.psm1:372`
**Issue:** The mock `New-ADUser` declares `param($ChangePasswordAtLogon)` in its parameter block. The real `New-ADUser` cmdlet does not have this parameter. This mock-fidelity defect causes `Safety.GateOrder.Tests.ps1` Test 14 to pass while the real wrapper would throw at runtime if it accidentally passed the parameter.

**Fix:** Remove `$ChangePasswordAtLogon` from the mock's param block so the mock matches the real cmdlet's parameter set.

### WR-08: New-AdmanUser / Set-AdmanUserPassword / New-AdmanLocalUser / Set-AdmanLocalUser display-once plaintext via Write-Host

**File:** `Public/New-AdmanUser.ps1:188`, `Public/Set-AdmanUserPassword.ps1:173`, `Public/New-AdmanLocalUser.ps1:159`, `Public/Set-AdmanLocalUser.ps1:190`
**Issue:** All four verbs display the generated password via `Write-Host "Generated password for ${Name}: $plain"`. Write-Host writes to the host's display buffer, which on some hosts (transcription enabled, certain ISE/VS Code hosts) is captured to a log file. If `Start-Transcript` is running, the plaintext password lands in the transcript file on disk — defeating the "plaintext never touches any stream" invariant claimed in the comment block. The comment says "Plaintext never touches any stream or audit field" but Write-Host IS a stream (the information stream in PS5+, the host display buffer in all editions).

**Fix:** Either:
(a) Use `[Console]::WriteLine()` directly (bypasses the information stream but still hits the console buffer); OR
(b) Document the transcript caveat explicitly in the comment block and recommend operators not run under `Start-Transcript` when generating passwords; OR
(c) Copy the password to the clipboard via `Set-Clipboard` (Windows-only) instead of displaying it, with a fallback to Write-Host when clipboard is unavailable.

The current claim "never touches any stream" is factually incorrect.

## Info

### IN-01: Resolve-AdmanCreateTarget RDN escape does not handle leading/trailing spaces correctly

**File:** `Private/Safety/Resolve-AdmanCreateTarget.ps1:46-48`
**Issue:** The leading-space escape `if ($v -match '^ ') { $v = '\' + $v }` only escapes the FIRST leading space. A value like `'  John'` (two leading spaces) becomes `'\  John'` — the second space is still unescaped. RFC 4514 requires ALL leading spaces to be escaped. Similarly, the trailing-space replacement `$v -replace ' $', '\ '` only handles one trailing space.

**Fix:** Use a loop or regex to escape all leading/trailing spaces:
```powershell
$v = $v -replace '^(\s+)', { param($m) ($m.Groups[1].Value -replace ' ', '\ ') }
$v = $v -replace '(\s+)$', { param($m) ($m.Groups[1].Value -replace ' ', '\ ') }
```

### IN-02: AdmanWriteVerbs.ps1 comment says "9-verb" but the list contains 10 verbs

**File:** `Private/Safety/AdmanWriteVerbs.ps1:5, 22, 27-38`
**Issue:** The synopsis and `.DESCRIPTION` both say "9-verb AD write allow-list" but the returned array contains 10 entries. The count drifted when `New-ADUser` was added in Plan 02-02.

**Fix:** Update the comments to say "10-verb" (or just "the AD write allow-list" without a count).

### IN-03: Magic number 20 (default password length) repeated in multiple places

**File:** `Public/New-AdmanUser.ps1:121, 145`, `Public/Set-AdmanUserPassword.ps1:106, 130`, `Public/New-AdmanLocalUser.ps1:104, 127`, `Public/Set-AdmanLocalUser.ps1:137, 160`, `Private/Menu/Read-AdmanActionParams.ps1:120, 151`
**Issue:** The literal `20` (default password length) appears as the fallback when `$script:Config.security.passwordGeneration.length` is absent. It's also the default in `New-AdmanRandomPassword`. If the default ever changes, multiple sites need to be updated.

**Fix:** Define a module-level constant `$script:DefaultPasswordLength = 20` in the module `.psm1` and reference it everywhere.

### IN-04: Test-AdmanPasswordComplexity MinLength default diverges from config default

**File:** `Private/Utility/Test-AdmanPasswordComplexity.ps1:21`
**Issue:** The function defaults `MinLength = 20`, but the config schema default is also 20. If the config is updated to a different value, callers that rely on the function default (rather than passing the config value) will diverge. The function should source its default from the same constant as `New-AdmanRandomPassword`.

**Fix:** Change the default to `$script:DefaultPasswordLength` or require the parameter.

---

_Reviewed: 2026-07-16_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
