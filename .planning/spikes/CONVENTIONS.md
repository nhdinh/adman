# Spike Conventions

Patterns and stack choices established during spike sessions. New spikes follow these unless the question requires otherwise.

## Stack

- **Language:** PowerShell — Windows PowerShell 5.1 is the required baseline; PowerShell 7.6 LTS is the modern target. Every script must run on both editions.
- **CSPRNG:** `[System.Security.Cryptography.RandomNumberGenerator]::Create()` + `GetBytes()` + rejection sampling. Do **not** use `RandomNumberGenerator.GetInt32()` — it does not exist on .NET Framework 4.x (PS 5.1).
- **Secrets at rest:** DPAPI CurrentUser via `Export-Clixml` / `Import-Clixml`. SecureString fields inside an object graph are encrypted automatically. No manual `ConvertFrom-SecureString` per field.
- **Data interchange:** JSON for observability/results. Use `[ordered]@{}` or string-keyed Hashtables — PS 7's `ConvertTo-Json` rejects Hashtables with non-string keys; PS 5.1 is lenient.

## Structure

- One directory per spike: `.planning/spikes/NNN-descriptive-name/`
- Each spike has a `README.md` with YAML frontmatter and an executable script (`Invoke-Spike.ps1`).
- Generated artifacts (`results.json`, `report.html`) are kept as evidence unless they are large binaries.

## Patterns

### Cross-edition source compatibility

1. **Keep `.ps1` files ASCII-safe.** PS 5.1 reads BOM-less UTF-8 as ANSI, so non-ASCII characters (em dash, curly quotes, Unicode symbols) break the parser. If non-ASCII is required, emit a UTF-8 BOM. Prefer plain ASCII.

2. **Defensive `$PSScriptRoot` fallback.** When a script is invoked via `powershell.exe -File` with a forward-slash path from bash, `$PSScriptRoot` can be empty on PS 5.1. Use:
   ```powershell
   if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
       $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
   }
   ```

3. **Wrap `Where-Object` / `Sort-Object` results in `@(...)` before `.Count`.** Under `Set-StrictMode -Version Latest`, PS 5.1 throws `PropertyNotFoundException` on `.Count` for single-element scalar results.

4. **Use case-sensitive operators when case matters.** PowerShell defaults are case-insensitive:
   - `-match` → use `-cmatch`
   - `-contains` → use `-ccontains`
   - `-eq` → use `-ceq`
   - `-in` → use `-cin`
   This bit password validation (ambiguous-character detection) and character-class checks in spike 004. It will also bite OU/DN comparison, username comparison, and any binary-check logic.

5. **Avoid non-core module dependencies in spike scripts unless the spike is about that module.** `Microsoft.PowerShell.Security` auto-import is unreliable in some PS 5.1 environments; `Export-Clixml`/`Import-Clixml` (in `Microsoft.PowerShell.Utility`) are more reliable.

### Vault design

- Single `Export-Clixml` file with schema version header.
- In-memory hashtable index built on load for O(1) newest-wins lookups.
- Rotation history preserved as an append-only list of records.
- Concurrent writes require a mutex (same pattern as audit log).

## Tools & Libraries

- `Export-Clixml` / `Import-Clixml` — DPAPI-encrypted object graphs, cross-edition.
- `System.Security.Cryptography.RandomNumberProvider` (via `[System.Security.Cryptography.RandomNumberGenerator]::Create()`) — CSPRNG.
- `ConvertTo-Json -Depth N` — results/observability; mind Hashtables and depth.
