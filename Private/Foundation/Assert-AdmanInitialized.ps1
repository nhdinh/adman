#Requires -Version 5.1
Set-StrictMode -Version Latest

function Assert-AdmanInitialized {
    <#
    .SYNOPSIS
        Assert-AdmanInitialized - central fail-closed initialization guard.

    .DESCRIPTION
        Verifies that Initialize-Adman completed successfully and that every
        safety cache required by the mutation gate is populated. A session that
        fails partway through Initialize-Adman can leave $script:Config loaded
        while $script:ProtectedSIDs, $script:DenyRids, and $script:ProtectedGroupDns
        remain empty. Calling code must therefore guard on the initialized state,
        not merely on the presence of $script:Config.ManagedOUs.

    .NOTES
        Used by every public verb as a single, centralized initialization check.
    #>
    [CmdletBinding()]
    param()

    $initialized = Get-Variable Initialized -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $protectedSIDs = Get-Variable ProtectedSIDs -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $denyRids = Get-Variable DenyRids -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $protectedGroupDns = Get-Variable ProtectedGroupDns -Scope Script -ValueOnly -ErrorAction SilentlyContinue

    if (-not $initialized -or
        -not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs -or
        $null -eq $protectedSIDs -or
        $null -eq $denyRids -or
        $null -eq $protectedGroupDns) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }
}
