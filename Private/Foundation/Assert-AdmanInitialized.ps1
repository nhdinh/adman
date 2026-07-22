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

    if (-not $script:Initialized -or
        -not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs -or
        -not $script:ProtectedSIDs -or
        -not $script:DenyRids -or
        -not $script:ProtectedGroupDns) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }
}
