[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [string]$DistributionDirectory = '',
    [switch]$AllowDevelopmentManifest
)

$ErrorActionPreference = 'Stop'
$productVersion = '4.8'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($DistributionDirectory)) { $DistributionDirectory = Join-Path $SourceDirectory 'dist' }
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-Sha256Hex([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-HashManifest([string]$ManifestPath, [string]$RootPath, [int]$ExpectedCount, [switch]$AllowRelativePaths) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $failures.Add("Thiếu manifest: $ManifestPath")
        return
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $ManifestPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
            $failures.Add("Dòng hash không hợp lệ trong $([IO.Path]::GetFileName($ManifestPath)): $line")
            continue
        }
        $name = $matches[2].Trim()
        $normalizedName = $name.Replace('/', '\')
        $rootFull = [IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
        $path = [IO.Path]::GetFullPath((Join-Path $RootPath $normalizedName))
        $unsafeName = if ($AllowRelativePaths) {
            [IO.Path]::IsPathRooted($name) -or $normalizedName -match '(^|\\)\.\.(\\|$)' -or
            -not $path.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
        } else {
            [IO.Path]::GetFileName($name) -ne $name
        }
        if ($unsafeName -or -not $seen.Add($normalizedName)) {
            $failures.Add("Tên tệp không an toàn hoặc bị lặp trong manifest: $name")
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("Manifest tham chiếu tệp bị thiếu: $name")
            continue
        }
        if ((Get-Sha256Hex $path) -ne $matches[1].ToUpperInvariant()) { $failures.Add("Sai SHA-256: $name") }
    }
    if ($seen.Count -ne $ExpectedCount) { $failures.Add("Manifest sai số lượng tệp: $($seen.Count), yêu cầu đúng $ExpectedCount") }
}

function Get-VerificationPowerShell([string]$Architecture) {
    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $path = if ($Architecture -eq 'x64') {
        Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        Join-Path $windowsDirectory 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return $path
}

$sourceDirectoryFull = [IO.Path]::GetFullPath($SourceDirectory)
$distributionDirectoryFull = [IO.Path]::GetFullPath($DistributionDirectory)
$peHelperPath = Join-Path $sourceDirectoryFull 'PE-HARDENING.ps1'
$embeddedVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-EMBEDDED-PAYLOAD.ps1'
$foundationVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-FOUNDATION.ps1'
$moduleVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-MODULE-CONTRACT.ps1'
$reportSchemaVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-REPORT-SCHEMA.ps1'
$safetyVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-SAFETY-REGRESSIONS.ps1'
$dashboardVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-DASHBOARD.ps1'
$extensionsVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-EXTENSIONS.ps1'
$enterpriseVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-ENTERPRISE.ps1'
$compatibilityVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-COMPATIBILITY.ps1'
$offlineI18nVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-OFFLINE-I18N.ps1'
$localizationVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-LOCALIZATION-COVERAGE.ps1'
$performanceVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-PERFORMANCE.ps1'
$dataLifecycleVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-DATA-LIFECYCLE.ps1'
$applicationUpdateVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-APPLICATION-UPDATE.ps1'
$assistantVerifierPath = Join-Path $sourceDirectoryFull 'VERIFY-ASSISTANT.ps1'
if (-not (Test-Path -LiteralPath $peHelperPath -PathType Leaf)) { $failures.Add('Thiếu PE-HARDENING.ps1.') }
else { . $peHelperPath }
if (-not (Test-Path -LiteralPath $embeddedVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-EMBEDDED-PAYLOAD.ps1.') }
if (-not (Test-Path -LiteralPath $foundationVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-FOUNDATION.ps1.') }
if (-not (Test-Path -LiteralPath $moduleVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-MODULE-CONTRACT.ps1.') }
if (-not (Test-Path -LiteralPath $reportSchemaVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-REPORT-SCHEMA.ps1.') }
if (-not (Test-Path -LiteralPath $safetyVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-SAFETY-REGRESSIONS.ps1.') }
if (-not (Test-Path -LiteralPath $dashboardVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-DASHBOARD.ps1.') }
if (-not (Test-Path -LiteralPath $extensionsVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-EXTENSIONS.ps1.') }
if (-not (Test-Path -LiteralPath $enterpriseVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-ENTERPRISE.ps1.') }
if (-not (Test-Path -LiteralPath $compatibilityVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-COMPATIBILITY.ps1.') }
if (-not (Test-Path -LiteralPath $offlineI18nVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-OFFLINE-I18N.ps1.') }
if (-not (Test-Path -LiteralPath $localizationVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-LOCALIZATION-COVERAGE.ps1.') }
if (-not (Test-Path -LiteralPath $performanceVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-PERFORMANCE.ps1.') }
if (-not (Test-Path -LiteralPath $dataLifecycleVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-DATA-LIFECYCLE.ps1.') }
if (-not (Test-Path -LiteralPath $applicationUpdateVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-APPLICATION-UPDATE.ps1.') }
if (-not (Test-Path -LiteralPath $assistantVerifierPath -PathType Leaf)) { $failures.Add('Thiếu VERIFY-ASSISTANT.ps1.') }

foreach ($script in Get-ChildItem -LiteralPath $sourceDirectoryFull -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { $failures.Add("Lỗi cú pháp $($script.Name): $($parseError.Message)") }
}

Test-HashManifest (Join-Path $sourceDirectoryFull 'TOOL-SHA256SUMS.txt') $sourceDirectoryFull 47
Test-HashManifest (Join-Path $sourceDirectoryFull 'SOURCE-SHA256SUMS.txt') $sourceDirectoryFull 91
Test-HashManifest (Join-Path $sourceDirectoryFull 'SOURCE-PACKAGE-SHA256SUMS.txt') $sourceDirectoryFull 102 -AllowRelativePaths
Test-HashManifest (Join-Path $distributionDirectoryFull 'RELEASE-SHA256SUMS.txt') $distributionDirectoryFull 25

$manifestPath = Join-Path $sourceDirectoryFull 'Tool-Kiem-Tra-v4.8-OneFile.manifest'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $failures.Add('Thiếu application manifest v4.8.')
} else {
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    if ($manifestText -notmatch 'requestedExecutionLevel\s+level="asInvoker"') { $failures.Add('Application manifest chưa dùng asInvoker cho dashboard least-privilege.') }
    if ($manifestText -match 'requestedExecutionLevel\s+level="requireAdministrator"') { $failures.Add('Application manifest vẫn buộc quyền quản trị ngay khi mở.') }
    if ($manifestText -notmatch 'version="4\.8\.0\.1"') { $failures.Add('Application manifest sai phiên bản 4.8.0.1.') }
}

$versionChecks = @(
    @{ File='Giao-Dien.ps1'; Pattern='\$toolVersion\s*=\s*"4\.8\.0"' },
    @{ File='Giao-Dien.ps1'; Pattern='\$releaseVersion\s*=\s*"4\.8\.0\.1"' },
    @{ File='Giao-Dien.ps1'; Pattern='\$releaseBuildDate\s*=\s*"2026\.08\.18"' },
    @{ File='kiem-tra-cau-hinh-ban-quyen.ps1'; Pattern='\$ToolVersion\s*=\s*"4\.8"' },
    @{ File='windows-license-forensics.ps1'; Pattern='\$toolVersion\s*=\s*"4\.8"' },
    @{ File='Tool-Kiem-Tra-v4.8-OneFile.cs'; Pattern='AssemblyVersion\("4\.8\.0\.1"\)' },
    @{ File='Tool-Kiem-Tra-v4.8-OneFile.cs'; Pattern='AssemblyFileVersion\("4\.8\.0\.1"\)' },
    @{ File='Tool-Kiem-Tra-v4.8-OneFile.cs'; Pattern='AssemblyInformationalVersion\("4\.8\.0\.1"\)' }
)
foreach ($check in $versionChecks) {
    $path = Join-Path $sourceDirectoryFull $check.File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -notmatch $check.Pattern) {
        $failures.Add("Sai hoặc thiếu nhãn phiên bản trong $($check.File)")
    }
}

$guiText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Giao-Dien.ps1') -Raw -Encoding UTF8
$elevatedBridgeText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ElevatedBridge.ps1') -Raw -Encoding UTF8
$cleanupText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-compliance-cleanup.ps1') -Raw -Encoding UTF8
$backupText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-backup.ps1') -Raw -Encoding UTF8
$restoreText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-restore.ps1') -Raw -Encoding UTF8
$reportText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
$launcherText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Kiem-Tra-v4.8-OneFile.cs') -Raw -Encoding UTF8
$buildText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'BUILD.ps1') -Raw -Encoding UTF8
$runtimeText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Runtime.ps1') -Raw -Encoding UTF8
$capabilityText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Capabilities.ps1') -Raw -Encoding UTF8
$loggingText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Logging.ps1') -Raw -Encoding UTF8
$moduleContractText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ModuleContract.ps1') -Raw -Encoding UTF8
$reportSchemaText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ReportSchema.ps1') -Raw -Encoding UTF8
$safetyPolicyText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-SafetyPolicy.ps1') -Raw -Encoding UTF8
$dataLifecycleText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-DataLifecycle.ps1') -Raw -Encoding UTF8
$reportExportText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ReportExport.ps1') -Raw -Encoding UTF8
$pluginEngineText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-PluginEngine.ps1') -Raw -Encoding UTF8
$timelineText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-LicenseTimeline.ps1') -Raw -Encoding UTF8
$assuranceText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-assurance.ps1') -Raw -Encoding UTF8
$enterpriseText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Enterprise.ps1') -Raw -Encoding UTF8
$enterpriseHostText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-EnterpriseHost.ps1') -Raw -Encoding UTF8
$enterpriseAgentText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-EnterpriseAgent.ps1') -Raw -Encoding UTF8
$enterpriseUiText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'enterprise-license-manager.ps1') -Raw -Encoding UTF8
$compatibilityText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Compatibility.ps1') -Raw -Encoding UTF8
$localizationText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Localization.ps1') -Raw -Encoding UTF8
$offlinePolicyText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-OfflinePolicy.ps1') -Raw -Encoding UTF8
$assistantText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Assistant.ps1') -Raw -Encoding UTF8

if ($guiText -notmatch '\$dashboardSchemaVersion\s*=\s*"2\.0"' -or
    $guiText -notmatch 'WindowsReleaseName' -or $guiText -notmatch 'OfficeSummary') {
    $failures.Add('Dashboard chưa hiển thị schema 2.0 và trạng thái Windows/Office v4.3.')
}
if ($guiText -notmatch 'function\s+Show-ProductIntroduction' -or
    $guiText -notmatch 'introDetailButton' -or
    $guiText -notmatch 'dashboard\.overview\.title' -or
    $guiText -notmatch 'function\s+Set-ModernRoundedRegion' -or
    $guiText -notmatch '\$ultraCompactHeight' -or
    $guiText -notmatch '\$sidebarPanel' -or
    $guiText -notmatch '\$activityPanel' -or
    $guiText -notmatch 'function\s+Show-DashboardPreferences') {
    $failures.Add('Dashboard v4.8.0.1 thiếu overview/nút giới thiệu, shell hiện đại, bo góc hoặc chế độ gọn.')
}
if ($guiText -notmatch 'introAssistantButton' -or $guiText -notmatch 'Show-ToolAssistantWindow' -or
    $guiText -notmatch 'TitleLabel' -or $guiText -notmatch 'DescriptionLabel' -or
    $guiText -notmatch 'Color\]::FromArgb\(0,\s*98,\s*218\)') {
    $failures.Add('Dashboard v4.8 thiếu nút Trợ lý Tool hoặc tiêu đề xanh thích ứng cho 10 chức năng.')
}
if ($guiText -notmatch 'TOOL_SECURE_LAUNCH' -or $guiText -notmatch 'Test-ProtectedToolDirectoryAcl') { $failures.Add('Giao diện thiếu khóa secure-launch/ACL.') }
if ($guiText -notmatch 'New-ToolElevatedBootstrapArguments' -or $guiText -notmatch 'Tool-ElevatedBridge\.ps1' -or
    $elevatedBridgeText -notmatch 'Test-BridgeProtectedDirectoryAcl' -or
    $elevatedBridgeText -notmatch 'ElevatedBridgeScriptBindingInvalid' -or
    $elevatedBridgeText -notmatch "'cleanup\.deep'\s*=\s*'windows-license-compliance-cleanup\.ps1'" -or
    $elevatedBridgeText -notmatch 'ProcessStartInfo' -or
    $elevatedBridgeText -notmatch 'UseShellExecute\s*=\s*\$false' -or
    $elevatedBridgeText -notmatch 'EnvironmentVariables\[\$name\]') {
    $failures.Add('Thiếu cầu nối UAC đã khóa module/script/runtime và allowlist biến môi trường.')
}
if ($launcherText -notmatch 'RequiresAdministrator' -or $launcherText -notmatch 'RelaunchElevated' -or
    $launcherText -notmatch 'SpecialFolder\.LocalApplicationData' -or $launcherText -notmatch 'TOOL_DATA_SCOPE') {
    $failures.Add('Launcher thiếu dashboard user-scope hoặc nâng quyền theo nhu cầu.')
}
if ($launcherText -notmatch '--repair-user-data-acl' -or
    $launcherText -notmatch 'EnsureGuiUserDataAccess' -or
    $launcherText -notmatch 'IsExpectedUserDataBase' -or
    $launcherText -notmatch 'ProfileList' -or
    $launcherText -notmatch 'TOOL_DATA_OWNER_SID') {
    $failures.Add('Launcher thiếu tự phục hồi ACL user-scope có UAC hoặc khóa đích theo SID/profile.')
}
if ($guiText -notmatch 'TOOL_DATA_OWNER_SID' -or $elevatedBridgeText -notmatch 'TOOL_DATA_OWNER_SID' -or
    $elevatedBridgeText -notmatch 'ElevatedBridgeDataOwnerSidInvalid') {
    $failures.Add('Cầu nối UAC chưa giữ và xác thực SID sở hữu dữ liệu user-scope.')
}
foreach ($aclScript in @($cleanupText, $backupText)) {
    if ($aclScript -notmatch 'Get-ToolDataOwnerSid' -or
        $aclScript -notmatch 'Set-ProtectedBackupAcl\s+-Path\s+\$path\s+-AllowCurrentUserForUserScope:\$userScope' -or
        $aclScript -notmatch 'Set-ProtectedBackupAcl\s+-Path\s+\$backupRoot') {
        $failures.Add('Luồng backup/cleanup còn nguy cơ khóa parent user-scope hoặc chưa giữ backup root chỉ cho quản trị viên.')
        break
    }
}
if ($guiText -notmatch 'Verb\s*=\s*"RunAs"' -or $guiText -notmatch 'ArgumentList\s+"--enterprise-ui"\s+-Verb\s+RunAs') {
    $failures.Add('Cập nhật/Mục 8 chưa yêu cầu quyền quản trị theo từng thao tác.')
}
if ($guiText -notmatch 'function\s+New-ToolReportRunDirectory' -or $guiText -notmatch 'function\s+Open-ToolHtmlReport' -or
    $reportText -notmatch 'WindowsConclusionCode' -or $reportText -notmatch 'KmsUnapprovedHost') {
    $failures.Add('Thiếu thư mục xuất riêng, giới hạn mở HTML hoặc kết luận bản quyền chặt chẽ v4.8.')
}
if ($assistantText -notmatch 'function\s+Show-ToolAssistantWindow' -or
    $assistantText -notmatch 'function\s+Get-ToolAssistantAnswer' -or
    $assistantText -notmatch 'DownloadOnlySignedKnowledgePackage' -or
    $assistantText -notmatch 'DetachedCmsSha256PinnedCertificate' -or
    $assistantText -notmatch 'PaidApiRequired\s*=\s*\$false' -or
    $assistantText -notmatch 'CodexRequired\s*=\s*\$false' -or
    $assistantText -notmatch 'ReportUpload\s*=\s*\$false' -or
    $assistantText -notmatch 'PortableEveryMachine\s*=\s*\$true' -or
    $assistantText -notmatch 'CentralServerRequired\s*=\s*\$false' -or
    $assistantText -notmatch 'Windows\.Forms\.FlowLayoutPanel' -or
    $assistantText -notmatch 'IsSubmitting') {
    $failures.Add('Trợ lý Tool v4.8 thiếu máy trả lời cục bộ hoặc ranh giới không API/Codex/upload.')
}
if ($guiText -notmatch 'enterprise-license-manager\.ps1' -or
    $guiText -notmatch 'status\.enterprise\.opening' -or
    $guiText -notmatch 'ArgumentList\s+"--enterprise-ui"') {
    $failures.Add('Mục 8 chưa nối tới trung tâm enterprise server/client.')
}
if ($enterpriseText -notmatch 'AES-256|AesManaged' -or $enterpriseText -notmatch 'HMACSHA256' -or
    $enterpriseText -notmatch 'EnterpriseInventory' -or $enterpriseText -notmatch 'Find-ToolEnterpriseNetworkDevices' -or
    $enterpriseText -notmatch 'AllowRemoteLicenseChanges') {
    $failures.Add('Lõi enterprise thiếu mã hóa, inventory, quét mạng hoặc quyền opt-in.')
}
if ($enterpriseHostText -notmatch 'HttpListener' -or $enterpriseHostText -notmatch '/tool/v1/enroll' -or
    $enterpriseHostText -notmatch '/tool/v1/report' -or $enterpriseHostText -notmatch 'Test-ToolEnterpriseHostReplay') {
    $failures.Add('Máy chủ enterprise thiếu listener/endpoint/replay protection.')
}
if ($enterpriseAgentText -notmatch 'Flush-ToolEnterpriseOutbox' -or $enterpriseAgentText -notmatch 'Get-ToolEnterpriseClientJob' -or
    $enterpriseAgentText -notmatch 'Invoke-ToolEnterpriseLicenseJob') {
    $failures.Add('Agent enterprise thiếu hàng đợi, nhận tác vụ hoặc thực thi chính thức.')
}
if ($guiText -match '-FilePath\s+["'']powershell\.exe["'']' -or $guiText -notmatch 'FilePath\s*=\s*\$toolPowerShellPath') {
    $failures.Add('Giao diện còn gọi powershell.exe mơ hồ hoặc chưa dùng đường dẫn native đã xác minh.')
}
if ($launcherText -notmatch 'Environment\.Is64BitOperatingSystem' -or
    $launcherText -notmatch 'RuntimeArchitecture' -or
    $launcherText -notmatch 'TOOL_BUILD_ARCHITECTURE.+AnyCPU' -or
    $launcherText -notmatch 'TOOL_EXPECTED_PROCESS_ARCHITECTURE' -or
    $launcherText -notmatch 'TOOL_POWERSHELL_PATH' -or
    $launcherText -notmatch 'TOOL_LOG_PATH' -or $launcherText -notmatch 'TOOL_PLUGIN_DIR' -or
    $launcherText -notmatch 'TOOL_TIMELINE_PATH' -or $launcherText -notmatch 'TOOL_TIMELINE_KEY_PATH' -or
    $launcherText -notmatch 'TOOL_CORRELATION_ID' -or
    $launcherText -notmatch 'TOOL_MODULE_CONTRACT_SCHEMA' -or
    $launcherText -notmatch 'TOOL_REPORT_SCHEMA' -or $launcherText -notmatch 'TOOL_SAFETY_POLICY_SCHEMA' -or
    $launcherText -notmatch 'TOOL_DASHBOARD_SCHEMA' -or
    $launcherText -notmatch 'TOOL_COMPATIBILITY_SCHEMA' -or
    $launcherText -notmatch 'TOOL_LOCALIZATION_SCHEMA' -or
    $launcherText -notmatch 'TOOL_OFFLINE_POLICY_SCHEMA' -or
    $launcherText -notmatch 'TOOL_OFFLINE_MODE' -or
    $launcherText -notmatch 'TOOL_ENTERPRISE_ROOT' -or
    $launcherText -notmatch 'TOOL_LAUNCHER_PID' -or
    $launcherText -notmatch 'TOOL_ENTERPRISE_SCHEMA' -or
    $launcherText -notmatch '--enterprise-server' -or
    $launcherText -notmatch '--enterprise-agent' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(logsDirectory,\s*machineScope\)' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(pluginsDirectory,\s*machineScope\)' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(timelineDirectory,\s*machineScope\)') {
    $failures.Add('Launcher AnyCPU thiếu tự nhận diện, chặn x86-on-x64, PowerShell native hoặc module schema.')
}
if ($launcherText -match 'powershellPath\s*=\s*"powershell\.exe"') { $failures.Add('Launcher còn fallback sang powershell.exe từ PATH.') }
if ($runtimeText -notmatch 'Is64BitOperatingSystem\s*-and\s*-not\s*\[Environment\]::Is64BitProcess' -or
    $runtimeText -notmatch 'Get-ToolNativeSystemPath' -or $runtimeText -notmatch 'Sysnative') {
    $failures.Add('Tool-Runtime.ps1 thiếu chặn WOW64 hoặc đường dẫn System32 native.')
}
if ($capabilityText -notmatch 'ToolVersion\s*=\s*"4\.8"' -or
    $capabilityText -notmatch 'SchemaVersion\s*=\s*"1\.1"' -or
    $capabilityText -notmatch 'Get-ToolWindowsReleaseProfile' -or
    $capabilityText -notmatch 'Get-ToolOfficeCompatibilityProfile' -or
    $capabilityText -notmatch 'CompatibilityTier' -or $capabilityText -notmatch 'CimCmdlets' -or
    $capabilityText -notmatch 'WmiFallback' -or $capabilityText -notmatch 'ScheduledTasksFallback') {
    $failures.Add('Tool-Capabilities.ps1 thiếu schema 1.1, catalog Windows/Office hoặc capability/fallback bắt buộc.')
}
if ($loggingText -notmatch 'TOOL_LOG_PATH' -or $loggingText -notmatch 'TOOL_CORRELATION_ID' -or
    $loggingText -notmatch 'TOOL_MODULE_ID' -or $loggingText -notmatch 'TOOL_MODULE_INVOCATION_ID' -or
    $loggingText -notmatch 'ThanhViet-Tool-Kiem-Tra\\v4\.6' -or
    $loggingText -notmatch 'Join-Path\s+\$dataRoot\s+"logs"' -or $loggingText -notmatch 'ReparsePoint' -or
    $loggingText -notmatch 'ConvertTo-Json.+-Compress' -or $loggingText -notmatch '32768') {
    $failures.Add('Tool-Logging.ps1 thiếu JSONL schema, vùng log bảo vệ hoặc giới hạn bản ghi.')
}
if ($guiText -notmatch 'Get-ToolCapabilityProfile' -or $guiText -notmatch 'Initialize-ToolLogging' -or
    $guiText -notmatch 'ChildProcess\.Exit' -or $reportText -notmatch 'Capabilities\s*=\s*\$capabilityState') {
    $failures.Add('GUI/báo cáo chưa tích hợp capability detection và structured logging v4.3.')
}
if ($moduleContractText -notmatch 'ToolModuleContractSchemaVersion\s*=\s*"1\.0"' -or
    $moduleContractText -notmatch 'ToolModuleResultSchemaVersion\s*=\s*"1\.0"' -or
    $moduleContractText -notmatch 'Test-ToolModuleAvailability' -or
    $moduleContractText -notmatch 'Complete-ToolModuleInvocation' -or
    $moduleContractText -notmatch 'assurance\.certificates' -or $moduleContractText -notmatch 'assurance\.plugins' -or $moduleContractText -notmatch 'assurance\.timeline' -or
    $moduleContractText -notmatch 'inventory\.registry' -or $moduleContractText -notmatch 'inventory\.service' -or $moduleContractText -notmatch 'inventory\.task' -or
    $moduleContractText -notmatch 'application\.update\.check') {
    $failures.Add('Tool-ModuleContract.ps1 thiếu schema, capability gate, ModuleResult hoặc nhóm logical bắt buộc.')
}
if ($guiText -notmatch 'Start-ToolModuleProcess' -or $guiText -notmatch 'Module\.Complete' -or
    $guiText -match 'Start-Process\s+-FilePath\s+\$toolPowerShellPath' -or
    $reportText -notmatch 'ModuleResult\s*=\s*\$moduleResult' -or $reportText -notmatch 'Complete-ToolModuleInvocation') {
    $failures.Add('GUI/báo cáo chưa dùng hợp đồng mô-đun v4.3 thống nhất.')
}

if ($compatibilityText -notmatch 'ToolCompatibilitySchemaVersion\s*=\s*"1\.0"' -or
    $compatibilityText -notmatch 'Get-ToolWindowsReleaseProfile' -or
    $compatibilityText -notmatch 'Get-ToolOfficeCompatibilityProfile' -or
    $compatibilityText -notmatch 'MaximumReviewAgeDays' -or
    $compatibilityText -notmatch 'CatalogFresh') {
    $failures.Add('Compatibility engine thiếu schema, nhận diện Windows/Office hoặc freshness gate.')
}
if ($localizationText -notmatch 'ToolLocalizationSchemaVersion\s*=\s*"1\.0"' -or
    $localizationText -notmatch '"vi-VN",\s*"en-US"' -or
    $localizationText -notmatch 'Get-ToolText' -or
    $localizationText -notmatch 'Set-ToolCulturePreference') {
    $failures.Add('Localization engine thiếu vi-VN/en-US, fallback hoặc lưu lựa chọn.')
}
if ($offlinePolicyText -notmatch 'ToolOfflinePolicySchemaVersion\s*=\s*"1\.0"' -or
    $offlinePolicyText -notmatch 'return\s+\$true' -or
    $offlinePolicyText -notmatch 'Assert-ToolNetworkActionAllowed' -or
    $offlinePolicyText -notmatch 'Internet.+LAN.+Loopback' -or
    $offlinePolicyText -notmatch 'Telemetry\s*=\s*"Disabled"' -or
    $offlinePolicyText -notmatch 'AutomaticUpdateCheckTrigger\s*=\s*"UserEnabledOnline"' -or
    $offlinePolicyText -notmatch 'SilentUpdate\s*=\s*\$false') {
    $failures.Add('Offline policy thiếu mặc định fail-closed, network gate hoặc telemetry disabled.')
}
if ($buildText -notmatch '/platform:\$\(\$target\.Platform\)' -or
    $buildText -notmatch "Platform='anycpu'" -or
    $buildText -notmatch '/highentropyva\+' -or
    $buildText -notmatch '/deterministic\+' -or $buildText -notmatch '/pathmap:' -or
    $buildText -match 'TOOL_X64|TOOL_X86|Platform=''(?:x64|x86|anycpu32bitpreferred)''') {
    $failures.Add('BUILD.ps1 chưa build AnyCPU không Prefer 32-bit, chưa bật HIGH_ENTROPY_VA hoặc chưa dùng Roslyn deterministic/pathmap.')
}

$executionPolicyFiles = Get-ChildItem -LiteralPath $sourceDirectoryFull -File | Where-Object { $_.Extension -in @('.ps1', '.cmd', '.cs', '.md', '.txt') }
foreach ($file in $executionPolicyFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($text -match '(?i)-ExecutionPolicy\s+Bypass') { $failures.Add("$($file.Name) còn dùng ExecutionPolicy Bypass.") }
}
if ($launcherText -notmatch '-ExecutionPolicy RemoteSigned' -or $guiText -notmatch '-ExecutionPolicy RemoteSigned') {
    $failures.Add('Launcher/Giao diện chưa dùng ExecutionPolicy RemoteSigned cho các tiến trình PowerShell con.')
}

$operationalScripts = @(
    'Giao-Dien.ps1', 'kiem-tra-cau-hinh-ban-quyen.ps1', 'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1', 'windows-license-restore.ps1',
    'windows-license-deep-scan.ps1', 'windows-license-forensics.ps1',
    'windows-oem-license-assistant.ps1', 'windows-office-license-manager.ps1',
    'windows-license-assurance.ps1', 'Tool-EnterpriseAgent.ps1', 'Tool-EnterpriseHost.ps1'
)
foreach ($name in $operationalScripts) {
    $text = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull $name) -Raw -Encoding UTF8
    if ($text -notmatch 'Assert-ToolNativeArchitecture') { $failures.Add("$name chưa chặn PowerShell 32-bit trên Windows 64-bit.") }
    if ($text -match '(?i)(?:&|Start-Process\s+)(?:sc|reg|cscript|certutil|sfc|netsh|w32tm|explorer|notepad)\.exe\b|Join-Path\s+\$env:(?:windir|SystemRoot)\s+["'']System32') {
        $failures.Add("$name còn gọi thành phần System32 qua đường dẫn có thể bị WOW64 chuyển hướng.")
    }
}

if ($cleanupText -notmatch '\[bool\]\$DefaultSelected\s*=\s*\$false') { $failures.Add('Danh sách cleanup chưa mặc định bỏ chọn.') }
if ($cleanupText -notmatch 'ToolVersion\s*=\s*"4\.8"' -or $cleanupText -notmatch 'LicenseNotice') { $failures.Add('Cleanup manifest v4.8 chưa đầy đủ.') }
if ($dataLifecycleText -notmatch 'ToolDataSchemaVersion\s*=\s*"2\.0"' -or
    $dataLifecycleText -notmatch 'ProducerVersion' -or
    $dataLifecycleText -notmatch 'Assert-ToolDataMigrationCopy' -or
    $dataLifecycleText -notmatch 'Merge-ToolDataMigrationStaging' -or
    $dataLifecycleText -notmatch 'Migration đã được hoàn tác') {
    $failures.Add('Data lifecycle v4.6 thiếu schema/producer, xác minh migration hoặc rollback.')
}
if ($cleanupText -notmatch '\[switch\]\$RedactSensitive' -or $cleanupText -notmatch 'Get-SecureBackupRoot') { $failures.Add('Cleanup thiếu chế độ che dữ liệu hoặc vùng backup ProgramData.') }
if ($backupText -notmatch 'HMACSHA256' -or $backupText -notmatch 'DataProtectionScope\]::LocalMachine' -or $backupText -notmatch 'Get-SecureBackupRoot') { $failures.Add('Backup thiếu HMAC/DPAPI LocalMachine/vùng ProgramData bảo vệ.') }
if ($restoreText -notmatch 'Test-ProtectedBackupAcl' -or $restoreText -notmatch 'BackupSha256' -or $restoreText -notmatch 'MachineBinding' -or $restoreText -notmatch 'expectedBackupRoot') { $failures.Add('Restore thiếu kiểm tra ACL/hash/máy/vùng backup.') }
if ($backupText -notmatch 'RuntimeHelperSha256' -or $cleanupText -notmatch 'RuntimeHelperSha256' -or $restoreText -notmatch 'RuntimeHelperSha256') {
    $failures.Add('Bộ backup/restore chưa xác thực Tool-Runtime.ps1 đi kèm.')
}
if ($backupText -notmatch 'SafetyPolicySha256' -or $cleanupText -notmatch 'SafetyPolicySha256' -or $restoreText -notmatch 'SafetyPolicySha256') {
    $failures.Add('Bộ backup/restore chưa xác thực Tool-SafetyPolicy.ps1 đi kèm.')
}
if ($reportText -notmatch '\[switch\]\$RedactSensitive' -or $reportText -notmatch 'strongCrackPattern') { $failures.Add('Báo cáo thiếu chế độ che dữ liệu hoặc mẫu phát hiện đặc hiệu.') }
if ($backupText -match 'Items\s*=\s*@\(\$items\)' -or $backupText -match 'Values\s*=\s*@\(\$values\)' -or
    $cleanupText -match 'Items\s*=\s*@\(\$restoreItems\)' -or $cleanupText -match 'Values\s*=\s*@\(\$values\)') {
    $failures.Add('Còn mẫu @() trực tiếp trên List[object], có thể gây lỗi Argument types do not match trong Windows PowerShell 5.1.')
}
if ($cleanupText -notmatch 'HandlingGuidance' -or $guiText -notmatch 'cleanup\.result\.guidanceHeading') { $failures.Add('Kết luận cleanup chưa kèm hướng xử lý đề xuất.') }
if ($reportSchemaText -notmatch 'ToolReportSchemaVersion\s*=\s*"1\.5"' -or
    $reportText -notmatch 'New-ToolReportEnvelope\s+-ReportKind\s+"InventoryAndLicense"' -or
    $cleanupText -notmatch 'New-ToolReportEnvelope\s+-ReportKind\s+"CleanupCompliance"' -or
    $moduleContractText -notmatch 'ToolModuleContractSchemaVersion') {
    $failures.Add('Schema báo cáo v4.3 chưa đồng bộ.')
}
if ($safetyPolicyText -notmatch 'ToolSafetyPolicySchemaVersion\s*=\s*"1\.0"' -or
    $safetyPolicyText -notmatch 'NoGenTicket' -or $safetyPolicyText -notmatch 'AllowStartupTypeChange=\$false') {
    $failures.Add('Safety policy v4.3 chưa khóa đúng NoGenTicket/StartupType.')
}
if ($reportExportText -notmatch 'Export-ToolReportXml' -or $reportExportText -notmatch 'Export-ToolReportPackage' -or
    $reportExportText -notmatch 'Export-ToolTextReportPresentation' -or
    $reportExportText -notmatch 'Convert-ToolHtmlToPdf' -or $reportExportText -notmatch 'Microsoft Word' -or
    $reportText -notmatch 'Export-ToolReportPackage') {
    $failures.Add('Bộ xuất báo cáo chưa đủ HTML/PDF/JSON/XML hoặc chưa được tích hợp.')
}
if ($reportExportText -notmatch 'ToolReportExportSchemaVersion\s*=\s*"1\.4"' -or
    $reportExportText -notmatch 'Test-ToolHtmlOfflineSafe' -or
    $reportExportText -notmatch "default-src 'none'" -or
    $reportExportText -notmatch 'no-pdf-header-footer' -or
    $reportExportText -notmatch 'print-to-pdf-no-header' -or
    $reportExportText -notmatch '@media\s+print' -or
    $reportExportText -notmatch 'section\{break-inside:auto!important' -or
    $reportExportText -notmatch '@page' -or
    $reportExportText -notmatch 'ConvertTo-ToolHtmlTableCell' -or
    $reportExportText -notmatch 'ConvertTo-ToolHtmlCompactPublisher' -or
    $reportExportText -notmatch 'PdfHtmlContent' -or
    $reportExportText -notmatch 'TOOL_REPORT_PDF_GUIDE' -or
    $reportText -notmatch 'data-report-view="summary"' -or
    $reportText -notmatch 'data-report-view="detailed"') {
    $failures.Add('HTML/PDF v4.3 thiếu offline safety gate, CSP hoặc bố cục in A4 hiện đại.')
}
if ($reportExportText -match 'TOOL_SECURE_RUNTIME_DIR' -or
    $reportExportText -notmatch 'LocalApplicationData' -or
    $reportExportText -notmatch 'Current user \+ SYSTEM' -or
    $reportExportText -notmatch 'Test-ToolPdfProfileDirectoryAcl' -or
    $reportExportText -notmatch 'Remove-ToolPdfProfileDirectory') {
    $failures.Add('Bản vá PDF R1 chưa tách profile khỏi ProgramData, chưa khóa ACL theo người dùng hoặc chưa dọn profile an toàn.')
}
if ($pluginEngineText -notmatch 'DeclarativeReadOnlyRules' -or $pluginEngineText -notmatch 'ArbitraryCodeAllowed\s*=\s*\$false' -or
    $pluginEngineText -notmatch 'Install-ToolPluginPackage' -or $pluginEngineText -notmatch 'Test-ToolPluginDirectory' -or
    $pluginEngineText -notmatch 'AreAccessRulesProtected' -or $pluginEngineText -notmatch 'Assert-ToolPluginPathWithoutReparsePoint' -or
    $pluginEngineText -notmatch '\[IO\.File\]::Replace' -or
    $guiText -notmatch 'Show-AssuranceCenter') {
    $failures.Add('Plugin engine/Trung tâm bảo đảm chưa khóa mô hình khai báo chỉ đọc.')
}
if ($timelineText -notmatch 'DataProtectionScope\]::LocalMachine' -or $timelineText -notmatch 'HMACSHA256' -or
    $timelineText -notmatch 'PreviousRecordHash' -or $timelineText -notmatch 'Save-ToolLicenseSnapshot' -or
    $timelineText -notmatch 'Assert-ToolTimelineDirectoryAcl' -or $timelineText -notmatch 'AreAccessRulesProtected' -or
    $reportText -notmatch 'Save-ToolLicenseSnapshot' -or $guiText -notmatch 'LicenseCleanupCompleted' -or
    $guiText -notmatch 'LicenseRestoreCompleted' -or $guiText -notmatch 'OemLicenseApplyCompleted') {
    $failures.Add('Timeline chưa có DPAPI/HMAC/hash chain hoặc chưa tích hợp snapshot.')
}
if ($assuranceText -notmatch 'Get-AuthenticodeSignature' -or $assuranceText -notmatch 'X509Chain' -or
    $assuranceText -notmatch 'CertificateAudit' -or $assuranceText -notmatch 'PluginAudit' -or $assuranceText -notmatch 'TimelineExport') {
    $failures.Add('Mô-đun assurance thiếu kiểm tra chứng chỉ/plugin/timeline.')
}
if ($buildText -notmatch 'SIGN-RELEASE\.ps1' -or $buildText -notmatch 'RequireAuthenticode' -or
    -not (Test-Path -LiteralPath (Join-Path $sourceDirectoryFull 'VERIFY-AUTHENTICODE.ps1') -PathType Leaf)) {
    $failures.Add('Chuỗi build chưa tích hợp ký/xác minh Authenticode có điều kiện.')
}
if ($cleanupText -notmatch 'ScanWarningCount' -or $cleanupText -notmatch 'cleanupReport\.action\.scanWarningBlocked' -or
    $guiText -notmatch 'Show-ScanWarningRecoveryDialog' -or $guiText -notmatch 'scanWarning\.repair') {
    $failures.Add('Cleanup chưa fail-closed khi nguồn quét quan trọng bị lỗi.')
}
if ($cleanupText -notmatch 'Get-CompatibleScheduledTaskRecords' -or $backupText -notmatch 'Get-CompatibleScheduledTaskRecords' -or $restoreText -notmatch 'Register-CompatibleScheduledTask') {
    $failures.Add('Backup/cleanup/restore thiếu fallback Scheduled Tasks cho Windows 7.')
}
if ($guiText -notmatch '(?s)Add_FormClosing\(.{0,600}?activeProcess.{0,600}?eventArgs\.Cancel\s*=\s*\$true') { $failures.Add('Giao diện chưa khóa đóng cửa sổ khi tác vụ con còn chạy.') }
if ($cleanupText -match '(?s)function\s+Run-Cscript\s*\{.{0,300}?\$Args\b') { $failures.Add('Run-Cscript dùng tên $Args trùng biến tự động PowerShell.') }
if ($cleanupText -notmatch 'param\(\[Parameter\(Mandatory\s*=\s*\$true\)\]\[string\[\]\]\$SlmgrArguments\)' -or
    $cleanupText -notmatch 'Invoke-SlmgrCommand\s+-SlmgrArguments\s+@\(''/upk'',\s*\$activationId\)' -or
    $cleanupText -notmatch 'TargetId\s*=\s*\$TargetId') {
    $failures.Add('Cleanup chưa truyền tham số slmgr an toàn hoặc chưa gỡ đúng Activation ID được chọn.')
}

try {
    $listObjectRegression = New-Object System.Collections.Generic.List[object]
    [void]$listObjectRegression.Add([pscustomobject]@{ Type='Regression'; Name='PowerShell 5.1' })
    $listJson = [pscustomobject]@{ Items=$listObjectRegression.ToArray() } | ConvertTo-Json -Depth 4
    $listRoundTrip = $listJson | ConvertFrom-Json
    if (@($listRoundTrip.Items).Count -ne 1) { throw 'Số mục sau JSON round-trip không đúng.' }
} catch { $failures.Add("Hồi quy List[object]/manifest thất bại: $($_.Exception.Message)") }

try {
    function Test-SlmgrArgumentBinding([string[]]$SlmgrArguments) { return ($SlmgrArguments -join '|') }
    if ((Test-SlmgrArgumentBinding @('/upk', 'activation-id')) -ne '/upk|activation-id') { throw 'Mảng tham số không giữ đủ hai phần tử.' }
} catch { $failures.Add("Hồi quy truyền tham số slmgr thất bại: $($_.Exception.Message)") }

foreach ($script in Get-ChildItem -LiteralPath $sourceDirectoryFull -Filter '*.ps1' -File) {
    if ($script.Name -eq 'BUILD.ps1' -or $script.Name -like 'VERIFY-*.ps1') { continue }
    $text = Get-Content -LiteralPath $script.FullName -Raw -Encoding UTF8
    if ($text -match '(?i)\bInvoke-Expression\b|\bEncodedCommand\b|\bInvoke-WebRequest\b|\bInvoke-RestMethod\b|\bStart-BitsTransfer\b') {
        $failures.Add("Phát hiện primitive tải/thực thi không được phép trong $($script.Name)")
    }
}

$payloadFiles = @(
    'approved-kms-servers.txt','HUONG-DAN.txt','USER-GUIDE-en-US.md','LICH-SU-PHIEN-BAN.txt','VERSION-HISTORY-en-US.md',
    'Giao-Dien.ps1','kiem-tra-cau-hinh-ban-quyen.ps1','Tool-Kiem-Tra-icon.svg','Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1','Tool-ElevatedBridge.ps1','Tool-DataLifecycle.ps1','Tool-Compatibility.ps1','compatibility-catalog-v1.0.json','Tool-Capabilities.ps1',
    'Tool-ScanOptimization.ps1',
    'Tool-Logging.ps1','Tool-ModuleContract.ps1','Tool-UiTheme.ps1','Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json','Tool-Strings.en-US.json','Tool-OfflinePolicy.ps1','Tool-Assistant.ps1','tool-assistant-knowledge-v1.1.json',
    'Tool-SoftwareInventory.ps1','software-license-catalog-v1.0.json','software-license-catalog-v1.0.json.p7s','software-license-online-update.ps1','Tool-UpdateManager.ps1',
    'Tool-ReportSchema.ps1','Tool-ReportExport.ps1','Tool-PluginEngine.ps1','Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1','Tool-Enterprise.ps1','Tool-EnterpriseHost.ps1','Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1','TOOL-SHA256SUMS.txt','windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1','windows-license-restore.ps1','windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1','windows-oem-license-assistant.ps1','windows-office-license-manager.ps1',
    'windows-license-assurance.ps1','builtin-windows-office-trust.plugin.json'
)
$payloadListArgument = $payloadFiles -join '|'
$targetFileName = 'Tool-Kiem-Tra-v4.8.exe'
$exePath = Join-Path $distributionDirectoryFull $targetFileName
$profile = $null
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    $failures.Add("Thiếu EXE phát hành: $targetFileName")
} else {
    if ([int64](Get-Item -LiteralPath $exePath).Length -gt 900000) {
        $failures.Add("$targetFileName vượt ngân sách 900000 byte của bản cập nhật tại chỗ.")
    }
    try {
        $profile = Get-PeSecurityProfile -Path $exePath
        if ($profile.ManagedPlatform -ne 'AnyCPU' -or $profile.Architecture -ne 'x86' -or
            $profile.Machine -ne '0x014C' -or $profile.PeFormat -ne 'PE32' -or
            -not $profile.Managed -or -not $profile.ClrIlOnly -or
            $profile.Clr32BitRequired -or $profile.Clr32BitPreferred) {
            $failures.Add("$targetFileName chưa đúng AnyCPU PE32/I386 IL-only hoặc còn cờ 32-bit bắt buộc/ưu tiên.")
        }
        foreach ($flag in @('HighEntropyVa','DynamicBase','NxCompat','NoSeh','TerminalServerAware')) {
            if (-not [bool]$profile.$flag) { $failures.Add("$targetFileName thiếu $flag.") }
        }
        if ($profile.ControlFlowGuardHeader -and (-not $profile.LoadConfigurationDirectoryPresent -or -not $profile.ControlFlowGuardInstrumented)) {
            $failures.Add("$targetFileName gắn GUARD_CF nhưng thiếu load-config/CFG instrumentation; từ chối cờ bảo vệ giả.")
        }
    } catch { $failures.Add("Không phân tích được PE ${targetFileName}: $($_.Exception.Message)") }

    foreach ($runtimeArchitecture in @('x64','x86')) {
        $verificationPowerShell = Get-VerificationPowerShell $runtimeArchitecture
        if (-not $verificationPowerShell) {
            $failures.Add("Không có PowerShell $runtimeArchitecture để đối chiếu EXE AnyCPU.")
        } elseif (Test-Path -LiteralPath $embeddedVerifierPath -PathType Leaf) {
            & $verificationPowerShell -NoProfile -ExecutionPolicy RemoteSigned -File $embeddedVerifierPath `
                -ExePath $exePath -SourceDirectory $sourceDirectoryFull -PayloadList $payloadListArgument -ExpectedArchitecture $runtimeArchitecture
            if ($LASTEXITCODE -ne 0) { $failures.Add("Đối chiếu EXE AnyCPU trên CLR $runtimeArchitecture thất bại.") }
        }
        if ($verificationPowerShell -and (Test-Path -LiteralPath $foundationVerifierPath -PathType Leaf)) {
            & $verificationPowerShell -NoProfile -ExecutionPolicy RemoteSigned -File $foundationVerifierPath `
                -SourceDirectory $sourceDirectoryFull -ExpectedArchitecture $runtimeArchitecture
            if ($LASTEXITCODE -ne 0) { $failures.Add("Kiểm tra nền tảng capability/logging trên $runtimeArchitecture thất bại.") }
        }
        if ($verificationPowerShell -and (Test-Path -LiteralPath $moduleVerifierPath -PathType Leaf)) {
            & $verificationPowerShell -NoProfile -ExecutionPolicy RemoteSigned -File $moduleVerifierPath `
                -SourceDirectory $sourceDirectoryFull -ExpectedArchitecture $runtimeArchitecture
            if ($LASTEXITCODE -ne 0) { $failures.Add("Kiểm tra module contract trên $runtimeArchitecture thất bại.") }
        }
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $exePath
    if ($signature.Status -ne 'Valid') {
        $warnings.Add("$targetFileName chưa có chữ ký Authenticode hợp lệ: $($signature.Status)")
    } elseif ($signature.SignerCertificate -and
        ([string]$signature.SignerCertificate.Subject -eq [string]$signature.SignerCertificate.Issuer -or
         [string]$signature.SignerCertificate.Subject -match '(?i)Self-Signed')) {
        $warnings.Add("$targetFileName dùng chứng thư tự ký; chỉ phù hợp thử nghiệm có kiểm soát khi chứng thư đã được phân phối qua kênh tin cậy.")
    }
}

if ($profile -and -not $profile.ControlFlowGuardHeader) {
    $warnings.Add('CFG/load configuration native chưa được tuyên bố cho launcher managed IL; SECURITY-HARDENING-v4.8.md ghi rõ giới hạn này.')
}

$releaseManifestPath = Join-Path $distributionDirectoryFull 'RELEASE-MANIFEST.json'
if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
    $failures.Add('Thiếu RELEASE-MANIFEST.json.')
} else {
    try {
        $releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$releaseManifest.SchemaVersion -ne '2.0' -or [string]$releaseManifest.ToolVersion -ne '4.8') { throw 'Sai schema/tool version.' }
        if (@($releaseManifest.Artifacts).Count -ne 1) { throw 'Release manifest phải có đúng một artefact AnyCPU.' }
        if ([string]$releaseManifest.PrimaryFileName -ne $targetFileName) { throw 'Sai PrimaryFileName.' }
        $entry = @($releaseManifest.Artifacts)[0]
        if ([string]$entry.FileName -ne $targetFileName -or [string]$entry.Architecture -ne 'AnyCPU') { throw 'Entry EXE không phải AnyCPU duy nhất.' }
        if ([string]$entry.Pe.ManagedPlatform -ne 'AnyCPU' -or [bool]$entry.Pe.Required32Bit -or [bool]$entry.Pe.Preferred32Bit) { throw 'Metadata CLR flags AnyCPU không hợp lệ.' }
        if ([string]$entry.Sha256 -ne (Get-Sha256Hex $exePath)) { throw "Sai SHA-256 metadata: $targetFileName." }
        if ([string]$releaseManifest.ControlFlowGuard.Status -ne 'NotClaimed') { throw 'Trạng thái CFG không minh bạch.' }
        if (-not [bool]$releaseManifest.DeterministicManagedBuild) { throw 'Release manifest chưa xác nhận deterministic managed build.' }
        if ([string]$releaseManifest.CapabilitySchemaVersion -ne '1.1' -or [string]$releaseManifest.LogSchemaVersion -ne '1.0-jsonl') { throw 'Thiếu metadata capability/log schema v4.3.' }
        if ([string]$releaseManifest.ReleaseVersion -ne '4.8.0.1' -or [string]$releaseManifest.ReleaseBuildDate -ne '2026.08.18') {
            throw 'Release manifest chưa đồng bộ phiên bản 4.8.0.1 / Build 2026.08.18.'
        }
        if ([string]$releaseManifest.ReleaseLabel -ne '4.8.0.1-production-20260818' -or
            [string]$releaseManifest.ReleaseStatus -ne 'Production') {
            throw 'Release chưa được nâng lên Production sau khi hoàn tất ma trận E2E.'
        }
        if ([int]$releaseManifest.PayloadCount -ne 49 -or [int]$releaseManifest.IntegrityFileCount -ne 47) { throw 'Sai số lượng payload/integrity.' }
        $payloadCompression = $releaseManifest.PayloadCompression
        if ([string]$payloadCompression.Scheme -ne 'SolidDeflateBundle-v1' -or
            [string]$payloadCompression.ResourceName -ne 'payload.bundle.deflate.v1' -or
            [int]$payloadCompression.FormatVersion -ne 1 -or
            [int]$payloadCompression.ResourceCount -ne 1 -or
            [int]$payloadCompression.PayloadCount -ne 49 -or
            [int64]$payloadCompression.HeaderBytes -ne 416 -or
            [int64]$payloadCompression.BundleBytes -ne ([int64]$payloadCompression.SourceBytes + [int64]$payloadCompression.HeaderBytes) -or
            [int64]$payloadCompression.SourceBytes -le [int64]$payloadCompression.EmbeddedBytes -or
            [int64]$payloadCompression.SavedBytes -ne ([int64]$payloadCompression.SourceBytes - [int64]$payloadCompression.EmbeddedBytes) -or
            [int64]$payloadCompression.MaximumPayloadBytes -ne 8388608 -or
            [int64]$payloadCompression.MaximumPayloadDataBytes -ne 16777216 -or
            [int64]$payloadCompression.MaximumCompressedBytes -ne 16777216 -or
            [int64]$payloadCompression.MaximumDecodedBytes -ne 33554432 -or
            [double]$payloadCompression.SavingsPercent -lt 50.0 -or [double]$payloadCompression.SavingsPercent -ge 100.0) {
            throw 'Metadata tối ưu dung lượng payload không hợp lệ.'
        }
        if ([string]$releaseManifest.DashboardSchemaVersion -ne '2.0' -or [string]$releaseManifest.DashboardMode -ne 'Modern adaptive WinForms dashboard' -or
            [string]$releaseManifest.StartupTheme -ne 'Light' -or [string]$releaseManifest.DarkMode -ne 'Optional per-session / WCAG-aware palette' -or
            [bool]$releaseManifest.QuickActionNumberLabels -or [int]$releaseManifest.DirectReportActionCount -ne 7 -or
            -not [bool]$releaseManifest.CleanupActionCenter -or -not [bool]$releaseManifest.AssuranceCenter -or
            [string]$releaseManifest.ElevatedModuleEnvironmentBridge -notmatch 'Encoded allowlisted TOOL_\* contract' -or
            [string]$releaseManifest.ElevatedModuleEnvironmentBridge -notmatch 'child exit-code propagation' -or
            [string]$releaseManifest.OfficeLicenseEnumeration -ne 'OSPP /dstatusall per SKU' -or
            [string]$releaseManifest.VersionHistoryPresentation -ne 'InToolModal' -or
            @($releaseManifest.UserPreferencePersistence).Count -ne 1 -or
            @($releaseManifest.EnvironmentWarnings).Count -ne 2 -or
            @($releaseManifest.ProgressUtilities).Count -ne 2) { throw 'Thiếu metadata cải tiến giao diện v4.6.' }
        if (@($releaseManifest.ThirdPartyLicenseRemediationAdapters).Count -ne 4 -or
            (@($releaseManifest.ThirdPartyLicenseRemediationAdapters) -join ' ') -notmatch 'WinRAR' -or
            (@($releaseManifest.ThirdPartyLicenseRemediationAdapters) -join ' ') -notmatch 'never automatically reset' -or
            [string]$releaseManifest.ThirdPartyAutomaticResetPolicy -notmatch 'No third-party license store is reset automatically' -or
            [string]$releaseManifest.ThirdPartyAutomaticResetPolicy -notmatch 'hash/size revalidation' -or
            [string]$releaseManifest.ThirdPartyAutomaticResetPolicy -notmatch 'manual-only' -or
            [string]$releaseManifest.ThirdPartyBackupPolicy -notmatch 'non-restorable') {
            throw 'Thiếu metadata khắc phục bản quyền phần mềm bên thứ ba v4.6.'
        }
        if (-not [bool]$releaseManifest.UniversalDeepSoftwareScan -or
            @($releaseManifest.DeepSoftwareScanEvidence).Count -lt 8 -or
            [string]$releaseManifest.DeepSoftwareScanScoring -notmatch 'direct known hash, active activator' -or
            [string]$releaseManifest.DeepSoftwareScanBudgetPolicy -notmatch 'weighted budgeting' -or
            [string]$releaseManifest.DeepSoftwareScanCatalogTrust -notmatch 'pinned-signer') {
            throw 'Thiếu metadata quét sâu phần mềm phổ quát v4.6.'
        }
        if ([string]$releaseManifest.SoftwareLicenseCatalogVersion -ne '1.4.0.1' -or
            [string]$releaseManifest.SoftwareLicenseCatalogGeneratedAtUtc -ne '2026-08-18T14:00:00Z' -or
            [int]$releaseManifest.SoftwareLicenseCatalogProductRules -lt 77 -or
            [string]$releaseManifest.SoftwareLicenseCatalogSignatureFile -ne 'software-license-catalog-v1.0.json.p7s' -or
            -not [bool]$releaseManifest.SoftwareLicenseCatalogSignatureRequired -or
            [string]$releaseManifest.SoftwareLicenseCatalogSignerCertificateSha256 -ne '90857DC1698CDDEAF7C405F5991992E6615D28299A78C7D1445A1B504F8044C3' -or
            [int]$releaseManifest.EngineeringSoftwareCatalogRules -lt 16 -or
            @($releaseManifest.EngineeringSoftwareCategories).Count -lt 8) {
            throw 'Thiếu metadata mở rộng catalog phần mềm kỹ thuật v4.6.'
        }
        if ([string]$releaseManifest.NormalReportActivatorInspection -notmatch 'MAS/PMAS' -or
            [string]$releaseManifest.NormalReportActivatorInspection -notmatch 'Activation Program 1.17' -or
            [string]$releaseManifest.NormalReportActivatorInspection -notmatch 'erturk-dev\.netlify\.app/run' -or
            [string]$releaseManifest.NormalSoftwareInstalledArtifactInspection -notmatch 'install roots' -or
            [string]$releaseManifest.WindowsKmsLifecyclePresentation -notmatch 'Notification' -or
            [string]$releaseManifest.InstallDateNormalization -notmatch 'yyyy-MM-dd' -or
            @($releaseManifest.MonitorNameSources).Count -ne 3 -or
            @($releaseManifest.ReportPrivacyChoice).Count -ne 3 -or
            [string]$releaseManifest.TimelineCurrentStatePolicy -notmatch 'Latest observed state' -or
            [string]$releaseManifest.ThirdPartyPostCleanupQueuePolicy -notmatch 'requeues only current' -or
            [string]$releaseManifest.ThirdPartyStandaloneArtifactPolicy -notmatch 'manual-only quarantine') {
            throw 'Thiếu metadata hotfix quét thường/KMS/ngày cài/màn hình/riêng tư/timeline/quét lại phần mềm khác.'
        }
        if (-not [bool]$releaseManifest.RemediationDryRun -or
            [string]$releaseManifest.RemediationDryRunPolicy -notmatch 'no system changes' -or
            [string]$releaseManifest.RemediationDryRunPolicy -notmatch 'new item confirmation') {
            throw 'Thiếu metadata Dry Run fail-safe v4.6.'
        }
        if ([string]$releaseManifest.OfflinePolicySchemaVersion -ne '1.0' -or
            [string]$releaseManifest.OfflineDefault -ne 'Offline' -or
            @($releaseManifest.OfflineBlockedScopes).Count -ne 3 -or
            [string]$releaseManifest.RuntimeTelemetry -ne 'Disabled' -or
            -not [bool]$releaseManifest.AutomaticUpdateCheck -or
            [string]$releaseManifest.AutomaticUpdateCheckTrigger -ne 'UserEnabledOnline' -or
            [bool]$releaseManifest.BackgroundUpdateService -or [bool]$releaseManifest.SilentUpdate -or
            [string]$releaseManifest.ApplicationUpdateSchemaVersion -ne '1.0' -or
            -not [bool]$releaseManifest.OfflineResetOnEveryLaunch -or
            @($releaseManifest.ApplicationUpdateChoices).Count -ne 3) { throw 'Thiếu metadata Offline mặc định/cập nhật theo quyền Online.' }
        if ([string]$releaseManifest.EnterpriseNetworkDefault -ne 'Blocked' -or
            -not [bool]$releaseManifest.EnterpriseNetworkToggle -or
            -not [bool]$releaseManifest.EnterpriseNetworkIndependentFromGlobalOffline) {
            throw 'Thiếu metadata công tắc mạng riêng bật/tắt của Mục 8.'
        }
        if ([string]$releaseManifest.DataSchemaVersion -ne '2.0' -or
            [string]$releaseManifest.DataStorageGeneration -ne 'v4.6' -or
            [string]$releaseManifest.LegacyDataStorageGeneration -ne 'v4.4' -or
            [string]$releaseManifest.DataMigrationPolicy -ne 'Verified staging copy + transactional commit + rollback' -or
            [string]$releaseManifest.StartupExecutionLevel -ne 'asInvoker' -or
            [string]$releaseManifest.ElevationPolicy -notmatch '^On demand' -or
            [string]$releaseManifest.DefaultDataRoot -ne '%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6' -or
            [string]$releaseManifest.ElevatedDataRoot -ne '%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6' -or
            [string]$releaseManifest.PersistentLogRoot -notmatch '^%LOCALAPPDATA%.*standard UI.*%ProgramData%.*elevated modes' -or
            [string]$releaseManifest.PersistentEnterpriseRoot -notmatch '\\v4\.6\\enterprise$') {
            throw 'Thiếu metadata data lifecycle/migration hoặc least-privilege riêng của v4.8.'
        }
        if ([string]$releaseManifest.LocalizationSchemaVersion -ne '1.0' -or
            [string]$releaseManifest.DefaultCulture -ne 'vi-VN' -or
            @($releaseManifest.SupportedCultures).Count -ne 2) { throw 'Thiếu metadata đa ngôn ngữ vi-VN/en-US.' }
        if ([string]$releaseManifest.CompatibilitySchemaVersion -ne '1.0' -or
            [string]$releaseManifest.CompatibilityCatalogSchemaVersion -ne '1.1' -or
            [string]$releaseManifest.CompatibilityCatalogVersion -ne '1.1.1.0' -or
            [string]$releaseManifest.CompatibilityCatalogHealth -ne 'Fresh' -or
            [int]$releaseManifest.CompatibilityCatalogReviewWarningAgeDays -ne 30 -or
            [int]$releaseManifest.CompatibilityCatalogMaximumReviewAgeDays -ne 45 -or
            [string]$releaseManifest.FutureCompatibilityMode -ne 'ReadOnlyManualReview' -or
            -not [bool]$releaseManifest.CompatibilityCatalogFresh -or
            @($releaseManifest.SupportedWindowsReleases).Count -lt 5 -or
            @($releaseManifest.SupportedOfficeFamilies).Count -lt 3) { throw 'Thiếu metadata vòng đời catalog Windows/Office và chế độ tương thích tương lai.' }
        if (-not [bool]$releaseManifest.EnterpriseLicenseCenter -or [string]$releaseManifest.EnterpriseProtocolVersion -ne '1.0' -or
            @($releaseManifest.EnterpriseRoles).Count -ne 2) { throw 'Thiếu metadata enterprise server/client.' }
        if ([string]$releaseManifest.ReportSchemaVersion -ne '1.5' -or [int]$releaseManifest.ReportKinds -ne 9 -or
            @($releaseManifest.ReportFormats).Count -ne 4 -or [string]$releaseManifest.PluginSchemaVersion -ne '1.0' -or
            [string]$releaseManifest.TimelineSchemaVersion -ne '1.0' -or [string]$releaseManifest.SafetyPolicySchemaVersion -ne '1.0' -or
            [bool]$releaseManifest.ScanRepairChangesStartupType -or
            [string]$releaseManifest.ReportExportSchemaVersion -ne '1.4' -or
            [string]$releaseManifest.ReportHtmlPresentation -ne 'Summary' -or
            [string]$releaseManifest.ReportPdfPresentation -ne 'Detailed' -or
            [string]$releaseManifest.ReportContentSplit -notmatch '^HTML summary' -or
            [string]$releaseManifest.DefaultReportOpenFormat -ne 'HTML' -or
            [string]$releaseManifest.ReportOutputRoot -ne '%USERPROFILE%\Desktop\BaoCao-Tool-Kiem-Tra' -or
            [string]$releaseManifest.ReportPackageLayout -notmatch '^One shared Desktop report folder' -or
            [string]$releaseManifest.ReportAutoOpenPolicy -ne 'Open HTML only after a completed export' -or
            [string]$releaseManifest.LicenseConclusionPolicy -notmatch '^Activation is separated from entitlement' -or
            [string]$releaseManifest.LicenseUndeterminedPolicy -notmatch '^Unreadable licensing data is reported as Undetermined' -or
            [string]$releaseManifest.OfficialActivationPostCheck -notmatch 'Windows LicenseStatus=1.*Office OSPP LICENSED' -or
            [string]$releaseManifest.GenuineLicensePreservation -notmatch '^Verified OEM/.*readiness for activation is separate from licensed=True' -or
            [string]$releaseManifest.DocumentationCache -ne 'Stable version/culture filename + source SHA-256' -or
            [string]$releaseManifest.DocumentationRendererRevision -ne '2' -or
            [string]$releaseManifest.DefaultDocumentationOpenFormat -ne 'HTMLBeforePdf' -or
            -not [bool]$releaseManifest.VersionHistoryCenter -or
            [string]$releaseManifest.GuideStyle -notmatch '^Function-oriented' -or
            -not [bool]$releaseManifest.DesktopHtmlPdfExport -or
            -not [bool]$releaseManifest.UnifiedProfessionalReportUi -or
            -not [bool]$releaseManifest.PdfSafePageBreaks -or
            [string]$releaseManifest.PdfHeaderFooter -ne 'Disabled' -or
            -not [bool]$releaseManifest.CapabilityFunctionMapping) { throw 'Thiếu metadata report/plugin/timeline/safety schema v4.3.' }
        $assistantManifest = $releaseManifest.ToolAssistant
        if ([string]$assistantManifest.SchemaVersion -ne '1.1' -or
            [string]$assistantManifest.Scope -ne 'Tool-Kiem-Tra' -or
            [string]$assistantManifest.Engine -ne 'LocalKnowledge' -or
            [bool]$assistantManifest.PaidApiRequired -or
            [bool]$assistantManifest.CodexRequired -or
            [string]$assistantManifest.OnlineTransfer -ne 'DownloadOnlySignedKnowledgePackage' -or
            [bool]$assistantManifest.ReportUpload -or
            [bool]$assistantManifest.QuestionUpload -or
            [bool]$assistantManifest.AutomaticRemediation -or
            -not [bool]$assistantManifest.PortableEveryMachine -or
            [bool]$assistantManifest.CentralServerRequired -or
            [string]$assistantManifest.KnowledgeStorage -ne 'BundledAndSignedPerUserLocalCache' -or
            [string]$assistantManifest.ReportContextSource -ne 'CurrentDeviceLocalReportOnly' -or
            -not [bool]$assistantManifest.KnowledgeCompatibilityEnforced -or
            [string]$assistantManifest.KnowledgeUpdateVerification -ne 'DetachedCmsSha256PinnedCertificate' -or
            -not [bool]$assistantManifest.KnowledgeRollbackProtection -or
            [bool]$assistantManifest.UnboundedSelfTraining -or
            [bool]$assistantManifest.ExternalTopicLearning -or
            [string]$assistantManifest.KnowledgeFileName -ne 'tool-assistant-knowledge-v1.1.json' -or
            [string]$assistantManifest.KnowledgeSignatureFileName -ne 'tool-assistant-knowledge-v1.1.json.p7s' -or
            -not [bool]$assistantManifest.ImmediateResponseRender) {
            throw 'Thiếu metadata ranh giới an toàn của Trợ lý Tool v4.8.'
        }
        if ([string]$releaseManifest.PdfProfileRoot -ne '%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf' -or
            [string]$releaseManifest.PdfProfileAcl -ne 'Current user + SYSTEM' -or
            [string]$releaseManifest.PdfProfileCleanup -notmatch 'Bounded retry') {
            throw 'Thiếu metadata profile PDF v4.3.'
        }
        if ([string]$releaseManifest.ModuleContractSchemaVersion -ne '1.0' -or [string]$releaseManifest.ModuleResultSchemaVersion -ne '1.0' -or [int]$releaseManifest.ModuleCount -ne 27 -or [int]$releaseManifest.ModuleEntryPointCount -ne 24) { throw 'Thiếu metadata module contract v4.8.' }
    } catch { $failures.Add("RELEASE-MANIFEST.json không hợp lệ: $($_.Exception.Message)") }
}

$sourceApplicationUpdateManifestPath = Join-Path $sourceDirectoryFull 'update-manifest-v1.json'
$applicationUpdateManifestPath = Join-Path $distributionDirectoryFull 'update-manifest-v1.json'
if (-not (Test-Path -LiteralPath $sourceApplicationUpdateManifestPath -PathType Leaf)) {
    $failures.Add('Thiếu update-manifest-v1.json trong gói mã nguồn.')
} elseif (-not $AllowDevelopmentManifest -and (Test-Path -LiteralPath $applicationUpdateManifestPath -PathType Leaf) -and
    (Get-Sha256Hex $sourceApplicationUpdateManifestPath) -ne (Get-Sha256Hex $applicationUpdateManifestPath)) {
    $failures.Add('update-manifest-v1.json trong Source và Release không giống hệt từng byte.')
} elseif ($AllowDevelopmentManifest) {
    try {
        $sourceApplicationUpdateManifest = Get-Content -LiteralPath $sourceApplicationUpdateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$sourceApplicationUpdateManifest.Channel -ne 'stable' -or -not [bool]$sourceApplicationUpdateManifest.AuthenticodeRequired) {
            throw 'Build development đã thay thế manifest stable trong mã nguồn.'
        }
    } catch { $failures.Add("update-manifest-v1.json trong Source không hợp lệ: $($_.Exception.Message)") }
}
if (-not (Test-Path -LiteralPath $applicationUpdateManifestPath -PathType Leaf)) {
    $failures.Add('Thiếu update-manifest-v1.json.')
} elseif (Test-Path -LiteralPath $exePath -PathType Leaf) {
    try {
        $applicationUpdateManifest = Get-Content -LiteralPath $applicationUpdateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedUpdateChannel = if ($AllowDevelopmentManifest) { 'development' } else { 'stable' }
        if ([string]$applicationUpdateManifest.SchemaVersion -ne '1.0' -or [string]$applicationUpdateManifest.Channel -ne $expectedUpdateChannel -or
            [string]$applicationUpdateManifest.LatestVersion -ne '4.8.0.1' -or [string]$applicationUpdateManifest.MinimumUpdaterVersion -ne '4.6.1.0' -or
            [string]$applicationUpdateManifest.PublishedAtUtc -ne '2026-08-18T00:00:00Z') {
            throw 'Sai schema/channel/version cập nhật.'
        }
        if ([string]$applicationUpdateManifest.ReleasePageUrl -ne 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.8.0.1' -or
            [string]$applicationUpdateManifest.DownloadUrl -ne 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.8.0.1/Tool-Kiem-Tra-v4.8.exe') {
            throw 'URL phát hành/cập nhật không đúng allowlist ổn định.'
        }
        if ([string]$applicationUpdateManifest.DownloadSha256 -ne (Get-Sha256Hex $exePath) -or
            [int64]$applicationUpdateManifest.DownloadSize -ne [int64](Get-Item -LiteralPath $exePath).Length) {
            throw 'Hash hoặc kích thước EXE trong manifest cập nhật không khớp.'
        }
        if ($null -eq $applicationUpdateManifest.Title.'vi-VN' -or $null -eq $applicationUpdateManifest.Title.'en-US' -or
            @($applicationUpdateManifest.Changes.'vi-VN').Count -lt 3 -or @($applicationUpdateManifest.Changes.'en-US').Count -lt 3) {
            throw 'Manifest cập nhật thiếu nội dung vi-VN/en-US.'
        }
        $manifestRequiresAuthenticode = [bool]$applicationUpdateManifest.AuthenticodeRequired
        $manifestSignerThumbprints = @($applicationUpdateManifest.SignerThumbprints | ForEach-Object { ([string]$_).Replace(' ', '').ToUpperInvariant() })
        if ($expectedUpdateChannel -eq 'stable' -and -not $manifestRequiresAuthenticode) {
            throw 'Manifest stable chưa bắt buộc Authenticode.'
        }
        if ($expectedUpdateChannel -eq 'development' -and $manifestRequiresAuthenticode) {
            throw 'Manifest development không được giả làm stable signed release.'
        }
        if ($manifestRequiresAuthenticode) {
            if ($manifestSignerThumbprints.Count -eq 0 -or @($manifestSignerThumbprints | Where-Object { $_ -notmatch '^[0-9A-F]{40,64}$' }).Count -gt 0) {
                throw 'Manifest yêu cầu Authenticode nhưng thiếu hoặc sai signer thumbprint.'
            }
            $releaseSignature = Get-AuthenticodeSignature -LiteralPath $exePath
            $releaseSignerThumbprint = if ($releaseSignature.SignerCertificate) { ([string]$releaseSignature.SignerCertificate.Thumbprint).Replace(' ', '').ToUpperInvariant() } else { '' }
            if ($releaseSignature.Status -ne 'Valid' -or $manifestSignerThumbprints -notcontains $releaseSignerThumbprint) {
                throw 'EXE phát hành không có chữ ký hợp lệ của signer đã ghim trong manifest.'
            }
        }
    } catch { $failures.Add("update-manifest-v1.json không hợp lệ: $($_.Exception.Message)") }
}

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
if ($analyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $analysis = @(Invoke-ScriptAnalyzer -Path $sourceDirectoryFull -Recurse -Severity Error)
    foreach ($finding in $analysis) { $failures.Add("PSScriptAnalyzer $($finding.ScriptName):$($finding.Line) $($finding.RuleName) - $($finding.Message)") }
} else {
    $warnings.Add('PSScriptAnalyzer chưa được cài; đã chạy parser PowerShell tích hợp thay thế.')
}

if ($profile) {
    Write-Host ("PE AnyCPU: {0}/{1}; ILOnly={2}; Required32={3}; Preferred32={4}; HEVA={5}; ASLR={6}; NX={7}; NO_SEH={8}; CFG={9}; LoadConfig={10}" -f `
        $profile.PeFormat, $profile.Machine, $profile.ClrIlOnly, $profile.Clr32BitRequired, $profile.Clr32BitPreferred,
        $profile.HighEntropyVa, $profile.DynamicBase, $profile.NxCompat, $profile.NoSeh,
        $profile.ControlFlowGuardHeader, $profile.LoadConfigurationDirectoryPresent)
}

if (Test-Path -LiteralPath $reportSchemaVerifierPath -PathType Leaf) {
    & $reportSchemaVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra schema báo cáo v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $safetyVerifierPath -PathType Leaf) {
    & $safetyVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra hồi quy an toàn v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $dashboardVerifierPath -PathType Leaf) {
    & $dashboardVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra dashboard v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $extensionsVerifierPath -PathType Leaf) {
    & $extensionsVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra report/plugin/timeline v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $compatibilityVerifierPath -PathType Leaf) {
    & $compatibilityVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra catalog Windows/Office v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $offlineI18nVerifierPath -PathType Leaf) {
    & $offlineI18nVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra Offline/i18n/report v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $localizationVerifierPath -PathType Leaf) {
    & $localizationVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra độ phủ localization vi-VN/en-US thất bại.') }
}
if (Test-Path -LiteralPath $enterpriseVerifierPath -PathType Leaf) {
    & $enterpriseVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra enterprise server/client v4.3 thất bại.') }
}
if (Test-Path -LiteralPath $performanceVerifierPath -PathType Leaf) {
    & $performanceVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra tối ưu quét v4.6 thất bại.') }
}
if (Test-Path -LiteralPath $dataLifecycleVerifierPath -PathType Leaf) {
    & $dataLifecycleVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra data lifecycle/migration v4.6 thất bại.') }
}
if (Test-Path -LiteralPath $applicationUpdateVerifierPath -PathType Leaf) {
    & $applicationUpdateVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra cập nhật ứng dụng theo quyền Online thất bại.') }
}
if (Test-Path -LiteralPath $assistantVerifierPath -PathType Leaf) {
    & $assistantVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra Trợ lý Tool cục bộ v4.8 thất bại.') }
}
foreach ($warning in $warnings) { Write-Warning $warning }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-RELEASE: KHÔNG ĐẠT ($($failures.Count) lỗi, $($warnings.Count) cảnh báo)"
    exit 1
}

Write-Host "VERIFY-RELEASE: ĐẠT (0 lỗi, $($warnings.Count) cảnh báo)" -ForegroundColor Green
exit 0
