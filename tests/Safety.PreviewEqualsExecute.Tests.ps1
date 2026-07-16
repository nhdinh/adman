#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED) — SAFE-10 preview==execute resolver tests + SAFE-09 allow-list data +
    resolver parameter-set validity (C2-H1).

      * Resolve-AdmanTarget materializes the target array ONCE (one Get-ADObject call per
        identity); the gate hands the SAME array to both the preview and the execute path
        (no second Get-ADObject between them).
      * The resolver's -Identity Get-ADObject call binds NO -SearchBase / -SearchScope (the
        Identity parameter set has neither - it has -Partition; an -Identity...-SearchBase mix
        cannot bind and would throw 'Parameter set cannot be resolved' BEFORE safety logic).
        -Server and -Properties are still pinned.
      * Get-AdmanAllowedWriteVerbs returns exactly the 9 allow-listed verbs and does NOT include
        the hard-delete verb (complement of Get-AdmanBannedWriteVerbs).

.NOTES
    Pester 6. PSFramework satisfied by a throwaway 1.14.457 stub on $TestDrive. All AD cmdlets
    mocked (-ModuleName adman); no live domain. Named binding into the module-scope scriptblock.
#>

BeforeAll {
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000c7'
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
    $script:ResolverPath = Join-Path $script:RepoRoot 'Private\Safety\Resolve-AdmanTarget.ps1'
    $script:WriteVerbsPath = Join-Path $script:RepoRoot 'Private\Safety\AdmanWriteVerbs.ps1'
    $script:RuleModule = Join-Path $script:RepoRoot 'rules\AdmanSafetyRules.psm1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
    Import-Module $script:RuleModule -Force -ErrorAction SilentlyContinue

    function global:Get-ADObject { param($Identity, $Properties, $Server, $LDAPFilter) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param([string]$DC = 'dc.mock.local')
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = $DC
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = 5 }
            bulk                = [pscustomobject]@{ maxCount = 50 }
            credentialPolicy    = [pscustomobject]@{ allowRememberMe = $false }
        }
    }

    function Set-AdmanSafetyState {
        [CmdletBinding()]
        param($Config)
        & (Get-Module adman) {
            param($Config)
            $script:Config = $Config
        } -Config $Config
    }
}

Describe 'SAFE-10: Resolve-AdmanTarget materializes the target array once (preview == execute)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig)
    }

    It 'calls Get-ADObject exactly once per identity (one resolver pass, no re-query)' {
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = "CN=$Identity,OU=Managed,DC=mock,DC=local"
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1000'
                objectClass       = @('top', 'person', 'organizationalPerson', 'user')
                memberOf          = @()
            }
        }

        $resolved = & (Get-Module adman) { param($t) Resolve-AdmanTarget -Targets $t } -t @('alice', 'bob', 'carol')

        @($resolved).Count | Should -Be 3
        Should -Invoke Get-ADObject -ModuleName adman -Times 3 -Exactly `
            -Because 'one Get-ADObject per identity; the gate reuses this array for preview AND execute'
    }

    It 'returns the resolved array (the SAME reference the gate hands to preview and execute)' {
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = "CN=$Identity,OU=Managed,DC=mock,DC=local"
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1000'
                objectClass       = @('top', 'person', 'organizationalPerson', 'user')
                memberOf          = @()
            }
        }

        $resolved = & (Get-Module adman) { param($t) Resolve-AdmanTarget -Targets $t } -t @('alice')
        @($resolved).Count | Should -Be 1
        $resolved[0].DistinguishedName | Should -Be 'CN=alice,OU=Managed,DC=mock,DC=local'
    }

    It 'pins -Server and -Properties on the resolver Get-ADObject call' {
        Mock Get-ADObject -ModuleName adman {
            [pscustomobject]@{
                DistinguishedName = "CN=$Identity,OU=Managed,DC=mock,DC=local"
                objectSid         = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-111-222-333-1000'
                objectClass       = @('top', 'person', 'organizationalPerson', 'user')
                memberOf          = @()
            }
        }

        $null = & (Get-Module adman) { param($t) Resolve-AdmanTarget -Targets $t } -t @('alice')
        Should -Invoke Get-ADObject -ModuleName adman -Times 1 -ParameterFilter {
            $Server -eq 'dc.mock.local' -and ($Properties -contains 'objectSid')
        } -Because 'the resolver pins -Server and requests exact -Properties'
    }

    It 'AST: the -Identity Get-ADObject call binds NO -SearchBase / -SearchScope (C2-H1)' {
        Test-Path -LiteralPath $script:ResolverPath | Should -BeTrue
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ResolverPath, [ref]$tokens, [ref]$errors)
        $calls = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Get-ADObject' }, $true)
        $identityCalls = @($calls | Where-Object {
            ($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Identity' })
        })
        $identityCalls.Count | Should -BeGreaterOrEqual 1 -Because 'the resolver looks up by -Identity'
        foreach ($c in $identityCalls) {
            $badParams = @($c.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                ($_.ParameterName -eq 'SearchBase' -or $_.ParameterName -eq 'SearchScope')
            }).Count
            $badParams | Should -Be 0 -Because 'the Identity parameter set has neither -SearchBase nor -SearchScope (it has -Partition); mixing them cannot bind (C2-H1)'
        }
    }

    It 'static: resolver pins -Server and -Properties' {
        Test-Path -LiteralPath $script:ResolverPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:ResolverPath -Raw
        @($src | Select-String -Pattern '\-Server ').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern '\-Properties ').Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'SAFE-09: Get-AdmanAllowedWriteVerbs is the 10-verb allow-list (hard-delete excluded)' -Tag 'Unit' {

    It 'returns exactly the 10 allow-listed verbs' {
        $verbs = & (Get-Module adman) { Get-AdmanAllowedWriteVerbs }
        @($verbs).Count | Should -Be 10
        $expected = @(
            'Disable-ADAccount', 'Enable-ADAccount', 'Move-ADObject',
            'Set-ADUser', 'Set-ADComputer', 'Set-ADAccountPassword', 'Unlock-ADAccount',
            'Add-ADGroupMember', 'Remove-ADGroupMember', 'New-ADUser'
        )
        foreach ($v in $expected) { $verbs | Should -Contain $v }
    }

    It 'does NOT include the hard-delete verb (complement of Get-AdmanBannedWriteVerbs)' {
        $verbs = & (Get-Module adman) { Get-AdmanAllowedWriteVerbs }
        $verbs | Should -Not -Contain 'Remove-ADObject'
        # Every allow-listed verb must be in the banned set (the guard bans direct Public/ calls);
        # the hard-delete verb is banned but NOT allow-listed (no wrapper).
        $banned = Get-AdmanBannedWriteVerbs
        foreach ($v in $verbs) { $banned | Should -Contain $v }
        $banned | Should -Contain 'Remove-ADObject'
    }
}
