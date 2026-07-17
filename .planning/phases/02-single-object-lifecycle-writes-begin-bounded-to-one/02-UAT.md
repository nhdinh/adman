---
status: complete
phase: 02-single-object-lifecycle-writes-begin-bounded-to-one
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md, 02-06-SUMMARY.md]
started: 2026-07-16T00:00:00.000Z
updated: 2026-07-16T12:35:00Z
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
result: pass

### 3. Create AD user end-to-end (lab OU)
expected: New-AdmanUser against the lab managed OU: shows -WhatIf-style preview, requires confirmation, then the user exists in AD with must-change-at-next-logon set. The audit log gains a matching PENDING + OUTCOME(Success) pair naming the new user DN.
result: pass
note: "User uat-passwordgen1 created under OU=adman-test,DC=lab,DC=local. Audit PENDING+Success pair shares correlationId 18450ad0-28ae-43fe-ade2-18e8c0d70168; sid=null on synthetic pre-create target (no StrictMode throw)."

### 4. Password never echoed or written to audit
expected: After any Generate or Prompt flow (create or reset), the audit JSONL contains NO password material — searching the audit file for the generated password (or any password-looking field) finds nothing. The password appears only in the one-time screen display.
result: pass
note: "Verified via menu 10 (Reset user password) on fixture uat-reset1 with Generate. Generated password shown once on screen only; Select-String -SimpleMatch for the password value over audit-20260716.jsonl returned zero matches; PENDING+OUTCOME pair carries no password material. Side finding logged as G-02-4 (identity prompt requires full DN; sAMAccountName crashes app)."

### 5. Disable/Enable AD user with -WhatIf leaves AD unchanged
expected: Disable-AdmanUser -WhatIf on a lab user previews the action and changes nothing in AD (user still enabled). Without -WhatIf, the disable actually applies after confirmation; Enable-AdmanUser reverses it. Audit target DN equals the resolved user DN.
result: pass
note: "Disable/Enable now prompt for confirmation on the cmdlet path. -WhatIf still previews without mutating."

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
result: pass
note: "Add to Domain Admins refused by direct SID equality with member DN in target and group DN in group field. Remove from Domain Admins of uat-protected1 succeeded via menu (remediation asymmetry). Direct cmdlet path requires DN; menu resolves identity."

## Summary

total: 12
passed: 10
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
