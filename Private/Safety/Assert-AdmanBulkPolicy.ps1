#Requires -Version 5.1
<#
.SYNOPSIS
    Assert-AdmanBulkPolicy - bulk cap/threshold reader (SAFE-02; cap enforcement is Phase 4).

.DESCRIPTION
    Reads bulk.maxCount and safety.bulkConfirmThreshold from $script:Config and returns them.
    In Phase 0 the cap is a PLACEHOLDER: it is NOT enforced (enforcement is Phase 4 / BULK-02).
    A switch -EnforceCap exists for forward-compatibility: only when -EnforceCap is passed AND
    Count exceeds the cap does this throw. Phase 0 / Phase 2 single-object flows never pass
    -EnforceCap, so the cap never blocks here.
#>

Set-StrictMode -Version Latest

function Assert-AdmanBulkPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Count,
        [switch]$EnforceCap
    )

    $cap = [int]$script:Config.bulk.maxCount
    $threshold = [int]$script:Config.safety.bulkConfirmThreshold

    Write-PSFMessage -Level Debug -Message "Assert-AdmanBulkPolicy: count=$Count cap=$cap threshold=$threshold"

    # Phase 0 placeholder: do NOT enforce the cap unless explicitly asked (Phase 4 / BULK-02).
    if ($EnforceCap -and $Count -gt $cap) {
        throw "Bulk count $Count exceeds cap $cap."
    }

    return @{ Cap = $cap; Threshold = $threshold }
}
