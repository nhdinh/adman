#Requires -Version 5.1
Set-StrictMode -Version Latest

function Start-Adman {
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
          4. Dispatch via the call operator with the splatted parameter hashtable.
          5. After the verb returns its PSCustomObject[], present an inline output-format
             prompt (1=console, 2=CSV, 3=HTML, 4=grid if available, B=back, Q=quit).
             For CSV/HTML, prompt for the output path and validate the parent directory
             exists before invoking the renderer; on invalid path, re-prompt once then
             treat a second failure as 'B'.
          6. PROPERTIES PROPAGATION (Cycle 4 finding): read the selected menu entry's
             Properties field (from Get-AdmanMenuDefinition) and pass it as -Properties
             to the chosen renderer. This guarantees that when a report verb returns
             zero rows, the CSV/HTML/console output still renders the header row from
             the D-03 schema instead of a zero-byte file or a no-table document.
    
        The menu contains no AD read logic and no formatting logic beyond the banner.
        Every verb dispatched is the same Public function a senior calls directly
        (MENU-04).
    
        READ-ONLY TUI: this function never mutates state, so it deliberately declares
        plain [CmdletBinding()] without the ShouldProcess attribute (review LOW).

    .EXAMPLE
        Start-Adman
        Launches the interactive adman TUI menu.
    #>

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

    :menuLoop while ($true) {
        Write-Host 'adman - AD Manager' -ForegroundColor Cyan
        Write-Host ''
        # SEPARATOR SKIP (Phase 2): entries with Verb=$null are non-selectable
        # section separators. Render them as plain text lines (no number prefix)
        # and exclude them from the numbered selection list. Build a parallel
        # array mapping display-number -> menu-index so selection stays correct
        # when separators are interleaved.
        $selectable = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt @($menu).Count; $i++) {
            if ($null -eq $menu[$i].Verb) {
                Write-Host $menu[$i].Label -ForegroundColor DarkCyan
            } else {
                [void]$selectable.Add($i)
                Write-Host ("{0}. {1}" -f $selectable.Count, $menu[$i].Label)
            }
        }
        Write-Host 'Q. Quit'
        Write-Host ''

        $selection = Read-Host 'Select'

        if ($selection -match '^[Qq]$') {
            break
        }

        $n = 0
        if (-not [int]::TryParse($selection, [ref]$n) -or $n -lt 1 -or $n -gt $selectable.Count) {
            Write-Host 'Invalid selection. Enter a number or Q.'
            continue
        }

        $entry = $menu[$selectable[$n - 1]]
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

        # FIXEDPARAMETERS MERGE (MEDIUM #6 review fix): merge the entry's
        # FixedParameters hashtable into $params BEFORE dispatch. The merge happens
        # AFTER prompting so fixed values are always present and never prompted for.
        # Used by the Set-AdmanLocalUser Enable/Disable entries to inject the
        # -Enable / -Disable switch declaratively (the operator picked the action
        # by picking the menu item; no further prompt).
        # WR-06 fix: warn when a FixedParameters key collides with a prompted parameter
        # so a future menu entry that accidentally overwrites operator input is visible
        # at runtime, not silently discarded.
        if ($null -ne $entry.FixedParameters) {
            foreach ($key in $entry.FixedParameters.Keys) {
                if ($params.ContainsKey($key)) {
                    Write-Warning "FixedParameters key '$key' collides with prompted parameter; using fixed value."
                }
                $params[$key] = $entry.FixedParameters[$key]
            }
        }

        # MENU-04: dispatch the same Public verb a senior calls directly.
        # WR-09 fix: validate the verb resolves to a loaded function BEFORE dispatch.
        # A typo in the menu definition or a verb that failed to export from the module
        # would otherwise throw a generic CommandNotFoundException with no context about
        # which menu entry failed.
        $cmd = Get-Command -Name $Verb -ErrorAction SilentlyContinue
        if ($null -eq $cmd) {
            Write-Host "Menu entry '$($entry.Label)' dispatches to '$Verb' which is not loaded. Contact the adman maintainer." -ForegroundColor Red
            continue
        }
        $reportData = & $Verb @params

        # WORKFLOW OUTPUT SKIP (Phase 4): onboarding/offboarding/restore produce their
        # own status/checklist text and should not be forced through the generic output
        # renderer. If the menu entry declares SkipOutputPrompt=$true, return to the
        # top-level menu immediately after the verb returns.
        if ($entry.PSObject.Properties.Name -contains 'SkipOutputPrompt' -and
            $entry.SkipOutputPrompt -eq $true) {
            continue
        }

        # --- Output-format prompt (D-04) -------------------------------------
        # Present inline output-format choices after the verb returns. B returns
        # to the top-level menu; Q exits Start-Adman.
        $formatChoice = $null
        $formatResolved = $false
        while (-not $formatResolved) {
            Write-Host ''
            Write-Host 'Output format:'
            Write-Host '1. Console table'
            Write-Host '2. CSV file'
            Write-Host '3. HTML file'
            Write-Host '4. Grid picker (if available)'
            Write-Host 'B. Back to menu'
            Write-Host 'Q. Quit'
            $formatChoice = Read-Host 'Select format'

            if ($formatChoice -match '^[Qq]$') {
                break menuLoop  # Exit both the format loop and the top-level menu loop.
            }
            if ($formatChoice -match '^[Bb]$') {
                $formatResolved = $true
                continue
            }

            $formatNum = 0
            if (-not [int]::TryParse($formatChoice, [ref]$formatNum) -or $formatNum -lt 1 -or $formatNum -gt 4) {
                Write-Host 'Invalid selection. Enter a number, B, or Q.'
                continue
            }

            # Resolve the renderer and any additional parameters.
            $renderer = $null
            $rendererParams = @{}
            switch ($formatNum) {
                1 { $renderer = 'Format-AdmanReport' }
                2 {
                    $renderer = 'Export-AdmanReportCsv'
                    $pathResolved = $false
                    $pathAttempts = 0
                    while (-not $pathResolved -and $pathAttempts -lt 2) {
                        $outPath = Read-Host 'Enter CSV output path'
                        if ($outPath -match '^[Bb]$') { $formatResolved = $true; break }
                        if ($outPath -match '^[Qq]$') { break menuLoop }
                        $parent = Split-Path -Path $outPath -Parent
                        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
                        if (Test-Path -LiteralPath $parent -PathType Container) {
                            $rendererParams['Path'] = $outPath
                            $pathResolved = $true
                        } else {
                            $pathAttempts++
                            if ($pathAttempts -lt 2) {
                                Write-Host "Directory does not exist: $parent. Re-enter path or B to cancel."
                            } else {
                                Write-Host "Directory does not exist: $parent. Returning to menu."
                                $formatResolved = $true
                            }
                        }
                    }
                    if (-not $pathResolved) { continue }
                }
                3 {
                    $renderer = 'Export-AdmanReportHtml'
                    $pathResolved = $false
                    $pathAttempts = 0
                    while (-not $pathResolved -and $pathAttempts -lt 2) {
                        $outPath = Read-Host 'Enter HTML output path'
                        if ($outPath -match '^[Bb]$') { $formatResolved = $true; break }
                        if ($outPath -match '^[Qq]$') { break menuLoop }
                        $parent = Split-Path -Path $outPath -Parent
                        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
                        if (Test-Path -LiteralPath $parent -PathType Container) {
                            $rendererParams['Path'] = $outPath
                            $pathResolved = $true
                        } else {
                            $pathAttempts++
                            if ($pathAttempts -lt 2) {
                                Write-Host "Directory does not exist: $parent. Re-enter path or B to cancel."
                            } else {
                                Write-Host "Directory does not exist: $parent. Returning to menu."
                                $formatResolved = $true
                            }
                        }
                    }
                    if (-not $pathResolved) { continue }
                }
                4 {
                    $renderer = 'Format-AdmanReport'
                    $rendererParams['UseGridView'] = $true
                }
            }

            if ($null -ne $renderer) {
                # PROPERTIES PROPAGATION (Cycle 4 finding): pass the menu entry's
                # Properties field to the renderer so a zero-row report still
                # renders headers from the D-03 schema.
                $rendererParams['Properties'] = $entry.Properties
                & $renderer -InputObject $reportData @rendererParams
                $formatResolved = $true
            }
        }
    }
}
