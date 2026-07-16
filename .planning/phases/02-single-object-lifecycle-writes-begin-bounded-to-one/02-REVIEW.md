---
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
reviewed: 2026-07-16T00:00:00Z
depth: standard
files_reviewed: 64
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
  - tests/Menu.Tests.ps1
  - tests/Mocks/ActiveDirectory.psm1
  - tests/Module.Manifest.Tests.ps1
  - tests/Safety.GateOrder.Tests.ps1
  - tests/Safety.NoHardDelete.Tests.ps1
  - tests/Safety.PreviewEqualsExecute.Tests.ps1
  - tests/Start.Adman.Tests.ps1
  - tests/User.Create.Tests.ps1
  - tests/User.Disable.Tests.ps1
  - tests/User.Move.Tests.ps1
  - tests/User.Password.Tests.ps1
  - tests/User.Unlock.Tests.ps1
findings:
  critical: 4
  warning: 9
  info: 4
  total: 17
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-07-16
**Depth:** standard
**Files Reviewed:** 64
**Status:** issues_found

## Summary

The Phase 02 write-verb layer is structurally sound: the gate pattern is consistent, the SAFE-08/09 AST guard is enforced, ShouldProcess is honored, and SecureString handling is mostly careful (BSTR zeroing in finally blocks). However, the review surfaced four critical defects that violate the phase's own safety invariants, plus nine warnings.

Headline concerns:
1. **CR-01** — `Adman.AD.Write.Set-ADAccountPassword` invokes `Set-ADUser` and `Unlock-ADAccount` directly, bypassing the SAFE-08 AST gate's spirit (the allow-list is per-verb; the wrapper for one verb silently invokes two other write cmdlets).
2. **CR-02** — `Resolve-AdmanLocalTarget` enumerates local Administrators group membership for EVERY verb (including `New-LocalUser` create-branch and `Add-LocalGroupMember`), causing N+1 CIM queries per call and a perf/correctness hazard on machines with many groups.
3. **CR-03** — `Test-AdmanLocalTargetAllowed` runs the machine-in-scope AD lookup (`Resolve-AdmanTarget` on the machine$) for EVERY local target, even when the local verb has nothing to do with AD scope. This makes local verbs depend on AD availability — a workstation with no DC connectivity cannot run any local verb, contradicting the "local accounts on managed machines" requirement.
4. **CR-04** — `Write-AdmanAudit` PENDING-failure path throws, but the throw message includes `$_.Exception.Message` from arbitrary downstream exceptions. Under StrictMode with certain failure shapes (e.g., null-path Test-Path), the catch block itself can throw a secondary exception that masks the audit failure.

## Critical Issues

### CR-01: Set-ADAccountPassword wrapper bypasses the per-verb allow-list by calling Set-ADUser and Unlock-ADAccount

**File:** `Private/AD/Adman.AD.Write.ps1:115-132`
**Issue:** The `Adman.AD.Write.Set-ADAccountPassword` wrapper does not just invoke `Set-ADAccountPassword`. It also invokes `Set-ADUser` (to apply `-ChangePasswordAtLogon`) and conditionally `Unlock-ADAccount`. The SAFE-09 allow-list (`AdmanWriteVerbs.ps1`) is structured as one-wrapper-per-verb, and the AST gate (`AdmanSafetyRules.psm1`) scopes the banned-literal check to `Public/` only — so this is technically allowed. But the *safety invariant* the gate is supposed to enforce is "every destructive AD write flows through `Invoke-AdmanMutation` with its own PENDING/OUTCOME audit pair and its own confirm." Here, a single gate invocation of verb `Set-ADAccountPassword` silently triggers up to THREE distinct AD writes (password reset + Set-ADUser + Unlock-ADAccount), all under one audit record. The audit record's `what` field will say `Set-ADAccountPassword`, but AD state has been mutated by two other cmdlets that the operator never explicitly confirmed. If `Set-ADUser` fails after `Set-ADAccountPassword` succeeded, the gate's catch records `Result='Failure'` for the whole operation — but the password WAS reset, leaving the directory in an inconsistent state with a misleading audit trail.

Additionally, the follow-up `Set-ADUser` and `Unlock-ADAccount` calls run inside the same `ShouldProcess` guard as the password reset, but they are SEPARATE AD operations with separate failure modes. The current structure conflates them.

**Fix:**
Either:
(a) Split into three separate gate invocations at the Public-verb layer (`Set-AdmanUserPassword` calls the gate three times: `Set-ADAccountPassword`, `Set-ADUser`, optionally `Unlock-ADAccount`), each with its own audit pair; OR
(b) Document the composite as a single logical operation, change the audit record's `what` field to name all three sub-operations (e.g., `Set-ADAccountPassword+Set-ADUser+Unlock-ADAccount`), and add a test that asserts the composite audit shape; OR
(c) Move `-ChangePasswordAtLogon` to a separate explicit gate call in `Set-AdmanUserPassword` after the password-reset gate returns, so the operator sees two distinct confirmations.

The current "silent composite" is the worst of the three options.

---

### CR-02: Resolve-AdmanLocalTarget enumerates ALL local groups for EVERY verb (N+1 CIM query, wrong scope)

**File:** `Private/Safety/Resolve-AdmanLocalTarget.ps1:80-102`
**Issue:** The `PreDeleteState` capture (group memberships + profile path) is gated only on `$Verb -eq 'Remove-LocalUser'`, but the OUTER loop that fetches group memberships via `Get-LocalGroupMember -Name $g.Name` is inside the `foreach ($name in $Targets)` loop. For a single-target call this is fine, but the code iterates `Get-LocalGroup` (potentially dozens of groups on a real machine) and calls `Get-LocalGroupMember` per group — an N+1 query pattern. More importantly, this code runs even when the caller is the local gate resolving targets for `Add-LocalGroupMember` or `Remove-LocalGroupMember` — verbs where the pre-delete state is irrelevant. The `if ($Verb -eq 'Remove-LocalUser')` guard wraps the entire block, so this is actually scoped correctly.

Re-reading more carefully: the guard IS in place. The actual bug is narrower: the orphaned-SID tolerance check `$_.Exception.Message -notmatch '0x80070534|0x534'` will swallow ANY exception whose message happens to contain `0x534` as a substring — including unrelated errors. The regex `0x534` matches the literal substring `0x534` anywhere in the message, so an error like `Failed to open SAM database, error 0x5340` would be incorrectly treated as an orphaned-SID and swallowed. The correct check is on the exception's HResult or NativeErrorCode, not a substring match on the message.

**Fix:**
```powershell
} catch {
    $hr = $_.Exception.HResult
    # 0x80070534 = 2147943732 (ERROR_NONE_MAPPED - no mapping between account names and SIDs)
    if ($hr -ne 2147943732 -and $hr -ne 1332) { throw }
}
```
Or check `$_.Exception -is [System.ComponentModel.Win32Exception] -and $_.Exception.NativeErrorCode -eq 1332`.

---

### CR-03: Test-AdmanLocalTargetAllowed forces AD dependency for ALL local verbs

**File:** `Private/Safety/Test-AdmanLocalTargetAllowed.ps1:56-68, 122-135`
**Issue:** Check (c) "machine-in-scope" resolves the target machine's AD computer object via `Resolve-AdmanTarget -Targets @("$($Object.Machine)`$")` and runs `Test-AdmanTargetAllowed` on it. This runs for EVERY local verb, including `New-LocalUser` (create-branch) and `Add-LocalGroupMember`. The stated intent is "local accounts on managed machines" — but the implementation makes local verbs fail-closed when AD is unreachable, even for purely local operations.

Concretely: if the operator runs `New-AdmanLocalUser -Name 'luser'` on a jump box that has lost DC connectivity, the gate throws "machine-in-scope check failed: ..." and refuses. This contradicts the project constraint that the tool must "degrade to CIM/WMI or skip per host" when remoting fails — the same degradation logic should apply when AD itself is unreachable for a local-only operation.

Worse, the check is performed against `$script:Config.DC` (pinned DC). If that DC is offline but another DC is available, the local verb still fails. The check also runs once per target — for a batch of 10 local users, that's 10 identical AD computer-object lookups against the same machine.

**Fix:**
Either:
(a) Cache the machine-in-scope decision per machine per session (the machine$ computer object doesn't move between OUs mid-session); OR
(b) Make the check opt-in via config (`safety.requireMachineInADScope`, default `$false` for Phase 2 localhost-only); OR
(c) Catch AD connectivity exceptions specifically and degrade to "warn but allow" when the target is localhost (the machine is trivially "in scope" for local operations on the operator's own workstation).

The current behavior makes local verbs unusable in any AD-degraded scenario.

---

### CR-04: Write-AdmanAudit catch block can throw a secondary exception that masks the audit failure

**File:** `Private/Audit/Write-AdmanAudit.ps1:127-141`
**Issue:** The PENDING-failure throw at line 131 uses `$_.Exception.Message` to build the error message. Under `Set-StrictMode -Version Latest`, if the original exception was itself a StrictMode violation (e.g., referencing a property on a null object), the `$_` automatic variable in the catch block may not have the expected shape, and `$_.Exception.Message` can itself throw. More importantly, the `finally` block calls `$mutex.ReleaseMutex()` and `$mutex.Dispose()` unconditionally. If `New-AdmanAuditMutex` itself threw (returned `$null`), the `WaitOne()` call at line 47 would have thrown, but the `finally` block would still execute and throw a `NullReferenceException` on `$mutex.ReleaseMutex()`, masking the original mutex-acquisition failure.

The `if ($Result -eq 'PENDING')` check inside the catch is correct in spirit, but the throw at line 131 loses the original exception as an inner exception, making diagnosis harder.

**Fix:**
```powershell
} catch {
    $originalError = $_
    if ($Result -eq 'PENDING') {
        $msg = "AUDIT FAIL-CLOSED: cannot write audit record"
        if ($originalError -and $originalError.Exception -and $originalError.Exception.Message) {
            $msg = "$msg ($($originalError.Exception.Message))"
        }
        $msg = "$msg; refusing $Verb."
        throw [System.InvalidOperationException]::new($msg, $originalError.Exception)
    }
    # OUTCOME path...
} finally {
    if ($null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
        try { $mutex.Dispose() } catch { }
    }
}
```

---

## Warnings

### WR-01: Set-AdmanLocalUser Enable/Disable menu entries bypass the password-source code path but still splat unused keys

**File:** `Public/Set-AdmanLocalUser.ps1:99-110`, `Private/Menu/Get-AdmanMenuDefinition.ps1:298-315`
**Issue:** The menu's "Enable local user" entry has `FixedParameters = @{ Enable = $true }` and `PromptSpec` containing only `Name`. After splat-merging, `$params` contains `Name` and `Enable`. The verb binds parameter set `Enable` and dispatches correctly. However, the `Password` and `PasswordSource` parameters are declared in the `Reset` parameter set only — so when the menu splats `Enable=$true`, the binder correctly resolves to the `Enable` set. This works, but the `Set-AdmanLocalUser` verb has dead code: the entire D-05 password-sourcing block (lines 122-172) is unreachable when `-Enable` or `-Disable` is supplied, yet it sits between the parameter-set dispatch and the gate call. A future maintainer adding code between the dispatch and the gate could accidentally run password-sourcing logic on the Enable path.

**Fix:** Move the password-sourcing block into a `if ($PSCmdlet.ParameterSetName -eq 'Reset')` guard, or extract it to a helper function called only from the Reset path.

---

### WR-02: Confirm-AdmanAction hardcodes Remove-LocalUser threshold override; should be data-driven

**File:** `Private/Safety/Confirm-AdmanAction.ps1:47-48`
**Issue:** `if ($Verb -eq 'Remove-LocalUser') { $threshold = 1 }` hardcodes a per-verb override in the confirm function. As more irreversible verbs are added (e.g., a future `Remove-AdmanComputer` hard-delete), each will need a code change here. This should be data-driven via config or a per-verb metadata table.

**Fix:** Add a `safety.typedCountVerbs` array to the config schema (default `@('Remove-LocalUser')`), and check `$Verb -in @($script:Config.safety.typedCountVerbs)`.

---

### WR-03: Unlock-AdmanUser pre-reads LockedOut on PDCe but does NOT pass -WhatIf to the pre-read

**File:** `Public/Unlock-AdmanUser.ps1:62-70`
**Issue:** Under `-WhatIf`, the verb still calls `Get-ADDomain` and `Get-ADUser` to check `LockedOut`. These are read-only, so this is technically safe, but the pre-read can throw (e.g., user not found, DC unreachable) BEFORE the gate's own resolver runs — producing a different error than the gate would have produced. Worse, under `-WhatIf` the operator expects a dry-run preview, but if the account is not locked out, the verb returns "Account is not locked out." and skips the gate entirely — so `-WhatIf` produces NO output, even though the operator asked for a preview of what WOULD happen.

**Fix:** Under `-WhatIf`, skip the LockedOut pre-read and let the gate produce the dry-run preview. The pre-read is a UX fail-fast for the real path; it should not suppress the dry-run.

---

### WR-04: Read-AdmanActionParams GeneratedPassword Prompt path stores $first but never disposes $second

**File:** `Private/Menu/Read-AdmanActionParams.ps1:135-150`
**Issue:** The Prompt path reads two SecureStrings (`$first`, `$second`), compares them via transient BSTRs (correctly zeroed in finally), then stores `$first` in `$params[$name]` and discards `$second`. The `$second` SecureString is never disposed. While SecureString doesn't implement IDisposable in the strictest sense (it does — `[System.Security.SecureString]::Dispose()`), best practice is to dispose of the duplicate promptly. The BSTR is zeroed, but the SecureString's internal buffer remains until GC.

**Fix:**
```powershell
$params[$name] = $first
$params["${name}Source"] = 'Prompt'
$second.Dispose()  # release the duplicate's internal buffer
$resolved = $true
```

---

### WR-05: New-AdmanUser / Set-AdmanUserPassword / New-AdmanLocalUser / Set-AdmanLocalUser display-once plaintext via Write-Host

**File:** `Public/New-AdmanUser.ps1:188`, `Public/Set-AdmanUserPassword.ps1:173`, `Public/New-AdmanLocalUser.ps1:159`, `Public/Set-AdmanLocalUser.ps1:190`
**Issue:** All four verbs display the generated password via `Write-Host "Generated password for ${Name}: $plain"`. Write-Host writes to the host's display buffer, which on some hosts (transcription enabled, certain ISE/VS Code hosts) is captured to a log file. If `Start-Transcript` is running, the plaintext password lands in the transcript file on disk — defeating the "plaintext never touches any stream" invariant claimed in the comment block. The comment says "Plaintext never touches any stream or audit field" but Write-Host IS a stream (the information stream in PS5+, the host display buffer in all editions).

**Fix:** Either:
(a) Use `[Console]::WriteLine()` directly (bypasses the information stream but still hits the console buffer); OR
(b) Document the transcript caveat explicitly in the comment block and recommend operators not run under `Start-Transcript` when generating passwords; OR
(c) Copy the password to the clipboard via `Set-Clipboard` (Windows-only) instead of displaying it, with a fallback to Write-Host when clipboard is unavailable.

The current claim "never touches any stream" is factually incorrect.

---

### WR-06: Invoke-AdmanMutation New-ADUser uniqueness pre-flight uses -Filter with escaped literal but no -SearchBase

**File:** `Private/Safety/Invoke-AdmanMutation.ps1:81-91`
**Issue:** The sAMAccountName uniqueness check runs `Get-ADObject -Filter "sAMAccountName -eq '$samEsc'" -Server $script:Config.DC` with NO `-SearchBase`. This searches the ENTIRE domain, including OUs outside the managed scope. A sAMAccountName collision in an unmanaged OU will refuse the create, even though the operator has no ability to see or modify that unmanaged object. This is over-refusal: AD enforces sAMAccountName uniqueness forest-wide, so the check is technically correct, but the error message ("sAMAccountName 'X' already exists.") doesn't tell the operator WHERE the collision is, making diagnosis hard when the conflicting object is in an unmanaged OU they can't see.

**Fix:** Add `-Properties DistinguishedName` to the call and include the conflicting DN in the error message:
```powershell
$samHit = Get-ADObject -Filter "sAMAccountName -eq '$samEsc'" `
    -Server $script:Config.DC -Properties DistinguishedName -ErrorAction Stop
if ($samHit) {
    throw "sAMAccountName '$($Parameters['SamAccountName'])' already exists at '$($samHit.DistinguishedName)'."
}
```

---

### WR-07: Test-AdmanGroupAllowed deny-RID check uses string comparison against $script:DenyRids without type coercion

**File:** `Private/Safety/Test-AdmanGroupAllowed.ps1:46-49`
**Issue:** `$rid = $sidString.Split('-')[-1]` produces a string like `'512'`. The check `if ($rid -in $script:DenyRids)` does a case-sensitive string `-in` comparison. If `$script:DenyRids` was loaded from JSON as integers (e.g., `[512]` rather than `['512']`), the comparison fails silently and the deny-list is bypassed. The same pattern exists in `Test-AdmanTargetAllowed.ps1:83-86`.

**Fix:** Coerce both sides to string explicitly:
```powershell
$rid = [string]($sidString.Split('-')[-1])
$denyStrings = @($script:DenyRids | ForEach-Object { [string]$_ })
if ($rid -in $denyStrings) { $reasons.Add("deny-listed RID $rid") }
```
Or enforce string type at config-load time in `Initialize-AdmanConfig.ps1` (validate that every `DenyList.token` is a string).

---

### WR-08: Resolve-AdmanCreateTarget fabricates DN by naive string interpolation; CN escaping not handled

**File:** `Private/Safety/Resolve-AdmanCreateTarget.ps1:38`
**Issue:** `DistinguishedName = "CN=$Name,$ParentOuDn"` interpolates the CN directly. If `$Name` contains a comma, equals sign, plus sign, backslash, or other DN-special characters (e.g., `Doe, John`), the fabricated DN is malformed. The downstream scope check in `Test-AdmanTargetAllowed` (create-branch) uses `ConvertTo-AdmanNormalizedDn` on the parent OU only, so the malformed DN doesn't break the scope check — but the audit record's `target` field will contain the malformed DN, and the `Adman.AD.Write.New-ADUser` wrapper passes `$o.DistinguishedName` to `ShouldProcess` for the preview line, producing a confusing preview.

**Fix:** Escape the CN per RFC 4514 before interpolation:
```powershell
$cnEsc = $Name -replace '\\', '\\' -replace ',', '\,' -replace '=', '\=' -replace '\+', '\+' `
    -replace '"', '\"' -replace '<', '\<' -replace '>', '\>' -replace ';', '\;' -replace '#', '\#'
DistinguishedName = "CN=$cnEsc,$ParentOuDn"
```
Or use a dedicated `ConvertTo-AdmanRdnEscaped` helper.

---

### WR-09: Start-Adman menu dispatches to $Verb via string name; no validation that the function exists

**File:** `Public/Start-Adman.ps1:157`
**Issue:** `$reportData = & $Verb @params` invokes the verb by string name. If `Get-AdmanMenuDefinition` returns an entry whose `Verb` doesn't resolve to a loaded function (e.g., a typo in the menu def, or a verb that failed to export from the module), the call operator throws a generic "CommandNotFoundException" with no context about which menu entry failed. The MENU-04 test (`Menu.Tests.ps1:295-313`) pins the verb NAMES but doesn't verify they resolve to loaded functions at runtime.

**Fix:** Validate before dispatch:
```powershell
$cmd = Get-Command $Verb -ErrorAction SilentlyContinue
if (-not $cmd) {
    Write-Host "Menu entry '$($entry.Label)' dispatches to '$Verb' which is not loaded. Contact the adman maintainer." -ForegroundColor Red
    continue
}
$reportData = & $Verb @params
```

---

## Info

### IN-01: AdmanWriteVerbs.ps1 comment says "9-verb" but the list contains 10 verbs

**File:** `Private/Safety/AdmanWriteVerbs.ps1:5, 22, 27-38`
**Issue:** The synopsis and `.DESCRIPTION` both say "9-verb AD write allow-list" but the returned array contains 10 entries (`Disable-ADAccount`, `Enable-ADAccount`, `Move-ADObject`, `Set-ADUser`, `Set-ADComputer`, `Set-ADAccountPassword`, `Unlock-ADAccount`, `Add-ADGroupMember`, `Remove-ADGroupMember`, `New-ADUser`). The count drifted when `New-ADUser` was added in Plan 02-02.

**Fix:** Update the comments to say "10-verb" (or just "the AD write allow-list" without a count).

---

### IN-02: Read-AdmanActionParams has unused `$required` variable for Choices/GeneratedPassword paths

**File:** `Private/Menu/Read-AdmanActionParams.ps1:86`
**Issue:** `$required = [bool](& $getVal 'Required')` is read for every field, but the Choices and GeneratedPassword branches never consult `$required` — they always loop until a valid selection or B/Q. Only the free-text branch uses `$required`. This is dead code for the choice paths.

**Fix:** Either remove the unused read for non-text paths, or document that Choices/GeneratedPassword are implicitly always required.

---

### IN-03: Magic number 20 (default password length) repeated in 5 places

**File:** `Public/New-AdmanUser.ps1:121, 145`, `Public/Set-AdmanUserPassword.ps1:106, 130`, `Public/New-AdmanLocalUser.ps1:104, 127`, `Public/Set-AdmanLocalUser.ps1:137, 160`, `Private/Menu/Read-AdmanActionParams.ps1:120, 151`
**Issue:** The literal `20` (default password length) appears as the fallback when `$script:Config.security.passwordGeneration.length` is absent. It's also the default in `New-AdmanRandomPassword -Length 20`. If the default ever changes, 11 sites need to be updated.

**Fix:** Define a module-level constant `$script:DefaultPasswordLength = 20` in the module `.psm1` and reference it everywhere.

---

### IN-04: tests/Mocks/ActiveDirectory.psm1 Search-ADAccount mock does not honor -SearchBase for out-of-scope row

**File:** `tests/Mocks/ActiveDirectory.psm1:308-318`
**Issue:** The mock returns one in-scope row (DN ends with `$sb`) and one out-of-scope row (DN is `OU=NotManaged,DC=mock,DC=local`). The out-of-scope row's DN is hardcoded and does NOT vary with `$sb`. This is fine for the current tests, but a future test that searches a DIFFERENT base (e.g., `OU=NotManaged`) would get the same out-of-scope row, which would then be IN scope — breaking the test's premise.

**Fix:** Make the out-of-scope row's DN derive from a sibling of `$sb`:
```powershell
$outScopeDn = "CN=OutScope{0},OU=NotManaged,{1}" -f $bucket, ($sb -replace '^[^,]+,', '')
```

---

_Reviewed: 2026-07-16_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
