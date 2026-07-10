# Negative control (SAFE-08): a Private-scoped wrapper that legitimately calls an AD write cmdlet.
# The scoped guard (Public/ only) MUST NOT flag this file. Wrappers like this are the ONLY
# sanctioned callers of AD write cmdlets - they live in Private/, never Public/.
function Write-FixtureAdUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$Identity)

    if ($PSCmdlet.ShouldProcess($Identity, 'Set-ADUser (private wrapper - allowed)')) {
        Set-ADUser -Identity $Identity -Description 'via private wrapper (allowed)'
    }
}
