#Requires -Modules Pester
<#
.SYNOPSIS
    DOC-03 help-coverage contract test for all exported adman commands.

.DESCRIPTION
    Imports adman.psd1 and asserts every exported public function has complete
    comment-based help: non-empty .Synopsis and .Description, at least one .Example,
    and a .Parameter entry matching every declared parameter by exact name.

    The test derives the command list from the manifest (FunctionsToExport) so a new
    public function cannot be added without also adding its help block. An optional
    [string[]]$FunctionName script-scope parameter lets sibling plans enforce the
    contract incrementally per category; when omitted, the test covers all exports
    and is the final gate after 05-01a3.
#>

[CmdletBinding()]
param(
    # Optional slice filter used by 05-01a1/05-01a2/05-01a3 to enforce help incrementally.
    [string[]]$FunctionName
)

BeforeDiscovery {
    # Pester 6 does not expose $TestDrive during discovery, so build the PSFramework
    # stub in a uniquely-named temp folder that is cleaned up in AfterAll.
    $script:StubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('adman-help-stub-' + [Guid]::NewGuid().ToString('N'))
    $stubDir = Join-Path $script:StubRoot 'PSFramework'
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
    $env:PSModulePath = "$script:StubRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"

    $script:ModuleName = 'adman'
    $script:TestRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
    $script:ManifestPath = Join-Path (Join-Path $script:TestRoot '..') 'adman.psd1'

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    $script:CommonParams = @(
        'WhatIf','Confirm','Verbose','Debug','ErrorAction','WarningAction','InformationAction',
        'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable'
    )

    # Scoped list for 05-01a2 incremental enforcement of SupportsShouldProcess description coverage.
    $script:AdLifecycleFunctions = @(
        'New-AdmanUser','Disable-AdmanUser','Enable-AdmanUser','Set-AdmanUserPassword',
        'Unlock-AdmanUser','Move-AdmanUser','Disable-AdmanComputer','Enable-AdmanComputer',
        'Move-AdmanComputer','Reset-AdmanComputerAccount'
    )

    $allCommands = @((Get-Module $script:ModuleName).ExportedFunctions.Keys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
    if ($FunctionName -and $FunctionName.Count -gt 0) {
        $script:Commands = @($allCommands | Where-Object { $FunctionName -contains $_ })
    } else {
        $script:Commands = $allCommands
    }
}

AfterAll {
    Get-Module 'adman' | Remove-Module -Force -ErrorAction SilentlyContinue
    if ($script:StubRoot -and (Test-Path -LiteralPath $script:StubRoot)) {
        Remove-Item -LiteralPath $script:StubRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'adman public help coverage' -Tag 'Unit' -ForEach $script:Commands {

    BeforeAll {
        $command = $_
        $help = Get-Help $command -Full -ErrorAction SilentlyContinue
        $cmdInfo = Get-Command $command -ErrorAction SilentlyContinue

        $SupportsShouldProcess = $false
        foreach ($attr in $cmdInfo.ScriptBlock.Attributes) {
            if ($attr -is [System.Management.Automation.CmdletBindingAttribute] -and $attr.SupportsShouldProcess) {
                $SupportsShouldProcess = $true
                break
            }
        }
    }

    It '<_> has a non-empty .Synopsis' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        [string]$help.Synopsis | Should -Not -Match '^\s*$'
    }

    It '<_> has a non-empty .Description' {
        $help.Description | Should -Not -BeNullOrEmpty
        $text = if ($help.Description -is [System.Collections.IEnumerable] -and $help.Description -isnot [string]) {
            ($help.Description | ForEach-Object { $_.Text }) -join "`n"
        } else {
            [string]$help.Description.Text
        }
        $text | Should -Not -BeNullOrEmpty
        $text | Should -Not -Match '^\s*$'
    }

    It '<_> has at least one .Example with code text' {
        $examples = $help.Examples.Example
        $examples | Should -Not -BeNullOrEmpty
        $exampleList = @($examples)
        $exampleList.Count | Should -BeGreaterOrEqual 1
        $first = $exampleList[0]
        [string]($first.Code) | Should -Not -BeNullOrEmpty
        [string]($first.Code) | Should -Not -Match '^\s*$'
    }

    $hasParamBlock = $null -ne $cmdInfo -and $null -ne $cmdInfo.ScriptBlock -and
        $null -ne $cmdInfo.ScriptBlock.Ast.Body.ParamBlock -and
        $cmdInfo.ScriptBlock.Ast.Body.ParamBlock.Parameters.Count -gt 0

    It '<_> has .Parameter help for every declared non-common parameter' -Skip:(-not $hasParamBlock) {
        $commonParams = @(
            'WhatIf','Confirm','Verbose','Debug','ErrorAction','WarningAction','InformationAction',
            'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable'
        )

        $declared = @($cmdInfo.ScriptBlock.Ast.Body.ParamBlock.Parameters.Name.VariablePath.UserPath |
            Where-Object { $commonParams -notcontains $_ } |
            Sort-Object -Unique)

        $helpParams = @()
        if ($help.Parameters -and $help.Parameters.Parameter) {
            $paramList = @($help.Parameters.Parameter)
            $helpParams = @($paramList.Name |
                Where-Object { $commonParams -notcontains $_ } |
                Sort-Object -Unique)
        }

        # Sets must match exactly (declared vs documented).
        Compare-Object -ReferenceObject $declared -DifferenceObject $helpParams | Should -BeNullOrEmpty
    }

    It '<_> .Description mentions at least two of -WhatIf/confirm/audit when state-changing' -Skip:(-not $SupportsShouldProcess -or ($script:AdLifecycleFunctions -notcontains $command)) {
        $text = if ($help.Description -is [System.Collections.IEnumerable] -and $help.Description -isnot [string]) {
            ($help.Description | ForEach-Object { $_.Text }) -join "`n"
        } else {
            [string]$help.Description.Text
        }
        $text | Should -Not -BeNullOrEmpty
        $lower = $text.ToLowerInvariant()
        $terms = 0
        if ($lower -like '*whatif*') { $terms++ }
        if ($lower -like '*confirm*') { $terms++ }
        if ($lower -like '*audit*') { $terms++ }
        $terms | Should -BeGreaterOrEqual 2 -Because 'state-changing help must document -WhatIf, confirmation, and audit behavior'
    }
}
