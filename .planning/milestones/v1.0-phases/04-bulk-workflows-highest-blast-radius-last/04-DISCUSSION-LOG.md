# Phase 4: Bulk & Workflows (highest blast radius, last) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-17
**Phase:** 04-Bulk & Workflows (highest blast radius, last)
**Areas discussed:** Bulk input source & action scope, Onboarding template design, Offboarding quarantine & restore, CSV schema & resume/idempotency

---

## Bulk input source & action scope

| Option | Description | Selected |
|--------|-------------|----------|
| Search-based only | Operators build the target set interactively from search/report results and run a bulk verb. | |
| CSV only | Operators prepare a CSV and ingest it through the gated bulk path. | |
| Both (recommended) | Both paths share the same bulk engine: search results can be piped/converted to a bulk input shape, and CSV ingestion produces the same shape before validation and cap checks. | ✓ |

**User's choice:** Both (recommended)
**Notes:** Normalized to the same bulk input shape.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Stale report only | The stale/inactive report is the most common bulk target. | |
| Stale + account-state reports | Account-state report and stale report both feed bulk. | |
| Any Find/report output (recommended) | Any user/computer search output can become a bulk target via a generic bulk verb. | ✓ |

**User's choice:** Any Find/report output (recommended)
**Notes:** Pipeline + menu support.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Disable/Enable/Move only | Low blast radius, easy to make idempotent. | |
| Disable/Enable/Move + Group membership (recommended) | Add the group-membership add/remove verbs. | ✓ |
| Include password reset | Riskier because it forces password changes at scale. | |

**User's choice:** Disable/Enable/Move + Group membership (recommended)
**Notes:** No bulk password reset.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Generic bulk engine (recommended) | One Public verb `Invoke-AdmanBulkAction -Action <verb> -InputObject <targets>`. | ✓ |
| Per-action bulk verbs | Separate Public verbs for each bulk action. | |

**User's choice:** Generic bulk engine (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Menu only | Bulk is menu-only; search results must be saved/exported and re-imported through CSV. | |
| Pipeline + menu (recommended) | Bulk accepts pipeline input from Find/report verbs and the menu offers a bulk entry point. | ✓ |

**User's choice:** Pipeline + menu (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Per-row destination | CSV or pipeline carries a TargetPath column per row. | |
| Single destination (recommended) | All objects in the bulk job move to the same destination OU supplied by `-TargetPath`. | ✓ |

**User's choice:** Single destination (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Users only | Bulk targets AD users only. | |
| Users + computers (recommended) | Bulk targets AD users and AD computers where the equivalent single-object verb exists. | ✓ |

**User's choice:** Users + computers (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Before filtering | Cap counts raw input rows before deny/protected/scope filtering. | |
| After filtering (recommended) | Cap counts only objects that pass gate filtering and will actually be touched. | ✓ |

**User's choice:** After filtering (recommended)

---

## Onboarding template design

| Option | Description | Selected |
|--------|-------------|----------|
| Config key (recommended) | Template lives as a non-secret JSON object inside the main config. | ✓ |
| Separate JSON file | A separate `config/onboarding-template.json` file loaded alongside the main config. | |
| Inline module defaults | Hard-coded defaults in the module. | |

**User's choice:** Config key (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| OU + groups only | Minimal template. | |
| OU + groups + naming pattern (recommended) | Adds a configurable name-derivation pattern string. | ✓ |
| Full attribute template | Adds department, title, manager, office, etc. | |

**User's choice:** OU + groups + naming pattern (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Name + template choice | Menu prompts for First/Last, then a numeric template choice. | |
| Name only, default template (recommended) | Menu prompts only for First/Last; default template auto-applied. | ✓ |

**User's choice:** Name only, default template (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| One pattern for sAMAccountName (recommended) | Single pattern string with placeholders produces sAMAccountName; UPN is `sAMAccountName@domain`. | ✓ |
| Separate sAM/UPN patterns | Separate pattern strings for sAMAccountName and UserPrincipalName. | |

**User's choice:** One pattern for sAMAccountName (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Fail at create | Workflow attempts `New-ADUser` and fails if the derived sAMAccountName collides. | |
| Pre-flight before confirm (recommended) | Run the same sAMAccountName/CN uniqueness pre-flight as `New-AdmanUser` before confirmation. | ✓ |

**User's choice:** Pre-flight before confirm (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Continue past group failures | Create the user, then skip failed group adds. | |
| Stop at first failure (recommended) | Per FLOW-04, a mid-workflow failure stops later steps for that target and logs FAIL. | ✓ |

**User's choice:** Stop at first failure (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Display-once hygiene (recommended) | Onboarding shows the generated password once with Read-Host + `[Console]::Clear()` hygiene. | ✓ |
| Return to caller | Onboarding returns the password as a SecureString to the caller. | |

**User's choice:** Display-once hygiene (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Template OU only (recommended) | The workflow always uses the template's target OU. | ✓ |
| Allow runtime override | Menu prompts for an explicit parent OU after name entry. | |

**User's choice:** Template OU only (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Start-AdmanUserOnboarding (recommended) | One Public verb `Start-AdmanUserOnboarding -FirstName -LastName` runs the entire workflow. | ✓ |
| Menu-only composition | A menu-only composition that calls `New-AdmanUser` + `Add-AdmanGroupMember` inline. | |

**User's choice:** Start-AdmanUserOnboarding (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Validate all groups upfront (recommended) | Validate each baseline group through `Test-AdmanGroupAllowed` before the workflow starts. | ✓ |
| Fail during workflow | Attempt group adds one by one and stop at the first refusal. | |

**User's choice:** Validate all groups upfront (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Enabled (recommended) | Create the account enabled; generated password is single-use via must-change. | ✓ |
| Disabled then enabled | Create disabled, then enable as a separate workflow step. | |

**User's choice:** Enabled (recommended)

---

## Offboarding quarantine & restore

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-created under each managed root | Fixed child OU auto-created under each managed root. | |
| Config key - single DN (recommended) | Single explicit DN in config (`templates.offboarding.quarantineOU`). | ✓ |

**User's choice:** Config key - single DN (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Audit record only (recommended) | Record original OU and non-protected groups in the audit record as structured fields. | ✓ |
| Separate state file | Write a separate JSON state file in `.store/` per offboarded user. | |

**User's choice:** Audit record only (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| All non-protected groups (recommended) | Remove membership from every group that is not protected. | ✓ |
| Only managed-scope groups | Only strip groups that live under a managed OU. | |

**User's choice:** All non-protected groups (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Single restore verb (recommended) | One Public verb `Restore-AdmanQuarantinedUser -Identity` reads the latest offboarding audit record and reverses steps. | ✓ |
| Manual checklist | Restore is a manual checklist using existing verbs. | |

**User's choice:** Single restore verb (recommended)

---

## CSV schema & resume/idempotency

| Option | Description | Selected |
|--------|-------------|----------|
| Verb-specific parameters | Identity + Action + Parameter1 + Parameter2. | |
| Fixed schema (recommended) | Fixed schema: `ObjectType`, `Identity`, `Action`, plus optional `TargetPath` and `GroupIdentity`. | ✓ |
| Identity only | Only `Identity` column; action/parameters supplied via parameters at runtime. | |

**User's choice:** Fixed schema (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| User-friendly (recommended) | CSV uses user-friendly values like `Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`. | ✓ |
| Internal verb names | CSV uses exact internal gate verb names. | |

**User's choice:** User-friendly (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Reject unknown columns (recommended) | Reject rows with unknown or misspelled columns. | ✓ |
| Ignore unknown columns | Ignore unknown columns and process only recognized ones. | |

**User's choice:** Reject unknown columns (recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| No persisted state + cheap idempotency (recommended) | No persisted job state; bulk returns per-item results; idempotent skips where cheap. | ✓ |
| Persisted progress file | Write a JSON progress file to `.store/` for resume. | |

**User's choice:** No persisted state + cheap idempotency (recommended)

---

## Claude's Discretion

- Exact fixed CSV column order and user-friendly action value strings.
- Bulk result object shape (summary + per-item array).
- Audit record extension mechanism for offboarding `OriginalOU`/`Groups` fields.
- Offboarding post-action cleanup checklist presentation (text/help output only).
- Quarantine OU scope validation wiring.
- No-op result reporting detail level.

## Deferred Ideas

- Full persisted/resume-safe bulk job state (`BULK-V01`) — v2.
- HR-CSV-driven provisioning (`FLOW-V02`) — v2.
- Multiple onboarding templates per role (`FLOW-V01`) — v2.
- Bulk password reset — not required in v1.
- Auto-compensation for offboarding partial failures — v2.
- Remote live actions (`RMT-V01`) — v2.
- Read-side audit for reports/bulk previews — revisit if compliance asks.
