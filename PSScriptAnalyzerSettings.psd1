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

    # --- DOCUMENTED suppression convention ------------------------------------------------
    # PSAvoidUsingWriteHost is NOT suppressed globally. Individual files that legitimately
    # paint the console (e.g. TUI menu modules, offboarding checklists) must use a per-file
    # [Diagnostics.CodeAnalysis.SuppressMessage] attribute per CLAUDE.md convention.

    # --- DOCUMENTED fixture exclusion -------------------------------------------------------
    # tests/Fixtures/** are intentional positive/negative controls for the SAFE-08 guard tests
    # and are deliberately NOT lint-clean by design (they contain banned AD write verbs). The
    # repo-wide `Invoke-ScriptAnalyzer -Path . -Recurse` stays green because the custom rule
    # scopes to the real Public/ tree and therefore never inspects tests/Fixtures/**. Any future
    # rule scoped to tests/ MUST exclude tests/Fixtures/**.
}
