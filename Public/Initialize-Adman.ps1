function Initialize-Adman {
    <#
    .SYNOPSIS
        Initialize an adman session (load/validate config, probe capabilities, set fail-closed flags).
    .DESCRIPTION
        Phase 0 scaffold stub. The real body lands in plan 00-03 (config load + deny-list seed,
        protected-SID resolution, audit-dir verification, capability probe). Exported so Start-Adman
        (Phase 1 menu) can invoke it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-PSFMessage -Level Verbose -Message 'Initialize-Adman: not implemented until 00-03'
    return
}
