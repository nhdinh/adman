#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanLocalTargetAllowed - policy for a single local target (D-02).

.DESCRIPTION
    Returns @{ Allowed = [bool]; Reason = [string] }. Reasons are ACCUMULATED.

    Non-synthetic targets run three checks:
      (a) LocalRid -eq '500' -> reason 'built-in local Administrator (RID-500)' (matched by
          RID, never by account name).
      (b) local Administrators membership via Get-LocalGroupMember -Name 'Administrators'
          with try/catch - on 0x80070534 / 0x534 fall back to Get-CimInstance
          Win32_GroupUser filtered by GroupComponent.Name='Administrators'; on total
          enumeration failure ADD a refusal reason (fail-closed). Refuse when the target
          SID is in the admin set AND Verb is in @('Disable-LocalUser','Remove-LocalUser',
          'Set-LocalUser').
      (c) machine-in-scope - resolve the target machine's AD computer object via
          Resolve-AdmanTarget -Targets @("$($Object.Machine)`$") (the trailing `$` is
          REQUIRED: Get-ADObject -Identity needs the sAMAccountName form of a computer,
          which is the machine name with a trailing dollar sign) then
          Test-AdmanTargetAllowed; refuse when not Allowed.

    CREATE-BRANCH (D-02 BLOCKER fix): when $Object.PSObject.Properties['IsSynthetic'] -and
    $Object.IsSynthetic, SKIP checks (a) and (b) entirely (no SID exists yet, no group
    memberships exist yet) and run ONLY (i) the machine-in-scope check (c) AND (ii)
    name-shape validation: Name is not null/empty/whitespace, contains no path separators
    ('\','/'), no control characters, and length <= 20 (matching New-LocalUser's own Name
    constraint); refuse closed when the machine is out of scope or the name is malformed.
#>

Set-StrictMode -Version Latest

function Test-AdmanLocalTargetAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object,
        [Parameter(Mandatory)]
        [string]$Verb
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # CREATE-BRANCH: synthetic pre-create local targets skip SID-dependent checks.
    if ($Object.PSObject.Properties['IsSynthetic'] -and $Object.IsSynthetic) {
        # (ii) name-shape validation.
        $name = [string]$Object.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $reasons.Add('local account name is null/empty/whitespace')
        } else {
            if ($name -match '[\\/]') { $reasons.Add("local account name '$name' contains a path separator") }
            if ($name -match '[\x00-\x1f]') { $reasons.Add("local account name '$name' contains a control character") }
            if ($name.Length -gt 20) { $reasons.Add("local account name '$name' exceeds 20 characters") }
        }
        # (i) machine-in-scope (same as (c) below).
        $machineScope = Get-AdmanLocalMachineScope -Machine $Object.Machine
        if (-not $machineScope.Allowed) { $reasons.Add($machineScope.Reason) }
        return @{
            Allowed = ($reasons.Count -eq 0)
            Reason  = ($reasons -join '; ')
        }
    }

    # (a) built-in local Administrator by RID (never by name).
    if ($Object.PSObject.Properties['LocalRid'] -and $Object.LocalRid -eq '500') {
        $reasons.Add('built-in local Administrator (RID-500)')
    }

    # (b) local Administrators membership - refuse when target is an admin AND Verb is in
    #     the destructive set. Get-LocalGroupMember with try/catch + WMI Win32_GroupUser
    #     fallback on orphaned-SID (0x80070534 / 0x534); fail-closed on total failure.
    $targetSidValue = $null
    if ($Object.PSObject.Properties['SID'] -and $null -ne $Object.SID) {
        $targetSidValue = ([System.Security.Principal.SecurityIdentifier]$Object.SID).Value
    }
    $adminSids = @()
    $enumFailed = $false
    # WR-05: resolve the well-known Administrators SID to the localized group name so the
    # check works on non-English Windows installations.
    $adminGroupName = 'Administrators'
    try {
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $adminNtAccount = $adminSid.Translate([System.Security.Principal.NTAccount])
        if ($adminNtAccount -and $adminNtAccount.Value) {
            $adminGroupName = ($adminNtAccount.Value -replace '^.*\\', '')
        }
    } catch {
        # SID-to-name translation can fail in constrained language mode; fall back to the
        # English default. The catch below will record an enumeration failure if needed.
    }
    try {
        $members = @(Get-LocalGroupMember -Name $adminGroupName -ErrorAction Stop)
        foreach ($m in $members) {
            if ($m.SID) { $adminSids += ([System.Security.Principal.SecurityIdentifier]$m.SID).Value }
        }
    } catch {
        # CR-02 fix: match structured HResult/NativeErrorCode, not message substring.
        # The previous regex '0x80070534|0x534' was a substring match that false-positived
        # on unrelated hex codes (e.g. 0x5340, 0x15340). Orphaned-SID is HRESULT
        # 0x80070534 (== -2147023564 signed, == 2147943732 unsigned) / Win32 error 1332
        # (ERROR_NONE_MAPPED: "No mapping between account names and security IDs was done").
        $hr = $null
        $native = $null
        if ($null -ne $_.Exception) {
            if ($_.Exception.PSObject.Properties['HResult']) { $hr = $_.Exception.HResult }
            if ($_.Exception.PSObject.Properties['NativeErrorCode']) { $native = $_.Exception.NativeErrorCode }
        }
        $isOrphanedSid = ($hr -eq -2147023564) -or ($hr -eq 2147943732) -or ($native -eq 1332)
        if ($isOrphanedSid) {
            # Orphaned-SID fallback: WMI Win32_GroupUser using the localized group name.
            try {
                $wmiMembers = @(Get-CimInstance -ClassName Win32_GroupUser -ErrorAction Stop |
                    Where-Object { $_.GroupComponent.Name -eq $adminGroupName })
                foreach ($wm in $wmiMembers) {
                    # Win32_GroupUser PartComponent is a Win32_UserAccount/Win32_SystemAccount
                    # reference; extract the SID via the associated CIM instance when present.
                    $part = $wm.PartComponent
                    if ($part -and $part.PSObject.Properties['SID'] -and $part.SID) {
                        $adminSids += ([System.Security.Principal.SecurityIdentifier]$part.SID).Value
                    }
                }
            } catch {
                $enumFailed = $true
            }
        } else {
            $enumFailed = $true
        }
    }
    if ($enumFailed) {
        $reasons.Add('local Administrators enumeration failed (fail-closed)')
    } elseif ($targetSidValue -and ($targetSidValue -in $adminSids) -and
        ($Verb -in @('Disable-LocalUser', 'Remove-LocalUser', 'Set-LocalUser'))) {
        $reasons.Add('member of local Administrators')
    }

    # (c) machine-in-scope - resolve the target machine's AD computer object (trailing `$`
    #     REQUIRED for the sAMAccountName form) and run Test-AdmanTargetAllowed.
    #     CR-03 fix: cached per machine per session via Get-AdmanLocalMachineScope; degrades
    #     to 'warn but allow' when AD is unreachable and the target is localhost (the
    #     operator's own workstation is trivially in scope for local operations on it).
    $machineScope = Get-AdmanLocalMachineScope -Machine $Object.Machine
    if (-not $machineScope.Allowed) { $reasons.Add($machineScope.Reason) }

    return @{
        Allowed = ($reasons.Count -eq 0)
        Reason  = ($reasons -join '; ')
    }
}

# CR-03 helper: per-session cached machine-in-scope check. The machine$ computer object
# does not move between OUs mid-session, so the AD lookup is cached after the first call.
# When the AD lookup throws (DC unreachable, machine has no computer object, etc.) AND
# the target is the local machine, degrade to 'Allowed with warning' rather than
# fail-closed — the project constraint is that local verbs must work even when AD is
# degraded (the same degradation logic as WinRM -> CIM -> skip per host).
function Get-AdmanLocalMachineScope {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Machine)

    if (-not $script:LocalMachineScopeCache) {
        $script:LocalMachineScopeCache = @{}
    }
    if ($script:LocalMachineScopeCache.ContainsKey($Machine)) {
        return $script:LocalMachineScopeCache[$Machine]
    }

    $machineSam = "$Machine`$"
    $result = $null
    try {
        $machineObj = @(Resolve-AdmanTarget -Targets @($machineSam)) | Select-Object -First 1
        if ($null -eq $machineObj) {
            $result = @{ Allowed = $false; Reason = "machine '$Machine' has no AD computer object" }
        } else {
            $md = Test-AdmanTargetAllowed -Object $machineObj
            if ($md.Allowed) {
                $result = @{ Allowed = $true; Reason = '' }
            } else {
                $result = @{ Allowed = $false; Reason = "machine out of scope: $($md.Reason)" }
            }
        }
    } catch {
        # Distinguish 'localhost' (the operator's own workstation) from a remote target.
        # Local operations on the local machine are trivially in scope when AD is
        # unreachable; remote targets remain fail-closed (cannot verify scope).
        $isLocal = ($Machine -eq $env:COMPUTERNAME) -or ($Machine -eq 'localhost') -or ($Machine -eq '.')
        if ($isLocal) {
            Write-Warning "machine-in-scope AD lookup failed for localhost ($($_.Exception.Message)); proceeding because the target is the local machine."
            $result = @{ Allowed = $true; Reason = '' }
        } else {
            $result = @{ Allowed = $false; Reason = "machine-in-scope check failed: $($_.Exception.Message)" }
        }
    }

    $script:LocalMachineScopeCache[$Machine] = $result
    return $result
}
