#Requires -Version 5.1
<#
.SYNOPSIS
    Start-Adman - read-only adman console menu entry point (Phase 1, D-01).

.DESCRIPTION
    Flat while-loop TUI dispatcher. Calls Initialize-Adman once, prints the startup
    banner (domain, DC, capability flags), then loops:

      1. Print the numbered menu from Get-AdmanMenuDefinition (1..N) plus 'Q. Quit'.
      2. Read-Host 'Select' - accept integer 1..N or 'Q'. 'B' is NOT reserved at the
         top level (it is reserved inside action prompts per UI-SPEC §Reserved inputs).
      3. For a valid choice, call Read-AdmanActionParams with the entry's PromptSpec
         to build the parameter hashtable. 'B' inside a prompt returns $null (resume
         the loop); 'Q' throws the ADMAN_QUIT sentinel which this loop catches and
         breaks on.
      4. Dispatch via the call operator with the splatted parameter hashtable and
         emit the returned PSCustomObject[] directly. Renderer dispatch is Plan
         01-04 - the menu body NEVER calls a renderer.

    The menu contains no AD read logic and no formatting logic beyond the banner.
    Every verb dispatched is the same Public function a senior calls directly
    (MENU-04).

    READ-ONLY TUI: this function never mutates state, so it deliberately declares
    plain [CmdletBinding()] without the ShouldProcess attribute (review LOW).
#>

Set-StrictMode -Version Latest

function Start-Adman {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param()

    Initialize-Adman

    # --- Startup banner -------------------------------------------------------
    $line = '=' * 60
    Write-Host $line -ForegroundColor DarkGray
    Write-Host ' adman - AD Manager' -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor DarkGray

    $domain = $null
    $dc = $null
    if ($null -ne $script:Config) {
        if ($script:Config.PSObject.Properties.Name -contains 'Domain') { $domain = $script:Config.Domain }
        if ($script:Config.PSObject.Properties.Name -contains 'DC') { $dc = $script:Config.DC }
    }
    if ($domain) { Write-Host (" Domain  : {0}" -f $domain) }
    if ($dc) { Write-Host (" DC      : {0}" -f $dc) }

    # Recovery posture / freshness lines are Wave 2+ (Plan 01-03) - render only when
    # the keys are already present on $script:Config so the banner never throws
    # during Wave 1 execution.
    if ($null -ne $script:Config -and
        $script:Config.PSObject.Properties.Name -contains 'RecoveryPosture' -and
        $null -ne $script:Config.RecoveryPosture) {
        $rp = $script:Config.RecoveryPosture
        $rb = if ($null -ne $rp.RecycleBinEnabled) { if ($rp.RecycleBinEnabled) { 'Yes' } else { 'No' } } else { 'unknown' }
        $ffl = if ($null -ne $rp.ForestFunctionalLevel) { $rp.ForestFunctionalLevel } else { 'unknown' }
        Write-Host (" Recovery: RecycleBin={0}, FFL={1}" -f $rb, $ffl)
    }
    if ($null -ne $script:Config -and
        $script:Config.PSObject.Properties.Name -contains 'LogonSyncIntervalDays' -and
        $null -ne $script:Config.LogonSyncIntervalDays) {
        Write-Host (" Freshness: lastLogonTimestamp fresh to within {0} days" -f $script:Config.LogonSyncIntervalDays)
    }

    Write-Host ('-' * 60) -ForegroundColor DarkGray

    if ($null -ne $script:Capability) {
        foreach ($prop in $script:Capability.PSObject.Properties) {
            $color = if ($prop.Value) { 'Green' } else { 'Yellow' }
            Write-Host (" {0} = {1}" -f $prop.Name, $prop.Value) -ForegroundColor $color
        }
    }

    Write-Host $line -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ''

    # --- Flat menu loop -------------------------------------------------------
    $menu = Get-AdmanMenuDefinition

    while ($true) {
        Write-Host 'adman - AD Manager' -ForegroundColor Cyan
        Write-Host ''
        for ($i = 0; $i -lt @($menu).Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i + 1), $menu[$i].Label)
        }
        Write-Host 'Q. Quit'
        Write-Host ''

        $selection = Read-Host 'Select'

        if ($selection -match '^[Qq]$') {
            break
        }

        $n = 0
        if (-not [int]::TryParse($selection, [ref]$n) -or $n -lt 1 -or $n -gt @($menu).Count) {
            Write-Host 'Invalid selection. Enter a number or Q.'
            continue
        }

        $entry = $menu[$n - 1]
        $Verb = [string]$entry.Verb

        try {
            $params = Read-AdmanActionParams -PromptSpec $entry.PromptSpec
        } catch {
            if ($_.Exception.Message -match 'ADMAN_QUIT') {
                break
            }
            throw
        }

        if ($null -eq $params) {
            # Operator typed B (or second empty on a required field) inside the action
            # prompts - resume the top-level loop.
            continue
        }

        # MENU-04: dispatch the same Public verb a senior calls directly.
        # Renderer dispatch is Plan 01-04 - emit the PSCustomObject[] as-is.
        & $Verb @params
    }
}
