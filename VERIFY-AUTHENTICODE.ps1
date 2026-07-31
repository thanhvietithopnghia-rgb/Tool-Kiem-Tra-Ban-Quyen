[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$FilePath,
    [string]$ExpectedThumbprint = "",
    [string]$ExpectedSubjectPattern = "",
    [switch]$RequireTimestamp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$failures = New-Object System.Collections.Generic.List[string]

foreach ($inputPath in $FilePath) {
    try {
        $fullPath = [IO.Path]::GetFullPath($inputPath)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Không tìm thấy tệp." }
        $signature = Get-AuthenticodeSignature -LiteralPath $fullPath
        if ($signature.Status -ne "Valid") { throw "Status=$($signature.Status); $($signature.StatusMessage)" }
        if (-not $signature.SignerCertificate) { throw "Thiếu signer certificate." }
        $certificate = $signature.SignerCertificate
        $hasCodeSigningEku = $false
        foreach ($extension in @($certificate.Extensions)) {
            if ($extension.Oid.Value -eq "2.5.29.37") {
                $eku = New-Object -TypeName Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension `
                    -ArgumentList @($extension, [bool]$extension.Critical)
                foreach ($oid in @($eku.EnhancedKeyUsages)) {
                    if ($oid.Value -eq "1.3.6.1.5.5.7.3.3") { $hasCodeSigningEku = $true }
                }
            }
        }
        if (-not $hasCodeSigningEku) { throw "Signer không có EKU Code Signing." }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedThumbprint) -and
            -not ([string]$certificate.Thumbprint).Equals(($ExpectedThumbprint -replace '\s',''), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Thumbprint signer không khớp."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSubjectPattern) -and [string]$certificate.Subject -notmatch $ExpectedSubjectPattern) {
            throw "Subject signer không khớp mẫu."
        }
        if ($RequireTimestamp -and -not $signature.TimeStamperCertificate) { throw "Thiếu timestamp certificate." }
        Write-Host "AUTHENTICODE OK: $([IO.Path]::GetFileName($fullPath))"
        Write-Host "  Signer: $($certificate.Subject)"
        Write-Host "  Thumbprint: $($certificate.Thumbprint)"
        Write-Host "  Timestamp: $(if ($signature.TimeStamperCertificate) { $signature.TimeStamperCertificate.Subject } else { 'Không bắt buộc/không có' })"
    } catch {
        [void]$failures.Add("$inputPath - $($_.Exception.Message)")
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    exit 1
}
exit 0
