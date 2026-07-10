function Start-Adman {
    <#
    .SYNOPSIS
        Entry point for the adman interactive menu (Phase 1).
    .DESCRIPTION
        Phase 0 scaffold stub. Calls Initialize-Adman, then (in Phase 1) renders the guided TUI menu.
        Exported now so the module boundary is stable; the menu body arrives in Phase 1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Initialize-Adman
    Write-PSFMessage -Level Verbose -Message 'Start-Adman: Phase 1 menu not implemented'
    return
}
