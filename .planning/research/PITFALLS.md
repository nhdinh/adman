# Pitfalls Research

**Domain:** Menu-driven PowerShell toolkit for on-prem Active Directory administration (user/computer lifecycle + remote ops), used by a small mixed-skill IT team
**Researched:** 2026-07-10
**Confidence:** HIGH (core AD/PowerShell semantics verified against Microsoft Docs / TechNet Wiki / AskDS / TechCommunity; specific default values and attribute names cross-checked)

> **Tooling note:** the `gsd-tools` research-plan/research-store seam is not installed in this environment (binary absent, not on PATH), so research was executed via the built-in `WebSearch` fallback provider (an allowed provider per tool strategy). Confidence tiers were classified directly per the source hierarchy: Microsoft-authored docs and protocol references = HIGH; long-established community sources cross-checked against Microsoft = HIGH/MEDIUM. Cached digests were therefore not written to the seam.

This file is the "what corrupts directories or locks admins out" reference. Every pitfall includes warning signs, prevention, and the build phase that should own it.

---

## Suggested phase skeleton (used by the "Phase to address" fields)

No roadmap exists yet (greenfield). These phase names are a recommendation for the roadmap author; pitfall mappings below reference them. The ordering is deliberate — safety harness before any write, read-only before writes, single-object before bulk, remoting isolated.

| Phase | Theme | Why here |
|-------|-------|----------|
| **Phase 0 — Foundation & Safety Harness** | Guardrails framework: `SupportsShouldProcess`/`-WhatIf` plumbing, confirmation, structured audit log, encrypted config, deny-list, managed-OU scoping, single-DC targeting helper, error-handling conventions | Must exist before *any* AD write is implemented. Everything depends on it. |
| **Phase 1 — AD Query & Reporting (read-only)** | Inventory, console/CSV/HTML reports, stale-object detection, lockout-source lookup, protected-object inventory | Read-only = lowest blast radius. Validates that the team/models correctly understand AD semantics (timestamps, replication, expired-vs-disabled) *before* acting on them. |
| **Phase 2 — Single-Object Lifecycle** | create / disable / enable / move OU / reset password / unlock / group membership (one object at a time) | Writes begin, but bounded to one object. Guardrails from Phase 0 are exercised on real mutations. |
| **Phase 3 — Remote Computer Operations** | WinRM → CIM(DCOM) → skip auto-detect; live actions; double-hop strategy | Remoting complexity (WinRM/DCOM/firewall/double-hop) is isolated so it doesn't destabilize the AD core. |
| **Phase 4 — Bulk & Workflows** | Bulk ops (preview + typed confirmation + max-count cap), onboarding, offboarding (disable+quarantine+strip groups) | Highest blast radius; only safe once single-object writes and guardrails are proven. |
| **Phase 5 — Hardening & Portability** | RSAT prerequisite check, PS 5.1/7.x compat, portability (workstation vs jump host), encrypted config backup/restore, docs/inline help | Cross-cutting polish and operational readiness. |

---

## Critical Pitfalls

### Pitfall 1: Mass-change via unfiltered pipeline (the "disable everyone" accident)

**What goes wrong:**
A command like `Get-ADUser -Filter * | Disable-ADAccount` (or `Set-ADUser`, `Move-ADObject`, `Remove-ADGroupMember`) runs against *every object in the domain*. The AD module's `-Filter *` returns the entire directory; the pipeline executes the verb for each object with no per-item abort on failure and no built-in blast-radius limit. A typo in `-Filter`, a wrong `-SearchBase`, or forgetting `-SearchBase` entirely turns a one-off task into a domain-wide outage: thousands of accounts disabled, every computer moved, group memberships stripped. This is the single most common catastrophic AD automation mistake and the reason this project's whole "safety property" exists.

**Why it happens:**
- `-Filter *` is the documented "give me everything" pattern; juniors copy it from examples.
- PowerShell pipelines are eager and per-item independent — one bad object doesn't stop the rest, and a too-wide filter isn't an error, it's just a large result set.
- `-SearchBase` is optional; omitting it searches the entire default naming context.
- AD cmdlets have `ConfirmImpact` that often sits *below* the default `$ConfirmPreference` (`High`), so `-Confirm` may not even prompt by default for a single object — and definitely doesn't reason about *count*.

**How to avoid:**
- **Never execute a verb pipeline directly against a query.** Always materialize the target set first, show it, gate on it:
  ```powershell
  $targets = Get-ADUser -Filter $Filter -SearchBase $ManagedOU -SearchScope Subtree -Properties $Needed
  # 1) Scope hardening (managed OU + deny-list + protected-object filter) — see Pitfalls 2 & 3
  $targets = $targets | Where-Object { Test-IsManagedObject $_ }   # central guard
  # 2) Preview
  $targets | Select-Object SamAccountName, DistinguishedName, Enabled | Format-Table -AutoSize
  # 3) Count cap
  if ($targets.Count -gt $MaxBulkCount) { throw "Refusing: $($targets.Count) targets exceeds cap $MaxBulkCount" }
  # 4) Typed confirmation for bulk
  if ($targets.Count -gt 1 -and (Read-Host "Type $($targets.Count) to proceed") -ne "$($targets.Count)") { throw "Aborted" }
  # 5) Act, still honoring -WhatIf, with per-item error capture
  $targets | Disable-ADAccount -WhatIf:$WhatIf -ErrorVariable +errs
  ```
- Default `-SearchBase` to the configured managed OU for *every* read and write; never search the domain root in the tool.
- Implement a central `Test-IsManagedObject`/`Assert-AllowedTarget` guard (managed-OU prefix on `DistinguishedName` AND not on deny-list AND not protected) that *every* verb calls before acting — one choke point, not scattered checks.
- Make bulk (>1 target) require a *typed* confirmation of the count plus a configurable `MaxBulkCount` cap; single-object uses normal confirmation.

**Warning signs:**
- Any code path that pipes `Get-AD*` straight into `Set-/Disable-/Move-/Remove-AD*` without an intervening variable + preview.
- `-SearchBase` absent, or computed from user input without a managed-OU anchor.
- A count that surprises the operator ("why is it about to touch 4,000 objects?"). Surface target count *before* confirm, always.
- Reports of "I only meant to do one OU" after a run.

**Phase to address:**
Phase 0 (the guardrails choke point, count cap, managed-OU default) and enforced again at Phase 4 (bulk preview + typed confirm). **No write verb may be merged in Phase 2 without routing through the guard.**

---

### Pitfall 2: Touching protected accounts / AdminSDHolder-protected objects

**What goes wrong:**
Built-in and privileged objects — `krbtgt`, `Guest`, built-in `Administrator`, Domain/Enterprise/Schema Admins members, Domain Controllers, service/gMSA accounts — are catastrophic to disable, move, or reset. Beyond the obvious, two subtle traps:
- **AdminSDHolder / SDProp reversion.** Objects transitively in protected groups are stamped by the AdminSDHolder template ACL: their DACL is reset and inheritance disabled by the SDProp process on the **PDC Emulator roughly every 60 minutes**. Any ACL/delegation change the tool makes on such an object is silently reverted within an hour — the operator thinks a change "worked" (it returned success) but it didn't persist. The object carries `adminCount=1` and inheritance-off.
- **Stale `adminCount` misidentification.** When an object is *removed* from a protected group, `adminCount` is **not** automatically cleared and inheritance is **not** re-enabled. So `adminCount=1` over-reports "currently protected": a former admin now in a normal OU still looks protected, and a stale-account or ACL routine either skips a valid target or (worse) a cleanup that "trusts" `adminCount=1` as proof of protection mishandles it. On modern Windows, protection is based on *transitive group membership*, not the `adminCount` bit alone.

**Why it happens:**
- Operators assume "the cmdlet returned success ⇒ the change persisted." SDProp reversion is invisible and delayed (up to 60 min), so it looks like a random later failure.
- `adminCount` is an intuitive but unreliable signal; people filter on it.
- Protected status is *transitive* (nested groups), so a naive `MemberOf` direct-membership check misses accounts protected via nesting.

**How to avoid:**
- Maintain a **startup-loaded deny-list** plus a **protected-object detector** that refuses the target *before* the verb runs:
  ```powershell
  # Well-known SIDs (domain-agnostic): 500 Administrator, 501 Guest, 502 krbtgt
  function Test-IsProtectedSid($obj) {
      $sid = [System.Security.Principal.SecurityIdentifier]$obj.SID
      $rid = $sid.Value.Split('-')[-1]
      return $rid -in '500','501','502'   # extend with 512/518/519 group RIDs as needed
  }
  # Transitive protected-group membership (use Get-ADGroupMember -Recursive against a protected-group list)
  # adminCount is a *hint*, not proof — combine with recursive group membership, never rely on it alone.
  ```
- Hard-refuse: built-in RIDs (500/501/502), members (recursive) of Domain Admins / Enterprise Admins / Schema Admins / Administrators, Domain Controllers (objectClass computer in the Domain Controllers OU / `primaryGroupID` 516), gMSA/service accounts (objectClass `msDS-GroupManagedServiceAccount`), and anything outside the managed OU.
- For ACL/delegation reporting in Phase 1, flag AdminSDHolder-protected objects and warn that SDProp may revert direct ACL edits — never let the tool "fix" ACLs on these.
- Treat `adminCount=1` as "investigate," not as ground truth; inventory stale `adminCount` accounts as a *reporting* item, not an action.

**Warning signs:**
- A change "works" but is gone an hour later (classic SDProp).
- `adminCount=1` on accounts that are no longer in any protected group (stale) — surface in Phase 1 inventory.
- Any write path whose protection check is a single direct-membership `MemberOf` test (misses nesting).
- Logs showing successful `Set-ADObject`/ACL edits against objects under the influence of AdminSDHolder.

**Phase to address:**
Phase 0 (deny-list + protected-object detector + recursive-membership check, wired into the central guard from Pitfall 1). Phase 1 surfaces stale `adminCount` and protected membership in reports. Baseline protection of `krbtgt`/`Guest`/`Administrator` confirmed as a v1 default per PROJECT.md "Key Decisions."

---

### Pitfall 3: `lastLogon` vs `lastLogonTimestamp` — misidentifying active accounts as stale

**What goes wrong:**
Stale-object cleanup that reads the wrong timestamp disables or quarantines accounts that are actually in use.
- `lastLogon` is **per-DC and not replicated**. Reading it from one DC tells you only when that *one* DC last authenticated the object. Querying a subset of DCs (missing a remote/site DC that actually serviced the logons) is a known real-world cause of deleting still-active accounts.
- `lastLogonTimestamp` (and its computed alias `LastLogonDate`) **is replicated**, but updates only when the prior value is "old enough": default threshold = 14 days minus a random 0–5 day factor, i.e. a **~9–14 day lag** (governed by `ms-DS-Logon-Time-Sync-Interval`). A value can look ~2 weeks stale even for a daily user.
- The **never-logged-on** edge case: value `0`/null converts with `[DateTime]::FromFileTime(0)` to **year 1601**, which naïvely sorts as "oldest → most stale" and gets purged first (including brand-new accounts that simply haven't logged on yet).

**Why it happens:**
- `LastLogonDate` looks authoritative and is easy (`Get-ADUser -Properties LastLogonDate`); people don't realize it's the coarse, lagged, replicated value.
- `-Properties` is required — `lastLogon*` are not returned by default, so a missing `-Properties` yields `$null` that a comparison treats as ancient.
- "90 days inactive" is treated as exact rather than "90 days + a ≥14-day buffer."

**How to avoid:**
- For stale detection (reporting/quarantine candidate), use `lastLogonTimestamp`/`LastLogonDate` **with a grace buffer ≥14 days** inside the threshold, and treat `0`/null/`1601` as a distinct "never logged on" bucket, not "infinitely stale":
  ```powershell
  $cutoff = (Get-Date).AddDays(-90)              # business rule
  $grace  = (Get-Date).AddDays(-(90 + 14))       # absorb replication lag
  Get-ADUser -SearchBase $ManagedOU -Filter {Enabled -eq $true} -Properties LastLogonDate, lastLogonTimestamp |
      Where-Object {
          if (-not $_.lastLogonTimestamp -or $_.lastLogonTimestamp -eq 0) { $never = $true }  # bucket separately
          else { [DateTime]::FromFileTime($_.lastLogonTimestamp) -lt $grace }
      }
  ```
- For an *exact* "last authentication anywhere" before a borderline disable/quarantine, aggregate `lastLogon` from **all** DCs and take the max — pin each query with `-Server`:
  ```powershell
  $latest = [datetime]::MinValue
  foreach ($dc in (Get-ADDomainController -Filter *).HostName) {
      try {
          $o = Get-ADUser $Sam -Server $dc -Properties LastLogon -ErrorAction Stop
          if ($o.LastLogon) { $t = [DateTime]::FromFileTime($o.LastLogon); if ($t -gt $latest) { $latest = $t } }
      } catch { Write-Warning "DC $dc unreadable: $_" }
  }
  ```
- Lifecycle, not blunt delete: detect → label/report → quarantine/disable (reversible) → archive. Surface "never logged on" as a separate report column.

**Warning signs:**
- Stale report contains accounts created within the last week, or shows year-1601 dates.
- Threshold acts at exactly N days with no grace buffer.
- Only one DC (or `Get-ADDomainController` not used) is ever queried for logon data.
- `-Properties` missing on the `Get-AD*` call (the attribute comes back `$null`).

**Phase to address:**
Phase 1 (read-only reporting is where the team proves it reads timestamps correctly, with the all-DC aggregation helper built once and reused). The quarantine *action* in Phase 4 consumes this logic but does not reimplement it.

---

### Pitfall 4: Disabled vs Expired vs Locked vs Password-Expired — four different states conflated

**What goes wrong:**
These are independent account states with different attributes, and treating them as one "can't log in" bucket produces wrong actions:
- **Disabled:** `userAccountControl` bit `ACCOUNTDISABLE` (`0x0002`) set → AD module `Enabled -eq $false`.
- **Expired:** `accountExpires` end date has passed. The account still shows **`Enabled -eq $true`** but cannot authenticate. A stale-cleanup filtered on `Enabled -eq $false` **misses expired accounts entirely**; conversely an "active accounts" report that trusts `Enabled -eq $true` **includes unusable expired accounts**.
- **Locked:** `lockoutTime > 0` (and within the lockout window) / computed `LockedOut`. Often transient and policy-driven; unlocking is a different, reversible action.
- **Password-expired / must-change:** `pwdLastSet = 0` ("change at next logon") or `msDS-User-Password-Expired` computed `true`, or a normal password age expiry. Distinct from the account being disabled.
- `userAccountControl` also carries `DONT_EXPIRE_PASSWORD` (`0x10000`), `SMARTCARD_REQUIRED` (`0x40000`), `PASSWORD_EXPIRED` (`0x800000`) — bit logic is easy to get wrong with raw `-band`/`-bor`; prefer the AD module's named properties (`Enabled`, `LockedOut`, `PasswordExpired`, `PasswordNeverExpires`) and `Search-ADAccount`.

**Why it happens:**
- `Enabled` is the most visible property; people assume `Enabled=$true` ⇒ "usable."
- Expiry is a *date* attribute, not a UAC bit, so it doesn't show up in a UAC-based filter.
- Raw `userAccountControl` bit math is error-prone and unreadable.

**How to avoid:**
- Use the dedicated helpers instead of hand-rolled filters:
  ```powershell
  Search-ADAccount -SearchBase $ManagedOU -AccountDisabled      # disabled
  Search-ADAccount -SearchBase $ManagedOU -AccountExpired       # expired (still Enabled=true!)
  Search-ADAccount -SearchBase $ManagedOU -LockedOut            # locked
  Search-ADAccount -SearchBase $ManagedOU -PasswordExpired      # password expired
  Search-ADAccount -SearchBase $ManagedOU -AccountExpiring -TimeSpan 30.00:00:00
  ```
- Report these as **separate columns/states**, never collapse to a single "inactive." Decide explicitly per workflow: offboarding disables (sets ACCOUNTDISABLE) regardless of expiry; "stale" detection must consider disabled *and* expired; unlock never touches disable/expiry state.
- If you must read UAC, use named flags and `-band` against constants, and always surface the *interpreted* state to the operator (don't show raw `514`/`66048`).

**Warning signs:**
- "Inactive users" report counts differ wildly depending on whether expiry is included.
- An expired contractor account (`Enabled=True`, can't log in) survives a "disabled stale accounts" sweep.
- Operators see raw `userAccountControl` integers in the TUI.
- Offboarding leaves an account `Enabled=True` because it was "already expired."

**Phase to address:**
Phase 1 (reporting must render Disabled/Expired/Locked/Password-Expired as distinct states). Phase 2 unlock/enable/disable/reset-password verbs each target exactly one state. Phase 4 offboarding explicitly sets disabled *and* records prior expiry/lock state for rollback.

---

### Pitfall 5: Account lockout — reading the wrong DC / wrong attribute

**What goes wrong:**
Lockout diagnostics lie because the relevant counters are **not replicated**:
- `badPwdCount`, `badPasswordTime`/`LastBadPasswordAttempt`, `lastLogon`, and `logonCount` are **per-DC and never replicate**. Querying one DC can show `badPwdCount = 0` while another holds the real count.
- The **PDC Emulator is authoritative** for bad-password processing: a DC that gets a bad password forwards to the PDCe, which increments the count and, at threshold, locks the account and logs **Event ID 4740**. The *locked state* (`lockoutTime`) **is replicated urgently**, but the *counters* are not.
- So a tool that checks lockout by reading one arbitrary DC (or only `LockedOut`/`lockoutTime`) will (a) miss where the bad attempts actually happened, and (b) report `badPwdCount=0`/no `LastBadPasswordAttempt` and conclude "not a password issue" when it is. Unlocking against a non-PDCe DC can also appear to "not work" transiently under replication lag.

**Why it happens:**
- `LockedOut`/`lockoutTime` are easy and replicated, so people stop there and never look at the per-DC counters.
- `Get-ADUser` without `-Server` hits "a" DC (often the nearest), not necessarily the PDCe or the DC that recorded the failures.
- The 4740 event lives on the PDCe; the *source* clues (logon type, process, source IP) live in 4625/4771/4776 on the *caller* machine — two hops of evidence.

**How to avoid:**
- Always resolve and prefer the PDCe for lockout writes/unlocks, and query counters **per DC** when diagnosing:
  ```powershell
  $pdc = (Get-ADDomain).PDCEmulator
  Get-ADDomainController -Filter * | ForEach-Object {
      Get-ADUser $Sam -Server $_.HostName -Properties LockedOut,LockoutTime,BadPwdCount,LastBadPasswordAttempt |
          Select-Object @{n='DC';e={$_.HostName}}, LockedOut, LockoutTime, BadPwdCount, LastBadPasswordAttempt
  }
  # Source of lockout: 4740 on the PDCe (Caller Computer Name), then 4625/4771/4776 on that caller
  ```
- Perform `Unlock-ADAccount` against the PDCe (`-Server $pdc`); the lock clears and replicates urgently.
- Treat "locked out but badPwdCount 0 everywhere" as a signal to check replication health / PDCe reachability / whether the role was seized, not as "no problem."
- Distinguish **unlock** (clear `lockoutTime`) from **reset password** from **enable** — three different verbs; never bundle them implicitly.

**Warning signs:**
- `badPwdCount = 0` reported for a user everyone agrees is locking out.
- Unlock "works" but the user locks again within minutes (the *source* on the caller machine was never found).
- Lockout investigation never touches the PDCe or reads Security logs.
- The tool reads lockout state from whatever DC `-Server` defaulted to.

**Phase to address:**
Phase 1 (lockout-source reporting: per-DC counter aggregation + 4740 lookup) and Phase 2 (unlock verb pinned to PDCe). The per-DC query helper is shared with Pitfall 3's logon aggregation.

---

### Pitfall 6: Replication & read-after-write inconsistency (acting on stale reads)

**What goes wrong:**
AD is multi-master with replication latency. A write on one DC is not instantly visible on others. A tool that writes to DC-A and immediately reads/acts from DC-B (the default when `-Server` isn't pinned) can:
- Move an object, then immediately group-modify it and fail because DC-B still sees it at the old DN.
- Disable an account, then report it still enabled.
- Reset a password against a non-PDCe DC and have the user unable to log on at a site that hasn't replicated yet (password changes are *urgently* replicated to the PDCe, but not necessarily to every site instantly).
- In a bulk loop, each `Get-AD*` may hit a different DC than the prior `Set-AD*`, producing "flapping" success/failure.

**Why it happens:**
- The AD module picks a DC per call (via DC Locator) unless `-Server` is given; two adjacent calls can land on different DCs.
- Operators test on a single-DC lab where replication is instant, then hit multi-DC production where it isn't.

**How to avoid:**
- **Pin the server for a whole operation sequence** — choose one DC (commonly the PDCe for password/lockout-sensitive ops) and pass `-Server` to *every* `Get-/Set-/Move-/New-/Remove-AD*` in that sequence. Build a small helper so the pin can't be forgotten:
  ```powershell
  $DC = (Get-ADDomain).PDCEmulator
  Get-ADUser $Sam -Server $DC | Set-ADUser -Server $DC -Enabled $false -PassThru |
      Move-ADObject -Server $DC -TargetPath $QuarantineOU
  ```
- For password resets and lockouts, target the **PDC Emulator** explicitly.
- After a write, re-read from the **same** DC to confirm (read-your-writes), not from "any" DC.
- Be explicit in reports about *which* DC the data came from when consistency matters.

**Warning signs:**
- Intermittent "object not found" or "attribute still old" immediately after a successful write.
- Flapping results in bulk loops (same object alternates pass/fail).
- Password resets that "don't take" at remote sites for a few minutes.
- No `-Server` anywhere in write code paths.

**Phase to address:**
Phase 0 (the single-DC-targeting helper and the rule that every AD call in a sequence carries `-Server`). Exercised in Phase 2 (single-object writes) and critical in Phase 4 (bulk, where flapping would otherwise appear).

---

### Pitfall 7: Recycle Bin assumptions — the safety net that isn't there

**What goes wrong:**
The project defines "delete = disable + quarantine" (reversible by design), which is correct — but accidents and *out-of-tool* deletions still happen, and recovery depends on the AD Recycle Bin, which has sharp edges:
- Recycle Bin requires **forest functional level 2008 R2 or higher** and must be explicitly enabled (`Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet`). On an older/never-enabled forest, a hard delete is *tombstoned* (most attributes stripped, including group memberships) — restore is painful/authoritative.
- Enabling it is **one-way / irreversible** (`IsDisableable: False`) and, critically, **immediately deletes all existing tombstones**. So you must never enable it *after* an accidental deletion hoping to recover — recover first, then enable.
- Two lifetimes matter: `msDS-DeletedObjectLifetime` (default **180 days**, fully restorable, memberships intact) and `tombstoneLifetime` (default **180 days**, 60 on very old forests) before garbage collection. Outside those windows the object is gone.
- `Restore-ADObject` fails if the original parent OU is gone (restore the OU first, then children) or if a conflicting UPN/DN now exists.

**Why it happens:**
- "We have a recycle bin" is assumed; nobody verified `Get-ADOptionalFeature ... EnabledScopes` is populated.
- People think enabling the Recycle Bin is a recovery *step* rather than a *prerequisite* — enabling after the fact wipes the very tombstones they needed.
- Quarantine-by-disable is treated as "delete is solved," ignoring that other admins/scripts can still hard-delete.

**How to avoid:**
- Phase 0/1 **preflight check**: read `Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"' | Select EnabledScopes`, FFL (`Get-ADForest`), and the two lifetimes; *report* the recovery posture (enabled? lifetimes?) in the TUI and at startup. If disabled, warn that any out-of-tool hard delete is tombstone-only.
- Keep the v1 design: **the tool never hard-deletes** — disable + move to quarantine OU + strip groups, always reversible. Make quarantine its own first-class workflow with a "restore from quarantine" reverse path.
- Document the real (Recycle Bin) restore procedure as a runbook for out-of-tool accidents: restore parent OU before children, resolve UPN/DN conflicts, mind the lifetime windows.
- Never offer an "enable Recycle Bin now" button as a recovery action.

**Warning signs:**
- `EnabledScopes` empty for the Recycle Bin feature, or FFL below 2008 R2.
- A quarantine workflow with no reverse/restore path.
- Any code path or doc that calls `Remove-ADObject` (without `-Recursive` accidents) as "cleanup."
- Operators conflating "in quarantine OU" (fully intact) with "recoverable from Recycle Bin."

**Phase to address:**
Phase 0/1 preflight + reporting of recovery posture. Phase 4 implements quarantine-with-restore and the hard rule that the tool never hard-deletes (aligns with PROJECT.md "Out of Scope: hard-delete"). Phase 5 documents the out-of-tool recovery runbook.

---

### Pitfall 8: The double-hop — remoting works, then the second hop silently loses credentials

**What goes wrong:**
The tool runs on a workstation/jump host, connects via PSRemoting to a target (or to a DC/management server) — **hop 1 works** — but any action *inside* that remote session that reaches a *second* network resource (another computer, a file share, the AD module calling a DC) fails with `Access is denied` / `0x8009030e` / the target seeing `NT AUTHORITY\ANONYMOUS LOGON`. This is by-design Kerberos: the first-hop server validated you but never received your password/TGT, so it has nothing to authenticate to the second hop with. Symptom in this tool: a remote query that then tries to read `\\server\c$`, query WMI on a *third* host, or run AD cmdlets from the jump box fails only when remoted, working fine interactively — leading to the wrong diagnosis ("firewall", "permissions").

**Why it happens:**
- It works on the operator's machine (single hop) and breaks only when the same logic runs inside a remote session — looks environmental.
- "Pass `-Credential`" fixes hop 1 but not hop 2; credentials don't traverse automatically.
- CredSSP is the tempting "just make it work" fix, but it ships *reusable* credentials to the hop server (theft risk if that host is compromised) and is disabled by default.

**How to avoid (in preference order):**
1. **Avoid the second hop entirely where possible** — run AD cmdlets from the workstation directly against the DC (the AD module remotes to AD Web Services on the DC itself; don't *also* nest that inside a remote session). Keep remote ops to *local-on-target* queries (CIM/registry/process on that one host) that don't need to reach a third machine.
2. **Resource-Based Kerberos Constrained Delegation (RBCD)** for WinRM→file/SQL hops (configured on the *destination* to trust the intermediary). Caveat: classic/RBCD delegation generally does **not** carry a WinRM→WinRM hop to a *third* machine; it suits WinRM→SMB/SQL. WinRM caches failed Kerberos ~15 min — `klist purge -LI 0x3e7` after changes.
3. **JEA / RunAs session configuration** on the intermediary (`RunAsVirtualAccount` or `-RunAsCredential`, scope allowed commands) so the connecting user never needs credentials on the hop host.
4. **Explicit credentials inside the script block** (`$using:cred`) for one-offs.
5. **CredSSP only as a last resort** on tightly trusted paths (`Enable-WSManCredSSP -Role Client/Server`, `-Authentication CredSSP`). Never for accounts flagged *"Account is sensitive and cannot be delegated"* — those cannot be delegated at all.

Surface the choice explicitly in the tool's remoting design rather than letting it "sort of work."

**Warning signs:**
- "Works on my machine, fails through the menu/remote" — the signature of a double-hop.
- `ANONYMOUS LOGON` in target Security logs, or `0x8009030e`.
- A remote action that reads a share/DC/third host failing while local-only remote actions succeed.
- Anyone proposing CredSSP as the default. Delegation failing specifically for sensitive/delegation-protected accounts.

**Phase to address:**
Phase 3 (remote operations). Decide the double-hop strategy up front (prefer "no second hop" + RBCD/JEA), document it, and design remote actions to be local-on-target. Phase 5 hardening verifies the delegation model on real hosts.

---

### Pitfall 9: WinRM vs CIM/DCOM transport and firewall reality

**What goes wrong:**
The project mandates auto-detect **WinRM → CIM → skip**, but "CIM" is not a single transport and the fallback is easy to get wrong:
- **WinRM/WSMan:** TCP **5985** (HTTP) / **5986** (HTTPS), single port, firewall-friendly. `New-CimSession`/`Invoke-CimMethod` **default to WSMAN** for remote targets.
- **DCOM (classic WMI, `Get-WmiObject`):** RPC Endpoint Mapper **135** + a **dynamic RPC port range** — painful through host firewalls; the classic symptom is **`0x800706BA` / "RPC server is unavailable."** `Get-WmiObject` is DCOM-only and effectively deprecated.
- The trap: "fall back from WinRM to CIM" but `Get-CimInstance` was *already* using WSMAN (WinRM) by default — so the "fallback" uses the same blocked transport and fails identically, while the operator thinks they degraded to "CIM/WMI." A true DCOM fallback requires `New-CimSessionOption -Protocol Dcom` and the DCOM firewall rules (135 + dynamic range) that often *aren't* open either.

**Why it happens:**
- "CIM = WMI = DCOM" is a common mental model; in reality CIM remotes over WSMAN by default.
- DCOM's dynamic range is hard to pin to firewall rules, so DCOM fallback frequently also fails — and the tool reports "skip" after two failures that had the same root cause (firewall), wasting time.
- Per-host retries with long timeouts make the menu feel hung.

**How to avoid:**
- Probe transport explicitly and cheaply per host, with short timeouts, and remember the result per session:
  ```powershell
  function Test-RemoteTransport($Computer) {
      if (Test-WSMan -ComputerName $Computer -ErrorAction SilentlyContinue) { return 'WSMAN' }
      try {
          $opt = New-CimSessionOption -Protocol Dcom
          $s = New-CimSession -ComputerName $Computer -SessionOption $opt -OperationTimeoutSec 5 -ErrorAction Stop
          $s | Remove-CimSession; return 'DCOM'
      } catch { return 'Skip' }
  }
  ```
- Use **CIM cmdlets** (not `Get-WmiObject`) for inventory; choose WSMAN by default, only use `-Protocol Dcom` when the probe says WSMAN is unavailable *and* DCOM is reachable.
- Cache per-host transport results for the session; never re-probe every call. Cap timeouts so a dead host costs seconds, not minutes.
- Treat "Skip" as a first-class, non-error outcome in reports (host unreachable/offline), distinct from an actual failure.

**Warning signs:**
- WinRM fails and "CIM fallback" fails with the same WSMAN error (because it *was* WSMAN).
- `0x800706BA` RPC errors on the DCOM path.
- Menu hangs for ~minutes on batches of offline hosts (no timeout cap / no caching).
- Reports mixing "offline" hosts with "error" hosts.

**Phase to address:**
Phase 3 (remote operations): implement the explicit transport probe + caching + short timeouts and the WSMAN/DCOM distinction. Phase 1 inventory reuses the same transport layer for read-only queries.

---

### Pitfall 10: PowerShell error handling — the script "succeeds" while silently half-failing

**What goes wrong:**
PowerShell's defaults are hostile to "stop on first problem" safety:
- `$ErrorActionPreference` defaults to **`Continue`**: non-terminating errors print and execution **keeps going**. A sequence like `disable → move → strip groups` can have the *disable fail* and still run the move and group-strip on the original (wrong) state — the user looks disabled-ish/in the wrong OU, and the operator sees only a red line scroll by.
- `try/catch` **does not catch non-terminating errors** (e.g., `Get-ADUser` not-found with default behavior, `Write-Error`, most per-item AD cmdlet failures). The single most common "my try/catch doesn't work" cause. You must escalate with `-ErrorAction Stop` (per call) or `$ErrorActionPreference = 'Stop'` (scope).
- In **advanced functions** (`[CmdletBinding()]`), an escalated error stays **statement-terminating** — the *next statement still runs* — unlike a plain script where it becomes script-terminating. So even with `-ErrorAction Stop`, the very next line in an advanced function can execute unless you structure around it.
- `$?` is unreliable with cmdlets (it's meaningful for native/exe and `$LASTEXITCODE`); pipelines swallow per-item failures; `2>$null` only hides redirection, not `ErrorRecord`s.
- `-ErrorVariable` appends with `+errs`; without it you lose which objects failed in a bulk run.

**Why it happens:**
- Defaults favor interactive convenience ("keep going"), not safety-critical batch ("stop and report").
- The terminating vs non-terminating distinction is non-obvious; `catch {}` looking like it "handles everything" is the trap.
- Advanced-function statement-terminating behavior is a subtle, late-discovered gotcha.

**How to avoid (project-wide convention, set in Phase 0):**
- Set `$ErrorActionPreference = 'Stop'` at script/module scope **and** pass `-ErrorAction Stop` on individual AD calls whose success the next step depends on.
- Wrap write operations in `try/catch/finally`; on failure, log to the audit log with the target DN, the operation, the `ErrorRecord`, and *do not* proceed to subsequent steps for that target:
  ```powershell
  $ErrorActionPreference = 'Stop'
  foreach ($t in $targets) {
      try {
          Disable-ADAccount -Identity $t.DistinguishedName -Server $DC -ErrorAction Stop -WhatIf:$WhatIf
          Write-Audit -Action 'Disable' -Target $t.DistinguishedName -Result 'OK'
      } catch {
          Write-Audit -Action 'Disable' -Target $t.DistinguishedName -Result 'FAIL' -Error $_
          Write-Warning "Failed $($t.SamAccountName): $_"
          continue   # do NOT fall through to move/strip for this target
      }
  }
  ```
- Capture per-item errors with `-ErrorVariable +errs` in bulk; summarize failures at the end (count + which DNs), never let a red scroll be the only record.
- Don't rely on `$?` for cmdlet success; use `try/catch` with `-ErrorAction Stop` and/or check the returned object.
- Make destructive helper functions advanced functions with `[CmdletBinding(SupportsShouldProcess)]` so `-WhatIf`/`-Confirm` flow through (Pitfall 11), and remember the statement-terminating caveat — `return`/throw explicitly after handling.

**Warning signs:**
- Red text in the console but the run "completed" and the audit log says success.
- A multi-step workflow where a later step ran on an object whose earlier step failed.
- `try/catch` present but `-ErrorAction Stop` absent on the calls inside it.
- Bulk runs that report total attempted but not per-target pass/fail.

**Phase to address:**
Phase 0 (error-handling conventions + audit-log-on-failure + the rule that dependent steps don't run after a failure). Enforced by code review for every write verb in Phase 2 and bulk in Phase 4.

---

### Pitfall 11: `-WhatIf` theater — dry-run exists in name but doesn't actually guard

**What goes wrong:**
The tool advertises dry-run, but it's inconsistent or bypassable:
- Custom functions don't declare `[CmdletBinding(SupportsShouldProcess)]` and don't call `$PSCmdlet.ShouldProcess()`, so `-WhatIf` is accepted but ignored (the action still runs).
- Some verbs call the AD cmdlet directly (which *does* support `-WhatIf`) while others go through a helper that silently drops it — dry-run "works" for disable but not for group-strip or move.
- `$WhatIfPreference` set globally (e.g., in a profile) makes *reads* or the tool's own internal writes no-op unexpectedly.
- `ConfirmImpact` of custom functions is left at the default `Medium`, below `$ConfirmPreference High`, so `-Confirm` never prompts even for destructive ops — operators get no prompt and assume `-WhatIf` is their only safety net.
- A "preview" shown to the operator is computed by a *different* code path than the one that executes, so the preview and the action diverge (preview shows 3 targets, action runs on 300).

**Why it happens:**
- `SupportsShouldProcess` is opt-in and boilerplate-heavy; easy to skip on "internal" helpers.
- `-WhatIf` is a switch that's trivially dropped across a function boundary.
- Preview and execute are written as two near-duplicate blocks that drift apart.

**How to avoid:**
- One execution path used for **both preview and execute**: the same target list is shown and then acted upon (preview = "what the execute loop will receive"), never a separate query:
  ```powershell
  function Invoke-AdmanDisable {
      [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
      param([Parameter(Mandatory,ValueFromPipeline)]$Targets)
      process {
          foreach ($t in $Targets) {
              Assert-AllowedTarget $t   # Pitfalls 1 & 2 guard — runs in BOTH -WhatIf and real mode
              if ($PSCmdlet.ShouldProcess($t.DistinguishedName, 'Disable-ADAccount')) {
                  Disable-ADAccount -Identity $t.DistinguishedName -Server $DC -ErrorAction Stop
              }
          }
      }
  }
  ```
- Set `ConfirmImpact='High'` on every destructive function so confirmation actually triggers under the default `$ConfirmPreference`.
- Guardrails (deny-list, managed-OU, protected-object, count cap) run **inside** the same function, in both `-WhatIf` and real mode — a target that would be refused is refused in preview too, so the preview is truthful.
- Audit-log the `-WhatIf` run as a dry-run (who/what/when + the target list) so previews are themselves traceable.
- Never set `$WhatIfPreference` globally; pass `-WhatIf` explicitly per call.

**Warning signs:**
- `-WhatIf` run and a real run show different target counts.
- A destructive helper with no `[CmdletBinding(SupportsShouldProcess)]` or no `ShouldProcess` call.
- `-Confirm` never prompts even with nothing specified (ConfirmImpact too low).
- Dry-run that prints a message but still mutates AD.

**Phase to address:**
Phase 0 (the ShouldProcess function template + ConfirmImpact standard + preview==execute invariant + audit-logging of dry-runs). Every Phase 2/4 verb is built from this template; CI/review rejects any write function lacking `SupportsShouldProcess`.

---

### Pitfall 12: No who-did-what audit trail (and a writable log)

**What goes wrong:**
When something breaks at 02:00, there is no reliable record of *who* ran *what* against *which objects* and *when* (and whether it was a dry-run). The AD module does not audit at the tool level; `Start-Transcript` is easily forgotten, stored locally, and mixes noise with signal. Worse, if the log is a plain file the operator can edit, it isn't trustworthy for the very disputes it's meant to settle. Without this, the project's core safety promise ("every destructive action … written to an audit log") is false, and blame/recovery becomes guesswork.

**Why it happens:**
- Auditing is treated as "nice to have / later," then never retrofitted consistently across verbs.
- Transcripts feel sufficient until you need structured query ("show me every disable by alice last week").
- Logs go to a world-writable path with no rotation/integrity.

**How to avoid:**
- Structured, append-only audit log written by the **central guard/execution wrapper** (so no verb can forget it): one record per action with `timestamp, user (DOMAIN\user), host, dry-run(bool), operation, target DN, target count, parameters (sanitized, NO passwords), result, error`. JSONL or CSV; easy to query:
  ```powershell
  function Write-Audit {
      param([string]$Action,[string]$Target,[string]$Result,$Error,[switch]$DryRun,[int]$Count=1)
      [pscustomobject]@{
          ts=(Get-Date).ToString('o'); user="$env:USERDOMAIN\$env:USERNAME"; host=$env:COMPUTERNAME
          dryrun=[bool]$DryRun; action=$Action; target=$Target; count=$Count; result=$Result
          error=($Error | Out-String).Trim()
      } | ConvertTo-Json -Compress | Add-Content -Path $AuditPath -Encoding UTF8
  }
  ```
- Emit the **same** record for dry-runs (`dryrun=true`) and real runs; include the *previewed target list* for bulk.
- Store on a path the operators can read but not silently rewrite (separate ACL; consider writing to a central share/forwarding to Windows Event Log as a tamper-evident mirror for v1.x). Rotate by date; never log credentials or password-reset values.
- Fail closed: if the audit log cannot be written, **refuse the destructive action** rather than run unaudited — logging is part of the safety property, not optional.

**Warning signs:**
- A destructive code path that returns without calling `Write-Audit`.
- Audit entries missing `dryrun`, `target`, or `result` fields.
- Log file editable by the same account that runs the tool with no separate control.
- "We think alice ran it" answered by guessing instead of querying the log.

**Phase to address:**
Phase 0 (audit helper + fail-closed behavior + dry-run logging), wired into the central wrapper so Phase 2 and Phase 4 verbs inherit it automatically. Phase 5 adds tamper-evidence/forwarding and rotation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reading `Enabled` only and ignoring `accountExpires`/lock/password-expired | Simpler filters, faster v1 | Misses expired-but-enabled accounts in stale sweeps; wrong offboarding decisions | Never for any action logic; only OK in a *labeled* rough report |
| Hand-rolled `userAccountControl` bit math | No dependency on `Search-ADAccount` | Unreadable, wrong flag combos, mishandles computed bits | Never — use named properties / `Search-ADAccount` |
| Querying a single DC for logon/lockout data | Less code, faster | Misidentifies active accounts as stale; wrong lockout source | Acceptable *only* for coarse stale reports with ≥14d buffer; never for pre-action verification |
| Omitting `-Server` on AD calls | Shorter commands | Read-after-write flapping; acting on stale replicas | Never in write sequences; OK only for one-off read-only lookups |
| `$ErrorActionPreference='Continue'` + no `-ErrorAction Stop` | Scripts "don't crash" | Half-completed workflows, silent partial changes, false "success" | Never for write paths |
| CredSSP everywhere to "fix" remoting | Double-hop just works | Reusable credentials exposed on hop hosts; theft risk | Never as default; only on tightly trusted, documented paths |
| Skipping `SupportsShouldProcess` on "internal" helpers | Less boilerplate | Dry-run bypassed for those verbs; preview lies | Never for any function that mutates AD |
| Logging to a local world-writable text file | Easy to start | Tamperable, not queryable, no integrity | Only as a temporary scaffold in Phase 0; replace before Phase 2 |
| Treating `adminCount=1` as proof of protection | Simple filter | Mishandles stale-protected accounts; misses nesting | Never — use recursive protected-group membership |
| Long/default remoting timeouts, no per-host cache | Simpler loops | Menu hangs minutes on offline hosts; re-probes every call | Never beyond a quick prototype |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| **ActiveDirectory module (RSAT)** | Assuming it's present; bundling it; calling cmdlets before import | Pre-flight `Import-Module ActiveDirectory` with a clear prerequisite error; document RSAT install (Windows Features / `Add-WindowsCapability` / Server Manager); don't bundle |
| **AD Web Services (ADWS) on DC** | Forgetting the AD module talks to ADWS on a DC (default 9389); "no DC" errors misread as module bugs | Ensure at least one DC runs ADWS; pin `-Server` to a healthy DC; surface the chosen DC |
| **PDC Emulator role** | Doing password resets/lockouts against any DC | Resolve `(Get-ADDomain).PDCEmulator` and target it for password/lockout-sensitive ops |
| **WinRM / WSMan (5985/5986)** | Assuming enabled everywhere; long timeouts | Probe with `Test-WSMan`; short timeouts; cache per-host; degrade gracefully |
| **CIM over DCOM (135 + dynamic RPC)** | Treating "CIM fallback" as DCOM when it's still WSMAN | Default CIM to WSMAN; only use `New-CimSessionOption -Protocol Dcom` when WSMAN fails *and* DCOM is reachable |
| **AD Recycle Bin / `Restore-ADObject`** | Assuming recovery is always possible; enabling it *after* a deletion | Pre-flight report of `EnabledScopes`/FFL/lifetimes; restore parent OU before children; never enable post-incident |
| **Group Policy / GPO** | Trying to author GPOs (out of scope) | Read/report at most in v1; do not write |
| **Exchange / home-dir / mailbox cleanup** | Bundling into offboarding (out of scope) | Surface as a *checklist* only in offboarding; don't automate |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `Get-AD* -Filter *` over the whole domain (no `-SearchBase`) | Slow queries, huge result sets, mass-change risk | Always set `-SearchBase` to managed OU; request only needed `-Properties` | Large domains / anytime `-SearchBase` is omitted |
| Requesting all `-Properties *` | Memory bloat, slow serialization | Specify exact `-Properties` list (e.g., `LastLogonDate,Enabled,MemberOf`) | Reports over thousands of objects |
| No paging on big queries (`-ResultPageSize`) | Truncated/incomplete large results | Use `-ResultPageSize 1000` (and `-ResultSetSize` only when you truly want a cap) | Result sets > page size |
| Re-probing remote transport per host, no cache | Menu hangs, repeated timeouts | Cache transport result per session; cap `-OperationTimeoutSec` | Batches with many offline hosts |
| Per-item DC re-resolution in bulk loops | Flapping, inconsistent reads | Pin `-Server` once per sequence; reuse | Multi-DC sites under replication lag |
| Aggregating `lastLogon` from all DCs for *every* object in a big report | Very slow reports | Reserve all-DC aggregation for single borderline pre-action checks; use `lastLogonTimestamp` for bulk stale scans | Large reports using per-DC logon |
| Building HTML reports by string concatenation | Memory/perf + injection risk | Use `ConvertTo-Html` / a templating step; encode values | Large inventories |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing credentials in plaintext config | Credential theft from the config file | Encrypt config (DPAPI / `ConvertFrom-SecureString`); never persist plaintext; align with PROJECT.md "MUST BE encrypted" |
| Running the whole tool as a standing Domain Admin | Over-broad blast radius; every mistake is DA-powered | Pass-through logged-in admin; least-privilege delegation to the managed OU; prompt for creds only if rights insufficient |
| CredSSP as default remoting auth | Reusable credentials exposed on hop hosts | Prefer no-second-hop + RBCD/JEA; CredSSP only on trusted, documented paths |
| Delegation to accounts marked "sensitive and cannot be delegated" | Silent delegation failure (looks like random auth errors) | Detect the flag; route such accounts to no-delegation paths |
| Editing ACLs on AdminSDHolder-protected objects | Changes reverted by SDProp within ~60 min; false sense of fix | Refuse/warn on protected objects; never "repair" their ACLs |
| Logging passwords / reset values / full credentials | Secret exposure via the audit log | Sanitize parameters; log that a reset occurred, never the value |
| Audit log writable by the operator | Tampering undermines the whole audit promise | Separate ACL / forward to a tamper-evident sink; fail-closed if unwritable |
| Hard delete offered anywhere ("cleanup") | Irreversible object loss, esp. without Recycle Bin | Tool never hard-deletes; disable+quarantine only |
| Trusting `adminCount=1` as protection proof | Mishandling stale-protected accounts | Use recursive protected-group membership; treat `adminCount` as a hint |
| Acting outside the managed OU (no scope check) | Domain-wide blast radius | Central guard enforces managed-OU prefix on `DistinguishedName` for every verb |

## UX Pitfalls (menu/TUI for mixed-skill team)

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Raw AD jargon in prompts ("userAccountControl 514", "DistinguishedName") | Juniors can't tell safe from dangerous | Plain-language summaries: "Disable jdoe (currently enabled), move to Quarantine" |
| Destructive and safe actions look identical | Muscle-memory mistakes | Visually distinct, always-previewed, typed-confirm for bulk; dry-run is the default first view |
| Preview computed separately from execution | "It showed 3, it did 300" | One target list used for both preview and execute |
| Errors dumped as raw red `ErrorRecord` stacks | Operators can't tell if it worked | Per-target OK/FAIL summary + count; details in audit log; never rely on scrollback |
| "Skip" (offline host) shown the same as "error" | False alarms / missed real failures | Distinct states: OK / Skipped-unreachable / Failed |
| No indication which DC / transport was used | Hard to diagnose flapping/slowness | Show pinned DC and chosen transport in verbose/status output |
| Bulk with no count cap or typed confirm | One mis-click → domain-wide change | Show count, require typing the count, enforce `MaxBulkCount` |
| Silent success with no audit confirmation | "Did it actually do anything?" | Confirm completion and point to the audit entry/report |

## "Looks Done But Isn't" Checklist

- [ ] **Dry-run:** `-WhatIf` honored on *every* destructive verb including helpers — verify by running a bulk `-WhatIf` and confirming AD is unchanged *and* the audit log records a dry-run.
- [ ] **Preview == execute:** the previewed target list is byte-for-byte the list passed to the execute loop (same variable, not a re-query).
- [ ] **Managed-OU scoping:** every read/write sets `-SearchBase` and the central guard rejects DNs outside the managed OU — test with a deliberately out-of-scope target.
- [ ] **Protected-object refusal:** `krbtgt`, built-in `Administrator` (RID 500), `Guest` (501), a Domain Admin (incl. via *nested* group), a DC, and a gMSA are all refused — test each, including nesting.
- [ ] **Stale-object logic:** never-logged-on (`0`/1601) bucketed separately; threshold includes ≥14-day grace buffer; `-Properties` actually requests the timestamp.
- [ ] **Expired vs disabled:** an `accountExpires`-passed but `Enabled=True` account is correctly classified — verify it's not missed by stale logic and not treated as fully "active."
- [ ] **Lockout source:** per-DC `badPwdCount`/`LastBadPasswordAttempt` queried; unlock pinned to PDCe; 4740 lookup path exists.
- [ ] **Single-DC sequences:** every write sequence pins `-Server`; re-read confirms against the same DC.
- [ ] **Remoting fallback:** transport probe distinguishes WSMAN vs DCOM; results cached per session; offline hosts = "Skip," capped timeouts; double-hop strategy documented and tested.
- [ ] **Error handling:** `$ErrorActionPreference='Stop'` + `-ErrorAction Stop` on dependent calls; a forced mid-workflow failure does *not* run later steps for that target and is audit-logged as FAIL.
- [ ] **Audit log:** structured record per action (who/what/when/dry-run/target/count/result); fail-closed if unwritable; never contains passwords.
- [ ] **Recovery posture:** startup preflight reports Recycle Bin `EnabledScopes`, FFL, and the two lifetimes; quarantine has a working reverse/restore path.
- [ ] **Config encryption:** config file is encrypted at rest; no plaintext credentials anywhere; backup/restore tested.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Mass disable/move from unfiltered pipeline | HIGH | Stop immediately; from audit log get exact target list + prior state; re-enable/move back in reverse, pinned to one DC; verify against a recent backup/Replica; for true hard-deletes use Recycle Bin `Restore-ADObject` (parent OU first) or authoritative restore |
| Protected object modified / ACL reverted by SDProp | MEDIUM | Re-apply within the model (don't fight SDProp on ACLs); if membership changed, fix group membership and wait one SDProp cycle (≤60 min) or trigger `RunProtectAdminGroupsTask`; review AdminSDHolder ACL for tampering (Event 5136) |
| Active account quarantined as "stale" (timestamp misread) | LOW–MEDIUM | Reverse from quarantine (re-enable, move back, restore groups) — the disable+quarantine design is reversible precisely for this; fix the threshold/buffer and re-run detection |
| Hard-deleted object with no Recycle Bin | HIGH | Authoritative restore from backup, or tombstone reanimation (attributes/memberships largely lost); going forward enable Recycle Bin *before* it's needed |
| Locked-out admin / lockout storm | MEDIUM | Find PDCe, read 4740 → caller → 4625/4771/4776 for source (service/RDP/script); `Unlock-ADAccount -Server $pdc`; remediate the source (cached creds, scheduled task, service account) |
| Double-hop action silently failed | LOW | Re-run with correct delegation (RBCD/JEA/`$using:cred`) or remove the second hop; `klist purge -LI 0x3e7` if Kerberos cache poisoned |
| Half-completed workflow (error default `Continue`) | MEDIUM | Use audit log to find which targets completed which steps; finish/roll back per target deliberately; fix error handling before re-running |
| Audit log missing/tampered | HIGH | Cross-reference DC Security logs (5136/4740/4732/4724/4723) and AD replication metadata (`repadmin /showobjmeta`) to reconstruct; restore log integrity controls (fail-closed) |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Unfiltered mass-change pipeline | Phase 0 (guard/cap), enforced Phase 4 | Bulk `-WhatIf` shows truthful count; out-of-scope target refused; count cap trips |
| 2. Protected accounts / AdminSDHolder | Phase 0; surfaced Phase 1 | RID 500/501/502, nested DA, DC, gMSA all refused; stale `adminCount` reported |
| 3. lastLogon vs lastLogonTimestamp | Phase 1 (logic), consumed Phase 4 | 1601 bucketed; ≥14d buffer; all-DC aggregation used only pre-action |
| 4. Disabled vs Expired vs Locked vs Pwd-Expired | Phase 1 (states), Phase 2 (verbs) | Each state rendered distinctly; `Search-ADAccount` used; expiry not missed |
| 5. Lockout wrong-DC/attribute | Phase 1 (diag), Phase 2 (unlock) | Per-DC counters shown; unlock pinned to PDCe; 4740 path works |
| 6. Replication / read-after-write | Phase 0 (`-Server` helper), Phase 2/4 | Forced stale-read test passes; no flapping in bulk |
| 7. Recycle Bin assumptions | Phase 0/1 (preflight), Phase 4 (quarantine) | Startup reports recovery posture; quarantine restore works; no hard-delete path exists |
| 8. Double-hop | Phase 3 | Remote→second-resource action works by design (or is eliminated); no CredSSP default |
| 9. WinRM/CIM/DCOM transport | Phase 3 (used Phase 1) | Probe distinguishes WSMAN/DCOM; caching + timeouts; offline = Skip |
| 10. PS error handling | Phase 0 (conventions), enforced Phase 2/4 | Forced mid-workflow failure stops later steps + logs FAIL |
| 11. `-WhatIf` theater | Phase 0 (template), all write phases | `-WhatIf` changes nothing + logs dry-run; preview==execute |
| 12. Audit gap / writable log | Phase 0 (helper+fail-closed), Phase 5 (hardening) | Every action logged structured; unwritable log blocks action; no secrets logged |

## Sources

**Microsoft / authoritative (HIGH confidence):**
- [about_Error_Handling (PowerShell-Docs)](https://github.com/MicrosoftDocs/PowerShell-Docs/blob/main/reference/7.6/Microsoft.PowerShell.Core/About/about_Error_Handling.md) — `$ErrorActionPreference` default `Continue`; non-terminating errors not caught by `try/catch`; `-ErrorAction Stop` escalation; advanced-function statement-terminating caveat
- [TechNet Wiki — LastLogon / LastLogonTimeStamp / LastLogonDate](https://social.technet.microsoft.com/wiki/contents/articles/22461.understanding-the-ad-account-attributes-lastlogon-lastlogontimestamp-and-lastlogondate.aspx) — per-DC vs replicated; `ms-DS-Logon-Time-Sync-Interval`; `LastLogonDate` is computed alias
- [AskDS — The AD Recycle Bin](https://techcommunity.microsoft.com/blog/askds/the-ad-recycle-bin-understanding-implementing-best-practices-and-troubleshooting/396944) — FFL 2008 R2; irreversible enable; enable wipes existing tombstones; lifetime attributes
- [TechCommunity — Five common questions about AdminSdHolder and SDProp](https://techcommunity.microsoft.com/t5/ask-the-directory-services-team/five-common-questions-about-adminsdholder-and-sdprop/ba-p/396293) — PDCe-only re-stamp; `adminCount` not sufficient alone; `AdminSDProtectFrequency`; `RunProtectAdminGroupsTask`
- Microsoft Learn — `about_Functions_CmdletBindingAttribute` / `SupportsShouldProcess`, `about_Preference_Variables` (`$WhatIfPreference`, `$ConfirmPreference`) (ShouldProcess / ConfirmImpact semantics)

**Established community / cross-checked (HIGH–MEDIUM):**
- [Adam the Automator — PowerShell Double-Hop fix](https://adamtheautomator.com/powershell-double-hop-fix/) and [4sysops — CredSSP second-hop](https://4sysops.com/archives/using-credssp-for-second-hop-powershell-remoting/) — double-hop cause and the CredSSP/RBCD/JEA/`$using:cred` options, RBCD WinRM→WinRM caveat, sensitive-and-cannot-be-delegated
- [TechTarget — Avoid the double-hop problem](https://www.techtarget.com/searchwindowsserver/tutorial/How-to-avoid-the-double-hop-problem-with-PowerShell)
- [Petri — Setting up the AD Recycle Bin (WS2008 R2)](https://petri.com/setting-up-active-directory-recycle-bin/) — `IsDisableable: False`, `RequiredForestMode: Windows2008R2Forest`; and [Restore Deleted Items](https://petri.com/active-directory-recycle-bin/) — `msDS-DeletedObjectLifetime`/`tombstoneLifetime`, `Restore-ADObject`
- [windows-active-directory.com — Disabled vs Expired vs Locked](https://www.windows-active-directory.com/difference-between-disabled-expired-and-locked-account.html) — distinct account states; expiry vs UAC disable
- [ServerFault — why badPwdCount/lastLogon are non-replicated](https://serverfault.com/questions/1105503/why-the-badpwdcount-last-logon-last-logoff-are-non-replicated) and [WOSHub — identify lockout source](https://woshub.com/troubleshooting-identify-source-of-active-directory-account-lockouts/) — per-DC counters, PDCe authoritative, Event 4740, LockoutStatus.exe
- [Progress — Get-CimInstance vs Get-WmiObject](https://www.progress.com/blogs/get-ciminstance-vs-get-wmiobject-whats-the-difference) and [SS64 — New-CimSessionOption](https://ss64.com/ps/new-cimsessionoption.html) — CIM defaults to WSMAN; `-Protocol Dcom` for DCOM; WinRM 5985/5986; DCOM RPC/135 + dynamic range (`0x800706BA`)

---
*Pitfalls research for: on-prem AD PowerShell administration toolkit (adman)*
*Researched: 2026-07-10*
