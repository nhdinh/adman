# Positive control (SAFE-08): a Public-scoped verb that calls an AD write cmdlet directly.
# The guard MUST flag this when pointed at it directly. It intentionally contains a banned
# verb by design; it is excluded from the repo-wide recurse lint because the custom rule
# scopes to the real Public/ tree and excludes tests/ (see PSScriptAnalyzerSettings.psd1).
function Set-FixtureUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Identity)

    if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADUser (direct call - banned in Public/)')) {
        Set-ADUser -Identity $Identity -Description 'direct write (banned in Public/)'
    }
}
