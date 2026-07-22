#Requires -Version 5.1
Set-StrictMode -Version Latest

function Set-AdmanLocalUser {
    <#
    .SYNOPSIS
        Set-AdmanLocalUser - reset a local user's password OR enable/disable a local user
        through the local mutation gate (LUSR-01, D-02, D-05).

    .DESCRIPTION
        Thin prompt-and-dispatch Public verb. Three parameter sets:
          * 'Reset'   (Name + Password [+ PasswordSource]) - routes to 'Set-LocalUser'
                      for password reset; sources the password per D-05 when -Password
                      is not supplied.
          * 'Enable'  (Name + Enable)                      - routes to 'Enable-LocalUser'.
          * 'Disable' (Name + Disable)                     - routes to 'Disable-LocalUser'.
        Enable and Disable are mutually exclusive (different sets). Password cannot be
        combined with Enable or Disable (different sets). PasswordSource is bound to the
        'Reset' set so it cannot be combined with -Enable/-Disable either.

        When the caller supplies no switch and no -Password, the default 'Reset' set binds
        and the verb throws "Parameter set cannot be resolved: supply -Password, -Enable,
        or -Disable." (no silent no-op).

        D-05 password sourcing for the 'Reset' set when -Password is NOT supplied:
          * Reads $script:Config.security.passwordSource (default 'Generate').
          * 'Generate' -> New-AdmanRandomPassword.
          * 'Prompt'   -> Read-Host -AsSecureString twice + Test-AdmanPasswordComplexity.
          * 'Ask'      -> defaults to 'Generate' for direct callers.

        D-05 display-once hygiene (Reset set only): AFTER the gate returns successfully
        (NOT under -WhatIf) AND when the per-call password source is 'Generate', retrieve
        the plaintext ONCE via SecureStringToBSTR + PtrToStringBSTR, display behind
        Read-Host 'Press Enter when recorded', [Console]::Clear() (best-effort),
        ZeroFreeBSTR in finally.

        Phase 2 localhost validation (D-02): accepts $null, '.', $env:COMPUTERNAME,
        'localhost'; throws "Remote targets arrive in Phase 3" otherwise.

        WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
        when $script:Config.ManagedOUs is absent.

    .PARAMETER Name
        The local user name to reset, enable, or disable.

    .PARAMETER Password
        Optional secure-string password for the 'Reset' parameter set. If omitted, the
        configured D-05 password source is used.

    .PARAMETER PasswordSource
        Optional per-call override for the configured password source, valid only with
        the 'Reset' parameter set: 'Generate' or 'Prompt'.

    .PARAMETER Enable
        Enable the local user. Cannot be combined with -Password or -Disable.

    .PARAMETER Disable
        Disable the local user. Cannot be combined with -Password or -Enable.

    .PARAMETER ComputerName
        Optional target machine. In Phase 2 only localhost, '.', or $env:COMPUTERNAME
        are accepted.

    .PARAMETER Force
        Skip the workflow confirmation prompt.

    .EXAMPLE
        Set-AdmanLocalUser -Name 'luser-fake'                # password reset (D-05 sourced)

    .EXAMPLE
        Set-AdmanLocalUser -Name 'luser-fake' -Enable

    .EXAMPLE
        Set-AdmanLocalUser -Name 'luser-fake' -Disable

    .EXAMPLE
        $sec = Read-Host -AsSecureString -Prompt 'New password'
        Set-AdmanLocalUser -Name 'luser-fake' -Password $sec -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Reset')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Reset')]
        [securestring]$Password,

        # HIGH #1 cycle-2 review fix: menu path sets $params['PasswordSource'] via
        # Read-AdmanActionParams; Start-Adman splats it into this parameter. Bound to
        # the 'Reset' set because the marker only applies to password operations.
        [Parameter(ParameterSetName = 'Reset')]
        [ValidateSet('Generate', 'Prompt')]
        [string]$PasswordSource,

        [Parameter(ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(ParameterSetName = 'Disable')]
        [switch]$Disable,

        [string]$ComputerName,

        [switch]$Force
    )

    Assert-AdmanInitialized

    # Phase 2 localhost validation (D-02).
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        $ComputerName -ne '.' -and
        $ComputerName -ne 'localhost' -and
        $ComputerName -ne $env:COMPUTERNAME) {
        throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
    }

    # Dispatch on the bound parameter set. When the default 'Reset' set binds with no
    # -Password, throw the parameter-set resolution error (no silent no-op).
    if ($PSCmdlet.ParameterSetName -eq 'Enable') {
        $params = @{ Name = $Name; ComputerName = $ComputerName }
        return Invoke-AdmanLocalMutation -Verb 'Enable-LocalUser' -Targets @($Name) `
            -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference
    }
    if ($PSCmdlet.ParameterSetName -eq 'Disable') {
        $params = @{ Name = $Name; ComputerName = $ComputerName }
        return Invoke-AdmanLocalMutation -Verb 'Disable-LocalUser' -Targets @($Name) `
            -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference
    }

    # 'Reset' set: require -Password OR source one per D-05. If neither -Password nor
    # a source can produce one, throw the parameter-set resolution error.
    # WR-01 fix: wrap the entire Reset-only block in an explicit ParameterSetName guard.
    # The early returns above already make this unreachable on Enable/Disable, but the
    # explicit guard prevents a future maintainer adding code between dispatch and the
    # gate from accidentally running password-sourcing logic on the Enable path.
    if ($PSCmdlet.ParameterSetName -eq 'Reset') {
        $passwordSupplied = $PSBoundParameters.ContainsKey('Password') -and $null -ne $Password
        $passwordSourceSupplied = $PSBoundParameters.ContainsKey('PasswordSource') -and $PasswordSource

        if (-not $passwordSupplied -and -not $passwordSourceSupplied) {
            # Caller bound the default 'Reset' set with no password input at all.
            throw 'Parameter set cannot be resolved: supply -Password, -Enable, or -Disable.'
        }

        # D-05 per-call password source resolution: explicit password wins over explicit
        # source marker; otherwise fall back to config.
        $passwordSource = if ($passwordSupplied) {
            'Prompt'
        } elseif ($passwordSourceSupplied) {
            $PasswordSource
        } else {
            $src = $script:Config.security.passwordSource
            if ([string]::IsNullOrWhiteSpace([string]$src)) { 'Generate' } else { [string]$src }
        }
        if ($passwordSource -eq 'Ask') { $passwordSource = 'Generate' }

        # D-05 password sourcing when -Password not supplied.
        if (-not $passwordSupplied) {
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
                    $Password = New-AdmanRandomPassword -Length $len
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
                    $Password = $first
                }
            }
        }

        # Build the gate $Parameters. DO NOT forward $PasswordSource — verb-local display hint.
        $params = @{
            Name         = $Name
            Password     = $Password
            ComputerName = $ComputerName
        }

        # WR-02: fail before mutating if a generated password would have to be displayed while a
        # transcript is recording. This prevents stranding an account with an unknown password.
        if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $Password) {
            if ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count -gt 0) {
                throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
            }
        }

        $result = Invoke-AdmanLocalMutation -Verb 'Set-LocalUser' -Targets @($Name) `
            -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference

        # D-05 display-once hygiene: ONLY when the per-call source is Generate AND the gate
        # returned successfully AND NOT under -WhatIf. Plaintext never touches the Success/
        # Error/Warning/Verbose/Information streams or any audit field; it is written directly
        # to the console via [Console]::WriteLine (WR-08 fix), bypassing the Information
        # stream that Write-Host would use. Caveat: when Start-Transcript is running, the
        # console display buffer is captured to the transcript file on disk - operators
        # should NOT run password-generating verbs under Start-Transcript.
        if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $Password) {
            # WR-03: refuse to display generated plaintext while a transcript is recording,
            # because Start-Transcript captures console output to disk.
            if ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InitialSessionState.Transcripts.Count -gt 0) {
                throw 'Generated password cannot be displayed while Start-Transcript is active. Stop the transcript and retry.'
            }
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try {
                $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                [Console]::WriteLine("Generated password for ${Name}: $plain")
                Read-Host -Prompt 'Press Enter when recorded' | Out-Null
                try { [Console]::Clear() } catch [System.IO.IOException] { }
            } finally {
                if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            }
        }

        return $result
    }
}
