#Requires -Version 5.1
Set-StrictMode -Version Latest

function Set-AdmanUserPassword {
    <#
    .SYNOPSIS
        Set-AdmanUserPassword - reset a single AD user's password through the mutation
        gate (USER-04, D-05).

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
        one or more Invoke-AdmanMutation gates so that every state-changing sub-operation
        gets its own PENDING/OUTCOME audit pair, its own Confirm-AdmanAction confirmation,
        and its own -WhatIf preview:

          1. Set-ADAccountPassword performs the actual password reset.
          2. Set-ADUser applies ChangePasswordAtLogon (HIGH #4: Set-ADAccountPassword does
             not accept this parameter).
          3. Unlock-ADAccount runs only when -Unlock is specified, after the reset succeeds.

        Each gate invocation resolves the target once (SAFE-10), runs Test-AdmanTargetAllowed,
        confirms via Confirm-AdmanAction, writes the PENDING audit, invokes the AD write,
        and writes the OUTCOME audit. Failures are captured and aggregated so a follow-up
        throw does not surface as an unhandled exception while earlier sub-operations show
        'Success' in the audit log.

        This state-changing verb routes through the mutation gate, which writes a PENDING/OUTCOME
        audit pair, prompts for confirmation, and supports -WhatIf for dry-run preview.

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

    .PARAMETER Identity
        The sAMAccountName, distinguished name, GUID, or SID of the AD user whose password
        will be reset.

    .PARAMETER NewPassword
        Optional secure-string password. If omitted, the password is sourced from
        $script:Config.security.passwordSource ('Generate' or 'Prompt').

    .PARAMETER NewPasswordSource
        Optional per-call override for password sourcing: 'Generate' or 'Prompt'.
        Used by the menu path; direct callers usually omit this and use -NewPassword.

    .PARAMETER ChangePasswordAtLogon
        Optional nullable boolean. If supplied, forces the value; otherwise the config
        key $script:Config.security.mustChangeAtNextLogon is used with a $true fallback.

    .PARAMETER Unlock
        When set, unlocks the account after a successful password reset via a separate
        gate invocation so it gets its own audit pair and confirmation.

    .PARAMETER Force
        Bypasses the confirmation prompt when set. -WhatIf still previews the action.

    .EXAMPLE
        Set-AdmanUserPassword -Identity 'jdoe'

    .EXAMPLE
        Set-AdmanUserPassword -Identity 'jdoe' -ChangePasswordAtLogon $false -Unlock

    .EXAMPLE
        $sec = Read-Host -AsSecureString -Prompt 'New password'
        Set-AdmanUserPassword -Identity 'jdoe' -NewPassword $sec -WhatIf
    #>

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
                $len = $script:DefaultPasswordLength
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
                $minLen = $script:DefaultPasswordLength
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

    # CR-01 fix: invoke the gate once per sub-operation so each gets its own PENDING/OUTCOME
    # audit pair and its own confirmation. Capture ALL three results and aggregate failures
    # so a follow-up throw does not surface as an unhandled exception with no correlation
    # ID while the audit log shows 'Success' for the earlier sub-operation.
    $results = @()
    $errors  = @()

    # Sub-operation 1: the password reset itself.
    $resetParams = @{ NewPassword = $NewPassword }
    try {
        $results += Invoke-AdmanMutation -Verb 'Set-ADAccountPassword' -Targets @($Identity) `
            -Parameters $resetParams -Force:$Force -WhatIf:$WhatIfPreference
    } catch { $errors += $_ }

    # Sub-operation 2: apply ChangePasswordAtLogon via Set-ADUser. Set-ADAccountPassword does
    # NOT accept -ChangePasswordAtLogon (HIGH #4); it belongs on Set-ADUser. Running this as
    # its own gate invocation means a Set-ADUser failure does NOT mislabel the (already
    # successful) password reset as 'Failure' in the audit log.
    if ($errors.Count -eq 0) {
        $setUserParams = @{ ChangePasswordAtLogon = $mustChange }
        try {
            $results += Invoke-AdmanMutation -Verb 'Set-ADUser' -Targets @($Identity) `
                -Parameters $setUserParams -Force:$Force -WhatIf:$WhatIfPreference
        } catch { $errors += $_ }
    }

    # Sub-operation 3: optional Unlock. A locked account cannot have its password reset by
    # some paths (B5), so Unlock runs AFTER the reset; as its own gate call it gets its own
    # audit pair and the operator sees a distinct confirmation.
    if ($Unlock -and $errors.Count -eq 0) {
        try {
            $results += Invoke-AdmanMutation -Verb 'Unlock-ADAccount' -Targets @($Identity) `
                -Parameters @{} -Force:$Force -WhatIf:$WhatIfPreference
        } catch { $errors += $_ }
    }

    if ($errors.Count -gt 0) {
        $errMsgs = ($errors | ForEach-Object { $_.Exception.Message }) -join '; '
        throw "One or more sub-operations failed: $errMsgs"
    }
    # CR-01 fix: return the reset sub-operation's result. Guard against the edge case where
    # the gate returned $null (e.g. a mocked gate in tests) - in that case $results may be
    # empty and indexing [0] would throw IndexOutOfRangeException.
    $result = if ($results.Count -gt 0) { $results[0] } else { $null }

    # D-05 display-once hygiene: ONLY when the per-call source is Generate AND the gate
    # returned successfully AND NOT under -WhatIf. Plaintext never touches the Success/
    # Error/Warning/Verbose/Information streams or any audit field; it is written directly
    # to the console via [Console]::WriteLine (WR-08 fix), bypassing the Information
    # stream that Write-Host would use. Caveat: when Start-Transcript is running, the
    # console display buffer is captured to the transcript file on disk - operators
    # should NOT run password-generating verbs under Start-Transcript.
    if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $NewPassword) {
        # WR-03: refuse to display generated plaintext while a transcript is recording,
        # because Start-Transcript captures console output to disk.
        if ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count -gt 0) {
            throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
        }
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [Console]::WriteLine("Generated password for ${Identity}: $plain")
            Read-Host -Prompt 'Press Enter when recorded' | Out-Null
            # Best-effort: [Console]::Clear() throws IOException in headless hosts.
            try { [Console]::Clear() } catch [System.IO.IOException] { }
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }

    return $result
}
