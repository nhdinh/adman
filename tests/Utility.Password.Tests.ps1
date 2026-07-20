#Requires -Modules Pester
<#
.SYNOPSIS
    D-05 password plumbing tests (Task 1, Plan 02-01).

    Proves the CSPRNG generator + complexity validator + the new security config schema:
      * Test 1: New-AdmanRandomPassword -Length 20 returns a [securestring] of length 20.
      * Test 2: 100 generated passwords each contain at least one uppercase, one lowercase,
        one digit, one symbol.
      * Test 3: 100 generated passwords contain zero ambiguous glyphs (case-sensitive match
        against 0, O, o, l, 1, I).
      * Test 4: New-AdmanRandomPassword -Length 3 throws "Length must be >= 4".
      * Test 5: Test-AdmanPasswordComplexity accepts a SecureString meeting length+4-classes;
        throws a precise reason for each failing class (length, upper, lower, digit, symbol).
      * Test 6: config schema requires security.passwordSource and
        security.passwordGeneration.length; defaults file carries Generate + 20.
      * Test 7: Test-AdmanConfigValid throws when security.passwordSource is missing.
      * Test 8: config schema carries security.mustChangeAtNextLogon (boolean, default $true);
        defaults file ships it as $true; Test-AdmanConfigValid accepts a config that omits it
        (optional key with shipped default).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. No live domain.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d5'
    FunctionsToExport = @('Set-PSFConfig','Get-PSFConfig','Register-PSFConfigValidation','Export-PSFConfig','Import-PSFConfig','Write-PSFMessage')
}
"@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psd1') -Encoding UTF8
    @'
function Set-PSFConfig { [CmdletBinding()] param($Value, [switch]$Initialize, $Name, $Module) }
function Get-PSFConfig { [CmdletBinding()] param($Name, $Module) }
function Register-PSFConfigValidation { [CmdletBinding()] param() }
function Export-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Import-PSFConfig { [CmdletBinding()] param($Path, $Module, $Name) }
function Write-PSFMessage { [CmdletBinding()] param($Level, $Message) }
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'PSFramework.psm1') -Encoding UTF8
    $env:PSModulePath = "$stubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:SchemaPath = Join-Path $script:RepoRoot 'config\adman.schema.json'
    $script:DefaultsPath = Join-Path $script:RepoRoot 'config\adman.defaults.json'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Read a SecureString into a transient plaintext buffer for assertion (test-only).
    function ConvertFrom-AdmanSecureString {
        [CmdletBinding()]
        param([Parameter(Mandatory)][securestring]$Password)
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    function New-AdmanTestSecureString {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Plain)
        $s = [securestring]::new()
        foreach ($c in $Plain.ToCharArray()) { $s.AppendChar($c) }
        $s.MakeReadOnly()
        return $s
    }
}

Describe 'D-05: New-AdmanRandomPassword (CSPRNG generator)' -Tag 'Unit' {

    It 'Test 1: -Length 20 returns a [securestring] of length 20' {
        $pw = & (Get-Module adman) { New-AdmanRandomPassword -Length 20 }
        $pw | Should -BeOfType [securestring]
        $plain = ConvertFrom-AdmanSecureString -Password $pw
        $plain.Length | Should -Be 20
    }

    It 'Test 2: 100 generated passwords each contain upper, lower, digit, symbol' {
        for ($i = 0; $i -lt 100; $i++) {
            $pw = & (Get-Module adman) { New-AdmanRandomPassword -Length 20 }
            $plain = ConvertFrom-AdmanSecureString -Password $pw
            $plain | Should -Match '[A-Z]'
            $plain | Should -Match '[a-z]'
            $plain | Should -Match '\d'
            $plain | Should -Match '[^A-Za-z0-9]'
        }
    }

    It 'Test 3: 100 generated passwords contain zero ambiguous glyphs (0 O o l 1 I)' {
        for ($i = 0; $i -lt 100; $i++) {
            $pw = & (Get-Module adman) { New-AdmanRandomPassword -Length 20 }
            $plain = ConvertFrom-AdmanSecureString -Password $pw
            # Case-SENSITIVE match — default -match is case-insensitive and would false-positive
            # on L (Upper) and i (Lower), which are NOT ambiguous.
            $plain | Should -Not -CMatch '[0Ool1I]'
        }
    }

    It 'Test 4: -Length 3 throws "Length must be >= 4"' {
        { & (Get-Module adman) { New-AdmanRandomPassword -Length 3 } } |
            Should -Throw -ExpectedMessage '*Length must be >= 4*'
    }
}

Describe 'D-05: Test-AdmanPasswordComplexity (prompt-path validator)' -Tag 'Unit' {

    It 'Test 5a: accepts a SecureString meeting length + 4-classes' {
        $good = New-AdmanTestSecureString -Plain 'Abcd1234!@#$WXYZwxyz'
        $result = & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $good
        $result | Should -BeTrue
    }

    It 'Test 5b: throws a precise reason when length is too short' {
        $short = New-AdmanTestSecureString -Plain 'Ab1!'
        { & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $short } | Should -Throw -ExpectedMessage '*at least*characters*'
    }

    It 'Test 5c: throws a precise reason when uppercase is missing' {
        $noUpper = New-AdmanTestSecureString -Plain 'abcd1234!@#$wxyzabcd'
        { & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $noUpper } | Should -Throw -ExpectedMessage '*uppercase*'
    }

    It 'Test 5d: throws a precise reason when lowercase is missing' {
        $noLower = New-AdmanTestSecureString -Plain 'ABCD1234!@#$WXYZABCD'
        { & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $noLower } | Should -Throw -ExpectedMessage '*lowercase*'
    }

    It 'Test 5e: throws a precise reason when digit is missing' {
        $noDigit = New-AdmanTestSecureString -Plain 'Abcdefgh!@#$WXYZwxyz'
        { & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $noDigit } | Should -Throw -ExpectedMessage '*digit*'
    }

    It 'Test 5f: throws a precise reason when symbol is missing' {
        $noSymbol = New-AdmanTestSecureString -Plain 'Abcd1234WXYZwxyzABCD'
        { & (Get-Module adman) {
            param($P) Test-AdmanPasswordComplexity -Password $P -MinLength 20
        } -P $noSymbol } | Should -Throw -ExpectedMessage '*symbol*'
    }
}

Describe 'D-05: config schema additions (security block)' -Tag 'Unit' {

    It 'Test 6: schema requires security.passwordSource and security.passwordGeneration.length; defaults ships Generate + 20' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json
        @($schema.required) | Should -Contain 'security'
        @($schema.properties.security.required) | Should -Contain 'passwordSource'
        @($schema.properties.security.required) | Should -Contain 'passwordGeneration'
        $schema.properties.security.properties.passwordSource.enum | Should -Contain 'Generate'
        $schema.properties.security.properties.passwordSource.enum | Should -Contain 'Prompt'
        $schema.properties.security.properties.passwordSource.enum | Should -Contain 'Ask'
        [int]$schema.properties.security.properties.passwordGeneration.properties.length.minimum | Should -Be 8

        $defaults = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
        $defaults.security.passwordSource | Should -Be 'Generate'
        [int]$defaults.security.passwordGeneration.length | Should -Be 20
    }

    It 'Test 7: Test-AdmanConfigValid throws when security.passwordSource is missing' {
        $cfg = [pscustomobject][ordered]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DenyList            = @(@{ token = '500'; note = 'starter, not exhaustive' })
            safety              = @{ bulkConfirmThreshold = 5 }
            bulk                = @{ maxCount = 50 }
            AuditDir            = '.store/audit'
            ReportDir           = 'reports'
            transport           = @{ order = @('WinRM', 'CimWsman', 'CimDcom', 'Skip'); timeouts = @{ WinRM = 15; CIM = 20 } }
            credentialPolicy    = @{ allowRememberMe = $false }
            AdmanProtectedGroup = ''
            DC                  = ''
            delegatedAdminGroup = ''
            # NO security block at all -> schema-required top-level key is missing.
        }
        { & (Get-Module adman) {
            param($C, $MR) Test-AdmanConfigValid -Config $C -ModuleRoot $MR
        } -C $cfg -MR $script:RepoRoot } | Should -Throw -ExpectedMessage "*'security'*"
    }

    It 'Test 8: schema carries security.mustChangeAtNextLogon (boolean, optional, default $true); validator accepts a config that omits it' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json
        $schema.properties.security.properties.mustChangeAtNextLogon.type | Should -Be 'boolean'
        # OPTIONAL: NOT in security.required
        @($schema.properties.security.required) | Should -Not -Contain 'mustChangeAtNextLogon'

        $defaults = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
        [bool]$defaults.security.mustChangeAtNextLogon | Should -BeTrue

        # A config WITHOUT mustChangeAtNextLogon still validates (optional key with shipped default).
        $cfg = [pscustomobject][ordered]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DenyList            = @([pscustomobject]@{ token = '500'; note = 'starter, not exhaustive' })
            safety              = @{ bulkConfirmThreshold = 5 }
            bulk                = @{ maxCount = 50 }
            AuditDir            = '.store/audit'
            ReportDir           = 'reports'
            transport           = @{ order = @('WinRM', 'CimWsman', 'CimDcom', 'Skip'); timeouts = @{ WinRM = 15; CIM = 20; perHostProbeCap = 10; totalInventoryRemoteCap = 120 } }
            credentialPolicy    = @{ allowRememberMe = $false }
            AdmanProtectedGroup = ''
            DC                  = ''
            domain              = 'mock.local'
            delegatedAdminGroup = ''
            templates           = @{
                onboarding  = @{ ParentOuDn = 'OU=Users,OU=Managed,DC=mock,DC=local'; BaselineGroups = @(); NamePattern = '{0}.{1}' }
                offboarding = @{ quarantineOU = 'OU=Quarantine,OU=Managed,DC=mock,DC=local' }
            }
            security            = @{
                passwordSource     = 'Generate'
                passwordGeneration = @{ length = 20 }
                # mustChangeAtNextLogon intentionally omitted.
            }
        }
        $result = & (Get-Module adman) {
            param($C, $MR) Test-AdmanConfigValid -Config $C -ModuleRoot $MR
        } -C $cfg -MR $script:RepoRoot
        $result | Should -BeTrue
    }
}
