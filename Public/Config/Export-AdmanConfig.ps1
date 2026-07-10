#Requires -Version 5.1
<#
.SYNOPSIS
    Export-AdmanConfig - write the loaded config to a plain-JSON file (CONF-03, D-01).
.DESCRIPTION
    State-changing verb (ShouldProcess, ConfirmImpact='High'). Serializes the loaded $script:Config
    to a plain-JSON file with ConvertTo-Json -Depth 5 (Pitfall 8 / T-00-14) so nested safety keys
    can never be silently truncated. The plain file written here is the CONF-03 round-trip source
    of truth that Initialize-AdmanConfig parses directly.

    For the PSFramework config backbone (D-01) a SEPARATE mirror file (<name>.psf.json) is written
    via a path-pinned framework export - NEVER the plain safety file, so a framework envelope can never
    overwrite and corrupt the file the loader depends on (CONF-03). The mirror is best-effort and
    is NOT consumed for any safety decision. The per-user auto-import persistence-registration cmdlet
    is never called for safety values (Pitfall 7 / T-00-07).
.PARAMETER Path
    Destination plain-JSON path; defaults to $script:StorePath\config.json. A caller-supplied path
    may be used for backup.
#>
function Export-AdmanConfig {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Path)

    if (-not $script:ConfigLoaded) { Initialize-AdmanConfig | Out-Null }
    if (-not $Path) {
        if (-not $script:StorePath) { $script:StorePath = '.store' }
        $Path = Join-Path $script:StorePath 'config.json'
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Export adman config (plain JSON, -Depth 5)')) {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        # Authoritative CONF-03 plain-JSON write (the loader parses THIS file).
        $json = ConvertTo-Json -InputObject $script:Config -Depth 5
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -ErrorAction Stop

        # D-01 backbone mirror (best-effort; sibling extension, never the safety file).
        try {
            $mirror = [System.IO.Path]::ChangeExtension($Path, '.psf.json')
            Export-PSFConfig -Path $mirror -Module adman -ErrorAction SilentlyContinue
        } catch { }
    }
}
