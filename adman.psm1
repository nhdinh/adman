# adman root module (Phase 0, plan 00-01 scaffold).
#
# Loader contract:
#   * Module-wide fail-fast: $ErrorActionPreference = 'Stop' (SAFE-08 boundary foundation).
#   * Dot-source Private/**/*.ps1 first, then Public/**/*.ps1 (sorted, recursive).
#   * Runtime export set == manifest FunctionsToExport (Export-ModuleMember -Function $public).
#   * Import is side-effect-free: NO domain touch, NO auto-run of Initialize-Adman.
#     Init/capability probing is invoked explicitly by Start-Adman / Initialize-Adman.

$ErrorActionPreference = 'Stop'

# Session configuration slot (populated by Initialize-Adman in 00-02).
# All AD cmdlets read -Server from $script:Config.DC (pinned per RESEARCH Pitfall 1/6).
$script:Config = @{}

# IN-03 fix: module-level default password length. The literal '20' was repeated in 11
# sites as the fallback when $script:Config.security.passwordGeneration.length is absent.
# Single source here so a future change is one edit, not eleven. Consumers fall back to
# this constant when the config value is missing.
$script:DefaultPasswordLength = 20

# Default store location (gitignored). Initialized here because consumers run under
# Set-StrictMode -Version Latest: reading an UNSET $script:StorePath to lazy-default it
# throws before the default can apply. Tests override this with a $TestDrive path.
$script:StorePath = '.store'

# Per-machine local-scope cache (Test-AdmanLocalTargetAllowed). Same StrictMode rule:
# its lazy default reads the unset variable, which throws before assignment.
$script:LocalMachineScopeCache = @{}

# Load Private (helpers/gate) first, then Public (exported verbs).
foreach ($scope in @('Private', 'Public')) {
    $dir = Join-Path $PSScriptRoot $scope
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Filter *.ps1 -Recurse -File |
        Sort-Object -Property FullName |
        ForEach-Object { . $_.FullName }
}

# Runtime export boundary mirrors the manifest (static boundary). Keep identical each plan.
$publicDir = Join-Path $PSScriptRoot 'Public'
$public = @()
if (Test-Path -LiteralPath $publicDir) {
    $public = Get-ChildItem -LiteralPath $publicDir -Filter *.ps1 -Recurse -File |
        ForEach-Object { $_.BaseName }
}
if ($public.Count -gt 0) {
    Export-ModuleMember -Function $public
}
