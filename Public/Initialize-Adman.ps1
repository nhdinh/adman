#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize-Adman - full startup orchestration (D-04).

.DESCRIPTION
    Runs the fixed startup sequence that turns a loaded config (00-02) into a fail-closed session
    the 00-04 gate can read. Order is fixed and asserted by tests:
      1. Initialize-AdmanConfig      (load/validate config + deny-list seed; pass -SetupMode through)
      2. Test-AdmanAuditWritable     (zero-byte probe; fail-closed if false)
      3. Get-AdmanCredential         (rights-first pass-through / DPAPI / prompt -> $script:Credential)
      4. Test-AdmanCapability        (probe flags + guidance -> $script:Capability)
      5. Get-AdmanLogonSyncInterval  (D-07 sync interval -> LogonSyncIntervalDays/LogonSyncGraceDays)
      6. Get-AdmanRecoveryPosture    (D-08 posture -> $script:Config.RecoveryPosture; never fatal)
      7. Resolve-AdmanDomainSid      (DomainSID + forest-root SID -> $script:DomainSid/ForestRootSid)
      8. Get-AdmanProtectedIdentity  (ProtectedGroupDns / ProtectedSIDs / DenyRids)
      9. Best-effort event-log source registration (never fatal).
    Sets $script:Initialized = $true on success.

    -SetupMode (init wizard): runs the config load + seed ONLY and returns - the wizard creates the
    config with NO AD mutation, so the fail-closed scope/audit throws and the AD-touching
    resolution are skipped.
#>

Set-StrictMode -Version Latest

function Initialize-Adman {
    [CmdletBinding()]
    param(
        [switch]$SetupMode
    )

    Initialize-AdmanConfig -SetupMode:$SetupMode | Out-Null

    if ($SetupMode) {
        $script:Initialized = $true
        return
    }

    if (-not (Test-AdmanAuditWritable)) {
        throw 'FAIL-CLOSED: audit path not writable.'
    }

    $script:Credential = Get-AdmanCredential
    $script:Capability = Test-AdmanCapability

    # D-07: cache the domain lastLogonTimestamp replication interval and derive the grace buffer.
    # Get-AdmanLogonSyncInterval never throws (falls back to 14 on any failure).
    $interval = Get-AdmanLogonSyncInterval
    $script:Config | Add-Member -MemberType NoteProperty -Name 'LogonSyncIntervalDays' -Value $interval -Force
    $script:Config | Add-Member -MemberType NoteProperty -Name 'LogonSyncGraceDays' -Value ([math]::Max(14, $interval) + 1) -Force

    # D-08: cache the recovery posture so the banner and reports do not re-query AD.
    # Wrapped in try/catch so a posture read failure NEVER blocks startup.
    try {
        $script:Config | Add-Member -MemberType NoteProperty -Name 'RecoveryPosture' -Value (Get-AdmanRecoveryPosture) -Force
    } catch {
        $script:Config | Add-Member -MemberType NoteProperty -Name 'RecoveryPosture' -Value $null -Force
    }

    Resolve-AdmanDomainSid | Out-Null
    $null = Get-AdmanProtectedIdentity

    try {
        New-EventLog -LogName Application -Source 'adman' -ErrorAction Stop
    } catch {
        Write-PSFMessage -Level Verbose -Message 'Event-log source registration skipped (non-fatal).'
    }

    $script:Initialized = $true
}
