#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-AdmanCapability {
    <#
    .SYNOPSIS
        Test-AdmanCapability - cheap, read-only startup capability probe with actionable guidance (MENU-05).
    
    .DESCRIPTION
        Probes what this session can do, never hangs, and NEVER mutates the directory to discover
        rights. Returns a PSCustomObject of flags and stores it in $script:Capability. For every false
        flag it emits Write-PSFMessage -Level Warning with ACTIONABLE guidance so the menu can tell the
        operator exactly how to fix it (exact RSAT install command, VPN/ADWS 9389 check, delegated-
        admin vs. credential, WinRM -> CIM/DCOM fallback, Recycle Bin tombstone note).
    
        Probes (all read-only; all transport/domain failures are caught into flags, not thrown):
          * RsatPresent       = Get-Module -ListAvailable -Name ActiveDirectory
          * DomainReachable   = try Get-ADDomain -Server $DC (ADWS TCP 9389) with short handling
          * AuditWritable     = Test-AdmanAuditWritable (zero-byte open-append + Flush probe)
          * RecycleBinEnabled = Get-ADOptionalFeature Recycle Bin -> EnabledScopes (warning only)
          * RightsSufficient  = Test-AdmanRightsSufficient (read managed OU + whoami /groups; read-only)
          * WinRM / CimDcom   = Test-WSMan, else optional New-CimSession -Protocol Dcom (short timeout)
    
        FAIL-CLOSED (the only two terminating errors):
          * empty ManagedOUs          -> throw 'FAIL-CLOSED: managed-OU is empty.'
          * AuditWritable -eq $false  -> throw 'FAIL-CLOSED: audit path not writable.'
        Transport timeouts are kept short (<= 30s) so the menu never hangs (MENU-05).

    .EXAMPLE
        Test-AdmanCapability
        Probes RSAT, domain reachability, audit path, and transport options.
    #>

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $dc = $script:Config.DC
    $probeTimeoutSec = 15

    # Fail-closed #1: an empty scope means every mutation would be unscoped - refuse to start.
    if (-not $script:Config.ManagedOUs -or @($script:Config.ManagedOUs).Count -eq 0) {
        throw 'FAIL-CLOSED: managed-OU is empty.'
    }

    # RSAT presence (documented prerequisite; never bundled).
    $rsat = $false
    try {
        $mod = Get-Module -ListAvailable -Name 'ActiveDirectory' -ErrorAction Stop
        $rsat = ($null -ne $mod)
    } catch {
        $rsat = $false
    }

    # Domain / ADWS reachability (TCP 9389). Failure is a flag, not a terminating error.
    $domain = $false
    try {
        $null = Get-ADDomain -Server $dc -ErrorAction Stop
        $domain = $true
    } catch {
        $domain = $false
    }

    # Audit writability (zero-byte probe).
    $audit = [bool](Test-AdmanAuditWritable)

    # Fail-closed #2: an unwritable audit path means mutations could not be logged - refuse.
    if (-not $audit) {
        throw 'FAIL-CLOSED: audit path not writable.'
    }

    # Recycle Bin optional feature (warning only - never a blocker).
    $recycle = $false
    try {
        $rb = Get-ADOptionalFeature -Filter "Name -like 'Recycle Bin*'" -ErrorAction Stop |
            Select-Object -First 1
        $recycle = ($null -ne $rb -and @($rb.EnabledScopes).Count -gt 0)
    } catch {
        $recycle = $false
    }

    # Rights hint (READ-ONLY): read the managed OU + whoami /groups for delegatedAdminGroup.
    $rights = [bool](Test-AdmanRightsSufficient)

    # Transport: WinRM first (hard-timeout wrapper); optional CIM/DCOM fallback only when WinRM is unavailable.
    $winrm = [bool](Test-AdmanWsmanTimeout -ComputerName $dc -TimeoutSeconds $probeTimeoutSec)

    $cimDcom = $false
    if (-not $winrm) {
        $cimDcom = Test-AdmanCimSessionTimeout -ComputerName $dc -Protocol Dcom -TimeoutSeconds $probeTimeoutSec
    }

    $flags = [pscustomobject]@{
        RsatPresent       = [bool]$rsat
        DomainReachable   = [bool]$domain
        AuditWritable     = [bool]$audit
        RecycleBinEnabled = [bool]$recycle
        RightsSufficient  = [bool]$rights
        WinRM             = [bool]$winrm
        CimDcom           = [bool]$cimDcom
    }
    $script:Capability = $flags

    if (-not $flags.RsatPresent) {
        Write-PSFMessage -Level Warning -Message 'RSAT ActiveDirectory module not found. Install: client -> Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0; server -> Install-WindowsFeature RSAT-AD-PowerShell.'
    }
    if (-not $flags.DomainReachable) {
        Write-PSFMessage -Level Warning -Message 'Domain not reachable. Check VPN/network and that ADWS (TCP 9389) answers on the pinned DC.'
    }
    if (-not $flags.RightsSufficient) {
        Write-PSFMessage -Level Warning -Message 'Pass-through rights look insufficient. Re-run as the delegated-admin group or provide domain credentials (CONF-06).'
    }
    if (-not $flags.WinRM) {
        Write-PSFMessage -Level Warning -Message 'WinRM unavailable on the DC; falling back to CIM/DCOM. Remote computer ops may degrade to Skipped per host (Phase 3).'
    }
    if (-not $flags.RecycleBinEnabled) {
        Write-PSFMessage -Level Warning -Message 'AD Recycle Bin is not enabled; out-of-tool hard deletes are tombstone-only and not recoverable through adman.'
    }

    $flags
}
