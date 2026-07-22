#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-AdmanTranscriptCount {
    <#
    .SYNOPSIS
        Get-AdmanTranscriptCount - guarded probe for active PowerShell transcripts.

    .DESCRIPTION
        Returns the number of active transcripts in the current runspace, or 0 when the
        host/runspace does not expose the InitialSessionState.Transcripts property
        (Windows PowerShell 5.1 under some hosts, constrained runspaces, test harnesses).

        Used by password-generating verbs to refuse displaying generated plaintext while
        a transcript is recording.
    #>
    [CmdletBinding()]
    param()

    try {
        $iss = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState
        if ($null -eq $iss) { return 0 }
        $prop = $iss.PSObject.Properties['Transcripts']
        if ($null -eq $prop) { return 0 }
        return @($prop.Value).Count
    } catch {
        return 0
    }
}
