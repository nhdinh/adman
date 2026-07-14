# Spike Manifest

## Idea

Local-admin lifecycle on domain-joined machines: scan for local administrator accounts across a fleet, disable/reset/create them remotely, mint servicing accounts with cryptographically-random passwords, and persist the rotated credentials in a queryable vault so a later session can recover "what's the current local admin password on machine X."

This capability area covers **LUSR-01 / LUSR-02** (Phase 2, local user lifecycle) and depends on **RMT-01 / RMT-02** (Phase 3, transport ladder). The spike resolves whether the connector primitive must land earlier than Phase 3, and whether a custom DPAPI vault is the right shape for the "query later" requirement (vs. adopting Windows LAPS).

## Requirements

Design decisions captured as they emerge from user choices during spiking. Non-negotiable for the real build.

- **Custom DPAPI vault, not LAPS.** Domain does not have Windows LAPS / legacy LAPS deployed (or unknown). Build the vault. Surface LAPS-detection as a startup capability probe in a later phase but do not block on it. (Decision 2026-07-14)
- **Remote spikes require a domain-joined MEMBER machine** — the lab DC is not a valid target because its local SAM is the AD database. Spike 001/002/003 are BLOCKED until the fixture exists. (Decision 2026-07-14)
- **Stop on first invalidation.** Build sequentially in risk order; halt and reassess if a HIGH-risk spike invalidates a core assumption. (Decision 2026-07-14)
- **All safety-gate invariants still apply.** Mutations route through `Invoke-AdmanMutation`, preview ≡ execute, fail-closed audit, no secrets in logs or repo. `.store/` is gitignored.

## Spikes

| # | Name | Type | Validates | Verdict | Tags |
|---|------|------|-----------|---------|------|
| 001 | transport-ladder-probe | standard | WinRM → CIM/WSMan → CIM/DCOM → skip ladder classifies alive/dead/DC-only hosts without hanging | **BLOCKED** (fixture) | remoting, transport |
| 002 | local-admin-inventory | standard | Enumerate local admins (incl. renamed RID-500) with enabled/lastlogon/password-age via the working transport | **BLOCKED** (fixture) | remoting, localaccounts |
| 003 | local-admin-mutation-via-gate | standard | Disable/reset/create local admin via `Invoke-Command` + `LocalAccounts` through the existing gate, without double-hop | **BLOCKED** (fixture) | remoting, localaccounts, safety |
| 004 | secure-password-generation | standard | CSPRNG-backed passwords (len 20, 4 classes, no ambiguous), 1000/1000 unique, works on PS 5.1 + 7 | **VALIDATED** | crypto, passwords |
| 005 | dpapi-vault-roundtrip | standard | Rotation-record store in `.store/`, same-user retrieve, cross-user fail, 500-record query < 100ms, history preserved | PENDING | dpapi, secrets, storage |
