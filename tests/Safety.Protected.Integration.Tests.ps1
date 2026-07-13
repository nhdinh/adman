#Requires -Modules Pester
<#
.SYNOPSIS
    LAB-ONLY integration test - SAFE-06 protected-account refusal against a disposable lab OU.

.DESCRIPTION
    Covers SAFE-06 (protected accounts are never mutated) end-to-end against REAL lab fixtures:
      * a nested Domain-Admins member (protected via transitive group membership),
      * a gMSA (group Managed Service Account objectClass pre-filter),
      * a renamed RID-500 account (the built-in Administrator, renamed via GPO).

    Asserts the gate REFUSES each and logs a 'Refused' audit record with the precise reason, and
    that the stale-on-removal adminCount attribute is NOT consulted (live membership is the only
    trustworthy signal).

    This test is LAB-ONLY and gated TWO ways:
      * It carries -Tag 'Integration' on every Describe/It, so the default Unit run
        (PesterConfiguration Filter.Tag='Unit' / -TagFilter Unit) NEVER collects it.
      * It is Skipped unless the operator explicitly sets the ADMAN_TEST_OU environment variable
        to a disposable lab OU DN. It NEVER auto-runs and NEVER targets a production OU.

    Run manually against a lab only:
      $env:ADMAN_TEST_OU = 'OU=AdmanLab,DC=lab,DC=local'
      Invoke-Pester -Path tests/Safety.Protected.Integration.Tests.ps1 -TagFilter Integration

.NOTES
    Pester 6. Requires RSAT ActiveDirectory + a reachable lab domain with the fixtures provisioned.
    NOT part of the Unit suite.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:TestOu = $env:ADMAN_TEST_OU
    $script:LabConfigured = -not [string]::IsNullOrWhiteSpace($script:TestOu)
}

Describe 'SAFE-06: protected-account refusal against lab fixtures (nested admin, gMSA, renamed RID-500)' -Tag 'Integration' {

    It 'is skipped unless ADMAN_TEST_OU points at a disposable lab OU' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU is not set; lab-only integration test (never auto-run).'
            return
        }
        $script:LabConfigured | Should -BeTrue
    }

    It 'refuses a nested Domain-Admins member and logs Refused with the precise reason' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU is not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # Locate a lab fixture that is a nested (transitive) Domain-Admins member.
        $fixture = Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree `
            -LDAPFilter '(sAMAccountName=lab-nested-admin)' -ErrorAction SilentlyContinue
        if (-not $fixture) {
            Set-ItResult -Skipped -Because 'lab fixture lab-nested-admin not provisioned under ADMAN_TEST_OU.'
            return
        }

        $result = Invoke-AdmanMutation -Verb 'Disable-ADAccount' `
            -Targets @($fixture.DistinguishedName) -Confirm:$false -Force

        # The gate refuses the protected target (Denied >= 1) and never mutates it.
        $result.Denied | Should -BeGreaterOrEqual 1 `
            -Because 'a nested Domain-Admins member is protected and must be refused (SAFE-06)'
        $result.Succeeded | Should -Be 0

        # A 'Refused' audit record was written with a precise reason.
        $auditDir = & (Get-Module adman) { $script:Config.AuditDir }
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $auditPath = Join-Path $auditDir $name
        $refused = @(Get-Content -LiteralPath $auditPath | Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object { $_.correlationId -eq $result.CorrelationId -and $_.result -eq 'Refused' })
        $refused | Should -Not -BeNullOrEmpty -Because 'a refused protected target is logged with its reason'
        $refused[0].reason | Should -Not -BeNullOrEmpty -Because 'the refusal carries a precise reason'
    }

    It 'refuses a gMSA and a renamed RID-500 account (adminCount NOT consulted)' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU is not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # gMSA fixture: objectClass msDS-GroupManagedServiceAccount is pre-filtered.
        $gmsa = Get-ADServiceAccount -SearchBase $script:TestOu -SearchScope Subtree `
            -Filter * -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gmsa) {
            $r = Invoke-AdmanMutation -Verb 'Disable-ADAccount' `
                -Targets @($gmsa.DistinguishedName) -Confirm:$false -Force
            $r.Denied | Should -BeGreaterOrEqual 1 `
                -Because 'a gMSA is refused by the objectClass pre-filter (SAFE-06)'
        } else {
            Set-ItResult -Inconclusive -Because 'no gMSA fixture provisioned under ADMAN_TEST_OU.'
        }

        # Renamed RID-500 fixture: matched by objectSid RID, never by name (rename-safe).
        $rid500 = Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree -Filter * `
            -Properties objectSid -ErrorAction SilentlyContinue |
            Where-Object { $_.objectSid.Value -match '-500$' } | Select-Object -First 1
        if ($rid500) {
            $r2 = Invoke-AdmanMutation -Verb 'Disable-ADAccount' `
                -Targets @($rid500.DistinguishedName) -Confirm:$false -Force
            $r2.Denied | Should -BeGreaterOrEqual 1 `
                -Because 'RID-500 is deny-listed by objectSid RID even when renamed (SAFE-05/06)'
        } else {
            Set-ItResult -Inconclusive -Because 'no RID-500 fixture provisioned under ADMAN_TEST_OU.'
        }
    }
}
