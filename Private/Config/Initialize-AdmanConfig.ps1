#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize-AdmanConfig - pinned-path, fail-closed config load/validate/seed (CONF-01/02/03,
    D-01/D-04/D-05), plus the single validator (Test-AdmanConfigValid) and single save path
    (Save-AdmanConfig) reused by the Set-/Import-AdmanConfig verbs.

.DESCRIPTION
    Safety invariants enforced here (independent of PSFramework - see D-01):
      * Load reads the explicit file .store/config.json only (Import-PSFConfig -Path, never the
        per-user/per-machine auto-import persistence - Pitfall 7 / T-00-07). The safety values are
        parsed directly from the plain JSON (Get-Content | ConvertFrom-Json) so fail-closed NEVER
        depends on a framework import succeeding.
      * FAIL-CLOSED (CONF-02): empty/missing ManagedOUs, a failed parse/validation, or a failed
        deny-list load THROW before any mutating operation can run - unless -SetupMode (the
        first-run wizard creating the config, D-04), which bypasses ONLY the empty-scope gate.
      * The deny-list is seeded ONCE into a fresh file from config/adman.defaults.json (RID 500/501/
        502, D-05); thereafter the file is the single source of truth (no re-seed).
      * Every save uses ConvertTo-Json -Depth 5 (Pitfall 8). 5.1-safe: read as PSCustomObject and
        index by property (the Core-only hashtable switch is not used). '_comment' keys (annotated example, D-04) are stripped
        before validation so the example validates and never pollutes the runtime config.
#>

Set-StrictMode -Version Latest

function ConvertTo-AdmanCleanConfig {
    <#
    .SYNOPSIS
        Recursively strip '_comment*' annotation keys from a parsed config object (D-04).
        Handles both shapes that configs arrive in: PSCustomObject (ConvertFrom-Json / loader)
        and IDictionary (in-memory ordered hashtable builders / wizard emitter). Primitive leaf
        values (int/bool/long/etc.) are returned UNCHANGED - the prior PSObject.Properties guard
        matched value types and silently collapsed leaves into empty PSCustomObjects (Rule 1 fix).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)]$Node)

    if ($null -eq $Node) { return $null }
    if ($Node -is [string]) { return $Node }
    if ($Node -is [array]) {
        $arr = @()
        foreach ($item in $Node) { $arr += ,(ConvertTo-AdmanCleanConfig -Node $item) }
        # Unary comma emits the array as a single pipeline object so PowerShell does not unroll a
        # one-element array into a scalar on return - arrayness must survive validation.
        return ,$arr
    }
    if ($Node -is [System.Collections.IDictionary]) {
        $clean = [ordered]@{}
        foreach ($key in @($Node.Keys)) {
            if ($key -like '_comment*') { continue }
            $clean[$key] = ConvertTo-AdmanCleanConfig -Node $Node[$key]
        }
        return [pscustomobject]$clean
    }
    if ($Node -is [pscustomobject]) {
        $clean = [ordered]@{}
        foreach ($prop in $Node.PSObject.Properties) {
            if ($prop.Name -like '_comment*') { continue }
            $clean[$prop.Name] = ConvertTo-AdmanCleanConfig -Node $prop.Value
        }
        return [pscustomobject]$clean
    }
    # Leaf (primitive / value type): return unchanged.
    return $Node
}

function Test-AdmanConfigValid {
    <#
    .SYNOPSIS
        Single config validator (structure + required keys + types) consumed by Initialize-/Set-/
        Import-AdmanConfig so a config edit can never weaken scope or the deny-list (T-00-13).
        Reads required-key membership from config/adman.schema.json (one shared schema for the
        wizard emitter and the loader - D-04) and enforces types in PowerShell (5.1-safe).
        Throws a terminating error on the first failure (treated as a load failure).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ModuleRoot
    )

    $schemaPath = Join-Path $ModuleRoot 'config\adman.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        throw "Config schema not found at '$schemaPath'; cannot validate (fail-closed)."
    }
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json

    # Required top-level keys (schema-driven so wizard + loader cannot drift).
    foreach ($key in @($schema.required)) {
        $present = $Config.PSObject.Properties.Name -contains $key
        if (-not $present) { throw "Config validation failed: required key '$key' is missing." }
    }

    # ManagedOUs: array of strings (emptiness is the CONF-02 scope gate, handled by the caller).
    if ($null -ne $Config.ManagedOUs -and -not ($Config.ManagedOUs -is [array])) {
        throw "Config validation failed: 'ManagedOUs' must be an array of DN strings."
    }

    # DenyList: array of { token:string, note:string }. Absent/null is handled by the seed step
    # (D-05) before validation; a present-but-wrong-typed value is a hard failure (CONF-02).
    # Membership-tested (not property-accessed) so Set-StrictMode does not throw when DenyList
    # is absent - this validator is shared by Set-/Import-AdmanConfig which validate directly.
    if ($Config.PSObject.Properties.Name -contains 'DenyList' -and $null -ne $Config.DenyList) {
        if (-not ($Config.DenyList -is [array])) {
            throw "Config validation failed: 'DenyList' must be an array of { token, note } objects."
        }
        foreach ($entry in $Config.DenyList) {
            $hasToken = $entry.PSObject.Properties.Name -contains 'token'
            $hasNote = $entry.PSObject.Properties.Name -contains 'note'
            if (-not $hasToken -or -not $hasNote) {
                throw "Config validation failed: each DenyList entry must have 'token' and 'note'."
            }
            if (-not ($entry.token -is [string]) -or -not ($entry.note -is [string])) {
                throw "Config validation failed: DenyList 'token' and 'note' must be strings."
            }
        }
    }

    # Nested required structure (schema properties.<x>.required).
    if ($null -eq $Config.safety -or $null -eq $Config.safety.bulkConfirmThreshold) {
        throw "Config validation failed: 'safety.bulkConfirmThreshold' is required."
    }
    if ([int]$Config.safety.bulkConfirmThreshold -lt 1) {
        throw "Config validation failed: 'safety.bulkConfirmThreshold' must be >= 1."
    }
    if ($null -eq $Config.bulk -or $null -eq $Config.bulk.maxCount) {
        throw "Config validation failed: 'bulk.maxCount' is required (placeholder; enforced in Phase 4)."
    }
    if ($null -eq $Config.transport -or $null -eq $Config.transport.order -or $null -eq $Config.transport.timeouts) {
        throw "Config validation failed: 'transport.order' and 'transport.timeouts' are required."
    }
    if ($null -eq $Config.transport.timeouts.WinRM -or $null -eq $Config.transport.timeouts.CIM) {
        throw "Config validation failed: 'transport.timeouts.WinRM' and 'transport.timeouts.CIM' are required."
    }
    if ($null -eq $Config.credentialPolicy -or $null -eq $Config.credentialPolicy.allowRememberMe) {
        throw "Config validation failed: 'credentialPolicy.allowRememberMe' is required (non-secret metadata)."
    }
    if (-not ($Config.AuditDir -is [string]) -or -not ($Config.ReportDir -is [string])) {
        throw "Config validation failed: 'AuditDir' and 'ReportDir' must be strings."
    }

    # D-05 security block (schema-required top-level key; the required-keys loop above already
    # refuses when 'security' itself is absent - these checks fire when the block is present but
    # malformed).
    if ($null -eq $Config.security -or $null -eq $Config.security.passwordSource) {
        throw "Config validation failed: 'security.passwordSource' is required."
    }
    if ([string]$Config.security.passwordSource -notin @('Generate', 'Prompt', 'Ask')) {
        throw "Config validation failed: 'security.passwordSource' must be one of Generate, Prompt, Ask."
    }
    if ($null -eq $Config.security.passwordGeneration -or $null -eq $Config.security.passwordGeneration.length) {
        throw "Config validation failed: 'security.passwordGeneration.length' is required."
    }
    if ([int]$Config.security.passwordGeneration.length -lt 8) {
        throw "Config validation failed: 'security.passwordGeneration.length' must be >= 8."
    }
    # OPTIONAL mustChangeAtNextLogon (shipped default $true): when present, must be a boolean.
    if ($Config.security.PSObject.Properties.Name -contains 'mustChangeAtNextLogon' -and
        $null -ne $Config.security.mustChangeAtNextLogon -and
        -not ($Config.security.mustChangeAtNextLogon -is [bool])) {
        throw "Config validation failed: 'security.mustChangeAtNextLogon' must be a boolean when present."
    }

    return $true
}

function Save-AdmanConfig {
    <#
    .SYNOPSIS
        Single save path for the adman config: serialize with ConvertTo-Json -Depth 5 (Pitfall 8)
        and write to the explicit -Path. Reused by the seed step and the Set-/Export-AdmanConfig
        verbs so nested safety keys can never be silently truncated (T-00-14).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Path
    )

    if ($PSCmdlet.ShouldProcess($Path, 'Save adman config')) {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        $json = ConvertTo-Json -InputObject $Config -Depth 5
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -ErrorAction Stop
    }
}

function Initialize-AdmanConfig {
    <#
    .SYNOPSIS
        Load, validate, seed, and publish the adman config to $script:Config (fail-closed).
    .PARAMETER SetupMode
        First-run wizard/init mode (D-04): bypasses ONLY the empty-ManagedOUs fail-closed gate so
        the wizard can write an empty-scope config; still validates structure and performs NO AD
        mutation.
    #>
    [CmdletBinding()]
    param([switch]$SetupMode)

    $script:ConfigLoaded = $false
    if (-not $script:StorePath) { $script:StorePath = '.store' }
    $path = Join-Path $script:StorePath 'config.json'

    # From Private/Config -> repo root (two parents up): home of config/adman.{schema,defaults}.json.
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    # Bootstrap a truly fresh file from the shipped defaults (the ONLY place the deny-list seed is
    # written, D-05). A present-but-malformed file is NOT overwritten - it must throw below.
    if (-not (Test-Path -LiteralPath $path)) {
        $defaultsPath = Join-Path $moduleRoot 'config\adman.defaults.json'
        $defaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
        $defaults = ConvertTo-AdmanCleanConfig -Node $defaults
        Save-AdmanConfig -Config $defaults -Path $path -Confirm:$false
    }

    # Direct parse of the plain JSON (5.1-safe: read as PSCustomObject, no Core-only hashtable switch). The safety values
    # come from THIS object - never from a framework import - so fail-closed is framework-independent.
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to load adman config from '$path': $($_.Exception.Message)"
    }

    $config = ConvertTo-AdmanCleanConfig -Node $parsed

    # Seed the deny-list once when absent (D-05); the file is the source of truth thereafter.
    # Membership-tested (not property-accessed) so Set-StrictMode does not throw on a NoDenyList file.
    if (-not ($config.PSObject.Properties.Name -contains 'DenyList')) {
        $defaultsPath = Join-Path $moduleRoot 'config\adman.defaults.json'
        $seed = (Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json).DenyList
        $seed = ConvertTo-AdmanCleanConfig -Node $seed
        $config | Add-Member -MemberType NoteProperty -Name DenyList -Value $seed -Force
        Save-AdmanConfig -Config $config -Path $path -Confirm:$false
    }

    # Validate (throws on failure = load failure), then the CONF-02 scope gate.
    Test-AdmanConfigValid -Config $config -ModuleRoot $moduleRoot | Out-Null

    if (-not $SetupMode) {
        $scopeCount = @($config.ManagedOUs).Count
        if ($scopeCount -lt 1) {
            throw "FAIL-CLOSED: managed-OU scope (ManagedOUs) is empty; refusing to permit any mutating operation until at least one managed-OU root is configured."
        }
    }

    # PSFramework config backbone (D-01): pinned with -Path, never the auto-import persistence. The
    # result is NOT used for any safety decision (those came from the direct parse above), so a
    # non-envelope/plain file can never weaken scope or fail-open (Pitfall 7 / T-00-07).
    try { Import-PSFConfig -Path $path -ErrorAction SilentlyContinue } catch { }

    $script:Config = $config
    $script:ConfigLoaded = $true
    return $true
}
