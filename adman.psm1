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
