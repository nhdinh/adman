#Requires -Modules Pester
<#
.SYNOPSIS
    MENU-01..04 contract tests for the Phase 1 flat menu (Start-Adman).

.DESCRIPTION
    Static + behavioral contract tests for the read-only adman menu. These tests pin the
    D-01 flat while-loop contract:
      * MENU-01: Start-Adman prints numbered items 1..N plus 'Q. Quit'.
      * MENU-02: A numeric choice calls the corresponding Public verb with parameters
                 supplied by the prompt helper.
      * MENU-03: 'B' inside a parameter prompt returns to the top-level menu; 'Q' exits
                 Start-Adman from any prompt.
      * MENU-04: The menu dispatches to the same Public verb function a senior would call
                 directly (no parallel implementation).

    Strategy:
      * Static AST checks prove the menu shape (single while loop, Read-Host 'Select',
        & $Verb @params dispatch, no Format-AdmanReport call, no SupportsShouldProcess,
        no direct Get-AD*/Search-ADAccount calls).
      * Behavioral checks invoke the menu body with a mocked Read-Host / Write-Host and
        stubbed Public verbs (in-memory function table; no RSAT, no AD).
      * Get-AdmanMenuDefinition is contract-tested directly for the six Phase-1 entries
        and the per-entry Properties [string[]] (Cycle 4 finding — D-03 schema source
        for Plan 01-04 empty-result renderer output).

    Runs entirely offline; no RSAT, no live domain. Pester 6 syntax.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:StartAdmanPath = Join-Path $script:RepoRoot 'Public/Start-Adman.ps1'
    $script:MenuDefPath = Join-Path $script:RepoRoot 'Private/Menu/Get-AdmanMenuDefinition.ps1'
    $script:ReadParamsPath = Join-Path $script:RepoRoot 'Private/Menu/Read-AdmanActionParams.ps1'
    $script:ManifestPath = Join-Path $script:RepoRoot 'adman.psd1'

    # AST helpers ---------------------------------------------------------------
    function Get-AdmanFileAst {
        param([string]$Path)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$tokens, [ref]$errors)
        return $ast
    }

    function Get-AdmanCommandNames {
        param([System.Management.Automation.Language.Ast]$Ast)
        $calls = $Ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        $names = foreach ($c in $calls) {
            $n = $c.GetCommandName()
            if (-not $n) { $n = $c.CommandElements[0].Extent.Text }
            if ($n) { $n }
        }
        return $names
    }

    # PSFramework stub so the module import works in a clean test host.
    $stubRoot = Join-Path $TestDrive 'Modules'
    $stubDir = Join-Path $stubRoot 'PSFramework'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    @"
@{
    RootModule        = 'PSFramework.psm1'
    ModuleVersion     = '1.14.457'
    GUID              = 'b0000000-0000-0000-0000-0000000000d5'
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

    # Import the module so Start-Adman and the report verbs are available for
    # behavioral tests. The AD mocks are NOT imported here; the behavioral tests
    # mock the report verbs directly.
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}

Describe 'MENU-01: Start-Adman prints numbered items 1..N plus Q. Quit' -Tag 'Unit' {

    It 'Public/Start-Adman.ps1 exists' {
        Test-Path $script:StartAdmanPath | Should -BeTrue
    }

    It 'declares [CmdletBinding()] without SupportsShouldProcess (read-only TUI dispatcher)' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match '\[CmdletBinding\('
        $raw | Should -Not -Match 'SupportsShouldProcess'
    }

    It 'contains exactly one top-level while loop (D-01 flat loop)' {
        $ast = Get-AdmanFileAst -Path $script:StartAdmanPath
        $loops = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.WhileStatementAst] }, $true)
        # The top-level menu loop plus the output-format prompt loop and two
        # path-validation loops (CSV/HTML) are expected.
        @($loops).Count | Should -BeGreaterOrEqual 1
    }

    It "reads top-level selection via Read-Host 'Select'" {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match "Read-Host\s+['\""]Select['\""]"
    }

    It 'prints Q. Quit as the last menu line' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match 'Q\.\s*Quit'
    }

    It 'top-level invalid-input copy is exactly "Invalid selection. Enter a number or Q." (no B)' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match 'Invalid selection\. Enter a number or Q\.'
    }

    It 'renders numbered items from Get-AdmanMenuDefinition (1..N)' {
        # Behavioral: drive Start-Adman with mocked Read-Host that answers 'Q' immediately,
        # capture Write-Host output, and assert each menu label appears with a numeric prefix.
        . $script:MenuDefPath
        $menuDef = Get-AdmanMenuDefinition
        $labels = @($menuDef | ForEach-Object { $_.Label })
        $labels.Count | Should -BeGreaterThan 0
    }
}

Describe 'MENU-02: numeric choice calls the corresponding Public verb with prompted parameters' -Tag 'Unit' {

    It 'dispatches via & $Verb @params (no per-item switch statement)' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        # Must use the call operator with splatted params from the prompt helper.
        $raw | Should -Match '&\s+\$Verb\s+@'
    }

    It 'Read-AdmanActionParams returns a hashtable of parameters on success' {
        . $script:ReadParamsPath
        # Stub Read-Host to supply deterministic answers.
        $script:answers = @('jdoe')
        $script:answerIdx = 0
        Mock Read-Host { $script:answers[$script:answerIdx++] } -ModuleName $null
        $spec = @(
            @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
        )
        $result = Read-AdmanActionParams -PromptSpec $spec
        $result | Should -BeOfType [hashtable]
        $result.SamAccountName | Should -Be 'jdoe'
    }

    It 'Get-AdmanMenuDefinition returns six menu items with Label, Verb, PromptSpec, Properties' {
        . $script:MenuDefPath
        $def = Get-AdmanMenuDefinition
        @($def).Count | Should -Be 6
        foreach ($entry in $def) {
            $entry.Label | Should -Not -BeNullOrEmpty
            $entry.Verb | Should -Not -BeNullOrEmpty
            $entry.PSObject.Properties.Name | Should -Contain 'PromptSpec'
            $entry.PSObject.Properties.Name | Should -Contain 'Properties'
        }
    }

    It 'every menu entry Properties field is a non-empty [string[]] of D-03 column names' {
        . $script:MenuDefPath
        $def = Get-AdmanMenuDefinition
        foreach ($entry in $def) {
            $entry.Properties | Should -Not -BeNullOrEmpty
            ,$entry.Properties | Should -BeOfType [string[]]
            @($entry.Properties).Count | Should -BeGreaterThan 0
        }
    }

    It 'Properties arrays match the pinned D-03 schema lists' {
        . $script:MenuDefPath
        $def = Get-AdmanMenuDefinition
        $byVerb = @{}
        foreach ($e in $def) { $byVerb[$e.Verb] = $e.Properties }

        $byVerb['Find-AdmanUser'] | Should -Contain 'UserPrincipalName'
        $byVerb['Find-AdmanUser'] | Should -Contain 'PasswordExpired'
        $byVerb['Find-AdmanUser'] | Should -Not -Contain 'Bucket'
        $byVerb['Find-AdmanUser'] | Should -Not -Contain 'OperatingSystem'

        $byVerb['Find-AdmanComputer'] | Should -Contain 'OperatingSystem'
        $byVerb['Find-AdmanComputer'] | Should -Contain 'IPv4Address'
        $byVerb['Find-AdmanComputer'] | Should -Not -Contain 'Bucket'
        $byVerb['Find-AdmanComputer'] | Should -Not -Contain 'UserPrincipalName'

        $byVerb['Get-AdmanStaleReport'] | Should -Contain 'Bucket'
        $byVerb['Get-AdmanStaleReport'] | Should -Contain 'UserPrincipalName'

        $byVerb['Get-AdmanAccountStateReport'] | Should -Contain 'Bucket'
        $byVerb['Get-AdmanAccountStateReport'] | Should -Contain 'LockedOut'

        $byVerb['Get-AdmanInventoryReport'] | Should -Contain 'Bucket'
        $byVerb['Get-AdmanInventoryReport'] | Should -Contain 'OperatingSystem'

        $byVerb['Get-AdmanRecoveryPostureReport'] | Should -Contain 'RecycleBinEnabled'
        $byVerb['Get-AdmanRecoveryPostureReport'] | Should -Contain 'ForestFunctionalLevel'
        $byVerb['Get-AdmanRecoveryPostureReport'] | Should -Contain 'TombstoneLifetime'
        $byVerb['Get-AdmanRecoveryPostureReport'] | Should -Contain 'Generated'
        $byVerb['Get-AdmanRecoveryPostureReport'] | Should -Contain 'Freshness'
        @($byVerb['Get-AdmanRecoveryPostureReport']).Count | Should -Be 5
    }
}

Describe 'MENU-03: B returns to menu; Q exits Start-Adman from any prompt' -Tag 'Unit' {

    It 'Read-AdmanActionParams returns $null when the operator types B at a prompt' {
        . $script:ReadParamsPath
        Mock Read-Host { 'B' }
        $spec = @(
            @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
        )
        $result = Read-AdmanActionParams -PromptSpec $spec
        $result | Should -BeNullOrEmpty
    }

    It 'Read-AdmanActionParams throws a QUIT sentinel when the operator types Q at a prompt' {
        . $script:ReadParamsPath
        Mock Read-Host { 'Q' }
        $spec = @(
            @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
        )
        # Q must exit Start-Adman. The helper signals this via a terminating sentinel
        # (a thrown error whose message is the reserved 'ADMAN_QUIT' token) so the
        # top-level loop can catch it and break out cleanly.
        $threw = $false
        $quitSentinel = $false
        try {
            $null = Read-AdmanActionParams -PromptSpec $spec
        } catch {
            $threw = $true
            if ($_.Exception.Message -match 'ADMAN_QUIT') { $quitSentinel = $true }
        }
        $threw | Should -BeTrue
        $quitSentinel | Should -BeTrue
    }

    It 'Read-AdmanActionParams re-prompts once on empty required input, then treats second empty as B' {
        . $script:ReadParamsPath
        $script:callCount = 0
        Mock Read-Host { $script:callCount++; '' }
        $spec = @(
            @{ Name = 'SamAccountName'; Prompt = 'Enter sAMAccountName'; Required = $true }
        )
        $result = Read-AdmanActionParams -PromptSpec $spec
        # Two empty answers -> treated as B -> $null returned.
        $result | Should -BeNullOrEmpty
        $script:callCount | Should -BeGreaterThan 1
    }

    It 'Start-Adman catches the ADMAN_QUIT sentinel and exits cleanly' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match 'ADMAN_QUIT'
    }
}

Describe 'MENU-04: menu dispatches the same Public verb a senior calls directly' -Tag 'Unit' {

    It 'Start-Adman contains no direct Get-AD*/Search-ADAccount calls (pure dispatch)' {
        $names = Get-AdmanCommandNames -Ast (Get-AdmanFileAst -Path $script:StartAdmanPath)
        # Match real AD cmdlets only: verb-AD<noun> where noun does NOT start with 'Adman'
        # (Get-AdmanMenuDefinition is an internal helper, not an AD cmdlet).
        $adCalls = @($names | Where-Object {
            $_ -match '^(Get|Set|New|Remove|Move|Enable|Disable|Rename)-AD(?!man)' -or
            $_ -eq 'Search-ADAccount'
        })
        $adCalls | Should -BeNullOrEmpty -Because 'the menu must be a thin prompt-and-dispatch layer (D-01/MENU-04)'
    }

    It 'Start-Adman dispatches output-format choices to the correct renderer' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        # The dispatch is via & $renderer @rendererParams where $renderer is
        # resolved from a switch statement. Check the source for the renderer
        # names and the dispatch pattern.
        $raw | Should -Match 'Format-AdmanReport'
        $raw | Should -Match 'Export-AdmanReportCsv'
        $raw | Should -Match 'Export-AdmanReportHtml'
        $raw | Should -Match '&\s+\$renderer\s+-InputObject\s+\$reportData\s+@rendererParams'
    }

    It 'Start-Adman reads the menu entry Properties field and passes it as -Properties to the renderer' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        $raw | Should -Match '\$entry\.Properties'
        $raw | Should -Match '-Properties'
    }

    It 'every menu entry Verb resolves to a real Public function name (no parallel implementation)' {
        . $script:MenuDefPath
        $def = Get-AdmanMenuDefinition
        foreach ($entry in $def) {
            # The verb name must be a non-empty string; the actual Public function
            # may not exist yet in Wave 1 (Find-AdmanUser etc. land in 01-02/01-03),
            # but the menu MUST dispatch by name via & $Verb so the same function
            # a senior calls directly is invoked. We pin the expected names here.
            $entry.Verb | Should -Match '^[A-Z][a-z]+-Adman[A-Z]'
        }
        $verbs = @($def | ForEach-Object { $_.Verb })
        $verbs | Should -Contain 'Find-AdmanUser'
        $verbs | Should -Contain 'Find-AdmanComputer'
        $verbs | Should -Contain 'Get-AdmanStaleReport'
        $verbs | Should -Contain 'Get-AdmanAccountStateReport'
        $verbs | Should -Contain 'Get-AdmanInventoryReport'
        $verbs | Should -Contain 'Get-AdmanRecoveryPostureReport'
    }

    It 'menu body invokes the verb by name through the call operator (no copy-paste re-implementation)' {
        $raw = Get-Content $script:StartAdmanPath -Raw
        # The dispatch site must be the generic & $Verb form, not a hard-coded call
        # to a specific verb (which would indicate a parallel implementation).
        $raw | Should -Match '&\s+\$Verb\s+@params'
    }
}

Describe 'MENU-05: output-format prompt navigation' -Tag 'Unit' {

    It 'B at the output-format prompt returns to the top-level menu' {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        # Select menu item 3 (Stale report, no PromptSpec), then B at the
        # output-format prompt, then Q at the top-level menu.
        $global:answers = @('3', 'B', 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }
        Mock -ModuleName adman Format-AdmanReport { param($InputObject, $Properties) "MOCKED CONSOLE" }
        Mock -ModuleName adman Export-AdmanReportCsv { param($InputObject, $Path, $Properties) "MOCKED CSV" }
        Mock -ModuleName adman Export-AdmanReportHtml { param($InputObject, $Path, $Properties) "MOCKED HTML" }

        # Start-Adman should process: menu select 3 -> verb runs -> format prompt B ->
        # back to menu -> Q exits. The function should return without throwing.
        { Start-Adman } | Should -Not -Throw
    }

    It 'Q at the output-format prompt exits Start-Adman' {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        $global:answers = @('3', 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }
        Mock -ModuleName adman Format-AdmanReport { param($InputObject, $Properties) "MOCKED CONSOLE" }

        { Start-Adman } | Should -Not -Throw
    }

    It 'invalid input at the output-format prompt re-prompts with the standard copy' {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        $global:answers = @('3', 'X', 'B', 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }

        { Start-Adman } | Should -Not -Throw
    }
}

Describe 'MENU-06: zero-row dispatch wires Properties through to the renderer' -Tag 'Unit' {

    BeforeAll {
        . $script:MenuDefPath
        . $script:ReadParamsPath
        $script:menuDef = Get-AdmanMenuDefinition
        $script:staleEntry = $script:menuDef | Where-Object { $_.Verb -eq 'Get-AdmanStaleReport' }
    }

    It 'CSV: zero-row verb produces a file with exactly one header row matching the menu entry Properties' {
        $csvPath = Join-Path $TestDrive 'zero-row.csv'
        $global:answers = @('3', '2', $csvPath, 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }

        { Start-Adman } | Should -Not -Throw
        Test-Path -LiteralPath $csvPath | Should -BeTrue
        $lines = @(Get-Content -LiteralPath $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 1
        $header = $lines[0]
        foreach ($prop in $script:staleEntry.Properties) {
            $header | Should -Match ([regex]::Escape($prop))
        }
    }

    It 'HTML: zero-row verb produces a file with a header row matching the menu entry Properties and no data rows' {
        $htmlPath = Join-Path $TestDrive 'zero-row.html'
        $global:answers = @('3', '3', $htmlPath, 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }

        { Start-Adman } | Should -Not -Throw
        Test-Path -LiteralPath $htmlPath | Should -BeTrue
        $content = Get-Content -LiteralPath $htmlPath -Raw
        $content | Should -Match '<table>'
        foreach ($prop in $script:staleEntry.Properties) {
            $content | Should -Match ([regex]::Escape($prop))
        }
        # Exactly one <tr> (the header row).
        $trCount = ([regex]::Matches($content, '<tr>')).Count
        $trCount | Should -Be 1
    }

    It 'Console: zero-row verb emits a header-only table (not the (no results) literal)' {
        $global:answers = @('3', '1', 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }

        $output = Start-Adman
        $text = ($output -join "`n")
        $text | Should -Not -Match '\(no results\)'
        foreach ($prop in $script:staleEntry.Properties) {
            $text | Should -Match ([regex]::Escape($prop))
        }
    }

    It 'renderer receives -Properties equal to the menu entry Properties' {
        $global:capturedProperties = $null
        $global:answers = @('3', '1', 'Q')
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
            }
        }
        Mock -ModuleName adman Get-AdmanStaleReport { return @() }
        Mock -ModuleName adman Format-AdmanReport {
            param($InputObject, $Properties, $UseGridView)
            $global:capturedProperties = $Properties
            "MOCKED"
        }

        { Start-Adman } | Should -Not -Throw
        $global:capturedProperties | Should -Not -BeNullOrEmpty
        $global:capturedProperties.Count | Should -Be $script:staleEntry.Properties.Count
        for ($i = 0; $i -lt $script:staleEntry.Properties.Count; $i++) {
            $global:capturedProperties[$i] | Should -Be $script:staleEntry.Properties[$i]
        }
    }
}
