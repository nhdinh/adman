#Requires -Modules Pester
<#
.SYNOPSIS
    Bulk engine behavior tests (BULK-01..04).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway stub on $TestDrive. Private
    collaborators are mocked with -ModuleName adman and invoked inside the
    module scope where needed. No live domain.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000ca'
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
        $script:Initialized = $true
        $script:ProtectedSIDs = @()
        $script:DenyRids = @()
        $script:ProtectedGroupDns = @()
        $script:Config = [pscustomobject]@{
            ManagedOUs = @('OU=Managed,DC=mock,DC=local')
            DC         = 'dc.mock.local'
            bulk       = [pscustomobject]@{ maxCount = 3 }
            safety     = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            AuditDir   = (Join-Path $TestDrive 'audit')
        }
    }

    function script:New-AdmanTarget {
        param([string]$Identity, [switch]$Enabled, [string[]]$MemberOf)
        $o = [pscustomobject]@{
            DistinguishedName = "CN=$Identity,OU=Managed,DC=mock,DC=local"
            objectSid         = [System.Security.Principal.SecurityIdentifier]"S-1-5-21-111-222-333-$($Identity.Length)"
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
            Enabled           = $Enabled
        }
        if ($PSBoundParameters.ContainsKey('MemberOf')) {
            $o | Add-Member -MemberType NoteProperty -Name 'memberOf' -Value $MemberOf -Force
        }
        return $o
    }
}

Describe 'Invoke-AdmanBulkAction engine (BULK-01..04)' -Tag 'Unit' {

    BeforeEach {
        & (Get-Module adman) {
            $script:Config.bulk.maxCount = 3
        }
    }

    It 'calls Invoke-AdmanMutation once per allowed pipeline item' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 3; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 2
        $result.Total | Should -Be 2
        $result.Succeeded | Should -Be 2
    }

    It 'enforces cap after filtering' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { throw 'cap exceeded' }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        { & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u3,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u4,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        ) } | Should -Throw -ExpectedMessage '*cap exceeded*'
    }

    It 'uses Confirm-AdmanAction -RequireTypedCount even below default threshold' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $null = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 1 -ParameterFilter {
            $RequireTypedCount -eq $true
        }
    }

    It 'continues on single-item failure and reports Failed in summary' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation {
            if ($Targets[0] -eq 'CN=u2,OU=Managed,DC=mock,DC=local') { throw 'DC error' }
        }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u3,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        $result.Failed | Should -Be 1
        $result.Succeeded | Should -Be 2
        $result.PerItem | Where-Object { $_.Identity -eq 'CN=u2,OU=Managed,DC=mock,DC=local' } | ForEach-Object { $_.Result | Should -Be 'Failed' }
    }

    It '-WhatIf returns summary with WhatIf=$true and does not invoke real mutations' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'DryRun'; WhatIf = $true } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -WhatIf
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        $result.WhatIf | Should -BeTrue
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1
    }

    It 'skips Move no-op and writes Success audit note' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=u1,OU=Target,OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Move' -InputObject $i -TargetPath 'OU=Target,OU=Managed,DC=mock,DC=local' -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Target,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        $result.Succeeded | Should -Be 1
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 0
        Should -Invoke -ModuleName adman Write-AdmanAudit -Times 1 -ParameterFilter {
            $Result -eq 'Success' -and $Reason -eq 'already in place'
        }
    }

    It 'refuses protected group destination before cap/confirm for AddGroup' {
        Mock -ModuleName adman Resolve-AdmanGroup {
            return [pscustomobject]@{
                DistinguishedName = 'CN=Domain Admins,CN=Users,DC=mock,DC=local'
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-512'
                objectClass       = @('top', 'group')
            }
        }
        Mock -ModuleName adman Test-AdmanGroupAllowed { @{ Allowed = $false; Reason = 'group is in the protected set' } }
        Mock -ModuleName adman Resolve-AdmanTarget { }
        Mock -ModuleName adman Confirm-AdmanAction { }

        { & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'AddGroup' -InputObject $i -GroupIdentity 'Domain Admins' -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        ) } | Should -Throw -ExpectedMessage '*group destination*refused*'

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 0
    }

    It 'does not duplicate Confirm-AdmanAction calls on inner gate invocations' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation {
            # Simulate the inner gate; ensure it is called with -Force:$true.
        }

        $null = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        Should -Invoke -ModuleName adman Confirm-AdmanAction -Times 1
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 2 -ParameterFilter {
            $Force -eq $true
        }
    }

    It '-Force skips outer confirmation but inner policy/audit still run' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { throw 'Confirm-AdmanAction must NOT be called under -Force' }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $null = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 1 -ParameterFilter { $Force -eq $true }
    }

    It 'inner gate re-validation is authoritative when target becomes denied' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation {
            throw 'inner gate refused: target became protected'
        }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        $result.Failed | Should -Be 1
        $result.PerItem[0].Note | Should -Match 'inner gate refused'
    }

    It 'returns zero-count summary for empty pipeline and empty CSV input' {
        Mock -ModuleName adman Resolve-AdmanTarget { }
        Mock -ModuleName adman Test-AdmanTargetAllowed { }
        Mock -ModuleName adman Confirm-AdmanAction { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) { Invoke-AdmanBulkAction -Action 'Disable' -Force }

        $result.Total | Should -Be 0
        $result.Succeeded | Should -Be 0
        $result.Failed | Should -Be 0
        $result.Denied | Should -Be 0
    }

    It 'processes CSV input through the engine' {
        $csv = Join-Path $TestDrive 'bulk.csv'
        @'
ObjectType,Identity,Action,TargetPath,GroupIdentity
User,u1,Disable,,
User,u2,Disable,,
'@ | Set-Content -LiteralPath $csv -Encoding UTF8

        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = "CN=$($Targets[0]),OU=Managed,DC=mock,DC=local"
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed { @{ Allowed = $true; Reason = '' } }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) { param($p) Invoke-AdmanBulkAction -Action 'Disable' -Path $p -Force } -p $csv

        $result.Total | Should -Be 2
        Should -Invoke -ModuleName adman Invoke-AdmanMutation -Times 2
    }

    It 'counts denied items in summary and audits them as Refused' {
        Mock -ModuleName adman Resolve-AdmanTarget {
            return [pscustomobject]@{
                DistinguishedName = $Targets[0]
                Enabled           = $true
            }
        }
        Mock -ModuleName adman Test-AdmanTargetAllowed {
            if ($Object.DistinguishedName -eq 'CN=u1,OU=Managed,DC=mock,DC=local') {
                return @{ Allowed = $false; Reason = 'protected' }
            }
            return @{ Allowed = $true; Reason = '' }
        }
        Mock -ModuleName adman Assert-AdmanBulkPolicy { @{ Cap = 50; Threshold = 5 } }
        Mock -ModuleName adman Confirm-AdmanAction { @{ Outcome = 'Proceed'; WhatIf = $false } }
        Mock -ModuleName adman Write-AdmanAudit { }
        Mock -ModuleName adman Invoke-AdmanMutation { }

        $result = & (Get-Module adman) {
            param($i)
            Invoke-AdmanBulkAction -Action 'Disable' -InputObject $i -Force
        } -i @(
            [pscustomobject]@{ DistinguishedName = 'CN=u1,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
            [pscustomobject]@{ DistinguishedName = 'CN=u2,OU=Managed,DC=mock,DC=local'; ObjectType = 'User' }
        )

        $result.Denied | Should -Be 1
        $result.Succeeded | Should -Be 1
        Should -Invoke -ModuleName adman Write-AdmanAudit -Times 1 -ParameterFilter { $Result -eq 'Refused' }
    }
}
