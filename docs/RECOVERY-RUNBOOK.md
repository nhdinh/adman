# adman Recovery Runbook

Operator reference for recovering AD objects and rotating the code-signing trust anchor used to sign the adman module.

## Restore from quarantine

When `Start-AdmanUserOffboarding` disables a user, it also moves the account into the configured quarantine OU. If the offboarding was performed in error, or if the user returns, restore the account with `Restore-AdmanQuarantinedUser`.

```powershell
# Preview the restore first
Restore-AdmanQuarantinedUser -Identity 'jdoe' -WhatIf

# Execute after confirming the preview
Restore-AdmanQuarantinedUser -Identity 'jdoe'
```

`Restore-AdmanQuarantinedUser` validates that:

- The source account currently lives in the configured quarantine OU.
- The destination OU is inside the managed-OU roots.
- The operation is written to the audit log before the move is applied.

If the account was deleted rather than quarantined, use the AD Recycle Bin path below.

## Restore from AD Recycle Bin

If the account was deleted after offboarding and Active Directory Recycle Bin is enabled, restore it without an authoritative restore.

```powershell
# List deleted objects matching the user
Get-ADObject -Filter "Name -like 'jdoe*'" -IncludeDeletedObjects |
    Where-Object { $_.ObjectClass -eq 'user' }

# Restore the object by GUID
Restore-ADObject -Identity 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
```

If the deleted object was a parent OU, restore the parent first, then its children. If the object has passed the tombstone lifetime (default 180 days), it is no longer in the Recycle Bin and an authoritative restore from backup is the only option.

## Authoritative restore warning

Do not run an Active Directory authoritative restore from backup unless:

- The object no longer exists in the AD Recycle Bin.
- A domain-wide disaster has occurred (for example, accidental bulk deletion of an OU tree).
- The restore is covered by a change control and has been approved by the directory engineering lead.

Authoritative restores roll back replication for the restored naming context and can undo legitimate changes made since the backup was taken. Always perform a non-authoritative restore first and only mark objects authoritative as a deliberate second step.

Escalation path:

1. Open a P1 incident with the identity platform team.
2. Restore a DC in DSRM and recover the required backup.
3. Use `ntdsutil authoritative restore` only on the specific objects or subtree required.
4. Validate replication and audit log integrity before returning the domain to normal operations.

## Certificate renewal and trust-anchor rotation

The adman module is signed with an Authenticode code-signing certificate. Before the certificate expires, generate a replacement, sign the module, and rotate the trust anchor on admin workstations.

### 1. Generate the replacement certificate

On a secure build host where the current certificate private key is available:

```powershell
$newCert = New-SelfSignedCertificate `
    -Subject 'CN=adman Internal Code Signing v2' `
    -Type CodeSigningCert `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(3)

Export-Certificate -Cert $newCert -FilePath 'C:\adman-certs\adman-signing-v2.cer'
```

### 2. Sign the module with the new certificate

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object {
        $_.Subject -eq 'CN=adman Internal Code Signing v2' -and
        $_.NotAfter -gt (Get-Date) -and
        $_.Thumbprint -eq 'A1B2C3D4E5F6...'  # Replace with the real thumbprint
    } | Select-Object -First 1

Get-ChildItem -Path 'C:\adman-build\adman' -Include '*.psd1','*.psm1','*.ps1' -Recurse -File |
    Where-Object FullName -notmatch '\\(tests|\.github|\.githooks)\\' |
    Set-AuthenticodeSignature -Certificate $cert -HashAlgorithm SHA256 `
        -TimestampServer 'http://timestamp.digicert.com'
```

### 3. Distribute the new public certificate

Deploy `adman-signing-v2.cer` to admin workstations via the same Group Policy path used for the original trust anchor:

- **Computer Configuration -> Policies -> Windows Settings -> Security Settings -> Public Key Policies -> Trusted Publishers**
  - Import `adman-signing-v2.cer`.
- For a self-signed certificate, also import the same `.cer` under **Trusted Root Certification Authorities**.

Keep the old certificate (`adman-signing-v1.cer`) in **Trusted Publishers** until every deployed copy of adman signed with the old certificate has been retired. This prevents execution-policy failures on workstations that still run the previous signed build.

### 4. Retire the old certificate

After all signed instances have been replaced and a reasonable overlap period has passed (for example, one business cycle or 30 days):

1. Remove the old `.cer` from **Trusted Publishers** in the GPO.
2. Remove the old `.cer` from **Trusted Root Certification Authorities** if it was deployed there.
3. Document the retirement date in the change control record.

### Emergency: certificate compromised

If the private key is suspected to be compromised:

1. Revoke or delete the compromised certificate from the build host.
2. Generate a new certificate with a new key pair immediately.
3. Re-sign the module.
4. Push the new public `.cer` to **Trusted Publishers** as an emergency GPO change.
5. Remove the compromised certificate from **Trusted Publishers** and **Trusted Root Certification Authorities** as soon as feasible.
6. Audit all code-signing events and review access to the build host.

---

*Last updated: 2026-07-22 for adman Phase 5.*
