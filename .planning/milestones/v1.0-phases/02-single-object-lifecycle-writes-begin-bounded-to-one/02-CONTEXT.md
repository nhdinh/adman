# Phase 2: Single-Object Lifecycle (writes begin) - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 ships the **first real AD writes**: single-object AD user lifecycle (create/disable/enable/reset-password/unlock/move), AD computer lifecycle (disable/enable/move/reset-account), local (per-machine) user lifecycle + local group membership, and AD group membership add/remove — **one object at a time, every change routed through the gate** with truthful preview, scaled confirmation, and fail-closed audit. No bulk, no workflows, no remoting transport (Phase 3), no computer/group *creation* (not in v1). Success is measured by the ROADMAP Phase 2 criteria: USER-02..06, LUSR-01/02, COMP-02..04, GRP-01..03 all true, with the lint + Pester gate-proof re-proven against the new verbs.

The safety *principles* and the Phase 0/1 spine (gate, config, audit, deny-list, protected-account resolution, capability probe, scoped reads, menu shell) are locked and reused. The decisions below pin down **how the four mutation families flow through the gate** — three of the four required extending the gate's target model because they don't fit the existing "resolve one existing AD object" shape.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Creates through the gate (USER-02)

- **D-01: Create-user flows through the EXISTING gate via a synthetic pre-create target.** No sibling creation gate, no two-phase create.
  - A new Private `Resolve-AdmanCreateTarget` fabricates a PSCustomObject shaped like an ADObject **without calling `Get-ADObject -Identity`** — it carries the *intended* DN (`CN=<name>,<parentOU-DN>`), the proposed `sAMAccountName`, `objectClass='user'`, and the parent OU DN. That synthetic object flows through the gate's fixed order unchanged: Test-AdmanTargetAllowed → Confirm-AdmanAction → Write-AdmanAudit PENDING → `Adman.AD.Write.New-ADUser` → OUTCOME.
  - **SAFE-10 preserved literally:** the preview and the audit `Target` field name the to-be-created DN (`CN=<name>,<parentOU>`), not the parent OU. The same synthetic array feeds WhatIf and execute.
  - **`Test-AdmanTargetAllowed` gains a create-branch:** for synthetic pre-create targets, SKIP checks (a) gMSA objectClass, (b) deny-RID, (d) recursive protected-membership (no objectSid/memberOf exist yet) and run ONLY (c) managed-OU scope **against the parent OU DN** — creating under an out-of-scope OU refuses closed.
  - **Uniqueness pre-flight, refuse closed:** before confirm, a lookup for the proposed `sAMAccountName` AND the proposed CN (within the parent OU) must return zero hits, else the action refuses with a precise reason. The TOCTOU window between pre-flight and write is closed by letting `New-ADUser` itself throw on collision and recording `Result='Failed'` in the OUTCOME audit write (the 00-05 writer already supports non-Success outcomes).
  - **Drift-test extends mechanically:** add `'New-ADUser'` to `Get-AdmanAllowedWriteVerbs`, to the gate `ValidateSet`, and one `Adman.AD.Write.New-ADUser` wrapper. The existing gate-order and no-hard-delete Pester guards continue to enforce the invariant.
  - `New-ADUser` single-call shape: `-Name -SamAccountName -UserPrincipalName -Path <parentOU> -AccountPassword <SecureString> -Enabled $true -ChangePasswordAtLogon $true` (enabling at creation requires the policy-compliant generated password to be present — see D-04). `-Server $script:Config.DC` pinned in the wrapper per the existing pattern.

### Area 2 — Local-user verbs: scope + target model (LUSR-01/02)

- **D-02: A sibling local gate `Invoke-AdmanLocalMutation` (Private, non-exported) + transport-agnostic Public verbs.** The AD gate stays a pure AD-only boundary.
  - **Transport:** Public verbs take an optional `-ComputerName` parameter that is **validated to localhost in Phase 2** (accepts `$null`, `'.'`, `$env:COMPUTERNAME`, `localhost` — anything else throws a clear "remote targets arrive in Phase 3" error). Phase 3 widens the validation when the transport ladder lands; **verb signatures never change between phases**. No `Invoke-Command` path ships in Phase 2 (remoting quarantine preserved).
  - **Local target model:** a local target is `machine + local username + local SID`. A new Private `Resolve-AdmanLocalTarget` materializes local account objects (via `Get-LocalUser`/`Get-LocalGroupMember` on the target machine — localhost in Phase 2); **no DN, no AD objectSid**.
  - **Local policy (`Test-AdmanLocalTargetAllowed`):** (a) refuse the built-in local Administrator **RID-500** (match the local SID's RID, never the name — renamed-admin is the norm); (b) refuse targets that are members of the local **Administrators S-1-5-32-544** group where the action would weaken that protection boundary (mirrors SAFE-06's spirit for local scope); (c) machine-in-scope: the target machine's **AD computer object** (resolvable via the existing `Resolve-AdmanTarget` — computer objects ARE AD objects) must pass managed-OU scope, so adman can't touch local accounts on out-of-scope machines. For localhost, the machine's own computer object is resolved by `$env:COMPUTERNAME`.
  - **Shared internals:** the local gate reuses `Confirm-AdmanAction`, `Write-AdmanAudit`, `Assert-AdmanBulkPolicy` verbatim — confirm semantics, write-ahead PENDING→OUTCOME, and fail-closed behavior are identical. Audit `Target` records `MACHINE\username` + local SID (no DN); the audit schema's no-secret-key regex and schema tests are extended to bless this shape.
  - **SAFE-08 lint guard extends to both gates:** the AST guard asserts no exported function names LocalAccounts mutation cmdlets directly; only `Adman.Local.Write.*` wrappers (new Private file, same one-wrapper-per-verb discipline) may name them, and only the two gates call wrappers. **Verified premise correction:** all LocalAccounts cmdlets DO declare `SupportsShouldProcess` on PS 5.1 — truthful `-WhatIf` works through the wrappers.
  - **Verbs:** `New-LocalUser`, `Disable-LocalUser`, `Enable-LocalUser`, `Set-LocalUser` (password reset), `Remove-LocalUser`, `Add-LocalGroupMember`, `Remove-LocalGroupMember` — each gated, audited, confirmed.

- **D-03: `Remove-LocalUser` ships as a higher-blast-radius verb.** Local accounts have no Recycle Bin / quarantine OU, so SAFE-09's reversible-delete mechanism cannot apply; the *spirit* (no casual hard delete) is preserved by:
  - **Typed-count confirmation even at count=1** — this verb overrides `safety.bulkConfirmThreshold` to 1, so the operator always types the exact count (D-07 mechanism, per-verb override).
  - **Pre-delete state capture in the audit record:** local SID, name, group memberships, profile path — enough for a manual re-create. The OUTCOME record references the captured state by correlation ID.
  - Help text on the Public verb states plainly: irreversible, no Recycle-Bin equivalent.

### Area 3 — Group-membership policy model (GRP-01/02/03)

- **D-04: Dual-resolution policy matrix + asymmetric add/remove.** The gate resolves BOTH parties of the two-object mutation and runs a per-side check matrix; one audit record names both.
  - **Member side (the user/computer whose privilege changes):** resolved via the existing `Resolve-AdmanTarget` and checked by the existing `Test-AdmanTargetAllowed` UNCHANGED — gMSA pre-filter, deny-RID, managed-OU scope, recursive protected-membership all apply to the member. The member DN remains the audit `target`.
  - **Group side:** resolved once via a new group-resolution call; checked by a NEW Private `Test-AdmanGroupAllowed` with exactly three checks: (i) the group's **own `objectSid` is NOT in `$script:ProtectedSIDs`** — direct SID equality against the D-02 protected set, NOT IN_CHAIN (the GRP-03 question is identity, not membership); (ii) group's SID NOT in `$script:DenyRids`; (iii) group is NOT a gMSA (defense-in-depth). The existing check (d) ("target is a recursive *member of* a protected group") is the wrong relation for GRP-03 and is NOT reused on the group side.
  - **No managed-OU scope required on the group side:** protected groups live in `CN=Users`/`Builtin` and legitimate shared groups typically live in a Groups OU outside the managed user/computer OUs — requiring scope would refuse legitimate GRP-01 ops. Opt-in config `safety.requireManagedGroupOU` (default `$false`) for shops that DO keep groups inside managed OUs.
  - **Asymmetry:** GRP-03's literal text covers *adding* — add is strict (all group-side checks). **Removing a principal FROM a protected group is a remediation and is ALLOWED** (member-side checks still apply; group-side protected check is skipped on remove; still confirmed + audited). This makes Tier-0 cleanup a first-class workflow.
  - **Audit schema gains a `group` field** alongside `target` (member DN). Preview and confirmation render both sides ("Add jdoe (DN) to group X (DN)"). SAFE-10 preserved: each side resolved ONCE, the same two arrays feed preview and execute.
  - The matrix is a small declarative hashtable (verb → member-checks, group-checks) so future two-object verbs (`Move-ADObject -TargetPath`, `Set-ADUser -Manager`) reuse the pattern.

### Area 4 — Password sourcing UX (USER-02/04)

- **D-05: Hybrid sourcing with `security.passwordSource = Generate|Prompt|Ask`, config default `Generate`.**
  - **Generate path (junior default):** `New-AdmanRandomPassword` (Private) implements the **Spike 004 validated recipe** — `[System.Security.Cryptography.RandomNumberGenerator]::Create()`, rejection sampling (no modulo bias), Fisher-Yates shuffle, 76-char no-ambiguous alphabet, length 20, ≥1 char from each of 4 classes. Config: `security.passwordGeneration.length` (default 20). `Get-Random` is NEVER used (not a CSPRNG); `System.Web.Security.Membership]::GeneratePassword` is NEVER used (Desktop-only, dead on PS7).
  - **Prompt path (senior escape hatch):** `Read-Host -AsSecureString`, twice-entered with equality confirm. **The prompt path MUST enforce the same complexity policy as the generator** (length + 4 classes) via a validator — otherwise it is a policy bypass. Weak input is rejected with a clear reason and re-prompt.
  - **`Ask` mode:** a 2-item numeric sub-choice per action (fits the existing PromptSpec `Choices` pattern). PromptSpec gains a polymorphic `Type` field (`GeneratedPassword` / `SecureString`) consumed by `Read-AdmanActionParams`.
  - **`must-change-at-next-logon` ON by default** for both create and reset (config-overridable per-installation, not per-action in the menu path). The generated password displayed once is a single-use relay — it dies at first logon.
  - **Display-once hygiene:** generated password shown once behind a `Read-Host 'Press Enter when recorded'` gate, then `[Console]::Clear()` (or scroll-off equivalent) to shrink the shoulder-surf window. No clipboard handoff (clipboard is a worse secret store: any process can read it, RDP/VM sync leaks, no auto-expire on 5.1, breaks over remoting/Server Core).
  - **Never-echo-or-log mechanics (USER-04):** the audit writer never receives the `$Parameters` hashtable (verified: it records DN/SID/objectClass metadata only) and its schema test enforces a no-secret-key regex — both invariants are extended by contract test to the new verbs. The SecureString is born in `New-AdmanRandomPassword`/`Read-Host -AsSecureString`, passed ONLY into `Set-ADAccountPassword -NewPassword` / `New-ADUser -AccountPassword`, and is **never marshaled to plaintext** (no BSTR conversion anywhere in the codebase).
  - **`-WhatIf`/audit preview strings describe without characters:** e.g. `"Reset password for {DN} (length 20, generated, must-change=ON)"` / `"... (prompted, must-change=ON)"`.

### Claude's Discretion

- **Menu organization for writes:** ~15 new write actions join the flat Phase-1 menu. Planner picks the shape (recommended: keep the flat `Read-Host` loop per 01-D-01 but add section headers/grouping — e.g., Search / Reports / User writes / Computer writes / Local writes / Group membership — rendered as non-selectable separator lines; a two-level submenu is acceptable if the flat list proves unreadable, but the B/Q reserved-input contract and thin prompt-and-dispatch discipline are unchanged). Each write menu item routes to the same Public verb a senior calls directly (MENU-04), and every write prompt flow ends at the gate's confirmation, never a menu-level confirm.
- **Computer-account reset shape (COMP-04):** planner pins the exact mechanics during research — expected shape: AD-side "Reset Account" = `Set-ADAccountPassword -Reset` with the default machine password (ADUC semantics, already an allow-listed gate verb), plus guidance text + the exact `Test-ComputerSecureChannel -Repair` command for the on-machine channel repair (runs ON the affected machine, out-of-gate, documented as a runbook step). "Which method applies" guidance is a help-text/runbook deliverable.
- **PDCe-pinned unlock (USER-05):** planner implements the per-verb `-Server` override — the unlock verb's resolver + wrapper pin to `(Get-ADDomain).PDCEmulator` instead of `$script:Config.DC` (reads `LockedOut` first on the PDCe; no-op with a clear message when not locked). Mechanism is planner's choice (per-verb server override in the gate's Parameters flow).
- **Move destination validation (USER-06/COMP-03):** `Move-ADObject -TargetPath` destination OU MUST be validated under managed roots before confirm (reuses the D-01 parent-OU scope check). This is a safety invariant, not an option — planner wires it as a per-verb Parameters validator in the gate.
- **Exact Public verb names** (`New-AdmanUser`, `Set-AdmanUserPassword`, `Move-AdmanUser`, `Add/Remove-AdmanGroupMember`, `New/Remove/Set-AdmanLocalUser`, etc.) — idiomatic `Adman` nouns, locked in `FunctionsToExport`.
- **Whether `-WhatIf` on the Public verbs shows the synthetic-target DN** for creates (recommended yes — it is the truthful intended target).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project definition & requirements
- `.planning/PROJECT.md` — Core value (safety property must hold), constraints (config/credential split, `.store/` gitignored, RSAT prereq, no WinRM assumption).
- `.planning/REQUIREMENTS.md` — **Phase 2 owns 13:** `USER-02`–`USER-06`, `LUSR-01`–`LUSR-02`, `COMP-02`–`COMP-04`, `GRP-01`–`GRP-03`. Traceability table is authoritative.
- `.planning/ROADMAP.md` §Phase 2 — Goal, 4 success criteria, suggested 4-plan split (02-01 AD user verbs, 02-02 AD computer verbs, 02-03 local-user verbs, 02-04 group membership + gate re-proof). **The suggested split predates these decisions; the planner should re-derive the split from D-01..D-05 (gate-extension work is cross-cutting and likely wants its own plan).**

### Phase 0/1 artifacts (the spine this phase extends)
- `.planning/phases/00-foundation-safety-harness/00-CONTEXT.md` — D-02 protected set (SID-resolved, IN_CHAIN), D-03 write-ahead audit, D-05 deny-list by RID, D-06 DPAPI credential, D-07 confirmation scaling + `-Force` semantics. **All unchanged; Phase 2 builds ON them.**
- `.planning/phases/00-foundation-safety-harness/00-PATTERNS.md`, `00-SUMMARY.md`, `00-VERIFICATION.md` — what shipped and what was proven.
- `.planning/phases/01-ad-query-reporting-read-only/01-CONTEXT.md` — 01-D-01 flat menu + B/Q reserved inputs + thin prompt-and-dispatch (MENU-04), D-03 result schema, menu-table shape (`Get-AdmanMenuDefinition` PromptSpec).

### Research corpus & spikes
- `.planning/research/PITFALLS.md` — AD/PowerShell gotchas: `-Server` pinning, Filter-vs-LDAPFilter parameter sets, RID-500 rename, `adminCount` staleness, `ResultPageSize`.
- `.planning/research/STACK.md`, `.planning/research/ARCHITECTURE.md` — dual-edition strategy, module/gate architecture.
- `.planning/spikes/004-secure-password-generation/README.md` + `Invoke-Spike.ps1` — **VALIDATED** CSPRNG recipe (RandomNumberGenerator + rejection sampling + Fisher-Yates, 76-char alphabet, length 20, dual-edition PASS). D-05's Generate path implements this spike's algorithm.

### Code that changes (read before planning)
- `Private/Safety/Invoke-AdmanMutation.ps1` — the gate; gains the create path (D-01) and dual-resolution group matrix (D-04).
- `Private/Safety/Resolve-AdmanTarget.ps1` — Identity-only resolver; sibling `Resolve-AdmanCreateTarget` (D-01) and group-side resolution (D-04) join it.
- `Private/Safety/Test-AdmanTargetAllowed.ps1` — gains the create-branch (D-01); unchanged for member-side group checks (D-04).
- `Private/Safety/AdmanWriteVerbs.ps1` + `Private/AD/Adman.AD.Write.ps1` — the allow-list + wrappers; `New-ADUser` joins both (drift-test enforced).
- `Private/Safety/Confirm-AdmanAction.ps1` — confirmation engine; per-verb threshold override for `Remove-LocalUser` (D-03), two-object rendering for group ops (D-04).
- `Private/Audit/Write-AdmanAudit.ps1` — audit writer; schema gains `group` field (D-04) and the `MACHINE\username` target shape (D-02); no-secret-key regex invariant extended by contract test.
- `Private/Menu/Get-AdmanMenuDefinition.ps1` + `Read-AdmanActionParams.ps1` — menu table + prompt engine; PromptSpec gains polymorphic `Type` for passwords (D-05) and ~15 new write entries.
- `rules/AdmanSafetyRules.psm1` + `tests/` — SAFE-08/09 AST guard extends to the local gate + `Adman.Local.Write.*` wrappers + LocalAccounts cmdlet names (D-02).

### Project rules & guardrails
- `.claude/CLAUDE.md` — "What NOT to Use" list, PSScriptAnalyzer rule set, dual-edition constraints (5.1 baseline; no PS7-only APIs; `ConvertFrom-Json` has no `-AsHashtable`).

### Runtime locations (gitignored — NEVER commit)
- `.store/config.json` — gains `security.passwordSource`, `security.passwordGeneration.length`, `safety.requireManagedGroupOU` (all with shipped defaults; first-run wizard documents them).
- `.store/audit/audit-YYYYMMDD.jsonl` — new `group` field + `MACHINE\username` target shape appear from this phase.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Invoke-AdmanMutation` (Private/Safety)** — the gate's fixed order (Resolve → Test → BulkPolicy → Confirm → PENDING → Write → OUTCOME) is reused verbatim by all four mutation families; the local gate (D-02) mirrors this skeleton with shared Confirm/Audit/BulkPolicy internals.
- **`Test-AdmanTargetAllowed`** — member-side group checks (D-04) and the machine-in-scope check via AD computer object (D-02) reuse it unchanged; the create-branch (D-01) is its only modification.
- **`Confirm-AdmanAction`** — already WhatIf-aware, supports typed-count and `-Force`; gains a per-verb threshold override (D-03) and two-object rendering (D-04).
- **`Write-AdmanAudit`** — write-ahead PENDING/OUTCOME with named mutex; no-secret-key schema regex already enforced by test; extended (not redesigned) for `group` field and local-target shape.
- **`Get-AdmanMenuDefinition` + `Read-AdmanActionParams`** — the menu-table/PromptSpec machinery absorbs the ~15 new write entries + password prompt types without a new menu engine.
- **Spike 004 code** (`.planning/spikes/004-secure-password-generation/Invoke-Spike.ps1`) — the reference implementation for `New-AdmanRandomPassword`.
- **`Escape-AdmanLdapFilterValue`** — reused by the uniqueness pre-flight lookup (D-01) for sAM/CN escaping.

### Established Patterns (mirror these, don't reinvent)
- **One thin wrapper per verb** (`Adman.AD.Write.ps1`): new `Adman.AD.Write.New-ADUser` and the whole `Adman.Local.Write.ps1` file follow the exact shape — `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]`, iterate resolved objects, `-WhatIf:$WhatIfPreference -Confirm:$false`, `-ErrorAction Stop`. Local wrappers omit `-Server` (LocalAccounts has none).
- **`-Server $script:Config.DC` pinning** on every AD cmdlet; the ONE sanctioned exception is PDCe-pinned unlock (Claude's discretion).
- **`$ErrorActionPreference='Stop'` module-wide**; explicit try/catch only for expected failure modes (e.g., uniqueness pre-flight DC unreachable → refuse closed).
- **Public/Private boundary:** all new policy/resolver/gate code is Private; Public verbs are thin prompt-and-dispatch targets callable directly by seniors.
- **Drift-test discipline:** `Get-AdmanAllowedWriteVerbs`, the gate `ValidateSet`, and the wrapper set are asserted equal by Pester — the same triple extends for local verbs.

### Integration Points
- **Gate create path** (D-01): `Invoke-AdmanMutation` branches to `Resolve-AdmanCreateTarget` when the verb is a create; planner keeps the fixed order otherwise byte-identical.
- **Local gate** (D-02): new `Private/Safety/Invoke-AdmanLocalMutation.ps1` + `Resolve-AdmanLocalTarget.ps1` + `Test-AdmanLocalTargetAllowed.ps1` + `Private/Local/Adman.Local.Write.ps1`; machine-in-scope reuses `Resolve-AdmanTarget` on `$env:COMPUTERNAME`'s AD computer object.
- **Group matrix** (D-04): gate gains a second resolution pass for the group parameter + `Test-AdmanGroupAllowed.ps1`; `Write-AdmanAudit` accepts the `group` field.
- **Password plumbing** (D-05): `New-AdmanRandomPassword` (Private/Utility) + PromptSpec `Type` handling in `Read-AdmanActionParams`; Public verbs pass the SecureString into the gate's `$Parameters` untouched.
- **Menu** (Claude's discretion): `Get-AdmanMenuDefinition` grows the write entries; `Start-Adman` stays a thin dispatcher.

</code_context>

<specifics>
## Specific Ideas

- **The audit record must always name the object whose state changes** — the created user's intended DN (D-01), the member DN not the group (D-04), `MACHINE\username` + local SID (D-02). "The preview literally names the object that will exist" was the deciding argument for extending the gate rather than validating the parent OU as target.
- **GRP-03 is about identity, not membership** — the group's OWN SID against the protected set by direct equality. The existing IN_CHAIN check answers a different question and stays member-side only.
- **Removal from a protected group is remediation, not a violation** — the tool should HELP clean up Tier-0 drift (jdoe found in Domain Admins → remove), not refuse it. Add is strict; remove is allowed (member-side checks + confirm + audit still apply).
- **A prompt path that skips the complexity policy is a policy bypass** — the hybrid only works if prompted passwords meet the same bar as generated ones.
- **LocalAccounts cmdlets DO support `-WhatIf` on PS 5.1** (verified on 5.1.26100) — the original discuss premise that they don't was wrong; truthful preview is achievable through the wrappers.
- **v1 has exactly ONE create verb** (`New-ADUser`) — no computer create, no group create. The create-branch investment is justified for USER-02 alone; no amortization argument was needed or used.

</specifics>

<deferred>
## Deferred Ideas

- **Remote local-user operations** (real `-ComputerName` against non-localhost targets) — Phase 3, when the transport ladder (WinRM → CIM/WSMan → CIM/DCOM → skip) exists. D-02's verb signatures are already stable for it.
- **Two-level menu / hotkeys** — acceptable planner fallback if the grouped flat menu proves unreadable; full redesign deferred past Phase 2 per 01-D-01's note.
- **`New-ADComputer` / group creation verbs** — not in v1 requirements; the create-branch pattern (D-01) is ready if v2 adds them.
- **Per-DC `lastLogon` forensic unlock diagnostics** (which DC recorded the lockout) — out of scope; unlock reads `LockedOut` on the PDCe only (USER-05).
- **Clipboard password handoff** — rejected (secret-lifetime worse than display-once; breaks over remoting/Server Core).
- **Symmetric protected-group refusal (refuse removal too)** — rejected; remediation must stay possible (D-04).
- **`safety.requireManagedGroupOU` default-true posture** — available via config for shops that manage their group OUs; not the default (D-04).
- **JEA/RBCD delegation for local-admin management** — Phase 3/5 hardening territory.

</deferred>

---

*Phase: 2-Single-Object Lifecycle (writes begin)*
*Context gathered: 2026-07-15*
