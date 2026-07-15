# Deferred Items — Phase 01

Items discovered during execution that are out of scope for the current plan.

## Pre-existing lint failure (Harness.Tests.ps1 SAFE-01)

- **Discovered during:** Plan 01-02, Task 5 full-suite verification.
- **Issue:** `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1` reports two parse errors in `.planning/spikes/005-dpapi-vault-roundtrip/Test-CrossUser.ps1` (missing string terminator, missing closing curly brace). This causes the SAFE-01 lint-clean test in `tests/Harness.Tests.ps1` to fail.
- **Root cause:** The spike file was committed in `934c38a docs(spike-005): VALIDATED — DPAPI vault round-trip, indexed queries` and is not valid PowerShell. It is a spike artifact, not production code.
- **Why not fixed here:** Out of scope per deviation rules — pre-existing issue not caused by the current plan's changes. The plan's own files pass PSScriptAnalyzer cleanly.
- **Suggested fix:** Either fix the spike file's syntax, exclude `.planning/spikes/` from the lint path in `PSScriptAnalyzerSettings.psd1`, or delete the spike file if it has served its purpose.
- **Status:** Deferred to a future cleanup task or Phase 5 hardening.
