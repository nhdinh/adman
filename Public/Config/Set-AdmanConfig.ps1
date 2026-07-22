#Requires -Version 5.1
Set-StrictMode -Version Latest

function Set-AdmanConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Key,
        $Value
    )
    $parts = $Key -split '\.'
    $cursor = $Object
    for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
        $name = $parts[$i]
        if (-not ($cursor.PSObject.Properties.Name -contains $name)) {
            $cursor | Add-Member -MemberType NoteProperty -Name $name -Value ([pscustomobject]@{}) -Force
        }
        $cursor = $cursor.$name
    }
    $leaf = $parts[$parts.Count - 1]
    if ($cursor.PSObject.Properties.Name -contains $leaf) {
        $cursor.$leaf = $Value
    } else {
        $cursor | Add-Member -MemberType NoteProperty -Name $leaf -Value $Value -Force
    }
}

function Set-AdmanConfig {
    <#
    .SYNOPSIS
        Set-AdmanConfig - validated, fail-closed config edit (CONF-01/02, T-00-13).
    .DESCRIPTION
        State-changing verb (ShouldProcess, ConfirmImpact='High'). Applies a single key/value change
        (dotted keys supported, e.g. 'safety.bulkConfirmThreshold') to a CLONE of the loaded config,
        re-runs the single Task-2 validator (Test-AdmanConfigValid) and the CONF-02 fail-closed scope
        check, and only then persists via Save-AdmanConfig (ConvertTo-Json -Depth 5). Because the edit
        is validated BEFORE it is written, an admin cannot weaken ManagedOUs/DenyList/safety via this
        verb (T-00-13). A failed validation leaves $script:Config and the file untouched.
    .PARAMETER Key
        Config key to set (supports dotted paths, e.g. 'transport.timeouts.WinRM').
    .PARAMETER Value
        New value for the key.
    .PARAMETER Path
        Config file path; defaults to $script:StorePath\config.json.

    .EXAMPLE
        Set-AdmanConfig -Key 'safety.bulkConfirmThreshold' -Value 10
        Updates a single config value after validation.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]$Value,
        [string]$Path
    )

    if (-not $script:ConfigLoaded) { Initialize-AdmanConfig | Out-Null }
    if (-not $Path) {
        if (-not $script:StorePath) { $script:StorePath = '.store' }
        $Path = Join-Path $script:StorePath 'config.json'
    }
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    # Deep-clone via JSON so a failed validation leaves the live config + file untouched.
    $proposed = $script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    Set-AdmanConfigValue -Object $proposed -Key $Key -Value $Value

    # Single validator (D-04) then CONF-02 fail-closed - a Set cannot weaken scope/deny-list (T-00-13).
    Test-AdmanConfigValid -Config $proposed -ModuleRoot $moduleRoot | Out-Null
    $scopeCount = if ($null -eq $proposed.ManagedOUs) { 0 } else { @($proposed.ManagedOUs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count }
    if ($scopeCount -lt 1) {
        throw "FAIL-CLOSED: managed-OU scope (ManagedOUs) is empty; Set-AdmanConfig cannot remove the last managed-OU root."
    }

    # BL-02: re-absolutize path keys before publishing so relative values resolve to module root.
    if ($proposed.AuditDir -is [string]) {
        $proposed.AuditDir = ConvertTo-AdmanAbsolutePath -Path $proposed.AuditDir -ModuleRoot $moduleRoot
    }
    if ($proposed.ReportDir -is [string]) {
        $proposed.ReportDir = ConvertTo-AdmanAbsolutePath -Path $proposed.ReportDir -ModuleRoot $moduleRoot
    }

    if ($PSCmdlet.ShouldProcess("$Key on $Path", 'Set adman config value')) {
        Save-AdmanConfig -Config $proposed -Path $Path -Confirm:$false
        $script:Config = $proposed
        $script:ConfigLoaded = $true
        # D-01 backbone mirror (best-effort, non-persisted, NOT the safety source): the authoritative
        # value is $script:Config + the plain-JSON file written by Save-AdmanConfig above. No
        # auto-import persistence-registration cmdlet is used, so this can never reach the
        # per-user/per-machine auto-import locations (Pitfall 7 / T-00-07).
        try { Set-PSFConfig -Module adman -Name $Key -Value $Value -ErrorAction SilentlyContinue } catch { }
    }
}
