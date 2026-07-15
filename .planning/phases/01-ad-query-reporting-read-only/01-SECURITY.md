---
phase: 01
slug: ad-query-reporting-read-only
status: verified
threats_open: 0
asvs_level: 1
created: 2026-07-15
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Admin console → Start-Adman | Untrusted interactive input crosses here. | Keystrokes / menu selections (untrusted) |
| Start-Adman → Public verb | Menu must not inject or modify parameters beyond the prompt spec. | Prompt-spec hashtable (validated) |
| AD (RSAT) → Find/report verb | Raw AD objects enter the module here. | Raw AD user/computer/domain attributes (sensitive) |
| Find/report verb → renderer | Only normalized D-03 objects cross this boundary. | D-03 schema PSCustomObject (normalized) |
| Renderer → filesystem | CSV/HTML files are written to operator-specified paths. | Report files (sensitive, operator-chosen location) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Information Disclosure | Start-Adman banner | low | accept | Banner shows only domain/DC/recovery posture already known to the operator; no secret fields. | closed |
| T-01-02 | Tampering | Read-Host input validation | medium | mitigate | Top-level accepts only `1..N`/`Q` with copy 'Invalid selection. Enter a number or Q.' (Start-Adman.ps1:111); action prompts accept `1..N`/`B`/`Q` (Start-Adman.ps1:162); everything else re-prompts. | closed |
| T-01-03 | Information Disclosure | Menu prompt helper | low | mitigate | Read-AdmanActionParams returns only parameters declared in the prompt spec; no Invoke-Expression/iex/Add-Type/Start-Process (grep-verified 0 matches). | closed |
| T-01-SC | Tampering | Package installs | high | accept | No packages introduced in Phase 1 (D-04 zero-dependency output layer); no install task to tamper. | closed |
| T-02-01 | Information Disclosure | Find verbs returning out-of-scope objects | high | mitigate | `-SearchBase` per ManagedOUs root + Test-AdmanInManagedScope re-check on every emitted object (10 call sites across Find-AdmanUser, Find-AdmanComputer, Get-AdmanStaleReport, Get-AdmanAccountStateReport, Get-AdmanInventoryReport). | closed |
| T-02-02 | Information Disclosure | Read path wrongly hiding protected accounts | medium | mitigate | Reads apply ONLY Test-AdmanInManagedScope; Test-AdmanTargetAllowed absent from Public/ (grep-verified 0 matches) — deny-list/protected checks remain mutation-only. | closed |
| T-02-03 | Tampering | LDAP filter injection via AD `-Filter` strings | high | mitigate | Escape-AdmanAdFilterLiteral (single-quote + backslash doubling) applied before interpolation in both Find verbs (8 call sites); Escape-AdmanLdapFilterValue never used for `-Filter` (grep-verified 0 matches in Public/); tests cover O'Brien-style input. | closed |
| T-02-SC | Tampering | Package installs | high | accept | No packages introduced this phase. | closed |
| T-03-01 | Information Disclosure | Stale report misclassifying never-logged-on accounts | medium | mitigate | Separate NeverLoggedOn bucket with whenCreated cross-check against the grace window (Get-AdmanStaleReport.ps1:80-84). | closed |
| T-03-02 | Information Disclosure | Account-state report using unreliable UAC LOCKOUT bit | high | mitigate | Search-ADAccount -AccountDisabled/-AccountExpired/-LockedOut/-PasswordExpired (9 switch refs); userAccountControl bit math absent (grep-verified 0 matches in Public/). | closed |
| T-03-03 | Tampering | Incorrect grace buffer from wrong sync-interval source | medium | mitigate | Reads `(Get-ADDomain).LastLogonReplicationInterval` (domain NC head) with `$default = 14` fallback for null/zero/negative/exception (Get-AdmanLogonSyncInterval.ps1:38,42). | closed |
| T-03-04 | Information Disclosure | Per-DC lastLogon aggregation bypassing replicated semantics | high | mitigate | lastLogonTimestamp only; per-DC lastLogon explicitly forbidden (Get-AdmanStaleReport.ps1:8 "NEVER queries per-DC lastLogon"). | closed |
| T-03-SC | Tampering | Package installs | high | accept | No packages introduced this phase. | closed |
| T-04-01 | Information Disclosure | CSV/HTML file written to unexpected path | low | mitigate | Parent directory validated via Split-Path + Test-Path -PathType Container; no auto-creation (Export-AdmanReportCsv.ps1:62-67, Export-AdmanReportHtml.ps1:73-77). | closed |
| T-04-02 | Information Disclosure | HTML report leaks raw AD attributes | low | mitigate | Renderers consume the D-03 schema only; no raw AD object properties rendered. | closed |
| T-04-03 | Tampering | HTML contains executable JavaScript | low | mitigate | ConvertTo-Html -Head with static CSS fragment only; no JavaScript, no -CssUri, no external resources (grep-verified). | closed |
| T-04-04 | Denial of Service | Large result set exhausts memory in pipeline collector | low | mitigate | Export-AdmanReportCsv streams row-by-row (first-row create, then -Append; Export-AdmanReportCsv.ps1:102); console/HTML renderers document ~10,000-row soft bound. | closed |
| T-04-SC | Tampering | Package installs | high | accept | No packages introduced this phase. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01-01 | T-01-01 | Banner displays only domain/DC/recovery posture the operator already knows; no secret fields cross the boundary. | Plan disposition (author-time) | 2026-07-15 |
| AR-01-02 | T-01-SC | Zero-dependency output layer (D-04); no package installs exist to tamper with. | Plan disposition (author-time) | 2026-07-15 |
| AR-01-03 | T-02-SC | Zero-dependency output layer (D-04); no package installs exist to tamper with. | Plan disposition (author-time) | 2026-07-15 |
| AR-01-04 | T-03-SC | Zero-dependency output layer (D-04); no package installs exist to tamper with. | Plan disposition (author-time) | 2026-07-15 |
| AR-01-05 | T-04-SC | Zero-dependency output layer (D-04); no package installs exist to tamper with. | Plan disposition (author-time) | 2026-07-15 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-07-15 | 18 | 18 | 0 | /gsd-secure-phase (L1 grep-depth, ASVS 1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-07-15
