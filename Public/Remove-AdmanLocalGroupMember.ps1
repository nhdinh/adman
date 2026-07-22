#Requires -Version 5.1
Set-StrictMode -Version Latest

function Remove-AdmanLocalGroupMember {
    <#
    .SYNOPSIS
        Remove-AdmanLocalGroupMember - remove a local user from a local group through the
        local mutation gate (LUSR-02, D-02).

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
        Invoke-AdmanLocalMutation -Verb 'Remove-LocalGroupMember'. The local gate's policy
        checks apply (Plan 02-01): RID-500 refusal (built-in Administrator by RID, never
        by name), local-Administrators membership check with orphaned-SID tolerance
        (Get-LocalGroupMember try/catch + WMI Win32_GroupUser fallback on 0x80070534),
        and machine-in-scope via the AD computer object.

        Phase 2 localhost validation (D-02): accepts $null, '.', $env:COMPUTERNAME,
        'localhost'; throws "Remote targets arrive in Phase 3" otherwise. Phase 3 widens
        the validation when the transport ladder lands; the verb signature is stable
        across phases.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is absent.

    .PARAMETER Name
        The local user name to remove from the group.

    .PARAMETER Group
        The local group name (for example, 'Administrators' or 'Remote Desktop Users').

    .PARAMETER ComputerName
        Optional target machine. In Phase 2 only localhost, '.', or $env:COMPUTERNAME
        are accepted.

    .PARAMETER Force
        Skip the per-verb confirmation prompt.

    .EXAMPLE
        Remove-AdmanLocalGroupMember -Name 'luser-fake' -Group 'Administrators'

    .EXAMPLE
        Remove-AdmanLocalGroupMember -Name 'luser-fake' -Group 'Remote Desktop Users' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Group,

        [string]$ComputerName,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Phase 2 localhost validation (D-02).
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        $ComputerName -ne '.' -and
        $ComputerName -ne 'localhost' -and
        $ComputerName -ne $env:COMPUTERNAME) {
        throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
    }

    $params = @{
        Group        = $Group
        ComputerName = $ComputerName
    }

    Invoke-AdmanLocalMutation -Verb 'Remove-LocalGroupMember' -Targets @($Name) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference
}
