---
status: testing
phase: 00-foundation-safety-harness
source: [00-VERIFICATION.md]
started: 2026-07-13T00:00:00.000Z
updated: 2026-07-13T00:00:00.000Z
---

## Current Test

number: 1
name: Approve and run the PSFramework/Pester/PSScriptAnalyzer install on a real workstation (00-01 user_setup / T-00-SC)
expected: |
  Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0) installs cleanly; the module still imports and the Unit suite stays green against the REAL PSFramework (tests currently use a throwaway stub).
awaiting: user response

## Tests

### 1. Approve and run the PSFramework/Pester/PSScriptAnalyzer install on a real workstation (00-01 user_setup / T-00-SC)
expected: Install-PSResource -Name PSFramework -Version 1.14.457 -Scope CurrentUser (plus Pester 6.0.0 / PSScriptAnalyzer 1.25.0) installs cleanly; the module still imports and the Unit suite stays green against the REAL PSFramework (tests currently use a throwaway stub).
why_human: The package-legitimacy seam did not run in this environment; the first PSFramework install is a deliberate human-approved supply-chain gate, never auto-approved.
result: [pending]

### 2. Optionally run the -Tag Integration tests against a disposable lab OU (set ADMAN_TEST_OU) to confirm SAFE-01/06/10 end-to-end -WhatIf and protected-account refusal
expected: AD is unchanged after a gated -WhatIf; the audit target list equals the resolved list; nested-DA / gMSA / renamed-RID-500 fixtures are Refused with precise reasons.
why_human: Lab-only by design (T-00-18); requires a real disposable domain/OU. Excluded from the default Unit run and cannot be auto-proven on a host with no live AD (VALIDATION manual-only).
result: [pending]

### 3. Confirm DPAPI cross-machine/cross-user re-prompt (CONF-04)
expected: A stored credential restored on a different machine/user throws CryptographicException 0x8009000B (or yields an empty password); the bad file is deleted and Get-Credential is invoked as fallback.
why_human: DPAPI is key-bound to user/machine; the cross-machine restore failure cannot be exercised on a single host and needs a second machine/user.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
