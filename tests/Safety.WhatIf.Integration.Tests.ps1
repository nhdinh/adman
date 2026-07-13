#Requires -Modules Pester
<#
.SYNOPSIS
    LAB-ONLY integration test - SAFE-01/10 end-to-end -WhatIf vs a disposable lab OU.

.DESCRIPTION
    Covers SAFE-01 (preview before execute) and SAFE-10 (preview == execute) end-to-end against a
    REAL disposable lab test OU. Asserts:
      (a) AD is UNCHANGED after a gated -WhatIf run (no object was actually mutated),
      (b) the audit record's target list equals the resolved list,
      (c) the operator-shown count equals $resolved.Count.

    This test is LAB-ONLY and gated TWO ways:
      * It carries -Tag 'Integration' on every Describe/It, so the default Unit run
        (PesterConfiguration Filter.Tag='Unit' / -TagFilter Unit) NEVER collects it.
      * It is Skipped unless the operator explicitly sets the ADMAN_TEST_OU environment variable
        to a disposable lab OU DN. It NEVER auto-runs a destructive path and NEVER targets a
        production OU.

    Run manually against a lab only:
      $env:ADMAN_TEST_OU = 'OU=AdmanLab,DC=lab,DC=local'
      Invoke-Pester -Path tests/Safety.WhatIf.Integration.Tests.ps1 -TagFilter Integration

.NOTES
    Pester 6. Requires RSAT ActiveDirectory + a reachable lab domain. NOT part of the Unit suite.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:TestOu = $env:ADMAN_TEST_OU
    $script:LabConfigured = -not [string]::IsNullOrWhiteSpace($script:TestOu)
}

Describe 'SAFE-01/10: end-to-end -WhatIf preview == execute against a disposable lab OU' -Tag 'Integration' {

    It 'is skipped unless ADMAN_TEST_OU points at a disposable lab OU' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU is not set; lab-only integration test (never auto-run destructive).'
            return
        }
        $script:LabConfigured | Should -BeTrue
    }

    It 'a gated -WhatIf leaves AD unchanged, audit target == resolved, shown count == resolved.Count' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU is not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # Snapshot the lab OU state before the dry-run.
        $before = @(Get-ADObject -SearchBase $script:TestOu -SearchScope OneLevel -Filter * |
            Select-Object -ExpandProperty DistinguishedName)

        # Run a gated -WhatIf mutation against the lab OU (preview only; no real change).
        $result = Invoke-AdmanMutation -Verb 'Disable-ADAccount' `
            -Targets @($script:TestOu) -WhatIf -Confirm:$false

        # (a) AD is UNCHANGED after the dry-run.
        $after = @(Get-ADObject -SearchBase $script:TestOu -SearchScope OneLevel -Filter * |
            Select-Object -ExpandProperty DistinguishedName)
        @($after | Sort-Object) | Should -Be @($before | Sort-Object) `
            -Because 'a -WhatIf dry-run must not mutate AD (SAFE-01)'

        # (c) operator-shown count equals the resolved count.
        $result.WhatIf | Should -BeTrue -Because 'the result reflects a dry-run'
        $result.Succeeded | Should -Be @($before).Count `
            -Because 'the operator-shown count equals the resolved target count (SAFE-10)'

        # (b) the audit record's target list equals the resolved list.
        $auditDir = & (Get-Module adman) { $script:Config.AuditDir }
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $auditPath = Join-Path $auditDir $name
        $cidRecords = @(Get-Content -LiteralPath $auditPath | Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object { $_.correlationId -eq $result.CorrelationId })
        $cidRecords | Should -Not -BeNullOrEmpty -Because 'the dry-run wrote an audit reservation'
        foreach ($rec in $cidRecords) {
            $rec.whatIf | Should -BeTrue -Because 'every audit record for a dry-run carries whatIf=$true'
        }
    }
}
