#Requires -Version 5.1
<#
.SYNOPSIS
    AdmanAuditIO - the private, mockable I/O seams for the audit writer (Write-AdmanAudit).

.DESCRIPTION
    These three non-exported wrappers are the ONLY surface Write-AdmanAudit uses for its
    mutex / file / event-log operations. They exist so the fail-closed behavior can be proven
    under test WITHOUT mocking raw .NET statics (which Pester cannot mock cleanly) and WITHOUT
    touching the real filesystem for the fail-closed cases.

      * New-AdmanAuditMutex   - creates/returns the Global\adman-audit named mutex (the
                                cross-process serialization point for concurrent writers).
      * Open-AdmanAuditStream - opens the given path Append / Write / Read-share and returns the
                                stream (readers may tail the file while a writer appends).
      * Write-AdmanEventLog   - wraps Write-EventLog in try/catch; degrades to Write-Warning when
                                the 'adman' source is unregistered (Initialize-Adman registers it
                                best-effort; RESEARCH L415 / A2).

    Write-AdmanAudit calls ONLY these seams for its mutex/file/eventlog operations. Tests mock
    these seams (-ModuleName adman) to drive the throw / flush / ordering behavior.
#>

Set-StrictMode -Version Latest

function New-AdmanAuditMutex {
    <#
    .SYNOPSIS
        Create and return the Global\adman-audit named mutex (the audit serialization point).
    #>
    [CmdletBinding()]
    [OutputType([System.Threading.Mutex])]
    param()

    # Global\ namespace => cross-session on the same host; the single writer-serialization point.
    return [System.Threading.Mutex]::new($false, 'Global\adman-audit')
}

function Open-AdmanAuditStream {
    <#
    .SYNOPSIS
        Open the given audit JSONL path Append / Write / Read-share and return the stream.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Append (never truncate), Write access, Read share (a monitor may tail while we append).
    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
}

function Write-AdmanEventLog {
    <#
    .SYNOPSIS
        Best-effort write to the Windows Application event log; degrade to Write-Warning when the
        'adman' source is unregistered (never throw - this is the OUTCOME-failure escalation path).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$EventId,
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Information')]
        [string]$EntryType,
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        Write-EventLog -LogName Application -Source 'adman' -EventId $EventId `
            -EntryType $EntryType -Message $Message -ErrorAction Stop
    } catch {
        # Source unregistered (or no rights): degrade to a console warning - never throw.
        Write-Warning "adman event-log write skipped (source 'adman' unregistered): $Message"
    }
}
