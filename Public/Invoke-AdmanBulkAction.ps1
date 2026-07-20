#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-AdmanBulkAction - generic gated bulk engine (BULK-01..04).

.DESCRIPTION
    Normalizes search/CSV input, resolves each target once, runs the same
    deny/scope/protected filtering as single-object verbs, applies the
    configurable bulk.maxCount cap AFTER filtering, performs one typed-count
    confirmation for the filtered set, then loops calling Invoke-AdmanMutation
    per item with try/catch/continue.

    -Action is the declared job action. Pipeline input is tagged with this
    action. CSV rows must carry the same action; a mismatch causes a terminating
    error before any gate call. Move jobs require -TargetPath for the entire
    job. Group jobs require -GroupIdentity for the whole job unless every row
    supplies its own GroupIdentity.

    After the outer typed-count confirmation, each per-item gate call runs with
    -Force so the operator is not re-prompted N times. No-op cases (already
    disabled/enabled, already in place, already member/not member) are detected
    and skipped with a Success audit note.

    -Force skips the outer typed-count confirmation while preserving per-item
    policy/audit; this is an intentional senior escape hatch, not the default
    TUI path.

.EXAMPLE
    Invoke-AdmanBulkAction -Action 'Disable' -InputObject (Find-AdmanUser -Name 'jdoe*') -Force

.EXAMPLE
    Invoke-AdmanBulkAction -Action 'Move' -Path 'C:\temp\users.csv' -TargetPath 'OU=Leavers,OU=Managed,DC=contoso,DC=local' -WhatIf
#>

Set-StrictMode -Version Latest

function Invoke-AdmanBulkAction {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Disable', 'Enable', 'Move', 'AddGroup', 'RemoveGroup')]
        [string]$Action,

        [Parameter(ValueFromPipeline)]
        $InputObject,

        [string]$Path,
        [string]$TargetPath,
        [string]$GroupIdentity,
        [switch]$Force
    )

    begin {
        # WR-01: fail with a clear message when Initialize-Adman has not run.
        if (-not $script:Config -or
            -not $script:Config.PSObject.Properties['ManagedOUs'] -or
            -not $script:Config.ManagedOUs) {
            throw 'adman is not initialized. Run Initialize-Adman first.'
        }

        $actionMap = @{
            'Disable'     = 'Disable-ADAccount'
            'Enable'      = 'Enable-ADAccount'
            'Move'        = 'Move-ADObject'
            'AddGroup'    = 'Add-ADGroupMember'
            'RemoveGroup' = 'Remove-ADGroupMember'
        }
        $gateVerb = $actionMap[$Action]

        $pipelineInput = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($null -ne $InputObject) {
            # Arrays passed as a bound parameter (e.g. -InputObject @(...)) are
            # received whole; enumerate them so each element becomes a record.
            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                foreach ($item in $InputObject) {
                    if ($null -ne $item) { $pipelineInput.Add($item) }
                }
            } else {
                $pipelineInput.Add($InputObject)
            }
        }
    }

    end {
        $records = [System.Collections.Generic.List[object]]::new()

        # CSV source: rows are authoritative for their own Action.
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $csvRows = Import-AdmanBulkCsv -Path $Path
            foreach ($row in $csvRows) {
                if ($row.Action -cne $Action) {
                    throw "CSV row has Action '$($row.Action)' but the job action is '$Action'. Use a CSV whose Action column matches -Action."
                }
                $records.Add([pscustomobject]@{
                    ObjectType    = $row.ObjectType
                    Identity      = $row.Identity
                    Action        = $row.Action
                    TargetPath    = if ($row.TargetPath) { $row.TargetPath } else { $null }
                    GroupIdentity = if ($row.GroupIdentity) { $row.GroupIdentity } else { $null }
                    GateVerb      = $actionMap[$row.Action]
                })
            }
        }

        # Pipeline source: normalize with the declared -Action.
        if ($pipelineInput.Count -gt 0) {
            $pipeRecords = $pipelineInput | ConvertTo-AdmanBulkInput -Action $Action -TargetPath $TargetPath -GroupIdentity $GroupIdentity
            foreach ($pr in $pipeRecords) {
                $pr | Add-Member -MemberType NoteProperty -Name 'GateVerb' -Value $actionMap[$pr.Action] -Force
                $records.Add($pr)
            }
        }

        if ($records.Count -eq 0) {
            return [pscustomobject]@{
                Total     = 0
                Succeeded = 0
                Failed    = 0
                Denied    = 0
                WhatIf    = [bool]$WhatIfPreference
                PerItem   = @()
            }
        }

        # Move jobs require a destination for the entire job or a per-row TargetPath.
        # The outer -TargetPath acts as the default when a CSV row omits the column.
        if ($Action -eq 'Move') {
            foreach ($rec in $records) {
                $effectiveTargetPath = if ($rec.TargetPath) { $rec.TargetPath } else { $TargetPath }
                if ([string]::IsNullOrWhiteSpace($effectiveTargetPath)) {
                    throw "Move action requires -TargetPath or a TargetPath value on every CSV row."
                }
                $tp = ConvertTo-AdmanNormalizedDn -Dn $effectiveTargetPath
                $tpInScope = $false
                foreach ($root in @($script:Config.ManagedOUs)) {
                    $r = ConvertTo-AdmanNormalizedDn -Dn ([string]$root)
                    if ([string]::IsNullOrEmpty($r)) { continue }
                    if ($tp -eq $r -or $tp.EndsWith(',' + $r)) { $tpInScope = $true; break }
                }
                if (-not $tpInScope) {
                    throw "TargetPath '$effectiveTargetPath' is outside managed OU scope."
                }
            }
        }

        # Group destination policy: resolve and validate every distinct group
        # BEFORE cap/confirm so a protected destination fails the whole job.
        $distinctGroupIds = [System.Collections.Generic.List[string]]::new()
        if ($Action -in @('AddGroup', 'RemoveGroup')) {
            foreach ($rec in $records) {
                $gid = if ($rec.GroupIdentity) { $rec.GroupIdentity } else { $GroupIdentity }
                if ([string]::IsNullOrWhiteSpace($gid)) {
                    throw "Group operation requires -GroupIdentity or a GroupIdentity value on every CSV row."
                }
                if (-not ($distinctGroupIds -contains $gid)) {
                    $distinctGroupIds.Add($gid)
                }
            }
            foreach ($gid in $distinctGroupIds) {
                $groupObj = Resolve-AdmanGroup -Identity $gid
                $groupDecision = Test-AdmanGroupAllowed -Object $groupObj -Operation $gateVerb
                if (-not $groupDecision.Allowed) {
                    throw "Bulk group destination '$gid' refused: $($groupDecision.Reason)"
                }
            }
        }

        # Resolve + filter each record. Failures during resolution are recorded
        # as per-item Failed and continue.
        $allowed = [System.Collections.Generic.List[object]]::new()
        $denied = [System.Collections.Generic.List[object]]::new()
        $perItem = [System.Collections.Generic.List[object]]::new()

        foreach ($rec in $records) {
            try {
                $resolved = @(Resolve-AdmanTarget -Targets @($rec.Identity))
                $targetObj = $resolved | Select-Object -First 1
                $decision = Test-AdmanTargetAllowed -Object $targetObj -Operation $rec.GateVerb
                if (-not $decision.Allowed) {
                    if ($Action -in @('AddGroup', 'RemoveGroup')) {
                        $gid = if ($rec.GroupIdentity) { $rec.GroupIdentity } else { $GroupIdentity }
                        $groupObj = Resolve-AdmanGroup -Identity $gid
                        Write-AdmanAudit -Verb $rec.GateVerb -Target $targetObj -Result 'Refused' `
                            -Reason $decision.Reason -Group $groupObj.DistinguishedName -WhatIf:$WhatIfPreference
                    } else {
                        Write-AdmanAudit -Verb $rec.GateVerb -Target $targetObj -Result 'Refused' `
                            -Reason $decision.Reason -WhatIf:$WhatIfPreference
                    }
                    $denied.Add($rec)
                    $perItem.Add([pscustomobject]@{ Identity = $rec.Identity; Result = 'Denied'; Note = $decision.Reason })
                } else {
                    $rec | Add-Member -MemberType NoteProperty -Name 'ResolvedTarget' -Value $targetObj -Force
                    if ($Action -in @('AddGroup', 'RemoveGroup')) {
                        $gid = if ($rec.GroupIdentity) { $rec.GroupIdentity } else { $GroupIdentity }
                        $groupObj = Resolve-AdmanGroup -Identity $gid
                        $rec | Add-Member -MemberType NoteProperty -Name 'ResolvedGroup' -Value $groupObj -Force
                    }
                    $allowed.Add($rec)
                }
            } catch {
                $perItem.Add([pscustomobject]@{ Identity = $rec.Identity; Result = 'Failed'; Note = $_.Exception.Message })
                Write-Warning "Bulk resolve/filter failed for $($rec.Identity): $($_.Exception.Message)"
            }
        }

        # Cap applies ONLY to the filtered set (D-07).
        Assert-AdmanBulkPolicy -Count $allowed.Count -EnforceCap | Out-Null

        # One typed-count confirmation for the exact filtered set.
        # -Force skips this outer confirmation but preserves per-item policy/audit.
        if (-not $Force) {
            $confirmArgs = @{
                Verb              = $gateVerb
                Targets           = $allowed.ToArray()
                RequireTypedCount = $true
                Force             = $Force
            }
            if ($Action -in @('AddGroup', 'RemoveGroup') -and $allowed.Count -gt 0) {
                $confirmArgs['Group'] = $allowed[0].ResolvedGroup.DistinguishedName
            }
            $confirm = Confirm-AdmanAction @confirmArgs
            if ($confirm.Outcome -eq 'Declined') {
                throw 'Operator declined.'
            }
        } else {
            $confirm = [pscustomobject]@{ Outcome = 'Proceed'; WhatIf = [bool]$WhatIfPreference }
        }

        # Per-item execution: continue on single-item failure.
        foreach ($rec in $allowed) {
            try {
                $skipReason = $null
                switch ($Action) {
                    'Disable' {
                        if ($rec.ResolvedTarget.PSObject.Properties['Enabled'] -and -not $rec.ResolvedTarget.Enabled) {
                            $skipReason = 'already disabled'
                        }
                    }
                    'Enable' {
                        if ($rec.ResolvedTarget.PSObject.Properties['Enabled'] -and $rec.ResolvedTarget.Enabled) {
                            $skipReason = 'already enabled'
                        }
                    }
                    'Move' {
                        $itemTargetPath = if ($rec.TargetPath) { $rec.TargetPath } else { $TargetPath }
                        $currentParent = ConvertTo-AdmanParentDn -Dn $rec.ResolvedTarget.DistinguishedName
                        if ((ConvertTo-AdmanNormalizedDn -Dn $currentParent) -eq (ConvertTo-AdmanNormalizedDn -Dn $itemTargetPath)) {
                            $skipReason = 'already in place'
                        }
                    }
                    'AddGroup' {
                        $groupDn = $rec.ResolvedGroup.DistinguishedName
                        if (@($rec.ResolvedTarget.memberOf) -contains $groupDn) {
                            $skipReason = 'already member'
                        }
                    }
                    'RemoveGroup' {
                        $groupDn = $rec.ResolvedGroup.DistinguishedName
                        if (-not (@($rec.ResolvedTarget.memberOf) -contains $groupDn)) {
                            $skipReason = 'not a member'
                        }
                    }
                }

                if ($skipReason) {
                    if ($Action -in @('AddGroup', 'RemoveGroup')) {
                        Write-AdmanAudit -Verb $rec.GateVerb -Target $rec.ResolvedTarget -Result 'Success' `
                            -Reason $skipReason -Group $rec.ResolvedGroup.DistinguishedName -WhatIf:$WhatIfPreference
                    } else {
                        Write-AdmanAudit -Verb $rec.GateVerb -Target $rec.ResolvedTarget -Result 'Success' `
                            -Reason $skipReason -WhatIf:$WhatIfPreference
                    }
                    $perItem.Add([pscustomobject]@{ Identity = $rec.Identity; Result = 'Success'; Note = $skipReason })
                    continue
                }

                $params = @{}
                if ($Action -eq 'Move') { $params['TargetPath'] = if ($rec.TargetPath) { $rec.TargetPath } else { $TargetPath } }
                if ($Action -in @('AddGroup', 'RemoveGroup')) { $params['GroupIdentity'] = $rec.ResolvedGroup.DistinguishedName }

                Invoke-AdmanMutation -Verb $rec.GateVerb -Targets @($rec.Identity) -Parameters $params `
                    -Force:$true -WhatIf:$WhatIfPreference | Out-Null
                $perItem.Add([pscustomobject]@{ Identity = $rec.Identity; Result = 'Success'; Note = $null })
            } catch {
                $perItem.Add([pscustomobject]@{ Identity = $rec.Identity; Result = 'Failed'; Note = $_.Exception.Message })
                Write-Warning "Bulk item failed: $($rec.Identity) - $($_.Exception.Message)"
            }
        }

        return [pscustomobject]@{
            Total     = $records.Count
            Succeeded = @($perItem | Where-Object { $_.Result -eq 'Success' }).Count
            Failed    = @($perItem | Where-Object { $_.Result -eq 'Failed' }).Count
            Denied    = $denied.Count
            WhatIf    = [bool]$WhatIfPreference
            PerItem   = $perItem.ToArray()
        }
    }
}
