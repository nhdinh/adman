#Requires -Version 5.1
<#
.SYNOPSIS
    Read-AdmanActionParams - per-action parameter prompter for the Start-Adman menu.

.DESCRIPTION
    Reads the PromptSpec from a Get-AdmanMenuDefinition entry and prompts the operator
    for each required input. Returns a hashtable of parameters suitable for splatting
    onto the entry's Public verb via & $Verb @params.

    Reserved inputs (UI-SPEC §Reserved inputs; D-01):
      * 'B' / 'b'  - abandon the current action and return $null (Start-Adman resumes
                     the top-level loop).
      * 'Q' / 'q'  - exit Start-Adman entirely. Signaled by throwing an error whose
                     message is the reserved 'ADMAN_QUIT' sentinel; the top-level loop
                     catches this sentinel and breaks cleanly.
      * Empty required input - re-prompts once; a second consecutive empty is treated
                     as 'B' (return $null).

    Polymorphic Type field (D-05, Phase 2):
      * Type='Text' (default)        - free-text prompt; the value is trimmed and stored.
      * Type='AdIdentity'            - resolves sAMAccountName or DN to an AD object DN
                                       at prompt time via Resolve-AdmanIdentity; re-prompts
                                       on failure (G-02-2). Honors the optional PromptSpec
                                       'Kind' field - 'AdUser' (default) or 'AdComputer'
                                       (tries both NAME and NAME$ sAMAccountName forms,
                                       REV-3). The resolved DistinguishedName is stored
                                       in $params[$name].
      * Type='AdOuDn'                - validates the input is a DN that resolves to an
                                       existing AD organizationalUnit via
                                       Resolve-AdmanIdentity -Kind AdOuDn; re-prompts on
                                       failure (G-02-4). The resolved OU DistinguishedName
                                       is stored in $params[$name].
      * Type='GeneratedPassword'     - renders the Choices array as a numeric sub-choice
                                       (1=Generate, 2=Prompt). The Generate path calls
                                       New-AdmanRandomPassword -Length $script:Config.security.passwordGeneration.length
                                       and stores the resulting SecureString in
                                       $params[$name], plus sets $params["${name}Source"]='Generate'.
                                       The Prompt path calls Read-Host -AsSecureString twice
                                       with an equality check (transient BSTR zeroed in
                                       finally) + Test-AdmanPasswordComplexity, stores the
                                       SecureString in $params[$name], and sets
                                       $params["${name}Source"]='Prompt'.
                                       The B/Q reserved-input contract applies to the
                                       sub-choice prompt as well.

    The $name here is the PromptSpec Name - which is per-verb ('AccountPassword',
    'NewPassword', or 'Password') per the PROMPTSPEC-PARAMETER NAME CONTRACT (HIGH #1
    cycle-2 review fix). The "${name}Source" marker key is therefore
    'AccountPasswordSource', 'NewPasswordSource', or 'PasswordSource' respectively,
    and each target verb declares the matching optional parameter (Plans 02-02 / 02-04),
    so the Start-Adman `& $Verb @params` splat binds cleanly.

    Validation:
      * Free-text inputs are trimmed and passed through; the underlying verb validates
        semantics.
      * Choice inputs (PromptSpec entries with a Choices array) accept only numeric
        indices 1..N or B/Q. Invalid input re-prompts with the standard copy:
        'Invalid selection. Enter a number, B, or Q.'

    This helper returns ONLY the parameters declared in the PromptSpec (plus the
    auto-generated "${name}Source" marker for GeneratedPassword fields) - no
    free-form code execution, no extra parameters (T-01-03).
#>

Set-StrictMode -Version Latest

function Read-AdmanActionParams {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$PromptSpec
    )

    $params = @{}

    foreach ($field in $PromptSpec) {
        # PromptSpec entries may be hashtables (menu def inline shape) or PSCustomObjects.
        # Hashtable keys are NOT exposed via PSObject.Properties.Name; probe via
        # the appropriate mechanism for each shape so Choices/Type are detected
        # consistently across both (Rule 1 bug fix).
        $isHashtable = $field -is [System.Collections.IDictionary]
        $hasKey = {
            param([string]$Key)
            if ($isHashtable) { return $field.Contains($Key) }
            return ($field.PSObject.Properties.Name -contains $Key)
        }
        $getVal = {
            param([string]$Key)
            if ($isHashtable) { return $field[$Key] }
            return $field.$Key
        }

        $name = [string](& $getVal 'Name')
        $prompt = [string](& $getVal 'Prompt')
        # IN-02 fix: $required is consulted ONLY by the free-text branch below. The
        # Choices and GeneratedPassword branches always loop until a valid selection or
        # B/Q (they are implicitly always required). Read it unconditionally because the
        # field shape is uniform, but document that the choice paths ignore it.
        $required = [bool](& $getVal 'Required')
        $choices = $null
        if (& $hasKey 'Choices') {
            $choices = & $getVal 'Choices'
        }
        $type = 'Text'
        if ((& $hasKey 'Type') -and (& $getVal 'Type')) {
            $type = [string](& $getVal 'Type')
        }
        # Optional Kind hint for Type='AdIdentity' (REV-3): 'AdUser' (default) or
        # 'AdComputer'. Read unconditionally; consumed only by the AdIdentity branch.
        $kind = 'AdUser'
        if ((& $hasKey 'Kind') -and (& $getVal 'Kind')) {
            $kind = [string](& $getVal 'Kind')
        }

        $emptySeen = $false
        $resolved = $false

        while (-not $resolved) {
            if ($type -eq 'GeneratedPassword') {
                # D-05 numeric sub-choice: 1=Generate (CSPRNG), 2=Prompt (Read-Host -AsSecureString).
                # B/Q reserved-input contract applies to this prompt as well.
                for ($i = 0; $i -lt @($choices).Count; $i++) {
                    Write-Host ("{0}. {1}" -f ($i + 1), $choices[$i])
                }
                Write-Host 'B. Back'
                Write-Host 'Q. Exit'
                $answer = Read-Host $prompt

                if ($answer -match '^[Qq]$') {
                    throw 'ADMAN_QUIT'
                }
                if ($answer -match '^[Bb]$') {
                    return $null
                }
                $n = 0
                if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le @($choices).Count) {
                    if ($n -eq 1) {
                        # Generate path: CSPRNG via New-AdmanRandomPassword.
                        $len = $script:DefaultPasswordLength
                        if ($script:Config -and
                            $script:Config.PSObject.Properties['security'] -and
                            $script:Config.security -and
                            $script:Config.security.PSObject.Properties['passwordGeneration'] -and
                            $script:Config.security.passwordGeneration -and
                            $script:Config.security.passwordGeneration.PSObject.Properties['length'] -and
                            $script:Config.security.passwordGeneration.length) {
                            $len = [int]$script:Config.security.passwordGeneration.length
                        }
                        $params[$name] = New-AdmanRandomPassword -Length $len
                        $params["${name}Source"] = 'Generate'
                        $resolved = $true
                    } else {
                        # Prompt path: Read-Host -AsSecureString twice + equality check + complexity.
                        $first = Read-Host -AsSecureString -Prompt 'Enter password'
                        $second = Read-Host -AsSecureString -Prompt 'Confirm password'
                        # WR-04 fix: track whether $first was consumed (stored into $params)
                        # so the finally block can dispose BOTH SecureStrings on every exit
                        # path (mismatch, complexity failure, success-with-consume). The BSTRs
                        # are zeroed below; the SecureString internal buffers are released
                        # by Dispose. $first is NOT disposed when stored into $params (the
                        # caller owns it from that point).
                        $firstConsumed = $false
                        try {
                            # Equality check via transient BSTR, zeroed in finally.
                            $b1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
                            $b2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
                            try {
                                $p1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
                                $p2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
                                if ($p1 -cne $p2) {
                                    Write-Host 'Passwords do not match. Try again.'
                                    continue
                                }
                            } finally {
                                if ($b1 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1) }
                                if ($b2 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) }
                            }
                            $minLen = $script:DefaultPasswordLength
                            if ($script:Config -and
                                $script:Config.PSObject.Properties['security'] -and
                                $script:Config.security -and
                                $script:Config.security.PSObject.Properties['passwordGeneration'] -and
                                $script:Config.security.passwordGeneration -and
                                $script:Config.security.passwordGeneration.PSObject.Properties['length'] -and
                                $script:Config.security.passwordGeneration.length) {
                                $minLen = [int]$script:Config.security.passwordGeneration.length
                            }
                            try {
                                Test-AdmanPasswordComplexity -Password $first -MinLength $minLen | Out-Null
                            } catch {
                                Write-Host ("Password does not meet complexity requirements: {0}" -f $_.Exception.Message)
                                continue
                            }
                            # CR-03 fix: set $firstConsumed BEFORE storing into $params so
                            # an exception between the two stores cannot cause the finally
                            # block to dispose a SecureString that $params still references.
                            # Wrap the store in try/catch so a partial store removes the
                            # reference and rethrows (finally will then dispose correctly).
                            $firstConsumed = $true
                            try {
                                $params[$name] = $first
                                $params["${name}Source"] = 'Prompt'
                                $resolved = $true
                            } catch {
                                $params.Remove($name)
                                $params.Remove("${name}Source")
                                throw
                            }
                        } finally {
                            # Always dispose the duplicate. Dispose $first only when it was
                            # NOT stored into $params (i.e. mismatch or complexity failure).
                            if ($null -ne $second) { $second.Dispose() }
                            if (-not $firstConsumed -and $null -ne $first) { $first.Dispose() }
                        }
                    }
                } else {
                    Write-Host 'Invalid selection. Enter a number, B, or Q.'
                }
            } elseif ($null -ne $choices -and @($choices).Count -gt 0) {
                # Numeric sub-choice prompt.
                for ($i = 0; $i -lt @($choices).Count; $i++) {
                    Write-Host ("{0}. {1}" -f ($i + 1), $choices[$i])
                }
                Write-Host 'B. Back'
                Write-Host 'Q. Exit'
                $answer = Read-Host $prompt

                if ($answer -match '^[Qq]$') {
                    throw 'ADMAN_QUIT'
                }
                if ($answer -match '^[Bb]$') {
                    return $null
                }
                $n = 0
                if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le @($choices).Count) {
                    $params[$name] = $choices[$n - 1]
                    $resolved = $true
                } else {
                    Write-Host 'Invalid selection. Enter a number, B, or Q.'
                }
            } else {
                # Free-text prompt.
                $answer = Read-Host $prompt

                if ($answer -match '^[Qq]$') {
                    throw 'ADMAN_QUIT'
                }
                if ($answer -match '^[Bb]$') {
                    return $null
                }

                $trimmed = if ($null -eq $answer) { '' } else { $answer.Trim() }

                if ($trimmed -eq '' -and $required) {
                    if ($emptySeen) {
                        # Second consecutive empty on a required field -> treat as B.
                        return $null
                    }
                    $emptySeen = $true
                    continue
                }

                # Type dispatch (G-02-2 / G-02-4): AdIdentity and AdOuDn route through
                # Resolve-AdmanIdentity at prompt time so malformed input re-prompts
                # instead of crashing the gate. The B/Q/empty handling above already
                # ran, so the reserved-input contract is preserved.
                if ($type -eq 'AdIdentity') {
                    try {
                        $resolvedObj = Resolve-AdmanIdentity -InputValue $trimmed -Kind $kind
                        $params[$name] = $resolvedObj.DistinguishedName
                        $resolved = $true
                    } catch {
                        Write-Host $_.Exception.Message
                        continue
                    }
                } elseif ($type -eq 'AdOuDn') {
                    try {
                        $resolvedOu = Resolve-AdmanIdentity -InputValue $trimmed -Kind 'AdOuDn'
                        $params[$name] = $resolvedOu.DistinguishedName
                        $resolved = $true
                    } catch {
                        Write-Host $_.Exception.Message
                        continue
                    }
                } else {
                    $params[$name] = $trimmed
                    $resolved = $true
                }
            }
        }
    }

    return $params
}
