---
phase: 05-hardening-portability
plan: 01b
type: execute
wave: 1
depends_on: []
files_modified:
  - README.md
  - docs/USAGE.md
  - docs/RECOVERY-RUNBOOK.md
  - tests/Docs.Coverage.Tests.ps1
autonomous: true
requirements:
  - DOC-01
  - DOC-02
user_setup: []
must_haves:
  truths:
    - README.md explains install prerequisites (RSAT + PSFramework 1.14.457), first-run config wizard, safe-usage summary, and a "What works today" section reflecting Phases 0-4 shipped state (D-01)
    - docs/USAGE.md lists every menu entry from Get-AdmanMenuDefinition (label, required inputs, B/Q behavior) and every exported function from adman.psd1 FunctionsToExport with at least one example (D-01)
    - tests/Docs.Coverage.Tests.ps1 accesses the private Get-AdmanMenuDefinition through module scope after importing adman.psd1 and verifies menu/PromptSpec coverage deterministically (D-02)
    - docs/RECOVERY-RUNBOOK.md documents quarantine restore via Restore-AdmanQuarantinedUser, AD Recycle Bin restore cmdlets, authoritative restore warning/escalation, and self-signed code-signing certificate renewal / trust-anchor rotation (D-07, D-04)
    - README.md documents the self-signed Authenticode trust-anchor deployment path for a single-company deployment: generate a code-signing cert, export the public .cer, and deploy it to admin workstations via Group Policy Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers (D-04)
    - README.md documents how to enable the .store/ commit guard with the exact command `git config core.hooksPath .githooks` (D-08)
    - README.md or docs/USAGE.md explains that .store/config.json is portable but .store/adman.credential.xml is DPAPI-bound and must be recreated on a new machine/user via the normal prompt + remember-me flow (D-06)
  artifacts:
    - README.md
    - docs/USAGE.md
    - docs/RECOVERY-RUNBOOK.md
    - tests/Docs.Coverage.Tests.ps1
  key_links:
    - Get-AdmanMenuDefinition -> docs/USAGE.md menu section
    - adman.psd1 FunctionsToExport -> docs/USAGE.md exported functions section
    - docs/USAGE.md -> tests/Docs.Coverage.Tests.ps1 contract verification
    - docs/REMOTE-OPS.md -> README.md and docs/USAGE.md references
  prohibitions:
    - statement: Documentation must never include example passwords, real credential values, or live OU paths from the deployed config
      status: flagged-unverified
      verification: manual
---

<objective>
Refresh the README to reflect the shipped Phases 0-4 state, author a standalone usage guide and recovery runbook, and add a Pester contract test that verifies README/USAGE coverage against the manifest and menu definition.

Purpose: DOC-01/02 are the remaining documentation requirements. This plan makes the tool operable by a mixed-skill team and closes the loop on docs-to-code drift, while inline help enforcement is handled by 05-01a1, 05-01a2, and 05-01a3.
Output: README.md (including self-signed signing and commit-guard guidance), docs/USAGE.md, docs/RECOVERY-RUNBOOK.md (including certificate renewal/rotation), and tests/Docs.Coverage.Tests.ps1.
</objective>

<execution_context>
@C:/Users/nhdinh/.claude/gsd-core/workflows/execute-plan.md
@C:/Users/nhdinh/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/STATE.md
@.planning/phases/05-hardening-portability/05-CONTEXT.md
@.planning/phases/05-hardening-portability/05-RESEARCH.md
@.planning/phases/05-hardening-portability/05-PATTERNS.md
@.planning/phases/05-hardening-portability/05-VALIDATION.md
@.claude/CLAUDE.md
@adman.psd1
@Private/Menu/Get-AdmanMenuDefinition.ps1
@docs/REMOTE-OPS.md
@README.md
</context>

<assumptions>
The following edge probes from the spec-less probe fallback remain unresolved and are carried as explicit planning assumptions:

- DOC-02 / adjacency: When a menu label exactly matches a function name prefix, the usage guide separates the menu description from the function example without merging them.
- DOC-02 / empty: The usage guide still contains a meaningful entry for menu actions that have an empty PromptSpec (read-only reports and recovery posture).
- DOC-02 / ordering: Exported functions in docs/USAGE.md follow the order of adman.psd1 FunctionsToExport; menu actions follow the order returned by Get-AdmanMenuDefinition.
</assumptions>

<tasks>

<task type="auto" tdd="true">
  <name>Task 3: Refresh README.md, create docs/USAGE.md, docs/RECOVERY-RUNBOOK.md, and the docs coverage contract test</name>
  <files>README.md, docs/USAGE.md, docs/RECOVERY-RUNBOOK.md, tests/Docs.Coverage.Tests.ps1</files>
  <read_first>
    - README.md (current Phase 0-only content)
    - docs/REMOTE-OPS.md (keep and reference)
    - Private/Menu/Get-AdmanMenuDefinition.ps1 (source of truth for menu entries)
    - adman.psd1 (FunctionsToExport source of truth)
    - tests/Module.Manifest.Tests.ps1 (PSFramework stub + manifest import pattern)
    - tests/Menu.Tests.ps1 (private menu access pattern)
    - 05-PATTERNS.md (README and docs patterns)
  </read_first>
  <behavior>
    - RED: tests/Docs.Coverage.Tests.ps1 is created and fails because docs/USAGE.md and docs/RECOVERY-RUNBOOK.md do not yet exist and README.md lacks the required sections.
    - GREEN: After writing the docs, the test passes and enforces the README/USAGE coverage contract.
  </behavior>
  <action>
    Addresses review concern: Get-AdmanMenuDefinition is private; the docs coverage test must access it through module scope after importing the manifest, and PromptSpec coverage must be deterministic rather than brittle over optional fields.

    Rewrite README.md per D-01, D-04, D-06, and D-08: keep the safety-guarantees section, update "What works today" to list the shipped menu action categories and exported function groups, and add or refresh sections ## Installation (RSAT + PSFramework 1.14.457), ## First run (Initialize-Adman / Start-Adman), ## Safe usage (-WhatIf, confirmation, managed-OU scoping, deny-list, protected accounts), ## Project layout, ## Code signing and execution policy (D-04), and ## Commit guard (D-08). In the ## Basic usage example, remove the stale "Start-Adman (currently a stub; full TUI lands in Phase 1)" language and describe Start-Adman as the interactive menu entry point. Update the project-status wording so it no longer claims the project is Phase 0 only. The ## Code signing section must document the self-signed Authenticode trust-anchor deployment path for a single-company deployment: generate a code-signing cert, export the public .cer, and deploy it to admin workstations via Group Policy at Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers (add the .cer to Trusted Publishers; for a self-signed cert also add the .cer to Trusted Root Certification Authorities). The ## Commit guard section must contain the exact command `git config core.hooksPath .githooks`. Add a paragraph explaining that .store/config.json is portable but .store/adman.credential.xml is DPAPI-bound and must be recreated on a new machine/user via the normal prompt + remember-me flow (D-06).

    Create docs/USAGE.md by reading Get-AdmanMenuDefinition to enumerate every non-separator menu entry with its Label, Verb, PromptSpec fields (Name, Prompt, Required, Type, Choices), and note that B/Q navigate back/quit. Add an ## Exported functions section with one example per function in adman.psd1 FunctionsToExport, organized by category. Reference docs/REMOTE-OPS.md for remote-computer operations.

    Create docs/RECOVERY-RUNBOOK.md per D-07 and D-04 with sections: ## Restore from quarantine (Restore-AdmanQuarantinedUser), ## Restore from AD Recycle Bin (Get-ADObject -IncludeDeletedObjects | Restore-ADObject), ## Authoritative restore warning (when to escalate, never run an authoritative restore without a change control), and ## Certificate renewal and trust-anchor rotation (D-04). The certificate section must cover: generating a replacement code-signing cert before the old one expires, signing the module with the new cert, exporting the new public .cer, distributing the new .cer via the same GPO path while retaining the old .cer in Trusted Publishers until all signed-instances are retired, and finally removing the old .cer. Use contoso.local placeholders for all DNs and example values.

    Create tests/Docs.Coverage.Tests.ps1 per D-01/D-02. In BeforeDiscovery, set up the PSFramework 1.14.457 stub in $TestDrive\Modules, prepend it to $env:PSModulePath, import adman.psd1 with -Force, and capture the menu definition by invoking the private function through module scope: $menu = & (Get-Module adman) { Get-AdmanMenuDefinition }. Use ($menu | Where-Object { $_.Label -ne '---' }).Label for non-separator labels and parse the PromptSpec for each entry by serializing the object deterministically (e.g. ($_.PromptSpec | ConvertTo-Json -Compress) or a fixed property list). Parse docs/USAGE.md and assert that every non-separator menu Label appears at least once; every exported function name appears at least once under the ## Exported functions heading; and each function name under that heading is immediately followed by a fenced PowerShell code example (```powershell ... ``` block) before the next function heading or end of the section. For PromptSpec coverage, assert that each non-separator entry's PromptSpec is represented as a JSON snippet or a table row containing the Name and Prompt values; do not require optional fields (Type, Choices, Kind) to be present verbatim if they are absent from the source PromptSpec. Also assert that README.md contains the exact text `git config core.hooksPath .githooks`, a markdown heading matching `## Code signing`, and a line referencing `Trusted Publishers`. Assert docs/RECOVERY-RUNBOOK.md contains a heading matching `## Certificate renewal`.
  </action>
  <verify>
    <automated>Test-Path docs/USAGE.md; Test-Path docs/RECOVERY-RUNBOOK.md; Invoke-Pester -Path tests/Docs.Coverage.Tests.ps1 -Tag Unit; Select-String -Path README.md -Pattern '## Installation|## First run|## Safe usage|## What works today|## Code signing|## Commit guard'; Select-String -Path tests/Docs.Coverage.Tests.ps1 -Pattern '\(Get-Module adman\)'</automated>
  </verify>
  <done>
    README.md reflects Phases 0-4 shipped state, documents the self-signed signing trust-anchor deployment via GPO Trusted Publishers (D-04), documents the .store/ commit guard installation command (D-08), and explains the DPAPI-bound credential portability limitation (D-06). docs/USAGE.md covers every menu action and exported function and is verified by tests/Docs.Coverage.Tests.ps1. docs/RECOVERY-RUNBOOK.md covers quarantine restore, Recycle Bin restore, authoritative-restore escalation, and certificate renewal/trust-anchor rotation (D-04, D-07).
  </done>
  <acceptance_criteria>
    - README.md contains markdown headings ## Installation, ## First run, ## Safe usage, ## What works today, ## Code signing, and ## Commit guard
    - README.md contains the exact command `git config core.hooksPath .githooks`
    - README.md contains text describing deployment of the public .cer to Group Policy `Trusted Publishers` under `Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies`
    - README.md no longer describes Start-Adman as a stub or claims the project is Phase 0 only
    - docs/USAGE.md contains a section or table row for every non-separator Label returned by (Get-AdmanMenuDefinition).Label
    - docs/USAGE.md contains an ## Exported functions section with one fenced PowerShell example per function in adman.psd1 FunctionsToExport
    - docs/USAGE.md menu section includes the PromptSpec details (Prompt and Required values; Type/Choices/Kind only when present in the source) for each non-separator menu entry
    - docs/RECOVERY-RUNBOOK.md contains markdown headings ## Restore from quarantine, ## Restore from AD Recycle Bin, ## Authoritative restore warning, and ## Certificate renewal and trust-anchor rotation
    - tests/Docs.Coverage.Tests.ps1 invokes Get-AdmanMenuDefinition through module scope (`& (Get-Module adman) { ... }`) after importing adman.psd1
    - tests/Docs.Coverage.Tests.ps1 passes and enforces the README/USAGE coverage contract
    - README.md or docs/USAGE.md contains text explaining that `.store/config.json` is portable but `.store/adman.credential.xml` is DPAPI-bound and must be recreated on a new machine/user via the normal prompt + remember-me flow (D-06)
    - No example in any doc file contains a plaintext password or a live OU path from config/adman.defaults.json
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Documentation -> operator | Static docs must not give unsafe examples or expose internal bypass details. |
| Contributor -> README/docs | Docs are part of the safety contract; inaccurate examples can mislead operators. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-05-01b-01 | Information Disclosure | README.md / docs/USAGE.md examples | high | mitigate | Scrub all examples of passwords, credential values, and live OU paths; use contoso.local placeholders. |
| T-05-01b-02 | Information Disclosure | docs/RECOVERY-RUNBOOK.md | low | accept | Runbook is internal documentation; access control is repository/file-share permissions, not code. |
| T-05-01b-SC | Tampering | npm/pip/cargo installs | n/a | accept | This plan installs no packages. |
</threat_model>

<verification>
- Invoke-Pester -Path tests/Docs.Coverage.Tests.ps1 -Tag Unit passes.
- README.md, docs/USAGE.md, and docs/RECOVERY-RUNBOOK.md exist and contain the required sections.
- docs/USAGE.md menu section matches (Get-AdmanMenuDefinition).Label set; exported-function examples match adman.psd1 FunctionsToExport.
- README.md contains no plaintext passwords or live OU paths.
</verification>

<success_criteria>
- README, USAGE, and RECOVERY-RUNBOOK are complete, accurate, and contain no unsafe examples.
- tests/Docs.Coverage.Tests.ps1 passes and will fail the build if README/USAGE drift from the manifest or menu definition.
- README documents the self-signed signing trust-anchor deployment path and the .store/ commit guard installation command.
- README or USAGE documents DPAPI-bound credential portability limitation.
- RECOVERY-RUNBOOK documents certificate renewal and trust-anchor rotation.
</success_criteria>

<output>
Create `.planning/phases/05-hardening-portability/05-01b-SUMMARY.md` when done.
</output>

## Artifacts this plan produces

- README.md (refreshed)
- docs/USAGE.md (new)
- docs/RECOVERY-RUNBOOK.md (new)
- tests/Docs.Coverage.Tests.ps1 (new)
