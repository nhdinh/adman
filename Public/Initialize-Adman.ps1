#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize-Adman - full startup orchestration (D-04).

.DESCRIPTION
    Runs the fixed startup sequence that turns a loaded config (00-02) into a fail-closed session
    the 00-04 gate can read. Order is fixed and asserted by tests:
      1. Initialize-AdmanConfig    (load/validate config + deny-list seed; pass -SetupMode through)
      2. Test-AdmanAuditWritable   (zero-byte probe; fail-closed if false)
      3. Get-AdmanCredential       (rights-first pass-through / DPAPI / prompt -> $script:Credential)
      4. Test-AdmanCapability      (probe flags + guidance -> $script:Capability)
      5. Resolve-AdmanDomainSid    (DomainSID + forest-root SID -> $script:DomainSid/ForestRootSid)
      6. Get-AdmanProtectedIdentity(ProtectedGroupDns / ProtectedSIDs / DenyRids)
      7. Best-effort event-log source registration (never fatal).
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

    Initialize-AdmanConfig -SetupMode:$SetupMode

    if ($SetupMode) {
        $script:Initialized = $true
        return
    }

    if (-not (Test-AdmanAuditWritable)) {
        throw 'FAIL-CLOSED: audit path not writable.'
    }

    $script:Credential = Get-AdmanCredential
    $script:Capability = Test-AdmanCapability
    Resolve-AdmanDomainSid | Out-Null
    $null = Get-AdmanProtectedIdentity

    try {
        New-EventLog -LogName Application -Source 'adman' -ErrorAction Stop
    } catch {
        Write-PSFMessage -Level Verbose -Message 'Event-log source registration skipped (non-fatal).'
    }

    $script:Initialized = $true
}
