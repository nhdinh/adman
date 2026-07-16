---
status: complete
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md, 02-06-SUMMARY.md]
started: 2026-07-16T00:00:00.000Z
updated: 2026-07-16T07:00:00.000Z
---

## Current Test

[testing complete]

## Tests

### 1. Menu write sections render with grouping
expected: Start-Adman lists write verbs grouped under plain-text separators (User writes / Computer writes / Local writes / Group membership). Separators are not numbered and not selectable. 19 write entries total (Set-AdmanLocalUser appears 3x for Reset/Enable/Disable).
result: pass
note: "Retested 2026-07-16 under lab (lab-dc01.lab.local reachable, RightsSufficient=True, WinRM=True). Launch clean (no StorePath error; known ConvertFromPersistedValue warning only). Menu rendered: 6+4+7+2=19 write entries, unnumbered separators, local-user Reset/Enable/Disable at 18/19/20."

### 2. Menu password Generate/Prompt sub-choice
expected: Picking a password-taking verb from the menu (e.g. New-AdmanUser) renders a numeric sub-choice: 1 = Generate (CSPRNG), 2 = Prompt (typed, complexity-validated, no echo). B/Q back out of the sub-choice. Choosing Generate ends with the generated password displayed ONCE on screen.
result: issue
reported: "Sub-choice rendered correctly (1. Generate (recommended) / 2. Prompt / B. Back / Q. Exit). But entered 'adman-test' (not a DN) at 'Enter parent OU DN' — no prompt-time validation; flow crashed at Private/Safety/Invoke-AdmanMutation.ps1:90 with raw Get-ADObject error 'The supplied distinguishedName must belong to one of the following partition(s)...'. Generated password never displayed."
severity: major

### 3. Create AD user end-to-end (lab OU)
expected: New-AdmanUser against the lab managed OU: shows -WhatIf-style preview, requires confirmation, then the user exists in AD with must-change-at-next-logon set. The audit log gains a matching PENDING + OUTCOME(Success) pair naming the new user DN.
result: issue
reported: "With valid DN OU=adman-test,DC=lab,DC=local and Generate chosen: OperationStopped at Private/Audit/Write-AdmanAudit.ps1:154 — 'AUDIT FAIL-CLOSED: cannot write audit record (The property ''Value'' cannot be found on this object. Verify that the property exists.); refusing New-ADUser.' User never created (fail-closed held; no AD write without audit)."
severity: blocker

### 4. Password never echoed or written to audit
expected: After any Generate or Prompt flow (create or reset), the audit JSONL contains NO password material — searching the audit file for the generated password (or any password-looking field) finds nothing. The password appears only in the one-time screen display.
result: pass
note: "Verified via menu 10 (Reset user password) on fixture uat-reset1 with Generate. Generated password shown once on screen only; Select-String -SimpleMatch for the password value over audit-20260716.jsonl returned zero matches; PENDING+OUTCOME pair carries no password material. Side finding logged as G-02-4 (identity prompt requires full DN; sAMAccountName crashes app)."

### 5. Disable/Enable AD user with -WhatIf leaves AD unchanged
expected: Disable-AdmanUser -WhatIf on a lab user previews the action and changes nothing in AD (user still enabled). Without -WhatIf, the disable actually applies after confirmation; Enable-AdmanUser reverses it. Audit target DN equals the resolved user DN.
result: issue
reported: "-WhatIf leg correct (preview, whatIf:true audit pair, no AD change); disable applied and enable reversed; audit target DN exact on all records; PENDING/Success pairs share correlationIds. BUT neither Disable-AdmanUser nor Enable-AdmanUser showed ANY confirmation prompt — both executed immediately (gate result object returned: Succeeded 1). The confirmation guardrail is silently disarmed on the cmdlet path."
severity: blocker

### 6. Out-of-scope target refused
expected: Attempting a write (e.g. Disable-AdmanUser) against an AD user OUTSIDE the managed OUs is refused with a precise scope reason BEFORE any confirmation prompt. AD is unchanged and a Refused audit record is written.
result: pass
note: "Refused correctly: gate returned Denied:1/Succeeded:0, account still enabled, single Refused audit record with scope reason + target DN, no PENDING/Success pair. Side finding logged as G-02-6: refusal reason not surfaced to the operator (only 'Denied: 1' on screen; reason exists only in the audit record)."

### 7. Protected account refused
expected: Attempting a write (e.g. Set-AdmanUserPassword or Disable-AdmanUser) against a protected account (Domain Admins member / nested admin) is refused with a precise protected-identity reason. AD is unchanged and a Refused audit record is written.
result: pass
note: "Fixture uat-protected1 (managed OU + Domain Admins member) refused: Denied:1/Succeeded:0, still enabled, Refused audit record with protected-identity reason."

### 8. Unlock AD user via PDCe
expected: On a locked-out lab user, Unlock-AdmanUser clears the lockout (user can log on). On a user that is NOT locked, it no-ops with the message 'Account is not locked out.' and performs no write.
result: pass
note: "Fixture locked via bad binds (after re-enabling from the Test-5 confirmation re-check), LockedOut=True/lockoutTime non-zero; Unlock-AdmanUser cleared it (LockedOut=False, lockoutTime=0) with PENDING+Success audit pair; immediate second run returned 'Account is not locked out.' with no new audit records."

### 9. Move AD user/computer scope validation
expected: Move-AdmanUser (or Move-AdmanComputer) to a TargetPath inside the managed OUs succeeds after confirmation. A TargetPath OUTSIDE the managed roots throws a precise out-of-scope message BEFORE the gate runs — no prompt, no AD change, no audit PENDING.
result: pass
note: "In-scope move succeeded (DN updated to OU=moved-in); out-of-scope TargetPath threw the precise scope message with no AD change and no PENDING in audit; fixture moved back to managed root."

### 10. Computer account reset shows honest guidance
expected: Reset-AdmanComputerAccount on a lab computer emits guidance naming BOTH methods (AD-side 'Reset Account' AND on-machine Test-ComputerSecureChannel -Repair) and states the trade-off (AD-side reset breaks the secure channel until rejoin/repair). Under -WhatIf the guidance is suppressed.
result: pass
note: "Guidance on the real run named both methods + the secure-channel trade-off; -WhatIf run showed only the what-if line (guidance suppressed); audit PENDING+Success pairs with correct whatIf flags for CN=UAT-PC01."

### 11. Local user lifecycle on localhost
expected: New-AdmanLocalUser creates a local account (Generate or Prompt password). Set-AdmanLocalUser -Password resets it; -Enable / -Disable toggle it (menu entries dispatch these WITHOUT further prompting). Remove-AdmanLocalUser requires TYPING the count '1' to confirm (even for a single account) and the audit record carries pre-delete state (SID, group memberships, profile path). Any -ComputerName that is not localhost throws 'Remote targets arrive in Phase 3'.
result: pass
note: "After G-02-7 inline fix + elevated shell: create/disable/enable/reset/delete all worked; removal audit carried preDeleteState (SID + GroupMemberships proven non-empty via uatlocal2 in Users; ProfilePath null is factual for never-logged-on accounts); non-localhost -ComputerName threw 'Remote targets arrive in Phase 3'. Typed-count prompt absent — expected under G-02-5."

### 12. Group membership with protected-group asymmetry
expected: Add-AdmanGroupMember to a protected group (e.g. Domain Admins) is REFUSED by direct SID equality with a Refused audit record — even for an otherwise in-scope member. Remove-AdmanGroupMember FROM that same protected group is ALLOWED (remediation) assuming the member passes member-side checks. The audit record for both names the member DN AND the group DN.
result: issue
reported: "Leg 1 (Add) passed: Refused, reason 'group is in the protected set (direct SID equality)'. Leg 2 (Remove) FAILED: Remove-AdmanGroupMember of uat-protected1 from Domain Admins was REFUSED with reason 'recursive member of protected group' (Denied:1) — the member-side protected check fires for ANY protected-group member, so remediation removal can never succeed. Also: the group-side Refused record names the group DN in both target and group fields but omits the MEMBER DN."
severity: major

## Summary

total: 12
passed: 8
issues: 4
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-02-1
  truth: "Start-Adman launches and lists write verbs grouped under section separators"
  status: resolved
  resolved_by: "inline working-tree fix (uncommitted): adman.psm1, Initialize-AdmanConfig.ps1, Test-AdmanAuditWritable.ps1, Initialize-Adman.ps1"
  resolved_at: 2026-07-16
  reason: "User reported: Initialize-AdmanConfig throws at Public/Initialize-Adman.ps1:33 - The variable '$script:StorePath' cannot be retrieved because it has not been set. TUI never starts."
  severity: blocker
  test: 1
  root_cause: "$script:StorePath is never initialized at module load. Four files do the lazy default 'if (-not $script:StorePath) { $script:StorePath = ''.store'' }' under Set-StrictMode -Version Latest (Initialize-AdmanConfig.ps1:204, Set-AdmanConfig.ps1:53, Export-AdmanConfig.ps1:26, Import-AdmanConfig.ps1:51). Under StrictMode, READING the unset variable throws before -not evaluates. Latent since c62e701 (00-02); every test injects $script:StorePath first, so the unset cold-start path was never exercised."
  artifacts:
    - path: "adman.psm1"
      issue: "missing $script:StorePath initialization at module load"
  missing:
    - "Initialize $script:StorePath = '.store' in adman.psm1 alongside $script:Config"
    - "Absolutize AuditDir/ReportDir at config load (PowerShell $PWD vs process-CWD split breaks .NET FileStream on relative paths)"
  debug_session: ""
  resolution: "FIXED inline during UAT (2026-07-16, uncommitted in working tree): (1) adman.psm1 initializes $script:StorePath = '.store' at load. (2) Test-AdmanAuditWritable catch Write-Warnings resolved path + exception before $false. (3) Initialize-Adman suppresses stray 'True' pipeline leak. (4) Initialize-AdmanConfig absolutizes AuditDir/ReportDir via GetUnresolvedProviderPathFromPSPath after validation - root cause of the user's audit-probe failure: their process CWD was C:\Users\nhdinh while $PWD was the repo root; cmdlet-based Test-Path/New-Item saw .store/audit under $PWD but the .NET FileStream resolved against the process CWD and threw 'part of the path not found'. Verified PS 5.1: simulated $PWD-vs-CWD split now reaches Get-AdmanCredential (past config/scope/audit-probe); unit suite 436 passed (identical to HEAD; 4 failures + Menu.Tests parse error pre-existing, not regressions). Parked: PSFramework installed version != pinned 1.14.457; Import-PSFConfig overload warning (swallowed by design); relative StorePath itself still CWD-relative (latent)."
  resolution: "FIXED inline during UAT (2026-07-16, uncommitted in working tree): (1) adman.psm1 now initializes $script:StorePath = '.store' at load. (2) Test-AdmanAuditWritable catch now Write-Warnings the resolved path + exception message before returning $false (silent fail-closed left no way to tell ACL vs invalid path). (3) Initialize-Adman suppresses the stray 'True' pipeline leak from Initialize-AdmanConfig. Verified PS 5.1 clean session: SetupMode INIT-OK; full init reaches designed CONF-02 empty-scope gate; probe failure now emits 'probe of <path> failed - <reason>'; valid probe still $true. Unit suite 436 passed with fixes vs 436 at HEAD (4 failures + Menu.Tests parse error pre-existing on this checkout, not regressions). FOLLOW-UP: user's audit-probe failure is environmental (probe passes from repo root under operator identity) - re-run will now show the exact reason; suspected full runas token without write rights to .store. ALSO parked: PSFramework installed version != pinned RequiredVersion 1.14.457 (manifest import fails; .psm1 import works); Import-PSFConfig 'ConvertFromPersistedValue overload' warning is swallowed-by-design noise; relative AuditDir/ReportDir/StorePath resolve against CWD not tool root (latent design gap)."

- gap_id: G-02-2
  truth: "Menu create-user flow validates the parent OU DN at prompt time (rejects non-DN input with a clear re-prompt); Choosing Generate ends with the generated password displayed ONCE on screen."
  status: failed
  reason: "User reported: entered 'adman-test' (not a DN) at 'Enter parent OU DN' — accepted without validation, then crashed at Private/Safety/Invoke-AdmanMutation.ps1:90 with raw Get-ADObject error 'The supplied distinguishedName must belong to one of the following partition(s): DC=lab,DC=local ...'. Guided TUI must catch malformed DN before dispatch; generated password never displayed."
  severity: major
  test: 2
  artifacts: []
  missing: []

- gap_id: G-02-4
  truth: "Menu identity prompts (e.g. Reset user password target) accept a sAMAccountName and resolve it to the object DN, or reject unresolvable input with a clean re-prompt."
  status: failed
  reason: "User reported: at the Identity prompt, entering 'uat-reset1' (sAMAccountName) crashed the app; only the full DN 'CN=UAT Reset Target,OU=adman-test,DC=lab,DC=local' works. Same defect class as G-02-2 (no prompt-time validation/resolution of identity input) — likely one shared fix (identity/DN resolver + re-prompt) covering both prompts."
  severity: blocker
  test: 4
  artifacts: []
  missing: []

- gap_id: G-02-5
  truth: "Every gate-routed mutation invoked as a cmdlet prompts for confirmation before executing (single-target: ShouldProcess prompt; bulk at/above threshold and typed-count verbs: exact-count token). Only -Force or an explicit caller-side -Confirm:$false bypasses the prompt."
  status: failed
  reason: "User reported: neither Disable-AdmanUser nor Enable-AdmanUser showed any confirmation prompt — both executed immediately and returned the gate result object (Succeeded: 1). Confirmation guardrail silently disarmed for cmdlet invocations."
  severity: blocker
  test: 5
  root_cause: "PRELIMINARY (high confidence; confirm in diagnosis): all 20 mutation call sites in Public/*.ps1 forward -Confirm:$false into Invoke-AdmanMutation (Unlock-AdmanUser:93, Disable-AdmanUser:43, Move-AdmanUser:74, Set-AdmanUserPassword:160/168/175, Move-AdmanComputer:74, Set-AdmanLocalUser:104/109/187, Disable-AdmanComputer:45, Enable-AdmanUser:43, Add-AdmanGroupMember:62, Add-AdmanLocalGroupMember:69, Reset-AdmanComputerAccount:67, Enable-AdmanComputer:45, Remove-AdmanGroupMember:61, New-AdmanLocalUser:151, Remove-AdmanLocalGroupMember:69, Remove-AdmanLocalUser:68, New-AdmanUser:180). -Confirm:$false sets $ConfirmPreference='None' inside the gate; Confirm-AdmanAction inherits it dynamically, so its prompt condition (Confirm-AdmanAction.ps1:81, '-not $Force -and ($ConfirmPreference -ne ''None'')') is false and the function returns Proceed without prompting. This also disarms the typed-count branch (Remove-LocalUser) since it lives inside the same condition. Fix direction: drop the unconditional -Confirm:$false forwarding (dynamic scope already does the right thing when a CALLER passes -Confirm:$false); regression-test that a plain cmdlet invocation prompts. NOTE: Verify how the menu dispatches — if the menu also routes via these public verbs, menu flows were equally unconfirmed during Tests 3/4."
  artifacts:
    - path: "Public/Enable-AdmanUser.ps1"
      issue: "line 43: unconditional -Confirm:$false forwarded to gate"
    - path: "Public/Disable-AdmanUser.ps1"
      issue: "line 43: unconditional -Confirm:$false forwarded to gate"
    - path: "Private/Safety/Confirm-AdmanAction.ps1"
      issue: "line 81: prompt condition inherits caller's $ConfirmPreference; disarmed by forwarded -Confirm:$false"
  missing: []
  debug_session: ""

- gap_id: G-02-6
  truth: "A refused write surfaces the precise refusal reason to the OPERATOR (scope/protected/deny wording on screen or in the thrown error), not only in the audit record."
  status: failed
  reason: "User reported: out-of-scope Disable-AdmanUser returned the gate summary object (Denied: 1, Succeeded: 0) with no reason shown; the scope reason exists only in the audit record. A junior admin sees 'Denied: 1' and cannot tell why. Gate early-return path (Invoke-AdmanMutation.ps1:148-158) emits no Write-Warning/throw carrying the aggregated refusal reasons."
  severity: minor
  test: 6
  artifacts: []
  missing: []

- gap_id: G-02-7
  truth: "Local-user verbs (New/Set/Remove-AdmanLocalUser) run against localhost without module-load-state errors."
  status: failed
  reason: "User reported: New-AdmanLocalUser -Name uatlocal1 -PasswordSource Generate threw at Test-AdmanLocalTargetAllowed.ps1:57 — 'The variable ''$script:LocalMachineScopeCache'' cannot be retrieved because it has not been set.'"
  severity: blocker
  test: 11
  root_cause: "Same StrictMode cold-start class as G-02-1: Test-AdmanLocalTargetAllowed.ps1:136 lazy-defaults via 'if (-not $script:LocalMachineScopeCache)', but reading the UNSET variable under Set-StrictMode -Version Latest throws before the default assigns. Nothing initialized it at module load; unit tests inject it (Local.Gate.Tests.ps1:97), masking the cold-start path."
  artifacts:
    - path: "adman.psm1"
      issue: "missing $script:LocalMachineScopeCache initialization at module load"
    - path: "Private/Safety/Test-AdmanLocalTargetAllowed.ps1"
      issue: "line 136: lazy default reads unset variable under StrictMode"
  missing: []
  resolution: "FIXED inline during UAT (2026-07-16, uncommitted): adman.psm1 now initializes $script:LocalMachineScopeCache = @{} at load alongside $script:StorePath. Awaiting module reload + retest in lab shell."
  debug_session: ""

- gap_id: G-02-8
  truth: "Remove-AdmanGroupMember FROM a protected group is ALLOWED (remediation asymmetry, D-04): the member-side protected-membership check must not refuse a removal whose whole purpose is to undo that membership."
  status: failed
  reason: "User reported: Remove-AdmanGroupMember of uat-protected1 from Domain Admins refused with reason 'recursive member of protected group' (Denied:1). Any protected-group member fails the member-side check, so remediation can never run — the asymmetry is dead code."
  severity: major
  test: 12
  root_cause: "PRELIMINARY: gate runs Test-AdmanTargetAllowed on the member for ALL group verbs; its protected-membership refusal is not operation-aware. For Remove-ADGroupMember the protected-membership refusal should be skipped (membership in the protected group is the state being remediated); other member-side checks (deny-RID, scope) should still apply."
  artifacts:
    - path: "Private/Safety/Invoke-AdmanMutation.ps1"
      issue: "member-side Test-AdmanTargetAllowed applied identically for Add and Remove (lines ~119-146)"
  missing: []
  debug_session: ""

- gap_id: G-02-9
  truth: "The Refused audit record for a protected-group Add names BOTH the member DN and the group DN."
  status: failed
  reason: "User reported: group-side Refused record for Add-ADGroupMember carries the group DN in both 'target' and 'group' fields; the member DN (who was being added) is absent — forensics cannot tell which member the add was attempted on."
  severity: minor
  test: 12
  root_cause: "PRELIMINARY: gate writes the group-refusal audit with -Target $groupObj (Invoke-AdmanMutation.ps1:123-124) before per-member records exist; member DN never enters the record."
  artifacts:
    - path: "Private/Safety/Invoke-AdmanMutation.ps1"
      issue: "group-refusal audit targets the group object only"
  missing: []
  debug_session: ""

- gap_id: G-02-3
  truth: "New-AdmanUser completes against the managed OU: preview, confirmation, user exists with must-change-at-next-logon, and the audit log gains a PENDING + OUTCOME(Success) pair naming the new user DN."
  status: failed
  reason: "User reported: OperationStopped at Write-AdmanAudit.ps1:154 — AUDIT FAIL-CLOSED (The property 'Value' cannot be found on this object); refusing New-ADUser. Create flow dead."
  severity: blocker
  test: 3
  root_cause: "PRELIMINARY (confirm in diagnosis): Write-AdmanAudit.ps1:78 reads ($t.objectSid.Value) under Set-StrictMode -Version Latest. For create-verbs the audit target is fabricated BEFORE the AD object exists, so objectSid is null (or a string) — .Value throws, the PENDING write fails, fail-closed refuses the mutation. Verbs against existing objects pass a real SecurityIdentifier and are unaffected. Fix direction: defensive SID extraction (null/type check) in the AD-target branch, mirroring the local-target branch's guarded $t.SID handling at line 87."
  artifacts:
    - path: "Private/Audit/Write-AdmanAudit.ps1"
      issue: "line 78: ($t.objectSid.Value) throws under StrictMode when objectSid is null/string (create-flow fabricated target)"
  missing: []
  debug_session: ""
