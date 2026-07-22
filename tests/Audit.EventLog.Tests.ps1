#Requires -Modules Pester
<#
.SYNOPSIS
    D-05 OUTCOME audit-write escalation tests (Write-AdmanAudit).

.DESCRIPTION
    Proves that when the OUTCOME audit write fails after a mutation, Write-AdmanAudit
    escalates to Write-AdmanEventLog with EventId 9001 and EntryType Error rather than
    throwing to the caller or attempting to roll back AD.
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

    function global:New-AdmanAuditMutex { }
    function global:Open-AdmanAuditStream { param($Path) }
    function global:Write-AdmanEventLog { param($EventId, $EntryType, $Message) }

    function New-AdmanAuditConfig {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$AuditDir)
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = 'dc.mock.local'
            AuditDir            = $AuditDir
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
            security            = [pscustomobject]@{
                passwordSource     = 'Generate'
                passwordGeneration = [pscustomobject]@{ length = 20 }
            }
            domain              = 'mock.local'
            templates           = [pscustomobject]@{
                onboarding  = [pscustomobject]@{ ParentOuDn = 'OU=Users,OU=Managed,DC=mock,DC=local'; BaselineGroups = @(); NamePattern = '{0}.{1}' }
                offboarding = [pscustomobject]@{ quarantineOU = 'OU=Quarantine,OU=Managed,DC=mock,DC=local' }
            }
            audit               = [pscustomobject]@{ retentionDays = 90 }
        }
    }

    function Set-AdmanAuditState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
            $script:AuditDegraded = $false
        } -Config $Config
    }

    function New-AdmanAuditTarget {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Dn, [string]$Sid = 'S-1-5-21-111-222-333-1000')
        [pscustomobject]@{
            DistinguishedName = $Dn
            objectSid         = [System.Security.Principal.SecurityIdentifier]$Sid
            objectClass       = @('top', 'person', 'organizationalPerson', 'user')
        }
    }

    function New-AdmanFakeMutex {
        [CmdletBinding()]
        param()
        $rec = [ordered]@{ WaitOneCalled = 0; ReleaseCalled = 0; Disposed = $false }
        $obj = [pscustomobject]$rec
        $obj | Add-Member -MemberType ScriptMethod -Name WaitOne -Value {
            $this.WaitOneCalled++
            return $true
        }
        $obj | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value {
            $this.ReleaseCalled++
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Disposed = $true
        }
        return $obj
    }

    function New-AdmanFakeStream {
        [CmdletBinding()]
        param()
        $rec = [ordered]@{ FlushArgs = [System.Collections.Generic.List[object]]::new(); Wrote = $false; Disposed = $false }
        $obj = [pscustomobject]$rec
        $obj | Add-Member -MemberType ScriptMethod -Name Write -Value {
            param($bytes, $offset, $count)
            $this.Wrote = $true
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Flush -Value {
            param([bool]$flushToDisk)
            $this.FlushArgs.Add($flushToDisk)
        }
        $obj | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Disposed = $true
        }
        return $obj
    }
}

Describe 'D-05: OUTCOME audit-write failure escalates to Event Log' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
        $script:FakeMutex = New-AdmanFakeMutex
        $script:FakeStream = New-AdmanFakeStream
        $script:OpenCount = 0
    }

    It 'escalates to Write-AdmanEventLog with EventId 9001 and EntryType Error when OUTCOME write fails' {
        Mock New-AdmanAuditMutex -ModuleName adman { $script:FakeMutex }
        Mock Open-AdmanAuditStream -ModuleName adman {
            $script:OpenCount++
            if ($script:OpenCount -eq 1) { return $script:FakeStream }
            throw 'sharing violation on OUTCOME'
        }
        Mock Write-AdmanEventLog -ModuleName adman { }

        $t = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $cid = [guid]::NewGuid().ToString()

        # PENDING write succeeds.
        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
        } -Cid $cid -T $t

        # OUTCOME write fails (Open-AdmanAuditStream throws on second call).
        {
            & (Get-Module adman) {
                param($Cid, $T)
                Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false -WarningAction SilentlyContinue
            } -Cid $cid -T $t
        } | Should -Not -Throw -Because 'an OUTCOME failure must not throw to the caller'

        Should -Invoke Write-AdmanEventLog -ModuleName adman -Times 1 -ParameterFilter {
            $EventId -eq 9001 -and $EntryType -eq 'Error'
        } -Because 'OUTCOME failure escalates to Event Log with EventId 9001 and EntryType Error'
    }
}
