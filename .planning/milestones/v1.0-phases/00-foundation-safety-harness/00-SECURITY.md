---
phase: 00
slug: foundation-safety-harness
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: 2026-07-14
---

# Phase 00 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Register consolidated from the six `<threat_model>` blocks (00-01…00-06) plus the four SUMMARY `## Threat Flags` sections (all report "none beyond the plan's threat model"). `register_authored_at_plan_time: true`. Classification is **L1 grep-depth** (sufficient at `asvs_level: 1`); every `high`-severity control was re-confirmed against the live source this session (2026-07-14) and cross-checked against `00-VERIFICATION.md` (17/17 must-haves, re-verified 2026-07-14) and the operator's green lab re-run (UAT test 2).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| module import → session | Export boundary is the static SAFE-08 control; drift here is a bypass. | function surface (the gate must stay non-exported) |
| source tree (Public/) → AD | AST guard + custom PSSA rule prove no Public verb calls AD writes directly. | AD write cmdlets |
| Gallery → workstation | PSFramework install is a supply-chain crossing; first install is human-approved. | module package / version pin |
| .store/config.json → session | Config is the safety-policy source; tampering or fail-open load weakens every refusal. | managed-OU scope, deny-list, protected group (non-secret) |
| PSFramework auto-import → portable config | A per-user default location could silently override the portable file (fail-open). | config values |
| Set-/Import-AdmanConfig → CONF-02 | Config-edit verbs are a side channel that could bypass fail-closed. | config writes |
| DPAPI file (.store/*.xml) → session | Restored credential crosses disk→memory; wrong-user/machine or empty restore must not masquerade as a rights problem. | encrypted credential (secret) |
| logged-in admin → AD | Rights are probed; a rights probe that performs a real write is itself an unaudited mutation. | read-only probes |
| domain → session flags | Protected/deny resolution feeds every SAFE-05/06 refusal; a wrong SID hard-codes a bypass. | DomainSID / protected-group DNs |
| caller input (DN/identity) → policy | DNs/identities are attacker-influenceable; scope/deny must canonicalize and anchor, never substring-match. | target identities |
| policy decision → AD write | The gate is the single crossing where a refused target must be structurally unable to reach an AD write cmdlet. | mutation verbs |
| preview → execute | If preview re-resolves, it can show a different set than executes (preview lies). | resolved target array |
| operator → confirmation | Bulk y-y-y muscle memory; a mistyped/absent confirmation must fail closed. | confirmation tokens |
| mutation → audit record | The audit write is the fail-closed control; if it can be skipped/fail-open, an action runs unaudited. | audit JSON-lines |
| audit file on disk → monitoring | OUTCOME-write gaps and tampering must be detectable (orphan sweep), never silently dropped. | audit JSON-lines |
| secret-bearing call → log | Any password/reset value reaching the audit record is an information-disclosure crossing. | secrets |
| test fixture → mutation gate | The WhatIf test provisions/targets real lab users; a protected fixture would mask the SAFE-01/10 proof. | lab fixtures |
| objectSid-absent target → RID-deny check | The step-(b) hardening relaxes a StrictMode crash into a skip; done wrong it could weaken SAFE-05. | objectSid / RID |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-00-01 | Tampering | Public/ verb calling AD write cmdlets directly (gate bypass) | high | mitigate | `FunctionsToExport` explicit 7-fn list excl. `Invoke-AdmanMutation` (`adman.psd1:53`, no `*`) + AST guard (`tests/Safety.Gate.Tests.ps1`) + custom PSSA rule (single banned list); re-proven at 00-04/00-05 exit | closed |
| T-00-02 | Tampering | DN spoof escapes managed-OU scope via substring/prefix | high | mitigate | Component-boundary anchor `$t -eq $root -or $t.EndsWith(','+$root)` (`Test-AdmanTargetAllowed.ps1:73`); zero `-like` in scope check | closed |
| T-00-03 | Elevation of Privilege | Protected/Tier-0 mutation incl. nesting/gMSA; wrong or hard-coded SID | high | mitigate | gMSA objectClass pre-filter + one DC-side IN_CHAIN `1.2.840.113556.1.4.1941` (`Test-AdmanTargetAllowed.ps1:88`); never `adminCount`; live `(Get-ADDomain).DomainSID` resolution; `S-1-5-21-` = **0** in Private/ | closed |
| T-00-04 | Repudiation | Audit fail-open / skipped write lets a mutation run unaudited | high | mitigate | Write-ahead PENDING reservation, `Flush($true)` under `Global\adman-audit` mutex; ANY PENDING failure throws `AUDIT FAIL-CLOSED` before AD (`Write-AdmanAudit.ps1:86,94`) | closed |
| T-00-05 | Information Disclosure | Secret persisted in config / audit record / log | high | mitigate | No-secret schema proven **both directions** (clean record has zero secret-named keys; positive-control secret fixture is caught); `.store/` gitignored; credential never logged | closed |
| T-00-06 | Tampering | `-WhatIf` preview shows a different set than execute (preview lies) | high | mitigate | Single `Resolve-AdmanTarget` called once; identical array reference to preview + execute; Identity param set without `-SearchBase` | closed |
| T-00-07 | Tampering | PSFramework auto-import overrides managed-OU/deny-list (fail-open) | high | mitigate | `Import-PSFConfig -Path` only; zero `Register-PSFConfig` in source; fail-closed implemented independent of the framework | closed |
| T-00-08 | Tampering | Deny-list bypass via renamed built-in Administrator (RID-500) / localized name | high | mitigate | Match by objectSid RID `Split('-')[-1]` (`Test-AdmanTargetAllowed.ps1:60`), never sAMAccountName; renamed-RID-500 refused (regression green) | closed |
| T-00-09 | Spoofing | DPAPI restore from wrong user/machine or empty credential treated as valid | medium | mitigate | try/catch `CryptographicException 0x8009000B` + empty-password guard (`GetNetworkCredential().Password`) → delete bad file + `Get-Credential` fallback; keyed-AES rejected (`Get-AdmanCredential.ps1:94,100`) | closed |
| T-00-10 | Tampering | Bulk confirmation defeated by y-y-y muscle memory or empty/Enter accept | medium | mitigate | Exact-count token `-cne` at/above threshold (case-sensitive, refuses mismatch/empty); default-No ShouldProcess below threshold | closed |
| T-00-11 | Information Disclosure | Live domain touched by a unit test | medium | mitigate | `tests/Mocks/ActiveDirectory.psm1` mocks every AD/CIM/remoting cmdlet; Unit suite 138/0 green with zero network | closed |
| T-00-12 | Tampering | Lint rule disabled globally, weakening ShouldProcess enforcement | medium | mitigate | `PSScriptAnalyzerSettings.psd1` enables `PSUseShouldProcessForStateChangingFunctions`; only documented TUI-scoped WriteHost suppression; repo-wide 0 findings | closed |
| T-00-13 | Tampering | Set-/Import-AdmanConfig weakens scope/deny-list, bypassing CONF-02 | high | mitigate | Both verbs route through the single `Test-AdmanConfigValid` validator and re-run fail-closed; `SupportsShouldProcess ConfirmImpact='High'` | closed |
| T-00-14 | Tampering | Truncated/lossy config save drops nested safety keys | medium | mitigate | `ConvertTo-Json -Depth 5` on every save; round-trip test asserts nested keys survive; 5.1-safe PSCustomObject indexing | closed |
| T-00-15 | Tampering | Rights probe performs a real AD write to "test" permissions | medium | mitigate | Non-destructive probe (read managed OU + `whoami /groups`); zero AD-write cmdlets in `Test-AdmanCapability` | closed |
| T-00-16 | Tampering | A hard-delete verb ships (irreversible object removal) | high | mitigate | 9-verb allow-list excludes it; no `Adman.AD.Write` wrapper for it; `Remove-ADObject` = **0** in `Public/` + `Private/AD/`; ValidateSet rejects it | closed |
| T-00-17 | Repudiation | OUTCOME-write failure masked, or a fake AD rollback compounds damage | medium | mitigate | OUTCOME failure escalates (Event Log + Write-Warning + `$script:AuditDegraded`); never rolls back AD; orphan sweep flags PENDING-without-OUTCOME | closed |
| T-00-18 | Tampering | Integration test runs against a production domain by default | medium | mitigate | `-Tag 'Integration'` excluded from the default Unit filter; Skipped unless `ADMAN_TEST_OU` + `ADMAN_TEST_DC` set (confirmed in both integration files) | closed |
| T-00-19 | Tampering | `-WhatIf` misclassified as an operator decline aborts before PENDING audit; 00-06 step-(b) RID-deny skip could weaken SAFE-05 | high | mitigate | `[bool]$WhatIfPreference` evaluated **before** a ShouldProcess `$false` is read as decline (`Confirm-AdmanAction.ps1:52`); step-(b) null-guard skips RID-deny ONLY when objectSid absent — any object WITH a sid runs the exact prior deny check (DenyList/Protected/Scope regression 29/0; renamed RID-500 still refused) | closed |
| T-00-20 | Repudiation | WhatIf test targets a protected fixture → false pass/fail, SAFE-01/10 not genuinely proven | medium | mitigate | Dedicated non-protected `lab-whatif-*` fixtures (not nested-admin/gMSA/RID-500); asserts `Denied == 0`; lab re-run 2026-07-14: Succeeded==2, Denied==0, AD unchanged | closed |
| T-00-SC | Tampering | PSFramework supply-chain / wrong version pinned | high | mitigate | Build-time re-verification (`00-01-PSFramework-verified.md`, verdict **OK**); manifest pins exact `1.14.457`; first install human-approved (UAT test 1 passed — never auto-approved) | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above `workflow.security_block_on` (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**All 21 unique threats: mitigate disposition, mitigation present and verified → CLOSED. `threats_open: 0`.**

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|

No accepted risks. Every registered threat is mitigated in code and verified; none were accepted or transferred.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-07-14 | 21 | 21 | 0 | Claude (gsd-secure-phase, L1 grep-depth; asvs_level 1) |

**Verification basis (L1 grep-depth, run this session 2026-07-14):** `FunctionsToExport` excludes the gate (`adman.psd1:53`); `Remove-ADObject` / `Register-PSFConfig` / `adminCount` appear only in tests+docs asserting their absence (0 in production source); `S-1-5-21-` = 0 in Private/; IN_CHAIN OID present (`Test-AdmanTargetAllowed.ps1:88`); component-anchor scope (`:73`) with no `-like`; objectSid RID deny (`:60`, null-guarded by 00-06); `[bool]$WhatIfPreference` discriminator (`Confirm-AdmanAction.ps1:52`); `Flush($true)` + `AUDIT FAIL-CLOSED` (`Write-AdmanAudit.ps1:86,94`); DPAPI `0x8009000B` + empty-password guard (`Get-AdmanCredential.ps1:94,100`). Cross-checked against `00-VERIFICATION.md` (17/17 must-haves, exit gate green) and the operator lab re-run (UAT 3/3 passed; SAFE-01/06/10 live).

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log (none — all mitigated)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-07-14
