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

    Validation:
      * Free-text inputs are trimmed and passed through; the underlying verb validates
        semantics.
      * Choice inputs (PromptSpec entries with a Choices array) accept only numeric
        indices 1..N or B/Q. Invalid input re-prompts with the standard copy:
        'Invalid selection. Enter a number, B, or Q.'

    This helper returns ONLY the parameters declared in the PromptSpec - no free-form
    code execution, no extra parameters (T-01-03).
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
        $name = [string]$field.Name
        $prompt = [string]$field.Prompt
        $required = [bool]$field.Required
        $choices = $null
        if ($field.PSObject.Properties.Name -contains 'Choices') {
            $choices = $field.Choices
        }

        $emptySeen = $false
        $resolved = $false

        while (-not $resolved) {
            if ($null -ne $choices -and @($choices).Count -gt 0) {
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

                $params[$name] = $trimmed
                $resolved = $true
            }
        }
    }

    return $params
}
