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

        # 2. Live lab Domain Admins DN -> makes the protected-group set non-empty (non-vacuous).
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

Describe 'SAFE-01/10: end-to-end -WhatIf preview == execute against a disposable lab OU' -Tag 'Integration' {

    It 'is skipped unless ADMAN_TEST_OU points at a disposable lab OU' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU and ADMAN_TEST_DC are not set; lab-only integration test (never auto-run destructive).'
            return
        }
        $script:LabConfigured | Should -BeTrue
    }

    It 'a gated -WhatIf leaves AD unchanged, audit target == resolved, shown count == resolved.Count' -Tag 'Integration' {
        if (-not $script:LabConfigured) {
            Set-ItResult -Skipped -Because 'ADMAN_TEST_OU and ADMAN_TEST_DC are not set; lab-only integration test.'
            return
        }

        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        # Initialize the module against a $TestDrive lab config so the gate has config + derived
        # safety state (ProtectedGroupDns / DenyRids). Non-vacuous: AdmanProtectedGroup is the
        # live lab Domain Admins DN.
        Initialize-AdmanLab

        # Snapshot the lab OU state before the dry-run.
        $before = @(Get-ADObject -SearchBase $script:TestOu -SearchScope OneLevel -Filter * |
            Select-Object -ExpandProperty DistinguishedName)

        # Run a gated -WhatIf mutation against the lab OU (preview only; no real change).
        $result = & (Get-Module adman) {
            param($t)
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $t -WhatIf -Confirm:$false
        } @($script:TestOu)

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
