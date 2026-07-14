#requires -Version 5.1
<#
.SYNOPSIS
    Cross-user DPAPI isolation test — run as a DIFFERENT user than the one who ran Invoke-Spike.ps1.

.DESCRIPTION
    Attempts to load the vault file created by Invoke-Spike.ps1 and decrypt the
    SecureString password fields. As a different user, DPAPI CurrentUser decryption
    should fail, leaving the SecureStrings empty (length 0) after Import-Clixml.

.EXAMPLE
    # As a different user (e.g., via runas or a separate logon session):
    runas /user:LAB\otheradmin "powershell -NoProfile -File C:\path\to\Test-CrossUser.ps1"

.NOTES
    This script does NOT take destructive action. It only reads the vault file
    and reports whether decryption succeeded (bad — means DPAPI isolation failed)
    or produced empty SecureStrings (good — DPAPI boundary is enforced).
#>
[CmdletBinding()]
param(
    [string]$VaultPath = (Join-Path $PSScriptRoot 'vault-test.clixml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== Cross-User DPAPI Isolation Test ===" -ForegroundColor Cyan
Write-Host "Running as: $env:USERDOMAIN\$env:USERNAME"
Write-Host "Vault path: $VaultPath"

if (-not (Test-Path $VaultPath)) {
    Write-Host "FAIL: vault file not found. Run Invoke-Spike.ps1 first." -ForegroundColor Red
    exit 1
}

$loaded = Import-Clixml -Path $VaultPath
Write-Host "Loaded $($loaded.Records.Count) records."

# Sample the first 10 records and check password lengths.
$sampleSize = [math]::Min(10, $loaded.Records.Count)
$emptyCount = 0
$nonEmptyCount = 0
foreach ($r in $loaded.Records[0..($sampleSize-1)]) {
    if ($r.Password.Length -eq 0) { $emptyCount++ } else { $nonEmptyCount++ }
}

Write-Host "Sample of $sampleSize records:"
Write-Host "  Empty SecureStrings (decrypt failed): $emptyCount"
Write-Host "  Non-empty SecureStrings (decrypt succeeded): $nonEmptyCount"

if ($emptyCount -eq $sampleSize) {
    Write-Host "`nVERDICT: PASS — all sampled passwords failed to decrypt as this user." -ForegroundColor Green
    Write-Host "DPAPI CurrentUser isolation is enforced." -ForegroundColor Green
    exit 0
} elseif ($nonEmptyCount -gt 0) {
    Write-Host "`nVERDICT: FAIL — $nonEmptyCount passwords decrypted successfully." -ForegroundColor Red
    Write-Host "This means either:" -ForegroundColor Red
    Write-Host "  (a) you are running as the SAME user who created the vault (expected: run as a different user), or" -ForegroundColor Red
    Write-Host "  (b) DPAPI isolation is broken (should not happen)." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nVERDICT: INCONCLUSIVE — sampled 0 records." -ForegroundColor Yellow
    exit 2
}
