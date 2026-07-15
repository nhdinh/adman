#Requires -Modules Pester
<#
.SYNOPSIS
    RPT-04 / D-05 contract tests for Get-AdmanStaleReport.

.DESCRIPTION
    Pins the stale / never-logged-on bucketing contract:
      * Requests lastLogonTimestamp in addition to the D-02 user properties.
      * Buckets as 'Stale' when lastLogonTimestamp is older than the grace window.
      * Buckets as 'NeverLoggedOn' when lastLogonTimestamp is 0/$null AND whenCreated is
        older than the grace window.
      * Excludes never-logged-on accounts created INSIDE the grace window.
      * Excludes fresh accounts (lastLogonTimestamp within the grace window).
      * NEVER queries per-DC lastLogon.
      * Out-of-scope objects are dropped via Test-AdmanInManagedScope.

    Runs entirely offline against tests/Mocks/ActiveDirectory.psm1; no RSAT, no live domain.
    Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'
    $script:MocksModule = Join-Path $script:RepoRoot 'tests/Mocks/ActiveDirectory.psm1'
    $script:StalePath = Join-Path $script:RepoRoot 'Public/Get-AdmanStaleReport.ps1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d2'
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

    # Import the AD mocks FIRST so Get-ADUser resolves to the mock when the module loads.
    Import-Module $script:MocksModule -Force -ErrorAction Stop
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Seed $script:Config with a known grace window.
    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = 'dc.mock.local'
            LogonSyncGraceDays  = 15
        }
    }

    # Helper to invoke the exported Get-AdmanStaleReport with the mock capture reset.
    function script:Invoke-StaleReport {
        Reset-AdmanMockCapture
        Get-AdmanStaleReport
    }
}

Describe 'Get-AdmanStaleReport: D-02 paging + properties invariants' -Tag 'Unit' {

    It 'requests lastLogonTimestamp in addition to the D-02 user properties' {
        Invoke-StaleReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls.Count | Should -BeGreaterOrEqual 1
        $calls[0].Properties | Should -Contain 'lastLogonTimestamp'
        $calls[0].Properties | Should -Contain 'whenCreated'
        $calls[0].Properties | Should -Contain 'MemberOf'
    }

    It 'uses -Filter * with -SearchScope Subtree and -ResultPageSize 1000' {
        Invoke-StaleReport | Out-Null
        $calls = @(Get-AdmanMockCapture | Where-Object { $_.Cmdlet -eq 'Get-ADUser' })
        $calls[0].Filter | Should -Be '*'
        $calls[0].SearchScope | Should -Be 'Subtree'
        $calls[0].ResultPageSize | Should -Be 1000
        $calls[0].Server | Should -Be 'dc.mock.local'
    }

    It 'never queries per-DC lastLogon (no -Server lastLogon attribute)' {
        $src = Get-Content -LiteralPath $script:StalePath -Raw
        # Per-DC lastLogon would appear as a bare 'lastLogon' property request (not
        # lastLogonTimestamp and not LastLogonDate). The D-05 contract forbids it.
        $src | Should -Not -Match "['""]lastLogon['""]" -Because 'per-DC lastLogon is forbidden (D-05)'
    }
}

Describe 'Get-AdmanStaleReport: bucketing logic (D-05)' -Tag 'Unit' {

    It 'buckets as Stale when lastLogonTimestamp is older than the grace window' {
        # NOTE: do NOT reference It-scope variables inside the Mock body — under
        # PS 5.1 + Pester 6 the mock executes in the adman module session state
        # and external variables resolve to $null. Inline all expressions.
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'Stale User'; SamAccountName = 'stale.user'; Enabled = $true
                    DistinguishedName = 'CN=Stale User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1001'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555555'
                    lastLogonTimestamp = [datetime]::UtcNow.AddDays(-30).ToFileTimeUtc()
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 1
        $result[0].Bucket | Should -Be 'Stale'
        $result[0].SamAccountName | Should -Be 'stale.user'
    }

    It 'buckets as NeverLoggedOn when lastLogonTimestamp is 0 and whenCreated is older than grace' {
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'Never User'; SamAccountName = 'never.user'; Enabled = $true
                    DistinguishedName = 'CN=Never User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1002'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555556'
                    lastLogonTimestamp = 0
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 1
        $result[0].Bucket | Should -Be 'NeverLoggedOn'
    }

    It 'buckets as NeverLoggedOn when lastLogonTimestamp is $null and whenCreated is older than grace' {
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'Never User'; SamAccountName = 'never.user'; Enabled = $true
                    DistinguishedName = 'CN=Never User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1003'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555557'
                    lastLogonTimestamp = $null
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 1
        $result[0].Bucket | Should -Be 'NeverLoggedOn'
    }

    It 'excludes never-logged-on accounts created INSIDE the grace window' {
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'New User'; SamAccountName = 'new.user'; Enabled = $true
                    DistinguishedName = 'CN=New User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1004'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555558'
                    lastLogonTimestamp = 0
                    whenCreated = [datetime]::UtcNow.AddDays(-5)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 0
    }

    It 'excludes fresh accounts (lastLogonTimestamp within the grace window)' {
        # NOTE: inline the FileTime expression — see 'buckets as Stale' for the
        # PS 5.1 mock-scoping rationale. This test must genuinely exercise the
        # exclusion path: the mock returns a fresh account and the report must
        # drop it (Count -Be 0), not pass vacuously because the mock returned
        # nothing.
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'Fresh User'; SamAccountName = 'fresh.user'; Enabled = $true
                    DistinguishedName = 'CN=Fresh User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1005'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555559'
                    lastLogonTimestamp = [datetime]::UtcNow.AddDays(-5).ToFileTimeUtc()
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 0
    }

    It 'drops out-of-scope objects via Test-AdmanInManagedScope' {
        # NOTE: inline the FileTime expression — see 'buckets as Stale' for the
        # PS 5.1 mock-scoping rationale.
        Mock Get-ADUser -ModuleName adman {
            @(
                [pscustomobject]@{
                    Name = 'Stale User'; SamAccountName = 'stale.user'; Enabled = $true
                    DistinguishedName = 'CN=Stale User,OU=Managed,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1006'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555560'
                    lastLogonTimestamp = [datetime]::UtcNow.AddDays(-30).ToFileTimeUtc()
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                },
                [pscustomobject]@{
                    Name = 'OutScope User'; SamAccountName = 'outscope.user'; Enabled = $true
                    DistinguishedName = 'CN=OutScope User,OU=NotManaged,DC=mock,DC=local'
                    ObjectSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1111111111-2222222222-3333333333-1007'
                    ObjectGuid = [guid]'11111111-2222-3333-4444-555555555561'
                    lastLogonTimestamp = [datetime]::UtcNow.AddDays(-30).ToFileTimeUtc()
                    whenCreated = [datetime]::UtcNow.AddDays(-60)
                }
            )
        }

        $result = @(Invoke-StaleReport)
        $result.Count | Should -Be 1
        $result[0].SamAccountName | Should -Be 'stale.user'
    }
}
