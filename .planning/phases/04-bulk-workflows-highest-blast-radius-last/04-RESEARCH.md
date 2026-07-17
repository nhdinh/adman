# Phase 04: Bulk & Workflows (highest blast radius, last) - Research

**Researched:** 2026-07-17
**Domain:** PowerShell bulk/workflow composition on top of the adman safety spine
**Confidence:** HIGH (architecture and patterns are dictated by locked Phase 0-3 decisions and verified codebase), MEDIUM (some AD cmdlet idempotency details and offboarding restore semantics)

## Summary

Phase 4 is the capstone of the v1 safety spine: it turns the proven single-object write verbs from Phase 2 into **gated bulk actions** and **reversible onboarding/offboarding workflows**. The core research finding is that no new external dependencies or AD primitives are needed. The implementation risk is almost entirely in composition logic — input normalization, cap/confirmation ordering, per-item error handling, and offboarding restore-state storage — not in new directory operations.

The bulk engine (`Invoke-AdmanBulkAction`) is a generic wrapper around the existing `Invoke-AdmanMutation` gate. It accepts target sets from pipeline (search/report output) or from a strict-schema CSV, resolves each target once, runs the same deny/scope/protected filtering as single-object verbs, applies the configurable `bulk.maxCount` cap, performs one typed-count confirmation for the *filtered* set, then loops through items with try/catch/continue. Each item is still audited individually through the gate, preserving SAFE-03/04/08/10.

Onboarding is a single-template workflow (`Start-AdmanUserOnboarding`) that builds a user creation request from a config-driven template, calls `New-AdmanUser`, then calls `Add-AdmanGroupMember` for each baseline group. Offboarding (`Start-AdmanUserOffboarding`) disables the account, snapshots non-protected group membership, removes those memberships, moves the account to a configured quarantine OU, and records the original OU/groups in the audit log for restore. Restore (`Restore-AdmanQuarantinedUser`) reads the latest offboarding audit record and reverses those steps. Because the audit log is already synchronous, fail-closed, and authoritative, it is the correct place for restore state; a separate state file would duplicate the source of truth.

**Primary recommendation:** Implement Phase 4 by composing existing Phase 0-2 verbs through `Invoke-AdmanMutation`. Do not add new AD write wrappers, do not add a separate offboarding state file, and do not allow bulk password reset or hard-delete actions in v1. Add only one generic bulk engine, three workflow verbs, CSV/schema helpers, and menu entries.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Phase 4 supports both search-based and CSV bulk input, normalized to one bulk input shape.
- **D-02:** Search-based bulk accepts any `Find-AdmanUser`/`Find-AdmanComputer`/report output; pipeline input is supported.
- **D-03:** Bulkable actions in v1 are `Disable`, `Enable`, `Move`, and AD group-membership `Add`/`Remove`. Bulk password reset is out of v1 scope.
- **D-04:** Public bulk surface is `Invoke-AdmanBulkAction -Action <verb> -InputObject <targets>` (plus `-Path` for CSV ingestion). Not per-action bulk verbs.
- **D-05:** Bulk Move uses a single `-TargetPath` for the entire job, not per-row destinations.
- **D-06:** Bulk supports AD users and AD computers where an equivalent single-object verb exists.
- **D-07:** The max-count cap applies after gate filtering.
- **D-08:** The v1 onboarding template is stored as a non-secret config key (`templates.onboarding`).
- **D-09:** Template fields: target OU (`ParentOuDn`), baseline AD group list (`BaselineGroups`), and a name-derivation pattern string.
- **D-10:** Menu flow prompts for First Name and Last Name only; the default template is applied automatically.
- **D-11:** Naming pattern produces `sAMAccountName`; UPN is built as `sAMAccountName@domain`.
- **D-12:** sAMAccountName/CN uniqueness pre-flight runs before confirmation, reusing `New-AdmanUser` logic.
- **D-13:** Mid-workflow failure stops later steps for that target and logs FAIL (FLOW-04).
- **D-14:** Generated password is surfaced with the same display-once hygiene as `New-AdmanUser`.
- **D-15:** The operator cannot override the template OU at runtime in v1.
- **D-16:** Public surface: `Start-AdmanUserOnboarding -FirstName -LastName`.
- **D-17:** All baseline groups are validated through `Test-AdmanGroupAllowed` before the workflow starts.
- **D-18:** Onboarding creates the user enabled; the generated password is single-use because `mustChangeAtNextLogon` is on by default.
- **D-19:** The quarantine OU is a single DN stored in config (`templates.offboarding.quarantineOU`).
- **D-20:** Original OU and stripped non-protected groups are recorded in the audit record as structured fields (`OriginalOU`, `Groups`). No separate state file.
- **D-21:** Offboarding strips membership from all non-protected groups; protected-group membership is left intact and recorded.
- **D-22:** Restore is `Restore-AdmanQuarantinedUser -Identity`; it reads the latest offboarding audit record and reverses the steps.
- **D-23:** CSV uses a fixed schema: `ObjectType`, `Identity`, `Action`, plus optional `TargetPath` (Move) and `GroupIdentity` (group ops). Unknown columns are rejected.
- **D-24:** CSV `Action` values are user-friendly: `Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`.
- **D-25:** CSV schema validation is strict; unknown/misspelled columns cause the import to fail before any gate invocation.
- **D-26:** v1 bulk has no persisted job state; it returns a per-item result array and is idempotent/resume-safe where cheap.

### Claude's Discretion

- Exact fixed CSV column order and exact user-friendly action value strings — planner picks the canonical names and documents them.
- Bulk result object shape: return a summary object with total/succeeded/failed/denied counts plus a `PerItem` array naming each target and result.
- Audit record extensions for offboarding: add `OriginalOU` and `Groups` fields to `Write-AdmanAudit` schema or use the existing `Details`/`Reason` extension pattern, choosing the least-invasive approach that preserves the no-secret-key invariant.
- Offboarding post-action cleanup checklist (mailbox/home-dir/GPO) is surfaced as plain text/help output only, not automated.
- Quarantine OU scope validation: the configured quarantine OU must pass the managed-OU scope check.
- No-op result reporting: already-correct state can be reported as `Success` with a `Note` like "already disabled" rather than introducing a new result enum.

### Deferred Ideas (OUT OF SCOPE)

- Full persisted/resume-safe bulk job state (`BULK-V01`) — v2.
- HR-CSV-driven provisioning with multi-column templates (`FLOW-V02`) — v2.
- Multiple onboarding templates per role (`FLOW-V01`) — v2.
- Bulk password reset — not required in v1.
- Auto-compensation for offboarding partial failures — v2.
- Remote live actions (`RMT-V01`) — v2.
- Read-side audit for reports/bulk previews — not required by SAFE-03.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLOW-01 | Onboarding workflow guides new-user setup through one gated, audited flow | Use `New-AdmanUser` + `Add-AdmanGroupMember` per baseline group; template stored in config; display-once password hygiene reused. |
| FLOW-02 | Offboarding disables user, strips non-protected groups, moves to quarantine OU, surfaces cleanup checklist only | Use `Disable-AdmanUser`, `Remove-AdmanGroupMember`, `Move-AdmanUser`; record original OU/groups in audit; checklist rendered as text. |
| FLOW-03 | Offboarding is reversible — restore quarantined user with recorded groups/original location | Read latest offboarding audit record; call `Enable-AdmanUser`, `Add-AdmanGroupMember`, `Move-AdmanUser`. |
| FLOW-04 | Workflows compose existing single-object verbs through the same gate; mid-workflow failure stops later steps and logs FAIL | Wrap each workflow step in try/catch; on failure write Failure audit and do not continue steps for that target. |
| BULK-01 | Admin can run gated bulk action: build target set from search → preview → max-count cap → typed count confirmation → per-item execution | Generic `Invoke-AdmanBulkAction` normalizes input, applies cap after filtering, confirms once, loops per item through `Invoke-AdmanMutation`. |
| BULK-02 | Bulk enforces configurable max-count cap and typed confirmation of the count before executing | `Assert-AdmanBulkPolicy -EnforceCap`; `Confirm-AdmanAction` already supports typed-count confirmation. |
| BULK-03 | Bulk continues on single-item failure, captures per-item results, and is idempotent/resume-safe where cheap | Per-item try/catch/continue with result collection; detect already-correct state to skip no-ops. |
| BULK-04 | No raw `Import-Csv \| Set-ADUser` path — CSV flows only through gated bulk with schema validation + preview + cap | Strict schema validation wrapper around `Import-Csv`; all rows routed through `Invoke-AdmanBulkAction`. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

The following directives from `.claude/CLAUDE.md` constrain this phase and must not be contradicted:

- **PowerShell version target:** Windows PowerShell 5.1 is the required baseline; PowerShell 7.6.3 LTS is the supported modern runtime. Do not optimize for 7.4/7.5. [CITED: .claude/CLAUDE.md]
- **ActiveDirectory module (RSAT):** prerequisite, never bundled. [CITED: .claude/CLAUDE.md]
- **No hard-delete:** adman ships no hard-delete verb; bulk and workflow allow-lists must exclude `Remove-ADObject`. [CITED: .claude/CLAUDE.md]
- **`-WhatIf` on every destructive action:** state-changing functions must declare `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` and call `$PSCmdlet.ShouldProcess(...)`. [CITED: .claude/CLAUDE.md]
- **Hand-rolled TUI primary:** menu is the product; no browser frontend. [CITED: .claude/CLAUDE.md]
- **No `Get-WmiObject` / `wmic.exe`:** use CIM cmdlets. Not directly relevant to bulk/workflows, but the phase must not introduce them. [CITED: .claude/CLAUDE.md]
- **No cmdlet aliases / positional parameters in module code:** full names and named parameters. [CITED: .claude/CLAUDE.md]
- **Config/credential split:** non-secret config is plain JSON in `.store/`; secrets are in a separate DPAPI-encrypted file. New template and quarantine OU keys are non-secret. [CITED: .claude/CLAUDE.md]
- **Audit is fail-closed and synchronous:** `Write-AdmanAudit` is the only audit sink; offboarding restore state lives in it, not in a separate async store. [CITED: .claude/CLAUDE.md]
- **No stored privileged creds in v1:** pass-through by default; prompt only when rights are insufficient. [CITED: .claude/CLAUDE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Bulk input normalization (search output + CSV) | API / Backend (module functions) | — | Parsing and schema validation are business logic; no UI code in the normalizer. |
| Bulk cap, confirmation, and per-item dispatch | API / Backend | TUI (menu entry) | The engine owns the safety-critical path; the menu only collects `-Path` or pipes search results. |
| Onboarding workflow | API / Backend | TUI (menu prompt for names) | The workflow composes existing write verbs; the menu only prompts for FirstName/LastName. |
| Offboarding workflow | API / Backend | TUI (confirmation prompt) | Reuses disable/remove/move verbs; the menu initiates the single Public verb. |
| Restore quarantined user | API / Backend | Audit log (storage) | Restore state is read from the authoritative audit log; restore logic is backend. |
| CSV file I/O | API / Backend | — | `Import-Csv` is used inside the bulk normalizer; no client-side parsing. |
| Menu entries for bulk/workflows | TUI / Client | API / Backend | `Get-AdmanMenuDefinition` adds entries that dispatch to the same Public verbs a senior calls directly (MENU-04). |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Windows PowerShell / PowerShell 7.6 LTS | 5.1 / 7.6.3 | Runtime | Required baseline per CLAUDE.md; all verbs target the 5.1-compatible subset. [CITED: .claude/CLAUDE.md] |
| `Microsoft.PowerShell.Utility` (built-in) | ships with PS | `Import-Csv`, `ConvertFrom-Json`, `ConvertTo-Json` | CSV ingestion and audit log parsing require no extra modules. [CITED: Microsoft Learn Import-Csv] |
| `ActiveDirectory` module (RSAT) | ships with RSAT | Target resolution and writes | Already a prerequisite; bulk/workflows add no new AD cmdlets. [CITED: .claude/CLAUDE.md] |
| `PSFramework` | 1.14.457 (existing) | Config/diagnostic logging only | Already used for non-audit logging; audit stays hand-rolled. [VERIFIED: codebase] |
| `Invoke-AdmanMutation` gate | existing (Phase 0) | Single funnel for all writes | All bulk/workflow writes must route through it to preserve SAFE-08/09. [VERIFIED: codebase] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Confirm-AdmanAction` | existing (Phase 0) | Scaled confirmation (typed count) | Reused by the bulk engine for the filtered target set. [VERIFIED: codebase] |
| `Assert-AdmanBulkPolicy` | existing (Phase 0) | Cap read/enforcement | Called with `-EnforceCap` for the first time in this phase. [VERIFIED: codebase] |
| `Test-AdmanTargetAllowed` / `Test-AdmanGroupAllowed` | existing (Phase 0/2) | Scope, deny, protected checks | Reused unchanged for each resolved target/group. [VERIFIED: codebase] |
| `Write-AdmanAudit` | existing (Phase 0) | Authoritative audit sink | Extended (optional `OriginalOU`/`Groups`) for offboarding restore state. [VERIFIED: codebase] |
| `Resolve-AdmanTarget` / `Resolve-AdmanGroup` | existing (Phase 1/2) | Target resolution | Bulk engine resolves each input identity once (SAFE-10). [VERIFIED: codebase] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Generic `Invoke-AdmanBulkAction` engine | Per-action bulk verbs (`Disable-AdmanUserBulk`, etc.) | More discoverable, but duplicates cap/confirm/audit logic and violates DRY; the locked decision is the generic engine. |
| Built-in `Import-Csv` | `ConvertFrom-Csv` with manual parsing | `Import-Csv` is the idiomatic file reader; strict validation is done by comparing headers, not by reimplementing the parser. |
| Audit log for offboarding restore state | Separate JSON state file | Duplicates the source of truth and breaks fail-closed; audit log is already synchronous and authoritative. |
| `Start-AdmanUserOnboarding` calling AD cmdlets directly | Calling `New-AdmanUser` + `Add-AdmanGroupMember` | Direct AD calls would bypass the gate and the audit writer; reusing Public verbs preserves safety. |

**Installation:**

```powershell
# No new packages are installed in Phase 4.
# Existing prerequisites (documented, not bundled):
#   - ActiveDirectory module (RSAT)
#   - PSFramework 1.14.457 (already in adman.psd1 RequiredModules)
```

**Version verification:** Not applicable — no new packages.

## Package Legitimacy Audit

Phase 4 does not introduce any new external packages. All functionality is built from the existing approved stack (`ActiveDirectory` RSAT module, built-in PowerShell cmdlets, and the module's own private safety spine). No registry lookups or legitimacy checks are required.

## Architecture Patterns

### System Architecture Diagram

```text
                         +------------------+
                         |   Operator TUI   |
                         | (Start-Adman)    |
                         +--------+---------+
                                  |
          +-----------------------+-----------------------+
          |                                               |
+---------v---------+                          +----------v----------+
| Bulk menu entry   |                          | Workflow menu       |
| (CSV path prompt) |                          | entries (names)     |
+---------+---------+                          +----------+----------+
          |                                               |
          v                                               v
+------------------+                           +----------------------+
| Invoke-AdmanBulk |                           | Start-AdmanUser      |
| -Action          |                           | Onboarding /         |
|                  |                           | Offboarding / Restore|
+--------+---------+                           +----------+-----------+
         |                                                |
         |   +----------------+   +----------------+      |
         +-->| CSV normalizer |   | Search object  |<-----+
             | (strict schema)|   | (D-03 schema)  |
             +--------+-------+   +--------+-------+
                      |                    |
                      +---------+----------+
                                |
                                v
                   +------------------------+
                   |  Bulk input record     |
                   |  {ObjectType, Identity,|
                   |   Action, TargetPath,  |
                   |   GroupIdentity}       |
                   +-----------+------------+
                               |
                               v
                   +------------------------+
                   | Resolve + gate filter  |
                   | (deny/protected/scope) |
                   +-----------+------------+
                               |
                               v
                   +------------------------+
                   | Assert-AdmanBulkPolicy |
                   | -EnforceCap            |
                   +-----------+------------+
                               |
                               v
                   +------------------------+
                   | Confirm-AdmanAction    |
                   | (typed count)          |
                   +-----------+------------+
                               |
                               v
                   +------------------------+
                   | Per-item loop:         |
                   | try { Invoke-AdmanMutation }
                   | catch { record; continue }
                   +-----------+------------+
                               |
                               v
                   +------------------------+
                   | Bulk result summary    |
                   | + per-item array       |
                   +------------------------+
```

### Recommended Project Structure

```
Public/
  Invoke-AdmanBulkAction.ps1           # generic bulk engine
  Start-AdmanUserOnboarding.ps1        # onboarding workflow
  Start-AdmanUserOffboarding.ps1       # offboarding workflow
  Restore-AdmanQuarantinedUser.ps1     # restore workflow
Private/
  Bulk/
    Import-AdmanBulkCsv.ps1            # strict-schema CSV normalizer
    ConvertTo-AdmanBulkInput.ps1       # search output -> bulk record
  Workflow/
    Get-AdmanOffboardingState.ps1      # read latest offboarding audit record
  Safety/
    (existing gate/resolver/policy functions; no new files)
  Audit/
    Write-AdmanAudit.ps1               # extend for OriginalOU/Groups
  Menu/
    Get-AdmanMenuDefinition.ps1        # add bulk/workflow entries
config/
  adman.schema.json                    # add templates.onboarding / templates.offboarding.quarantineOU
  adman.defaults.json                  # add defaults for new keys
```

### Pattern 1: Bulk Input Normalization

**What:** Both pipeline objects and CSV rows are converted to a single internal record shape before any filtering or cap logic runs.

**When to use:** For every bulk path so that cap, confirmation, and dispatch have one code path.

**Example:**

```powershell
# Source: adman codebase pattern + Phase 4 context D-01/D-23
$bulkRecord = [pscustomobject]@{
    ObjectType   = 'User'            # User | Computer
    Identity     = 'jdoe'            # sAMAccountName or DN
    Action       = 'Disable'         # Disable | Enable | Move | AddGroup | RemoveGroup
    TargetPath   = $null             # required for Move
    GroupIdentity = $null            # required for AddGroup/RemoveGroup
}
```

### Pattern 2: Cap After Gate Filtering

**What:** Resolve targets and run `Test-AdmanTargetAllowed` first, then apply `bulk.maxCount` to the allowed list.

**When to use:** Always. The operator confirms the count of objects that will actually be touched, not raw input.

**Example:**

```powershell
# Source: adman codebase (Invoke-AdmanMutation.ps1) + Phase 4 context D-07
$allowed = [System.Collections.Generic.List[object]]::new()
foreach ($t in $resolved) {
    $decision = Test-AdmanTargetAllowed -Object $t -Operation $mappedGateVerb
    if ($decision.Allowed) { $allowed.Add($t) }
}
Assert-AdmanBulkPolicy -Count $allowed.Count -EnforceCap | Out-Null
```

### Pattern 3: Per-Item Continue-on-Failure Loop

**What:** After a single confirmation for the filtered set, each item is executed in its own try/catch so one failure does not abort the batch.

**When to use:** All bulk execution.

**Example:**

```powershell
# Source: PowerShell best practice + adman gate pattern
$results = [System.Collections.Generic.List[object]]::new()
foreach ($item in $allowed) {
    try {
        $r = Invoke-AdmanMutation -Verb $mappedGateVerb -Targets @($item.Identity) `
            -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference
        $results.Add([pscustomobject]@{ Identity = $item.Identity; Result = 'Success'; Note = $null })
    } catch {
        $results.Add([pscustomobject]@{ Identity = $item.Identity; Result = 'Failed'; Note = $_.Exception.Message })
        Write-Warning "Bulk item failed: $($item.Identity) - $($_.Exception.Message)"
    }
}
```

### Pattern 4: Onboarding as Sequential Gate Calls

**What:** The onboarding workflow builds the create parameters from the template, calls `New-AdmanUser`, then iterates baseline groups calling `Add-AdmanGroupMember`. Any step failure stops subsequent steps for that target.

**When to use:** Only for the single-user onboarding flow.

**Example:**

```powershell
# Source: Phase 4 context D-08..D-18
function Start-AdmanUserOnboarding {
    param([string]$FirstName, [string]$LastName)
    $template = $script:Config.templates.onboarding
    $sam = ($template.NamePattern -f $FirstName, $LastName).ToLower()
    $upn = "$sam@$($script:Config.Domain)"
    try {
        New-AdmanUser -Name "$FirstName $LastName" -SamAccountName $sam `
            -UserPrincipalName $upn -ParentOuDn $template.ParentOuDn -Force
        foreach ($g in $template.BaselineGroups) {
            Add-AdmanGroupMember -Identity $sam -GroupIdentity $g -Force
        }
    } catch {
        Write-AdmanAudit -Verb 'Start-AdmanUserOnboarding' -Target $sam `
            -Result 'Failure' -Reason $_.Exception.Message
        throw
    }
}
```

### Pattern 5: Offboarding Restore State in Audit Log

**What:** The offboarding workflow records the original OU and the list of stripped non-protected groups directly in the audit record. Restore reads the latest such record.

**When to use:** All offboarding/restores in v1.

**Example:**

```powershell
# Source: Phase 4 context D-20 + Write-AdmanAudit.ps1 extension pattern
Write-AdmanAudit -Verb 'Start-AdmanUserOffboarding' -Target $user `
    -Result 'Success' -OriginalOU $originalOu -Groups ($groupsToRemove -join '|')
```

### Anti-Patterns to Avoid

- **Per-action bulk verbs:** Do not create `Disable-AdmanUserBulk`, `Move-AdmanUserBulk`, etc. The locked public surface is the generic engine. [CITED: 04-CONTEXT.md D-04]
- **Cap on raw input count:** Do not apply `bulk.maxCount` before deny/scope/protected filtering; that would mislead the operator about blast radius. [CITED: 04-CONTEXT.md D-07]
- **Direct AD calls in workflows:** Workflows must call Public verbs that route through `Invoke-AdmanMutation`, not AD cmdlets directly. [CITED: 04-CONTEXT.md FLOW-04]
- **Separate offboarding state file:** Do not invent a sidecar JSON/CSV file for restore state; the audit log is already authoritative and fail-closed. [CITED: 04-CONTEXT.md D-20]
- **Bulk password reset:** Do not add it in v1; it is explicitly out of scope. [CITED: 04-CONTEXT.md D-03]
- **Ignoring no-op states:** For `Move`, `Disable`, and `Enable`, detect already-correct state to avoid unnecessary AD errors and to support resume. [ASSUMED]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV parsing | A custom parser or regex | `Import-Csv` + header schema validation | `Import-Csv` handles quoting, delimiters, and encoding; strict schema is just a header-set comparison. [CITED: Microsoft Learn Import-Csv] |
| AD write operations | New AD cmdlet wrappers or direct `Set-AD*` calls | Existing `Adman.AD.Write.*` wrappers invoked via `Invoke-AdmanMutation` | The gate owns preview, audit, scope, deny, and confirmation (SAFE-08/10). [VERIFIED: codebase] |
| Offboarding restore state | A separate JSON/CSV state file | Extended `Write-AdmanAudit` record | The audit log is synchronous, fail-closed, and already required for every action. [CITED: .claude/CLAUDE.md] |
| Bulk confirmation | A custom prompt | `Confirm-AdmanAction` with typed-count threshold | Already implements `-WhatIf`, `Force`, and typed-count confirmation; reuse preserves SAFE-02. [VERIFIED: codebase] |
| Target resolution | `Get-ADUser`/`Get-ADComputer` scattered in bulk engine | `Resolve-AdmanTarget` / `Resolve-AdmanGroup` | Single resolver used for preview and execute (SAFE-10). [VERIFIED: codebase] |
| Protected/scope checks | Inline filtering in the bulk engine | `Test-AdmanTargetAllowed` / `Test-AdmanGroupAllowed` | Centralized policy prevents drift and ensures refusals are audited consistently. [VERIFIED: codebase] |
| Group membership idempotency | Custom logic to pre-check every member | AD's permissive modify (`Add-ADGroupMember`/`Remove-ADGroupMember` default) | Already silently succeeds for already-present/absent members; pre-check only needed for accurate "no-change" notes. [CITED: Microsoft Learn Add-ADGroupMember / Remove-ADGroupMember] |

**Key insight:** Phase 4 is composition, not invention. The safety properties were proven in Phases 0-2; the bulk/workflow layer's only job is to call them in the right order, cap the blast radius, collect per-item results, and store offboarding restore data in the existing audit sink.

## Runtime State Inventory

This phase is a greenfield addition, not a rename/refactor/migration. No runtime state inventory is required.

## Common Pitfalls

### Pitfall 1: Applying the cap before gate filtering

**What goes wrong:** A CSV with 100 rows where 60 are out-of-scope or protected would pass the cap check as "100", then fail or mislead after filtering. The operator could be asked to confirm 100 objects when only 40 will actually change.

**Why it happens:** The natural place to check a `maxCount` is right after reading the file/pipeline, before paying the cost of resolving each target.

**How to avoid:** Resolve and filter first, then call `Assert-AdmanBulkPolicy -Count $allowed.Count -EnforceCap`. [CITED: 04-CONTEXT.md D-07]

**Warning signs:** Tests that pass a 60-row input with 55 protected objects and expect the cap to block because raw count > 50.

### Pitfall 2: One failing item aborting the entire bulk job

**What goes wrong:** A transient DC error or locked object mid-loop terminates the whole batch, leaving the operator with no result summary.

**Why it happens:** Wrapping the entire loop in one try/catch instead of per-item handling.

**How to avoid:** Place `try { Invoke-AdmanMutation ... } catch { $results.Add(...); Write-Warning; continue }` inside the loop. [CITED: PowerShell per-item error handling best practice]

**Warning signs:** Unit tests where the second mocked item throws and the third item is never invoked.

### Pitfall 3: `Move-ADObject` idempotency

**What goes wrong:** Re-running a bulk Move for an object already in the destination OU throws `The object already exists` or a similar directory error.

**Why it happens:** `Move-ADObject` is not idempotent for an object that is already in the target container. [CITED: Microsoft Learn Move-ADObject]

**How to avoid:** Before calling `Move-ADObject`, compare the object's current parent DN to the target path and skip with a "already in place" note. [ASSUMED]

**Warning signs:** Resume tests that re-run the same CSV fail on the second pass.

### Pitfall 4: Inaccurate "no-change" reporting for group membership

**What goes wrong:** `Add-ADGroupMember` and `Remove-ADGroupMember` use permissive modify by default, so they succeed even when no change occurred, but the result summary reports every row as a successful mutation.

**Why it happens:** The AD cmdlet suppresses the duplicate-member error by default. [CITED: Microsoft Learn Add-ADGroupMember / Remove-ADGroupMember]

**How to avoid:** Inspect the resolved object's `memberOf` before dispatch and report `Success` with a `Note = 'already member'` (or `not a member`) when appropriate. [ASSUMED]

**Warning signs:** Bulk result summary shows 50 changes for a CSV that was already applied.

### Pitfall 5: `-WhatIf` not propagating to nested gate calls

**What goes wrong:** A user runs `Invoke-AdmanBulkAction -WhatIf` and the engine's confirmation path respects it, but individual `Invoke-AdmanMutation` calls execute real AD writes.

**Why it happens:** PowerShell preference variables do not reliably cross script-module boundaries. [CITED: Microsoft Learn ShouldProcess deep dive]

**How to avoid:** Always pass `-WhatIf:$WhatIfPreference` explicitly when calling `Invoke-AdmanMutation` and other state-changing verbs. The existing gate and wrappers already do this; the bulk engine must continue the pattern. [VERIFIED: codebase]

**Warning signs:** `-WhatIf` bulk tests that do not assert zero AD write calls.

### Pitfall 6: CSV header typos slipping through

**What goes wrong:** `Import-Csv` creates properties for every header it sees; a typo like `GropuIdentity` becomes a silent no-op instead of an error.

**Why it happens:** `Import-Csv` has no strict schema mode. [CITED: Microsoft Learn Import-Csv]

**How to avoid:** Compare the file's actual header set (`$rows[0].PSObject.Properties.Name`) against the allowed set before processing and throw if unknown columns exist. [CITED: 04-CONTEXT.md D-25]

**Warning signs:** A CSV with `Actionn` is accepted and no actions are performed.

### Pitfall 7: Offboarding restore state containing secrets

**What goes wrong:** Extending the audit record with new fields accidentally captures passwords, certificates, or DPAPI material.

**Why it happens:** The audit schema is extended for the first time since Phase 0.

**How to avoid:** Only add non-secret fields (`OriginalOU`, `Groups`). Group DNs and OU DNs are directory topology, not credentials. [CITED: .claude/CLAUDE.md]

**Warning signs:** Any new audit field name that resembles `Password`, `Credential`, `Key`, or `Secret`.

### Pitfall 8: Mid-workflow partial state without FAIL audit

**What goes wrong:** A workflow disables a user but fails on group removal; subsequent steps are skipped, but no audit record marks the workflow as failed for that target.

**Why it happens:** The workflow catches the step failure and silently returns.

**How to avoid:** Wrap each step; on catch, write a `Failure` audit record with the step that failed and the target, then stop further steps for that target. [CITED: 04-CONTEXT.md D-13]

**Warning signs:** Workflow tests that expect a Failure audit record after a mocked step throw.

## Code Examples

### Strict CSV schema validation

```powershell
# Source: Microsoft Learn Import-Csv + Phase 4 context D-23/D-25
function Import-AdmanBulkCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $allowed = @('ObjectType','Identity','Action','TargetPath','GroupIdentity')
    $rows = Import-Csv -LiteralPath $Path -ErrorAction Stop
    if ($null -eq $rows -or $rows.Count -eq 0) { return @() }

    $actual = $rows | Select-Object -First 1 | ForEach-Object { $_.PSObject.Properties.Name }
    $unknown = $actual | Where-Object { $_ -notin $allowed }
    if ($unknown) {
        throw "CSV contains unknown columns: $($unknown -join ', ')"
    }

    $rows
}
```

### Bulk input record (search output path)

```powershell
# Source: Phase 4 context D-01/D-03 + adman D-03 schema
function ConvertTo-AdmanBulkInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$InputObject,
        [Parameter(Mandatory)][string]$Action,
        [string]$TargetPath,
        [string]$GroupIdentity
    )
    process {
        $objectType = if ($InputObject.ObjectType) { $InputObject.ObjectType } else { 'User' }
        [pscustomobject]@{
            ObjectType    = $objectType
            Identity      = $InputObject.DistinguishedName
            Action        = $Action
            TargetPath    = $TargetPath
            GroupIdentity = $GroupIdentity
        }
    }
}
```

### Bulk engine loop with result collection

```powershell
# Source: adman gate pattern + PowerShell per-item error handling best practice
$perItem = [System.Collections.Generic.List[object]]::new()
foreach ($item in $allowed) {
    try {
        Invoke-AdmanMutation -Verb $gateVerb -Targets @($item.Identity) `
            -Parameters $stepParams -Force:$Force -WhatIf:$WhatIfPreference | Out-Null
        $perItem.Add([pscustomobject]@{
            Identity = $item.Identity
            Result   = 'Success'
            Note     = $null
        })
    } catch {
        $perItem.Add([pscustomobject]@{
            Identity = $item.Identity
            Result   = 'Failed'
            Note     = $_.Exception.Message
        })
        Write-Warning "Failed to $Action $($item.Identity): $($_.Exception.Message)"
    }
}

[pscustomobject]@{
    Total    = $allowed.Count + $denied.Count
    Succeeded = ($perItem | Where-Object Result -eq 'Success').Count
    Failed   = ($perItem | Where-Object Result -eq 'Failed').Count
    Denied   = $denied.Count
    PerItem  = $perItem.ToArray()
}
```

### Offboarding audit record extension (optional fields)

```powershell
# Source: Write-AdmanAudit.ps1 + Phase 4 context D-20
function Write-AdmanAudit {
    param(
        # ... existing parameters ...
        [string]$OriginalOU,
        [string[]]$Groups
    )
    # ... existing record build ...
    if (-not [string]::IsNullOrEmpty($OriginalOU)) {
        $rec['originalOU'] = $OriginalOU
    }
    if ($null -ne $Groups -and $Groups.Count -gt 0) {
        $rec['groups'] = $Groups
    }
    # ... write ...
}
```

### Reading the latest offboarding record for restore

```powershell
# Source: adman audit log format (JSON-lines)
function Get-AdmanLatestOffboardingRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)

    $file = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
    if (-not (Test-Path -LiteralPath $file)) { return $null }

    Get-Content -LiteralPath $file |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object {
            $_.what -eq 'Start-AdmanUserOffboarding' -and
            $_.result -eq 'Success' -and
            $_.target -like "*$Identity*"
        } |
        Sort-Object tsUtc -Descending |
        Select-Object -First 1
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw `Import-Csv \| Set-ADUser` scripts | Gated `Invoke-AdmanBulkAction` with schema validation, cap, and confirmation | Phase 4 (v1) | Eliminates the classic mass-change foot-gun identified in REQUIREMENTS.md. |
| Separate offboarding state file or manual group snapshots | Offboarding restore state stored in the authoritative audit log | Phase 4 (v1) | Keeps one source of truth and preserves the fail-closed audit property. |
| Per-action bulk cmdlets | Generic bulk engine over existing single-object verbs | Phase 4 (v1) | Reduces duplicated safety logic and makes cap/confirmation behavior uniform. |

**Deprecated/outdated:**
- `Get-WmiObject` / `wmic.exe`: already prohibited by CLAUDE.md; not introduced here.
- Direct AD write calls from Public verbs: already prohibited by SAFE-08; bulk/workflows must continue to route through `Invoke-AdmanMutation`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | AD objects expose an `Enabled` property when requested via `Get-ADObject -Properties Enabled`, and comparing it allows safe no-op detection for Disable/Enable bulk actions. | Common Pitfalls / Idempotency | If `Get-ADObject` does not surface `Enabled`, the engine may throw or always execute. The code can fall back to `Get-ADUser`/`Get-ADComputer` per object type if needed. |
| A2 | `Move-ADObject` throws when asked to move an object to its current parent OU, so comparing the current parent DN to the target path before calling is required for idempotency. | Common Pitfalls | If the cmdlet is actually idempotent, the pre-check adds negligible overhead but remains safe. |
| A3 | The operator will configure `templates.offboarding.quarantineOU` to an OU that is within the managed-OU scope before running offboarding. | Architecture Patterns | Offboarding will fail the scope check if the quarantine OU is misconfigured; this is the desired fail-closed behavior. |
| A4 | Group DNs and OU DNs are non-secret and safe to record in the audit log. | Architecture Patterns / Security | These are directory topology, not credentials; aligns with the existing audit schema and CLAUDE.md. |
| A5 | The `Add-ADGroupMember` and `Remove-ADGroupMember` cmdlets in the target environment use permissive modify by default (as documented for Windows Server 2019+ with current updates). | Common Pitfalls | If permissive modify is disabled, re-running a CSV could throw; the engine's try/catch would report those as Failed, not crash the batch. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed. *(Table is not empty; the assumptions above should be validated during planning/implementation.)*

## Open Questions

1. **Offboarding audit field shape**
   - What we know: CONTEXT leaves the choice to the planner — add `OriginalOU`/`Groups` fields or encode them in `Reason`/`Details`. [CITED: 04-CONTEXT.md]
   - What's unclear: Whether adding top-level fields will break any existing audit-schema tests that assert the exact key set.
   - Recommendation: Extend `Write-AdmanAudit` with optional `-OriginalOU` and `-Groups` parameters (only emitted when supplied), mirroring the existing optional `-Group` field. This preserves the exact-key-set invariant for non-offboarding records.

2. **CSV canonical column order and action strings**
   - What we know: The allowed columns are fixed; the order and exact user-friendly action strings are planner discretion. [CITED: 04-CONTEXT.md]
   - What's unclear: None functionally, but the team may prefer a specific order for documentation.
   - Recommendation: Use `ObjectType,Identity,Action,TargetPath,GroupIdentity` and action values `Disable`, `Enable`, `Move`, `AddGroup`, `RemoveGroup`.

3. **Restore idempotency when target is not in quarantine**
   - What we know: Restore must re-enable, re-add groups, and move back to the original OU. [CITED: 04-CONTEXT.md]
   - What's unclear: Whether restore should refuse if the user is not currently under the configured quarantine OU.
   - Recommendation: Validate that the target's current parent OU matches the configured quarantine OU before restore; if not, warn and ask confirmation (or refuse). This prevents accidental restore of a normally-located account.

4. **Bulk engine support for computer group membership**
   - What we know: Bulk supports AD computers where an equivalent single-object verb exists. [CITED: 04-CONTEXT.md]
   - What's unclear: Whether the menu will expose a "Bulk add computers to group" action or only users.
   - Recommendation: The engine is object-type-agnostic; expose only the actions the menu needs in v1 (likely user-centric), but accept `ObjectType=Computer` from CSV/pipeline.

## Environment Availability

Step 2.6: SKIPPED. Phase 4 introduces no new external tools, services, or CLIs beyond the existing PowerShell runtime and the ActiveDirectory RSAT module, which are already prerequisites documented in CLAUDE.md and verified by earlier phases.

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json`; this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Pester 6.0.0 |
| Config file | none (uses default `Invoke-Pester` behavior) |
| Quick run command | `Invoke-Pester -Path tests/Bulk.*.Tests.ps1,tests/Workflow.*.Tests.ps1 -Tag Unit -Output Detailed` |
| Full suite command | `Invoke-Pester -Output Detailed` (from repo root) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BULK-01 | `Invoke-AdmanBulkAction` accepts pipeline input, resolves, confirms, and dispatches per item | unit | `Invoke-Pester tests/Bulk.Engine.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| BULK-02 | Cap enforced after filtering; typed count confirmation required above cap | unit | `Invoke-Pester tests/Bulk.Engine.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| BULK-03 | Per-item failures continue and are reported in summary | unit | `Invoke-Pester tests/Bulk.Engine.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| BULK-04 | CSV with unknown columns rejected; valid rows route through engine | unit | `Invoke-Pester tests/Bulk.Csv.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| FLOW-01 | Onboarding creates user and adds baseline groups; mid-step failure stops workflow | unit | `Invoke-Pester tests/Workflow.Onboarding.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| FLOW-02 | Offboarding disables, strips non-protected groups, moves to quarantine, records state | unit + integration | `Invoke-Pester tests/Workflow.Offboarding.Tests.ps1` | ❌ Wave 0 |
| FLOW-03 | Restore reads latest offboarding audit and reverses disable/groups/move | unit | `Invoke-Pester tests/Workflow.Restore.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| FLOW-04 | Workflow step failure writes Failure audit and stops later steps for that target | unit | `Invoke-Pester tests/Workflow.*.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| MENU-04 | New menu entries dispatch to the same Public verbs | unit | `Invoke-Pester tests/Menu.BulkWorkflow.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| SAFE-08 | New Public bulk/workflow verbs do not call AD write cmdlets directly | unit | `Invoke-Pester tests/Safety.Gate.Tests.ps1 -Tag Unit` | ✅ exists |

### Sampling Rate

- **Per task commit:** Run the quick command for the files touched by that task.
- **Per wave merge:** Run the full suite (excluding integration tests unless in the lab).
- **Phase gate:** Full suite green, including the new Phase 4 test files, before `/gsd-verify-work`.

### Wave 0 Gaps

- [ ] `tests/Bulk.Engine.Tests.ps1` — covers BULK-01/02/03.
- [ ] `tests/Bulk.Csv.Tests.ps1` — covers BULK-04.
- [ ] `tests/Workflow.Onboarding.Tests.ps1` — covers FLOW-01/FLOW-04.
- [ ] `tests/Workflow.Offboarding.Tests.ps1` — covers FLOW-02/FLOW-04.
- [ ] `tests/Workflow.Restore.Tests.ps1` — covers FLOW-03.
- [ ] `tests/Menu.BulkWorkflow.Tests.ps1` — covers MENU-04 for new entries.
- [ ] `tests/Module.Manifest.Tests.ps1` — update to assert new exports are listed.
- [ ] `config/adman.schema.json` + `config/adman.defaults.json` — add template keys.

## Security Domain

> `security_enforcement` is enabled; `security_asvs_level` is 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Pass-through Windows auth; no change in this phase. |
| V3 Session Management | no | No session concept. |
| V4 Access Control | yes | Managed-OU scope (`Test-AdmanTargetAllowed`), protected-group checks (`Test-AdmanGroupAllowed`), and configurable cap limit blast radius. [VERIFIED: codebase] |
| V5 Input Validation | yes | CSV strict schema validation, action value allow-list, and identity resolution before AD calls. [CITED: 04-CONTEXT.md] |
| V6 Cryptography | no | No new crypto; password generation still uses `New-AdmanRandomPassword`. |
| V7 Error Handling | yes | Per-item try/catch prevents one bad row from corrupting others; failure records aid forensics. [CITED: PowerShell best practice] |
| V8 Data Protection | yes | Audit log extension only stores non-secret topology (OU/group DNs), not credentials. [CITED: .claude/CLAUDE.md] |
| V10 Logging | yes | All actions, including bulk and workflow steps, write to the synchronous JSON-lines audit log. [VERIFIED: codebase] |

### Known Threat Patterns for the Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Bulk action against protected accounts | Elevation of privilege | `Test-AdmanTargetAllowed` recursive protected-membership check runs before bulk confirmation. [VERIFIED: codebase] |
| CSV injection of an unknown action column | Tampering | Strict header allow-list rejects unknown columns before any gate call. [CITED: 04-CONTEXT.md] |
| Bypassing confirmation with a just-under-cap count | Elevation of privilege | Cap applies to *filtered* target list; typed-count confirmation matches actual blast radius. [CITED: 04-CONTEXT.md] |
| Restoring an account that was never offboarded | Repudiation / tampering | Restore reads the latest offboarding Success audit record and should validate current quarantine OU. [ASSUMED] |
| Offboarding cleanup automation (mailbox/home dir) | Denial of service / data loss | Cleanup is surfaced as a checklist only; no automated deletion. [CITED: 04-CONTEXT.md] |
| Audit log tampering to hide offboarding | Repudiation | Audit writer is fail-closed and synchronous; restore reads the same log. [VERIFIED: codebase] |

## Sources

### Primary (HIGH confidence)

- `C:/Users/nhdinh/dev/adman/Private/Safety/Invoke-AdmanMutation.ps1` — gate fixed order, audit/confirm flow, SAFE-08/09/10.
- `C:/Users/nhdinh/dev/adman/Private/Safety/Confirm-AdmanAction.ps1` — scaled confirmation and typed-count logic.
- `C:/Users/nhdinh/dev/adman/Private/Safety/Assert-AdmanBulkPolicy.ps1` — cap placeholder with `-EnforceCap` forward-compat.
- `C:/Users/nhdinh/dev/adman/Private/Safety/Test-AdmanTargetAllowed.ps1` / `Test-AdmanGroupAllowed.ps1` — policy checks reused for bulk.
- `C:/Users/nhdinh/dev/adman/Private/Audit/Write-AdmanAudit.ps1` — audit schema and fail-closed behavior.
- `C:/Users/nhdinh/dev/adman/Public/New-AdmanUser.ps1`, `Disable-AdmanUser.ps1`, `Move-AdmanUser.ps1`, `Add-AdmanGroupMember.ps1` — existing Public verbs to be composed.
- `C:/Users/nhdinh/dev/adman/Private/AD/Adman.AD.Write.ps1` — the only AD write wrappers; no new ones needed.
- `C:/Users/nhdinh/dev/adman/.planning/phases/04-bulk-workflows-highest-blast-radius-last/04-CONTEXT.md` — locked Phase 4 decisions.

### Secondary (MEDIUM confidence)

- [Microsoft Learn — Import-Csv](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv) — no strict schema mode; creates PSCustomObjects from headers.
- [Microsoft Learn — Everything about ShouldProcess](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess) — per-item ShouldProcess, explicit -WhatIf propagation.
- [Microsoft Learn — Add-ADGroupMember](https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember) — permissive modify by default.
- [Microsoft Learn — Remove-ADGroupMember](https://learn.microsoft.com/en-us/powershell/module/activedirectory/remove-adgroupmember) — permissive modify by default.
- [Microsoft Learn — Move-ADObject](https://learn.microsoft.com/en-us/powershell/module/activedirectory/move-adobject) — non-idempotent for already-in-place objects.
- [Microsoft Learn — Disable-ADAccount](https://learn.microsoft.com/en-us/powershell/module/activedirectory/disable-adaccount) — cmdlet reference.
- [Microsoft Learn — Enable-ADAccount](https://learn.microsoft.com/en-us/powershell/module/activedirectory/enable-adaccount) — cmdlet reference.

### Tertiary (LOW confidence)

- Web search summaries for PowerShell per-item error handling and reversible AD offboarding patterns (cross-checked against official docs and codebase; specific environment behavior may vary).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Phase 4 adds no new packages; stack is the existing approved stack.
- Architecture: HIGH — driven by locked CONTEXT decisions and verified existing code.
- Pitfalls: MEDIUM/HIGH — cmdlet idempotency details rely on documented permissive-modify behavior and code assumptions about `Enabled`/parent-DN checks.

**Research date:** 2026-07-17
**Valid until:** 2026-08-17 (stable PowerShell/AD stack)
