#Requires -Modules Pester
<#
.SYNOPSIS
    Task 1 (RED/GREEN) tests for the shipped config artifacts: schema + defaults + TRACKED
    annotated example. Enforces CONF-05 (no secret fields/values; .store/ gitignored; example
    tracked OUTSIDE .store/), CONF-02 (fresh install fails closed: empty ManagedOUs), and D-04
    (one shared schema; '_comment' keys the loader strips).

.NOTES
    No-secret rule (review concern C2-M1): uses a REAL regex (-match) per key-name and a
    secret-value scan - NEVER Select-String -SimpleMatch (which literal-matches a pipe pattern
    and false-passes). The metadata key credentialPolicy.allowRememberMe and the DenyList[].token
    key are non-secret and explicitly allow-listed; the bare substring 'credential' is NOT banned.
    Pure file/JSON checks - does NOT import the adman module or PSFramework.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ConfigDir = Join-Path $script:RepoRoot 'config'
    $script:SchemaPath = Join-Path $script:ConfigDir 'adman.schema.json'
    $script:DefaultsPath = Join-Path $script:ConfigDir 'adman.defaults.json'
    $script:ExamplePath = Join-Path $script:ConfigDir 'adman.example.json'
    $script:GitignorePath = Join-Path $script:RepoRoot '.gitignore'

    # Secret-name regex (case-insensitive): password|secret|apiKey|privateKey as a bounded token.
    # Applied per-key with -match (NEVER -SimpleMatch). 'credential' and 'token' are NOT in the set.
    $script:SecretNameRegex = '(^|[^A-Za-z])(password|secret|apiKey|privateKey)([^A-Za-z]|$)'

    # Explicit non-secret allow-list (review C2-M1): present in the schema, must NOT be flagged.
    $script:AllowedNonSecretNames = @('credentialPolicy', 'allowRememberMe', 'token')
}

# Recursively yield every property NAME in a JSON object graph (PSCustomObject / arrays / scalars).
function Get-AdmanObjectPropertyName {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Node)

    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($item in $Node) { Get-AdmanObjectPropertyName -Node $item }
        return
    }
    $props = $Node.PSObject.Properties
    if ($null -eq $props) { return }
    foreach ($p in $props) {
        $p.Name
        Get-AdmanObjectPropertyName -Node $p.Value
    }
}

# Yield string VALUES whose immediate property name is a literal-value carrier
# (default/enum/examples/const) - the places a hard-coded secret would actually live.
function Get-AdmanLiteralStringValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Node)

    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($item in $Node) { Get-AdmanLiteralStringValue -Node $item }
        return
    }
    $props = $Node.PSObject.Properties
    if ($null -eq $props) { return }
    foreach ($p in $props) {
        if ($p.Name -in @('default', 'enum', 'examples', 'const')) {
            foreach ($v in @($p.Value)) {
                if ($v -is [string]) { $v }
            }
        }
        Get-AdmanLiteralStringValue -Node $p.Value
    }
}

Describe 'CONF-05 no-secret config artifacts (Task 1)' -Tag 'Unit' {

    It 'ships the three config artifacts under config/ (schema, defaults, example)' {
        Test-Path -LiteralPath $script:SchemaPath | Should -BeTrue
        Test-Path -LiteralPath $script:DefaultsPath | Should -BeTrue
        Test-Path -LiteralPath $script:ExamplePath | Should -BeTrue
    }

    It 'schema parses and contains the non-secret allow-listed keys (whitelist is meaningful)' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json
        $names = @(Get-AdmanObjectPropertyName -Node $schema)
        # Whitelist is exercised: these non-secret keys ARE present ...
        $names | Should -Contain 'credentialPolicy'
        $names | Should -Contain 'allowRememberMe'
        $names | Should -Contain 'token'
        # ... yet none of them matches the secret-name regex (bare 'credential'/'token' not banned).
        $flagged = @($names | Where-Object {
                ($_ -match $script:SecretNameRegex) -and ($_ -notin $script:AllowedNonSecretNames)
            })
        $flagged | Should -BeNullOrEmpty -Because "schema must define no secret key-names; flagged: $($flagged -join ',')"
    }

    It 'schema contains no secret VALUES under any literal-value carrier' {
        $schema = Get-Content -LiteralPath $script:SchemaPath -Raw | ConvertFrom-Json
        $values = @(Get-AdmanLiteralStringValue -Node $schema)
        $flagged = @($values | Where-Object { $_ -match $script:SecretNameRegex })
        $flagged | Should -BeNullOrEmpty -Because "no secret value under any key; flagged: $($flagged -join ',')"
    }

    It 'positive-control schema with a banned key IS flagged (rule exercises both directions)' {
        $fixture = Join-Path $TestDrive 'bad.schema.json'
        @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "ManagedOUs": { "type": "array" },
    "password":   { "type": "string", "default": "hunter2" }
  }
}
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8
        $bad = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json
        $names = @(Get-AdmanObjectPropertyName -Node $bad)
        $flagged = @($names | Where-Object {
                ($_ -match $script:SecretNameRegex) -and ($_ -notin $script:AllowedNonSecretNames)
            })
        $flagged | Should -Not -BeNullOrEmpty -Because 'a schema with a password key must be rejected'
        $flagged | Should -Contain 'password'
    }

    It 'no-secret check uses a real regex (-match / Where-Object), never -SimpleMatch' {
        $self = Get-Content -LiteralPath $PSCommandPath -Raw
        $self | Should -Match '-match'
        $self | Should -Match 'Where-Object'
        # -SimpleMatch literal-matches a pipe pattern and false-passes; it must not appear here.
        $self | Should -Not -Match '-SimpleMatch'
    }
}

Describe 'CONF-02 shipped defaults fail closed (Task 1)' -Tag 'Unit' {

    It 'defaults parse and encode a fail-closed fresh install' {
        $d = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
        @($d.ManagedOUs).Count | Should -Be 0 -Because 'empty ManagedOUs => fresh install fails closed (CONF-02)'
        [int]$d.safety.bulkConfirmThreshold | Should -Be 5
        [bool]$d.credentialPolicy.allowRememberMe | Should -BeFalse
    }

    It 'defaults seed the deny-list with RID tokens 500/501/502 labeled starter, not exhaustive' {
        $d = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
        $tokens = @($d.DenyList | ForEach-Object { $_.token })
        $tokens | Should -Contain '500'
        $tokens | Should -Contain '501'
        $tokens | Should -Contain '502'
        $notes = @($d.DenyList | ForEach-Object { $_.note })
        ($notes -join '|') | Should -Match 'starter, not exhaustive'
    }
}

Describe 'D-04 annotated example is tracked JSON outside .store/ (Task 1)' -Tag 'Unit' {

    It 'example is valid JSON containing at least one _comment key and is NOT under .store/' {
        Test-Path -LiteralPath $script:ExamplePath | Should -BeTrue
        $script:ExamplePath | Should -Not -Match '[\\/]\.store[\\/]'
        $comments = @(Select-String -LiteralPath $script:ExamplePath -Pattern '"_comment"')
        $comments.Count | Should -BeGreaterOrEqual 1
    }

    It 'example first _comment documents the CONF-05 path reconciliation (tracked, not .store/)' {
        $raw = Get-Content -LiteralPath $script:ExamplePath -Raw
        # The very first "_comment" entry must mention CONF-05 and the tracked-not-.store decision.
        $first = (Select-String -LiteralPath $script:ExamplePath -Pattern '"_comment"' | Select-Object -First 1).Line
        $first | Should -Match 'CONF-05'
        $first | Should -Match 'tracked'
        $raw | Should -Match 'tracked outside|tracked OUTSIDE|not under \.store|tracked, not \.store|gitignored'
    }
}

Describe 'CONF-05 .store/ gitignore + untracked (Task 1)' -Tag 'Unit' {

    It '.gitignore lists .store/ and git tracks nothing under .store/' {
        $hits = @(Select-String -LiteralPath $script:GitignorePath -Pattern '^\.store/')
        $hits.Count | Should -BeGreaterOrEqual 1
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git) {
            $tracked = & git -C $script:RepoRoot ls-files .store
            @($tracked).Count | Should -Be 0 -Because 'CONF-05: nothing under .store/ may be tracked'
        }
    }
}
