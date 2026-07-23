# Phase 2: Single-Object Lifecycle (writes begin) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 02-single-object-lifecycle-writes-begin-bounded-to-one
**Areas discussed:** Creates through the gate, Local-user verbs: scope + target model, Group-membership policy model, Password sourcing UX

---

## Creates through the gate (USER-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing gate | Synthetic pre-create target (parent OU + proposed CN/sAM) through the existing pipeline; uniqueness pre-flight refuses closed; New-ADUser added to ValidateSet + wrapper + drift-test | ✓ |
| Sibling creation gate | Parallel Invoke-AdmanCreation pipeline reusing confirm/audit primitives; existing gate untouched; SAFE-08 wording amended | |
| Two-phase create | Create-disabled minimal path, then enable/set-attrs as separate gated mutations; multi-prompt UX, fragmented audit | |
| Parent-OU as target | Resolve the parent OU as the target; smallest delta but audit names the OU, not the new user | |

**User's choice:** Extend existing gate
**Notes:** Recommended by advisor research. Deciding factors: SAFE-08 single funnel + SAFE-10 preview≡execute — the synthetic target's intended DN flows through confirm, PENDING, write, OUTCOME so the audit names the created object truthfully. Research correction recorded: v1 has no computer-create requirement (COMP-01 was Phase 1 read-only), so the path serves USER-02 only.

---

## Local-user verbs: scope + target model (LUSR-01/02)

| Option | Description | Selected |
|--------|-------------|----------|
| Sibling local gate + future-proof verbs | Transport-agnostic Public verbs (-ComputerName validated to localhost in Phase 2) + sibling Invoke-AdmanLocalMutation with local-target policy (local RID-500, S-1-5-32-544, machine-in-scope via AD computer object); Phase 3 widens validation, signatures never break | ✓ |
| Localhost-only, minimal | No -ComputerName at all; remote re-scoped into Phase 3, signatures reopen then | |
| Minimal Invoke-Command now | Rejected — violates remoting-quarantine sequencing, hangs on dead hosts | |
| Extend AD gate with local branch | Not recommended — pollutes the AD gate's fixed order with a second object model | |

**User's choice:** Sibling local gate + future-proof verbs

### Follow-up: Remove-LocalUser treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Typed-confirm + state audit | Typed-count confirmation even at count=1 + pre-delete state (SID, name, memberships, profile path) in audit for manual re-creation; help flags irreversibility | ✓ |
| Standard y/n confirm only | Same as any single-object verb; mistyped target unrecoverable | |
| Exclude remove from Phase 2 | LUSR-01 ships partial; remove deferred | |

**User's choice:** Typed-confirm + state audit
**Notes:** Research verified on PS 5.1.26100 that all LocalAccounts cmdlets declare SupportsShouldProcess — the original premise that they lack -WhatIf was wrong; truthful preview works through wrappers. Local accounts have no Recycle-Bin equivalent, so SAFE-09's reversible-delete mechanism can't apply; the typed-confirm + state-audit treatment preserves its spirit.

---

## Group-membership policy model (GRP-01/02/03)

| Option | Description | Selected |
|--------|-------------|----------|
| Dual-resolution matrix + asymmetric add/remove | Gate resolves both sides; member keeps existing 4 checks; group gets own-SID-not-protected (GRP-03 enforcement, direct SID equality) + not-deny-listed + not-gMSA; no managed-OU scope on groups (opt-in safety.requireManagedGroupOU default false); add=strict, remove-from-protected=allowed remediation; audit gains group field | ✓ |
| Member-as-target only | New verb-conditional group test bolted on; smaller delta, no reusable two-object pattern | |
| Matrix, group scope required by default | Only if all managed groups already live inside managed OUs | |
| Refuse protected-group removal too | Symmetric strictness; Tier-0 cleanup happens outside the tool | |

**User's choice:** Dual-resolution matrix + asymmetric add/remove
**Notes:** Key research finding: existing check (d) asks "is the target a recursive member of a protected group" — GRP-03 asks "is the group itself protected", answered by direct SID equality against $script:ProtectedSIDs, not IN_CHAIN. Group-as-target was rejected outright (breaks SAFE-07 — protected groups live in CN=Users/Builtin outside managed OUs — and leaves the member side unchecked).

---

## Password sourcing UX (USER-02/04)

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid, Generate default | security.passwordSource = Generate\|Prompt\|Ask, default Generate (Spike 004 recipe, length 20); prompt path enforces identical complexity policy; must-change ON by default | ✓ |
| Generate-only | Always generate, display once behind Press-Enter-to-clear, must-change forced ON | |
| Prompt-only | Masked twice-entry + runtime complexity validator; juniors pick weak passwords | |
| Hybrid, must-change OFF default | Only if helpdesk requires persistent admin-known passwords | |

**User's choice:** Hybrid, Generate default
**Notes:** Spike 004 verified in-repo (VALIDATED: RandomNumberGenerator + rejection sampling + Fisher-Yates, 76-char no-ambiguous alphabet, dual-edition PASS). Audit writer verified to never receive the $Parameters hashtable; schema test enforces a no-secret-key regex. Clipboard handoff disqualified (worse secret store, breaks over remoting/Server Core). Condition recorded: prompt path MUST enforce the same complexity policy as the generator or it is a policy bypass.

---

## Claude's Discretion

- Menu organization for writes (recommended: grouped flat menu with section separators; B/Q contract + thin dispatch unchanged; two-level acceptable fallback)
- Computer-account reset shape (COMP-04): AD-side Set-ADAccountPassword -Reset with default machine password (in-gate) + Test-ComputerSecureChannel -Repair guidance (on-machine, runbook)
- PDCe-pinned unlock mechanism (per-verb -Server override; reads LockedOut first)
- Move destination validation wired as per-verb Parameters validator (safety invariant, not optional)
- Exact Public verb names (locked in FunctionsToExport)

## Deferred Ideas

- Remote local-user ops (real -ComputerName) — Phase 3 transport ladder
- Two-level menu / hotkeys — post-Phase-2 stabilization
- New-ADComputer / group creation verbs — not in v1
- Per-DC lastLogon forensic unlock diagnostics — PDCe-only reads in v1
- Clipboard password handoff — rejected
- Symmetric protected-group refusal — rejected (remediation must stay possible)
- safety.requireManagedGroupOU default-true — config opt-in for shops that manage group OUs
- JEA/RBCD delegation — Phase 3/5 territory
