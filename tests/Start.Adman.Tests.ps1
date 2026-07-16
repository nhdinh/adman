#Requires -Modules Pester
<#
.SYNOPSIS
    Start-Adman dispatcher contract tests for Phase 2 (separator rendering,
    FixedParameters merge).

.DESCRIPTION
    Tests the two Start-Adman changes landed in Plan 02-06:

      * SEPARATOR SKIP: menu entries with Verb=$null are rendered as plain text
        lines WITHOUT a number prefix; the numbered selection list contains ONLY
        entries with a non-null Verb.
      * FIXEDPARAMETERS MERGE (MEDIUM #6 review fix): when the operator selects
        the "Enable local user" entry, the dispatched params contain Enable=$true
        WITHOUT prompting; the FixedParameters hashtable is merged into $params
        AFTER Read-AdmanActionParams returns and BEFORE & $Verb @params.

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:StartAdmanPath = Join-Path $script:RepoRoot 'Public/Start-Adman.ps1'
    $script:MenuDefPath = Join-Path $script:RepoRoot 'Private/Menu/Get-AdmanMenuDefinition.ps1'
    $script:ReadParamsPath = Join-Path $script:RepoRoot 'Private/Menu/Read-AdmanActionParams.ps1'
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d6'
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

    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}

Describe 'START-01: separator entries render as plain text (no number prefix)' -Tag 'Unit' {

    It 'separator labels appear in the Write-Host stream but NOT as numbered items' {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        # Quit immediately — we only want to capture the menu render.
        $global:answers = @('Q')
        $global:answerIdx = 0
        $global:writeHostLines = New-Object System.Collections.ArrayList
        Mock -ModuleName adman Read-Host { $global:answers[$global:answerIdx++] }
        Mock -ModuleName adman Write-Host {
            param($Object, $ForegroundColor)
            [void]$global:writeHostLines.Add([string]$Object)
        }
        Mock -ModuleName adman Initialize-Adman {
            & (Get-Module adman) {
                $script:Capability = [pscustomobject]@{
                    RsatPresent       = $true
                    DomainReachable   = $true
                    AuditWritable     = $true
                    RecycleBinEnabled = $true
                    RightsSufficient  = $true
                    WinRM             = $true
                    CimDcom           = $false
                }
            }
        }

        { Start-Adman } | Should -Not -Throw

        # Assert each separator label appears as a plain (unnumbered) line.
        $separatorLabels = @('--- User writes ---', '--- Computer writes ---', '--- Local writes ---', '--- Group membership ---')
        foreach ($label in $separatorLabels) {
            $exactMatch = @($global:writeHostLines | Where-Object { $_ -eq $label })
            $exactMatch.Count | Should -BeGreaterThan 0 -Because "separator '$label' must render as a plain text line"
            # The label must NOT appear with a number prefix.
            $numberedMatch = @($global:writeHostLines | Where-Object { $_ -match "^\d+\.\s+$([regex]::Escape($label))$" })
            $numberedMatch.Count | Should -Be 0 -Because "separator '$label' must NOT be numbered"
        }
    }

    It 'numbered selection list contains ONLY entries with a non-null Verb' {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        $global:answers = @('Q')
        $global:answerIdx = 0
        $global:writeHostLines = New-Object System.Collections.ArrayList
        Mock -ModuleName adman Read-Host { $global:answers[$global:answerIdx++] }
        Mock -ModuleName adman Write-Host {
            param($Object, $ForegroundColor)
            [void]$global:writeHostLines.Add([string]$Object)
        }
        Mock -ModuleName adman Initialize-Adman {
            & (Get-Module adman) {
                $script:Capability = [pscustomobject]@{
                    RsatPresent       = $true
                    DomainReachable   = $true
                    AuditWritable     = $true
                    RecycleBinEnabled = $true
                    RightsSufficient  = $true
                    WinRM             = $true
                    CimDcom           = $false
                }
            }
        }

        { Start-Adman } | Should -Not -Throw

        # Collect all numbered lines from the menu render.
        $numberedLines = @($global:writeHostLines | Where-Object { $_ -match '^\d+\.\s+' })
        $menuDef = Get-AdmanMenuDefinition
        $selectableCount = @($menuDef | Where-Object { $null -ne $_.Verb }).Count
        $numberedLines.Count | Should -Be $selectableCount -Because 'numbered items must equal non-separator entries'

        # Assert no numbered line corresponds to a separator label.
        foreach ($line in $numberedLines) {
            $line | Should -Not -Match '^---' -Because "separator entries must not be numbered"
        }
    }
}

Describe 'START-02: FixedParameters merge (MEDIUM #6 review fix)' -Tag 'Unit' {

    It 'selecting "Enable local user" dispatches with Enable=$true WITHOUT prompting for it' {
        . $script:MenuDefPath
        $menuDef = Get-AdmanMenuDefinition
        $enableEntry = $menuDef | Where-Object { $_.Label -eq 'Enable local user' }
        $enableEntry | Should -Not -BeNullOrEmpty

        # Compute the selection number for the Enable local user entry.
        $selectableIdx = 0
        $enableSelection = 0
        for ($i = 0; $i -lt @($menuDef).Count; $i++) {
            if ($null -ne $menuDef[$i].Verb) {
                $selectableIdx++
                if ($menuDef[$i].Label -eq 'Enable local user') {
                    $enableSelection = $selectableIdx
                    break
                }
            }
        }
        $enableSelection | Should -BeGreaterThan 0

        # Mock: operator selects the Enable local user entry, supplies Name='luser',
        # then B at the output-format prompt, then Q at the top-level menu.
        $global:answers = @([string]$enableSelection, 'luser', 'B', 'Q')
        $global:answerIdx = 0
        Mock -ModuleName adman Read-Host { $global:answers[$global:answerIdx++] }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Initialize-Adman {
            & (Get-Module adman) {
                $script:Capability = [pscustomobject]@{
                    RsatPresent       = $true
                    DomainReachable   = $true
                    AuditWritable     = $true
                    RecycleBinEnabled = $true
                    RightsSufficient  = $true
                    WinRM             = $true
                    CimDcom           = $false
                }
                $script:Config = [pscustomobject]@{
                    ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                    security   = [pscustomobject]@{
                        passwordGeneration = [pscustomobject]@{ length = 20 }
                    }
                }
            }
        }

        # Capture the params Set-AdmanLocalUser receives.
        $global:capturedParams = $null
        Mock -ModuleName adman Set-AdmanLocalUser {
            param($Name, $Enable, $Disable, $ComputerName, $Force)
            $global:capturedParams = @{
                Name        = $Name
                Enable      = $Enable
                Disable     = $Disable
                BoundParams = $PSBoundParameters
            }
            return @()
        }

        { Start-Adman } | Should -Not -Throw

        $global:capturedParams | Should -Not -BeNull
        $global:capturedParams.Name | Should -Be 'luser'
        # The FixedParameters merge MUST inject Enable=$true into the splat.
        $global:capturedParams.BoundParams.ContainsKey('Enable') | Should -BeTrue -Because 'FixedParameters must inject Enable into the dispatched params'
        [bool]$global:capturedParams.BoundParams['Enable'] | Should -BeTrue
        # Disable must NOT be present (the operator picked Enable, not Disable).
        $global:capturedParams.BoundParams.ContainsKey('Disable') | Should -BeFalse
    }

    It 'selecting "Disable local user" dispatches with Disable=$true WITHOUT prompting for it' {
        . $script:MenuDefPath
        $menuDef = Get-AdmanMenuDefinition

        $selectableIdx = 0
        $disableSelection = 0
        for ($i = 0; $i -lt @($menuDef).Count; $i++) {
            if ($null -ne $menuDef[$i].Verb) {
                $selectableIdx++
                if ($menuDef[$i].Label -eq 'Disable local user') {
                    $disableSelection = $selectableIdx
                    break
                }
            }
        }
        $disableSelection | Should -BeGreaterThan 0

        $global:answers = @([string]$disableSelection, 'luser', 'B', 'Q')
        $global:answerIdx = 0
        Mock -ModuleName adman Read-Host { $global:answers[$global:answerIdx++] }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Initialize-Adman {
            & (Get-Module adman) {
                $script:Capability = [pscustomobject]@{
                    RsatPresent       = $true
                    DomainReachable   = $true
                    AuditWritable     = $true
                    RecycleBinEnabled = $true
                    RightsSufficient  = $true
                    WinRM             = $true
                    CimDcom           = $false
                }
                $script:Config = [pscustomobject]@{
                    ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                    security   = [pscustomobject]@{
                        passwordGeneration = [pscustomobject]@{ length = 20 }
                    }
                }
            }
        }

        $global:capturedParams = $null
        Mock -ModuleName adman Set-AdmanLocalUser {
            param($Name, $Enable, $Disable, $ComputerName, $Force)
            $global:capturedParams = @{
                Name        = $Name
                Enable      = $Enable
                Disable     = $Disable
                BoundParams = $PSBoundParameters
            }
            return @()
        }

        { Start-Adman } | Should -Not -Throw

        $global:capturedParams | Should -Not -BeNull
        $global:capturedParams.Name | Should -Be 'luser'
        $global:capturedParams.BoundParams.ContainsKey('Disable') | Should -BeTrue
        [bool]$global:capturedParams.BoundParams['Disable'] | Should -BeTrue
        $global:capturedParams.BoundParams.ContainsKey('Enable') | Should -BeFalse
    }

    It 'when an entry has both PromptSpec and FixedParameters, dispatched params contain BOTH' {
        . $script:MenuDefPath
        $menuDef = Get-AdmanMenuDefinition
        $enableEntry = $menuDef | Where-Object { $_.Label -eq 'Enable local user' }

        # The Enable local user entry has PromptSpec for Name AND FixedParameters for Enable.
        $enableEntry.PromptSpec.Count | Should -BeGreaterThan 0
        $enableEntry.FixedParameters | Should -Not -BeNull

        $selectableIdx = 0
        $enableSelection = 0
        for ($i = 0; $i -lt @($menuDef).Count; $i++) {
            if ($null -ne $menuDef[$i].Verb) {
                $selectableIdx++
                if ($menuDef[$i].Label -eq 'Enable local user') {
                    $enableSelection = $selectableIdx
                    break
                }
            }
        }

        $global:answers = @([string]$enableSelection, 'testuser', 'B', 'Q')
        $global:answerIdx = 0
        Mock -ModuleName adman Read-Host { $global:answers[$global:answerIdx++] }
        Mock -ModuleName adman Write-Host { }
        Mock -ModuleName adman Initialize-Adman {
            & (Get-Module adman) {
                $script:Capability = [pscustomobject]@{
                    RsatPresent       = $true
                    DomainReachable   = $true
                    AuditWritable     = $true
                    RecycleBinEnabled = $true
                    RightsSufficient  = $true
                    WinRM             = $true
                    CimDcom           = $false
                }
                $script:Config = [pscustomobject]@{
                    ManagedOUs = @('OU=Managed,DC=mock,DC=local')
                    security   = [pscustomobject]@{
                        passwordGeneration = [pscustomobject]@{ length = 20 }
                    }
                }
            }
        }

        $global:capturedParams = $null
        Mock -ModuleName adman Set-AdmanLocalUser {
            param($Name, $Enable, $Disable, $ComputerName, $Force)
            $global:capturedParams = @{
                BoundParams = $PSBoundParameters
            }
            return @()
        }

        { Start-Adman } | Should -Not -Throw

        # Both the prompted Name AND the fixed Enable must be present.
        $global:capturedParams.BoundParams.ContainsKey('Name') | Should -BeTrue
        $global:capturedParams.BoundParams['Name'] | Should -Be 'testuser'
        $global:capturedParams.BoundParams.ContainsKey('Enable') | Should -BeTrue
    }
}
