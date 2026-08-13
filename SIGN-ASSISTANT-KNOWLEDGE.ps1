[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [string]$KnowledgePath = (Join-Path $PSScriptRoot 'tool-assistant-knowledge-v1.1.json'),
    [string]$SignaturePath = '',
    [Parameter(Mandatory = $true, ParameterSetName = 'Store')][string]$CertificateThumbprint,
    [Parameter(ParameterSetName = 'Store')][ValidateSet('CurrentUser','LocalMachine')][string]$StoreLocation = 'CurrentUser',
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][string]$PfxPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][Security.SecureString]$PfxPassword
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Security

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Get-KnowledgeSigningCertificate {
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

$fullKnowledgePath = [IO.Path]::GetFullPath($KnowledgePath)
if (-not (Test-Path -LiteralPath $fullKnowledgePath -PathType Leaf)) { throw "Khong tim thay tep tri thuc: $fullKnowledgePath" }
$knowledgeItem = Get-Item -LiteralPath $fullKnowledgePath -Force
if (($knowledgeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $knowledgeItem.Length -le 16 -or $knowledgeItem.Length -gt 2097152) {
    throw 'Tep tri thuc khong an toan hoac vuot gioi han 2 MiB.'
}
if ([string]::IsNullOrWhiteSpace($SignaturePath)) { $SignaturePath = $fullKnowledgePath + '.p7s' }
$fullSignaturePath = [IO.Path]::GetFullPath($SignaturePath)
$knowledge = Get-Content -LiteralPath $fullKnowledgePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if ([string]$knowledge.SchemaVersion -ne '1.1' -or [string]$knowledge.Scope -ne 'Tool-Kiem-Tra' -or
    [Version]([string]$knowledge.KnowledgeVersion) -lt [Version]'1.3.0' -or @($knowledge.Entries).Count -lt 20) {
    throw 'Tep tri thuc khong dung schema, pham vi hoac phien ban toi thieu.'
}

$certificate = Get-KnowledgeSigningCertificate
try {
    if (-not $certificate.HasPrivateKey) { throw 'Chung thu khong co private key.' }
    if ($certificate.PublicKey.Oid.Value -ne '1.2.840.113549.1.1.1') { throw 'Chung thu phai dung khoa RSA.' }
    $now = Get-Date
    if ($now -lt $certificate.NotBefore -or $now -gt $certificate.NotAfter) { throw 'Chung thu chua hieu luc hoac da het han.' }

    $knowledgeBytes = [IO.File]::ReadAllBytes($fullKnowledgePath)
    $contentInfo = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$knowledgeBytes)
    $signedCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($contentInfo, $true)
    $signer = New-Object Security.Cryptography.Pkcs.CmsSigner -ArgumentList $certificate
    $signer.IncludeOption = [Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
    $signer.DigestAlgorithm = New-Object Security.Cryptography.Oid('2.16.840.1.101.3.4.2.1')
    $signedCms.ComputeSignature($signer, $false)
    $signatureBytes = $signedCms.Encode()

    $verificationContent = New-Object Security.Cryptography.Pkcs.ContentInfo -ArgumentList (,$knowledgeBytes)
    $verificationCms = New-Object Security.Cryptography.Pkcs.SignedCms -ArgumentList @($verificationContent, $true)
    $verificationCms.Decode($signatureBytes)
    $verificationCms.CheckSignature($true)
    if ($verificationCms.SignerInfos.Count -ne 1 -or
        (Get-Sha256Hex -Bytes $verificationCms.SignerInfos[0].Certificate.RawData) -ne (Get-Sha256Hex -Bytes $certificate.RawData)) {
        throw 'Khong xac minh duoc chu ky vua tao.'
    }

    $signatureDirectory = Split-Path -Parent $fullSignaturePath
    if (-not (Test-Path -LiteralPath $signatureDirectory -PathType Container)) { New-Item -ItemType Directory -Path $signatureDirectory -Force | Out-Null }
    $temporarySignature = Join-Path $signatureDirectory ('.knowledge-signature-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporarySignature, $signatureBytes)
        Move-Item -LiteralPath $temporarySignature -Destination $fullSignaturePath -Force
    } finally {
        if (Test-Path -LiteralPath $temporarySignature -PathType Leaf) { Remove-Item -LiteralPath $temporarySignature -Force -ErrorAction SilentlyContinue }
    }

    Write-Host "SIGNED KNOWLEDGE: $fullKnowledgePath"
    Write-Host "  Signature: $fullSignaturePath"
    Write-Host "  Knowledge version: $($knowledge.KnowledgeVersion)"
    Write-Host "  Signer certificate SHA-256: $(Get-Sha256Hex -Bytes $certificate.RawData)"
    Write-Host "  Knowledge SHA-256: $(Get-Sha256Hex -Bytes $knowledgeBytes)"
    Write-Host "  Signature SHA-256: $(Get-Sha256Hex -Bytes $signatureBytes)"
} finally {
    if ($certificate -and $PSCmdlet.ParameterSetName -eq 'Pfx') { $certificate.Dispose() }
}
