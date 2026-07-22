---
phase: 05-hardening-portability
fixed_at: 2026-07-22T21:00:00Z
review_path: C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-07-22T21:00:00Z
**Source review:** C:/Users/nhdinh/dev/adman/.planning/phases/05-hardening-portability/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: New-AdmanLocalUser reintroduces the BL-03 password-disclosure bug

**Files modified:** `Public/New-AdmanLocalUser.ps1`
**Commit:** 4dcb251
**Applied fix:** Reordered per-call password-source resolution so an explicit `-Password` value forces the effective source to `Prompt`, preventing a caller-supplied secret from being printed as a generated password.

### WR-01: Set-AdmanConfig and Import-AdmanConfig bypass the CONF-02 fail-closed scope gate when ManagedOUs is $null

**Files modified:** `Public/Config/Set-AdmanConfig.ps1`, `Public/Config/Import-AdmanConfig.ps1`
**Commit:** 6e7e65e
**Applied fix:** Replaced `@($config.ManagedOUs).Count` with a null-aware count that filters whitespace entries, so a `$null` ManagedOUs correctly triggers the fail-closed throw.

### WR-02: New-AdmanLocalUser lacks a pre-mutation transcript guard for generated passwords

**Files modified:** `Public/New-AdmanLocalUser.ps1`
**Commit:** cda4a64
**Applied fix:** Added the same pre-mutation transcript guard used in sibling verbs; if a transcript is active and a password would be generated, the verb throws before creating the account.

### WR-03: Invoke-AdmanAuditRotation mutates the filesystem under -WhatIf

**Files modified:** `Private/Audit/Rotation.ps1`
**Commit:** 7e07eda
**Applied fix:** Moved archive directory creation and marker-file writing inside a dedicated `$PSCmdlet.ShouldProcess(...)` block, leaving only pure string computation outside the guard.

### WR-04: Get-AdmanStaleReport compares a UTC lastLogonTimestamp against a local-time cutoff

**Files modified:** `Public/Get-AdmanStaleReport.ps1`
**Commit:** 697cbd8
**Applied fix:** Changed stale-cutoff computation to `(Get-Date).ToUniversalTime().AddDays(-$graceDays)` so comparison against `[datetime]::FromFileTimeUtc(...)` is timezone-consistent.

### WR-05: build/Sign-AdmanModule.ps1 uses a 3-argument Join-Path incompatible with Windows PowerShell 5.1

**Files modified:** `build/Sign-AdmanModule.ps1`
**Commit:** fb96201
**Applied fix:** Nested `Join-Path` calls so the default `ModulePath` parameter binds correctly on Windows PowerShell 5.1.

### WR-06: Start-AdmanUserOffboarding relies on uninitialized protected-identity caches

**Files modified:** `Public/Start-AdmanUserOffboarding.ps1`
**Commit:** 0136e60
**Applied fix:** Added a fail-closed check that throws when the protected SID, deny RID, or protected group DN caches are not populated, preventing protected-group removal when `Initialize-Adman` has not run.

## Skipped Issues

None — all findings were fixed.

---

_Fixed: 2026-07-22T21:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
