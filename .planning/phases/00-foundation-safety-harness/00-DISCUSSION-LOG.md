# Phase 0: Foundation & Safety Harness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-10
**Phase:** 0-Foundation & Safety Harness
**Mode:** advisor (full_maturity tier; NON_TECHNICAL_OWNER signal = guided → light outcome framing applied)
**Areas discussed:** Logging & config backbone; Safety-core enforcement (protected-account detection + audit fail-closed); First-run setup & scope seed; Human-in-the-loop UX (credential storage + confirmation)

**Carried forward (locked, not re-asked):** config/credential split + gitignored `.store/` (PROJECT.md ✓); no hard-coded RID baseline (PROJECT.md ✓); one non-exported gate `Invoke-AdmanMutation` + `SupportsShouldProcess`/`ConfirmImpact='High'` + Pester/lint guard (SAFE-08); delete = disable+quarantine, no hard-delete verb (SAFE-09); preview ≡ execute (SAFE-10); fail-closed audit / deny-list / managed-OU scoping as *principles* (SAFE-03/04/05/07); module scaffold + Pester 6 + PSScriptAnalyzer 1.25.0 (ROADMAP 00-01 / CLAUDE.md).

**Conflict flagged & resolved:** CLAUDE.md (hand-rolled JSON-lines; defer PSFramework) vs ROADMAP 00-01 ("PSFramework config+logging backbone") → resolved as a hybrid (Area 1).

---

## Area 1 — Logging & config backbone

| Option | Description | Selected |
|--------|-------------|----------|
| Opt 2 | PSFramework (1.14.457, pinned) for validated config + diagnostic logging; audit writer stays synchronous/hand-rolled | ✓ |
| Opt 1 | Fully hand-rolled config + synchronous audit (RSAT the only prereq) | |
| Opt 4 | Hand-rolled behind thin Adman.Config/Adman.Log facades; PSFramework swapped in v2 | |
| Opt 3 | Full PSFramework incl. audit-via-providers (async → weakens fail-closed) | |

**User's choice:** Opt 2 — PSFramework + synchronous audit.
**Notes:** Reconciles both source docs. Deciding fact: PSFramework durable logging is async (background runspace) → cannot enforce "refuse if can't log." Action: amend ROADMAP 00-01 wording and CLAUDE.md "Alternatives Considered." Caveats: pin version; pin config path to `.store\config.json` (no magic default-location import); `ConvertTo-Json -Depth` explicit; `ConvertFrom-Json` has no `-AsHashtable` on 5.1.

---

## Area 2A — Protected-account detection (SAFE-06)

| Option | Description | Selected |
|--------|-------------|----------|
| A1 | Runtime-SID + one IN_CHAIN query over (7 protected groups ∪ `adman-Protected`); gMSA by objectClass; flat deny-list floor | ✓ |
| A2 | `tokenGroups` (ADSI `RefreshCache`) full SID expansion | |
| A3 | `Get-ADGroupMember -Recursive` over 7 groups (cached) + `svc_` naming heuristic | |
| A4 | Naming heuristic + protected Service-Accounts OU + deny-list; no recursion | |

**User's choice:** A1 — IN_CHAIN + `adman-Protected`.
**Notes:** Service-account protection = membership in `adman-Protected` (explicit, recursive, AD-audited). `svc_` heuristic = warning-only. gMSA objectClass pre-filter (msDS-GroupManagedServiceAccount + legacy msDS-ManagedServiceAccount). `adminCount` rejected (stale: never cleared on removal; ≤60 min stamp lag on add). Protected set resolved at runtime (never hard-code domain SID).

## Area 2B — Fail-closed audit write-order (SAFE-03/04)

| Option | Description | Selected |
|--------|-------------|----------|
| B1 | Write-ahead reservation: mutex → PENDING → Flush(true) → throw before AD on failure → mutate → OUTCOME best-effort | ✓ |
| B2 | Single transaction-log record rewritten in place with outcome | |
| B3 | Write-after, "refuse on failure" (NOT fail-closed; reads/dry-runs only) | |
| B4 | Event Log / SIEM as primary store (hard dependency; secondary only) | |

**User's choice:** B1 — write-ahead reservation.
**Notes:** Local `.store/audit/audit-YYYYMMDD.jsonl` JSON-lines; named `Global\adman-audit` mutex; correlationId PENDING↔OUTCOME pairing + startup orphan sweep; OUTCOME-write failure → escalate (Event Log + UI + session flag), never fake AD rollback; refusal gated on pre-write only. Schema fixed, no secrets.

---

## Area 3A — First-run configuration (CONF-01/02/03)

| Option | Description | Selected |
|--------|-------------|----------|
| (c) | Annotated `config.example.json` + optional `init`/wizard emitting the SAME JSON + `doctor`/`validate`; one shared schema | ✓ |
| (a) | Wizard only (prompts → writes JSON) | |
| (b) | Example file only; refuse to run until copied/edited | |

**User's choice:** (c) Both — example file + wizard.
**Notes:** Wizard is a pure emitter of flat portable JSON; strict JSON (no JSONC/JSON5) — "comments" via sibling annotated file or `_comment` keys the loader strips. Wizard runs in setup mode (no AD mutation); fail-closed gate applies only to AD-mutating ops. DN syntax at input; OU existence best-effort at setup, authoritative at startup.

## Area 3B — Starter deny-list seed (SAFE-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal | krbtgt (502), Guest (501), built-in Administrator (500) — matched by objectSid/RID | ✓ |
| Empty | Team fills it (zero SAFE-05 protection on day one) | |
| Expanded | Core + DA/EA/Schema/Protected Users + adminCount guard (Tier-0) | |

**User's choice:** Minimal SID-based core seed.
**Notes:** Written into the JSON file (visible/editable), labeled "starter, not exhaustive." Match by SID/RID never `sAMAccountName` (RID-500 rename). Portable tokens (RID suffix vs DomainSID; S-1-5-32-* literals). Expanded Tier-0 = deferred second layer.

---

## Area 4A — Credential "remember me" storage (CONF-04/06)

| Option | Description | Selected |
|--------|-------------|----------|
| A1+A2 | `Export-Clixml` CurrentUser + `credentialPolicy.allowRememberMe` flag + checkbox on first capture | ✓ |
| A1 minimal | `Export-Clixml` CurrentUser, no policy flag | |
| A3 | Raw `ProtectedData` LocalMachine (shared jump host; any local process can unwrap) | |
| A4 | `ConvertFrom-SecureString -Key` keyed AES file (cross-machine; reintroduces vault) | |

**User's choice:** A1+A2 — `Export-Clixml` CurrentUser + policy flag.
**Notes:** DPAPI behavior consistent across 5.1/7.6 on Windows. Bad restore → delete file + `Get-Credential` (this IS the re-prompt). Never proceed with empty credential. Do NOT use `Export-Clixml -EncryptionKey` (PS7-only). A4 rejected (reintroduces secret vault). LocalMachine (A3) documented opt-in for ACL-locked jump host only.

## Area 4B — Confirmation scaled to blast radius (SAFE-02)

| Option | Description | Selected |
|--------|-------------|----------|
| B1 | Type the exact count; threshold configurable (default 5); below threshold ShouldProcess y/n naming the count | ✓ |
| B2 | Fixed token "CONFIRM" (terraform-style); threshold 5 | |
| B3 | Type the set identity (GitHub repo-name style) | |
| B4 | Bulk starts at `>1` (typed confirm for anything beyond a single object) | |

**User's choice:** B1 — type the exact count, threshold 5.
**Notes:** `safety.bulkConfirmThreshold` in non-secret config. Run gate ONCE, inner cmdlets `-Confirm:$false`. Automation bypass = `-Force` + `-Confirm:$false` (ShouldContinue is unsuppressible). Non-bypassable: deny-list, protected-account block, managed-OU scope, Phase-4 CAP. Log confirmation (who/verb/count/token-type), never credential.

---

## Claude's Discretion

- Concrete managed-OU roots, domain name, paths, transport order/timeouts, and the exact bulk CAP value are runtime config (first-run wizard / `config.example.json`), not hard-coded — schema is Phase 0, values are environment-specific.
- Internal `Public/`/`Private/` names and exact manifest fields within the ROADMAP 00-01 scaffold.
- Adding Protected Users (525) / Key Admins (526-527) to the default protected set (recommended where present).

## Deferred Ideas

- Expanded Tier-0/AdminSDHolder deny-list seed — second layer once group/lifecycle ops near Tier-0 exist (Phase 2+).
- `tokenGroups` effective-membership report (A2) — only if a read-only effective-access report is later wanted (Phase 1/5).
- LocalMachine DPAPI scope (A3) — documented opt-in for ACL-locked jump host; not default.
- Event Log/SIEM forwarding as primary audit (B4) — keep local for fail-closed; forwarding/rotation/tamper-evidence = Phase 5 (ROADMAP 05-03).
- Keyed-AES portable credential file (A4) — rejected for v1; revisit only if credential roaming becomes an explicit v2 requirement.
- Write-after "refuse on failure" audit (B3) — never for destructive actions; reads/dry-runs only.
- Bulk-starts-at-`>1` confirmation (B4) — rejected as global default; per-OU override only.
- RSAT server feature-name vs target-SKU nuance — confirm in Phase 0/5 research (STATE.md HIGH flag).
