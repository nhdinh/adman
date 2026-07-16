#Requires -Version 5.1
<#
.SYNOPSIS
    New-AdmanLocalUser - create a single local user through the local mutation gate
    (LUSR-01, D-02, D-05).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanLocalMutation -Verb 'New-LocalUser'. The gate (built in Plan 02-01)
    routes New-LocalUser through the create-branch: Resolve-AdmanLocalTarget fabricates
    a synthetic local target (Machine, proposed Name, no SID yet) when Verb='New-LocalUser';
    Test-AdmanLocalTargetAllowed skips SID-dependent checks (RID-500, Administrators
    membership) for synthetic targets and runs only machine-in-scope + name-shape
    validation; uniqueness pre-flight via Get-LocalUser returning zero hits refuses
    BEFORE confirm; New-LocalUser's own collision throw closes TOCTOU with a Failure
    OUTCOME audit record. Strictly parallel to D-01's AD-create pattern.

    D-05 password sourcing when -Password is NOT supplied:
      * Reads $script:Config.security.passwordSource (default 'Generate').
      * 'Generate' -> New-AdmanRandomPassword -Length $script:Config.security.passwordGeneration.length.
      * 'Prompt'   -> Read-Host -AsSecureString twice, equality check via transient BSTR
                      (zeroed in finally), then Test-AdmanPasswordComplexity.
      * 'Ask'      -> defaults to 'Generate' for direct callers; the menu path handles
                      the sub-choice via Read-AdmanActionParams and splats the resolved
                      value into -PasswordSource.

    D-05 display-once hygiene: AFTER the gate returns successfully (NOT under -WhatIf)
    AND when the per-call password source is 'Generate', retrieve the plaintext ONCE
    via SecureStringToBSTR + PtrToStringBSTR, display behind Read-Host 'Press Enter
    when recorded', [Console]::Clear() (best-effort; headless hosts throw IOException),
    ZeroFreeBSTR in finally. Plaintext never touches any stream or audit field.

    Phase 2 localhost validation (D-02): accepts $null, '.', $env:COMPUTERNAME,
    'localhost'; throws "Remote targets arrive in Phase 3. -ComputerName '<x>' is not
    localhost." otherwise. Phase 3 widens the validation when the transport ladder
    lands; the verb signature is stable across phases.

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    New-AdmanLocalUser -Name 'luser'

.EXAMPLE
    $sec = Read-Host -AsSecureString -Prompt 'Password'
    New-AdmanLocalUser -Name 'luser' -Password $sec -WhatIf
#>

Set-StrictMode -Version Latest

function New-AdmanLocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [securestring]$Password,

        # HIGH #1 cycle-2 review fix: menu path sets $params['PasswordSource'] via
        # Read-AdmanActionParams; Start-Adman splats it into this parameter. Without
        # the declared parameter the splat throws "parameter cannot be found".
        [Parameter()]
        [ValidateSet('Generate', 'Prompt')]
        [string]$PasswordSource,

        [string]$ComputerName,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # Phase 2 localhost validation (D-02). Accept $null, '.', $env:COMPUTERNAME,
    # 'localhost'; throw on anything else. Phase 3 widens the validation.
    if (-not [string]::IsNullOrWhiteSpace($ComputerName) -and
        $ComputerName -ne '.' -and
        $ComputerName -ne 'localhost' -and
        $ComputerName -ne $env:COMPUTERNAME) {
        throw "Remote targets arrive in Phase 3. -ComputerName '$ComputerName' is not localhost."
    }

    # D-05 per-call password source resolution (HIGH #1 cycle-2 review fix):
    # explicit menu marker wins; otherwise infer from $PSBoundParameters; otherwise config.
    $passwordSource = if ($PSBoundParameters.ContainsKey('PasswordSource') -and $PasswordSource) {
        $PasswordSource
    } elseif ($PSBoundParameters.ContainsKey('Password') -and $null -ne $Password) {
        'Prompt'
    } else {
        $src = $script:Config.security.passwordSource
        if ([string]::IsNullOrWhiteSpace([string]$src)) { 'Generate' } else { [string]$src }
    }
    if ($passwordSource -eq 'Ask') { $passwordSource = 'Generate' }

    # D-05 password sourcing when -Password not supplied.
    if (-not $PSBoundParameters.ContainsKey('Password') -or $null -eq $Password) {
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
                $first = Read-Host -AsSecureString -Prompt 'Enter password'
                $second = Read-Host -AsSecureString -Prompt 'Confirm password'
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

    # Build the gate $Parameters. DO NOT forward $PasswordSource — it is a verb-local
    # display hint, not gate input (the gate's audit writer never receives it,
    # preserving the no-secret-key invariant).
    $params = @{
        Name         = $Name
        Password     = $Password
        ComputerName = $ComputerName
    }

    $result = Invoke-AdmanLocalMutation -Verb 'New-LocalUser' -Targets @($Name) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference

    # D-05 display-once hygiene: ONLY when the per-call source is Generate AND the gate
    # returned successfully AND NOT under -WhatIf. Plaintext never touches the Success/
    # Error/Warning/Verbose streams or any audit field; it DOES go to the host display
    # via Write-Host (WR-05). Caveat: when Start-Transcript is running, the host display
    # buffer is captured to the transcript file on disk - operators should NOT run
    # password-generating verbs under Start-Transcript.
    if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $Password) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            Write-Host "Generated password for ${Name}: $plain"
            Read-Host -Prompt 'Press Enter when recorded' | Out-Null
            # Best-effort: [Console]::Clear() throws IOException in headless hosts.
            try { [Console]::Clear() } catch [System.IO.IOException] { }
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }

    return $result
}
