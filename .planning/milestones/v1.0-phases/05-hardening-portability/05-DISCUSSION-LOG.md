# Phase 5: Hardening & Portability - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-20
**Phase:** 5-Hardening & Portability
**Areas discussed:** Documentation structure, Inline help enforcement, Dual-edition CI/signing, Operational hardening
**Mode:** `--auto` — all gray areas auto-selected with recommended defaults.

---

## Area 1 — Documentation deliverables (DOC-01/02)

| Option | Description | Selected |
|--------|-------------|----------|
| README + standalone usage guide | Refresh README for install/first-run/safety; add `docs/USAGE.md` for action-by-action reference. | ✓ |
| Single monolithic README | Put everything in README.md. | |

**User's choice:** [auto] README + standalone usage guide (recommended default)
**Notes:** README currently claims "Phase 0 only" and must be refreshed to reflect Phases 0–4 shipped state. `Get-AdmanMenuDefinition` and `adman.psd1 FunctionsToExport` are the sources of truth for the usage guide.

---

## Area 2 — Inline help enforcement (DOC-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Pester contract test | Iterate exported functions and assert `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for each declared parameter, plus at least one `.EXAMPLE`. | ✓ |
| PSScriptAnalyzer-only | Rely on existing PSSA rules for help coverage. | |

**User's choice:** [auto] Pester contract test (recommended default)
**Notes:** PSScriptAnalyzer does not enforce parameter-level help; a Pester test closing the loop on `FunctionsToExport` is the reliable path.

---

## Area 3 — Dual-edition support and Authenticode signing

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Actions matrix + self-signed CI signing | Add `.github/workflows/ci.yml` running PSScriptAnalyzer + Pester on 5.1 and 7.6; sign with a generated self-signed cert for the `AllSigned` test. | ✓ |
| Manual scripts only | Provide local test scripts; no CI. | |

**User's choice:** [auto] GitHub Actions matrix + self-signed CI signing (recommended default)
**Notes:** Integration tests remain lab-only. `CompatiblePSEditions` in `adman.psd1` flips to `('Desktop','Core')` only after the matrix passes. Production signing uses enterprise PKI documented in README.

---

## Area 4 — Operational hardening

| Option | Description | Selected |
|--------|-------------|----------|
| Full package | Audit hash-chain + rotation + event-log forwarding; credential portability documented only; recovery runbook; `.store/` pre-commit hook + CI guard. | ✓ |
| Minimal hardening | Keep existing audit as-is; only add `.gitignore` check. | |

**User's choice:** [auto] Full package (recommended default)
**Notes:** Audit hardening is additive to the existing fail-closed writer. Hash-chain is tamper-evidence, not tamper-proof. Rotation archives files older than `audit.retentionDays` (default 90). Recovery runbook is human documentation, not a new command.

---

## Claude's Discretion

- Exact GitHub Actions versions/setup for PowerShell 7.6 LTS.
- Exact hash serialization/archive folder naming.
- Self-signed cert generation parameters in CI.
- Choice of help parser (`Get-Help` AST vs PlatyPS).

## Deferred Ideas

- Remote syslog/SIEM forwarding — v2/operational scope.
- Encrypted audit / BitLocker policy — operational scope.
- HSM-backed certificate renewal — enterprise PKI ops.
- Cross-forest portability (`PLAT-V04`) — v2 scope.
- Compiled `.exe` distribution (`PLAT-V02`) — v2 scope.
- Persisted bulk job state (`BULK-V01`) — v2 scope.
