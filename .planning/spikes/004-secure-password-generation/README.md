---
spike: 004
name: secure-password-generation
type: standard
validates: "Given a complexity policy (length 20, 4 character classes, no ambiguous glyphs), when generating N=1000 passwords via System.Security.Cryptography.RandomNumberGenerator on PS 5.1 and PS 7, then 100% pass policy, 100% are unique, and the per-position class distribution is uniform"
verdict: VALIDATED
related: []
tags: [crypto, passwords, cross-edition, ps5.1, ps7]
---

# Spike 004: Secure Password Generation

## What This Validates

**Given** a password-complexity policy (length 20, must contain at least one each of upper/lower/digit/symbol, must NOT contain ambiguous glyphs `0 O o l 1 I`),
**when** generating 1000 passwords via `[System.Security.Cryptography.RandomNumberGenerator]::Create()` + rejection sampling on both Windows PowerShell 5.1 and PowerShell 7,
**then** 100% pass the policy, 100% are unique, no ambiguous characters appear, and the per-position class distribution is statistically uniform.

## Research

| Approach | API | Pros | Cons | Verdict |
|----------|-----|------|------|---------|
| `Get-Random` | Built-in cmdlet | Idiomatic | **Not a CSPRNG** — uses `System.Random` on 5.1, `Random.Shared` on 7; seed-recoverable. Excluded by security requirement. | ✗ |
| `[System.Web.Security.Membership]::GeneratePassword()` | Legacy .NET Fx | One-liner | `System.Web` is Desktop-only (removed from PS 7 Core); deprecated; can emit ambiguous chars. | ✗ |
| `RandomNumberGenerator.GetInt32(min,max)` | .NET 6+ static method | Cleanest API, no modulo bias | **Does not exist on .NET Framework 4.x** — breaks the 5.1 baseline. | ✗ (5.1) |
| `RNGCryptoServiceProvider.GetBytes()` + rejection sampling | Works on .NET Fx 4.x **and** .NET 10 | CSPRNG-backed, bias-free, dual-edition | A few extra lines for rejection sampling | ✓ **CHOSEN** |

**Chosen approach:** `[System.Security.Cryptography.RandomNumberGenerator]::Create()` returns `RNGCryptoServiceProvider` on .NET Framework and the platform CSPRNG on .NET 10. Both are FIPS-validated. Rejection sampling eliminates modulo bias: for alphabet size N, draw uniform bytes and accept `b` only if `b < N * floor(256/N)` — rejection rate ~6% for N=76, negligible.

### Algorithm
1. Guarantee one char from each of the 4 classes (seed positions 0–3).
2. Fill remaining 16 chars from the 76-char union alphabet via rejection sampling.
3. Fisher-Yates shuffle the full 20-char array, using CSPRNG for swap indices (otherwise the guaranteed-class chars cluster at the front).

### Alphabet (76 chars, no ambiguous glyphs)
- Upper: `ABCDEFGHJKLMNPQRSTUVWXYZ` (23, excludes I/O)
- Lower: `abcdefghijkmnpqrstuvwxyz` (23, excludes l/o)
- Digit: `23456789` (8, excludes 0/1)
- Symbol: `!@#$%^&*-_=+[]{}|;:,.<>?` (22, shell-safe subset — no quotes/backslash/backtick)

## How to Run

```powershell
# PS 7
pwsh -NoProfile -File .\Invoke-Spike.ps1 -Count 1000 -Length 20

# PS 5.1
powershell.exe -NoProfile -File .\Invoke-Spike.ps1 -Count 1000 -Length 20
```

Outputs: `results.json` (machine-readable), `report.html` (visual), console summary, exit code 0 on PASS / 1 on FAIL.

## What to Expect

- `Verdict: PASS`
- 0 policy failures, 0 duplicates, 0 ambiguous-char hits
- Per-position class distribution within ±5% of alphabet-proportional (30/30/10/29)
- Throughput: ~800 passwords/s on PS 7, ~1800/s on PS 5.1 (both far above any conceivable need)

## Investigation Trail

### Iteration 1 — initial implementation
First run on PS 5.1 failed with `PropertyNotFoundStrict` on `(...).Count` when the `Where-Object` returned a single element. Under `Set-StrictMode -Version Latest`, PS 5.1 treats a scalar result as having no `.Count` property.
**Fix:** wrap in `@(...)` to force array. **Cross-edition convention candidate.**

### Iteration 2 — Hashtable with int keys
PS 7's `ConvertTo-Json` rejected the `$positionClassDist` hashtable: `The type 'System.Collections.Hashtable' is not supported for serialization ... Keys must be strings.` (PS 5.1 is lenient; PS 7 is strict.)
**Fix:** use `[string]$pos` keys. **Cross-edition convention candidate: always string-key Hashtables that may serialize to JSON.**

### Iteration 3 — `$OutputDir` came up empty on PS 5.1
When invoked via bash with forward-slash path (`-File 'C:/Users/...'`), `$PSScriptRoot` defaulted to empty on PS 5.1 (PS 7 normalizes the path). `Join-Path '' 'results.json'` threw.
**Fix:** defensive fallback `if (-not $OutputDir) { $OutputDir = Split-Path -Parent $MyInvocation.MyCommand.Path }`. **Note: always use backslash paths when invoking `powershell.exe -File` from bash.**

### Iteration 4 — false-positive "ambiguous char" hits (397/1000)
Policy test regex `[0Ol1I]` flagged 39.7% of passwords as containing ambiguous chars, but manual inspection showed none. Root cause: PowerShell's `-match` is **case-insensitive by default**, so the pattern matched `L` (Upper) and `i` (Lower) as false positives. My alphabets correctly exclude lowercase `l` and uppercase `I`, but include `L` and `i`.
**Fix:** use `-cmatch` for case-sensitive match; expand pattern to `[0Ool1I]` for completeness.

### Iteration 5 — per-position distribution skewed (Upper 57%, Lower 1%)
Uniformity check revealed Upper-class hit-rate ~57% at every position (expected ~30%) and Lower ~1% (expected ~30%). Same root cause as iteration 4: `-contains` is case-insensitive, so every lowercase letter was classified as "Upper".
**Fix:** use `-ccontains` for case-sensitive containment.

**Important:** the generator was always correct — both bugs were in the *measurement* code, not the generation. But this is precisely why the uniformity check exists: without it, the bug would have shipped.

### Iteration 6 — PASS on both editions
Final run: 1000/1000 unique, 0 policy failures, 0 ambiguous hits, per-position distribution uniform (Upper 26–31%, Lower 25–32%, Digit 11–15%, Symbol 26–32% — within expected variance including the guaranteed-class seeding bump).

## Results

| Metric | PS 7.6.0 (.NET 10) | PS 5.1 (.NET Fx 4.8) |
|--------|--------------------|----------------------|
| Verdict | **PASS** | **PASS** |
| Policy failures | 0 / 1000 | 0 / 1000 |
| Duplicates | 0 / 1000 | 0 / 1000 |
| Ambiguous-char hits | 0 / 1000 | 0 / 1000 |
| Throughput | 773 /s | 1838 /s |
| Total time (N=1000) | 1293 ms | 544 ms |

**Per-position class distribution (PS 7, all 20 positions):** Upper 26.4–31.0%, Lower 25.4–31.5%, Digit 11.2–14.9%, Symbol 26.1–31.8%. Within expected variance — the small Digit/Symbol bump is the guaranteed-class seeding (1 char of each class pre-seeded, so effective rate is slightly above alphabet-proportional). No positional bias.

### Surprises / Gotchas for the Build

1. **PowerShell's default case-insensitivity is a foot-gun.** `-match`, `-contains`, `-eq`, `-in` are all case-insensitive by default. Any code that distinguishes by case (password validation, character-class detection, filename comparison on case-sensitive filesystems) **must** use the `-c*` variants (`-cmatch`, `-ccontains`, `-ceq`, `-cin`). This will bite the project elsewhere — consider a PSScriptAnalyzer custom rule or a coding-standards note.

2. **PS 7 `ConvertTo-Json` is stricter than PS 5.1.** Hashtable keys must be strings; PS 5.1 silently coerces. Any JSON-serializable state should use `[ordered]@{}` (OrderedDictionary serializes cleanly on both) or string-keyed Hashtables.

3. **`Set-StrictMode -Version Latest` + `(...).Count` on scalar.** Wrap with `@(...)` defensively, or use `$null -eq $x` / explicit type checks. The project already mandates StrictMode Latest, so this convention matters.

4. **`RNGCryptoServiceProvider` is the cross-edition CSPRNG.** Don't be tempted by `RandomNumberGenerator.GetInt32()` — it's .NET 6+ only and breaks the 5.1 baseline.

5. **Throughput is a non-issue.** Even PS 7's slower path (773/s) is orders of magnitude above any realistic provisioning scenario. No perf concern for the build.

## Signal for the Build

- **Use** the rejection-sampling + Fisher-Yates recipe as-is. Lift `Get-CsprngIndex` and `New-AdmanRandomPassword` into `Private/Foundation/` or `Private/LocalAdmin/` for the LUSR-01 implementation.
- **Adopt** the 76-char no-ambiguous alphabet as the default policy; make length and class counts config-driven.
- **Codify** the case-sensitivity convention in `CONVENTIONS.md` — this is a cross-cutting concern, not just a password-gen issue.
