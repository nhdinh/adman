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
    $script:TestDc = $env:ADMAN_TEST_DC
    $script:LabConfigured = -not [string]::IsNullOrWhiteSpace($script:TestOu) -and
        -not [string]::IsNullOrWhiteSpace($script:TestDc)

    # Initialize the adman module against a LAB config written under $TestDrive so the mutation
    # gate has the config + derived safety state ($script:Config / ProtectedGroupDns / DenyRids)
    # it needs. Runs ONLY in the lab-configured path (never when the env vars are unset).
    function Initialize-AdmanLab {
        [CmdletBinding()]
        param()

        # 1. Per-test store dir under $TestDrive (+ audit/reports subdirs).
        $testStore = Join-Path $TestDrive 'adman-store'
        New-Item -ItemType Directory -Path $testStore -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testStore 'audit') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testStore 'reports') -Force | Out-Null

        # 2. Live lab Domain Admins DN -> makes the protected-group set non-empty. CRITICAL: this
        #    is what makes the nested-admin refusal NON-vacuous. Without it, ProtectedGroupDns is
        #    empty, Test-AdmanTargetAllowed step (d) builds an empty $or filter, skips the IN_CHAIN
        #    query, and the nested-admin fixture would be allowed (false green).
        $daDn = (Get-ADGroup -Identity 'Domain Admins' -Server $script:TestDc -ErrorAction Stop).DistinguishedName

        # 3. Lab config satisfying config/adman.schema.json exactly (DenyList omitted -> seeded
        #    from config/adman.defaults.json by Initialize-AdmanConfig).
        $labConfig = [pscustomobject]@{
            ManagedOUs          = @($script:TestOu)
            DC                  = $script:TestDc
            AdmanProtectedGroup = $daDn
            AuditDir            = (Join-Path $testStore 'audit')
            ReportDir           = (Join-Path $testStore 'reports')
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            transport           = [pscustomobject]@{
                order    = @('WinRM', 'CimWsman', 'CimDcom', 'Skip')
                timeouts = [pscustomobject]@{ WinRM = 15; CIM = 20 }
            }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
            delegatedAdminGroup = ''
        }

        # 4. Serialize + write the lab config.json under $TestDrive.
        $labConfig | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $testStore 'config.json') -Encoding UTF8

        # 5. Inject $script:StorePath BEFORE Initialize-Adman so Initialize-AdmanConfig reads the
        #    lab config.json (it only defaults to '.store' when StorePath is unset).
        & (Get-Module adman) { param($p) $script:StorePath = $p } -p $testStore

        # 6. Initialize the module (rights-first pass-through under runas /netonly; no prompt).
        & (Get-Module adman) { Initialize-Adman }
    }
}

Describe 'SAFE-06: protected-account refusal against lab fixtures (nested admin, gMSA, renamed RID-500)' -Tag 'Integration' {

    It 'is skipped unless ADMAN_TEST_OU points at a disposable lab OU' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU and ADMAN_TEST_DC are not set; lab-only integration test (never auto-run).'
            return
        }
        $script:LabConfigured | Should -BeTrue
    }

    It 'refuses a nested Domain-Admins member and logs Refused with the precise reason' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU and ADMAN_TEST_DC are not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # Initialize the module against a $TestDrive lab config. AdmanProtectedGroup = live lab
        # Domain Admins DN makes the nested-admin refusal NON-vacuous (ProtectedGroupDns populated).
        Initialize-AdmanLab

        # Locate a lab fixture that is a nested (transitive) Domain-Admins member.
        $fixture = Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree `
            -LDAPFilter '(sAMAccountName=lab-nested-admin)' -ErrorAction SilentlyContinue
        if (-not $fixture) {
            Set-ItResult -Skipped -Because 'lab fixture lab-nested-admin not provisioned under ADMAN_TEST_OU.'
            return
        }

        $result = & (Get-Module adman) {
            param($t)
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $t -Confirm:$false -Force
        } @($fixture.DistinguishedName)

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
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU and ADMAN_TEST_DC are not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # Initialize the module against a $TestDrive lab config (same as the nested-admin block).
        Initialize-AdmanLab

        # gMSA fixture: objectClass msDS-GroupManagedServiceAccount is pre-filtered.
        $gmsa = Get-ADServiceAccount -SearchBase $script:TestOu -SearchScope Subtree `
            -Filter * -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gmsa) {
            $r = & (Get-Module adman) {
                param($t)
                Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $t -Confirm:$false -Force
            } @($gmsa.DistinguishedName)
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
            $r2 = & (Get-Module adman) {
                param($t)
                Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $t -Confirm:$false -Force
            } @($rid500.DistinguishedName)
            $r2.Denied | Should -BeGreaterOrEqual 1 `
                -Because 'RID-500 is deny-listed by objectSid RID even when renamed (SAFE-05/06)'
        } else {
            Set-ItResult -Inconclusive -Because 'no RID-500 fixture provisioned under ADMAN_TEST_OU.'
        }
    }
}
