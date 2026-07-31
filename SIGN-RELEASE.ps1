[CmdletBinding(DefaultParameterSetName = "Store")]
param(
    [Parameter(Mandatory = $true)][string[]]$FilePath,
    [Parameter(Mandatory = $true, ParameterSetName = "Store")][string]$CertificateThumbprint,
    [Parameter(ParameterSetName = "Store")][ValidateSet("CurrentUser", "LocalMachine")][string]$StoreLocation = "CurrentUser",
    [Parameter(Mandatory = $true, ParameterSetName = "Pfx")][string]$PfxPath,
    [Parameter(Mandatory = $true, ParameterSetName = "Pfx")][Security.SecureString]$PfxPassword,
    [string]$TimestampServer = "http://timestamp.digicert.com",
    [switch]$RequireTrustedSignature
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Get-SigningCertificate {
    if ($PSCmdlet.ParameterSetName -eq "Store") {
        $normalized = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
        if ($normalized -notmatch '^[A-F0-9]{40,64}$') { throw "Thumbprint chứng thư không hợp lệ." }
        $certificatePath = "Cert:\$StoreLocation\My\$normalized"
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw "Không tìm thấy chứng thư trong $StoreLocation\My." }
        return Get-Item -LiteralPath $certificatePath -ErrorAction Stop
    }
    $fullPfxPath = [IO.Path]::GetFullPath($PfxPath)
    if (-not (Test-Path -LiteralPath $fullPfxPath -PathType Leaf)) { throw "Không tìm thấy PFX." }
    $info = Get-Item -LiteralPath $fullPfxPath -Force
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "PFX không được là symlink/reparse point." }
    if ($info.Length -le 0 -or $info.Length -gt 10485760) { throw "PFX có kích thước không hợp lệ." }
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PfxPassword)
        $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $flags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
        return New-Object -TypeName Security.Cryptography.X509Certificates.X509Certificate2 `
            -ArgumentList @($fullPfxPath, $passwordText, $flags)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $passwordText = $null
    }
}

function Test-CodeSigningCertificate {
    param([Parameter(Mandatory = $true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    if (-not $Certificate.HasPrivateKey) { throw "Chứng thư không có private key." }
    $now = Get-Date
    if ($now -lt $Certificate.NotBefore -or $now -gt $Certificate.NotAfter) { throw "Chứng thư chưa hiệu lực hoặc đã hết hạn." }
    $hasCodeSigningEku = $false
    foreach ($extension in @($Certificate.Extensions)) {
        if ($extension.Oid.Value -eq "2.5.29.37") {
            $eku = New-Object -TypeName Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension `
                -ArgumentList @($extension, [bool]$extension.Critical)
            foreach ($oid in @($eku.EnhancedKeyUsages)) {
                if ($oid.Value -eq "1.3.6.1.5.5.7.3.3") { $hasCodeSigningEku = $true }
            }
        }
    }
    if (-not $hasCodeSigningEku) { throw "Chứng thư không có EKU Code Signing (1.3.6.1.5.5.7.3.3)." }
}

$certificate = Get-SigningCertificate
try {
    Test-CodeSigningCertificate -Certificate $certificate
    foreach ($inputPath in $FilePath) {
        $fullPath = [IO.Path]::GetFullPath($inputPath)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Không tìm thấy artefact: $fullPath" }
        if ([IO.Path]::GetExtension($fullPath) -notin @(".exe", ".dll", ".ps1", ".psm1")) {
            throw "Không ký loại tệp ngoài EXE/DLL/PS1/PSM1: $fullPath"
        }
        $parameters = @{
            LiteralPath = $fullPath
            Certificate = $certificate
            HashAlgorithm = "SHA256"
        }
        if (-not [string]::IsNullOrWhiteSpace($TimestampServer)) { $parameters.TimestampServer = $TimestampServer }
        $result = Set-AuthenticodeSignature @parameters
        $verification = Get-AuthenticodeSignature -LiteralPath $fullPath
        if (-not $verification.SignerCertificate -or
            -not ([string]$verification.SignerCertificate.Thumbprint).Equals([string]$certificate.Thumbprint, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Tệp đã ký không chứa đúng signer certificate: $fullPath"
        }
        if ($RequireTrustedSignature -and $verification.Status -ne "Valid") {
            throw "Chữ ký chưa được Windows tin cậy: $($verification.Status) - $($verification.StatusMessage)"
        }
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        Write-Host "SIGNED: $fullPath"
        Write-Host "  Signer: $($certificate.Subject)"
        Write-Host "  Thumbprint: $($certificate.Thumbprint)"
        Write-Host "  Timestamp: $(if ($verification.TimeStamperCertificate) { $verification.TimeStamperCertificate.Subject } else { 'Không có' })"
        Write-Host "  Status: $($verification.Status)"
        Write-Host "  SHA-256: $hash"
    }
} finally {
    if ($certificate -and $PSCmdlet.ParameterSetName -eq "Pfx") { $certificate.Dispose() }
}
