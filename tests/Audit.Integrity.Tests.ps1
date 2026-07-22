#Requires -Modules Pester
<#
.SYNOPSIS
    D-05 audit hash-chain integrity tests (Get-AdmanAuditIntegrity).

.DESCRIPTION
    Proves the tamper-evident hash chain:
      * A valid chain of three records verifies cleanly.
      * Mutating the middle record breaks the chain at line 3 (the mutated record's
        self-hash no longer validates and the next record's prevHash no longer matches).
      * Mutating only the final record breaks at line 3 because its self-hash fails.

    Records are written through the real Write-AdmanAudit path so the on-disk bytes
    are authoritative.
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
}

Describe 'D-05: audit hash-chain integrity' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:AuditDir -Force | Out-Null
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
    }

    It 'verifies a clean chain of three records' {
        $t = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $cid = [guid]::NewGuid().ToString()

        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -Cid $cid -T $t

        $cid2 = [guid]::NewGuid().ToString()
        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -Cid $cid2 -T $t

        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))
        $result = & (Get-Module adman) { param($p) Get-AdmanAuditIntegrity -Path $p } -p $path

        $result.Valid | Should -BeTrue -Because 'an unmodified audit chain must validate'
        $result.Lines | Should -Be 3 -Because 'three records were written'
        $result.BrokenAtLine | Should -Be 0 -Because 'no line is broken'
    }

    It 'detects tampering of the middle record' {
        $t = New-AdmanAuditTarget -Dn 'CN=Bob,OU=Managed,DC=mock,DC=local'
        $cid = [guid]::NewGuid().ToString()

        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -Cid $cid -T $t

        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))
        $lines = @(Get-Content -LiteralPath $path)
        # Mutate the middle record's hash so line 3's prevHash linkage fails (chain test).
        $zeroHash = '0' * 64
        $replacement = '"hash":"' + $zeroHash + '"'
        $mutated = $lines[1] -replace '"hash":"[0-9a-f]{64}"', $replacement
        $lines[1] = $mutated
        $lines | Set-Content -LiteralPath $path -Encoding UTF8

        $result = & (Get-Module adman) { param($p) Get-AdmanAuditIntegrity -Path $p } -p $path

        $result.Valid | Should -BeFalse -Because 'mutating a record breaks the chain'
        $result.BrokenAtLine | Should -Be 3 -Because 'line 3''s prevHash points at the tampered line 2'
    }

    It 'detects tampering of the final record by self-hash mismatch' {
        $t = New-AdmanAuditTarget -Dn 'CN=Carol,OU=Managed,DC=mock,DC=local'
        $cid = [guid]::NewGuid().ToString()

        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'PENDING' -Reason '' -WhatIf:$false
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -Cid $cid -T $t

        $path = Join-Path $script:AuditDir ('audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd'))
        $lines = @(Get-Content -LiteralPath $path)
        $mutated = $lines[2] -replace '"reason":""', '"reason":"TAMPERED"'
        $lines[2] = $mutated
        $lines | Set-Content -LiteralPath $path -Encoding UTF8

        $result = & (Get-Module adman) { param($p) Get-AdmanAuditIntegrity -Path $p } -p $path

        $result.Valid | Should -BeFalse -Because 'mutating the final record breaks its own hash'
        $result.BrokenAtLine | Should -Be 3 -Because 'line 3 is the tampered final record'
    }
}
