[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipVerification,
    [string]$SigningCertificateThumbprint = '',
    [ValidateSet('CurrentUser','LocalMachine')][string]$SigningCertificateStore = 'CurrentUser',
    [string]$SigningPfxPath = '',
    [Security.SecureString]$SigningPfxPassword,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$RequireAuthenticode
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$productVersion = '4.3'
$releaseVersion = '4.3.0.7'
$releaseBuildDate = '2026.07.31'
$releaseLabel = "$releaseVersion-guide-history-layout-github-20260731"
$sourceDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $sourceDirectory 'dist' }
$sourceName = "Tool-Kiem-Tra-v$productVersion-OneFile.cs"
$applicationManifestName = "Tool-Kiem-Tra-v$productVersion-OneFile.manifest"
$embeddedVerifierName = 'VERIFY-EMBEDDED-PAYLOAD.ps1'
$peHardeningName = 'PE-HARDENING.ps1'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    throw 'BUILD.ps1 phải chạy bằng Windows PowerShell 64-bit để build AnyCPU và kiểm tra trên cả CLR x64/x86.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Máy build phải là Windows 64-bit để kiểm tra cùng một EXE AnyCPU trên cả CLR x64/x86.'
}

$payloadFiles = @(
    '00-Tool-Kiem-Tra.ico',
    'approved-kms-servers.txt',
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
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
    '00-Tool-Kiem-Tra.ico',
    'HUONG-DAN.txt',
    'USER-GUIDE-en-US.md',
    'LICH-SU-PHIEN-BAN.txt',
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Kiem-Tra-icon.svg',
    'Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1',
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Capabilities.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-UiTheme.ps1',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1',
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
    'BUILD.ps1'
    'DANH-GIA-VA-NANG-CAP-v4.3.md'
    'LICENSE-NOTICE.txt'
    'README.md'
    'README-MA-NGUON.md'
    'MODULE-CONTRACT-v1.0.md'
    'REPORT-SCHEMA-v1.5.md'
    'ROADMAP-v5.0.md'
    'SECURITY-HARDENING-v4.3.md'
    'TECHNICAL-ARCHITECTURE-v4.3.md'
    'ENTRY-POINTS-v4.3.md'
    'COMPATIBILITY-MATRIX-v4.3.md'
    'OFFLINE-AND-REPORTING-v4.3.md'
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
    'VERIFY-OFFLINE-I18N.ps1'
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
    throw 'Không tìm thấy Roslyn csc.exe. Hãy cài Visual Studio Build Tools (MSBuild/Roslyn); v4.3 không dùng compiler legacy vì cần deterministic build.'
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
    'BUILD.ps1',
    'DANH-GIA-VA-NANG-CAP-v4.3.md',
    'LICENSE-NOTICE.txt',
    'README.md',
    'README-MA-NGUON.md',
    'MODULE-CONTRACT-v1.0.md',
    'REPORT-SCHEMA-v1.5.md',
    'ROADMAP-v5.0.md',
    'SECURITY-HARDENING-v4.3.md',
    'TECHNICAL-ARCHITECTURE-v4.3.md',
    'ENTRY-POINTS-v4.3.md',
    'COMPATIBILITY-MATRIX-v4.3.md',
    'OFFLINE-AND-REPORTING-v4.3.md',
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
$moduleContractMetadata = Get-ToolModuleContractMetadata
$reportSchemaMetadata = Get-ToolReportSchemaMetadata
$reportExportMetadata = Get-ToolReportExportMetadata
$safetyPolicyMetadata = Get-ToolSafetyPolicyMetadata
$compatibilityMetadata = Get-ToolCompatibilityMetadata
$localizationMetadata = Get-ToolLocalizationMetadata
$offlinePolicyMetadata = Get-ToolOfflinePolicyMetadata

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

Write-Host '[3/8] Chuẩn bị thư mục đầu ra...'
if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
$compiler = Find-CSharpCompiler
$compilerVersion = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion
$payloadListArgument = $payloadFiles -join '|'
$targets = @(
    [pscustomobject]@{ Architecture='AnyCPU'; Platform='anycpu'; OutputName="Tool-Kiem-Tra-v$productVersion.exe"; HighEntropy=$true }
)
$artifactResults = New-Object System.Collections.Generic.List[object]

foreach ($staleName in @("Tool-Kiem-Tra-v$productVersion-x64.exe", "Tool-Kiem-Tra-v$productVersion-x86.exe")) {
    $stalePath = Join-Path $OutputDirectory $staleName
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force }
}

Write-Host '[4/8] Nhúng payload và biên dịch một EXE AnyCPU...'
foreach ($target in $targets) {
    $outputPath = Join-Path $OutputDirectory $target.OutputName
    Write-Host "  - Build $($target.Architecture): $($target.OutputName)"
    $compilerArguments = @(
        '/nologo',
        '/target:winexe',
        "/platform:$($target.Platform)",
        '/deterministic+',
        "/pathmap:$sourceDirectory=C:\_src\Tool-Kiem-Tra-v4.3",
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
    for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
        $compilerArguments += "/resource:$(Join-Path $sourceDirectory $payloadFiles[$index]),payload.$index"
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

Write-Host '[5/8] Tạo metadata phát hành...'
foreach ($sidecar in @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICENSE-NOTICE.txt',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'TECHNICAL-ARCHITECTURE-v4.3.md', 'ENTRY-POINTS-v4.3.md', 'COMPATIBILITY-MATRIX-v4.3.md',
    'OFFLINE-AND-REPORTING-v4.3.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.3.md',
    'compatibility-catalog-v1.0.json', 'builtin-windows-office-trust.plugin.json'
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
    PrimaryFileName = "Tool-Kiem-Tra-v$productVersion.exe"
    RuntimeArchitecture = 'Auto: x64 on Windows 64-bit; x86 on Windows 32-bit'
    Artifacts = $manifestArtifacts
    PayloadCount = [int]$payloadFiles.Count
    IntegrityFileCount = [int]$integrityFiles.Count
    FrameworkTarget = '.NET Framework 4 / CLR v4'
    PowerShellTarget = 'Windows PowerShell 3+'
    CapabilitySchemaVersion = '1.1'
    LogSchemaVersion = '1.0-jsonl'
    DashboardSchemaVersion = '2.0'
    DashboardMode = 'Modern adaptive WinForms dashboard'
    DarkMode = 'Persistent full-tool / WCAG-aware palette'
    OfflinePolicySchemaVersion = [string]$offlinePolicyMetadata.SchemaVersion
    OfflineDefault = [string]$offlinePolicyMetadata.DefaultMode
    OfflineBlockedScopes = @($offlinePolicyMetadata.BlockedScopes)
    RuntimeTelemetry = [string]$offlinePolicyMetadata.Telemetry
    AutomaticUpdateCheck = [bool]$offlinePolicyMetadata.AutomaticUpdateCheck
    LocalizationSchemaVersion = [string]$localizationMetadata.SchemaVersion
    DefaultCulture = [string]$localizationMetadata.DefaultCulture
    SupportedCultures = @($localizationMetadata.SupportedCultures)
    CompatibilitySchemaVersion = [string]$compatibilityMetadata.SchemaVersion
    CompatibilityCatalogReviewedAtUtc = [string]$compatibilityMetadata.ReviewedAtUtc
    CompatibilityCatalogFresh = [bool]$compatibilityMetadata.CatalogFresh
    SupportedWindowsReleases = @('Windows 11 24H2 build 26100','Windows 11 25H2 build 26200','Windows 11 26H1 build 28000')
    SupportedOfficeFamilies = @('Office 2024 / LTSC 2024','Microsoft 365 Apps')
    CleanupActionCenter = $true
    AssuranceCenter = $true
    Function5Compatibility = 'v4.3.0.3 title, primary tables, assessment and summary-card layout preserved'
    ThirdPartySoftwareInspection = 'Additive registry inventory + Authenticode + install source + autorun + service + task + review reasons'
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
    OfficeLicenseEnumeration = 'OSPP /dstatusall per SKU'
    ReportFormats = @('HTML','PDF','JSON','XML')
    ReportExportSchemaVersion = [string]$reportExportMetadata.SchemaVersion
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
    PersistentLogRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\logs'
    PersistentPluginRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\plugins'
    PersistentTimelineRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\timeline'
    PersistentEnterpriseRoot = '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\enterprise'
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

$infoName = 'THONG-TIN-PHAT-HANH-v4.3.txt'
$primaryArtifact = @($artifactResults.ToArray())[0]
$infoLines = @(
    "TOOL KIEM TRA v$releaseVersion ENTERPRISE - MOT EXE ANYCPU",
    "Release version: $releaseVersion",
    "Release build date: $releaseBuildDate",
    "Release label: $releaseLabel",
    "Tep chay duy nhat: Tool-Kiem-Tra-v$productVersion.exe",
    "SHA-256: $($primaryArtifact.Sha256)",
    'AnyCPU: CLR tu chay x64 tren Windows 64-bit va x86 tren Windows 32-bit; khong bat Prefer 32-bit.',
    'Fail-closed neu phat hien tien trinh 32-bit tren Windows 64-bit de tranh WOW64 redirection.',
    'PowerShell duoc khoi dong voi ExecutionPolicy RemoteSigned; khong dung Bypass.',
    'Capability detection chon CIM/WMI, ScheduledTasks/schtasks va cac tinh nang theo he dieu hanh.',
    'Dashboard schema 2.0: WinForms hien dai, the trang thai Windows/Office, tile co mo ta, responsive DPI, Light/Dark day du.',
    'Typography dong bo Segoe UI/GDI+; dashboard fit WorkingArea sau DPI va chi bat cuon doc du phong khi man hinh qua thap.',
    'Da ngon ngu: vi-VN va en-US dung catalog JSON dong bo cho dashboard, log trang thai, bao cao, Muc 8 va trinh quan ly Windows/Office cuc bo; lua chon duoc ghi nho theo tai khoan.',
    'Muc 5 giu nguyen giao dien, chuc nang va cac bang bao cao chinh cua v4.3.0.3; kiem tra ben thu ba chi noi them o cuoi bao cao va DetailedInventory JSON.',
    'Offline toan ung dung mac dinh; Muc 8 co cong tac mang rieng mac dinh tat, co the bat/tat lai ma khong an chuc nang hoac xoa cau hinh.',
    "Compatibility catalog schema $($compatibilityMetadata.SchemaVersion), ra soat $($compatibilityMetadata.ReviewedAtUtc); bat buoc cap nhat khi qua $($compatibilityMetadata.MaximumReviewAgeDays) ngay.",
    'Nhan dien Windows 11 24H2 build 26100, 25H2 build 26200 va 26H1 build 28000; build moi khong ro duoc danh dau can ra soat.',
    'Nhan dien Office 2024/LTSC 2024 va Microsoft 365 Apps theo ProductReleaseIds, Click-to-Run channel va build.',
    'Enterprise: may chu quet CIDR/IP, ghep noi bang ma tam thoi, quan ly fleet, xuat JSON/CSV/HTML/PDF va gui tac vu license da ma hoa.',
    'Enterprise UI hotfix: co-fit theo WorkingArea/DPI, khong tran ngang; Quet nhanh tu nhan CIDR cuc bo khi o nhap trong.',
    'Enterprise IP auto: may chu tu chon IPv4 LAN uu tien theo card co gateway; may tram tu do server duy nhat khi de trong dia chi.',
    'Enterprise server reset: nut Xoa cau hinh may chu bat buoc ma quan tri va xac nhan cuoi; giu bao cao, ket qua va audit.',
    'Enterprise UI refresh: bo muc Tren may nay; doi thanh Chon chuc nang; them mau theo chuc nang, nut Tro ve phien truoc va nut Dong chuc nang 8.',
    'Enterprise network toggle: nut Cho phep mang cho Muc 8 doi thanh Tat mang cho Muc 8 sau khi bat; ba chuc nang luon hien thi.',
    'Enterprise UI close hotfix: ve tab dung RectangleF de tranh loi overload DrawString va dam bao nut Dong chuc nang 8 hoat dong.',
    'Enterprise local manager restore: khoi phuc quan ly license cuc bo duoi ten chuc nang moi, khong dung lai ten tab Tren may nay.',
    'Enterprise quick scan hotfix: sua loi hien thi ket qua khi IP phan hoi va them kiem thu hoi quy PowerShell 5.1.',
    'Full dark mode: ghi nho Light/Dark, phu dashboard, cac cua so con, chuc nang 8 va quan ly cuc bo Windows/Office; tu dong truyen theme qua UAC.',
    'May tram tu dong gui bao cao hoac xep hang DPAPI khi mat route; thay doi license tu xa mac dinh tat va phai duoc may tram cho phep.',
    'Cleanup Action Center co vung cuon/nut xu ly tiep; Office KMS dung OSPP /dstatusall va rang buoc lua chon theo tung SKU/Last5.',
    "Report schema $($reportSchemaMetadata.SchemaVersion): $(@($reportSchemaMetadata.ReportKinds).Count) loai bao cao; safety policy schema $($safetyPolicyMetadata.SchemaVersion); quick repair khong doi StartupType.",
    'Bao cao xuat HTML/PDF/JSON/XML voi giao dien chuyen nghiep dong bo, responsive va print A4; ngat trang PDF an toan de khong mat noi dung.',
    'HTML/PDF nguoi dung duoc luu truc tiep tren Desktop; sau khi xong Tool mo HTML bang trinh duyet mac dinh, khong mo PDF hay Notepad.',
    'Huong dan vi-VN/en-US duoc nhung trong EXE; Muc 10, lua chon 6 xuat HTML/PDF A4 va mo truc tiep HTML.',
    'HTML/PDF chi dung asset cuc bo, CSP default-src none; browser PDF tat background networking va map DNS ve 0.0.0.0.',
    'Profile Edge/Chrome tam nam trong %LOCALAPPDATA%\Temp, ACL chi cho nguoi dung hien tai va SYSTEM; profile duoc don sau moi lan xuat.',
    'Plugin chi dung JSON khai bao, khong chay script/command; thu muc plugin co ACL Administrators/SYSTEM.',
    'Timeline dung DPAPI LocalMachine, HMAC-SHA256 va hash chain; neu chuoi hong tool tu choi noi them.',
    'Certificate audit kiem tra Authenticode va chuoi tin cay offline cua tep Windows/Office quan trong.',
    "Module contract schema $($moduleContractMetadata.ContractSchemaVersion): $($moduleContractMetadata.EntryPointCount) entry point / $($moduleContractMetadata.ModuleCount) module; co capability gate va ModuleResult thong nhat.",
    'Log JSON Lines nam trong ProgramData co ACL Administrators/SYSTEM; khong ghi product key day du.',
    'PE: HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, Terminal Server Aware.',
    'CFG/load configuration native chua duoc tuyen bo; xem SECURITY-HARDENING-v4.3.md.',
    'Pham vi runtime: Windows 7 SP1 den Windows 11 desktop x64/x86; compatibility catalog hien tai tap trung Windows 11 24H2/25H2/26H1.',
    'Khong the vuot AppLocker, WDAC, SmartScreen, antivirus hoac chinh sach doanh nghiep.'
)
[IO.File]::WriteAllLines((Join-Path $OutputDirectory $infoName), $infoLines, (New-Object Text.UTF8Encoding($false)))

$releaseHashFiles = @($targets.OutputName) + @(
    'approved-kms-servers.txt', 'HUONG-DAN.txt', 'USER-GUIDE-en-US.md', 'LICENSE-NOTICE.txt',
    'MODULE-CONTRACT-v1.0.md', 'REPORT-SCHEMA-v1.5.md', 'SAFETY-POLICY-v1.0.md',
    'TECHNICAL-ARCHITECTURE-v4.3.md', 'ENTRY-POINTS-v4.3.md', 'COMPATIBILITY-MATRIX-v4.3.md',
    'OFFLINE-AND-REPORTING-v4.3.md', 'LOCALIZATION-v1.0.md', 'SECURITY-HARDENING-v4.3.md',
    'compatibility-catalog-v1.0.json', 'builtin-windows-office-trust.plugin.json', 'RELEASE-MANIFEST.json', $infoName
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
    & (Join-Path $sourceDirectory 'VERIFY-ENTERPRISE.ps1') -SourceDirectory $sourceDirectory
    if ($LASTEXITCODE -ne 0) { throw "VERIFY-ENTERPRISE.ps1 thất bại, mã thoát: $LASTEXITCODE" }
    Write-Host '[7/8] Kiểm tra phát hành tổng thể...'
    & (Join-Path $sourceDirectory 'VERIFY-RELEASE.ps1') -SourceDirectory $sourceDirectory -DistributionDirectory $OutputDirectory
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
