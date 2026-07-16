#Requires -Version 5.1
<#
.SYNOPSIS
    Resolve-AdmanIdentity - prompt-time identity/OU-DN resolver for the menu layer.

.DESCRIPTION
    Single resolver used by Read-AdmanActionParams for Type='AdIdentity' and
    Type='AdOuDn' PromptSpec entries (G-02-2 / G-02-4). Catches malformed operator
    input at prompt time so the guided TUI re-prompts instead of crashing deep in
    the gate with a raw Get-ADObject error (UAT Tests 2 and 4).

    This function does NO scope checking and NO policy filtering. Managed-OU scope
    is enforced downstream by Test-AdmanTargetAllowed step (c) (SAFE-07) and the
    gate's Resolve-AdmanTarget still runs on the resolved DN. Both resolvers run
    in sequence: this one at prompt time, Resolve-AdmanTarget at gate time.

    -Server is ALWAYS pinned to $script:Config.DC on every AD cmdlet call.

    Kinds:
      * AdUser     - sAMAccountName or DN for a user object (Disable/Enable/Reset/
                     Unlock/Move user, group member).
      * AdComputer - sAMAccountName or DN for a computer object (Disable/Enable/
                     Move/Reset computer). For sAMAccountName lookup, BOTH forms
                     are tried in order (REV-3):
                       a. Exact:            sAMAccountName -eq 'NAME'
                       b. Trailing-dollar:  sAMAccountName -eq 'NAME$'
                     Computer sAMAccountName is conventionally 'NAME$'; operators
                     habitually type the bare 'NAME' form.
      * AdOuDn     - parent-OU / destination-OU prompt. Validates the input LOOKS
                     like a DN (contains '=' AND ',') and resolves to an existing
                     AD organizationalUnit object.

    DN shape detection: a DN contains '=' AND ','; a sAMAccountName does not.
    The resolver does NOT call ConvertTo-AdmanNormalizedDn - normalization is a
    scope-check concern handled downstream; prompt-time only needs shape detection.

    Throws typed errors on failure so Read-AdmanActionParams can Write-Host the
    message and re-prompt without crashing the menu loop.
#>

Set-StrictMode -Version Latest

function Resolve-AdmanIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputValue,

        [Parameter(Mandatory)]
        [ValidateSet('AdUser', 'AdComputer', 'AdOuDn')]
        [string]$Kind
    )

    # DN shape heuristic: a DN contains '=' AND ','; a sAMAccountName does not.
    $looksLikeDn = ($InputValue -match '=') -and ($InputValue -match ',')

    switch ($Kind) {
        'AdOuDn' {
            if (-not $looksLikeDn) {
                throw "'$InputValue' is not a distinguished name. Enter the full OU DN (e.g. OU=adman-test,DC=lab,DC=local)."
            }
            try {
                return Get-ADOrganizationalUnit -Identity $InputValue -Server $script:Config.DC `
                    -Properties DistinguishedName -ErrorAction Stop
            } catch {
                throw "Cannot resolve OU '$InputValue': $($_.Exception.Message)"
            }
        }

        'AdUser' {
            if ($looksLikeDn) {
                try {
                    return Get-ADObject -Identity $InputValue -Server $script:Config.DC `
                        -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop
                } catch {
                    throw "Cannot resolve identity '$InputValue' to an AD object: $($_.Exception.Message)"
                }
            }
            $esc = Escape-AdmanAdFilterLiteral -Value $InputValue
            $hits = @(Get-ADObject -Filter "sAMAccountName -eq '$esc'" -Server $script:Config.DC `
                -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop)
            if ($hits.Count -eq 0) {
                throw "No AD object found with sAMAccountName '$InputValue'."
            }
            if ($hits.Count -gt 1) {
                throw "Multiple AD objects match sAMAccountName '$InputValue'."
            }
            return $hits[0]
        }

        'AdComputer' {
            if ($looksLikeDn) {
                try {
                    return Get-ADObject -Identity $InputValue -Server $script:Config.DC `
                        -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop
                } catch {
                    throw "Cannot resolve identity '$InputValue' to an AD object: $($_.Exception.Message)"
                }
            }
            $esc = Escape-AdmanAdFilterLiteral -Value $InputValue
            # REV-3: try exact form first (operator typed 'PC01$' explicitly), then the
            # trailing-dollar form (operator typed bare 'PC01' - computer sAMAccountName
            # is conventionally 'PC01$').
            $exactHits = @(Get-ADObject -Filter "sAMAccountName -eq '$esc'" -Server $script:Config.DC `
                -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop)
            if ($exactHits.Count -gt 1) {
                throw "Multiple AD objects match sAMAccountName '$InputValue'."
            }
            if ($exactHits.Count -eq 1) {
                return $exactHits[0]
            }
            $dollarHits = @(Get-ADObject -Filter "sAMAccountName -eq '$esc`$'" -Server $script:Config.DC `
                -Properties objectSid, objectClass, DistinguishedName, memberOf -ErrorAction Stop)
            if ($dollarHits.Count -gt 1) {
                throw "Multiple AD objects match sAMAccountName '$InputValue`'$'."
            }
            if ($dollarHits.Count -eq 1) {
                return $dollarHits[0]
            }
            throw "No AD computer found with sAMAccountName '$InputValue' or '$InputValue`'$'."
        }
    }
}
