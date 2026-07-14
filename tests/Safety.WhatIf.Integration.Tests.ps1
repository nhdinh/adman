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

        # Provision dedicated NON-PROTECTED user fixtures idempotently (resolve-identity-as-is:
        # the gate resolves each given identity as-is and does NOT enumerate OU children, so we
        # target child USER fixtures, NOT the OU DN). These are deliberately non-protected: not
        # Domain Admins (or any protected group), not gMSA, not RID 500/501/502 -> the gate
        # ALLOWS them and they land in Succeeded. Do NOT reuse lab-nested-admin / gMSA / RID-500
        # fixtures (those are protected and would produce Denied, failing the Succeeded assertion
        # for the wrong reason).
        $fixtureNames = @('lab-whatif-1', 'lab-whatif-2')
        foreach ($name in $fixtureNames) {
            $u = Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree `
                -LDAPFilter "(sAMAccountName=$name)" -Server $script:TestDc -ErrorAction SilentlyContinue
            if (-not $u) {
                try {
                    New-ADUser -Name $name -SamAccountName $name -Path $script:TestOu `
                        -Server $script:TestDc -Enabled $true `
                        -AccountPassword (ConvertTo-SecureString 'Lab!Passw0rd1' -AsPlainText -Force) `
                        -ErrorAction Stop | Out-Null
                } catch {
                    Set-ItResult -Inconclusive `
                        -Because "could not provision fixture '$name' under ADMAN_TEST_OU (insufficient lab rights?): $($_.Exception.Message)"
                    return
                }
            }
        }

        # Resolve the fixture DNs into $targets (the two lab-whatif-* DistinguishedNames).
        $targets = @()
        foreach ($name in $fixtureNames) {
            $dn = (Get-ADUser -SearchBase $script:TestOu -SearchScope Subtree `
                -LDAPFilter "(sAMAccountName=$name)" -Server $script:TestDc -ErrorAction SilentlyContinue).DistinguishedName
            if ($dn) { $targets += $dn }
        }
        if ($targets.Count -lt $fixtureNames.Count) {
            Set-ItResult -Inconclusive `
                -Because 'lab-whatif-* fixtures could not be provisioned under ADMAN_TEST_OU.'
            return
        }

        # Snapshot AD state for the TARGETED USERS before the dry-run (not the whole OU): capture
        # each fixture's Enabled state into a map keyed by DN.
        $before = @{}
        foreach ($dn in $targets) {
            $before[$dn] = (Get-ADUser -Identity $dn -Server $script:TestDc -Properties Enabled).Enabled
        }

        # Run a gated -WhatIf mutation against the USER fixtures (preview only; no real change).
        $result = & (Get-Module adman) {
            param($t)
            Invoke-AdmanMutation -Verb 'Disable-ADAccount' -Targets $t -WhatIf -Confirm:$false
        } $targets

        # (a) AD is UNCHANGED after the dry-run: every targeted user is STILL Enabled (a -WhatIf
        #     dry-run must not disable them, SAFE-01). Do NOT assert on OU child-object count.
        foreach ($dn in $targets) {
            $enabledAfter = (Get-ADUser -Identity $dn -Server $script:TestDc -Properties Enabled).Enabled
            $enabledAfter | Should -Be $before[$dn] `
                -Because "a -WhatIf dry-run must not mutate AD (SAFE-01): $dn Enabled unchanged"
            $enabledAfter | Should -BeTrue `
                -Because "a -WhatIf dry-run must not disable the target (SAFE-01): $dn still Enabled"
        }

        # (c) operator-shown count equals the resolved count.
        $result.WhatIf | Should -BeTrue -Because 'the result reflects a dry-run'
        $result.Succeeded | Should -Be $targets.Count `
            -Because 'each non-protected user fixture resolves as-is and is allowed (SAFE-10)'
        $result.Denied | Should -Be 0 `
            -Because 'no fixture is protected/deny-listed, so none is refused'

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
        # The union of the audit records' target DNs equals the resolved set ($targets). The
        # audit 'targets' field is an array of {dn,sid,objectClass} objects -> extract .dn.
        $auditTargets = @($cidRecords | ForEach-Object { @($_.targets) | ForEach-Object { $_.dn } } |
            Where-Object { $_ } | Select-Object -Unique)
        @($auditTargets | Sort-Object) | Should -Be @($targets | Sort-Object) `
            -Because 'the audit target list equals the resolved target set (SAFE-10)'
    }
}
