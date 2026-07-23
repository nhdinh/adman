#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanLocalTarget - materialize local account targets for the local gate (D-02).

.DESCRIPTION
    Phase 2 scope: localhost ONLY. -ComputerName accepts $null, '.', $env:COMPUTERNAME, or
    'localhost'; any other value throws "Remote targets arrive in Phase 3." Materializes one
    PSCustomObject per local username via Get-LocalUser carrying Machine, Name, SID, Enabled,
    FullName, LocalRid (SID split on '-' last segment).

    CREATE-BRANCH (D-02 BLOCKER fix): when -Verb is 'New-LocalUser' (or -Create is set), DO
    NOT call Get-LocalUser; fabricate a synthetic local target PSCustomObject carrying
    Machine=<validated localhost>, Name=<proposed name>, SID=$null, LocalRid=$null,
    Enabled=$null, IsSynthetic=$true. The synthetic object flows through the local gate's
    fixed order unchanged. SAFE-10 preserved: preview and audit Target name the
    to-be-created MACHINE\username.

    D-03 pre-delete state capture: when -Verb is 'Remove-LocalUser', ALSO captures (a)
    group memberships via Get-LocalGroupMember per local group (orphaned-SID-tolerant:
    try/catch around each call, skip groups that throw 0x80070534) and (b) the profile path
    via Get-CimInstance Win32_UserProfile filtered by SID (tolerate $null when no profile
    exists); the captured state is attached to the returned PSCustomObject as a
    PreDeleteState property carrying @{ GroupMemberships=@(...); ProfilePath='...' }.
#>

Set-StrictMode -Version Latest

function Resolve-AdmanLocalTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [string]$ComputerName,
        [string]$Verb,
        [switch]$Create
    )

    # Phase 2 scope: localhost only. Validate -ComputerName.
    $machine = $env:COMPUTERNAME
    if (-not [string]::IsNullOrEmpty($ComputerName)) {
        if ($ComputerName -in @('.', 'localhost') -or $ComputerName -eq $env:COMPUTERNAME) {
            $machine = $env:COMPUTERNAME
        } else {
            throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
        }
    }

    # CREATE-BRANCH: fabricate a synthetic local target without calling Get-LocalUser.
    if ($Create -or $Verb -eq 'New-LocalUser') {
        foreach ($name in $Targets) {
            [pscustomobject]@{
                Machine     = $machine
                Name        = $name
                SID         = $null
                LocalRid    = $null
                Enabled     = $null
                FullName    = $null
                IsSynthetic = $true
            }
        }
        return
    }

    foreach ($name in $Targets) {
        $u = Get-LocalUser -Name $name -ErrorAction Stop
        $sidValue = if ($null -ne $u.SID) { ([System.Security.Principal.SecurityIdentifier]$u.SID).Value } else { $null }
        $localRid = if ($sidValue) { $sidValue.Split('-')[-1] } else { $null }

        $obj = [pscustomobject]@{
            Machine  = $machine
            Name     = $u.Name
            SID      = $u.SID
            LocalRid = $localRid
            Enabled  = $u.Enabled
            FullName = $u.FullName
        }

        # D-03 pre-delete state capture for Remove-LocalUser.
        if ($Verb -eq 'Remove-LocalUser') {
            $memberships = @()
            foreach ($g in @(Get-LocalGroup -ErrorAction SilentlyContinue)) {
                try {
                    $m = Get-LocalGroupMember -Name $g.Name -ErrorAction Stop |
                        Where-Object { $_.SID -and ([System.Security.Principal.SecurityIdentifier]$_.SID).Value -eq $sidValue }
                    if ($m) { $memberships += $g.Name }
                } catch {
                    # Orphaned-SID-tolerant: skip groups that throw ERROR_NONE_MAPPED
                    # (0x80070534 = 2147943732; Win32 error 1332 = "no mapping between
                    # account names and security IDs"). CR-02 fix: match on the structured
                    # HResult / NativeErrorCode, NOT a substring of the message — the
                    # previous regex '0x80070534|0x534' would also swallow unrelated
                    # errors whose message happened to contain '0x534' (e.g. 0x5340).
                    $hr = $null
                    $native = $null
                    if ($null -ne $_.Exception) {
                        if ($_.Exception.PSObject.Properties['HResult']) { $hr = $_.Exception.HResult }
                        if ($_.Exception.PSObject.Properties['NativeErrorCode']) { $native = $_.Exception.NativeErrorCode }
                    }
                    $isOrphanedSid = ($hr -eq -2147023564) -or ($hr -eq 2147943732) -or ($native -eq 1332)
                    if (-not $isOrphanedSid) { throw }
                }
            }
            $profilePath = $null
            try {
                $profile = Get-CimInstance -ClassName Win32_UserProfile `
                    -Filter "SID='$sidValue'" -ErrorAction SilentlyContinue
                if ($profile) { $profilePath = $profile.LocalPath }
            } catch {
                Write-Warning "Could not capture Win32_UserProfile for '$sidValue': $($_.Exception.Message)"
            }
            $obj | Add-Member -NotePropertyName PreDeleteState -NotePropertyValue @{
                GroupMemberships = $memberships
                ProfilePath      = $profilePath
            }
        }

        $obj
    }
}
