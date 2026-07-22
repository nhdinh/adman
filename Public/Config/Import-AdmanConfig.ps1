#Requires -Version 5.1
Set-StrictMode -Version Latest

function Import-AdmanConfig {
    <#
    .SYNOPSIS
        Import-AdmanConfig - validated, fail-closed config restore (CONF-02/03, T-00-13).
    .DESCRIPTION
        State-changing verb (ShouldProcess, ConfirmImpact='High'). Reads a plain-JSON config file
        (ConvertFrom-Json into a PSCustomObject - 5.1-safe, no Core-only hashtable switch), strips
        '_comment' annotation keys, re-runs the single Task-2 validator (Test-AdmanConfigValid) and the
        CONF-02 fail-closed scope check, then persists into the active store via Save-AdmanConfig
        (ConvertTo-Json -Depth 5) and publishes $script:Config. Because every restore is validated
        before it is published, an imported config cannot weaken ManagedOUs/DenyList/safety (T-00-13).
    
        The authoritative values come from the direct ConvertFrom-Json parse (framework-independent);
        Import-PSFConfig -Path is then invoked best-effort for the D-01 backbone only - it is never the
        safety source, so a non-envelope/plain file can never fail-open (Pitfall 7 / T-00-07).
    .PARAMETER Path
        Source plain-JSON file to restore from (required).
    .PARAMETER SetupMode
        First-run wizard/init restore: bypasses ONLY the empty-ManagedOUs fail-closed gate; still
        validates structure and performs NO AD mutation (D-04).

    .EXAMPLE
        Import-AdmanConfig -Path 'C:\backups\adman-config.json'
        Restores and validates a config from a plain-JSON backup.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$SetupMode
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Import-AdmanConfig: file not found: '$Path'"
    }
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Import-AdmanConfig: failed to parse '$Path': $($_.Exception.Message)"
    }
    $config = ConvertTo-AdmanCleanConfig -Node $parsed

    # Single validator (D-04) then CONF-02 fail-closed - an import cannot weaken scope/deny-list (T-00-13).
    Test-AdmanConfigValid -Config $config -ModuleRoot $moduleRoot | Out-Null
    if (-not $SetupMode) {
        if (@($config.ManagedOUs).Count -lt 1) {
            throw "FAIL-CLOSED: managed-OU scope (ManagedOUs) is empty; refusing to import a config with no managed-OU root."
        }
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Import adman config')) {
        if (-not $script:StorePath) { $script:StorePath = '.store' }
        $target = Join-Path $script:StorePath 'config.json'
        Save-AdmanConfig -Config $config -Path $target -Confirm:$false
        $script:Config = $config
        $script:ConfigLoaded = $true
        # D-01 backbone mirror (best-effort; not the safety source - see Pitfall 7 / T-00-07).
        try { Import-PSFConfig -Path $target -ErrorAction SilentlyContinue } catch { }
    }
}
