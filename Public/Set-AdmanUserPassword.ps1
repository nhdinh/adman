#Requires -Version 5.1
<#
.SYNOPSIS
    Set-AdmanUserPassword - reset a single AD user's password through the mutation
    gate (USER-04, D-05).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanMutation -Verb 'Set-ADAccountPassword'. The gate resolves the target
    once (SAFE-10), runs Test-AdmanTargetAllowed, confirms via Confirm-AdmanAction,
    writes the PENDING audit, and invokes the Adman.AD.Write.Set-ADAccountPassword
    wrapper for the one real write. The wrapper (Plan 02-01) detects
    $Parameters['Unlock'], strips it, and calls Unlock-ADAccount after the reset
    succeeds — one gate invocation, one audit pair. ChangePasswordAtLogon is split
    to a follow-up Set-ADUser call after the reset (HIGH #4).

    D-05 password sourcing when -NewPassword is NOT supplied:
      * Reads $script:Config.security.passwordSource (default 'Generate').
      * 'Generate' -> New-AdmanRandomPassword -Length $script:Config.security.passwordGeneration.length.
      * 'Prompt'   -> Read-Host -AsSecureString twice, equality check via transient
                      BSTR (zeroed in finally), then Test-AdmanPasswordComplexity.
      * 'Ask'      -> defaults to 'Generate' for direct callers; the menu path
                      handles the sub-choice via Read-AdmanActionParams and splats
                      the resolved value into -NewPasswordSource.

    must-change resolution (warning fix): when $PSBoundParameters.ContainsKey(
    'ChangePasswordAtLogon'), use [bool]$ChangePasswordAtLogon (caller intent wins);
    otherwise read $script:Config.security.mustChangeAtNextLogon with a $true
    fallback (D-05 config-overridable per-installation). A [bool]=$true default
    would mask whether the caller supplied the value or the default fired — the
    PSBoundParameters pattern is the only way to detect caller intent.

    D-05 display-once hygiene (B7 fix + per-call source warning fix + HIGH #1
    cycle-2 review fix): identical to New-AdmanUser — AFTER the gate returns
    successfully (NOT under -WhatIf) AND when the per-call password source is
    Generate, retrieve the plaintext ONCE via SecureStringToBSTR + PtrToStringBSTR,
    display behind Read-Host 'Press Enter when recorded', [Console]::Clear()
    (best-effort; headless hosts throw IOException), ZeroFreeBSTR in finally. The
    plaintext never touches any stream or audit field.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    Set-AdmanUserPassword -Identity 'jdoe'

.EXAMPLE
    Set-AdmanUserPassword -Identity 'jdoe' -ChangePasswordAtLogon $false -Unlock

.EXAMPLE
    $sec = Read-Host -AsSecureString -Prompt 'New password'
    Set-AdmanUserPassword -Identity 'jdoe' -NewPassword $sec -WhatIf
#>

Set-StrictMode -Version Latest

function Set-AdmanUserPassword {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [securestring]$NewPassword,

        # HIGH #1 cycle-2 review fix: menu path sets $params['NewPasswordSource'] via
        # Read-AdmanActionParams; Start-Adman splats it into this parameter. Without
        # the declared parameter the splat throws "parameter cannot be found".
        [Parameter()]
        [ValidateSet('Generate', 'Prompt')]
        [string]$NewPasswordSource,

        # NO DEFAULT — caller intent must be detectable via $PSBoundParameters.
        # A [bool]=$true default would mask whether the caller supplied the value
        # or the default fired (warning fix).
        [Parameter()]
        [Nullable[bool]]$ChangePasswordAtLogon,

        [switch]$Unlock,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # D-05 per-call password source resolution (warning fix + HIGH #1 cycle-2 review fix).
    $passwordSource = if ($PSBoundParameters.ContainsKey('NewPasswordSource') -and $NewPasswordSource) {
        $NewPasswordSource
    } elseif ($PSBoundParameters.ContainsKey('NewPassword') -and $null -ne $NewPassword) {
        'Prompt'
    } else {
        $src = $script:Config.security.passwordSource
        if ([string]::IsNullOrWhiteSpace([string]$src)) { 'Generate' } else { [string]$src }
    }
    if ($passwordSource -eq 'Ask') { $passwordSource = 'Generate' }

    # D-05 password sourcing when -NewPassword not supplied.
    if (-not $PSBoundParameters.ContainsKey('NewPassword') -or $null -eq $NewPassword) {
        switch ($passwordSource) {
            'Generate' {
                $len = 20
                if ($script:Config.security -and
                    $script:Config.security.PSObject.Properties['passwordGeneration'] -and
                    $script:Config.security.passwordGeneration -and
                    $script:Config.security.passwordGeneration.PSObject.Properties['length'] -and
                    $script:Config.security.passwordGeneration.length) {
                    $len = [int]$script:Config.security.passwordGeneration.length
                }
                $NewPassword = New-AdmanRandomPassword -Length $len
            }
            'Prompt' {
                $first = Read-Host -AsSecureString -Prompt 'Enter new password'
                $second = Read-Host -AsSecureString -Prompt 'Confirm new password'
                $b1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
                $b2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
                try {
                    $p1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
                    $p2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
                    if ($p1 -cne $p2) { throw 'Passwords do not match.' }
                } finally {
                    if ($b1 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1) }
                    if ($b2 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) }
                }
                $minLen = 20
                if ($script:Config.security -and
                    $script:Config.security.PSObject.Properties['passwordGeneration'] -and
                    $script:Config.security.passwordGeneration -and
                    $script:Config.security.passwordGeneration.PSObject.Properties['length'] -and
                    $script:Config.security.passwordGeneration.length) {
                    $minLen = [int]$script:Config.security.passwordGeneration.length
                }
                Test-AdmanPasswordComplexity -Password $first -MinLength $minLen | Out-Null
                $NewPassword = $first
            }
        }
    }

    # must-change resolution (warning fix): caller intent wins; otherwise config with $true fallback.
    $mustChange = if ($PSBoundParameters.ContainsKey('ChangePasswordAtLogon')) {
        [bool]$ChangePasswordAtLogon
    } else {
        $cfgVal = $true
        if ($script:Config.security -and
            $script:Config.security.PSObject.Properties['mustChangeAtNextLogon'] -and
            $null -ne $script:Config.security.mustChangeAtNextLogon) {
            $cfgVal = [bool]$script:Config.security.mustChangeAtNextLogon
        }
        $cfgVal
    }

    # Build the gate $Parameters. DO NOT forward $NewPasswordSource — it is a verb-local
    # display hint, not gate input.
    $params = @{
        NewPassword           = $NewPassword
        ChangePasswordAtLogon = $mustChange
    }
    if ($Unlock) { $params['Unlock'] = $true }

    $result = Invoke-AdmanMutation -Verb 'Set-ADAccountPassword' -Targets @($Identity) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference -Confirm:$false

    # D-05 display-once hygiene: ONLY when the per-call source is Generate AND the gate
    # returned successfully AND NOT under -WhatIf. Plaintext never touches any stream.
    if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $NewPassword) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            Write-Host "Generated password for ${Identity}: $plain"
            Read-Host -Prompt 'Press Enter when recorded' | Out-Null
            # Best-effort: [Console]::Clear() throws IOException in headless hosts.
            try { [Console]::Clear() } catch [System.IO.IOException] { }
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }

    return $result
}
