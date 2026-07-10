#Requires -Modules Pester
<#
.SYNOPSIS
    SAFE-08 / SAFE-09 AST guard. Parses every Public/**/*.ps1 with the PowerShell language
    AST and asserts no CommandAst resolves to a banned AD write cmdlet. The banned list is
    single-sourced from rules/AdmanSafetyRules.psm1 (Get-AdmanBannedWriteVerbs) so this test
    and the PSScriptAnalyzer custom rule can never drift. Static only - never touches a domain.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RuleModule = Join-Path $script:RepoRoot 'rules/AdmanSafetyRules.psm1'
    $script:PublicDir = Join-Path $script:RepoRoot 'Public'
    $script:FixturePublic = Join-Path $script:RepoRoot 'tests/Fixtures/Public/BadDirectWrite.ps1'
    $script:FixturePrivate = Join-Path $script:RepoRoot 'tests/Fixtures/Private/GoodWrapper.ps1'

    Import-Module $script:RuleModule -Force -ErrorAction SilentlyContinue
}

Describe 'SAFE-08: no exported function calls AD write cmdlets directly' -Tag 'Unit' {

    It 'uses the single-sourced banned list (Get-AdmanBannedWriteVerbs)' {
        $banned = Get-AdmanBannedWriteVerbs
        $banned | Should -Not -BeNullOrEmpty
        $banned | Should -Contain 'Set-ADUser'
        $banned | Should -Contain 'Remove-ADObject'
    }

    It 'Public/<file> contains no direct AD write call' {
        $banned = Get-AdmanBannedWriteVerbs
        $files = @(Get-ChildItem -Path $script:PublicDir -Filter *.ps1 -Recurse -File)
        $allHits = @()
        foreach ($f in $files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$tokens, [ref]$errors)
            $calls = $ast.FindAll(
                { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
            $names = foreach ($c in $calls) {
                $n = $c.GetCommandName()
                if (-not $n) { $n = $c.CommandElements[0].Extent.Text }   # L304 fallback
                if ($n) { $n }
            }
            $allHits += @($names | Where-Object { $_ -in $banned })
        }
        $allHits | Should -BeNullOrEmpty -Because 'Public/ verbs must route writes through Invoke-AdmanMutation'
    }

    It 'positive control fixture IS flagged (guard fires)' {
        $banned = Get-AdmanBannedWriteVerbs
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:FixturePublic, [ref]$tokens, [ref]$errors)
        $names = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object {
                $n = $_.GetCommandName()
                if (-not $n) { $n = $_.CommandElements[0].Extent.Text }
                $n
            } | Where-Object { $_ }
        $hits = @($names | Where-Object { $_ -in $banned })
        $hits | Should -Not -BeNullOrEmpty
    }

    It 'negative control (Private wrapper) is out of Public/ scope' {
        $hits = @(Invoke-AdmanScopedGuard -Path $script:FixturePrivate)
        $hits | Should -BeNullOrEmpty
    }
}
