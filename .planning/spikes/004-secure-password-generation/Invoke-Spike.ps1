#requires -Version 5.1
<#
.SYNOPSIS
    Spike 004 — validate CSPRNG-backed password generation on PS 5.1 and PS 7.

.DESCRIPTION
    Generates N passwords using System.Security.Cryptography.RandomNumberGenerator
    with rejection sampling (no modulo bias), then validates:
      - length matches policy
      - at least 1 char from each of 4 classes (upper/lower/digit/symbol)
      - no ambiguous chars (0 O l 1 I)
      - all N unique
      - per-position character-class distribution is roughly uniform
    Emits a JSON summary and an HTML report the user can open.

.NOTES
    Cross-edition contract: must produce identical behavior on
    Windows PowerShell 5.1 (.NET Framework 4.x) and PowerShell 7.6 (.NET 10).
    Avoids RandomNumberGenerator.GetInt32() because it does not exist on .NET Fx.
#>
[CmdletBinding()]
param(
    [int]$Count = 1000,
    [int]$Length = 20,
    [string]$OutputDir = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Defensive fallback: $PSScriptRoot can come up empty when the script is invoked
# via -File with a forward-slash path on PS 5.1. Resolve from MyInvocation instead.
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# --- Alphabet: 4 classes, no ambiguous glyphs ---------------------------------
$Upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()   # 23 (excludes I, O)
$Lower  = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray()   # 23 (excludes l, o)
$Digit  = '23456789'.ToCharArray()                   # 8  (excludes 0, 1)
$Symbol = '!@#$%^&*-_=+[]{}|;:,.<>?'.ToCharArray()   # 22 (shell-safe subset)
$All    = $Upper + $Lower + $Digit + $Symbol         # 76

function Get-CsprngIndex {
    <#
        Rejection-sample a uniform byte into [0, $AlphabetSize).
        Avoids modulo bias: accept byte b only if b < AlphabetSize * floor(256/AlphabetSize).
    #>
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

function New-AdmanRandomPassword {
    param(
        [Parameter(Mandatory)][int]$Length
    )
    if ($Length -lt 4) { throw "Length must be >= 4 to guarantee all four character classes." }

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        # Guarantee at least one of each class.
        $chars = [System.Collections.Generic.List[char]]::new($Length)
        $chars.Add($Upper[(Get-CsprngIndex -Rng $rng -AlphabetSize $Upper.Count)])
        $chars.Add($Lower[(Get-CsprngIndex -Rng $rng -AlphabetSize $Lower.Count)])
        $chars.Add($Digit[(Get-CsprngIndex -Rng $rng -AlphabetSize $Digit.Count)])
        $chars.Add($Symbol[(Get-CsprngIndex -Rng $rng -AlphabetSize $Symbol.Count)])

        # Fill the rest from the union alphabet.
        for ($i = $chars.Count; $i -lt $Length; $i++) {
            $chars.Add($All[(Get-CsprngIndex -Rng $rng -AlphabetSize $All.Count)])
        }

        # Fisher-Yates shuffle using CSPRNG for the swap index.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = Get-CsprngIndex -Rng $rng -AlphabetSize ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }

        return -join $chars
    }
    finally {
        $rng.Dispose()
    }
}

function Test-PasswordPolicy {
    param([Parameter(Mandatory)][string]$Password, [Parameter(Mandatory)][int]$ExpectedLength)
    $result = [ordered]@{
        LengthOk   = $Password.Length -eq $ExpectedLength
        HasUpper   = [bool]($Password -match '[A-Z]')
        HasLower   = [bool]($Password -match '[a-z]')
        HasDigit   = [bool]($Password -match '\d')
        HasSymbol  = [bool]($Password -match '[^A-Za-z0-9]')
        # Case-SENSITIVE match — default -match is case-insensitive and would
        # false-positive on L (Upper) and i (Lower), which are NOT ambiguous.
        NoAmbiguous = -not [bool]($Password -cmatch '[0Ool1I]')
    }
    $result.Pass = (@($result.Values | Where-Object { $_ -eq $false })).Count -eq 0
    return [pscustomobject]$result
}

# --- Run -----------------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$passwords = [System.Collections.Generic.List[string]]::new($Count)
for ($i = 0; $i -lt $Count; $i++) {
    $passwords.Add((New-AdmanRandomPassword -Length $Length))
}
$stopwatch.Stop()

# --- Validate ------------------------------------------------------------------
$policyFailures = 0
$perClassHits   = @{ Upper = 0; Lower = 0; Digit = 0; Symbol = 0 }
$ambiguousHits  = 0
$lengthDist     = @{}
$positionClassDist = @{}   # position -> class -> count (for uniformity check)

foreach ($pw in $passwords) {
    $t = Test-PasswordPolicy -Password $pw -ExpectedLength $Length
    if (-not $t.Pass) { $policyFailures++ }
    if ($t.HasUpper)  { $perClassHits.Upper++  }
    if ($t.HasLower)  { $perClassHits.Lower++  }
    if ($t.HasDigit)  { $perClassHits.Digit++  }
    if ($t.HasSymbol) { $perClassHits.Symbol++ }
    if (-not $t.NoAmbiguous) { $ambiguousHits++ }
    $lengthDist[$pw.Length] = 1 + ($lengthDist[$pw.Length] | ForEach-Object { $_ } )

    # Per-position class distribution (is any position biased toward a class?)
    # Use STRING keys — PS 7's ConvertTo-Json rejects Hashtables with non-string keys.
    # Use -ccontains (case-sensitive) — default -contains would misclassify every
    # lowercase letter as Upper.
    for ($pos = 0; $pos -lt $pw.Length; $pos++) {
        $c = $pw[$pos]
        $cls = if ($Upper -ccontains $c) { 'Upper' }
               elseif ($Lower -ccontains $c) { 'Lower' }
               elseif ($Digit -ccontains $c) { 'Digit' }
               elseif ($Symbol -ccontains $c) { 'Symbol' }
               else { 'Unknown' }
        $posKey = [string]$pos
        if (-not $positionClassDist.ContainsKey($posKey)) {
            $positionClassDist[$posKey] = @{ Upper = 0; Lower = 0; Digit = 0; Symbol = 0; Unknown = 0 }
        }
        $positionClassDist[$posKey][$cls]++
    }
}

$uniqueCount = ($passwords | Select-Object -Unique).Count
$duplicateCount = $Count - $uniqueCount

# Expected per-position class share (alphabet-proportional):
# Upper 23/76 = 30.3%, Lower 23/76 = 30.3%, Digit 8/76 = 10.5%, Symbol 22/76 = 28.9%
# (Slightly perturbed by the guaranteed-class seeding, but should be near-uniform across positions.)

$summary = [ordered]@{
    Edition              = $PSVersionTable.PSEdition
    PSVersion            = $PSVersionTable.PSVersion.ToString()
    DotNet               = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    Count                = $Count
    Length               = $Length
    AlphabetSize         = $All.Count
    PolicyFailures       = $policyFailures
    DuplicateCount       = $duplicateCount
    AmbiguousCharHits    = $ambiguousHits
    PerClassPresence     = $perClassHits
    DurationMs           = $stopwatch.Elapsed.TotalMilliseconds
    PasswordsPerSecond   = [math]::Round($Count / ($stopwatch.Elapsed.TotalMilliseconds / 1000), 0)
    SamplePasswords      = $passwords[0..9]
    PositionClassDist    = $positionClassDist
    Verdict              = if ($policyFailures -eq 0 -and $duplicateCount -eq 0 -and $ambiguousHits -eq 0) { 'PASS' } else { 'FAIL' }
}

$jsonPath = Join-Path $OutputDir 'results.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

# --- HTML report ----------------------------------------------------------------
$sampleRows = ($summary.SamplePasswords | ForEach-Object {
    "<tr><td><code>$_</code></td><td>$($_.Length)</td></tr>"
}) -join "`n"

$classRows = ($perClassHits.GetEnumerator() | ForEach-Object {
    $pct = [math]::Round(100.0 * $_.Value / $Count, 1)
    $bar = '#' * [math]::Floor($pct / 2)
    "<tr><td>$($_.Key)</td><td>$($_.Value)</td><td>$pct%</td><td class='bar'>$bar</td></tr>"
}) -join "`n"

$posRows = (0..($Length-1) | ForEach-Object {
    $posKey = [string]$_
    $d = $positionClassDist[$posKey]
    if (-not $d) { return }
    $uPct = [math]::Round(100.0 * $d.Upper  / $Count, 1)
    $lPct = [math]::Round(100.0 * $d.Lower  / $Count, 1)
    $dPct = [math]::Round(100.0 * $d.Digit  / $Count, 1)
    $sPct = [math]::Round(100.0 * $d.Symbol / $Count, 1)
    "<tr><td>$posKey</td><td>$uPct%</td><td>$lPct%</td><td>$dPct%</td><td>$sPct%</td></tr>"
}) -join "`n"

$verdictColor = if ($summary.Verdict -eq 'PASS') { '#1a7f37' } else { '#cf222e' }
$html = @"
<!doctype html><html><head><meta charset='utf-8'><title>Spike 004 — Password Generation</title>
<style>
  body{font-family:Consolas,monospace;margin:24px;background:#0d1117;color:#c9d1d9}
  h1{color:#58a6ff} h2{color:#79c0ff;border-bottom:1px solid #30363d;padding-bottom:4px}
  table{border-collapse:collapse;margin:12px 0} th,td{padding:4px 12px;border:1px solid #30363d;text-align:left}
  th{background:#161b22} code{background:#161b22;padding:2px 6px;border-radius:3px;color:#79c0ff}
  .verdict{font-size:1.4em;font-weight:bold;color:$verdictColor}
  .bar{color:#58a6ff;font-size:.85em}
  .muted{color:#8b949e}
</style></head><body>
<h1>Spike 004 — Secure Password Generation</h1>
<p class='muted'>Edition: $($summary.Edition) &nbsp;|&nbsp; PS: $($summary.PSVersion) &nbsp;|&nbsp; .NET: $($summary.DotNet)</p>
<p class='muted'>Count: $Count &nbsp;|&nbsp; Length: $Length &nbsp;|&nbsp; Alphabet: $($summary.AlphabetSize) chars &nbsp;|&nbsp; Throughput: $($summary.PasswordsPerSecond)/s &nbsp;|&nbsp; Total: $([math]::Round($summary.DurationMs,1))ms</p>
<p class='verdict'>Verdict: $($summary.Verdict)</p>

<h2>Validation</h2>
<table>
<tr><th>Check</th><th>Result</th></tr>
<tr><td>Policy failures</td><td>$($summary.PolicyFailures) / $Count</td></tr>
<tr><td>Duplicates</td><td>$($summary.DuplicateCount) / $Count</td></tr>
<tr><td>Ambiguous-char hits (0 O l 1 I)</td><td>$($summary.AmbiguousCharHits) / $Count</td></tr>
</table>

<h2>Sample (first 10)</h2>
<table><tr><th>Password</th><th>Len</th></tr>$sampleRows</table>

<h2>Class presence per password (should be 100% each)</h2>
<table><tr><th>Class</th><th>Count</th><th>%</th><th></th></tr>$classRows</table>

<h2>Per-position class distribution % (uniformity check)</h2>
<p class='muted'>If any position is heavily biased toward a class, the shuffle is broken. Expect near-alphabet-proportional (~30/30/10/29) at every position.</p>
<table><tr><th>Pos</th><th>Upper</th><th>Lower</th><th>Digit</th><th>Symbol</th></tr>$posRows</table>

<p class='muted'>Raw JSON: <code>results.json</code></p>
</body></html>
"@

$htmlPath = Join-Path $OutputDir 'report.html'
$html | Set-Content -Path $htmlPath -Encoding UTF8

# --- Console summary -------------------------------------------------------------
Write-Host ""
Write-Host "=== Spike 004 Summary ===" -ForegroundColor Cyan
Write-Host "Edition:        $($summary.Edition) ($($summary.PSVersion))"
Write-Host ".NET:           $($summary.DotNet)"
Write-Host "Count:          $Count passwords, length $Length"
Write-Host "Throughput:     $($summary.PasswordsPerSecond)/s ($([math]::Round($summary.DurationMs,1)) ms total)"
Write-Host "Policy fails:   $($summary.PolicyFailures)"
Write-Host "Duplicates:     $($summary.DuplicateCount)"
Write-Host "Ambiguous hits: $($summary.AmbiguousCharHits)"
Write-Host "Verdict:        $($summary.Verdict)" -ForegroundColor $(if ($summary.Verdict -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host "HTML report:    $htmlPath"
Write-Host "JSON results:   $jsonPath"
Write-Host ""
Write-Host "Sample:         $($passwords[0])"

# Exit code: 0 on PASS, 1 on FAIL (so CI / Pester can consume it)
if ($summary.Verdict -ne 'PASS') { exit 1 }
