# adman Remote Operations Guide

> Operator reference for Phase 3 remote computer operations in adman.

## What adman Phase 3 does

Phase 3 performs **read-only, local-on-target CIM queries** against managed computers. When you run the fleet inventory report (`Get-AdmanInventoryReport`), adman probes each computer with this transport ladder:

1. WinRM (`Test-WSMan`)
2. CIM over WSMan (`New-CimSessionOption -Protocol Wsman`)
3. CIM over DCOM (`New-CimSessionOption -Protocol Dcom`)
4. Skip the host if none succeed

The winning transport is cached for the rest of the PowerShell process. For each reachable host, adman reads only these two local CIM classes:

- `Win32_OperatingSystem` — OS caption/version/service pack and last boot time
- `Win32_ComputerSystem` — logged-on console user

Hosts that cannot be reached, reject authentication, or exceed the configured time caps are reported as `Transport='Skipped'`. Phase 3 does **not** restart services, run `gpupdate`, or perform any other live action on remote machines.

## Double-hop problem in one paragraph

When you connect to a remote computer, Kerberos validates your identity to that computer but does **not** forward your credentials to a third machine. If the remote session then tries to reach a file share, another host, or Active Directory, the second hop fails with `ANONYMOUS LOGON` / `Access is denied`. This is by design, not a firewall or permission bug.

## adman stance: no second-hop operations in Phase 3

adman Phase 3 avoids the double-hop entirely:

- Queries read only `Win32_OperatingSystem` and `Win32_ComputerSystem` **on the target itself**.
- No AD cmdlets, no remote shares, and no other hosts are queried from inside the remote session.
- If a future code change requests a disallowed CIM class, the structural guard throws: `Second-hop operation not supported in adman remote queries.`

## CredSSP is excluded

CredSSP is **not used** as a transport option in Phase 3 and is excluded from v1 generally. CredSSP "fixes" the double hop by shipping reusable credentials to the hop host, which exposes them to theft if that host is compromised. Do not enable CredSSP to make adman inventory reads work.

## If you need second-hop later

For live actions that legitimately need a second hop (for example, reaching a file share or database from a remote endpoint), the preferred paths are:

- **Resource-Based Constrained Delegation (RBCD)** — configured on the destination to trust the intermediary. Requires Active Directory changes.
- **Just Enough Administration (JEA)** — a constrained endpoint on the intermediary using a virtual RunAs account. Requires endpoint configuration.

Both require infrastructure changes outside the adman module and are out of scope for Phase 3. If a future phase adds second-hop live actions, it must go through an RBCD/JEA design review, not CredSSP.

## Sensitive accounts

Accounts flagged **"Account is sensitive and cannot be delegated"** are unaffected by Phase 3 remote reads because adman requests no delegation at all. The tool reads local CIM classes with pass-through Kerberos/NTLM credentials only.

## Credentials in Phase 3 inventory reads

Inventory enrichment uses your existing Windows token via Kerberos or NTLM. adman does **not** prompt for alternate credentials during read-only remote queries. If your current token is not accepted by a target (for example, you are a delegated admin but not a local administrator on the workstation), that host is reported as `Transport='Skipped'` rather than elevating or forwarding credentials. Future live-action phases may add explicit credential forwarding through RBCD/JEA.

## Timeouts and dead hosts

Transport detection and CIM session setup are wrapped in hard-timeout `Start-Job` probes. A silently-dropped host cannot hang the menu. Hosts that exceed either of these config values are reported as `Transport='Skipped'`:

- `transport.timeouts.perHostProbeCap` — maximum seconds spent on a single host
- `transport.timeouts.totalInventoryRemoteCap` — maximum seconds for the whole remote-enrichment pass

If the total cap is reached, hosts already probed keep their results; all remaining hosts become `Skipped`.

## Firewall ports

The transport the tool uses depends on what the target host has open.

| Transport | Ports | Notes |
|-----------|-------|-------|
| WinRM / WSMan | TCP 5985 (HTTP), TCP 5986 (HTTPS) | Single fixed ports; easier to firewall |
| DCOM / classic WMI | TCP 135 + dynamic RPC range | Dynamic range is 49152–65535 by default on modern Windows |

To view the current dynamic RPC range on a target:

```powershell
# PowerShell
Get-NetFirewallRule -DisplayGroup 'Remote Service Management' | Get-NetFirewallPortFilter
# or
netsh int ipv4 show dynamicport tcp
```

A host showing `Transport='Skipped'` may simply be firewalled. Choosing which ports to open is an operator decision; adman does not modify firewalls or attempt to enable remoting on targets.

---

*Last updated: 2026-07-17 for adman Phase 3.*
