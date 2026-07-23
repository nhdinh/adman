---
phase: 05
slug: hardening-portability
status: verified
threats_open: 0
asvs_level: 1
created: 2026-07-23
---

# Phase 05 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Contributor -> Public/*.ps1 help blocks | Help text is part of the safety contract; inaccurate help can mislead reviewers. | Comment-based help metadata |
| Test code -> production code | Test fixes must not relax production safety invariants. | Test assertions, mock data |
| CI runner -> signed module artifacts | Signature proves source integrity before AllSigned execution. | Authenticode signatures, certificates |
| CI runner -> GitHub Actions | Workflow file defines the build; tampering with the workflow undermines the proof. | Workflow YAML, external actions |
| Audit writer -> filesystem | Hash chain detects tampering after the record is written. | JSONL audit records |
| Audit writer -> Event Log | Escalation path when the local write fails after a mutation. | Windows Event Log entries |
| Developer workstation -> Git | Pre-commit hook blocks accidental secret/config commits. | .store/ paths |
| Documentation -> operator | Static docs must not give unsafe examples or expose internal bypass details. | README, USAGE, RECOVERY-RUNBOOK |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01a1-01 | Tampering | Public/*.ps1 comment-based help | medium | mitigate | `tests/Help.Coverage.Tests.ps1` enforces Synopsis/Description/Example/Parameter presence; PSScriptAnalyzer enforces SupportsShouldProcess accuracy. | closed |
| T-05-01a1-02 | Information Disclosure | Public/*.ps1 help examples | medium | mitigate | Examples use `contoso.local`/`jdoe-fake`/`luser-fake` placeholders; no passwords or live OU paths. | closed |
| T-05-01a1-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |
| T-05-01a2-01 | Tampering | Public/*.ps1 comment-based help | medium | mitigate | `tests/Help.Coverage.Tests.ps1` enforces Synopsis/Description/Example/Parameter presence; scoped SupportsShouldProcess description assertion for AD lifecycle functions. | closed |
| T-05-01a2-02 | Information Disclosure | Public/*.ps1 help examples | medium | mitigate | Examples use `contoso.local` placeholders and fake identities. | closed |
| T-05-01a2-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |
| T-05-01a3-01 | Tampering | Public/*.ps1 comment-based help | medium | mitigate | `tests/Help.Coverage.Tests.ps1` enforces full help coverage for local/group/bulk/workflow functions; Restore-AdmanQuarantinedUser help describes audit retention/rotation/archive search. | closed |
| T-05-01a3-02 | Information Disclosure | Public/*.ps1 help examples | medium | mitigate | Examples use `contoso.local` placeholders and fake identities. | closed |
| T-05-01a3-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |
| T-05-01b-01 | Information Disclosure | README.md / docs/USAGE.md examples | high | mitigate | `tests/Docs.Coverage.Tests.ps1` verifies required sections; grep confirms no plaintext passwords or live OU paths; all examples use `contoso.local` placeholders. | closed |
| T-05-01b-02 | Information Disclosure | docs/RECOVERY-RUNBOOK.md | low | accept | Runbook is internal documentation; access control is repository/file-share permissions, not code. | closed |
| T-05-01b-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |
| T-05-02-01 | Tampering / Elevation of Privilege | AllSigned test run | high | mitigate | `build/Sign-AdmanModule.ps1` signs module files; `.github/workflows/ci.yml` imports self-signed public .cer into `Cert:\LocalMachine\TrustedPublisher` and `Cert:\LocalMachine\Root`, then verifies `Get-AuthenticodeSignature Status -eq 'Valid'`. | closed |
| T-05-02-02 | Information Disclosure | Self-signed cert in CI | high | mitigate | CI workflow generates cert in `Cert:\CurrentUser\My`, exports only the public .cer via `Export-Certificate`, and never logs or exports the private key. | closed |
| T-05-02-03 | Tampering | build/Sign-AdmanModule.ps1 exclusions | medium | mitigate | Exclusion regex `\(tests|\.github|\.githooks)\` verified in `Sign-AdmanModule.ps1:81`; acceptance criteria and CI verification confirm it. | closed |
| T-05-02-04 | Repudiation / Information Disclosure | .store/ in checkout | medium | mitigate | `.github/workflows/ci.yml` fails the build if `.store/` paths are tracked or staged; `.githooks/pre-commit` blocks staged `.store/` paths locally. | closed |
| T-05-02-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages; Pester/PSScriptAnalyzer/PSFramework installed via `Install-PSResource` from the PowerShell Gallery. | closed |
| T-05-03-01 | Tampering | Audit JSONL files | high | mitigate | `Private/Audit/Write-AdmanAudit.ps1` writes SHA-256 `hash`/`prevHash` per record under a named mutex; `Private/Audit/Rotation.ps1` provides `Get-AdmanAuditIntegrity` verifier; tamper-evident semantics documented. | closed |
| T-05-03-02 | Repudiation | Write-AdmanAudit OUTCOME path | high | mitigate | `Write-AdmanAudit.ps1` throws on PENDING failure and escalates OUTCOME failures to Windows Event Log ID 9001/Error; proven by `tests/Audit.EventLog.Tests.ps1`. | closed |
| T-05-03-03 | Information Disclosure | Audit archive folder | medium | mitigate | `Invoke-AdmanAuditRotation` archives to `$AuditDir\archive\YYYYMM\`; default `$AuditDir` is `.store/audit`, governed by OS filesystem ACLs. | closed |
| T-05-03-04 | Tampering | .store/ commit guard bypass | medium | mitigate | `.githooks/pre-commit` is executable (git index mode 100755) and rejects staged `.store/` paths; CI checkout scan provides defense in depth. | closed |
| T-05-03-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |
| T-05-04-01 | Tampering | tests/Workflow.OffboardingState.Tests.ps1 archive record | low | mitigate | Archive test setup computes a valid SHA-256 self-hash using `ConvertTo-Json -Compress -Depth 5` + UTF8 encoding, matching production canonicalization. | closed |
| T-05-04-02 | Denial of Service | Private/Config/Initialize-AdmanConfig.ps1 | low | mitigate | `Initialize-AdmanConfig.ps1:411-414` retains the CONF-02 fail-closed scope gate; whitespace-only `ManagedOUs` still throws `FAIL-CLOSED: managed-OU scope`. | closed |
| T-05-04-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-05-01b-01 | T-05-01b-02 | Recovery runbook is internal documentation; access control is repository/file-share permissions, not code. | Phase 5 plan author | 2026-07-21 |
| R-05-SC | T-05-0*1-SC through T-05-04-SC | Phase 5 plans do not install npm/pip/cargo packages; dev dependencies are installed via signed PowerShell Gallery modules. | Phase 5 plan author | 2026-07-21 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-07-23 | 23 | 23 | 0 | gsd-security-auditor (manual /gsd-secure-phase run) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-07-23
