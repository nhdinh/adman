#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanProtectedIdentity - startup protected-SID + deny-RID resolver (D-02/D-05, A3).

.DESCRIPTION
    Builds the session's protected-group DN set and deny-RID set from the LIVE domain SID - never
    a hard-coded SID. Consumed by the 00-04 mutation gate (Test-AdmanTargetAllowed). Names lie;
    SIDs do not. The 518/519 entries deliberately use the FOREST-ROOT SID (Assumption A3): Schema
    Admins and Enterprise Admins exist only in the forest-root domain.

    Protected set (resolved to DNs where possible, kept as SIDs otherwise):
      * Domain Admins        = DomainSID-512
      * Schema Admins        = ForestRootSID-518  (forest root - A3)
      * Enterprise Admins    = ForestRootSID-519  (forest root - A3)
      * Administrators       = S-1-5-32-544
      * Account Operators    = S-1-5-32-548
      * Backup Operators     = S-1-5-32-551
      * Server Operators     = S-1-5-32-549
      * Protected Users      = DomainSID-525      (defense-in-depth; absent pre-2012R2 -> kept as SID)
      * + $script:Config.AdmanProtectedGroup when configured.

    Deny RIDs (D-05): each DenyList token - a numeric RID (500/501/502) is kept as a bare RID for
    fast RID checks at the gate (the gate combines DomainSid + RID); a full SID token (S-1-...) is
    kept as-is. Produces $script:ProtectedGroupDns, $script:ProtectedSIDs, $script:DenyRids.
#>

Set-StrictMode -Version Latest

function Get-AdmanProtectedIdentity {
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Name DomainSid -Scope Script -ErrorAction SilentlyContinue)) {
        Resolve-AdmanDomainSid | Out-Null
    }

    $dc = $script:Config.DC

    # SID map. 518/519 use the FOREST-ROOT SID (A3) - they only exist in the root domain.
    $sidMap = @(
        "$script:DomainSid-512"        # Domain Admins
        "$script:ForestRootSid-518"    # Schema Admins (forest root)
        "$script:ForestRootSid-519"    # Enterprise Admins (forest root)
        'S-1-5-32-544'                 # Administrators
        'S-1-5-32-548'                 # Account Operators
        'S-1-5-32-551'                 # Backup Operators
        'S-1-5-32-549'                 # Server Operators
        "$script:DomainSid-525"        # Protected Users (defense-in-depth)
    )

    $dns = [System.Collections.Generic.List[string]]::new()
    foreach ($sid in $sidMap) {
        try {
            $group = Get-ADGroup -Identity $sid -Server $dc -ErrorAction Stop
            if ($null -ne $group -and -not [string]::IsNullOrWhiteSpace([string]$group.DistinguishedName)) {
                $dns.Add([string]$group.DistinguishedName)
            }
        } catch {
            $dns.Add([string]$sid)
        }
    }

    $admanGroup = $script:Config.AdmanProtectedGroup
    if (-not [string]::IsNullOrWhiteSpace([string]$admanGroup)) {
        $dns.Add([string]$admanGroup)
    }

    $script:ProtectedGroupDns = @($dns | Sort-Object -Unique)
    $script:ProtectedSIDs = @($sidMap | Sort-Object -Unique)

    $rids = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($script:Config.DenyList)) {
        $token = [string]$entry.token
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($token -match '^[0-9]+$') {
            $rids.Add($token)
        } elseif ($token -like 'S-1-*') {
            $rids.Add($token)
        }
    }
    $script:DenyRids = @($rids | Sort-Object -Unique)

    [pscustomobject]@{
        ProtectedGroupDns = $script:ProtectedGroupDns
        ProtectedSIDs     = $script:ProtectedSIDs
        DenyRids          = $script:DenyRids
    }
}
