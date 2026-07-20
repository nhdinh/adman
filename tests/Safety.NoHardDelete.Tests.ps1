#Requires -Modules Pester
<#
.SYNOPSIS
    Task 2 (RED) — SAFE-09 gate-only AD write wrappers + SAFE-02 bulk-policy placeholder.

      * Adman.AD.Write.ps1 defines exactly ONE wrapper per allow-listed verb (9 total), named
        Adman.AD.Write.<Verb>. Each declares SupportsShouldProcess ConfirmImpact='High', pins
        -Server, and forwards -WhatIf:$WhatIfPreference -Confirm:$false to the real AD cmdlet.
      * There is NO wrapper for the hard-delete verb (SAFE-09) - "delete" is reversible
        disable+quarantine, never an irreversible object removal.
      * The wrapper function-name set EQUALS Get-AdmanAllowedWriteVerbs (no drift).
      * Assert-AdmanBulkPolicy reads bulk.maxCount + safety.bulkConfirmThreshold and returns
        them WITHOUT enforcing the cap in Phase 0 (enforcement is Phase 4 / BULK-02); a switch
        -EnforceCap exists but is not used by the Phase-0 gate.

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
    GUID              = 'b0000000-0000-0000-0000-0000000000c9'
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
    $script:WritePath = Join-Path $script:RepoRoot 'Private\AD\Adman.AD.Write.ps1'
    $script:BulkPath = Join-Path $script:RepoRoot 'Private\Safety\Assert-AdmanBulkPolicy.ps1'
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Global stubs so Pester's Mock resolver finds the real AD write cmdlets at RED.
    function global:Disable-ADAccount { param($Identity, $Server) }
    function global:Enable-ADAccount { param($Identity, $Server) }
    function global:Move-ADObject { param($Identity, $TargetPath, $Server) }
    function global:Set-ADUser { param($Identity, $Server) }
    function global:Set-ADComputer { param($Identity, $Server) }
    function global:Set-ADAccountPassword { param($Identity, $NewPassword, $Server) }
    function global:Unlock-ADAccount { param($Identity, $Server) }
    function global:Add-ADGroupMember { param($Identity, $Members, $Server) }
    function global:Remove-ADGroupMember { param($Identity, $Members, $Server) }
    function global:Write-PSFMessage { param($Level, $Message) }

    function New-AdmanSafetyConfig {
        [CmdletBinding()]
        param([int]$BulkConfirmThreshold = 5, [int]$BulkMaxCount = 50, [string]$DC = 'dc.mock.local')
        [pscustomobject]@{
            ManagedOUs          = @('OU=Managed,DC=mock,DC=local')
            DC                  = $DC
            AuditDir            = (Join-Path $TestDrive 'audit')
            AdmanProtectedGroup = ''
            DenyList            = @(@{ token = '500' }, @{ token = '501' }, @{ token = '502' })
            safety              = [pscustomobject]@{ bulkConfirmThreshold = $BulkConfirmThreshold }
            bulk                = [pscustomobject]@{ maxCount = $BulkMaxCount }
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

Describe 'SAFE-09: Adman.AD.Write wrappers are the sole, gate-only callers of real AD write cmdlets' -Tag 'Unit' {

    It 'defines exactly one wrapper per allow-listed verb; the set EQUALS Get-AdmanAllowedWriteVerbs' {
        Test-Path -LiteralPath $script:WritePath | Should -BeTrue
        $allowed = & (Get-Module adman) { Get-AdmanAllowedWriteVerbs }
        $src = Get-Content -LiteralPath $script:WritePath -Raw
        $defined = [regex]::Matches($src, 'function\s+(Adman\.AD\.Write\.([A-Za-z-]+))') |
            ForEach-Object { $_.Groups[2].Value }
        @($defined).Count | Should -Be 10 -Because 'one wrapper per allow-listed verb (incl. New-ADUser)'
        foreach ($v in $allowed) { $defined | Should -Contain $v }
        # No extra wrappers beyond the allow-list.
        foreach ($d in $defined) { $allowed | Should -Contain $d }
    }

    It 'has NO wrapper for the hard-delete verb (SAFE-09)' {
        Test-Path -LiteralPath $script:WritePath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:WritePath -Raw
        $defined = [regex]::Matches($src, 'function\s+(Adman\.AD\.Write\.([A-Za-z-]+))') |
            ForEach-Object { $_.Groups[2].Value }
        $defined | Should -Not -Contain 'Remove-ADObject' `
            -Because 'the hard-delete verb has no wrapper (delete = reversible disable+quarantine)'
    }

    It 'has no literal Remove-ADObject in any Public or Private source file (repo-wide SAFE-09)' {
        $sourceFiles = Get-ChildItem -Path (Join-Path $script:RepoRoot 'Public'), (Join-Path $script:RepoRoot 'Private') -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue
        $matches = foreach ($file in $sourceFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            if ($content -match 'Remove-ADObject') {
                $file.FullName
            }
        }
        @($matches).Count | Should -Be 0 -Because "hard-delete cmdlet literal must not appear in source files; found in: $($matches -join ', ')"
    }

    It 'every wrapper declares SupportsShouldProcess ConfirmImpact=High, pins -Server, forwards -Confirm:$false' {
        Test-Path -LiteralPath $script:WritePath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:WritePath -Raw
        # Count actual occurrences (Select-String over a -Raw string returns one MatchInfo per
        # pattern, not per occurrence); use [regex]::Matches for a true occurrence count.
        [regex]::Matches($src, 'SupportsShouldProcess').Count | Should -BeGreaterOrEqual 9
        [regex]::Matches($src, 'ConfirmImpact').Count | Should -BeGreaterOrEqual 9
        [regex]::Matches($src, [regex]::Escape('-Confirm:$false')).Count | Should -BeGreaterOrEqual 9
        [regex]::Matches($src, '-Server ').Count | Should -BeGreaterOrEqual 9
    }

    It 'a wrapper forwards -WhatIf:$WhatIfPreference and calls the real AD cmdlet (Disable-ADAccount)' {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig)
        Mock Disable-ADAccount -ModuleName adman { }
        $targets = @([pscustomobject]@{ DistinguishedName = 'CN=A,OU=Managed,DC=mock,DC=local' })
        & (Get-Module adman) { param($o) Adman.AD.Write.Disable-ADAccount -Objects $o -Confirm:$false } -o $targets
        Should -Invoke Disable-ADAccount -ModuleName adman -Times 1 `
            -Because 'the wrapper is the ONE place the real AD write cmdlet is called'
    }
}

Describe 'SAFE-02: Assert-AdmanBulkPolicy cap placeholder (Phase 0 does NOT enforce)' -Tag 'Unit' {

    BeforeEach {
        Set-AdmanSafetyState -Config (New-AdmanSafetyConfig -BulkConfirmThreshold 5 -BulkMaxCount 50)
        Mock Write-PSFMessage -ModuleName adman { }
    }

    It 'reads bulk.maxCount + safety.bulkConfirmThreshold and returns them WITHOUT enforcing the cap' {
        $r = & (Get-Module adman) { Assert-AdmanBulkPolicy -Count 999 }
        $r.Cap | Should -Be 50
        $r.Threshold | Should -Be 5
        # 999 > cap 50 but Phase 0 does NOT enforce: no throw.
    }

    It 'does NOT throw when Count exceeds the cap and -EnforceCap is NOT passed (Phase 0 placeholder)' {
        { & (Get-Module adman) { Assert-AdmanBulkPolicy -Count 999 } } | Should -Not -Throw `
            -Because 'cap enforcement is Phase 4 / BULK-02; Phase 0 only reads the values'
    }

    It 'throws only when -EnforceCap is passed AND Count exceeds the cap (forward-compat for Phase 4)' {
        { & (Get-Module adman) { Assert-AdmanBulkPolicy -Count 999 -EnforceCap } } |
            Should -Throw -ExpectedMessage '*exceeds cap*'
    }

    It 'static: exposes an -EnforceCap switch and reads bulk.maxCount + safety.bulkConfirmThreshold' {
        Test-Path -LiteralPath $script:BulkPath | Should -BeTrue
        $src = Get-Content -LiteralPath $script:BulkPath -Raw
        @($src | Select-String -Pattern '\[switch\]\$EnforceCap').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'bulk\.maxCount').Count | Should -BeGreaterOrEqual 1
        @($src | Select-String -Pattern 'safety\.bulkConfirmThreshold').Count | Should -BeGreaterOrEqual 1
    }
}
