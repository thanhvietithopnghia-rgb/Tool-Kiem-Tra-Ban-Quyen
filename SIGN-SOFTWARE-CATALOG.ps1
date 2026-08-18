[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [string]$CatalogPath = 'software-license-catalog-v1.0.json',
    [string]$SignaturePath = '',
    [Parameter(Mandatory = $true, ParameterSetName = 'Store')][string]$CertificateThumbprint,
    [Parameter(ParameterSetName = 'Store')][ValidateSet('CurrentUser','LocalMachine')][string]$StoreLocation = 'CurrentUser',
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][string]$PfxPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][Security.SecureString]$PfxPassword
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Security

function Get-CatalogSha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Get-CatalogSigningCertificate {
    if ($PSCmdlet.ParameterSetName -eq 'Store') {
        $normalized = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
        if ($normalized -notmatch '^[A-F0-9]{40,64}$') { throw 'Thumbprint chung thu khong hop le.' }
        $certificatePath = "Cert:\$StoreLocation\My\$normalized"
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw "Khong tim thay chung thu trong $StoreLocation\My." }
        return Get-Item -LiteralPath $certificatePath -ErrorAction Stop
    }

    $fullPfxPath = [IO.Path]::GetFullPath($PfxPath)
    if (-not (Test-Path -LiteralPath $fullPfxPath -PathType Leaf)) { throw 'Khong tim thay PFX.' }
    $pfxItem = Get-Item -LiteralPath $fullPfxPath -Force
    if (($pfxItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $pfxItem.Length -le 0 -or $pfxItem.Length -gt 10485760) {
        throw 'PFX khong an toan hoac co kich thuoc khong hop le.'
    }
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PfxPassword)
        $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        return New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(
            $fullPfxPath,
            $passwordText,
            [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
        )
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $passwordText = $null
    }
}

if (-not [IO.Path]::IsPathRooted($CatalogPath)) { $CatalogPath = Join-Path $PSScriptRoot $CatalogPath }
$fullCatalogPath = [IO.Path]::GetFullPath($CatalogPath)
if (-not (Test-Path -LiteralPath $fullCatalogPath -PathType Leaf)) { throw "Khong tim thay catalog: $fullCatalogPath" }
$catalogItem = Get-Item -LiteralPath $fullCatalogPath -Force
if (($catalogItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $catalogItem.Length -le 16 -or $catalogItem.Length -gt 2097152) {
    throw 'Catalog khong an toan hoac vuot gioi han 2 MiB.'
}
if ([string]::IsNullOrWhiteSpace($SignaturePath)) { $SignaturePath = $fullCatalogPath + '.p7s' }
elseif (-not [IO.Path]::IsPathRooted($SignaturePath)) { $SignaturePath = Join-Path $PSScriptRoot $SignaturePath }
$fullSignaturePath = [IO.Path]::GetFullPath($SignaturePath)
$catalog = Get-Content -LiteralPath $fullCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
$catalogVersion = [Version]'0.0'
try { $catalogVersion = [Version]([string]$catalog.CatalogVersion) } catch { throw 'CatalogVersion khong hop le.' }
$productIds = @($catalog.Products | ForEach-Object { [string]$_.Id })
if ([string]$catalog.SchemaVersion -ne '1.0' -or $catalogVersion -lt [Version]'1.0.0.0' -or
    $productIds.Count -lt 1 -or $productIds.Count -gt 5000 -or
    @($productIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
    @($productIds | Select-Object -Unique).Count -ne $productIds.Count) {
    throw 'Catalog khong dung schema, phien ban hoac danh sach san pham.'
}
if ($catalogVersion -ge [Version]'1.4.0.0' -and
    ([string]$catalog.SignatureAsset -ne 'software-license-catalog-v1.0.json.p7s' -or
     [string]::IsNullOrWhiteSpace([string]$catalog.CoveragePolicy) -or
     [string]::IsNullOrWhiteSpace([string]$catalog.UpdatePolicy))) {
    throw 'Catalog 1.4 tro len thieu metadata chu ky hoac chinh sach.'
}

$certificate = Get-CatalogSigningCertificate
try {
    if (-not $certificate.HasPrivateKey) { throw 'Chung thu khong co private key.' }
    if ($certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { throw 'Chung thu phai dung khoa RSA.' }
    $now = Get-Date
    if ($now -lt $certificate.NotBefore -or $now -gt $certificate.NotAfter) { throw 'Chung thu chua hieu luc hoac da het han.' }

    $catalogBytes = [IO.File]::ReadAllBytes($fullCatalogPath)
    $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$catalogBytes)
    $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
    $signer = New-Object Security.Cryptography.Pkcs.CmsSigner -ArgumentList $certificate
    $signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
    $signedCms.ComputeSignature($signer, $false)
    $signatureBytes = $signedCms.Encode()

    $verificationContent = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$catalogBytes)
    $verificationCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($verificationContent, $true)
    $verificationCms.Decode($signatureBytes)
    $verificationCms.CheckSignature($true)
    if ($verificationCms.SignerInfos.Count -ne 1 -or
        (Get-CatalogSha256Hex -Bytes $verificationCms.SignerInfos[0].Certificate.RawData) -ne (Get-CatalogSha256Hex -Bytes $certificate.RawData)) {
        throw 'Khong xac minh duoc chu ky vua tao.'
    }

    $signatureDirectory = Split-Path -Parent $fullSignaturePath
    if (-not (Test-Path -LiteralPath $signatureDirectory -PathType Container)) { New-Item -ItemType Directory -Path $signatureDirectory -Force | Out-Null }
    $temporarySignature = Join-Path $signatureDirectory ('.catalog-signature-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporarySignature, $signatureBytes)
        Move-Item -LiteralPath $temporarySignature -Destination $fullSignaturePath -Force
    } finally {
        if (Test-Path -LiteralPath $temporarySignature -PathType Leaf) { Remove-Item -LiteralPath $temporarySignature -Force -ErrorAction SilentlyContinue }
    }

    Write-Host "SIGNED SOFTWARE CATALOG: $fullCatalogPath"
    Write-Host "  Signature: $fullSignaturePath"
    Write-Host "  Catalog version: $catalogVersion"
    Write-Host "  Product rules: $($productIds.Count)"
    Write-Host "  Signer certificate SHA-256: $(Get-CatalogSha256Hex -Bytes $certificate.RawData)"
    Write-Host "  Catalog SHA-256: $(Get-CatalogSha256Hex -Bytes $catalogBytes)"
    Write-Host "  Signature SHA-256: $(Get-CatalogSha256Hex -Bytes $signatureBytes)"
} finally {
    if ($certificate -and $PSCmdlet.ParameterSetName -eq 'Pfx') { $certificate.Dispose() }
}
