#Requires -Modules Pester
<#
.SYNOPSIS
    CR-02 unit tests for ConvertTo-AdmanNormalizedDn.

.DESCRIPTION
    Pins the DN normalization contract used by the managed-OU scope boundary:
      * Uppercase and lowercase hex escapes are equivalent.
      * Multi-escape values unescape to canonical component text.
      * A hex-escaped backslash (\5C) normalizes to a literal backslash, not to
        a corrupted string.
      * Named escapes (\, \" \\ etc.) unescape to their literal characters.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:HelperPath = Join-Path $script:RepoRoot 'Private/Utility/ConvertTo-AdmanNormalizedDn.ps1'

    # Dot-source the helper under test (private utility, not exported).
    . $script:HelperPath
}

Describe 'ConvertTo-AdmanNormalizedDn: hex escape unescaping (CR-02)' -Tag 'Unit' {

    It 'unescapes lowercase hex comma escape: CN=Foo\2cBar -> cn=Foo,Bar' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo\2cBar,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=Foo,Bar,ou=managed,dc=contoso,dc=com'
    }

    It 'unescapes uppercase hex comma escape: CN=Foo\2CBar -> cn=Foo,Bar' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo\2CBar,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=Foo,Bar,ou=managed,dc=contoso,dc=com'
    }

    It 'normalizes uppercase and lowercase hex escapes identically' {
        $lower = ConvertTo-AdmanNormalizedDn -Dn 'CN=A\2cB,OU=Managed,DC=contoso,DC=com'
        $upper = ConvertTo-AdmanNormalizedDn -Dn 'CN=A\2CB,OU=Managed,DC=contoso,DC=com'
        $lower | Should -Be $upper
        $lower | Should -Be 'cn=A,B,ou=managed,dc=contoso,dc=com'
    }

    It 'unescapes multiple hex escapes in one RDN: CN=A\2CB\2CC -> cn=A,B,C' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=A\2CB\2CC,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=A,B,C,ou=managed,dc=contoso,dc=com'
    }

    It 'unescapes hex backslash escape to a literal backslash: CN=Foo\5CBar -> cn=Foo\Bar' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo\5CBar,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=Foo\Bar,ou=managed,dc=contoso,dc=com'
    }
}

Describe 'ConvertTo-AdmanNormalizedDn: named escape unescaping' -Tag 'Unit' {

    It 'unescapes doubled backslash to a literal backslash: CN=Foo\\Bar -> cn=Foo\Bar' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo\\Bar,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=Foo\Bar,ou=managed,dc=contoso,dc=com'
    }

    It 'unescapes escaped comma: CN=Foo\,Bar -> cn=Foo,Bar' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo\,Bar,OU=Managed,DC=contoso,DC=com' |
            Should -Be 'cn=Foo,Bar,ou=managed,dc=contoso,dc=com'
    }

    It 'trims whitespace around each RDN' {
        ConvertTo-AdmanNormalizedDn -Dn 'CN=Foo , OU=Managed , DC=contoso,DC=com' |
            Should -Be 'cn=foo,ou=managed,dc=contoso,dc=com'
    }
}

Describe 'ConvertTo-AdmanNormalizedDn: edge cases' -Tag 'Unit' {

    It 'returns empty string for null input' {
        ConvertTo-AdmanNormalizedDn -Dn $null | Should -Be ''
    }

    It 'returns empty string for empty input' {
        ConvertTo-AdmanNormalizedDn -Dn '' | Should -Be ''
    }
}
