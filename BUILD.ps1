[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipVerification,
    [string]$SigningCertificateThumbprint = '',
    [ValidateSet('CurrentUser','LocalMachine')][string]$SigningCertificateStore = 'CurrentUser',
    [string]$SigningPfxPath = '',
    [Security.SecureString]$SigningPfxPassword,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$RequireAuthenticode,
    [switch]$AllowUnsignedDevelopmentBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$productVersion = '4.8'
$releaseVersion = '4.8.0.1'
$releaseBuildDate = '2026.08.18'
$releaseLabel = "$releaseVersion-production-20260818"
$maximumInPlaceExecutableBytes = 900000
$sourceDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $sourceDirectory 'dist' }
$sourceName = "Tool-Kiem-Tra-v$productVersion-OneFile.cs"
$applicationManifestName = "Tool-Kiem-Tra-v$productVersion-OneFile.manifest"
$embeddedVerifierName = 'VERIFY-EMBEDDED-PAYLOAD.ps1'
$peHardeningName = 'PE-HARDENING.ps1'

if ($RequireAuthenticode -and $AllowUnsignedDevelopmentBuild) {
    throw 'Không được đồng thời bật RequireAuthenticode và AllowUnsignedDevelopmentBuild.'
}
if (-not $RequireAuthenticode -and -not $AllowUnsignedDevelopmentBuild) {
    throw 'Build stable bắt buộc Authenticode. Chỉ dùng -AllowUnsignedDevelopmentBuild cho artefact phát triển không phát hành.'
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    throw 'BUILD.ps1 phải chạy bằng Windows PowerShell 64-bit để build AnyCPU và kiểm tra trên cả CLR x64/x86.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Máy build phải là Windows 64-bit để kiểm tra cùng một EXE AnyCPU trên cả CLR x64/x86.'
}

$payloadFiles = @(
    'approved-kms-servers.txt',
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'VERSION-HISTORY-en-US.md',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-ElevatedBridge.ps1',
    'Tool-DataLifecycle.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-ScanOptimization.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
    'Tool-Assistant.ps1',
    'tool-assistant-knowledge-v1.1.json',
    'Tool-SoftwareInventory.ps1',
    'software-license-catalog-v1.0.json',
    'software-license-catalog-v1.0.json.p7s',
    'software-license-online-update.ps1',
    'Tool-UpdateManager.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1',
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1',
    'TOOL-SHA256SUMS.txt',
    'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1',
    'windows-license-restore.ps1',
    'windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1',
    'windows-oem-license-assistant.ps1',
    'windows-office-license-manager.ps1',
    'windows-license-assurance.ps1',
    'builtin-windows-office-trust.plugin.json'
)

$integrityFiles = @(
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'VERSION-HISTORY-en-US.md',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-ElevatedBridge.ps1',
    'Tool-DataLifecycle.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-ScanOptimization.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
    'Tool-Assistant.ps1',
    'tool-assistant-knowledge-v1.1.json',
    'Tool-SoftwareInventory.ps1',
    'software-license-catalog-v1.0.json',
    'software-license-catalog-v1.0.json.p7s',
    'software-license-online-update.ps1',
    'Tool-UpdateManager.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1',
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1',
    'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1',
    'windows-license-restore.ps1',
    'windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1',
    'windows-oem-license-assistant.ps1',
    'windows-office-license-manager.ps1',
    'windows-license-assurance.ps1',
    'builtin-windows-office-trust.plugin.json'
)

$sourceFiles = @(
    $payloadFiles
    '.gitattributes'
    '00-Tool-Kiem-Tra.ico'
    'BUILD.ps1'
    'DANH-GIA-VA-NANG-CAP-v4.8.md'
    'LICENSE-NOTICE.txt'
    'README.md'
    'README-MA-NGUON.md'
    'MODULE-CONTRACT-v1.0.md'
    'REPORT-SCHEMA-v1.5.md'
    'ROADMAP-v5.0.md'
    'SECURITY-HARDENING-v4.8.md'
    'TECHNICAL-ARCHITECTURE-v4.8.md'
    'ENTRY-POINTS-v4.8.md'
    'COMPATIBILITY-MATRIX-v4.8.md'
    'OFFLINE-AND-REPORTING-v4.8.md'
    'LOCALIZATION-v1.0.md'
    'SAFETY-POLICY-v1.0.md'
    $sourceName
    $applicationManifestName
    $embeddedVerifierName
    'VERIFY-FOUNDATION.ps1'
    'VERIFY-MODULE-CONTRACT.ps1'
    'VERIFY-REPORT-SCHEMA.ps1'
    'VERIFY-SAFETY-REGRESSIONS.ps1'
    'VERIFY-DASHBOARD.ps1'
    'VERIFY-EXTENSIONS.ps1'
    'VERIFY-ENTERPRISE.ps1'
    'VERIFY-COMPATIBILITY.ps1'
    'VERIFY-MICROSOFT-CATALOG-SOURCES.ps1'
    'VERIFY-OFFLINE-I18N.ps1'
    'VERIFY-LOCALIZATION-COVERAGE.ps1'
    'VERIFY-PERFORMANCE.ps1'
    'VERIFY-DATA-LIFECYCLE.ps1'
    'VERIFY-APPLICATION-UPDATE.ps1'
    'VERIFY-ASSISTANT.ps1'
    'SIGN-ASSISTANT-KNOWLEDGE.ps1'
    'tool-assistant-knowledge-v1.1.json.p7s'
    'SIGN-SOFTWARE-CATALOG.ps1'
    'SIGN-RELEASE.ps1'
    'VERIFY-AUTHENTICODE.ps1'
    $peHardeningName
    'VERIFY-RELEASE.ps1'
) | Select-Object -Unique

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function Write-SourcePackageHashManifest {
    $sourcePackageManifestPath = Join-Path $sourceDirectory 'SOURCE-PACKAGE-SHA256SUMS.txt'
    $sourcePackageRootPrefix = [IO.Path]::GetFullPath($sourceDirectory).TrimEnd('\') + '\'
    $outputRootPrefix = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\') + '\'
    $sourcePackageFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File -Force | Where-Object {
        $_.FullName -ne $sourcePackageManifestPath -and
        -not $_.FullName.StartsWith($outputRootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $_.FullName -notmatch '\\(?:\.git|dist(?:-[^\\]+)?|test)(?:\\|$)'
    } | Sort-Object { $_.FullName.Substring($sourcePackageRootPrefix.Length) })
    $sourcePackageManifestLines = @(
        "# SHA-256 cua toan bo goi ma nguon v$productVersion.0; khong tu liet ke tep manifest nay."
    )
    foreach ($file in $sourcePackageFiles) {
        $relativePath = $file.FullName.Substring($sourcePackageRootPrefix.Length)
        $sourcePackageManifestLines += "$(Get-Sha256Hex $file.FullName)  $relativePath"
    }
    [IO.File]::WriteAllLines(
        $sourcePackageManifestPath,
        $sourcePackageManifestLines,
        (New-Object Text.UTF8Encoding($false))
    )
}

function New-SolidPayloadBundle {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string[]]$PayloadFiles,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    [byte[]]$magic = [Text.Encoding]::ASCII.GetBytes('TVPBNDL1')
    [uint32]$formatVersion = 1
    [int64]$maximumPayloadBytes = 8MB
    [int64]$maximumBundlePayloadBytes = 16MB
    $payloadEntries = New-Object System.Collections.Generic.List[object]
    [int64]$payloadSourceBytes = 0
    foreach ($name in $PayloadFiles) {
        $path = Join-Path $SourceDirectory $name
        $length = [int64](Get-Item -LiteralPath $path).Length
        if ($length -lt 0 -or $length -gt $maximumPayloadBytes) {
            throw "Payload vượt giới hạn solid bundle: $name ($length / $maximumPayloadBytes byte)."
        }
        if ($payloadSourceBytes -gt ($maximumBundlePayloadBytes - $length)) {
            throw "Tổng payload vượt giới hạn solid bundle $maximumBundlePayloadBytes byte."
        }
        $payloadSourceBytes += $length
        [void]$payloadEntries.Add([pscustomobject]@{ Name=$name; Path=$path; Length=$length })
    }

    [int64]$headerBytes = $magic.Length + 4 + 4 + 8 + (8 * $payloadEntries.Count)
    $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = $null
    try {
        $writer = New-Object IO.BinaryWriter($output)
        $writer.Write($magic)
        $writer.Write([uint32]$formatVersion)
        $writer.Write([uint32]$payloadEntries.Count)
        $writer.Write([uint64]$payloadSourceBytes)
        foreach ($entry in $payloadEntries) { $writer.Write([uint64]$entry.Length) }
        $writer.Flush()

        foreach ($entry in $payloadEntries) {
            $input = [IO.File]::OpenRead($entry.Path)
            try { $input.CopyTo($output) }
            finally { $input.Dispose() }
        }
        $output.Flush()
    } finally {
        if ($writer) { $writer.Dispose() }
        else { $output.Dispose() }
    }

    return [pscustomobject]@{
        FormatVersion = [int]$formatVersion
        PayloadCount = [int]$payloadEntries.Count
        HeaderBytes = [int64]$headerBytes
        SourceBytes = [int64]$payloadSourceBytes
        BundleBytes = [int64]($headerBytes + $payloadSourceBytes)
        MaximumPayloadBytes = [int64]$maximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$maximumBundlePayloadBytes
        MaximumCompressedBytes = [int64](16MB)
        MaximumDecodedBytes = [int64](32MB)
    }
}

function New-DeflatedPayloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $input = [IO.File]::OpenRead($SourcePath)
    try {
        $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $deflate = New-Object IO.Compression.DeflateStream($output, [IO.Compression.CompressionLevel]::Optimal, $true)
            try { $input.CopyTo($deflate) }
            finally { $deflate.Dispose() }
        } finally { $output.Dispose() }
    } finally { $input.Dispose() }
}

function Find-CSharpCompiler {
    $candidates = New-Object System.Collections.Generic.List[object]
    $visualStudioRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'
    if (Test-Path -LiteralPath $visualStudioRoot -PathType Container) {
        foreach ($candidate in Get-ChildItem -LiteralPath $visualStudioRoot -Filter 'csc.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\MSBuild\\Current\\Bin\\Roslyn\\csc\.exe$' }) {
            [void]$candidates.Add($candidate)
        }
    }
    $nugetRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.nuget\packages\microsoft.net.compilers.toolset'
    if (Test-Path -LiteralPath $nugetRoot -PathType Container) {
        foreach ($candidate in Get-ChildItem -LiteralPath $nugetRoot -Filter 'csc.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\tasks\\net472\\csc\.exe$' }) {
            [void]$candidates.Add($candidate)
        }
    }
    $selected = @($candidates.ToArray() | Sort-Object { [Version]$_.VersionInfo.FileVersion } -Descending | Select-Object -First 1)
    if ($selected.Count -eq 1) { return $selected[0].FullName }
    throw 'Không tìm thấy Roslyn csc.exe. Hãy cài Visual Studio Build Tools (MSBuild/Roslyn); v4.6 không dùng compiler legacy vì cần deterministic build.'
}

function Get-VerificationPowerShell([string]$Architecture) {
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $path = if ($Architecture -eq 'x64') {
        Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        Join-Path $windowsDirectory 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu PowerShell $Architecture để kiểm tra build: $path" }
    return $path
}

$requiredFiles = @($payloadFiles | Where-Object { $_ -ne 'TOOL-SHA256SUMS.txt' }) + @(
    '00-Tool-Kiem-Tra.ico',
    'BUILD.ps1',
    'DANH-GIA-VA-NANG-CAP-v4.8.md',
    'LICENSE-NOTICE.txt',
    'README.md',
    'README-MA-NGUON.md',
    'MODULE-CONTRACT-v1.0.md',
    'REPORT-SCHEMA-v1.5.md',
    'ROADMAP-v5.0.md',
    'SECURITY-HARDENING-v4.8.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md',
    'ENTRY-POINTS-v4.8.md',
    'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md',
    'LOCALIZATION-v1.0.md',
    'SAFETY-POLICY-v1.0.md',
    $sourceName,
    $applicationManifestName,
    $embeddedVerifierName,
    'VERIFY-FOUNDATION.ps1',
    'VERIFY-MODULE-CONTRACT.ps1',
    'VERIFY-REPORT-SCHEMA.ps1',
    'VERIFY-SAFETY-REGRESSIONS.ps1',
    'VERIFY-DASHBOARD.ps1',
    'VERIFY-EXTENSIONS.ps1',
    'VERIFY-ENTERPRISE.ps1',
    'VERIFY-COMPATIBILITY.ps1',
    'VERIFY-OFFLINE-I18N.ps1',
    'VERIFY-LOCALIZATION-COVERAGE.ps1',
    'VERIFY-PERFORMANCE.ps1',
    'VERIFY-DATA-LIFECYCLE.ps1',
    'VERIFY-APPLICATION-UPDATE.ps1',
    'VERIFY-ASSISTANT.ps1',
    'SIGN-ASSISTANT-KNOWLEDGE.ps1',
    'tool-assistant-knowledge-v1.1.json.p7s',
    'SIGN-SOFTWARE-CATALOG.ps1',
    'SIGN-RELEASE.ps1',
    'VERIFY-AUTHENTICODE.ps1',
    $peHardeningName,
    'VERIFY-RELEASE.ps1'
)
foreach ($name in ($requiredFiles | Select-Object -Unique)) {
    $path = Join-Path $sourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu tệp nguồn bắt buộc: $name" }
}

. (Join-Path $sourceDirectory $peHardeningName)
. (Join-Path $sourceDirectory 'Tool-ModuleContract.ps1')
. (Join-Path $sourceDirectory 'Tool-ReportSchema.ps1')
. (Join-Path $sourceDirectory 'Tool-ReportExport.ps1')
. (Join-Path $sourceDirectory 'Tool-SafetyPolicy.ps1')
. (Join-Path $sourceDirectory 'Tool-Compatibility.ps1')
. (Join-Path $sourceDirectory 'Tool-Localization.ps1')
. (Join-Path $sourceDirectory 'Tool-OfflinePolicy.ps1')
. (Join-Path $sourceDirectory 'Tool-Assistant.ps1')
. (Join-Path $sourceDirectory 'Tool-SoftwareInventory.ps1')
$moduleContractMetadata = Get-ToolModuleContractMetadata
$reportSchemaMetadata = Get-ToolReportSchemaMetadata
$reportExportMetadata = Get-ToolReportExportMetadata
$safetyPolicyMetadata = Get-ToolSafetyPolicyMetadata
$compatibilityMetadata = Get-ToolCompatibilityMetadata
$localizationMetadata = Get-ToolLocalizationMetadata
$offlinePolicyMetadata = Get-ToolOfflinePolicyMetadata
$assistantMetadata = Get-ToolAssistantMetadata
$softwareCatalogMetadata = Import-ToolSoftwareCatalogFile `
    -Path (Join-Path $sourceDirectory 'software-license-catalog-v1.0.json') `
    -SignaturePath (Join-Path $sourceDirectory 'software-license-catalog-v1.0.json.p7s') `
    -Source 'Bundled' -RequireSignature
if (-not $softwareCatalogMetadata -or -not [bool]$softwareCatalogMetadata.CatalogSignatureValid) {
    throw 'Catalog phần mềm tích hợp thiếu chữ ký CMS hợp lệ từ signer đã ghim.'
}
$engineeringCatalogRules = @($softwareCatalogMetadata.Products | Where-Object {
    $_.PSObject.Properties['Category'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Category)
})
if ([string]$softwareCatalogMetadata.CatalogVersion -ne '1.4.0.0' -or
    @($softwareCatalogMetadata.Products).Count -lt 77 -or $engineeringCatalogRules.Count -lt 16) {
    throw 'Catalog phần mềm v4.8 chưa đạt phiên bản 1.4.0.0 / 77 quy tắc / 16 quy tắc kỹ thuật.'
}

Write-Host '[1/8] Tạo TOOL-SHA256SUMS.txt...'
$toolManifestLines = @(
    "# Manifest kiem tra toan ven bo Tool-Kiem-Tra v$productVersion.",
    '# approved-kms-servers.txt duoc loai tru vi la tep cau hinh duoc phep tuy chinh.'
)
foreach ($name in $integrityFiles) {
    $toolManifestLines += "$(Get-Sha256Hex (Join-Path $sourceDirectory $name))  $name"
}
[IO.File]::WriteAllLines(
    (Join-Path $sourceDirectory 'TOOL-SHA256SUMS.txt'),
    $toolManifestLines,
    (New-Object Text.UTF8Encoding($false))
)

Write-Host '[2/8] Tạo SOURCE-SHA256SUMS.txt...'
$sourceManifestLines = @(
    "# SHA-256 cua goi ma nguon Tool-Kiem-Tra v$productVersion.",
    '# SOURCE-SHA256SUMS.txt va tep build dau ra khong tu liet ke de tranh tham chieu vong.'
)
foreach ($name in $sourceFiles) {
    $path = Join-Path $sourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Không thể tạo source manifest; thiếu: $name" }
    $sourceManifestLines += "$(Get-Sha256Hex $path)  $name"
}
[IO.File]::WriteAllLines(
    (Join-Path $sourceDirectory 'SOURCE-SHA256SUMS.txt'),
    $sourceManifestLines,
    (New-Object Text.UTF8Encoding($false))
)

# Manifest này bao phủ toàn bộ gói mã nguồn bàn giao, kể cả tài liệu và workflow
# nằm trong thư mục con. Nó được tạo lại sau khi manifest cập nhật cuối cùng đã
# được đồng bộ về nguồn để không giữ hash của bản cũ.
Write-SourcePackageHashManifest

Write-Host '[3/8] Chuẩn bị thư mục đầu ra...'
if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$compiler = Find-CSharpCompiler
$compilerVersion = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
$payloadListArgument = $payloadFiles -join '|'
$targets = @(
    [pscustomobject]@{ Architecture='AnyCPU'; Platform='anycpu'; OutputName="Tool-Kiem-Tra-v$productVersion.exe"; HighEntropy=$true }
)
$artifactResults = New-Object System.Collections.Generic.List[object]
$embeddedPayloadResources = New-Object System.Collections.Generic.List[object]
$payloadCompressionStats = $null

foreach ($staleName in @("Tool-Kiem-Tra-v$productVersion-x64.exe", "Tool-Kiem-Tra-v$productVersion-x86.exe")) {
    $stalePath = Join-Path $OutputDirectory $staleName
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force }
}

$payloadBuildDirectory = Join-Path $OutputDirectory ('.payload-build-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $payloadBuildDirectory | Out-Null
    $payloadBundlePath = Join-Path $payloadBuildDirectory 'payload.bundle.v1'
    $compressedPayloadPath = Join-Path $payloadBuildDirectory 'payload.bundle.v1.deflate'
    $bundleStats = New-SolidPayloadBundle -SourceDirectory $sourceDirectory -PayloadFiles $payloadFiles -DestinationPath $payloadBundlePath
    New-DeflatedPayloadFile -SourcePath $payloadBundlePath -DestinationPath $compressedPayloadPath
    [int64]$payloadEmbeddedBytes = (Get-Item -LiteralPath $compressedPayloadPath).Length
    if ($payloadEmbeddedBytes -le 0 -or $payloadEmbeddedBytes -ge [int64]$bundleStats.BundleBytes) {
        throw "Solid payload bundle không được nén hợp lệ: $payloadEmbeddedBytes / $($bundleStats.BundleBytes) byte."
    }
    [void]$embeddedPayloadResources.Add([pscustomobject]@{
        Path = $compressedPayloadPath
        ResourceName = 'payload.bundle.deflate.v1'
        SourceBytes = [int64]$bundleStats.SourceBytes
        EmbeddedBytes = [int64]$payloadEmbeddedBytes
    })
    $payloadCompressionStats = [pscustomobject]@{
        Scheme = 'SolidDeflateBundle-v1'
        ResourceName = 'payload.bundle.deflate.v1'
        FormatVersion = [int]$bundleStats.FormatVersion
        ResourceCount = 1
        PayloadCount = [int]$bundleStats.PayloadCount
        HeaderBytes = [int64]$bundleStats.HeaderBytes
        SourceBytes = [int64]$bundleStats.SourceBytes
        BundleBytes = [int64]$bundleStats.BundleBytes
        EmbeddedBytes = [int64]$payloadEmbeddedBytes
        SavedBytes = [int64]$bundleStats.SourceBytes - $payloadEmbeddedBytes
        SavingsPercent = [math]::Round((1.0 - ($payloadEmbeddedBytes / [double]$bundleStats.SourceBytes)) * 100.0, 2)
        MaximumPayloadBytes = [int64]$bundleStats.MaximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$bundleStats.MaximumPayloadDataBytes
        MaximumCompressedBytes = [int64]$bundleStats.MaximumCompressedBytes
        MaximumDecodedBytes = [int64]$bundleStats.MaximumDecodedBytes
    }
    Write-Host "[4/8] Nhúng 49 payload vào một solid Deflate bundle; giảm $($payloadCompressionStats.SavingsPercent)%..."

    foreach ($target in $targets) {
    $outputPath = Join-Path $OutputDirectory $target.OutputName
    Write-Host "  - Build $($target.Architecture): $($target.OutputName)"
    $compilerArguments = @(
        '/nologo',
        '/target:winexe',
        "/platform:$($target.Platform)",
        '/deterministic+',
        "/pathmap:$sourceDirectory=C:\_src\Tool-Kiem-Tra-v4.8",
        '/langversion:5',
        '/debug-',
        '/optimize+',
        '/warn:4',
        '/codepage:65001',
        '/reference:System.dll',
        '/reference:System.Windows.Forms.dll',
        '/reference:System.Drawing.dll',
        "/win32icon:$(Join-Path $sourceDirectory '00-Tool-Kiem-Tra.ico')",
        "/win32manifest:$(Join-Path $sourceDirectory $applicationManifestName)",
        "/out:$outputPath"
    )
    if ($target.HighEntropy) { $compilerArguments += '/highentropyva+' }
    foreach ($resource in $embeddedPayloadResources) {
        $compilerArguments += "/resource:$($resource.Path),$($resource.ResourceName)"
    }
    $compilerArguments += (Join-Path $sourceDirectory $sourceName)

    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Biên dịch $($target.Architecture) thất bại, mã thoát: $LASTEXITCODE"
    }

    $profile = Get-PeSecurityProfile -Path $outputPath
    if ($profile.ManagedPlatform -ne 'AnyCPU') { throw "CLR flags không phải AnyCPU: $($profile.ManagedPlatform)." }
    foreach ($requiredFlag in @('DynamicBase', 'NxCompat', 'NoSeh', 'TerminalServerAware')) {
        if (-not [bool]$profile.$requiredFlag) { throw "Bản $($target.Architecture) thiếu cờ $requiredFlag." }
    }
    if ($profile.PeFormat -ne 'PE32' -or $profile.Machine -ne '0x014C' -or
        -not $profile.Managed -or -not $profile.ClrIlOnly -or
        $profile.Clr32BitRequired -or $profile.Clr32BitPreferred -or
        -not $profile.HighEntropyVa) {
        throw 'EXE chưa đúng AnyCPU: cần PE32/I386, ILONLY, không 32BITREQUIRED/32BITPREFERRED và bật HIGH_ENTROPY_VA.'
    }

    foreach ($runtimeArchitecture in @('x64', 'x86')) {
        $verificationPowerShell = Get-VerificationPowerShell $runtimeArchitecture
        & $verificationPowerShell -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $sourceDirectory $embeddedVerifierName) `
            -ExePath $outputPath -SourceDirectory $sourceDirectory -PayloadList $payloadListArgument -ExpectedArchitecture $runtimeArchitecture
        if ($LASTEXITCODE -ne 0) { throw "Đối chiếu cùng EXE AnyCPU trên CLR $runtimeArchitecture thất bại, mã thoát: $LASTEXITCODE" }
    }

    $signingRequested = -not [string]::IsNullOrWhiteSpace($SigningCertificateThumbprint) -or -not [string]::IsNullOrWhiteSpace($SigningPfxPath)
    if ($signingRequested) {
        Write-Host "  - Ký Authenticode SHA-256: $($target.OutputName)"
        $signingScript = Join-Path $sourceDirectory 'SIGN-RELEASE.ps1'
        if (-not [string]::IsNullOrWhiteSpace($SigningCertificateThumbprint)) {
            & $signingScript -FilePath $outputPath -CertificateThumbprint $SigningCertificateThumbprint `
                -StoreLocation $SigningCertificateStore -TimestampServer $TimestampServer -RequireTrustedSignature:$RequireAuthenticode
        } else {
            if ($null -eq $SigningPfxPassword) { throw 'SigningPfxPassword là bắt buộc khi dùng SigningPfxPath.' }
            & $signingScript -FilePath $outputPath -PfxPath $SigningPfxPath -PfxPassword $SigningPfxPassword `
                -TimestampServer $TimestampServer -RequireTrustedSignature:$RequireAuthenticode
        }
        if ($LASTEXITCODE -ne 0) { throw "Ký Authenticode thất bại, mã thoát: $LASTEXITCODE" }
    } elseif ($RequireAuthenticode) {
        throw 'RequireAuthenticode được bật nhưng chưa cung cấp chứng thư code-signing.'
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $outputPath
    if ($RequireAuthenticode -and $signature.Status -ne 'Valid') {
        throw "Artefact chưa có chữ ký Authenticode hợp lệ: $($signature.Status)"
    }
    $artifactLength = [int64](Get-Item -LiteralPath $outputPath).Length
    if ($artifactLength -gt $maximumInPlaceExecutableBytes) {
        throw "EXE vượt dung lượng bản v4.8 đang phát hành: $artifactLength / $maximumInPlaceExecutableBytes byte."
    }
    [void]$artifactResults.Add([pscustomobject]@{
        FileName = $target.OutputName
        Architecture = 'AnyCPU'
        RuntimeArchitecture = 'Auto: x64 on Windows 64-bit; x86 on Windows 32-bit'
        Sha256 = Get-Sha256Hex $outputPath
        AuthenticodeStatus = [string]$signature.Status
        AuthenticodeSigner = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        AuthenticodeThumbprint = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { '' }
        AuthenticodeTimestamped = [bool]($null -ne $signature.TimeStamperCertificate)
        PeProfile = $profile
    })
    }
} finally {
    if (Test-Path -LiteralPath $payloadBuildDirectory -PathType Container) {
        Remove-Item -LiteralPath $payloadBuildDirectory -Recurse -Force
    }
}

Write-Host '[5/8] Tạo metadata phát hành...'
foreach ($sidecar in @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICH-SU-PHIEN-BAN.txt', 'VERSION-HISTORY-en-US.md', 'LICENSE-NOTICE.txt',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md', 'ENTRY-POINTS-v4.8.md', 'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.8.md',
    'compatibility-catalog-v1.0.json', 'software-license-catalog-v1.0.json', 'software-license-catalog-v1.0.json.p7s', 'builtin-windows-office-trust.plugin.json', 'tool-assistant-knowledge-v1.1.json', 'tool-assistant-knowledge-v1.1.json.p7s'
)) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $sidecar) -Destination (Join-Path $OutputDirectory $sidecar) -Force
}

$manifestArtifacts = @($artifactResults.ToArray() | ForEach-Object {
    [ordered]@{
        FileName = $_.FileName
        Architecture = $_.Architecture
        RuntimeArchitecture = $_.RuntimeArchitecture
        Sha256 = $_.Sha256
        AuthenticodeStatus = $_.AuthenticodeStatus
        AuthenticodeSigner = $_.AuthenticodeSigner
        AuthenticodeThumbprint = $_.AuthenticodeThumbprint
        AuthenticodeTimestamped = $_.AuthenticodeTimestamped
        Pe = [ordered]@{
            Format = $_.PeProfile.PeFormat
            Machine = $_.PeProfile.Machine
            ManagedPlatform = $_.PeProfile.ManagedPlatform
            Managed = $_.PeProfile.Managed
            IlOnly = $_.PeProfile.ClrIlOnly
            Required32Bit = $_.PeProfile.Clr32BitRequired
            Preferred32Bit = $_.PeProfile.Clr32BitPreferred
            LargeAddressAware = $_.PeProfile.LargeAddressAware
            HighEntropyVa = $_.PeProfile.HighEntropyVa
            DynamicBase = $_.PeProfile.DynamicBase
            NxCompat = $_.PeProfile.NxCompat
            NoSeh = $_.PeProfile.NoSeh
            TerminalServerAware = $_.PeProfile.TerminalServerAware
            ControlFlowGuardHeader = $_.PeProfile.ControlFlowGuardHeader
            LoadConfigurationDirectoryPresent = $_.PeProfile.LoadConfigurationDirectoryPresent
        }
    }
})
$releaseManifestPath = Join-Path $OutputDirectory 'RELEASE-MANIFEST.json'
$releaseManifest = [ordered]@{
    SchemaVersion = '2.0'
    ToolVersion = $productVersion
    ReleaseVersion = $releaseVersion
    ReleaseBuildDate = $releaseBuildDate
    ReleaseLabel = $releaseLabel
    ReleaseStatus = 'Production'
    PrimaryFileName = "Tool-Kiem-Tra-v$productVersion.exe"
    RuntimeArchitecture = 'Auto: x64 on Windows 64-bit; x86 on Windows 32-bit'
    Artifacts = $manifestArtifacts
    PayloadCount = [int]$payloadFiles.Count
    IntegrityFileCount = [int]$integrityFiles.Count
    PayloadCompression = [ordered]@{
        Scheme = [string]$payloadCompressionStats.Scheme
        ResourceName = [string]$payloadCompressionStats.ResourceName
        FormatVersion = [int]$payloadCompressionStats.FormatVersion
        ResourceCount = [int]$payloadCompressionStats.ResourceCount
        PayloadCount = [int]$payloadCompressionStats.PayloadCount
        HeaderBytes = [int64]$payloadCompressionStats.HeaderBytes
        SourceBytes = [int64]$payloadCompressionStats.SourceBytes
        BundleBytes = [int64]$payloadCompressionStats.BundleBytes
        EmbeddedBytes = [int64]$payloadCompressionStats.EmbeddedBytes
        SavedBytes = [int64]$payloadCompressionStats.SavedBytes
        SavingsPercent = [double]$payloadCompressionStats.SavingsPercent
        MaximumPayloadBytes = [int64]$payloadCompressionStats.MaximumPayloadBytes
        MaximumPayloadDataBytes = [int64]$payloadCompressionStats.MaximumPayloadDataBytes
        MaximumCompressedBytes = [int64]$payloadCompressionStats.MaximumCompressedBytes
        MaximumDecodedBytes = [int64]$payloadCompressionStats.MaximumDecodedBytes
    }
    FrameworkTarget = '.NET Framework 4 / CLR v4'
    PowerShellTarget = 'Windows PowerShell 3+'
    CapabilitySchemaVersion = '1.1'
    LogSchemaVersion = '1.0-jsonl'
    DashboardSchemaVersion = '2.0'
    DashboardMode = 'Modern adaptive WinForms dashboard'
    StartupExecutionLevel = 'asInvoker'
    ElevationPolicy = 'On demand for system changes, application update and enterprise administration'
    DefaultDataRoot = '%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6'
    ElevatedDataRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6'
    StartupTheme = 'Light'
    DarkMode = 'Optional per-session / WCAG-aware palette'
    QuickActionNumberLabels = $false
    DirectReportActionCount = 7
    OfflinePolicySchemaVersion = [string]$offlinePolicyMetadata.SchemaVersion
    OfflineDefault = [string]$offlinePolicyMetadata.DefaultMode
    OfflineResetOnEveryLaunch = $true
    OfflineBlockedScopes = @($offlinePolicyMetadata.BlockedScopes)
    RuntimeTelemetry = [string]$offlinePolicyMetadata.Telemetry
    AutomaticUpdateCheck = [bool]$offlinePolicyMetadata.AutomaticUpdateCheck
    AutomaticUpdateCheckTrigger = [string]$offlinePolicyMetadata.AutomaticUpdateCheckTrigger
    BackgroundUpdateService = [bool]$offlinePolicyMetadata.BackgroundUpdateService
    SilentUpdate = [bool]$offlinePolicyMetadata.SilentUpdate
    ApplicationUpdateSchemaVersion = '1.0'
    ApplicationUpdateManifestUrl = 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json'
    ApplicationUpdateChoices = @('UpdateNow','Later','DismissForSession')
    ApplicationUpdateDeferral = 'After next completed task or 2 hours; next launch rechecks only when Online is allowed'
    ApplicationUpdateVerification = 'Fixed GitHub HTTPS allowlist + declared size + SHA-256 + mandatory pinned Authenticode signer for stable + rollback'
    LocalizationSchemaVersion = [string]$localizationMetadata.SchemaVersion
    DefaultCulture = [string]$localizationMetadata.DefaultCulture
    SupportedCultures = @($localizationMetadata.SupportedCultures)
    CompatibilitySchemaVersion = [string]$compatibilityMetadata.SchemaVersion
    CompatibilityCatalogSchemaVersion = [string]$compatibilityMetadata.CatalogSchemaVersion
    CompatibilityCatalogVersion = [string]$compatibilityMetadata.CatalogVersion
    CompatibilityCatalogReviewedAtUtc = [string]$compatibilityMetadata.ReviewedAtUtc
    CompatibilityCatalogAgeDays = [int]$compatibilityMetadata.CatalogAgeDays
    CompatibilityCatalogHealth = [string]$compatibilityMetadata.CatalogHealth
    CompatibilityCatalogFresh = [bool]$compatibilityMetadata.CatalogFresh
    CompatibilityCatalogReviewWarningAgeDays = [int]$compatibilityMetadata.ReviewWarningAgeDays
    CompatibilityCatalogMaximumReviewAgeDays = [int]$compatibilityMetadata.MaximumReviewAgeDays
    FutureCompatibilityMode = [string]$compatibilityMetadata.FutureCompatibilityMode
    SupportedWindowsReleases = @($compatibilityMetadata.WindowsReleaseNames)
    SupportedOfficeFamilies = @($compatibilityMetadata.OfficeFamilyNames)
    CleanupActionCenter = $true
    AutomaticSafeCleanup = 'Registry allowlist plus decisive-evidence third-party scopes with a scope-locked safe plan; preview + confirmation + HMAC backup + UAC + post-verification'
    ElevatedModuleEnvironmentBridge = 'Encoded allowlisted TOOL_* contract + schema/age/module/invocation validation + protected runtime restoration + child exit-code propagation'
    AssuranceCenter = $true
    Function5Compatibility = 'v4.3.0.3 title, primary tables, assessment and summary-card layout preserved'
    ThirdPartySoftwareInspection = 'All-source installed-software inventory + vendor-neutral bounded deep scan + conservative evidence scoring'
    NormalReportActivatorInspection = 'Windows/Office-only reports inspect current process/service/startup/task and bounded file evidence for MAS/PMAS, Activation Program 1.17, exact erturk-dev.netlify.app/run commands, TSforge, OHook, KMS tools and Microsoft Toolkit'
    NormalSoftwareInstalledArtifactInspection = 'Bounded scan of priority paid/trial/review application install roots plus user and shared data roots'
    WindowsKmsLifecyclePresentation = 'KMS channel remains visible in Notification state; grace minutes/days/expiry and approved-host trust are reported separately from entitlement'
    InstallDateNormalization = 'Registry yyyyMMdd, CIM datetime and plausible Unix epoch values normalize to yyyy-MM-dd'
    MonitorNameSources = @('WmiMonitorID EDID','Win32_DesktopMonitor','Win32_PnPEntity')
    ReportPrivacyChoice = @('Redacted copy','Full internal copy','Cancel')
    TimelineCurrentStatePolicy = 'Latest observed state is separated from retained historical events; removed evidence is not presented as current'
    UniversalDeepSoftwareScan = $true
    SoftwareLicenseCatalogVersion = [string]$softwareCatalogMetadata.CatalogVersion
    SoftwareLicenseCatalogProductRules = [int]@($softwareCatalogMetadata.Products).Count
    SoftwareLicenseCatalogSignatureFile = 'software-license-catalog-v1.0.json.p7s'
    SoftwareLicenseCatalogSignatureRequired = $true
    SoftwareLicenseCatalogSignerCertificateSha256 = $script:ToolSoftwareCatalogSignerCertificateSha256
    EngineeringSoftwareCatalogRules = [int]$engineeringCatalogRules.Count
    EngineeringSoftwareCategories = @($engineeringCatalogRules | ForEach-Object { [string]$_.Category } | Sort-Object -Unique)
    SoftwareInventoryDeduplication = 'Compatible name/version/publisher/location records are merged while retaining all discovery sources'
    SystemSoftwarePresentation = 'Hidden from main application tables; available through HTML internal link and a full PDF/JSON appendix'
    FileIntegrityAssessment = 'HashMismatch maps to IntegrityCompromised and does not alone prove non-genuine entitlement'
    DeepSoftwareScanEvidence = @('Multiple EXE/DLL Authenticode','Trusted known-bad SHA-256','Activator/artifact identity','IFEO','Firewall','Disabled licensing service','Autorun','Task/service/process/folder correlation','Blocked licensing domains')
    DeepSoftwareScanScoring = 'NonGenuine requires decisive evidence or two independent strong groups; generic/moderate evidence remains Suspicious; incomplete coverage remains Unverified'
    DeepSoftwareScanBudgetPolicy = 'Bounded time/depth/files/signatures/hashes; weighted budgeting prioritizes paid/trial/evidence-bearing software while reserving coverage for unknown/free applications'
    DeepSoftwareScanCatalogTrust = 'Online-cache rules cannot create decisive hash/name evidence unless byte-identical to the bundled catalog'
    ThirdPartyLicenseRemediationAdapters = @('Adobe shared licensing scope','Autodesk/AutoCAD shared licensing scope','WinRAR adapter gated by independent activator/tampering evidence; rarreg.key alone is never eligible','Generic exact-artifact/hosts cleanup + exact application-scoped firewall cleanup + validated MSI Repair + manual official-reinstall fallback')
    ThirdPartyAutomaticResetPolicy = 'Verified decisive evidence + scope-locked safe action + complete scan sources; firewall changes and uninstall/reinstall are manual-only'
    ThirdPartyBackupPolicy = 'HMAC-protected inventory and quarantine; unauthorized activators and licensing tokens are non-restorable'
    ThirdPartyPostCleanupQueuePolicy = 'Post-verification requeues only current activator/tampering evidence; inventory-only Unverified state remains reportable but is not remediation residue'
    ThirdPartyStandaloneArtifactPolicy = 'Exact-path activator files in user Downloads/Desktop/TEMP are manual-only quarantine candidates; protected backup/quarantine roots are excluded'
    RemediationDryRun = $true
    RemediationDryRunPolicy = 'Simulation lists exact targets/actions/backup/restorability and performs no system changes; real execution requires a new item confirmation'
    DetailedInventoryExport = $true
    UserGuideExport = 'Embedded vi-VN/en-US source to self-contained HTML/PDF; HTML opens by default'
    DocumentationCache = 'Stable version/culture filename + source SHA-256'
    DocumentationRendererRevision = '2'
    DefaultDocumentationOpenFormat = 'HTMLBeforePdf'
    VersionHistoryCenter = $true
    GuideStyle = 'Function-oriented; chronological changes kept in separate version history'
    SharedUiTypography = 'Segoe UI / GDI+'
    CapabilityFunctionMapping = $true
    EnterpriseLicenseCenter = $true
    EnterpriseNetworkDefault = [string]$offlinePolicyMetadata.EnterpriseNetworkDefault
    EnterpriseNetworkToggle = $true
    EnterpriseNetworkIndependentFromGlobalOffline = $true
    EnterpriseProtocolVersion = '1.0'
    EnterpriseDefaultPort = 49420
    EnterpriseTransport = 'HTTP with AES-256-CBC + HMAC-SHA256 application envelopes'
    EnterpriseRoles = @('Server','Client')
    EnterpriseEndpointDiagnostics = @('InvalidEndpoint','TcpUnavailable','ServiceUnavailable','ServiceRejected','ProtocolMismatch','VersionMismatch','Connected')
    EnterpriseDiscovery = 'Neighbor/ARP + ICMP + TCP probes; blank workstation address invokes local server discovery'
    EnterpriseReportRetry = 'DPAPI-protected local outbox retried by the workstation agent'
    OfficeLicenseEnumeration = 'OSPP /dstatusall per SKU'
    OfficialActivationPostCheck = 'Windows LicenseStatus=1 plus submitted-key Last5; Office OSPP LICENSED plus submitted-key Last5; process exit code alone never confirms activation'
    GenuineLicensePreservation = 'Verified OEM/Retail/MAK or approved organization KMS remains unchanged; readiness for activation is separate from licensed=True'
    OfficeScanExecution = 'Parallel runspace pool with bounded throttle'
    FileScanExecution = 'Parallel per-root enumeration with bounded depth and reparse-point exclusion'
    UserPreferencePersistence = @('Culture')
    EnvironmentWarnings = @('VirtualMachine','RemoteDesktop')
    ProgressUtilities = @('CopyAllLog','OpenReportFolder')
    VersionHistoryPresentation = 'InToolModal'
    ReportFormats = @('HTML','PDF','JSON','XML')
    ReportOutputRoot = '%USERPROFILE%\Desktop\BaoCao-Tool-Kiem-Tra'
    ReportPackageLayout = 'One shared Desktop report folder; unique timestamped files stay together without per-scan subfolders'
    ReportAutoOpenPolicy = 'Open HTML only after a completed export'
    LicenseConclusionPolicy = 'Activation is separated from entitlement; KMS and intervention conclusions require direct evidence'
    LicenseUndeterminedPolicy = 'Unreadable licensing data is reported as Undetermined and does not prove valid or invalid entitlement'
    ToolAssistant = [ordered]@{
        SchemaVersion = [string]$assistantMetadata.SchemaVersion
        Scope = [string]$assistantMetadata.Scope
        Engine = [string]$assistantMetadata.Engine
        PaidApiRequired = [bool]$assistantMetadata.PaidApiRequired
        CodexRequired = [bool]$assistantMetadata.CodexRequired
        OnlineTransfer = [string]$assistantMetadata.OnlineTransfer
        ReportUpload = [bool]$assistantMetadata.ReportUpload
        QuestionUpload = [bool]$assistantMetadata.QuestionUpload
        AutomaticRemediation = [bool]$assistantMetadata.AutomaticRemediation
        PortableEveryMachine = [bool]$assistantMetadata.PortableEveryMachine
        CentralServerRequired = [bool]$assistantMetadata.CentralServerRequired
        KnowledgeStorage = [string]$assistantMetadata.KnowledgeStorage
        ReportContextSource = [string]$assistantMetadata.ReportContextSource
        KnowledgeCompatibilityEnforced = [bool]$assistantMetadata.KnowledgeCompatibilityEnforced
        KnowledgeUpdateVerification = [string]$assistantMetadata.KnowledgeUpdateVerification
        KnowledgeRollbackProtection = [bool]$assistantMetadata.KnowledgeRollbackProtection
        UnboundedSelfTraining = [bool]$assistantMetadata.UnboundedSelfTraining
        ExternalTopicLearning = [bool]$assistantMetadata.ExternalTopicLearning
        KnowledgeFileName = [string]$assistantMetadata.KnowledgeFileName
        KnowledgeSignatureFileName = [string]$assistantMetadata.KnowledgeSignatureFileName
        ImmediateResponseRender = $true
    }
    ReportExportSchemaVersion = [string]$reportExportMetadata.SchemaVersion
    ReportHtmlPresentation = [string]$reportExportMetadata.HtmlPresentation
    ReportPdfPresentation = [string]$reportExportMetadata.PdfPresentation
    ReportContentSplit = 'HTML summary for quick review; PDF contains the complete technical report'
    ReportSummaryWideCardCount = 5
    ReportConclusionPanels = @('VerificationLevel','RecommendedAction')
    PdfFooterLineCount = 2
    DefaultReportOpenFormat = 'HTML'
    DesktopHtmlPdfExport = $true
    UnifiedProfessionalReportUi = $true
    PdfSafePageBreaks = $true
    PdfHeaderFooter = 'Disabled'
    HtmlAssets = 'Embedded local CSS only; CSP default-src none'
    PdfNetworkPolicy = 'Background networking disabled; host resolver mapped to 0.0.0.0'
    PdfEngines = @('Microsoft Edge','Google Chrome','Microsoft Word')
    PdfProfileRoot = [string]$reportExportMetadata.PdfProfileRoot
    PdfProfileAcl = [string]$reportExportMetadata.PdfProfileAcl
    PdfProfileCleanup = [string]$reportExportMetadata.PdfProfileCleanup
    PluginSchemaVersion = '1.0'
    PluginModel = 'DeclarativeReadOnlyRules'
    TimelineSchemaVersion = '1.0'
    TimelineIntegrity = 'DPAPI LocalMachine + HMAC-SHA256 + hash chain'
    CertificateAudit = 'Windows/Office Authenticode + offline chain'
    ReportSchemaVersion = [string]$reportSchemaMetadata.SchemaVersion
    ReportKinds = [int]@($reportSchemaMetadata.ReportKinds).Count
    SafetyPolicySchemaVersion = [string]$safetyPolicyMetadata.SchemaVersion
    ScanRepairChangesStartupType = [bool]$safetyPolicyMetadata.StartupTypeChangesAllowedByQuickRepair
    ModuleContractSchemaVersion = [string]$moduleContractMetadata.ContractSchemaVersion
    ModuleResultSchemaVersion = [string]$moduleContractMetadata.ResultSchemaVersion
    ModuleCount = [int]$moduleContractMetadata.ModuleCount
    ModuleEntryPointCount = [int]$moduleContractMetadata.EntryPointCount
    DataSchemaVersion = '2.0'
    DataProducerVersion = $releaseVersion
    DataStorageGeneration = 'v4.6'
    LegacyDataStorageGeneration = 'v4.4'
    DataMigrationPolicy = 'Verified staging copy + transactional commit + rollback'
    DataConcurrencyPolicy = 'Separate v4.6 write root; launcher blocks detected v4.4/v4.5 mutexes before migration'
    LegacyReadOnlyRoots = @('%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.4\logs','%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.4\backups')
    PersistentLogRoot = '%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6\logs (standard UI); %ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\logs (elevated modes)'
    PersistentPluginRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\plugins'
    PersistentTimelineRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\timeline'
    PersistentEnterpriseRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\enterprise'
    CompilerFileVersion = [string]$compilerVersion
    DeterministicManagedBuild = $true
    DeterministicScope = 'Unsigned managed image; Authenticode intentionally changes final bytes when enabled.'
    AuthenticodeRequired = [bool]$RequireAuthenticode
    ControlFlowGuard = [ordered]@{
        Status = 'NotClaimed'
        Reason = 'Launcher la managed IL; CSC khong tao CFG instrumentation/load-config native. Khong gan co GUARD_CF gia.'
    }
    BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($releaseManifestPath, ($releaseManifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

$primaryArtifact = @($artifactResults.ToArray())[0]
$primaryArtifactPath = Join-Path $OutputDirectory $primaryArtifact.FileName
$updateSignerThumbprints = @()
$updateAuthenticodeRequired = [bool]$RequireAuthenticode
if ($updateAuthenticodeRequired) {
    if ($primaryArtifact.AuthenticodeStatus -ne 'Valid' -or
        [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
        throw 'Stable update manifest requires a valid Authenticode signature and signer thumbprint.'
    }
    $updateSignerThumbprints = @(([string]$primaryArtifact.AuthenticodeThumbprint).Replace(' ', '').ToUpperInvariant())
}
$applicationUpdateManifest = [ordered]@{
    SchemaVersion = '1.0'
    Channel = if ($updateAuthenticodeRequired) { 'stable' } else { 'development' }
    LatestVersion = $releaseVersion
    MinimumUpdaterVersion = '4.6.1.0'
    PublishedAtUtc = '2026-08-18T00:00:00Z'
    Title = [ordered]@{
        'vi-VN' = 'v4.8.0 - Nhanh hơn, dễ dùng hơn, an toàn hơn'
        'en-US' = 'v4.8.0 - Faster, clearer, and safer'
    }
    Changes = [ordered]@{
        'vi-VN' = @(
            'Đánh giá phần mềm tách mô hình giấy phép khỏi bằng chứng crack/can thiệp; phần mềm miễn phí và mức tin cậy Low không còn bị yêu cầu hóa đơn hay đưa vào diện tự động xóa.',
            'Bổ sung nhận diện bảo thủ MAS/PMAS, Activation Program 1.17 và đúng lệnh erturk-dev; giữ ứng dụng, chỉ cô lập đúng artifact/tác vụ đáng ngờ khi đủ bằng chứng.',
            'WinRAR không coi rarreg.key đơn lẻ là vi phạm; MathType và WinRAR mở đúng nguồn chính thức, còn Windows, Office và phần mềm bên thứ ba có hướng xử lý riêng.',
            'Phụ lục phần mềm dùng bảng màu teal dễ phân biệt; PDF chi tiết giãn chữ, tự tách bảng rộng và sửa lỗi báo cáo Toàn bộ/Phần mềm không xuất PDF khi có liên kết chính thức.',
            'Trợ lý Tool trả lời rõ kết luận, bằng chứng, điều kiện khắc phục và bước tiếp theo bằng tiếng Việt/Anh.',
            'Mặc định Offline, không telemetry; v4.8.0.1 bổ sung cập nhật ứng dụng an toàn theo phiên bản và hash.'
        )
        'en-US' = @(
            'Software assessment separates the license model from crack/tampering evidence; freeware and Low-confidence items no longer require invoices or become automatic deletion candidates.',
            'Conservative detection now covers MAS/PMAS, Activation Program 1.17, and the exact erturk-dev command; applications stay installed while only proven artifacts or tasks are isolated.',
            'A lone rarreg.key is not treated as WinRAR abuse; MathType and WinRAR open official sources, with separate guidance for Windows, Office, and third-party software.',
            'The software appendix uses a clearer teal palette; detailed PDFs add spacing, split wide tables, and fix Full/Software PDF export when official references are present.',
            'Tool Assistant answers now separate the conclusion, evidence, remediation conditions, and next action in Vietnamese and English.',
            'Offline remains the default with no telemetry; v4.8.0.1 adds safe application updates by version and hash.'
        )
    }
    ReleasePageUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v$releaseVersion"
    DownloadUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v$releaseVersion/$($primaryArtifact.FileName)"
    DownloadSha256 = [string]$primaryArtifact.Sha256
    DownloadSize = [int64](Get-Item -LiteralPath $primaryArtifactPath).Length
    AuthenticodeRequired = $updateAuthenticodeRequired
    SignerThumbprints = @($updateSignerThumbprints)
}
$applicationUpdateManifestJson = $applicationUpdateManifest | ConvertTo-Json -Depth 8
$sourceUpdateManifestPath = Join-Path $sourceDirectory 'update-manifest-v1.json'
$outputUpdateManifestPath = Join-Path $OutputDirectory 'update-manifest-v1.json'
[IO.File]::WriteAllText($sourceUpdateManifestPath, $applicationUpdateManifestJson, (New-Object Text.UTF8Encoding($false)))
if (-not $sourceUpdateManifestPath.Equals($outputUpdateManifestPath, [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $sourceUpdateManifestPath -Destination $outputUpdateManifestPath -Force
}
if ((Get-Sha256Hex $sourceUpdateManifestPath) -ne (Get-Sha256Hex $outputUpdateManifestPath)) {
    throw 'Manifest cập nhật trong mã nguồn và thư mục phát hành không giống hệt từng byte.'
}
Write-SourcePackageHashManifest

$infoName = 'THONG-TIN-PHAT-HANH-v4.8.txt'
$authenticodeInfo = if (-not [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
    "Authenticode signer: $($primaryArtifact.AuthenticodeSigner); thumbprint $($primaryArtifact.AuthenticodeThumbprint); status $($primaryArtifact.AuthenticodeStatus)."
} else {
    'Authenticode: NotSigned.'
}
$authenticodeTrustInfo = if ([string]$primaryArtifact.AuthenticodeStatus -eq 'Valid' -and [string]$primaryArtifact.AuthenticodeSigner -match 'Self-Signed') {
    'Chu ky Authenticode tu ky duoc may build xac minh Valid sau khi cai chung thu tin cay cho Current User; may la van can cai chung thu hoac co the bao Unknown publisher/SmartScreen.'
} elseif ([string]$primaryArtifact.AuthenticodeStatus -eq 'Valid') {
    'Chu ky Authenticode duoc Windows tren may build xac minh Valid; SmartScreen van co the can danh tieng cho tep moi.'
} elseif (-not [string]::IsNullOrWhiteSpace([string]$primaryArtifact.AuthenticodeThumbprint)) {
    'Chu ky tu ky mien phi chi giup nhan biet tep bi sua; khong duoc Windows tin cay cong khai va khong loai bo canh bao SmartScreen tren may la.'
} else {
    'Tep chua co chu ky Authenticode; chi tai tu GitHub chinh thuc va doi chieu SHA-256.'
}
$infoLines = @(
    "PHAN MEM KIEM TRA BAN QUYEN v$releaseVersion - HO TRO CA NHAN VA DOANH NGHIEP",
    "Release version: $releaseVersion",
    "Release build date: $releaseBuildDate",
    "Release label: $releaseLabel",
    'Release status: Production (da dat ma tran E2E HTML/JSON/XML/PDF, x64/x86, ky so va hash).',
    "Tep chay duy nhat: Tool-Kiem-Tra-v$productVersion.exe",
    "SHA-256: $($primaryArtifact.Sha256)",
    'AnyCPU: CLR tu chay x64 tren Windows 64-bit va x86 tren Windows 32-bit; khong bat Prefer 32-bit.',
    'Fail-closed neu phat hien tien trinh 32-bit tren Windows 64-bit de tranh WOW64 redirection.',
    'PowerShell duoc khoi dong voi ExecutionPolicy RemoteSigned; khong dung Bypass.',
    'Dashboard mo bang quyen nguoi dung hien tai; UAC chi duoc yeu cau theo nhu cau khi thay doi he thong, cap nhat ung dung hoac quan tri doanh nghiep.',
    'Cau noi UAC ma hoa chi truyen allowlist bien TOOL_* da xac thuc, khoi phuc secure runtime va tra ma thoat tien trinh con; khong tat fail-closed de ne loi.',
    "Payload nhung duoc toi uu $($payloadCompressionStats.Scheme): 49 tep trong mot resource Deflate co header fail-closed; giam $($payloadCompressionStats.SavingsPercent)% va van doi chieu SHA-256 tung tep sau giai nen.",
    'Capability detection chon CIM/WMI, ScheduledTasks/schtasks va cac tinh nang theo he dieu hanh.',
    'Dashboard schema 2.0: WinForms hien dai, bang mau trung tinh, the trang thai Windows/Office, tile co mo ta, responsive DPI va mac dinh giao dien sang.',
    'Typography dong bo Segoe UI/GDI+ voi co chu gon hon; icon co khoang dem, tile va tab can deu, noi dung dai co tooltip day du.',
    'Da ngon ngu: vi-VN va en-US dung catalog JSON dong bo cho dashboard, log trang thai, bao cao, trung tam doanh nghiep va trinh quan ly Windows/Office cuc bo; lua chon duoc ghi nho theo tai khoan.',
    'Ghi nho ngon ngu; moi lan mo luon bat dau bang giao dien sang va che do Offline, khong khoi phuc Online tu phien truoc.',
    'Canh bao khi phat hien may ao hoac Remote Desktop; khong khoa cac chuc nang hien co.',
    'Them nut Sao chep toan bo log va Mo thu muc bao cao; lich su phien ban hien thi ngay trong Tool.',
    'Bo nhan danh so cu tren cua so chuc nang; toan bo nut WinForms dung mau va icon vector hanh dong chung o Light/Dark.',
    'Quet Office va tep chi bao duoc song song co gioi han, bo qua reparse point va giu nguyen pham vi quet cu.',
    'Quet sau pho quat moi phan mem phat hien duoc: nhieu EXE/DLL, Authenticode, hash xau da biet, artifact va dau vet he thong tuong quan; ngan sach chu ky duoc chia deu va do phu duoc ghi trong JSON/report.',
    'Toi uu hieu nang v4.8: descriptor inventory tinh mot lan, chi muc nhom ten/bang chung ngoai, dung property bag thay Add-Member lap lai, tai su dung snapshot Scheduled Tasks, bang dich nguoc cho report va Authenticode theo lo toi da 4 worker; doi chung cung du lieu cho 0 khac biet, giu nguyen nguon, do sau, artifact va dau vet he thong.',
    'Chi ket luan NonGenuine khi co bang chung quyet dinh hoac hai nhom bang chung manh doc lap; dau hieu chung giu Suspicious, thieu do phu giu Unverified.',
    'Bao cao phan mem va dau hieu can thiep giu nguyen hop dong v4.3.0.3; kiem ke ung dung va trang thai ky thuat ben thu ba duoc noi them o cuoi bao cao va DetailedInventory JSON.',
    'Khac phuc ben thu ba: moi phan mem NonGenuine/Suspicious deu co the chon thu cong; tu dong chi dung ke hoach da khoa pham vi (adapter hang, artifact/hosts chinh xac hoac Repair MSI hop le). Go/cai lai luon la thu cong.',
    'Backup HMAC luu kiem ke va cach ly truoc thay doi; activator va token cap phep da loai bo khong duoc khoi phuc.',
    'Offline toan ung dung mac dinh; trung tam doanh nghiep co cong tac mang rieng mac dinh tat, co the bat/tat lai ma khong an chuc nang hoac xoa cau hinh.',
    'Ket noi online chi chay sau khi nguoi dung xac nhan, tai catalog JSON HTTPS tu host allowlist; khong gui inventory, duong dan, khoa hoac token va khong doi preference Offline.',
    'Tu dong kiem tra phien ban moi chi khi Online da duoc cho phep; khong co service nen, telemetry hay cap nhat im lang.',
    'Khi co ban moi, Tool hoi 3 lua chon: Cap nhat ngay, De sau, Bo qua lan nay. De sau hoi lai sau tac vu ke tiep hoac 2 gio.',
    'Cap nhat ngay chi tai EXE tu GitHub HTTPS co dinh, doi chieu dung luong/SHA-256/chu ky neu bat buoc, backup ban cu va rollback neu ban moi loi.',
    "Compatibility catalog $($compatibilityMetadata.CatalogVersion), schema $($compatibilityMetadata.CatalogSchemaVersion), ra soat $($compatibilityMetadata.ReviewedAtUtc); canh bao $($compatibilityMetadata.ReviewWarningAgeDays) ngay va het han $($compatibilityMetadata.MaximumReviewAgeDays) ngay.",
    "Nhan dien theo catalog: $(@($compatibilityMetadata.WindowsReleaseNames) -join ', '); build moi/chua biet chuyen sang ReadOnlyManualReview.",
    "Nhan dien Office theo catalog: $(@($compatibilityMetadata.OfficeFamilyNames) -join ', '); Product ID/kenh moi chua biet khong duoc tu suy dien tuong thich.",
    'Enterprise: may chu quet CIDR/IP, ghep noi bang ma tam thoi, quan ly fleet, xuat JSON/CSV/HTML/PDF va gui tac vu license da ma hoa.',
    'Enterprise UI hotfix: co-fit theo WorkingArea/DPI, khong tran ngang; Quet nhanh tu nhan CIDR cuc bo khi o nhap trong.',
    'Enterprise IP auto: may chu tu chon IPv4 LAN uu tien theo card co gateway; may tram tu do server duy nhat khi de trong dia chi.',
    'Enterprise server reset: nut Xoa cau hinh may chu bat buoc ma quan tri va xac nhan cuoi; giu bao cao, ket qua va audit.',
    'Enterprise UI refresh: bo muc Tren may nay; doi thanh Chon chuc nang; them mau theo chuc nang, nut Tro ve phien truoc va nut Dong trung tam doanh nghiep.',
    'Enterprise network toggle: nut hien trang thai Online/Offline hien tai; tooltip noi ro thao tac chuyen che do va ba chuc nang luon hien thi.',
    'Enterprise UI close hotfix: ve tab dung RectangleF de tranh loi overload DrawString va dam bao nut Dong trung tam doanh nghiep hoat dong.',
    'Enterprise local manager restore: khoi phuc quan ly license cuc bo duoi ten chuc nang moi, khong dung lai ten tab Tren may nay.',
    'Enterprise quick scan hotfix: sua loi hien thi ket qua khi IP phan hoi va them kiem thu hoi quy PowerShell 5.1.',
    'Dark mode van co the bat trong phien hien tai, phu dashboard, cua so con, chuc nang 8 va quan ly cuc bo Windows/Office.',
    'May tram tu dong gui bao cao hoac xep hang DPAPI khi mat route; thay doi license tu xa mac dinh tat va phai duoc may tram cho phep.',
    'Cleanup Action Center co vung cuon/nut xu ly tiep; Office KMS dung OSPP /dstatusall va rang buoc lua chon theo tung SKU/Last5.',
    'Kich hoat chinh hang tach sach crack khoi da cap phep: Windows chi TRUE khi LicenseStatus=1 dung Last5; Office chi TRUE khi OSPP /dstatusall bao LICENSED dung Last5; neu chua dat thi FALSE va mo luong chinh thuc.',
    "Report schema $($reportSchemaMetadata.SchemaVersion): $(@($reportSchemaMetadata.ReportKinds).Count) loai bao cao; safety policy schema $($safetyPolicyMetadata.SchemaVersion); quick repair khong doi StartupType.",
    'Bao cao HTML la ban tong quan gon, khong con bang dai; chi giu cau hinh chinh, ket luan, canh bao va nut mo PDF day du.',
    'PDF la ban chi tiet A4 gom toan bo bang cau hinh, phan mem, bang chung va du lieu ky thuat; moi lan xuat van gom HTML/PDF/JSON/XML/checksum trong mot thu muc va chi tu mo HTML.',
    'Ket luan ban quyen tach ro trang thai kich hoat voi quyen su dung; du lieu cap phep khong doc duoc ghi CHUA XAC DINH va khong tu chung minh hop le/khong hop le.',
    'Tro ly Tool dung tri thuc cuc bo, khong tu khac phuc va khong tai cau hoi/bao cao/du lieu may len mang; Online chi tai JSON va chu ky CMS tu hai path GitHub co dinh.',
    'Tro ly bo tri truc tiep va co them luot ve bu sau su kien Gui/Enter; cau tra loi hien ngay sau khi xu ly, khong cho cau hoi tiep theo; nhan Offline co le an toan, khung nhap co vien focus va bong bong hoi-dap co mau/vien rieng.',
    'HTML, PDF va cac bao cao dung chung giu du nam o ket qua tren cung mot hang khi du rong; Muc xac minh/Huong xu ly tach thanh o con va chan trang PDF chia hai hang.',
    'Tro ly dong bo day du vi-VN/en-US cho nut, trang thai dong bo va dien giai bao cao hien tai theo ma ket qua.',
    'Tro ly schema 1.1 / knowledge 1.3.1 co 63 nhom va 481 tu khoa/cach hoi; cache roi co chu ky CMS SHA-256, ghim chung thu, chong ha phien ban va giu EXE trong ngan sach 900000 byte.',
    'Catalogue phan mem 1.4.0.0 co 77 quy tac va chu ky CMS; tach mo hinh giay phep khoi bang chung can thiep, Low chi de tham khao va khong tao hanh dong xoa.',
    'Bao cao Windows/Office thuong van ra kenh KMS khi license o Notification, hien chu ky KMS toi da 180 ngay va ra MAS/PMAS, Activation Program 1.17, lenh erturk-dev.netlify.app/run, TSforge, OHook, KMS toolkit/Microsoft Toolkit con hien huu.',
    'Quet phan mem thuong ra them artifact trong thu muc cai dat thuong mai co gioi han, khong chi du lieu Download; ngay cai duoc chuan hoa yyyy-MM-dd.',
    'Ten man hinh co fallback EDID/DesktopMonitor/PNP; hop chon rieng tu co nut Ban da che, Ban day du noi bo va Huy; timeline tach trang thai hien tai khoi su kien lich su.',
    'WinRAR khong coi rarreg.key don le la bang chung vi pham hay dieu kien khac phuc; neu het thu dung thi mua giay phep hoac dung phan mem thay the hop phap.',
    'Khac phuc phan mem ben thu ba ghi ket qua tung hanh dong va chi bao thanh cong khi he thong thuc su thay doi; huong dan don thuan khong con bi tinh la da sua.',
    'Sau hau kiem, hang doi phan mem khac chi con bang chung activator/can thiep; Unverified don thuan khong quay lai, tep activator doc lap co candidate cach ly thu cong va kho backup bi loai tru.',
    'HashMismatch duoc tach thanh IntegrityCompromised: tep bi sua/hong nhung khong tu ket luan quyen su dung khong chinh hang.',
    'Phan mem he thong/mac dinh an khoi bang chinh, co link mo phu luc trong HTML va hien day du trong PDF/JSON chi tiet.',
    'Moi bao cao nam truc tiep trong Desktop\BaoCao-Tool-Kiem-Tra, khong tao thu muc con; ten tep co mili-giay va HTML link dung PDF.',
    'PDF tach bang rong thanh tong quan/bang chung, mo chi tiet khi in, lap header va tranh cat dong/hang qua trang.',
    'Enterprise nhan IP:port, tu do khi de trong, chan doan endpoint/TCP/service/protocol/version va quet Neighbor-ARP/ICMP/TCP.',
    'Enterprise server cau hinh va hau kiem URLACL/Firewall qua UAC; chi bao da khoi dong sau heartbeat/diagnostic, agent chi bao da gui sau tep ket qua xac nhan.',
    'Muc Bao cao hien thi truc tiep du bay chuc nang con; huong dan vi-VN/en-US duoc nhung trong EXE va mo bang HTML/PDF A4.',
    'HTML/PDF chi dung asset cuc bo, CSP default-src none; browser PDF tat background networking va map DNS ve 0.0.0.0.',
    'Profile Edge/Chrome tam nam trong %LOCALAPPDATA%\Temp, ACL chi cho nguoi dung hien tai va SYSTEM; profile duoc don sau moi lan xuat.',
    'Plugin chi dung JSON khai bao, khong chay script/command; thu muc plugin co ACL Administrators/SYSTEM.',
    'Timeline dung DPAPI LocalMachine, HMAC-SHA256 va hash chain; neu chuoi hong tool tu choi noi them.',
    'Certificate audit kiem tra Authenticode va chuoi tin cay offline cua tep Windows/Office quan trong.',
    "Module contract schema $($moduleContractMetadata.ContractSchemaVersion): $($moduleContractMetadata.EntryPointCount) entry point / $($moduleContractMetadata.ModuleCount) module; co capability gate va ModuleResult thong nhat.",
    'Log JSON Lines cua dashboard nam trong LocalAppData theo tai khoan; che do nang quyen va doanh nghiep dung ProgramData co ACL Administrators/SYSTEM; khong ghi product key day du.',
    'PE: HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, Terminal Server Aware.',
    'CFG/load configuration native chua duoc tuyen bo; xem SECURITY-HARDENING-v4.8.md.',
    'Pham vi runtime: Windows 7 SP1 den Windows 11 desktop x64/x86; catalog hien tai theo doi Windows 10 22H2 va Windows 11 23H2/24H2/25H2/26H1.',
    $authenticodeInfo,
    $authenticodeTrustInfo,
    'Khong the vuot AppLocker, WDAC, SmartScreen, antivirus hoac chinh sach doanh nghiep.'
)
[IO.File]::WriteAllLines((Join-Path $OutputDirectory $infoName), $infoLines, (New-Object Text.UTF8Encoding($false)))

$releaseHashFiles = @($targets.OutputName) + @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICH-SU-PHIEN-BAN.txt', 'VERSION-HISTORY-en-US.md', 'LICENSE-NOTICE.txt',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'TECHNICAL-ARCHITECTURE-v4.8.md', 'ENTRY-POINTS-v4.8.md', 'COMPATIBILITY-MATRIX-v4.8.md',
    'OFFLINE-AND-REPORTING-v4.8.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.8.md',
    'compatibility-catalog-v1.0.json', 'software-license-catalog-v1.0.json', 'software-license-catalog-v1.0.json.p7s', 'builtin-windows-office-trust.plugin.json', 'tool-assistant-knowledge-v1.1.json', 'tool-assistant-knowledge-v1.1.json.p7s', 'RELEASE-MANIFEST.json', 'update-manifest-v1.json', $infoName
)
$releaseHashLines = @("# SHA-256 goi phat hanh Tool-Kiem-Tra v$productVersion.")
foreach ($name in $releaseHashFiles) {
    $releaseHashLines += "$(Get-Sha256Hex (Join-Path $OutputDirectory $name))  $name"
}
[IO.File]::WriteAllLines((Join-Path $OutputDirectory 'RELEASE-SHA256SUMS.txt'), $releaseHashLines, (New-Object Text.UTF8Encoding($false)))

Write-Host '[6/8] Kiểm tra extension/report/plugin/timeline...'
if (-not $SkipVerification) {
    & (Join-Path $sourceDirectory 'VERIFY-SAFETY-REGRESSIONS.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-SAFETY-REGRESSIONS.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-DASHBOARD.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-DASHBOARD.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-REPORT-SCHEMA.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-REPORT-SCHEMA.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-EXTENSIONS.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-EXTENSIONS.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-COMPATIBILITY.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-COMPATIBILITY.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-OFFLINE-I18N.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-OFFLINE-I18N.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-LOCALIZATION-COVERAGE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-LOCALIZATION-COVERAGE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-ENTERPRISE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-ENTERPRISE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-PERFORMANCE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-PERFORMANCE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-APPLICATION-UPDATE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-APPLICATION-UPDATE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    & (Join-Path $sourceDirectory 'VERIFY-ASSISTANT.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-ASSISTANT.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    Write-Host '[7/8] Kiểm tra phát hành tổng thể...'
    & (Join-Path $sourceDirectory 'VERIFY-RELEASE.ps1') -SourceDirectory $sourceDirectory -DistributionDirectory $OutputDirectory `
        -AllowDevelopmentManifest:$AllowUnsignedDevelopmentBuild
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-RELEASE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    if ($RequireAuthenticode) {
        & (Join-Path $sourceDirectory 'VERIFY-AUTHENTICODE.ps1') -FilePath (Join-Path $OutputDirectory "Tool-Kiem-Tra-v$productVersion.exe") -RequireTimestamp
        if ($LASTEXITCODE -ne 0) { throw "VERIFY-AUTHENTICODE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    }
}

Write-Host '[8/8] Hoàn tất.'
foreach ($artifact in $artifactResults) {
    Write-Host "  $($artifact.Architecture), tự nhận diện runtime: $(Join-Path $OutputDirectory $artifact.FileName)" -ForegroundColor Green
    Write-Host "  SHA-256: $($artifact.Sha256)"
    Write-Host "  Authenticode: $($artifact.AuthenticodeStatus)"
}
