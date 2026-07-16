#Requires -Version 5.1
<#
.SYNOPSIS
    Test-AdmanPasswordComplexity - validate a SecureString meets the password policy
    (length + 4 character classes).

.DESCRIPTION
    Used by the D-05 Prompt path so a typed password is held to the SAME bar as the
    generator. Reads the SecureString ONCE into a transient plaintext buffer for the
    regex checks, then discards it via ZeroFreeBSTR in a finally block. Returns $true
    on success; throws a precise reason per failing class (length, upper, lower,
    digit, symbol). Length comes from security.passwordGeneration.length (default 20).
#>

Set-StrictMode -Version Latest

function Test-AdmanPasswordComplexity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][securestring]$Password,
        [int]$MinLength = 20
    )

    # Transient plaintext for validation only. BSTR is zeroed in finally.
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ($plain.Length -lt $MinLength) {
            throw "Password must be at least $MinLength characters (got $($plain.Length))."
        }
        # Case-SENSITIVE class checks (-cmatch): the default -match is case-insensitive and
        # would false-pass a no-uppercase sample (it would match a lowercase letter against
        # the [A-Z] class). The generator's alphabet is case-sensitive; the validator must be
        # too, or a typed password missing an entire class would be silently accepted.
        if ($plain -cnotmatch '[A-Z]') { throw 'Password must contain at least one uppercase letter.' }
        if ($plain -cnotmatch '[a-z]') { throw 'Password must contain at least one lowercase letter.' }
        if ($plain -notmatch '\d')     { throw 'Password must contain at least one digit.' }
        if ($plain -notmatch '[^A-Za-z0-9]') { throw 'Password must contain at least one symbol.' }
        return $true
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
