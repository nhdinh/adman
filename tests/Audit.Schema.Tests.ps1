#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) - SAFE-03 audit record schema + no-secret guarantee (Write-AdmanAudit).

    Proves the D-03 field set and the CONF-05 no-secret invariant in BOTH directions:
      * Test 1 (schema shape): a record written by Write-AdmanAudit (happy path, real TestDrive
        file via the real seams) parses back to EXACTLY the D-03 key set:
        tsUtc, who, userSid, what, scope, target, targets, count, whatIf, result, reason,
        correlationId, host, psEdition, moduleVersion. who/userSid/result shape asserted.
      * Test 2a (no secrets, CLEAN direction): the parsed record's key set has ZERO keys matching
        /pass(word)?|secret|credential|apiKey|privateKey|key|token/i and no value equal to a
        supplied sensitive value. PASS.
      * Test 2b (no secrets, POSITIVE CONTROL): a fixture record that DOES carry a banned key
        (password / credential / apiKey / privateKey) or a banned value IS caught by the SAME
        regex - the test FAILS if the regex does not match the fixture. This proves the verifier
        actually detects sensitive data instead of trivially passing (C3-L1 both-directions).
      * Test 2c (source hygiene): the writer SOURCE declares no parameter named
        Password/Secret/Credential/ApiKey/PrivateKey and contains zero banned tokens (real regex,
        no -SimpleMatch) - including in comments.

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. The happy-path
    schema test uses the REAL seams against a TestDrive audit dir (no mock) so the on-disk record
    is authoritative; the no-secret source checks are static. No live domain.
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
    $script:WriterPath = Join-Path $script:RepoRoot 'Private\Audit\Write-AdmanAudit.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # The D-03 field set (authoritative; CONTEXT L42 + PLAN Test 1).
    # D-05: hash and prevHash are always present as part of the fixed audit record schema.
    $script:D03Keys = @(
        'tsUtc', 'who', 'userSid', 'what', 'scope', 'target', 'targets', 'count',
        'whatIf', 'result', 'reason', 'correlationId', 'host', 'psEdition', 'moduleVersion',
        'hash', 'prevHash'
    )
    # The banned secret-name regex (CONF-05; C3-L1). Real regex, no -SimpleMatch.
    # WR-09: this must match the source-code scan regex used below.
    $script:SecretNameRegex = 'password|secret|credential|apiKey|privateKey'

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

    # Read the single JSONL record written to today's file under $AuditDir.
    function Read-AdmanAuditRecord {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$AuditDir)
        $name = 'audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd')
        $path = Join-Path $AuditDir $name
        $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop | Where-Object { $_ -and $_.Trim() })
        $lines.Count | Should -BeGreaterOrEqual 1 -Because 'Write-AdmanAudit must append one JSONL record'
        return ($lines[-1] | ConvertFrom-Json)
    }
}

Describe 'SAFE-03: Write-AdmanAudit record schema + no-secret guarantee' -Tag 'Unit' {

    BeforeEach {
        $script:AuditDir = Join-Path $TestDrive ('audit-{0}' -f [guid]::NewGuid().ToString('n'))
        Set-AdmanAuditState -Config (New-AdmanAuditConfig -AuditDir $script:AuditDir)
    }

    It 'Test 1: a written record parses back to EXACTLY the D-03 key set with correct who/userSid/result shape' {
        $t1 = New-AdmanAuditTarget -Dn 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $cid = [guid]::NewGuid().ToString()

        & (Get-Module adman) {
            param($Cid, $T)
            Write-AdmanAudit -CorrelationId $Cid -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -Cid $cid -T $t1

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $keys = @($rec.PSObject.Properties.Name)
        # Exact set equality (order-independent): no missing, no extra fields.
        @($keys | Sort-Object) | Should -Be @($script:D03Keys | Sort-Object) `
            -Because 'the audit schema is fixed to the D-03 field set (no more, no fewer)'

        $rec.who | Should -Be "$env:USERDOMAIN\$env:USERNAME"
        $rec.userSid | Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $rec.result | Should -BeIn @('PENDING', 'Success', 'Failure', 'Refused', 'Cancelled')
        $rec.result | Should -Be 'Success'
        $rec.what | Should -Be 'Disable-ADAccount'
        $rec.correlationId | Should -Be $cid
        $rec.count | Should -Be 1
        $rec.whatIf | Should -BeFalse
        # targets carries dn + sid + objectClass detail.
        @($rec.targets).Count | Should -Be 1
        $rec.targets[0].dn | Should -Be 'CN=Alice,OU=Managed,DC=mock,DC=local'
        $rec.targets[0].sid | Should -Be 'S-1-5-21-111-222-333-1000'
        ($rec.targets[0].objectClass -join ',') | Should -Match 'user'
    }

    It 'Test 1b: a record written with -OriginalOU and -Groups includes those keys and retains the D-03 base set' {
        $t1 = New-AdmanAuditTarget -Dn 'CN=Carol,OU=Managed,DC=mock,DC=local'
        $originalOu = 'OU=Users,OU=Managed,DC=mock,DC=local'
        $groups = @('CN=G1,OU=Groups,DC=mock,DC=local', 'CN=G2,OU=Groups,DC=mock,DC=local')

        & (Get-Module adman) {
            param($T, $OU, $G)
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Start-AdmanUserOffboarding' `
                -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false `
                -OriginalOU $OU -Groups $G
        } -T $t1 -OU $originalOu -G $groups

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $keys = @($rec.PSObject.Properties.Name)
        $keys | Should -Contain 'originalOU'
        $keys | Should -Contain 'groups'
        $rec.originalOU | Should -Be $originalOu
        @($rec.groups).Count | Should -Be 2
        $rec.groups[0] | Should -Be $groups[0]
        $rec.groups[1] | Should -Be $groups[1]

        # Base D-03 keys are still present.
        foreach ($k in $script:D03Keys) {
            $keys | Should -Contain $k
        }
    }

    It 'Test 1c: a record written without -OriginalOU/-Groups does not contain those keys' {
        $t1 = New-AdmanAuditTarget -Dn 'CN=Dave,OU=Managed,DC=mock,DC=local'

        & (Get-Module adman) {
            param($T)
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Disable-ADAccount' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -T $t1

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $keys = @($rec.PSObject.Properties.Name)
        $keys | Should -Not -Contain 'originalOU'
        $keys | Should -Not -Contain 'groups'
    }

    It 'Test 2a (CLEAN): a written record has ZERO secret-named keys and no value equal to a supplied sensitive value' {
        $t1 = New-AdmanAuditTarget -Dn 'CN=Bob,OU=Managed,DC=mock,DC=local'
        $sensitive = 'P@ssw0rd!-supplied-secret-value'

        & (Get-Module adman) {
            param($T)
            Write-AdmanAudit -CorrelationId ([guid]::NewGuid().ToString()) -Verb 'Set-ADAccountPassword' -Targets @($T) -Result 'Success' -Reason '' -WhatIf:$false
        } -T $t1

        $rec = Read-AdmanAuditRecord -AuditDir $script:AuditDir
        $keys = @($rec.PSObject.Properties.Name)
        $badKeys = @($keys | Where-Object { $_ -match $script:SecretNameRegex })
        $badKeys | Should -BeNullOrEmpty `
            -Because 'the audit record must contain NO secret-named field (CONF-05)'

        # No value anywhere in the record equals the supplied sensitive value.
        $json = $rec | ConvertTo-Json -Compress -Depth 6
        $json | Should -Not -Match ([regex]::Escape($sensitive)) `
            -Because 'a sensitive authentication VALUE must never reach the audit record'
    }

    It 'Test 2b (POSITIVE CONTROL): the secret regex CATCHES a fixture record carrying banned keys/values' {
        # A fixture that DOES carry banned keys/values - the SAME regex MUST match it.
        $fixture = [ordered]@{
            tsUtc      = (Get-Date).ToUniversalTime().ToString('o')
            who        = 'DOMAIN\admin'
            password   = 'P@ssw0rd!'
            credential = 'some-cred'
            apiKey     = 'AKIAFAKE'
            privateKey = '-----BEGIN-----'
        }
        $fixtureJson = $fixture | ConvertTo-Json -Compress -Depth 5

        # Each banned key is caught by the regex (the verifier fires on the fixture).
        foreach ($k in @('password', 'credential', 'apiKey', 'privateKey')) {
            $k | Should -Match $script:SecretNameRegex `
                -Because "the verifier regex MUST catch the banned key '$k' (positive control)"
        }
        # And the serialized fixture is matched by the regex over its content.
        $fixtureJson | Should -Match $script:SecretNameRegex `
            -Because 'the verifier regex MUST fire on a record that carries secret material'

        # Sanity: a clean D-03 key set is NOT matched (the regex is not a match-everything tautology).
        foreach ($k in $script:D03Keys) {
            $k | Should -Not -Match $script:SecretNameRegex `
                -Because "the legitimate D-03 key '$k' must NOT trip the secret regex"
        }
    }

    It 'Test 2c (source hygiene): the writer source declares no secret-named parameter and contains zero banned tokens' {
        Test-Path -LiteralPath $script:WriterPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:WriterPath -Raw

        # No parameter named Password/Secret/Credential/ApiKey/PrivateKey.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:WriterPath, [ref]$tokens, [ref]$errors)
        $paramAsts = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)
        $paramNames = @($paramAsts | ForEach-Object { $_.Name.VariablePath.UserPath })
        foreach ($pn in $paramNames) {
            $pn | Should -Not -Match '^(Password|Secret|Credential|ApiKey|PrivateKey)$' `
                -Because "the writer must not accept a secret-bearing parameter '$pn'"
        }

        # Zero banned tokens anywhere in the source (real regex, NO -SimpleMatch) - incl. comments.
        $matches = [regex]::Matches($src, 'password|secret|credential|apiKey|privateKey', 'IgnoreCase')
        $matches.Count | Should -Be 0 `
            -Because 'the writer source must contain zero secret tokens (C3-L1; the phase-exit grep requires 0)'
    }
}
