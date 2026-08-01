param()

$toolVersion = "4.4"
$dashboardSchemaVersion = "2.0"
$releaseVersion = "4.4.0.0"
$releaseBuildDate = "2026.07.31"
$releaseDisplayName = "v$releaseVersion Enterprise"

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Công cụ cần PowerShell 3.0 trở lên. Windows 7 có thể cài Windows Management Framework 3+.",
        "Không đủ điều kiện chạy",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 10
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$compatibilityHelper = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
$capabilityHelper = Join-Path $PSScriptRoot "Tool-Capabilities.ps1"
$loggingHelper = Join-Path $PSScriptRoot "Tool-Logging.ps1"
$moduleContractHelper = Join-Path $PSScriptRoot "Tool-ModuleContract.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$pluginEngineHelper = Join-Path $PSScriptRoot "Tool-PluginEngine.ps1"
$timelineHelper = Join-Path $PSScriptRoot "Tool-LicenseTimeline.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$enterpriseHelper = Join-Path $PSScriptRoot "Tool-Enterprise.ps1"
$uiThemeHelper = Join-Path $PSScriptRoot "Tool-UiTheme.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$offlinePolicyHelper = Join-Path $PSScriptRoot "Tool-OfflinePolicy.ps1"
$missingFoundationFiles = @($runtimeHelper, $compatibilityHelper, $capabilityHelper, $loggingHelper, $moduleContractHelper, $reportSchemaHelper, $reportExportHelper, $pluginEngineHelper, $timelineHelper, $safetyPolicyHelper, $enterpriseHelper, $uiThemeHelper, $localizationHelper, $offlinePolicyHelper) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missingFoundationFiles.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Thiếu mô-đun nền tảng: $((@($missingFoundationFiles | ForEach-Object { [IO.Path]::GetFileName($_) })) -join ', ').",
        "Bộ tool không đầy đủ", "OK", "Error") | Out-Null
    exit 12
}
try {
    . $runtimeHelper
    . $compatibilityHelper
    . $capabilityHelper
    . $loggingHelper
    . $moduleContractHelper
    . $reportSchemaHelper
    . $reportExportHelper
    . $pluginEngineHelper
    . $timelineHelper
    . $safetyPolicyHelper
    . $enterpriseHelper
    . $uiThemeHelper
    . $localizationHelper
    . $offlinePolicyHelper
    $architectureState = Assert-ToolNativeArchitecture
    $toolPowerShellPath = Get-ToolNativePowerShellPath
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $capabilityState = Get-ToolCapabilityProfile
    if (-not $capabilityState.SupportedOperatingSystem) { throw "Hệ điều hành không thuộc phạm vi Windows 7 SP1 đến Windows 11." }
    $moduleContractState = Get-ToolModuleContractMetadata
    $reportSchemaState = Get-ToolReportSchemaMetadata
    $safetyPolicyState = Get-ToolSafetyPolicyMetadata
    $enterpriseState = Get-ToolEnterpriseMetadata
    $compatibilityState = Get-ToolCompatibilityMetadata
    $localizationState = Get-ToolLocalizationMetadata
    $offlinePolicyState = Get-ToolOfflinePolicyMetadata
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_CAPABILITY_SCHEMA -ne [string]$capabilityState.SchemaVersion) { throw "Launcher và payload không thống nhất capability schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_MODULE_CONTRACT_SCHEMA -ne [string]$moduleContractState.ContractSchemaVersion) { throw "Launcher và payload không thống nhất module contract schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_REPORT_SCHEMA -ne [string]$reportSchemaState.SchemaVersion) { throw "Launcher và payload không thống nhất report schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_SAFETY_POLICY_SCHEMA -ne [string]$safetyPolicyState.SchemaVersion) { throw "Launcher và payload không thống nhất safety policy schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_DASHBOARD_SCHEMA -ne [string]$dashboardSchemaVersion) { throw "Launcher và payload không thống nhất dashboard schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_ENTERPRISE_SCHEMA -ne [string]$enterpriseState.SchemaVersion) { throw "Launcher và payload không thống nhất enterprise schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_COMPATIBILITY_SCHEMA -ne [string]$compatibilityState.SchemaVersion) { throw "Launcher và payload không thống nhất compatibility schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_LOCALIZATION_SCHEMA -ne [string]$localizationState.SchemaVersion) { throw "Launcher và payload không thống nhất localization schema." }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_OFFLINE_POLICY_SCHEMA -ne [string]$offlinePolicyState.SchemaVersion) { throw "Launcher và payload không thống nhất offline policy schema." }
    $loggingState = Initialize-ToolLogging -Component "GUI" -ToolVersion $toolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $toolVersion
    $nativeNotepadPath = Get-ToolNativeSystemPath "notepad.exe"
    # explorer.exe belongs to the Windows root, not System32/Sysnative.
    $nativeExplorerPath = Get-ToolWindowsPath "explorer.exe"
    if (-not (Test-Path -LiteralPath $nativeExplorerPath -PathType Leaf)) {
        throw "Không tìm thấy Windows Explorer: $nativeExplorerPath"
    }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        "Sai kiến trúc chạy", "OK", "Warning") | Out-Null
    exit 12
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::EnableVisualStyles()

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportScript = Join-Path $baseDir "kiem-tra-cau-hinh-ban-quyen.ps1"
$cleanupScript = Join-Path $baseDir "windows-license-compliance-cleanup.ps1"
$backupScript = Join-Path $baseDir "windows-license-backup.ps1"
$restoreScript = Join-Path $baseDir "windows-license-restore.ps1"
$oemScript = Join-Path $baseDir "windows-oem-license-assistant.ps1"
$deepScanScript = Join-Path $baseDir "windows-license-deep-scan.ps1"
$forensicsScript = Join-Path $baseDir "windows-license-forensics.ps1"
$licenseManagerScript = Join-Path $baseDir "enterprise-license-manager.ps1"
$localLicenseManagerScript = Join-Path $baseDir "windows-office-license-manager.ps1"
$assuranceScript = Join-Path $baseDir "windows-license-assurance.ps1"
$guideFile = Join-Path $baseDir "HUONG-DAN.txt"
$englishGuideFile = Join-Path $baseDir "USER-GUIDE-en-US.md"
$historyFile = Join-Path $baseDir "LICH-SU-PHIEN-BAN.txt"
$integrityManifest = Join-Path $baseDir "TOOL-SHA256SUMS.txt"
$requiredIntegrityFiles = @(
    "00-Tool-Kiem-Tra.ico", "HUONG-DAN.txt", "USER-GUIDE-en-US.md", "LICH-SU-PHIEN-BAN.txt",
    "Giao-Dien.ps1", "kiem-tra-cau-hinh-ban-quyen.ps1", "Tool-Kiem-Tra-icon.svg",
    "Tool-Kiem-Tra.cmd", "Tool-Runtime.ps1", "Tool-Compatibility.ps1", "compatibility-catalog-v1.0.json", "Tool-Capabilities.ps1", "Tool-ScanOptimization.ps1", "Tool-Logging.ps1", "Tool-ModuleContract.ps1", "Tool-UiTheme.ps1", "Tool-Localization.ps1", "Tool-Strings.vi-VN.json", "Tool-Strings.en-US.json", "Tool-OfflinePolicy.ps1", "windows-license-backup.ps1",
    "Tool-ReportSchema.ps1", "Tool-ReportExport.ps1", "Tool-PluginEngine.ps1", "Tool-LicenseTimeline.ps1", "Tool-SafetyPolicy.ps1",
    "Tool-Enterprise.ps1", "Tool-EnterpriseHost.ps1", "Tool-EnterpriseAgent.ps1", "enterprise-license-manager.ps1",
    "windows-license-compliance-cleanup.ps1", "windows-license-restore.ps1",
    "windows-license-deep-scan.ps1", "windows-license-forensics.ps1",
    "windows-oem-license-assistant.ps1", "windows-office-license-manager.ps1",
    "windows-license-assurance.ps1", "builtin-windows-office-trust.plugin.json"
)
$runtimeDir = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $baseDir "runtime" }
if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) { New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null }
try {
    $administratorsSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $runtimeAcl = New-Object Security.AccessControl.DirectorySecurity
    $runtimeAcl.SetAccessRuleProtection($true, $false)
    $runtimeAcl.SetOwner($administratorsSid)
    $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administratorsSid, "FullControl", $inheritance, "None", "Allow")))
    $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
    Set-Acl -LiteralPath $runtimeDir -AclObject $runtimeAcl -ErrorAction Stop
} catch {
    $env:TOOL_SECURE_RUNTIME_FAILED = "1"
}
$approvedKmsFile = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_APPROVED_KMS_FILE)) { $env:TOOL_APPROVED_KMS_FILE } else { Join-Path $baseDir "approved-kms-servers.txt" }
$bundledApprovedKmsFile = Join-Path $baseDir "approved-kms-servers.txt"
$desktop = [Environment]::GetFolderPath("Desktop")
$uiTypography = Get-ToolUiTypography
$fontNormal = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Regular)
$fontSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.SmallSize, [System.Drawing.FontStyle]::Regular)
$fontBold = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.DashboardTitleSize, [System.Drawing.FontStyle]::Bold)
$fontCardValue = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.CardValueSize, [System.Drawing.FontStyle]::Bold)
$fontIntroTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.IntroTitleSize, [System.Drawing.FontStyle]::Bold)
$fontTile = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.TileSize, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Công cụ kiểm tra cấu hình và bản quyền - $releaseDisplayName"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1040, 820)
$form.MinimumSize = New-Object System.Drawing.Size(780, 600)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
$form.Font = $fontNormal
$form.AutoScroll = $false
$form.AutoScrollMargin = New-Object System.Drawing.Size(0, 0)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$script:dashboardTheme = Get-ToolUiTheme
$env:TOOL_UI_THEME = $script:dashboardTheme
$script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
$script:dashboardCulture = Get-ToolCulture
$script:offlineMode = [bool](Get-ToolOfflineMode)
$env:TOOL_UI_CULTURE = $script:dashboardCulture
$env:TOOL_OFFLINE_MODE = if ($script:offlineMode) { "1" } else { "0" }
$form.Text = "$(Get-ToolText -Key "app.title" -Culture $script:dashboardCulture) - $releaseDisplayName"
$dashboardCards = @{}
$dashboardCardPanels = New-Object System.Collections.ArrayList
$menuButtonMetadata = @{}
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 100

$title = New-Object System.Windows.Forms.Label
$title.Text = Get-ToolText -Key "app.title" -Culture $script:dashboardCulture
$title.Font = $fontTitle
$title.UseCompatibleTextRendering = $false
$title.UseMnemonic = $false
$title.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$title.TextAlign = "MiddleLeft"
$title.Location = New-Object System.Drawing.Point(38, 10)
$title.Size = New-Object System.Drawing.Size(700, 38)
$form.Controls.Add($title)

$themeButton = New-Object System.Windows.Forms.Button
$themeButton.Text = Get-ToolText -Key "app.theme.dark" -Culture $script:dashboardCulture
$themeButton.Font = $fontBold
$themeButton.FlatStyle = "Flat"
$themeButton.Size = New-Object System.Drawing.Size(112, 32)
$themeButton.Location = New-Object System.Drawing.Point(820, 12)
$themeButton.Add_Click({
    $script:dashboardTheme = if ($script:dashboardTheme -eq "Light") { "Dark" } else { "Light" }
    $script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    [void](Set-ToolUiThemePreference -Mode $script:dashboardTheme)
    Set-DashboardTheme -Mode $script:dashboardTheme
})
$form.Controls.Add($themeButton)

$offlineButton = New-Object System.Windows.Forms.Button
$offlineButton.Font = $fontBold
$offlineButton.FlatStyle = "Flat"
$offlineButton.FlatAppearance.BorderSize = 1
$offlineButton.Size = New-Object System.Drawing.Size(156, 32)
$offlineButton.Location = New-Object System.Drawing.Point(650, 12)
$offlineButton.Add_Click({ Toggle-DashboardOfflineMode })
$form.Controls.Add($offlineButton)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$languageCombo.Font = $fontNormal
$languageCombo.Size = New-Object System.Drawing.Size(116, 32)
[void]$languageCombo.Items.Add("Tiếng Việt")
[void]$languageCombo.Items.Add("English")
$languageCombo.SelectedIndex = if ($script:dashboardCulture -eq "en-US") { 1 } else { 0 }
$languageCombo.Add_SelectedIndexChanged({
    $selectedCulture = if ($languageCombo.SelectedIndex -eq 1) { "en-US" } else { "vi-VN" }
    if ($selectedCulture -ne $script:dashboardCulture) { Set-DashboardLanguage -Culture $selectedCulture }
})
$form.Controls.Add($languageCombo)

$developer = New-Object System.Windows.Forms.Label
$developer.Text = Get-ToolText -Key "app.developer" -Culture $script:dashboardCulture
$developer.Font = $fontBold
$developer.UseCompatibleTextRendering = $false
$developer.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$developer.TextAlign = "MiddleLeft"
$developer.Location = New-Object System.Drawing.Point(38, 48)
$developer.Size = New-Object System.Drawing.Size(700, 22)
$form.Controls.Add($developer)

$version = New-Object System.Windows.Forms.Label
$version.Text = "$releaseDisplayName · $($capabilityState.WindowsReleaseName) build $($capabilityState.FullBuildNumber) · $($capabilityState.OperatingSystemArchitecture) · Report $($reportSchemaState.SchemaVersion)"
$version.Font = $fontSmall
$version.UseCompatibleTextRendering = $false
$version.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$version.TextAlign = "MiddleLeft"
$version.Location = New-Object System.Drawing.Point(38, 72)
$version.Size = New-Object System.Drawing.Size(860, 20)
$form.Controls.Add($version)

$introPanel = New-Object System.Windows.Forms.Panel
$introPanel.Location = New-Object System.Drawing.Point(38, 100)
$introPanel.Size = New-Object System.Drawing.Size(860, 58)
$introPanel.BackColor = [System.Drawing.Color]::FromArgb(235, 244, 255)
$introPanel.BorderStyle = "None"
$form.Controls.Add($introPanel)

$introAccent = New-Object System.Windows.Forms.Panel
$introAccent.BackColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$introAccent.Location = New-Object System.Drawing.Point(0, 0)
$introAccent.Size = New-Object System.Drawing.Size(5, 58)
$introPanel.Controls.Add($introAccent)

$description = New-Object System.Windows.Forms.Label
$description.Text = Get-ToolText -Key "app.hero.title" -Culture $script:dashboardCulture
$description.Font = $fontIntroTitle
$description.UseCompatibleTextRendering = $false
$description.UseMnemonic = $false
$description.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$description.AutoEllipsis = $true
$description.Location = New-Object System.Drawing.Point(15, 6)
$description.Size = New-Object System.Drawing.Size(650, 22)
$introPanel.Controls.Add($description)

$introSummary = New-Object System.Windows.Forms.Label
$introSummary.Text = Get-ToolText -Key "app.hero.summary" -Culture $script:dashboardCulture
$introSummary.Font = $fontSmall
$introSummary.UseCompatibleTextRendering = $false
$introSummary.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$introSummary.AutoEllipsis = $true
$introSummary.Location = New-Object System.Drawing.Point(15, 30)
$introSummary.Size = New-Object System.Drawing.Size(650, 20)
$introPanel.Controls.Add($introSummary)

$introDetailButton = New-Object System.Windows.Forms.Button
$introDetailButton.Text = Get-ToolText -Key "app.about" -Culture $script:dashboardCulture
$introDetailButton.Font = $fontBold
$introDetailButton.FlatStyle = "Flat"
$introDetailButton.FlatAppearance.BorderSize = 0
$introDetailButton.BackColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$introDetailButton.ForeColor = [System.Drawing.Color]::White
$introDetailButton.Size = New-Object System.Drawing.Size(154, 32)
$introDetailButton.Location = New-Object System.Drawing.Point(690, 12)
$introDetailButton.Add_Click({ Show-ProductIntroduction })
$introPanel.Controls.Add($introDetailButton)
$form.PerformLayout()

$dashboardPanel = New-Object System.Windows.Forms.Panel
$dashboardPanel.Location = New-Object System.Drawing.Point(38, ($introPanel.Bottom + 8))
$dashboardPanel.Size = New-Object System.Drawing.Size(860, 92)
$dashboardPanel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($dashboardPanel)

$cardDefinitions = @(
    @{ Key="Compatibility"; Caption=(Get-ToolText -Key "dashboard.windows" -Culture $script:dashboardCulture); Value=[string]$capabilityState.WindowsReleaseName },
    @{ Key="Architecture"; Caption=(Get-ToolText -Key "dashboard.office" -Culture $script:dashboardCulture); Value=[string]$capabilityState.OfficeSummary },
    @{ Key="SecureLaunch"; Caption=(Get-ToolText -Key "dashboard.runMode" -Culture $script:dashboardCulture); Value=$(if ($env:TOOL_SECURE_LAUNCH -eq "1") { Get-ToolText -Key "dashboard.secure" -Culture $script:dashboardCulture } else { Get-ToolText -Key "dashboard.source" -Culture $script:dashboardCulture }) },
    @{ Key="Integrity"; Caption=(Get-ToolText -Key "dashboard.integrity" -Culture $script:dashboardCulture); Value=(Get-ToolText -Key "dashboard.checking" -Culture $script:dashboardCulture) }
)
for ($cardIndex = 0; $cardIndex -lt $cardDefinitions.Count; $cardIndex++) {
    $definition = $cardDefinitions[$cardIndex]
    $card = New-Object System.Windows.Forms.Panel
    $card.BorderStyle = "None"
    $card.BackColor = [System.Drawing.Color]::White
    $card.Size = New-Object System.Drawing.Size(202, 80)
    $card.Location = New-Object System.Drawing.Point(($cardIndex * 216), 6)
    $card.Tag = "DashboardCard"

    $cardCaption = New-Object System.Windows.Forms.Label
    $cardCaption.Text = [string]$definition.Caption
    $cardCaption.Font = $fontSmall
    $cardCaption.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
    $cardCaption.Location = New-Object System.Drawing.Point(12, 10)
    $cardCaption.Size = New-Object System.Drawing.Size(176, 18)
    $card.Controls.Add($cardCaption)

    $cardValue = New-Object System.Windows.Forms.Label
    $cardValue.Text = [string]$definition.Value
    $cardValue.Font = $fontCardValue
    $cardValue.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $cardValue.AutoEllipsis = $true
    $cardValue.Location = New-Object System.Drawing.Point(12, 34)
    $cardValue.Size = New-Object System.Drawing.Size(176, 30)
    $card.Controls.Add($cardValue)

    $cardAccent = New-Object System.Windows.Forms.Panel
    $cardAccent.BackColor = [System.Drawing.Color]::FromArgb(45, 111, 203)
    $cardAccent.Location = New-Object System.Drawing.Point(0, 0)
    $cardAccent.Size = New-Object System.Drawing.Size(5, 80)
    $cardAccent.Tag = "CardAccent"
    $card.Controls.Add($cardAccent)

    $dashboardCards[[string]$definition.Key] = [pscustomobject]@{ Panel=$card; Caption=$cardCaption; Value=$cardValue }
    [void]$dashboardCardPanels.Add($card)
    $dashboardPanel.Controls.Add($card)
}

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(38, ($dashboardPanel.Bottom + 10))
$buttonPanel.Size = New-Object System.Drawing.Size(860, 334)
$buttonPanel.BackColor = [System.Drawing.Color]::White
$buttonPanel.BorderStyle = "None"
$form.Controls.Add($buttonPanel)

$menuCaption = New-Object System.Windows.Forms.Label
$menuCaption.Text = Get-ToolText -Key "dashboard.functions" -Culture $script:dashboardCulture
$menuCaption.Font = $fontBold
$menuCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$menuCaption.Location = New-Object System.Drawing.Point(16, 8)
$menuCaption.Size = New-Object System.Drawing.Size(300, 22)
$buttonPanel.Controls.Add($menuCaption)

$status = New-Object System.Windows.Forms.Label
$status.Text = ""
$status.Font = $fontNormal
$status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$status.TextAlign = "MiddleLeft"
$status.Location = New-Object System.Drawing.Point(38, ($buttonPanel.Bottom + 13))
$status.Size = New-Object System.Drawing.Size(550, 24)
$form.Controls.Add($status)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
$closeButton.Font = $fontBold
$closeButton.Location = New-Object System.Drawing.Point(600, ($buttonPanel.Bottom + 10))
$closeButton.Size = New-Object System.Drawing.Size(108, 30)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
$stopButton.Font = $fontBold
$stopButton.Location = New-Object System.Drawing.Point(484, ($buttonPanel.Bottom + 10))
$stopButton.Size = New-Object System.Drawing.Size(108, 30)
$stopButton.Visible = $false
$stopButton.Enabled = $false
$stopButton.Add_Click({ Stop-ActiveTask })
$form.Controls.Add($stopButton)

$copyLogButton = New-Object System.Windows.Forms.Button
$copyLogButton.Text = Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture
$copyLogButton.Font = $fontSmall
$copyLogButton.Size = New-Object System.Drawing.Size(142, 26)
$copyLogButton.Add_Click({ Copy-AllToolLog })
$form.Controls.Add($copyLogButton)

$openReportFolderButton = New-Object System.Windows.Forms.Button
$openReportFolderButton.Text = Get-ToolText -Key "report.openFolder" -Culture $script:dashboardCulture
$openReportFolderButton.Font = $fontSmall
$openReportFolderButton.Size = New-Object System.Drawing.Size(166, 26)
$openReportFolderButton.Add_Click({ Open-ReportDirectory })
$form.Controls.Add($openReportFolderButton)

$progressCaption = New-Object System.Windows.Forms.Label
$progressCaption.Text = Get-ToolText -Key "progress.caption" -Culture $script:dashboardCulture
$progressCaption.Font = $fontBold
$progressCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$progressCaption.Location = New-Object System.Drawing.Point(38, ($closeButton.Bottom + 5))
$progressCaption.Size = New-Object System.Drawing.Size(670, 18)
$form.Controls.Add($progressCaption)

$activityLabel = New-Object System.Windows.Forms.Label
$activityLabel.Text = ""
$activityLabel.Font = $fontSmall
$activityLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$activityLabel.TextAlign = "MiddleLeft"
$activityLabel.AutoEllipsis = $true
$activityLabel.Location = New-Object System.Drawing.Point(38, ($progressCaption.Bottom + 2))
$activityLabel.Size = New-Object System.Drawing.Size(585, 20)
$form.Controls.Add($activityLabel)

$elapsedLabel = New-Object System.Windows.Forms.Label
$elapsedLabel.Text = ""
$elapsedLabel.Font = $fontSmall
$elapsedLabel.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$elapsedLabel.TextAlign = "MiddleRight"
$elapsedLabel.Location = New-Object System.Drawing.Point(623, ($progressCaption.Bottom + 2))
$elapsedLabel.Size = New-Object System.Drawing.Size(85, 20)
$form.Controls.Add($elapsedLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Location = New-Object System.Drawing.Point(38, ($activityLabel.Bottom + 1))
$progressBar.Size = New-Object System.Drawing.Size(670, 15)
$form.Controls.Add($progressBar)

$progressLog = New-Object System.Windows.Forms.TextBox
$progressLog.Multiline = $true
$progressLog.ReadOnly = $true
$progressLog.ScrollBars = "Vertical"
$progressLog.WordWrap = $true
$progressLog.Font = $fontSmall
$progressLog.BackColor = [System.Drawing.Color]::White
$progressLog.Location = New-Object System.Drawing.Point(38, ($progressBar.Bottom + 4))
$progressLog.Size = New-Object System.Drawing.Size(670, 62)
$form.Controls.Add($progressLog)

$activityLabel.Visible = $false
$elapsedLabel.Visible = $false
$progressBar.Visible = $false
$progressLog.Visible = $false

# Kích thước cuối chỉ được chốt ở sự kiện Shown, sau khi WinForms đã áp dụng
# DPI. Nếu tính trước AutoScale, control bị phóng lên nhưng cửa sổ vẫn giữ kích
# thước cũ và phần nhật ký/nút dưới cùng sẽ bị cắt như ở bản 4.0 ban đầu.
$form.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($progressLog.Bottom + 16))

$activeProcess = $null
$activeAction = ""
$activeTaskKind = ""
$activeModuleId = ""
$activeModuleInvocation = $null
$lastModuleResult = $null
$cleanupDecisionFile = ""
$cleanupResultFile = ""
$cleanupSelectionFile = ""
$cleanupRepairDecisionFile = ""
$cleanupRedactSensitive = $true
$cleanupAutoSafeMode = $false
$backupResultFile = ""
$restoreResultFile = ""
$oemDecisionFile = ""
$deepScanDecisionFile = ""
$forensicsDecisionFile = ""
$progressTick = 0
$progressPhase = 0
$taskStartedAt = $null
$lastProgressHeartbeat = 0
$buttons = New-Object System.Collections.ArrayList
$script:reportPresentationCache = @{}
$script:updatingMainLayout = $false
$script:hasTaskActivity = $false
$script:taskCancellationRequested = $false
$script:lastReportDirectory = $desktop
$script:executionEnvironmentWarningShown = $false

function Register-ToolReportPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $directory = if (Test-Path -LiteralPath $fullPath -PathType Container) { $fullPath } else { Split-Path -Parent $fullPath }
        if (-not [string]::IsNullOrWhiteSpace($directory) -and (Test-Path -LiteralPath $directory -PathType Container)) {
            $script:lastReportDirectory = $directory
        }
    } catch {}
}

function Copy-AllToolLog {
    $text = [string]$progressLog.Text
    if ([string]::IsNullOrWhiteSpace($text) -and $loggingState.Enabled -and (Test-Path -LiteralPath $loggingState.Path -PathType Leaf)) {
        try { $text = [IO.File]::ReadAllText($loggingState.Path, [Text.Encoding]::UTF8) } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "progress.copyNoLog" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture), "OK", "Information") | Out-Null
        return
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($text)
        $status.Text = Get-ToolText -Key "progress.copySuccess" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "progress.copyFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Open-ReportDirectory {
    $directory = [string]$script:lastReportDirectory
    if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) { $directory = $desktop }
    try {
        Start-Process -FilePath $nativeExplorerPath -ArgumentList ('"' + $directory + '"')
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.openFolderFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "report.openFolder" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Show-ExecutionEnvironmentWarning {
    if ($script:executionEnvironmentWarningShown) { return }
    $environmentProfile = $capabilityState.ExecutionEnvironment
    if (-not $environmentProfile -or (-not $environmentProfile.VirtualMachineDetected -and -not $environmentProfile.RemoteDesktopDetected)) { return }
    $script:executionEnvironmentWarningShown = $true
    $details = New-Object System.Collections.Generic.List[string]
    if ($environmentProfile.VirtualMachineDetected) {
        [void]$details.Add((Get-ToolText -Key "environment.virtualMachine" -Culture $script:dashboardCulture -FormatArguments @([string]$environmentProfile.VirtualizationProvider)))
    }
    if ($environmentProfile.RemoteDesktopDetected) {
        [void]$details.Add((Get-ToolText -Key "environment.remoteDesktop" -Culture $script:dashboardCulture -FormatArguments @([string]$environmentProfile.SessionName)))
    }
    $message = (Get-ToolText -Key "environment.warning" -Culture $script:dashboardCulture -FormatArguments @(($details -join [Environment]::NewLine)))
    $status.Text = Get-ToolText -Key "environment.status" -Culture $script:dashboardCulture
    $status.ForeColor = [System.Drawing.Color]::DarkOrange
    Write-ProgressLog $message
    [void](Write-ToolLog -Level "WARN" -Event "ExecutionEnvironment.Warning" -Message $message -Data $environmentProfile)
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        (Get-ToolText -Key "environment.warningTitle" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Open-ToolReportPresentation {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$FilePrefix
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return $null
    }
    $sourceFull = [IO.Path]::GetFullPath($SourcePath)
    $cacheKey = $sourceFull.ToLowerInvariant()
    if ($script:reportPresentationCache.ContainsKey($cacheKey)) {
        $cached = $script:reportPresentationCache[$cacheKey]
        if ($cached -and (Test-Path -LiteralPath $cached.HtmlPath -PathType Leaf)) {
            Start-Process -FilePath $cached.HtmlPath
            return $cached
        }
        $script:reportPresentationCache.Remove($cacheKey)
    }

    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $safePrefix = ([string]$FilePrefix -replace '[^A-Za-z0-9_-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) { $safePrefix = "BaoCao" }
    $basePath = Join-Path $desktop "${safePrefix}_$($env:COMPUTERNAME)_$stamp"
    $extension = [IO.Path]::GetExtension($sourceFull).ToLowerInvariant()
    if ($extension -in @(".html", ".htm")) {
        $desktopFull = [IO.Path]::GetFullPath($desktop).TrimEnd([char]92)
        $sourceDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $sourceFull)).TrimEnd([char]92)
        if ([string]::Equals($desktopFull, $sourceDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            $htmlPath = $sourceFull
            $pdfPath = [IO.Path]::ChangeExtension($htmlPath, ".pdf")
        } else {
            $htmlPath = "$basePath.html"
            $pdfPath = "$basePath.pdf"
            $htmlContent = [IO.File]::ReadAllText($sourceFull, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($htmlPath, $htmlContent, (New-Object Text.UTF8Encoding($false)))
        }
        if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) {
            throw "Báo cáo HTML không đạt kiểm tra an toàn ngoại tuyến."
        }
        $pdfResult = if ((Test-Path -LiteralPath $pdfPath -PathType Leaf) -and (Get-Item -LiteralPath $pdfPath).Length -gt 1024) {
            [pscustomobject][ordered]@{ Success=$true; Engine="Existing"; Path=$pdfPath; Error="" }
        } else {
            Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
        }
        $package = [pscustomobject][ordered]@{
            Success = $true
            HtmlPath = $htmlPath
            PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
            ManifestPath = ""
            Pdf = $pdfResult
        }
    } else {
        $sourceLines = [IO.File]::ReadAllLines($sourceFull, [Text.Encoding]::UTF8)
        $package = Export-ToolTextReportPresentation `
            -Lines $sourceLines -Title $Title -BasePath $basePath `
            -Subtitle (Get-ToolText -Key "report.description" -Culture $script:dashboardCulture) `
            -Eyebrow (Get-ToolText -Key "report.eyebrow" -Culture $script:dashboardCulture) `
            -Footer "$(Get-ToolText -Key "app.developer" -Culture $script:dashboardCulture) · $releaseDisplayName" `
            -Culture $script:dashboardCulture -IncludePdf
    }
    $script:reportPresentationCache[$cacheKey] = $package
    Register-ToolReportPath -Path $package.HtmlPath
    Start-Process -FilePath $package.HtmlPath
    Write-ProgressLog "Đã lưu HTML/PDF trên Desktop và mở báo cáo HTML: $([IO.Path]::GetFileName($package.HtmlPath))"
    return $package
}

function Set-ModernRoundedRegion {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
        [int]$Radius = 12
    )
    if ($Control.Width -le 2 -or $Control.Height -le 2) { return }
    $diameter = [Math]::Max(2, [Math]::Min($Radius * 2, [Math]::Min($Control.Width - 1, $Control.Height - 1)))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc($Control.Width - $diameter - 1, 0, $diameter, $diameter, 270, 90)
        $path.AddArc($Control.Width - $diameter - 1, $Control.Height - $diameter - 1, $diameter, $diameter, 0, 90)
        $path.AddArc(0, $Control.Height - $diameter - 1, $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $newRegion = New-Object System.Drawing.Region($path)
        $oldRegion = $Control.Region
        $Control.Region = $newRegion
        if ($oldRegion) { $oldRegion.Dispose() }
    } finally {
        $path.Dispose()
    }
}

function Update-MainLayout {
    if ($script:updatingMainLayout) { return }
    $script:updatingMainLayout = $true
    try {
        $left = 28
        $right = 28
        $form.AutoScroll = $false
        $form.AutoScrollMinSize = New-Object System.Drawing.Size(0, 0)
        $clientWidth = [Math]::Max(1, $form.ClientSize.Width)
        $contentWidth = [Math]::Max(360, $clientWidth - $left - $right)
        $compactHeight = [bool]($form.ClientSize.Height -lt 760)
        $ultraCompactHeight = [bool]($form.ClientSize.Height -lt 640)
        $progressExpanded = [bool]$script:hasTaskActivity

        # Toàn bộ trục dọc được tính lại bằng pixel sau AutoScale/DPI. Không sử
        # dụng Bottom đã bị scale từ designer cũ vì nó làm sai chiều cao cửa sổ.
        $title.Left = $left
        $title.Top = 7
        $title.Height = [Math]::Max(34, $title.PreferredHeight + 4)
        $commandGap = 8
        $themeButton.Top = 8
        $themeButton.Left = $left + $contentWidth - $themeButton.Width
        $languageCombo.Top = 10
        $languageCombo.Left = $themeButton.Left - $commandGap - $languageCombo.Width
        $offlineButton.Top = 8
        $offlineButton.Left = $languageCombo.Left - $commandGap - $offlineButton.Width
        $title.Width = [Math]::Max(300, $offlineButton.Left - $left - 12)

        $developer.Left = $left
        $developer.Top = $title.Bottom
        $developer.Height = [Math]::Max(20, $developer.PreferredHeight)
        $developer.Width = $contentWidth
        $version.Left = $left
        $version.Top = $developer.Bottom + 1
        $version.Height = [Math]::Max(18, $version.PreferredHeight)
        $version.Width = $contentWidth

        $introPanel.Left = $left
        $introPanel.Top = $version.Bottom + 5
        $introPanel.Width = $contentWidth
        $introPanel.Height = if ($ultraCompactHeight) { 40 } elseif ($compactHeight) { 48 } else { 58 }
        $introAccent.Left = 0
        $introAccent.Top = 0
        $introAccent.Width = 5
        $introAccent.Height = $introPanel.ClientSize.Height
        $introDetailButton.Width = if ($ultraCompactHeight) { 142 } else { 154 }
        $introDetailButton.Height = 30
        $introDetailButton.Left = $introPanel.ClientSize.Width - $introDetailButton.Width - 10
        $introDetailButton.Top = [Math]::Max(4, [Math]::Floor(($introPanel.ClientSize.Height - $introDetailButton.Height) / 2))
        $description.Left = 15
        $description.Top = if ($ultraCompactHeight) { 9 } else { 5 }
        $description.Width = [Math]::Max(260, $introDetailButton.Left - $description.Left - 10)
        $description.Height = 22
        $description.Visible = $true
        $introSummary.Left = 15
        $introSummary.Top = 29
        $introSummary.Width = $description.Width
        $introSummary.Height = 19
        $introSummary.Visible = -not $ultraCompactHeight

        $dashboardPanel.Left = $left
        $dashboardPanel.Top = $introPanel.Bottom + 5
        $dashboardPanel.Width = $contentWidth
        $dashboardPanel.Height = if ($ultraCompactHeight) { 64 } elseif ($compactHeight) { 68 } else { 82 }
        $cardGap = 9
        $cardWidth = [Math]::Max(145, [Math]::Floor(($dashboardPanel.ClientSize.Width - ($cardGap * 3)) / 4))
        for ($cardIndex = 0; $cardIndex -lt $dashboardCardPanels.Count; $cardIndex++) {
            $card = $dashboardCardPanels[$cardIndex]
            $card.Left = $cardIndex * ($cardWidth + $cardGap)
            $card.Top = 2
            $card.Width = $cardWidth
            $card.Height = if ($ultraCompactHeight) { 60 } elseif ($compactHeight) { 64 } else { 76 }
            if ($card.Controls.Count -ge 2) {
                $card.Controls[0].Top = if ($ultraCompactHeight) { 4 } elseif ($compactHeight) { 5 } else { 8 }
                $card.Controls[0].Width = [Math]::Max(110, $cardWidth - 22)
                $card.Controls[1].Top = if ($ultraCompactHeight) { 23 } elseif ($compactHeight) { 25 } else { 30 }
                $card.Controls[1].Width = [Math]::Max(110, $cardWidth - 22)
            }
            foreach ($child in $card.Controls) {
                if ([string]$child.Tag -eq "CardAccent") { $child.Height = $card.ClientSize.Height }
            }
            Set-ModernRoundedRegion -Control $card -Radius 13
        }

        $buttonPanel.Left = $left
        $buttonPanel.Top = $dashboardPanel.Bottom + 7
        $buttonPanel.Width = $contentWidth
        $menuCaption.Width = [Math]::Max(300, $buttonPanel.ClientSize.Width - 28)
        $menuCaption.Top = 7

        $tileGap = 9
        $rowGap = if ($ultraCompactHeight) { 2 } elseif ($compactHeight) { 5 } else { 7 }
        $tileMargin = 13
        $tileWidth = [Math]::Max(220, [Math]::Floor(($buttonPanel.ClientSize.Width - ($tileMargin * 2) - $tileGap) / 2))
        $minimumLogHeight = if ($ultraCompactHeight) { 24 } elseif ($compactHeight) { 36 } else { 62 }
        $statusRowHeight = if ($ultraCompactHeight) { 30 } elseif ($compactHeight) { 32 } else { 36 }
        $buttonPanelBottomPadding = if ($ultraCompactHeight) { 4 } else { 8 }
        $progressFixedHeight = if ($progressExpanded) {
            5 + 26 + 20 + 15 + 4 + $minimumLogHeight + 8
        } else {
            5 + 26 + 8
        }
        $availableButtonHeight = $form.ClientSize.Height - $buttonPanel.Top - $statusRowHeight - $progressFixedHeight
        $calculatedTileHeight = [Math]::Floor(($availableButtonHeight - 32 - (4 * $rowGap) - $buttonPanelBottomPadding) / 5)
        # Giao diện không dùng thanh cuộn của cửa sổ chính. Ở màn hình thấp,
        # tile co xuống ngưỡng an toàn nhưng vẫn giữ đủ hai dòng và tooltip.
        $minimumTileHeight = if ($ultraCompactHeight) { 42 } elseif ($compactHeight) { 46 } else { 50 }
        $tileHeight = [Math]::Max($minimumTileHeight, [Math]::Min(66, $calculatedTileHeight))
        for ($buttonIndex = 0; $buttonIndex -lt $buttons.Count; $buttonIndex++) {
            $button = $buttons[$buttonIndex]
            $row = [Math]::Floor($buttonIndex / 2)
            $column = $buttonIndex % 2
            $button.Left = $tileMargin + ($column * ($tileWidth + $tileGap))
            $button.Top = 32 + ($row * ($tileHeight + $rowGap))
            $button.Width = $tileWidth
            $button.Height = $tileHeight
            Set-ModernRoundedRegion -Control $button -Radius 10
        }
        $buttonPanel.Height = 32 + (5 * $tileHeight) + (4 * $rowGap) + $buttonPanelBottomPadding

        $status.Left = $left
        $status.Top = $buttonPanel.Bottom + $(if ($ultraCompactHeight) { 4 } else { 8 })
        $status.Height = if ($ultraCompactHeight) { 22 } elseif ($compactHeight) { 24 } else { 28 }
        $closeButton.Height = if ($ultraCompactHeight) { 28 } else { 30 }
        $closeButton.Left = $left + $contentWidth - $closeButton.Width
        $closeButton.Top = $buttonPanel.Bottom + $(if ($ultraCompactHeight) { 2 } else { 5 })
        $stopButton.Height = $closeButton.Height
        $stopButton.Left = $closeButton.Left - $stopButton.Width - 8
        $stopButton.Top = $closeButton.Top
        $status.Width = [Math]::Max(260, $contentWidth - $closeButton.Width - $(if ($stopButton.Visible) { $stopButton.Width + 8 } else { 0 }) - 12)

        $progressCaption.Left = $left
        $progressCaption.Top = [Math]::Max($status.Bottom, $closeButton.Bottom) + $(if ($ultraCompactHeight) { 2 } else { 5 })
        $progressCaption.Height = 26
        $copyLogButton.Height = 26
        $openReportFolderButton.Height = 26
        $openReportFolderButton.Left = $left + $contentWidth - $openReportFolderButton.Width
        $openReportFolderButton.Top = $progressCaption.Top
        $copyLogButton.Left = $openReportFolderButton.Left - $copyLogButton.Width - 8
        $copyLogButton.Top = $progressCaption.Top
        $progressCaption.Width = [Math]::Max(220, $copyLogButton.Left - $left - 8)
        if ($progressExpanded) {
            $activityLabel.Visible = $true
            $elapsedLabel.Visible = $true
            $progressBar.Visible = $true
            $progressLog.Visible = $true
            $activityLabel.Left = $left
            $activityLabel.Top = $progressCaption.Bottom
            $activityLabel.Height = 20
            $activityLabel.Width = [Math]::Max(260, $contentWidth - $elapsedLabel.Width - 8)
            $elapsedLabel.Left = $left + $contentWidth - $elapsedLabel.Width
            $elapsedLabel.Top = $activityLabel.Top
            $progressBar.Left = $left
            $progressBar.Top = $activityLabel.Bottom + 1
            $progressBar.Height = 14
            $progressBar.Width = $contentWidth
            $progressLog.Left = $left
            $progressLog.Top = $progressBar.Bottom + 4
            $progressLog.Width = $contentWidth
            $availableLogHeight = $form.ClientSize.Height - $progressLog.Top - 8
            $progressLog.Height = [Math]::Max(20, $availableLogHeight)
        } else {
            $activityLabel.Visible = $false
            $elapsedLabel.Visible = $false
            $progressBar.Visible = $false
            $progressLog.Visible = $false
        }
        Set-ModernRoundedRegion -Control $introPanel -Radius 14
        Set-ModernRoundedRegion -Control $buttonPanel -Radius 14
        Set-ModernRoundedRegion -Control $themeButton -Radius 9
        Set-ModernRoundedRegion -Control $offlineButton -Radius 9
        Set-ModernRoundedRegion -Control $introDetailButton -Radius 9
        Set-ModernRoundedRegion -Control $stopButton -Radius 9
        Set-ModernRoundedRegion -Control $closeButton -Radius 9
        Set-ModernRoundedRegion -Control $copyLogButton -Radius 8
        Set-ModernRoundedRegion -Control $openReportFolderButton -Radius 8
    } finally {
        $script:updatingMainLayout = $false
    }
}

function Fit-MainWindowToWorkingArea {
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $availableWidth = [Math]::Max(640, $workArea.Width - 16)
    $availableHeight = [Math]::Max(520, $workArea.Height - 12)
    $targetWidth = [Math]::Min(1040, $availableWidth)
    $targetHeight = [Math]::Min(820, $availableHeight)
    $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min(720, $targetWidth), [Math]::Min(540, $targetHeight))
    $targetX = $workArea.Left + [Math]::Max(0, [Math]::Floor(($workArea.Width - $targetWidth) / 2))
    $targetY = $workArea.Top + [Math]::Max(0, [Math]::Floor(($workArea.Height - $targetHeight) / 2))
    $form.StartPosition = "Manual"
    $form.Bounds = New-Object System.Drawing.Rectangle($targetX, $targetY, $targetWidth, $targetHeight)
}

function Show-ProductIntroduction {
    $dark = [bool]($script:dashboardTheme -eq "Dark")
    $surface = if ($dark) { [System.Drawing.Color]::FromArgb(31, 36, 48) } else { [System.Drawing.Color]::White }
    $background = if ($dark) { [System.Drawing.Color]::FromArgb(20, 24, 33) } else { [System.Drawing.Color]::FromArgb(244, 246, 249) }
    $primary = if ($dark) { [System.Drawing.Color]::FromArgb(126, 174, 255) } else { [System.Drawing.Color]::FromArgb(18, 59, 116) }
    $text = if ($dark) { [System.Drawing.Color]::FromArgb(226, 231, 239) } else { [System.Drawing.Color]::FromArgb(52, 64, 84) }
    $muted = if ($dark) { [System.Drawing.Color]::FromArgb(164, 174, 192) } else { [System.Drawing.Color]::FromArgb(102, 112, 133) }
    $introSurface = if ($dark) { [System.Drawing.Color]::FromArgb(30, 44, 65) } else { [System.Drawing.Color]::FromArgb(235, 244, 255) }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key "about.form.title" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName)
    $dialog.StartPosition = "CenterParent"
    $dialog.ShowInTaskbar = $false
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.BackColor = $background
    $dialog.Font = $fontNormal
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(620, [Math]::Min(840, $workArea.Width - 40))
    $dialogHeight = [Math]::Max(480, [Math]::Min(620, $workArea.Height - 40))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(620, $dialogWidth), [Math]::Min(480, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 84)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $header.BackColor = $introSurface
    $header.BorderStyle = "FixedSingle"
    $layout.Controls.Add($header, 0, 0)

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Dock = "Left"
    $headerAccent.Width = 6
    $headerAccent.BackColor = $primary
    $header.Controls.Add($headerAccent)

    $productHeadingFont = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "about.heading" -Culture $script:dashboardCulture
    $heading.Font = $productHeadingFont
    $heading.ForeColor = $primary
    $heading.Location = New-Object System.Drawing.Point(20, 8)
    $heading.Size = New-Object System.Drawing.Size(730, 34)
    $heading.Anchor = "Top, Left, Right"
    $heading.UseMnemonic = $false
    $heading.AutoEllipsis = $true
    $header.Controls.Add($heading)

    $tagline = New-Object System.Windows.Forms.Label
    $tagline.Text = Get-ToolText -Key "about.byline" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName, $releaseBuildDate)
    $tagline.Font = $fontBold
    $tagline.ForeColor = $text
    $tagline.Location = New-Object System.Drawing.Point(20, 45)
    $tagline.Size = New-Object System.Drawing.Size(730, 24)
    $tagline.Anchor = "Top, Left, Right"
    $header.Controls.Add($tagline)

    $detailTabs = New-Object System.Windows.Forms.TabControl
    $detailTabs.Dock = "Fill"
    $detailTabs.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 4)
    $detailTabs.Font = $fontBold
    $layout.Controls.Add($detailTabs, 0, 1)

    $aboutPage = New-Object System.Windows.Forms.TabPage
    $aboutPage.Text = Get-ToolText -Key "about.productTab" -Culture $script:dashboardCulture
    $aboutPage.BackColor = $surface
    $aboutPage.Padding = New-Object System.Windows.Forms.Padding(10)
    [void]$detailTabs.TabPages.Add($aboutPage)

    $overviewPage = New-Object System.Windows.Forms.TabPage
    $overviewPage.Text = Get-ToolText -Key "about.capabilitiesTab" -Culture $script:dashboardCulture
    $overviewPage.BackColor = $background
    $overviewPage.Padding = New-Object System.Windows.Forms.Padding(4)
    [void]$detailTabs.TabPages.Add($overviewPage)

    $officialReleaseUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest"
    $aboutBox = New-Object System.Windows.Forms.RichTextBox
    $aboutBox.Dock = "Fill"
    $aboutBox.ReadOnly = $true
    $aboutBox.DetectUrls = $true
    $aboutBox.WordWrap = $true
    $aboutBox.ScrollBars = "Vertical"
    $aboutBox.BorderStyle = "None"
    $aboutBox.BackColor = $surface
    $aboutBox.ForeColor = $text
    $aboutBox.Font = $fontNormal
    $aboutBox.Tag = $officialReleaseUrl
    $aboutPage.Controls.Add($aboutBox)

    $aboutSections = @(
        @{
            Title = Get-ToolText -Key "about.product.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.product.body" -Culture $script:dashboardCulture -FormatArguments @($releaseDisplayName, $releaseBuildDate)
        },
        @{
            Title = Get-ToolText -Key "about.purpose.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.purpose.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.model.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.model.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.technology.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.technology.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.support.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.support.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.release.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.release.body" -Culture $script:dashboardCulture -FormatArguments @($officialReleaseUrl)
        },
        @{
            Title = Get-ToolText -Key "about.terms.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.terms.body" -Culture $script:dashboardCulture
        },
        @{
            Title = Get-ToolText -Key "about.safety.title" -Culture $script:dashboardCulture
            Body = Get-ToolText -Key "about.safety.body" -Culture $script:dashboardCulture
        }
    )
    foreach ($aboutSection in $aboutSections) {
        $aboutBox.SelectionStart = $aboutBox.TextLength
        $aboutBox.SelectionLength = 0
        $aboutBox.SelectionFont = $fontBold
        $aboutBox.SelectionColor = $primary
        $aboutBox.AppendText(([string]$aboutSection.Title) + "`r`n")
        $aboutBox.SelectionStart = $aboutBox.TextLength
        $aboutBox.SelectionLength = 0
        $aboutBox.SelectionFont = $fontNormal
        $aboutBox.SelectionColor = $text
        $aboutBox.AppendText(([string]$aboutSection.Body) + "`r`n`r`n")
    }
    $aboutBox.SelectionStart = 0
    $aboutBox.SelectionLength = 0
    $aboutBox.Add_LinkClicked({
        param($sender, $eventArgs)
        $approvedUrl = [string]$sender.Tag
        if ([string]::Equals([string]$eventArgs.LinkText, $approvedUrl, [StringComparison]::OrdinalIgnoreCase)) {
            if ($script:offlineMode) {
                [System.Windows.Forms.MessageBox]::Show(
                    (Get-ToolText -Key "app.offline.blocked" -Culture $script:dashboardCulture),
                    (Get-ToolText -Key "app.offline.blockedTitle" -Culture $script:dashboardCulture),
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }
            try {
                [void][Diagnostics.Process]::Start($approvedUrl)
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    (Get-ToolText -Key "about.openReleaseFailed" -Culture $script:dashboardCulture -FormatArguments @($approvedUrl)),
                    (Get-ToolText -Key "about.openReleaseFailedTitle" -Culture $script:dashboardCulture),
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
    })

    $featureGrid = New-Object System.Windows.Forms.TableLayoutPanel
    $featureGrid.Dock = "Fill"
    $featureGrid.Margin = New-Object System.Windows.Forms.Padding(0)
    $featureGrid.ColumnCount = 2
    $featureGrid.RowCount = 3
    [void]$featureGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$featureGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 45)))
    [void]$featureGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 10)))
    $overviewPage.Controls.Add($featureGrid)

    $featureDefinitions = @(
        @{ Title=(Get-ToolText -Key "about.card.config.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.config.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(238,246,255); Dark=[Drawing.Color]::FromArgb(28,43,63); Accent=[Drawing.Color]::FromArgb(37,99,235) },
        @{ Title=(Get-ToolText -Key "about.card.remediation.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.remediation.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(255,248,232); Dark=[Drawing.Color]::FromArgb(58,43,25); Accent=[Drawing.Color]::FromArgb(217,119,6) },
        @{ Title=(Get-ToolText -Key "about.card.report.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.report.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(237,250,244); Dark=[Drawing.Color]::FromArgb(25,51,43); Accent=[Drawing.Color]::FromArgb(5,150,105) },
        @{ Title=(Get-ToolText -Key "about.card.assurance.title" -Culture $script:dashboardCulture); Body=(Get-ToolText -Key "about.card.assurance.body" -Culture $script:dashboardCulture); Light=[Drawing.Color]::FromArgb(247,241,255); Dark=[Drawing.Color]::FromArgb(48,37,64); Accent=[Drawing.Color]::FromArgb(124,58,237) }
    )
    for ($featureIndex = 0; $featureIndex -lt $featureDefinitions.Count; $featureIndex++) {
        $feature = $featureDefinitions[$featureIndex]
        $card = New-Object System.Windows.Forms.Panel
        $card.Dock = "Fill"
        $card.Margin = New-Object System.Windows.Forms.Padding(5)
        $featureSurface = if ($dark) { $feature.Dark } else { $feature.Light }
        $card.BackColor = $featureSurface
        $card.BorderStyle = "FixedSingle"

        $cardLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $cardLayout.Dock = "Fill"
        $cardLayout.BackColor = $featureSurface
        $cardLayout.Padding = New-Object System.Windows.Forms.Padding(17, 9, 12, 8)
        $cardLayout.ColumnCount = 1
        $cardLayout.RowCount = 2
        [void]$cardLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$cardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
        [void]$cardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $card.Controls.Add($cardLayout)

        $cardTitle = New-Object System.Windows.Forms.Label
        $cardTitle.Text = [string]$feature.Title
        $cardTitle.Font = $fontBold
        $cardTitle.ForeColor = $primary
        $cardTitle.UseMnemonic = $false
        $cardTitle.Dock = "Fill"
        $cardTitle.TextAlign = "MiddleLeft"
        $cardLayout.Controls.Add($cardTitle, 0, 0)

        $cardBody = New-Object System.Windows.Forms.Label
        $cardBody.Text = [string]$feature.Body
        $cardBody.Font = $fontNormal
        $cardBody.ForeColor = $text
        $cardBody.Dock = "Fill"
        $cardBody.TextAlign = "TopLeft"
        $cardBody.UseCompatibleTextRendering = $false
        $cardLayout.Controls.Add($cardBody, 0, 1)

        $featureAccent = New-Object System.Windows.Forms.Panel
        $featureAccent.Dock = "Left"
        $featureAccent.Width = 5
        $featureAccent.BackColor = $feature.Accent
        $card.Controls.Add($featureAccent)
        $featureAccent.BringToFront()

        $featureGrid.Controls.Add($card, ($featureIndex % 2), [Math]::Floor($featureIndex / 2))
    }

    $note = New-Object System.Windows.Forms.Label
    $note.Text = Get-ToolText -Key "about.note" -Culture $script:dashboardCulture
    $note.Font = $fontSmall
    $note.ForeColor = $muted
    $note.Dock = "Fill"
    $note.TextAlign = "MiddleLeft"
    $note.AutoEllipsis = $true
    $note.Margin = New-Object System.Windows.Forms.Padding(6, 1, 6, 1)
    $featureGrid.Controls.Add($note, 0, 2)
    $featureGrid.SetColumnSpan($note, 2)

    $buttonBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonBar.Dock = "Fill"
    $buttonBar.FlowDirection = "RightToLeft"
    $buttonBar.WrapContents = $false
    $buttonBar.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $layout.Controls.Add($buttonBar, 0, 2)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
    $close.Font = $fontBold
    $close.Size = New-Object System.Drawing.Size(108, 30)
    $close.BackColor = $primary
    $close.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $close.FlatStyle = "Flat"
    $close.FlatAppearance.BorderSize = 0
    $close.Add_Click({ $dialog.Close() })
    $buttonBar.Controls.Add($close)

    $guide = New-Object System.Windows.Forms.Button
    $guide.Text = Get-ToolText -Key "about.openGuide" -Culture $script:dashboardCulture
    $guide.Font = $fontBold
    $guide.Size = New-Object System.Drawing.Size(126, 30)
    $guide.BackColor = $surface
    $guide.ForeColor = $text
    $guide.FlatStyle = "Flat"
    $guide.Add_Click({ Open-Guide })
    $buttonBar.Controls.Add($guide)

    $history = New-Object System.Windows.Forms.Button
    $history.Text = Get-ToolText -Key "about.openHistory" -Culture $script:dashboardCulture
    $history.Font = $fontBold
    $history.Size = New-Object System.Drawing.Size(174, 30)
    $history.BackColor = $surface
    $history.ForeColor = $text
    $history.FlatStyle = "Flat"
    $history.Add_Click({ Open-VersionHistory })
    $buttonBar.Controls.Add($history)

    $dialog.AcceptButton = $close
    $dialog.CancelButton = $close
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $dialog.Dispose()
    $productHeadingFont.Dispose()
}

function Get-DashboardMenuText {
    param([Parameter(Mandatory = $true)]$Metadata)
    $number = "{0:00}" -f [int]$Metadata.Number
    $titleText = Get-ToolText -Key ([string]$Metadata.TitleKey) -Culture $script:dashboardCulture
    $descriptionText = Get-ToolText -Key ([string]$Metadata.DescriptionKey) -Culture $script:dashboardCulture
    return "$number  $titleText`r`n     $descriptionText"
}

function Update-DashboardOfflineUi {
    $offlineKey = if ($script:offlineMode) { "app.offline.enabled" } else { "app.offline.disabled" }
    $offlineButton.Text = Get-ToolText -Key $offlineKey -Culture $script:dashboardCulture
    $toolTip.SetToolTip($offlineButton, (Get-ToolText -Key $(if ($script:offlineMode) { "app.offline.disable" } else { "app.offline.enable" }) -Culture $script:dashboardCulture))
}

function Toggle-DashboardOfflineMode {
    if ($script:offlineMode) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "app.offline.confirm" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "app.offline.confirmTitle" -Culture $script:dashboardCulture),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:offlineMode = $false
    } else {
        $script:offlineMode = $true
    }
    [void](Set-ToolOfflineModePreference -OfflineMode $script:offlineMode)
    $env:TOOL_OFFLINE_MODE = if ($script:offlineMode) { "1" } else { "0" }
    Update-DashboardOfflineUi
    Set-DashboardTheme -Mode $script:dashboardTheme
    [void](Write-ToolLog -Level "AUDIT" -Event "OfflineMode.Changed" -Message $(if ($script:offlineMode) { "Đã bật chế độ Offline." } else { "Người dùng đã chủ động cho phép chức năng mạng." }) -Data ([ordered]@{ OfflineMode=[bool]$script:offlineMode }))
}

function Set-DashboardLanguage {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)

    $script:dashboardCulture = $Culture
    $env:TOOL_UI_CULTURE = $Culture
    [void](Set-ToolCulturePreference -Culture $Culture)
    $form.Text = "$(Get-ToolText -Key "app.title" -Culture $Culture) - $releaseDisplayName"
    $title.Text = Get-ToolText -Key "app.title" -Culture $Culture
    $developer.Text = Get-ToolText -Key "app.developer" -Culture $Culture
    $description.Text = Get-ToolText -Key "app.hero.title" -Culture $Culture
    $introSummary.Text = Get-ToolText -Key "app.hero.summary" -Culture $Culture
    $introDetailButton.Text = Get-ToolText -Key "app.about" -Culture $Culture
    $menuCaption.Text = Get-ToolText -Key "dashboard.functions" -Culture $Culture
    $closeButton.Text = Get-ToolText -Key "app.close" -Culture $Culture
    $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $Culture
    $copyLogButton.Text = Get-ToolText -Key "progress.copyAllLog" -Culture $Culture
    $openReportFolderButton.Text = Get-ToolText -Key "report.openFolder" -Culture $Culture
    $progressCaption.Text = Get-ToolText -Key "progress.caption" -Culture $Culture

    $dashboardCards["Compatibility"].Caption.Text = Get-ToolText -Key "dashboard.windows" -Culture $Culture
    $dashboardCards["Architecture"].Caption.Text = Get-ToolText -Key "dashboard.office" -Culture $Culture
    $dashboardCards["SecureLaunch"].Caption.Text = Get-ToolText -Key "dashboard.runMode" -Culture $Culture
    $dashboardCards["Integrity"].Caption.Text = Get-ToolText -Key "dashboard.integrity" -Culture $Culture
    $dashboardCards["SecureLaunch"].Value.Text = if ($env:TOOL_SECURE_LAUNCH -eq "1") {
        Get-ToolText -Key "dashboard.secure" -Culture $Culture
    } else {
        Get-ToolText -Key "dashboard.source" -Culture $Culture
    }
    if ($script:lastIntegrityResult) {
        $dashboardCards["Integrity"].Value.Text = if ($script:lastIntegrityResult.Valid) {
            Get-ToolText -Key "dashboard.integrity.ok" -Culture $Culture -FormatArguments @($safetyPolicyState.RegistryValuePolicyCount)
        } else {
            Get-ToolText -Key "dashboard.integrity.failed" -Culture $Culture
        }
    }
    foreach ($button in $buttons) {
        $metadata = $button.Tag
        if ($metadata -and $metadata.PSObject.Properties["TitleKey"]) {
            $button.Text = Get-DashboardMenuText -Metadata $metadata
            $toolTip.SetToolTip($button, (Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture))
        }
    }
    Update-DashboardOfflineUi
    Set-DashboardTheme -Mode $script:dashboardTheme
    Update-MainLayout
    Refresh-DashboardLocalizedActivity
    [void](Write-ToolLog -Level "INFO" -Event "Culture.Changed" -Message "Dashboard culture: $Culture." -Data ([ordered]@{ Culture=$Culture }))
}

function Get-DashboardTilePalette {
    param(
        [ValidateSet("Normal", "Warning", "Enterprise")][string]$Tone = "Normal",
        [ValidateSet("Light", "Dark")][string]$Mode = "Light",
        [switch]$Hover
    )

    $dark = [bool]($Mode -eq "Dark")
    if ($Tone -eq "Enterprise") {
        return [pscustomobject]@{
            BackColor = if ($dark) {
                if ($Hover) { [System.Drawing.Color]::FromArgb(34, 91, 78) } else { [System.Drawing.Color]::FromArgb(26, 72, 62) }
            } else {
                if ($Hover) { [System.Drawing.Color]::FromArgb(210, 240, 226) } else { [System.Drawing.Color]::FromArgb(232, 247, 240) }
            }
            ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(139, 233, 190) } else { [System.Drawing.Color]::FromArgb(14, 111, 78) }
        }
    }
    if ($Tone -eq "Warning") {
        return [pscustomobject]@{
            BackColor = if ($dark) {
                if ($Hover) { [System.Drawing.Color]::FromArgb(94, 70, 35) } else { [System.Drawing.Color]::FromArgb(78, 57, 30) }
            } else {
                if ($Hover) { [System.Drawing.Color]::FromArgb(250, 235, 199) } else { [System.Drawing.Color]::FromArgb(255, 248, 230) }
            }
            ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(255, 199, 117) } else { [System.Drawing.Color]::FromArgb(128, 64, 0) }
        }
    }
    return [pscustomobject]@{
        BackColor = if ($dark) {
            if ($Hover) { [System.Drawing.Color]::FromArgb(48, 64, 88) } else { [System.Drawing.Color]::FromArgb(36, 48, 67) }
        } else {
            if ($Hover) { [System.Drawing.Color]::FromArgb(224, 237, 253) } else { [System.Drawing.Color]::FromArgb(241, 247, 255) }
        }
        ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(124, 174, 255) } else { [System.Drawing.Color]::FromArgb(22, 72, 132) }
    }
}

function Set-DashboardTheme {
    param([ValidateSet("Light", "Dark")][string]$Mode)
    $env:TOOL_UI_THEME = $Mode
    $script:toolUiPalette = Get-ToolUiPalette -Mode $Mode
    $dark = [bool]($Mode -eq "Dark")
    $surface = if ($dark) { [System.Drawing.Color]::FromArgb(29, 34, 45) } else { [System.Drawing.Color]::White }
    $background = if ($dark) { [System.Drawing.Color]::FromArgb(15, 19, 27) } else { [System.Drawing.Color]::FromArgb(239, 243, 248) }
    $primary = if ($dark) { [System.Drawing.Color]::FromArgb(124, 174, 255) } else { [System.Drawing.Color]::FromArgb(22, 72, 132) }
    $text = if ($dark) { [System.Drawing.Color]::FromArgb(226, 231, 239) } else { [System.Drawing.Color]::FromArgb(52, 64, 84) }
    $muted = if ($dark) { [System.Drawing.Color]::FromArgb(164, 174, 192) } else { [System.Drawing.Color]::FromArgb(102, 112, 133) }
    $introSurface = if ($dark) { [System.Drawing.Color]::FromArgb(30, 44, 65) } else { [System.Drawing.Color]::FromArgb(235, 244, 255) }

    $form.BackColor = $background
    $title.ForeColor = $primary
    $developer.ForeColor = $primary
    $version.ForeColor = $muted
    $introPanel.BackColor = $introSurface
    $introAccent.BackColor = $primary
    $description.ForeColor = $primary
    $introSummary.ForeColor = $text
    $introDetailButton.BackColor = $primary
    $introDetailButton.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $dashboardPanel.BackColor = $background
    $buttonPanel.BackColor = $surface
    $menuCaption.ForeColor = $primary
    $progressCaption.ForeColor = $primary
    $elapsedLabel.ForeColor = $muted
    $progressLog.BackColor = $surface
    $progressLog.ForeColor = $text
    $closeButton.BackColor = $surface
    $closeButton.ForeColor = $text
    $stopButton.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(139, 43, 52) } else { [System.Drawing.Color]::FromArgb(185, 28, 28) }
    $stopButton.ForeColor = [System.Drawing.Color]::White
    $copyLogButton.BackColor = $surface
    $copyLogButton.ForeColor = $text
    $openReportFolderButton.BackColor = $surface
    $openReportFolderButton.ForeColor = $text
    $themeButton.BackColor = $surface
    $themeButton.ForeColor = $text
    $themeButton.Text = Get-ToolText -Key $(if ($dark) { "app.theme.light" } else { "app.theme.dark" }) -Culture $script:dashboardCulture
    $languageCombo.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(38, 44, 57) } else { [System.Drawing.Color]::White }
    $languageCombo.ForeColor = $text
    $offlineButton.BackColor = if ($script:offlineMode) {
        if ($dark) { [System.Drawing.Color]::FromArgb(24, 91, 66) } else { [System.Drawing.Color]::FromArgb(222, 246, 235) }
    } else {
        if ($dark) { [System.Drawing.Color]::FromArgb(94, 62, 23) } else { [System.Drawing.Color]::FromArgb(255, 241, 218) }
    }
    $offlineButton.ForeColor = if ($script:offlineMode) {
        if ($dark) { [System.Drawing.Color]::FromArgb(139, 233, 190) } else { [System.Drawing.Color]::FromArgb(15, 111, 74) }
    } else {
        if ($dark) { [System.Drawing.Color]::FromArgb(255, 200, 122) } else { [System.Drawing.Color]::FromArgb(135, 76, 0) }
    }

    foreach ($card in $dashboardCardPanels) {
        $card.BackColor = $surface
        if ($card.Controls.Count -ge 2) {
            $card.Controls[0].ForeColor = $muted
            if ($card.Controls[1].Tag -ne "StatusColor") { $card.Controls[1].ForeColor = $primary }
        }
        foreach ($child in $card.Controls) {
            if ([string]$child.Tag -eq "CardAccent") { $child.BackColor = $primary }
        }
    }
    foreach ($button in $buttons) {
        $tone = if ($button.Tag -and $button.Tag.PSObject.Properties["Tone"]) { [string]$button.Tag.Tone } else { "Normal" }
        $tilePalette = Get-DashboardTilePalette -Tone $tone -Mode $Mode
        $button.BackColor = $tilePalette.BackColor
        $button.ForeColor = $tilePalette.ForeColor
    }

    $neutralLightArgb = [System.Drawing.Color]::FromArgb(52, 64, 84).ToArgb()
    $neutralDarkArgb = [System.Drawing.Color]::FromArgb(226, 231, 239).ToArgb()
    if ($status.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb)) { $status.ForeColor = $text }
    if ($activityLabel.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb, [System.Drawing.Color]::FromArgb(18, 59, 116).ToArgb(), [System.Drawing.Color]::FromArgb(126, 174, 255).ToArgb())) { $activityLabel.ForeColor = $text }
    Register-ToolUiDynamicContrast -Root $form -Mode $Mode
    $form.Invalidate($true)
}

function Update-DashboardStatus {
    param($IntegrityResult)
    $script:lastIntegrityResult = $IntegrityResult
    $dashboardCards["Compatibility"].Value.Text = [string]$capabilityState.WindowsReleaseName
    $dashboardCards["Architecture"].Value.Text = [string]$capabilityState.OfficeSummary
    $dashboardCards["SecureLaunch"].Value.Text = if ($env:TOOL_SECURE_LAUNCH -eq "1") { Get-ToolText -Key "dashboard.secure" -Culture $script:dashboardCulture } else { Get-ToolText -Key "dashboard.source" -Culture $script:dashboardCulture }
    $dashboardCards["Integrity"].Value.Text = if ($IntegrityResult.Valid) {
        Get-ToolText -Key "dashboard.integrity.ok" -Culture $script:dashboardCulture -FormatArguments @($safetyPolicyState.RegistryValuePolicyCount)
    } else {
        Get-ToolText -Key "dashboard.integrity.failed" -Culture $script:dashboardCulture
    }
    $dashboardCards["Integrity"].Value.ForeColor = if ($IntegrityResult.Valid) { [System.Drawing.Color]::FromArgb(28, 125, 69) } else { [System.Drawing.Color]::DarkOrange }
    $dashboardCards["Integrity"].Value.Tag = "StatusColor"
    $dashboardCards["SecureLaunch"].Value.ForeColor = if ($env:TOOL_SECURE_LAUNCH -eq "1") { [System.Drawing.Color]::FromArgb(28, 125, 69) } else { [System.Drawing.Color]::DarkOrange }
    $dashboardCards["SecureLaunch"].Value.Tag = "StatusColor"
    Update-DashboardOfflineUi
}

function Get-ApprovedKmsEntries {
    $entries = New-Object System.Collections.Generic.List[string]
    $invalid = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $approvedKmsFile -PathType Leaf)) {
        return [pscustomobject]@{ Exists=$false; Entries=@(); Invalid=@(); Path=$approvedKmsFile }
    }
    try {
        foreach ($line in Get-Content -LiteralPath $approvedKmsFile -ErrorAction Stop) {
            $value = ([string]$line).Trim()
            if (-not $value -or $value.StartsWith('#')) { continue }
            $candidate = $value -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
            $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
            if ($candidate -match '^[a-zA-Z0-9][a-zA-Z0-9._-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9._-]*)*$' -or
                $candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$' -or
                $candidate -match '^[0-9a-fA-F:]+$') {
                [void]$entries.Add($value)
            } else {
                [void]$invalid.Add($value)
            }
        }
    } catch { [void]$invalid.Add("Không đọc được file: $($_.Exception.Message)") }
    return [pscustomobject]@{ Exists=$true; Entries=@($entries | Select-Object -Unique); Invalid=@($invalid); Path=$approvedKmsFile }
}

function Get-DetectedKmsServers {
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform',
        'HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform'
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach ($name in @('KeyManagementServiceName','DiscoveredKeyManagementServiceName')) {
                $value = [string]$item.$name
                if ($value -and $value -notmatch '^(localhost|127\.0\.0\.1|::1)$') { [void]$found.Add($value.Trim()) }
            }
        } catch {}
    }
    try {
        $slmgr = Get-ToolNativeSystemPath 'slmgr.vbs'
        if (Test-Path -LiteralPath $slmgr) {
            $text = (& $nativeCscriptPath //nologo $slmgr /dlv 2>$null) -join "`n"
            foreach ($pattern in @('(?im)^\s*KMS machine name from DNS:\s*(.+)$','(?im)^\s*Key Management Service machine name:\s*(.+)$','(?im)^\s*KMS machine IP address:\s*(.+)$')) {
                if ($text -match $pattern -and $matches[1].Trim() -notmatch '^(not available|localhost)$') { [void]$found.Add($matches[1].Trim()) }
            }
        }
    } catch {}
    return @($found | Where-Object { $_ } | Select-Object -Unique)
}

function Normalize-KmsServer([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $candidate = $value.Trim().ToLowerInvariant()
    $candidate = $candidate -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
    $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
    return $candidate
}

function Test-DetectedKmsIsApproved([string]$server, [string[]]$approved) {
    $candidate = Normalize-KmsServer $server
    if (-not $candidate) { return $false }
    foreach ($entry in @($approved)) {
        if ($candidate -eq (Normalize-KmsServer $entry)) { return $true }
    }
    return $false
}

function Save-ApprovedKmsEntries([string[]]$entries) {
    try {
        $parent = Split-Path -Parent $approvedKmsFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $content = @(
            '# Danh sach KMS noi bo da duoc co quan/doanh nghiep phe duyet.'
            '# Moi dong mot ten DNS hoac IP; khong tu dong phe duyet may chu.'
            '# Cap nhat: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            @($entries | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
        )
        Set-Content -LiteralPath $approvedKmsFile -Value $content -Encoding UTF8 -Force
        if ($approvedKmsFile -ne $bundledApprovedKmsFile) {
            Set-Content -LiteralPath $bundledApprovedKmsFile -Value $content -Encoding UTF8 -Force
        }
        [void](Write-LicenseTimelineEventSafe -EventType "ApprovedKmsListUpdated" -Source "GUI" -IsChange:$true -Data ([ordered]@{
            ApprovedServerCount=@($entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique).Count
            ServerNamesStoredInTimeline=$false
        }))
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Không thể lưu danh sách KMS được phê duyệt:`r`n$($_.Exception.Message)", "Không lưu được", "OK", "Error") | Out-Null
        return $false
    }
}

function Confirm-KmsApprovalConfiguration {
    $config = Get-ApprovedKmsEntries
    $detected = @(Get-DetectedKmsServers)
    $unapprovedDetected = @($detected | Where-Object { -not (Test-DetectedKmsIsApproved $_ $config.Entries) })
    if ($config.Entries.Count -gt 0 -and $config.Invalid.Count -eq 0 -and $unapprovedDetected.Count -eq 0) { return $true }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Xác nhận máy chủ KMS hợp lệ"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false; $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(670, 390)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244,246,249); $dialog.Font = $fontNormal
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "CẢNH BÁO: danh sách KMS được phê duyệt chưa hoàn chỉnh"
    $heading.Font = $fontBold; $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.Location = New-Object System.Drawing.Point(18, 14); $heading.Size = New-Object System.Drawing.Size(630, 26)
    $dialog.Controls.Add($heading)
    $info = New-Object System.Windows.Forms.Label
    $detectedText = if ($detected.Count) { $detected -join ', ' } else { 'Chưa phát hiện máy chủ KMS cục bộ.' }
    $unapprovedText = if ($unapprovedDetected.Count) { "`r`nMáy chủ chưa khớp danh sách: $($unapprovedDetected -join ', ')" } else { '' }
    $info.Text = "KMS phát hiện trên máy: $detectedText$unapprovedText`r`nNếu đây là KMS của cơ quan/doanh nghiệp, chỉ thêm tên/IP sau khi quản trị viên xác nhận. Tool không tự phê duyệt và không gửi dữ liệu ra Internet. Danh sách trống sẽ khiến mục 6 coi KMS là chưa phê duyệt."
    $info.Location = New-Object System.Drawing.Point(18, 48); $info.Size = New-Object System.Drawing.Size(630, 70)
    $dialog.Controls.Add($info)
    $editor = New-Object System.Windows.Forms.TextBox
    $editor.Multiline = $true; $editor.ScrollBars = 'Vertical'; $editor.Font = $fontSmall
    $editor.Location = New-Object System.Drawing.Point(18, 126); $editor.Size = New-Object System.Drawing.Size(630, 125)
    $editor.Text = (@($config.Entries) -join [Environment]::NewLine)
    $dialog.Controls.Add($editor)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Mỗi dòng một hostname/IP (có thể kèm :1688). Không nhập máy chủ Internet hoặc máy chưa được phê duyệt."
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(102,112,133); $hint.Location = New-Object System.Drawing.Point(18, 258); $hint.Size = New-Object System.Drawing.Size(630, 22)
    $dialog.Controls.Add($hint)
    $open = New-Object System.Windows.Forms.Button; $open.Text = 'Mở file cấu hình'; $open.Location = New-Object System.Drawing.Point(18, 302); $open.Size = New-Object System.Drawing.Size(125, 34)
    $open.Add_Click({ Start-Process -FilePath $nativeNotepadPath -ArgumentList ('"' + $approvedKmsFile + '"') }); $dialog.Controls.Add($open)
    $strict = New-Object System.Windows.Forms.Button; $strict.Text = 'Tiếp tục nghiêm ngặt'; $strict.Location = New-Object System.Drawing.Point(155, 302); $strict.Size = New-Object System.Drawing.Size(145, 34)
    $strict.Add_Click({ $dialog.Tag = 'Strict'; $dialog.Close() }); $dialog.Controls.Add($strict)
    $save = New-Object System.Windows.Forms.Button; $save.Text = 'Lưu và tiếp tục'; $save.Font = $fontBold; $save.Location = New-Object System.Drawing.Point(315, 302); $save.Size = New-Object System.Drawing.Size(145, 34)
    $save.Add_Click({ $dialog.Tag = 'Save'; $dialog.Close() }); $dialog.Controls.Add($save)
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Thoát'; $cancel.Location = New-Object System.Drawing.Point(507, 302); $cancel.Size = New-Object System.Drawing.Size(141, 34)
    $cancel.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() }); $dialog.CancelButton = $cancel; $dialog.Controls.Add($cancel)
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag; $entriesToSave = @($editor.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $dialog.Dispose()
    if ($choice -eq 'Save') {
        if ($entriesToSave.Count -eq 0) {
            $confirm = [System.Windows.Forms.MessageBox]::Show('Bạn đang lưu danh sách rỗng. Mục 6 sẽ coi mọi KMS là chưa phê duyệt. Tiếp tục?', 'Xác nhận danh sách rỗng', 'YesNo', 'Warning')
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
        }
        if (-not (Save-ApprovedKmsEntries $entriesToSave)) { return $false }
        Write-ProgressLog "Đã cập nhật danh sách KMS được phê duyệt: $approvedKmsFile"
        return $true
    }
    if ($choice -eq 'Strict') { Write-ProgressLog 'Tiếp tục theo chế độ nghiêm ngặt: KMS ngoài danh sách sẽ bị xem là chưa phê duyệt.'; return $true }
    return $false
}

function Get-Sha256([string]$path) {
    try {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
        $stream = [IO.File]::OpenRead($path)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant()
        } finally {
            $stream.Dispose()
        }
    } catch { return "" }
}

function Get-AccountSid([string]$accountName) {
    try {
        return (New-Object Security.Principal.NTAccount($accountName)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return "" }
}

function Test-ProtectedToolDirectoryAcl([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        $ownerSid = Get-AccountSid ([string]$acl.Owner)
        if ($ownerSid -notin @("S-1-5-32-544", "S-1-5-18") -or -not $acl.AreAccessRulesProtected) { return $false }
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
            [Security.AccessControl.FileSystemRights]::Modify -bor
            [Security.AccessControl.FileSystemRights]::FullControl -bor
            [Security.AccessControl.FileSystemRights]::Delete -bor
            [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
            [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $allowedWriters -notcontains $rule.IdentityReference.Value -and
                (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Test-ToolIntegrity {
    # approved-kms-servers.txt được loại khỏi manifest vì đây là tệp cấu hình
    # do quản trị viên được phép sửa. Mọi thao tác có quyền cao đều kiểm tra lại.
    if (-not (Test-Path -LiteralPath $integrityManifest)) {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message="Không tìm thấy manifest SHA-256 của bộ tool." }
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $required = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($requiredName in $requiredIntegrityFiles) { [void]$required.Add($requiredName) }
    try {
        foreach ($line in Get-Content -LiteralPath $integrityManifest -ErrorAction Stop) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
            if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
                $problems.Add("Dòng manifest không hợp lệ: $line")
                continue
            }
            $expected = $matches[1].ToUpperInvariant()
            $relativeName = $matches[2].Trim()
            if ([IO.Path]::GetFileName($relativeName) -ne $relativeName -or $relativeName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                $problems.Add("Tên tệp không an toàn trong manifest: $relativeName")
                continue
            }
            if (-not $required.Contains($relativeName)) {
                $problems.Add("Tệp ngoài danh sách bắt buộc: $relativeName")
                continue
            }
            if (-not $seen.Add($relativeName)) {
                $problems.Add("Tệp bị lặp trong manifest: $relativeName")
                continue
            }
            $target = Join-Path $baseDir $relativeName
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $problems.Add("Thiếu tệp: $relativeName")
                continue
            }
            $actual = Get-Sha256 $target
            if (-not $actual -or $actual -ne $expected) { $problems.Add("Sai SHA-256: $relativeName") }
        }
        foreach ($requiredName in $requiredIntegrityFiles) {
            if (-not $seen.Contains($requiredName)) { $problems.Add("Thiếu dòng bắt buộc: $requiredName") }
        }
    } catch {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message="Không đọc được manifest SHA-256: $($_.Exception.Message)" }
    }
    if ($problems.Count -eq 0) {
        return [pscustomobject]@{ Checked=$true; Valid=$true; Message="Toàn vẹn bộ tool: Đạt." }
    }
    return [pscustomobject]@{ Checked=$true; Valid=$false; Message=("Cảnh báo toàn vẹn: " + ($problems -join '; ')) }
}

function New-SecureRuntimePath([string]$prefix) {
    if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
    }
    return (Join-Path $runtimeDir ($prefix + [guid]::NewGuid().ToString("N") + ".json"))
}

function Confirm-IntegrityForElevatedAction([string]$actionName) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or
        -not (Test-ProtectedToolDirectoryAcl $baseDir) -or
        -not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.adminSourceBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.adminBlockedTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
        return $false
    }
    if ($env:TOOL_SECURE_RUNTIME_FAILED -eq "1") {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.runtimeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.protectionTitle" -Culture $script:dashboardCulture),
            "OK",
            "Error"
        ) | Out-Null
        return $false
    }
    $freshResult = Test-ToolIntegrity
    if ($freshResult.Valid) { return $true }
    Write-ProgressLog "ĐÃ KHÓA ${actionName}: $($freshResult.Message)"
    $status.Text = Get-ToolText -Key "integrity.statusBlocked" -Culture $script:dashboardCulture
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "integrity.actionBlocked" -Culture $script:dashboardCulture -FormatArguments @($actionName, $freshResult.Message)),
        (Get-ToolText -Key "integrity.protectionTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    return $false
}

function Write-ProgressLog([string]$message) {
    $stamp = (Get-Date).ToString("HH:mm:ss")
    if ($progressLog.TextLength -gt 0) { [void]$progressLog.AppendText([Environment]::NewLine) }
    [void]$progressLog.AppendText("[$stamp] $message")
    $progressLog.SelectionStart = $progressLog.TextLength
    $progressLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-DashboardLocalizedActivity {
    if (-not $script:hasTaskActivity) {
        $status.Text = ""
        $activityLabel.Text = ""
        $elapsedLabel.Text = ""
        $progressLog.Clear()
        return
    }
    if (-not $script:activeProcess) { $activityLabel.Text = $status.Text }
}

function Write-LicenseTimelineEventSafe {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$Source,
        [AllowNull()][object]$Data = $null,
        [bool]$IsChange = $false
    )

    if (-not $timelineState.Enabled) {
        return [pscustomobject]@{ Written=$false; Error=[string]$timelineState.Error }
    }
    try {
        return Write-ToolLicenseTimelineEvent -EventType $EventType -Source $Source -Data $Data -IsChange:$IsChange
    } catch {
        $message = "Timeline từ chối ghi thêm: $($_.Exception.Message)"
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $message -Data ([ordered]@{ EventType=$EventType; Source=$Source }))
        Write-ProgressLog "CẢNH BÁO: $message"
        return [pscustomobject]@{ Written=$false; Error=$_.Exception.Message }
    }
}

function Start-ProgressDisplay([string]$action, [string]$detail, [bool]$preserveLog) {
    if (-not $preserveLog) { $progressLog.Clear() }
    $script:hasTaskActivity = $true
    $script:taskCancellationRequested = $false
    $script:taskStartedAt = Get-Date
    $script:lastProgressHeartbeat = 0
    $script:progressTick = 0
    $script:progressPhase = 0
    $activityLabel.Text = $detail
    $activityLabel.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $elapsedLabel.Text = "00:00"
    $progressBar.Value = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progressBar.MarqueeAnimationSpeed = 24
    Update-MainLayout
    Write-ProgressLog (Get-ToolText -Key "progress.started" -Culture $script:dashboardCulture -FormatArguments @($action))
    [void](Write-ToolLog -Level "INFO" -Event "Action.Start" -Message $action -Data ([ordered]@{
        Detail = $detail
        CompatibilityTier = $capabilityState.CompatibilityTier
    }))
}

function Stop-ProgressDisplay([string]$summary) {
    $durationMs = $null
    if ($script:taskStartedAt) {
        $elapsed = (Get-Date) - $script:taskStartedAt
        $durationMs = [long][Math]::Round($elapsed.TotalMilliseconds)
        $elapsedLabel.Text = "{0:00}:{1:00}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
    }
    $script:taskStartedAt = $null
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.Value = 100
    $activityLabel.Text = $summary
    $activityLabel.ForeColor = $status.ForeColor
    [void](Write-ToolLog -Level "INFO" -Event "Action.DisplayStopped" -Message $summary -DurationMs $durationMs)
}

function Reset-IdleTaskDisplay {
    $script:hasTaskActivity = $false
    $script:taskCancellationRequested = $false
    $status.Text = ""
    $activityLabel.Text = ""
    $elapsedLabel.Text = ""
    $progressBar.MarqueeAnimationSpeed = 0
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $progressBar.Value = 0
    $progressLog.Clear()
    $stopButton.Visible = $false
    $stopButton.Enabled = $false
    Update-MainLayout
}

function Stop-ProgressOnStartError([string]$message) {
    $status.Text = $message
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    Write-ProgressLog $message
    [void](Write-ToolLog -Level "ERROR" -Event "Action.StartFailed" -Message $message)
    Stop-ProgressDisplay $message
}

function Stop-ProgressIfIdle {
    if (-not $script:activeProcess) { Stop-ProgressDisplay $status.Text }
}

$integrityResult = Test-ToolIntegrity
[void](Write-ToolLog -Level "INFO" -Event "Application.Start" -Message "Dashboard đã khởi động." -Data ([ordered]@{
    DashboardSchemaVersion = $dashboardSchemaVersion
    ReportSchemaVersion = $reportSchemaState.SchemaVersion
    SafetyPolicySchemaVersion = $safetyPolicyState.SchemaVersion
    CompatibilitySchemaVersion = $compatibilityState.SchemaVersion
    LocalizationSchemaVersion = $localizationState.SchemaVersion
    OfflinePolicySchemaVersion = $offlinePolicyState.SchemaVersion
    Culture = $script:dashboardCulture
    OfflineMode = [bool]$script:offlineMode
    Capabilities = $capabilityState
}))
Update-DashboardStatus -IntegrityResult $integrityResult
Refresh-DashboardLocalizedActivity
if (-not $loggingState.Enabled) {
    Write-ProgressLog "$(if ($script:dashboardCulture -eq 'en-US') { 'LOG WARNING' } else { 'CẢNH BÁO LOG' }): $($loggingState.Error)"
}
if (-not $timelineState.Enabled) {
    Write-ProgressLog "$(if ($script:dashboardCulture -eq 'en-US') { 'TIMELINE WARNING' } else { 'CẢNH BÁO TIMELINE' }): $($timelineState.Error)"
} else {
    $timelineCheck = Get-ToolLicenseTimeline
    Write-ProgressLog $(if ($timelineCheck.Valid) {
        Get-ToolText -Key "progress.timeline.valid" -Culture $script:dashboardCulture -FormatArguments @($timelineCheck.RecordCount, $timelineCheck.ChangeCount)
    } else {
        Get-ToolText -Key "progress.timeline.invalid" -Culture $script:dashboardCulture
    })
}
if (-not $integrityResult.Valid) {
    $status.Text = Get-ToolText -Key "progress.integrity.locked" -Culture $script:dashboardCulture
    $status.ForeColor = [System.Drawing.Color]::DarkOrange
}
$kmsConfigAtStartup = Get-ApprovedKmsEntries
if (-not $kmsConfigAtStartup.Exists -or $kmsConfigAtStartup.Entries.Count -eq 0) {
    Write-ProgressLog (Get-ToolText -Key "progress.kms.missing" -Culture $script:dashboardCulture)
} elseif ($kmsConfigAtStartup.Invalid.Count -gt 0) {
    Write-ProgressLog (Get-ToolText -Key "progress.kms.invalid" -Culture $script:dashboardCulture -FormatArguments @($kmsConfigAtStartup.Invalid.Count))
} else {
    Write-ProgressLog (Get-ToolText -Key "progress.kms.approved" -Culture $script:dashboardCulture -FormatArguments @($kmsConfigAtStartup.Entries.Count))
}
Reset-IdleTaskDisplay

function Set-ButtonsEnabled([bool]$enabled) {
    foreach ($button in $buttons) { $button.Enabled = $enabled }
    $canStop = [bool]((-not $enabled) -and $script:activeProcess -and -not $script:activeProcess.HasExited)
    $stopButton.Visible = $canStop
    $stopButton.Enabled = $canStop
    $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
    Update-MainLayout
}

function Stop-ActiveTask {
    if (-not $script:activeProcess -or $script:activeProcess.HasExited) {
        Set-ButtonsEnabled $true
        return
    }

    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "progress.stopConfirm" -Culture $script:dashboardCulture),
        (Get-ToolText -Key "progress.stopTitle" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:taskCancellationRequested = $true
    $stopButton.Enabled = $false
    $stopButton.Text = Get-ToolText -Key "progress.stopping" -Culture $script:dashboardCulture
    $activityLabel.Text = Get-ToolText -Key "progress.stopping" -Culture $script:dashboardCulture
    Write-ProgressLog (Get-ToolText -Key "progress.stopRequested" -Culture $script:dashboardCulture)
    [void](Write-ToolLog -Level "WARN" -Event "Action.StopRequested" -Message $script:activeAction -Data ([ordered]@{
        ProcessId = [int]$script:activeProcess.Id
        TaskKind = [string]$script:activeTaskKind
        ModuleId = [string]$script:activeModuleId
    }))

    try {
        $taskKillPath = Get-ToolNativeSystemPath "taskkill.exe"
        if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
            $taskKillProcess = Start-Process -FilePath $taskKillPath -ArgumentList @('/PID', [string][int]$script:activeProcess.Id, '/T', '/F') -WindowStyle Hidden -Wait -PassThru
            if ($taskKillProcess.ExitCode -ne 0 -and -not $script:activeProcess.HasExited) {
                $script:activeProcess.Kill()
            }
        } else {
            $script:activeProcess.Kill()
        }
    } catch {
        $script:taskCancellationRequested = $false
        $stopButton.Enabled = $true
        $stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
        $message = Get-ToolText -Key "progress.stopFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
        Write-ProgressLog $message
        [void](Write-ToolLog -Level "ERROR" -Event "Action.StopFailed" -Message $message)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-ToolText -Key "progress.stopTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Get-ReadyToolModule([string]$moduleId, [bool]$elevatedLaunch) {
    $availability = Test-ToolModuleAvailability -ModuleId $moduleId -CapabilityProfile $capabilityState -SourceDirectory $baseDir
    if (-not $availability.Available) { throw "Mô-đun $moduleId không sẵn sàng. $($availability.Message)" }
    if ($availability.Descriptor.RequiresElevation -and -not $elevatedLaunch) { throw "Mô-đun $moduleId yêu cầu luồng nâng quyền." }
    return $availability.Descriptor
}

function Start-ToolModuleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Action,
        [switch]$Elevate,
        [switch]$Hidden
    )

    if ($script:activeProcess -and -not $script:activeProcess.HasExited) { throw "Một mô-đun khác đang chạy." }
    $descriptor = Get-ReadyToolModule -moduleId $ModuleId -elevatedLaunch ([bool]$Elevate)
    $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
    $previousModuleId = [string]$env:TOOL_MODULE_ID
    $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
    try {
        $env:TOOL_MODULE_ID = $descriptor.ModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
        $startParameters = @{
            FilePath = $toolPowerShellPath
            ArgumentList = $Arguments
            PassThru = $true
        }
        if ($Elevate) { $startParameters.Verb = "RunAs" }
        if ($Hidden) { $startParameters.WindowStyle = "Hidden" }
        $process = Start-Process @startParameters
        if (-not $process) { throw "Windows không trả về tiến trình mô-đun." }
    } finally {
        $env:TOOL_MODULE_ID = $previousModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
    }

    $script:activeProcess = $process
    $script:activeAction = $Action
    $script:activeTaskKind = $descriptor.TaskKind
    $script:activeModuleId = $descriptor.ModuleId
    $script:activeModuleInvocation = $invocation
    [void](Write-ToolLog -Level "AUDIT" -Event "Module.Start" -Message $Action -Data ([ordered]@{
        ModuleId = $descriptor.ModuleId
        InvocationId = $invocation.InvocationId
        AccessMode = $descriptor.AccessMode
        RequiresElevation = [bool]$descriptor.RequiresElevation
    }))
    return $process
}

function Start-DetachedToolModuleProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [switch]$Elevate
    )

    $descriptor = Get-ReadyToolModule -moduleId $ModuleId -elevatedLaunch ([bool]$Elevate)
    $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
    $previousModuleId = [string]$env:TOOL_MODULE_ID
    $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
    try {
        $env:TOOL_MODULE_ID = $descriptor.ModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
        $startParameters = @{ FilePath=$toolPowerShellPath; ArgumentList=$Arguments; PassThru=$true }
        if ($Elevate) { $startParameters.Verb = "RunAs" }
        $process = Start-Process @startParameters
        if (-not $process) { throw "Windows không trả về tiến trình mô-đun." }
    } finally {
        $env:TOOL_MODULE_ID = $previousModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
    }
    [void](Write-ToolLog -Level "AUDIT" -Event "Module.Launched" -Message $descriptor.DisplayName -Data ([ordered]@{
        ModuleId=$descriptor.ModuleId; InvocationId=$invocation.InvocationId; ProcessId=$process.Id
    }))
    [void](Write-LicenseTimelineEventSafe -EventType "ModuleLaunched" -Source "GUI" -IsChange:$false -Data ([ordered]@{
        ModuleId=$descriptor.ModuleId; InvocationId=$invocation.InvocationId; AccessMode=$descriptor.AccessMode
        ChangeCapable=[bool]($descriptor.AccessMode -eq "SystemChange")
    }))
    return $process
}

function Start-Report([string]$mode, [string]$displayName) {
    if (-not (Test-Path -LiteralPath $reportScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.missingModule" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "report.errorTitle" -Culture $script:dashboardCulture),
            "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "report.privacy.prompt" -Culture $script:dashboardCulture),
        (Get-ToolText -Key "report.privacy.title" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $redactSensitive = [bool]($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes)
    try {
        Start-ProgressDisplay $displayName (Get-ToolText -Key "report.starting" -Culture $script:dashboardCulture) $false
        Write-ProgressLog (Get-ToolText -Key $(if ($redactSensitive) { "report.redactedProgress" } else { "report.internalProgress" }) -Culture $script:dashboardCulture)
        $privacyArgument = if ($redactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$reportScript`" -OutputDir `"$desktop`" -Mode `"$mode`" -Culture `"$script:dashboardCulture`" -Pdf$privacyArgument"
        $moduleId = Get-ToolReportModuleId -Mode $mode
        [void](Start-ToolModuleProcess -ModuleId $moduleId -Arguments $arguments -Action $displayName -Hidden)
        $status.Text = Get-ToolText -Key "report.running" -Culture $script:dashboardCulture -FormatArguments @($displayName)
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-ToolText -Key "report.startFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message))
    }
}

function Start-Cleanup {
    param([switch]$ReuseSessionSettings, [switch]$AutoSafeMode)
    if (-not (Test-Path -LiteralPath $cleanupScript)) {
        $script:cleanupAutoSafeMode = $false
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy mô-đun xử lý bản quyền.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    if (-not $ReuseSessionSettings) {
        $script:cleanupAutoSafeMode = [bool]$AutoSafeMode
        if (-not (Confirm-KmsApprovalConfiguration)) {
            $script:cleanupAutoSafeMode = $false
            $status.Text = "Đã thoát mục 6; chưa thay đổi hệ thống."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog "Mục 6 đã dừng vì danh sách KMS hợp lệ chưa được xác nhận."
            return
        }
        $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
            "Báo cáo kiểm tra/gỡ bản quyền có thể chứa tên máy, người dùng, đường dẫn và máy chủ KMS.`r`n`r`nYES: tạo báo cáo đã che dữ liệu nhạy cảm (khuyến nghị).`r`nNO: tạo báo cáo đầy đủ để kiểm kê nội bộ.`r`nCANCEL: không tiếp tục.",
            "Chọn mức riêng tư của báo cáo",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
        if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            $script:cleanupAutoSafeMode = $false
            return
        }
        $script:cleanupRedactSensitive = [bool]($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    try {
        Start-ProgressDisplay "Kiểm tra an toàn trước khi gỡ KMS/crack" "Đang đọc trạng thái bản quyền và dấu hiệu kích hoạt..." $false
        Write-ProgressLog "Đang kiểm tra trạng thái bản quyền Windows và Office..."
        $output = Join-Path $desktop "bao-cao-go-ban-quyen"
        $script:cleanupDecisionFile = New-SecureRuntimePath "tool-license-decision-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupDecisionFile`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.scan" -Arguments $arguments -Action "Kiểm tra trước khi gỡ KMS/crack" -Hidden)
        $status.Text = "Đang kiểm tra bản quyền Windows, Office và dấu hiệu crack..."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError "Không thể khởi động bước kiểm tra bản quyền: $($_.Exception.Message)"
    }
}

function Get-AutomaticSafeCleanupItems {
    param($CleanupItems)

    # Chế độ tự động chỉ được phép thay đổi các giá trị Registry cấp phép có
    # allowlist và có thể khôi phục đầy đủ. License, service, task, process,
    # tệp, thư mục, Defender và lịch sử sự kiện luôn cần người dùng chọn tay.
    return @($CleanupItems | Where-Object {
        $type = [string]$_.Type
        $kind = [string]$_.Kind
        $path = [string]$_.Location
        $type -eq "Registry" -and (
            ($kind -eq "KmsOverride" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "KeyManagementServiceName")) -or
            ($kind -eq "SppNoGenTicketPolicy" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "NoGenTicket"))
        )
    })
}

function Confirm-AutomaticSafeCleanup {
    param($CleanupItems)

    $safeItems = @(Get-AutomaticSafeCleanupItems -CleanupItems $CleanupItems)
    if ($safeItems.Count -eq 0) {
        return [pscustomobject]@{ Confirmed=$false; SelectedIds=@(); SafeItemCount=0 }
    }

    $preview = @($safeItems | ForEach-Object {
        "- $([string]$_.Name)`r`n  $([string]$_.Location)`r`n  $([string]$_.Detail)"
    }) -join "`r`n"
    $message = "Tool đề xuất tự động xử lý $($safeItems.Count) cấu hình an toàn sau:`r`n`r`n$preview`r`n`r`nTool sẽ tạo backup có HMAC trước khi thay đổi, yêu cầu quyền Administrator và hậu kiểm ngay sau xử lý.`r`n`r`nKhông tự gỡ key bản quyền, service, task, tiến trình, tệp/thư mục, ngoại lệ Defender hoặc lịch sử Event Log.`r`n`r`nTiếp tục làm sạch các mục trên?"
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        "Xác nhận tự động làm sạch an toàn",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    return [pscustomobject]@{
        Confirmed = [bool]($answer -eq [System.Windows.Forms.DialogResult]::Yes)
        SelectedIds = @($safeItems | ForEach-Object { [string]$_.Id })
        SafeItemCount = [int]$safeItems.Count
    }
}

function Show-DeepCleanupSelection {
    param($CleanupItems)
    $items = @($CleanupItems)
    if ($items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Không còn service, task, thư mục, tệp hoặc Registry nào thuộc phạm vi gỡ sâu.",
            "Không có mục để chọn", "OK", "Information") | Out-Null
        return [pscustomobject]@{ Confirmed=$false; SelectedIds=@() }
    }

    $chooser = New-Object System.Windows.Forms.Form
    $chooser.Text = "Chọn từng mục cần xử lý - Tool v4.4"
    $chooser.StartPosition = "CenterParent"
    $chooser.FormBorderStyle = "Sizable"
    $chooser.MinimumSize = New-Object System.Drawing.Size(760, 480)
    $chooser.ClientSize = New-Object System.Drawing.Size(900, 540)
    $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $chooser.Font = $fontNormal
    $chooser.Tag = [pscustomobject]@{ Confirmed=$false; SelectedIds=@() }

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "Đánh dấu chính xác từng mục cần gỡ/cách ly"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(18, 10)
    $heading.Size = New-Object System.Drawing.Size(864, 36)
    $heading.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Mặc định tất cả mục đều bỏ chọn. Chỉ đánh dấu khi đã kiểm tra tên, vị trí và chi tiết; chỉ các dòng được đánh dấu mới bị xử lý."
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.Location = New-Object System.Drawing.Point(22, 48)
    $hint.Size = New-Object System.Drawing.Size(856, 38)
    $hint.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($hint)

    $list = New-Object System.Windows.Forms.ListView
    $list.CheckBoxes = $true
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.Location = New-Object System.Drawing.Point(22, 90)
    $list.Size = New-Object System.Drawing.Size(856, 380)
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add("Loại", 115)
    [void]$list.Columns.Add("Tên", 240)
    [void]$list.Columns.Add("Vị trí / chi tiết", 480)
    $typeLabels = @{
        Service="Service"; ScheduledTask="Task"; Folder="Thư mục"; Registry="Registry"
        File="Tệp"; Process="Tiến trình"; Defender="Defender"; License="Bản quyền"
    }
    foreach ($cleanupItem in $items) {
        $typeText = if ($typeLabels.ContainsKey([string]$cleanupItem.Type)) { $typeLabels[[string]$cleanupItem.Type] } else { [string]$cleanupItem.Type }
        $row = New-Object System.Windows.Forms.ListViewItem($typeText)
        [void]$row.SubItems.Add([string]$cleanupItem.Name)
        $locationText = [string]$cleanupItem.Location
        if (-not [string]::IsNullOrWhiteSpace([string]$cleanupItem.Detail)) { $locationText += " — " + [string]$cleanupItem.Detail }
        [void]$row.SubItems.Add($locationText)
        $row.Tag = [string]$cleanupItem.Id
        $row.Checked = [bool]$cleanupItem.DefaultSelected
        [void]$list.Items.Add($row)
    }
    $chooser.Controls.Add($list)

    $allButton = New-Object System.Windows.Forms.Button
    $allButton.Text = "Chọn tất cả"
    $allButton.Location = New-Object System.Drawing.Point(22, 486)
    $allButton.Size = New-Object System.Drawing.Size(110, 34)
    $allButton.Anchor = "Bottom,Left"
    $allButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $true } })
    $chooser.Controls.Add($allButton)

    $noneButton = New-Object System.Windows.Forms.Button
    $noneButton.Text = "Bỏ chọn tất cả"
    $noneButton.Location = New-Object System.Drawing.Point(138, 486)
    $noneButton.Size = New-Object System.Drawing.Size(124, 34)
    $noneButton.Anchor = "Bottom,Left"
    $noneButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $false } })
    $chooser.Controls.Add($noneButton)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = "Tiếp tục"
    $applyButton.Font = $fontBold
    $applyButton.Location = New-Object System.Drawing.Point(648, 486)
    $applyButton.Size = New-Object System.Drawing.Size(110, 34)
    $applyButton.Anchor = "Bottom,Right"
    $applyButton.Add_Click({
        $selectedIds = @($list.CheckedItems | ForEach-Object { [string]$_.Tag })
        if ($selectedIds.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Hãy đánh dấu ít nhất một mục hoặc chọn Thoát.", "Chưa chọn mục", "OK", "Warning") | Out-Null
            return
        }
        $selectedObjects = @($items | Where-Object { $selectedIds -contains [string]$_.Id })
        $licenseCount = @($selectedObjects | Where-Object { $_.Type -eq "License" }).Count
        $licenseWarning = if ($licenseCount -gt 0) { "`r`n`r`nCẢNH BÁO: có $licenseCount mục bản quyền/KMS key. Tool chỉ lưu nhật ký và 5 ký tự cuối; không lưu key đầy đủ nên thay đổi key không thể tự khôi phục." } else { "" }
        $summary = "Đã chọn $($selectedIds.Count)/$($list.Items.Count) mục.`r`n`r`nTool sẽ sao lưu và xác thực các mục có thể phục hồi trước khi xử lý.$licenseWarning`r`n`r`nXác nhận tiếp tục?"
        $answer = [System.Windows.Forms.MessageBox]::Show($summary, "Xác nhận tổng thể lần cuối", "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $chooser.Tag = [pscustomobject]@{ Confirmed=$true; SelectedIds=$selectedIds }
            $chooser.Close()
        }
    })
    $chooser.Controls.Add($applyButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Thoát"
    $cancelButton.Location = New-Object System.Drawing.Point(768, 486)
    $cancelButton.Size = New-Object System.Drawing.Size(110, 34)
    $cancelButton.Anchor = "Bottom,Right"
    $cancelButton.Add_Click({ $chooser.Close() })
    $chooser.CancelButton = $cancelButton
    $chooser.Controls.Add($cancelButton)

    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void]$chooser.ShowDialog($form)
    $result = $chooser.Tag
    $chooser.Dispose()
    return $result
}

function Start-CleanupDeep {
    param($CleanupItems, [switch]$AutomaticSafeMode)
    if (-not (Confirm-IntegrityForElevatedAction "gỡ sâu các mục đã chọn")) {
        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        return
    }
    $selection = if ($AutomaticSafeMode) {
        Confirm-AutomaticSafeCleanup -CleanupItems $CleanupItems
    } else {
        Show-DeepCleanupSelection -CleanupItems $CleanupItems
    }
    if (-not [bool]$selection.Confirmed) {
        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        $status.Text = if ($AutomaticSafeMode) { "Đã hủy tự động làm sạch; hệ thống không thay đổi." } else { "Đã thoát gỡ sâu; các mục chưa chọn được giữ nguyên." }
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog $status.Text
        return
    }
    try {
        Start-ProgressDisplay "Gỡ sạch tồn dư kích hoạt" "Đang sao lưu và chuẩn bị phục hồi cấu hình cấp phép..." $true
        $selectionMode = if ($AutomaticSafeMode) { "tự động an toàn" } else { "thủ công" }
        Write-ProgressLog "Đã chọn $(@($selection.SelectedIds).Count) mục theo chế độ $selectionMode. Đang yêu cầu quyền Quản trị viên..."
        Write-ProgressLog "Tool chỉ xử lý các dòng được đánh dấu và sẽ tạo bộ khôi phục tự động."
        $output = Join-Path $desktop "bao-cao-go-ban-quyen"
        $script:cleanupResultFile = New-SecureRuntimePath "tool-license-deep-clean-result-"
        $script:cleanupSelectionFile = New-SecureRuntimePath "tool-license-deep-selection-"
        [pscustomobject]@{ SelectedIds=@($selection.SelectedIds) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:cleanupSelectionFile -Encoding UTF8
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -Remediate -DeepClean -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupResultFile`" -SelectionFile `"$script:cleanupSelectionFile`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.deep" -Arguments $arguments -Action "Gỡ sạch tồn dư kích hoạt" -Elevate)
        $status.Text = "Đang gỡ sạch tồn dư và phục hồi cấu hình cấp phép gốc..."
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:cleanupAutoSafeMode = $false
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = "Đã hủy quyền Administrator hoặc không thể chạy gỡ sạch nâng cao."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog "Gỡ sạch nâng cao chưa được khởi động; hệ thống không thay đổi thêm."
        Stop-ProgressDisplay $status.Text
    }
}

function Show-ScanWarningRecoveryDialog {
    param($Scan)
    $warningLines = @($Scan.ScanWarnings | ForEach-Object { "- $_" })
    $warningText = if ($warningLines.Count -gt 0) { $warningLines -join "`r`n" } else { "- Không đọc được chi tiết cảnh báo." }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Nguồn quét chưa đầy đủ"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(700, 430)
    $dialog.ClientSize = New-Object System.Drawing.Size(760, 460)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "Tool đã khóa thay đổi vì chưa đọc đủ nguồn quét quan trọng"
    $heading.Font = $fontBold
    $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.Location = New-Object System.Drawing.Point(18, 14)
    $heading.Size = New-Object System.Drawing.Size(706, 28)
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = "Đây là khóa an toàn: nếu WMI/CIM, slmgr hoặc Task Scheduler lỗi thì tool không được phép kết luận sạch hoặc gỡ KMS/crack. Có thể thử sửa nhanh các dịch vụ nền rồi quét lại."
    $intro.Location = New-Object System.Drawing.Point(18, 48)
    $intro.Size = New-Object System.Drawing.Size(706, 56)
    $intro.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($intro)

    $warnings = New-Object System.Windows.Forms.TextBox
    $warnings.Multiline = $true
    $warnings.ReadOnly = $true
    $warnings.ScrollBars = "Vertical"
    $warnings.WordWrap = $true
    $warnings.Text = $warningText
    $warnings.Location = New-Object System.Drawing.Point(18, 110)
    $warnings.Size = New-Object System.Drawing.Size(706, 230)
    $warnings.Anchor = "Top,Bottom,Left,Right"
    $dialog.Controls.Add($warnings)

    $repairButton = New-Object System.Windows.Forms.Button
    $repairButton.Text = "Sửa nhanh nguồn quét"
    $repairButton.Font = $fontBold
    $repairButton.Location = New-Object System.Drawing.Point(328, 368)
    $repairButton.Size = New-Object System.Drawing.Size(170, 38)
    $repairButton.Anchor = "Bottom,Right"
    $repairButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
    $repairButton.Add_Click({ $dialog.Tag = "Repair"; $dialog.Close() })
    $dialog.Controls.Add($repairButton)

    $retryButton = New-Object System.Windows.Forms.Button
    $retryButton.Text = "Quét lại"
    $retryButton.Location = New-Object System.Drawing.Point(508, 368)
    $retryButton.Size = New-Object System.Drawing.Size(96, 38)
    $retryButton.Anchor = "Bottom,Right"
    $retryButton.Add_Click({ $dialog.Tag = "Retry"; $dialog.Close() })
    $dialog.Controls.Add($retryButton)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = "Đóng"
    $close.Location = New-Object System.Drawing.Point(614, 368)
    $close.Size = New-Object System.Drawing.Size(110, 38)
    $close.Anchor = "Bottom,Right"
    $close.Add_Click({ $dialog.Tag = "Close"; $dialog.Close() })
    $dialog.CancelButton = $close
    $dialog.Controls.Add($close)

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Start-ScanSourceRepair {
    if (-not (Confirm-IntegrityForElevatedAction "kiểm tra và sửa nhanh nguồn quét")) { Set-ButtonsEnabled $true; return }
    try {
        Start-ProgressDisplay "Sửa nhanh nguồn quét" "Đang kiểm tra WMI/CIM, Task Scheduler và dịch vụ cấp phép..." $true
        Write-ProgressLog "Đang yêu cầu quyền Administrator để kiểm tra/khởi động lại dịch vụ nền cần cho quá trình quét."
        $output = Join-Path $desktop "bao-cao-go-ban-quyen"
        $script:cleanupRepairDecisionFile = New-SecureRuntimePath "tool-scan-source-repair-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -RepairScanSources -DecisionFile `"$script:cleanupRepairDecisionFile`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.repair" -Arguments $arguments -Action "Sửa nhanh nguồn quét" -Elevate)
        $status.Text = "Đang sửa/kiểm tra lại nguồn quét. Vui lòng chờ..."
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError "Không thể khởi động sửa nhanh nguồn quét: $($_.Exception.Message)"
    }
}

function Complete-ScanSourceRepair {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupRepairDecisionFile -PathType Leaf)) {
            throw "Không nhận được kết quả sửa nhanh nguồn quét."
        }
        $result = Get-Content -LiteralPath $script:cleanupRepairDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupRepairDecisionFile -Force -ErrorAction SilentlyContinue
        $script:cleanupRepairDecisionFile = ""
        $beforeState = @($result.ServiceStateBefore) | ConvertTo-Json -Depth 5 -Compress
        $afterState = @($result.ServiceStateAfter) | ConvertTo-Json -Depth 5 -Compress
        $serviceStateChanged = [bool]($beforeState -ne $afterState -and -not [bool]$result.RollbackApplied)
        [void](Write-LicenseTimelineEventSafe -EventType "ScanSourceRepairCompleted" -Source "GUI" -IsChange:$serviceStateChanged -Data ([ordered]@{
            RecheckPassed=[bool]$result.RecheckPassed
            ServiceStateChanged=$serviceStateChanged
            StartupTypeChanged=[bool]$result.StartupTypeChanged
            RollbackApplied=[bool]$result.RollbackApplied
        }))
        $checkLines = @($result.Checks | ForEach-Object { "- [$($_.Status)] $($_.Name): $($_.Detail)" })
        $guidanceLines = @($result.HandlingGuidance | ForEach-Object { "- $_" })
        $message = "Kết quả sửa nhanh nguồn quét: $(if ([bool]$result.RecheckPassed) { 'ĐẠT' } else { 'CÒN LỖI' })`r`n`r`n$($checkLines -join "`r`n")`r`n`r`nHướng xử lý:`r`n$($guidanceLines -join "`r`n")`r`n`r`nBáo cáo: $($result.ReportPath)"
        if ([bool]$result.RecheckPassed) {
            $answer = [System.Windows.Forms.MessageBox]::Show("$message`r`n`r`nQuét lại mục 6 ngay bây giờ?", "Nguồn quét đã sẵn sàng", "YesNo", "Information")
            $status.Text = "Nguồn quét đã sẵn sàng; có thể quét lại mục 6."
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
            Write-ProgressLog "Sửa nhanh nguồn quét đạt; sẵn sàng quét lại."
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Cleanup }
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, "Nguồn quét vẫn còn lỗi", "OK", "Warning") | Out-Null
            $status.Text = "Nguồn quét vẫn lỗi; chưa được phép gỡ hoặc kết luận sạch."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog "Nguồn quét vẫn lỗi sau sửa nhanh; xem báo cáo repair."
        }
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title "Báo cáo sửa nhanh nguồn quét Mục 6" -FilePrefix "BaoCao_Muc6_SuaNguonQuet")
        }
    } catch {
        $status.Text = "Không đọc được kết quả sửa nhanh nguồn quét: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Complete-CleanupScan {
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupDecisionFile)) {
            throw "Không nhận được kết quả kiểm tra."
        }
        $scan = Get-Content -LiteralPath $script:cleanupDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupDecisionFile -Force -ErrorAction SilentlyContinue
        $script:cleanupDecisionFile = ""
        if ($scan.ReportPath -and (Test-Path -LiteralPath $scan.ReportPath -PathType Leaf)) {
            $scanPresentation = Open-ToolReportPresentation -SourcePath ([string]$scan.ReportPath) -Title "Báo cáo kiểm tra và khắc phục KMS/Activator" -FilePrefix "BaoCao_Muc6_KiemTra"
            if ($scanPresentation) { $scan.ReportPath = [string]$scanPresentation.HtmlPath }
        }

        if ([int]$scan.ScanWarningCount -gt 0) {
            Set-ButtonsEnabled $true
            $status.Text = "Quét chưa đầy đủ; tool không kết luận sạch và không cho phép gỡ."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog "Đã khóa xử lý vì có $($scan.ScanWarningCount) cảnh báo nguồn quét quan trọng."
            $choice = Show-ScanWarningRecoveryDialog -Scan $scan
            if ($choice -eq "Repair") {
                Start-ScanSourceRepair
            } elseif ($choice -eq "Retry") {
                if ([bool]$script:cleanupAutoSafeMode) { Start-Cleanup -ReuseSessionSettings }
                else { Start-Cleanup }
            } else {
                $script:cleanupAutoSafeMode = $false
                Write-ProgressLog "Người dùng đóng cảnh báo nguồn quét; hệ thống không thay đổi."
            }
            return
        }

        if ([bool]$scan.CrackDetected) {
            if ([bool]$script:cleanupAutoSafeMode) {
                $automaticSafeItems = @(Get-AutomaticSafeCleanupItems -CleanupItems @($scan.CleanupItems))
                if ($automaticSafeItems.Count -gt 0) {
                    Write-ProgressLog "Chế độ tự động an toàn tìm thấy $($automaticSafeItems.Count) cấu hình Registry có thể backup và khôi phục."
                    Start-CleanupDeep -CleanupItems @($scan.CleanupItems) -AutomaticSafeMode
                    return
                }

                $script:cleanupAutoSafeMode = $false
                Set-ButtonsEnabled $true
                $manualAnswer = [System.Windows.Forms.MessageBox]::Show(
                    "Tool không tìm thấy cấu hình Registry nào đủ điều kiện tự động xử lý an toàn.`r`n`r`nCác dấu hiệu còn lại cần được người dùng xem và chọn thủ công. Mở danh sách chi tiết?",
                    "Không có mục tự động an toàn",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($manualAnswer -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Start-CleanupDeep -CleanupItems @($scan.CleanupItems)
                } else {
                    $status.Text = "Không có mục tự động an toàn; hệ thống không thay đổi."
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                return
            }

            $licenseNote = if ([bool]$scan.ProtectedLicense) {
                "Bản quyền Windows cần bảo vệ: $($scan.ProtectedChannel).`r`n$($scan.ProtectedReason)`r`n`r`n"
            } else {
                "Không phát hiện khóa Windows OEM/Retail/MAK hợp lệ cần bảo vệ.`r`n`r`n"
            }
            $message = "$licenseNote" + "Đã phát hiện dấu hiệu KMS/crack cần xử lý:`r`n- Dấu hiệu activator đang tồn tại: $($scan.ActivatorFindingCount)`r`n- Cấu hình/tồn dư: $($scan.ConfigurationResidueCount)`r`n- KMS Windows chưa phê duyệt: $($scan.WindowsKmsCount)`r`n- Bản Office KMS: $($scan.OfficeKmsCount)`r`n- Dấu vết lịch sử: $($scan.HistoryFindingCount)`r`n`r`nBước tiếp theo chỉ mở danh sách chi tiết; hệ thống chưa bị thay đổi. Có thể đánh dấu riêng từng service, task, thư mục, tệp, Registry và mục bản quyền cần xử lý.`r`n`r`nBạn có muốn mở danh sách chọn?"
            $answer = [System.Windows.Forms.MessageBox]::Show($message, "Xem danh sách trước khi gỡ", "YesNo", "Warning")
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                Set-ButtonsEnabled $true
                $status.Text = "Đã hủy xử lý; hệ thống không thay đổi."
                Write-ProgressLog "Đã chọn không xử lý KMS/crack; chỉ giữ báo cáo kiểm tra."
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
                return
            }
            Start-CleanupDeep -CleanupItems @($scan.CleanupItems)
            return
        }

        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        if ([bool]$scan.ProtectedLicense) {
            [System.Windows.Forms.MessageBox]::Show("Máy đang có bản quyền $($scan.ProtectedChannel) và không phát hiện KMS/crack đang hoạt động. Dấu vết lịch sử tìm thấy: $($scan.HistoryFindingCount).`r`n`r`n$($scan.CleanupConclusion)", "Bản quyền đang được bảo vệ", "OK", "Information") | Out-Null
            $status.Text = "Không phát hiện crack. Bản quyền $($scan.ProtectedChannel) được giữ nguyên."
            Write-ProgressLog "Hoàn tất kiểm tra: không phát hiện KMS/crack cần gỡ."
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show("Không phát hiện KMS/crack đang hoạt động nên chương trình không tự gỡ key. Dấu vết lịch sử tìm thấy: $($scan.HistoryFindingCount).`r`n`r`n$($scan.CleanupConclusion)`r`n`r`nHãy xem báo cáo trên Desktop.", "Kết quả kiểm tra", "OK", "Information") | Out-Null
            $status.Text = "Không phát hiện KMS/crack rõ ràng; không thực hiện thay đổi."
            Write-ProgressLog "Hoàn tất kiểm tra: chưa đủ bằng chứng để thực hiện thay đổi."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = "Không đọc được kết quả kiểm tra: $($_.Exception.Message)"
        Write-ProgressLog "Lỗi khi đọc kết quả: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Show-CleanupResultCenter {
    param($Result, [bool]$WasDeepCleanup, [bool]$SafetyBlocked)

    $remainingItems = @($Result.CleanupItems)
    $nextActions = @($Result.NextActions)
    if ($SafetyBlocked) {
        $nextActions = @($nextActions | Where-Object { [string]$_.Code -in @('Recheck','OpenReport') })
    }

    $headingText = if ($SafetyBlocked) {
        "Đã khóa thay đổi để bảo vệ hệ thống"
    } elseif ([bool]$Result.ReadyForOfficialActivation) {
        "Đã đủ sạch — chọn bước kích hoạt hợp lệ"
    } elseif ($remainingItems.Count -gt 0) {
        "Còn $($remainingItems.Count) mục có thể xử lý tiếp"
    } else {
        "Cần hậu kiểm hoặc xử lý theo hướng dẫn"
    }
    $headingColor = if ([bool]$Result.ReadyForOfficialActivation) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
    if ($SafetyBlocked) { $headingColor = [System.Drawing.Color]::DarkRed }

    $body = New-Object System.Collections.Generic.List[string]
    $body.Add([string]$Result.CleanupConclusion)
    $body.Add("")
    $body.Add("KẾT QUẢ HẬU KIỂM")
    $body.Add("• Dấu hiệu activator đang hoạt động: $($Result.ActivatorFindingCount)")
    $body.Add("• Cấu hình/tồn dư: $($Result.ConfigurationResidueCount)")
    $body.Add("• KMS Windows chưa phê duyệt: $($Result.WindowsKmsCount)")
    $body.Add("• KMS Office chưa phê duyệt: $($Result.OfficeKmsCount)")
    $body.Add("• Dấu vết lịch sử (không phải lỗi đang hoạt động): $($Result.HistoryFindingCount)")
    $body.Add("• Cảnh báo nguồn quét: $($Result.ScanWarningCount)")
    $body.Add("• Chẩn đoán cần xem xét: $($Result.ReadinessReviewCount)")

    if ($nextActions.Count -gt 0) {
        $body.Add("")
        $body.Add("BƯỚC TIẾP THEO CÓ THỂ THỰC HIỆN NGAY")
        $stepNumber = 0
        foreach ($next in $nextActions) {
            if ([string]$next.Code -eq 'OpenReport') { continue }
            $stepNumber++
            $candidateText = if ([int]$next.CandidateCount -gt 0) { " ($($next.CandidateCount) mục)" } else { "" }
            $body.Add("$stepNumber. $($next.Label)$candidateText — $($next.Detail)")
        }
    }

    if ($remainingItems.Count -gt 0) {
        $body.Add("")
        $body.Add("MỤC CÒN LẠI SAU HẬU KIỂM")
        foreach ($item in @($remainingItems | Select-Object -First 30)) {
            $detail = (([string]$item.Detail) -replace "`0|`r?`n", " ").Trim()
            $body.Add("• [$($item.Type)] $($item.Name) — $detail")
        }
        if ($remainingItems.Count -gt 30) { $body.Add("• Còn $($remainingItems.Count - 30) mục khác; mở báo cáo để xem đầy đủ.") }
    }

    $guidance = @($Result.HandlingGuidance)
    if ($guidance.Count -gt 0) {
        $body.Add("")
        $body.Add("HƯỚNG XỬ LÝ ĐỀ XUẤT")
        foreach ($line in $guidance) { $body.Add("• $line") }
    }

    $rawActions = @($Result.Actions)
    if ($rawActions.Count -gt 0) {
        $body.Add("")
        $body.Add("HÀNH ĐỘNG ĐÃ THỰC HIỆN (TÓM TẮT)")
        foreach ($action in @($rawActions | Select-Object -First 14)) {
            $line = (([string]$action) -replace "`0|`r?`n", " | ").Trim()
            if ($line.Length -gt 240) { $line = $line.Substring(0, 237) + "..." }
            $body.Add("• $line")
        }
        if ($rawActions.Count -gt 14) { $body.Add("• Còn $($rawActions.Count - 14) dòng khác trong báo cáo.") }
    }
    $body.Add("")
    $body.Add([string]$Result.ScopeNote)
    $body.Add("Báo cáo: $($Result.ReportPath)")

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ([bool]$Result.ReadyForOfficialActivation) { "Kết quả cleanup và bước tiếp theo" } else { "Còn mục cần xử lý — chọn bước tiếp theo" }
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MaximizeBox = $true
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(660, [Math]::Min(940, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(440, [Math]::Min(700, $workArea.Height - 70))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(660, $dialogWidth), [Math]::Min(440, $dialogHeight))
    $dialog.Size = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Fill"
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $headingText
    $heading.Font = $fontTitle
    $heading.ForeColor = $headingColor
    $heading.Dock = "Top"
    $heading.Height = 38
    $header.Controls.Add($heading)
    $subheading = New-Object System.Windows.Forms.Label
    $subheading.Text = if ($SafetyBlocked) { "Không có thay đổi mới. Có thể quét lại hoặc mở báo cáo." } elseif ($remainingItems.Count -gt 0) { "Không cần tự tìm lệnh trong báo cáo: chọn một hành động ở hàng nút bên dưới." } else { "Kết quả và nút hành động được giữ trong cùng một cửa sổ có thể cuộn/phóng to." }
    $subheading.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $subheading.Dock = "Fill"
    $header.Controls.Add($subheading)
    $layout.Controls.Add($header, 0, 0)

    $details = New-Object System.Windows.Forms.RichTextBox
    $details.Dock = "Fill"
    $details.ReadOnly = $true
    $details.DetectUrls = $false
    $details.WordWrap = $true
    $details.ScrollBars = "ForcedVertical"
    $details.BackColor = [System.Drawing.Color]::White
    $details.ForeColor = [System.Drawing.Color]::FromArgb(35, 45, 62)
    $details.Font = $fontNormal
    $details.Text = $body -join "`r`n"
    $layout.Controls.Add($details, 0, 1)

    $buttonBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonBar.Dock = "Fill"
    $buttonBar.FlowDirection = "RightToLeft"
    $buttonBar.WrapContents = $false
    $buttonBar.AutoScroll = $true
    $buttonBar.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $layout.Controls.Add($buttonBar, 0, 2)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = "Đóng"
    $close.Size = New-Object System.Drawing.Size(92, 34)
    $close.Tag = "Close"
    $close.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
    $dialog.CancelButton = $close
    $buttonBar.Controls.Add($close)

    $reportButton = New-Object System.Windows.Forms.Button
    $reportButton.Text = "Mở báo cáo"
    $reportButton.Size = New-Object System.Drawing.Size(108, 34)
    $reportButton.Add_Click({
        if ($Result.ReportPath -and (Test-Path -LiteralPath $Result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$Result.ReportPath) -Title "Báo cáo kiểm tra và khắc phục KMS/Activator" -FilePrefix "BaoCao_Muc6_KetQua")
        }
    })
    $buttonBar.Controls.Add($reportButton)

    foreach ($next in @($nextActions | Where-Object { [string]$_.Code -ne 'OpenReport' })) {
        $actionButton = New-Object System.Windows.Forms.Button
        $actionButton.Text = [string]$next.Label
        $actionButton.AutoSize = $true
        $actionButton.MinimumSize = New-Object System.Drawing.Size(108, 34)
        $actionButton.MaximumSize = New-Object System.Drawing.Size(190, 34)
        $actionButton.Tag = [string]$next.Code
        if ([string]$next.Code -in @('RemediateRemaining','RepairScanSources','OpenLicenseManager')) {
            $actionButton.Font = $fontBold
            $actionButton.BackColor = if ([string]$next.Code -eq 'OpenLicenseManager') { [System.Drawing.Color]::FromArgb(230, 247, 236) } else { [System.Drawing.Color]::FromArgb(255, 248, 230) }
        }
        $actionButton.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
        $buttonBar.Controls.Add($actionButton)
        if (-not $dialog.AcceptButton -and [string]$next.Code -in @('RemediateRemaining','RepairScanSources','OpenLicenseManager','Recheck')) { $dialog.AcceptButton = $actionButton }
    }

    $dialog.Add_Shown({ $details.SelectionStart = 0; $details.SelectionLength = 0; $details.ScrollToCaret() })
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Complete-CleanupRemediation([bool]$wasDeepCleanup) {
    Set-ButtonsEnabled $true
    $completedAutoSafeMode = [bool]$script:cleanupAutoSafeMode
    $script:cleanupAutoSafeMode = $false
    try {
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        if (-not (Test-Path -LiteralPath $script:cleanupResultFile)) {
            throw "Không nhận được kết quả kiểm tra sau xử lý."
        }
        $result = Get-Content -LiteralPath $script:cleanupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupResultFile -Force -ErrorAction SilentlyContinue
        $script:cleanupResultFile = ""
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            $cleanupPresentation = Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title "Báo cáo hậu kiểm KMS/Activator" -FilePrefix "BaoCao_Muc6_HauKiem"
            if ($cleanupPresentation) { $result.ReportPath = [string]$cleanupPresentation.HtmlPath }
        }
        $wasSafetyBlocked = [bool](@($result.Actions | Where-Object { [string]$_ -match '^ĐÃ KHÓA XỬ LÝ:' }).Count -gt 0)
        $confirmedActions = @($result.Actions | Where-Object {
            [string]$_ -match '^(Đã |Office /(?:remhst|unpkey:).+ ĐẠT|Windows /(?:upk|ckms|cpky|rilc):.+(?:ĐẠT|success|thành công))'
        })
        [void](Write-LicenseTimelineEventSafe -EventType "LicenseCleanupCompleted" -Source "GUI" -IsChange:([bool](-not $wasSafetyBlocked -and $confirmedActions.Count -gt 0)) -Data ([ordered]@{
            SafetyBlocked=$wasSafetyBlocked
            SelectedItemCount=[int]$result.SelectedCleanupItemCount
            ConfirmedActionCount=[int]$confirmedActions.Count
            ReadyForOfficialActivation=[bool]$result.ReadyForOfficialActivation
            RemainingItemCount=[int](@($result.CleanupItems).Count)
            BackupCreated=[bool](-not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory))
            AutomaticSafeMode=$completedAutoSafeMode
        }))
        if ($wasSafetyBlocked) {
            $status.Text = "Tool đã khóa xử lý vì môi trường chạy không đạt yêu cầu an toàn; hệ thống không bị thay đổi."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } elseif ([bool]$result.ReadyForOfficialActivation) {
            $status.Text = "Đã kiểm tra sau xử lý: máy đủ điều kiện kỹ thuật để kích hoạt chính thức."
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            $status.Text = "Hậu kiểm còn $(@($result.CleanupItems).Count) mục; hãy chọn bước xử lý tiếp theo."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog "Hoàn tất kiểm tra sau xử lý: $($result.CleanupConclusion)"
        if ($wasDeepCleanup -and -not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory)) {
            Write-ProgressLog "Bộ khôi phục tự động: $($result.BackupDirectory)"
        }
        $nextChoice = Show-CleanupResultCenter -Result $result -WasDeepCleanup $wasDeepCleanup -SafetyBlocked $wasSafetyBlocked
        switch ($nextChoice) {
            "RemediateRemaining" {
                Write-ProgressLog "Đang mở danh sách hậu kiểm để chọn chính xác các mục còn lại."
                Start-CleanupDeep -CleanupItems @($result.CleanupItems)
                return
            }
            "ConfigureApprovedKms" {
                if (Confirm-KmsApprovalConfiguration) {
                    Write-ProgressLog "Danh sách KMS nội bộ đã được xác nhận; đang quét lại theo cấu hình mới."
                    Start-Cleanup -ReuseSessionSettings
                } else {
                    $status.Text = "Chưa thay đổi danh sách KMS; kết quả hiện tại được giữ nguyên."
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                return
            }
            "RepairScanSources" { Start-ScanSourceRepair; return }
            "Recheck" { Start-Cleanup -ReuseSessionSettings; return }
            "OpenLicenseManager" { Open-LicenseManager; return }
            "RestoreBackup" { Start-CleanupRestore; return }
            default {
                if (-not [bool]$result.ReadyForOfficialActivation) {
                    Write-ProgressLog "Đã đóng Trung tâm xử lý; chưa thực hiện thay đổi tiếp theo."
                }
            }
        }
    } catch {
        $status.Text = "Không đọc được kết quả sau xử lý: $($_.Exception.Message)"
        Write-ProgressLog "Dừng gỡ tiếp, giữ nguyên thư mục backup và mở thư mục báo cáo trên Desktop để kiểm tra."
        Write-ProgressLog "Nếu gặp 'Argument types do not match', không dùng lại bản EXE cũ; hãy chạy bản đã sửa rồi tạo backup mới trước khi xử lý."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-OemInspect {
    if (-not (Test-Path -LiteralPath $oemScript)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy mô-đun kiểm tra key OEM trong BIOS.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay "Kiểm tra key OEM trong BIOS" "Đang đọc key OEM OA3 và trạng thái Windows..." $false
        Write-ProgressLog "Đang đọc key OEM OA3 trong BIOS và trạng thái bản quyền hiện tại..."
        Write-ProgressLog "Product key đầy đủ sẽ không được hiển thị hoặc ghi vào báo cáo."
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-decision-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Inspect -OutputDir `"$desktop`" -DecisionFile `"$script:oemDecisionFile`""
        [void](Start-ToolModuleProcess -ModuleId "oem.inspect" -Arguments $arguments -Action "Kiểm tra key OEM trong BIOS" -Hidden)
        $status.Text = "Đang kiểm tra key OEM trong BIOS..."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError "Không thể khởi động kiểm tra key OEM: $($_.Exception.Message)"
    }
}

function Start-OemApply {
    if (-not (Confirm-IntegrityForElevatedAction "khôi phục key OEM")) { return }
    try {
        Start-ProgressDisplay "Khôi phục key OEM trong BIOS" "Đang chờ quyền Quản trị viên và Windows xác minh key OEM..." $true
        Write-ProgressLog "Đã xác nhận. Đang yêu cầu quyền Quản trị viên để Windows kiểm tra và cài key OEM..."
        Write-ProgressLog "Công cụ không gỡ key hiện tại trước khi thử key OEM."
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-apply-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Apply -OutputDir `"$desktop`" -DecisionFile `"$script:oemDecisionFile`""
        [void](Start-ToolModuleProcess -ModuleId "oem.apply" -Arguments $arguments -Action "Khôi phục key OEM trong BIOS" -Elevate -Hidden)
        $status.Text = "Đang cài key OEM và yêu cầu Windows kích hoạt..."
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        if ($script:oemDecisionFile -and (Test-Path -LiteralPath $script:oemDecisionFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        }
        $script:oemDecisionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = "Đã hủy yêu cầu quyền Quản trị viên hoặc không thể chạy khôi phục key OEM."
        Write-ProgressLog "Không thực hiện thay đổi hệ thống."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-OemInspect {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:oemDecisionFile)) {
            throw "Không nhận được kết quả kiểm tra."
        }
        $result = Get-Content -LiteralPath $script:oemDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        $script:oemDecisionFile = ""
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title "Báo cáo key OEM trong BIOS" -FilePrefix "BaoCao_Key_OEM_BIOS")
        }

        if (-not [bool]$result.FirmwareKeyFound) {
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy key OEM OA3 trong BIOS. Chương trình không thực hiện thay đổi.", "Không có key OEM trong BIOS", "OK", "Information") | Out-Null
            $status.Text = "Không tìm thấy key OEM trong BIOS; không thay đổi hệ thống."
            Write-ProgressLog "Hoàn tất kiểm tra: không tìm thấy key OEM OA3."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }

        $activation = if ([bool]$result.IsActivated) { "Đã cấp phép" } else { "Chưa xác nhận được cấp phép" }
        $message = "Đã tìm thấy key OEM trong BIOS: $($result.FirmwareKeyMasked)`r`nWindows hiện tại: $($result.ProductName) - $($result.CurrentEdition)`r`nTrạng thái: $activation`r`nKênh hiện tại: $($result.CurrentChannel)`r`n5 ký tự cuối key hiện tại: $($result.CurrentPartialKey)`r`n`r`nBạn có muốn Windows thử cài key OEM và yêu cầu kích hoạt không?`r`n`r`nCơ chế bảo vệ: công cụ không gỡ key hiện tại trước khi thử. Nếu key OEM không khớp edition, Windows sẽ từ chối; công cụ không dùng key crack/generic và không thay đổi firewall."
        $answer = [System.Windows.Forms.MessageBox]::Show($message, "Xác nhận khôi phục key OEM", "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-OemApply
            return
        }
        $status.Text = "Đã kiểm tra key OEM; người dùng chọn không thay đổi hệ thống."
        Write-ProgressLog "Đã tạo báo cáo kiểm tra trên Desktop; không cài key OEM."
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    } catch {
        $status.Text = "Không đọc được kết quả kiểm tra key OEM: $($_.Exception.Message)"
        Write-ProgressLog "Lỗi khi đọc kết quả kiểm tra key OEM."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-DeepLicenseScan {
    if (-not (Confirm-IntegrityForElevatedAction "kiểm tra bản quyền chuyên sâu")) { return }
    if (-not (Test-Path -LiteralPath $deepScanScript)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy mô-đun kiểm tra bản quyền chuyên sâu.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        "YES: tạo báo cáo đã che tên máy/người dùng, KMS nội bộ, IP, MAC và đường dẫn cá nhân (khuyến nghị khi chia sẻ).`r`nNO: báo cáo đầy đủ nội bộ.`r`nCANCEL: dừng.",
        "Mức riêng tư báo cáo chuyên sâu", "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay "Kiểm tra bản quyền Windows chuyên sâu" "Đang chờ quyền Administrator để kiểm tra 7 nhóm tiêu chí..." $false
        Write-ProgressLog "Kiểm tra bản quyền Windows chuyên sâu theo 7 nhóm tiêu chí."
        Write-ProgressLog "Windows sẽ hỏi quyền Administrator để đọc đủ thành phần hệ thống."
        Write-ProgressLog "Chế độ này chỉ đọc; không sửa key, Registry, hosts, firewall, service hoặc task."
        $script:deepScanDecisionFile = New-SecureRuntimePath "tool-deep-license-"
        $output = $desktop
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$deepScanScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:deepScanDecisionFile`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "license.deep-scan" -Arguments $arguments -Action "Kiểm tra bản quyền Windows chuyên sâu" -Elevate -Hidden)
        $status.Text = "Đang kiểm tra 7 nhóm dấu hiệu bản quyền Windows..."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError "Không thể khởi động kiểm tra chuyên sâu: $($_.Exception.Message)"
    }
}

function Complete-DeepLicenseScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:deepScanDecisionFile)) {
            throw "Không nhận được kết quả kiểm tra."
        }
        $result = Get-Content -LiteralPath $script:deepScanDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:deepScanDecisionFile -Force -ErrorAction SilentlyContinue
        $script:deepScanDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            [System.Windows.Forms.MessageBox]::Show("Không được cấp quyền Administrator nên chưa chạy kiểm tra chuyên sâu. Không có thay đổi nào được thực hiện.", "Chưa được cấp quyền", "OK", "Information") | Out-Null
            $status.Text = "Chưa chạy kiểm tra chuyên sâu vì chưa được cấp quyền Administrator."
            Write-ProgressLog "Không thực hiện thay đổi hệ thống."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $guidanceLines = @($result.HandlingGuidance | ForEach-Object { "- $_" })
        $reviewLines = @($result.ReviewItems | Select-Object -First 3 | ForEach-Object { "- $($_.Name): $($_.Recommendation)" })
        $guidanceSummary = if ($guidanceLines.Count -gt 0) { "`r`n`r`nCần làm tiếp:`r`n$($guidanceLines -join "`r`n")" } else { "" }
        $reviewSummary = if ($reviewLines.Count -gt 0) { "`r`n`r`nMục cần xem:`r`n$($reviewLines -join "`r`n")" } else { "" }
        $message = "Kết quả: $($result.Overall)`r`nDấu hiệu mạnh: $($result.HighCount)`r`nMục cần xác minh: $($result.ReviewCount)`r`nKênh hiện tại: $($result.ActiveChannel)`r`nKey OEM BIOS: $(if ([bool]$result.OemKeyPresent) { 'Có' } else { 'Không tìm thấy' })$guidanceSummary$reviewSummary`r`n`r`nBáo cáo chi tiết:`r`n$($result.ReportPath)"
        [System.Windows.Forms.MessageBox]::Show($message, "Kiểm tra chuyên sâu hoàn tất", "OK", $(if ([int]$result.HighCount -gt 0) { "Warning" } else { "Information" })) | Out-Null
        if (Test-Path -LiteralPath $result.ReportPath) { Start-Process $result.ReportPath }
        $status.Text = "Hoàn tất kiểm tra chuyên sâu: $($result.Overall)."
        Write-ProgressLog "Đã lưu và mở báo cáo chuyên sâu trên Desktop."
        $status.ForeColor = if ([int]$result.HighCount -gt 0) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = "Không đọc được kết quả kiểm tra chuyên sâu: $($_.Exception.Message)"
        Write-ProgressLog "Lỗi khi đọc kết quả kiểm tra chuyên sâu."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-ForensicsScan {
    if (-not (Confirm-IntegrityForElevatedAction "điều tra bản quyền")) { return }
    if (-not (Test-Path -LiteralPath $forensicsScript)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy mô-đun điều tra bản quyền.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        "YES: tạo bộ bằng chứng đã che tên máy/người dùng, KMS nội bộ, IP, MAC và đường dẫn cá nhân (khuyến nghị khi chia sẻ).`r`nNO: bộ bằng chứng đầy đủ nội bộ.`r`nCANCEL: dừng.",
        "Mức riêng tư bộ bằng chứng", "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay "Điều tra bản quyền và chấm điểm rủi ro" "Đang chờ quyền Administrator để điều tra 12 nhóm kỹ thuật..." $false
        Write-ProgressLog "Điều tra bản quyền theo 12 nhóm kỹ thuật."
        Write-ProgressLog "Đang yêu cầu quyền Administrator để đọc chữ ký, hash, nhật ký SPP và trạng thái bảo mật."
        Write-ProgressLog "Chế độ chỉ đọc; không gửi dữ liệu ra Internet và không lưu product key đầy đủ."
        $script:forensicsDecisionFile = New-SecureRuntimePath "tool-license-forensics-"
        $output = $desktop
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$forensicsScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:forensicsDecisionFile`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "forensics.scan" -Arguments $arguments -Action "Điều tra bản quyền và chấm điểm rủi ro" -Elevate -Hidden)
        $status.Text = "Đang kiểm tra 12 nhóm kỹ thuật và tạo bộ bằng chứng SHA-256..."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = "Đã hủy quyền Administrator hoặc không thể chạy điều tra."
        Write-ProgressLog "Không thực hiện thay đổi hệ thống."
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-ForensicsScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:forensicsDecisionFile)) {
            throw "Không nhận được kết quả điều tra."
        }
        $result = Get-Content -LiteralPath $script:forensicsDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:forensicsDecisionFile -Force -ErrorAction SilentlyContinue
        $script:forensicsDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            $status.Text = "Chưa chạy điều tra vì chưa được cấp quyền Administrator."
            Write-ProgressLog "Không thực hiện thay đổi hệ thống."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $message = "Kết quả: $($result.Overall)`r`nĐiểm rủi ro: $($result.RiskScore)/100 - $($result.RiskLevel)`r`nRủi ro cao: $($result.HighCount)`r`nCần xác minh: $($result.ReviewCount)`r`nDấu hiệu mới so với lần trước: $($result.NewFindingCount)`r`nDấu hiệu đã hết: $($result.ResolvedFindingCount)`r`n`r`nBộ bằng chứng:`r`n$($result.EvidenceFolder)"
        $icon = if ([int]$result.RiskScore -ge 40) { "Warning" } else { "Information" }
        [System.Windows.Forms.MessageBox]::Show($message, "Điều tra bản quyền hoàn tất", "OK", $icon) | Out-Null
        if (Test-Path -LiteralPath $result.ReportPath) { Start-Process $result.ReportPath }
        $status.Text = "Hoàn tất điều tra: điểm $($result.RiskScore)/100 - $($result.RiskLevel)."
        Write-ProgressLog "Đã tạo HTML, JSON, CSV và SHA256SUMS trong bộ bằng chứng."
        $status.ForeColor = if ([int]$result.RiskScore -ge 40) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = "Không đọc được kết quả điều tra: $($_.Exception.Message)"
        Write-ProgressLog "Lỗi khi đọc kết quả điều tra."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Open-LicenseManager {
    if (-not (Confirm-IntegrityForElevatedAction (Get-ToolText -Key "status.enterprise.action" -Culture $script:dashboardCulture))) { return }
    if (-not (Test-Path -LiteralPath $licenseManagerScript)) {
        $status.Text = Get-ToolText -Key "status.enterprise.missing" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        return
    }
    try {
        Start-ProgressDisplay `
            (Get-ToolText -Key "status.enterprise.opening" -Culture $script:dashboardCulture) `
            (Get-ToolText -Key "status.enterprise.elevation" -Culture $script:dashboardCulture) `
            $false
        # Truyền theme hiện tại qua tiến trình UAC; cửa sổ enterprise cũng đọc
        # thiết lập đã lưu nếu Windows tạo môi trường tiến trình mới.
        $env:TOOL_UI_THEME = $script:dashboardTheme
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        if ($env:TOOL_SECURE_LAUNCH -eq "1" -and -not [string]::IsNullOrWhiteSpace($launcherPath) -and (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
            [void](Get-ReadyToolModule -moduleId "license.manager" -elevatedLaunch $true)
            $enterpriseProcess = Start-Process -FilePath $launcherPath -ArgumentList "--enterprise-ui" -PassThru
            if (-not $enterpriseProcess) { throw (Get-ToolText -Key "status.enterprise.launchFailed" -Culture $script:dashboardCulture) }
            [void](Write-ToolLog -Level "AUDIT" -Event "Module.Launched" -Message "Trung tâm quản lý license doanh nghiệp" -Data ([ordered]@{
                ModuleId="license.manager"; ProcessId=$enterpriseProcess.Id; LaunchMode="--enterprise-ui"; OfflineMode=[bool]$script:offlineMode
            }))
        } else {
            $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$licenseManagerScript`""
            [void](Start-DetachedToolModuleProcess -ModuleId "license.manager" -Arguments $arguments -Elevate)
        }
        $status.Text = Get-ToolText -Key "status.enterprise.opened" -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog (Get-ToolText -Key "status.enterprise.adminNotice" -Culture $script:dashboardCulture)
        Stop-ProgressDisplay $status.Text
    } catch {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            $status.Text = Get-ToolText -Key "status.enterprise.cancelled" -Culture $script:dashboardCulture
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-ToolText -Key "status.enterprise.cancelledLog" -Culture $script:dashboardCulture)
        } else {
            $status.Text = Get-ToolText -Key "status.enterprise.failed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
            $status.ForeColor = [System.Drawing.Color]::DarkRed
            Write-ProgressLog $status.Text
        }
        Stop-ProgressDisplay $status.Text
    }
}

function Test-GuideHeading {
    param([AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $trimmed = $Line.Trim()
    if ($trimmed -match '^#{1,4}\s+(.+)$') {
        return [string]$matches[1].Trim()
    }
    if ($trimmed.Length -le 130 -and $trimmed -notmatch '^[-+*]\s+' -and $trimmed -notmatch '[.!?:;]$') {
        $lettersOnly = $trimmed -replace '[^A-Za-zÀ-ỹĐđ]', ''
        if ($lettersOnly.Length -ge 4 -and $trimmed -ceq $trimmed.ToUpperInvariant()) {
            return $trimmed
        }
    }
    return $null
}

function Convert-GuideLinesToHtml {
    param([AllowNull()][object[]]$Lines)

    $htmlBuilder = New-Object Text.StringBuilder
    $listType = ""
    $insideCode = $false
    foreach ($rawLine in @($Lines)) {
        $line = [string]$rawLine
        $trimmed = $line.Trim()
        if ($trimmed -eq '```powershell' -or $trimmed -eq '```') {
            if (-not [string]::IsNullOrWhiteSpace($listType)) {
                [void]$htmlBuilder.Append("</$listType>")
                $listType = ""
            }
            if ($insideCode) {
                [void]$htmlBuilder.Append("</code></pre>")
                $insideCode = $false
            } else {
                [void]$htmlBuilder.Append("<pre class='guide-code'><code>")
                $insideCode = $true
            }
            continue
        }
        if ($insideCode) {
            [void]$htmlBuilder.Append((ConvertTo-ToolHtmlText $line))
            [void]$htmlBuilder.Append("`n")
            continue
        }
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if (-not [string]::IsNullOrWhiteSpace($listType)) {
                [void]$htmlBuilder.Append("</$listType>")
                $listType = ""
            }
            continue
        }

        $targetList = ""
        $itemText = ""
        if ($trimmed -match '^[-+*]\s+(.+)$') {
            $targetList = "ul"
            $itemText = [string]$matches[1]
        } elseif ($trimmed -match '^\d+[.)]\s+(.+)$') {
            $targetList = "ol"
            $itemText = [string]$matches[1]
        }
        if (-not [string]::IsNullOrWhiteSpace($targetList)) {
            if ($listType -ne $targetList) {
                if (-not [string]::IsNullOrWhiteSpace($listType)) { [void]$htmlBuilder.Append("</$listType>") }
                [void]$htmlBuilder.Append("<$targetList>")
                $listType = $targetList
            }
            [void]$htmlBuilder.Append("<li>$(ConvertTo-ToolHtmlText $itemText)</li>")
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($listType)) {
            [void]$htmlBuilder.Append("</$listType>")
            $listType = ""
        }
        [void]$htmlBuilder.Append("<p>$(ConvertTo-ToolHtmlText $trimmed)</p>")
    }
    if (-not [string]::IsNullOrWhiteSpace($listType)) { [void]$htmlBuilder.Append("</$listType>") }
    if ($insideCode) { [void]$htmlBuilder.Append("</code></pre>") }
    return $htmlBuilder.ToString()
}

function Convert-GuideSourceToSections {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$FallbackTitle
    )

    $groups = New-Object System.Collections.ArrayList
    $documentTitle = $FallbackTitle
    $currentTitle = if ($script:dashboardCulture -eq "en-US") { "Overview" } else { "Tổng quan" }
    $currentLines = New-Object System.Collections.ArrayList
    $firstHeading = $true
    foreach ($line in $Lines) {
        $headingText = Test-GuideHeading -Line ([string]$line)
        if (-not [string]::IsNullOrWhiteSpace([string]$headingText)) {
            if ($firstHeading) {
                $documentTitle = [string]$headingText
                $firstHeading = $false
                continue
            }
            if ($currentLines.Count -gt 0) {
                [void]$groups.Add([pscustomobject][ordered]@{
                    Title = $currentTitle
                    BodyHtml = Convert-GuideLinesToHtml -Lines @($currentLines.ToArray())
                })
                $currentLines = New-Object System.Collections.ArrayList
            }
            $currentTitle = [string]$headingText
            continue
        }
        [void]$currentLines.Add([string]$line)
    }
    if ($currentLines.Count -gt 0 -or $groups.Count -eq 0) {
        [void]$groups.Add([pscustomobject][ordered]@{
            Title = $currentTitle
            BodyHtml = Convert-GuideLinesToHtml -Lines @($currentLines.ToArray())
        })
    }
    return [pscustomobject][ordered]@{ Title=$documentTitle; Sections=@($groups.ToArray()) }
}

function Open-ToolEmbeddedDocument {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$FilePrefix,
        [Parameter(Mandatory = $true)][string]$TitleKey,
        [Parameter(Mandatory = $true)][string]$SubtitleKey,
        [Parameter(Mandatory = $true)][string]$EyebrowKey,
        [Parameter(Mandatory = $true)][string]$FooterKey,
        [Parameter(Mandatory = $true)][string]$MissingKey,
        [Parameter(Mandatory = $true)][string]$ExportingKey,
        [Parameter(Mandatory = $true)][string]$ExportingDetailKey,
        [Parameter(Mandatory = $true)][string]$ExportedKey,
        [Parameter(Mandatory = $true)][string]$ExportFailedKey
    )

    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        $status.Text = Get-ToolText -Key $MissingKey -Culture $script:dashboardCulture
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        return
    }

    try {
        $documentAction = Get-ToolText -Key $ExportingKey -Culture $script:dashboardCulture
        Start-ProgressDisplay $documentAction (Get-ToolText -Key $ExportingDetailKey -Culture $script:dashboardCulture) $false
        [System.Windows.Forms.Application]::DoEvents()

        # Tên ổn định theo phiên bản/ngôn ngữ giúp mở lại tức thì và tránh tạo
        # nhiều bản trùng nhau trên Desktop. SHA-256 nguồn làm khóa cache.
        $documentRendererRevision = "2"
        $sourceHash = Get-ToolSha256Hex -Path $SourceFile
        $documentBasePath = Join-Path $desktop "$FilePrefix-v$releaseVersion-$($script:dashboardCulture)"
        $htmlPath = "$documentBasePath.html"
        $pdfPath = "$documentBasePath.pdf"
        $manifestPath = "${documentBasePath}-SHA256SUMS.txt"
        $cacheValid = $false
        $pdfCacheValid = $false
        if ((Test-Path -LiteralPath $htmlPath -PathType Leaf) -and
            (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $manifestLines = @([IO.File]::ReadAllLines($manifestPath, [Text.Encoding]::UTF8))
            $htmlHash = Get-ToolSha256Hex -Path $htmlPath
            $cacheValid = [bool](
                $manifestLines -contains "# Source-SHA256: $sourceHash" -and
                $manifestLines -contains "# Renderer-Revision: $documentRendererRevision" -and
                $manifestLines -contains "$htmlHash  $([IO.Path]::GetFileName($htmlPath))" -and
                (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)
            )
            if ($cacheValid -and (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
                $pdfHash = Get-ToolSha256Hex -Path $pdfPath
                $pdfCacheValid = [bool]($manifestLines -contains "$pdfHash  $([IO.Path]::GetFileName($pdfPath))")
            }
        }

        if (-not $cacheValid) {
            $sourceLines = [IO.File]::ReadAllLines($SourceFile, [Text.Encoding]::UTF8)
            $fallbackTitle = Get-ToolText -Key $TitleKey -Culture $script:dashboardCulture
            $document = Convert-GuideSourceToSections -Lines $sourceLines -FallbackTitle $fallbackTitle
            $metadata = @(
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.version" -Culture $script:dashboardCulture); Value=$releaseDisplayName },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.language" -Culture $script:dashboardCulture); Value=$script:dashboardCulture },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.format" -Culture $script:dashboardCulture); Value="HTML / PDF · A4" }
            )
            $cards = @(
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.complete" -Culture $script:dashboardCulture); Value="100%"; Tone="ok" },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.sections" -Culture $script:dashboardCulture); Value=[string](@($document.Sections).Count); Tone="info" },
                [pscustomobject]@{ Label=(Get-ToolText -Key "guide.lines" -Culture $script:dashboardCulture); Value=[string]$sourceLines.Count; Tone="info" }
            )
            $html = New-ToolProfessionalHtmlDocument `
                -Title ([string]$document.Title) `
                -Subtitle (Get-ToolText -Key $SubtitleKey -Culture $script:dashboardCulture) `
                -Eyebrow (Get-ToolText -Key $EyebrowKey -Culture $script:dashboardCulture) `
                -Metadata $metadata -Cards $cards -Sections @($document.Sections) `
                -Footer (Get-ToolText -Key $FooterKey -Culture $script:dashboardCulture) `
                -Culture $script:dashboardCulture -OfflineMode $true
            $documentCss = @'
.guide-code{background:#111827;border-radius:8px;color:#e5e7eb;overflow:auto;padding:12px 14px;white-space:pre-wrap}
section p{margin:6px 0}section li{margin:4px 0}section ul,section ol{padding-left:25px}
@media print{section{break-inside:auto!important}.guide-code{background:#f4f4f4!important;color:#111!important}}
'@
            $html = $html.Replace("</style>", "$documentCss`r`n</style>")
            foreach ($stalePath in @($htmlPath, $pdfPath, $manifestPath)) {
                if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
                    Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
                }
            }
            [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
            if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) {
                if ($script:dashboardCulture -eq "en-US") { throw "The HTML document failed the local-only safety check." }
                throw "Tài liệu HTML không đạt kiểm tra an toàn ngoại tuyến."
            }
            $initialHashLines = @(
                "# SHA-256 local documentation package.",
                "# Source-SHA256: $sourceHash",
                "# Renderer-Revision: $documentRendererRevision",
                "$(Get-ToolSha256Hex -Path $htmlPath)  $([IO.Path]::GetFileName($htmlPath))"
            )
            [IO.File]::WriteAllLines($manifestPath, $initialHashLines, (New-Object Text.UTF8Encoding($false)))
        }

        # Mở HTML ngay sau khi có tệp hợp lệ. Tạo PDF diễn ra sau đó nên người
        # dùng không còn phải chờ Edge/Chrome/Word trước khi đọc hướng dẫn.
        Register-ToolReportPath -Path $htmlPath
        Start-Process -FilePath $htmlPath
        $status.Text = Get-ToolText -Key $ExportedKey -Culture $script:dashboardCulture -FormatArguments @([IO.Path]::GetFileName($htmlPath))
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog $status.Text
        Stop-ProgressDisplay $status.Text
        [System.Windows.Forms.Application]::DoEvents()

        if (-not $pdfCacheValid) {
            $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
            $hashLines = @(
                "# SHA-256 local documentation package.",
                "# Source-SHA256: $sourceHash",
                "# Renderer-Revision: $documentRendererRevision",
                "$(Get-ToolSha256Hex -Path $htmlPath)  $([IO.Path]::GetFileName($htmlPath))"
            )
            if ($pdfResult.Success -and (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
                $hashLines += "$(Get-ToolSha256Hex -Path $pdfPath)  $([IO.Path]::GetFileName($pdfPath))"
                Write-ProgressLog (Get-ToolText -Key "document.pdfSaved" -Culture $script:dashboardCulture -FormatArguments @([IO.Path]::GetFileName($pdfPath)))
            } else {
                Write-ProgressLog (Get-ToolText -Key "document.pdfFailed" -Culture $script:dashboardCulture -FormatArguments @([string]$pdfResult.Error))
            }
            [IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))
        } else {
            Write-ProgressLog (Get-ToolText -Key "document.cacheUsed" -Culture $script:dashboardCulture)
        }
    } catch {
        $status.Text = Get-ToolText -Key $ExportFailedKey -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
        Stop-ProgressDisplay $status.Text
    }
}

function Open-Guide {
    $selectedGuideFile = if ($script:dashboardCulture -eq "en-US") { $englishGuideFile } else { $guideFile }
    Open-ToolEmbeddedDocument `
        -SourceFile $selectedGuideFile -FilePrefix "HUONG-DAN-Tool-Kiem-Tra" `
        -TitleKey "guide.title" -SubtitleKey "guide.subtitle" -EyebrowKey "guide.eyebrow" -FooterKey "guide.footer" `
        -MissingKey "guide.missing" -ExportingKey "guide.exporting" -ExportingDetailKey "guide.exportingDetail" `
        -ExportedKey "guide.exported" -ExportFailedKey "guide.exportFailed"
}

function Open-VersionHistory {
    if (-not (Test-Path -LiteralPath $historyFile -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "history.missing" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "history.title" -Culture $script:dashboardCulture), "OK", "Warning") | Out-Null
        return
    }
    try {
        $dialog = New-Object System.Windows.Forms.Form
        $dialog.Text = Get-ToolText -Key "history.title" -Culture $script:dashboardCulture
        $dialog.StartPosition = "CenterParent"
        $dialog.ShowInTaskbar = $false
        $dialog.MinimizeBox = $false
        $dialog.MaximizeBox = $true
        $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $dialog.ClientSize = New-Object System.Drawing.Size(850, 620)
        $dialog.MinimumSize = New-Object System.Drawing.Size(620, 440)
        $dialog.Font = $fontNormal

        $heading = New-Object System.Windows.Forms.Label
        $heading.Text = Get-ToolText -Key "history.eyebrow" -Culture $script:dashboardCulture
        $heading.Font = $fontTitle
        $heading.Location = New-Object System.Drawing.Point(18, 14)
        $heading.Size = New-Object System.Drawing.Size(800, 38)
        $heading.Anchor = "Top,Left,Right"
        $dialog.Controls.Add($heading)

        $historyBox = New-Object System.Windows.Forms.RichTextBox
        $historyBox.ReadOnly = $true
        $historyBox.DetectUrls = $false
        $historyBox.WordWrap = $true
        $historyBox.ScrollBars = "Vertical"
        $historyBox.Font = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize)
        $historyBox.Location = New-Object System.Drawing.Point(18, 58)
        $historyBox.Size = New-Object System.Drawing.Size(814, 500)
        $historyBox.Anchor = "Top,Bottom,Left,Right"
        $historyBox.Text = [IO.File]::ReadAllText($historyFile, [Text.Encoding]::UTF8)
        $dialog.Controls.Add($historyBox)

        $copyButton = New-Object System.Windows.Forms.Button
        $copyButton.Text = Get-ToolText -Key "history.copy" -Culture $script:dashboardCulture
        $copyButton.Size = New-Object System.Drawing.Size(150, 32)
        $copyButton.Location = New-Object System.Drawing.Point(18, 572)
        $copyButton.Anchor = "Bottom,Left"
        $copyButton.Add_Click({ if ($historyBox.TextLength -gt 0) { [System.Windows.Forms.Clipboard]::SetText($historyBox.Text) } })
        $dialog.Controls.Add($copyButton)

        $close = New-Object System.Windows.Forms.Button
        $close.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
        $close.Size = New-Object System.Drawing.Size(120, 32)
        $close.Location = New-Object System.Drawing.Point(712, 572)
        $close.Anchor = "Bottom,Right"
        $close.Add_Click({ $dialog.Close() })
        $dialog.Controls.Add($close)
        $dialog.AcceptButton = $close
        $dialog.CancelButton = $close
        Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
        [void]$dialog.ShowDialog($form)
        $historyBox.Font.Dispose()
        $dialog.Dispose()
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "history.openFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message)),
            (Get-ToolText -Key "history.title" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
    }
}

function Show-AdvancedScanMenu {
    $chooser = New-Object System.Windows.Forms.Form
    $chooser.Text = Get-ToolText -Key "advanced.form.title" -Culture $script:dashboardCulture
    $chooser.StartPosition = "CenterParent"
    $chooser.FormBorderStyle = "FixedDialog"
    $chooser.MaximizeBox = $false
    $chooser.MinimizeBox = $false
    $chooser.ShowInTaskbar = $false
    $chooser.ClientSize = New-Object System.Drawing.Size(590, 248)
    $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $chooser.Font = $fontNormal
    $chooser.Tag = ""

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "advanced.heading" -Culture $script:dashboardCulture
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(20, 12)
    $heading.Size = New-Object System.Drawing.Size(550, 34)
    $chooser.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-ToolText -Key "advanced.hint" -Culture $script:dashboardCulture
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleCenter"
    $hint.Location = New-Object System.Drawing.Point(28, 48)
    $hint.Size = New-Object System.Drawing.Size(534, 32)
    $chooser.Controls.Add($hint)

    $deepButton = New-Object System.Windows.Forms.Button
    $deepButton.Text = Get-ToolText -Key "advanced.deep.title" -Culture $script:dashboardCulture
    $deepButton.Font = $fontBold
    $deepButton.TextAlign = "MiddleLeft"
    $deepButton.Location = New-Object System.Drawing.Point(34, 88)
    $deepButton.Size = New-Object System.Drawing.Size(522, 42)
    $deepButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $deepButton.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $deepButton.FlatStyle = "Flat"
    $deepButton.Add_Click({ $chooser.Tag = "Deep"; $chooser.Close() })
    $chooser.Controls.Add($deepButton)

    $forensicsButton = New-Object System.Windows.Forms.Button
    $forensicsButton.Text = Get-ToolText -Key "advanced.forensics.title" -Culture $script:dashboardCulture
    $forensicsButton.Font = $fontBold
    $forensicsButton.TextAlign = "MiddleLeft"
    $forensicsButton.Location = New-Object System.Drawing.Point(34, 136)
    $forensicsButton.Size = New-Object System.Drawing.Size(522, 42)
    $forensicsButton.BackColor = [System.Drawing.Color]::FromArgb(232, 247, 240)
    $forensicsButton.ForeColor = [System.Drawing.Color]::FromArgb(20, 96, 66)
    $forensicsButton.FlatStyle = "Flat"
    $forensicsButton.Add_Click({ $chooser.Tag = "Forensics"; $chooser.Close() })
    $chooser.Controls.Add($forensicsButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
    $cancelButton.Location = New-Object System.Drawing.Point(448, 194)
    $cancelButton.Size = New-Object System.Drawing.Size(108, 32)
    $cancelButton.Add_Click({ $chooser.Tag = ""; $chooser.Close() })
    $chooser.CancelButton = $cancelButton
    $chooser.Controls.Add($cancelButton)

    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void]$chooser.ShowDialog($form)
    $choice = [string]$chooser.Tag
    $chooser.Dispose()
    if ($choice -eq "Deep") { Start-DeepLicenseScan; return }
    if ($choice -eq "Forensics") { Start-ForensicsScan; return }
    $status.Text = "Đã hủy lựa chọn kiểm tra chuyên sâu."
    $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
}

function Start-CleanupBackup {
    if (-not (Confirm-IntegrityForElevatedAction "tạo backup")) { return }
    if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy script backup trước khi thực hiện.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay "Backup trước khi thực hiện" "Đang chờ quyền Quản trị viên và sao lưu trạng thái hiện tại..." $true
        $output = Join-Path $desktop "bao-cao-go-ban-quyen"
        $script:backupResultFile = New-SecureRuntimePath "tool-license-backup-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$backupScript`" -OutputDir `"$output`" -DecisionFile `"$script:backupResultFile`""
        [void](Start-ToolModuleProcess -ModuleId "backup.create" -Arguments $arguments -Action "Backup trước khi thực hiện" -Elevate)
        $status.Text = "Đang backup Registry, task, service và dữ liệu liên quan..."
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Write-ProgressLog "Đang tạo bản backup độc lập; chức năng này không gỡ hoặc thay đổi cấu hình cấp phép."
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = "Đã hủy quyền Administrator hoặc không thể chạy backup."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-CleanupBackup {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:backupResultFile -PathType Leaf)) {
            throw "Không nhận được kết quả backup."
        }
        $result = Get-Content -LiteralPath $script:backupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:backupResultFile -Force -ErrorAction SilentlyContinue
        $script:backupResultFile = ""
        $message = "$($result.Message)`r`n`r`nSố mục đã backup: $($result.ItemCount)`r`nCảnh báo/lỗi: $($result.ErrorCount)`r`n`r`nThư mục backup:`r`n$($result.BackupDirectory)"
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, "Backup hoàn tất", "OK", "Information") | Out-Null
            $status.Text = "Backup trước khi thực hiện đã hoàn tất."
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, "Backup có cảnh báo", "OK", "Warning") | Out-Null
            $status.Text = "Backup hoàn tất nhưng có mục cần kiểm tra."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog "Bộ backup và script khôi phục: $($result.BackupDirectory)"
        Write-ProgressLog "Thư mục backup được khóa cho Administrators/SYSTEM; dùng nút Khôi phục tự động để mở và xác thực."
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title "Báo cáo sao lưu trước khi khắc phục" -FilePrefix "BaoCao_Muc6_Backup")
        }
    } catch {
        $status.Text = "Không đọc được kết quả backup: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Show-RestorePreview($manifest, [string]$backupDir) {
    $items = @($manifest.Items)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Xem toàn bộ danh sách trước khi khôi phục"
    $dialog.StartPosition = "CenterParent"
    $dialog.MinimumSize = New-Object System.Drawing.Size(760, 500)
    $dialog.ClientSize = New-Object System.Drawing.Size(920, 590)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = $false

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "Đối chiếu $($items.Count) mục sẽ được kiểm tra để khôi phục"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.Location = New-Object System.Drawing.Point(18, 12)
    $heading.Size = New-Object System.Drawing.Size(884, 36)
    $heading.TextAlign = "MiddleCenter"
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $sourceLabel = New-Object System.Windows.Forms.Label
    $sourceLabel.Text = "Nguồn: $backupDir"
    $sourceLabel.Location = New-Object System.Drawing.Point(20, 50)
    $sourceLabel.Size = New-Object System.Drawing.Size(880, 24)
    $sourceLabel.AutoEllipsis = $true
    $sourceLabel.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($sourceLabel)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.Location = New-Object System.Drawing.Point(20, 78)
    $list.Size = New-Object System.Drawing.Size(880, 410)
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add("Loại", 125)
    [void]$list.Columns.Add("Tên", 220)
    [void]$list.Columns.Add("Vị trí gốc", 390)
    [void]$list.Columns.Add("Cách xử lý", 140)
    foreach ($item in $items) {
        $action = if ([string]$item.Type -eq "Defender") { "Bỏ qua an toàn" } elseif ([string]$item.Type -eq "LicenseNotice") { "Không thể tự phục hồi" } else { "Có thể phục hồi" }
        $row = New-Object System.Windows.Forms.ListViewItem([string]$item.Type)
        [void]$row.SubItems.Add([string]$item.Name)
        [void]$row.SubItems.Add([string]$item.OriginalPath)
        [void]$row.SubItems.Add($action)
        [void]$list.Items.Add($row)
    }
    $dialog.Controls.Add($list)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "Sau khi xác nhận, script vẫn phải đạt ACL + HMAC + đúng máy + SHA-256 từng dữ liệu. Tệp/thư mục đang tồn tại không bị ghi đè; ngoại lệ Defender không tự được thêm lại."
    $note.Location = New-Object System.Drawing.Point(20, 496)
    $note.Size = New-Object System.Drawing.Size(690, 48)
    $note.Anchor = "Bottom,Left,Right"
    $dialog.Controls.Add($note)

    $confirm = New-Object System.Windows.Forms.Button
    $confirm.Text = "Xác nhận khôi phục"
    $confirm.Font = $fontBold
    $confirm.Location = New-Object System.Drawing.Point(714, 514)
    $confirm.Size = New-Object System.Drawing.Size(150, 36)
    $confirm.Anchor = "Bottom,Right"
    $confirm.Add_Click({ $dialog.Tag = $true; $dialog.Close() })
    $dialog.Controls.Add($confirm)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Thoát"
    $cancel.Location = New-Object System.Drawing.Point(714, 552)
    $cancel.Size = New-Object System.Drawing.Size(150, 30)
    $cancel.Anchor = "Bottom,Right"
    $cancel.Add_Click({ $dialog.Close() })
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $confirmed = [bool]$dialog.Tag
    $dialog.Dispose()
    return $confirmed
}

function Start-CleanupRestore {
    if (-not (Confirm-IntegrityForElevatedAction "khôi phục tự động")) { return }
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy script khôi phục tự động.", "Lỗi", "OK", "Error") | Out-Null
        return
    }
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = "Chọn thư mục backup_pre_cleanup_* hoặc quarantine_* trong vùng ProgramData bảo vệ"
    $picker.ShowNewFolderButton = $false
    $secureBackupRoot = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.4\backups"
    if (Test-Path -LiteralPath $secureBackupRoot -PathType Container) { $picker.SelectedPath = $secureBackupRoot }
    if ($picker.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        $picker.Dispose()
        return
    }
    $backupDir = $picker.SelectedPath
    $picker.Dispose()
    $manifestPath = Join-Path $backupDir "RESTORE-MANIFEST.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Thư mục đã chọn không có RESTORE-MANIFEST.json.", "Không đúng thư mục backup", "OK", "Warning") | Out-Null
        return
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $itemCount = @($manifest.Items).Count
        if ([string]$manifest.SchemaVersion -ne "2.0" -or [string]$manifest.ToolVersion -ne $toolVersion) { throw "Backup không đúng SchemaVersion 2.0 / ToolVersion $toolVersion." }
    } catch {
        $manifestError = "Không đọc được manifest khôi phục: $($_.Exception.Message)`r`n`r`nHướng xử lý: dừng gỡ tiếp, giữ nguyên thư mục backup và không sửa/xóa các tệp RESTORE-*. Hãy tạo backup mới bằng bản tool đã sửa; không được bỏ qua cảnh báo HMAC, ACL hoặc SHA-256."
        [System.Windows.Forms.MessageBox]::Show($manifestError, "Manifest không hợp lệ", "OK", "Error") | Out-Null
        return
    }
    if ($itemCount -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Manifest không có mục nào để khôi phục.", "Không có dữ liệu", "OK", "Information") | Out-Null
        return
    }
    if (-not (Show-RestorePreview -manifest $manifest -backupDir $backupDir)) { return }

    try {
        Start-ProgressDisplay "Khôi phục tự động" "Đang chờ quyền Quản trị viên và phục hồi các mục đã sao lưu..." $true
        $script:restoreResultFile = New-SecureRuntimePath "tool-license-restore-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`" -BackupDir `"$backupDir`" -DecisionFile `"$script:restoreResultFile`""
        [void](Start-ToolModuleProcess -ModuleId "restore.apply" -Arguments $arguments -Action "Khôi phục tự động" -Elevate)
        $status.Text = "Đang khôi phục từ bản sao lưu đã chọn..."
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog "Đang khôi phục $itemCount mục từ $backupDir"
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = "Đã hủy quyền Administrator hoặc không thể chạy khôi phục."
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-CleanupRestore {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:restoreResultFile -PathType Leaf)) {
            throw "Không nhận được kết quả khôi phục."
        }
        $result = Get-Content -LiteralPath $script:restoreResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:restoreResultFile -Force -ErrorAction SilentlyContinue
        $script:restoreResultFile = ""
        [void](Write-LicenseTimelineEventSafe -EventType "LicenseRestoreCompleted" -Source "GUI" -IsChange:([bool]([int]$result.RestoredCount -gt 0)) -Data ([ordered]@{
            Success=[bool]$result.Success
            RestoredCount=[int]$result.RestoredCount
            SkippedCount=[int]$result.SkippedCount
            ErrorCount=[int]$result.ErrorCount
        }))
        $restoreNextStep = if ([int]$result.ErrorCount -gt 0) { "`r`n`r`nHướng xử lý: dừng gỡ tiếp, giữ nguyên backup, mở báo cáo để xử lý đúng lỗi rồi thử lại bằng bản tool mới nhất. Không bỏ qua kiểm tra ACL/HMAC/đúng máy/SHA-256." } else { "`r`n`r`nBước tiếp theo: quét lại mục 6; chỉ kích hoạt bằng giấy phép chính thức hoặc KMS nội bộ đã được xác nhận." }
        $message = "$($result.Message)`r`n`r`nĐã phục hồi: $($result.RestoredCount)`r`nBỏ qua an toàn: $($result.SkippedCount)`r`nLỗi: $($result.ErrorCount)$restoreNextStep`r`n`r`nBáo cáo: $($result.ReportPath)"
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, "Khôi phục tự động hoàn tất", "OK", "Information") | Out-Null
            $status.Text = "Khôi phục tự động hoàn tất."
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, "Khôi phục còn mục lỗi", "OK", "Warning") | Out-Null
            $status.Text = "Khôi phục hoàn tất nhưng còn mục cần kiểm tra."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog $message
        if (Test-Path -LiteralPath $result.ReportPath) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title "Báo cáo khôi phục tự động" -FilePrefix "BaoCao_Muc6_KhoiPhuc")
        }
    } catch {
        $status.Text = "Không đọc được kết quả khôi phục: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
        Write-ProgressLog "Hướng xử lý: dừng gỡ tiếp, giữ nguyên backup; nếu lỗi là 'Argument types do not match' thì bỏ bản EXE cũ và tạo backup mới bằng bản đã sửa."
        [System.Windows.Forms.MessageBox]::Show("$($status.Text)`r`n`r`nDừng gỡ tiếp và giữ nguyên thư mục backup. Nếu lỗi là 'Argument types do not match', không dùng lại bản EXE cũ; hãy tạo backup mới bằng bản đã sửa.", "Không thể hoàn tất khôi phục", "OK", "Error") | Out-Null
    }
}

function Show-CleanupFunctionScreen {
    param([ValidateSet("Backup","Cleanup","Restore","AutoCleanup")][string]$Mode)
    $titles = @{
        Backup="1. Backup trước khi thực hiện"
        Cleanup="2. Kiểm tra và gỡ KMS/crack"
        Restore="3. Khôi phục tự động từ thư mục backup"
        AutoCleanup="4. Tự động làm sạch an toàn"
    }
    $descriptions = @{
        Backup="Tạo một thư mục backup độc lập trong vùng ProgramData bảo vệ, gồm Registry cấp phép, task, service, tệp/thư mục liên quan và script khôi phục tự động. Chức năng này không thực hiện gỡ."
        Cleanup="Kiểm tra Windows và Office, sau đó hiển thị danh sách chi tiết để đánh dấu từng mục trước khi gỡ. Khóa OEM/Retail/MAK và KMS nội bộ đã phê duyệt được bảo vệ."
        Restore="Chọn thư mục backup_pre_cleanup_* hoặc quarantine_* có RESTORE-MANIFEST.json để khôi phục tự động các mục đã sao lưu."
        AutoCleanup="Quét trước, tự chọn riêng cấu hình Registry cấp phép nằm trong allowlist và có thể khôi phục, cho xem trước rồi mới xử lý. Không tự gỡ key, service, task, tiến trình, tệp hoặc lịch sử Event Log."
    }
    $actionTexts = @{ Backup="Bắt đầu backup"; Cleanup="Bắt đầu kiểm tra"; Restore="Chọn thư mục backup"; AutoCleanup="Quét và xử lý" }

    $screen = New-Object System.Windows.Forms.Form
    $screen.Text = $titles[$Mode]
    $screen.StartPosition = "CenterParent"
    $screen.FormBorderStyle = "FixedDialog"
    $screen.MaximizeBox = $false
    $screen.MinimizeBox = $false
    $screen.ShowInTaskbar = $false
    $screen.ClientSize = New-Object System.Drawing.Size(640, 270)
    $screen.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $screen.Font = $fontNormal
    $screen.Tag = "Back"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $titles[$Mode]
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(20, 16)
    $heading.Size = New-Object System.Drawing.Size(600, 40)
    $screen.Controls.Add($heading)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = $descriptions[$Mode]
    $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $descriptionLabel.Location = New-Object System.Drawing.Point(42, 72)
    $descriptionLabel.Size = New-Object System.Drawing.Size(556, 92)
    $screen.Controls.Add($descriptionLabel)

    $actionButton = New-Object System.Windows.Forms.Button
    $actionButton.Text = $actionTexts[$Mode]
    $actionButton.Font = $fontBold
    $actionButton.Location = New-Object System.Drawing.Point(326, 196)
    $actionButton.Size = New-Object System.Drawing.Size(142, 40)
    $actionButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $actionButton.Add_Click({ $screen.Tag = "Action"; $screen.Close() })
    $screen.Controls.Add($actionButton)

    $backButton = New-Object System.Windows.Forms.Button
    $backButton.Text = "Trở về"
    $backButton.Font = $fontBold
    $backButton.Location = New-Object System.Drawing.Point(478, 196)
    $backButton.Size = New-Object System.Drawing.Size(120, 40)
    $backButton.Add_Click({ $screen.Tag = "Back"; $screen.Close() })
    $screen.CancelButton = $backButton
    $screen.Controls.Add($backButton)

    Set-ToolWindowTheme -Root $screen -Mode $script:dashboardTheme
    [void]$screen.ShowDialog($form)
    $choice = [string]$screen.Tag
    $screen.Dispose()
    if ($choice -ne "Action") { return $false }
    if ($Mode -eq "Backup") { Start-CleanupBackup }
    elseif ($Mode -eq "Cleanup") { Start-Cleanup }
    elseif ($Mode -eq "Restore") { Start-CleanupRestore }
    elseif ($Mode -eq "AutoCleanup") { Start-Cleanup -AutoSafeMode }
    return $true
}

function Show-CleanupMenu {
    while ($true) {
        $chooser = New-Object System.Windows.Forms.Form
        $chooser.Text = "Mục 6 - Kiểm tra và gỡ KMS/crack"
        $chooser.StartPosition = "CenterParent"
        $chooser.FormBorderStyle = "FixedDialog"
        $chooser.MaximizeBox = $false
        $chooser.MinimizeBox = $false
        $chooser.ShowInTaskbar = $false
        $chooser.ClientSize = New-Object System.Drawing.Size(650, 390)
        $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
        $chooser.Font = $fontNormal
        $chooser.Tag = ""

        $heading = New-Object System.Windows.Forms.Label
        $heading.Text = "Kiểm tra và gỡ KMS/crack, đưa Windows và Office về trạng thái gốc"
        $heading.Font = $fontTitle
        $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        $heading.TextAlign = "MiddleCenter"
        $heading.Location = New-Object System.Drawing.Point(18, 12)
        $heading.Size = New-Object System.Drawing.Size(614, 48)
        $chooser.Controls.Add($heading)

        $backupButton = New-Object System.Windows.Forms.Button
        $backupButton.Text = "1. Backup trước khi thực hiện"
        $backupButton.Font = $fontBold
        $backupButton.TextAlign = "MiddleLeft"
        $backupButton.Location = New-Object System.Drawing.Point(44, 76)
        $backupButton.Size = New-Object System.Drawing.Size(562, 48)
        $backupButton.BackColor = [System.Drawing.Color]::FromArgb(232, 247, 240)
        $backupButton.Add_Click({ $chooser.Tag = "Backup"; $chooser.Close() })
        $chooser.Controls.Add($backupButton)

        $cleanupButton = New-Object System.Windows.Forms.Button
        $cleanupButton.Text = "2. Kiểm tra và gỡ, đưa Windows và Office về trạng thái gốc"
        $cleanupButton.Font = $fontBold
        $cleanupButton.TextAlign = "MiddleLeft"
        $cleanupButton.Location = New-Object System.Drawing.Point(44, 132)
        $cleanupButton.Size = New-Object System.Drawing.Size(562, 48)
        $cleanupButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
        $cleanupButton.Add_Click({ $chooser.Tag = "Cleanup"; $chooser.Close() })
        $chooser.Controls.Add($cleanupButton)

        $restoreButton = New-Object System.Windows.Forms.Button
        $restoreButton.Text = "3. Khôi phục tự động từ thư mục backup"
        $restoreButton.Font = $fontBold
        $restoreButton.TextAlign = "MiddleLeft"
        $restoreButton.Location = New-Object System.Drawing.Point(44, 188)
        $restoreButton.Size = New-Object System.Drawing.Size(562, 48)
        $restoreButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
        $restoreButton.Add_Click({ $chooser.Tag = "Restore"; $chooser.Close() })
        $chooser.Controls.Add($restoreButton)

        $autoCleanupButton = New-Object System.Windows.Forms.Button
        $autoCleanupButton.Text = "4. Tự động làm sạch an toàn, sẵn sàng kích hoạt"
        $autoCleanupButton.Font = $fontBold
        $autoCleanupButton.TextAlign = "MiddleLeft"
        $autoCleanupButton.Location = New-Object System.Drawing.Point(44, 244)
        $autoCleanupButton.Size = New-Object System.Drawing.Size(562, 48)
        $autoCleanupButton.BackColor = [System.Drawing.Color]::FromArgb(255, 238, 238)
        $autoCleanupButton.Add_Click({ $chooser.Tag = "AutoCleanup"; $chooser.Close() })
        $chooser.Controls.Add($autoCleanupButton)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Trở về"
        $cancelButton.Font = $fontBold
        $cancelButton.Location = New-Object System.Drawing.Point(486, 326)
        $cancelButton.Size = New-Object System.Drawing.Size(120, 38)
        $cancelButton.Add_Click({ $chooser.Close() })
        $chooser.CancelButton = $cancelButton
        $chooser.Controls.Add($cancelButton)

        Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
        [void]$chooser.ShowDialog($form)
        $choice = [string]$chooser.Tag
        $chooser.Dispose()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $status.Text = "Đã trở về giao diện chính; chưa thay đổi hệ thống."
            $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
            return
        }
        if (Show-CleanupFunctionScreen -Mode $choice) { return }
    }
}

function Start-AssuranceReport {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("CertificateAudit","PluginAudit","TimelineExport")][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $assuranceScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.missingModule" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "report.errorTitle" -Culture $script:dashboardCulture),
            "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-ToolText -Key "report.privacy.prompt" -Culture $script:dashboardCulture),
        (Get-ToolText -Key "report.privacy.title" -Culture $script:dashboardCulture),
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $redactArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay $DisplayName (Get-ToolText -Key "report.starting" -Culture $script:dashboardCulture) $false
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$assuranceScript`" -Operation `"$Operation`" -OutputDir `"$desktop`" -Culture `"$script:dashboardCulture`" -Pdf$redactArgument"
        [void](Start-ToolModuleProcess -ModuleId $ModuleId -Arguments $arguments -Action $DisplayName -Hidden)
        $status.Text = Get-ToolText -Key "report.running" -Culture $script:dashboardCulture -FormatArguments @($DisplayName)
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-ToolText -Key "report.startFailed" -Culture $script:dashboardCulture -FormatArguments @($_.Exception.Message))
    }
}

function Install-PluginFromDialog {
    $pluginDirectory = Get-ToolPluginDirectory
    try {
        if (-not (Test-Path -LiteralPath $pluginDirectory -PathType Container) -and $env:TOOL_SECURE_LAUNCH -ne "1") {
            New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null
        }
        $directoryState = Test-ToolPluginDirectory -Path $pluginDirectory
        if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title = "Chọn plugin JSON khai báo"
        $picker.Filter = "Tool plugin (*.plugin.json)|*.plugin.json"
        $picker.Multiselect = $false
        if ($picker.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $package = Read-ToolPluginPackage -Path $picker.FileName -AllowOutsideProtectedDirectory
        if (-not $package.Valid) { throw ($package.Errors -join "`r`n") }
        $plugin = $package.Plugin
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Cài plugin chỉ đọc sau?`r`n`r`nTên: $($plugin.Name)`r`nID: $($plugin.PluginId)`r`nPhiên bản: $($plugin.Version)`r`nNhà phát hành: $($plugin.Publisher)`r`nQuy tắc: $(@($plugin.Rules).Count)`r`nSHA-256: $($package.Sha256)`r`n`r`nPlugin không được chạy script/command; mọi trường ngoài schema sẽ bị từ chối.",
            "Xác nhận cài plugin",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $destination = Join-Path $directoryState.Path "$([string]$plugin.PluginId).plugin.json"
        $force = $false
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                "Plugin ID này đã tồn tại. Ghi đè sau khi xác minh schema/SHA-256?",
                "Plugin đã tồn tại", "YesNo", "Warning")
            if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $force = $true
        }
        $installed = Install-ToolPluginPackage -SourcePath $package.Path -PluginDirectory $directoryState.Path -Force:$force
        [void](Write-ToolLog -Level "AUDIT" -Event "Plugin.Installed" -Message $installed.Name -Data ([ordered]@{
            PluginId=$installed.PluginId; Version=$installed.Version; Publisher=$installed.Publisher; Sha256=$installed.Sha256
        }))
        [void](Write-LicenseTimelineEventSafe -EventType "PluginInstalled" -Source "GUI" -IsChange:$true -Data ([ordered]@{
            PluginId=$installed.PluginId; Version=$installed.Version; Publisher=$installed.Publisher; Sha256=$installed.Sha256
        }))
        [System.Windows.Forms.MessageBox]::Show(
            "Đã cài và xác minh plugin:`r`n$($installed.Path)`r`n`r`nSHA-256: $($installed.Sha256)",
            "Cài plugin hoàn tất", "OK", "Information") | Out-Null
        Write-ProgressLog "Đã cài plugin $($installed.PluginId) $($installed.Version)."
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Không cài được plugin", "OK", "Error") | Out-Null
        Write-ProgressLog "Plugin bị từ chối: $($_.Exception.Message)"
    }
}

function Show-AssuranceCenter {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key "assurance.form.title" -Culture $script:dashboardCulture
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(720, 590)
    $dialog.MinimumSize = New-Object System.Drawing.Size(620, 540)
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.AutoScroll = $true
    $dialog.Font = $fontNormal
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Tag = ""

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ToolText -Key "assurance.heading" -Culture $script:dashboardCulture
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.Location = New-Object System.Drawing.Point(28, 18)
    $heading.Size = New-Object System.Drawing.Size(640, 38)
    $dialog.Controls.Add($heading)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key "assurance.description" -Culture $script:dashboardCulture
    $descriptionLabel.Location = New-Object System.Drawing.Point(30, 60)
    $descriptionLabel.Size = New-Object System.Drawing.Size(640, 42)
    $dialog.Controls.Add($descriptionLabel)

    $choices = @(
        @{Tag="Certificate"; Text=(Get-ToolText -Key "assurance.certificate" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(234,242,255)},
        @{Tag="PluginAudit"; Text=(Get-ToolText -Key "assurance.pluginAudit" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(232,247,240)},
        @{Tag="Timeline"; Text=(Get-ToolText -Key "assurance.timeline" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(255,248,230)},
        @{Tag="InstallPlugin"; Text=(Get-ToolText -Key "assurance.installPlugin" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(245,238,255)},
        @{Tag="PluginFolder"; Text=(Get-ToolText -Key "assurance.pluginFolder" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(244,246,249)},
        @{Tag="Guide"; Text=(Get-ToolText -Key "assurance.guide" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(244,246,249)},
        @{Tag="History"; Text=(Get-ToolText -Key "assurance.history" -Culture $script:dashboardCulture); Color=[System.Drawing.Color]::FromArgb(238,246,255)}
    )
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $choice = $choices[$index]
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $choice.Text
        $button.Tag = $choice.Tag
        $button.Font = $fontBold
        $button.TextAlign = "MiddleLeft"
        $button.Location = New-Object System.Drawing.Point(42, (106 + ($index * 47)))
        $button.Size = New-Object System.Drawing.Size(620, 40)
        $button.Anchor = "Top,Left,Right"
        $button.BackColor = $choice.Color
        $button.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
        $dialog.Controls.Add($button)
    }
    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-ToolText -Key "common.back" -Culture $script:dashboardCulture
    $close.Location = New-Object System.Drawing.Point(542, 462)
    $close.Size = New-Object System.Drawing.Size(120, 34)
    $close.Anchor = "Bottom,Right"
    $close.Add_Click({ $dialog.Tag = ""; $dialog.Close() })
    $dialog.CancelButton = $close
    $dialog.Controls.Add($close)
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    switch ($choice) {
        "Certificate" { Start-AssuranceReport -Operation "CertificateAudit" -ModuleId "assurance.certificates" -DisplayName (Get-ToolText -Key "assurance.certificate" -Culture $script:dashboardCulture) }
        "PluginAudit" { Start-AssuranceReport -Operation "PluginAudit" -ModuleId "assurance.plugins" -DisplayName (Get-ToolText -Key "assurance.pluginAudit" -Culture $script:dashboardCulture) }
        "Timeline" { Start-AssuranceReport -Operation "TimelineExport" -ModuleId "assurance.timeline" -DisplayName (Get-ToolText -Key "assurance.timeline" -Culture $script:dashboardCulture) }
        "InstallPlugin" { Install-PluginFromDialog }
        "PluginFolder" {
            $pluginDirectory = Get-ToolPluginDirectory
            if (-not (Test-Path -LiteralPath $pluginDirectory -PathType Container) -and $env:TOOL_SECURE_LAUNCH -ne "1") { New-Item -ItemType Directory -Path $pluginDirectory -Force | Out-Null }
            if (Test-Path -LiteralPath $pluginDirectory -PathType Container) { Start-Process -FilePath $nativeExplorerPath -ArgumentList "`"$pluginDirectory`"" }
        }
        "Guide" { Open-Guide }
        "History" { Open-VersionHistory }
    }
}

function Add-MenuButton([int]$number, [string]$titleKey, [string]$descriptionKey, [int]$index, [scriptblock]$action, [bool]$warning) {
    $button = New-Object System.Windows.Forms.Button
    $metadata = [pscustomobject][ordered]@{
        Number = $number
        TitleKey = $titleKey
        DescriptionKey = $descriptionKey
        Tone = if ($number -eq 8) { "Enterprise" } elseif ($warning) { "Warning" } else { "Normal" }
    }
    $button.Text = Get-DashboardMenuText -Metadata $metadata
    $button.Font = $fontTile
    $button.TextAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(13, 2, 8, 2)
    # GDI+ is kept for the two-line tile text because the WinForms GDI button
    # renderer can collapse the explicit title/description line break at high DPI.
    $button.UseCompatibleTextRendering = $true
    $row = [Math]::Floor($index / 2)
    $column = $index % 2
    $button.Location = New-Object System.Drawing.Point((14 + ($column * 420)), (34 + ($row * 58)))
    $button.Size = New-Object System.Drawing.Size(410, 50)
    $initialTilePalette = Get-DashboardTilePalette -Tone ([string]$metadata.Tone) -Mode $script:dashboardTheme
    $button.BackColor = $initialTilePalette.BackColor
    $button.ForeColor = $initialTilePalette.ForeColor
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $metadata
    $button.Add_Click($action)
    $button.Add_MouseEnter({
        param($sender, $eventArgs)
        $tone = if ($sender.Tag -and $sender.Tag.PSObject.Properties["Tone"]) { [string]$sender.Tag.Tone } else { "Normal" }
        $hoverPalette = Get-DashboardTilePalette -Tone $tone -Mode $script:dashboardTheme -Hover
        $sender.BackColor = $hoverPalette.BackColor
        $sender.ForeColor = $hoverPalette.ForeColor
    })
    $button.Add_MouseLeave({
        param($sender, $eventArgs)
        $tone = if ($sender.Tag -and $sender.Tag.PSObject.Properties["Tone"]) { [string]$sender.Tag.Tone } else { "Normal" }
        $normalPalette = Get-DashboardTilePalette -Tone $tone -Mode $script:dashboardTheme
        $sender.BackColor = $normalPalette.BackColor
        $sender.ForeColor = $normalPalette.ForeColor
    })
    $toolTip.SetToolTip($button, (Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture))
    $menuButtonMetadata[[string]$number] = $metadata
    [void]$buttons.Add($button)
    $buttonPanel.Controls.Add($button)
}

Add-MenuButton 1 "menu.1.title" "menu.1.description" 0 { Start-Report "All" (Get-ToolText -Key "menu.1.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 2 "menu.2.title" "menu.2.description" 1 { Start-Report "Hardware" (Get-ToolText -Key "menu.2.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 3 "menu.3.title" "menu.3.description" 2 { Start-Report "Windows" (Get-ToolText -Key "menu.3.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 4 "menu.4.title" "menu.4.description" 3 { Start-Report "Office" (Get-ToolText -Key "menu.4.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 5 "menu.5.title" "menu.5.description" 4 { Start-Report "Software" (Get-ToolText -Key "menu.5.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 6 "menu.6.title" "menu.6.description" 5 { Show-CleanupMenu } $true
Add-MenuButton 7 "menu.7.title" "menu.7.description" 6 { Start-OemInspect } $true
Add-MenuButton 8 "menu.8.title" "menu.8.description" 7 { Open-LicenseManager } $false
Add-MenuButton 9 "menu.9.title" "menu.9.description" 8 { Show-AdvancedScanMenu } $false
Add-MenuButton 10 "menu.10.title" "menu.10.description" 9 { Show-AssuranceCenter } $false
Update-MainLayout
Set-DashboardTheme -Mode $script:dashboardTheme
$form.Add_Shown({ Fit-MainWindowToWorkingArea; Update-MainLayout; Show-ExecutionEnvironmentWarning })
$form.Add_Resize({ Update-MainLayout })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    $script:progressTick++
    if ($script:activeProcess -and $script:taskStartedAt) {
        $elapsed = (Get-Date) - $script:taskStartedAt
        $elapsedSeconds = [int][Math]::Floor($elapsed.TotalSeconds)
        $elapsedLabel.Text = "{0:00}:{1:00}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        if ($elapsedSeconds -ge ($script:lastProgressHeartbeat + 10)) {
            $script:lastProgressHeartbeat = $elapsedSeconds
            $elapsedText = "{0:00}:{1:00}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
            Write-ProgressLog (Get-ToolText -Key "progress.taskRunning" -Culture $script:dashboardCulture -FormatArguments @($elapsedText))
        }
    }
    if ($script:activeProcess -and $script:activeProcess.HasExited) {
        $timer.Stop()
        $exitCode = $script:activeProcess.ExitCode
        $finishedTaskKind = $script:activeTaskKind
        $finishedAction = $script:activeAction
        $finishedModuleId = $script:activeModuleId
        $finishedModuleInvocation = $script:activeModuleInvocation
        $wasCancellationRequested = [bool]$script:taskCancellationRequested
        $processDurationMs = if ($script:taskStartedAt) { [long][Math]::Round(((Get-Date) - $script:taskStartedAt).TotalMilliseconds) } else { $null }
        if ($finishedModuleInvocation) {
            $moduleResult = Complete-ToolModuleInvocation -Invocation $finishedModuleInvocation -ExitCode $exitCode -Summary $finishedAction
            $moduleValidation = Test-ToolModuleResult -Result $moduleResult
            if (-not $moduleValidation.Valid) {
                [void](Write-ToolLog -Level "ERROR" -Event "Module.ResultInvalid" -Message ($moduleValidation.Errors -join "; ") -Data ([ordered]@{ ModuleId=$finishedModuleId; ExitCode=[int]$exitCode }))
            } else {
                $script:lastModuleResult = $moduleResult
                [void](Write-ToolLog -Level $(if ($moduleResult.Status -eq "Completed") { "AUDIT" } else { "WARN" }) -Event "Module.Complete" -Message $finishedAction -DurationMs $moduleResult.DurationMs -Data ([ordered]@{
                    ModuleId = $moduleResult.ModuleId
                    InvocationId = $moduleResult.InvocationId
                    Status = $moduleResult.Status
                    ExitCode = [int]$moduleResult.ExitCode
                }))
                $completedDescriptor = Get-ToolModuleDescriptor -ModuleId $moduleResult.ModuleId
                [void](Write-LicenseTimelineEventSafe -EventType "ModuleCompleted" -Source "GUI" -IsChange:$false -Data ([ordered]@{
                    ModuleId=$moduleResult.ModuleId; InvocationId=$moduleResult.InvocationId; Status=$moduleResult.Status
                    ExitCode=[int]$moduleResult.ExitCode; DurationMs=[long]$moduleResult.DurationMs
                    ChangeCapable=[bool]($completedDescriptor -and $completedDescriptor.AccessMode -eq "SystemChange")
                }))
            }
        }
        [void](Write-ToolLog -Level $(if ($exitCode -eq 0) { "INFO" } else { "WARN" }) -Event "ChildProcess.Exit" -Message $finishedAction -DurationMs $processDurationMs -Data ([ordered]@{
            TaskKind = $finishedTaskKind
            ModuleId = $finishedModuleId
            ExitCode = [int]$exitCode
        }))
        $script:activeProcess = $null
        $script:activeTaskKind = ""
        $script:activeModuleId = ""
        $script:activeModuleInvocation = $null
        if ($wasCancellationRequested) {
            $script:taskCancellationRequested = $false
            Set-ButtonsEnabled $true
            $status.Text = Get-ToolText -Key "progress.cancelled" -Culture $script:dashboardCulture -FormatArguments @($finishedAction)
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog $status.Text
            [void](Write-ToolLog -Level "WARN" -Event "Action.Cancelled" -Message $finishedAction -DurationMs $processDurationMs -Data ([ordered]@{
                TaskKind = $finishedTaskKind
                ModuleId = $finishedModuleId
                ExitCode = [int]$exitCode
            }))
            Stop-ProgressDisplay $status.Text
            return
        }
        if ($finishedTaskKind -eq "CleanupScan") {
            Complete-CleanupScan
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupRemediate") {
            Complete-CleanupRemediation $false
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupDeep") {
            Complete-CleanupRemediation $true
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupScanRepair") {
            Complete-ScanSourceRepair
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupBackup") {
            Complete-CleanupBackup
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "CleanupRestore") {
            Complete-CleanupRestore
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "OemInspect") {
            Complete-OemInspect
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "OemApply") {
            Set-ButtonsEnabled $true
            if ($script:oemDecisionFile -and (Test-Path -LiteralPath $script:oemDecisionFile -PathType Leaf)) {
                try {
                    $oemApplyResult = Get-Content -LiteralPath $script:oemDecisionFile -Raw | ConvertFrom-Json
                    if ($oemApplyResult.ReportPath -and (Test-Path -LiteralPath $oemApplyResult.ReportPath -PathType Leaf)) {
                        [void](Open-ToolReportPresentation -SourcePath ([string]$oemApplyResult.ReportPath) -Title "Báo cáo khôi phục key OEM" -FilePrefix "BaoCao_KhoiPhuc_Key_OEM")
                    }
                } catch {
                    Write-ProgressLog "Không mở được báo cáo key OEM: $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
                    $script:oemDecisionFile = ""
                }
            }
            [void](Write-LicenseTimelineEventSafe -EventType "OemLicenseApplyCompleted" -Source "GUI" -IsChange:([bool]($exitCode -in @(0, 23))) -Data ([ordered]@{
                ExitCode=[int]$exitCode
                KeyAccepted=[bool]($exitCode -in @(0, 23))
                ActivationConfirmed=[bool]($exitCode -eq 0)
                ProductKeyStoredInTimeline=$false
            }))
            if ($exitCode -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Đã cài key OEM và Windows xác nhận trạng thái đã cấp phép. Báo cáo được lưu trên Desktop.", "Khôi phục key OEM hoàn tất", "OK", "Information") | Out-Null
                $status.Text = "Đã cài và kích hoạt key OEM thành công."
                Write-ProgressLog "Hoàn tất khôi phục key OEM; báo cáo đã lưu trên Desktop."
                $status.ForeColor = [System.Drawing.Color]::DarkGreen
            } elseif ($exitCode -eq 22) {
                [System.Windows.Forms.MessageBox]::Show("Windows không chấp nhận key OEM cho edition hiện tại. Công cụ không gỡ key cũ trước khi thử. Hãy xem báo cáo trên Desktop.", "Key OEM không khớp", "OK", "Warning") | Out-Null
                $status.Text = "Key OEM không được edition Windows hiện tại chấp nhận."
                Write-ProgressLog "Không gỡ key cũ trước khi thử; xem báo cáo trên Desktop."
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } elseif ($exitCode -eq 23) {
                [System.Windows.Forms.MessageBox]::Show("Key OEM đã được Windows chấp nhận nhưng chưa xác nhận kích hoạt. Kiểm tra kết nối mạng, edition hoặc liên hệ Microsoft/nhà sản xuất.", "Cần kiểm tra kích hoạt", "OK", "Warning") | Out-Null
                $status.Text = "Đã cài key OEM nhưng chưa xác nhận kích hoạt."
                Write-ProgressLog "Hãy xem báo cáo trên Desktop để biết chi tiết."
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } else {
                $status.Text = "Khôi phục key OEM kết thúc với mã $exitCode; hãy xem báo cáo trên Desktop."
                Write-ProgressLog "Tác vụ key OEM kết thúc với mã $exitCode."
                $status.ForeColor = [System.Drawing.Color]::DarkRed
            }
            Stop-ProgressDisplay $status.Text
            return
        }
        if ($finishedTaskKind -eq "DeepLicenseScan") {
            Complete-DeepLicenseScan
            Stop-ProgressIfIdle
            return
        }
        if ($finishedTaskKind -eq "ForensicsScan") {
            Complete-ForensicsScan
            Stop-ProgressIfIdle
            return
        }
        Set-ButtonsEnabled $true
        if ($exitCode -eq 0) {
            $status.Text = Get-ToolText -Key "progress.completed" -Culture $script:dashboardCulture -FormatArguments @($finishedAction)
            Write-ProgressLog $status.Text
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            $status.Text = Get-ToolText -Key "progress.failed" -Culture $script:dashboardCulture -FormatArguments @($finishedAction, $exitCode)
            Write-ProgressLog $status.Text
            $status.ForeColor = [System.Drawing.Color]::DarkRed
        }
        Stop-ProgressDisplay $status.Text
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
        [void](Write-ToolLog -Level "WARN" -Event "Application.CloseBlocked" -Message "Tác vụ con vẫn đang chạy." -Data ([ordered]@{ TaskKind=$script:activeTaskKind; ModuleId=$script:activeModuleId; Action=$script:activeAction }))
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "app.closeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "app.closeBlockedTitle" -Culture $script:dashboardCulture), "OK", "Warning") | Out-Null
        $eventArgs.Cancel = $true
    } else {
        [void](Write-ToolLog -Level "INFO" -Event "Application.Stop" -Message "Giao diện đã đóng bình thường.")
    }
})

[void]$form.ShowDialog()


