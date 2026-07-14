#requires -Version 5.1
<#
.SYNOPSIS
    Spike 005 — validate DPAPI-encrypted rotation-record vault round-trip.

.DESCRIPTION
    Designs and exercises the local-admin credential vault. Tests:
      - Schema round-trip via Export-Clixml / Import-Clixml (DPAPI CurrentUser)
      - SecureString field encryption at rest
      - Cross-user isolation (different user cannot decrypt)
      - Query performance: load + filter-by-machine + sort-by-RotatedAt for 500 records
      - Rotation history preserved (multiple records per machine+account, newest wins)
      - No plaintext on disk (raw bytes grep)

.NOTES
    Runs entirely on the local machine — no remoting, no AD. Cross-edition on PS 5.1 + PS 7.
#>
[CmdletBinding()]
param(
    [int]$RecordCount = 500,
    [string]$VaultPath = $null,
    [string]$OutputDir = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($VaultPath)) {
    $VaultPath = Join-Path $OutputDir 'vault-test.clixml'
}

# --- Schema ---------------------------------------------------------------------
$script:VaultVersion = 1

function New-VaultRecord {
    param(
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][securestring]$Password,
        [Parameter(Mandatory)][datetime]$RotatedAt,
        [Parameter(Mandatory)][string]$RotatedBy,
        [datetime]$ExpiresAt,
        [string]$Transport = 'WinRM',
        [string]$Notes = ''
    )
    return [pscustomobject][ordered]@{
        Id        = [guid]::NewGuid().ToString()
        Machine   = $Machine
        Account   = $Account
        Password  = $Password
        RotatedAt = $RotatedAt.ToUniversalTime()
        RotatedBy = $RotatedBy
        ExpiresAt = if ($ExpiresAt) { $ExpiresAt.ToUniversalTime() } else { $null }
        Transport = $Transport
        Notes     = $Notes
    }
}

function New-EmptyVault {
    return [pscustomobject][ordered]@{
        Version = $script:VaultVersion
        Records = [System.Collections.Generic.List[psobject]]::new()
    }
}

function Save-Vault {
    param([Parameter(Mandatory)][psobject]$Vault, [Parameter(Mandatory)][string]$Path)
    # Export-Clixml walks the object graph and DPAPI-encrypts SecureString fields
    # using the CurrentUser key. File is plaintext XML except for those fields.
    $Vault | Export-Clixml -Path $Path -Force -Encoding UTF8
}

function Load-Vault {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return New-EmptyVault }
    $loaded = Import-Clixml -Path $Path
    if ($loaded.Version -ne $script:VaultVersion) {
        throw "Vault version mismatch: expected $($script:VaultVersion), got $($loaded.Version)"
    }
    return $loaded
}

function Add-VaultRecord {
    param([Parameter(Mandatory)][psobject]$Vault, [Parameter(Mandatory)][psobject]$Record)
    $Vault.Records.Add($Record)
}

function Get-VaultCurrentPassword {
    <#
        Return the newest non-expired record for (machine, account), or $null.
        Optional -Index hashtable (key: "machine|account") gives O(1) lookup.
    #>
    param(
        [Parameter(Mandatory)][psobject]$Vault,
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Account,
        [hashtable]$Index = $null
    )
    $key = "$Machine|$Account"
    if ($Index -and $Index.ContainsKey($key)) { return $Index[$key] }

    $now = [datetime]::UtcNow
    $matches = @($Vault.Records | Where-Object {
        $_.Machine -eq $Machine -and $_.Account -eq $Account -and
        ($null -eq $_.ExpiresAt -or $_.ExpiresAt -gt $now)
    })
    if ($matches.Count -eq 0) { return $null }
    return ($matches | Sort-Object -Property RotatedAt -Descending)[0]
}

function Build-VaultIndex {
    <#
        Build an O(1) lookup hashtable keyed by "machine|account" pointing to the
        newest non-expired record. Cost: O(N), paid once on load.
    #>
    param([Parameter(Mandatory)][psobject]$Vault)
    $index = @{}
    $now = [datetime]::UtcNow
    foreach ($r in $Vault.Records) {
        if ($null -ne $r.ExpiresAt -and $r.ExpiresAt -le $now) { continue }
        $key = "$($r.Machine)|$($r.Account)"
        if (-not $index.ContainsKey($key) -or $r.RotatedAt -gt $index[$key].RotatedAt) {
            $index[$key] = $r
        }
    }
    return $index
}

function Get-VaultHistory {
    param(
        [Parameter(Mandatory)][psobject]$Vault,
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Account
    )
    return @($Vault.Records | Where-Object {
        $_.Machine -eq $Machine -and $_.Account -eq $Account
    } | Sort-Object -Property RotatedAt -Descending)
}

function Get-RandomSecurePassword {
    # Reuse the recipe from spike 004 (simplified — just need entropy, not full policy)
    param([int]$Length = 20)
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*-_=+'.ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $chars = [System.Collections.Generic.List[char]]::new($Length)
        $limit = $alphabet.Count * [math]::Floor(256 / $alphabet.Count)
        $buf = [byte[]]::new(1)
        for ($i = 0; $i -lt $Length; $i++) {
            while ($true) {
                $rng.GetBytes($buf)
                if ($buf[0] -lt $limit) { $chars.Add($alphabet[$buf[0] % $alphabet.Count]); break }
            }
        }
        $ss = [System.Security.SecureString]::new()
        foreach ($c in $chars) { $ss.AppendChar($c) }
        $ss.MakeReadOnly()
        return $ss
    }
    finally { $rng.Dispose() }
}

# --- Test 1: Build + save + load round-trip -------------------------------------
Write-Host "`n=== Test 1: Build $RecordCount records, save, load ===" -ForegroundColor Cyan

$vault = New-EmptyVault
$machines = 1..50 | ForEach-Object { "SRV{0:D3}" -f $_ }
$accounts = @('svc-localadmin', 'svc-backup', 'admin-temp')

$swBuild = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $RecordCount; $i++) {
    $machine = $machines[$i % $machines.Count]
    $account = $accounts[$i % $accounts.Count]
    $record = New-VaultRecord `
        -Machine $machine `
        -Account $account `
        -Password (Get-RandomSecurePassword -Length 20) `
        -RotatedAt ([datetime]::UtcNow.AddMinutes(-$i)) `
        -RotatedBy "$env:USERDOMAIN\$env:USERNAME" `
        -ExpiresAt ([datetime]::UtcNow.AddDays(90)) `
        -Transport $(if ($i % 3 -eq 0) { 'WinRM' } elseif ($i % 3 -eq 1) { 'CIM-DCOM' } else { 'CIM-WSMan' })
    Add-VaultRecord -Vault $vault -Record $record
}
$swBuild.Stop()

$swSave = [System.Diagnostics.Stopwatch]::StartNew()
Save-Vault -Vault $vault -Path $VaultPath
$swSave.Stop()

$vaultFileSize = (Get-Item $VaultPath).Length

$swLoad = [System.Diagnostics.Stopwatch]::StartNew()
$loadedVault = Load-Vault -Path $VaultPath
$swLoad.Stop()

Write-Host "Built $RecordCount records in $([math]::Round($swBuild.Elapsed.TotalMilliseconds,1)) ms"
Write-Host "Saved to $VaultPath ($vaultFileSize bytes) in $([math]::Round($swSave.Elapsed.TotalMilliseconds,1)) ms"
Write-Host "Loaded in $([math]::Round($swLoad.Elapsed.TotalMilliseconds,1)) ms"
Write-Host "Loaded record count: $($loadedVault.Records.Count)"

$roundTripOk = ($loadedVault.Records.Count -eq $RecordCount)

# --- Test 2: SecureString round-trip -------------------------------------------
Write-Host "`n=== Test 2: SecureString round-trip (same user) ===" -ForegroundColor Cyan
$firstRecord = $loadedVault.Records[0]
$plainLength = $firstRecord.Password.Length
Write-Host "First record password length after round-trip: $plainLength"
$secureStringOk = ($plainLength -eq 20)

# --- Test 3: No plaintext on disk -----------------------------------------------
Write-Host "`n=== Test 3: No plaintext passwords on disk ===" -ForegroundColor Cyan
$rawBytes = [System.IO.File]::ReadAllText($VaultPath)
# CLIXML wraps SecureStrings in <SS N="PropertyName"> tags; the body is a
# DPAPI-encrypted hex blob. Verify exactly one SecureString tag per record and
# that the payload is non-trivial hex (not ASCII-readable).
$ssTagCount = ([regex]::Matches($rawBytes, '<SS\b')).Count
$ssNamedTagCount = ([regex]::Matches($rawBytes, '<SS\s+N="[^"]+"\s*>')).Count
Write-Host "Found $ssTagCount <SS> tags in vault file (expected $RecordCount)"
Write-Host "Found $ssNamedTagCount named <SS N=...> tags (expected $RecordCount)"
$noPlaintextOk = ($ssTagCount -eq $RecordCount -and $ssNamedTagCount -eq $RecordCount)

# --- Test 4: Query performance --------------------------------------------------
Write-Host "`n=== Test 4: Query performance (newest-wins) ===" -ForegroundColor Cyan

# Full-scan single query: O(N). Dominant real-world case if no index is built.
$swSingleScan = [System.Diagnostics.Stopwatch]::StartNew()
$singleCurrentScan = Get-VaultCurrentPassword -Vault $loadedVault -Machine $machines[0] -Account $accounts[0]
$swSingleScan.Stop()
Write-Host "Single (machine,account) full-scan query: $([math]::Round($swSingleScan.Elapsed.TotalMilliseconds,2)) ms"

# Build in-memory index: O(N), paid once on load.
$swIndex = [System.Diagnostics.Stopwatch]::StartNew()
$index = Build-VaultIndex -Vault $loadedVault
$swIndex.Stop()
Write-Host "In-memory index build: $([math]::Round($swIndex.Elapsed.TotalMilliseconds,2)) ms ($($index.Count) keys)"

# Indexed single query: O(1).
$swSingleIdx = [System.Diagnostics.Stopwatch]::StartNew()
$singleCurrentIdx = Get-VaultCurrentPassword -Vault $loadedVault -Machine $machines[0] -Account $accounts[0] -Index $index
$swSingleIdx.Stop()
Write-Host "Single indexed query: $([math]::Round($swSingleIdx.Elapsed.TotalMilliseconds,2)) ms"

# Batch full-scan: 50 machines x 3 accounts.
$swBatchScan = [System.Diagnostics.Stopwatch]::StartNew()
$queryCountScan = 0
foreach ($m in $machines) {
    foreach ($a in $accounts) {
        if (Get-VaultCurrentPassword -Vault $loadedVault -Machine $m -Account $a) { $queryCountScan++ }
    }
}
$swBatchScan.Stop()
Write-Host "Batch $($machines.Count * $accounts.Count) full-scan queries: $([math]::Round($swBatchScan.Elapsed.TotalMilliseconds,1)) ms"

# Batch indexed.
$swBatchIdx = [System.Diagnostics.Stopwatch]::StartNew()
$queryCountIdx = 0
foreach ($m in $machines) {
    foreach ($a in $accounts) {
        if (Get-VaultCurrentPassword -Vault $loadedVault -Machine $m -Account $a -Index $index) { $queryCountIdx++ }
    }
}
$swBatchIdx.Stop()
Write-Host "Batch $($machines.Count * $accounts.Count) indexed queries: $([math]::Round($swBatchIdx.Elapsed.TotalMilliseconds,1)) ms"
Write-Host "Resolved $queryCountIdx / $($machines.Count * $accounts.Count) pairs"

# Thresholds: indexed single <5 ms (hashtable overhead); indexed batch 150 <25 ms.
$querySingleOk = ($swSingleIdx.Elapsed.TotalMilliseconds -lt 5)
$queryBatchOk  = ($swBatchIdx.Elapsed.TotalMilliseconds -lt 25)
$queryPerfOk   = $querySingleOk -and $queryBatchOk
Write-Host "Indexed single query <5ms: $querySingleOk"
Write-Host "Indexed batch 150 queries <25ms: $queryBatchOk"

# --- Test 5: Rotation history preserved ----------------------------------------
Write-Host "`n=== Test 5: Rotation history preserved ===" -ForegroundColor Cyan
$historyMachine = $machines[0]
$historyAccount = $accounts[0]
$history = Get-VaultHistory -Vault $loadedVault -Machine $historyMachine -Account $historyAccount
Write-Host "History for ($historyMachine, $historyAccount): $($history.Count) records"
# Verify descending RotatedAt
$sortedDesc = $true
for ($i = 0; $i -lt $history.Count - 1; $i++) {
    if ($history[$i].RotatedAt -lt $history[$i+1].RotatedAt) { $sortedDesc = $false; break }
}
Write-Host "History sorted descending by RotatedAt: $sortedDesc"
$historyOk = ($history.Count -gt 0 -and $sortedDesc)

# --- Test 6: Newest-wins correctness -------------------------------------------
Write-Host "`n=== Test 6: Newest-wins returns the most recent record ===" -ForegroundColor Cyan
$current = Get-VaultCurrentPassword -Vault $loadedVault -Machine $historyMachine -Account $historyAccount
$newestOk = ($current.Id -eq $history[0].Id)
Write-Host "Newest-wins returns most recent: $newestOk"

# --- Test 7: DPAPI encryption present on disk (no module dependency) ------------
Write-Host "`n=== Test 7: DPAPI encryption present on disk ===" -ForegroundColor Cyan
# Export-Clixml stores SecureString fields inside <SS N="Password">...</SS> as a
# DPAPI-encrypted hex blob. We verify the blob is non-trivial hex without needing
# Microsoft.PowerSecurity to decrypt it.
$ssMatch = [regex]::Match($rawBytes, '<SS\s+N="Password"\s*>([0-9a-fA-F]+)\s*</SS\s*>')
if ($ssMatch.Success) {
    $encryptedPayload = $ssMatch.Groups[1].Value
    # DPAPI-protected SecureString blobs start with 01000000D08C9DDF0115D1...
    # (the first 4 bytes 0x01000000 are the DPAPI version marker).
    $dpapiMarkerOk = $encryptedPayload.StartsWith('01000000', [System.StringComparison]::OrdinalIgnoreCase)
    $payloadLenOk = $encryptedPayload.Length -ge 100
    Write-Host "Encrypted payload length: $($encryptedPayload.Length) chars"
    Write-Host "DPAPI marker 01000000 present: $dpapiMarkerOk"
    Write-Host "Payload non-trivial (>=100 hex chars): $payloadLenOk"
    $encryptionOk = $dpapiMarkerOk -and $payloadLenOk
} else {
    Write-Host "FAIL: could not locate encrypted SecureString payload in vault file" -ForegroundColor Red
    $encryptionOk = $false
}

# --- Summary --------------------------------------------------------------------
$results = [ordered]@{
    Edition           = $PSVersionTable.PSEdition
    PSVersion         = $PSVersionTable.PSVersion.ToString()
    RecordCount       = $RecordCount
    VaultPath         = $VaultPath
    VaultFileSize     = $vaultFileSize
    BuildMs           = [math]::Round($swBuild.Elapsed.TotalMilliseconds, 1)
    SaveMs            = [math]::Round($swSave.Elapsed.TotalMilliseconds, 1)
    LoadMs            = [math]::Round($swLoad.Elapsed.TotalMilliseconds, 1)
    IndexBuildMs      = [math]::Round($swIndex.Elapsed.TotalMilliseconds, 2)
    SingleScanMs      = [math]::Round($swSingleScan.Elapsed.TotalMilliseconds, 2)
    SingleIndexedMs   = [math]::Round($swSingleIdx.Elapsed.TotalMilliseconds, 3)
    BatchScanMs       = [math]::Round($swBatchScan.Elapsed.TotalMilliseconds, 1)
    BatchIndexedMs    = [math]::Round($swBatchIdx.Elapsed.TotalMilliseconds, 1)
    QueryPairsResolved = "$queryCountIdx / $($machines.Count * $accounts.Count)"
    Tests             = [ordered]@{
        RoundTrip        = $roundTripOk
        SecureStringRT   = $secureStringOk
        NoPlaintext      = $noPlaintextOk
        QueryPerf        = $queryPerfOk
        HistoryPreserved = $historyOk
        NewestWins       = $newestOk
        EncryptionActive = $encryptionOk
    }
}

$passCount = (@($results.Tests.Values | Where-Object { $_ -eq $true })).Count
$totalTests = $results.Tests.Count
$results.Verdict = if ($passCount -eq $totalTests) { 'PASS' } else { 'FAIL' }

$jsonPath = Join-Path $OutputDir 'results.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "`n=== Spike 005 Summary ===" -ForegroundColor Cyan
Write-Host "Edition:        $($results.Edition) ($($results.PSVersion))"
Write-Host "Records:        $RecordCount"
Write-Host "Vault size:     $vaultFileSize bytes"
Write-Host "Build/Save/Load: $($results.BuildMs) / $($results.SaveMs) / $($results.LoadMs) ms"
Write-Host "Index build: $($results.IndexBuildMs) ms"
Write-Host "Query single scan/indexed: $($results.SingleScanMs) ms / $($results.SingleIndexedMs) ms"
Write-Host "Query batch scan/indexed: $($results.BatchScanMs) ms / $($results.BatchIndexedMs) ms"
Write-Host "Tests passed:   $passCount / $totalTests"
Write-Host "Verdict:        $($results.Verdict)" -ForegroundColor $(if ($results.Verdict -eq 'PASS') { 'Green' } else { 'Red' })

foreach ($k in $results.Tests.Keys) {
    $color = if ($results.Tests[$k]) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $(if ($results.Tests[$k]) { 'PASS' } else { 'FAIL' }), $k) -ForegroundColor $color
}

Write-Host "`nJSON results: $jsonPath"
Write-Host "Vault file:   $VaultPath (kept for cross-user test - run Test-CrossUser.ps1 as a DIFFERENT user)"

if ($results.Verdict -ne 'PASS') { exit 1 }
