# Phase 2: Single-Object Lifecycle (writes begin) - Pattern Map

**Mapped:** 2026-07-15
**Files analyzed:** 28 (new + modified)
**Analogs found:** 28 / 28 (every new artifact has a direct in-repo analog; no orphan patterns)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Private/Safety/Invoke-AdmanMutation.ps1` (MOD) | gate | request-response | self (existing) | exact |
| `Private/Safety/Invoke-AdmanLocalMutation.ps1` (NEW) | gate | request-response | `Private/Safety/Invoke-AdmanMutation.ps1` | exact |
| `Private/Safety/Resolve-AdmanCreateTarget.ps1` (NEW) | resolver | request-response | `Private/Safety/Resolve-AdmanTarget.ps1` | exact |
| `Private/Safety/Resolve-AdmanLocalTarget.ps1` (NEW) | resolver | request-response | `Private/Safety/Resolve-AdmanTarget.ps1` | role-match (different source API) |
| `Private/Safety/Resolve-AdmanGroup.ps1` (NEW, D-04) | resolver | request-response | `Private/Safety/Resolve-AdmanTarget.ps1` | exact |
| `Private/Safety/Test-AdmanTargetAllowed.ps1` (MOD, create-branch) | policy | request-response | self (existing) | exact |
| `Private/Safety/Test-AdmanLocalTargetAllowed.ps1` (NEW) | policy | request-response | `Private/Safety/Test-AdmanTargetAllowed.ps1` | exact |
| `Private/Safety/Test-AdmanGroupAllowed.ps1` (NEW) | policy | request-response | `Private/Safety/Test-AdmanTargetAllowed.ps1` | exact |
| `Private/Safety/Confirm-AdmanAction.ps1` (MOD, per-verb threshold + two-object render) | confirm | request-response | self (existing) | exact |
| `Private/Safety/AdmanWriteVerbs.ps1` (MOD, +New-ADUser) | allow-list | config | self (existing) | exact |
| `Private/AD/Adman.AD.Write.ps1` (MOD, +New-ADUser wrapper) | wrapper | request-response | self (existing 9 wrappers) | exact |
| `Private/Local/Adman.Local.Write.ps1` (NEW, 7 wrappers) | wrapper | request-response | `Private/AD/Adman.AD.Write.ps1` | exact |
| `Private/Audit/Write-AdmanAudit.ps1` (MOD, +group field, +MACHINE\user shape) | audit | file-I/O | self (existing) | exact |
| `Private/Utility/New-AdmanRandomPassword.ps1` (NEW) | utility | transform | `.planning/spikes/004-secure-password-generation/Invoke-Spike.ps1` | exact (lift directly) |
| `Private/Utility/Test-AdmanPasswordComplexity.ps1` (NEW, prompt-path validator) | utility | transform | Spike 004 `Test-PasswordPolicy` | exact |
| `Private/Menu/Get-AdmanMenuDefinition.ps1` (MOD, +~15 entries) | menu-def | config | self (existing) | exact |
| `Private/Menu/Read-AdmanActionParams.ps1` (MOD, polymorphic Type) | prompt-engine | request-response | self (existing) | exact |
| `Public/New-AdmanUser.ps1` (NEW) | public-verb | request-response | `Public/Find-AdmanUser.ps1` (shape) + `Invoke-AdmanMutation` (gate call) | role-match |
| `Public/Disable-AdmanUser.ps1`, `Enable-AdmanUser.ps1`, `Move-AdmanUser.ps1`, `Set-AdmanUserPassword.ps1`, `Unlock-AdmanUser.ps1` (NEW) | public-verb | request-response | `Public/Find-AdmanUser.ps1` (shape) + gate call | role-match |
| `Public/Disable-AdmanComputer.ps1`, `Enable-AdmanComputer.ps1`, `Move-AdmanComputer.ps1`, `Reset-AdmanComputerAccount.ps1` (NEW) | public-verb | request-response | `Public/Find-AdmanComputer.ps1` (shape) + gate call | role-match |
| `Public/New-AdmanLocalUser.ps1`, `Set-AdmanLocalUser.ps1`, `Remove-AdmanLocalUser.ps1`, `Add-AdmanLocalGroupMember.ps1`, `Remove-AdmanLocalGroupMember.ps1` (NEW) | public-verb | request-response | `Public/Find-AdmanUser.ps1` (shape) + `Invoke-AdmanLocalMutation` call | role-match |
| `Public/Add-AdmanGroupMember.ps1`, `Remove-AdmanGroupMember.ps1` (NEW) | public-verb | request-response | `Public/Find-AdmanUser.ps1` (shape) + dual-resolution gate call | role-match |
| `rules/AdmanSafetyRules.psm1` (MOD, +LocalAccounts banned set) | lint-rule | static-analysis | self (existing) | exact |
| `tests/Mocks/ActiveDirectory.psm1` (MOD, +LocalAccounts mocks) | test-fixture | mock | self (existing) | exact |
| `tests/Safety.GateOrder.Tests.ps1` (MOD, +create path + group matrix) | test | unit-test | self (existing) | exact |
| `tests/Safety.Gate.Tests.ps1` (MOD, +LocalAccounts AST guard) | test | unit-test | self (existing) | exact |
| `tests/Audit.Schema.Tests.ps1` (MOD, +group field + MACHINE\user) | test | unit-test | self (existing) | exact |
| `tests/User.Create.Tests.ps1`, `User.Password.Tests.ps1`, `User.Unlock.Tests.ps1`, `User.Move.Tests.ps1`, `Local.User.Tests.ps1`, `Local.Group.Tests.ps1`, `Computer.*.Tests.ps1`, `Group.*.Tests.ps1` (NEW) | test | unit-test | `tests/Find.User.Tests.ps1`, `tests/Safety.GateOrder.Tests.ps1` | exact |
| `adman.psd1` (MOD, +new Public verb exports) | manifest | config | self (existing) | exact |

## Pattern Assignments

### `Private/Safety/Invoke-AdmanLocalMutation.ps1` (gate, request-response)

**Analog:** `Private/Safety/Invoke-AdmanMutation.ps1` (the existing AD gate)

**File header + Set-StrictMode pattern** (lines 1-32):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanLocalMutation - THE LOCAL GATE: sibling mutation funnel for
    Microsoft.PowerShell.LocalAccounts writes (SAFE-08 extended, D-02).
.DESCRIPTION
    [Mirror the existing gate's doc block: fixed order, ValidateSet is the SAFE-09
    boundary, PENDING/OUTCOME write-ahead, decline writes NOTHING, -Force forwards
    to Confirm-AdmanAction only. LocalAccounts cmdlets DO declare
    SupportsShouldProcess on PS 5.1 (verified) so truthful -WhatIf works through
    the wrappers. Audit Target records MACHINE\username + local SID (no DN).]
#>

Set-StrictMode -Version Latest
```

**Function signature + ValidateSet pattern** (lines 34-46 of analog):
```powershell
function Invoke-AdmanLocalMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('New-LocalUser', 'Disable-LocalUser', 'Enable-LocalUser',
            'Set-LocalUser', 'Remove-LocalUser',
            'Add-LocalGroupMember', 'Remove-LocalGroupMember')]
        [string]$Verb,
        [Parameter(Mandatory)]
        [string[]]$Targets,        # Local usernames (NOT DNs)
        [hashtable]$Parameters = @{},
        [switch]$Force
    )
```

**Fixed-order body** (lines 48-112 of analog — copy verbatim, swap resolver + test + wrapper namespace):
```powershell
    $cid = [guid]::NewGuid().ToString()

    # SAFE-10: ONE resolver, called once.
    $resolved = @(Resolve-AdmanLocalTarget -Targets $Targets -ComputerName $Parameters['ComputerName'])

    # Deny / protected / scope: refusals logged 'Refused' and skipped.
    $allowed = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $resolved) {
        $decision = Test-AdmanLocalTargetAllowed -Object $t -Verb $Verb
        if (-not $decision.Allowed) {
            Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Target $t -Result 'Refused' `
                -Reason $decision.Reason -WhatIf:$WhatIfPreference
        } else {
            $allowed.Add($t)
        }
    }

    if ($allowed.Count -eq 0) {
        return [pscustomobject]@{
            Action = $Verb; Targets = $Targets; Denied = $resolved.Count
            Succeeded = 0; Failed = 0; WhatIf = [bool]$WhatIfPreference
            CorrelationId = $cid
        }
    }

    Assert-AdmanBulkPolicy -Count $allowed.Count | Out-Null

    # D-03: per-verb threshold override for Remove-LocalUser (typed-count even at 1).
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force

    if ($confirm.Outcome -eq 'Declined') { throw 'Operator declined.' }

    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
        -Result 'PENDING' -WhatIf:$confirm.WhatIf

    & "Adman.Local.Write.$Verb" -Objects $allowed.ToArray() -Parameters $Parameters `
        -WhatIf:$confirm.WhatIf -Confirm:$false

    Write-AdmanAudit -CorrelationId $cid -Verb $Verb -Targets $allowed.ToArray() `
        -Result 'Success' -WhatIf:$confirm.WhatIf

    return [pscustomobject]@{
        Action = $Verb
        Targets = @($allowed | ForEach-Object { "{0}\{1}" -f $_.Machine, $_.Name })
        Denied = ($resolved.Count - $allowed.Count)
        Succeeded = $allowed.Count; Failed = 0
        WhatIf = [bool]$confirm.WhatIf; CorrelationId = $cid
    }
}
```

---

### `Private/Safety/Resolve-AdmanCreateTarget.ps1` (resolver, request-response)

**Analog:** `Private/Safety/Resolve-AdmanTarget.ps1`

**Pattern to copy** (file header style + Set-StrictMode + function shape from lines 1-40 of analog). The new resolver does NOT call `Get-ADObject -Identity` — it fabricates a synthetic PSCustomObject shaped like an ADObject.

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanCreateTarget - fabricate a synthetic pre-create target (D-01).
.DESCRIPTION
    Returns a PSCustomObject SHAPED like an ADObject so the gate's fixed order
    (Test-AdmanTargetAllowed -> Confirm -> PENDING -> write -> OUTCOME) runs
    unchanged for creates. The object carries the INTENDED DN
    (CN=<name>,<parentOU-DN>), the proposed sAMAccountName, objectClass='user',
    and IsSynthetic=$true so Test-AdmanTargetAllowed's create-branch can skip
    the SID/memberOf checks (no objectSid exists yet) and run ONLY the
    managed-OU scope check against the parent OU DN.
    SAFE-10 preserved: the preview and the audit Target field name the
    to-be-created DN, not the parent OU.
#>

Set-StrictMode -Version Latest

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
        Name              = $Name
        objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        objectSid         = $null              # No SID yet
        memberOf          = @()
        ParentOuDn        = $ParentOuDn
        IsSynthetic       = $true              # Flag for the create-branch
    }
}
```

---

### `Private/Safety/Resolve-AdmanLocalTarget.ps1` (resolver, request-response)

**Analog:** `Private/Safety/Resolve-AdmanTarget.ps1` (shape) — but the data source is `Get-LocalUser` / `Get-LocalGroupMember`, not `Get-ADObject`.

**Pattern:**
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanLocalTarget - materialize local account objects (D-02).
.DESCRIPTION
    Returns one PSCustomObject per local username with Machine, Name, SID,
    and (for group-side checks) local Administrators membership. No DN, no
    AD objectSid. Phase 2 validates -ComputerName to localhost only; Phase 3
    widens the validation when the transport ladder lands (verb signatures
    never change between phases).
    Wraps Get-LocalGroupMember in try/catch + WMI fallback (Pitfall 3:
    orphaned-SID 0x80070534 fatal error).
#>

Set-StrictMode -Version Latest

function Resolve-AdmanLocalTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Targets,
        [string]$ComputerName = $env:COMPUTERNAME
    )

    # Phase 2 localhost validation (D-02): accept $null, '.', $env:COMPUTERNAME,
    # 'localhost' - anything else throws "remote targets arrive in Phase 3".
    $machine = $ComputerName
    if ([string]::IsNullOrWhiteSpace($machine) -or $machine -eq '.') {
        $machine = $env:COMPUTERNAME
    } elseif ($machine -eq 'localhost') {
        $machine = $env:COMPUTERNAME
    } elseif ($machine -ne $env:COMPUTERNAME) {
        throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
    }

    foreach ($name in $Targets) {
        $user = Get-LocalUser -Name $name -ErrorAction Stop
        [pscustomobject]@{
            Machine   = $machine
            Name      = $user.Name
            SID       = $user.SID            # Local SID (S-1-5-21-...-1xxx)
            Enabled   = $user.Enabled
            FullName  = $user.FullName
            LocalRid  = ([string]$user.SID).Split('-')[-1]
        }
    }
}
```

---

### `Private/Safety/Resolve-AdmanGroup.ps1` (resolver, request-response, D-04)

**Analog:** `Private/Safety/Resolve-AdmanTarget.ps1` (Identity parameter set, `-Server` pinning)

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanGroup - resolve a group identity to its ADObject (D-04).
.DESCRIPTION
    Single-shot resolver for the group side of the two-object mutation matrix.
    Identity parameter set ONLY (-Identity + -Server + -Properties); no
    -SearchBase. Group-side has NO managed-OU scope requirement (D-04):
    protected groups live in CN=Users/Builtin and legitimate shared groups
    typically live outside managed user/computer OUs.
#>

Set-StrictMode -Version Latest

function Resolve-AdmanGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity
    )

    Get-ADGroup -Identity $Identity -Server $script:Config.DC `
        -Properties objectSid, objectClass, DistinguishedName -ErrorAction Stop
}
```

---

### `Private/Safety/Test-AdmanTargetAllowed.ps1` (MOD: create-branch)

**Analog:** self (existing). The create-branch is added at the TOP of the function — when `IsSynthetic` is true, run ONLY step (c) managed-OU scope against the parent OU DN, skip (a)/(b)/(d).

**Insertion point** (after line 40 `$Object` parameter, before line 42 `$reasons = ...`):
```powershell
    # D-01 create-branch: synthetic pre-create targets have no objectSid/memberOf.
    # Skip (a) gMSA objectClass, (b) deny-RID, (d) recursive protected-membership.
    # Run ONLY (c) managed-OU scope against the PARENT OU DN - creating under an
    # out-of-scope OU refuses closed.
    if ($Object.PSObject.Properties['IsSynthetic'] -and $Object.IsSynthetic) {
        $parentDn = [string]$Object.ParentOuDn
        $t = (ConvertTo-AdmanNormalizedDn -Dn $parentDn)
        $inScope = $false
        foreach ($root in @($script:Config.ManagedOUs)) {
            $r = (ConvertTo-AdmanNormalizedDn -Dn ([string]$root))
            if ([string]::IsNullOrEmpty($r)) { continue }
            if ($t -eq $r -or $t.EndsWith(',' + $r)) { $inScope = $true; break }
        }
        if (-not $inScope) {
            return @{ Allowed = $false; Reason = 'parent OU outside managed-OU scope' }
        }
        return @{ Allowed = $true; Reason = '' }
    }

    # ... existing (a)(b)(c)(d) unchanged below ...
```

---

### `Private/Safety/Test-AdmanLocalTargetAllowed.ps1` (policy, request-response)

**Analog:** `Private/Safety/Test-AdmanTargetAllowed.ps1` (lines 35-108 — same `Allowed/Reason` hashtable return shape, same accumulated-reasons pattern).

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanLocalTargetAllowed - local-account policy checks (D-02).
.DESCRIPTION
    Returns @{ Allowed = [bool]; Reason = [string] }. Three checks, accumulated:
      (a) refuse the built-in local Administrator RID-500 (match the local SID's
          RID, never the name - renamed-admin is the norm).
      (b) refuse targets that are members of the local Administrators
          S-1-5-32-544 group where the action would weaken that protection
          boundary (mirrors SAFE-06's spirit for local scope). Uses
          Get-LocalGroupMember with try/catch + WMI fallback (Pitfall 3).
      (c) machine-in-scope: the target machine's AD computer object (resolved
          via the existing Resolve-AdmanTarget on $env:COMPUTERNAME) must pass
          managed-OU scope, so adman can't touch local accounts on out-of-scope
          machines.
#>

Set-StrictMode -Version Latest

function Test-AdmanLocalTargetAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Verb
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # (a) local RID-500 (built-in Administrator) - match by RID, never by name.
    if ($Object.LocalRid -eq '500') {
        $reasons.Add('built-in local Administrator (RID-500)')
    }

    # (b) local Administrators S-1-5-32-544 membership - weakening protection.
    #     Get-LocalGroupMember can throw 0x80070534 on orphaned SIDs (Pitfall 3);
    #     fall back to WMI Win32_GroupUser. Refuse closed on enumeration failure.
    try {
        $admins = @(Get-LocalGroupMember -Name 'Administrators' -ErrorAction Stop)
    } catch {
        if ($_.Exception.Message -match '0x80070534|0x534') {
            $admins = @(Get-CimInstance -ClassName Win32_GroupUser |
                Where-Object { $_.GroupComponent.Name -eq 'Administrators' })
        } else {
            $reasons.Add("local Administrators enumeration failed: $($_.Exception.Message)")
            $admins = @()
        }
    }
    $isAdmin = @($admins | Where-Object { $_.SID -eq $Object.SID }).Count -gt 0
    if ($isAdmin -and $Verb -in @('Disable-LocalUser', 'Remove-LocalUser', 'Set-LocalUser')) {
        $reasons.Add('target is a member of local Administrators (S-1-5-32-544)')
    }

    # (c) machine-in-scope: the local machine's AD computer object must be in managed OUs.
    try {
        $computerObject = Resolve-AdmanTarget -Targets @($Object.Machine)
        $machineDecision = Test-AdmanTargetAllowed -Object $computerObject
        if (-not $machineDecision.Allowed) {
            $reasons.Add("machine '$($Object.Machine)' out of scope: $($machineDecision.Reason)")
        }
    } catch {
        $reasons.Add("machine-in-scope check failed: $($_.Exception.Message)")
    }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}
```

---

### `Private/Safety/Test-AdmanGroupAllowed.ps1` (policy, request-response, D-04)

**Analog:** `Private/Safety/Test-AdmanTargetAllowed.ps1` (same return shape, accumulated reasons).

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanGroupAllowed - group-side policy for two-object mutations (D-04).
.DESCRIPTION
    Returns @{ Allowed = [bool]; Reason = [string] }. Exactly three checks:
      (i)   the group's OWN objectSid is NOT in $script:ProtectedSIDs - direct
            SID equality, NOT IN_CHAIN. GRP-03 is identity, not membership.
      (ii)  group's SID NOT in $script:DenyRids.
      (iii) group is NOT a gMSA (defense-in-depth).
    The existing check (d) ("target is a recursive *member of* a protected
    group") is the WRONG relation for GRP-03 and is NOT reused here.
    ASYMMETRY: when -Operation is 'Remove-ADGroupMember', check (i) is SKIPPED
    (removing a principal FROM a protected group is remediation, allowed).
    No managed-OU scope on the group side (D-04).
#>

Set-StrictMode -Version Latest

function Test-AdmanGroupAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)]
        [ValidateSet('Add-ADGroupMember', 'Remove-ADGroupMember')]
        [string]$Operation
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # (i) direct SID equality against the protected set - SKIP on Remove (remediation).
    if ($Operation -eq 'Add-ADGroupMember') {
        $sidValue = ([System.Security.Principal.SecurityIdentifier]$Object.objectSid).Value
        if ($sidValue -in $script:ProtectedSIDs) {
            $reasons.Add("group is a protected identity (SID $sidValue)")
        }
    }

    # (ii) deny-RID.
    $rid = ([System.Security.Principal.SecurityIdentifier]$Object.objectSid).Value.Split('-')[-1]
    if ($rid -in $script:DenyRids) {
        $reasons.Add("deny-listed RID $rid")
    }

    # (iii) gMSA defense-in-depth.
    $objectClass = @($Object.objectClass)
    if ($objectClass -contains 'msDS-GroupManagedServiceAccount' -or
        $objectClass -contains 'msDS-ManagedServiceAccount') {
        $reasons.Add('gMSA/service account (objectClass)')
    }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}
```

---

### `Private/Local/Adman.Local.Write.ps1` (wrapper, request-response)

**Analog:** `Private/AD/Adman.AD.Write.ps1` (lines 23-147 — one wrapper per verb, exact same shape).

**Pattern to copy** (one wrapper per LocalAccounts verb; NO `-Server` parameter — LocalAccounts cmdlets have none):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Adman.Local.Write - the gate-only raw LocalAccounts write wrappers (SAFE-08
    extended, D-02).
.DESCRIPTION
    ONE thin wrapper per allow-listed local verb. The local mutation gate
    (Invoke-AdmanLocalMutation) is the ONLY caller. Each wrapper declares
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')], forwards
    -WhatIf:$WhatIfPreference -Confirm:$false, and iterates the resolved
    -Objects array. NO -Server parameter (LocalAccounts cmdlets have none).
    All LocalAccounts cmdlets DO declare SupportsShouldProcess on PS 5.1
    (verified premise correction) - truthful -WhatIf works through the wrappers.
#>

Set-StrictMode -Version Latest

function Adman.Local.Write.New-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'New-LocalUser')) {
            New-LocalUser -Name $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Disable-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Disable-LocalUser')) {
            Disable-LocalUser -Name $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Enable-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Enable-LocalUser')) {
            Enable-LocalUser -Name $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Set-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Set-LocalUser')) {
            Set-LocalUser -Name $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Remove-LocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Remove-LocalUser')) {
            Remove-LocalUser -Name $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Add-LocalGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Add-LocalGroupMember')) {
            Add-LocalGroupMember -Group $Parameters['Group'] -Member $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}

function Adman.Local.Write.Remove-LocalGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess("$($o.Machine)\$($o.Name)", 'Remove-LocalGroupMember')) {
            Remove-LocalGroupMember -Group $Parameters['Group'] -Member $o.Name @Parameters `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}
```

---

### `Private/AD/Adman.AD.Write.ps1` (MOD: +New-ADUser wrapper)

**Analog:** existing 9 wrappers in the same file. Append at the bottom.

```powershell
function Adman.AD.Write.New-ADUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Objects,
        [hashtable]$Parameters = @{}
    )
    foreach ($o in @($Objects)) {
        if ($PSCmdlet.ShouldProcess($o.DistinguishedName, 'New-ADUser')) {
            # D-01 single-call shape: -Name -SamAccountName -UserPrincipalName
            # -Path <parentOU> -AccountPassword <SecureString> -Enabled $true
            # -ChangePasswordAtLogon $true. -Server pinned per the existing pattern.
            New-ADUser -Name $o.Name `
                -SamAccountName $o.SamAccountName `
                -UserPrincipalName $Parameters['UserPrincipalName'] `
                -Path $o.ParentOuDn `
                -AccountPassword $Parameters['AccountPassword'] `
                -Enabled $true `
                -ChangePasswordAtLogon $true `
                -Server $script:Config.DC `
                -WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
        }
    }
}
```

---

### `Private/Safety/AdmanWriteVerbs.ps1` (MOD: +New-ADUser)

**Analog:** self (existing). Add `'New-ADUser'` to the array (line 28-37). The drift-test (Test 2 in `tests/Safety.GateOrder.Tests.ps1`) asserts the array equals the gate's `ValidateSet` and the wrapper set.

```powershell
    return @(
        'Disable-ADAccount'
        'Enable-ADAccount'
        'Move-ADObject'
        'Set-ADUser'
        'Set-ADComputer'
        'Set-ADAccountPassword'
        'Unlock-ADAccount'
        'Add-ADGroupMember'
        'Remove-ADGroupMember'
        'New-ADUser'                # D-01: the ONE create verb in v1
    )
```

---

### `Private/Utility/New-AdmanRandomPassword.ps1` (utility, transform)

**Analog:** `.planning/spikes/004-secure-password-generation/Invoke-Spike.ps1` lines 37-92 — **lift the recipe directly**, wrap as a module function returning `[securestring]`.

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    New-AdmanRandomPassword - CSPRNG-backed password generator (D-05).
.DESCRIPTION
    Implements the Spike 004 validated recipe:
      * [System.Security.Cryptography.RandomNumberGenerator]::Create()
      * Rejection sampling (no modulo bias)
      * Fisher-Yates shuffle
      * 76-char no-ambiguous alphabet (23 upper + 23 lower + 8 digit + 22 symbol)
      * Length 20 (config: security.passwordGeneration.length)
      * >= 1 char from each of 4 classes
    Returns a [securestring]. Get-Random is NEVER used (not a CSPRNG);
    [System.Web.Security.Membership]::GeneratePassword is NEVER used
    (Desktop-only, dead on PS7). The SecureString is born here and passed ONLY
    into Set-ADAccountPassword -NewPassword / New-ADUser -AccountPassword -
    never marshaled to plaintext (no BSTR conversion anywhere).
#>

Set-StrictMode -Version Latest

function New-AdmanRandomPassword {
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [int]$Length = 20
    )
    if ($Length -lt 4) { throw "Length must be >= 4 to guarantee all four character classes." }

    # 4 classes, no ambiguous glyphs (excludes 0 O l 1 I).
    $Upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()   # 23
    $Lower  = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray()   # 23
    $Digit  = '23456789'.ToCharArray()                   # 8
    $Symbol = '!@#$%^&*-_=+[]{}|;:,.<>?'.ToCharArray()   # 22
    $All    = $Upper + $Lower + $Digit + $Symbol         # 76

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        # Guarantee at least one of each class.
        $chars = [System.Collections.Generic.List[char]]::new($Length)
        $chars.Add($Upper[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Upper.Count)])
        $chars.Add($Lower[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Lower.Count)])
        $chars.Add($Digit[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Digit.Count)])
        $chars.Add($Symbol[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Symbol.Count)])

        # Fill the rest from the union alphabet.
        for ($i = $chars.Count; $i -lt $Length; $i++) {
            $chars.Add($All[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $All.Count)])
        }

        # Fisher-Yates shuffle using CSPRNG for the swap index.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = Get-AdmanCsprngIndex -Rng $rng -AlphabetSize ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }

        $plain = -join $chars
        $secure = [securestring]::new()
        foreach ($c in $plain.ToCharArray()) { $secure.AppendChar($c) }
        $secure.MakeReadOnly()
        return $secure
    }
    finally {
        $rng.Dispose()
    }
}

function Get-AdmanCsprngIndex {
    <#
        Rejection-sample a uniform byte into [0, $AlphabetSize).
        Avoids modulo bias: accept byte b only if b < AlphabetSize * floor(256/AlphabetSize).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.RandomNumberGenerator]$Rng,
        [Parameter(Mandatory)][int]$AlphabetSize
    )
    $limit = $AlphabetSize * [math]::Floor(256 / $AlphabetSize)
    $buf = [byte[]]::new(1)
    while ($true) {
        $Rng.GetBytes($buf)
        if ($buf[0] -lt $limit) { return $buf[0] % $AlphabetSize }
    }
}
```

---

### `Private/Utility/Test-AdmanPasswordComplexity.ps1` (utility, transform)

**Analog:** Spike 004 `Test-PasswordPolicy` (lines 94-108). Used by the prompt path (D-05) so a typed password meets the same bar as the generator.

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanPasswordComplexity - validate a SecureString meets the password
    policy (length + 4 character classes).
.DESCRIPTION
    Used by the D-05 Prompt path so a typed password is held to the SAME bar
    as the generator. Reads the SecureString ONCE into a transient plaintext
    buffer for validation, then discards it. Returns $true / throws with a
    precise reason. Length comes from security.passwordGeneration.length
    (default 20).
#>

Set-StrictMode -Version Latest

function Test-AdmanPasswordComplexity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][securestring]$Password,
        [int]$MinLength = 20
    )

    # Transient plaintext for validation only. BSTR is zeroed in finally.
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ($plain.Length -lt $MinLength) {
            throw "Password must be at least $MinLength characters (got $($plain.Length))."
        }
        if ($plain -notmatch '[A-Z]') { throw 'Password must contain at least one uppercase letter.' }
        if ($plain -notmatch '[a-z]') { throw 'Password must contain at least one lowercase letter.' }
        if ($plain -notmatch '\d')    { throw 'Password must contain at least one digit.' }
        if ($plain -notmatch '[^A-Za-z0-9]') { throw 'Password must contain at least one symbol.' }
        return $true
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
```

---

### `Private/Audit/Write-AdmanAudit.ps1` (MOD: +group field, +MACHINE\user shape)

**Analog:** self (existing). Two surgical changes:

**Change 1** — add `[string]$Group` parameter (after line 39 `[string]$Reason`):
```powershell
        [string]$Reason,
        [string]$Group,             # D-04: group DN for two-object mutations
        [string]$LocalMachine,      # D-02: machine name for local targets
        [switch]$WhatIf
```

**Change 2** — extend the `$rec` ordered hashtable (around line 63-79) to include the new fields conditionally:
```powershell
        # D-02 local-target shape: when Targets carry Machine+Name+SID (no DN),
        # the target field is "MACHINE\username" and sid is the local SID.
        $targetObjs = @($Targets)
        $targetDns = $targetObjs | ForEach-Object {
            if ($_.PSObject.Properties['DistinguishedName'] -and $_.DistinguishedName) {
                $_.DistinguishedName
            } elseif ($_.PSObject.Properties['Machine'] -and $_.PSObject.Properties['Name']) {
                "{0}\{1}" -f $_.Machine, $_.Name
            }
        }
        $targetDetail = @($targetObjs | ForEach-Object {
            if ($_.PSObject.Properties['DistinguishedName'] -and $_.DistinguishedName) {
                @{
                    dn          = $_.DistinguishedName
                    sid         = ($_.objectSid.Value)
                    objectClass = ($_.objectClass -join ',')
                }
            } else {
                @{
                    machine = $_.Machine
                    name    = $_.Name
                    sid     = ([string]$_.SID)
                }
            }
        })

        $rec = [ordered]@{
            tsUtc         = (Get-Date).ToUniversalTime().ToString('o')
            who           = "$env:USERDOMAIN\$env:USERNAME"
            userSid       = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            what          = $Verb
            scope         = ($script:Config.ManagedOUs -join '|')
            target        = ($targetDns -join '|')
            targets       = $targetDetail
            count         = $targetObjs.Count
            whatIf        = [bool]$WhatIf
            result        = $Result
            reason        = $Reason
            correlationId = $CorrelationId
            host          = $env:COMPUTERNAME
            psEdition     = $PSEdition
            moduleVersion = (Get-Module adman).Version.ToString()
        }
        # D-04: include group DN when present (two-object mutations).
        if (-not [string]::IsNullOrWhiteSpace($Group)) {
            $rec['group'] = $Group
        }
        $rec = $rec | ConvertTo-Json -Compress -Depth 5
```

The no-secret-key regex test in `tests/Audit.Schema.Tests.ps1` is extended to assert `group`, `machine`, `name` are NOT in the banned set (they aren't — none match `pass|secret|credential|apiKey|privateKey|key|token`).

---

### `Private/Safety/Confirm-AdmanAction.ps1` (MOD: per-verb threshold + two-object render)

**Analog:** self (existing). Two surgical changes:

**Change 1** — per-verb threshold override (D-03) at line 45:
```powershell
    $count = @($Targets).Count
    # D-03: Remove-LocalUser overrides bulkConfirmThreshold to 1 (typed-count even
    # at count=1; local accounts have no Recycle Bin).
    $threshold = if ($Verb -eq 'Remove-LocalUser') { 1 }
                 else { [int]$script:Config.safety.bulkConfirmThreshold }
```

**Change 2** — two-object rendering (D-04): the ShouldProcess message names both sides when `$Parameters['GroupIdentity']` is present. This requires Confirm-AdmanAction to accept an optional `-Group` parameter and render "Add jdoe (DN) to group X (DN)" in the prompt.

```powershell
    param(
        [Parameter(Mandatory)][string]$Verb,
        [Parameter(Mandatory)]$Targets,
        [string]$Group,             # D-04: group DN for two-object rendering
        [switch]$Force
    )
    # ...
    $targetDesc = if ($Group) { "$count object(s) -> group $Group" } else { "$count object(s)" }
    # Use $targetDesc in the Read-Host prompt and ShouldProcess call.
```

---

### `Private/Menu/Get-AdmanMenuDefinition.ps1` (MOD: +~15 write entries)

**Analog:** existing entries (lines 57-98). Append new PSCustomObject entries following the same shape. Section grouping is Claude's discretion — recommended: non-selectable separator lines.

```powershell
        # --- User writes (Phase 2) ---
        [pscustomobject]@{
            Label      = '--- User writes ---'
            Verb       = $null                    # Non-selectable separator
            PromptSpec = @()
            Properties = @()
        }
        [pscustomobject]@{
            Label      = 'Create user'
            Verb       = 'New-AdmanUser'
            PromptSpec = @(
                @{ Name = 'Name'; Prompt = 'Enter full name (CN)'; Required = $true }
                @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
                @{ Name = 'UserPrincipalName'; Prompt = 'Enter UPN'; Required = $true }
                @{ Name = 'ParentOuDn'; Prompt = 'Enter parent OU DN'; Required = $true }
                @{ Name = 'Password'; Prompt = 'Password source'; Required = $true
                   Type = 'GeneratedPassword'     # D-05 polymorphic Type
                   Choices = @('Generate (recommended)', 'Prompt') }
            )
            Properties = @()
        }
        [pscustomobject]@{
            Label      = 'Reset user password'
            Verb       = 'Set-AdmanUserPassword'
            PromptSpec = @(
                @{ Name = 'Identity'; Prompt = 'Enter sAMAccountName or DN'; Required = $true }
                @{ Name = 'Password'; Prompt = 'Password source'; Required = $true
                   Type = 'GeneratedPassword'
                   Choices = @('Generate (recommended)', 'Prompt') }
            )
            Properties = @()
        }
        # ... (Disable/Enable/Move/Unlock user, computer writes, local writes,
        #      group membership entries follow the same shape) ...
```

---

### `Private/Menu/Read-AdmanActionParams.ps1` (MOD: polymorphic Type)

**Analog:** self (existing). Add a `Type` switch inside the `foreach ($field in $PromptSpec)` loop (around line 44) to dispatch on `GeneratedPassword` / `SecureString`.

```powershell
    foreach ($field in $PromptSpec) {
        $name = [string]$field.Name
        $prompt = [string]$field.Prompt
        $required = [bool]$field.Required
        $type = if ($field.PSObject.Properties.Name -contains 'Type') { [string]$field.Type } else { 'Text' }
        $choices = $null
        if ($field.PSObject.Properties.Name -contains 'Choices') {
            $choices = $field.Choices
        }

        # D-05: polymorphic password handling.
        if ($type -eq 'GeneratedPassword') {
            # Sub-choice: Generate or Prompt (the Choices array carries the labels).
            for ($i = 0; $i -lt @($choices).Count; $i++) {
                Write-Host ("{0}. {1}" -f ($i + 1), $choices[$i])
            }
            $answer = Read-Host $prompt
            if ($answer -match '^[Qq]$') { throw 'ADMAN_QUIT' }
            if ($answer -match '^[Bb]$') { return $null }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le @($choices).Count) {
                if ($n -eq 1) {
                    # Generate path.
                    $params[$name] = New-AdmanRandomPassword -Length ([int]$script:Config.security.passwordGeneration.length)
                    $params["${name}Source"] = 'Generate'
                } else {
                    # Prompt path with complexity validation (D-05).
                    $p1 = Read-Host -AsSecureString 'Enter password'
                    $p2 = Read-Host -AsSecureString 'Confirm password'
                    # Equality check via transient BSTR (zeroed in finally).
                    # ... (equality + Test-AdmanPasswordComplexity call) ...
                    $params[$name] = $p1
                    $params["${name}Source"] = 'Prompt'
                }
                continue
            }
            Write-Host 'Invalid selection. Enter a number, B, or Q.'
            continue
        }

        # ... existing Choices / free-text branches unchanged ...
    }
```

---

### `Public/New-AdmanUser.ps1` (public-verb, request-response)

**Analog:** `Public/Find-AdmanUser.ps1` (shape: comment-based help, WR-01 init check, `Set-StrictMode`, `Escape-AdmanAdFilterLiteral` usage) + `Invoke-AdmanMutation` (the gate call).

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    New-AdmanUser - create a single AD user through the gate (USER-02, D-01).
.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and
    calls Invoke-AdmanMutation -Verb 'New-ADUser'. The gate fabricates a
    synthetic pre-create target via Resolve-AdmanCreateTarget, runs the
    create-branch scope check against the parent OU, performs the uniqueness
    pre-flight (sAMAccountName + CN within the parent OU must return zero
    hits), confirms, writes PENDING, calls Adman.AD.Write.New-ADUser, and
    writes OUTCOME. The same synthetic array feeds WhatIf and execute
    (SAFE-10). must-change-at-next-logon is ON by default (D-05).
.EXAMPLE
    New-AdmanUser -Name 'Alice Jones' -SamAccountName 'ajones' `
        -UserPrincipalName 'ajones@contoso.com' -ParentOuDn 'OU=Users,OU=Managed,DC=contoso,DC=com'
#>

Set-StrictMode -Version Latest

function New-AdmanUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SamAccountName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UserPrincipalName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ParentOuDn,
        [securestring]$AccountPassword,         # Optional; menu supplies via D-05
        [switch]$Force
    )

    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # sAMAccountName length validation (Pitfall 6).
    if ($SamAccountName.Length -gt 20) {
        throw "sAMAccountName '$SamAccountName' exceeds the 20-character limit."
    }

    # D-05: source the password if not supplied (Generate default).
    if (-not $AccountPassword) {
        $source = [string]$script:Config.security.passwordSource   # Generate|Prompt|Ask
        if ([string]::IsNullOrWhiteSpace($source)) { $source = 'Generate' }
        switch ($source) {
            'Generate' {
                $AccountPassword = New-AdmanRandomPassword -Length ([int]$script:Config.security.passwordGeneration.length)
            }
            'Prompt' {
                $p1 = Read-Host -AsSecureString 'Enter password'
                $p2 = Read-Host -AsSecureString 'Confirm password'
                # Equality + complexity validation (D-05).
                Test-AdmanPasswordComplexity -Password $p1 -MinLength ([int]$script:Config.security.passwordGeneration.length) | Out-Null
                # ... (BSTR equality check, ZeroFreeBSTR in finally) ...
                $AccountPassword = $p1
            }
            'Ask' {
                # 2-item numeric sub-choice (handled by Read-AdmanActionParams in menu path;
                # direct callers get Generate as the safe default).
                $AccountPassword = New-AdmanRandomPassword -Length ([int]$script:Config.security.passwordGeneration.length)
            }
        }
    }

    $params = @{
        Name              = $Name
        SamAccountName    = $SamAccountName
        UserPrincipalName = $UserPrincipalName
        ParentOuDn        = $ParentOuDn
        AccountPassword   = $AccountPassword
    }

    # The gate fabricates the synthetic target, runs the create-branch, confirms,
    # writes PENDING, calls the wrapper, writes OUTCOME. -WhatIf flows through.
    Invoke-AdmanMutation -Verb 'New-ADUser' -Targets @($SamAccountName) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
```

---

### `Public/Set-AdmanUserPassword.ps1`, `Unlock-AdmanUser.ps1`, `Move-AdmanUser.ps1`, etc. (public-verb, request-response)

**Analog:** same shape as `New-AdmanUser.ps1` above. Each Public verb is a thin prompt-and-dispatch that:
1. Validates init (WR-01 pattern from `Find-AdmanUser.ps1` lines 67-71).
2. Builds the `$Parameters` hashtable.
3. Calls `Invoke-AdmanMutation -Verb '<ADVerb>' -Targets @($Identity) -Parameters $params -Force:$Force`.

**PDCe-pinned unlock** (USER-05, Claude's discretion): the unlock verb's resolver + wrapper pin to `(Get-ADDomain).PDCEmulator` instead of `$script:Config.DC`. Implement as a per-verb `-Server` override in the gate's Parameters flow:
```powershell
# In Public/Unlock-AdmanUser.ps1:
$pdc = (Get-ADDomain -Server $script:Config.DC).PDCEmulator
$params = @{ Server = $pdc }   # Wrapper reads $Parameters['Server'] ?? $script:Config.DC
Invoke-AdmanMutation -Verb 'Unlock-ADAccount' -Targets @($Identity) -Parameters $params -Force:$Force
```

**Move destination validation** (USER-06/COMP-03, Claude's discretion): `Move-ADObject -TargetPath` destination OU MUST be validated under managed roots before confirm. Wire as a per-verb Parameters validator in the gate (reuses the D-01 parent-OU scope check).

---

### `Public/New-AdmanLocalUser.ps1`, `Remove-AdmanLocalUser.ps1`, etc. (public-verb, request-response)

**Analog:** same shape as `New-AdmanUser.ps1`, but calls `Invoke-AdmanLocalMutation` instead.

```powershell
function Remove-AdmanLocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [string]$ComputerName,                  # Phase 2: localhost only
        [switch]$Force
    )

    if (-not $script:Config -or -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Phase 2 localhost validation (D-02). Throws on non-localhost.
    $params = @{ ComputerName = $ComputerName }

    # D-03: Remove-LocalUser is irreversible (no Recycle Bin). The gate's
    # Confirm-AdmanAction overrides bulkConfirmThreshold to 1 for this verb
    # (typed-count even at count=1). Pre-delete state capture happens in the
    # audit record via the local SID + group memberships.
    Invoke-AdmanLocalMutation -Verb 'Remove-LocalUser' -Targets @($Name) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
```

---

### `Public/Add-AdmanGroupMember.ps1`, `Remove-AdmanGroupMember.ps1` (public-verb, request-response, D-04)

**Analog:** same shape, but the gate performs dual resolution.

```powershell
function Add-AdmanGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Identity,       # Member (user/computer)
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GroupIdentity,  # Group
        [switch]$Force
    )

    if (-not $script:Config -or -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    $params = @{ GroupIdentity = $GroupIdentity }

    # The gate resolves BOTH sides: member via Resolve-AdmanTarget (existing),
    # group via Resolve-AdmanGroup (new). Member-side checks run unchanged;
    # group-side runs Test-AdmanGroupAllowed (D-04). Audit record names both.
    Invoke-AdmanMutation -Verb 'Add-ADGroupMember' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false
}
```

---

### `rules/AdmanSafetyRules.psm1` (MOD: +LocalAccounts banned set)

**Analog:** self (existing). Add a second banned-verb set for LocalAccounts and a second rule function. The Pester AST guard (`tests/Safety.Gate.Tests.ps1`) is extended to assert no exported function names LocalAccounts mutation cmdlets directly.

```powershell
# Single source of truth (imported by tests/Safety.Gate.Tests.ps1 via Get-AdmanBannedWriteVerbs).
$script:AdmanBannedWriteVerbs = @(
    'Set-ADUser'
    'Set-ADComputer'
    'Set-ADObject'
    'Set-ADAccountPassword'
    'Disable-ADAccount'
    'Enable-ADAccount'
    'Unlock-ADAccount'
    'Move-ADObject'
    'New-ADUser'
    'New-ADComputer'
    'Add-ADGroupMember'
    'Remove-ADGroupMember'
    'Add-ADPrincipalGroupMembership'
    'Remove-ADObject'   # SAFE-09: hard-delete verb - must appear NOWHERE in Public/
)

# D-02: LocalAccounts mutation cmdlets - banned in Public/ (only Adman.Local.Write.*
# wrappers may name them, and only the two gates call wrappers).
$script:AdmanBannedLocalWriteVerbs = @(
    'New-LocalUser'
    'Disable-LocalUser'
    'Enable-LocalUser'
    'Set-LocalUser'
    'Remove-LocalUser'
    'Add-LocalGroupMember'
    'Remove-LocalGroupMember'
)

function Get-AdmanBannedLocalWriteVerbs {
    <#
    .SYNOPSIS
        Return the banned LocalAccounts write cmdlet set (D-02).
    #>
    [CmdletBinding()]
    param()
    return $script:AdmanBannedLocalWriteVerbs
}

# Extend Measure-AdmanPublicWriteSafety to also flag LocalAccounts verbs.
# (Same Find-AdmanBannedHit pattern; pass the union of both banned sets.)

Export-ModuleMember -Function @(
    'Get-AdmanBannedWriteVerbs'
    'Get-AdmanBannedLocalWriteVerbs'   # NEW
    'Test-AdmanIsPublicScope'
    'Find-AdmanBannedHit'
    'Test-AdmanBannedWriteAst'
    'Invoke-AdmanScopedGuard'
    'Measure-AdmanPublicWriteSafety'
)
```

---

### `tests/Mocks/ActiveDirectory.psm1` (MOD: +LocalAccounts mocks)

**Analog:** existing write stubs (lines 357-371). Append LocalAccounts mocks at the bottom and add to `Export-ModuleMember`.

```powershell
# --- LocalAccounts write stubs (SupportsShouldProcess keeps the lint gate clean) ---
function New-LocalUser { [CmdletBinding(SupportsShouldProcess)] param($Name, $Password) if ($PSCmdlet.ShouldProcess($Name, 'New-LocalUser (mock)')) { [pscustomobject]@{ Name = $Name; SID = 'S-1-5-21-111-222-333-1001'; Enabled = $true } } }
function Disable-LocalUser { [CmdletBinding(SupportsShouldProcess)] param($Name) if ($PSCmdlet.ShouldProcess($Name, 'Disable-LocalUser (mock)')) { } }
function Enable-LocalUser { [CmdletBinding(SupportsShouldProcess)] param($Name) if ($PSCmdlet.ShouldProcess($Name, 'Enable-LocalUser (mock)')) { } }
function Set-LocalUser { [CmdletBinding(SupportsShouldProcess)] param($Name, $Password) if ($PSCmdlet.ShouldProcess($Name, 'Set-LocalUser (mock)')) { } }
function Remove-LocalUser { [CmdletBinding(SupportsShouldProcess)] param($Name) if ($PSCmdlet.ShouldProcess($Name, 'Remove-LocalUser (mock)')) { } }
function Add-LocalGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Group, $Member) if ($PSCmdlet.ShouldProcess("$Group\$Member", 'Add-LocalGroupMember (mock)')) { } }
function Remove-LocalGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Group, $Member) if ($PSCmdlet.ShouldProcess("$Group\$Member", 'Remove-LocalGroupMember (mock)')) { } }

# --- LocalAccounts read stubs ---
function Get-LocalUser {
    [CmdletBinding()] param($Name)
    [pscustomobject]@{
        Name = $Name; SID = 'S-1-5-21-111-222-333-1001'; Enabled = $true
        FullName = 'Mock Local User'
    }
}
function Get-LocalGroupMember {
    [CmdletBinding()] param($Name)
    @([pscustomobject]@{ Name = 'MOCK\alice'; SID = 'S-1-5-21-111-222-333-1002' })
}

Export-ModuleMember -Function @(
    # ... existing exports ...
    'New-LocalUser', 'Disable-LocalUser', 'Enable-LocalUser', 'Set-LocalUser',
    'Remove-LocalUser', 'Add-LocalGroupMember', 'Remove-LocalGroupMember',
    'Get-LocalUser', 'Get-LocalGroupMember'
)
```

---

### `tests/Safety.GateOrder.Tests.ps1` (MOD: +create path + group matrix)

**Analog:** self (existing). Add new `It` blocks following the exact same pattern as Tests 1-6 (lines 119-271). New tests:

```powershell
It 'Test 7: create path - New-ADUser flows through Resolve-AdmanCreateTarget and the create-branch' {
    # Mock Resolve-AdmanCreateTarget to return a synthetic target.
    # Mock Test-AdmanTargetAllowed to assert the create-branch was taken
    # (IsSynthetic=$true, ParentOuDn scope check only).
    # Assert the fixed order is preserved.
}

It 'Test 8: group matrix - Add-ADGroupMember resolves BOTH member and group, runs per-side checks' {
    # Mock Resolve-AdmanTarget (member) and Resolve-AdmanGroup (group).
    # Mock Test-AdmanTargetAllowed (member) and Test-AdmanGroupAllowed (group).
    # Assert Write-AdmanAudit receives the 'group' field.
}

It 'Test 9: ValidateSet includes New-ADUser; drift-test still passes' {
    # Extend the existing Test 2 assertion.
}
```

---

### `tests/Safety.Gate.Tests.ps1` (MOD: +LocalAccounts AST guard)

**Analog:** self (existing). Add a new `It` block asserting no Public/ file names a LocalAccounts mutation cmdlet.

```powershell
It 'Public/<file> contains no direct LocalAccounts write call (D-02)' {
    $banned = Get-AdmanBannedLocalWriteVerbs
    $files = @(Get-ChildItem -Path $script:PublicDir -Filter *.ps1 -Recurse -File)
    $allHits = @()
    foreach ($f in $files) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $f.FullName, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        $names = foreach ($c in $calls) {
            $n = $c.GetCommandName()
            if (-not $n) { $n = $c.CommandElements[0].Extent.Text }
            if ($n) { $n }
        }
        $allHits += @($names | Where-Object { $_ -in $banned })
    }
    $allHits | Should -BeNullOrEmpty -Because 'Public/ verbs must route local writes through Invoke-AdmanLocalMutation'
}
```

---

### `tests/Audit.Schema.Tests.ps1` (MOD: +group field + MACHINE\user shape)

**Analog:** self (existing). Extend Test 1 to assert the `group` field appears when present, and add a new test for the local-target shape.

```powershell
It 'Test 1b: a group-mutation record includes the group field alongside target' {
    # Write a record with -Group 'CN=Domain Admins,...' and assert the parsed
    # JSON has both 'target' (member DN) and 'group' (group DN).
}

It 'Test 1c: a local-target record uses MACHINE\username shape (no DN)' {
    # Write a record with a local target (Machine+Name+SID, no DN) and assert
    # the target field is "MACHINE\username" and targets[0].sid is the local SID.
}

It 'Test 2d: group/machine/name keys do NOT trip the no-secret regex' {
    'group', 'machine', 'name' | ForEach-Object {
        $_ | Should -Not -Match $script:SecretNameRegex
    }
}
```

---

### `tests/User.Create.Tests.ps1`, `User.Password.Tests.ps1`, etc. (NEW test files)

**Analog:** `tests/Find.User.Tests.ps1` (Public verb contract tests) + `tests/Safety.GateOrder.Tests.ps1` (gate flow tests). Each new test file follows the same BeforeAll pattern (PSFramework stub on $TestDrive, import mocks, import module, seed `$script:Config`).

```powershell
#Requires -Modules Pester
<#
.SYNOPSIS
    USER-02 contract tests for New-AdmanUser.
.DESCRIPTION
    Pins the D-01 create-path contract:
      * New-AdmanUser calls Invoke-AdmanMutation -Verb 'New-ADUser'.
      * The gate fabricates a synthetic pre-create target (IsSynthetic=$true).
      * The create-branch skips gMSA/deny-RID/protected-membership checks.
      * The managed-OU scope check runs against the parent OU DN.
      * Uniqueness pre-flight refuses closed on sAMAccountName/CN collision.
      * must-change-at-next-logon is ON by default.
    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1.
#>

BeforeAll {
    # ... (PSFramework stub, import mocks, import module, seed config) ...
    # Copy from tests/Find.User.Tests.ps1 lines 25-71.
}

Describe 'New-AdmanUser: create path (USER-02, D-01)' -Tag 'Unit' {
    It 'calls Invoke-AdmanMutation with -Verb New-ADUser' {
        Mock Invoke-AdmanMutation -ModuleName adman { }
        New-AdmanUser -Name 'Alice' -SamAccountName 'alice' `
            -UserPrincipalName 'alice@mock.local' -ParentOuDn 'OU=Managed,DC=mock,DC=local'
        Should -Invoke Invoke-AdmanMutation -ModuleName adman -Times 1 -ParameterFilter {
            $Verb -eq 'New-ADUser'
        }
    }

    It 'refuses when sAMAccountName exceeds 20 characters' {
        { New-AdmanUser -Name 'Alice' -SamAccountName ('a' * 21) `
            -UserPrincipalName 'alice@mock.local' -ParentOuDn 'OU=Managed,DC=mock,DC=local' } |
            Should -Throw '*20-character*'
    }

    # ... more tests ...
}
```

---

### `adman.psd1` (MOD: +new Public verb exports)

**Analog:** self (existing). Append the new Public verb names to `FunctionsToExport` (line 53). Keep the explicit list (NEVER `'*'`).

```powershell
    FunctionsToExport = @(
        'Initialize-Adman', 'Start-Adman',
        'Get-AdmanConfig', 'Set-AdmanConfig', 'Export-AdmanConfig', 'Import-AdmanConfig',
        'Test-AdmanCapability',
        'Find-AdmanUser', 'Find-AdmanComputer',
        'Get-AdmanStaleReport', 'Get-AdmanAccountStateReport', 'Get-AdmanRecoveryPostureReport',
        'Format-AdmanReport', 'Export-AdmanReportCsv', 'Export-AdmanReportHtml',
        'Get-AdmanInventoryReport',
        # Phase 2: single-object lifecycle writes
        'New-AdmanUser', 'Disable-AdmanUser', 'Enable-AdmanUser',
        'Move-AdmanUser', 'Set-AdmanUserPassword', 'Unlock-AdmanUser',
        'Disable-AdmanComputer', 'Enable-AdmanComputer', 'Move-AdmanComputer',
        'Reset-AdmanComputerAccount',
        'New-AdmanLocalUser', 'Set-AdmanLocalUser', 'Remove-AdmanLocalUser',
        'Add-AdmanLocalGroupMember', 'Remove-AdmanLocalGroupMember',
        'Add-AdmanGroupMember', 'Remove-AdmanGroupMember'
    )
```

---

## Shared Patterns

### Module-wide fail-fast + StrictMode
**Source:** `adman.psm1` line 10, every Private/Public file
**Apply to:** ALL new files
```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'   # Module-wide in adman.psm1; per-file via Set-StrictMode
```

### File header doc block
**Source:** Every existing file (e.g., `Private/Safety/Invoke-AdmanMutation.ps1` lines 1-30)
**Apply to:** ALL new files
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    <One-line summary with requirement ID and decision ID.>
.DESCRIPTION
    <Multi-paragraph description of the pattern, the invariant it enforces,
    and any pitfalls it avoids. Reference the CONTEXT.md decision (D-01..D-05)
    and the SAFE-* invariant where applicable.>
#>

Set-StrictMode -Version Latest
```

### `-Server $script:Config.DC` pinning
**Source:** `Private/AD/Adman.AD.Write.ps1` (every wrapper), `Private/Safety/Resolve-AdmanTarget.ps1` line 37
**Apply to:** ALL AD cmdlet calls (the ONE sanctioned exception is PDCe-pinned unlock)
```powershell
-Server $script:Config.DC
```

### ShouldProcess + ConfirmImpact='High' on state-changing functions
**Source:** Every wrapper in `Private/AD/Adman.AD.Write.ps1`, `Private/Safety/Invoke-AdmanMutation.ps1` line 35
**Apply to:** ALL write wrappers, BOTH gates, ALL Public write verbs
```powershell
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
```

### `-WhatIf:$WhatIfPreference -Confirm:$false` forwarding
**Source:** `Private/AD/Adman.AD.Write.ps1` lines 32, 45, 58, etc.
**Apply to:** ALL write wrappers (no per-object re-prompt; the gate already confirmed once)
```powershell
-WhatIf:$WhatIfPreference -Confirm:$false -ErrorAction Stop
```

### Allowed/Reason hashtable return from policy checks
**Source:** `Private/Safety/Test-AdmanTargetAllowed.ps1` lines 104-107
**Apply to:** `Test-AdmanLocalTargetAllowed`, `Test-AdmanGroupAllowed`, the create-branch in `Test-AdmanTargetAllowed`
```powershell
return @{
    Allowed = ($reasons.Count -eq 0)
    Reason  = ($reasons -join '; ')
}
```

### Accumulated reasons (no early return)
**Source:** `Private/Safety/Test-AdmanTargetAllowed.ps1` lines 42-102
**Apply to:** ALL policy check functions
```powershell
$reasons = [System.Collections.Generic.List[string]]::new()
# ... each check ADDS a reason; never returns early ...
return @{ Allowed = ($reasons.Count -eq 0); Reason = ($reasons -join '; ') }
```

### Managed-OU scope check (component-boundary anchored)
**Source:** `Private/Safety/Test-AdmanTargetAllowed.ps1` lines 66-77
**Apply to:** create-branch (against parent OU), machine-in-scope check, Move destination validation
```powershell
$t = (ConvertTo-AdmanNormalizedDn -Dn $targetDn)
$inScope = $false
foreach ($root in @($script:Config.ManagedOUs)) {
    $r = (ConvertTo-AdmanNormalizedDn -Dn ([string]$root))
    if ([string]::IsNullOrEmpty($r)) { continue }
    if ($t -eq $r -or $t.EndsWith(',' + $r)) { $inScope = $true; break }
}
if (-not $inScope) { $reasons.Add('outside managed-OU scope') }
```

### WR-01 init check in Public verbs
**Source:** `Public/Find-AdmanUser.ps1` lines 67-71
**Apply to:** ALL new Public verbs
```powershell
if (-not $script:Config -or
    -not $script:Config.PSObject.Properties['ManagedOUs'] -or
    -not $script:Config.ManagedOUs) {
    throw 'adman is not initialized. Run Initialize-Adman first.'
}
```

### Pester test BeforeAll pattern (PSFramework stub + mocks + module import)
**Source:** `tests/Find.User.Tests.ps1` lines 25-71, `tests/Safety.GateOrder.Tests.ps1` lines 28-110
**Apply to:** ALL new test files
```powershell
BeforeAll {
    # PSFramework stub on $TestDrive (exact version 1.14.457).
    # Import tests/Mocks/ActiveDirectory.psm1 -Force FIRST.
    # Import adman.psd1 -Force.
    # Seed $script:Config via & (Get-Module adman) { $script:Config = ... }.
}
```

### Pester 6 mock assertion syntax
**Source:** `tests/Safety.GateOrder.Tests.ps1` lines 121, 155, 179
**Apply to:** ALL new test files
```powershell
Mock <FunctionName> -ModuleName adman { <body> }
Should -Invoke <FunctionName> -ModuleName adman -Times <N> [-ParameterFilter { ... }]
# NEVER use Assert-MockCalled / Assert-VerifiableMock (removed in Pester 6).
```

### No-secret-key regex (audit schema)
**Source:** `tests/Audit.Schema.Tests.ps1` line 61
**Apply to:** audit schema extensions (group, machine, name fields)
```powershell
$script:SecretNameRegex = 'pass(word)?|secret|credential|apiKey|privateKey|key|token'
# New fields (group, machine, name) must NOT match this regex.
```

### Escape-AdmanAdFilterLiteral for -Filter strings
**Source:** `Public/Find-AdmanUser.ps1` lines 84-93, `Private/Utility/Escape-AdmanAdFilterLiteral.ps1`
**Apply to:** uniqueness pre-flight lookup (D-01), any user-supplied value interpolated into `-Filter`
```powershell
$esc = Escape-AdmanAdFilterLiteral -Value $userInput
$filter = "sAMAccountName -eq '$esc'"
```

### Escape-AdmanLdapFilterValue for -LDAPFilter strings
**Source:** `Private/Safety/Test-AdmanTargetAllowed.ps1` lines 83-89, `Private/Safety/Escape-AdmanLdapFilterValue.ps1`
**Apply to:** protected-membership IN_CHAIN query (existing), any RFC 4515 assertion value
```powershell
$dnEsc = Escape-AdmanLdapFilterValue -Value $targetDn
```

## No Analog Found

**None.** Every new artifact in Phase 2 has a direct in-repo analog:
- The gate, resolver, policy check, wrapper, confirm, audit, menu, and test patterns are all established in Phase 0/1.
- The CSPRNG password generator is lifted directly from Spike 004 (validated recipe).
- The only truly new code is the *composition* of existing patterns (e.g., the local gate mirrors the AD gate with a different resolver/policy/wrapper namespace).

## Metadata

**Analog search scope:** `Private/`, `Public/`, `tests/`, `rules/`, `.planning/spikes/`
**Files scanned:** 25 Private, 16 Public, 38 test, 1 rules, 2 spike
**Pattern extraction date:** 2026-07-15
