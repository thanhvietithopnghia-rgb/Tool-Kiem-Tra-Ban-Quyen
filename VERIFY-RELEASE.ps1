[CmdletBinding()]
param(
    [string]$SourceDirectory = '',
    [string]$DistributionDirectory = ''
)

$ErrorActionPreference = 'Stop'
$productVersion = '4.3'
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

function Test-HashManifest([string]$ManifestPath, [string]$RootPath, [int]$ExpectedCount) {
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
        if ([IO.Path]::GetFileName($name) -ne $name -or -not $seen.Add($name)) {
            $failures.Add("Tên tệp không an toàn hoặc bị lặp trong manifest: $name")
            continue
        }
        $path = Join-Path $RootPath $name
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

foreach ($script in Get-ChildItem -LiteralPath $sourceDirectoryFull -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { $failures.Add("Lỗi cú pháp $($script.Name): $($parseError.Message)") }
}

Test-HashManifest (Join-Path $sourceDirectoryFull 'TOOL-SHA256SUMS.txt') $sourceDirectoryFull 37
Test-HashManifest (Join-Path $sourceDirectoryFull 'SOURCE-SHA256SUMS.txt') $sourceDirectoryFull 70
Test-HashManifest (Join-Path $distributionDirectoryFull 'RELEASE-SHA256SUMS.txt') $distributionDirectoryFull 18

$manifestPath = Join-Path $sourceDirectoryFull 'Tool-Kiem-Tra-v4.3-OneFile.manifest'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $failures.Add('Thiếu application manifest v4.3.')
} else {
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    if ($manifestText -notmatch 'requestedExecutionLevel\s+level="requireAdministrator"') { $failures.Add('Application manifest chưa yêu cầu requireAdministrator.') }
    if ($manifestText -notmatch 'version="4\.3\.0\.8"') { $failures.Add('Application manifest sai phiên bản 4.3.0.8.') }
}

$versionChecks = @(
    @{ File='Giao-Dien.ps1'; Pattern='\$toolVersion\s*=\s*"4\.3"' },
    @{ File='Giao-Dien.ps1'; Pattern='\$releaseVersion\s*=\s*"4\.3\.0\.8"' },
    @{ File='Giao-Dien.ps1'; Pattern='\$releaseBuildDate\s*=\s*"2026\.07\.31"' },
    @{ File='kiem-tra-cau-hinh-ban-quyen.ps1'; Pattern='\$ToolVersion\s*=\s*"4\.3"' },
    @{ File='windows-license-forensics.ps1'; Pattern='\$toolVersion\s*=\s*"4\.3"' },
    @{ File='Tool-Kiem-Tra-v4.3-OneFile.cs'; Pattern='AssemblyVersion\("4\.3\.0\.8"\)' },
    @{ File='Tool-Kiem-Tra-v4.3-OneFile.cs'; Pattern='AssemblyFileVersion\("4\.3\.0\.8"\)' },
    @{ File='Tool-Kiem-Tra-v4.3-OneFile.cs'; Pattern='AssemblyInformationalVersion\("4\.3\.0\.8"\)' }
)
foreach ($check in $versionChecks) {
    $path = Join-Path $sourceDirectoryFull $check.File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -notmatch $check.Pattern) {
        $failures.Add("Sai hoặc thiếu nhãn phiên bản trong $($check.File)")
    }
}

$guiText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Giao-Dien.ps1') -Raw -Encoding UTF8
$cleanupText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-compliance-cleanup.ps1') -Raw -Encoding UTF8
$backupText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-backup.ps1') -Raw -Encoding UTF8
$restoreText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'windows-license-restore.ps1') -Raw -Encoding UTF8
$reportText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
$launcherText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Kiem-Tra-v4.3-OneFile.cs') -Raw -Encoding UTF8
$buildText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'BUILD.ps1') -Raw -Encoding UTF8
$runtimeText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Runtime.ps1') -Raw -Encoding UTF8
$capabilityText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Capabilities.ps1') -Raw -Encoding UTF8
$loggingText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-Logging.ps1') -Raw -Encoding UTF8
$moduleContractText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ModuleContract.ps1') -Raw -Encoding UTF8
$reportSchemaText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-ReportSchema.ps1') -Raw -Encoding UTF8
$safetyPolicyText = Get-Content -LiteralPath (Join-Path $sourceDirectoryFull 'Tool-SafetyPolicy.ps1') -Raw -Encoding UTF8
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

if ($guiText -notmatch '\$dashboardSchemaVersion\s*=\s*"2\.0"' -or
    $guiText -notmatch 'WindowsReleaseName' -or $guiText -notmatch 'OfficeSummary') {
    $failures.Add('Dashboard chưa hiển thị schema 2.0 và trạng thái Windows/Office v4.3.')
}
if ($guiText -notmatch 'function\s+Show-ProductIntroduction' -or
    $guiText -notmatch 'introDetailButton' -or
    $guiText -notmatch 'app\.hero\.title' -or
    $guiText -notmatch 'function\s+Set-ModernRoundedRegion' -or
    $guiText -notmatch '\$ultraCompactHeight') {
    $failures.Add('Dashboard v4.3 thiếu banner/nút giới thiệu, bo góc hoặc chế độ gọn.')
}
if ($guiText -notmatch 'TOOL_SECURE_LAUNCH' -or $guiText -notmatch 'Test-ProtectedToolDirectoryAcl') { $failures.Add('Giao diện thiếu khóa secure-launch/ACL.') }
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
    $launcherText -notmatch 'TOOL_ENTERPRISE_SCHEMA' -or
    $launcherText -notmatch '--enterprise-server' -or
    $launcherText -notmatch '--enterprise-agent' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(logsDirectory\)' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(pluginsDirectory\)' -or
    $launcherText -notmatch 'CreateProtectedDirectory\(timelineDirectory\)') {
    $failures.Add('Launcher AnyCPU thiếu tự nhận diện, chặn x86-on-x64, PowerShell native hoặc module schema.')
}
if ($launcherText -match 'powershellPath\s*=\s*"powershell\.exe"') { $failures.Add('Launcher còn fallback sang powershell.exe từ PATH.') }
if ($runtimeText -notmatch 'Is64BitOperatingSystem\s*-and\s*-not\s*\[Environment\]::Is64BitProcess' -or
    $runtimeText -notmatch 'Get-ToolNativeSystemPath' -or $runtimeText -notmatch 'Sysnative') {
    $failures.Add('Tool-Runtime.ps1 thiếu chặn WOW64 hoặc đường dẫn System32 native.')
}
if ($capabilityText -notmatch 'ToolVersion\s*=\s*"4\.3"' -or
    $capabilityText -notmatch 'SchemaVersion\s*=\s*"1\.1"' -or
    $capabilityText -notmatch 'Get-ToolWindowsReleaseProfile' -or
    $capabilityText -notmatch 'Get-ToolOfficeCompatibilityProfile' -or
    $capabilityText -notmatch 'CompatibilityTier' -or $capabilityText -notmatch 'CimCmdlets' -or
    $capabilityText -notmatch 'WmiFallback' -or $capabilityText -notmatch 'ScheduledTasksFallback') {
    $failures.Add('Tool-Capabilities.ps1 thiếu schema 1.1, catalog Windows/Office hoặc capability/fallback bắt buộc.')
}
if ($loggingText -notmatch 'TOOL_LOG_PATH' -or $loggingText -notmatch 'TOOL_CORRELATION_ID' -or
    $loggingText -notmatch 'TOOL_MODULE_ID' -or $loggingText -notmatch 'TOOL_MODULE_INVOCATION_ID' -or
    $loggingText -notmatch 'v4\.3\\logs' -or $loggingText -notmatch 'ReparsePoint' -or
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
    $moduleContractText -notmatch 'inventory\.registry' -or $moduleContractText -notmatch 'inventory\.service' -or $moduleContractText -notmatch 'inventory\.task') {
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
    $offlinePolicyText -notmatch 'Telemetry\s*=\s*"Disabled"') {
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
if ($cleanupText -notmatch 'ToolVersion\s*=\s*"4\.3"' -or $cleanupText -notmatch 'LicenseNotice') { $failures.Add('Cleanup manifest v4.3 chưa đầy đủ.') }
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
if ($cleanupText -notmatch 'HandlingGuidance' -or $guiText -notmatch 'Hướng xử lý đề xuất') { $failures.Add('Kết luận cleanup chưa kèm hướng xử lý đề xuất.') }
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
if ($reportExportText -notmatch 'ToolReportExportSchemaVersion\s*=\s*"1\.2"' -or
    $reportExportText -notmatch 'Test-ToolHtmlOfflineSafe' -or
    $reportExportText -notmatch "default-src 'none'" -or
    $reportExportText -notmatch 'no-pdf-header-footer' -or
    $reportExportText -notmatch 'print-to-pdf-no-header' -or
    $reportExportText -notmatch '@media\s+print' -or
    $reportExportText -notmatch 'section\{break-inside:auto!important' -or
    $reportExportText -notmatch '@page') {
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
if ($cleanupText -notmatch 'ScanWarningCount' -or $cleanupText -notmatch 'ĐÃ KHÓA XỬ LÝ: nguồn quét quan trọng' -or
    $guiText -notmatch 'Show-ScanWarningRecoveryDialog' -or $guiText -notmatch 'Sửa nhanh nguồn quét') {
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
    if ($script.Name -in @('VERIFY-RELEASE.ps1', 'BUILD.ps1')) { continue }
    $text = Get-Content -LiteralPath $script.FullName -Raw -Encoding UTF8
    if ($text -match '(?i)\bInvoke-Expression\b|\bEncodedCommand\b|\bInvoke-WebRequest\b|\bInvoke-RestMethod\b|\bStart-BitsTransfer\b') {
        $failures.Add("Phát hiện primitive tải/thực thi không được phép trong $($script.Name)")
    }
}

$payloadFiles = @(
    '00-Tool-Kiem-Tra.ico','approved-kms-servers.txt','HUONG-DAN.txt','USER-GUIDE-en-US.md','LICH-SU-PHIEN-BAN.txt',
    'Giao-Dien.ps1','kiem-tra-cau-hinh-ban-quyen.ps1','Tool-Kiem-Tra-icon.svg','Tool-Kiem-Tra.cmd',
    'Tool-Runtime.ps1','Tool-Compatibility.ps1','compatibility-catalog-v1.0.json','Tool-Capabilities.ps1',
    'Tool-Logging.ps1','Tool-ModuleContract.ps1','Tool-UiTheme.ps1','Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json','Tool-Strings.en-US.json','Tool-OfflinePolicy.ps1',
    'Tool-ReportSchema.ps1','Tool-ReportExport.ps1','Tool-PluginEngine.ps1','Tool-LicenseTimeline.ps1',
    'Tool-SafetyPolicy.ps1','Tool-Enterprise.ps1','Tool-EnterpriseHost.ps1','Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1','TOOL-SHA256SUMS.txt','windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1','windows-license-restore.ps1','windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1','windows-oem-license-assistant.ps1','windows-office-license-manager.ps1',
    'windows-license-assurance.ps1','builtin-windows-office-trust.plugin.json'
)
$payloadListArgument = $payloadFiles -join '|'
$targetFileName = 'Tool-Kiem-Tra-v4.3.exe'
$exePath = Join-Path $distributionDirectoryFull $targetFileName
$profile = $null
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    $failures.Add("Thiếu EXE phát hành: $targetFileName")
} else {
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
    if ($signature.Status -ne 'Valid') { $warnings.Add("$targetFileName chưa có chữ ký Authenticode hợp lệ: $($signature.Status)") }
}

if ($profile -and -not $profile.ControlFlowGuardHeader) {
    $warnings.Add('CFG/load configuration native chưa được tuyên bố cho launcher managed IL; SECURITY-HARDENING-v4.3.md ghi rõ giới hạn này.')
}

$releaseManifestPath = Join-Path $distributionDirectoryFull 'RELEASE-MANIFEST.json'
if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
    $failures.Add('Thiếu RELEASE-MANIFEST.json.')
} else {
    try {
        $releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$releaseManifest.SchemaVersion -ne '2.0' -or [string]$releaseManifest.ToolVersion -ne '4.3') { throw 'Sai schema/tool version.' }
        if (@($releaseManifest.Artifacts).Count -ne 1) { throw 'Release manifest phải có đúng một artefact AnyCPU.' }
        if ([string]$releaseManifest.PrimaryFileName -ne $targetFileName) { throw 'Sai PrimaryFileName.' }
        $entry = @($releaseManifest.Artifacts)[0]
        if ([string]$entry.FileName -ne $targetFileName -or [string]$entry.Architecture -ne 'AnyCPU') { throw 'Entry EXE không phải AnyCPU duy nhất.' }
        if ([string]$entry.Pe.ManagedPlatform -ne 'AnyCPU' -or [bool]$entry.Pe.Required32Bit -or [bool]$entry.Pe.Preferred32Bit) { throw 'Metadata CLR flags AnyCPU không hợp lệ.' }
        if ([string]$entry.Sha256 -ne (Get-Sha256Hex $exePath)) { throw "Sai SHA-256 metadata: $targetFileName." }
        if ([string]$releaseManifest.ControlFlowGuard.Status -ne 'NotClaimed') { throw 'Trạng thái CFG không minh bạch.' }
        if (-not [bool]$releaseManifest.DeterministicManagedBuild) { throw 'Release manifest chưa xác nhận deterministic managed build.' }
        if ([string]$releaseManifest.CapabilitySchemaVersion -ne '1.1' -or [string]$releaseManifest.LogSchemaVersion -ne '1.0-jsonl') { throw 'Thiếu metadata capability/log schema v4.3.' }
        if ([string]$releaseManifest.ReleaseVersion -ne '4.3.0.8' -or [string]$releaseManifest.ReleaseBuildDate -ne '2026.07.31') {
            throw 'Release manifest chưa đồng bộ phiên bản 4.3.0.8 / Build 2026.07.31.'
        }
        if ([string]$releaseManifest.ReleaseLabel -ne '4.3.0.8-fit-stop-network-history-20260731') { throw 'Sai release label v4.3.0.8.' }
        if ([int]$releaseManifest.PayloadCount -ne 39 -or [int]$releaseManifest.IntegrityFileCount -ne 37) { throw 'Sai số lượng payload/integrity.' }
        if ([string]$releaseManifest.DashboardSchemaVersion -ne '2.0' -or [string]$releaseManifest.DashboardMode -ne 'Modern adaptive WinForms dashboard' -or [string]$releaseManifest.DarkMode -ne 'Persistent full-tool / WCAG-aware palette' -or
            -not [bool]$releaseManifest.CleanupActionCenter -or -not [bool]$releaseManifest.AssuranceCenter -or
            [string]$releaseManifest.OfficeLicenseEnumeration -ne 'OSPP /dstatusall per SKU') { throw 'Thiếu metadata dashboard/assurance/Office multi-SKU v4.3.' }
        if ([string]$releaseManifest.OfflinePolicySchemaVersion -ne '1.0' -or
            [string]$releaseManifest.OfflineDefault -ne 'Offline' -or
            @($releaseManifest.OfflineBlockedScopes).Count -ne 3 -or
            [string]$releaseManifest.RuntimeTelemetry -ne 'Disabled' -or
            [bool]$releaseManifest.AutomaticUpdateCheck) { throw 'Thiếu metadata Offline mặc định/fail-closed.' }
        if ([string]$releaseManifest.EnterpriseNetworkDefault -ne 'Blocked' -or
            -not [bool]$releaseManifest.EnterpriseNetworkToggle -or
            -not [bool]$releaseManifest.EnterpriseNetworkIndependentFromGlobalOffline) {
            throw 'Thiếu metadata công tắc mạng riêng bật/tắt của Mục 8.'
        }
        if ([string]$releaseManifest.LocalizationSchemaVersion -ne '1.0' -or
            [string]$releaseManifest.DefaultCulture -ne 'vi-VN' -or
            @($releaseManifest.SupportedCultures).Count -ne 2) { throw 'Thiếu metadata đa ngôn ngữ vi-VN/en-US.' }
        if ([string]$releaseManifest.CompatibilitySchemaVersion -ne '1.0' -or
            -not [bool]$releaseManifest.CompatibilityCatalogFresh -or
            @($releaseManifest.SupportedWindowsReleases).Count -lt 3 -or
            @($releaseManifest.SupportedOfficeFamilies).Count -lt 2) { throw 'Thiếu metadata catalog Windows/Office hiện hành.' }
        if (-not [bool]$releaseManifest.EnterpriseLicenseCenter -or [string]$releaseManifest.EnterpriseProtocolVersion -ne '1.0' -or
            @($releaseManifest.EnterpriseRoles).Count -ne 2) { throw 'Thiếu metadata enterprise server/client.' }
        if ([string]$releaseManifest.ReportSchemaVersion -ne '1.5' -or [int]$releaseManifest.ReportKinds -ne 9 -or
            @($releaseManifest.ReportFormats).Count -ne 4 -or [string]$releaseManifest.PluginSchemaVersion -ne '1.0' -or
            [string]$releaseManifest.TimelineSchemaVersion -ne '1.0' -or [string]$releaseManifest.SafetyPolicySchemaVersion -ne '1.0' -or
            [bool]$releaseManifest.ScanRepairChangesStartupType -or
            [string]$releaseManifest.ReportExportSchemaVersion -ne '1.2' -or
            [string]$releaseManifest.DefaultReportOpenFormat -ne 'HTML' -or
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
        if ([string]$releaseManifest.PdfProfileRoot -ne '%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf' -or
            [string]$releaseManifest.PdfProfileAcl -ne 'Current user + SYSTEM' -or
            [string]$releaseManifest.PdfProfileCleanup -notmatch 'Bounded retry') {
            throw 'Thiếu metadata profile PDF v4.3.'
        }
        if ([string]$releaseManifest.ModuleContractSchemaVersion -ne '1.0' -or [string]$releaseManifest.ModuleResultSchemaVersion -ne '1.0' -or [int]$releaseManifest.ModuleCount -ne 25 -or [int]$releaseManifest.ModuleEntryPointCount -ne 22) { throw 'Thiếu metadata module contract v4.3.' }
    } catch { $failures.Add("RELEASE-MANIFEST.json không hợp lệ: $($_.Exception.Message)") }
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
if (Test-Path -LiteralPath $enterpriseVerifierPath -PathType Leaf) {
    & $enterpriseVerifierPath -SourceDirectory $sourceDirectoryFull
    if ($LASTEXITCODE -ne 0) { $failures.Add('Kiểm tra enterprise server/client v4.3 thất bại.') }
}
foreach ($warning in $warnings) { Write-Warning $warning }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-RELEASE: KHÔNG ĐẠT ($($failures.Count) lỗi, $($warnings.Count) cảnh báo)"
    exit 1
}

Write-Host "VERIFY-RELEASE: ĐẠT (0 lỗi, $($warnings.Count) cảnh báo)" -ForegroundColor Green
exit 0
