# Phase 5: Hardening & Portability - Pattern Map

**Mapped:** 2026-07-21
**Files analyzed:** 15
**Analogs found:** 12 / 15

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `README.md` | documentation | static/reference | `README.md` (self) | exact |
| `docs/USAGE.md` | documentation | static/reference | `docs/REMOTE-OPS.md` | role-match |
| `docs/RECOVERY-RUNBOOK.md` | documentation | static/reference | `docs/REMOTE-OPS.md` | role-match |
| `adman.psd1` | config | static/declarative | `adman.psd1` (self) | exact |
| `Private/Audit/Write-AdmanAudit.ps1` | service | file-I/O (append) | `Private/Audit/Write-AdmanAudit.ps1` (self) | exact |
| `Private/Audit/AdmanAuditIO.ps1` | utility/service | file-I/O | `Private/Audit/AdmanAuditIO.ps1` (self) | exact |
| `Private/Audit/Rotation.ps1` | utility/service | file-I/O, batch | `Private/Audit/Find-AdmanAuditOrphans.ps1` | role-match |
| `config/adman.schema.json` | config | static/schema | `config/adman.schema.json` (self) | exact |
| `config/adman.defaults.json` | config | static/defaults | `config/adman.defaults.json` (self) | exact |
| `tests/Help.Coverage.Tests.ps1` | test | validation/transform | `tests/Module.Manifest.Tests.ps1` | role-match |
| `tests/Audit.Integrity.Tests.ps1` | test | file-I/O validation | `tests/Audit.OrphanSweep.Tests.ps1` | role-match |
| `tests/Audit.EventLog.Tests.ps1` | test | event-driven validation | `tests/Audit.FailClosed.Tests.ps1` | role-match |
| `.github/workflows/ci.yml` | config | batch/orchestration | none | no analog |
| `build/Sign-AdmanModule.ps1` | utility | file-I/O | none | no analog |
| `.githooks/pre-commit` | config | validation | none | no analog |

## Pattern Assignments

### `README.md` (documentation, static/reference)

**Analog:** `README.md` (refresh in place)

**Header + status badge pattern** (lines 1-5):
```markdown
# adman

Menu-driven (interactive TUI) PowerShell toolkit for safely administering users and computers in an on-prem Active Directory domain.

> Status: Phase 0 (foundation & safety harness) complete. Phases 1–5 ...
```

**Safety guarantees section pattern** (lines 17-25):
```markdown
## Safety guarantees

- `-WhatIf` / dry-run on every destructive action. Preview and execute use the same target resolution, so the preview cannot lie. Enforced by Pester + PSScriptAnalyzer.
- Confirmation prompts scaled to blast radius: y/n for a single object; typed token + exact count for bulk.
- Managed-OU scoping — refuses any DN outside configured roots (component-boundary anchored).
```

**Project layout code block pattern** (lines 94-119):
```markdown
## Project layout

```
adman.psd1                  # Module manifest (Desktop-only, PSFramework pinned)
adman.psm1                  # Root module / loader
Public/                     # Exported functions
  Initialize-Adman.ps1
```
```

---

### `docs/USAGE.md` (documentation, static/reference)

**Analog:** `docs/REMOTE-OPS.md`

**Document header pattern** (lines 1-5):
```markdown
# adman Remote Operations Guide

> Operator reference for Phase 3 remote computer operations in adman.
```

**Section heading + table pattern** (lines 63-71):
```markdown
## Firewall ports

| Transport | Ports | Notes |
|-----------|-------|-------|
| WinRM / WSMan | TCP 5985 (HTTP), TCP 5986 (HTTPS) | Single fixed ports; easier to firewall |
| DCOM / classic WMI | TCP 135 + dynamic RPC range | Dynamic range is 49152–65535 by default on modern Windows |
```

**PowerShell example block pattern** (lines 74-79):
```markdown
```powershell
# PowerShell
Get-NetFirewallRule -DisplayGroup 'Remote Service Management' | Get-NetFirewallPortFilter
```
```

---

### `docs/RECOVERY-RUNBOOK.md` (documentation, static/reference)

**Analog:** `docs/REMOTE-OPS.md`

Use the same one-page guide format as `docs/REMOTE-OPS.md`:
- H1 title + operator-reference subtitle
- `##` sections for each recovery path
- Tables for decision trees
- PowerShell code blocks for AD Recycle Bin cmdlets
- Footer with last-updated date

---

### `adman.psd1` (config, static/declarative)

**Analog:** `adman.psd1` (self)

**Version + edition claim pattern** (lines 16-19):
```powershell
ModuleVersion = '0.1.0'

# Supported PSEditions — Desktop only until the Phase 5 CI matrix passes on 7.6.
CompatiblePSEditions = @('Desktop')
```

**RequiredModules pinning pattern** (lines 43-48):
```powershell
RequiredModules = @(
    @{
        ModuleName      = 'PSFramework'
        RequiredVersion = '1.14.457'
    }
)
```

**Explicit FunctionsToExport pattern** (lines 50-53):
```powershell
FunctionsToExport = @('Initialize-Adman', 'Start-Adman', 'Get-AdmanConfig', ...)
```

**ReleaseNotes pattern** (lines 68-73):
```powershell
ReleaseNotes = @'
Phase 0 (00-01) scaffold only: export boundary + loader + lint/test harness.
CompatiblePSEditions is Desktop-only on purpose; it gains Core only after the
Phase 5 dual-edition CI matrix passes on PowerShell 7.6 (honest edition claim).
The mutation gate Invoke-AdmanMutation is private and not exported (SAFE-08).
'@
```

---

### `Private/Audit/Write-AdmanAudit.ps1` (service, file-I/O append)

**Analog:** `Private/Audit/Write-AdmanAudit.ps1` (self)

**Script header + comment-based help pattern** (lines 1-35):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Write-AdmanAudit - the ONLY audit writer: synchronous, write-ahead, fail-closed (SAFE-03/04).

.DESCRIPTION
    Appends ONE JSON-lines record to the daily-rotated audit file under a named mutex, flushing
    durably before returning. This is the single audit sink (D-01): no audit record is ever routed
    through any asynchronous logging framework (async breaks fail-closed).
#>

Set-StrictMode -Version Latest
```

**Param block pattern** (lines 37-53):
```powershell
function Write-AdmanAudit {
    [CmdletBinding()]
    param(
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [string]$Verb,
        ...
        [switch]$WhatIf
    )
```

**Mutex acquisition pattern** (lines 55-76):
```powershell
$mutex = New-AdmanAuditMutex
if ($null -eq $mutex) {
    throw "AUDIT FAIL-CLOSED: cannot acquire audit mutex; refusing $Verb."
}
$acquired = $false
try {
    $acquired = $mutex.WaitOne([timespan]::FromSeconds(30))
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}
if (-not $acquired) { ... }
```

**Record building pattern** (lines 138-167):
```powershell
$rec = [ordered]@{
    tsUtc         = $nowUtc.ToString('o')
    who           = "$env:USERDOMAIN\$env:USERNAME"
    userSid       = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    what          = $Verb
    scope         = ($script:Config.ManagedOUs -join '|')
    target        = ($targetStrings -join '|')
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
$rec = $rec | ConvertTo-Json -Compress -Depth 5
```

**Durable write pattern** (lines 170-181):
```powershell
$fs = Open-AdmanAuditStream -Path $path
if ($null -eq $fs) {
    throw "AUDIT FAIL-CLOSED: cannot open audit stream for '$path'."
}
try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($rec + "`n")
    $fs.Write($bytes, 0, $bytes.Length)
    $fs.Flush($true)
} finally {
    $fs.Dispose()
}
```

**PENDING fail-closed pattern** (lines 188-206):
```powershell
if ($Result -eq 'PENDING') {
    $msg = 'AUDIT FAIL-CLOSED: cannot write audit record'
    ...
    throw [System.InvalidOperationException]::new($msg, $inner)
}
```

**OUTCOME escalation pattern** (lines 207-211):
```powershell
$script:AuditDegraded = $true
Write-AdmanEventLog -EventId 9001 -EntryType Error `
    -Message "AUDIT OUTCOME WRITE FAILED cid=$CorrelationId verb=$Verb (mutation already applied)"
Write-Warning "AUDIT OUTCOME WRITE FAILED for cid=$CorrelationId - see Event Log."
```

---

### `Private/Audit/AdmanAuditIO.ps1` (utility/service, file-I/O)

**Analog:** `Private/Audit/AdmanAuditIO.ps1` (self)

**Seam header pattern** (lines 1-23):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    AdmanAuditIO - the private, mockable I/O seams for the audit writer (Write-AdmanAudit).
#>

Set-StrictMode -Version Latest
```

**Mutex seam pattern** (lines 26-37):
```powershell
function New-AdmanAuditMutex {
    [CmdletBinding()]
    [OutputType([System.Threading.Mutex])]
    param()

    return [System.Threading.Mutex]::new($false, 'Global\adman-audit')
}
```

**Stream seam pattern** (lines 39-58):
```powershell
function Open-AdmanAuditStream {
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
}
```

**Event-log seam pattern** (lines 60-84):
```powershell
function Write-AdmanEventLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$EventId,
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Information')]
        [string]$EntryType,
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        Write-EventLog -LogName Application -Source 'adman' -EventId $EventId `
            -EntryType $EntryType -Message $Message -ErrorAction Stop
    } catch {
        Write-Warning "adman event-log write skipped (source 'adman' unregistered): $Message"
    }
}
```

---

### `Private/Audit/Rotation.ps1` (utility/service, file-I/O batch)

**Analog:** `Private/Audit/Find-AdmanAuditOrphans.ps1`

**Function header pattern** (lines 1-20):
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Find-AdmanAuditOrphans - PENDING to OUTCOME correlation sweep (SAFE-04 audit integrity; D-03).

.DESCRIPTION
    Read-only detection seam for an OUTCOME-write gap. Scans the last N days of daily-rotated
    audit-*.jsonl files, parses every line as strict JSON, groups records by correlationId...
#>
```

**Config-driven path pattern** (lines 24-30):
```powershell
function Find-AdmanAuditOrphans {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$AuditDir = $script:Config.AuditDir,
        [int]$LookbackDays = 7
    )
```

**Daily-rotated file enumeration pattern** (lines 34-52):
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

**Apply to Rotation.ps1:** `Get-AdmanAuditIntegrity` reads each `.jsonl` line via `Get-Content`, computes SHA-256 over the canonical record (excluding `prevHash`), and compares to the stored `prevHash` of the next line. `Invoke-AdmanAuditRotation` moves files older than `$script:Config.audit.retentionDays` to `.store/audit/archive/YYYYMM/` using `Move-Item`.

---

### `config/adman.schema.json` (config, static/schema)

**Analog:** `config/adman.schema.json` (self)

**Top-level required array pattern** (lines 7-22):
```json
"required": [
    "ManagedOUs",
    "DenyList",
    ...
],
```

**Nested object with default pattern** (lines 41-62):
```json
"safety": {
    "type": "object",
    "required": [ "bulkConfirmThreshold" ],
    "properties": {
        "bulkConfirmThreshold": {
            "type": "integer",
            "description": "At/above this target count the operator must type the exact count (SAFE-02). Default 5 (D-07).",
            "default": 5,
            "minimum": 1
        }
    }
},
```

**Add `audit` object next to `safety`** with `retentionDays` integer (default 90, minimum 1).

---

### `config/adman.defaults.json` (config, static/defaults)

**Analog:** `config/adman.defaults.json` (self)

**Top-level defaults pattern** (lines 1-3):
```json
{
  "_comment": "adman non-secret config defaults (CONF-01/02/03). Source-of-truth values for a fresh .store/config.json.",
  "ManagedOUs": [],
```

**Nested defaults block pattern** (lines 9-15):
```json
"safety": {
    "bulkConfirmThreshold": 5,
    "_comment_requireManagedGroupOU": "Opt-in D-04 group-OU enforcement. Default false...",
    "requireManagedGroupOU": false,
    "typedCountVerbs": [ "Remove-LocalUser" ]
},
```

**Add `audit` block** matching the schema:
```json
"audit": {
    "retentionDays": 90
},
```

---

### `tests/Help.Coverage.Tests.ps1` (test, validation/transform)

**Analog:** `tests/Module.Manifest.Tests.ps1` + `tests/Menu.Tests.ps1`

**Module import pattern** (lines 12-55):
```powershell
BeforeAll {
    # Throwaway PSFramework 1.14.457 stub so RequiredModules resolves without a real install.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    ...
}
"@ | Set-Content -Path (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
    ...
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:ModuleName = 'adman'
    $script:ManifestPath = Join-Path $PSScriptRoot '..\adman.psd1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}
```

**Manifest-driven iteration pattern** (lines 51-62):
```powershell
$mf = Test-ModuleManifest $script:ManifestPath -ErrorAction Stop
$expected = @($mf.ExportedFunctions.Keys)
```

**AST parameter discovery pattern** (`tests/Menu.Tests.ps1` lines 38-57):
```powershell
function Get-AdmanFileAst {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$tokens, [ref]$errors)
    return $ast
}
```

**Apply to Help.Coverage.Tests.ps1:** Iterate `$mf.ExportedFunctions.Keys`, call `Get-Help $_ -Full`, assert `.Synopsis` and `.Description` are non-empty/whitespace, `.Examples.Example.Count >= 1`, and for each declared AST parameter (excluding common params) there is a matching `.Parameters.Parameter` entry.

---

### `tests/Audit.Integrity.Tests.ps1` (test, file-I/O validation)

**Analog:** `tests/Audit.OrphanSweep.Tests.ps1`

**PSFramework stub + import pattern** (lines 23-49):
```powershell
BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    ...
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}
```

**Test audit record writer helper pattern** (lines 79-108):
```powershell
function Write-AdmanJsonlLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AuditDir,
        [Parameter(Mandatory)][string]$CorrelationId,
        [Parameter(Mandatory)][string]$Result,
        ...
    )
    $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
    $path = Join-Path $AuditDir $name
    $rec = [ordered]@{
        tsUtc = (Get-Date).ToUniversalTime().ToString('o')
        ...
    } | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath $path -Value $rec -Encoding UTF8
}
```

**Apply to Audit.Integrity.Tests.ps1:** Write two or more records to a `$TestDrive` audit file, then call `Get-AdmanAuditIntegrity`. Assert valid chain when records are unmodified, and assert `Valid=$false` with a broken line number when a middle record is mutated.

---

### `tests/Audit.EventLog.Tests.ps1` (test, event-driven validation)

**Analog:** `tests/Audit.FailClosed.Tests.ps1`

**Global seam stub pattern** (lines 58-60):
```powershell
function global:New-AdmanAuditMutex { }
function global:Open-AdmanAuditStream { param($Path) }
function global:Write-AdmanEventLog { param($EventId, $EntryType, $Message) }
```

**Mock seam for OUTCOME failure pattern** (lines 178-182):
```powershell
Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
Mock Open-AdmanAuditStream -ModuleName adman { throw 'sharing violation' }
$script:EventLogCalls = 0
Mock Write-AdmanEventLog -ModuleName adman { $script:EventLogCalls++ }
```

**Assert event-log escalation pattern** (lines 193-196):
```powershell
$script:EventLogCalls | Should -BeGreaterOrEqual 1 `
    -Because 'an OUTCOME-write failure escalates to the Windows Event Log (best-effort)'
(Get-AdmanAuditDegraded) | Should -BeTrue `
    -Because 'an OUTCOME-write failure sets $script:AuditDegraded=$true'
```

**Apply to Audit.EventLog.Tests.ps1:** Reuse the same `Mock Write-AdmanEventLog -ModuleName adman` pattern, trigger an OUTCOME write failure, and assert the mock is invoked with `EventId 9001` and `EntryType Error`.

---

### `.github/workflows/ci.yml` (config, batch/orchestration)

**Analog:** none in codebase

Use the standard GitHub Actions matrix pattern from `05-RESEARCH.md` (Example 2, lines 533-569):
```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    strategy:
      fail-fast: false
      matrix:
        edition: [desktop, core]
    steps:
      - uses: actions/checkout@v4

      - name: Install PowerShell 7.6 LTS
        if: matrix.edition == 'core'
        uses: mchave3/setup-pwsh@v1
        with:
          version: '7.6.4'

      - name: Install dependencies
        shell: ${{ matrix.edition == 'desktop' && 'powershell' || 'pwsh' }}
        run: |
          Install-PSResource Pester -RequiredVersion 6.0.0 -Scope CurrentUser
          Install-PSResource PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser

      - name: Set execution policy to AllSigned (Core leg test)
        if: matrix.edition == 'core'
        shell: pwsh
        run: Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope Process -Force

      - name: Run tests
        shell: ${{ matrix.edition == 'desktop' && 'powershell' || 'pwsh' }}
        run: |
          Invoke-ScriptAnalyzer -Path . -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
          Invoke-Pester -Configuration (Import-PowerShellDataFile ./tests/PesterConfiguration.psd1)
```

Add a CI checkout scan step that fails if `.store/` exists in the working tree.

---

### `build/Sign-AdmanModule.ps1` (utility, file-I/O)

**Analog:** none in codebase

Use the standard `Set-AuthenticodeSignature` pattern from `05-RESEARCH.md` (Pattern 2, lines 336-354):
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [string]$ModulePath = $PSScriptRoot\..\adman.psd1
)

$moduleRoot = Split-Path -Parent -Path (Resolve-Path $ModulePath).Path
$files = Get-ChildItem -Path $moduleRoot -Include '*.psd1','*.psm1','*.ps1' -Recurse -File |
    Where-Object FullName -notmatch '\\(tests|\.github|\.githooks)\\'

foreach ($file in $files) {
    $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $Certificate -HashAlgorithm SHA256
    if ($result.Status -ne 'Valid') {
        throw "Signing failed for $($file.FullName): $($result.StatusMessage)"
    }
}
```

Also support `-CertificateThumbprint` and `-CertificateFilePath` per CONTEXT D-04.

---

### `.githooks/pre-commit` (config, validation)

**Analog:** none in codebase

Use the standard shell hook pattern from `05-RESEARCH.md` (Pattern 4, lines 406-421):
```bash
#!/bin/sh
BLOCKED='\.store/'
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    AGAINST=HEAD
else
    AGAINST=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

if git diff --cached --name-only "$AGAINST" | grep -qE "^$BLOCKED"; then
    echo "ERROR: Committing .store/ files is not allowed." >&2
    exit 1
fi
exit 0
```

Document installation in README: `git config core.hooksPath .githooks`.

## Shared Patterns

### PowerShell Script Header
**Source:** Every module script (e.g., `Public/Find-AdmanUser.ps1` lines 1-46, `Public/Disable-AdmanUser.ps1` lines 1-23)
**Apply to:** All new `.ps1` files (`Rotation.ps1`, `Sign-AdmanModule.ps1`, test files)
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Function-name - one-line summary.

.DESCRIPTION
    Longer explanation.

.PARAMETER Name
    Parameter description.

.EXAMPLE
    PS> Verb-Noun -Name value
    Expected output description.
#>

Set-StrictMode -Version Latest
```

### Comment-Based Help on Public Functions
**Source:** `Public/Find-AdmanUser.ps1` lines 2-44 (complete); `Public/Disable-AdmanUser.ps1` lines 2-21 (already has DESCRIPTION/EXAMPLE)
**Apply to:** All 37 `FunctionsToExport` entries that lack `.DESCRIPTION` and `.EXAMPLE`
```powershell
<#
.SYNOPSIS
    Find-AdmanUser - scoped, read-only AD user search (USER-01).

.DESCRIPTION
    Searches Active Directory for users matching the supplied criteria, scoped to the
    configured ManagedOUs roots. Returns a normalized PSCustomObject[] in the D-03 schema.

.PARAMETER SamAccountName
    The sAMAccountName to search for.

.EXAMPLE
    Find-AdmanUser -SamAccountName 'alice'
#>
```

### PSFramework Stub in Tests
**Source:** `tests/Audit.FailClosed.Tests.ps1` lines 30-49
**Apply to:** All new unit tests
```powershell
$stubRoot = Join-Path $TestDrive 'Modules'
$stubDir = Join-Path $stubRoot 'PSFramework'
New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
@"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000ca'
    FunctionsToExport = @('Set-PSFConfig','Get-PSFConfig','Register-PSFConfigValidation','Export-PSFConfig','Import-PSFConfig','Write-PSFMessage')
}
"@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
@'
function Set-PSFConfig { [CmdletBinding()] param($Value, [switch]$Initialize, $Name, $Module) }
...
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psm1') -Encoding UTF8
$env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
```

### Config Additive Defaults Migration
**Source:** `Private/Config/Initialize-AdmanConfig.ps1` lines 256-291
**Apply to:** Adding `audit.retentionDays` to schema/defaults
```powershell
# Phase 3 additive timeout defaults (D-02): on every load, seed any missing
# transport.timeouts keys from shipped defaults without overwriting user values.
$defaultsPath = Join-Path $moduleRoot 'config\adman.defaults.json'
if (Test-Path -LiteralPath $defaultsPath) {
    $defaultsRaw = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
    $defaults = ConvertTo-AdmanCleanConfig -Node $defaultsRaw
    if ($null -ne $defaults.transport -and $null -ne $defaults.transport.timeouts) { ... }
}
```

### Audit Record JSONL Serialization
**Source:** `Private/Audit/Write-AdmanAudit.ps1` lines 138-168
**Apply to:** Hash-chain helpers (`Rotation.ps1`)
```powershell
$rec = [ordered]@{ ... } | ConvertTo-Json -Compress -Depth 5
$bytes = [System.Text.Encoding]::UTF8.GetBytes($rec + "`n")
```

### Module Loader / Export Boundary
**Source:** `adman.psm1` lines 10-57
**Apply to:** Ensure any new `Private/Audit/*.ps1` is loaded by the existing recursive loader
```powershell
$ErrorActionPreference = 'Stop'
$script:Config = @{}
...
foreach ($scope in @('Private', 'Public')) {
    $dir = Join-Path $PSScriptRoot $scope
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Filter *.ps1 -Recurse -File |
        Sort-Object -Property FullName |
        ForEach-Object { . $_.FullName }
}
```

## No Analog Found

Files with no close match in the codebase (planner should use `05-RESEARCH.md` patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.github/workflows/ci.yml` | config | batch/orchestration | No GitHub Actions workflows exist in the repo |
| `build/Sign-AdmanModule.ps1` | utility | file-I/O | No build/sign scripts exist; role is external to the module |
| `.githooks/pre-commit` | config | validation | No git hooks are tracked in the repo |

## Metadata

**Analog search scope:** `C:\Users\nhdinh\dev\adman` (recursive)
**Files scanned:** 15 analogs read (README, docs/REMOTE-OPS.md, adman.psd1, adman.psm1, Private/Audit/*.ps1, config/*.json, tests/*.Tests.ps1, Public/*.ps1, Private/Config/Initialize-AdmanConfig.ps1, .gitignore)
**Pattern extraction date:** 2026-07-21
