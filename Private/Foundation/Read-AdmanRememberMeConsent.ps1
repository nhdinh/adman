#Requires -Version 5.1
<#
.SYNOPSIS
    Read-AdmanRememberMeConsent - the first-capture "remember me" checkbox (CONF-04, D-06).
    Prompts ONCE and returns [bool]$true only on an explicit yes; default-No. Kept as its own
    tiny function so tests can Mock it (Pester: Mock Read-AdmanRememberMeConsent -ModuleName adman)
    and so the consent gate is isolated from the credential decision logic.

.NOTES
    The consent is offered only when $script:Config.credentialPolicy.allowRememberMe is $true (the
    caller, Get-AdmanCredential, gates on that flag). Returning $false means: do NOT write the
    DPAPI file - the prompted credential is still returned for the session (D-06).
#>

Set-StrictMode -Version Latest

function Read-AdmanRememberMeConsent {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $answer = Read-Host 'Remember this credential on this machine with DPAPI (CurrentUser)? [y/N]'
    return ($answer -match '^(y|yes)$')
}
