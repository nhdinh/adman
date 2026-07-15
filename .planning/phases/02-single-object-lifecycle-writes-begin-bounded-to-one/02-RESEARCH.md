# Phase 2: Single-Object Lifecycle (writes begin, bounded to one) - Research

**Researched:** 2026-07-15
**Domain:** Active Directory single-object write operations via PowerShell (AD user/computer lifecycle, local user lifecycle, group membership)
**Confidence:** HIGH

## Summary

Phase 2 extends the Phase 0/1 safety spine (gate, audit, confirm, deny-list, protected-SID resolution, scoped reads) with the first real AD writes. The research confirms that all required cmdlet surfaces are well-documented and stable, but reveals several critical behavioral landmines that the planner must design around: New-ADUser's "create-then-fail" password complexity behavior, the PDC Emulator's authoritative role in lockout operations, Get-LocalGroupMember's fatal orphaned-SID bug, and the irreversibility of Remove-LocalUser. The locked decisions D-01 through D-05 are fully implementable with the verified cmdlet patterns below.

**Primary recommendation:** Extend the existing gate with a create-branch for synthetic pre-create targets (D-01), build a sibling local gate reusing the same Confirm/Audit/BulkPolicy internals (D-02), implement the dual-resolution group matrix with asymmetric add/remove (D-04), and lift the Spike 004 CSPRNG recipe directly into New-AdmanRandomPassword (D-05). Every write wrapper must pin -Server (except PDCe-pinned unlock) and declare SupportsShouldProcess with ConfirmImpact='High'.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Create-user flows through the EXISTING gate via a synthetic pre-create target.** No sibling creation gate, no two-phase create.
  - A new Private `Resolve-AdmanCreateTarget` fabricates a PSCustomObject shaped like an ADObject **without calling `Get-ADObject -Identity`** — it carries the *intended* DN (`CN=<name>,<parentOU-DN>`), the proposed `sAMAccountName`, `objectClass='user'`, and the parent OU DN. That synthetic object flows through the gate's fixed order unchanged: Test-AdmanTargetAllowed → Confirm-AdmanAction → Write-AdmanAudit PENDING → `Adman.AD.Write.New-ADUser` → OUTCOME.
  - **SAFE-10 preserved literally:** the preview and the audit `Target` field name the to-be-created DN (`CN=<name>,<parentOU>`), not the parent OU. The same synthetic array feeds WhatIf and execute.
  - **`Test-AdmanTargetAllowed` gains a create-branch:** for synthetic pre-create targets, SKIP checks (a) gMSA objectClass, (b) deny-RID, (d) recursive protected-membership (no objectSid/memberOf exist yet) and run ONLY (c) managed-OU scope **against the parent OU DN** — creating under an out-of-scope OU refuses closed.
  - **Uniqueness pre-flight, refuse closed:** before confirm, a lookup for the proposed `sAMAccountName` AND the proposed CN (within the parent OU) must return zero hits, else the action refuses with a precise reason. The TOCTOU window between pre-flight and write is closed by letting `New-ADUser` itself throw on collision and recording `Result='Failed'` in the OUTCOME audit write (the 00-05 writer already supports non-Success outcomes).
  - **Drift-test extends mechanically:** add `'New-ADUser'` to `Get-AdmanAllowedWriteVerbs`, to the gate `ValidateSet`, and one `Adman.AD.Write.New-ADUser` wrapper. The existing gate-order and no-hard-delete Pester guards continue to enforce the invariant.
  - `New-ADUser` single-call shape: `-Name -SamAccountName -UserPrincipalName -Path <parentOU> -AccountPassword <SecureString> -Enabled $true -ChangePasswordAtLogon $true` (enabling at creation requires the policy-compliant generated password to be present — see D-04). `-Server $script:Config.DC` pinned in the wrapper per the existing pattern.

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

- **D-04: Dual-resolution policy matrix + asymmetric add/remove.** The gate resolves BOTH parties of the two-object mutation and runs a per-side check matrix; one audit record names both.
  - **Member side (the user/computer whose privilege changes):** resolved via the existing `Resolve-AdmanTarget` and checked by the existing `Test-AdmanTargetAllowed` UNCHANGED — gMSA pre-filter, deny-RID, managed-OU scope, recursive protected-membership all apply to the member. The member DN remains the audit `target`.
  - **Group side:** resolved once via a new group-resolution call; checked by a NEW Private `Test-AdmanGroupAllowed` with exactly three checks: (i) the group's **own `objectSid` is NOT in `$script:ProtectedSIDs`** — direct SID equality against the D-02 protected set, NOT IN_CHAIN (the GRP-03 question is identity, not membership); (ii) group's SID NOT in `$script:DenyRids`; (iii) group is NOT a gMSA (defense-in-depth). The existing check (d) ("target is a recursive *member of* a protected group") is the wrong relation for GRP-03 and is NOT reused on the group side.
  - **No managed-OU scope required on the group side:** protected groups live in `CN=Users`/`Builtin` and legitimate shared groups typically live in a Groups OU outside the managed user/computer OUs — requiring scope would refuse legitimate GRP-01 ops. Opt-in config `safety.requireManagedGroupOU` (default `$false`) for shops that DO keep groups inside managed OUs.
  - **Asymmetry:** GRP-03's literal text covers *adding* — add is strict (all group-side checks). **Removing a principal FROM a protected group is a remediation and is ALLOWED** (member-side checks still apply; group-side protected check is skipped on remove; still confirmed + audited). This makes Tier-0 cleanup a first-class workflow.
  - **Audit schema gains a `group` field** alongside `target` (member DN). Preview and confirmation render both sides ("Add jdoe (DN) to group X (DN)"). SAFE-10 preserved: each side resolved ONCE, the same two arrays feed preview and execute.
  - The matrix is a small declarative hashtable (verb → member-checks, group-checks) so future two-object verbs (`Move-ADObject -TargetPath`, `Set-ADUser -Manager`) reuse the pattern.

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

### Deferred Ideas (OUT OF SCOPE)

- **Remote local-user operations** (real `-ComputerName` against non-localhost targets) — Phase 3, when the transport ladder (WinRM → CIM/WSMan → CIM/DCOM → skip) exists. D-02's verb signatures are already stable for it.
- **Two-level menu / hotkeys** — acceptable planner fallback if the grouped flat menu proves unreadable; full redesign deferred past Phase 2 per 01-D-01's note.
- **`New-ADComputer` / group creation verbs** — not in v1 requirements; the create-branch pattern (D-01) is ready if v2 adds them.
- **Per-DC `lastLogon` forensic unlock diagnostics** (which DC recorded the lockout) — out of scope; unlock reads `LockedOut` on the PDCe only (USER-05).
- **Clipboard password handoff** — rejected (secret-lifetime worse than display-once; breaks over remoting/Server Core).
- **Symmetric protected-group refusal (refuse removal too)** — rejected; remediation must stay possible (D-04).
- **`safety.requireManagedGroupOU` default-true posture** — available via config for shops that manage their group OUs; not the default (D-04).
- **JEA/RBCD delegation for local-admin management** — Phase 3/5 hardening territory.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| USER-02 | Admin can create a single user with required attributes (name, sAMAccountName, UPN, OU, password, must-change-at-next-logon, enabled) | New-ADUser verified with -Name, -SamAccountName, -UserPrincipalName, -Path, -AccountPassword, -Enabled, -ChangePasswordAtLogon. Password complexity landmine documented (creates disabled user on failure). D-01 synthetic target pattern validated. |
| USER-03 | Admin can disable and enable a user (through the gate) | Disable-ADAccount / Enable-ADAccount verified. Existing gate wrappers already present. |
| USER-04 | Admin can reset a user's password (optionally force change at next logon and unlock) without ever echoing or logging the password | Set-ADAccountPassword -Reset verified. SecureString handling verified. D-05 password sourcing patterns validated. |
| USER-05 | Admin can unlock a locked account (reads LockedOut first; pinned to the PDC emulator) | Unlock-ADAccount verified with -Server parameter. PDC Emulator authoritative role confirmed. |
| USER-06 | Admin can move a user to another OU within managed scope | Move-ADObject -TargetPath verified. Destination validation pattern established. |
| LUSR-01 | Admin can create/disable/enable/reset-password/remove a local user on a target machine via the LocalAccounts module (mutations through the gate) | All LocalAccounts cmdlets verified with -WhatIf support on PS 5.1. Remove-LocalUser irreversibility confirmed. |
| LUSR-02 | Admin can manage local group membership (e.g., local Administrators) on a target machine | Add-LocalGroupMember / Remove-LocalGroupMember verified. Get-LocalGroupMember orphaned-SID bug documented. |
| COMP-02 | Admin can disable/enable a computer (through the gate) | Disable-ADAccount / Enable-ADAccount work on computer objects. Existing wrappers sufficient. |
| COMP-03 | Admin can move a computer to another OU within managed scope | Move-ADObject verified for computer objects. |
| COMP-04 | Admin can reset a computer account / repair the secure channel (with guidance on which method applies) | Set-ADAccountPassword -Reset (AD-side) and Test-ComputerSecureChannel -Repair (local-side) verified. |
| GRP-01 | Admin can add a user to one or more groups (through the gate) | Add-ADGroupMember verified with -Members ADPrincipal[] array. |
| GRP-02 | Admin can remove a user from a group (through the gate) | Remove-ADGroupMember verified. |
| GRP-03 | Tool refuses adding any principal to a protected group (Domain Admins etc.) per SAFE-06 | Test-AdmanGroupAllowed pattern validated: direct SID equality against ProtectedSIDs, not IN_CHAIN. |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| AD user create/disable/enable/reset/unlock/move | API / Backend (AD DS) | — | All mutations are LDAP writes against the directory; no local state changes |
| AD computer disable/enable/move/reset | API / Backend (AD DS) | — | Same as user lifecycle; computer objects are AD security principals |
| Local user create/disable/enable/reset/remove | OS / Local Machine | — | LocalAccounts module operates on the local SAM database |
| Local group membership add/remove | OS / Local Machine | — | Local group operations are machine-local |
| AD group membership add/remove | API / Backend (AD DS) | — | Group membership is a directory attribute (member/memberOf) |
| Password generation | Client / Utility | — | CSPRNG runs locally; no network dependency |
| Audit write | Local File System | Windows Event Log (fallback) | JSONL append with named mutex; event log only on OUTCOME failure |
| Confirmation prompt | Console / TUI | — | Read-Host / ShouldProcess interaction |
| PDC Emulator resolution | API / Backend (AD DS) | — | Get-ADDomain query to discover PDCEmulator |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ActiveDirectory module (RSAT) | ships with Windows/RSAT | AD user/computer/group/OU lifecycle | The only Microsoft-supported cmdlet surface for on-prem AD. Natively compatible with PS 5.1 and PS 7.6 on 1809+. |
| Microsoft.PowerShell.LocalAccounts | built-in (5.1) / built-in (PS7) | Local user/group lifecycle | Covers the "AD/Local user lifecycle" requirement. Natively compatible with both editions. |
| Pester | 6.0.0 | Unit/integration test + mock framework | Standard PowerShell test framework. v6 supports WinPS 5.1 and PS 7.4+. |
| PSScriptAnalyzer | 1.25.0 | Static analysis + custom rules | Min PS 5.1; enforces SAFE-08 via custom rule. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PSFramework | 1.14.457 (exact pinned) | Config + diagnostic/ops logging | Already adopted in Phase 0 for config and diagnostic logging; audit writer stays hand-rolled. |
| CimCmdlets | built-in | Inventory + no-WinRM remote fallback | Phase 3 transport ladder; not used in Phase 2. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled menu | Terminal.Gui / Spectre.Console | Adds .NET/edition friction and over-remoting flakiness for no safety benefit |
| CIM over WSMan, DCOM fallback | Plain Get-WmiObject | Removed in PS7; breaks dual-edition goal |
| Microsoft.PowerShell.PlatyPS 1.0.2 | legacy platyPS 0.14.2 | Different cmdlet surface; greenfield should use 1.0.2 |
| PSResourceGet 1.2.0 | PowerShellGet 2.2.5 | Legacy line; PSResourceGet is the replacement |
| JSON-lines audit (hand-rolled) | PSFramework for audit sink | PSFramework durable logging is async; breaks fail-closed |

**Installation:**
```powershell
# Dev toolchain (CurrentUser scope)
Install-Module Pester -RequiredVersion 6.0.0 -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
Install-Module PSFramework -RequiredVersion 1.14.457 -Scope CurrentUser -Force
```

**Version verification:** Pester 6.0.0 stable published 2026-07-07 (6.1.0-alpha1 prerelease 2026-07-09). PSScriptAnalyzer 1.25.0 published 2026-03-20. Both verified on PowerShell Gallery.

## Package Legitimacy Audit

> **Required** whenever this phase installs external packages. Run the Package Legitimacy Gate protocol before completing this section.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| Pester | PSGallery | 12+ yrs | 50M+ | github.com/pester/Pester | OK | Approved |
| PSScriptAnalyzer | PSGallery | 10+ yrs | 100M+ | github.com/PowerShell/PSScriptAnalyzer | OK | Approved |
| PSFramework | PSGallery | 8+ yrs | 10M+ | github.com/PowershellFrameworkCollective/psframework | OK | Approved |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Note: The gsd-tools package-legitimacy check was run against npm (incorrect ecosystem for PowerShell modules) and returned SUS/SLOP for Pester/PSScriptAnalyzer. These are PowerShell Gallery modules, not npm packages. Verified directly on PSGallery.*

## Architecture Patterns

### System Architecture Diagram

```
User Input (Menu or Direct Call)
    |
    v
Public Verb (New-AdmanUser, Set-AdmanUserPassword, etc.)
    |
    v
Invoke-AdmanMutation (AD gate) / Invoke-AdmanLocalMutation (local gate)
    |
    +--> Resolve-AdmanTarget / Resolve-AdmanCreateTarget / Resolve-AdmanLocalTarget
    |         |
    |         v
    |    AD Object / Synthetic Target / Local Principal
    |         |
    +--> Test-AdmanTargetAllowed / Test-AdmanLocalTargetAllowed / Test-AdmanGroupAllowed
    |         |
    |         v
    |    Allowed? + Reason
    |         |
    +--> Assert-AdmanBulkPolicy (threshold source)
    |         |
    +--> Confirm-AdmanAction (WhatIf-aware, scaled)
    |         |
    |         v
    |    Outcome: Proceed / DryRun / Declined
    |         |
    +--> Write-AdmanAudit (PENDING) [fail-closed]
    |         |
    +--> Adman.AD.Write.<Verb> / Adman.Local.Write.<Verb>
    |         |
    |         v
    |    AD DS / Local SAM
    |         |
    +--> Write-AdmanAudit (OUTCOME: Success/Failure/Refused)
```

### Recommended Project Structure
```
adman/
├── Public/                    # Exported verbs (thin prompt-and-dispatch)
│   ├── New-AdmanUser.ps1
│   ├── Set-AdmanUserPassword.ps1
│   ├── Move-AdmanUser.ps1
│   ├── Add-AdmanGroupMember.ps1
│   ├── Remove-AdmanGroupMember.ps1
│   ├── New-AdmanLocalUser.ps1
│   ├── Set-AdmanLocalUser.ps1
│   ├── Remove-AdmanLocalUser.ps1
│   └── ... (existing Find/Get verbs)
├── Private/
│   ├── Safety/
│   │   ├── Invoke-AdmanMutation.ps1        # THE GATE (extended for creates + groups)
│   │   ├── Invoke-AdmanLocalMutation.ps1   # Sibling local gate (D-02)
│   │   ├── Resolve-AdmanTarget.ps1         # Existing resolver
│   │   ├── Resolve-AdmanCreateTarget.ps1   # NEW: synthetic pre-create target (D-01)
│   │   ├── Resolve-AdmanLocalTarget.ps1    # NEW: local account resolver (D-02)
│   │   ├── Test-AdmanTargetAllowed.ps1     # Extended with create-branch (D-01)
│   │   ├── Test-AdmanLocalTargetAllowed.ps1 # NEW: local policy (D-02)
│   │   ├── Test-AdmanGroupAllowed.ps1      # NEW: group-side checks (D-04)
│   │   ├── Confirm-AdmanAction.ps1         # Extended: per-verb threshold override (D-03)
│   │   ├── Assert-AdmanBulkPolicy.ps1      # Existing
│   │   ├── AdmanWriteVerbs.ps1             # Extended: New-ADUser + local verbs
│   │   └── Get-AdmanProtectedIdentity.ps1  # Existing
│   ├── AD/
│   │   └── Adman.AD.Write.ps1              # Extended: New-ADUser wrapper
│   ├── Local/
│   │   └── Adman.Local.Write.ps1           # NEW: local write wrappers (D-02)
│   ├── Audit/
│   │   ├── Write-AdmanAudit.ps1            # Extended: group field + local target shape
│   │   └── AdmanAuditIO.ps1                # Existing seams
│   ├── Menu/
│   │   ├── Get-AdmanMenuDefinition.ps1     # Extended: ~15 new write entries
│   │   └── Read-AdmanActionParams.ps1      # Extended: password prompt types (D-05)
│   └── Utility/
│       ├── New-AdmanRandomPassword.ps1     # NEW: CSPRNG generator (D-05)
│       ├── Escape-AdmanAdFilterLiteral.ps1 # Existing
│       └── Escape-AdmanLdapFilterValue.ps1 # Existing
├── rules/
│   └── AdmanSafetyRules.psm1               # Extended: LocalAccounts banned verbs
└── tests/
    ├── Mocks/
    │   └── ActiveDirectory.psm1            # Extended: local account mocks
    ├── Safety.GateOrder.Tests.ps1          # Extended: create path + group matrix
    ├── Safety.Gate.Tests.ps1               # Extended: local verb AST guard
    └── ... (new test files per verb family)
```

### Pattern 1: Synthetic Pre-Create Target (D-01)
**What:** A PSCustomObject fabricated to look like an ADObject for the gate's fixed order, without querying AD for an existing object.
**When to use:** Creating new AD objects (users) where the target doesn't exist yet.
**Example:**
```powershell
# Source: D-01 design + existing Resolve-AdmanTarget pattern
function Resolve-AdmanCreateTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$ParentOuDn
    )
    $dn = "CN=$Name,$ParentOuDn"
    [pscustomobject]@{
        DistinguishedName = $dn
        SamAccountName    = $SamAccountName
        objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        objectSid         = $null  # No SID yet
        memberOf          = @()
        ParentOuDn        = $ParentOuDn
        IsSynthetic       = $true  # Flag for Test-AdmanTargetAllowed create-branch
    }
}
```

### Pattern 2: Dual-Resolution Group Matrix (D-04)
**What:** Resolve both member and group independently, run per-side checks, produce one audit record naming both.
**When to use:** Two-object mutations (Add-ADGroupMember, Remove-ADGroupMember).
**Example:**
```powershell
# Source: D-04 design + existing gate pattern
# In Invoke-AdmanMutation, when Verb is Add-ADGroupMember or Remove-ADGroupMember:
$member = Resolve-AdmanTarget -Targets $Targets[0]  # The user/computer
$group  = Resolve-AdmanGroup -Identity $Parameters['GroupIdentity']  # The group

$memberDecision = Test-AdmanTargetAllowed -Object $member
$groupDecision  = Test-AdmanGroupAllowed -Object $group -Operation $Verb

# Audit record gains 'group' field alongside 'target' (member DN)
Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $member -Group $group `
    -Result 'PENDING' -WhatIf:$confirm.WhatIf
```

### Pattern 3: Local Gate Sibling (D-02)
**What:** A parallel gate for local machine operations that reuses Confirm/Audit/BulkPolicy but has its own resolver and policy checks.
**When to use:** Local user/group mutations on localhost (Phase 2) or remote machines (Phase 3).
**Example:**
```powershell
# Source: D-02 design
function Invoke-AdmanLocalMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('New-LocalUser','Disable-LocalUser','Enable-LocalUser',
            'Set-LocalUser','Remove-LocalUser','Add-LocalGroupMember','Remove-LocalGroupMember')]
        [string]$Verb,
        [Parameter(Mandatory)][string[]]$Targets,  # Local usernames
        [hashtable]$Parameters = @{},
        [switch]$Force
    )
    # Fixed order mirrors Invoke-AdmanMutation:
    # Resolve-AdmanLocalTarget -> Test-AdmanLocalTargetAllowed -> Assert-AdmanBulkPolicy ->
    # Confirm-AdmanAction -> Write-AdmanAudit(PENDING) -> Adman.Local.Write.<Verb> -> Write-AdmanAudit(OUTCOME)
}
```

### Pattern 4: CSPRNG Password Generation (D-05)
**What:** Cryptographically secure random password generation with rejection sampling and Fisher-Yates shuffle.
**When to use:** Generating passwords for New-ADUser and Set-ADAccountPassword.
**Example:**
```powershell
# Source: Spike 004 validated recipe (lift directly)
function New-AdmanRandomPassword {
    param([int]$Length = 20)
    # Uses [System.Security.Cryptography.RandomNumberGenerator]::Create()
    # Rejection sampling (no modulo bias)
    # Fisher-Yates shuffle
    # 76-char alphabet: 23 upper + 23 lower + 8 digit + 22 symbol
    # Guarantees >= 1 char from each of 4 classes
}
```

### Anti-Patterns to Avoid
- **New-ADUser -Enabled $true without pre-validating password complexity:** The cmdlet creates the user disabled even when the password fails. Always either (a) create disabled first, then set password, then enable; or (b) try/catch with Remove-ADUser cleanup on ADPasswordComplexityException.
- **Unlock-ADAccount without -Server $pdc:** The PDC Emulator is authoritative for lockout state. Unlocking against a non-PDCe DC can appear to fail transiently under replication lag.
- **Get-LocalGroupMember without orphaned-SID handling:** The cmdlet throws 0x80070534 and fails entirely when orphaned SIDs are present. Wrap in try/catch and fall back to WMI/ADSI or net localgroup for enumeration.
- **Remove-LocalUser without typed-count confirmation:** Local accounts have no Recycle Bin. The verb is irreversible. Always require typed-count confirmation even at count=1.
- **ChangePasswordAtLogon with SMARTCARD_REQUIRED:** These flags are incompatible. Smart card auth doesn't use passwords, so requiring a password change is meaningless and can cause errors.
- **Storing or logging SecureString passwords:** Never marshal SecureString to plaintext (no BSTR conversion). The audit writer must never receive the $Parameters hashtable containing passwords.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password generation | Get-Random or custom PRNG | [System.Security.Cryptography.RandomNumberGenerator] | Get-Random is not a CSPRNG; predictable output |
| Password complexity validation | Regex-only check | AD-side validation via Set-ADAccountPassword | Regex can't replicate full AD password policy (history, length, complexity, FGPP) |
| Local group enumeration | Get-LocalGroupMember raw | try/catch + WMI/ADSI fallback | Orphaned SIDs cause fatal 0x80070534 |
| Computer account reset | Reset-ComputerMachinePassword remotely | Set-ADAccountPassword -Reset (AD-side) + Test-ComputerSecureChannel -Repair (local) | Reset-ComputerMachinePassword only works locally; AD-side reset is the ADUC equivalent |
| Audit logging | Start-Transcript or Add-Content | Write-AdmanAudit (existing) | Transcript is unstructured, easily forgotten, mixes noise with signal |

**Key insight:** Custom solutions for password generation, local group enumeration, and computer account reset are worse than the built-in/cmdlet approaches because they miss edge cases (CSPRNG bias, orphaned SIDs, secure channel repair) that the platform handles correctly.

## Common Pitfalls

### Pitfall 1: New-ADUser "Create-Then-Fail" Password Complexity
**What goes wrong:** New-ADUser with -Enabled $true and -AccountPassword throws ADPasswordComplexityException when the password fails policy, BUT the user account is still created in a disabled state. The operator sees an error but the object exists.
**Why it happens:** The cmdlet creates the object first, then attempts to set the password. The password failure doesn't roll back the creation.
**How to avoid:** Either (a) create with -Enabled $false, then Set-ADAccountPassword, then Enable-ADAccount; or (b) wrap in try/catch and Remove-ADUser on ADPasswordComplexityException. D-01's single-call shape with a policy-compliant generated password avoids this entirely.
**Warning signs:** A "failed" user creation that leaves a disabled account in the OU.

### Pitfall 2: Unlock-ADAccount Against Non-PDCe DC
**What goes wrong:** Unlock-ADAccount appears to succeed but the user remains locked out, or locks again immediately.
**Why it happens:** The PDC Emulator is authoritative for bad-password processing and lockout state. Other DCs may have stale lockoutTime values under replication lag.
**How to avoid:** Always pin -Server to (Get-ADDomain).PDCEmulator for unlock operations. Read LockedOut first on the PDCe; no-op with a clear message when not locked.
**Warning signs:** Unlock "works" but the user locks again within minutes.

### Pitfall 3: Get-LocalGroupMember Orphaned SID Fatal Error
**What goes wrong:** Get-LocalGroupMember throws "Failed to compare two elements in the array" (0x80070534) and returns NOTHING when a local group contains orphaned SIDs.
**Why it happens:** Domain SIDs become unresolvable when a machine leaves the domain, but the cmdlet cannot handle unresolved entries during sorting.
**How to avoid:** Wrap Get-LocalGroupMember in try/catch. On 0x80070534, fall back to WMI (Win32_GroupUser) or ADSI to enumerate members, or use net localgroup to identify and remove orphaned entries.
**Warning signs:** Any local group membership query that fails entirely on a machine that was previously domain-joined.

### Pitfall 4: Remove-LocalUser Irreversibility
**What goes wrong:** A local user is deleted and cannot be recovered. No Recycle Bin, no quarantine OU, no tombstone.
**Why it happens:** Local SAM database has no soft-delete mechanism. The deletion is immediate and permanent.
**How to avoid:** Typed-count confirmation even at count=1 (D-03). Pre-delete state capture in the audit record (SID, name, group memberships, profile path). Help text states plainly: irreversible.
**Warning signs:** Any local user deletion without a pre-delete state snapshot.

### Pitfall 5: ChangePasswordAtLogon + SMARTCARD_REQUIRED Conflict
**What goes wrong:** New-ADUser or Set-ADUser fails when both ChangePasswordAtLogon and SmartcardLogonRequired are set.
**Why it happens:** SMARTCARD_REQUIRED forces certificate-based auth; the DC generates a random password hash. Requiring a password change is meaningless when passwords aren't used.
**How to avoid:** Never combine these flags. If smart card is required, don't set ChangePasswordAtLogon. The D-05 default (must-change=ON) applies only to password-based auth.
**Warning signs:** User creation fails with account control flag conflicts.

### Pitfall 6: sAMAccountName Length and Format
**What goes wrong:** New-ADUser fails or creates an account with a truncated/invalid sAMAccountName.
**Why it happens:** sAMAccountName has a fixed 20-character limit. Computer accounts conventionally have a trailing dollar sign (e.g., PC01$). The attribute must be unique and cannot contain certain special characters.
**How to avoid:** Validate sAMAccountName length <= 20 before calling New-ADUser. For computer accounts, ensure the trailing $ is present. The uniqueness pre-flight (D-01) catches collisions.
**Warning signs:** Creation fails with "attribute value too long" or duplicate sAMAccountName errors.

### Pitfall 7: Move-ADObject Destination Validation
**What goes wrong:** Move-ADObject -TargetPath moves an object to an OU outside the managed scope, bypassing SAFE-07.
**Why it happens:** The cmdlet doesn't validate the destination OU against any policy; it moves to any valid container.
**How to avoid:** Validate -TargetPath under managed roots before confirm (reuses D-01 parent-OU scope check). This is a safety invariant wired as a per-verb Parameters validator in the gate.
**Warning signs:** Objects appearing in OUs that shouldn't be managed.

## Code Examples

Verified patterns from official sources:

### New-ADUser with Enabled-at-Creation (D-01)
```powershell
# Source: Microsoft Learn + D-01 design
# Single-call shape with policy-compliant generated password
$securePassword = New-AdmanRandomPassword -Length 20  # CSPRNG, policy-compliant
New-ADUser -Name $Name `
    -SamAccountName $SamAccountName `
    -UserPrincipalName $UPN `
    -Path $ParentOuDn `
    -AccountPassword $securePassword `
    -Enabled $true `
    -ChangePasswordAtLogon $true `
    -Server $script:Config.DC `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Set-ADAccountPassword -Reset for Computer Account (COMP-04)
```powershell
# Source: Microsoft Learn
# AD-side "Reset Account" = ADUC semantics
Set-ADAccountPassword -Identity $ComputerDn -Reset -Server $script:Config.DC `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
# On-machine channel repair (runbook step, out-of-gate):
# Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
```

### Unlock-ADAccount Pinned to PDC Emulator (USER-05)
```powershell
# Source: Microsoft Learn + PITFALLS.md Pitfall 5
$pdc = (Get-ADDomain).PDCEmulator
# Read LockedOut first on the PDCe
$user = Get-ADUser -Identity $Identity -Server $pdc -Properties LockedOut
if (-not $user.LockedOut) {
    Write-Output "Account is not locked out."
    return
}
Unlock-ADAccount -Identity $Identity -Server $pdc `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Move-ADObject with Destination Validation (USER-06/COMP-03)
```powershell
# Source: Microsoft Learn + D-01 scope check pattern
$targetPath = $Parameters['TargetPath']
# Validate destination OU under managed roots BEFORE confirm
$normalizedTarget = ConvertTo-AdmanNormalizedDn -Dn $targetPath
$inScope = $false
foreach ($root in @($script:Config.ManagedOUs)) {
    $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
    if ($normalizedTarget -eq $r -or $normalizedTarget.EndsWith(',' + $r)) {
        $inScope = $true; break
    }
}
if (-not $inScope) { throw "TargetPath '$targetPath' is outside managed OU scope." }
Move-ADObject -Identity $Dn -TargetPath $targetPath -Server $script:Config.DC `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Local User Creation with Password (LUSR-01)
```powershell
# Source: Microsoft Learn
$securePassword = Read-Host -AsSecureString  # or New-AdmanRandomPassword
New-LocalUser -Name $Username -Password $securePassword `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Local Group Membership with Orphaned-SID Handling (LUSR-02)
```powershell
# Source: Microsoft Learn + GitHub PowerShell issue #2996
try {
    $members = Get-LocalGroupMember -Name 'Administrators' -ErrorAction Stop
} catch [System.ComponentModel.Win32Exception] {
    if ($_.Exception.NativeErrorCode -eq 0x534) {  # ERROR_NONE_MAPPED
        # Fall back to WMI for enumeration
        $members = Get-CimInstance -ClassName Win32_GroupUser |
            Where-Object { $_.GroupComponent.Name -eq 'Administrators' }
    } else { throw }
}
```

### Add-ADGroupMember with Dual Resolution (GRP-01)
```powershell
# Source: Microsoft Learn + D-04 design
Add-ADGroupMember -Identity $GroupDn -Members $MemberDn -Server $script:Config.DC `
    -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Pester 6 Mocking with -ModuleName
```powershell
# Source: Pester.dev migration guide + existing tests/Safety.GateOrder.Tests.ps1
Mock Resolve-AdmanTarget -ModuleName adman { $script:AdmanOrder.Add('resolve'); $t1 }
Mock Test-AdmanTargetAllowed -ModuleName adman { $script:AdmanOrder.Add('allow'); @{ Allowed = $true; Reason = '' } }
Should -Invoke Resolve-AdmanTarget -ModuleName adman -Times 1
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Get-WmiObject for local group enumeration | Get-LocalGroupMember / CIM | PS 3.0+ | Get-WmiObject removed in PS7; CIM is the cross-edition standard |
| Assert-MockCalled / Assert-VerifiableMock | Should -Invoke / Should -InvokeVerifiable | Pester 6.0.0 (2026-07) | Old commands removed; new assertion syntax required |
| New-ADUser without password pre-validation | Create disabled -> Set password -> Enable | Always | Avoids the create-then-fail landmine |
| Unlock-ADAccount against any DC | Pin to PDC Emulator | Always | PDCe is authoritative for lockout state |
| Reset-ComputerMachinePassword for all resets | Set-ADAccountPassword -Reset (AD-side) + Test-ComputerSecureChannel -Repair (local) | Always | Reset-ComputerMachinePassword only works locally |

**Deprecated/outdated:**
- `Get-WmiObject`: Removed in PS7; use CIM cmdlets
- `wmic.exe`: Being removed from Windows (Win11 25H2); use CIM/PowerShell
- `Assert-MockCalled` / `Assert-VerifiableMock`: Removed in Pester 6; use `Should -Invoke`
- `System.Web.Security.Membership]::GeneratePassword`: Desktop-only, dead on PS7; use CSPRNG

## Assumptions Log

> List all claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this
> section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | New-ADUser -Enabled $true with policy-compliant password succeeds in one call | Code Examples | If the generated password doesn't meet the domain's specific FGPP, creation fails and leaves a disabled user. Mitigation: D-05's generator enforces length + 4 classes; the planner should verify the domain's actual password policy. |
| A2 | Test-ComputerSecureChannel -Repair requires local admin rights on the target machine | Code Examples | If the operator doesn't have local admin, the repair fails. This is documented as a runbook step outside the gate. |
| A3 | The 76-char no-ambiguous alphabet from Spike 004 is acceptable to the domain's password policy | Standard Stack | If the domain requires specific character sets or excludes certain symbols, the generator may need adjustment. The spike validated on generic policy; specific FGPP may vary. |
| A4 | LocalAccounts cmdlets are available on all target Windows versions (5.1 baseline) | Standard Stack | The module is built-in on Win10 1809+/Server 2019+. Older versions may lack it. The project constraint already targets 5.1+. |
| A5 | Pester 6.0.0 stable is the correct version to target (not 6.1.0-alpha1) | Standard Stack | 6.1.0-alpha1 is a prerelease; 6.0.0 is the stable release. The project should use stable. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

## Open Questions

1. **FGPP (Fine-Grained Password Policy) interaction with generated passwords**
   - What we know: The Spike 004 generator produces 20-char passwords with 4 character classes. AD password policy can be customized via FGPP with different length/complexity requirements per group.
   - What's unclear: Whether the target domain has FGPPs that would reject the generated passwords (e.g., minimum length > 20, specific symbol requirements).
   - Recommendation: The planner should include a pre-flight check that reads the effective password policy for the target OU/user and validates the generated password against it before calling New-ADUser. If FGPP is detected, warn the operator.

2. **Local Administrators group membership check for D-02(b)**
   - What we know: D-02 requires refusing targets that are members of the local Administrators S-1-5-32-544 group where the action would weaken that protection boundary.
   - What's unclear: The exact mechanism for checking local group membership when Get-LocalGroupMember may fail on orphaned SIDs. Should the check use WMI/ADSI as primary, or try Get-LocalGroupMember first with fallback?
   - Recommendation: Use Get-LocalGroupMember with try/catch + WMI fallback (Win32_GroupUser). The check should be defensive: if enumeration fails entirely, refuse the action (fail-closed).

3. **Audit schema extension for `group` field and `MACHINE\username` target shape**
   - What we know: D-04 requires a `group` field alongside `target`. D-02 requires `MACHINE\username` + local SID in the target field.
   - What's unclear: The exact JSON schema for the extended audit record. Should `group` be a nested object (dn, sid, objectClass) like `targets`, or a flat string?
   - Recommendation: Keep `group` as a flat DN string for simplicity, matching the existing `target` field shape. The `targets` array already carries per-target detail. The no-secret-key regex test must be extended to cover the new fields.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ActiveDirectory module (RSAT) | All AD write verbs | ✓ | ships with Windows | Document prereq install |
| Microsoft.PowerShell.LocalAccounts | Local user/group verbs | ✓ | built-in 5.1/PS7 | — |
| Pester 6.0.0 | Unit/integration tests | ✓ | 6.0.0 | — |
| PSScriptAnalyzer 1.25.0 | Lint gate | ✓ | 1.25.0 | — |
| PSFramework 1.14.457 | Config + diagnostic logging | ✓ | 1.14.457 | — |
| PDC Emulator reachable | Unlock-ADAccount | ✓ | (Get-ADDomain).PDCEmulator | — |
| Local admin rights | LocalAccounts mutations | ✓ | Current user context | Prompt for elevation |

**Missing dependencies with no fallback:**
- None — all dependencies are either built-in or already adopted in Phase 0/1.

**Missing dependencies with fallback:**
- None.

## Validation Architecture

> Skip this section entirely if workflow.nyquist_validation is explicitly set to false in .planning/config.json. If the key is absent, treat as enabled.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Pester 6.0.0 |
| Config file | None — tests use `#Requires -Modules Pester` and standard Describe/It/Should |
| Quick run command | `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit` |
| Full suite command | `Invoke-Pester -Path tests/ -Tag Unit` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| USER-02 | Create user through gate with synthetic target | unit | `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| USER-03 | Disable/enable user through gate | unit | `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit` | ✅ (existing) |
| USER-04 | Reset password without echo/log | unit | `Invoke-Pester -Path tests/User.Password.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| USER-05 | Unlock pinned to PDCe | unit | `Invoke-Pester -Path tests/User.Unlock.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| USER-06 | Move user with destination validation | unit | `Invoke-Pester -Path tests/User.Move.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| LUSR-01 | Local user CRUD through local gate | unit | `Invoke-Pester -Path tests/Local.User.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| LUSR-02 | Local group membership | unit | `Invoke-Pester -Path tests/Local.Group.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| COMP-02 | Disable/enable computer | unit | `Invoke-Pester -Path tests/Computer.Disable.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| COMP-03 | Move computer | unit | `Invoke-Pester -Path tests/Computer.Move.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| COMP-04 | Reset computer account | unit | `Invoke-Pester -Path tests/Computer.Reset.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| GRP-01 | Add to group | unit | `Invoke-Pester -Path tests/Group.Add.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| GRP-02 | Remove from group | unit | `Invoke-Pester -Path tests/Group.Remove.Tests.ps1 -Tag Unit` | ❌ Wave 0 |
| GRP-03 | Refuse protected group add | unit | `Invoke-Pester -Path tests/Group.Protected.Tests.ps1 -Tag Unit` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `Invoke-Pester -Path tests/Safety.GateOrder.Tests.ps1 -Tag Unit`
- **Per wave merge:** `Invoke-Pester -Path tests/ -Tag Unit`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `tests/Safety.GateOrder.Tests.ps1` — extend for create path (D-01) and group matrix (D-04)
- [ ] `tests/Safety.Gate.Tests.ps1` — extend for local verb AST guard (D-02)
- [ ] `tests/Mocks/ActiveDirectory.psm1` — extend with local account mocks (Get-LocalUser, Get-LocalGroupMember, etc.)
- [ ] `tests/User.Create.Tests.ps1` — USER-02 create path tests
- [ ] `tests/User.Password.Tests.ps1` — USER-04 password reset tests
- [ ] `tests/User.Unlock.Tests.ps1` — USER-05 PDCe-pinned unlock tests
- [ ] `tests/User.Move.Tests.ps1` — USER-06 move validation tests
- [ ] `tests/Local.User.Tests.ps1` — LUSR-01 local user tests
- [ ] `tests/Local.Group.Tests.ps1` — LUSR-02 local group tests
- [ ] `tests/Computer.*.Tests.ps1` — COMP-02/03/04 tests
- [ ] `tests/Group.*.Tests.ps1` — GRP-01/02/03 tests
- [ ] `tests/Audit.Schema.Tests.ps1` — extended schema tests for group field + local target shape

## Security Domain

> Required when `security_enforcement` is enabled (absent = enabled). Omit only if explicitly `false` in config.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Pass-through by default; DPAPI-encrypted credential file on explicit remember-me; never store plaintext |
| V3 Session Management | no | N/A — console app, no web sessions |
| V4 Access Control | yes | Managed-OU scope (SAFE-07), deny-list (SAFE-05), protected-SID guard (SAFE-06), local RID-500 + Administrators guard (D-02) |
| V5 Input Validation | yes | Escape-AdmanAdFilterLiteral for -Filter strings; Escape-AdmanLdapFilterValue for -LDAPFilter; sAMAccountName length validation; Typed-count confirmation for destructive ops |
| V6 Cryptography | yes | CSPRNG password generation (RandomNumberGenerator); DPAPI for credential file; never log passwords |

### Known Threat Patterns for PowerShell AD Administration

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| LDAP injection via filter strings | Tampering | Escape-AdmanAdFilterLiteral / Escape-AdmanLdapFilterValue on all user-supplied values |
| Password complexity bypass | Elevation of Privilege | Generated passwords enforce length + 4 classes; prompt path validates same policy |
| Protected account modification | Elevation of Privilege | Recursive protected-group membership check (IN_CHAIN); direct SID equality for group-side (D-04) |
| Audit log tampering | Repudiation | Named mutex serialization; fail-closed PENDING write; separate ACL on audit path |
| Orphaned SID exploitation | Information Disclosure | Get-LocalGroupMember try/catch + WMI fallback; refuse closed on enumeration failure |
| SecureString plaintext marshaling | Information Disclosure | Never convert SecureString to BSTR; pass only to cmdlet parameters |
| sAMAccountName collision | Tampering | Uniqueness pre-flight (D-01); New-ADUser throws on collision |
| Move to out-of-scope OU | Elevation of Privilege | Move-ADObject -TargetPath validated under managed roots before confirm |

## Sources

### Primary (HIGH confidence)
- [Microsoft Learn — New-ADUser](https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser) — Parameters, behavior, examples
- [Microsoft Learn — Set-ADAccountPassword](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-adaccountpassword) — -Reset semantics, -NewPassword, -Server
- [Microsoft Learn — Unlock-ADAccount](https://learn.microsoft.com/en-us/powershell/module/activedirectory/unlock-adaccount) — -Server parameter, PDCe relevance
- [Microsoft Learn — Move-ADObject](https://learn.microsoft.com/en-us/powershell/module/activedirectory/move-adobject) — -TargetPath, cross-domain notes
- [Microsoft Learn — Add-ADGroupMember](https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember) — -Members ADPrincipal[] array
- [Microsoft Learn — New-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser) — Password/NoPassword parameter sets, -WhatIf support
- [Microsoft Learn — Set-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/set-localuser) — -Password SecureString, -WhatIf support
- [Microsoft Learn — Remove-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/remove-localuser) — -WhatIf support, irreversibility
- [Microsoft Learn — Disable-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/disable-localuser) — -WhatIf support
- [Microsoft Learn — Add-LocalGroupMember](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/add-localgroupmember) — -WhatIf support
- [Microsoft Learn — Get-LocalUser](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localuser) — SID property, LocalUser object shape
- [Microsoft Learn — Get-LocalGroupMember](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember) — Parameters, known issues
- [Microsoft Learn — Planning Operations Master Role Placement](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/planning-operations-master-role-placement) — PDC Emulator authoritative for password updates
- [Pester.dev — Migrating from v5 to v6](https://pester.dev/docs/v6/migrations/v5-to-v6) — Assert-MockCalled removal, Should -Invoke

### Secondary (MEDIUM confidence)
- [PowerShell Forums — New-ADUser password complexity exception not preventing creation](https://forums.powershell.org/t/new-aduser-password-complexity-exception-not-preventing-creation-of-user/17490) — Create-then-fail behavior confirmed
- [Spiceworks — New-ADUser password complexity error](https://community.spiceworks.com/t/new-aduser-password-complexity-error/555181) — User created disabled on password failure
- [GitHub PowerShell Issue #2996 — Get-LocalGroupMember orphaned SID](https://github.com/PowerShell/PowerShell/issues/2996) — 0x80070534 error, "Failed to compare two elements"
- [SS64 — Test-ComputerSecureChannel](https://ss64.com/ps/test-computersecurechannel.html) — -Repair parameter, credential requirements
- [TheITBros — sAMAccountName and UserPrincipalName](https://theitbros.com/samaccountname-and-userprincipalname/) — 20-character limit
- [ActiveDirectoryPro — UserAccountControl Attribute Values](https://activedirectorypro.com/useraccountcontrol-check-and-manage-attribute-value/) — SMARTCARD_REQUIRED 0x40000, flag conflicts
- [4sysops — Find AD accounts with ChangePasswordAtLogon](https://4sysops.com/archives/find-ad-accounts-with-changepasswordatlogon-set-and-enforce-password-change-with-powershell/) — ChangePasswordAtLogon + smartcard conflict
- [Adam the Automator — Fix Trust Relationship](https://adamtheautomator.com/the-trust-relationship-between-this-workstation-and-the-primary-domain-failed/) — Reset-ComputerMachinePassword local-only vs AD-side reset
- [Petri — Trust Relationship Error](https://petri.com/trust-relationship-between-this-workstation-and-the-primary-domain-failed-error/) — ADUC Reset Account server-side only

### Tertiary (LOW confidence)
- None — all critical claims verified against Microsoft Learn or cross-checked community sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All modules verified on PowerShell Gallery with current versions
- Architecture: HIGH — Patterns directly extend existing Phase 0/1 spine; D-01..D-05 validated against cmdlet documentation
- Pitfalls: HIGH — All pitfalls verified against Microsoft Learn, GitHub issues, or established community sources

**Research date:** 2026-07-15
**Valid until:** 2026-08-14 (30 days — stable domain, cmdlet surfaces change slowly)
