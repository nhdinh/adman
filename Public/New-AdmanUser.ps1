#Requires -Version 5.1
<#
.SYNOPSIS
    New-AdmanUser - create a single AD user through the mutation gate (USER-02, D-01, D-05).

.DESCRIPTION
    Thin prompt-and-dispatch Public verb. Builds the parameter hashtable and calls
    Invoke-AdmanMutation -Verb 'New-ADUser'. The gate runs the D-01 synthetic pre-create
    target path: Resolve-AdmanCreateTarget fabricates the to-be-created object (no
    Get-ADObject -Identity call), Test-AdmanTargetAllowed runs the create-branch (managed-OU
    scope against the parent OU DN only), the uniqueness pre-flight refuses sAMAccountName
    or CN collisions BEFORE confirm, and the wrapper Adman.AD.Write.New-ADUser performs the
    one real write. TOCTOU between pre-flight and write is closed by letting New-ADUser
    itself throw on collision; the gate records Result='Failure' in the OUTCOME audit.

    D-05 password sourcing when -AccountPassword is NOT supplied:
      * Reads $script:Config.security.passwordSource (default 'Generate').
      * 'Generate' -> New-AdmanRandomPassword -Length $script:Config.security.passwordGeneration.length.
      * 'Prompt'   -> Read-Host -AsSecureString twice, equality check via transient BSTR
                      (zeroed in finally), then Test-AdmanPasswordComplexity.
      * 'Ask'      -> defaults to 'Generate' for direct callers; the menu path handles the
                      sub-choice via Read-AdmanActionParams and splats the resolved value
                      into -AccountPasswordSource.

    D-05 display-once hygiene (B7 fix + per-call source warning fix):
      * AFTER the gate returns successfully (NOT under -WhatIf) AND when the per-call
        password source is 'Generate', retrieve the plaintext ONCE via
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR + PtrToStringBSTR,
        display it behind Read-Host 'Press Enter when recorded', then [Console]::Clear()
        to shrink the shoulder-surf window, and finally ZeroFreeBSTR in a finally block.
      * Per-call source detection: $AccountPasswordSource (explicit menu marker) wins;
        otherwise the $PSBoundParameters heuristic infers 'Prompt' when -AccountPassword
        was supplied, else falls back to $script:Config.security.passwordSource.
      * The plaintext is a local function-scoped variable, NEVER written to any stream
        (no Write-Verbose/Debug/Output, no audit field, no log line). The ONLY output
        is the transient console display before the Clear.
      * Skipped under -WhatIf (the password was never set).

    must-change-at-next-logon: reads $script:Config.security.mustChangeAtNextLogon
    (default $true when the key is absent) and passes it into
    $params['ChangePasswordAtLogon'].

    WR-01 init check: throws 'adman is not initialized. Run Initialize-Adman first.'
    when $script:Config.ManagedOUs is absent.

.EXAMPLE
    New-AdmanUser -Name 'John Doe' -SamAccountName 'jdoe' `
        -UserPrincipalName 'jdoe@contoso.local' `
        -ParentOuDn 'OU=Users,OU=Managed,DC=contoso,DC=local'

.EXAMPLE
    $sec = Read-Host -AsSecureString -Prompt 'Password'
    New-AdmanUser -Name 'John Doe' -SamAccountName 'jdoe' `
        -UserPrincipalName 'jdoe@contoso.local' `
        -ParentOuDn 'OU=Users,OU=Managed,DC=contoso,DC=local' `
        -AccountPassword $sec -WhatIf
#>

Set-StrictMode -Version Latest

function New-AdmanUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ParentOuDn,

        [securestring]$AccountPassword,

        # HIGH #1 cycle-2 review fix: menu path sets $params['AccountPasswordSource'] via
        # Read-AdmanActionParams; Start-Adman splats it into this parameter. Without the
        # declared parameter the splat throws "parameter cannot be found".
        [Parameter()]
        [ValidateSet('Generate', 'Prompt')]
        [string]$AccountPasswordSource,

        [switch]$Force
    )

    # WR-01: fail with a clear message when Initialize-Adman has not run.
    if (-not $script:Config -or
        -not $script:Config.PSObject.Properties['ManagedOUs'] -or
        -not $script:Config.ManagedOUs) {
        throw 'adman is not initialized. Run Initialize-Adman first.'
    }

    # sAMAccountName length validation (T-02-01 mitigation).
    if ($SamAccountName.Length -gt 20) {
        throw "sAMAccountName '$SamAccountName' exceeds the 20-character limit (got $($SamAccountName.Length))."
    }

    # D-05 per-call password source resolution (warning fix + HIGH #1 cycle-2 review fix):
    # explicit menu marker wins; otherwise infer from $PSBoundParameters; otherwise config.
    $passwordSource = if ($PSBoundParameters.ContainsKey('AccountPasswordSource') -and $AccountPasswordSource) {
        $AccountPasswordSource
    } elseif ($PSBoundParameters.ContainsKey('AccountPassword') -and $null -ne $AccountPassword) {
        'Prompt'
    } else {
        $src = $script:Config.security.passwordSource
        if ([string]::IsNullOrWhiteSpace([string]$src)) { 'Generate' } else { [string]$src }
    }
    # 'Ask' defaults to Generate for direct callers (menu path resolves the sub-choice).
    if ($passwordSource -eq 'Ask') { $passwordSource = 'Generate' }

    # D-05 password sourcing when -AccountPassword not supplied.
    if (-not $PSBoundParameters.ContainsKey('AccountPassword') -or $null -eq $AccountPassword) {
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
                $AccountPassword = New-AdmanRandomPassword -Length $len
            }
            'Prompt' {
                $first = Read-Host -AsSecureString -Prompt 'Enter password'
                $second = Read-Host -AsSecureString -Prompt 'Confirm password'
                # Equality check via transient BSTR, zeroed in finally.
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
                $AccountPassword = $first
            }
        }
    }

    # must-change-at-next-logon: config-overridable per installation (D-05), default $true.
    $mustChange = $true
    if ($script:Config.security -and
        $script:Config.security.PSObject.Properties['mustChangeAtNextLogon'] -and
        $null -ne $script:Config.security.mustChangeAtNextLogon) {
        $mustChange = [bool]$script:Config.security.mustChangeAtNextLogon
    }

    # Build the gate $Parameters. DO NOT forward $AccountPasswordSource — it is a verb-local
    # display hint, not gate input (the gate's audit writer never receives it, preserving
    # the no-secret-key invariant).
    $params = @{
        Name                   = $Name
        SamAccountName         = $SamAccountName
        UserPrincipalName      = $UserPrincipalName
        ParentOuDn             = $ParentOuDn
        AccountPassword        = $AccountPassword
        ChangePasswordAtLogon  = $mustChange
    }

    $result = Invoke-AdmanMutation -Verb 'New-ADUser' -Targets @($SamAccountName) `
        -Parameters $params -Force:$Force -WhatIf:$WhatIfPreference

    # D-05 display-once hygiene: ONLY when the per-call source is Generate AND the gate
    # returned successfully AND NOT under -WhatIf. Plaintext never touches the Success/
    # Error/Warning/Verbose/Information streams or any audit field; it is written directly
    # to the console via [Console]::WriteLine (WR-08 fix), bypassing the Information
    # stream that Write-Host would use. Caveat: when Start-Transcript is running, the
    # console display buffer is captured to the transcript file on disk - operators
    # should NOT run password-generating verbs under Start-Transcript.
    if (-not $WhatIfPreference -and $passwordSource -eq 'Generate' -and $null -ne $AccountPassword) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccountPassword)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [Console]::WriteLine("Generated password for ${SamAccountName}: $plain")
            Read-Host -Prompt 'Press Enter when recorded' | Out-Null
            # [Console]::Clear() throws IOException "The handle is invalid" in headless
            # hosts (Pester, ISE, remoting). Best-effort only: swallow that specific
            # failure so the verb still completes; the shoulder-surf shrink is a UX
            # nicety, not a security boundary (the BSTR is already zeroed below).
            try { [Console]::Clear() } catch [System.IO.IOException] { }
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }

    return $result
}
