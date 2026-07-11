#Requires -Version 5.1
<#
.SYNOPSIS
    Get-AdmanCredential - pass-through-by-default credential decision with an opt-in DPAPI
    remember-me file and re-prompt-on-restore-failure (CONF-04/06, D-06). Also hosts the cheap,
    non-destructive Test-AdmanRightsSufficient helper that feeds the decision when a caller has
    not pre-set $script:RightsInsufficient.

.DESCRIPTION
    Ordering is RIGHTS-FIRST (CONF-06) - this deliberately fixes the unreachable-prompt bug where
    an early 'allowRememberMe' gate made the prompt path dead code:
      1. Rights FIRST: honor a pre-set $script:RightsInsufficient; otherwise compute it via a
         cheap non-destructive read (read the managed OU + whoami /groups for delegatedAdminGroup)
         so this function does NOT depend on Test-AdmanCapability ordering.
      2. Pass-through: if rights are sufficient, return $null (use the logged-in admin) regardless
         of allowRememberMe - NEVER prompt.
      3. Stored credential ONLY when rights are insufficient AND remember-me is on AND the DPAPI
         file is readable: Import-Clixml -> type guard (must be a PSCredential; rejects keyed-AES /
         corrupt restores) -> empty-password guard (GetNetworkCredential().Password). On ANY failure
         (CryptographicException 0x8009000B, wrong type, empty password) DELETE the bad file and
         fall through to the prompt. The stored credential never short-circuits the rights check.
      4. Prompt (rights insufficient, no usable stored credential): Get-Credential; write the DPAPI
         file ONLY when allowRememberMe AND Read-AdmanRememberMeConsent; always return the credential
         for the session.

    Invariants (D-06 / CONF-05):
      * DPAPI CurrentUser only (Export-Clixml default; identical on PS 5.1 and 7 on Windows). The
        keyed-AES export switch is never used; a keyed-AES/non-PSCredential restore is rejected.
      * No credential / password is ever logged; the only diagnostic emitted is a static,
        secret-free string.
      * LocalMachine scope is a documented opt-in only (deferred; not implemented here).
#>

Set-StrictMode -Version Latest

function Test-AdmanRightsSufficient {
    <#
    .SYNOPSIS
        Cheap, NON-DESTRUCTIVE rights sufficiency signal for the credential decision (CONF-06).
        Reads the first managed OU and, when a delegatedAdminGroup is configured, checks the
        current token's groups via 'whoami /groups'. NEVER performs an AD write. Returns $true
        when pass-through rights appear sufficient, $false otherwise (any failure => $false).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $ou = @($script:Config.ManagedOUs | Select-Object -First 1)[0]
        if (-not $ou) { return $false }
        $null = Get-ADOrganizationalUnit -Identity $ou -Server $script:Config.DC -ErrorAction Stop

        $group = $script:Config.delegatedAdminGroup
        if ($group) {
            $groups = (& whoami /groups 2>$null | Out-String)
            if ($groups -notmatch [regex]::Escape($group)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Get-AdmanCredential {
    <#
    .SYNOPSIS
        Decide which credential (if any) the next AD task should use.
    .OUTPUTS
        $null when pass-through rights are sufficient (use the logged-in admin); otherwise a
        [pscredential] (restored from the DPAPI file or freshly prompted).
    #>
    [CmdletBinding()]
    param()

    $file = Join-Path $script:StorePath 'adman.credential.xml'

    # Step 1 - rights FIRST (CONF-06). Honor a pre-set flag; else compute cheaply/non-destructively.
    if (Get-Variable -Name RightsInsufficient -Scope Script -ErrorAction SilentlyContinue) {
        $insufficient = [bool]$script:RightsInsufficient
    } else {
        $insufficient = -not (Test-AdmanRightsSufficient)
    }

    # Step 2 - pass-through: rights sufficient => use the logged-in admin; never prompt.
    if (-not $insufficient) { return $null }

    # Step 3 - stored credential ONLY when remember-me is on AND the file is readable.
    if ($script:Config.credentialPolicy.allowRememberMe -and (Test-Path -LiteralPath $file)) {
        try {
            $cred = Import-Clixml -Path $file -ErrorAction Stop
            if (-not ($cred -is [pscredential])) {
                throw 'stored credential file did not yield a PSCredential (keyed-AES/corrupt)'
            }
            $pw = $cred.GetNetworkCredential().Password
            if ([string]::IsNullOrEmpty($pw)) {
                throw 'stored credential restored an empty password'
            }
            return $cred
        } catch {
            # CryptographicException 0x8009000B (wrong user/machine), wrong type, OR empty password:
            # delete the bad file and fall back to a prompt (D-06).
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            Write-PSFMessage -Level Warning -Message 'Stored credential unreadable; re-prompting.'
        }
    }

    # Step 4 - prompt when rights insufficient (and no usable stored credential).
    $cred = Get-Credential -Message 'Domain credentials required for this task'
    if ($script:Config.credentialPolicy.allowRememberMe -and (Read-AdmanRememberMeConsent)) {
        $cred | Export-Clixml -Path $file -Force   # DPAPI CurrentUser (5.1/7 identical on Windows)
    }
    return $cred
}
