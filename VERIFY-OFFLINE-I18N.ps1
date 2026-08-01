[CmdletBinding()]
param([string]$SourceDirectory = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { [void]$failures.Add($Message) }

$offlinePath = Join-Path $root "Tool-OfflinePolicy.ps1"
$localizationPath = Join-Path $root "Tool-Localization.ps1"
$reportExportPath = Join-Path $root "Tool-ReportExport.ps1"
foreach ($name in @("Tool-OfflinePolicy.ps1", "Tool-Localization.ps1", "Tool-Strings.vi-VN.json", "Tool-Strings.en-US.json", "Tool-ReportExport.ps1", "Giao-Dien.ps1", "enterprise-license-manager.ps1", "windows-office-license-manager.ps1", "Tool-Kiem-Tra-v4.4-OneFile.cs")) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) { Fail "Thiếu $name." }
}

if ($failures.Count -eq 0) {
    $oldOfflineMode = [string]$env:TOOL_OFFLINE_MODE
    $oldOfflineSettings = [string]$env:TOOL_OFFLINE_SETTINGS_PATH
    $oldEnterpriseNetworkAllowed = [string]$env:TOOL_ENTERPRISE_NETWORK_ALLOWED
    $oldEnterpriseNetworkSettings = [string]$env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH
    $oldCulture = [string]$env:TOOL_UI_CULTURE
    $oldCultureSettings = [string]$env:TOOL_UI_CULTURE_SETTINGS_PATH
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("tool-v43-offline-i18n-" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        $env:TOOL_OFFLINE_SETTINGS_PATH = Join-Path $temporaryRoot "offline.json"
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $temporaryRoot "enterprise-network.json"
        $env:TOOL_UI_CULTURE_SETTINGS_PATH = Join-Path $temporaryRoot "culture.json"
        $env:TOOL_OFFLINE_MODE = ""
        $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = ""
        $env:TOOL_UI_CULTURE = ""
        . $offlinePath
        . $localizationPath

        if (-not (Get-ToolOfflineMode)) { Fail "Offline không phải mặc định." }
        if (Test-ToolNetworkActionAllowed -Scope Internet) { Fail "Offline vẫn cho phép Internet." }
        if (Test-ToolNetworkActionAllowed -Scope Lan) { Fail "Offline vẫn cho phép LAN." }
        if (-not (Set-ToolOfflineModePreference -OfflineMode $false) -or (Get-ToolOfflineMode)) { Fail "Không lưu được lựa chọn cho phép mạng." }
        if (-not (Set-ToolOfflineModePreference -OfflineMode $true) -or -not (Get-ToolOfflineMode)) { Fail "Không bật lại được Offline." }
        if (Get-ToolEnterpriseNetworkAllowed) { Fail "Mạng Mục 8 không bị chặn theo mặc định." }
        if (-not (Set-ToolEnterpriseNetworkAllowedPreference -Allowed $true) -or -not (Test-ToolEnterpriseNetworkActionAllowed)) {
            Fail "Không bật được mạng riêng cho Mục 8."
        }
        if ((Get-ToolOfflineMode) -ne $true) { Fail "Bật mạng Mục 8 đã làm thay đổi Offline toàn cục." }
        if (-not (Set-ToolEnterpriseNetworkAllowedPreference -Allowed $false) -or (Test-ToolEnterpriseNetworkActionAllowed)) {
            Fail "Không tắt lại được mạng riêng cho Mục 8."
        }

        if ((Get-ToolCulture) -ne "vi-VN") { Fail "Ngôn ngữ mặc định không phải vi-VN." }
        if ((Get-ToolText -Key "app.title" -Culture "en-US") -ne "Configuration & License Assurance Tool") { Fail "Catalog en-US không hoạt động." }
        if (-not (Set-ToolCulturePreference -Culture "en-US") -or (Get-ToolCulture) -ne "en-US") { Fail "Không lưu được en-US." }
        $missing = Get-ToolText -Key "key.does.not.exist" -Culture "en-US"
        if ($missing -ne "[key.does.not.exist]") { Fail "Fallback key ngôn ngữ không xác định sai." }

        $reportText = Get-Content -LiteralPath $reportExportPath -Raw -Encoding UTF8
        foreach ($required in @("disable-background-networking", "host-resolver-rules", "Test-ToolHtmlOfflineSafe", "default-src 'none'")) {
            if ($reportText -notmatch [regex]::Escape($required)) { Fail "PDF/HTML offline thiếu biện pháp: $required" }
        }
        $catalogKeys = @{}
        foreach ($catalogName in @("Tool-Strings.vi-VN.json", "Tool-Strings.en-US.json")) {
            $catalog = Get-Content -LiteralPath (Join-Path $root $catalogName) -Raw -Encoding UTF8 | ConvertFrom-Json
            $catalogKeys[$catalogName] = @($catalog.PSObject.Properties.Name | Sort-Object)
            foreach ($key in @("app.title", "app.offline.enabled", "menu.1.title", "menu.10.title", "report.toc", "enterprise.network.allow", "enterprise.network.disable", "enterprise.client.tab", "localLicense.title")) {
                if (-not $catalog.PSObject.Properties[$key]) { Fail "$catalogName thiếu key $key." }
            }
        }
        $catalogDifference = @(Compare-Object $catalogKeys["Tool-Strings.vi-VN.json"] $catalogKeys["Tool-Strings.en-US.json"])
        if ($catalogDifference.Count -gt 0) { Fail "Catalog vi-VN/en-US không đồng bộ key." }

        $dashboardText = Get-Content -LiteralPath (Join-Path $root "Giao-Dien.ps1") -Raw -Encoding UTF8
        if ($dashboardText -notmatch 'ArgumentList\s+"--enterprise-ui"' -or
            $dashboardText -match '\$licenseLaunchMode\s*=\s*if\s*\(\$script:offlineMode\)' -or
            $dashboardText -match 'máy chủ/máy trạm bị ẩn') {
            Fail "Offline đang làm Mục 8 mất hoặc ẩn chức năng."
        }
        $enterpriseUiText = Get-Content -LiteralPath (Join-Path $root "enterprise-license-manager.ps1") -Raw -Encoding UTF8
        if ($enterpriseUiText -notmatch 'function\s+Toggle-EnterpriseNetworkAccess' -or
            $enterpriseUiText -notmatch 'function\s+Confirm-EnterpriseNetworkAccess' -or
            $enterpriseUiText -notmatch 'Set-ToolEnterpriseNetworkAllowedPreference' -or
            $enterpriseUiText -notmatch 'Offline không được ẩn hoặc vô hiệu hóa chức năng Máy chủ/Máy trạm') {
            Fail "Enterprise UI chưa giữ đủ 3 chức năng hoặc thiếu công tắc mạng riêng."
        }
        if ($enterpriseUiText -match 'Mục 8 vẫn giữ nguyên đủ 3 chức năng.+v4\.2\.0\.8') {
            Fail "Enterprise UI vẫn còn câu cảnh báo Mục 8 mà người dùng yêu cầu bỏ."
        }
        $launcherText = Get-Content -LiteralPath (Join-Path $root "Tool-Kiem-Tra-v4.4-OneFile.cs") -Raw -Encoding UTF8
        if ($launcherText -match 'mode\s*==\s*LaunchMode\.EnterpriseUi\s*\|\|\s*mode\s*==\s*LaunchMode\.EnterpriseServer' -or
            $launcherText -notmatch 'ResolveEnterpriseNetworkAllowed' -or
            $launcherText -notmatch 'TOOL_ENTERPRISE_NETWORK_ALLOWED') {
            Fail "Launcher không tách đúng UI Mục 8 khỏi quyền mạng riêng của server/agent."
        }
    } catch {
        Fail "Kiểm thử Offline/i18n thất bại: $($_.Exception.Message)"
    } finally {
        $env:TOOL_OFFLINE_MODE = $oldOfflineMode
        $env:TOOL_OFFLINE_SETTINGS_PATH = $oldOfflineSettings
        $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = $oldEnterpriseNetworkAllowed
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = $oldEnterpriseNetworkSettings
        $env:TOOL_UI_CULTURE = $oldCulture
        $env:TOOL_UI_CULTURE_SETTINGS_PATH = $oldCultureSettings
        if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-OFFLINE-I18N: FAILED ($($failures.Count) errors)"
    exit 1
}
Write-Host "VERIFY-OFFLINE-I18N: OK (offline-default + Section 8 network toggle + synchronized vi-VN/en-US + offline PDF policy)" -ForegroundColor Green
exit 0
