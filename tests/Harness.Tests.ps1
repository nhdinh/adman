#Requires -Modules Pester
<#
.SYNOPSIS
    Task 3 behavior tests for the lint/test harness: repo-wide lint cleanliness (SAFE-01),
    the custom SAFE-08 rule firing on a positive control, AD/CIM/remoting mocks (no network),
    and the L304 token-grep fallback.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:SettingsPath = Join-Path $script:RepoRoot 'PSScriptAnalyzerSettings.psd1'
    $script:RuleModule = Join-Path $script:RepoRoot 'rules/AdmanSafetyRules.psm1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:FixturePublic = Join-Path $script:RepoRoot 'tests/Fixtures/Public/BadDirectWrite.ps1'
    $script:FixturePrivate = Join-Path $script:RepoRoot 'tests/Fixtures/Private/GoodWrapper.ps1'
    $script:FixtureDynamic = Join-Path $script:RepoRoot 'tests/Fixtures/Public/DynamicInvoke.ps1'

    Import-Module PSScriptAnalyzer -MinimumVersion 1.25.0 -ErrorAction SilentlyContinue
    Import-Module $script:RuleModule -Force -ErrorAction SilentlyContinue
}

Describe 'adman safety harness (SAFE-01 / SAFE-08)' -Tag 'Unit' {

    It 'lint is clean with PSUseShouldProcessForStateChangingFunctions enabled (SAFE-01)' {
        Test-Path $script:SettingsPath | Should -BeTrue
        $raw = Get-Content $script:SettingsPath -Raw
        $raw | Should -Match 'PSUseShouldProcessForStateChangingFunctions'

        $results = @(Invoke-ScriptAnalyzer -Path $script:RepoRoot -Recurse -Settings $script:SettingsPath)
        $results | Should -BeNullOrEmpty
    }

    It 'custom rule flags a direct AD write in a Public fixture but not a Private wrapper (SAFE-08)' {
        Import-Module $script:RuleModule -Force -ErrorAction Stop

        $posHits = @(Test-AdmanBannedWriteAst -Path $script:FixturePublic)
        $posHits | Should -Not -BeNullOrEmpty

        $negHits = @(Invoke-AdmanScopedGuard -Path $script:FixturePrivate)
        $negHits | Should -BeNullOrEmpty
    }

    It 'AD/CIM/remoting mocks supply canned objects with zero network' {
        Import-Module $script:MocksModule -Force -ErrorAction Stop

        $u = Get-ADUser -Identity 'dummy'
        $u | Should -Not -BeNullOrEmpty
        $u.objectSid | Should -Not -BeNullOrEmpty
        ($u.PSObject.TypeNames -join ',') | Should -Match 'AdmanMock'

        { Set-ADUser -Identity 'x' -Description 'y' } | Should -Not -Throw
        { Disable-ADAccount -Identity 'x' } | Should -Not -Throw
        { Move-ADObject -Identity 'x' -TargetPath 'OU=y,DC=z' } | Should -Not -Throw
        { Get-ADDomain } | Should -Not -Throw
        { Get-CimInstance -ClassName 'Win32_OperatingSystem' } | Should -Not -Throw
        { Invoke-Command -ScriptBlock { 1 } } | Should -Not -Throw
    }

    It 'token-grep flags a dynamic/Invoke-Expression AD write in a Public fixture (L304)' {
        Import-Module $script:RuleModule -Force -ErrorAction Stop
        $hits = @(Test-AdmanBannedWriteAst -Path $script:FixtureDynamic)
        $hits | Should -Not -BeNullOrEmpty
    }
}
