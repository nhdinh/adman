# Phase 04: Bulk & Workflows (highest blast radius, last) - Pattern Map

**Mapped:** 2026-07-17
**Files analyzed:** 20
**Analogs found:** 18 / 20

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Public/Invoke-AdmanBulkAction.ps1` | controller/engine | batch | `Private/Safety/Invoke-AdmanMutation.ps1` | exact |
| `Public/Start-AdmanUserOnboarding.ps1` | workflow | request-response | `Public/New-AdmanUser.ps1` | exact |
| `Public/Start-AdmanUserOffboarding.ps1` | workflow | request-response | `Public/Disable-AdmanUser.ps1` + `Public/Remove-AdmanGroupMember.ps1` | role-match |
| `Public/Restore-AdmanQuarantinedUser.ps1` | workflow | request-response | `Public/Move-AdmanUser.ps1` + `Public/Add-AdmanGroupMember.ps1` | role-match |
| `Private/Bulk/Import-AdmanBulkCsv.ps1` | utility | file-I/O | none in repo | no analog |
| `Private/Bulk/ConvertTo-AdmanBulkInput.ps1` | utility | transform | `Private/Reporting/ConvertTo-AdmanResult.ps1` | role-match |
| `Private/Workflow/Get-AdmanOffboardingState.ps1` | utility/query | file-I/O | `Private/Audit/Find-AdmanAuditOrphans.ps1` | role-match |
| `Private/Menu/Get-AdmanMenuDefinition.ps1` | config/menu | request-response | same file (extend) | self |
| `Private/Menu/Read-AdmanActionParams.ps1` | utility | request-response | same file (extend if new Type) | self |
| `Private/Audit/Write-AdmanAudit.ps1` | service/utility | event-driven | same file (extend) | self |
| `config/adman.schema.json` | config | request-response | same file (extend) | self |
| `config/adman.defaults.json` | config | request-response | same file (extend) | self |
| `adman.psd1` | config | request-response | same file (extend) | self |
| `tests/Bulk.Engine.Tests.ps1` | test | batch | `tests/User.Disable.Tests.ps1` + `tests/Group.Add.Tests.ps1` | role-match |
| `tests/Bulk.Csv.Tests.ps1` | test | file-I/O | none in repo | no analog |
| `tests/Workflow.Onboarding.Tests.ps1` | test | request-response | `tests/User.Create.Tests.ps1` | role-match |
| `tests/Workflow.Offboarding.Tests.ps1` | test | request-response | `tests/User.Disable.Tests.ps1` + `tests/Group.Remove.Tests.ps1` | role-match |
| `tests/Workflow.Restore.Tests.ps1` | test | request-response | `tests/User.Move.Tests.ps1` + `tests/Group.Add.Tests.ps1` | role-match |
| `tests/Menu.BulkWorkflow.Tests.ps1` | test | request-response | `tests/Menu.Tests.ps1` | exact |
| `tests/Module.Manifest.Tests.ps1` | test | request-response | same file (extend) | self |

## Pattern Assignments

### `Public/Invoke-AdmanBulkAction.ps1` (controller/engine, batch)

**Analog:** `Private/Safety/Invoke-AdmanMutation.ps1`

**File header + StrictMode pattern** (lines 1-41):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanBulkAction - generic gated bulk engine (BULK-01..04).

.DESCRIPTION
    Normalizes search/CSV input, resolves each target once, runs the same
    deny/scope/protected filtering as single-object verbs, applies the
    configurable bulk.maxCount cap after filtering, performs one typed-count
    confirmation for the filtered set, then loops calling Invoke-AdmanMutation
    per item with try/catch/continue.
#>

Set-StrictMode -Version Latest
```

**Cmdlet binding + SupportsShouldProcess pattern** (lines 43-55):
```powershell
function Invoke-AdmanMutation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Disable-ADAccount', 'Enable-ADAccount', 'Move-ADObject',
            'Add-ADGroupMember', 'Remove-ADGroupMember')]
        [string]$Verb,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [string]$Path,              # CSV ingestion
        [string]$TargetPath,        # Move destination for entire job
        [string]$GroupIdentity,     # Group ops
        [switch]$Force
    )
```

**Init check pattern** (from `Public/New-AdmanUser.ps1` lines 92-97):
```powershell
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }
```

**Per-item loop + result-collection pattern** (from `Invoke-AdmanMutation.ps1` lines 220-235 and RESEARCH.md Pattern 3):
```powershell
    $perItem = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $allowed) {
        try {
            Invoke-AdmanMutation -Verb $mappedGateVerb -Targets @($item.Identity) `
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
```

**Summary result shape** (from `Invoke-AdmanMutation.ps1` lines 246-254 and RESEARCH.md Pattern 3):
```powershell
    return [pscustomobject]@{
        Total     = $allowed.Count + $denied.Count
        Succeeded = ($perItem | Where-Object Result -eq 'Success').Count
        Failed    = ($perItem | Where-Object Result -eq 'Failed').Count
        Denied    = $denied.Count
        WhatIf    = [bool]$WhatIfPreference
        PerItem   = $perItem.ToArray()
    }
```

**Cap-after-filter pattern** (from `Invoke-AdmanMutation.ps1` lines 191-192 and RESEARCH.md Pattern 2):
```powershell
    Assert-AdmanBulkPolicy -Count $allowed.Count -EnforceCap | Out-Null
```

**Confirmation pattern** (from `Invoke-AdmanMutation.ps1` lines 196-201):
```powershell
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force
    if ($confirm.Outcome -eq 'Declined') { throw 'Operator declined.' }
```

---

### `Public/Start-AdmanUserOnboarding.ps1` (workflow, request-response)

**Analog:** `Public/New-AdmanUser.ps1`

**File header + StrictMode pattern** (from `Public/New-AdmanUser.ps1` lines 1-59):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Start-AdmanUserOnboarding - gated new-user workflow (FLOW-01).

.DESCRIPTION
    Builds a user creation request from the config-driven onboarding template,
    calls New-AdmanUser, then calls Add-AdmanGroupMember for each baseline group.
    Any step failure stops subsequent steps for that target and logs FAIL.
#>

Set-StrictMode -Version Latest

function Start-AdmanUserOnboarding {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LastName,

        [switch]$Force
    )
```

**Template-driven parameter build** (from `Public/New-AdmanUser.ps1` lines 167-177 + Phase 4 D-09..D-11):
```powershell
    $template = $script:Config.templates.onboarding
    $sam = ($template.NamePattern -f $FirstName, $LastName).ToLower()
    $upn = "$sam@$($script:Config.Domain)"

    New-AdmanUser -Name "$FirstName $LastName" -SamAccountName $sam `
        -UserPrincipalName $upn -ParentOuDn $template.ParentOuDn -Force:$Force `
        -WhatIf:$WhatIfPreference

    foreach ($g in $template.BaselineGroups) {
        Add-AdmanGroupMember -Identity $sam -GroupIdentity $g -Force:$Force `
            -WhatIf:$WhatIfPreference
    }
```

**Mid-workflow failure pattern** (from `Invoke-AdmanMutation.ps1` lines 222-235):
```powershell
    try {
        # workflow steps
    } catch {
        Write-AdmanAudit -Verb 'Start-AdmanUserOnboarding' -Target $sam `
            -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$WhatIfPreference
        throw
    }
```

**Baseline-group validation pattern** (from `Private/Safety/Invoke-AdmanMutation.ps1` lines 131-135):
```powershell
    foreach ($g in $template.BaselineGroups) {
        $groupObj = Resolve-AdmanGroup -Identity $g
        $decision = Test-AdmanGroupAllowed -Object $groupObj -Operation 'Add-ADGroupMember'
        if (-not $decision.Allowed) {
            throw "Baseline group '$g' refused: $($decision.Reason)"
        }
    }
```

---

### `Public/Start-AdmanUserOffboarding.ps1` (workflow, request-response)

**Analog:** `Public/Disable-AdmanUser.ps1` + `Public/Remove-AdmanGroupMember.ps1`

**Public-verb shell pattern** (from `Public/Disable-AdmanUser.ps1` lines 25-44):
```powershell
function Start-AdmanUserOffboarding {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [switch]$Force
    )

    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # ...
}
```

**Composing existing Public verbs** (from RESEARCH.md Pattern 4 + Phase 4 D-19..D-21):
```powershell
    $user = Resolve-AdmanTarget -Targets @($Identity) | Select-Object -First 1
    $originalOu = [string]$user.DistinguishedName -replace '^[^,]+,'
    $quarantineOu = $script:Config.templates.offboarding.quarantineOU

    # Validate quarantine OU is in managed scope (same pattern as Move-AdmanUser).
    $tp = ConvertTo-AdmanNormalizedDn -Dn $quarantineOu
    $tpInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
    }
    if (-not $tpInScope) {
        throw "Quarantine OU '$quarantineOu' is outside managed OU scope."
    }

    try {
        Disable-AdmanUser -Identity $Identity -Force:$Force -WhatIf:$WhatIfPreference

        $groupsToRemove = @($user.memberOf | Where-Object {
            # filter out protected groups; record kept groups elsewhere
        })

        foreach ($g in $groupsToRemove) {
            Remove-AdmanGroupMember -Identity $Identity -GroupIdentity $g `
                -Force:$Force -WhatIf:$WhatIfPreference
        }

        Move-AdmanUser -Identity $Identity -TargetPath $quarantineOu `
            -Force:$Force -WhatIf:$WhatIfPreference

        Write-AdmanAudit -Verb 'Start-AdmanUserOffboarding' -Target $user `
            -Result 'Success' -OriginalOU $originalOu -Groups $groupsToRemove `
            -WhatIf:$WhatIfPreference
    } catch {
        Write-AdmanAudit -Verb 'Start-AdmanUserOffboarding' -Target $user `
            -Result 'Failure' -Reason $_.Exception.Message -WhatIf:$WhatIfPreference
        throw
    }
```

---

### `Public/Restore-AdmanQuarantinedUser.ps1` (workflow, request-response)

**Analog:** `Public/Move-AdmanUser.ps1` + `Public/Add-AdmanGroupMember.ps1`

**Move validation pattern** (from `Public/Move-AdmanUser.ps1` lines 57-68):
```powershell
    $tp = ConvertTo-AdmanNormalizedDn -Dn $TargetPath
    $tpInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
    }
    if (-not $tpInScope) {
        throw "TargetPath '$TargetPath' is outside managed OU scope."
    }
```

**Restore composition pattern** (from RESEARCH.md + Phase 4 D-22):
```powershell
    $state = Get-AdmanOffboardingState -Identity $Identity
    if (-not $state) { throw "No offboarding record found for '$Identity'." }

    Enable-AdmanUser -Identity $Identity -Force:$Force -WhatIf:$WhatIfPreference

    foreach ($g in $state.Groups) {
        Add-AdmanGroupMember -Identity $Identity -GroupIdentity $g `
            -Force:$Force -WhatIf:$WhatIfPreference
    }

    Move-AdmanUser -Identity $Identity -TargetPath $state.OriginalOU `
        -Force:$Force -WhatIf:$WhatIfPreference
```

---

### `Private/Bulk/Import-AdmanBulkCsv.ps1` (utility, file-I/O)

**Analog:** none in repo (use RESEARCH.md pattern)

**Strict CSV schema validation pattern** (from RESEARCH.md Code Examples lines 467-487):
```powershell
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

---

### `Private/Bulk/ConvertTo-AdmanBulkInput.ps1` (utility, transform)

**Analog:** `Private/Reporting/ConvertTo-AdmanResult.ps1`

**Function shape + pipeline pattern** (from `ConvertTo-AdmanResult.ps1` lines 32-42):
```powershell
function ConvertTo-AdmanBulkInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Disable','Enable','Move','AddGroup','RemoveGroup')]
        [string]$Action,

        [string]$TargetPath,
        [string]$GroupIdentity
    )
    process {
        # ...
    }
}
```

**Object mapping pattern** (from `ConvertTo-AdmanResult.ps1` lines 54-64 + RESEARCH.md Pattern 1):
```powershell
    process {
        $objectType = if ($InputObject.PSObject.Properties['ObjectType'] -and $InputObject.ObjectType) {
            $InputObject.ObjectType
        } else { 'User' }

        [pscustomobject]@{
            ObjectType    = $objectType
            Identity      = [string]$InputObject.DistinguishedName
            Action        = $Action
            TargetPath    = $TargetPath
            GroupIdentity = $GroupIdentity
        }
    }
```

---

### `Private/Workflow/Get-AdmanOffboardingState.ps1` (utility/query, file-I/O)

**Analog:** `Private/Audit/Find-AdmanAuditOrphans.ps1`

**Audit file enumeration pattern** (from `Find-AdmanAuditOrphans.ps1` lines 34-52):
```powershell
    $records = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $LookbackDays; $i++) {
        $day = (Get-Date).AddDays(-$i)
        $name = 'audit-{0}.jsonl' -f $day.ToString('yyyyMMdd')
        $path = Join-Path $AuditDir $name
        if (-not (Test-Path -LiteralPath $path)) { continue }

        foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $records.Add(($line | ConvertFrom-Json -ErrorAction Stop))
            } catch {
                continue
            }
        }
    }
```

**Filtering + latest-record pattern** (from RESEARCH.md Code Examples lines 572-591):
```powershell
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
```

---

### `Private/Menu/Get-AdmanMenuDefinition.ps1` (config/menu, request-response)

**Analog:** same file (extend)

**Menu-entry shape pattern** (from lines 105-115):
```powershell
        [pscustomobject]@{
            Label           = 'Bulk disable users'
            Verb            = 'Invoke-AdmanBulkAction'
            PromptSpec      = @(
                @{ Name = 'Path'; Prompt = 'Enter CSV path (optional; press Enter to use pipeline)'; Required = $false }
                @{ Name = 'Action'; Prompt = 'Action'; Required = $true }
            )
            Properties      = $emptyProperties
            FixedParameters = $null
        }
```

**Separator helper pattern** (from lines 94-103):
```powershell
    $newSeparator = {
        param([string]$Label)
        [pscustomobject]@{
            Label           = $Label
            Verb            = $null
            PromptSpec      = @()
            Properties      = $emptyProperties
            FixedParameters = $null
        }
    }
```

---

### `Private/Menu/Read-AdmanActionParams.ps1` (utility, request-response)

**Analog:** same file (extend if new Type)

**Polymorphic Type dispatch pattern** (from lines 118-122, 222-243):
```powershell
        $type = 'Text'
        if ((& $hasKey 'Type') -and (& $getVal 'Type')) {
            $type = [string](& $getVal 'Type')
        }

        while (-not $resolved) {
            if ($type -eq 'GeneratedPassword') { ... }
            elseif ($null -ne $choices -and @($choices).Count -gt 0) { ... }
            else { ... }
        }
```

**Reserved-input contract pattern** (from lines 132-136, 246-253):
```powershell
                if ($answer -match '^[Qq]$') { throw 'ADMAN_QUIT' }
                if ($answer -match '^[Bb]$') { return $null }
```

---

### `Private/Audit/Write-AdmanAudit.ps1` (service/utility, event-driven)

**Analog:** same file (extend)

**Optional field extension pattern** (from lines 151-155):
```powershell
        # D-04: emit the group field ONLY when -Group is supplied (preserves the exact-key-set
        # Test 1 invariant for non-group records).
        if (-not [string]::IsNullOrEmpty($Group)) {
            $rec['group'] = $Group
        }
```

**Parameter addition pattern** (from lines 37-50):
```powershell
function Write-AdmanAudit {
    [CmdletBinding()]
    param(
        [string]$CorrelationId,
        [string]$Verb,
        $Targets,
        $Target,
        [Parameter(Mandatory)]
        [ValidateSet('PENDING', 'Success', 'Failure', 'Refused', 'Cancelled')]
        [string]$Result,
        [string]$Reason,
        [string]$Group,
        [string]$OriginalOU,
        [string[]]$Groups,
        [switch]$WhatIf
    )
```

**Conditional record-field pattern** (from lines 151-155, adapted for offboarding):
```powershell
        if (-not [string]::IsNullOrEmpty($OriginalOU)) {
            $rec['originalOU'] = $OriginalOU
        }
        if ($null -ne $Groups -and $Groups.Count -gt 0) {
            $rec['groups'] = $Groups
        }
```

---

### `config/adman.schema.json` (config, request-response)

**Analog:** same file (extend)

**Object property extension pattern** (from lines 39-61):
```json
    "templates": {
      "type": "object",
      "required": ["onboarding", "offboarding"],
      "properties": {
        "onboarding": {
          "type": "object",
          "required": ["ParentOuDn", "BaselineGroups", "NamePattern"],
          "properties": {
            "ParentOuDn": { "type": "string" },
            "BaselineGroups": {
              "type": "array",
              "items": { "type": "string" }
            },
            "NamePattern": { "type": "string" }
          }
        },
        "offboarding": {
          "type": "object",
          "required": ["quarantineOU"],
          "properties": {
            "quarantineOU": { "type": "string" }
          }
        }
      }
    }
```

**Adding to required list** (from lines 7-20):
```json
  "required": [
    "ManagedOUs",
    "DenyList",
    "safety",
    "bulk",
    "AuditDir",
    "ReportDir",
    "transport",
    "credentialPolicy",
    "AdmanProtectedGroup",
    "DC",
    "delegatedAdminGroup",
    "security",
    "templates"
  ]
```

---

### `config/adman.defaults.json` (config, request-response)

**Analog:** same file (extend)

**Default value pattern** (from lines 3-48):
```json
  "templates": {
    "onboarding": {
      "ParentOuDn": "OU=Users,OU=Managed,DC=contoso,DC=local",
      "BaselineGroups": [],
      "NamePattern": "{0}.{1}"
    },
    "offboarding": {
      "quarantineOU": "OU=Quarantine,OU=Managed,DC=contoso,DC=local"
    }
  }
```

---

### `adman.psd1` (config, request-response)

**Analog:** same file (extend)

**FunctionsToExport extension pattern** (from line 53):
```powershell
    FunctionsToExport = @('Initialize-Adman', 'Start-Adman', ..., 'Invoke-AdmanBulkAction', 'Start-AdmanUserOnboarding', 'Start-AdmanUserOffboarding', 'Restore-AdmanQuarantinedUser')
```

---

### `tests/Bulk.Engine.Tests.ps1` (test, batch)

**Analog:** `tests/User.Disable.Tests.ps1` + `tests/Group.Add.Tests.ps1`

**Pester 6 test harness pattern** (from `User.Disable.Tests.ps1` lines 20-56):
```powershell
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'

    # PSFramework stub
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    # ... manifest + psm1 stub ...
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
            bulk       = [pscustomobject]@{ maxCount = 50 }
            safety     = [pscustomobject]@{ bulkConfirmThreshold = 5 }
        }
    }
}
```

**Mock + Should-Invoke pattern** (from `Group.Add.Tests.ps1` lines 62-73):
```powershell
    It 'calls Invoke-AdmanMutation once per item' {
        Mock -ModuleName adman Invoke-AdmanMutation { }

        Invoke-AdmanBulkAction -Action 'Disable' -InputObject @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        ) -Force

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 2
    }
```

---

### `tests/Bulk.Csv.Tests.ps1` (test, file-I/O)

**Analog:** none in repo

**CSV test pattern** (from RESEARCH.md + Pester 6 conventions):
```powershell
BeforeAll {
    # ... same harness as Bulk.Engine.Tests.ps1 ...
}

It 'rejects CSV with unknown columns' {
    $csv = Join-Path $TestDrive 'bad.csv'
    @'
ObjectType,Identity,Action,BadColumn
User,jdoe,Disable,x
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

    { Import-AdmanBulkCsv -Path $csv } | Should -Throw '*unknown columns*'
}
```

---

### `tests/Workflow.Onboarding.Tests.ps1` (test, request-response)

**Analog:** `tests/User.Create.Tests.ps1`

**Mocking composed verbs pattern** (from `User.Create.Tests.ps1` lines 87-107):
```powershell
    It 'calls New-AdmanUser then Add-AdmanGroupMember for each baseline group' {
        Mock -ModuleName adman New-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $true; Reason = '' } }

        & (Get-Module adman) {
            $script:Config.templates = [pscustomobject]@{
                onboarding = [pscustomobject]@{
                    ParentOuDn    = 'OU=Users,OU=Managed,DC=mock,DC=local'
                    BaselineGroups = @('G1', 'G2')
                    NamePattern   = '{0}.{1}'
                }
            }
        }

        Start-AdmanUserOnboarding -FirstName 'John' -LastName 'Doe' -Force

        Should -Invoke -ModuleName adman New-AdmanUser -Times 1
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 2
    }
```

---

### `tests/Workflow.Offboarding.Tests.ps1` (test, request-response)

**Analog:** `tests/User.Disable.Tests.ps1` + `tests/Group.Remove.Tests.ps1`

**Mid-workflow failure test pattern** (from `User.Disable.Tests.ps1` lines 96-109):
```powershell
    It 'writes a Failure audit and stops later steps when a step throws' {
        Mock -ModuleName adman Disable-AdmanUser { throw 'DC down' }
        Mock -ModuleName adman Remove-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }
        Mock -ModuleName adman Write-AdmanAudit { }

        { Start-AdmanUserOffboarding -Identity 'jdoe' -Force } | Should -Throw 'DC down'

        Should -Invoke -ModuleName adman Write-AdmanAudit -Times 1 -ParameterFilter {
            $Verb -eq 'Start-AdmanUserOffboarding' -and $Result -eq 'Failure'
        }
        Should -Invoke -ModuleName adman Remove-AdmanGroupMember -Times 0
    }
```

---

### `tests/Workflow.Restore.Tests.ps1` (test, request-response)

**Analog:** `tests/User.Move.Tests.ps1` + `tests/Group.Add.Tests.ps1`

**Restore-state test pattern**:
```powershell
    It 'reads latest offboarding audit and reverses disable/groups/move' {
        Mock -ModuleName adman Get-AdmanOffboardingState {
            [pscustomobject]@{
                OriginalOU = 'OU=Users,OU=Managed,DC=mock,DC=local'
                Groups     = @('CN=G1,OU=Groups,DC=mock,DC=local')
            }
        }
        Mock -ModuleName adman Enable-AdmanUser { }
        Mock -ModuleName adman Add-AdmanGroupMember { }
        Mock -ModuleName adman Move-AdmanUser { }

        Restore-AdmanQuarantinedUser -Identity 'jdoe' -Force

        Should -Invoke -ModuleName adman Enable-AdmanUser -Times 1
        Should -Invoke -ModuleName adman Add-AdmanGroupMember -Times 1
        Should -Invoke -ModuleName adman Move-AdmanUser -Times 1
    }
```

---

### `tests/Menu.BulkWorkflow.Tests.ps1` (test, request-response)

**Analog:** `tests/Menu.Tests.ps1`

**Menu entry existence test pattern** (from `Menu.Tests.ps1` lines 560-582):
```powershell
    It 'menu contains entries for Phase 4 bulk/workflow verbs' {
        . $script:MenuDefPath
        $def = Get-AdmanMenuDefinition
        $byVerb = @{}
        foreach ($e in $def) {
            if ($null -eq $e.Verb) { continue }
            if (-not $byVerb.ContainsKey($e.Verb)) { $byVerb[$e.Verb] = New-Object System.Collections.ArrayList }
            [void]$byVerb[$e.Verb].Add($e)
        }

        $expectedVerbs = @(
            'Invoke-AdmanBulkAction'
            'Start-AdmanUserOnboarding'
            'Start-AdmanUserOffboarding'
            'Restore-AdmanQuarantinedUser'
        )
        foreach ($v in $expectedVerbs) {
            $byVerb.ContainsKey($v) | Should -BeTrue -Because "menu must contain an entry for $v"
        }
    }
```

**PromptSpec-name contract test pattern** (from `Menu.Tests.ps1` lines 799-823):
```powershell
    It 'every new menu entry PromptSpec Name resolves to a declared parameter' {
        foreach ($entry in $script:menuDef | Where-Object { $_.Verb -in @('Invoke-AdmanBulkAction','Start-AdmanUserOnboarding','Start-AdmanUserOffboarding','Restore-AdmanQuarantinedUser') }) {
            $cmd = Get-Command $entry.Verb -ErrorAction Stop
            $declaredParams = @($cmd.Parameters.Keys)
            foreach ($spec in $entry.PromptSpec) {
                $declaredParams | Should -Contain $spec.Name
            }
        }
    }
```

---

### `tests/Module.Manifest.Tests.ps1` (test, request-response)

**Analog:** same file (extend)

**Export list test pattern** (from lines 97-127):
```powershell
    It 'FunctionsToExport contains all Phase 4 bulk/workflow verbs explicitly' {
        $mf = Test-ModuleManifest $script:ManifestPath -ErrorAction Stop
        $exported = @($mf.ExportedFunctions.Keys)

        $phase4Verbs = @(
            'Invoke-AdmanBulkAction'
            'Start-AdmanUserOnboarding'
            'Start-AdmanUserOffboarding'
            'Restore-AdmanQuarantinedUser'
        )
        foreach ($v in $phase4Verbs) {
            $exported | Should -Contain $v -Because "Phase 4 plan landed the export for $v"
        }
    }
```

## Shared Patterns

### Init Check
**Source:** `Public/New-AdmanUser.ps1` (lines 92-97)
**Apply to:** All new Public verbs (`Invoke-AdmanBulkAction`, `Start-AdmanUserOnboarding`, `Start-AdmanUserOffboarding`, `Restore-AdmanQuarantinedUser`)
```powershell
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }
```

### SupportsShouldProcess + -WhatIf Propagation
**Source:** `Public/Disable-AdmanUser.ps1` (lines 25-43)
**Apply to:** All new Public verbs
```powershell
function Disable-AdmanUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [switch]$Force
    )
    # ...
    Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets @($Identity) `
        -Force:$Force -WhatIf:$WhatIfPreference
}
```

### Gate Invocation
**Source:** `Private/Safety/Invoke-AdmanMutation.ps1` (lines 43-55)
**Apply to:** `Public/Invoke-AdmanBulkAction.ps1`
```powershell
    Invoke-AdmanMutation -Verb $mappedGateVerb -Targets @($item.Identity) `
        -Parameters $stepParams -Force:$Force -WhatIf:$WhatIfPreference
```

### Bulk Policy Enforcement
**Source:** `Private/Safety/Assert-AdmanBulkPolicy.ps1` (lines 16-35)
**Apply to:** `Public/Invoke-AdmanBulkAction.ps1`
```powershell
function Assert-AdmanBulkPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Count,
        [switch]$EnforceCap
    )

    $cap = [int]$script:Config.bulk.maxCount
    # ...
    if ($EnforceCap -and $Count -gt $cap) {
        throw "Bulk count $Count exceeds cap $cap."
    }
    return @{ Cap = $cap; Threshold = $threshold }
}
```

### Scaled Confirmation
**Source:** `Private/Safety/Confirm-AdmanAction.ps1` (lines 34-98)
**Apply to:** `Public/Invoke-AdmanBulkAction.ps1`
```powershell
    $confirm = Confirm-AdmanAction -Verb $Verb -Targets $allowed.ToArray() -Force:$Force
    if ($confirm.Outcome -eq 'Declined') { throw 'Operator declined.' }
```

### Audit Extension (Optional Fields)
**Source:** `Private/Audit/Write-AdmanAudit.ps1` (lines 151-155)
**Apply to:** `Private/Audit/Write-AdmanAudit.ps1` (offboarding)
```powershell
        if (-not [string]::IsNullOrEmpty($Group)) {
            $rec['group'] = $Group
        }
```

### Per-Item Try/Catch/Continue
**Source:** `Private/Safety/Invoke-AdmanMutation.ps1` (lines 222-235)
**Apply to:** `Public/Invoke-AdmanBulkAction.ps1`, workflow verbs
```powershell
    try {
        # ... gate call or workflow step ...
    } catch {
        # record failure
        Write-AdmanAudit -Verb $Verb -Target $target -Result 'Failure' -Reason $_.Exception.Message
        throw  # or continue for bulk
    }
```

### Managed-OU Scope Validation
**Source:** `Public/Move-AdmanUser.ps1` (lines 57-68)
**Apply to:** `Public/Invoke-AdmanBulkAction.ps1` (Move target path), `Public/Start-AdmanUserOffboarding.ps1` (quarantine OU)
```powershell
    $tp = ConvertTo-AdmanNormalizedDn -Dn $TargetPath
    $tpInScope = $false
    foreach ($root in @($script:Config.ManagedOUs)) {
        $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
        if ([string]::IsNullOrEmpty($r)) { continue }
        if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
    }
    if (-not $tpInScope) {
        throw "TargetPath '$TargetPath' is outside managed OU scope."
    }
```

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `Private/Bulk/Import-AdmanBulkCsv.ps1` | utility | file-I/O | No `Import-Csv` usage exists in the repo yet. Use RESEARCH.md strict-schema example. |
| `tests/Bulk.Csv.Tests.ps1` | test | file-I/O | No CSV-import tests exist yet; derive from `Import-AdmanBulkCsv` contract. |

## Metadata

**Analog search scope:** `C:/Users/nhdinh/dev/adman/Public/**/*.ps1`, `Private/**/*.ps1`, `config/*.json`, `tests/*.Tests.ps1`, `adman.psd1`
**Files scanned:** 50+
**Pattern extraction date:** 2026-07-17
