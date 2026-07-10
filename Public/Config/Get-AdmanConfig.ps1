#Requires -Version 5.1
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
    whole config object is returned.
#>
function Get-AdmanConfig {
    [CmdletBinding()]
    param([string]$Key)

    if (-not $script:ConfigLoaded) { Initialize-AdmanConfig | Out-Null }

    if (-not $Key) { return $script:Config }

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
