#Requires -Version 5.1
<#
.SYNOPSIS
    New-AdmanRandomPassword - CSPRNG-backed password generator (D-05).

.DESCRIPTION
    Implements the Spike 004 validated recipe:
      * [System.Security.Cryptography.RandomNumberGenerator]::Create()
      * Rejection sampling (no modulo bias)
      * Fisher-Yates shuffle
      * 76-char no-ambiguous alphabet (23 upper + 23 lower + 8 digit + 22 symbol)
      * Length 20 default (config: security.passwordGeneration.length)
      * >= 1 char from each of 4 classes
    Returns a read-only [securestring]. Get-Random is NEVER used (not a CSPRNG);
    [System.Web.Security.Membership]::GeneratePassword is NEVER used (Desktop-only,
    dead on PS7). The SecureString is born here and passed ONLY into
    Set-ADAccountPassword -NewPassword / New-ADUser -AccountPassword - never
    marshaled to plaintext (no BSTR conversion anywhere in the codebase).
#>

Set-StrictMode -Version Latest

function Get-AdmanCsprngIndex {
    <#
    .SYNOPSIS
        Rejection-sample a uniform byte into [0, $AlphabetSize).
    .DESCRIPTION
        Avoids modulo bias: accept byte b only if b < AlphabetSize * floor(256/AlphabetSize).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.RandomNumberGenerator]$Rng,
        [Parameter(Mandatory)][int]$AlphabetSize
    )
    $limit = $AlphabetSize * [math]::Floor(256 / $AlphabetSize)
    $buf = [byte[]]::new(1)
    while ($true) {
        $Rng.GetBytes($buf)
        if ($buf[0] -lt $limit) { return $buf[0] % $AlphabetSize }
    }
}

function New-AdmanRandomPassword {
    <#
    .SYNOPSIS
        Generate a cryptographically secure random password as a read-only SecureString.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        # IN-03 fix: default sourced from the module-level constant so the fallback
        # is single-sourced. Callers that pass -Length explicitly are unaffected.
        [int]$Length = $script:DefaultPasswordLength
    )
    if ($Length -lt 4) { throw "Length must be >= 4 to guarantee all four character classes." }

    # 4 classes, no ambiguous glyphs (excludes 0 O o l 1 I).
    $Upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()   # 23 (excludes I, O)
    $Lower  = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray()   # 23 (excludes l, o)
    $Digit  = '23456789'.ToCharArray()                   # 8  (excludes 0, 1)
    $Symbol = '!@#$%^&*-_=+[]{}|;:,.<>?'.ToCharArray()   # 22 (shell-safe subset)
    $All    = $Upper + $Lower + $Digit + $Symbol         # 76

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        # Guarantee at least one of each class.
        $chars = [System.Collections.Generic.List[char]]::new($Length)
        $chars.Add($Upper[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Upper.Count)])
        $chars.Add($Lower[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Lower.Count)])
        $chars.Add($Digit[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Digit.Count)])
        $chars.Add($Symbol[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $Symbol.Count)])

        # Fill the rest from the union alphabet.
        for ($i = $chars.Count; $i -lt $Length; $i++) {
            $chars.Add($All[(Get-AdmanCsprngIndex -Rng $rng -AlphabetSize $All.Count)])
        }

        # Fisher-Yates shuffle using CSPRNG for the swap index.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = Get-AdmanCsprngIndex -Rng $rng -AlphabetSize ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }

        $secure = [securestring]::new()
        foreach ($c in $chars) { $secure.AppendChar($c) }
        $secure.MakeReadOnly()
        return $secure
    }
    finally {
        $rng.Dispose()
    }
}
