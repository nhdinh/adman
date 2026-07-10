#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED/GREEN) DPAPI restore + consent + no-secret tests for Get-AdmanCredential
    (CONF-04/05, D-06). Proves:
      * DPAPI restore success returns the credential and exercises the empty-password guard
        (GetNetworkCredential().Password) on the non-empty path.
      * Restore failure (CryptographicException 0x8009000B) OR empty/null restored password
        => the bad file is DELETED (Remove-Item) and Get-Credential is invoked as fallback.
      * Export-Clixml is called ONLY when allowRememberMe=$true AND consent=$true; consent=$false
        writes nothing but still returns the prompted credential for the session.
      * A keyed-AES / non-PSCredential restore is rejected (delete + re-prompt) and the source
        carries NO keyed-AES export switch token.
      * No credential / password is ever logged (CONF-05): zero Write-AdmanAudit/Write-Log and
        no Write-PSFMessage line that interpolates the credential or password.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. $script:StorePath
    pointed at a per-test temp dir. Get-Credential is stubbed in test scope (not resolvable here).
    Import-Clixml / Export-Clixml / Remove-Item / Get-Credential are all mocked - no real DPAPI.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c2'
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
    $script:ImplPath = Join-Path $script:RepoRoot 'Private\Foundation\Get-AdmanCredential.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Test doubles qualified with global: so Pester's Mock resolver (Get-Command) finds them from
    # any scope. Get-Credential is not resolvable here; the consent helper is module-private at
    # GREEN (inert fallback). Live only in the test process - never shipped.
    function global:Get-Credential { param($Message) }
    function global:Read-AdmanRememberMeConsent { }
    function global:Get-ADOrganizationalUnit { param($Identity, $Server, $Filter) }

    function New-AdmanTestCred {
        [CmdletBinding()]
        param([string]$Value = 'Str0ng!')
        $sec = New-Object System.Security.SecureString
        if ($Value) { $Value.ToCharArray() | ForEach-Object { $sec.AppendChar($_) } }
        $sec.MakeReadOnly()
        return [pscredential]::new('DOMAIN\user', $sec)
    }

    function Get-AdmanCredTestConfig {
        [CmdletBinding()]
        param([bool]$Allow = $true)
        [pscustomobject]@{
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $Allow }
            DC                  = 'dc.mock.local'
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            delegatedAdminGroup = ''
        }
    }

    function Set-AdmanCredState {
        [CmdletBinding()]
        param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Store)
        & (Get-Module adman) {
            param($Config, $Store)
            $script:Config = $Config
            $script:StorePath = $Store
            Set-Variable -Name RightsInsufficient -Scope Script -Value $true
        } -Config $Config -Store $Store
    }
}

Describe 'Get-AdmanCredential DPAPI restore + consent + no-secret (CONF-04/05, D-06)' -Tag 'Unit' {

    It 'Test 3: DPAPI restore success returns the credential (empty-password guard, non-empty path)' {
        $store = Join-Path $TestDrive 't3'
        $null = New-Item -ItemType Directory -Path $store -Force
        'placeholder' | Set-Content -LiteralPath (Join-Path $store 'adman.credential.xml') -Encoding UTF8
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Import-Clixml -ModuleName adman { New-AdmanTestCred 'Str0ng!' }
        Mock Remove-Item -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        $cred.GetNetworkCredential().Password | Should -Be 'Str0ng!' -Because 'a valid restore yields the stored credential (guard reads non-empty password)'
        Should -Invoke Get-Credential -ModuleName adman -Times 0
        Should -Invoke Remove-Item -ModuleName adman -Times 0 -Because 'a good restore must not delete the file'
    }

    It 'Test 4a: restore CryptographicException (0x8009000B) deletes the bad file and re-prompts' {
        $store = Join-Path $TestDrive 't4a'
        $null = New-Item -ItemType Directory -Path $store -Force
        $file = Join-Path $store 'adman.credential.xml'
        'placeholder' | Set-Content -LiteralPath $file -Encoding UTF8
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Import-Clixml -ModuleName adman {
            throw (New-Object System.Security.Cryptography.CryptographicException 'Key not valid for use in specified state')
        }
        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Remove-Item -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        $cred.GetNetworkCredential().Password | Should -Be 'Prompted!'
        Should -Invoke Remove-Item -ModuleName adman -Times 1 -ParameterFilter { $Path -eq $file } -Because 'a bad DPAPI file must be deleted'
        Should -Invoke Get-Credential -ModuleName adman -Times 1 -Because 'restore failure falls back to Get-Credential'
    }

    It 'Test 4b: empty/null restored password deletes the bad file and re-prompts' {
        $store = Join-Path $TestDrive 't4b'
        $null = New-Item -ItemType Directory -Path $store -Force
        $file = Join-Path $store 'adman.credential.xml'
        'placeholder' | Set-Content -LiteralPath $file -Encoding UTF8
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Import-Clixml -ModuleName adman { New-AdmanTestCred '' }   # empty password -> guard throws
        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Remove-Item -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        $cred.GetNetworkCredential().Password | Should -Be 'Prompted!'
        Should -Invoke Remove-Item -ModuleName adman -Times 1 -ParameterFilter { $Path -eq $file }
        Should -Invoke Get-Credential -ModuleName adman -Times 1
    }

    It 'Test 5a: consent=$true (with allowRememberMe=$true) writes the DPAPI file and returns the credential' {
        $store = Join-Path $TestDrive 't5a'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Read-AdmanRememberMeConsent -ModuleName adman { $true }
        Mock Export-Clixml -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        Should -Invoke Export-Clixml -ModuleName adman -Times 1 -Because 'consent + remember-me writes the DPAPI file'
    }

    It 'Test 5b: consent=$false writes NO file but still returns the prompted credential' {
        $store = Join-Path $TestDrive 't5b'
        $null = New-Item -ItemType Directory -Path $store -Force
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Read-AdmanRememberMeConsent -ModuleName adman { $false }
        Mock Export-Clixml -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue -Because 'the prompted credential is still returned for the session even when consent is declined'
        Should -Invoke Export-Clixml -ModuleName adman -Times 0 -Because 'declining consent must not write a DPAPI file'
    }

    It 'Test 6: keyed-AES / non-PSCredential restore is rejected (delete + re-prompt); source has no keyed-AES export token' {
        $store = Join-Path $TestDrive 't6'
        $null = New-Item -ItemType Directory -Path $store -Force
        $file = Join-Path $store 'adman.credential.xml'
        'placeholder' | Set-Content -LiteralPath $file -Encoding UTF8
        Set-AdmanCredState -Config (Get-AdmanCredTestConfig -Allow $true) -Store $store

        Mock Import-Clixml -ModuleName adman { 'not-a-pscredential' }   # keyed-AES/corrupt -> type check fails
        Mock Get-Credential -ModuleName adman { New-AdmanTestCred 'Prompted!' }
        Mock Remove-Item -ModuleName adman { }
        $cred = & (Get-Module adman) { Get-AdmanCredential }

        $cred -is [pscredential] | Should -BeTrue
        Should -Invoke Remove-Item -ModuleName adman -Times 1 -ParameterFilter { $Path -eq $file }
        Should -Invoke Get-Credential -ModuleName adman -Times 1

        # Static: the source MUST NOT contain the keyed-AES export switch (PS7-only; rejected by D-06).
        Test-Path -LiteralPath $script:ImplPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ImplPath -Raw
        @($src | Select-String -Pattern '\-EncryptionKey').Count | Should -Be 0 -Because 'the keyed-AES export switch is forbidden (D-06)'
        $src | Should -Match 'Export-Clixml' -Because 'consented writes still use DPAPI Export-Clixml'
    }

    It 'Test 7: no credential/password is ever logged (CONF-05)' {
        Test-Path -LiteralPath $script:ImplPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ImplPath -Raw

        @($src | Select-String -Pattern 'Write-AdmanAudit|Write-Log').Count | Should -Be 0 -Because 'Get-AdmanCredential must never write to the audit/log'
        $msgLines = $src -split "`r?`n" | Where-Object { $_ -match 'Write-PSFMessage' }
        foreach ($line in $msgLines) {
            $line | Should -Not -Match '\$cred|Password' -Because 'diagnostic messages must not interpolate the credential or password'
        }
    }
}
