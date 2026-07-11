#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanDomainSid - resolve and cache the domain + forest-root SIDs (D-02/D-05, A3).

.DESCRIPTION
    Resolves the live domain SID from (Get-ADDomain).DomainSID and the FOREST-ROOT SID from
    (Get-ADDomain -Identity (Get-ADForest).RootDomain).DomainSID, pinning -Server to
    $script:Config.DC. Caches both into $script:DomainSid and $script:ForestRootSid (string form)
    for Get-AdmanProtectedIdentity and the 00-04 gate. FAIL-CLOSED: if either SID cannot be
    resolved it THROWS - SAFE-05/06 enforcement is impossible without the real SIDs (names lie,
    SIDs do not). No domain SID is ever hard-coded (D-05).
#>

Set-StrictMode -Version Latest

function Resolve-AdmanDomainSid {
    [CmdletBinding()]
    param()

    $dc = $script:Config.DC

    try {
        $domain = Get-ADDomain -Server $dc -ErrorAction Stop
        $script:DomainSid = [string]$domain.DomainSID.Value
    } catch {
        throw 'FAIL-CLOSED: cannot resolve domain SID; SAFE-05/06 enforcement impossible.'
    }

    try {
        $forest = Get-ADForest -Server $dc -ErrorAction Stop
        $rootDomain = $forest.RootDomain
        $root = Get-ADDomain -Identity $rootDomain -Server $dc -ErrorAction Stop
        $script:ForestRootSid = [string]$root.DomainSID.Value
    } catch {
        throw 'FAIL-CLOSED: cannot resolve forest-root SID; SAFE-05/06 enforcement impossible.'
    }

    [pscustomobject]@{
        DomainSid     = $script:DomainSid
        ForestRootSid = $script:ForestRootSid
    }
}
