#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-AdmanConfig {
    <#
    .SYNOPSIS
        Get-AdmanConfig - read-only access to the loaded adman config (CONF-01).
    .DESCRIPTION
        Returns the resolved, fail-closed-validated config from $script:Config (the authoritative
        in-session safety source populated by Initialize-AdmanConfig). Read-only: no ShouldProcess,
        no mutation. With -Key, returns a single value; dotted keys (e.g. 'safety.bulkConfirmThreshold')
        are supported. If the config is not yet loaded, Initialize-AdmanConfig is invoked first (which
        enforces CONF-02 fail-closed, so a Get can never observe a half-valid config).
    .NOTES
        D-01: the safety values come from $script:Config (plain-JSON parse in Initialize-AdmanConfig),
        never from PSFramework's per-user/per-machine auto-import locations (Pitfall 7 / T-00-07).
    .PARAMETER Key
        Optional config key (supports dotted paths, e.g. 'transport.timeouts.WinRM'). When omitted the
        whole config object is returned as a deep-cloned snapshot; modifications to the returned object
        do not affect the authoritative in-memory config.

    .EXAMPLE
        Get-AdmanConfig
        Returns the full loaded config object as a deep-cloned snapshot.

    .EXAMPLE
        Get-AdmanConfig -Key 'safety.bulkConfirmThreshold'
        Returns the value of the specified dotted key.
    #>

    [CmdletBinding()]
    param([string]$Key)

    if (-not $script:ConfigLoaded) { Initialize-AdmanConfig | Out-Null }

    if (-not $Key) { return ($script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

    $cursor = $script:Config
    foreach ($name in ($Key -split '\.')) {
        if ($null -eq $cursor) { return $null }
        if ($cursor.PSObject.Properties.Name -contains $name) {
            $cursor = $cursor.$name
        } else {
            return $null
        }
    }
    return $cursor
}
