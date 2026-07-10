# Positive control (SAFE-08 token-grep, RESEARCH L304): a Public-scoped verb that hides an AD
# write behind Invoke-Expression so a naive AST pass (GetCommandName only) misses it. The
# guard's token-grep fallback MUST still flag it.
function Set-FixtureUserDynamic {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Identity)

    if ($PSCmdlet.ShouldProcess($Identity, 'Invoke-Expression Set-ADUser (dynamic - banned)')) {
        Invoke-Expression "Set-ADUser -Identity $Identity -Description 'dynamic write (banned)'"
    }
}
