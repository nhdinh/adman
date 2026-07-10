@{
    # PSScriptAnalyzer settings for adman (SAFE-01 / SAFE-08 lint gate).
    # Wired into VS Code via powershell.scriptAnalysis.settingsPath.

    # --- Custom SAFE-08 rule host -----------------------------------------------------------
    # Single-sourced banned AD write cmdlets under Public/ (must resolve to this path or the
    # custom rule silently does not run).
    CustomRulePath = @('rules/AdmanSafetyRules.psm1')

    # --- Rule set (CLAUDE.md guardrails) ----------------------------------------------------
    # Only these rules run. PSUseShouldProcessForStateChangingFunctions directly enforces the
    # -WhatIf/dry-run guardrail (SAFE-01) on every state-changing function.
    IncludeRules   = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingPlainTextForPassword'
        'PSUsePSCredentialType'
        'PSAvoidGlobalVars'
        'PSUseApprovedVerbs'
        'PSAvoidUsingCmdletAliases'
        'PSUseConsistentIndentation'
    )

    # --- DOCUMENTED suppression (forward-declared) ------------------------------------------
    # PSAvoidUsingWriteHost is suppressed ONLY for the future TUI menu module
    # (e.g. Public/Menu*.ps1, Phase 1) - the menu legitimately paints the console. That module
    # does not exist in Phase 0, so the target is forward-declared here and will be paired with
    # a per-file [Diagnostics.CodeAnalysis.SuppressMessage] attribute when the menu lands.
    # No other rule is suppressed globally.
    Rules          = @{
        PSAvoidUsingWriteHost = @{
            Enable = $false
        }
    }

    # --- DOCUMENTED fixture exclusion -------------------------------------------------------
    # tests/Fixtures/** are intentional positive/negative controls for the SAFE-08 guard tests
    # and are deliberately NOT lint-clean by design (they contain banned AD write verbs). The
    # repo-wide `Invoke-ScriptAnalyzer -Path . -Recurse` stays green because the custom rule
    # scopes to the real Public/ tree and therefore never inspects tests/Fixtures/**. Any future
    # rule scoped to tests/ MUST exclude tests/Fixtures/**.
}
