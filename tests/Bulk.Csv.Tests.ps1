#Requires -Modules Pester
<#
.SYNOPSIS
    Bulk CSV normalization tests (BULK-04, D-23/D-25).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive.
    Import-AdmanBulkCsv and ConvertTo-AdmanBulkInput are private; invoked via
    module-scope scriptblock. No live domain.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c9'
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
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    & (Get-Module adman) {
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
            bulk       = [pscustomobject]@{ maxCount = 50 }
            safety     = [pscustomobject]@{ bulkConfirmThreshold = 5 }
        }
    }
}

Describe 'Import-AdmanBulkCsv strict schema (BULK-04, D-23/D-25)' -Tag 'Unit' {

    It 'returns rows for a valid CSV' {
        $csv = Join-Path $TestDrive 'valid.csv'
        @'
ObjectType,Identity,Action,TargetPath,GroupIdentity
User,jdoe,Disable,,
Computer,pc1,Enable,,
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        $rows = & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv
        $rows.Count | Should -Be 2
        $rows[0].ObjectType | Should -Be 'User'
        $rows[0].Action | Should -Be 'Disable'
    }

    It 'rejects unknown columns' {
        $csv = Join-Path $TestDrive 'unknown.csv'
        @'
ObjectType,Identity,Action,BadColumn
User,jdoe,Disable,x
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        { & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv } | Should -Throw -ExpectedMessage '*unknown columns*'
    }

    It 'rejects duplicate columns' {
        $csv = Join-Path $TestDrive 'duplicate.csv'
        @'
ObjectType,Identity,Action,Identity
User,jdoe,Disable,jdoe
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        { & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv } | Should -Throw -ExpectedMessage '*duplicate columns*'
    }

    It 'rejects missing required column Identity' {
        $csv = Join-Path $TestDrive 'missing-identity.csv'
        @'
ObjectType,Action
User,Disable
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        { & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv } | Should -Throw -ExpectedMessage '*missing required columns*Identity*'
    }

    It 'rejects missing required column Action' {
        $csv = Join-Path $TestDrive 'missing-action.csv'
        @'
ObjectType,Identity
User,jdoe
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        { & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv } | Should -Throw -ExpectedMessage '*missing required columns*Action*'
    }

    It 'returns empty array for an empty file' {
        $csv = Join-Path $TestDrive 'empty.csv'
        '' | Set-Content -LiteralPath $csv -Encoding UTF8

        $rows = & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv
        $rows | Should -Be @()
    }

    It 'accepts columns in any order' {
        $csv = Join-Path $TestDrive 'reordered.csv'
        @'
Action,Identity,ObjectType
Disable,jdoe,User
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        $rows = & (Get-Module adman) { param($p) Import-AdmanBulkCsv -Path $p } -p $csv
        $rows.Count | Should -Be 1
        $rows[0].Action | Should -Be 'Disable'
        $rows[0].ObjectType | Should -Be 'User'
    }
}

Describe 'ConvertTo-AdmanBulkInput pipeline normalization (D-01/D-02)' -Tag 'Unit' {

    It 'maps Find-AdmanUser-shaped objects to bulk records' {
        $inputObj = [pscustomobject]@{
            DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'
            ObjectType        = 'User'
            SamAccountName    = 'jdoe'
        }

        $record = & (Get-Module adman) {
            param($o)
            $o | ConvertTo-AdmanBulkInput -Action 'Disable'
        } -o $inputObj

        $record.ObjectType | Should -Be 'User'
        $record.Identity | Should -Be 'CN=u1,OU=Managed,DC=mock,DC=local'
        $record.Action | Should -Be 'Disable'
        $record.TargetPath | Should -BeNullOrEmpty
        $record.GroupIdentity | Should -BeNullOrEmpty
    }

    It 'defaults ObjectType to User when input lacks it' {
        $inputObj = [pscustomobject]@{
            DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'
        }

        $record = & (Get-Module adman) {
            param($o)
            $o | ConvertTo-AdmanBulkInput -Action 'Move' -TargetPath 'OU=Target,OU=Managed,DC=mock,DC=local'
        } -o $inputObj

        $record.ObjectType | Should -Be 'User'
        $record.TargetPath | Should -Be 'OU=Target,OU=Managed,DC=mock,DC=local'
    }

    It 'passes TargetPath and GroupIdentity through' {
        $inputObj = [pscustomobject]@{
            DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'
            ObjectType        = 'User'
        }

        $record = & (Get-Module adman) {
            param($o)
            $o | ConvertTo-AdmanBulkInput -Action 'AddGroup' -GroupIdentity 'G1'
        } -o $inputObj

        $record.Action | Should -Be 'AddGroup'
        $record.GroupIdentity | Should -Be 'G1'
    }
}
