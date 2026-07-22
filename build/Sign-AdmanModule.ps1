#Requires -Version 5.1
<#
.SYNOPSIS
    Sign every .psd1, .psm1, and .ps1 file in the adman module with an Authenticode signature.

.DESCRIPTION
    Signs all module script and manifest files under the resolved module root, excluding the
    tests/, .github/, and .githooks/ directories. Supports passing an X509Certificate2 object,
    a code-signing certificate thumbprint from Cert:\CurrentUser\My, or a PFX file path.

.PARAMETER Certificate
    An X509Certificate2 code-signing certificate with a private key.

.PARAMETER CertificateThumbprint
    Thumbprint of a code-signing certificate in Cert:\CurrentUser\My.

.PARAMETER CertificateFilePath
    Path to a PFX file containing a code-signing certificate with a private key.

.PARAMETER ModulePath
    Path to the adman module manifest. Defaults to the adman.psd1 next to this script's parent directory.

.EXAMPLE
    PS> $cert = New-SelfSignedCertificate -Subject 'CN=adman CI Code Signing' -Type CodeSigning -CertStoreLocation Cert:\CurrentUser\My -HashAlgorithm sha256 -NotAfter (Get-Date).AddHours(1)
    PS> build\Sign-AdmanModule.ps1 -Certificate $cert
    Signs all adman module files using the supplied self-signed certificate.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByCertificate')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [Parameter(Mandatory, ParameterSetName = 'ByThumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory, ParameterSetName = 'ByFile')]
    [string]$CertificateFilePath,

    [Parameter(ParameterSetName = 'ByFile')]
    [Security.SecureString]$CertificatePassword,

    [string]$ModulePath = (Join-Path (Join-Path $PSScriptRoot '..') 'adman.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

switch ($PSCmdlet.ParameterSetName) {
    'ByCertificate' {
        $cert = $Certificate
    }
    'ByThumbprint' {
        $cert = Get-ChildItem -Path Cert:\CurrentUser\My |
            Where-Object { $_.Thumbprint -eq $CertificateThumbprint -and $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3' } |
            Select-Object -First 1
        if (-not $cert) {
            throw "No code-signing certificate with thumbprint '$CertificateThumbprint' found in Cert:\CurrentUser\My."
        }
    }
    'ByFile' {
        $resolvedPath = Resolve-Path -LiteralPath $CertificateFilePath | Select-Object -ExpandProperty Path
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "Certificate file not found: $CertificateFilePath"
        }
        # WR-07: avoid interactive Get-PfxCertificate prompt in non-interactive CI when a
        # password-protected PFX is supplied.
        if ($CertificatePassword) {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $resolvedPath, $CertificatePassword, 'Exportable')
        } else {
            $cert = Get-PfxCertificate -FilePath $resolvedPath
        }
    }
}

$manifest = Resolve-Path -Path $ModulePath | Select-Object -ExpandProperty Path
$moduleRoot = Split-Path -Parent -Path $manifest

$files = Get-ChildItem -Path $moduleRoot -Include '*.psd1', '*.psm1', '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\(tests|\.github|\.githooks)\\' }

if (-not $files) {
    throw "No .psd1/.psm1/.ps1 files found under $moduleRoot."
}

foreach ($file in $files) {
    if ($PSCmdlet.ShouldProcess($file.FullName, 'Set-AuthenticodeSignature')) {
        $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -HashAlgorithm SHA256
        if ($result.Status -ne 'Valid') {
            throw "Signing failed for $($file.FullName): $($result.StatusMessage)"
        }
    }
}
