#Requires -Modules Pester
<#
.SYNOPSIS
    D-05 / FLOW-03 offboarding restore state from archived audit files.

.DESCRIPTION
    Proves that Get-AdmanOffboardingState finds successful offboarding records that
    have been moved into archive\YYYYMM\ folders by Invoke-AdmanAuditRotation, so
    Restore-AdmanQuarantinedUser can still reconstruct the original OU and groups.
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

    function global:Resolve-AdmanTarget { param($Targets) }
}

Describe 'FLOW-03 / D-05: Get-AdmanOffboardingState searches archived audit files' -Tag 'Unit' {

    It 'finds an offboarding record that has been rotated into archive\YYYYMM' {
        $auditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        $archiveDir = Join-Path $auditDir 'archive\202607'
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null

        $userDn = 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $userSid = 'S-1-5-21-111-222-333-1001'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'
        $groups = @('CN=G1,OU=Groups,DC=mock,DC=local', 'CN=G2,OU=Groups,DC=mock,DC=local')

        $rec = [ordered]@{
            tsUtc         = '2026-07-01T10:00:00.0000000Z'
            who           = 'DOMAIN\admin'
            userSid       = 'S-1-5-21-111-222-333-1000'
            what          = 'Start-AdmanUserOffboarding'
            scope         = 'OU=Managed,DC=mock,DC=local'
            target        = $userDn
            targets       = @(@{ dn = $userDn; sid = $userSid; objectClass = 'user' })
            count         = 1
            whatIf        = $false
            result        = 'Success'
            reason        = ''
            correlationId = [guid]::NewGuid().ToString()
            host          = 'TESTHOST'
            psEdition     = 'Desktop'
            moduleVersion = '0.1.0'
            originalOU    = $originalOu
            groups        = $groups
            prevHash      = '0' * 64
        }
        $canonicalJson = $rec | ConvertTo-Json -Compress -Depth 5
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonicalJson)
        $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $hash = -join ($sha | ForEach-Object { $_.ToString('x2') })
        $rec['hash'] = $hash
        $rec | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath (Join-Path $archiveDir 'audit-20260701.jsonl') -Encoding UTF8

        Mock Resolve-AdmanTarget -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = $userDn
                objectSid         = [System.Security.Principal.SecurityIdentifier]$userSid
            }
        }

        $state = & (Get-Module adman) {
            param($Dir, $Identity)
            $script:Config = [pscustomobject]@{ AuditDir = $Dir }
            Get-AdmanOffboardingState -Identity $Identity
        } -Dir $auditDir -Identity 'alice'

        $state | Should -Not -BeNullOrEmpty -Because 'the archived offboarding record must be discoverable'
        $state.OriginalOU | Should -Be $originalOu
        @($state.Groups).Count | Should -Be 2
        $state.Groups[0] | Should -Be $groups[0]
        $state.Groups[1] | Should -Be $groups[1]
    }
}
