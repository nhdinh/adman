#Requires -Version 5.1
Set-StrictMode -Version Latest

function Export-AdmanConfig {
    <#
    .SYNOPSIS
        Export-AdmanConfig - write the loaded config to a plain-JSON file (CONF-03, D-01).
    .DESCRIPTION
        State-changing verb (ShouldProcess, ConfirmImpact='High'). Serializes the loaded $script:Config
        to a plain-JSON file with ConvertTo-Json -Depth 5 (Pitfall 8 / T-00-14) so nested safety keys
        can never be silently truncated. The plain file written here is the CONF-03 round-trip source
        of truth that Initialize-AdmanConfig parses directly.

        No PSFramework mirror file is written by this function; Import-AdmanConfig loads the plain-JSON
        file directly and mirrors to the framework backbone from that authoritative source (Pitfall 7 /
        T-00-07). Keeping the export surface plain-JSON only prevents stale .psf.json siblings from
        drifting out of sync with the safety file.
    .PARAMETER Path
        Destination plain-JSON path; defaults to $script:StorePath\config.json. A caller-supplied path
        may be used for backup.

    .EXAMPLE
        Export-AdmanConfig -Path 'C:\backups\adman-config.json'
        Exports the loaded config to a plain-JSON backup file.
    #>

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

        # WR-04 fix: the in-memory config has had its paths absolutized against the module root
        # during load. For a portable export, relativize AuditDir and ReportDir back to the
        # module root before serialization so the backup can be imported on another host.
        $exportCfg = $script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        foreach ($key in @('AuditDir', 'ReportDir')) {
            $p = $exportCfg.$key
            if ($p -is [string] -and $p.StartsWith($moduleRoot)) {
                $exportCfg.$key = $p.Substring($moduleRoot.Length).TrimStart('\', '/')
            }
        }

        # Authoritative CONF-03 plain-JSON write (the loader parses THIS file).
        $json = ConvertTo-Json -InputObject $exportCfg -Depth 5
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -ErrorAction Stop
    }
}
