#Requires -Version 5.1
<#
.SYNOPSIS
    adman SAFE-08 custom PSScriptAnalyzer rule + single-sourced banned-verb data.

.DESCRIPTION
    Single source of truth for the AD write cmdlet set that MUST NOT be called directly from
    any Public/ verb (they must route through the private, non-exported gate Invoke-AdmanMutation).
    The same banned list drives both:
      * the PSScriptAnalyzer custom rule (Measure-AdmanPublicWriteSafety) wired via
        PSScriptAnalyzerSettings.psd1 -> CustomRulePath, and
      * the Pester AST guard (tests/Safety.Gate.Tests.ps1) which imports Get-AdmanBannedWriteVerbs.
    Scope is the real module Public/ tree only; tests/Fixtures/** (positive controls) are
    deliberately excluded from the repo-wide recurse lint and are exercised by pointing the
    detection at them directly (see tests/). This file is the allowlisted home of the banned
    literals (SAFE-09 includes Remove-ADObject, the hard-delete verb, which has no wrapper).
#>

Set-StrictMode -Version Latest

# Single source of truth (imported by tests/Safety.Gate.Tests.ps1 via Get-AdmanBannedWriteVerbs).
$script:AdmanBannedWriteVerbs = @(
    'Set-ADUser'
    'Set-ADComputer'
    'Set-ADObject'
    'Set-ADAccountPassword'
    'Disable-ADAccount'
    'Enable-ADAccount'
    'Unlock-ADAccount'
    'Move-ADObject'
    'New-ADUser'
    'New-ADComputer'
    'Add-ADGroupMember'
    'Remove-ADGroupMember'
    'Add-ADPrincipalGroupMembership'
    'Remove-ADObject'   # SAFE-09: hard-delete verb - must appear NOWHERE in Public/
)

function Get-AdmanBannedWriteVerbs {
    <#
    .SYNOPSIS
        Return the banned AD write cmdlet set (single source of truth for the SAFE-08 guards).
    #>
    [CmdletBinding()]
    param()
    return $script:AdmanBannedWriteVerbs
}

# Single source of truth for the banned LOCAL write cmdlet set (D-02). Public/ verbs must
# route local writes through Invoke-AdmanLocalMutation, never call these directly.
$script:AdmanBannedLocalWriteVerbs = @(
    'New-LocalUser'
    'Disable-LocalUser'
    'Enable-LocalUser'
    'Set-LocalUser'
    'Remove-LocalUser'
    'Add-LocalGroupMember'
    'Remove-LocalGroupMember'
)

function Get-AdmanBannedLocalWriteVerbs {
    <#
    .SYNOPSIS
        Return the banned LocalAccounts write cmdlet set (D-02; single source of truth).
    #>
    [CmdletBinding()]
    param()
    return $script:AdmanBannedLocalWriteVerbs
}

function Test-AdmanIsPublicScope {
    <#
    .SYNOPSIS
        True if a path lives in the real module Public/ tree (Public/ AND NOT under tests/).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $p = $Path.Replace('/', '\')
    return ($p -match '\\Public\\') -and ($p -notmatch '\\tests\\')
}

function Find-AdmanBannedHit {
    <#
    .SYNOPSIS
        Pure (scope-agnostic) detection: return banned AD write invocations found in an Ast.
    .DESCRIPTION
        Walks CommandAst nodes (GetCommandName, with the RESEARCH L304 fallback to
        CommandElements[0].Extent.Text and a token-grep for Invoke-Expression / '& $cmd'
        dynamic invocation). Alias resolution via Get-Alias is best-effort and never triggers
        module auto-load (Get-Alias reads the in-session alias table only), so the guard stays
        RSAT-agnostic/offline (T-00-11) and never loads the real ActiveDirectory module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)][System.Management.Automation.Language.Token[]]$Tokens,
        [Parameter(Mandatory)][string]$SourceText,
        [Parameter(Mandatory)][string[]]$Banned
    )

    $hits = New-Object System.Collections.ArrayList

    $calls = $Ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)

    foreach ($cmd in $calls) {
        $name = $cmd.GetCommandName()
        if (-not $name) {
            # L304: dynamic invocation '& $cmd' -> first element text
            $name = $cmd.CommandElements[0].Extent.Text
        }
        if (-not $name) { continue }

        $resolved = $name
        # Best-effort alias resolution that CANNOT auto-import the real RSAT ActiveDirectory
        # module: Get-Alias reads only the in-session alias table (a name -> target-name string
        # map) and never loads the target module. The previous Get-Command probe auto-loaded
        # RSAT as a side effect, breaking offline/RSAT-agnostic behavior (T-00-11) and the
        # "import must not load ActiveDirectory" test invariant. Name-based matching below
        # ($Banned -contains $name) remains the primary signal; this only catches aliases like
        # 'sau' -> Set-ADUser that an operator defined earlier in the same session.
        $aliasInfo = Get-Alias -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($aliasInfo) {
            $def = $aliasInfo.Definition
            if ([string]::IsNullOrWhiteSpace($def) -and $aliasInfo.ResolvedCommand) {
                $def = $aliasInfo.ResolvedCommand.Name
            }
            if (-not [string]::IsNullOrWhiteSpace($def)) { $resolved = $def }
        }

        if ($Banned -contains $name -or $Banned -contains $resolved) {
            [void]$hits.Add([pscustomobject]@{
                    Name      = $name
                    Resolved  = $resolved
                    Extent    = $cmd.Extent
                    StartLine = $cmd.Extent.StartLineNumber
                    Reason    = 'direct AD write call'
                })
        }
    }

    # L304 token-grep: dynamic invocation patterns a naive AST pass misses.
    $hasInvokeExpression = $calls | Where-Object { $_.GetCommandName() -eq 'Invoke-Expression' } |
        Select-Object -First 1
    $hasAmpersand = $Tokens | Where-Object { $_.Kind -eq 'Ampersand' } | Select-Object -First 1
    $bannedInSource = $Banned | Where-Object { $SourceText -match [regex]::Escape($_) } |
        Select-Object -First 1

    if (($hasInvokeExpression -or $hasAmpersand) -and $bannedInSource) {
        $anchor = if ($hasInvokeExpression) { $hasInvokeExpression.Extent } else { $hasAmpersand.Extent }
        [void]$hits.Add([pscustomobject]@{
                Name      = [string]$bannedInSource
                Resolved  = [string]$bannedInSource
                Extent    = $anchor
                StartLine = $anchor.StartLineNumber
                Reason    = 'dynamic/Invoke-Expression AD write (token-grep)'
            })
    }

    return $hits
}

function Test-AdmanBannedWriteAst {
    <#
    .SYNOPSIS
        Parse a file and return banned AD write invocations (scope-agnostic, pure detection).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $src = Get-Content -LiteralPath $Path -Raw
    return (Find-AdmanBannedHit -Ast $ast -Tokens $tokens -SourceText $src -Banned (Get-AdmanBannedWriteVerbs))
}

function Invoke-AdmanScopedGuard {
    <#
    .SYNOPSIS
        Scoped guard: return banned AD write hits only when the file is in the real Public/ tree.
    .DESCRIPTION
        Mirrors the PSScriptAnalyzer custom rule's scope gating: files under tests/ (including the
        tests/Fixtures/** positive controls) and under Private/ are out of scope and return empty.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-AdmanIsPublicScope -Path $Path)) { return @() }
    return (Test-AdmanBannedWriteAst -Path $Path)
}

function Measure-AdmanPublicWriteSafety {
    <#
    .SYNOPSIS
        PSScriptAnalyzer custom rule: flag banned AD write cmdlets invoked from the Public/ tree.
    .DESCRIPTION
        Discovered by PSScriptAnalyzer via the ScriptBlockAst parameter. Emits an Error
        DiagnosticRecord per banned CommandAst, scoped to the real Public/ tree (excludes tests/).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$Ast
    )

    $file = $Ast.Extent.File
    if (-not $file) { return @() }
    if (-not (Test-AdmanIsPublicScope -Path $file)) { return @() }

    # PSScriptAnalyzer invokes a ScriptBlockAst rule once per ScriptBlockAst node (root AND every
    # nested function body). FindAll(...,$true) already recurses the whole tree, so only emit on
    # the file-level (root) AST to avoid duplicate diagnostics for the same line.
    if ($null -ne $Ast.Parent) { return @() }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Ast.Extent.Text, [ref]$tokens, [ref]$errors)
    $hits = Find-AdmanBannedHit -Ast $ast -Tokens $tokens -SourceText $Ast.Extent.Text `
        -Banned (Get-AdmanBannedWriteVerbs)

    $ruleName = 'Measure-AdmanPublicWriteSafety'
    $severity = [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Error
    $records = New-Object System.Collections.ArrayList
    foreach ($h in $hits) {
        $msg = "SAFE-08: Public/ verb calls banned AD write cmdlet '$($h.Name)' ($($h.Reason)); route writes through Invoke-AdmanMutation."
        $rec = New-Object -TypeName 'Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord' `
            -ArgumentList $msg, $h.Extent, $ruleName, $severity, $file, $ruleName, $null
        [void]$records.Add($rec)
    }
    return $records
}

Export-ModuleMember -Function @(
    'Get-AdmanBannedWriteVerbs'
    'Get-AdmanBannedLocalWriteVerbs'
    'Test-AdmanIsPublicScope'
    'Find-AdmanBannedHit'
    'Test-AdmanBannedWriteAst'
    'Invoke-AdmanScopedGuard'
    'Measure-AdmanPublicWriteSafety'
)
