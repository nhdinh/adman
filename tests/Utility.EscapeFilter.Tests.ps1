#Requires -Modules Pester
<#
.SYNOPSIS
    HIGH-1 unit tests for Escape-AdmanAdFilterLiteral (AD PowerShell -Filter string literals).

.DESCRIPTION
    Pins the escaping contract for the dedicated -Filter-aware helper:
      * Single quote (') is DOUBLED ('') — the AD -Filter string-literal escape.
      * Backslash (\) is DOUBLED (\\) — backslash is the AD -Filter escape character.
      * Wildcards (* and ?) are NOT escaped — the Find verbs use -like semantics on -Name (D-02).
      * Parentheses ( ) and alphanumerics pass through unchanged.
      * Empty / null input returns the empty string.
      * The helper is INDEPENDENT of Escape-AdmanLdapFilterValue (RFC4515) — the two are NOT
        interchangeable and confusing them produces either an unparseable filter or an
        injectable one.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:HelperPath = Join-Path $script:RepoRoot 'Private/Utility/Escape-AdmanAdFilterLiteral.ps1'
    $script:LdapHelperPath = Join-Path $script:RepoRoot 'Private/Safety/Escape-AdmanLdapFilterValue.ps1'

    # Dot-source the helper under test (private utility, not exported).
    . $script:HelperPath
}

Describe 'Escape-AdmanAdFilterLiteral: single-quote doubling (HIGH-1)' -Tag 'Unit' {

    It "doubles a single quote: O'Brien -> O''Brien" {
        Escape-AdmanAdFilterLiteral -Value "O'Brien" | Should -Be "O''Brien"
    }

    It "doubles multiple single quotes: O'Brien's -> O''Brien''s" {
        Escape-AdmanAdFilterLiteral -Value "O'Brien's" | Should -Be "O''Brien''s"
    }

    It "doubles a leading single quote: 'Admin -> ''Admin" {
        Escape-AdmanAdFilterLiteral -Value "'Admin" | Should -Be "''Admin"
    }
}

Describe 'Escape-AdmanAdFilterLiteral: backslash doubling (HIGH-1)' -Tag 'Unit' {

    It 'doubles a single backslash: CN=Doe\John -> CN=Doe\\John' {
        Escape-AdmanAdFilterLiteral -Value 'CN=Doe\John' | Should -Be 'CN=Doe\\John'
    }

    It 'doubles multiple backslashes: A\B\C -> A\\B\\C' {
        Escape-AdmanAdFilterLiteral -Value 'A\B\C' | Should -Be 'A\\B\\C'
    }
}

Describe 'Escape-AdmanAdFilterLiteral: combined quote + backslash' -Tag 'Unit' {

    It "doubles both: O'\Brien -> O''\\Brien (backslash first, then quote)" {
        Escape-AdmanAdFilterLiteral -Value "O'\Brien" | Should -Be "O''\\Brien"
    }
}

Describe 'Escape-AdmanAdFilterLiteral: pass-through (no escape)' -Tag 'Unit' {

    It 'passes alphanumerics through unchanged' {
        Escape-AdmanAdFilterLiteral -Value 'normal' | Should -Be 'normal'
    }

    It 'passes parentheses through unchanged (NOT special in -Filter string literals)' {
        Escape-AdmanAdFilterLiteral -Value 'O(Brien)' | Should -Be 'O(Brien)'
    }

    It 'passes wildcard * through unchanged (preserved for -like semantics, D-02)' {
        Escape-AdmanAdFilterLiteral -Value 'O*Brien' | Should -Be 'O*Brien'
    }

    It 'passes wildcard ? through unchanged (preserved for -like semantics, D-02)' {
        Escape-AdmanAdFilterLiteral -Value 'O?Brien' | Should -Be 'O?Brien'
    }

    It 'passes spaces and hyphens through unchanged' {
        Escape-AdmanAdFilterLiteral -Value 'Mary-Jane Watson' | Should -Be 'Mary-Jane Watson'
    }
}

Describe 'Escape-AdmanAdFilterLiteral: empty / null input' -Tag 'Unit' {

    It 'returns empty string for empty input' {
        Escape-AdmanAdFilterLiteral -Value '' | Should -Be ''
    }

    It 'returns empty string for null input' {
        Escape-AdmanAdFilterLiteral -Value $null | Should -Be ''
    }
}

Describe 'Escape-AdmanAdFilterLiteral: independence from Escape-AdmanLdapFilterValue' -Tag 'Unit' {

    It 'does NOT call Escape-AdmanLdapFilterValue (the two helpers are independent)' {
        $content = Get-Content $script:HelperPath -Raw
        # The helper file must not invoke Escape-AdmanLdapFilterValue anywhere in code.
        # (Comment-based help MAY mention the name to disambiguate; we strip comments before checking.)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:HelperPath, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        $names = foreach ($c in $calls) {
            $n = $c.GetCommandName()
            if ($n) { $n }
        }
        $names | Should -Not -Contain 'Escape-AdmanLdapFilterValue'
    }

    It 'comment-based help explicitly distinguishes the two helpers' {
        $content = Get-Content $script:HelperPath -Raw
        $content | Should -Match 'Escape-AdmanLdapFilterValue'
        $content | Should -Match 'NOT interchangeable'
    }

    It 'produces DIFFERENT output than Escape-AdmanLdapFilterValue for the same input' {
        . $script:LdapHelperPath
        $input = "O'Brien*"
        $adFilter = Escape-AdmanAdFilterLiteral -Value $input
        $ldapFilter = Escape-AdmanLdapFilterValue -Value $input
        # -Filter helper doubles the quote and preserves the wildcard.
        $adFilter | Should -Be "O''Brien*"
        # RFC4515 helper hex-escapes the wildcard and leaves the quote alone.
        $ldapFilter | Should -Be "O'Brien\2a"
        $adFilter | Should -Not -Be $ldapFilter
    }
}
