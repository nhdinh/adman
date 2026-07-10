# Phase 0: Foundation & Safety Harness - Pattern Map

**Mapped:** 2026-07-10
**Files analyzed:** 30 (planned, greenfield)
**Analogs found:** 0 / 30 in existing code — **GREENFIELD**. Source of truth = `00-RESEARCH.md` Patterns 1–7.

## Greenfield Banner (read first)

There is **no existing application code** to copy from. Verified:
- `Glob **/*.{ps1,psm1,psd1}` over the whole repo → **0 files**.
- Repo contents = `.planning/` docs + `.claude/CLAUDE.md` + empty gitignored `.store/` + `.gitignore` (already ignores `.store/` → CONF-05).
- The design spec is `.planning/research/{STACK,ARCHITECTURE,PITFALLS,SUMMARY,FEATURES}.md` + this phase's `00-RESEARCH.md`.

Therefore the "Closest Analog" column is inverted: each planned file maps to the **canonical mechanism** in `00-RESEARCH.md` (the load-bearing patterns the researcher corroborated at HIGH confidence). The planner copies **concrete identifiers, signatures, parameter blocks, and sequencing** from the cited `00-RESEARCH.md` line ranges — NOT from a non-existent sibling file. Where `00-RESEARCH.md` gives a full function body, that body is the reference implementation to lift and adapt.

**Hard rules inherited from `.claude/CLAUDE.md` "What NOT to Use" (apply to every file):**
- PowerShell **5.1 language subset**; full cmdlet names + **named params only** (no aliases/positional — lint `PSAvoidUsingCmdletAliases`).
- **No** `Get-WmiObject` / `wmic.exe` (CIM only). **No** `Export-Clixml -EncryptionKey` (PS7-only). **No** `Invoke-Expression` / dynamic cmdlet names in `Public/`.
- Every state-changing function: `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` + `$PSCmdlet.ShouldProcess(...)` (lint `PSUseShouldProcessForStateChangingFunctions`).
- `ConvertTo-Json` **always** with explicit `-Depth` (≥5); on 5.1 `ConvertFrom-Json` has **no `-AsHashtable`** (read as `PSCustomObject`, index by property).
- Match identity by **`objectSid`/RID, never `sAMAccountName`**; never trust `adminCount`; DN scope checks are **component-boundary-anchored** (no substring).

---

## File Classification

| New/Modified File | Role | Data Flow | Source of Truth (`00-RESEARCH.md`) | Match |
|-------------------|------|-----------|------------------------------------|-------|
| `adman.psd1` | manifest | module-load | §Recommended Project Structure L194–L198; §Standard Stack L89–L98 | greenfield |
| `adman.psm1` | root module (loader + export + run init) | module-load | §System Architecture Diagram L157–L188; L198 | greenfield |
| `Public/Initialize-Adman.ps1` | Public exported orchestration | startup / request-response | §Arch Responsibility Map L73–L85; L159–L170 | greenfield |
| `Public/Test-AdmanCapability.ps1` | Public exported probe | probe / request-response | Pattern 7 L475–L507 (body L489–L506) | greenfield |
| `Public/Config/Get-AdmanConfig.ps1` | Public exported config verb | config CRUD / file-I/O | D-01/D-04 L14,L17; §Don't Hand-Roll L521–L528 | greenfield |
| `Public/Config/Set-AdmanConfig.ps1` | Public exported config verb | config CRUD / file-I/O | D-01/D-04; Pitfall 7 L570–L574 | greenfield |
| `Public/Config/Export-AdmanConfig.ps1` | Public exported config verb | config file-I/O | L117–L130; `Export-PSFConfig -Path` | greenfield |
| `Public/Config/Import-AdmanConfig.ps1` | Public exported config verb | config file-I/O | `Import-PSFConfig -Path`; Pitfall 7 L570–L574 | greenfield |
| `Private/Safety/Invoke-AdmanMutation.ps1` | **Private GATE (non-exported)** | CRUD write + ordered sequence | **Pattern 1 L231–L304 (body L247–L273)** | greenfield |
| `Private/Safety/Resolve-AdmanTarget.ps1` | Private resolver (shared preview/execute) | read | **Pattern 2 L306–L322 (body L311–L318)** | greenfield |
| `Private/Safety/Test-AdmanTargetAllowed.ps1` | Private policy (scope+deny+protected) | policy / transform | Pattern 3 L324–L369; Pitfall 5 L558–L561 | greenfield |
| `Private/Safety/Confirm-AdmanAction.ps1` | Private confirmation | request-response (UI) | **Pattern 6 L451–L473 (body L456–L470)** | greenfield |
| `Private/Safety/Assert-AdmanBulkPolicy.ps1` | Private cap placeholder (Phase 4 enforces) | policy | D-07 L20; §Arch Diagram L181 | greenfield |
| `Private/Safety/Get-AdmanProtectedIdentity.ps1` | Private startup SID resolver | read / startup | **Pattern 3 startup L329–L345** | greenfield |
| `Private/Safety/AdmanWriteVerbs.ps1` | Private allow-list data | config | Pattern 1 L251–L253 (ValidateSet); SAFE-09 | greenfield |
| `Private/Audit/Write-AdmanAudit.ps1` | Private synchronous audit writer | file-I/O append (write-ahead) | **Pattern 4 L371–L415 (body L376–L412)** | greenfield |
| `Private/Config/Initialize-AdmanConfig.ps1` | Private config load/validate/seed | config / file-I/O | D-01/D-04/D-05; Pitfall 7,8 L570–L579 | greenfield |
| `Private/Foundation/Get-AdmanCredential.ps1` | Private credential decision | DPAPI file-I/O + prompt | **Pattern 5 L417–L449 (body L424–L446)** | greenfield |
| `Private/Foundation/Resolve-AdmanDomainSid.ps1` | Private SID helper | read / startup | Pattern 3 L330–L333 (DomainSID + forest-root) | greenfield |
| `Private/AD/Adman.AD.Write.ps1` | Private raw write wrappers (gate-only) | CRUD write (the ONE caller) | Pattern 1 L271; SAFE-09 allow-list L251–L253 | greenfield |
| `config/adman.defaults.json` | shipped defaults / schema source-of-truth | config | D-04/D-05; L222 | greenfield |
| `config/adman.schema.json` | shared schema (wizard + loader) | config | D-04 L17 (one schema, two entry points) | greenfield |
| `.store/config.example.json` | shipped annotated example | config | D-04 L17 (`_comment` keys, not JSONC) | greenfield |
| `tests/PesterConfiguration.psd1` | test config | config | §Validation Architecture L685–L692; Wave 0 L720 | greenfield |
| `tests/Safety.Gate.Tests.ps1` | test (AST guard SAFE-08/09) | static analysis | **Pattern 1 guard L279–L302 (+ caveat L304)** | greenfield |
| `tests/Safety.WhatIf.Integration.Tests.ps1` | test (integration SAFE-01/10) | integration | Pattern 2 L322; Test Map L703,L712 | greenfield |
| `tests/Safety.Protected.Tests.ps1` | test (SAFE-06) | unit+integration | Pattern 3; Test Map L708 | greenfield |
| `tests/Audit.FailClosed.Tests.ps1` | test (SAFE-04 pre-write throw⇒refusal) | unit (mock FileStream) | Pattern 4; Test Map L706 | greenfield |
| `tests/Mocks/ActiveDirectory.psm1` | test mock module | test infra | Wave 0 L725; Test Map note L714 | greenfield |
| `PSScriptAnalyzerSettings.psd1` | lint settings | config | CLAUDE.md L76; Wave 0 L726 | greenfield |
| `rules/AdmanSafetyRules.psm1` | custom PSSA rule (SAFE-08) | static analysis | Pattern 1 caveat L304; Wave 0 L727 | greenfield |

**Remaining test files** (full enumeration in `00-RESEARCH.md` Test Map L694–L712 — implement per that table; each maps to one REQ and reuses the patterns below): `Foundation.Capability.Tests.ps1` (→Pattern 7), `Config.Load/FailClosed/RoundTrip/NoSecrets.Tests.ps1` (→Initialize-AdmanConfig + Pattern 4 schema), `Credential.Dpapi/PassThrough.Tests.ps1` (→Pattern 5), `Safety.Confirm.Tests.ps1` (→Pattern 6), `Safety.DenyList.Tests.ps1` (→Pattern 3 deny-list branch L356–L358), `Safety.Scope.Tests.ps1` (→Pitfall 5 DN matrix L558–L561), `Safety.NoHardDelete.Tests.ps1` (→SAFE-09 banned list L283–L286), `Safety.PreviewEqualsExecute.Tests.ps1` (→Pattern 2 L319), `Audit.Schema.Tests.ps1` (→Pattern 4 record shape L385–L393).

---

## Pattern Assignments

### `Private/Safety/Invoke-AdmanMutation.ps1` (Private GATE — non-exported; ordered write sequence)

**Source of truth:** `00-RESEARCH.md` Pattern 1, **L231–L304** (signature L247–L273). This is THE load-bearing file — the only function allowed to call AD write cmdlets.

**Signature / param block to copy (L248–L257):**
```powershell
function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateSet('Disable-ADAccount','Enable-ADAccount','Move-ADObject',
            'Set-ADUser','Set-ADComputer','Set-ADAccountPassword','Unlock-ADAccount',
            'Add-ADGroupMember','Remove-ADGroupMember')]   # SAFE-09: Remove-ADObject deliberately ABSENT
        [string]$Verb,
        [Parameter(Mandatory)][string[]]$Targets,
        [hashtable]$Parameters = @{}
    )
```

**Core ordered pipeline to copy (L258–L272) — do not reorder:**
```powershell
$cid = [guid]::NewGuid().ToString()
$resolved = Resolve-AdmanTarget -Targets $Targets                       # SAFE-10: ONE resolver
foreach ($t in $resolved) {
    $decision = Test-AdmanTargetAllowed -Object $t                       # SAFE-05/06/07
    if (-not $decision.Allowed) {
        Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' -Reason $decision.Reason
        continue
    }
}
Assert-AdmanBulkPolicy -Count $resolved.Count                            # cap (Phase 4) + threshold
Confirm-AdmanAction -Verb $Verb -Targets $resolved -CorrelationId $cid   # SAFE-02 (+ShouldProcess)
Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $resolved -Result 'PENDING' -WhatIf:$WhatIfPreference
# ^ Write-AdmanAudit THROWS on PENDING-write failure → SAFE-04 refusal happens BEFORE the write below
& "Adman.AD.Write.$Verb" -Objects $resolved @Parameters -WhatIf:$WhatIfPreference -Confirm:$false
Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $resolved -Result 'Success' -WhatIf:$WhatIfPreference
```

**Critical sequencing rules (must hold):**
- Resolve → Allow → Bulk-policy → **Audit PENDING (throw on failure)** → Confirm → Execute (the only real write) → Audit OUTCOME.
- Inner write runs with `-WhatIf:$WhatIfPreference -Confirm:$false` (no per-object re-prompt — confirmation already happened once at the gate).
- The `ValidateSet` is the SAFE-09 boundary: `Remove-ADObject` (hard delete) is **never** in it.

---

### `Private/Safety/Resolve-AdmanTarget.ps1` (Private resolver — shared by preview AND execute; SAFE-10)

**Source of truth:** `00-RESEARCH.md` Pattern 2, **L306–L322** (body L311–L318).

**Core pattern to copy (L311–L318):**
```powershell
function Resolve-AdmanTarget {
    param([Parameter(Mandatory)][string[]]$Targets)
    foreach ($id in $Targets) {
        # scoped read: -SearchBase always set, exact -Properties, -Server pinned (Pitfall 1/6)
        Get-ADObject -Identity $id -Server $script:Config.DC `
            -Properties objectSid,objectClass,DistinguishedName,memberOf -ErrorAction Stop
    }
}
```

**Invariant to preserve (L319–L322):** BOTH the `-WhatIf` preview and the execute loop consume this exact same array — no re-query between preview and execute. Pester asserts the preview array is reference/count-equal to the execute array, and the operator-visible count equals `$resolved.Count`. Always pin `-Server $script:Config.DC`, always set `-SearchBase`, request exact `-Properties`.

---

### `Private/Safety/Test-AdmanTargetAllowed.ps1` (Private policy — scope SAFE-07 + deny SAFE-05 + protected SAFE-06)

**Source of truth:** `00-RESEARCH.md` Pattern 3, **L324–L369** (check-time body L349–L366); scope anchoring Pitfall 5 L558–L561.

**Core pattern to copy (L349–L366):**
```powershell
function Test-AdmanProtectedAccount {
    param([Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADObject]$Object)
    # (a) gMSA / legacy sMSA pre-filter — precise refusal reason, run FIRST (D-02)
    if ($Object.objectClass -contains 'msDS-GroupManagedServiceAccount' -or
        $Object.objectClass -contains 'msDS-ManagedServiceAccount') {
        return @{ Protected = $true; Reason = 'gMSA/service account (objectClass)' }
    }
    # (b) flat deny-list by SID/RID — the hard floor (D-05); match objectSid, never sAMAccountName
    $rid = ([System.Security.Principal.SecurityIdentifier]$Object.objectSid).Value.Split('-')[-1]
    if ($rid -in $script:DenyRids) { return @{ Protected = $true; Reason = "deny-listed RID $rid" } }
    # (c) recursive protected-group membership — single IN_CHAIN query over all protected groups
    $or = ($script:ProtectedGroupDns | ForEach-Object {
        "(memberOf:1.2.840.113556.1.4.1941:=$_)" }) -join ''
    $hit = Get-ADObject -Identity $Object.DistinguishedName -Server $script:Config.DC `
        -LDAPFilter "(|$or)" -ErrorAction Stop
    if ($hit) { return @{ Protected = $true; Reason = 'recursive member of protected group' } }
    return @{ Protected = $false }
}
```

**Scope check to add in the same function (Pitfall 5, L558–L561):** normalize both DNs (lowercase/trim/unescape); accept only if `$t -eq $root` OR `$t.EndsWith(",$root")` — component-boundary anchored, **never** `$dn -like "*$root*"`. Run the objectClass pre-filter FIRST (precise gMSA reason), then deny-list, then IN_CHAIN. Direction of IN_CHAIN matters (L369): bind the search to the **target** and filter on `memberOf:...:=<groupDN>` ORed across groups — never enumerate group members client-side.

---

### `Private/Safety/Get-AdmanProtectedIdentity.ps1` (Private startup SID resolver — D-02)

**Source of truth:** `00-RESEARCH.md` Pattern 3 startup, **L329–L345**.

**Core pattern to copy (L330–L344):**
```powershell
# Startup: build protected-group DN list from well-known SIDs (names lie, SIDs don't)
$dom   = Get-ADDomain -Server $script:Config.DC
$domSid= $dom.DomainSID.Value
# Forest-root SID for 518/519 (Schema/Enterprise Admins live in the forest ROOT domain)
$rootSid = (Get-ADDomain -Identity ((Get-ADForest).RootDomain) -Server $script:Config.DC).DomainSID.Value
$protectedRids = @{
    'Domain Admins'      = "$domSid-512";   'Schema Admins'      = "$rootSid-518"
    'Enterprise Admins'  = "$rootSid-519";  'Administrators'     = 'S-1-5-32-544'
    'Account Operators'  = 'S-1-5-32-548';  'Backup Operators'   = 'S-1-5-32-551'
    'Server Operators'   = 'S-1-5-32-549';  'Protected Users'    = "$domSid-525"  # defense-in-depth
}
$protectedGroupDns = foreach ($sid in $protectedRids.Values) {
    (Get-ADGroup -Identity $sid -Server $script:Config.DC -ErrorAction SilentlyContinue).DistinguishedName
}
if ($script:Config.AdmanProtectedGroup) { $protectedGroupDns += $script:Config.AdmanProtectedGroup }  # adman-Protected
$script:ProtectedGroupDns = $protectedGroupDns | Where-Object { $_ } | Select-Object -Unique
```

**Note (Assumption A3, RESEARCH L638):** 518/519 resolve against the **forest-root-domain** SID (comment this in-file; no v1 behavior change for single-domain). 525/526-527 are defense-in-depth where present (planner discretion per CONTEXT L79).

---

### `Private/Audit/Write-AdmanAudit.ps1` (Private synchronous write-ahead JSONL — SAFE-03/04; the ONLY audit writer)

**Source of truth:** `00-RESEARCH.md` Pattern 4, **L371–L415** (body L376–L412). Hand-rolled + synchronous by design — do **not** route through PSFramework (D-01; async logging breaks fail-closed).

**Full body to copy (L376–L412):**
```powershell
function Write-AdmanAudit {
    param([string]$CorrelationId,[string]$Verb,$Targets,[string]$Result,[string]$Reason,[switch]$WhatIf)
    $mutex = [System.Threading.Mutex]::new($false, 'Global\adman-audit')
    [void]$mutex.WaitOne()
    try {
        $path = Join-Path $script:Config.AuditDir ("audit-{0:yyyyMMdd}.jsonl" -f (Get-Date))
        if (-not (Test-Path $script:Config.AuditDir)) {
            New-Item -ItemType Directory -Path $script:Config.AuditDir -Force -ErrorAction Stop | Out-Null
        }
        $rec = [ordered]@{
            tsUtc=(Get-Date).ToUniversalTime().ToString('o'); who="$env:USERDOMAIN\$env:USERNAME"
            userSid=([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            what=$Verb; scope=($script:Config.ManagedOUs -join '|')
            target=(($Targets | ForEach-Object { $_.DistinguishedName }) -join '|')
            count=@($Targets).Count; whatIf=[bool]$WhatIf; result=$Result; reason=$Reason
            correlationId=$CorrelationId; host=$env:COMPUTERNAME; psEdition=$PSEdition
            moduleVersion=(Get-Module adman).Version.ToString()
        } | ConvertTo-Json -Compress -Depth 5
        # Append, allow readers, DURABLY flush to disk
        $fs = [System.IO.File]::Open($path,
            [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($rec + "`n")
            $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true)   # $true = flush to disk (not just OS cache)
        } finally { $fs.Dispose() }
    } catch {
        if ($Result -eq 'PENDING') {
            # SAFE-04: pre-write reservation failed → REFUSE the destructive action
            throw "AUDIT FAIL-CLOSED: cannot write audit record ($($_.Exception.Message)); refusing $Verb."
        }
        # OUTCOME failure after a successful mutation → escalate, do NOT roll back AD (D-03)
        Write-EventLog -LogName Application -Source adman -EventId 9001 -EntryType Error `
            -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
        Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId — see Event Log."
        $script:AuditDegraded = $true
    } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
```

**Sequencing rules (D-03):** named mutex `Global\adman-audit` → open daily-rotated `audit-YYYYMMDD.jsonl` (Append/Write/Read-share) → write **PENDING** `{correlationId}` → `Flush($true)` → **throw before AD on any exception (the refusal)** → mutate → append OUTCOME best-effort. **No secret fields** in the schema (SAFE-03/CONF-05). OUTCOME-failure escalates to Event Log + loud UI + `$script:AuditDegraded`; **never** fake an AD rollback (D-03). `Write-EventLog -Source adman` needs the source registered — best-effort `New-EventLog` in `Initialize-Adman`, degrade to console warning (RESEARCH L415, A2).

---

### `Private/Safety/Confirm-AdmanAction.ps1` (Private scaled confirmation — SAFE-02)

**Source of truth:** `00-RESEARCH.md` Pattern 6, **L451–L473** (body L456–L470).

**Core pattern to copy (L456–L470):**
```powershell
function Confirm-AdmanAction {
    param([string]$Verb,$Targets,[string]$CorrelationId)
    $count = @($Targets).Count
    $threshold = [int]$script:Config.safety.bulkConfirmThreshold   # default 5 (D-07)
    # -Force / -Confirm:$false bypass ONLY the prompt — scope/deny/protected/cap already ran above (non-bypassable)
    if (-not $Force -and -not ($ConfirmPreference -eq 'None')) {
        if ($count -ge $threshold) {
            $token = Read-Host "Type the exact count ($count) to $Verb these $count objects"
            if ($token -ceq "$count") { throw "Confirmation failed: expected $count, got '$token'. Refused." }
        } elseif (-not $PSCmdlet.ShouldProcess("$count object(s)", $Verb)) {   # default-No, honors -WhatIf
            Write-AdmanAudit -CorrelationId $CorrelationId -Verb $Verb -Targets $Targets -Result 'Cancelled'
            throw "Operator declined."
        }
    }
}
```

**Rules:** single-object → `$PSCmdlet.ShouldProcess` (default-No, honors `-WhatIf`/`-Confirm`); bulk (≥`safety.bulkConfirmThreshold`, default 5) → custom `Read-Host` **exact-count** token (NOT `ShouldContinue` — it ignores `-Confirm:$false` and can't carry a typed token, L513); `-Force`/`-Confirm:$false` short-circuit **only** the prompt (deny/protected/scope/cap already enforced upstream). Pitfall 2 (L540–L544): test suppression via `$ConfirmPreference -eq 'None'`, **never** read the automatic `$Confirm` (unset under `Set-StrictMode -Version Latest`, issue #14294).

---

### `Private/Foundation/Get-AdmanCredential.ps1` (Private credential decision — CONF-04/06)

**Source of truth:** `00-RESEARCH.md` Pattern 5, **L417–L449** (body L424–L446).

**Core pattern to copy (L424–L446):**
```powershell
function Get-AdmanCredential {
    if (-not $script:Config.credentialPolicy.allowRememberMe) { return $null }   # pass-through
    $file = Join-Path $script:StorePath 'adman.credential.xml'
    if (Test-Path $file) {
        try {
            $cred = Import-Clixml -Path $file -ErrorAction Stop
            [void]$cred.GetNetworkCredential().Password   # guard: bad restore → null/empty throws
            return $cred
        } catch {
            # CryptographicException 0x8009000B ("Key not valid for use in specified state") OR empty-password
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue      # delete bad file (D-06)
            Write-PSFMessage -Level Warning -Message "Stored credential unreadable; re-prompting."
        }
    }
    if ($script:RightsInsufficient) {            # only prompt when pass-through rights insufficient (CONF-06)
        $cred = Get-Credential -Message 'Domain credentials required for this task'
        if ($script:Config.credentialPolicy.allowRememberMe -and (Read-AdmanRememberMeConsent)) {
            $cred | Export-Clixml -Path $file -Force                            # DPAPI CurrentUser
        }
        return $cred
    }
    return $null
}
```

**Rules (D-06):** pass-through default; stored credential consumed **only** when pass-through rights insufficient (never short-circuits the per-task rights check); `Export-Clixml` CurrentUser only (identical on 5.1+7); on restore failure (`CryptographicException` 0x8009000B OR empty-password) **delete the bad file** and fall back to `Get-Credential`; **reject** keyed-AES (`-EncryptionKey`) files; LocalMachine scope is a documented opt-in only for an ACL-locked jump host (Pitfall 6 L565–L568); never log the credential.

---

### `Public/Test-AdmanCapability.ps1` (Public exported startup probe — MENU-05)

**Source of truth:** `00-RESEARCH.md` Pattern 7, **L475–L507** (body L489–L506); probe table L479–L486.

**Core pattern to copy (L489–L506):**
```powershell
function Test-AdmanCapability {
    $flags = [ordered]@{}
    $flags.RsatPresent = [bool](Get-Module -ListAvailable ActiveDirectory)
    $flags.DomainReachable = $false
    if ($flags.RsatPresent) {
        try { $null = Get-ADDomain -ErrorAction Stop; $flags.DomainReachable = $true } catch { }
    }
    $flags.AuditWritable = Test-AdmanAuditWritable
    $flags.RecycleBinEnabled = [bool](Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"' |
        Where-Object { $_.EnabledScopes.Count -gt 0 })
    $script:Capability = [pscustomobject]$flags
    foreach ($k in $flags.Keys) {
        if (-not $flags[$k]) { Write-PSFMessage -Level Warning -Message (Get-AdmanCapabilityGuidance $k) }
    }
    # FAIL-CLOSED: refuse mutating operations if scope empty or audit unwritable
    if (-not $script:Config.ManagedOUs) { throw 'FAIL-CLOSED: managed-OU is empty.' }
    if (-not $flags.AuditWritable)     { throw 'FAIL-CLOSED: audit path not writable.' }
}
```

**Probe coverage (L479–L486):** RSAT present (`Get-Module -ListAvailable ActiveDirectory`); domain/ADWS reachable (`Get-ADDomain -Server <dc> -ErrorAction Stop`, short timeout; ADWS = TCP 9389); current rights **non-destructively** (read managed OU + `whoami /groups` for configured delegated-admin group — **never** a real write to test rights); transport (`Test-WSMan` + optional `New-CimSession -Protocol Dcom`); audit dir writable (open append + `Flush($true)` → fail-closed). Surface guidance via `Write-PSFMessage -Level Warning`. Fail-closed throws on empty managed-OU / unwritable audit. Cheap + short timeouts (never let a probe hang).

---

### `Private/Config/Initialize-AdmanConfig.ps1` (Private config load/validate/seed — CONF-01/02/03 + D-05 deny-list)

**Source of truth:** `00-RESEARCH.md` D-01/D-04/D-05 (L14–L18); Pitfall 7 (L570–L574, PSFramework auto-import fail-open); Pitfall 8 (L576–L579, JSON depth/`-AsHashtable`); §Don't Hand-Roll L521–L528.

**Rules to encode (no single full body in RESEARCH — compose from these):**
- Use PSFramework **with `-Path` pinning only**: `Import-PSFConfig -Path .store/config.json` / `Export-PSFConfig -Path .store/config.json`. **Never** call `Register-PSFConfig` for safety-critical values (managed-OU/deny-list) — its per-user default auto-loads at every import and can silently override the portable file (fail-open, Pitfall 7).
- Validate against the **shared schema** `config/adman.schema.json` (D-04: one schema for wizard emitter AND loader, so they cannot drift).
- **Fail-closed in `Initialize-Adman`** regardless of framework: empty `ManagedOUs`, failed config load, or failed deny-list load ⇒ throw before any mutating op (CONF-02). NOTE (D-04): the first-run `init`/wizard runs in **setup mode** and is **exempt** from this gate (it creates the config) — the gate applies only to AD-mutating operations.
- Seed the deny-list into the JSON on first creation (D-05): RID tokens `500` (built-in Administrator), `501` (Guest), `502` (krbtgt), resolved against `(Get-ADDomain).DomainSID` at match time; label "starter, not exhaustive"; the file is the single source of truth thereafter (code holds only the default used to populate a fresh file).
- `ConvertTo-Json` **always `-Depth ≥5`** on save (Pitfall 8); on 5.1 read as `PSCustomObject` and index by property (no `-AsHashtable`).

---

### `Public/Initialize-Adman.ps1` (Public exported startup orchestration — entry used by `Start-Adman` Phase 1)

**Source of truth:** `00-RESEARCH.md` §Arch Responsibility Map L73–L85; §System Architecture Diagram L159–L170.

**Startup sequence to encode (L164–L170):**
1. `Initialize-AdmanConfig` → `Import-PSFConfig -Path .store/config.json`; validate schema; **FAIL-CLOSED** if managed-OU empty / deny-list / config fails to load; seed deny-list (D-05).
2. `Write-AdmanAudit` **probe** → verify `.store/audit` writable → FAIL-CLOSED.
3. `Get-AdmanCredential` → pass-through | prompt | `Import-Clixml` (opt-in) → in-memory `[pscredential]`.
4. `Test-AdmanCapability` → RSAT? domain/ADWS? rights? transport? (MENU-05 flags).
5. Resolve protected SIDs + deny-list into session (`Get-AdmanProtectedIdentity`, `Resolve-AdmanDomainSid`).

**Session flags set (read by the gate at call time):** `ConfigLoaded` (bool), `ManagedOUs[]` (DN roots), `DenyList[]` (SID tokens), `ProtectedSIDs` (resolved), `AuditWritable` (bool), `PSCredential` (in-mem), `Capability` (flags). Best-effort `New-EventLog -Source adman` here (degrade to console warning). `$ErrorActionPreference = 'Stop'` module-wide; pin DC via a `-Server` helper.

---

### `Public/Config/{Get,Set,Export,Import}-AdmanConfig.ps1` (Public exported config verbs — thin wrappers)

**Source of truth:** `00-RESEARCH.md` D-01/D-04 (L14,L17); Pitfall 7 L570–L574; §Don't Hand-Roll L521–L528.

**Pattern:** thin Public verbs that delegate to PSFramework **pinned with `-Path`** (never rely on magic per-user/per-machine auto-import locations). `Get/Set` wrap `Get-PSFConfig`/`Set-PSFConfig`; `Export/Import` wrap `Export-PSFConfig -Path`/`Import-PSFConfig -Path` against `.store/config.json`. State-changing verbs (`Set-`, `Import-`) declare `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` and route any safety-critical change through the same validation as `Initialize-AdmanConfig` (so CONF-02 fail-closed can't be bypassed by editing scope/deny-list via `Set-AdmanConfig`). Always `-Depth ≥5` on save (Pitfall 8).

---

### `Private/AD/Adman.AD.Write.ps1` (Private raw write wrappers — GATE-ONLY; the ONE place `Set-AD*` lives)

**Source of truth:** `00-RESEARCH.md` Pattern 1 L271 (the `& "Adman.AD.Write.$Verb"` call) + SAFE-09 allow-list L251–L253; Anti-Pattern L510.

**Pattern:** one thin wrapper per allow-listed verb (`Adman.AD.Write.Disable-ADAccount`, `.Enable-ADAccount`, `.Move-ADObject`, `.Set-ADUser`, `.Set-ADComputer`, `.Set-ADAccountPassword`, `.Unlock-ADAccount`, `.Add-ADGroupMember`, `.Remove-ADGroupMember`). Each wrapper declares `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]`, pins `-Server $script:Config.DC`, forwards `-WhatIf:$WhatIfPreference -Confirm:$false`, and is the **only** code that calls the real AD cmdlet. **`Remove-ADObject` has NO wrapper** (SAFE-09 — "delete" = reversible disable+quarantine; no hard-delete verb). The AST guard (SAFE-08) scans `Public/` only, so these Private wrappers are expected to contain the banned cmdlet names — that is correct and intended; do not add these names anywhere under `Public/`.

---

### `adman.psd1` (manifest) and `adman.psm1` (root module)

**Source of truth:** `00-RESEARCH.md` §Recommended Project Structure L194–L198; §Standard Stack L89–L98; §System Architecture Diagram L157–L188.

**Manifest fields to set (L194–L198):**
- `RootModule = 'adman.psm1'`; `PowerShellVersion = '5.1'`.
- `CompatiblePSEditions = @('Desktop')` **until CI passes on 7.6** (then add `'Core'`).
- `RequiredModules = @('PSFramework')` (ActiveDirectory is a **PREREQ, not a dependency** — do not list it).
- `FunctionsToExport = <explicit list>` — **NEVER `'*'`**. Phase 0 exports only: `Initialize-Adman`, `Test-AdmanCapability`, and the `*/AdmanConfig` verbs (plus a `Start-Adman` stub for Phase 1). The gate `Invoke-AdmanMutation` and all `Private/*` are **NOT** exported.
- Pin `PSFramework` to **1.14.457** (D-01); dev deps `Pester 6.0.0`, `PSScriptAnalyzer 1.25.0` (L95–L98).

**Root module (`adman.psm1`) pattern (L198):** `$ErrorActionPreference = 'Stop'`; dot-source every `Private/**/*.ps1` first, then `Public/**/*.ps1`; collect the public function names and `Export-ModuleMember -Function $public` (explicit, matches the manifest); the loader does **not** auto-run a domain-touching init at import (capability probe/init is invoked by `Start-Adman`/`Initialize-Adman`, not at module import, to keep import side-effect-free and fail-closed deterministic).

---

### `tests/Safety.Gate.Tests.ps1` (AST guard — proves SAFE-08/09; static, no domain)

**Source of truth:** `00-RESEARCH.md` Pattern 1 guard, **L279–L302** (+ caveat L304); Code Examples L593–L599.

**Test body to copy (L280–L301):**
```powershell
Describe 'SAFE-08: no exported function calls AD write cmdlets directly' {
    $banned = @(
        'Set-ADUser','Set-ADComputer','Set-ADObject','Set-ADAccountPassword',
        'Disable-ADAccount','Enable-ADAccount','Unlock-ADAccount',
        'Move-ADObject','New-ADUser','New-ADComputer',
        'Add-ADGroupMember','Remove-ADGroupMember','Add-ADPrincipalGroupMembership',
        'Remove-ADObject'   # SAFE-09: hard-delete verb must appear NOWHERE in Public/
    )
    $publicFiles = Get-ChildItem -Path "$PSScriptRoot/../Public" -Filter *.ps1 -Recurse
    It 'Public/<file> contains no direct AD write call' -ForEach ($publicFiles | ForEach-Object {@{File=$_}}) {
        param($File)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] },
            $true)                                  # $true = recurse into nested scriptblocks
        $names = $calls | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        $hits  = $names | Where-Object { $_ -in $banned }
        $hits | Should -BeNullOrEmpty -Because "$($File.Name) must route writes through Invoke-AdmanMutation"
    }
}
```

**Caveat to implement (L304):** `CommandAst.GetCommandName()` returns `$null` for dynamic invocations (`& $cmd`) — fall back to `$cmd.CommandElements[0].Extent.Text`; also grep `$tokens` for `&`/`Invoke-Expression` to catch string-built calls; resolve aliases via `Get-Command` so an aliased call can't slip through. Use the AST, **not** regex (regex misses comments/strings/aliases — §Don't Hand-Roll L527).

---

### `rules/AdmanSafetyRules.psm1` + `PSScriptAnalyzerSettings.psd1` (custom PSSA rule + lint settings — SAFE-08 host)

**Source of truth:** `00-RESEARCH.md` Pattern 1 caveat L304; Wave 0 L726–L727; `.claude/CLAUDE.md` L76.

**`PSScriptAnalyzerSettings.psd1` — enable (CLAUDE.md L76):** `PSUseShouldProcessForStateChangingFunctions` (enforces SAFE-01), `PSAvoidUsingPlainTextForPassword`, `PSUsePSCredentialType`, `PSAvoidGlobalVars`, `PSUseApprovedVerbs`, `PSAvoidUsingCmdletAliases`, `PSUseConsistentIndentation`. Add a **documented** suppression for `PSAvoidUsingWriteHost` **only** in the TUI-rendering module (the menu legitimately paints the console) — that module arrives in Phase 1, so the suppression target is forward-declared.

**`rules/AdmanSafetyRules.psm1` — custom rule:** mirror the AST guard (banned AD write cmdlets in `Public/`); emit a `DiagnosticRecord` when a `CommandAst` under `Public/` resolves to a banned name, including the `& $cmd`/`Invoke-Expression` token-grep fallback from L304. Wire it into the settings file via `CustomRulePath`.

---

### `config/adman.defaults.json`, `config/adman.schema.json`, `.store/config.example.json` (config artifacts — D-04/D-05)

**Source of truth:** `00-RESEARCH.md` D-04 (L17), D-05 (L18); runtime locations L107–L110 (in `00-CONTEXT.md`).

**Pattern:**
- `config/adman.schema.json` — the **single shared schema** used by both the wizard emitter (CONF-01/03) and the loader (CONF-01). Keys (per D-01..D-07, CONTEXT L107): `ManagedOUs[]`, `DenyList[]` (SID/RID tokens), `safety.bulkConfirmThreshold` (default 5), bulk cap placeholder (Phase 4 enforces), `AuditDir`, report paths, transport order/timeouts, `credentialPolicy.allowRememberMe`, `AdmanProtectedGroup` (the `adman-Protected` DN), `DC` pinning, `delegatedAdminGroup` SID. No secret fields.
- `config/adman.defaults.json` — shipped defaults = schema source-of-truth values (empty `ManagedOUs` so a fresh install fails closed until configured; deny-list seeded with RID 500/501/502 tokens per D-05; `bulkConfirmThreshold=5`; `allowRememberMe=false`).
- `.store/config.example.json` — the **annotated** shipped example (D-04). Strict JSON has no comments → use **`_comment` keys the loader strips** (NOT JSONC/JSON5 — breaks the zero-dep plain-JSON constraint). The wizard/init emits this same shape.

---

### `tests/Safety.WhatIf.Integration.Tests.ps1`, `tests/Safety.Protected.Tests.ps1`, `tests/Audit.FailClosed.Tests.ps1`, `tests/Mocks/ActiveDirectory.psm1`, `tests/PesterConfiguration.psd1`

**Source of truth:** `00-RESEARCH.md` §Validation Architecture L679–L728 (Test Map L694–L712; Sampling L714–L717; Wave 0 Gaps L719–L728).

- **`tests/Mocks/ActiveDirectory.psm1`** (L725): mock every `Get-AD*/Set-AD*/Disable-AD*/Move-ADObject` so **Unit tests never touch a live domain**. All `*.Tests.ps1` (Unit) import this mock; `*.Integration.Tests.ps1` run only against a disposable lab test OU.
- **`tests/PesterConfiguration.psd1`** (L720): Pester 6 config — Run/Filter/CodeCoverage (profiler-based, default in v6) + Output. Quick run: `Invoke-Pester -Path tests -Output Normal -TagFilter Unit`; full: `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)`.
- **`tests/Safety.WhatIf.Integration.Tests.ps1`** (L722; covers SAFE-01/10): end-to-end `-WhatIf` vs lab OU — assert (a) AD unchanged AND (b) audit `target` list == resolved list AND (c) operator-shown count == `$resolved.Count` (Pattern 2 L322).
- **`tests/Safety.Protected.Tests.ps1`** (L723; covers SAFE-06): unit + lab fixtures for nested Domain Admins, gMSA, and **RID-500 rename** — prove live IN_CHAIN membership is used and `adminCount` is NOT consulted.
- **`tests/Audit.FailClosed.Tests.ps1`** (L724; covers SAFE-04): mock `FileStream` to throw on the PENDING write → assert the mutation is refused and AD is untouched.

**Sampling discipline (L683, L714–L717):** per task commit run mocked Unit suite (<30s, never touches a domain); per wave merge run full suite incl. `-Tag Integration` against the lab OU; phase gate = full suite green + `Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1 -Recurse` clean. DN-canonicalization and confirmation-token handling get a small generated-input matrix (case/escaping/component-boundary/spoof DNs; threshold ±1, wrong/empty token).

---

## Shared Patterns (cross-cutting — apply to all relevant files)

### ShouldProcess boilerplate (every state-changing function)
**Source:** `.claude/CLAUDE.md` L121; `00-RESEARCH.md` Pitfall 1 L534–L538, Pitfall 2 L540–L544.
**Apply to:** every Public/Private function that mutates or is destructive (gate, AD wrappers, config `Set/Import`, the future Phase-2 verbs).
```powershell
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
# forward explicitly to inner AD cmdlets; never set $WhatIfPreference globally:
... -WhatIf:$WhatIfPreference -Confirm:$false
# test suppression via $ConfirmPreference -eq 'None' — NEVER read the automatic $Confirm (StrictMode)
```

### `-Force` / `-Confirm:$false` automation idiom (the senior fast path)
**Source:** `00-RESEARCH.md` D-07 L20; Pattern 6 L451–L473.
**Apply to:** the gate and any Public verb that wraps confirmation. `-Force` / `-Confirm:$false` skip **only** the prompt; deny-list / protected-account / managed-OU scope / Phase-4 cap remain **non-bypassable** under any flag (menu or direct-call).

### Fail-closed audit ordering (write-ahead reservation)
**Source:** `00-RESEARCH.md` Pattern 4 L371–L415.
**Apply to:** every mutation (gate is the only caller; `Write-AdmanAudit` is the only writer). PENDING flushed (`Flush($true)`) **before** the AD call; throw on PENDING-write failure = the refusal; OUTCOME best-effort after; never fake AD rollback.

### SID/RID identity matching (never names)
**Source:** `00-RESEARCH.md` D-02/D-05 (L15,L18); Pitfall 4 L553–L556.
**Apply to:** deny-list (D-05), protected-account (D-02), scope. Match `objectSid`/RID against `(Get-ADDomain).DomainSID`; well-known SIDs (`S-1-5-32-544` etc.) as literals. Never `sAMAccountName` (RID-500 renamed via GPO), never `adminCount` (stale-on-removal + SDProp-window lag).

### Component-boundary-anchored DN scope (SAFE-07)
**Source:** `00-RESEARCH.md` Pitfall 5 L558–L561.
**Apply to:** `Test-AdmanTargetAllowed`. Normalize (lowercase/trim/unescape); accept only `$t -eq $root` OR `$t.EndsWith(",$root")`; resolve canonical DN from AD rather than trusting caller input; never substring `-like "*$root*"`.

### PSFramework config pinning (no auto-import)
**Source:** `00-RESEARCH.md` D-01 L14; Pitfall 7 L570–L574.
**Apply to:** all config verbs + `Initialize-AdmanConfig`. `Import-PSFConfig -Path`/`Export-PSFConfig -Path` only; never `Register-PSFConfig` for safety-critical values; fail-closed implemented in `Initialize-Adman` independent of the framework.

### JSON depth + 5.1 indexing
**Source:** `00-RESEARCH.md` D-01 L14; Pitfall 8 L576–L579.
**Apply to:** every config save + the audit writer. `ConvertTo-Json ... -Depth 5` (or higher) on **every** save; on 5.1 read config as `PSCustomObject` and index by property (no `-AsHashtable`).

### Diagnostics vs audit (PSFramework split)
**Source:** `00-RESEARCH.md` D-01 L14; §Don't Hand-Roll L521–L530.
**Apply to:** all files. `Write-PSFMessage -Level <...>` for diagnostics/ops/guidance only; the **audit** record is **never** emitted via PSFramework (async/first-record-loss/exit-drain breaks fail-closed) — it goes only through `Write-AdmanAudit`.

---

## No Analog Found

**All 30 planned files are greenfield** — there is no existing PowerShell anywhere in the repo (verified by Glob). Nothing in the codebase is close enough to serve as a sibling analog. Every file maps to a `00-RESEARCH.md` pattern (Patterns 1–7 + pitfalls) as its source of truth. The planner copies concrete signatures/bodies from the cited line ranges; no file should be modeled on a non-existent predecessor.

| File | Role | Why no codebase analog |
|------|------|------------------------|
| (all 30 listed above) | — | Greenfield Phase 0; no `.ps1/.psm1/.psd1` exists yet. |

## Metadata

**Analog search scope:** entire repo (`C:\Users\nhdinh\dev\adman`) via `Glob **/*.{ps1,psm1,psd1}` (0 hits); `.planning/research/*.md` and `.planning/*.md` confirmed present; `.store/` empty + gitignored.
**Files scanned (existing source):** 0 PowerShell source files.
**Source-of-truth scanned:** `00-RESEARCH.md` (795 lines, Patterns 1–7 + pitfalls + validation architecture), `00-CONTEXT.md` (D-01..D-07), `.claude/CLAUDE.md` (What NOT to Use + lint rules).
**Pattern extraction date:** 2026-07-10
**Downstream:** planner maps each file to the cited `00-RESEARCH.md` line range and lifts the concrete signature/body into PLAN action steps; build-time re-verification of PSFramework 1.14.457 exact parameter names (Assumption A1) is a REQUIRED first task before pinning.
