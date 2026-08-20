param()

$toolVersion = "4.8.0"
$dashboardSchemaVersion = "2.0"
$releaseVersion = "4.8.0.1"
$releaseBuildDate = "2026.08.18"
$toolDisplayVersion = "v$toolVersion"
$releaseDisplayName = "v$releaseVersion"

if ($PSVersionTable.PSVersion.Major -lt 3) {
    exit 10
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$dataLifecycleHelper = Join-Path $PSScriptRoot "Tool-DataLifecycle.ps1"
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
$assistantHelper = Join-Path $PSScriptRoot "Tool-Assistant.ps1"
$softwareInventoryHelper = Join-Path $PSScriptRoot "Tool-SoftwareInventory.ps1"
$softwareCatalogUpdateScript = Join-Path $PSScriptRoot "software-license-online-update.ps1"
$applicationUpdateScript = Join-Path $PSScriptRoot "Tool-UpdateManager.ps1"
$applicationUpdateManifestUrl = "https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json"
$script:dashboardCulture = "vi-VN"
if (Test-Path -LiteralPath $localizationHelper -PathType Leaf) {
    . $localizationHelper
    $script:dashboardCulture = Get-ToolCulture
    $env:TOOL_UI_CULTURE = $script:dashboardCulture
}

function Get-DashboardText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    if (Get-Command Get-ToolText -ErrorAction SilentlyContinue) {
        return Get-ToolText -Key $Key -Culture $script:dashboardCulture -FormatArguments $Arguments
    }
    return "[$Key]"
}

$missingFoundationFiles = @($runtimeHelper, $dataLifecycleHelper, $compatibilityHelper, $capabilityHelper, $loggingHelper, $moduleContractHelper, $reportSchemaHelper, $reportExportHelper, $pluginEngineHelper, $timelineHelper, $safetyPolicyHelper, $enterpriseHelper, $uiThemeHelper, $localizationHelper, $offlinePolicyHelper, $assistantHelper, $softwareInventoryHelper, $softwareCatalogUpdateScript, $applicationUpdateScript) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missingFoundationFiles.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "startup.missingFoundation" @((@($missingFoundationFiles | ForEach-Object { [IO.Path]::GetFileName($_) })) -join ', ')),
        (Get-DashboardText "startup.incompleteTitle"), "OK", "Error") | Out-Null
    exit 12
}
try {
    . $runtimeHelper
    . $dataLifecycleHelper
    $dataLifecycleState = Initialize-ToolDataLifecycle
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
    if (-not (Get-Command Get-ToolText -ErrorAction SilentlyContinue)) { . $localizationHelper }
    . $offlinePolicyHelper
    . $assistantHelper
    . $softwareInventoryHelper
    $architectureState = Assert-ToolNativeArchitecture
    $toolPowerShellPath = Get-ToolNativePowerShellPath
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $capabilityState = Get-ToolCapabilityProfile
    if (-not $capabilityState.SupportedOperatingSystem) { throw (Get-DashboardText "startup.unsupportedOs") }
    $moduleContractState = Get-ToolModuleContractMetadata
    $reportSchemaState = Get-ToolReportSchemaMetadata
    $safetyPolicyState = Get-ToolSafetyPolicyMetadata
    $enterpriseState = Get-ToolEnterpriseMetadata
    $compatibilityState = Get-ToolCompatibilityMetadata
    $localizationState = Get-ToolLocalizationMetadata
    $offlinePolicyState = Get-ToolOfflinePolicyMetadata
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_CAPABILITY_SCHEMA -ne [string]$capabilityState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("capability")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_MODULE_CONTRACT_SCHEMA -ne [string]$moduleContractState.ContractSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("module contract")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_REPORT_SCHEMA -ne [string]$reportSchemaState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("report")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_SAFETY_POLICY_SCHEMA -ne [string]$safetyPolicyState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("safety policy")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_DASHBOARD_SCHEMA -ne [string]$dashboardSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("dashboard")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_ENTERPRISE_SCHEMA -ne [string]$enterpriseState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("enterprise")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_COMPATIBILITY_SCHEMA -ne [string]$compatibilityState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("compatibility")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_LOCALIZATION_SCHEMA -ne [string]$localizationState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("localization")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_OFFLINE_POLICY_SCHEMA -ne [string]$offlinePolicyState.SchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("offline policy")) }
    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and [string]$env:TOOL_DATA_SCHEMA_VERSION -ne [string]$dataLifecycleState.DataSchemaVersion) { throw (Get-DashboardText "startup.schemaMismatch" @("data lifecycle")) }
    $loggingState = Initialize-ToolLogging -Component "GUI" -ToolVersion $toolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $toolVersion
    $nativeNotepadPath = Get-ToolNativeSystemPath "notepad.exe"
    $nativeExplorerPath = Get-ToolWindowsPath "explorer.exe"
    if (-not (Test-Path -LiteralPath $nativeExplorerPath -PathType Leaf)) {
        throw (Get-DashboardText "startup.explorerMissing" @($nativeExplorerPath))
    }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        (Get-DashboardText "startup.runtimeTitle"), "OK", "Warning") | Out-Null
    exit 12
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-DashboardRoundedPath {
    param(
        [single]$X,
        [single]$Y,
        [single]$Width,
        [single]$Height,
        [single]$Radius
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [single]([Math]::Max(2, $Radius * 2))
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($X + $Width - $diameter), $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($X + $Width - $diameter), ($Y + $Height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($X, ($Y + $Height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-DashboardIconBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "Windows", "Office", "Shield", "Check", "Search", "Hardware", "Software",
            "Repair", "Key", "License", "DeepScan", "Report", "NavOverview", "NavScan",
            "NavRepair", "NavReport", "NavSettings", "Chat"
        )]
        [string]$Kind,
        [ValidateRange(16, 96)][int]$Size = 40
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $blueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))
    $lightBlueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, 126, 229))
    $officeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(242, 80, 34))
    $officeDarkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 51, 20))
    $greenBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 158, 96))
    $cyanBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 150, 170))
    $purpleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(126, 75, 214))
    $amberBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 138, 0))
    $tealBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 132, 112))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $transparentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
    $whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3.2)
    $whiteThinPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
    $navPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.8)
    foreach ($pen in @($whitePen, $whiteThinPen, $navPen)) {
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    }

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = [single]($Size / 48.0)
        $graphics.ScaleTransform($scale, $scale)

        switch ($Kind) {
            "Windows" {
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(5, 9)), (New-Object System.Drawing.PointF(22, 7)),
                    (New-Object System.Drawing.PointF(22, 22)), (New-Object System.Drawing.PointF(5, 22))))
                $graphics.FillPolygon($lightBlueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(25, 6)), (New-Object System.Drawing.PointF(43, 4)),
                    (New-Object System.Drawing.PointF(43, 22)), (New-Object System.Drawing.PointF(25, 22))))
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(5, 25)), (New-Object System.Drawing.PointF(22, 25)),
                    (New-Object System.Drawing.PointF(22, 41)), (New-Object System.Drawing.PointF(5, 39))))
                $graphics.FillPolygon($lightBlueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(25, 25)), (New-Object System.Drawing.PointF(43, 25)),
                    (New-Object System.Drawing.PointF(43, 44)), (New-Object System.Drawing.PointF(25, 42))))
            }
            "Office" {
                $graphics.FillPolygon($officeBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(9, 8)), (New-Object System.Drawing.PointF(28, 2)),
                    (New-Object System.Drawing.PointF(41, 8)), (New-Object System.Drawing.PointF(41, 40)),
                    (New-Object System.Drawing.PointF(28, 46)), (New-Object System.Drawing.PointF(9, 40))))
                $graphics.FillPolygon($officeDarkBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(9, 8)), (New-Object System.Drawing.PointF(29, 13)),
                    (New-Object System.Drawing.PointF(29, 37)), (New-Object System.Drawing.PointF(9, 40))))
                $graphics.FillPolygon($whiteBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(16, 14)), (New-Object System.Drawing.PointF(25, 16)),
                    (New-Object System.Drawing.PointF(25, 34)), (New-Object System.Drawing.PointF(16, 35))))
            }
            "Shield" {
                $graphics.FillPolygon($blueBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(24, 3)), (New-Object System.Drawing.PointF(41, 10)),
                    (New-Object System.Drawing.PointF(38, 31)), (New-Object System.Drawing.PointF(24, 45)),
                    (New-Object System.Drawing.PointF(10, 31)), (New-Object System.Drawing.PointF(7, 10))))
                $graphics.DrawArc($whitePen, 17, 13, 14, 16, 180, 180)
                $lockPath = New-DashboardRoundedPath -X 14 -Y 22 -Width 20 -Height 15 -Radius 3
                try { $graphics.FillPath($whiteBrush, $lockPath) } finally { $lockPath.Dispose() }
                $graphics.FillEllipse($blueBrush, 22, 27, 4, 6)
            }
            "Check" {
                $graphics.FillPolygon($greenBrush, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(24, 3)), (New-Object System.Drawing.PointF(41, 10)),
                    (New-Object System.Drawing.PointF(38, 31)), (New-Object System.Drawing.PointF(24, 45)),
                    (New-Object System.Drawing.PointF(10, 31)), (New-Object System.Drawing.PointF(7, 10))))
                $graphics.DrawLines($whitePen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(14, 24)), (New-Object System.Drawing.PointF(21, 31)),
                    (New-Object System.Drawing.PointF(34, 17))))
            }
            "Search" {
                $graphics.FillEllipse($blueBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whitePen, 11, 10, 19, 19)
                $graphics.DrawLine($whitePen, 28, 28, 38, 38)
            }
            "Hardware" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($cyanBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 14, 14, 20, 20)
                $graphics.DrawRectangle($whiteThinPen, 18, 18, 12, 12)
                foreach ($offset in @(17, 23, 29)) {
                    $graphics.DrawLine($whiteThinPen, $offset, 9, $offset, 14)
                    $graphics.DrawLine($whiteThinPen, $offset, 34, $offset, 39)
                    $graphics.DrawLine($whiteThinPen, 9, $offset, 14, $offset)
                    $graphics.DrawLine($whiteThinPen, 34, $offset, 39, $offset)
                }
            }
            "Software" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($purpleBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                foreach ($x in @(13, 25)) {
                    foreach ($y in @(13, 25)) { $graphics.FillRectangle($whiteBrush, $x, $y, 9, 9) }
                }
            }
            "Repair" {
                $graphics.FillEllipse($amberBrush, 3, 3, 42, 42)
                $graphics.DrawLine($whitePen, 16, 33, 32, 17)
                $graphics.DrawArc($whitePen, 27, 10, 11, 11, 25, 245)
                $graphics.DrawEllipse($whiteThinPen, 11, 31, 7, 7)
            }
            "Key" {
                $graphics.FillEllipse($amberBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whitePen, 11, 11, 13, 13)
                $graphics.DrawLine($whitePen, 22, 22, 37, 37)
                $graphics.DrawLine($whitePen, 31, 31, 35, 27)
                $graphics.DrawLine($whitePen, 35, 35, 39, 31)
            }
            "License" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($greenBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 12, 9, 24, 30)
                $graphics.DrawLine($whiteThinPen, 17, 16, 31, 16)
                $graphics.DrawLine($whiteThinPen, 17, 21, 27, 21)
                $graphics.DrawLines($whiteThinPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(18, 30)), (New-Object System.Drawing.PointF(22, 34)),
                    (New-Object System.Drawing.PointF(31, 25))))
            }
            "DeepScan" {
                $graphics.FillEllipse($purpleBrush, 3, 3, 42, 42)
                $graphics.DrawEllipse($whiteThinPen, 9, 9, 27, 27)
                $graphics.DrawLine($whitePen, 34, 34, 40, 40)
                $graphics.DrawLines($whiteThinPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(13, 25)), (New-Object System.Drawing.PointF(18, 25)),
                    (New-Object System.Drawing.PointF(21, 18)), (New-Object System.Drawing.PointF(25, 30)),
                    (New-Object System.Drawing.PointF(29, 22)), (New-Object System.Drawing.PointF(33, 22))))
            }
            "Report" {
                $backgroundPath = New-DashboardRoundedPath -X 3 -Y 3 -Width 42 -Height 42 -Radius 8
                try { $graphics.FillPath($tealBrush, $backgroundPath) } finally { $backgroundPath.Dispose() }
                $graphics.DrawRectangle($whiteThinPen, 12, 8, 24, 32)
                $graphics.DrawLine($whiteThinPen, 17, 17, 31, 17)
                $graphics.DrawLine($whiteThinPen, 17, 23, 31, 23)
                $graphics.DrawLine($whiteThinPen, 17, 29, 28, 29)
                $graphics.DrawLine($whiteThinPen, 17, 35, 25, 35)
            }
            "NavOverview" {
                $graphics.DrawLines($navPen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(7, 22)), (New-Object System.Drawing.PointF(24, 7)),
                    (New-Object System.Drawing.PointF(41, 22))))
                $graphics.DrawRectangle($navPen, 12, 21, 24, 20)
                $graphics.DrawRectangle($navPen, 21, 28, 7, 13)
            }
            "NavScan" {
                $graphics.DrawEllipse($navPen, 8, 7, 25, 25)
                $graphics.DrawLine($navPen, 31, 30, 41, 40)
            }
            "NavRepair" {
                $graphics.DrawLine($navPen, 14, 36, 34, 16)
                $graphics.DrawArc($navPen, 28, 8, 12, 12, 25, 245)
                $graphics.DrawEllipse($navPen, 9, 34, 7, 7)
            }
            "NavReport" {
                $graphics.DrawRectangle($navPen, 11, 6, 26, 36)
                $graphics.DrawLine($navPen, 17, 16, 31, 16)
                $graphics.DrawLine($navPen, 17, 23, 31, 23)
                $graphics.DrawLine($navPen, 17, 30, 27, 30)
            }
            "NavSettings" {
                $graphics.DrawEllipse($navPen, 14, 14, 20, 20)
                $graphics.DrawEllipse($navPen, 20, 20, 8, 8)
                foreach ($angle in 0, 45, 90, 135, 180, 225, 270, 315) {
                    $radians = $angle * [Math]::PI / 180
                    $x1 = 24 + ([Math]::Cos($radians) * 11)
                    $y1 = 24 + ([Math]::Sin($radians) * 11)
                    $x2 = 24 + ([Math]::Cos($radians) * 17)
                    $y2 = 24 + ([Math]::Sin($radians) * 17)
                    $graphics.DrawLine($navPen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                }
            }
            "Chat" {
                $bubble = New-Object System.Drawing.Drawing2D.GraphicsPath
                $bubble.AddArc(5, 7, 38, 31, 180, 90)
                $bubble.AddArc(5, 7, 38, 31, 270, 90)
                $bubble.AddArc(5, 7, 38, 31, 0, 90)
                $bubble.AddLine(31, 38, 22, 44)
                $bubble.AddLine(23, 38, 12, 38)
                $bubble.AddArc(5, 7, 38, 31, 90, 90)
                $bubble.CloseFigure()
                try { $graphics.FillPath($blueBrush, $bubble) } finally { $bubble.Dispose() }
                $graphics.DrawLine($whiteThinPen, 13, 18, 35, 18)
                $graphics.DrawLine($whiteThinPen, 13, 26, 30, 26)
            }
        }
    } catch {
        $bitmap.Dispose()
        throw
    } finally {
        foreach ($resource in @(
            $graphics, $blueBrush, $lightBlueBrush, $officeBrush, $officeDarkBrush, $greenBrush,
            $cyanBrush, $purpleBrush, $amberBrush, $tealBrush, $whiteBrush, $transparentBrush,
            $whitePen, $whiteThinPen, $navPen
        )) {
            if ($resource) { $resource.Dispose() }
        }
    }
    return $bitmap
}

function New-DashboardTileIconBitmap {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [ValidateRange(16, 64)][int]$IconSize = 32,
        [ValidateRange(4, 24)][int]$RightGap = 12
    )

    $source = New-DashboardIconBitmap -Kind $Kind -Size $IconSize
    $canvas = New-Object System.Drawing.Bitmap(($IconSize + $RightGap), $IconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawImageUnscaled($source, 0, 0)
    } finally {
        $graphics.Dispose()
        $source.Dispose()
    }
    return $canvas
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
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $userScopedData = [string]$env:TOOL_DATA_SCOPE -ne "Machine"
        $allowedOwners = @("S-1-5-32-544", "S-1-5-18")
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        if ($userScopedData) {
            $allowedOwners += $currentUserSid
            $allowedWriters += $currentUserSid
        }
        if ($ownerSid -notin $allowedOwners -or -not $acl.AreAccessRulesProtected) { return $false }
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

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportScript = Join-Path $baseDir "kiem-tra-cau-hinh-ban-quyen.ps1"
$elevatedBridgeScript = Join-Path $baseDir "Tool-ElevatedBridge.ps1"
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
$englishHistoryFile = Join-Path $baseDir "VERSION-HISTORY-en-US.md"
$integrityManifest = Join-Path $baseDir "TOOL-SHA256SUMS.txt"
$requiredIntegrityFiles = @(
    "HUONG-DAN.txt", "USER-GUIDE-en-US.md", "LICH-SU-PHIEN-BAN.txt", "VERSION-HISTORY-en-US.md",
    "Giao-Dien.ps1", "kiem-tra-cau-hinh-ban-quyen.ps1", "Tool-Kiem-Tra-icon.svg",
    "Tool-Kiem-Tra.cmd", "Tool-Runtime.ps1", "Tool-ElevatedBridge.ps1", "Tool-DataLifecycle.ps1", "Tool-Compatibility.ps1", "compatibility-catalog-v1.0.json", "Tool-Capabilities.ps1", "Tool-ScanOptimization.ps1", "Tool-Logging.ps1", "Tool-ModuleContract.ps1", "Tool-UiTheme.ps1", "Tool-Localization.ps1", "Tool-Strings.vi-VN.json", "Tool-Strings.en-US.json", "Tool-OfflinePolicy.ps1", "Tool-Assistant.ps1", "tool-assistant-knowledge-v1.1.json", "Tool-SoftwareInventory.ps1", "software-license-catalog-v1.0.json", "software-license-catalog-v1.0.json.p7s", "software-license-online-update.ps1", "Tool-UpdateManager.ps1", "windows-license-backup.ps1",
    "Tool-ReportSchema.ps1", "Tool-ReportExport.ps1", "Tool-PluginEngine.ps1", "Tool-LicenseTimeline.ps1", "Tool-SafetyPolicy.ps1",
    "Tool-Enterprise.ps1", "Tool-EnterpriseHost.ps1", "Tool-EnterpriseAgent.ps1", "enterprise-license-manager.ps1",
    "windows-license-compliance-cleanup.ps1", "windows-license-restore.ps1",
    "windows-license-deep-scan.ps1", "windows-license-forensics.ps1",
    "windows-oem-license-assistant.ps1", "windows-office-license-manager.ps1",
    "windows-license-assurance.ps1", "builtin-windows-office-trust.plugin.json"
)
$runtimeDir = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $baseDir "runtime" }
if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) { New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null }
$env:TOOL_SECURE_RUNTIME_FAILED = "0"
$script:secureRuntimeAclInitError = ""
if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
    try {
        $administratorsSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $userScopedData = [string]$env:TOOL_DATA_SCOPE -ne "Machine"
        $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $runtimeAcl = New-Object Security.AccessControl.DirectorySecurity
        $runtimeAcl.SetAccessRuleProtection($true, $false)
        $runtimeAcl.SetOwner($(if ($userScopedData) { $currentUserSid } else { $administratorsSid }))
        $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administratorsSid, "FullControl", $inheritance, "None", "Allow")))
        $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
        if ($userScopedData) {
            $runtimeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentUserSid, "FullControl", $inheritance, "None", "Allow")))
        }
        Set-Acl -LiteralPath $runtimeDir -AclObject $runtimeAcl -ErrorAction Stop
    } catch {
        $script:secureRuntimeAclInitError = $_.Exception.Message
    }
}
if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
    $env:TOOL_SECURE_RUNTIME_FAILED = "1"
    if (Get-Command Write-ToolLog -ErrorAction SilentlyContinue) {
        [void](Write-ToolLog -Level "ERROR" -Event "Security.RuntimeAclInvalid" -Message $script:secureRuntimeAclInitError -Data ([ordered]@{ RuntimeDirectory=$runtimeDir }))
    }
}
$approvedKmsFile = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_APPROVED_KMS_FILE)) { $env:TOOL_APPROVED_KMS_FILE } else { Join-Path $baseDir "approved-kms-servers.txt" }
$bundledApprovedKmsFile = Join-Path $baseDir "approved-kms-servers.txt"
$desktop = [Environment]::GetFolderPath("Desktop")
$reportRoot = Join-Path $desktop "BaoCao-Tool-Kiem-Tra"
$uiTypography = Get-ToolUiTypography
$fontNormal = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Regular)
$fontSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.SmallSize, [System.Drawing.FontStyle]::Regular)
$fontSupportSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, [Math]::Max(7.5, ($uiTypography.SmallSize - 1.0)), [System.Drawing.FontStyle]::Regular)
$fontBold = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.NormalSize, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.DashboardTitleSize, [System.Drawing.FontStyle]::Bold)
$fontTitleCompact = New-Object System.Drawing.Font($uiTypography.FontFamily, 16.0, [System.Drawing.FontStyle]::Bold)
$fontTitleMedium = New-Object System.Drawing.Font($uiTypography.FontFamily, 14.0, [System.Drawing.FontStyle]::Bold)
$fontTitleSmall = New-Object System.Drawing.Font($uiTypography.FontFamily, 12.0, [System.Drawing.FontStyle]::Bold)
$fontTitleTiny = New-Object System.Drawing.Font($uiTypography.FontFamily, 10.5, [System.Drawing.FontStyle]::Bold)
$fontTitleMicro = New-Object System.Drawing.Font($uiTypography.FontFamily, 9.0, [System.Drawing.FontStyle]::Bold)
$fontTitleMinimum = New-Object System.Drawing.Font($uiTypography.FontFamily, 8.0, [System.Drawing.FontStyle]::Bold)
$fontCardValue = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.CardValueSize, [System.Drawing.FontStyle]::Bold)
$fontIntroTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.IntroTitleSize, [System.Drawing.FontStyle]::Bold)
$fontTile = New-Object System.Drawing.Font($uiTypography.FontFamily, $uiTypography.TileSize, [System.Drawing.FontStyle]::Regular)
$fontSidebarTitle = New-Object System.Drawing.Font($uiTypography.FontFamily, 11.5, [System.Drawing.FontStyle]::Bold)
$fontSidebar = New-Object System.Drawing.Font($uiTypography.FontFamily, 10.0, [System.Drawing.FontStyle]::Regular)

$form = New-Object System.Windows.Forms.Form
$form.Text = "[$releaseDisplayName]"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1480, 900)
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
$form.Font = $fontNormal
$form.AutoScroll = $false
$form.AutoScrollMargin = New-Object System.Drawing.Size(0, 0)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$script:dashboardTheme = "Light"
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
$dashboardIconImages = New-Object System.Collections.ArrayList

$sidebarPanel = New-Object System.Windows.Forms.Panel
$sidebarPanel.BackColor = [System.Drawing.Color]::FromArgb(11, 55, 105)
$sidebarPanel.Location = New-Object System.Drawing.Point(0, 0)
$sidebarPanel.Size = New-Object System.Drawing.Size(196, $form.ClientSize.Height)
$form.Controls.Add($sidebarPanel)

$sidebarBrand = New-Object System.Windows.Forms.Label
$sidebarBrand.Text = Get-DashboardText "dashboard.sidebar.brand"
$sidebarBrand.Font = $fontSidebarTitle
$sidebarBrand.ForeColor = [System.Drawing.Color]::White
$sidebarBrand.TextAlign = "MiddleLeft"
$sidebarBrand.UseCompatibleTextRendering = $false
$sidebarBrand.Location = New-Object System.Drawing.Point(20, 24)
$sidebarBrand.Size = New-Object System.Drawing.Size(160, 30)
$sidebarPanel.Controls.Add($sidebarBrand)

$sidebarEdition = New-Object System.Windows.Forms.Label
$sidebarEdition.Text = Get-DashboardText "dashboard.sidebar.edition"
$sidebarEdition.Font = $fontSmall
$sidebarEdition.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
$sidebarEdition.TextAlign = "MiddleLeft"
$sidebarEdition.UseCompatibleTextRendering = $false
$sidebarEdition.Location = New-Object System.Drawing.Point(20, 54)
$sidebarEdition.Size = New-Object System.Drawing.Size(160, 22)
$sidebarPanel.Controls.Add($sidebarEdition)

$sidebarNavButtons = New-Object System.Collections.ArrayList
$sidebarNavDefinitions = @(
    @{ Section="Overview"; TextKey="dashboard.nav.overview"; IconKind="NavOverview" },
    @{ Section="Scan"; TextKey="dashboard.nav.scan"; IconKind="NavScan" },
    @{ Section="Remediation"; TextKey="dashboard.nav.remediation"; IconKind="NavRepair" },
    @{ Section="Reports"; TextKey="dashboard.nav.reports"; IconKind="NavReport" },
    @{ Section="Settings"; TextKey="dashboard.nav.settings"; IconKind="NavSettings" }
)
for ($navIndex = 0; $navIndex -lt $sidebarNavDefinitions.Count; $navIndex++) {
    $navDefinition = $sidebarNavDefinitions[$navIndex]
    $navButton = New-Object System.Windows.Forms.Button
    $navButton.Text = Get-DashboardText ([string]$navDefinition.TextKey)
    $navButton.Font = $fontSidebar
    $navButton.ForeColor = [System.Drawing.Color]::White
    $navButton.BackColor = [System.Drawing.Color]::FromArgb(11, 55, 105)
    $navButton.TextAlign = "MiddleLeft"
    $navButton.ImageAlign = "MiddleLeft"
    $navButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
    $navButton.Padding = New-Object System.Windows.Forms.Padding(12, 0, 8, 0)
    $navButton.FlatStyle = "Flat"
    $navButton.FlatAppearance.BorderSize = 0
    $navButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $navButton.Location = New-Object System.Drawing.Point(10, (102 + ($navIndex * 54)))
    $navButton.Size = New-Object System.Drawing.Size(176, 44)
    $navIconImage = New-DashboardIconBitmap -Kind ([string]$navDefinition.IconKind) -Size 22
    [void]$dashboardIconImages.Add($navIconImage)
    $navButton.Image = $navIconImage
    $navButton.Tag = [pscustomobject]@{
        Section = [string]$navDefinition.Section
        TextKey = [string]$navDefinition.TextKey
        IconKind = [string]$navDefinition.IconKind
    }
    $navButton.Add_Click({
        param($sender, $eventArgs)
        $selectedSection = [string]$sender.Tag.Section
        if ($selectedSection -eq "Settings") {
            Show-DashboardPreferences
        } else {
            Set-DashboardSection -Section $selectedSection
        }
    })
    [void]$sidebarNavButtons.Add($navButton)
    $sidebarPanel.Controls.Add($navButton)
}

$sidebarFooter = New-Object System.Windows.Forms.Label
$sidebarFooter.Text = Get-DashboardText "dashboard.sidebar.footer" @($toolDisplayVersion)
$sidebarFooter.Font = $fontSmall
$sidebarFooter.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
$sidebarFooter.TextAlign = "MiddleLeft"
$sidebarFooter.UseCompatibleTextRendering = $false
$sidebarFooter.Location = New-Object System.Drawing.Point(20, 700)
$sidebarFooter.Size = New-Object System.Drawing.Size(160, 52)
$sidebarPanel.Controls.Add($sidebarFooter)

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.BackColor = [System.Drawing.Color]::White
$headerPanel.Location = New-Object System.Drawing.Point(196, 0)
$headerPanel.Size = New-Object System.Drawing.Size(($form.ClientSize.Width - 196), 78)
$form.Controls.Add($headerPanel)

$headerBrandIcon = New-Object System.Windows.Forms.PictureBox
$headerBrandIcon.BackColor = [System.Drawing.Color]::Transparent
$headerBrandIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$headerBrandIcon.Location = New-Object System.Drawing.Point(20, 14)
$headerBrandIcon.Size = New-Object System.Drawing.Size(42, 48)
$headerBrandImage = New-DashboardIconBitmap -Kind "Shield" -Size 42
[void]$dashboardIconImages.Add($headerBrandImage)
$headerBrandIcon.Image = $headerBrandImage
$headerPanel.Controls.Add($headerBrandIcon)

$title = New-Object System.Windows.Forms.Label
$title.Text = Get-ToolText -Key "app.title" -Culture $script:dashboardCulture
$title.Font = $fontTitle
$title.UseCompatibleTextRendering = $false
$title.UseMnemonic = $false
$title.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$title.TextAlign = "MiddleLeft"
$title.Location = New-Object System.Drawing.Point(74, 10)
$title.Size = New-Object System.Drawing.Size(700, 38)
$headerPanel.Controls.Add($title)

$themeButton = New-Object System.Windows.Forms.Button
$themeButton.Text = Get-ToolText -Key "app.theme.dark" -Culture $script:dashboardCulture
$themeButton.Font = $fontBold
$themeButton.FlatStyle = "Flat"
$themeButton.Size = New-Object System.Drawing.Size(152, 32)
$themeButton.Location = New-Object System.Drawing.Point(820, 12)
$themeButton.Add_Click({
    $script:dashboardTheme = if ($script:dashboardTheme -eq "Light") { "Dark" } else { "Light" }
    $script:toolUiPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    [void](Set-ToolUiThemePreference -Mode $script:dashboardTheme)
    Set-DashboardTheme -Mode $script:dashboardTheme
})
$headerPanel.Controls.Add($themeButton)

$offlineButton = New-Object System.Windows.Forms.Button
$offlineButton.Font = $fontBold
$offlineButton.FlatStyle = "Flat"
$offlineButton.FlatAppearance.BorderSize = 1
$offlineButton.Size = New-Object System.Drawing.Size(156, 32)
$offlineButton.Location = New-Object System.Drawing.Point(650, 12)
$offlineButton.Add_Click({ Toggle-DashboardOfflineMode })
$headerPanel.Controls.Add($offlineButton)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$languageCombo.Font = $fontNormal
$languageCombo.Size = New-Object System.Drawing.Size(116, 32)
[void]$languageCombo.Items.Add((Get-DashboardText "app.language.vi"))
[void]$languageCombo.Items.Add((Get-DashboardText "app.language.en"))
$languageCombo.SelectedIndex = if ($script:dashboardCulture -eq "en-US") { 1 } else { 0 }
$languageCombo.Add_SelectedIndexChanged({
    $selectedCulture = if ($languageCombo.SelectedIndex -eq 1) { "en-US" } else { "vi-VN" }
    if ($selectedCulture -ne $script:dashboardCulture) { Set-DashboardLanguage -Culture $selectedCulture }
})
$headerPanel.Controls.Add($languageCombo)

$developer = New-Object System.Windows.Forms.Label
$developer.Text = Get-ToolText -Key "app.developer" -Culture $script:dashboardCulture
$developer.Font = $fontSupportSmall
$developer.UseCompatibleTextRendering = $false
$developer.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$developer.TextAlign = "MiddleLeft"
$developer.Location = New-Object System.Drawing.Point(74, 46)
$developer.Size = New-Object System.Drawing.Size(700, 22)
$headerPanel.Controls.Add($developer)

$version = New-Object System.Windows.Forms.Label
$version.Text = Get-DashboardText "dashboard.versionSummary" @($releaseDisplayName, $capabilityState.WindowsReleaseName, $capabilityState.FullBuildNumber, $capabilityState.OperatingSystemArchitecture, $reportSchemaState.SchemaVersion)
$version.Font = $fontSmall
$version.UseCompatibleTextRendering = $false
$version.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$version.TextAlign = "MiddleLeft"
$version.Location = New-Object System.Drawing.Point(74, 62)
$version.Size = New-Object System.Drawing.Size(860, 20)
$headerPanel.Controls.Add($version)

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
$description.Text = Get-ToolText -Key "dashboard.overview.title" -Culture $script:dashboardCulture
$description.Font = $fontIntroTitle
$description.UseCompatibleTextRendering = $false
$description.UseMnemonic = $false
$description.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$description.AutoEllipsis = $true
$description.Location = New-Object System.Drawing.Point(15, 6)
$description.Size = New-Object System.Drawing.Size(650, 22)
$introPanel.Controls.Add($description)

$introSummary = New-Object System.Windows.Forms.Label
$introSummary.Text = Get-ToolText -Key "dashboard.overview.subtitle" -Culture $script:dashboardCulture
$introSummary.Font = $fontSupportSmall
$introSummary.UseCompatibleTextRendering = $false
$introSummary.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$introSummary.AutoEllipsis = $true
$introSummary.Location = New-Object System.Drawing.Point(15, 30)
$introSummary.Size = New-Object System.Drawing.Size(650, 20)
$introPanel.Controls.Add($introSummary)

$introAssistantButton = New-Object System.Windows.Forms.Button
$introAssistantButton.Text = Get-ToolText -Key "app.assistant" -Culture $script:dashboardCulture
$introAssistantButton.Font = $fontBold
$introAssistantButton.FlatStyle = "Flat"
$introAssistantButton.FlatAppearance.BorderSize = 0
$introAssistantButton.BackColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$introAssistantButton.ForeColor = [System.Drawing.Color]::White
$introAssistantButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
$introAssistantButton.ImageAlign = "MiddleLeft"
$introAssistantButton.TextAlign = "MiddleCenter"
$introAssistantButton.Padding = New-Object System.Windows.Forms.Padding(7, 0, 6, 0)
$introAssistantIcon = New-DashboardIconBitmap -Kind "Chat" -Size 18
[void]$dashboardIconImages.Add($introAssistantIcon)
$introAssistantButton.Image = $introAssistantIcon
$introAssistantButton.Size = New-Object System.Drawing.Size(154, 32)
$introAssistantButton.Location = New-Object System.Drawing.Point(526, 12)
$introAssistantButton.Add_Click({
    $requestAssistantOnline = {
        if ($script:offlineMode) { [void](Toggle-DashboardOfflineMode) }
        return (-not [bool]$script:offlineMode)
    }
    Show-ToolAssistantWindow -Owner $form -Culture $script:dashboardCulture -OnlineMode (-not $script:offlineMode) -CurrentReportPath ([string]$script:lastReportPath) -Theme $script:dashboardTheme -RequestOnline $requestAssistantOnline
})
$toolTip.SetToolTip($introAssistantButton, (Get-ToolText -Key "assistant.tooltip" -Culture $script:dashboardCulture))
$introPanel.Controls.Add($introAssistantButton)

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
    @{ Key="Compatibility"; IconKind="Windows"; Tone="Windows"; Caption=(Get-ToolText -Key "dashboard.windows" -Culture $script:dashboardCulture); Value=[string]$capabilityState.WindowsReleaseName },
    @{ Key="Architecture"; IconKind="Office"; Tone="Office"; Caption=(Get-ToolText -Key "dashboard.office" -Culture $script:dashboardCulture); Value=[string]$capabilityState.OfficeSummary },
    @{ Key="SecureLaunch"; IconKind="Shield"; Tone="Secure"; Caption=(Get-ToolText -Key "dashboard.runMode" -Culture $script:dashboardCulture); Value=$(if ($env:TOOL_SECURE_LAUNCH -eq "1") { Get-ToolText -Key "dashboard.secure" -Culture $script:dashboardCulture } else { Get-ToolText -Key "dashboard.source" -Culture $script:dashboardCulture }) },
    @{ Key="Integrity"; IconKind="Check"; Tone="Integrity"; Caption=(Get-ToolText -Key "dashboard.integrity" -Culture $script:dashboardCulture); Value=(Get-ToolText -Key "dashboard.checking" -Culture $script:dashboardCulture) }
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
    $cardCaption.AutoEllipsis = $true
    $cardCaption.Location = New-Object System.Drawing.Point(58, 10)
    $cardCaption.Size = New-Object System.Drawing.Size(134, 18)
    $card.Controls.Add($cardCaption)

    $cardValue = New-Object System.Windows.Forms.Label
    $cardValue.Text = [string]$definition.Value
    $cardValue.Font = $fontCardValue
    $cardValue.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $cardValue.AutoEllipsis = $true
    $cardValue.TextAlign = "MiddleLeft"
    $cardValue.UseCompatibleTextRendering = $false
    $cardValue.Location = New-Object System.Drawing.Point(58, 32)
    $cardValue.Size = New-Object System.Drawing.Size(134, 34)
    $card.Controls.Add($cardValue)

    $cardGlyph = New-Object System.Windows.Forms.PictureBox
    $cardGlyph.BackColor = [System.Drawing.Color]::Transparent
    $cardGlyph.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $cardGlyph.Location = New-Object System.Drawing.Point(11, 23)
    $cardGlyph.Size = New-Object System.Drawing.Size(34, 34)
    $cardGlyph.Tag = "CardGlyph"
    $cardIconImage = New-DashboardIconBitmap -Kind ([string]$definition.IconKind) -Size 34
    [void]$dashboardIconImages.Add($cardIconImage)
    $cardGlyph.Image = $cardIconImage
    $card.Controls.Add($cardGlyph)

    $cardAccent = New-Object System.Windows.Forms.Panel
    $cardAccent.BackColor = [System.Drawing.Color]::FromArgb(45, 111, 203)
    $cardAccent.Location = New-Object System.Drawing.Point(0, 0)
    $cardAccent.Size = New-Object System.Drawing.Size(5, 80)
    $cardAccent.Tag = "CardAccent"
    $card.Controls.Add($cardAccent)

    $dashboardCards[[string]$definition.Key] = [pscustomobject]@{
        Panel=$card
        Caption=$cardCaption
        Value=$cardValue
        Glyph=$cardGlyph
        Tone=[string]$definition.Tone
        IconKind=[string]$definition.IconKind
    }
    [void]$dashboardCardPanels.Add($card)
    $dashboardPanel.Controls.Add($card)
    $toolTip.SetToolTip($cardCaption, [string]$definition.Caption)
    $toolTip.SetToolTip($cardValue, [string]$definition.Value)
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

$activityPanel = New-Object System.Windows.Forms.Panel
$activityPanel.BackColor = [System.Drawing.Color]::White
$activityPanel.BorderStyle = "None"
$activityPanel.Location = New-Object System.Drawing.Point(($buttonPanel.Right + 12), $buttonPanel.Top)
$activityPanel.Size = New-Object System.Drawing.Size(300, $buttonPanel.Height)
$form.Controls.Add($activityPanel)

$activityPanelCaption = New-Object System.Windows.Forms.Label
$activityPanelCaption.Text = Get-DashboardText "dashboard.activity"
$activityPanelCaption.Font = $fontBold
$activityPanelCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$activityPanelCaption.Location = New-Object System.Drawing.Point(16, 14)
$activityPanelCaption.Size = New-Object System.Drawing.Size(250, 24)
$activityPanel.Controls.Add($activityPanelCaption)

$status = New-Object System.Windows.Forms.Label
$status.Text = ""
$status.Font = $fontNormal
$status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$status.TextAlign = "MiddleLeft"
$status.Location = New-Object System.Drawing.Point(38, ($buttonPanel.Bottom + 13))
$status.Size = New-Object System.Drawing.Size(550, 24)
$activityPanel.Controls.Add($status)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = Get-ToolText -Key "app.close" -Culture $script:dashboardCulture
$closeButton.Font = $fontBold
$closeButton.Location = New-Object System.Drawing.Point(600, ($buttonPanel.Bottom + 10))
$closeButton.Size = New-Object System.Drawing.Size(108, 30)
$closeButton.Add_Click({ $form.Close() })
$activityPanel.Controls.Add($closeButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = Get-ToolText -Key "progress.stop" -Culture $script:dashboardCulture
$stopButton.Font = $fontBold
$stopButton.Location = New-Object System.Drawing.Point(484, ($buttonPanel.Bottom + 10))
$stopButton.Size = New-Object System.Drawing.Size(108, 30)
$stopButton.Visible = $false
$stopButton.Enabled = $false
$stopButton.Add_Click({ Stop-ActiveTask })
$activityPanel.Controls.Add($stopButton)

$copyLogButton = New-Object System.Windows.Forms.Button
$copyLogButton.Text = Get-ToolText -Key "progress.copyAllLog" -Culture $script:dashboardCulture
$copyLogButton.Font = $fontSmall
$copyLogButton.Size = New-Object System.Drawing.Size(142, 26)
$copyLogButton.Add_Click({ Copy-AllToolLog })
$activityPanel.Controls.Add($copyLogButton)

$openReportFolderButton = New-Object System.Windows.Forms.Button
$openReportFolderButton.Text = Get-ToolText -Key "report.openFolder" -Culture $script:dashboardCulture
$openReportFolderButton.Font = $fontSmall
$openReportFolderButton.Size = New-Object System.Drawing.Size(166, 26)
$openReportFolderButton.Add_Click({ Open-ReportDirectory })
$activityPanel.Controls.Add($openReportFolderButton)

$progressCaption = New-Object System.Windows.Forms.Label
$progressCaption.Text = Get-ToolText -Key "progress.caption" -Culture $script:dashboardCulture
$progressCaption.Font = $fontBold
$progressCaption.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$progressCaption.Location = New-Object System.Drawing.Point(38, ($closeButton.Bottom + 5))
$progressCaption.Size = New-Object System.Drawing.Size(670, 18)
$activityPanel.Controls.Add($progressCaption)

$activityLabel = New-Object System.Windows.Forms.Label
$activityLabel.Text = ""
$activityLabel.Font = $fontSmall
$activityLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$activityLabel.TextAlign = "MiddleLeft"
$activityLabel.AutoEllipsis = $true
$activityLabel.Location = New-Object System.Drawing.Point(38, ($progressCaption.Bottom + 2))
$activityLabel.Size = New-Object System.Drawing.Size(585, 20)
$activityPanel.Controls.Add($activityLabel)

$elapsedLabel = New-Object System.Windows.Forms.Label
$elapsedLabel.Text = ""
$elapsedLabel.Font = $fontSmall
$elapsedLabel.ForeColor = [System.Drawing.Color]::FromArgb(102, 112, 133)
$elapsedLabel.TextAlign = "MiddleRight"
$elapsedLabel.Location = New-Object System.Drawing.Point(623, ($progressCaption.Bottom + 2))
$elapsedLabel.Size = New-Object System.Drawing.Size(85, 20)
$activityPanel.Controls.Add($elapsedLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Location = New-Object System.Drawing.Point(38, ($activityLabel.Bottom + 1))
$progressBar.Size = New-Object System.Drawing.Size(670, 15)
$activityPanel.Controls.Add($progressBar)

$progressLog = New-Object System.Windows.Forms.TextBox
$progressLog.Multiline = $true
$progressLog.ReadOnly = $true
$progressLog.ScrollBars = "Vertical"
$progressLog.WordWrap = $true
$progressLog.Font = $fontSmall
$progressLog.BackColor = [System.Drawing.Color]::White
$progressLog.Location = New-Object System.Drawing.Point(38, ($progressBar.Bottom + 4))
$progressLog.Size = New-Object System.Drawing.Size(670, 62)
$activityPanel.Controls.Add($progressLog)

$activityLabel.Visible = $false
$elapsedLabel.Visible = $false
$progressBar.Visible = $false
$progressLog.Visible = $false

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
$cleanupDryRunMode = $false
$cleanupScanScope = "All"
$softwareCatalogUpdateResultFile = ""
$softwareCatalogAutoScan = $false
$softwareCatalogAutoScanScope = "ThirdParty"
$applicationUpdateResultFile = ""
$availableApplicationUpdate = $null
$applicationUpdateProcess = $null
$applicationUpdateInvocation = $null
$applicationUpdateCheckPending = $false
$applicationUpdatePromptPending = $false
$applicationUpdateReminderPending = $false
$applicationUpdateReminderDueUtc = [DateTime]::MinValue
$applicationUpdateTaskObservedAfterDeferral = $false
$applicationUpdateDismissedForSession = $false
$applicationUpdateCancelledForOffline = $false
$applicationUpdateDialogVisible = $false
$applicationUpdateApplyStarted = $false
$backupScope = "All"
$restoreScope = "All"
$backupResultFile = ""
$restoreResultFile = ""
$oemDecisionFile = ""
$deepScanDecisionFile = ""
$forensicsDecisionFile = ""
$progressTick = 0
$progressPhase = 0
$taskStartedAt = $null
$lastProgressHeartbeat = 0
$taskStallWarningShown = $false
$buttons = New-Object System.Collections.ArrayList
$script:reportPresentationCache = @{}
$script:updatingMainLayout = $false
$script:hasTaskActivity = $false
$script:dashboardSection = "Overview"
$script:taskCancellationRequested = $false
$script:lastReportDirectory = $reportRoot
$script:lastReportPath = ""
$script:executionEnvironmentWarningShown = $false

function New-ToolReportRunDirectory {
    param([AllowNull()][string]$Category = "BaoCao")

    if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    }
    $script:lastReportDirectory = $reportRoot
    return $reportRoot
}

function Register-ToolReportPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) { $script:lastReportPath = $fullPath }
        $directory = if (Test-Path -LiteralPath $fullPath -PathType Container) { $fullPath } else { Split-Path -Parent $fullPath }
        if (-not [string]::IsNullOrWhiteSpace($directory) -and (Test-Path -LiteralPath $directory -PathType Container)) {
            $script:lastReportDirectory = $directory
        }
    } catch {}
}

function Open-ToolHtmlReport {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $extension = [IO.Path]::GetExtension([string]$Path).ToLowerInvariant()
    if ($extension -notin @('.html', '.htm')) {
        Write-ProgressLog (Get-DashboardText "report.htmlOnly" @([IO.Path]::GetFileName([string]$Path)))
        return $false
    }
    Register-ToolReportPath -Path $Path
    Start-Process -FilePath $Path
    return $true
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
    if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
        $directory = if (Test-Path -LiteralPath $reportRoot -PathType Container) { $reportRoot } else { $desktop }
    }
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
            [void](Open-ToolHtmlReport -Path $cached.HtmlPath)
            return $cached
        }
        $script:reportPresentationCache.Remove($cacheKey)
    }

    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $safePrefix = ([string]$FilePrefix -replace '[^A-Za-z0-9_-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) { $safePrefix = "BaoCao" }
    $presentationDirectory = New-ToolReportRunDirectory -Category "TaiLieu"
    $basePath = Join-Path $presentationDirectory "${safePrefix}_$($env:COMPUTERNAME)_$stamp"
    $extension = [IO.Path]::GetExtension($sourceFull).ToLowerInvariant()
    if ($extension -in @(".html", ".htm")) {
        $desktopFull = [IO.Path]::GetFullPath($presentationDirectory).TrimEnd([char]92)
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
            throw (Get-DashboardText "report.offlineSafetyFailed")
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
            -Footer "$(Get-ToolText -Key "report.footer" -Culture $script:dashboardCulture) · $releaseDisplayName" `
            -Culture $script:dashboardCulture -IncludePdf
    }
    $script:reportPresentationCache[$cacheKey] = $package
    Register-ToolReportPath -Path $package.HtmlPath
    [void](Open-ToolHtmlReport -Path $package.HtmlPath)
    Write-ProgressLog (Get-DashboardText "report.savedOpened" @([IO.Path]::GetFileName($package.HtmlPath)))
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

function Set-DashboardHeaderTitleFont {
    param([bool]$PreferLarge = $true)

    $candidateFonts = if ($PreferLarge) {
        @($fontTitle, $fontTitleCompact, $fontTitleMedium, $fontTitleSmall, $fontTitleTiny, $fontTitleMicro, $fontTitleMinimum)
    } else {
        @($fontTitleCompact, $fontTitleMedium, $fontTitleSmall, $fontTitleTiny, $fontTitleMicro, $fontTitleMinimum)
    }
    $availableWidth = [Math]::Max(1, $title.ClientSize.Width - 4)
    $selectedFont = $candidateFonts[$candidateFonts.Count - 1]
    foreach ($candidateFont in $candidateFonts) {
        $measuredWidth = [System.Windows.Forms.TextRenderer]::MeasureText([string]$title.Text, $candidateFont).Width
        if ($measuredWidth -le $availableWidth) {
            $selectedFont = $candidateFont
            break
        }
    }
    $title.Font = $selectedFont
}

function Get-DashboardComboRequiredWidth {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ComboBox]$ComboBox,
        [ValidateRange(4, 40)][int]$HorizontalSafety = 18
    )

    $textFlags = [System.Windows.Forms.TextFormatFlags]::NoPadding -bor
        [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
        [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $maximumTextWidth = 0
    foreach ($item in $ComboBox.Items) {
        $itemWidth = [System.Windows.Forms.TextRenderer]::MeasureText(
            [string]$item,
            $ComboBox.Font,
            [System.Drawing.Size]::Empty,
            $textFlags).Width
        if ($itemWidth -gt $maximumTextWidth) { $maximumTextWidth = $itemWidth }
    }
    return [int]($maximumTextWidth + [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + $HorizontalSafety)
}

function Update-MainLayout {
    if ($script:updatingMainLayout) { return }
    $script:updatingMainLayout = $true
    try {
        $form.AutoScroll = $false
        $form.AutoScrollMinSize = New-Object System.Drawing.Size(0, 0)
        $clientWidth = [Math]::Max(1, $form.ClientSize.Width)
        $clientHeight = [Math]::Max(1, $form.ClientSize.Height)
        $sidebarWidth = if ($clientWidth -ge 1040) { 196 } else { 0 }
        $outerGap = if ($clientWidth -lt 900) { 12 } else { 18 }
        $left = $sidebarWidth + $outerGap
        $right = $outerGap
        $contentWidth = [Math]::Max(360, $clientWidth - $left - $right)
        $compactHeight = [bool]($form.ClientSize.Height -lt 760)
        $ultraCompactHeight = [bool]($form.ClientSize.Height -lt 640)
        $progressExpanded = [bool]$script:hasTaskActivity

        $sidebarPanel.Visible = [bool]($sidebarWidth -gt 0)
        if ($sidebarPanel.Visible) {
            $sidebarPanel.Left = 0
            $sidebarPanel.Top = 0
            $sidebarPanel.Width = $sidebarWidth
            $sidebarPanel.Height = $clientHeight
            $sidebarBrand.Width = $sidebarWidth - 36
            $sidebarEdition.Width = $sidebarWidth - 36
            for ($navIndex = 0; $navIndex -lt $sidebarNavButtons.Count; $navIndex++) {
                $navButton = $sidebarNavButtons[$navIndex]
                $navButton.Left = 10
                $navButton.Top = 102 + ($navIndex * 54)
                $navButton.Width = $sidebarWidth - 20
                $navButton.Height = 44
                Set-ModernRoundedRegion -Control $navButton -Radius 9
            }
            $sidebarFooter.Left = 20
            $sidebarFooter.Top = [Math]::Max(420, $sidebarPanel.ClientSize.Height - 72)
            $sidebarFooter.Width = $sidebarWidth - 36
        }

        $headerPanel.Left = $sidebarWidth
        $headerPanel.Top = 0
        $headerPanel.Width = $clientWidth - $sidebarWidth
        $headerPanel.Height = if ($ultraCompactHeight) { 70 } else { 86 }

        $showHeaderBrand = [bool]($headerPanel.ClientSize.Width -ge 1000)
        $headerBrandIcon.Visible = $showHeaderBrand
        $headerBrandIcon.Left = 20
        $headerBrandIcon.Top = [Math]::Max(8, [Math]::Floor(($headerPanel.ClientSize.Height - $headerBrandIcon.Height) / 2))
        $headerTextLeft = if ($showHeaderBrand) { 74 } else { 24 }
        $title.Left = $headerTextLeft
        $title.Top = 7

        $compactHeaderToolbar = -not $showHeaderBrand
        $buttonSafety = if ($compactHeaderToolbar) { 10 } else { 14 }
        $themeButton.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 136 } else { 152 }),
            (Get-ToolUiButtonRequiredWidth -Button $themeButton -HorizontalSafety $buttonSafety))
        $offlineButton.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 112 } else { 156 }),
            (Get-ToolUiButtonRequiredWidth -Button $offlineButton -HorizontalSafety $buttonSafety))
        $languageCombo.Width = [Math]::Max(
            $(if ($compactHeaderToolbar) { 104 } else { 116 }),
            (Get-DashboardComboRequiredWidth -ComboBox $languageCombo -HorizontalSafety $(if ($compactHeaderToolbar) { 14 } else { 18 })))

        $commandGap = if ($compactHeaderToolbar) { 6 } else { 8 }
        $toolbarRight = if ($compactHeaderToolbar) { 14 } else { 22 }
        $titleCommandGap = if ($compactHeaderToolbar) { 8 } else { 12 }
        $themeButton.Top = 8
        $themeButton.Left = $headerPanel.ClientSize.Width - $themeButton.Width - $toolbarRight
        $languageCombo.Top = 10
        $languageCombo.Left = $themeButton.Left - $commandGap - $languageCombo.Width
        $offlineButton.Top = 8
        $offlineButton.Left = $languageCombo.Left - $commandGap - $offlineButton.Width
        $title.Width = [Math]::Max(260, $offlineButton.Left - $title.Left - $titleCommandGap)
        Set-DashboardHeaderTitleFont -PreferLarge:$showHeaderBrand
        $title.Height = [Math]::Max(34, $title.PreferredHeight + 4)

        $developer.Left = $headerTextLeft
        $developer.Top = 40
        $developer.Height = [Math]::Max(20, $developer.PreferredHeight)
        $developer.Width = [Math]::Max(220, $headerPanel.ClientSize.Width - $developer.Left - 24)
        $version.Left = $headerTextLeft
        $version.Top = 61
        $version.Height = [Math]::Max(18, $version.PreferredHeight)
        $version.Width = [Math]::Max(220, $headerPanel.ClientSize.Width - $version.Left - 24)
        $version.Visible = -not $ultraCompactHeight

        $introPanel.Left = $left
        $introPanel.Top = $headerPanel.Bottom + $(if ($ultraCompactHeight) { 8 } else { 14 })
        $introPanel.Width = $contentWidth
        $introPanel.Height = if ($ultraCompactHeight) { 44 } elseif ($compactHeight) { 50 } else { 58 }
        $introAccent.Left = 0
        $introAccent.Top = 0
        $introAccent.Width = 4
        $introAccent.Height = $introPanel.ClientSize.Height
        $introDetailButton.Width = if ($ultraCompactHeight) { 142 } else { 154 }
        $introDetailButton.Height = 30
        $introDetailButton.Left = $introPanel.ClientSize.Width - $introDetailButton.Width - 10
        $introDetailButton.Top = [Math]::Max(4, [Math]::Floor(($introPanel.ClientSize.Height - $introDetailButton.Height) / 2))
        $introAssistantButton.Width = if ($ultraCompactHeight) { 142 } else { 154 }
        $introAssistantButton.Height = 30
        $introAssistantButton.Left = $introDetailButton.Left - $introAssistantButton.Width - 8
        $introAssistantButton.Top = $introDetailButton.Top
        $description.Left = 15
        $description.Top = if ($ultraCompactHeight) { 9 } else { 5 }
        $description.Width = [Math]::Max(180, $introAssistantButton.Left - $description.Left - 10)
        $description.Height = 22
        $description.Visible = $true
        $introSummary.Left = 15
        $introSummary.Top = 29
        $introSummary.Width = $description.Width
        $introSummary.Height = 19
        $introSummary.Visible = -not $ultraCompactHeight

        $dashboardPanel.Left = $left
        $dashboardPanel.Top = $introPanel.Bottom + 8
        $dashboardPanel.Width = $contentWidth
        $dashboardPanel.Height = if ($ultraCompactHeight) { 66 } elseif ($compactHeight) { 72 } else { 88 }
        $cardGap = 10
        $cardWidth = [Math]::Max(145, [Math]::Floor(($dashboardPanel.ClientSize.Width - ($cardGap * 3)) / 4))
        for ($cardIndex = 0; $cardIndex -lt $dashboardCardPanels.Count; $cardIndex++) {
            $card = $dashboardCardPanels[$cardIndex]
            $card.Left = $cardIndex * ($cardWidth + $cardGap)
            $card.Top = 3
            $card.Width = $cardWidth
            $card.Height = if ($ultraCompactHeight) { 60 } elseif ($compactHeight) { 66 } else { 82 }
            if ($card.Controls.Count -ge 2) {
                $card.Controls[0].Top = if ($ultraCompactHeight) { 4 } elseif ($compactHeight) { 5 } else { 8 }
                $card.Controls[0].Left = 58
                $card.Controls[0].Width = [Math]::Max(78, $cardWidth - 68)
                $card.Controls[1].Top = if ($ultraCompactHeight) { 23 } elseif ($compactHeight) { 25 } else { 30 }
                $card.Controls[1].Left = 58
                $card.Controls[1].Width = [Math]::Max(78, $cardWidth - 68)
                $card.Controls[1].Height = if ($ultraCompactHeight) { 32 } elseif ($compactHeight) { 35 } else { 42 }
            }
            foreach ($child in $card.Controls) {
                if ([string]$child.Tag -eq "CardAccent") { $child.Height = $card.ClientSize.Height }
                if ([string]$child.Tag -eq "CardGlyph") {
                    $iconSize = if ($ultraCompactHeight) { 30 } elseif ($compactHeight) { 32 } else { 34 }
                    $child.Left = 11
                    $child.Top = [Math]::Max(7, [Math]::Floor(($card.ClientSize.Height - $iconSize) / 2))
                    $child.Width = $iconSize
                    $child.Height = $iconSize
                }
            }
            Set-ModernRoundedRegion -Control $card -Radius 13
        }

        $mainTop = $dashboardPanel.Bottom + 10
        $mainBottom = $clientHeight - $(if ($ultraCompactHeight) { 8 } else { 16 })
        $mainHeight = [Math]::Max(250, $mainBottom - $mainTop)
        $paneGap = if ($clientWidth -lt 900) { 8 } else { 12 }
        $activityWidth = if ($contentWidth -ge 980) { 302 } elseif ($contentWidth -ge 780) { 272 } else { 220 }

        $buttonPanel.Left = $left
        $buttonPanel.Top = $mainTop
        $buttonPanel.Width = [Math]::Max(470, $contentWidth - $activityWidth - $paneGap)
        $buttonPanel.Height = $mainHeight
        $activityPanel.Left = $buttonPanel.Right + $paneGap
        $activityPanel.Top = $mainTop
        $activityPanel.Width = [Math]::Max(200, $left + $contentWidth - $activityPanel.Left)
        $activityPanel.Height = $mainHeight
        $menuCaption.Width = [Math]::Max(300, $buttonPanel.ClientSize.Width - 28)
        $menuCaption.Left = 16
        $menuCaption.Top = 12
        $menuCaption.Height = 24

        $tileGap = 10
        $rowGap = if ($ultraCompactHeight) { 3 } elseif ($compactHeight) { 5 } else { 8 }
        $tileMargin = 13
        $tileWidth = [Math]::Max(220, [Math]::Floor(($buttonPanel.ClientSize.Width - ($tileMargin * 2) - $tileGap) / 2))
        $buttonPanelBottomPadding = if ($ultraCompactHeight) { 5 } else { 10 }
        $visibleButtons = @($buttons | Where-Object { $_.Visible })
        $visibleRowCount = [Math]::Max(1, [Math]::Ceiling($visibleButtons.Count / 2.0))
        $availableButtonHeight = $buttonPanel.ClientSize.Height - 42 - (($visibleRowCount - 1) * $rowGap) - $buttonPanelBottomPadding
        $calculatedTileHeight = [Math]::Floor($availableButtonHeight / $visibleRowCount)
        $minimumTileHeight = if ($ultraCompactHeight) { 42 } elseif ($compactHeight) { 46 } else { 50 }
        $tileHeight = [Math]::Max($minimumTileHeight, [Math]::Min(78, $calculatedTileHeight))
        for ($buttonIndex = 0; $buttonIndex -lt $visibleButtons.Count; $buttonIndex++) {
            $button = $visibleButtons[$buttonIndex]
            $row = [Math]::Floor($buttonIndex / 2)
            $column = $buttonIndex % 2
            $button.Left = $tileMargin + ($column * ($tileWidth + $tileGap))
            $button.Top = 42 + ($row * ($tileHeight + $rowGap))
            $button.Width = $tileWidth
            $button.Height = $tileHeight
            if ($button.Tag -and [string]$button.Tag.Kind -in @("QuickAction", "ReportAction")) {
                $textLeft = if ($tileWidth -lt 280) { 54 } else { 60 }
                $textWidth = [Math]::Max(80, $tileWidth - $textLeft - 10)
                $titleHeight = if ($tileHeight -le 46) { 17 } else { 20 }
                $descriptionHeight = if ($tileHeight -le 46) { 15 } else { [Math]::Min(22, $tileHeight - $titleHeight - 9) }
                $contentHeight = $titleHeight + $descriptionHeight + 2
                $contentTop = [Math]::Max(3, [Math]::Floor(($tileHeight - $contentHeight) / 2))
                $button.Tag.TitleLabel.Left = $textLeft
                $button.Tag.TitleLabel.Top = $contentTop
                $button.Tag.TitleLabel.Width = $textWidth
                $button.Tag.TitleLabel.Height = $titleHeight
                $button.Tag.DescriptionLabel.Left = $textLeft
                $button.Tag.DescriptionLabel.Top = $contentTop + $titleHeight + 2
                $button.Tag.DescriptionLabel.Width = $textWidth
                $button.Tag.DescriptionLabel.Height = $descriptionHeight
            }
            if ($script:dashboardSection -eq "Reports" -and
                $visibleButtons.Count % 2 -eq 1 -and $buttonIndex -eq ($visibleButtons.Count - 1)) {
                $button.Left = [Math]::Floor(($buttonPanel.ClientSize.Width - $tileWidth) / 2)
            }
            Set-ModernRoundedRegion -Control $button -Radius 10
        }

        $activityPanelCaption.Left = 16
        $activityPanelCaption.Top = 14
        $activityPanelCaption.Width = $activityPanel.ClientSize.Width - 32
        $status.Left = 16
        $status.Top = 48
        $status.Width = $activityPanel.ClientSize.Width - 32
        $status.Height = 42
        $progressCaption.Left = 16
        $progressCaption.Top = 96
        $progressCaption.Width = $activityPanel.ClientSize.Width - 32
        $progressCaption.Height = 22
        $progressCaption.Visible = $progressExpanded

        $closeButton.Height = 30
        $closeButton.Width = 108
        $closeButton.Left = $activityPanel.ClientSize.Width - $closeButton.Width - 16
        $closeButton.Top = $activityPanel.ClientSize.Height - $closeButton.Height - 12
        $stopButton.Height = $closeButton.Height
        $stopButton.Width = 108
        $stopButton.Left = $closeButton.Left - $stopButton.Width - 8
        $stopButton.Top = $closeButton.Top

        $copyLogButton.Left = 16
        $copyLogButton.Width = $activityPanel.ClientSize.Width - 32
        $copyLogButton.Height = 32
        $copyLogButton.Top = $closeButton.Top - $copyLogButton.Height - 8
        $openReportFolderButton.Left = 16
        $openReportFolderButton.Width = $activityPanel.ClientSize.Width - 32
        $openReportFolderButton.Height = 32
        $openReportFolderButton.Top = $copyLogButton.Top - $openReportFolderButton.Height - 8

        if ($progressExpanded) {
            $activityLabel.Visible = $true
            $elapsedLabel.Visible = $true
            $progressBar.Visible = $true
            $progressLog.Visible = $true
            $activityLabel.Left = 16
            $activityLabel.Top = $progressCaption.Bottom + 2
            $activityLabel.Height = 20
            $activityLabel.Width = [Math]::Max(80, $activityPanel.ClientSize.Width - $elapsedLabel.Width - 40)
            $elapsedLabel.Left = $activityPanel.ClientSize.Width - $elapsedLabel.Width - 16
            $elapsedLabel.Top = $activityLabel.Top
            $progressBar.Left = 16
            $progressBar.Top = $activityLabel.Bottom + 1
            $progressBar.Height = 14
            $progressBar.Width = $activityPanel.ClientSize.Width - 32
            $progressLog.Left = 16
            $progressLog.Top = $progressBar.Bottom + 4
            $progressLog.Width = $activityPanel.ClientSize.Width - 32
            $availableLogHeight = $openReportFolderButton.Top - $progressLog.Top - 8
            $progressLog.Height = [Math]::Max(30, $availableLogHeight)
        } else {
            $activityLabel.Visible = $false
            $elapsedLabel.Visible = $false
            $progressBar.Visible = $false
            $progressLog.Visible = $false
        }
        Set-ModernRoundedRegion -Control $introPanel -Radius 14
        Set-ModernRoundedRegion -Control $buttonPanel -Radius 14
        Set-ModernRoundedRegion -Control $activityPanel -Radius 14
        Set-ModernRoundedRegion -Control $themeButton -Radius 9
        Set-ModernRoundedRegion -Control $offlineButton -Radius 9
        Set-ModernRoundedRegion -Control $introAssistantButton -Radius 9
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
    $targetWidth = [Math]::Min(1480, $availableWidth)
    $targetHeight = [Math]::Min(900, $availableHeight)
    $form.MinimumSize = New-Object System.Drawing.Size([Math]::Min(860, $targetWidth), [Math]::Min(560, $targetHeight))
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

    $officialReleaseUrl = "https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases"
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
    $close.Size = New-Object System.Drawing.Size(112, 30)
    $close.BackColor = $primary
    $close.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $close.FlatStyle = "Flat"
    $close.FlatAppearance.BorderSize = 0
    $close.Add_Click({ $dialog.Close() })
    $buttonBar.Controls.Add($close)

    $guide = New-Object System.Windows.Forms.Button
    $guide.Text = Get-ToolText -Key "about.openGuide" -Culture $script:dashboardCulture
    $guide.Font = $fontBold
    $guide.Size = New-Object System.Drawing.Size(154, 30)
    $guide.BackColor = $surface
    $guide.ForeColor = $text
    $guide.FlatStyle = "Flat"
    $guide.Add_Click({ Open-Guide })
    $buttonBar.Controls.Add($guide)

    $history = New-Object System.Windows.Forms.Button
    $history.Text = Get-ToolText -Key "about.openHistory" -Culture $script:dashboardCulture
    $history.Font = $fontBold
    $history.Size = New-Object System.Drawing.Size(204, 30)
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
    $titleText = Get-ToolText -Key ([string]$Metadata.TitleKey) -Culture $script:dashboardCulture
    $descriptionText = Get-ToolText -Key ([string]$Metadata.DescriptionKey) -Culture $script:dashboardCulture
    return "$titleText`r`n$descriptionText"
}

function Get-DashboardSectionTitleKey {
    param([ValidateSet("Overview", "Scan", "Remediation", "Reports")][string]$Section)
    switch ($Section) {
        "Scan" { return "dashboard.section.scan" }
        "Remediation" { return "dashboard.section.remediation" }
        "Reports" { return "dashboard.section.reports" }
        default { return "dashboard.section.overview" }
    }
}

function Set-DashboardSection {
    param([ValidateSet("Overview", "Scan", "Remediation", "Reports")][string]$Section = "Overview")

    $script:dashboardSection = $Section
    $allowedNumbers = switch ($Section) {
        "Scan" { @(1, 2, 3, 4, 5, 9) }
        "Remediation" { @(6, 7, 8) }
        "Reports" { @() }
        default { @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) }
    }
    foreach ($button in $buttons) {
        $metadata = $button.Tag
        $kind = if ($metadata -and $metadata.PSObject.Properties["Kind"]) { [string]$metadata.Kind } else { "QuickAction" }
        if ($kind -eq "ReportAction") {
            $button.Visible = [bool]($Section -eq "Reports")
        } else {
            $number = if ($metadata -and $metadata.PSObject.Properties["Number"]) { [int]$metadata.Number } else { 0 }
            $button.Visible = [bool]($number -in $allowedNumbers)
        }
    }
    $menuCaption.Text = Get-ToolText -Key (Get-DashboardSectionTitleKey -Section $Section) -Culture $script:dashboardCulture

    foreach ($navButton in $sidebarNavButtons) {
        $selected = [bool]([string]$navButton.Tag.Section -eq $Section)
        $navButton.BackColor = if ($selected) {
            if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(34, 104, 196) } else { [System.Drawing.Color]::FromArgb(24, 124, 238) }
        } else {
            if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
        }
        $navButton.Font = if ($selected) { $fontBold } else { $fontSidebar }
    }
    Update-MainLayout
}

function Show-DashboardPreferences {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "dashboard.settings.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(520, 370)
    $dialog.MinimumSize = New-Object System.Drawing.Size(470, 340)
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.Font = $fontNormal

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "dashboard.settings.heading"
    $heading.Font = $fontIntroTitle
    $heading.Location = New-Object System.Drawing.Point(24, 20)
    $heading.Size = New-Object System.Drawing.Size(410, 30)
    $dialog.Controls.Add($heading)

    $settingsSummary = New-Object System.Windows.Forms.Label
    $settingsSummary.Text = Get-DashboardText "dashboard.settings.summary"
    $settingsSummary.Location = New-Object System.Drawing.Point(24, 52)
    $settingsSummary.Size = New-Object System.Drawing.Size(410, 38)
    $dialog.Controls.Add($settingsSummary)

    $languageLabel = New-Object System.Windows.Forms.Label
    $languageLabel.Text = Get-DashboardText "app.language"
    $languageLabel.Location = New-Object System.Drawing.Point(24, 108)
    $languageLabel.Size = New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($languageLabel)

    $settingsLanguage = New-Object System.Windows.Forms.ComboBox
    $settingsLanguage.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$settingsLanguage.Items.Add((Get-DashboardText "app.language.vi"))
    [void]$settingsLanguage.Items.Add((Get-DashboardText "app.language.en"))
    $settingsLanguage.SelectedIndex = if ($script:dashboardCulture -eq "en-US") { 1 } else { 0 }
    $settingsLanguage.Location = New-Object System.Drawing.Point(190, 104)
    $settingsLanguage.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsLanguage)

    $themeLabel = New-Object System.Windows.Forms.Label
    $themeLabel.Text = Get-DashboardText "dashboard.settings.theme"
    $themeLabel.Location = New-Object System.Drawing.Point(24, 151)
    $themeLabel.Size = New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($themeLabel)

    $settingsTheme = New-Object System.Windows.Forms.ComboBox
    $settingsTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$settingsTheme.Items.Add((Get-DashboardText "app.theme.light"))
    [void]$settingsTheme.Items.Add((Get-DashboardText "app.theme.dark"))
    $settingsTheme.SelectedIndex = if ($script:dashboardTheme -eq "Dark") { 1 } else { 0 }
    $settingsTheme.Location = New-Object System.Drawing.Point(190, 147)
    $settingsTheme.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsTheme)

    $settingsOffline = New-Object System.Windows.Forms.CheckBox
    $settingsOffline.Text = Get-DashboardText "dashboard.settings.offline"
    $settingsOffline.Checked = [bool]$script:offlineMode
    $settingsOffline.Location = New-Object System.Drawing.Point(190, 188)
    $settingsOffline.Size = New-Object System.Drawing.Size(244, 30)
    $dialog.Controls.Add($settingsOffline)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = Get-DashboardText "dashboard.settings.apply"
    $applyButton.Font = $fontBold
    $applyButton.FlatStyle = "Flat"
    $applyButton.FlatAppearance.BorderSize = 0
    $applyButton.UseCompatibleTextRendering = $false
    $applyButton.UseVisualStyleBackColor = $false
    $applyButton.TextAlign = "MiddleCenter"
    $applyButton.Size = New-Object System.Drawing.Size(136, 38)
    $applyButton.Location = New-Object System.Drawing.Point(218, 248)
    $applyButton.Add_Click({
        $selectedCulture = if ($settingsLanguage.SelectedIndex -eq 1) { "en-US" } else { "vi-VN" }
        if ($selectedCulture -ne $script:dashboardCulture) { Set-DashboardLanguage -Culture $selectedCulture }

        $selectedTheme = if ($settingsTheme.SelectedIndex -eq 1) { "Dark" } else { "Light" }
        if ($selectedTheme -ne $script:dashboardTheme) {
            $script:dashboardTheme = $selectedTheme
            $script:toolUiPalette = Get-ToolUiPalette -Mode $selectedTheme
            [void](Set-ToolUiThemePreference -Mode $selectedTheme)
            Set-DashboardTheme -Mode $selectedTheme
        }

        $requestedOffline = [bool]$settingsOffline.Checked
        if ($requestedOffline -ne [bool]$script:offlineMode) {
            if ($requestedOffline) {
                $script:offlineMode = $true
                [void](Set-ToolOfflineModePreference -OfflineMode $true)
                $env:TOOL_OFFLINE_MODE = "1"
                Reset-ApplicationUpdateForOffline
                Update-DashboardOfflineUi
                Set-DashboardTheme -Mode $script:dashboardTheme
            } else {
                Toggle-DashboardOfflineMode
            }
        }
        $dialog.Close()
    })
    $dialog.Controls.Add($applyButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "app.close"
    $cancelButton.Size = New-Object System.Drawing.Size(126, 38)
    $cancelButton.Location = New-Object System.Drawing.Point(364, 248)
    $cancelButton.Add_Click({ $dialog.Close() })
    $dialog.CancelButton = $cancelButton
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $applyButton

    Set-ModernRoundedRegion -Control $applyButton -Radius 9
    Set-ModernRoundedRegion -Control $cancelButton -Radius 9
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $settingsPalette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $applyButton.BackColor = $settingsPalette.Primary
    $applyButton.ForeColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    [void]$dialog.ShowDialog($form)
    $dialog.Dispose()
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
    Refresh-DashboardLocalizedActivity
    [void](Write-ToolLog -Level "AUDIT" -Event "OfflineMode.Changed" -Message $(if ($script:offlineMode) { Get-DashboardText "offline.enabledLog" } else { Get-DashboardText "offline.networkAllowedLog" }) -Data ([ordered]@{ OfflineMode=[bool]$script:offlineMode }))
    if ($script:offlineMode) {
        Reset-ApplicationUpdateForOffline
    } else {
        Request-ApplicationUpdateCheck
    }
}

function Set-DashboardLanguage {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)

    $script:dashboardCulture = $Culture
    $env:TOOL_UI_CULTURE = $Culture
    [void](Set-ToolCulturePreference -Culture $Culture)
    $form.Text = "$(Get-ToolText -Key "app.title" -Culture $Culture) - $releaseDisplayName"
    $title.Text = Get-ToolText -Key "app.title" -Culture $Culture
    $developer.Text = Get-ToolText -Key "app.developer" -Culture $Culture
    $sidebarFooter.Text = Get-DashboardText "dashboard.sidebar.footer" @($toolDisplayVersion)
    $description.Text = Get-ToolText -Key "dashboard.overview.title" -Culture $Culture
    $introSummary.Text = Get-ToolText -Key "dashboard.overview.subtitle" -Culture $Culture
    $introAssistantButton.Text = Get-ToolText -Key "app.assistant" -Culture $Culture
    $toolTip.SetToolTip($introAssistantButton, (Get-ToolText -Key "assistant.tooltip" -Culture $Culture))
    $introDetailButton.Text = Get-ToolText -Key "app.about" -Culture $Culture
    $activityPanelCaption.Text = Get-ToolText -Key "dashboard.activity" -Culture $Culture
    $sidebarBrand.Text = Get-ToolText -Key "dashboard.sidebar.brand" -Culture $Culture
    $sidebarEdition.Text = Get-ToolText -Key "dashboard.sidebar.edition" -Culture $Culture
    foreach ($navButton in $sidebarNavButtons) {
        $navButton.Text = Get-ToolText -Key ([string]$navButton.Tag.TextKey) -Culture $Culture
    }
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
            if ([string]$metadata.Kind -in @("QuickAction", "ReportAction") -and $metadata.TitleLabel -and $metadata.DescriptionLabel) {
                $metadata.TitleLabel.Text = Get-ToolText -Key ([string]$metadata.TitleKey) -Culture $Culture
                $metadata.DescriptionLabel.Text = Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture
            } else {
                $button.Text = Get-DashboardMenuText -Metadata $metadata
            }
            $button.AccessibleName = Get-ToolText -Key ([string]$metadata.TitleKey) -Culture $Culture
            $button.AccessibleDescription = Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture
            $toolTip.SetToolTip($button, (Get-ToolText -Key ([string]$metadata.DescriptionKey) -Culture $Culture))
        }
    }
    Set-DashboardSection -Section $script:dashboardSection
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
    return [pscustomobject]@{
        BackColor = if ($dark) {
            if ($Hover) { [System.Drawing.Color]::FromArgb(43, 53, 69) } else { [System.Drawing.Color]::FromArgb(34, 42, 55) }
        } else {
            if ($Hover) { [System.Drawing.Color]::FromArgb(231, 238, 247) } else { [System.Drawing.Color]::FromArgb(244, 247, 251) }
        }
        ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(220, 228, 239) } else { [System.Drawing.Color]::FromArgb(30, 64, 105) }
        TitleColor = if ($dark) { [System.Drawing.Color]::FromArgb(137, 190, 255) } else { [System.Drawing.Color]::FromArgb(0, 98, 218) }
        DescriptionColor = if ($dark) { [System.Drawing.Color]::FromArgb(174, 184, 200) } else { [System.Drawing.Color]::FromArgb(88, 101, 121) }
    }
}

function Get-DashboardStatusPalette {
    param(
        [ValidateSet("Windows", "Office", "Secure", "Integrity")][string]$Tone,
        [ValidateSet("Light", "Dark")][string]$Mode = "Light"
    )
    $dark = [bool]($Mode -eq "Dark")
    return [pscustomobject]@{
        BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(31, 38, 50) } else { [System.Drawing.Color]::FromArgb(247, 249, 252) }
        AccentColor = if ($dark) { [System.Drawing.Color]::FromArgb(105, 153, 222) } else { [System.Drawing.Color]::FromArgb(70, 112, 166) }
        ValueColor = if ($dark) { [System.Drawing.Color]::FromArgb(220, 228, 239) } else { [System.Drawing.Color]::FromArgb(34, 61, 94) }
    }
}

function Set-DashboardTheme {
    param([ValidateSet("Light", "Dark")][string]$Mode)
    $env:TOOL_UI_THEME = $Mode
    $script:toolUiPalette = Get-ToolUiPalette -Mode $Mode
    $dark = [bool]($Mode -eq "Dark")
    $surface = if ($dark) { [System.Drawing.Color]::FromArgb(29, 34, 45) } else { [System.Drawing.Color]::White }
    $background = if ($dark) { [System.Drawing.Color]::FromArgb(15, 19, 27) } else { [System.Drawing.Color]::FromArgb(246, 249, 253) }
    $primary = if ($dark) { [System.Drawing.Color]::FromArgb(137, 190, 255) } else { [System.Drawing.Color]::FromArgb(0, 98, 218) }
    $text = if ($dark) { [System.Drawing.Color]::FromArgb(226, 231, 239) } else { [System.Drawing.Color]::FromArgb(52, 64, 84) }
    $muted = if ($dark) { [System.Drawing.Color]::FromArgb(164, 174, 192) } else { [System.Drawing.Color]::FromArgb(102, 112, 133) }
    $introSurface = if ($dark) { [System.Drawing.Color]::FromArgb(30, 44, 65) } else { [System.Drawing.Color]::FromArgb(232, 243, 255) }

    $form.BackColor = $background
    $headerPanel.BackColor = $surface
    $sidebarPanel.BackColor = if ($dark) { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
    $sidebarBrand.ForeColor = [System.Drawing.Color]::White
    $sidebarEdition.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
    $sidebarFooter.ForeColor = [System.Drawing.Color]::FromArgb(182, 214, 248)
    $title.ForeColor = $primary
    $developer.ForeColor = $primary
    $version.ForeColor = $muted
    $introPanel.BackColor = $introSurface
    $introAccent.BackColor = $primary
    $description.ForeColor = $primary
    $introSummary.ForeColor = $text
    $introAssistantButton.BackColor = $primary
    $introAssistantButton.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $introDetailButton.BackColor = $primary
    $introDetailButton.ForeColor = if ($dark) { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    $dashboardPanel.BackColor = $background
    $buttonPanel.BackColor = $surface
    $activityPanel.BackColor = $surface
    $activityPanelCaption.ForeColor = $primary
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

    foreach ($cardKey in @($dashboardCards.Keys)) {
        $cardRecord = $dashboardCards[$cardKey]
        $statusPalette = Get-DashboardStatusPalette -Tone ([string]$cardRecord.Tone) -Mode $Mode
        $cardRecord.Panel.BackColor = $statusPalette.BackColor
        $cardRecord.Caption.ForeColor = $muted
        if ($cardRecord.Value.Tag -ne "StatusColor") { $cardRecord.Value.ForeColor = $statusPalette.ValueColor }
        foreach ($child in $cardRecord.Panel.Controls) {
            if ([string]$child.Tag -eq "CardAccent") { $child.BackColor = $statusPalette.AccentColor }
            if ([string]$child.Tag -eq "CardGlyph") { $child.BackColor = [System.Drawing.Color]::Transparent }
        }
    }
    if ($script:lastIntegrityResult) { Update-DashboardStatus -IntegrityResult $script:lastIntegrityResult }
    foreach ($button in $buttons) {
        $tone = if ($button.Tag -and $button.Tag.PSObject.Properties["Tone"]) { [string]$button.Tag.Tone } else { "Normal" }
        $tilePalette = Get-DashboardTilePalette -Tone $tone -Mode $Mode
        $button.BackColor = $tilePalette.BackColor
        $button.ForeColor = $tilePalette.ForeColor
        if ($button.Tag -and [string]$button.Tag.Kind -in @("QuickAction", "ReportAction")) {
            if ($button.Tag.TitleLabel) { $button.Tag.TitleLabel.ForeColor = $tilePalette.TitleColor }
            if ($button.Tag.DescriptionLabel) { $button.Tag.DescriptionLabel.ForeColor = $tilePalette.DescriptionColor }
        }
    }
    foreach ($navButton in $sidebarNavButtons) {
        $selected = [bool]([string]$navButton.Tag.Section -eq $script:dashboardSection)
        $navButton.BackColor = if ($selected) {
            if ($dark) { [System.Drawing.Color]::FromArgb(34, 104, 196) } else { [System.Drawing.Color]::FromArgb(24, 124, 238) }
        } else {
            if ($dark) { [System.Drawing.Color]::FromArgb(7, 31, 61) } else { [System.Drawing.Color]::FromArgb(6, 61, 125) }
        }
        $navButton.ForeColor = [System.Drawing.Color]::White
    }

    $neutralLightArgb = [System.Drawing.Color]::FromArgb(52, 64, 84).ToArgb()
    $neutralDarkArgb = [System.Drawing.Color]::FromArgb(226, 231, 239).ToArgb()
    if ($status.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb)) { $status.ForeColor = $text }
    if ($activityLabel.ForeColor.ToArgb() -in @($neutralLightArgb, $neutralDarkArgb, [System.Drawing.Color]::FromArgb(18, 59, 116).ToArgb(), [System.Drawing.Color]::FromArgb(126, 174, 255).ToArgb())) { $activityLabel.ForeColor = $text }
    foreach ($actionButton in @($introAssistantButton, $introDetailButton, $themeButton, $offlineButton, $openReportFolderButton, $copyLogButton, $stopButton, $closeButton)) {
        Set-ToolUiActionButtonVisual -Button $actionButton -Mode $Mode
    }
    Set-ToolUiLiteralText -Root $form
    Register-ToolUiDynamicContrast -Root $form -Mode $Mode
    $form.Invalidate($true)
}

function Update-DashboardStatus {
    param($IntegrityResult)
    $script:lastIntegrityResult = $IntegrityResult
    $successColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(86, 230, 156) } else { [System.Drawing.Color]::FromArgb(0, 125, 69) }
    $warningColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(255, 193, 82) } else { [System.Drawing.Color]::FromArgb(217, 119, 0) }
    $compatibilityCard = $dashboardCards["Compatibility"]
    $compatibilityCard.Value.AutoEllipsis = $true
    $catalogHealth = [string]$compatibilityState.CatalogHealth
    $catalogAgeDays = [int]$compatibilityState.CatalogAgeDays
    $catalogMaximumAgeDays = [int]$compatibilityState.MaximumReviewAgeDays
    $catalogTooltip = if ($catalogHealth -eq "Stale") {
        Get-DashboardText "dashboard.compatibility.catalogStale" @($catalogAgeDays, $catalogMaximumAgeDays)
    } elseif ($catalogHealth -eq "Warning") {
        Get-DashboardText "dashboard.compatibility.catalogWarning" @($catalogAgeDays, $catalogMaximumAgeDays)
    } else {
        Get-DashboardText "dashboard.compatibility.catalogFresh" @($compatibilityState.ReviewedAtUtc, $catalogAgeDays, $catalogMaximumAgeDays)
    }
    $compatibilityCard.Value.Text = if ($catalogHealth -eq "Stale") {
        Get-DashboardText "dashboard.compatibility.valueStale" @($capabilityState.WindowsReleaseName)
    } elseif ($catalogHealth -eq "Warning") {
        Get-DashboardText "dashboard.compatibility.valueWarning" @($capabilityState.WindowsReleaseName, $catalogAgeDays)
    } else {
        [string]$capabilityState.WindowsReleaseName
    }
    $toolTip.SetToolTip($compatibilityCard.Panel, $catalogTooltip)
    $toolTip.SetToolTip($compatibilityCard.Value, $catalogTooltip)
    if ($catalogHealth -in @("Warning", "Stale")) {
        $compatibilityCard.Value.ForeColor = $warningColor
        $compatibilityCard.Value.Tag = "StatusColor"
    } else {
        $compatibilityPalette = Get-DashboardStatusPalette -Tone ([string]$compatibilityCard.Tone) -Mode $script:dashboardTheme
        $compatibilityCard.Value.ForeColor = $compatibilityPalette.ValueColor
        $compatibilityCard.Value.Tag = $null
    }
    $dashboardCards["Architecture"].Value.Text = [string]$capabilityState.OfficeSummary
    $dashboardCards["SecureLaunch"].Value.Text = if ($env:TOOL_SECURE_LAUNCH -eq "1") { Get-ToolText -Key "dashboard.secure" -Culture $script:dashboardCulture } else { Get-ToolText -Key "dashboard.source" -Culture $script:dashboardCulture }
    $dashboardCards["Integrity"].Value.Text = if ($IntegrityResult.Valid) {
        Get-ToolText -Key "dashboard.integrity.ok" -Culture $script:dashboardCulture -FormatArguments @($safetyPolicyState.RegistryValuePolicyCount)
    } else {
        Get-ToolText -Key "dashboard.integrity.failed" -Culture $script:dashboardCulture
    }
    $dashboardCards["Integrity"].Value.ForeColor = if ($IntegrityResult.Valid) { $successColor } else { $warningColor }
    $dashboardCards["Integrity"].Value.Tag = "StatusColor"
    $dashboardCards["SecureLaunch"].Value.ForeColor = if ($env:TOOL_SECURE_LAUNCH -eq "1") { $successColor } else { $warningColor }
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
    } catch { [void]$invalid.Add((Get-DashboardText "kms.readFailed" @($_.Exception.Message))) }
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
            (Get-DashboardText "kms.file.header")
            (Get-DashboardText "kms.file.hint")
            (Get-DashboardText "kms.file.updated" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
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
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "kms.saveFailed" @($_.Exception.Message)),
            (Get-DashboardText "kms.saveFailedTitle"), "OK", "Error") | Out-Null
        return $false
    }
}

function Confirm-KmsApprovalConfiguration {
    $config = Get-ApprovedKmsEntries
    $detected = @(Get-DetectedKmsServers)
    $unapprovedDetected = @($detected | Where-Object { -not (Test-DetectedKmsIsApproved $_ $config.Entries) })
    if ($config.Entries.Count -gt 0 -and $config.Invalid.Count -eq 0 -and $unapprovedDetected.Count -eq 0) { return $true }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "kms.dialog.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false; $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(740, 390)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244,246,249); $dialog.Font = $fontNormal
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "kms.dialog.heading"
    $heading.Font = $fontBold; $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.Location = New-Object System.Drawing.Point(18, 14); $heading.Size = New-Object System.Drawing.Size(700, 26)
    $dialog.Controls.Add($heading)
    $info = New-Object System.Windows.Forms.Label
    $detectedText = if ($detected.Count) { $detected -join ', ' } else { Get-DashboardText "kms.dialog.noneDetected" }
    $unapprovedText = if ($unapprovedDetected.Count) { Get-DashboardText "kms.dialog.unapproved" @(($unapprovedDetected -join ', ')) } else { '' }
    $info.Text = Get-DashboardText "kms.dialog.summary" @($detectedText, $unapprovedText)
    $info.Location = New-Object System.Drawing.Point(18, 48); $info.Size = New-Object System.Drawing.Size(700, 70)
    $dialog.Controls.Add($info)
    $editor = New-Object System.Windows.Forms.TextBox
    $editor.Multiline = $true; $editor.ScrollBars = 'Vertical'; $editor.Font = $fontSmall
    $editor.Location = New-Object System.Drawing.Point(18, 126); $editor.Size = New-Object System.Drawing.Size(700, 125)
    $editor.Text = (@($config.Entries) -join [Environment]::NewLine)
    $dialog.Controls.Add($editor)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText "kms.dialog.hint"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(102,112,133); $hint.Location = New-Object System.Drawing.Point(18, 258); $hint.Size = New-Object System.Drawing.Size(700, 22)
    $dialog.Controls.Add($hint)
    $open = New-Object System.Windows.Forms.Button; $open.Text = Get-DashboardText "kms.dialog.openFile"; $open.Location = New-Object System.Drawing.Point(18, 302); $open.Size = New-Object System.Drawing.Size(170, 34)
    $open.Add_Click({ Start-Process -FilePath $nativeNotepadPath -ArgumentList ('"' + $approvedKmsFile + '"') }); $dialog.Controls.Add($open)
    $strict = New-Object System.Windows.Forms.Button; $strict.Text = Get-DashboardText "kms.dialog.strict"; $strict.Location = New-Object System.Drawing.Point(196, 302); $strict.Size = New-Object System.Drawing.Size(184, 34)
    $strict.Add_Click({ $dialog.Tag = 'Strict'; $dialog.Close() }); $dialog.Controls.Add($strict)
    $save = New-Object System.Windows.Forms.Button; $save.Text = Get-DashboardText "kms.dialog.save"; $save.Font = $fontBold; $save.Location = New-Object System.Drawing.Point(388, 302); $save.Size = New-Object System.Drawing.Size(172, 34)
    $save.Add_Click({ $dialog.Tag = 'Save'; $dialog.Close() }); $dialog.Controls.Add($save)
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = Get-DashboardText "app.close"; $cancel.Location = New-Object System.Drawing.Point(568, 302); $cancel.Size = New-Object System.Drawing.Size(150, 34)
    $cancel.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() }); $dialog.CancelButton = $cancel; $dialog.Controls.Add($cancel)
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag; $entriesToSave = @($editor.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $dialog.Dispose()
    if ($choice -eq 'Save') {
        if ($entriesToSave.Count -eq 0) {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "kms.empty.confirm"),
                (Get-DashboardText "kms.empty.title"), 'YesNo', 'Warning')
            if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
        }
        if (-not (Save-ApprovedKmsEntries $entriesToSave)) { return $false }
        Write-ProgressLog (Get-DashboardText "kms.updated" @($approvedKmsFile))
        return $true
    }
    if ($choice -eq 'Strict') { Write-ProgressLog (Get-DashboardText "kms.strictContinued"); return $true }
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

function Test-ToolIntegrity {
    if (-not (Test-Path -LiteralPath $integrityManifest)) {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message=(Get-DashboardText "integrity.manifestMissing") }
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $required = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($requiredName in $requiredIntegrityFiles) { [void]$required.Add($requiredName) }
    try {
        foreach ($line in Get-Content -LiteralPath $integrityManifest -ErrorAction Stop) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
            if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
                $problems.Add((Get-DashboardText "integrity.invalidManifestLine" @($line)))
                continue
            }
            $expected = $matches[1].ToUpperInvariant()
            $relativeName = $matches[2].Trim()
            if ([IO.Path]::GetFileName($relativeName) -ne $relativeName -or $relativeName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                $problems.Add((Get-DashboardText "integrity.unsafeManifestName" @($relativeName)))
                continue
            }
            if (-not $required.Contains($relativeName)) {
                $problems.Add((Get-DashboardText "integrity.unexpectedFile" @($relativeName)))
                continue
            }
            if (-not $seen.Add($relativeName)) {
                $problems.Add((Get-DashboardText "integrity.duplicateFile" @($relativeName)))
                continue
            }
            $target = Join-Path $baseDir $relativeName
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $problems.Add((Get-DashboardText "integrity.fileMissing" @($relativeName)))
                continue
            }
            $actual = Get-Sha256 $target
            if (-not $actual -or $actual -ne $expected) { $problems.Add((Get-DashboardText "integrity.hashMismatch" @($relativeName))) }
        }
        foreach ($requiredName in $requiredIntegrityFiles) {
            if (-not $seen.Contains($requiredName)) { $problems.Add((Get-DashboardText "integrity.requiredEntryMissing" @($requiredName))) }
        }
    } catch {
        return [pscustomobject]@{ Checked=$false; Valid=$false; Message=(Get-DashboardText "integrity.manifestReadFailed" @($_.Exception.Message)) }
    }
    if ($problems.Count -eq 0) {
        return [pscustomobject]@{ Checked=$true; Valid=$true; Message=(Get-DashboardText "integrity.valid") }
    }
    return [pscustomobject]@{ Checked=$true; Valid=$false; Message=(Get-DashboardText "integrity.warning" @(($problems -join '; '))) }
}

function New-SecureRuntimePath([string]$prefix) {
    if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
    }
    return (Join-Path $runtimeDir ($prefix + [guid]::NewGuid().ToString("N") + ".json"))
}

function Confirm-IntegrityForElevatedAction([string]$actionName) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedToolDirectoryAcl $baseDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.adminSourceBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.adminBlockedTitle" -Culture $script:dashboardCulture), "OK", "Error") | Out-Null
        return $false
    }
    if (-not (Test-ProtectedToolDirectoryAcl $runtimeDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "integrity.runtimeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "integrity.protectionTitle" -Culture $script:dashboardCulture),
            "OK",
            "Error"
        ) | Out-Null
        return $false
    }
    $env:TOOL_SECURE_RUNTIME_FAILED = "0"
    $freshResult = Test-ToolIntegrity
    if ($freshResult.Valid) { return $true }
    Write-ProgressLog (Get-DashboardText "integrity.blockedLog" @($actionName, $freshResult.Message))
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
        $status.Text = Get-DashboardText "status.chooseTask"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(20, 126, 82)
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
        $message = Get-DashboardText "timeline.writeRejected" @($_.Exception.Message)
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $message -Data ([ordered]@{ EventType=$EventType; Source=$Source }))
        Write-ProgressLog (Get-DashboardText "common.warning" @($message))
        return [pscustomobject]@{ Written=$false; Error=$_.Exception.Message }
    }
}

function Start-ProgressDisplay([string]$action, [string]$detail, [bool]$preserveLog) {
    if (-not $preserveLog) { $progressLog.Clear() }
    $script:hasTaskActivity = $true
    $script:taskCancellationRequested = $false
    $script:taskStartedAt = Get-Date
    $script:lastProgressHeartbeat = 0
    $script:taskStallWarningShown = $false
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
    $status.Text = Get-DashboardText "status.chooseTask"
    $status.ForeColor = [System.Drawing.Color]::FromArgb(20, 126, 82)
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
[void](Write-ToolLog -Level "INFO" -Event "Application.Start" -Message (Get-DashboardText "log.dashboardStarted") -Data ([ordered]@{
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
    Write-ProgressLog (Get-DashboardText "progress.logWarning" @($loggingState.Error))
}
if (-not $timelineState.Enabled) {
    Write-ProgressLog (Get-DashboardText "progress.timelineWarning" @($timelineState.Error))
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
    if (-not $availability.Available) { throw (Get-DashboardText "module.unavailable" @($moduleId, $availability.Message)) }
    if ($availability.Descriptor.RequiresElevation -and -not $elevatedLaunch) { throw (Get-DashboardText "module.elevationRequired" @($moduleId)) }
    return $availability.Descriptor
}

function Get-ToolElevatedEnvironmentSnapshot {
    $allowedNames = @(
        'TOOL_APPROVED_KMS_FILE','TOOL_BUILD_ARCHITECTURE','TOOL_CAPABILITY_SCHEMA',
        'TOOL_COMPATIBILITY_CATALOG','TOOL_COMPATIBILITY_SCHEMA','TOOL_CORRELATION_ID',
        'TOOL_DASHBOARD_SCHEMA','TOOL_DATA_OWNER_SID','TOOL_DATA_ROOT','TOOL_DATA_SCHEMA_VERSION','TOOL_DATA_SCOPE',
        'TOOL_ENTERPRISE_NETWORK_ALLOWED','TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH','TOOL_ENTERPRISE_ROOT',
        'TOOL_ENTERPRISE_SCHEMA','TOOL_EXPECTED_PROCESS_ARCHITECTURE','TOOL_LAUNCHER_PATH',
        'TOOL_LAUNCHER_PID','TOOL_LAUNCH_MODE','TOOL_LEGACY_DATA_ROOT','TOOL_LOCALIZATION_SCHEMA',
        'TOOL_LOG_PATH','TOOL_MODULE_CONTRACT_SCHEMA','TOOL_MODULE_ID','TOOL_MODULE_INVOCATION_ID',
        'TOOL_OFFLINE_MODE','TOOL_OFFLINE_POLICY_SCHEMA','TOOL_OFFLINE_SETTINGS_PATH','TOOL_PLUGIN_DIR',
        'TOOL_POWERSHELL_PATH','TOOL_REPORT_SCHEMA','TOOL_SAFETY_POLICY_SCHEMA','TOOL_SECURE_LAUNCH',
        'TOOL_SELF_UPDATE_ALLOWED',
        'TOOL_SECURE_RUNTIME_DIR','TOOL_SECURE_RUNTIME_FAILED','TOOL_TIMELINE_KEY_PATH','TOOL_TIMELINE_PATH',
        'TOOL_TOOL_VERSION','TOOL_UI_CULTURE','TOOL_UI_CULTURE_SETTINGS_PATH','TOOL_UI_THEME',
        'TOOL_UI_THEME_SETTINGS_PATH','TOOL_UPDATE_CACHE_ROOT'
    )
    $snapshot = [ordered]@{}
    foreach ($name in $allowedNames) {
        $value = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
        $snapshot[$name] = if ($null -eq $value) { $null } else { [string]$value }
    }
    if ([string]$snapshot['TOOL_SECURE_LAUNCH'] -ne '1') { throw 'ElevatedBridgeSecureLaunchRequired' }
    if ([string]::IsNullOrWhiteSpace([string]$snapshot['TOOL_SECURE_RUNTIME_DIR'])) { throw 'ElevatedBridgeRuntimeMissing' }
    if ([string]$snapshot['TOOL_DATA_SCOPE'] -eq 'User') {
        try {
            $dataOwnerSid = New-Object Security.Principal.SecurityIdentifier([string]$snapshot['TOOL_DATA_OWNER_SID'])
            if (-not $dataOwnerSid.IsAccountSid()) { throw 'ElevatedBridgeDataOwnerSidInvalid' }
        } catch { throw 'ElevatedBridgeDataOwnerSidInvalid' }
    }
    if ([string]$snapshot['TOOL_MODULE_ID'] -notmatch '^[a-z0-9][a-z0-9._-]{0,127}$') { throw 'ElevatedBridgeModuleIdInvalid' }
    $invocationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$snapshot['TOOL_MODULE_INVOCATION_ID'], [ref]$invocationId) -or $invocationId -eq [guid]::Empty) {
        throw 'ElevatedBridgeInvocationIdInvalid'
    }
    return $snapshot
}

function New-ToolElevatedBootstrapArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BridgeScriptPath,
        [Parameter(Mandatory = $true)][string]$TargetFilePath,
        [Parameter(Mandatory = $true)][string]$TargetArguments,
        [bool]$HiddenWindow = $false
    )

    if (-not (Test-Path -LiteralPath $BridgeScriptPath -PathType Leaf)) { throw 'ElevatedBridgeScriptMissing' }
    if (-not (Test-Path -LiteralPath $TargetFilePath -PathType Leaf)) { throw 'ElevatedBridgeTargetMissing' }
    $payload = [ordered]@{
        SchemaVersion = '1.0'
        CreatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        TargetFilePath = [IO.Path]::GetFullPath($TargetFilePath)
        TargetArguments = [string]$TargetArguments
        HiddenWindow = [bool]$HiddenWindow
        Environment = Get-ToolElevatedEnvironmentSnapshot
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 5 -Compress
    $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
    if ($payloadBase64.Length -gt 24000) { throw 'ElevatedBridgePayloadTooLarge' }
    return "-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File `"$BridgeScriptPath`" -PayloadBase64 `"$payloadBase64`""
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

    if ($script:activeProcess -and -not $script:activeProcess.HasExited) { throw (Get-DashboardText "module.alreadyRunning") }
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
        if ($Elevate) {
            $startParameters.ArgumentList = New-ToolElevatedBootstrapArguments -BridgeScriptPath $elevatedBridgeScript -TargetFilePath $toolPowerShellPath -TargetArguments $Arguments -HiddenWindow ([bool]$Hidden)
            $startParameters.Verb = "RunAs"
        }
        if ($Hidden) { $startParameters.WindowStyle = "Hidden" }
        $process = Start-Process @startParameters
        if (-not $process) { throw (Get-DashboardText "module.processMissing") }
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
        [switch]$Elevate,
        [switch]$Hidden
    )

    $descriptor = Get-ReadyToolModule -moduleId $ModuleId -elevatedLaunch ([bool]$Elevate)
    $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
    $previousModuleId = [string]$env:TOOL_MODULE_ID
    $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
    try {
        $env:TOOL_MODULE_ID = $descriptor.ModuleId
        $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
        $startParameters = @{ FilePath=$toolPowerShellPath; ArgumentList=$Arguments; PassThru=$true }
        if ($Elevate) {
            $startParameters.ArgumentList = New-ToolElevatedBootstrapArguments -BridgeScriptPath $elevatedBridgeScript -TargetFilePath $toolPowerShellPath -TargetArguments $Arguments -HiddenWindow ([bool]$Hidden)
            $startParameters.Verb = "RunAs"
        }
        if ($Hidden) { $startParameters.WindowStyle = "Hidden" }
        $process = Start-Process @startParameters
        if (-not $process) { throw (Get-DashboardText "module.processMissing") }
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

function Show-ReportPrivacyChooser {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-ToolText -Key 'report.privacy.title' -Culture $script:dashboardCulture
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.ClientSize = New-Object System.Drawing.Size(650, 260)
    $dialog.Tag = 'Cancel'

    $message = New-Object System.Windows.Forms.Label
    $message.Text = Get-ToolText -Key 'report.privacy.promptExplicit' -Culture $script:dashboardCulture
    $message.Font = $fontNormal
    $message.Location = New-Object System.Drawing.Point(28, 24)
    $message.Size = New-Object System.Drawing.Size(594, 140)
    $message.AutoEllipsis = $true
    $dialog.Controls.Add($message)

    $redactedButton = New-Object System.Windows.Forms.Button
    $redactedButton.Text = Get-ToolText -Key 'report.privacy.redactedButton' -Culture $script:dashboardCulture
    $redactedButton.Location = New-Object System.Drawing.Point(28, 188)
    $redactedButton.Size = New-Object System.Drawing.Size(212, 42)
    $redactedButton.Font = $fontBold
    $redactedButton.Add_Click({ $dialog.Tag = 'Redacted'; $dialog.Close() })
    $dialog.Controls.Add($redactedButton)

    $internalButton = New-Object System.Windows.Forms.Button
    $internalButton.Text = Get-ToolText -Key 'report.privacy.internalButton' -Culture $script:dashboardCulture
    $internalButton.Location = New-Object System.Drawing.Point(252, 188)
    $internalButton.Size = New-Object System.Drawing.Size(220, 42)
    $internalButton.Add_Click({ $dialog.Tag = 'Internal'; $dialog.Close() })
    $dialog.Controls.Add($internalButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-ToolText -Key 'report.privacy.cancelButton' -Culture $script:dashboardCulture
    $cancelButton.Location = New-Object System.Drawing.Point(484, 188)
    $cancelButton.Size = New-Object System.Drawing.Size(138, 42)
    $cancelButton.Add_Click({ $dialog.Tag = 'Cancel'; $dialog.Close() })
    $dialog.Controls.Add($cancelButton)
    $dialog.AcceptButton = $redactedButton
    $dialog.CancelButton = $cancelButton

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    Set-ToolUiPrimaryActionButtonVisual -Button $redactedButton -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Start-Report([string]$mode, [string]$displayName) {
    if (-not (Test-Path -LiteralPath $reportScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "report.missingModule" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "report.errorTitle" -Culture $script:dashboardCulture),
            "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = Show-ReportPrivacyChooser
    if ($privacyChoice -eq 'Cancel') { return }
    $redactSensitive = [bool]($privacyChoice -eq 'Redacted')
    try {
        Start-ProgressDisplay $displayName (Get-ToolText -Key "report.starting" -Culture $script:dashboardCulture) $false
        Write-ProgressLog (Get-ToolText -Key $(if ($redactSensitive) { "report.redactedProgress" } else { "report.internalProgress" }) -Culture $script:dashboardCulture)
        $privacyArgument = if ($redactSensitive) { " -RedactSensitive" } else { "" }
        $output = New-ToolReportRunDirectory -Category "BaoCao-$mode"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$reportScript`" -OutputDir `"$output`" -Mode `"$mode`" -Culture `"$script:dashboardCulture`" -ApprovedKmsServerFile `"$approvedKmsFile`" -Pdf$privacyArgument"
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

function Get-CleanupScopeLabel {
    param([ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope)
    $key = switch ($Scope) {
        "WindowsOffice" { "cleanup.scope.windowsOffice" }
        "WindowsThirdParty" { "cleanup.scope.windowsThirdParty" }
        "OfficeThirdParty" { "cleanup.scope.officeThirdParty" }
        "ThirdParty" { "cleanup.scope.thirdParty" }
        "Windows" { "cleanup.scope.windows" }
        "Office" { "cleanup.scope.office" }
        default { "cleanup.scope.all" }
    }
    return Get-DashboardText $key
}

function ConvertTo-CleanupScanScope {
    param([bool]$Windows, [bool]$Office, [bool]$ThirdParty)

    $selectionKey = "{0}{1}{2}" -f [int]$Windows, [int]$Office, [int]$ThirdParty
    switch ($selectionKey) {
        "100" { return "Windows" }
        "010" { return "Office" }
        "001" { return "ThirdParty" }
        "110" { return "WindowsOffice" }
        "101" { return "WindowsThirdParty" }
        "011" { return "OfficeThirdParty" }
        "111" { return "All" }
        default { return "" }
    }
}

function Test-GuiCleanupScopeIncludes {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope,
        [ValidateSet("Windows", "Office", "ThirdParty")][string]$Component
    )

    switch ($Component) {
        "Windows" { return [bool]($Scope -in @("All", "Windows", "WindowsOffice", "WindowsThirdParty")) }
        "Office" { return [bool]($Scope -in @("All", "Office", "WindowsOffice", "OfficeThirdParty")) }
        "ThirdParty" { return [bool]($Scope -in @("All", "ThirdParty", "WindowsThirdParty", "OfficeThirdParty")) }
    }
    return $false
}

function Get-GuiCleanupItemComponentScope {
    param($CleanupItem)

    if ($CleanupItem.PSObject.Properties['ComponentScope']) {
        $explicitScope = [string]$CleanupItem.ComponentScope
        if ($explicitScope -in @("Windows", "Office", "ThirdParty", "Shared")) { return $explicitScope }
    }
    $type = [string]$CleanupItem.Type
    $kind = [string]$CleanupItem.Kind
    $text = (([string]$CleanupItem.Name) + " " + ([string]$CleanupItem.Location) + " " + ([string]$CleanupItem.Detail)).Trim()
    if ($type -eq "Application" -or $kind -match '^ThirdParty') { return "ThirdParty" }
    if ($kind -eq "OfficeKmsLicense" -or $text -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|\bOffice\s+KMS\b') { return "Office" }
    if ($kind -eq "WindowsKmsLicense" -or $kind -eq "SppNoGenTicketPolicy" -or
        $text -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|\bSppExtComObj\b|\bNoGenTicket\b') { return "Windows" }
    return "Shared"
}

function Get-GuiScopedCleanupItems {
    param(
        $CleanupItems,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$Scope = "All"
    )
    return @($CleanupItems | Where-Object {
        $componentScope = Get-GuiCleanupItemComponentScope -CleanupItem $_
        if ($componentScope -eq "Shared") {
            return [bool]((Test-GuiCleanupScopeIncludes -Scope $Scope -Component "Windows") -or
                (Test-GuiCleanupScopeIncludes -Scope $Scope -Component "Office"))
        }
        return Test-GuiCleanupScopeIncludes -Scope $Scope -Component $componentScope
    })
}

function Start-Cleanup {
    param(
        [switch]$ReuseSessionSettings,
        [switch]$AutoSafeMode,
        [switch]$DryRunMode,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$ScanScope = "All"
    )
    if (-not (Test-Path -LiteralPath $cleanupScript)) {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.moduleMissing"),
            (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    if (-not $ReuseSessionSettings) {
        $script:cleanupScanScope = $ScanScope
        $script:cleanupAutoSafeMode = [bool]$AutoSafeMode
        $script:cleanupDryRunMode = [bool]$DryRunMode
        if (((Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") -or
            (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Office")) -and
            -not (Confirm-KmsApprovalConfiguration)) {
            $script:cleanupAutoSafeMode = $false
            $status.Text = Get-DashboardText "cleanup.kmsCancelled"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "cleanup.kmsNotConfirmed")
            return
        }
        $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.privacy.prompt"),
            (Get-DashboardText "cleanup.privacy.title"),
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1)
        if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            $script:cleanupAutoSafeMode = $false
            $script:cleanupDryRunMode = $false
            return
        }
        $script:cleanupRedactSensitive = [bool]($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "cleanup.scan.action") (Get-DashboardText "cleanup.scan.detail") $false
        Write-ProgressLog (Get-DashboardText "cleanup.scan.scopeLog" @((Get-CleanupScopeLabel -Scope $script:cleanupScanScope)))
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-Quet"
        $script:cleanupDecisionFile = New-SecureRuntimePath "tool-license-decision-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupDecisionFile`" -ScanScope `"$script:cleanupScanScope`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.scan" -Arguments $arguments -Action (Get-DashboardText "cleanup.scan.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "cleanup.scan.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "cleanup.scan.startFailed" @($_.Exception.Message))
    }
}

function Start-ThirdPartyManualReview {
    # This entry point only starts the assessment.  It never applies a cleanup
    # on its own: the user must choose one/all eligible exact artifacts and
    # confirm again in the final plan dialog.
    Start-Cleanup -ScanScope "ThirdParty"
}

function Enable-DashboardOnlineForCurrentCatalogSession {
    param([switch]$ConsentAlreadyGranted)

    if (-not $ConsentAlreadyGranted) {
        $consent = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "software.online.consentMessage"),
            (Get-DashboardText "software.online.consentTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) {
            $status.Text = Get-DashboardText "software.online.cancelledStatus"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
            return $false
        }
    }

    # This is intentionally local to the current process.  The Offline policy
    # writes NextLaunchMode=Offline, so a new Tool launch will fail closed even
    # though the catalog button can enable Online for this one approved run.
    if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne '0' -or
        -not (Test-ToolNetworkActionAllowed -Scope Internet)) {
        $script:offlineMode = $false
        [void](Set-ToolOfflineModePreference -OfflineMode $false)
        $env:TOOL_OFFLINE_MODE = '0'
        Update-DashboardOfflineUi
        Set-DashboardTheme -Mode $script:dashboardTheme
        Refresh-DashboardLocalizedActivity
        [void](Write-ToolLog -Level 'AUDIT' -Event 'OnlineMode.CatalogSessionEnabled' -Message (Get-DashboardText 'offline.networkAllowedLog') -Data ([ordered]@{
            Source='SoftwareCatalog'; SessionOnly=$true; UploadedInventory=$false; SentLicenseKeys=$false
        }))
    }
    return [bool](Test-ToolNetworkActionAllowed -Scope Internet)
}

function Start-SoftwareCatalogOnlineUpdate {
    param(
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")]
        [string]$ScanScope = "ThirdParty",
        [switch]$ConsentAlreadyGranted
    )

    $script:softwareCatalogAutoScan = $false
    $script:softwareCatalogAutoScanScope = "ThirdParty"
    if (-not (Enable-DashboardOnlineForCurrentCatalogSession -ConsentAlreadyGranted:$ConsentAlreadyGranted)) {
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "software.online.action") (Get-DashboardText "software.online.connecting") $false
        Write-ProgressLog (Get-DashboardText "software.online.privacyLog")
        Write-ProgressLog (Get-DashboardText "cleanup.scan.scopeLog" @((Get-CleanupScopeLabel -Scope $ScanScope)))
        $script:softwareCatalogUpdateResultFile = New-SecureRuntimePath "tool-software-catalog-update-"
        $script:softwareCatalogAutoScan = $true
        $script:softwareCatalogAutoScanScope = $ScanScope
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$softwareCatalogUpdateScript`" -ResultFile `"$script:softwareCatalogUpdateResultFile`" -ConsentGranted -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "software.catalog.update" -Arguments $arguments -Action (Get-DashboardText "software.online.action") -Hidden)
        $status.Text = Get-DashboardText "software.online.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:softwareCatalogAutoScan = $false
        $script:softwareCatalogAutoScanScope = "ThirdParty"
        if ($script:softwareCatalogUpdateResultFile -and (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:softwareCatalogUpdateResultFile -Force -ErrorAction SilentlyContinue
        }
        $script:softwareCatalogUpdateResultFile = ""
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "software.online.startFailed" @($_.Exception.Message))
    }
}

function Get-SoftwareCatalogOnlineFailureDetail {
    param($Result)

    $errorText = if ($Result -and $Result.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
        [string]$Result.Error
    } else { Get-DashboardText 'common.unknown' }
    $code = if ($Result -and $Result.PSObject.Properties['ErrorCode']) { [string]$Result.ErrorCode } else { '' }
    if ([string]::IsNullOrWhiteSpace($code) -and (Get-Command Get-ToolSoftwareCatalogFailureCode -ErrorAction SilentlyContinue)) {
        $code = Get-ToolSoftwareCatalogFailureCode -Message $errorText
    }
    $causeKey = switch ($code) {
        'OfflinePolicy' { 'software.online.failure.offlinePolicy' }
        'Allowlist' { 'software.online.failure.allowlist' }
        'Signature' { 'software.online.failure.signature' }
        'Schema' { 'software.online.failure.schema' }
        'Version' { 'software.online.failure.version' }
        'Proxy' { 'software.online.failure.proxy' }
        'Connectivity' { 'software.online.failure.connectivity' }
        default { 'software.online.failure.unknown' }
    }
    return Get-DashboardText 'software.online.failure.detail' @((Get-DashboardText $causeKey), $errorText)
}

function Show-SoftwareCatalogFailureDialog {
    param([Parameter(Mandatory = $true)][string]$Detail)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText 'software.online.failedTitle'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(650, 230)
    $dialog.Font = $fontNormal
    $dialog.Tag = 'Close'

    $message = New-Object System.Windows.Forms.Label
    $message.Text = $Detail
    $message.AutoEllipsis = $true
    $message.Location = New-Object System.Drawing.Point(20, 18)
    $message.Size = New-Object System.Drawing.Size(610, 142)
    $message.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($message)

    $retry = New-Object System.Windows.Forms.Button
    $retry.Text = Get-DashboardText 'software.online.retry'
    $retry.Size = New-Object System.Drawing.Size(160, 38)
    $retry.Location = New-Object System.Drawing.Point(132, 174)
    $retry.Add_Click({ $dialog.Tag='Retry'; $dialog.Close() })
    $dialog.Controls.Add($retry)

    $offline = New-Object System.Windows.Forms.Button
    $offline.Text = Get-DashboardText 'software.online.scanOffline'
    $offline.Size = New-Object System.Drawing.Size(176, 38)
    $offline.Location = New-Object System.Drawing.Point(300, 174)
    $offline.Add_Click({ $dialog.Tag='Offline'; $dialog.Close() })
    $dialog.Controls.Add($offline)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText 'app.close'
    $close.Size = New-Object System.Drawing.Size(120, 38)
    $close.Location = New-Object System.Drawing.Point(484, 174)
    $close.Add_Click({ $dialog.Close() })
    $dialog.CancelButton = $close
    $dialog.AcceptButton = $retry
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Complete-SoftwareCatalogOnlineUpdate {
    Set-ButtonsEnabled $true
    $shouldScan = [bool]$script:softwareCatalogAutoScan
    $requestedScanScope = [string]$script:softwareCatalogAutoScanScope
    if ($requestedScanScope -notin @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
        $requestedScanScope = "ThirdParty"
    }
    $script:softwareCatalogAutoScan = $false
    $script:softwareCatalogAutoScanScope = "ThirdParty"
    $result = $null
    try {
        if (-not $script:softwareCatalogUpdateResultFile -or -not (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            throw (Get-DashboardText "software.online.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:softwareCatalogUpdateResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $result = [pscustomobject]@{ Success=$false; Error=[string]$_.Exception.Message; ErrorCode='Unknown'; CatalogVersion=''; ProductRuleCount=0; CachePath='' }
    } finally {
        if ($script:softwareCatalogUpdateResultFile -and (Test-Path -LiteralPath $script:softwareCatalogUpdateResultFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:softwareCatalogUpdateResultFile -Force -ErrorAction SilentlyContinue
        }
        $script:softwareCatalogUpdateResultFile = ""
    }

    if ([bool]$result.Success) {
        $status.Text = Get-DashboardText "software.online.successStatus" @($result.CatalogVersion, $result.ProductRuleCount)
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
        Write-ProgressLog (Get-DashboardText "software.online.successLog" @($result.CatalogVersion, $result.ProductRuleCount, $result.CachePath))
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "software.online.successMessage" @($result.CatalogVersion, $result.ProductRuleCount)),
            (Get-DashboardText "software.online.successTitle"), "OK", "Information") | Out-Null
        if ($shouldScan) { Start-Cleanup -ScanScope $requestedScanScope }
        return
    }

    $failureDetail = Get-SoftwareCatalogOnlineFailureDetail -Result $result
    $status.Text = Get-DashboardText "software.online.failedStatus"
    $status.ForeColor = [System.Drawing.Color]::DarkOrange
    Write-ProgressLog (Get-DashboardText "software.online.failedLog" @($failureDetail))
    $fallback = Show-SoftwareCatalogFailureDialog -Detail (Get-DashboardText "software.online.fallbackPrompt" @($failureDetail))
    if ($fallback -eq 'Retry') {
        Start-SoftwareCatalogOnlineUpdate -ScanScope $requestedScanScope -ConsentAlreadyGranted
    } elseif ($shouldScan -and $fallback -eq 'Offline') {
        Start-Cleanup -ScanScope $requestedScanScope
    }
}

function Get-ApplicationUpdateFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "").ToUpperInvariant() }
        finally { $algorithm.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Test-ApplicationSelfUpdateAllowed {
    # The EXE launcher creates this value from a compile-time marker.  Missing
    # or malformed values fail closed so extracted/source/dev payloads cannot
    # hand off to the public self-updater.
    return ([string]$env:TOOL_SECURE_LAUNCH -eq '1' -and [string]$env:TOOL_SELF_UPDATE_ALLOWED -eq '1')
}

function Remove-ApplicationUpdateResultFile {
    if ($script:applicationUpdateResultFile -and (Test-Path -LiteralPath $script:applicationUpdateResultFile -PathType Leaf)) {
        Remove-Item -LiteralPath $script:applicationUpdateResultFile -Force -ErrorAction SilentlyContinue
    }
    $script:applicationUpdateResultFile = ""
}

function Reset-ApplicationUpdateForOffline {
    $script:applicationUpdateCheckPending = $false
    $script:applicationUpdatePromptPending = $false
    $script:applicationUpdateReminderPending = $false
    $script:applicationUpdateReminderDueUtc = [DateTime]::MinValue
    $script:applicationUpdateTaskObservedAfterDeferral = $false
    $script:availableApplicationUpdate = $null
    $script:applicationUpdateCancelledForOffline = $false
    if ($script:applicationUpdateProcess) {
        $script:applicationUpdateCancelledForOffline = $true
        if (-not $script:applicationUpdateProcess.HasExited) {
            try { $script:applicationUpdateProcess.Kill() } catch {}
        }
    }
    Remove-ApplicationUpdateResultFile
    [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.DisabledOffline" -Message (Get-DashboardText "offline.enabledLog"))
}

function Request-ApplicationUpdateCheck {
    if (-not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession -or $script:applicationUpdateApplyStarted) {
        return
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) { return }
    $script:applicationUpdateCheckPending = $true
    Invoke-PendingApplicationUpdateWork
}

function Start-ApplicationUpdateCheck {
    if (-not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession -or $script:applicationUpdateApplyStarted) {
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdatePromptPending = $false
        $script:availableApplicationUpdate = $null
        return
    }
    try {
        $freshIntegrity = Test-ToolIntegrity
        if (-not $freshIntegrity.Valid) { throw $freshIntegrity.Message }
        $descriptor = Get-ReadyToolModule -moduleId "application.update.check" -elevatedLaunch $false
        $invocation = New-ToolModuleInvocation -ModuleId $descriptor.ModuleId
        $script:applicationUpdateResultFile = New-SecureRuntimePath "tool-application-update-check-"
        $currentLauncherSha256 = ""
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        if ([string]$env:TOOL_SECURE_LAUNCH -eq "1") {
            if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
                throw (Get-DashboardText "update.secureLauncherRequired")
            }
            $currentLauncherSha256 = Get-ApplicationUpdateFileSha256 $launcherPath
        }
        $currentHashArgument = if ($currentLauncherSha256) { " -ExpectedCurrentSha256 `"$currentLauncherSha256`"" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$applicationUpdateScript`" -Mode Check -ConsentGranted -Culture `"$script:dashboardCulture`" -CurrentVersion `"$releaseVersion`" -ResultFile `"$script:applicationUpdateResultFile`" -ManifestUrl `"$applicationUpdateManifestUrl`"$currentHashArgument"
        $previousModuleId = [string]$env:TOOL_MODULE_ID
        $previousInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
        try {
            $env:TOOL_MODULE_ID = $descriptor.ModuleId
            $env:TOOL_MODULE_INVOCATION_ID = $invocation.InvocationId
            $updateCheckStartParameters = @{
                FilePath = $toolPowerShellPath
                ArgumentList = $arguments
                WindowStyle = "Hidden"
                PassThru = $true
            }
            $process = Start-Process @updateCheckStartParameters
            if (-not $process) { throw (Get-DashboardText "module.processMissing") }
        } finally {
            $env:TOOL_MODULE_ID = $previousModuleId
            $env:TOOL_MODULE_INVOCATION_ID = $previousInvocationId
        }
        $script:applicationUpdateProcess = $process
        $script:applicationUpdateInvocation = $invocation
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdateCancelledForOffline = $false
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.running"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        }
        [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.CheckStarted" -Message (Get-DashboardText "update.check.checking") -Data ([ordered]@{
            CurrentVersion=$releaseVersion; ManifestHost="raw.githubusercontent.com"; OnlineConsent=$true
        }))
    } catch {
        $script:applicationUpdateCheckPending = $false
        $script:applicationUpdateProcess = $null
        $script:applicationUpdateInvocation = $null
        Remove-ApplicationUpdateResultFile
        $message = Get-DashboardText "update.check.startFailed" @($_.Exception.Message)
        if (-not $script:activeProcess) {
            $status.Text = $message
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.CheckStartFailed" -Message $message)
    }
}

function Complete-ApplicationUpdateCheck {
    if (-not $script:applicationUpdateProcess -or -not $script:applicationUpdateProcess.HasExited) { return }
    $exitCode = [int]$script:applicationUpdateProcess.ExitCode
    $invocation = $script:applicationUpdateInvocation
    $script:applicationUpdateProcess = $null
    $script:applicationUpdateInvocation = $null
    if ($invocation) {
        try {
            $moduleResult = Complete-ToolModuleInvocation -Invocation $invocation -ExitCode $exitCode -Summary (Get-DashboardText "update.check.action")
            $moduleValidation = Test-ToolModuleResult -Result $moduleResult
            if (-not $moduleValidation.Valid) {
                [void](Write-ToolLog -Level "ERROR" -Event "ApplicationUpdate.ModuleResultInvalid" -Message ($moduleValidation.Errors -join "; "))
            }
        } catch {
            [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.ModuleCompletionFailed" -Message $_.Exception.Message)
        }
    }

    $result = $null
    try {
        if (-not $script:applicationUpdateResultFile -or -not (Test-Path -LiteralPath $script:applicationUpdateResultFile -PathType Leaf)) {
            throw (Get-DashboardText "update.check.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:applicationUpdateResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $result = [pscustomobject]@{ Success=$false; Error=[string]$_.Exception.Message }
    } finally {
        Remove-ApplicationUpdateResultFile
    }

    if ($script:applicationUpdateCancelledForOffline -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0") {
        $script:applicationUpdateCancelledForOffline = $false
        return
    }
    if (-not [bool]$result.Success) {
        $errorText = if ($result.PSObject.Properties["Error"]) { [string]$result.Error } else { Get-DashboardText "common.unknown" }
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.failedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        [void](Write-ToolLog -Level "WARN" -Event "ApplicationUpdate.CheckFailed" -Message (Get-DashboardText "update.check.failedLog" @($errorText)) -Data ([ordered]@{ ExitCode=$exitCode }))
        return
    }

    if ([bool]$result.UpdateAvailable) {
        $script:availableApplicationUpdate = $result
        $script:applicationUpdatePromptPending = $true
        if (-not $script:activeProcess) {
            $status.Text = Get-DashboardText "update.check.availableStatus" @($result.LatestVersion)
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Available" -Message (Get-DashboardText "update.check.availableLog" @($result.LatestVersion)) -Data ([ordered]@{
            CurrentVersion=$result.CurrentVersion; LatestVersion=$result.LatestVersion; DownloadStarted=$false
        }))
        Invoke-PendingApplicationUpdateWork
        return
    }

    $script:availableApplicationUpdate = $null
    $script:applicationUpdatePromptPending = $false
    if (-not $script:activeProcess) {
        $status.Text = Get-DashboardText "update.check.latestStatus" @($result.CurrentVersion)
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Current" -Message (Get-DashboardText "update.check.latestLog" @($result.CurrentVersion)))
}

function Show-ApplicationUpdateDialog {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "update.dialog.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(750, 610)
    $dialog.MinimumSize = New-Object System.Drawing.Size(750, 610)
    $dialog.MaximumSize = New-Object System.Drawing.Size(750, 610)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.Tag = "Later"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "update.dialog.heading" @([string]$Candidate.Title, [string]$Candidate.LatestVersion)
    $heading.Font = $fontTitle
    $heading.Location = New-Object System.Drawing.Point(28, 24)
    $heading.Size = New-Object System.Drawing.Size(680, 46)
    $dialog.Controls.Add($heading)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = Get-DashboardText "update.dialog.version" @([string]$Candidate.CurrentVersion, [string]$Candidate.LatestVersion)
    $versionLabel.Font = $fontBold
    $versionLabel.Location = New-Object System.Drawing.Point(30, 76)
    $versionLabel.Size = New-Object System.Drawing.Size(670, 26)
    $dialog.Controls.Add($versionLabel)

    $publishedAt = [DateTime]::MinValue
    $publishedText = [string]$Candidate.PublishedAtUtc
    if ([DateTime]::TryParse([string]$Candidate.PublishedAtUtc, [ref]$publishedAt)) {
        $publishedText = $publishedAt.ToLocalTime().ToString("dd/MM/yyyy HH:mm")
    }
    $publishedLabel = New-Object System.Windows.Forms.Label
    $publishedLabel.Text = Get-DashboardText "update.dialog.published" @($publishedText)
    $publishedLabel.Location = New-Object System.Drawing.Point(30, 104)
    $publishedLabel.Size = New-Object System.Drawing.Size(670, 24)
    $dialog.Controls.Add($publishedLabel)

    $changesText = (@($Candidate.Changes | ForEach-Object { "• " + [string]$_ }) -join "`r`n")
    $changes = New-Object System.Windows.Forms.TextBox
    $changes.Multiline = $true
    $changes.ReadOnly = $true
    $changes.ScrollBars = "Vertical"
    $changes.WordWrap = $true
    $changes.Text = Get-DashboardText "update.dialog.changes" @($changesText)
    $changes.Font = $fontNormal
    $changes.Location = New-Object System.Drawing.Point(30, 136)
    $changes.Size = New-Object System.Drawing.Size(670, 230)
    $dialog.Controls.Add($changes)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = Get-DashboardText "update.dialog.privacy"
    $privacy.Location = New-Object System.Drawing.Point(30, 380)
    $privacy.Size = New-Object System.Drawing.Size(670, 88)
    $privacy.Font = $fontSmall
    $dialog.Controls.Add($privacy)

    $updateNowButton = New-Object System.Windows.Forms.Button
    $updateNowButton.Text = Get-DashboardText "update.choice.updateNow"
    $updateNowButton.Font = $fontBold
    $updateNowButton.Location = New-Object System.Drawing.Point(76, 494)
    $updateNowButton.Size = New-Object System.Drawing.Size(180, 42)
    $updateNowButton.Add_Click({ $dialog.Tag = "UpdateNow"; $dialog.Close() })
    $dialog.Controls.Add($updateNowButton)

    $laterButton = New-Object System.Windows.Forms.Button
    $laterButton.Text = Get-DashboardText "update.choice.remindLater"
    $laterButton.Location = New-Object System.Drawing.Point(274, 494)
    $laterButton.Size = New-Object System.Drawing.Size(180, 42)
    $laterButton.Add_Click({ $dialog.Tag = "Later"; $dialog.Close() })
    $dialog.Controls.Add($laterButton)

    $dismissButton = New-Object System.Windows.Forms.Button
    $dismissButton.Text = Get-DashboardText "update.choice.dismissSession"
    $dismissButton.Location = New-Object System.Drawing.Point(472, 494)
    $dismissButton.Size = New-Object System.Drawing.Size(180, 42)
    $dismissButton.Add_Click({ $dialog.Tag = "Dismiss"; $dialog.Close() })
    $dialog.Controls.Add($dismissButton)
    $dialog.AcceptButton = $updateNowButton
    $dialog.CancelButton = $laterButton

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    $palette = Get-ToolUiPalette -Mode $script:dashboardTheme
    $updateNowButton.BackColor = $palette.Primary
    $updateNowButton.ForeColor = if ($script:dashboardTheme -eq "Dark") { [System.Drawing.Color]::FromArgb(18, 26, 38) } else { [System.Drawing.Color]::White }
    foreach ($button in @($updateNowButton, $laterButton, $dismissButton)) {
        $button.FlatStyle = "Flat"
        $button.FlatAppearance.BorderSize = 0
        Set-ModernRoundedRegion -Control $button -Radius 9
    }
    $changes.SelectionStart = 0
    $changes.SelectionLength = 0
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Start-ApplicationUpdateApply {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    try {
        if (-not (Test-ApplicationSelfUpdateAllowed)) { throw (Get-DashboardText "update.selfUpdateUnavailable") }
        if ($script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0") { throw (Get-DashboardText "foundation.offline.actionBlocked" @((Get-DashboardText "update.check.action"))) }
        if (-not [bool]$Candidate.CanSelfUpdate) { throw (Get-DashboardText "update.selfUpdateUnavailable") }
        if ([string]$env:TOOL_SECURE_LAUNCH -ne "1") { throw (Get-DashboardText "update.secureLauncherRequired") }
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        $launcherProcessId = 0
        if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf) -or
            -not [int]::TryParse([string]$env:TOOL_LAUNCHER_PID, [ref]$launcherProcessId) -or $launcherProcessId -le 0) {
            throw (Get-DashboardText "update.secureLauncherRequired")
        }
        $freshIntegrity = Test-ToolIntegrity
        if (-not $freshIntegrity.Valid) { throw $freshIntegrity.Message }
        $currentLauncherSha256 = Get-ApplicationUpdateFileSha256 $launcherPath
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$applicationUpdateScript`" -Mode Apply -ConsentGranted -Culture `"$script:dashboardCulture`" -CurrentVersion `"$releaseVersion`" -ExpectedVersion `"$($Candidate.LatestVersion)`" -ManifestUrl `"$applicationUpdateManifestUrl`" -LauncherPath `"$launcherPath`" -LauncherProcessId $launcherProcessId -ExpectedCurrentSha256 `"$currentLauncherSha256`""
        # Do not call RunAs directly here.  The Windows RunAs broker may drop
        # the secure-launch variables; the bridge restores only the reviewed
        # environment and binds this request to Tool-UpdateManager.ps1.
        $updaterProcess = Start-DetachedToolModuleProcess -ModuleId "application.update.apply" -Arguments $arguments -Elevate -Hidden
        if (-not $updaterProcess) { throw (Get-DashboardText "module.processMissing") }
        $script:applicationUpdateApplyStarted = $true
        $script:applicationUpdatePromptPending = $false
        $script:applicationUpdateReminderPending = $false
        [void](Write-ToolLog -Level "AUDIT" -Event "ApplicationUpdate.Confirmed" -Message (Get-DashboardText "update.choice.updateNow") -Data ([ordered]@{
            CurrentVersion=$releaseVersion; TargetVersion=[string]$Candidate.LatestVersion; UpdaterProcessId=[int]$updaterProcess.Id
        }))
        $form.Close()
    } catch {
        $message = Get-DashboardText "update.apply.startFailed" @($_.Exception.Message)
        $status.Text = $message
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        [void](Write-ToolLog -Level "ERROR" -Event "ApplicationUpdate.ApplyStartFailed" -Message $message)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "update.apply.failedTitle"), "OK", "Error") | Out-Null
        $script:applicationUpdateReminderPending = $true
        $script:applicationUpdateReminderDueUtc = [DateTime]::UtcNow.AddMinutes(10)
        $script:applicationUpdateTaskObservedAfterDeferral = $false
    }
}

function Invoke-PendingApplicationUpdateWork {
    if ($script:applicationUpdateApplyStarted -or $script:applicationUpdateDialogVisible -or
        -not (Test-ApplicationSelfUpdateAllowed) -or $script:offlineMode -or [string]$env:TOOL_OFFLINE_MODE -ne "0" -or
        $script:applicationUpdateDismissedForSession) {
        return
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) { return }
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) { return }

    if ($script:applicationUpdateReminderPending -and $script:availableApplicationUpdate -and
        ($script:applicationUpdateTaskObservedAfterDeferral -or [DateTime]::UtcNow -ge $script:applicationUpdateReminderDueUtc)) {
        $script:applicationUpdateReminderPending = $false
        $script:applicationUpdatePromptPending = $true
    }
    if ($script:applicationUpdatePromptPending -and $script:availableApplicationUpdate) {
        $script:applicationUpdateDialogVisible = $true
        try {
            $choice = Show-ApplicationUpdateDialog -Candidate $script:availableApplicationUpdate
            $script:applicationUpdatePromptPending = $false
            if ($choice -eq "UpdateNow") {
                Start-ApplicationUpdateApply -Candidate $script:availableApplicationUpdate
            } elseif ($choice -eq "Dismiss") {
                $script:applicationUpdateDismissedForSession = $true
                $script:applicationUpdateReminderPending = $false
                $status.Text = Get-DashboardText "update.dismissed.status"
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.DismissedForSession" -Message $status.Text)
            } else {
                $script:applicationUpdateReminderPending = $true
                $script:applicationUpdateReminderDueUtc = [DateTime]::UtcNow.AddHours(2)
                $script:applicationUpdateTaskObservedAfterDeferral = $false
                $status.Text = Get-DashboardText "update.reminder.scheduled"
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                [void](Write-ToolLog -Level "INFO" -Event "ApplicationUpdate.Deferred" -Message $status.Text -Data ([ordered]@{ ReminderAfterHours=2; ReminderAfterNextTask=$true }))
            }
        } finally {
            $script:applicationUpdateDialogVisible = $false
        }
        return
    }
    if ($script:applicationUpdateCheckPending) { Start-ApplicationUpdateCheck }
}

function Get-AutomaticSafeCleanupItems {
    param($CleanupItems)

    # Third-party licensing actions are always manual-selection only.  The
    # automatic path is limited to the Windows registry allowlist below.
    return @($CleanupItems | Where-Object {
        $type = [string]$_.Type
        $kind = [string]$_.Kind
        $path = [string]$_.Location
        ($type -eq "Registry" -and (
            ($kind -eq "KmsOverride" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "KeyManagementServiceName")) -or
            ($kind -eq "SppNoGenTicketPolicy" -and (Test-ToolRegistryValueRestoreAllowed -Path $path -ValueName "NoGenTicket"))
        ))
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
    $message = Get-DashboardText "cleanup.auto.confirm" @($safeItems.Count, $preview)
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        (Get-DashboardText "cleanup.auto.title"),
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
    param(
        $CleanupItems,
        [ValidateSet("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")][string]$ScanScope = "All",
        [string[]]$SuggestedIds = @()
    )
    $items = @(Get-GuiScopedCleanupItems -CleanupItems $CleanupItems -Scope $ScanScope)
    if ($items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "cleanup.selection.none"),
            (Get-DashboardText "cleanup.selection.noneTitle"), "OK", "Information") | Out-Null
        return [pscustomobject]@{ Confirmed=$false; SelectedIds=@(); ScanScope=$ScanScope }
    }

    $chooser = New-Object System.Windows.Forms.Form
    $chooser.Text = Get-DashboardText "cleanup.selection.formTitle"
    $chooser.StartPosition = "CenterParent"
    $chooser.FormBorderStyle = "Sizable"
    $chooser.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(820, [Math]::Min(1280, $workArea.Width - 50))
    $dialogHeight = [Math]::Max(540, [Math]::Min(690, $workArea.Height - 70))
    $chooser.MinimumSize = New-Object System.Drawing.Size([Math]::Min(820, $dialogWidth), [Math]::Min(540, $dialogHeight))
    $chooser.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $chooser.Font = $fontNormal
    $chooser.Tag = [pscustomobject]@{ Confirmed=$false; SelectedIds=@(); ScanScope=$ScanScope }

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $(if ($ScanScope -eq "ThirdParty") { "cleanup.selection.heading.thirdParty" } elseif ($ScanScope -eq "WindowsOffice") { "cleanup.selection.heading.windowsOffice" } else { "cleanup.selection.heading" })
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Location = New-Object System.Drawing.Point(18, 10)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 36), 42)
    $heading.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText $(if ($ScanScope -eq "ThirdParty") { "cleanup.selection.hint.thirdParty" } elseif ($ScanScope -eq "WindowsOffice") { "cleanup.selection.hint.windowsOffice" } else { "cleanup.selection.hint" })
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.Location = New-Object System.Drawing.Point(22, 56)
    $hint.Size = New-Object System.Drawing.Size(($dialogWidth - 44), 50)
    $hint.Anchor = "Top,Left,Right"
    $chooser.Controls.Add($hint)

    $list = New-Object System.Windows.Forms.ListView
    $list.CheckBoxes = $true
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.ShowItemToolTips = $true
    $list.Location = New-Object System.Drawing.Point(22, 112)
    $list.Size = New-Object System.Drawing.Size(($dialogWidth - 44), ($dialogHeight - 184))
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add((Get-DashboardText "common.type"), 132)
    [void]$list.Columns.Add((Get-DashboardText "common.name"), 320)
    [void]$list.Columns.Add((Get-DashboardText "common.locationDetail"), 580)
    $resizeCleanupColumns = {
        $usable = [Math]::Max(540, $list.ClientSize.Width - 8)
        $list.Columns[0].Width = 132
        $list.Columns[1].Width = [Math]::Max(260, [Math]::Floor(($usable - 132) * 0.44))
        $list.Columns[2].Width = [Math]::Max(260, $usable - $list.Columns[0].Width - $list.Columns[1].Width)
    }
    $list.Add_Resize($resizeCleanupColumns)
    $typeLabels = @{
        Service=(Get-DashboardText "cleanup.type.service"); ScheduledTask=(Get-DashboardText "cleanup.type.task"); Folder=(Get-DashboardText "cleanup.type.folder"); Registry=(Get-DashboardText "cleanup.type.registry")
        File=(Get-DashboardText "cleanup.type.file"); Process=(Get-DashboardText "cleanup.type.process"); Defender=(Get-DashboardText "cleanup.type.defender"); License=(Get-DashboardText "cleanup.type.license"); Application=(Get-DashboardText "cleanup.type.application")
        Hosts=(Get-DashboardText "cleanup.type.hosts"); Repair=(Get-DashboardText "cleanup.type.repair"); Uninstall=(Get-DashboardText "cleanup.type.uninstall"); Guidance=(Get-DashboardText "cleanup.type.guidance")
    }
    foreach ($cleanupItem in $items) {
        $typeText = if ($typeLabels.ContainsKey([string]$cleanupItem.Type)) { $typeLabels[[string]$cleanupItem.Type] } else { [string]$cleanupItem.Type }
        $row = New-Object System.Windows.Forms.ListViewItem($typeText)
        [void]$row.SubItems.Add([string]$cleanupItem.Name)
        $locationText = [string]$cleanupItem.Location
        if (-not [string]::IsNullOrWhiteSpace([string]$cleanupItem.Detail)) { $locationText += " - " + [string]$cleanupItem.Detail }
        [void]$row.SubItems.Add($locationText)
        $row.Tag = [string]$cleanupItem.Id
        $row.ToolTipText = "$([string]$cleanupItem.Name)`r`n$locationText"
        $row.Checked = [bool]($cleanupItem.DefaultSelected -or ($SuggestedIds -contains [string]$cleanupItem.Id))
        [void]$list.Items.Add($row)
    }
    $chooser.Controls.Add($list)
    & $resizeCleanupColumns

    $buttonLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $buttonLayout.Location = New-Object System.Drawing.Point(22, ($dialogHeight - 60))
    $buttonLayout.Size = New-Object System.Drawing.Size(($dialogWidth - 44), 46)
    $buttonLayout.Anchor = "Bottom,Left,Right"
    $buttonLayout.ColumnCount = 2
    [void]$buttonLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$buttonLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $chooser.Controls.Add($buttonLayout)

    $leftButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $leftButtons.Dock = "Fill"
    $leftButtons.WrapContents = $false
    $buttonLayout.Controls.Add($leftButtons, 0, 0)
    $rightButtons = New-Object System.Windows.Forms.FlowLayoutPanel
    $rightButtons.Dock = "Fill"
    $rightButtons.FlowDirection = "RightToLeft"
    $rightButtons.WrapContents = $false
    $buttonLayout.Controls.Add($rightButtons, 1, 0)

    $allButton = New-Object System.Windows.Forms.Button
    $allButton.Text = Get-DashboardText "common.selectAll"
    $allButton.Size = New-Object System.Drawing.Size(142, 36)
    $allButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $true } })
    $leftButtons.Controls.Add($allButton)

    $noneButton = New-Object System.Windows.Forms.Button
    $noneButton.Text = Get-DashboardText "common.clearAll"
    $noneButton.Size = New-Object System.Drawing.Size(142, 36)
    $noneButton.Add_Click({ foreach ($row in $list.Items) { $row.Checked = $false } })
    $leftButtons.Controls.Add($noneButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "app.close"
    $cancelButton.Size = New-Object System.Drawing.Size(116, 36)
    $cancelButton.Add_Click({ $chooser.Close() })
    $chooser.CancelButton = $cancelButton
    $rightButtons.Controls.Add($cancelButton)

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = Get-DashboardText "common.continue"
    $applyButton.Font = $fontBold
    $applyButton.Size = New-Object System.Drawing.Size(132, 36)
    $applyButton.Add_Click({
        $selectedIds = @($list.CheckedItems | ForEach-Object { [string]$_.Tag })
        if ($selectedIds.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "cleanup.selection.required"),
                (Get-DashboardText "cleanup.selection.requiredTitle"), "OK", "Warning") | Out-Null
            return
        }
        $selectedObjects = @($items | Where-Object { $selectedIds -contains [string]$_.Id })
        $licenseCount = @($selectedObjects | Where-Object { $_.Type -eq "License" }).Count
        # Guidance-only application rows are deliberately counted separately:
        # the artifact warning must never imply that selecting a vendor repair
        # guide will quarantine or alter that application.
        $applicationCount = @($selectedObjects | Where-Object {
            [string]$_.Type -eq 'Application' -and
            -not ($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)
        }).Count
        $guidanceCount = @($selectedObjects | Where-Object {
            [string]$_.Type -eq 'Guidance' -or
            ($_.PSObject.Properties['GuidanceOnly'] -and [bool]$_.GuidanceOnly)
        }).Count
        $licenseWarning = if ($licenseCount -gt 0) { Get-DashboardText "cleanup.selection.licenseWarning" @($licenseCount) } else { "" }
        if ($applicationCount -gt 0) { $licenseWarning += Get-DashboardText "cleanup.selection.applicationWarning" @($applicationCount) }
        if ($guidanceCount -gt 0) { $licenseWarning += Get-DashboardText "cleanup.selection.guidanceWarning" @($guidanceCount) }
        $summary = Get-DashboardText "cleanup.selection.summary" @($selectedIds.Count, $list.Items.Count, $licenseWarning)
        $answer = [System.Windows.Forms.MessageBox]::Show($summary, (Get-DashboardText "cleanup.selection.finalTitle"), "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $chooser.Tag = [pscustomobject]@{ Confirmed=$true; SelectedIds=$selectedIds; ScanScope=$ScanScope }
            $chooser.Close()
        }
    })
    $rightButtons.Controls.Add($applyButton)

    Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
    [void]$chooser.ShowDialog($form)
    $result = $chooser.Tag
    $chooser.Dispose()
    return $result
}

function Start-CleanupDeep {
    param($CleanupItems, [switch]$AutomaticSafeMode, [string[]]$SuggestedIds = @())
    $scopedCleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems $CleanupItems -Scope $script:cleanupScanScope)
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "cleanup.deep.integrityAction"))) {
        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        return
    }
    $selection = if ($AutomaticSafeMode) {
        Confirm-AutomaticSafeCleanup -CleanupItems $scopedCleanupItems
    } else {
        Show-DeepCleanupSelection -CleanupItems $scopedCleanupItems -ScanScope $script:cleanupScanScope -SuggestedIds $SuggestedIds
    }
    if (-not [bool]$selection.Confirmed) {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        Set-ButtonsEnabled $true
        $status.Text = if ($AutomaticSafeMode) { Get-DashboardText "cleanup.auto.cancelled" } else { Get-DashboardText "cleanup.deep.cancelled" }
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog $status.Text
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "cleanup.deep.action") (Get-DashboardText "cleanup.deep.preparing") $true
        $selectionMode = if ($AutomaticSafeMode) { Get-DashboardText "cleanup.mode.automatic" } else { Get-DashboardText "cleanup.mode.manual" }
        Write-ProgressLog (Get-DashboardText "cleanup.deep.selected" @(@($selection.SelectedIds).Count, $selectionMode))
        Write-ProgressLog (Get-DashboardText "cleanup.deep.scopeNote")
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-XuLy"
        $script:cleanupResultFile = New-SecureRuntimePath "tool-license-deep-clean-result-"
        $script:cleanupSelectionFile = New-SecureRuntimePath "tool-license-deep-selection-"
        [pscustomobject][ordered]@{
            SchemaVersion='1.0'
            RequestId=[guid]::NewGuid().ToString('D')
            CreatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
            SelectedIds=@($selection.SelectedIds)
            ScanScope=$script:cleanupScanScope
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:cleanupSelectionFile -Encoding UTF8
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $dryRunArgument = if ($script:cleanupDryRunMode) { " -DryRun" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -Remediate -DeepClean$dryRunArgument -ApprovedKmsServerFile `"$approvedKmsFile`" -TreatUnapprovedKmsAsNonCompliant -DecisionFile `"$script:cleanupResultFile`" -SelectionFile `"$script:cleanupSelectionFile`" -ScanScope `"$script:cleanupScanScope`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        $actionText = if ($script:cleanupDryRunMode) { Get-DashboardText 'cleanup.dryRun.action' } else { Get-DashboardText "cleanup.deep.action" }
        [void](Start-ToolModuleProcess -ModuleId "cleanup.deep" -Arguments $arguments -Action $actionText -Elevate)
        $status.Text = if ($script:cleanupDryRunMode) { Get-DashboardText 'cleanup.dryRun.running' } else { Get-DashboardText "cleanup.deep.running" }
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        $script:cleanupAutoSafeMode = $false
        $script:cleanupDryRunMode = $false
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "cleanup.deep.elevationCancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog (Get-DashboardText "cleanup.deep.notStarted")
        Stop-ProgressDisplay $status.Text
    }
}

function Show-ScanWarningRecoveryDialog {
    param($Scan)
    $warningLines = @($Scan.ScanWarnings | ForEach-Object { "- $_" })
    $warningText = if ($warningLines.Count -gt 0) { $warningLines -join "`r`n" } else { Get-DashboardText "scanWarning.noDetail" }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "scanWarning.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.MinimumSize = New-Object System.Drawing.Size(700, 430)
    $dialog.ClientSize = New-Object System.Drawing.Size(760, 460)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = "Close"

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "scanWarning.heading"
    $heading.Font = $fontBold
    $heading.ForeColor = [System.Drawing.Color]::DarkRed
    $heading.Location = New-Object System.Drawing.Point(18, 14)
    $heading.Size = New-Object System.Drawing.Size(706, 28)
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = Get-DashboardText "scanWarning.intro"
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
    $repairButton.Text = Get-DashboardText "scanWarning.repair"
    $repairButton.Font = $fontBold
    $repairButton.Location = New-Object System.Drawing.Point(274, 368)
    $repairButton.Size = New-Object System.Drawing.Size(200, 38)
    $repairButton.Anchor = "Bottom,Right"
    $repairButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
    $repairButton.Add_Click({ $dialog.Tag = "Repair"; $dialog.Close() })
    $dialog.Controls.Add($repairButton)

    $retryButton = New-Object System.Windows.Forms.Button
    $retryButton.Text = Get-DashboardText "common.rescan"
    $retryButton.Location = New-Object System.Drawing.Point(484, 368)
    $retryButton.Size = New-Object System.Drawing.Size(120, 38)
    $retryButton.Anchor = "Bottom,Right"
    $retryButton.Add_Click({ $dialog.Tag = "Retry"; $dialog.Close() })
    $dialog.Controls.Add($retryButton)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText "common.close"
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
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "scanRepair.integrityAction"))) { Set-ButtonsEnabled $true; return }
    try {
        Start-ProgressDisplay (Get-DashboardText "scanRepair.action") (Get-DashboardText "scanRepair.detail") $true
        Write-ProgressLog (Get-DashboardText "scanRepair.requestAdmin")
        $output = New-ToolReportRunDirectory -Category "KhacPhuc-NguonQuet"
        $script:cleanupRepairDecisionFile = New-SecureRuntimePath "tool-scan-source-repair-"
        $privacyArgument = if ($script:cleanupRedactSensitive) { " -RedactSensitive" } else { "" }
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupScript`" -OutputDir `"$output`" -RepairScanSources -DecisionFile `"$script:cleanupRepairDecisionFile`" -Culture `"$script:dashboardCulture`"$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "cleanup.repair" -Arguments $arguments -Action (Get-DashboardText "scanRepair.action") -Elevate)
        $status.Text = Get-DashboardText "scanRepair.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "scanRepair.startFailed" @($_.Exception.Message))
    }
}

function Complete-ScanSourceRepair {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupRepairDecisionFile -PathType Leaf)) {
            throw (Get-DashboardText "scanRepair.resultMissing")
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
        $resultLabel = if ([bool]$result.RecheckPassed) { Get-DashboardText "common.pass" } else { Get-DashboardText "common.fail" }
        $message = Get-DashboardText "scanRepair.resultSummary" @($resultLabel, ($checkLines -join "`r`n"), ($guidanceLines -join "`r`n"), $result.ReportPath)
        if ([bool]$result.RecheckPassed) {
            $answer = [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "scanRepair.retryPrompt" @($message)), (Get-DashboardText "scanRepair.readyTitle"), "YesNo", "Information")
            $status.Text = Get-DashboardText "scanRepair.readyStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
            Write-ProgressLog (Get-DashboardText "scanRepair.passLog")
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Cleanup -ReuseSessionSettings }
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "scanRepair.errorTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "scanRepair.errorStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "scanRepair.errorLog")
        }
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        $status.Text = Get-DashboardText "scanRepair.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Test-GuiThirdPartyCleanupFinding {
    param($Application)
    if (-not $Application) { return $false }
    if ($Application.PSObject.Properties['CleanupFinding']) { return [bool]$Application.CleanupFinding }
    return [bool]([string]$Application.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised'))
}

function Test-GuiSystemComponent {
    param($Application)

    # The final assessment owns this classification.  Do not infer it from a
    # product being free, paid, a runtime, its publisher, or its name: that
    # would put user applications such as PC-NVR in the wrong view.
    return [bool]($Application -and $Application.PSObject.Properties['IsSystemComponent'] -and
        [bool]$Application.IsSystemComponent)
}

function Test-GuiThirdPartyDirectRemediationEvidence {
    param($Application)

    if (-not (Test-GuiThirdPartyCleanupFinding -Application $Application)) { return $false }
    if (-not $Application.PSObject.Properties['CleanupCandidateId'] -or
        -not $Application.PSObject.Properties['RemediationSupported']) { return $false }
    $hasCandidate = [bool](-not [string]::IsNullOrWhiteSpace([string]$Application.CleanupCandidateId) -and
        [bool]$Application.RemediationSupported)
    if (-not $hasCandidate) { return $false }
    if ($Application.PSObject.Properties['StandaloneArtifact'] -and [bool]$Application.StandaloneArtifact) {
        return [bool]($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed -and
            $Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
    }
    $manualArtifactQuarantine = [bool](
        $Application.PSObject.Properties['ManualArtifactQuarantineAllowed'] -and [bool]$Application.ManualArtifactQuarantineAllowed -and
        $Application.PSObject.Properties['CleanupManualArtifactQuarantineOnly'] -and [bool]$Application.CleanupManualArtifactQuarantineOnly -and
        $Application.PSObject.Properties['AssessmentCode'] -and [string]$Application.AssessmentCode -eq 'Suspicious' -and
        $Application.PSObject.Properties['LicenseTechnicalState'] -and [string]$Application.LicenseTechnicalState -eq 'Suspicious'
    )
    if ($manualArtifactQuarantine) {
        # The candidate builder has already bound this exact file to a path,
        # SHA-256 and length.  The final picker still asks the user to confirm;
        # this is not an automatic cleanup permission.
        return [bool]($Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
    }
    if (-not ($Application.PSObject.Properties['LicenseTechnicalState'] -and [string]$Application.LicenseTechnicalState -eq 'CrackConfirmed')) { return $false }
    if (-not ($Application.PSObject.Properties['ArtifactCleanupAllowed'] -and [bool]$Application.ArtifactCleanupAllowed)) { return $false }
    return [bool]($Application.PSObject.Properties['CleanupArtifactCleanupAllowed'] -and [bool]$Application.CleanupArtifactCleanupAllowed)
}

function Test-GuiThirdPartySelectionAllowed {
    param($Application)

    if (Test-GuiThirdPartyDirectRemediationEvidence -Application $Application) { return $true }
    if (-not (Test-GuiThirdPartyCleanupFinding -Application $Application)) { return $false }
    if (-not ($Application.PSObject.Properties['CleanupCandidateId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Application.CleanupCandidateId))) { return $false }
    # Guidance selection is expressly not remediation permission.  The
    # backend accepts only a Guidance item for it and leaves the application,
    # licence store, services, tasks and registry untouched.
    return [bool](
        $Application.PSObject.Properties['GuidedRemediationSupported'] -and [bool]$Application.GuidedRemediationSupported -and
        $Application.PSObject.Properties['CleanupGuidanceOnly'] -and [bool]$Application.CleanupGuidanceOnly
    )
}

function Get-GuiThirdPartyCleanupFindings {
    param($Applications)
    return @($Applications | Where-Object { Test-GuiThirdPartyCleanupFinding -Application $_ })
}

function Get-GuiThirdPartyStandaloneCleanupRows {
    param($Candidates)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates | Where-Object {
        @($_.ApplicationIds).Count -eq 0 -and
        @($_.PlanItems | Where-Object { [string]$_.Type -eq 'File' -and [string]$_.Kind -eq 'ThirdPartyUnauthorizedArtifact' }).Count -gt 0
    })) {
        $rows.Add([pscustomobject][ordered]@{
            Id=('standalone:' + [string]$candidate.Id); Name=[string]$candidate.Name; Version=''; Publisher=''
            LicenseModel='Unknown'; AssessmentCode='Suspicious'; TechnicalStatus=(Get-DashboardText 'report.software.status.suspicious')
            Confidence='Medium'; Evidence=@($candidate.Evidence); NeedsReview=$true; CleanupFinding=$true
            IsSystemComponent=$false; SystemComponentReason=''
            RemediationSupported=$true; CleanupCandidateId=[string]$candidate.Id
            CleanupRemediationMode=[string]$candidate.RemediationMode; OfficialReferenceUrl=''
            StandaloneArtifact=$true; LicenseTechnicalState='ArtifactConfirmed'
            ArtifactCleanupAllowed=[bool]$candidate.ArtifactCleanupAllowed
            CleanupArtifactCleanupAllowed=[bool]$candidate.ArtifactCleanupAllowed
            CleanupLicenseStateResetAllowed=[bool]$candidate.LicenseStateResetAllowed
            RecoveryMode=[string]$candidate.RecoveryMode
        })
    }
    return $rows.ToArray()
}

function Get-GuiScanIntegerProperty {
    param($Scan, [string]$Name, [int]$Default = 0)

    if (-not $Scan -or -not $Scan.PSObject.Properties[$Name]) { return $Default }
    $value = 0
    if ([int]::TryParse([string]$Scan.PSObject.Properties[$Name].Value, [ref]$value)) { return $value }
    return $Default
}

function Get-GuiCleanupComponentLicenseState {
    param(
        $Scan,
        [ValidateSet('Windows','Office')][string]$Component
    )

    if (-not $Scan -or -not $Scan.PSObject.Properties['OfficialLicensePostCheck']) { return 'Unverified' }
    $postCheck = $Scan.PSObject.Properties['OfficialLicensePostCheck'].Value
    if (-not $postCheck -or -not $postCheck.PSObject.Properties[$Component]) { return 'Unverified' }
    $componentResult = $postCheck.PSObject.Properties[$Component].Value
    if ($componentResult -and $componentResult.PSObject.Properties['StateCode'] -and
        -not [string]::IsNullOrWhiteSpace([string]$componentResult.StateCode)) {
        return [string]$componentResult.StateCode
    }
    return 'Unverified'
}

function Get-GuiCleanupLicenseStateLabel {
    param([string]$StateCode)

    $key = switch ($StateCode) {
        'Licensed' { 'cleanup.scan.state.licensed' }
        'Unactivated' { 'cleanup.scan.state.unactivated' }
        'NeedsRepair' { 'cleanup.scan.state.needsRepair' }
        'NotDetected' { 'cleanup.scan.state.notDetected' }
        'NotScanned' { 'cleanup.scan.state.notScanned' }
        'CrackEvidencePresent' { 'cleanup.scan.state.crackEvidence' }
        'ActivationRequired' { 'cleanup.scan.state.activationRequired' }
        default { 'cleanup.scan.state.unverified' }
    }
    return Get-DashboardText $key
}

function Get-GuiCleanupComponentStatusLines {
    param(
        $Scan,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')][string]$Scope
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'Windows') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.windows' @(
            (Get-GuiCleanupLicenseStateLabel (Get-GuiCleanupComponentLicenseState -Scan $Scan -Component 'Windows')),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'WindowsKmsCount'))))
    }
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'Office') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.office' @(
            (Get-GuiCleanupLicenseStateLabel (Get-GuiCleanupComponentLicenseState -Scan $Scan -Component 'Office')),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'OfficeKmsCount'))))
    }
    if (Test-GuiCleanupScopeIncludes -Scope $Scope -Component 'ThirdParty') {
        $lines.Add((Get-DashboardText 'cleanup.scan.component.thirdParty' @(
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'ThirdPartyApplicationCount'),
            (Get-GuiScanIntegerProperty -Scan $Scan -Name 'ThirdPartyRemediationFindingCount'))))
    }
    if ($lines.Count -eq 0) { $lines.Add((Get-DashboardText 'cleanup.scan.component.none')) }
    return $lines.ToArray()
}

function Get-GuiCleanupNoFindingMessage {
    param(
        $Scan,
        [ValidateSet('All','Windows','Office','ThirdParty','WindowsOffice','WindowsThirdParty','OfficeThirdParty')][string]$Scope
    )

    $conclusion = if ($Scan -and $Scan.PSObject.Properties['CleanupConclusion'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Scan.CleanupConclusion)) {
        [string]$Scan.CleanupConclusion
    } else {
        Get-DashboardText 'common.unknown'
    }
    return Get-DashboardText 'cleanup.scan.noFindingResult' @(
        (Get-CleanupScopeLabel -Scope $Scope),
        (@(Get-GuiCleanupComponentStatusLines -Scan $Scan -Scope $Scope) -join "`r`n"),
        (Get-GuiScanIntegerProperty -Scan $Scan -Name 'HistoryFindingCount'),
        $conclusion)
}

function Show-ThirdPartyAssessmentResults {
    param(
        $Scan,
        [switch]$ReadOnly,
        [string[]]$Warnings = @()
    )

    $inventoryApplications = @($Scan.ThirdPartyApplications)
    $standaloneRows = @(Get-GuiThirdPartyStandaloneCleanupRows -Candidates @($Scan.ThirdPartyCandidates))
    $allApplications = @($inventoryApplications) + @($standaloneRows)
    $sortProperties = @(
        @{ Expression = { if (Test-GuiThirdPartyDirectRemediationEvidence -Application $_) { 0 } elseif (Test-GuiThirdPartySelectionAllowed -Application $_) { 1 } else { 2 } }; Ascending = $true }
        @{ Expression = { [string]$_.Name }; Ascending = $true }
        @{ Expression = { [string]$_.Publisher }; Ascending = $true }
    )
    $applications = @($allApplications | Sort-Object -Property $sortProperties)
    # Do not treat free software as a system component.  The final assessment's
    # IsSystemComponent field is the only source of truth for this split.
    $thirdPartyApplications = @($applications | Where-Object { -not (Test-GuiSystemComponent -Application $_) })
    $systemApplications = @($applications | Where-Object { Test-GuiSystemComponent -Application $_ })
    $actionableCount = @($thirdPartyApplications | Where-Object { Test-GuiThirdPartyDirectRemediationEvidence -Application $_ }).Count
    $selectableCount = @($thirdPartyApplications | Where-Object { Test-GuiThirdPartySelectionAllowed -Application $_ }).Count

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "software.results.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "Sizable"
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.MaximizeBox = $true
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(660, [Math]::Min(1460, $workArea.Width - 36))
    $dialogHeight = [Math]::Max(560, [Math]::Min(820, $workArea.Height - 54))
    $dialog.MinimumSize = New-Object System.Drawing.Size(660, 560)
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = [pscustomobject]@{ Proceed=$false; SelectedCandidateIds=@() }

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = "Fill"
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding(18)
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 6
    [void]$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($mainLayout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $(if ($ReadOnly) { "software.results.heading.readOnly" } else { "software.results.heading" })
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.AutoSize = $true
    $heading.TextAlign = "MiddleCenter"
    $heading.Dock = "Top"
    $mainLayout.Controls.Add($heading, 0, 0)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Text = Get-DashboardText "software.results.summary" @(
        $allApplications.Count,
        $selectableCount,
        $actionableCount,
        @($allApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count,
        @($allApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count,
        @($allApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count)
    $summary.Font = $fontBold
    $summary.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $summary.AutoSize = $true
    $summary.Dock = "Top"
    $mainLayout.Controls.Add($summary, 0, 1)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText $(if ($ReadOnly) { "software.results.hint.readOnly" } elseif ($allApplications.Count -eq 0) { "software.results.noApplications" } else { "software.results.hint" })
    if ($ReadOnly -and @($Warnings).Count -gt 0) {
        $hint.Text = (Get-DashboardText 'software.results.hint.scanWarning' @((@($Warnings | Select-Object -First 3) -join '; '))) + "`r`n" + $hint.Text
    }
    if ($Scan.PSObject.Properties['DeepSoftwareScanEnabled'] -and [bool]$Scan.DeepSoftwareScanEnabled) {
        $deepCompleteText = Get-DashboardText $(if ([bool]$Scan.DeepSoftwareScanComplete) { 'common.yes' } else { 'common.no' })
        $hint.Text = (Get-DashboardText "software.results.deepSummary" @(
            $deepCompleteText,
            [int]$Scan.DeepSoftwareScanApplicationsScanned,
            [int]$Scan.DeepSoftwareScanRelevantFiles,
            [int]$Scan.DeepSoftwareScanSignatureChecks,
            [int]$Scan.DeepSoftwareScanHashChecks,
            [int]$Scan.DeepSoftwareScanAccessWarningCount)) + "`r`n" + $hint.Text
    }
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.AutoSize = $true
    $hint.Dock = "Top"
    $mainLayout.Controls.Add($hint, 0, 2)

    $details = New-Object System.Windows.Forms.RichTextBox
    $details.Dock = "Fill"
    $details.ReadOnly = $true
    $details.DetectUrls = $false
    $details.WordWrap = $true
    $details.ScrollBars = "ForcedVertical"
    $details.BackColor = [System.Drawing.Color]::White
    $details.ForeColor = [System.Drawing.Color]::FromArgb(35, 45, 62)
    $details.Font = $fontNormal
    $details.Text = Get-DashboardText 'software.results.detail.selectRow'
    $mainLayout.Controls.Add($details, 0, 4)

    $licenseLabels = @{
        Free=(Get-DashboardText "software.license.free"); OpenSource=(Get-DashboardText "software.license.openSource")
        Freeware=(Get-DashboardText "software.license.freeware"); Freemium=(Get-DashboardText "software.license.freemium")
        Paid=(Get-DashboardText "software.license.paid"); Subscription=(Get-DashboardText "software.license.subscription")
        Perpetual=(Get-DashboardText "software.license.perpetual"); Trialware=(Get-DashboardText "software.license.trialware")
        SystemComponent=(Get-DashboardText "software.license.systemComponent"); Driver=(Get-DashboardText "software.license.driver")
        Runtime=(Get-DashboardText "software.license.runtime"); Unknown=(Get-DashboardText "software.license.unknown")
    }
    $confidenceLabels = @{
        High=(Get-DashboardText "software.confidence.high"); Medium=(Get-DashboardText "software.confidence.medium"); Low=(Get-DashboardText "software.confidence.low")
    }

    $resizeListColumns = {
        param($Target)
        if ($null -eq $Target -or $Target.Columns.Count -lt 6) { return }
        $availableWidth = [Math]::Max(280, [int]$Target.ClientSize.Width - 8)
        $Target.BeginUpdate()
        try {
            if ($availableWidth -lt 860) {
                # At narrow widths, keep just identity, version and status. All
                # hidden values remain visible in the word-wrapped detail pane.
                $applicationWidth = [Math]::Max(170, [int][Math]::Floor($availableWidth * 0.48))
                $versionWidth = [Math]::Max(80, [int][Math]::Floor($availableWidth * 0.16))
                $statusWidth = [Math]::Max(1, $availableWidth - $applicationWidth - $versionWidth)
                $widths = @($applicationWidth, $versionWidth, 0, 0, $statusWidth, 0)
            } else {
                $applicationWidth = [Math]::Max(190, [int][Math]::Floor($availableWidth * 0.25))
                $versionWidth = [Math]::Max(75, [int][Math]::Floor($availableWidth * 0.11))
                $publisherWidth = [Math]::Max(110, [int][Math]::Floor($availableWidth * 0.18))
                $modelWidth = [Math]::Max(80, [int][Math]::Floor($availableWidth * 0.13))
                $statusWidth = [Math]::Max(130, [int][Math]::Floor($availableWidth * 0.18))
                $confidenceWidth = [Math]::Max(1, $availableWidth - $applicationWidth - $versionWidth - $publisherWidth - $modelWidth - $statusWidth)
                $widths = @($applicationWidth, $versionWidth, $publisherWidth, $modelWidth, $statusWidth, $confidenceWidth)
            }
            for ($columnIndex = 0; $columnIndex -lt $widths.Count; $columnIndex++) {
                $Target.Columns[$columnIndex].Width = [int]$widths[$columnIndex]
            }
        } finally {
            $Target.EndUpdate()
        }
    }

    $renderSelectionDetails = {
        param($SourceList)
        if ($null -eq $SourceList -or $SourceList.SelectedItems.Count -eq 0) {
            $details.Text = Get-DashboardText 'software.results.detail.selectRow'
            return
        }
        $metadata = $SourceList.SelectedItems[0].Tag
        $application = $metadata.Application
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add((Get-DashboardText 'software.results.column.application') + ': ' + [string]$application.Name)
        $lines.Add((Get-DashboardText 'software.results.column.version') + ': ' + [string]$application.Version)
        $lines.Add((Get-DashboardText 'software.results.column.publisher') + ': ' + [string]$application.Publisher)
        $lines.Add((Get-DashboardText 'software.results.column.model') + ': ' + [string]$metadata.LicenseText)
        $lines.Add((Get-DashboardText 'software.results.column.status') + ': ' + [string]$application.TechnicalStatus)
        $lines.Add((Get-DashboardText 'software.results.column.confidence') + ': ' + [string]$metadata.ConfidenceText)
        if ([bool]$metadata.IsSystemComponent) {
            $lines.Add('')
            $lines.Add((Get-DashboardText 'software.results.detail.systemReadOnly'))
        }
        $lines.Add('')
        $lines.Add((Get-DashboardText 'software.results.detail.evidence'))
        $lines.Add([string]$metadata.EvidenceText)
        $lines.Add('')
        $lines.Add((Get-DashboardText 'software.results.detail.action'))
        $lines.Add([string]$metadata.ActionText)
        $details.Text = $lines -join "`r`n"
        $details.SelectionStart = 0
        $details.SelectionLength = 0
        $details.ScrollToCaret()
    }

    $newApplicationList = {
        param(
            [object[]]$Rows = @(),
            [bool]$IsSystemView = $false
        )

        $list = New-Object System.Windows.Forms.ListView
        $list.CheckBoxes = [bool](-not $ReadOnly -and -not $IsSystemView)
        $list.View = [System.Windows.Forms.View]::Details
        $list.FullRowSelect = $true
        $list.GridLines = $true
        $list.HideSelection = $false
        $list.ShowItemToolTips = $true
        $list.MultiSelect = $true
        $list.Dock = "Fill"
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.application"), 220)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.version"), 92)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.publisher"), 152)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.model"), 110)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.status"), 152)
        [void]$list.Columns.Add((Get-DashboardText "software.results.column.confidence"), 96)

        foreach ($application in @($Rows)) {
            $candidateId = if ($application.PSObject.Properties['CleanupCandidateId']) { [string]$application.CleanupCandidateId } else { '' }
            $actionable = if ($IsSystemView) { $false } else { Test-GuiThirdPartyDirectRemediationEvidence -Application $application }
            $selectionAllowed = if ($IsSystemView) { $false } else { Test-GuiThirdPartySelectionAllowed -Application $application }
            $guidanceOnly = [bool]($selectionAllowed -and -not $actionable)
            $evidenceText = @($application.Evidence | ForEach-Object {
                $detail = if ($_.PSObject.Properties['Location'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Location)) { [string]$_.Location } else { [string]$_.Detail }
                if ([string]::IsNullOrWhiteSpace($detail)) { [string]$_.Code } else { "$([string]$_.Code): $detail" }
            }) -join '; '
            if ([string]::IsNullOrWhiteSpace($evidenceText)) { $evidenceText = Get-DashboardText "software.results.noEvidence" }
            $remediationMode = if ($application.PSObject.Properties['CleanupRemediationMode']) { [string]$application.CleanupRemediationMode } else { '' }
            $actionText = if ($IsSystemView) {
                Get-DashboardText 'software.results.detail.systemReadOnly'
            } elseif ($actionable) {
                $actionDetail = switch ($remediationMode) {
                    'VendorSharedReset' { Get-DashboardText "software.results.action.resetSupported" }
                    'ArtifactCleanupOnly' { Get-DashboardText "software.results.action.artifactCleanupOnly" }
                    'ArtifactCleanup' { Get-DashboardText "software.results.action.artifactCleanup" }
                    'ManualArtifactQuarantine' { Get-DashboardText "software.results.action.manualArtifactQuarantine" }
                    'ManualOfficialReinstall' { Get-DashboardText "software.results.action.manualReinstall" }
                    default { Get-DashboardText "software.results.action.guidedRepair" }
                }
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.actionable'), $actionDetail)
            } elseif ($guidanceOnly) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.actionable'),
                    (Get-DashboardText 'software.results.action.guidedOnly'))
            } elseif (Test-GuiThirdPartyCleanupFinding -Application $application) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.manualReview'),
                    (Get-DashboardText "software.results.action.officialRepair"))
            } elseif (($application.PSObject.Properties['NeedsReview'] -and [bool]$application.NeedsReview) -or
                [string]$application.AssessmentCode -in @('Unverified','TrialOrUnverified','IntegrityCompromised')) {
                Get-DashboardText 'software.results.action.classified' @(
                    (Get-DashboardText 'software.results.classification.manualReview'),
                    (Get-DashboardText 'software.results.action.manualReview'))
            } else {
                Get-DashboardText "software.results.action.none"
            }
            $licenseModel = [string]$application.LicenseModel
            if (-not $licenseLabels.ContainsKey($licenseModel)) { $licenseModel = 'Unknown' }
            $confidence = [string]$application.Confidence
            if (-not $confidenceLabels.ContainsKey($confidence)) { $confidence = 'Low' }
            $licenseText = [string]$licenseLabels[$licenseModel]
            $confidenceText = [string]$confidenceLabels[$confidence]
            $row = New-Object System.Windows.Forms.ListViewItem([string]$application.Name)
            [void]$row.SubItems.Add([string]$application.Version)
            [void]$row.SubItems.Add([string]$application.Publisher)
            [void]$row.SubItems.Add($licenseText)
            [void]$row.SubItems.Add([string]$application.TechnicalStatus)
            [void]$row.SubItems.Add($confidenceText)
            $row.Tag = [pscustomobject]@{
                Application=$application; CandidateId=$candidateId; Actionable=$actionable; SelectionAllowed=$selectionAllowed
                GuidanceOnly=$guidanceOnly; IsSystemComponent=$IsSystemView; EvidenceText=$evidenceText; ActionText=$actionText
                LicenseText=$licenseText; ConfidenceText=$confidenceText
            }
            $row.ToolTipText = "$([string]$application.Name)`r`n$([string]$application.TechnicalStatus)`r`n$evidenceText`r`n$actionText"
            if (-not $selectionAllowed) { $row.ForeColor = [System.Drawing.Color]::FromArgb(105, 112, 125) }
            [void]$list.Items.Add($row)
        }
        $list.Add_ItemCheck({
            param($sender, $eventArgs)
            if ($eventArgs.Index -lt 0 -or $eventArgs.Index -ge $sender.Items.Count) { return }
            $metadata = $sender.Items[$eventArgs.Index].Tag
            if (-not [bool]$metadata.SelectionAllowed) { $eventArgs.NewValue = [System.Windows.Forms.CheckState]::Unchecked }
        })
        $list.Add_SelectedIndexChanged({ param($sender, $eventArgs) & $renderSelectionDetails $sender })
        $list.Add_SizeChanged({ param($sender, $eventArgs) & $resizeListColumns $sender })
        & $resizeListColumns $list
        return $list
    }

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Multiline = $true
    $thirdPartyPage = New-Object System.Windows.Forms.TabPage
    $thirdPartyPage.Text = Get-DashboardText 'software.results.tab.thirdParty' @($thirdPartyApplications.Count)
    $systemPage = New-Object System.Windows.Forms.TabPage
    $systemPage.Text = Get-DashboardText 'software.results.tab.system' @($systemApplications.Count)
    $thirdPartyList = & $newApplicationList -Rows $thirdPartyApplications -IsSystemView $false
    $systemList = & $newApplicationList -Rows $systemApplications -IsSystemView $true
    $thirdPartyPage.Controls.Add($thirdPartyList)
    $systemPage.Controls.Add($systemList)
    $thirdPartyPage.Tag = $thirdPartyList
    $systemPage.Tag = $systemList
    [void]$tabControl.TabPages.Add($thirdPartyPage)
    [void]$tabControl.TabPages.Add($systemPage)
    $tabControl.Add_SelectedIndexChanged({
        param($sender, $eventArgs)
        $selectedList = if ($sender.SelectedTab -and $sender.SelectedTab.Tag) { $sender.SelectedTab.Tag } else { $null }
        & $renderSelectionDetails $selectedList
    })
    $mainLayout.Controls.Add($tabControl, 0, 3)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Top"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $true
    $footer.AutoScroll = $false
    $footer.AutoSize = $true
    $footer.AutoSizeMode = "GrowAndShrink"
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $mainLayout.Controls.Add($footer, 0, 5)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-DashboardText "app.close"
    $closeButton.Size = New-Object System.Drawing.Size(116, 38)
    $closeButton.Add_Click({ $dialog.Close() })
    $dialog.CancelButton = $closeButton
    $footer.Controls.Add($closeButton)

    if (-not $ReadOnly -and $selectableCount -gt 0) {
        $continueButton = New-Object System.Windows.Forms.Button
        $continueButton.Text = Get-DashboardText "software.results.continueCleanup"
        $continueButton.Font = $fontBold
        $continueButton.Size = New-Object System.Drawing.Size(210, 38)
        $continueButton.Add_Click({
            $candidateIds = @($thirdPartyList.CheckedItems | ForEach-Object { [string]$_.Tag.CandidateId } | Where-Object { $_ } | Select-Object -Unique)
            if ($candidateIds.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.selectionRequired"), (Get-DashboardText "software.results.selectionRequiredTitle"), "OK", "Warning") | Out-Null
                return
            }
            $warning = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "software.results.sharedResetWarning" @($candidateIds.Count)),
                (Get-DashboardText "software.results.sharedResetTitle"),
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
            if ($warning -eq [System.Windows.Forms.DialogResult]::Yes) {
                $dialog.Tag = [pscustomobject]@{ Proceed=$true; SelectedCandidateIds=$candidateIds }
                $dialog.Close()
            }
        })
        $footer.Controls.Add($continueButton)
    }

    $officialButton = New-Object System.Windows.Forms.Button
    $officialButton.Text = Get-DashboardText "software.results.openOfficial"
    $officialButton.Size = New-Object System.Drawing.Size(190, 38)
    $officialButton.Add_Click({
        $selectedList = if ($tabControl.SelectedTab -and $tabControl.SelectedTab.Tag) { $tabControl.SelectedTab.Tag } else { $thirdPartyList }
        if ($selectedList.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.selectForOfficial"), (Get-DashboardText "software.results.title"), "OK", "Information") | Out-Null
            return
        }
        $url = [string]$selectedList.SelectedItems[0].Tag.Application.OfficialReferenceUrl
        if ([string]::IsNullOrWhiteSpace($url)) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.noOfficialLink"), (Get-DashboardText "software.results.title"), "OK", "Information") | Out-Null
            return
        }
        try { Start-Process -FilePath $url } catch {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "software.results.openOfficialFailed" @($_.Exception.Message)), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        }
    })
    $footer.Controls.Add($officialButton)

    if (-not $ReadOnly -and $selectableCount -gt 0) {
        $clearButton = New-Object System.Windows.Forms.Button
        $clearButton.Text = Get-DashboardText "common.clearAll"
        $clearButton.Size = New-Object System.Drawing.Size(138, 38)
        $clearButton.Add_Click({ foreach ($row in $thirdPartyList.Items) { $row.Checked = $false } })
        $footer.Controls.Add($clearButton)

        $selectAllButton = New-Object System.Windows.Forms.Button
        $selectAllButton.Text = Get-DashboardText "common.selectAll"
        $selectAllButton.Size = New-Object System.Drawing.Size(138, 38)
        $selectAllButton.Add_Click({ foreach ($row in $thirdPartyList.Items) { if ([bool]$row.Tag.SelectionAllowed) { $row.Checked = $true } } })
        $footer.Controls.Add($selectAllButton)
    }

    $setTextMaximumWidth = {
        $availableWidth = [Math]::Max(120, $mainLayout.ClientSize.Width - $mainLayout.Padding.Horizontal)
        foreach ($label in @($heading, $summary, $hint)) {
            if ($label.MaximumSize.Width -ne $availableWidth) {
                $label.MaximumSize = New-Object System.Drawing.Size($availableWidth, 0)
            }
        }
    }
    $refreshLayout = {
        $mainLayout.SuspendLayout()
        try {
            & $setTextMaximumWidth
            foreach ($targetList in @($thirdPartyList, $systemList)) { & $resizeListColumns $targetList }
            $footer.AutoScroll = $false
            $footer.PerformLayout()
        } finally {
            $mainLayout.ResumeLayout($true)
        }
    }
    $mainLayout.Add_SizeChanged({ & $refreshLayout })
    $dialog.Add_Shown({ & $refreshLayout })

    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $result = $dialog.Tag
    $dialog.Dispose()
    return $result
}

function Complete-CleanupScan {
    try {
        if (-not (Test-Path -LiteralPath $script:cleanupDecisionFile)) {
            throw (Get-DashboardText "cleanup.scan.resultMissing")
        }
        $scan = Get-Content -LiteralPath $script:cleanupDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupDecisionFile -Force -ErrorAction SilentlyContinue
        $script:cleanupDecisionFile = ""
        if ($scan.PSObject.Properties['ScanScope'] -and [string]$scan.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
            $script:cleanupScanScope = [string]$scan.ScanScope
        }
        $scopedCleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems @($scan.CleanupItems) -Scope $script:cleanupScanScope)
        $scan.CleanupItems = $scopedCleanupItems
        if ($scan.ReportPath -and (Test-Path -LiteralPath $scan.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$scan.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($scan.ReportPath))
        }
        $thirdPartySuggestedIds = @()

        if ([int]$scan.ScanWarningCount -gt 0) {
            Set-ButtonsEnabled $true
            $status.Text = Get-DashboardText "cleanup.scan.incompleteStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            Write-ProgressLog (Get-DashboardText "cleanup.scan.incompleteLog" @($scan.ScanWarningCount))
            if (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "ThirdParty") {
                # A partial scan still has useful evidence, but it must never
                # unlock execution.  Show it read-only before the recovery
                # choice instead of making the inventory appear empty.
                [void](Show-ThirdPartyAssessmentResults -Scan $scan -ReadOnly -Warnings @($scan.ScanWarnings))
            }
            $choice = Show-ScanWarningRecoveryDialog -Scan $scan
            if ($choice -eq "Repair") {
                Start-ScanSourceRepair
            } elseif ($choice -eq "Retry") {
                Start-Cleanup -ReuseSessionSettings
            } else {
                $script:cleanupAutoSafeMode = $false
                Write-ProgressLog (Get-DashboardText "cleanup.scan.closedLog")
            }
            return
        }

        if ($script:cleanupScanScope -eq "ThirdParty") {
            $script:cleanupAutoSafeMode = $false
            Set-ButtonsEnabled $true
            $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan
            if ([bool]$assessmentChoice.Proceed) {
                Start-CleanupDeep -CleanupItems $scopedCleanupItems -SuggestedIds @($assessmentChoice.SelectedCandidateIds)
            } else {
                $remainingThirdPartyCount = if ($scan.PSObject.Properties['ThirdPartyRemediationFindingCount']) {
                    [int]$scan.ThirdPartyRemediationFindingCount
                } else {
                    [int]$scan.ThirdPartyCandidateCount
                }
                $status.Text = Get-DashboardText "software.results.closedStatus" @(
                    [int]$scan.ThirdPartyApplicationCount,
                    $remainingThirdPartyCount)
                $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
                Write-ProgressLog (Get-DashboardText "software.results.closedLog")
            }
            return
        }

        if (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "ThirdParty") {
            # In a normal combined scan, let the user choose eligible third-party
            # artifacts one-by-one or all at once.  The choices only preselect
            # IDs for the unified final review; they are never auto-applied.
            if ([bool]$script:cleanupAutoSafeMode) {
                [void](Show-ThirdPartyAssessmentResults -Scan $scan -ReadOnly)
            } else {
                $assessmentChoice = Show-ThirdPartyAssessmentResults -Scan $scan
                if ([bool]$assessmentChoice.Proceed) {
                    $thirdPartySuggestedIds = @($assessmentChoice.SelectedCandidateIds)
                }
            }
        }

        if ($scopedCleanupItems.Count -gt 0) {
            if ([bool]$script:cleanupAutoSafeMode) {
                $automaticSafeItems = @(Get-AutomaticSafeCleanupItems -CleanupItems $scopedCleanupItems)
                if ($automaticSafeItems.Count -gt 0) {
                    Write-ProgressLog (Get-DashboardText "cleanup.auto.safeFound" @($automaticSafeItems.Count))
                    Start-CleanupDeep -CleanupItems $scopedCleanupItems -AutomaticSafeMode
                    return
                }

                $script:cleanupAutoSafeMode = $false
                Set-ButtonsEnabled $true
                $manualAnswer = [System.Windows.Forms.MessageBox]::Show(
                    (Get-DashboardText "cleanup.auto.nonePrompt"),
                    (Get-DashboardText "cleanup.auto.noneTitle"),
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($manualAnswer -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Start-CleanupDeep -CleanupItems $scopedCleanupItems
                } else {
                    $status.Text = Get-DashboardText "cleanup.auto.noneStatus"
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                return
            }

            $licenseNote = if ((Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") -and [bool]$scan.ProtectedLicense) {
                Get-DashboardText "cleanup.scan.protectedNote" @($scan.ProtectedChannel, $scan.ProtectedReason)
            } elseif (Test-GuiCleanupScopeIncludes -Scope $script:cleanupScanScope -Component "Windows") {
                Get-DashboardText "cleanup.scan.unprotectedNote"
            } else {
                ""
            }
            $findingMessage = switch ($script:cleanupScanScope) {
                "WindowsOffice" { Get-DashboardText "cleanup.scan.findingSummary.windowsOffice" @($scan.ActivatorFindingCount, $scan.ConfigurationResidueCount, $scan.WindowsKmsCount, $scan.OfficeKmsCount, $scopedCleanupItems.Count) }
                "ThirdParty" { Get-DashboardText "cleanup.scan.findingSummary.thirdParty" @($scopedCleanupItems.Count) }
                default { Get-DashboardText "cleanup.scan.findingSummary" @($scan.ActivatorFindingCount, $scan.ConfigurationResidueCount, $scan.WindowsKmsCount, $scan.OfficeKmsCount, $scan.HistoryFindingCount, $scan.ThirdPartyCandidateCount) }
            }
            $message = $licenseNote + $findingMessage
            $answer = [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "cleanup.scan.selectionTitle"), "YesNo", "Warning")
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                Set-ButtonsEnabled $true
                $status.Text = Get-DashboardText "cleanup.scan.cancelledStatus"
                Write-ProgressLog (Get-DashboardText "cleanup.scan.cancelledLog")
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
                return
            }
            Start-CleanupDeep -CleanupItems $scopedCleanupItems -SuggestedIds $thirdPartySuggestedIds
            return
        }

        $script:cleanupAutoSafeMode = $false
        Set-ButtonsEnabled $true
        $componentSummary = @(Get-GuiCleanupComponentStatusLines -Scan $scan -Scope $script:cleanupScanScope) -join "`r`n"
        $scopeLabel = Get-CleanupScopeLabel -Scope $script:cleanupScanScope
        if ([bool]$scan.ProtectedLicense) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "cleanup.scan.protectedResult" @($scan.ProtectedChannel, $componentSummary, (Get-GuiScanIntegerProperty -Scan $scan -Name 'HistoryFindingCount'), $scan.CleanupConclusion)), (Get-DashboardText "cleanup.scan.protectedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "cleanup.scan.protectedStatus" @($scan.ProtectedChannel)
            Write-ProgressLog (Get-DashboardText "cleanup.scan.cleanLog" @($scopeLabel))
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show((Get-GuiCleanupNoFindingMessage -Scan $scan -Scope $script:cleanupScanScope), (Get-DashboardText "cleanup.scan.resultTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "cleanup.scan.noFindingStatus"
            Write-ProgressLog (Get-DashboardText "cleanup.scan.noFindingLog")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "cleanup.scan.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "cleanup.scan.readFailedLog" @($_.Exception.Message))
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Test-GuiOfficialHttpsTarget([string]$Target) {
    $uri = $null
    return [bool]([Uri]::TryCreate($Target, [UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -eq 'https' -and -not [string]::IsNullOrWhiteSpace($uri.Host) -and
        [string]::IsNullOrWhiteSpace($uri.UserInfo))
}

function Open-GuiVendorLicenseAction {
    param($Action, $Result)
    if ($script:offlineMode) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'app.offline.blocked'), (Get-DashboardText 'app.offline.blockedTitle'), 'OK', 'Information') | Out-Null
        return
    }
    $targets = @(if ($Action -and $Action.PSObject.Properties['Target'] -and (Test-GuiOfficialHttpsTarget ([string]$Action.Target))) {
        @($Action)
    } elseif ($Action -and $Action.PSObject.Properties['Targets']) {
        @($Action.Targets | Where-Object { Test-GuiOfficialHttpsTarget ([string]$_.Target) })
    } elseif ($Result -and $Result.PSObject.Properties['OfficialLicensePostCheck']) {
        @($Result.OfficialLicensePostCheck.OfficialActions | Where-Object {
            [string]$_.Code -in @('OpenVendorActivation','OpenVendorRepair') -and
            (Test-GuiOfficialHttpsTarget ([string]$_.Target))
        })
    } else { @() })
    if ($targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'cleanup.result.vendorTargetMissing'), (Get-DashboardText 'cleanup.result.vendorTitle'), 'OK', 'Information') | Out-Null
        return
    }
    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = Get-DashboardText 'cleanup.result.vendorTitle'
    $picker.StartPosition = 'CenterParent'; $picker.ClientSize = New-Object System.Drawing.Size(700,160); $picker.Tag = ''
    $label = New-Object System.Windows.Forms.Label
    $label.Text = Get-DashboardText 'cleanup.result.vendorHint'; $label.Location = New-Object System.Drawing.Point(16,14); $label.Size = New-Object System.Drawing.Size(668,38)
    $picker.Controls.Add($label)
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'; $combo.Location = New-Object System.Drawing.Point(16,58); $combo.Size = New-Object System.Drawing.Size(668,28)
    foreach ($target in $targets) {
        [void]$combo.Items.Add([pscustomobject]@{ Label="$([string]$target.Name) — $([string]$target.Target)"; Target=[string]$target.Target })
    }
    $combo.DisplayMember = 'Label'; if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }; $picker.Controls.Add($combo)
    $open = New-Object System.Windows.Forms.Button
    $open.Text = Get-DashboardText 'software.results.openOfficial'; $open.Location = New-Object System.Drawing.Point(454,108); $open.Size = New-Object System.Drawing.Size(140,32)
    $open.Add_Click({ if ($combo.SelectedItem) { $picker.Tag=[string]$combo.SelectedItem.Target; $picker.Close() } }); $picker.Controls.Add($open)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = Get-DashboardText 'app.close'; $cancel.Location = New-Object System.Drawing.Point(600,108); $cancel.Size = New-Object System.Drawing.Size(84,32)
    $cancel.Add_Click({ $picker.Close() }); $picker.CancelButton=$cancel; $picker.Controls.Add($cancel)
    Set-ToolWindowTheme -Root $picker -Mode $script:dashboardTheme
    [void]$picker.ShowDialog($form); $targetUrl=[string]$picker.Tag; $picker.Dispose()
    if (Test-GuiOfficialHttpsTarget $targetUrl) { try { Start-Process -FilePath $targetUrl } catch { [System.Windows.Forms.MessageBox]::Show((Get-DashboardText 'software.results.openOfficialFailed' @($_.Exception.Message)), (Get-DashboardText 'common.errorTitle'), 'OK', 'Error') | Out-Null } }
}

function Get-GuiPostVerificationDispositionLabel {
    param([string]$Disposition)

    $key = switch ($Disposition) {
        'ResidualAfterSelectedAction' { 'cleanup.result.postDisposition.residual' }
        'RemainingActionable' { 'cleanup.result.postDisposition.actionable' }
        'OfficialActionRequired' { 'cleanup.result.postDisposition.officialAction' }
        'OfficialGuidanceAvailable' { 'cleanup.result.postDisposition.officialGuidance' }
        'ActionFailed' { 'cleanup.result.postDisposition.failed' }
        'ScanIncomplete' { 'cleanup.result.postDisposition.scanIncomplete' }
        default { 'cleanup.result.postDisposition.cannotAutoHandle' }
    }
    return Get-DashboardText $key
}

function Get-GuiPostVerificationOutcomeLabel {
    param([string]$Outcome)

    $key = switch ($Outcome) {
        'VerifiedValid' { 'cleanup.result.postOutcome.verifiedValid' }
        'FullyHandled' { 'cleanup.result.postOutcome.fullyHandled' }
        'RemainingActionable' { 'cleanup.result.postOutcome.remainingActionable' }
        default { 'cleanup.result.postOutcome.cannotAutoHandle' }
    }
    return Get-DashboardText $key
}

function Show-CleanupResultCenter {
    param($Result, [bool]$WasDeepCleanup, [bool]$SafetyBlocked)

    $isDryRun = [bool]($Result.PSObject.Properties['SimulationOnly'] -and [bool]$Result.SimulationOnly)
    $hasPostVerification = [bool]$Result.PSObject.Properties['PostVerificationItems']
    $postVerificationItems = if ($hasPostVerification) { @($Result.PostVerificationItems) } else { @() }
    $remainingItems = if ($hasPostVerification) { @($postVerificationItems) } else { @($Result.CleanupItems) }
    $postVerificationOutcome = if ($Result.PSObject.Properties['PostVerificationOutcome']) { [string]$Result.PostVerificationOutcome } else { '' }
    $thirdPartyExecutionResults = @($(if ($Result.PSObject.Properties['ThirdPartyExecutionResults']) { @($Result.ThirdPartyExecutionResults) }))
    $systemChangeApplied = [bool]($Result.PSObject.Properties['SystemChangeApplied'] -and [bool]$Result.SystemChangeApplied)
    $noAutomaticChange = [bool](-not $isDryRun -and -not $SafetyBlocked -and [int]$Result.SelectedCleanupItemCount -gt 0 -and -not $systemChangeApplied -and $thirdPartyExecutionResults.Count -gt 0)
    $guidedActionOnly = [bool]($Result.PSObject.Properties['DecisionCode'] -and [string]$Result.DecisionCode -eq 'GuidedActionRequired')
    $officiallyLicensed = [bool]($Result.PSObject.Properties['OfficiallyLicensed'] -and [bool]$Result.OfficiallyLicensed)
    $officialLicenseStateCode = if ($Result.PSObject.Properties['OfficialLicenseStateCode']) { [string]$Result.OfficialLicenseStateCode } else { 'Unknown' }
    $officialPostCheck = if ($Result.PSObject.Properties['OfficialLicensePostCheck']) { $Result.OfficialLicensePostCheck } else { $null }
    $nextActions = @($Result.NextActions)
    if ($isDryRun) {
        $nextActions = @([pscustomobject]@{
            Code='ExecuteDryRunPlan'; Label=(Get-DashboardText 'cleanup.dryRun.executeButton')
            Detail=(Get-DashboardText 'cleanup.dryRun.executeDetail'); CandidateCount=[int]@($Result.SelectedCleanupIds).Count
        }) + @($nextActions | Where-Object { [string]$_.Code -in @('Recheck','OpenReport') })
    }
    if ($SafetyBlocked) {
        $nextActions = @($nextActions | Where-Object { [string]$_.Code -in @('Recheck','OpenReport') })
    }

    $headingText = if ($isDryRun) {
        Get-DashboardText 'cleanup.dryRun.completedHeading' @([int]$Result.PlannedActionCount)
    } elseif ($SafetyBlocked) {
        Get-DashboardText "cleanup.result.blockedHeading"
    } elseif ($guidedActionOnly) {
        Get-DashboardText 'cleanup.result.guidedActionHeading'
    } elseif ($noAutomaticChange) {
        Get-DashboardText "cleanup.result.noAutomaticChangeHeading"
    } elseif ($postVerificationOutcome -eq 'VerifiedValid' -or $officiallyLicensed) {
        Get-DashboardText 'cleanup.result.licensedHeading'
    } elseif ($postVerificationOutcome -eq 'FullyHandled') {
        Get-DashboardText 'cleanup.result.fullyHandledHeading'
    } elseif ([bool]$Result.ReadyForOfficialActivation) {
        Get-DashboardText "cleanup.result.readyHeading"
    } elseif ($remainingItems.Count -gt 0) {
        Get-DashboardText "cleanup.result.remainingHeading" @($remainingItems.Count)
    } else {
        Get-DashboardText "cleanup.result.reviewHeading"
    }
    $headingColor = if ($isDryRun) { [System.Drawing.Color]::FromArgb(18, 59, 116) } elseif ($officiallyLicensed -or $postVerificationOutcome -eq 'FullyHandled') { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
    if ($SafetyBlocked) { $headingColor = [System.Drawing.Color]::DarkRed }

    $body = New-Object System.Collections.Generic.List[string]
    $body.Add([string]$Result.CleanupConclusion)
    $body.Add("")
    $body.Add((Get-DashboardText "cleanup.result.verificationHeading"))
    $body.Add((Get-DashboardText "cleanup.result.activatorCount" @($Result.ActivatorFindingCount)))
    $body.Add((Get-DashboardText "cleanup.result.residueCount" @($Result.ConfigurationResidueCount)))
    $body.Add((Get-DashboardText "cleanup.result.windowsKmsCount" @($Result.WindowsKmsCount)))
    $body.Add((Get-DashboardText "cleanup.result.officeKmsCount" @($Result.OfficeKmsCount)))
    $body.Add((Get-DashboardText "cleanup.result.thirdPartyCount" @($Result.ThirdPartyCandidateCount)))
    if ($Result.PSObject.Properties['SelectedThirdPartyCandidateCount'] -and [int]$Result.SelectedThirdPartyCandidateCount -gt 0) {
        $body.Add((Get-DashboardText 'cleanup.result.selectedThirdPartySummary' @(
            [int]$Result.SelectedThirdPartyResolvedCount,
            [int]$Result.SelectedThirdPartyCandidateCount,
            [int]$Result.SelectedThirdPartyRemainingCount
        )))
    }
    $body.Add((Get-DashboardText "cleanup.result.historyCount" @($Result.HistoryFindingCount)))
    $body.Add((Get-DashboardText "cleanup.result.warningCount" @($Result.ScanWarningCount)))
    $body.Add((Get-DashboardText "cleanup.result.reviewCount" @($Result.ReadinessReviewCount)))
    $body.Add((Get-DashboardText 'cleanup.result.licenseState' @(
        $(if ($officiallyLicensed) { 'True' } else { 'False' }),
        $officialLicenseStateCode,
        $(if ([bool]$Result.ReadyForOfficialActivation) { 'True' } else { 'False' })
    )))
    if ($hasPostVerification) {
        $body.Add((Get-DashboardText 'cleanup.result.postVerificationHeading'))
        $body.Add((Get-DashboardText 'cleanup.result.postVerificationOutcome' @(
            (Get-GuiPostVerificationOutcomeLabel -Outcome $postVerificationOutcome))))
    }
    if ($officialPostCheck) {
        foreach ($outcome in @($officialPostCheck.Windows, $officialPostCheck.Office) | Where-Object { $_ -and [bool]$_.Applicable }) {
            $body.Add((Get-DashboardText 'cleanup.result.componentLicenseState' @(
                [string]$outcome.Component,
                $(if ([bool]$outcome.OfficiallyLicensed) { 'True' } else { 'False' }),
                [string]$outcome.StateCode
            )))
        }
        $thirdPartyOutcomes = @($officialPostCheck.ThirdParty | Where-Object { [bool]$_.Applicable })
        if ($thirdPartyOutcomes.Count -gt 0) {
            $body.Add((Get-DashboardText 'cleanup.result.thirdPartyLicenseState' @(
                @($thirdPartyOutcomes | Where-Object { [bool]$_.OfficiallyLicensed }).Count,
                $thirdPartyOutcomes.Count
            )))
        }
    }

    if ($isDryRun) {
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.dryRun.noChangesHeading'))
        $body.Add((Get-DashboardText 'cleanup.dryRun.noChangesDetail'))
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.dryRun.planHeading' @([int]$Result.PlannedActionCount)))
        foreach ($planned in @($Result.PlannedActions)) {
            $restoreLabel = if ([bool]$planned.Restorable) { Get-DashboardText 'cleanup.dryRun.restorable' } else { Get-DashboardText 'cleanup.dryRun.notRestorable' }
            $body.Add("$($planned.Order). $($planned.Action) - $($planned.Target) [$restoreLabel]")
        }
    }

    if ($thirdPartyExecutionResults.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText 'cleanup.result.thirdPartyExecutionHeading'))
        foreach ($execution in @($thirdPartyExecutionResults)) {
            $statusKey = if ($execution.PSObject.Properties['PostCheckStatus'] -and [string]$execution.PostCheckStatus -eq 'ResidualRemaining') {
                'cleanup.result.execution.residueRemaining'
            } else { switch ([string]$execution.Status) {
                'Succeeded' { 'cleanup.result.execution.succeeded' }
                'SucceededNeedsVerification' { 'cleanup.result.execution.needsVerification' }
                'Failed' { 'cleanup.result.execution.failed' }
                'NoChange' { 'cleanup.result.execution.noChange' }
                default { 'cleanup.result.execution.guidanceOnly' }
            } }
            $executionStatus = Get-DashboardText $statusKey
            $executionTarget = if ([string]::IsNullOrWhiteSpace([string]$execution.Target)) { Get-DashboardText 'common.unknown' } else { [string]$execution.Target }
            $body.Add("- [$executionStatus] $([string]$execution.Name) - $executionTarget")
        }
    }

    if ($nextActions.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.nextHeading"))
        $stepNumber = 0
        foreach ($next in $nextActions) {
            if ([string]$next.Code -eq 'OpenReport') { continue }
            $stepNumber++
            $candidateText = if ([int]$next.CandidateCount -gt 0) { Get-DashboardText "cleanup.result.candidateSuffix" @($next.CandidateCount) } else { "" }
            $body.Add("$stepNumber. $($next.Label)$candidateText - $($next.Detail)")
        }
    }

    if ($remainingItems.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText $(if ($hasPostVerification) { 'cleanup.result.postVerificationItemsHeading' } else { 'cleanup.result.remainingItemsHeading' })))
        foreach ($item in @($remainingItems)) {
            if ($hasPostVerification) {
                $location = (([string]$item.Location) -replace "`0|`r?`n", " ").Trim()
                if ([string]::IsNullOrWhiteSpace($location)) { $location = Get-DashboardText 'common.unknown' }
                $reason = (([string]$item.Reason) -replace "`0|`r?`n", " ").Trim()
                if ([string]::IsNullOrWhiteSpace($reason)) { $reason = (([string]$item.Detail) -replace "`0|`r?`n", " ").Trim() }
                $body.Add((Get-DashboardText 'cleanup.result.postVerificationItem' @(
                    (Get-GuiPostVerificationDispositionLabel -Disposition ([string]$item.Disposition)),
                    [string]$item.Name, $location, $reason)))
            } else {
                $detail = (([string]$item.Detail) -replace "`0|`r?`n", " ").Trim()
                $body.Add("- [$($item.Type)] $($item.Name) - $detail")
            }
        }
    }

    $guidance = @($Result.HandlingGuidance)
    if ($guidance.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.guidanceHeading"))
        foreach ($line in $guidance) { $body.Add("• $line") }
    }

    $rawActions = @($Result.Actions)
    if ($rawActions.Count -gt 0) {
        $body.Add("")
        $body.Add((Get-DashboardText "cleanup.result.actionsHeading"))
        foreach ($action in @($rawActions)) {
            $line = (([string]$action) -replace "`0|`r?`n", " | ").Trim()
            $body.Add("• $line")
        }
    }
    $body.Add("")
    $body.Add([string]$Result.ScopeNote)
    $body.Add((Get-DashboardText "common.reportPath" @($Result.ReportPath)))

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($isDryRun) { Get-DashboardText 'cleanup.dryRun.resultTitle' } elseif ($postVerificationOutcome -eq 'VerifiedValid' -or $officiallyLicensed) { Get-DashboardText 'cleanup.result.licensedTitle' } elseif ($postVerificationOutcome -eq 'FullyHandled') { Get-DashboardText 'cleanup.result.fullyHandledTitle' } elseif ($guidedActionOnly) { Get-DashboardText 'cleanup.result.guidedActionTitle' } elseif ($noAutomaticChange) { Get-DashboardText 'cleanup.result.noAutomaticChangeTitle' } elseif ([bool]$Result.ReadyForOfficialActivation) { Get-DashboardText "cleanup.result.readyTitle" } else { Get-DashboardText "cleanup.result.remainingTitle" }
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
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.TableLayoutPanel
    $header.Dock = "Top"
    $header.AutoSize = $true
    $header.AutoSizeMode = "GrowAndShrink"
    $header.ColumnCount = 1
    $header.RowCount = 2
    [void]$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $headingText
    $heading.Font = $fontTitle
    $heading.ForeColor = $headingColor
    $heading.AutoSize = $true
    $heading.Dock = "Top"
    $header.Controls.Add($heading, 0, 0)
    $subheading = New-Object System.Windows.Forms.Label
    $subheading.Text = if ($isDryRun) { Get-DashboardText 'cleanup.dryRun.resultHint' } elseif ($SafetyBlocked) { Get-DashboardText "cleanup.result.blockedHint" } elseif ($guidedActionOnly) { Get-DashboardText 'cleanup.result.guidedActionHint' } elseif ($postVerificationOutcome -eq 'FullyHandled') { Get-DashboardText 'cleanup.result.fullyHandledHint' } elseif ($postVerificationOutcome -eq 'CannotAutoHandle') { Get-DashboardText 'cleanup.result.cannotAutoHandleHint' } elseif ($remainingItems.Count -gt 0) { Get-DashboardText "cleanup.result.remainingHint" } else { Get-DashboardText "cleanup.result.defaultHint" }
    $subheading.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $subheading.AutoSize = $true
    $subheading.Dock = "Top"
    $header.Controls.Add($subheading, 0, 1)
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
    $buttonBar.Dock = "Top"
    $buttonBar.FlowDirection = "RightToLeft"
    $buttonBar.WrapContents = $true
    $buttonBar.AutoScroll = $false
    $buttonBar.AutoSize = $true
    $buttonBar.AutoSizeMode = "GrowAndShrink"
    $buttonBar.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $layout.Controls.Add($buttonBar, 0, 2)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = Get-DashboardText "common.close"
    $close.Size = New-Object System.Drawing.Size(92, 34)
    $close.Tag = "Close"
    $close.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
    $dialog.CancelButton = $close
    $buttonBar.Controls.Add($close)

    $reportButton = New-Object System.Windows.Forms.Button
    $reportButton.Text = Get-DashboardText "common.openReport"
    $reportButton.Size = New-Object System.Drawing.Size(128, 34)
    $reportButton.Add_Click({
        if ($Result.ReportPath -and (Test-Path -LiteralPath $Result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$Result.ReportPath) -Title (Get-DashboardText "cleanup.report.inspectionTitle") -FilePrefix "BaoCao_KhacPhucKMS_KetQua")
        }
    })
    $buttonBar.Controls.Add($reportButton)

    foreach ($next in @($nextActions | Where-Object { [string]$_.Code -ne 'OpenReport' })) {
        $actionButton = New-Object System.Windows.Forms.Button
        $actionButton.Text = [string]$next.Label
        $actionButton.AutoSize = $true
        $actionButton.MinimumSize = New-Object System.Drawing.Size(108, 34)
        $actionButton.MaximumSize = New-Object System.Drawing.Size(280, 34)
        $actionButton.Tag = [string]$next.Code
        if ([string]$next.Code -in @('ExecuteDryRunPlan','RemediateRemaining','RepairScanSources','OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair')) {
            $actionButton.Font = $fontBold
            $actionButton.BackColor = if ([string]$next.Code -in @('OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation')) { [System.Drawing.Color]::FromArgb(230, 247, 236) } else { [System.Drawing.Color]::FromArgb(255, 248, 230) }
        }
        $actionButton.Add_Click({ param($sender,$eventArgs) $dialog.Tag = [string]$sender.Tag; $dialog.Close() })
        $buttonBar.Controls.Add($actionButton)
        if (-not $dialog.AcceptButton -and [string]$next.Code -in @('ExecuteDryRunPlan','RemediateRemaining','RepairScanSources','OpenLicenseManager','ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair','Recheck')) { $dialog.AcceptButton = $actionButton }
    }

    $updateResultHeaderWidth = {
        $availableWidth = [Math]::Max(120, $layout.ClientSize.Width - $layout.Padding.Horizontal)
        foreach ($label in @($heading, $subheading)) {
            if ($label.MaximumSize.Width -ne $availableWidth) {
                $label.MaximumSize = New-Object System.Drawing.Size($availableWidth, 0)
            }
        }
        $layout.PerformLayout()
    }
    $layout.Add_SizeChanged({ & $updateResultHeaderWidth })
    $dialog.Add_Shown({
        & $updateResultHeaderWidth
        $buttonBar.AutoScroll = $false
        $buttonBar.PerformLayout()
        $details.SelectionStart = 0; $details.SelectionLength = 0; $details.ScrollToCaret()
    })
    Set-ToolWindowTheme -Root $dialog -Mode $script:dashboardTheme
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    return $choice
}

function Complete-CleanupRemediation([bool]$wasDeepCleanup) {
    Set-ButtonsEnabled $true
    $completedAutoSafeMode = [bool]$script:cleanupAutoSafeMode
    $completedDryRunMode = [bool]$script:cleanupDryRunMode
    $script:cleanupAutoSafeMode = $false
    $script:cleanupDryRunMode = $false
    try {
        if ($script:cleanupSelectionFile -and (Test-Path -LiteralPath $script:cleanupSelectionFile)) {
            Remove-Item -LiteralPath $script:cleanupSelectionFile -Force -ErrorAction SilentlyContinue
        }
        $script:cleanupSelectionFile = ""
        if (-not (Test-Path -LiteralPath $script:cleanupResultFile)) {
            throw (Get-DashboardText "cleanup.remediation.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:cleanupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:cleanupResultFile -Force -ErrorAction SilentlyContinue
        $script:cleanupResultFile = ""
        if ($result.PSObject.Properties['ScanScope'] -and [string]$result.ScanScope -in @("All", "Windows", "Office", "ThirdParty", "WindowsOffice", "WindowsThirdParty", "OfficeThirdParty")) {
            $script:cleanupScanScope = [string]$result.ScanScope
        }
        $result.CleanupItems = @(Get-GuiScopedCleanupItems -CleanupItems @($result.CleanupItems) -Scope $script:cleanupScanScope)
        $postVerificationItems = if ($result.PSObject.Properties['PostVerificationItems']) { @($result.PostVerificationItems) } else { @($result.CleanupItems) }
        $postVerificationSuggestedIds = if ($result.PSObject.Properties['PostVerificationSuggestedIds']) { @($result.PostVerificationSuggestedIds) } else { @() }
        $overallReadyForActivation = [bool]$result.ReadyForOfficialActivation
        $scopeReadyForOriginalState = if ($result.PSObject.Properties['ScopeReadyForOriginalState']) { [bool]$result.ScopeReadyForOriginalState } else { $overallReadyForActivation }
        $result | Add-Member -NotePropertyName OverallReadyForOfficialActivation -NotePropertyValue $overallReadyForActivation -Force
        $result.ReadyForOfficialActivation = $scopeReadyForOriginalState
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
        $wasSafetyBlocked = [bool](
            ($result.PSObject.Properties['DecisionCode'] -and [string]$result.DecisionCode -in @('SelectionRejected','RemediationFailed')) -or
            @($result.Actions | Where-Object { [string]$_ -match '^(?:ĐÃ KHÓA XỬ LÝ:|REMEDIATION BLOCKED:)' }).Count -gt 0
        )
        $systemChangeApplied = if ($result.PSObject.Properties['SystemChangeApplied']) { [bool]$result.SystemChangeApplied } else { $false }
        $confirmedActionCount = if ($result.PSObject.Properties['SystemChangeCount']) { [int]$result.SystemChangeCount } else { 0 }
        $timelineEventType = if ($completedDryRunMode) { 'LicenseCleanupDryRunCompleted' } else { 'LicenseCleanupCompleted' }
        [void](Write-LicenseTimelineEventSafe -EventType $timelineEventType -Source "GUI" -IsChange:([bool](-not $completedDryRunMode -and -not $wasSafetyBlocked -and $systemChangeApplied)) -Data ([ordered]@{
            SafetyBlocked=$wasSafetyBlocked
            SelectedItemCount=[int]$result.SelectedCleanupItemCount
            ConfirmedActionCount=$confirmedActionCount
            ReadyForOfficialActivation=[bool]$result.ReadyForOfficialActivation
            RemainingItemCount=[int]$postVerificationItems.Count
            BackupCreated=[bool](-not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory))
            AutomaticSafeMode=$completedAutoSafeMode
            SimulationOnly=$completedDryRunMode
            PlannedActionCount=[int]$result.PlannedActionCount
        }))
        if ($completedDryRunMode) {
            $status.Text = Get-DashboardText 'cleanup.dryRun.completedStatus' @([int]$result.PlannedActionCount)
            $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        } elseif ($wasSafetyBlocked) {
            $status.Text = Get-DashboardText "cleanup.remediation.blockedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } elseif ($result.PSObject.Properties['PostVerificationOutcome'] -and [string]$result.PostVerificationOutcome -eq 'FullyHandled') {
            $status.Text = Get-DashboardText 'cleanup.remediation.fullyHandledStatus'
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } elseif ([int]$result.SelectedCleanupItemCount -gt 0 -and -not $systemChangeApplied) {
            $status.Text = Get-DashboardText "cleanup.remediation.noAutomaticChangeStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } elseif ($result.PSObject.Properties['OfficiallyLicensed'] -and [bool]$result.OfficiallyLicensed) {
            $status.Text = Get-DashboardText 'cleanup.remediation.licensedStatus'
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } elseif ([bool]$result.ReadyForOfficialActivation) {
            $status.Text = Get-DashboardText "cleanup.remediation.readyStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        } else {
            $status.Text = Get-DashboardText "cleanup.remediation.remainingStatus" @($postVerificationItems.Count)
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.completedLog" @($result.CleanupConclusion))
        if ($wasDeepCleanup -and -not [string]::IsNullOrWhiteSpace([string]$result.BackupDirectory)) {
            Write-ProgressLog (Get-DashboardText "cleanup.remediation.backupLog" @($result.BackupDirectory))
        }
        $nextChoice = Show-CleanupResultCenter -Result $result -WasDeepCleanup $wasDeepCleanup -SafetyBlocked $wasSafetyBlocked
        switch ($nextChoice) {
            "ExecuteDryRunPlan" {
                $script:cleanupDryRunMode = $false
                Write-ProgressLog (Get-DashboardText 'cleanup.dryRun.executeLog')
                Start-CleanupDeep -CleanupItems @($result.CleanupItems) -SuggestedIds @($result.SelectedCleanupIds)
                return
            }
            "RemediateRemaining" {
                Write-ProgressLog (Get-DashboardText "cleanup.remediation.openRemainingLog")
                Start-CleanupDeep -CleanupItems @($result.CleanupItems) -SuggestedIds @($postVerificationSuggestedIds)
                return
            }
            "ConfigureApprovedKms" {
                if (Confirm-KmsApprovalConfiguration) {
                    Write-ProgressLog (Get-DashboardText "cleanup.remediation.kmsConfirmedLog")
                    Start-Cleanup -ReuseSessionSettings
                } else {
                    $status.Text = Get-DashboardText "cleanup.remediation.kmsUnchangedStatus"
                    $status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                return
            }
            "RepairScanSources" { Start-ScanSourceRepair; return }
            "Recheck" { Start-Cleanup -ReuseSessionSettings; return }
            "OpenLicenseManager" { Open-LicenseManager; return }
            { $_ -in @('ReviewVendorActivation','OpenVendorActivation','OpenVendorRepair') } {
                $vendorAction = @($result.NextActions | Where-Object { [string]$_.Code -eq [string]$nextChoice } | Select-Object -First 1)
                Open-GuiVendorLicenseAction -Action $(if ($vendorAction.Count -gt 0) { $vendorAction[0] } else { $null }) -Result $result
                return
            }
            "RestoreBackup" {
                $restoreScope = Show-LicenseScopeChooser -Mode "Restore"
                if (-not [string]::IsNullOrWhiteSpace($restoreScope)) { Start-CleanupRestore -Scope $restoreScope }
                return
            }
            default {
                if (-not [bool]$result.ReadyForOfficialActivation) {
                    Write-ProgressLog (Get-DashboardText "cleanup.remediation.closedLog")
                }
            }
        }
    } catch {
        $status.Text = Get-DashboardText "cleanup.remediation.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.failureGuidance")
        Write-ProgressLog (Get-DashboardText "cleanup.remediation.versionGuidance")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-OemInspect {
    if (-not (Test-Path -LiteralPath $oemScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "oem.inspect.action") (Get-DashboardText "oem.inspect.detail") $false
        Write-ProgressLog (Get-DashboardText "oem.inspect.progressLog")
        Write-ProgressLog (Get-DashboardText "oem.keyPrivacyLog")
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-decision-"
        $output = New-ToolReportRunDirectory -Category "OEM-KiemTra"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Inspect -OutputDir `"$output`" -DecisionFile `"$script:oemDecisionFile`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "oem.inspect" -Arguments $arguments -Action (Get-DashboardText "oem.inspect.action") -Hidden)
        $status.Text = Get-DashboardText "oem.inspect.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "oem.inspect.startFailed" @($_.Exception.Message))
    }
}

function Start-OemApply {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "oem.apply.integrityAction"))) { return }
    try {
        Start-ProgressDisplay (Get-DashboardText "oem.apply.action") (Get-DashboardText "oem.apply.detail") $true
        Write-ProgressLog (Get-DashboardText "oem.apply.requestAdmin")
        Write-ProgressLog (Get-DashboardText "oem.apply.preserveKeyLog")
        $script:oemDecisionFile = New-SecureRuntimePath "tool-oem-apply-result-"
        $output = New-ToolReportRunDirectory -Category "OEM-ApDung"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$oemScript`" -Mode Apply -OutputDir `"$output`" -DecisionFile `"$script:oemDecisionFile`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "oem.apply" -Arguments $arguments -Action (Get-DashboardText "oem.apply.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "oem.apply.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        if ($script:oemDecisionFile -and (Test-Path -LiteralPath $script:oemDecisionFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        }
        $script:oemDecisionFile = ""
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "oem.apply.cancelled"
        Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-OemInspect {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:oemDecisionFile)) {
            throw (Get-DashboardText "oem.inspect.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:oemDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:oemDecisionFile -Force -ErrorAction SilentlyContinue
        $script:oemDecisionFile = ""
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            [void](Open-ToolReportPresentation -SourcePath ([string]$result.ReportPath) -Title (Get-DashboardText "oem.report.inspectTitle") -FilePrefix "BaoCao_Key_OEM_BIOS")
        }

        if (-not [bool]$result.FirmwareKeyFound) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.inspect.notFoundMessage"), (Get-DashboardText "oem.inspect.notFoundTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "oem.inspect.notFoundStatus"
            Write-ProgressLog (Get-DashboardText "oem.inspect.notFoundLog")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }

        $activation = if ([bool]$result.IsActivated) { Get-DashboardText "common.licensed" } else { Get-DashboardText "common.notLicensedConfirmed" }
        $message = Get-DashboardText "oem.inspect.foundPrompt" @($result.FirmwareKeyMasked, $result.ProductName, $result.CurrentEdition, $activation, $result.CurrentChannel, $result.CurrentPartialKey)
        $answer = [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "oem.apply.confirmTitle"), "YesNo", "Warning")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-OemApply
            return
        }
        $status.Text = Get-DashboardText "oem.inspect.declinedStatus"
        Write-ProgressLog (Get-DashboardText "oem.inspect.declinedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    } catch {
        $status.Text = Get-DashboardText "oem.inspect.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "oem.inspect.readFailedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-DeepLicenseScan {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "deepScan.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $deepScanScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "deepScan.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "deepScan.privacyPrompt"),
        (Get-DashboardText "deepScan.privacyTitle"), "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay (Get-DashboardText "deepScan.action") (Get-DashboardText "deepScan.detail") $false
        Write-ProgressLog (Get-DashboardText "deepScan.progressLog")
        Write-ProgressLog (Get-DashboardText "deepScan.adminLog")
        Write-ProgressLog (Get-DashboardText "deepScan.readOnlyLog")
        $script:deepScanDecisionFile = New-SecureRuntimePath "tool-deep-license-"
        $output = New-ToolReportRunDirectory -Category "Quet-ChuyenSau"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$deepScanScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:deepScanDecisionFile`" -Culture `"$script:dashboardCulture`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "license.deep-scan" -Arguments $arguments -Action (Get-DashboardText "deepScan.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "deepScan.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        Stop-ProgressOnStartError (Get-DashboardText "deepScan.startFailed" @($_.Exception.Message))
    }
}

function Complete-DeepLicenseScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:deepScanDecisionFile)) {
            throw (Get-DashboardText "deepScan.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:deepScanDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:deepScanDecisionFile -Force -ErrorAction SilentlyContinue
        $script:deepScanDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "deepScan.accessDeniedMessage"), (Get-DashboardText "common.accessDeniedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "deepScan.accessDeniedStatus"
            Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $guidanceLines = @($result.HandlingGuidance | ForEach-Object { "- $_" })
        $reviewLines = @($result.ReviewItems | Select-Object -First 3 | ForEach-Object { "- $($_.Name): $($_.Recommendation)" })
        $guidanceSummary = if ($guidanceLines.Count -gt 0) { Get-DashboardText "deepScan.guidanceSummary" @(($guidanceLines -join "`r`n")) } else { "" }
        $reviewSummary = if ($reviewLines.Count -gt 0) { Get-DashboardText "deepScan.reviewSummary" @(($reviewLines -join "`r`n")) } else { "" }
        $oemState = if ([bool]$result.OemKeyPresent) { Get-DashboardText "common.yes" } else { Get-DashboardText "common.notFound" }
        $message = Get-DashboardText "deepScan.resultSummary" @($result.Overall, $result.HighCount, $result.ReviewCount, $result.ActiveChannel, $oemState, $guidanceSummary, $reviewSummary, $result.ReportPath)
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "deepScan.completedTitle"), "OK", $(if ([int]$result.HighCount -gt 0) { "Warning" } else { "Information" })) | Out-Null
        [void](Open-ToolHtmlReport -Path ([string]$result.ReportPath))
        $status.Text = Get-DashboardText "deepScan.completedStatus" @($result.Overall)
        Write-ProgressLog (Get-DashboardText "deepScan.completedLog")
        $status.ForeColor = if ([int]$result.HighCount -gt 0) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = Get-DashboardText "deepScan.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "deepScan.readFailedLog")
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Start-ForensicsScan {
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "forensics.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $forensicsScript)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "forensics.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    $privacyChoice = [System.Windows.Forms.MessageBox]::Show(
        (Get-DashboardText "forensics.privacyPrompt"),
        (Get-DashboardText "forensics.privacyTitle"), "YesNoCancel", "Information")
    if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
    $privacyArgument = if ($privacyChoice -eq [System.Windows.Forms.DialogResult]::Yes) { " -RedactSensitive" } else { "" }
    try {
        Start-ProgressDisplay (Get-DashboardText "forensics.action") (Get-DashboardText "forensics.detail") $false
        Write-ProgressLog (Get-DashboardText "forensics.progressLog")
        Write-ProgressLog (Get-DashboardText "forensics.adminLog")
        Write-ProgressLog (Get-DashboardText "forensics.readOnlyLog")
        $script:forensicsDecisionFile = New-SecureRuntimePath "tool-license-forensics-"
        $output = New-ToolReportRunDirectory -Category "Quet-Forensics"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$forensicsScript`" -OutputDir `"$output`" -ApprovedKmsServerFile `"$approvedKmsFile`" -DecisionFile `"$script:forensicsDecisionFile`" -Culture `"$script:dashboardCulture`" -NoOpen$privacyArgument"
        [void](Start-ToolModuleProcess -ModuleId "forensics.scan" -Arguments $arguments -Action (Get-DashboardText "forensics.action") -Elevate -Hidden)
        $status.Text = Get-DashboardText "forensics.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "forensics.cancelled"
        Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-ForensicsScan {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:forensicsDecisionFile)) {
            throw (Get-DashboardText "forensics.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:forensicsDecisionFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:forensicsDecisionFile -Force -ErrorAction SilentlyContinue
        $script:forensicsDecisionFile = ""
        if ([bool]$result.AccessDenied) {
            $status.Text = Get-DashboardText "forensics.accessDeniedStatus"
            Write-ProgressLog (Get-DashboardText "common.noSystemChanges")
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            return
        }
        $message = Get-DashboardText "forensics.resultSummary" @($result.Overall, $result.RiskScore, $result.RiskLevel, $result.HighCount, $result.ReviewCount, $result.NewFindingCount, $result.ResolvedFindingCount, $result.EvidenceFolder)
        $icon = if ([int]$result.RiskScore -ge 40) { "Warning" } else { "Information" }
        [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "forensics.completedTitle"), "OK", $icon) | Out-Null
        [void](Open-ToolHtmlReport -Path ([string]$result.ReportPath))
        $status.Text = Get-DashboardText "forensics.completedStatus" @($result.RiskScore, $result.RiskLevel)
        Write-ProgressLog (Get-DashboardText "forensics.completedLog")
        $status.ForeColor = if ([int]$result.RiskScore -ge 40) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
    } catch {
        $status.Text = Get-DashboardText "forensics.readFailed" @($_.Exception.Message)
        Write-ProgressLog (Get-DashboardText "forensics.readFailedLog")
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
        $env:TOOL_UI_THEME = $script:dashboardTheme
        $launcherPath = [string]$env:TOOL_LAUNCHER_PATH
        if ($env:TOOL_SECURE_LAUNCH -eq "1" -and -not [string]::IsNullOrWhiteSpace($launcherPath) -and (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
            [void](Get-ReadyToolModule -moduleId "license.manager" -elevatedLaunch $true)
            $enterpriseProcess = Start-Process -FilePath $launcherPath -ArgumentList "--enterprise-ui" -Verb RunAs -PassThru
            if (-not $enterpriseProcess) { throw (Get-ToolText -Key "status.enterprise.launchFailed" -Culture $script:dashboardCulture) }
            [void](Write-ToolLog -Level "AUDIT" -Event "Module.Launched" -Message (Get-ToolText -Key "status.enterprise.action" -Culture $script:dashboardCulture) -Data ([ordered]@{
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
        $lettersOnly = $trimmed -replace '[^\p{L}]', ''
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
    $currentTitle = Get-DashboardText "document.overview"
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

        $documentRendererRevision = "2"
        $sourceHash = Get-ToolSha256Hex -Path $SourceFile
        $documentDirectory = Join-Path $reportRoot "TaiLieu"
        if (-not (Test-Path -LiteralPath $documentDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $documentDirectory -Force | Out-Null
        }
        $script:lastReportDirectory = $documentDirectory
        $documentBasePath = Join-Path $documentDirectory "$FilePrefix-v$releaseVersion-$($script:dashboardCulture)"
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
                throw (Get-DashboardText "document.offlineSafetyFailed")
            }
            $initialHashLines = @(
                "# SHA-256 local documentation package.",
                "# Source-SHA256: $sourceHash",
                "# Renderer-Revision: $documentRendererRevision",
                "$(Get-ToolSha256Hex -Path $htmlPath)  $([IO.Path]::GetFileName($htmlPath))"
            )
            [IO.File]::WriteAllLines($manifestPath, $initialHashLines, (New-Object Text.UTF8Encoding($false)))
        }

        [void](Open-ToolHtmlReport -Path $htmlPath)
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
    $selectedHistoryFile = if ($script:dashboardCulture -eq "en-US") { $englishHistoryFile } else { $historyFile }
    if (-not (Test-Path -LiteralPath $selectedHistoryFile -PathType Leaf)) {
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
        $historyBox.Text = [IO.File]::ReadAllText($selectedHistoryFile, [Text.Encoding]::UTF8)
        $dialog.Controls.Add($historyBox)

        $copyButton = New-Object System.Windows.Forms.Button
        $copyButton.Text = Get-ToolText -Key "history.copy" -Culture $script:dashboardCulture
        $copyButton.Size = New-Object System.Drawing.Size(230, 32)
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
    $status.Text = Get-DashboardText "advanced.cancelled"
    $status.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
}

function Start-CleanupBackup {
    param([ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All")
    $script:backupScope = $Scope
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "backup.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "backup.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    try {
        Start-ProgressDisplay (Get-DashboardText "backup.action") (Get-DashboardText "backup.detail") $true
        $output = New-ToolReportRunDirectory -Category "SaoLuu-BanQuyen"
        $script:backupResultFile = New-SecureRuntimePath "tool-license-backup-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$backupScript`" -OutputDir `"$output`" -DecisionFile `"$script:backupResultFile`" -Scope `"$script:backupScope`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "backup.create" -Arguments $arguments -Action (Get-DashboardText "backup.action") -Elevate)
        $status.Text = Get-DashboardText "backup.running"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        Write-ProgressLog (Get-DashboardText "backup.readOnlyLog")
        Write-ProgressLog (Get-DashboardText "backup.scopeLog" @((Get-CleanupScopeLabel -Scope $script:backupScope)))
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "backup.cancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-CleanupBackup {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:backupResultFile -PathType Leaf)) {
            throw (Get-DashboardText "backup.resultMissing")
        }
        $result = Get-Content -LiteralPath $script:backupResultFile -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $script:backupResultFile -Force -ErrorAction SilentlyContinue
        $script:backupResultFile = ""
        $message = Get-DashboardText "backup.resultSummary" @($result.Message, $result.ItemCount, $result.ErrorCount, $result.BackupDirectory)
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "backup.completedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "backup.completedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "backup.warningTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "backup.warningStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog (Get-DashboardText "backup.pathLog" @($result.BackupDirectory))
        Write-ProgressLog (Get-DashboardText "backup.securityLog")
        if ($result.ReportPath -and (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        $status.Text = Get-DashboardText "backup.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
    }
}

function Get-RestoreUiItemScope($Item) {
    $kind = [string]$Item.Kind
    $combined = "$kind|$([string]$Item.Name)|$([string]$Item.OriginalPath)"
    if ($kind -match '^ThirdParty' -or $combined -match '(?i)ThirdPartyInventory|InstalledSoftware') { return "ThirdParty" }
    if ($kind -match '^Office' -or $combined -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|Office_SPP') { return "Office" }
    if ($kind -match '^Windows' -or $combined -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|SppExtComObj|Windows_SPP|NoGenTicket') { return "Windows" }
    return "WindowsOfficeShared"
}

function Get-RestoreUiItemsForScope {
    param($Items, [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope)
    $allItems = @($Items)
    switch ($Scope) {
        "Windows" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -in @("Windows", "WindowsOfficeShared") }) }
        "Office" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -in @("Office", "WindowsOfficeShared") }) }
        "ThirdParty" { return @($allItems | Where-Object { (Get-RestoreUiItemScope $_) -eq "ThirdParty" }) }
        default { return $allItems }
    }
}

function Show-RestorePreview($manifest, [string]$backupDir, [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All") {
    $items = @(Get-RestoreUiItemsForScope -Items @($manifest.Items) -Scope $Scope)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = Get-DashboardText "restore.preview.title"
    $dialog.StartPosition = "CenterParent"
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(840, [Math]::Min(1100, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(560, [Math]::Min(680, $workArea.Height - 70))
    $dialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(840, $dialogWidth), [Math]::Min(560, $dialogHeight))
    $dialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $dialog.Font = $fontNormal
    $dialog.Tag = $false

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "restore.preview.heading" @($items.Count)
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.Location = New-Object System.Drawing.Point(18, 12)
    $heading.Size = New-Object System.Drawing.Size(($dialogWidth - 36), 36)
    $heading.TextAlign = "MiddleCenter"
    $heading.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($heading)

    $sourceLabel = New-Object System.Windows.Forms.Label
    $sourceLabel.Text = Get-DashboardText "restore.preview.source" @($backupDir)
    $sourceLabel.Location = New-Object System.Drawing.Point(20, 50)
    $sourceLabel.Size = New-Object System.Drawing.Size(($dialogWidth - 40), 24)
    $sourceLabel.AutoEllipsis = $true
    $sourceLabel.Anchor = "Top,Left,Right"
    $dialog.Controls.Add($sourceLabel)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    $list.ShowItemToolTips = $true
    $list.Location = New-Object System.Drawing.Point(20, 78)
    $list.Size = New-Object System.Drawing.Size(($dialogWidth - 40), ($dialogHeight - 170))
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add((Get-DashboardText "common.type"), 125)
    [void]$list.Columns.Add((Get-DashboardText "common.name"), 220)
    [void]$list.Columns.Add((Get-DashboardText "restore.preview.originalLocation"), 390)
    [void]$list.Columns.Add((Get-DashboardText "restore.preview.handling"), 140)
    $resizeRestoreColumns = {
        $usable = [Math]::Max(620, $list.ClientSize.Width - 8)
        $list.Columns[0].Width = 125
        $list.Columns[1].Width = [Math]::Max(220, [Math]::Floor(($usable - 265) * 0.34))
        $list.Columns[3].Width = 140
        $list.Columns[2].Width = [Math]::Max(260, $usable - $list.Columns[0].Width - $list.Columns[1].Width - $list.Columns[3].Width)
    }
    $list.Add_Resize($resizeRestoreColumns)
    foreach ($item in $items) {
        $explicitlyNotRestorable = [bool]($item.PSObject.Properties['Restorable'] -and -not [bool]$item.Restorable)
        $action = if ($explicitlyNotRestorable) { Get-DashboardText "restore.preview.notRestorable" } elseif ([string]$item.Type -eq "Defender") { Get-DashboardText "restore.preview.safeSkip" } elseif ([string]$item.Type -eq "LicenseNotice") { Get-DashboardText "restore.preview.notRestorable" } else { Get-DashboardText "restore.preview.restorable" }
        $row = New-Object System.Windows.Forms.ListViewItem([string]$item.Type)
        [void]$row.SubItems.Add([string]$item.Name)
        [void]$row.SubItems.Add([string]$item.OriginalPath)
        [void]$row.SubItems.Add($action)
        $row.ToolTipText = "$([string]$item.Name)`r`n$([string]$item.OriginalPath)`r`n$action"
        [void]$list.Items.Add($row)
    }
    $dialog.Controls.Add($list)
    & $resizeRestoreColumns

    $note = New-Object System.Windows.Forms.Label
    $note.Text = Get-DashboardText "restore.preview.note"
    $note.Location = New-Object System.Drawing.Point(20, ($dialogHeight - 82))
    $note.Size = New-Object System.Drawing.Size(($dialogWidth - 350), 64)
    $note.Anchor = "Bottom,Left,Right"
    $dialog.Controls.Add($note)

    $confirm = New-Object System.Windows.Forms.Button
    $confirm.Text = Get-DashboardText "restore.preview.confirm"
    $confirm.Font = $fontBold
    $confirm.Location = New-Object System.Drawing.Point(($dialogWidth - 316), ($dialogHeight - 58))
    $confirm.Size = New-Object System.Drawing.Size(188, 38)
    $confirm.Anchor = "Bottom,Right"
    $confirm.Add_Click({ $dialog.Tag = $true; $dialog.Close() })
    $dialog.Controls.Add($confirm)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = Get-DashboardText "common.close"
    $cancel.Location = New-Object System.Drawing.Point(($dialogWidth - 120), ($dialogHeight - 58))
    $cancel.Size = New-Object System.Drawing.Size(104, 38)
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
    param([ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$Scope = "All")
    $script:restoreScope = $Scope
    if (-not (Confirm-IntegrityForElevatedAction (Get-DashboardText "restore.integrityAction"))) { return }
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.moduleMissing"), (Get-DashboardText "common.errorTitle"), "OK", "Error") | Out-Null
        return
    }
    $picker = New-Object System.Windows.Forms.FolderBrowserDialog
    $picker.Description = Get-DashboardText "restore.pickerDescription"
    $picker.ShowNewFolderButton = $false
    $dataRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) { [string]$env:TOOL_DATA_ROOT } else { Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.6" }
    $secureBackupRoot = Join-Path $dataRoot "backups"
    if (Test-Path -LiteralPath $secureBackupRoot -PathType Container) { $picker.SelectedPath = $secureBackupRoot }
    if ($picker.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        $picker.Dispose()
        return
    }
    $backupDir = $picker.SelectedPath
    $picker.Dispose()
    $manifestPath = Join-Path $backupDir "RESTORE-MANIFEST.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.manifestMissing"), (Get-DashboardText "restore.invalidFolderTitle"), "OK", "Warning") | Out-Null
        return
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $scopedRestoreItems = @(Get-RestoreUiItemsForScope -Items @($manifest.Items) -Scope $script:restoreScope)
        $itemCount = $scopedRestoreItems.Count
        if ([string]$manifest.SchemaVersion -ne "2.0" -or [string]$manifest.ToolVersion -ne $toolVersion) { throw (Get-DashboardText "restore.versionMismatch" @($toolVersion)) }
    } catch {
        $manifestError = Get-DashboardText "restore.manifestInvalid" @($_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($manifestError, (Get-DashboardText "restore.manifestInvalidTitle"), "OK", "Error") | Out-Null
        return
    }
    if ($itemCount -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.noItems"), (Get-DashboardText "restore.noItemsTitle"), "OK", "Information") | Out-Null
        return
    }
    if (-not (Show-RestorePreview -manifest $manifest -backupDir $backupDir -Scope $script:restoreScope)) { return }

    try {
        Start-ProgressDisplay (Get-DashboardText "restore.action") (Get-DashboardText "restore.detail") $true
        $script:restoreResultFile = New-SecureRuntimePath "tool-license-restore-result-"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`" -BackupDir `"$backupDir`" -DecisionFile `"$script:restoreResultFile`" -Scope `"$script:restoreScope`" -Culture `"$script:dashboardCulture`""
        [void](Start-ToolModuleProcess -ModuleId "restore.apply" -Arguments $arguments -Action (Get-DashboardText "restore.action") -Elevate)
        $status.Text = Get-DashboardText "restore.running"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
        Write-ProgressLog (Get-DashboardText "restore.runningLog" @($itemCount, $backupDir))
        Write-ProgressLog (Get-DashboardText "restore.scopeLog" @((Get-CleanupScopeLabel -Scope $script:restoreScope)))
        Set-ButtonsEnabled $false
        $timer.Start()
    } catch {
        Set-ButtonsEnabled $true
        $status.Text = Get-DashboardText "restore.cancelled"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Stop-ProgressDisplay $status.Text
    }
}

function Complete-CleanupRestore {
    Set-ButtonsEnabled $true
    try {
        if (-not (Test-Path -LiteralPath $script:restoreResultFile -PathType Leaf)) {
            throw (Get-DashboardText "restore.resultMissing")
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
        $restoreNextStep = if ([int]$result.ErrorCount -gt 0) { Get-DashboardText "restore.failureNextStep" } else { Get-DashboardText "restore.successNextStep" }
        $message = Get-DashboardText "restore.resultSummary" @($result.Message, $result.RestoredCount, $result.SkippedCount, $result.ErrorCount, $restoreNextStep, $result.ReportPath)
        if ([bool]$result.Success) {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "restore.completedTitle"), "OK", "Information") | Out-Null
            $status.Text = Get-DashboardText "restore.completedStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show($message, (Get-DashboardText "restore.warningTitle"), "OK", "Warning") | Out-Null
            $status.Text = Get-DashboardText "restore.warningStatus"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        Write-ProgressLog $message
        if (Test-Path -LiteralPath $result.ReportPath) {
            Register-ToolReportPath -Path ([string]$result.ReportPath)
            Write-ProgressLog (Get-DashboardText "cleanup.report.readyOnDemand" @($result.ReportPath))
        }
    } catch {
        $status.Text = Get-DashboardText "restore.readFailed" @($_.Exception.Message)
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        Write-ProgressLog $status.Text
        Write-ProgressLog (Get-DashboardText "restore.failureGuidance")
        [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "restore.failureMessage" @($status.Text)), (Get-DashboardText "restore.failureTitle"), "OK", "Error") | Out-Null
    }
}

function Show-CleanupScopeChecklist {
    $scopeDialog = New-Object System.Windows.Forms.Form
    $scopeDialog.Text = Get-DashboardText "cleanup.scope.dialogTitle"
    $scopeDialog.StartPosition = "CenterParent"
    $scopeDialog.FormBorderStyle = "Sizable"
    $scopeDialog.MaximizeBox = $false
    $scopeDialog.MinimizeBox = $false
    $scopeDialog.ShowInTaskbar = $false
    $scopeDialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dialogWidth = [Math]::Max(680, [Math]::Min(820, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(430, [Math]::Min(470, $workArea.Height - 70))
    $scopeDialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $dialogWidth), [Math]::Min(430, $dialogHeight))
    $scopeDialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $scopeDialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $scopeDialog.Font = $fontNormal
    $scopeDialog.Tag = ""

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 6
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    foreach ($unused in 1..3) {
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68)))
    }
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $scopeDialog.Controls.Add($layout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText "cleanup.scope.cleanupHeading"
    $heading.Dock = "Fill"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $layout.Controls.Add($heading, 0, 0)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText "cleanup.scope.cleanupHint"
    $hint.Dock = "Fill"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleLeft"
    $layout.Controls.Add($hint, 0, 1)

    $checkDefinitions = @(
        [pscustomobject]@{ Name="Windows"; TextKey="cleanup.scope.scanWindows" },
        [pscustomobject]@{ Name="Office"; TextKey="cleanup.scope.scanOffice" },
        [pscustomobject]@{ Name="ThirdParty"; TextKey="cleanup.scope.scanThirdParty" }
    )
    $scopeChecks = @{}
    [int]$rowIndex = 2
    foreach ($definition in $checkDefinitions) {
        $scopeCheck = New-Object System.Windows.Forms.CheckBox
        $scopeCheck.Name = "cleanupScope$([string]$definition.Name)"
        $scopeCheck.Text = Get-DashboardText ([string]$definition.TextKey)
        $scopeCheck.Tag = [string]$definition.Name
        $scopeCheck.Dock = "Fill"
        $scopeCheck.Margin = New-Object System.Windows.Forms.Padding(16, 5, 16, 5)
        $scopeCheck.Padding = New-Object System.Windows.Forms.Padding(16, 0, 12, 0)
        $scopeCheck.Font = $fontBold
        $scopeCheck.TextAlign = "MiddleLeft"
        $scopeCheck.CheckAlign = "MiddleLeft"
        $scopeCheck.AutoCheck = $true
        $scopeCheck.ThreeState = $false
        $scopeChecks[[string]$definition.Name] = $scopeCheck
        $layout.Controls.Add($scopeCheck, 0, $rowIndex)
        $rowIndex++
    }

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)
    $layout.Controls.Add($footer, 0, 5)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "common.back"
    $cancelButton.Font = $fontBold
    $cancelButton.Size = New-Object System.Drawing.Size(132, 38)
    $cancelButton.Add_Click({ $scopeDialog.Close() })
    $scopeDialog.CancelButton = $cancelButton
    $footer.Controls.Add($cancelButton)

    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Text = Get-DashboardText "common.continue"
    $continueButton.Font = $fontBold
    $continueButton.Size = New-Object System.Drawing.Size(156, 38)
    $continueButton.Enabled = $false
    $continueButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $continueButton.Add_Click({
        $scopeDialog.Tag = ConvertTo-CleanupScanScope `
            -Windows ([bool]$scopeChecks['Windows'].Checked) `
            -Office ([bool]$scopeChecks['Office'].Checked) `
            -ThirdParty ([bool]$scopeChecks['ThirdParty'].Checked)
        if (-not [string]::IsNullOrWhiteSpace([string]$scopeDialog.Tag)) { $scopeDialog.Close() }
    })
    $footer.Controls.Add($continueButton)
    $scopeDialog.AcceptButton = $continueButton

    $updateContinueState = {
        $continueButton.Enabled = [bool]($scopeChecks['Windows'].Checked -or $scopeChecks['Office'].Checked -or $scopeChecks['ThirdParty'].Checked)
    }
    foreach ($scopeCheck in $scopeChecks.Values) { $scopeCheck.Add_CheckedChanged($updateContinueState) }

    Set-ToolWindowTheme -Root $scopeDialog -Mode $script:dashboardTheme
    $scopeDialog.Add_Shown({ $scopeChecks['Windows'].Focus() })
    [void]$scopeDialog.ShowDialog($form)
    $scope = [string]$scopeDialog.Tag
    $scopeDialog.Dispose()
    return $scope
}

function Show-LicenseScopeChooser {
    param([ValidateSet("Cleanup", "Backup", "Restore")][string]$Mode)

    if ($Mode -eq "Cleanup") { return Show-CleanupScopeChecklist }

    $options = if ($Mode -eq "Backup") {
        @(
            [pscustomobject]@{ Scope="All"; TextKey="cleanup.scope.backupAll" },
            [pscustomobject]@{ Scope="Windows"; TextKey="cleanup.scope.backupWindows" },
            [pscustomobject]@{ Scope="Office"; TextKey="cleanup.scope.backupOffice" },
            [pscustomobject]@{ Scope="ThirdParty"; TextKey="cleanup.scope.backupThirdParty" }
        )
    } else {
        @(
            [pscustomobject]@{ Scope="All"; TextKey="cleanup.scope.restoreAll" },
            [pscustomobject]@{ Scope="Windows"; TextKey="cleanup.scope.restoreWindows" },
            [pscustomobject]@{ Scope="Office"; TextKey="cleanup.scope.restoreOffice" },
            [pscustomobject]@{ Scope="ThirdParty"; TextKey="cleanup.scope.restoreThirdParty" }
        )
    }
    $headingKey = "cleanup.scope.$($Mode.ToLowerInvariant())Heading"
    $hintKey = "cleanup.scope.$($Mode.ToLowerInvariant())Hint"

    $scopeDialog = New-Object System.Windows.Forms.Form
    $scopeDialog.Text = Get-DashboardText "cleanup.scope.dialogTitle"
    $scopeDialog.StartPosition = "CenterParent"
    $scopeDialog.FormBorderStyle = "Sizable"
    $scopeDialog.MaximizeBox = $false
    $scopeDialog.MinimizeBox = $false
    $scopeDialog.ShowInTaskbar = $false
    $scopeDialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $desiredHeight = 226 + ($options.Count * 66)
    $dialogWidth = [Math]::Max(680, [Math]::Min(820, $workArea.Width - 70))
    $dialogHeight = [Math]::Max(410, [Math]::Min($desiredHeight, $workArea.Height - 70))
    $scopeDialog.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $dialogWidth), [Math]::Min(410, $dialogHeight))
    $scopeDialog.ClientSize = New-Object System.Drawing.Size($dialogWidth, $dialogHeight)
    $scopeDialog.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $scopeDialog.Font = $fontNormal
    $scopeDialog.Tag = ""

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
    $layout.ColumnCount = 1
    $layout.RowCount = 3 + $options.Count
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    foreach ($unused in $options) {
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    }
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $scopeDialog.Controls.Add($layout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $headingKey
    $heading.Dock = "Fill"
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $layout.Controls.Add($heading, 0, 0)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = Get-DashboardText $hintKey
    $hint.Dock = "Fill"
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $hint.TextAlign = "MiddleLeft"
    $layout.Controls.Add($hint, 0, 1)

    $optionIndex = 0
    foreach ($option in $options) {
        $scopeButton = New-Object System.Windows.Forms.Button
        $scopeButton.Text = Get-DashboardText ([string]$option.TextKey)
        $scopeButton.Tag = [string]$option.Scope
        $scopeButton.Dock = "Fill"
        $scopeButton.Margin = New-Object System.Windows.Forms.Padding(16, 5, 16, 5)
        $scopeButton.Font = $fontBold
        $scopeButton.TextAlign = "MiddleLeft"
        $scopeButton.Add_Click({
            param($sender, $eventArgs)
            $scopeDialog.Tag = [string]$sender.Tag
            $scopeDialog.Close()
        })
        $layout.Controls.Add($scopeButton, 0, (2 + $optionIndex))
        $optionIndex++
    }

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.AutoScroll = $true
    $footer.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)
    $layout.Controls.Add($footer, 0, (2 + $options.Count))

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = Get-DashboardText "common.back"
    $cancelButton.Font = $fontBold
    $cancelButton.Size = New-Object System.Drawing.Size(132, 38)
    $cancelButton.Add_Click({ $scopeDialog.Close() })
    $scopeDialog.CancelButton = $cancelButton
    $footer.Controls.Add($cancelButton)

    Set-ToolWindowTheme -Root $scopeDialog -Mode $script:dashboardTheme
    [void]$scopeDialog.ShowDialog($form)
    $scope = [string]$scopeDialog.Tag
    $scopeDialog.Dispose()
    return $scope
}

function Show-CleanupFunctionScreen {
    param([ValidateSet("Backup","Cleanup","Restore","AutoCleanup")][string]$Mode)
    $titleKeys = @{
        Backup="cleanup.menu.backupTitle"
        Cleanup="cleanup.menu.cleanupTitle"
        Restore="cleanup.menu.restoreTitle"
        AutoCleanup="cleanup.menu.autoTitle"
    }
    $descriptionKeys = @{
        Backup="cleanup.menu.backupDescription"
        Cleanup="cleanup.menu.cleanupDescription"
        Restore="cleanup.menu.restoreDescription"
        AutoCleanup="cleanup.menu.autoDescription"
    }
    $actionKeys = @{ Backup="cleanup.menu.backupAction"; Cleanup="cleanup.menu.cleanupAction"; Restore="cleanup.menu.restoreAction"; AutoCleanup="cleanup.menu.autoAction" }

    $screen = New-Object System.Windows.Forms.Form
    $screen.Text = Get-DashboardText $titleKeys[$Mode]
    $screen.StartPosition = "CenterParent"
    $screen.FormBorderStyle = "Sizable"
    $screen.MaximizeBox = $false
    $screen.MinimizeBox = $false
    $screen.ShowInTaskbar = $false
    $screen.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $screenWidth = [Math]::Max(680, [Math]::Min(780, $workArea.Width - 70))
    $screenHeight = [Math]::Max(320, [Math]::Min(380, $workArea.Height - 70))
    $screen.MinimumSize = New-Object System.Drawing.Size([Math]::Min(680, $screenWidth), [Math]::Min(320, $screenHeight))
    $screen.ClientSize = New-Object System.Drawing.Size($screenWidth, $screenHeight)
    $screen.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
    $screen.Font = $fontNormal
    $screen.Tag = "Back"

    $screenLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $screenLayout.Dock = "Fill"
    $screenLayout.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 14)
    $screenLayout.ColumnCount = 1
    $screenLayout.RowCount = 3
    [void]$screenLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 62)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$screenLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    $screen.Controls.Add($screenLayout)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-DashboardText $titleKeys[$Mode]
    $heading.Font = $fontTitle
    $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
    $heading.TextAlign = "MiddleCenter"
    $heading.Dock = "Fill"
    $screenLayout.Controls.Add($heading, 0, 0)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-DashboardText $descriptionKeys[$Mode]
    $descriptionLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
    $descriptionLabel.TextAlign = "MiddleLeft"
    $descriptionLabel.Dock = "Fill"
    $descriptionLabel.Padding = New-Object System.Windows.Forms.Padding(18, 8, 18, 8)
    $screenLayout.Controls.Add($descriptionLabel, 0, 1)

    $footer = New-Object System.Windows.Forms.FlowLayoutPanel
    $footer.Dock = "Fill"
    $footer.FlowDirection = "RightToLeft"
    $footer.WrapContents = $false
    $footer.AutoScroll = $true
    $footer.Padding = if ($Mode -eq "Cleanup") {
        New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
    } else {
        New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
    }
    $screenLayout.Controls.Add($footer, 0, 2)

    $compactCleanupButtonWidth = 90

    $backButton = New-Object System.Windows.Forms.Button
    $backButton.Text = Get-DashboardText "common.back"
    $backButton.Font = $fontTile
    $backButton.Size = New-Object System.Drawing.Size($(if ($Mode -eq "Cleanup") { $compactCleanupButtonWidth } else { 132 }), 40)
    $backButton.Add_Click({ $screen.Tag = "Back"; $screen.Close() })
    $screen.CancelButton = $backButton
    $footer.Controls.Add($backButton)

    $actionButton = New-Object System.Windows.Forms.Button
    $actionButton.Text = Get-DashboardText $actionKeys[$Mode]
    $actionButton.Font = $fontTile
    $actionButton.Size = New-Object System.Drawing.Size($(if ($Mode -eq "Cleanup") { $compactCleanupButtonWidth } else { 250 }), 40)
    $actionButton.BackColor = [System.Drawing.Color]::FromArgb(234, 242, 255)
    $actionButton.Add_Click({ $screen.Tag = "Action"; $screen.Close() })
    $footer.Controls.Add($actionButton)

    if ($Mode -eq "Cleanup") {
        $dryRunButton = New-Object System.Windows.Forms.Button
        $dryRunButton.Text = Get-DashboardText 'cleanup.dryRun.button'
        $dryRunButton.Font = $fontTile
        $dryRunButton.Size = New-Object System.Drawing.Size($compactCleanupButtonWidth, 40)
        $dryRunButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 230)
        $dryRunButton.Add_Click({ $screen.Tag = 'DryRun'; $screen.Close() })
        $footer.Controls.Add($dryRunButton)

        $onlineButton = New-Object System.Windows.Forms.Button
        $onlineButton.Text = Get-DashboardText "software.online.button"
        $onlineButton.Font = $fontTile
        $onlineButton.Size = New-Object System.Drawing.Size($compactCleanupButtonWidth, 40)
        $onlineButton.BackColor = [System.Drawing.Color]::FromArgb(232, 247, 240)
        $onlineButton.Add_Click({ $screen.Tag = "Online"; $screen.Close() })
        $footer.Controls.Add($onlineButton)
    }

    Set-ToolWindowTheme -Root $screen -Mode $script:dashboardTheme
    if ($Mode -eq "Cleanup") {
        Set-ToolUiFlowButtonSpacing -Panel $footer -PreferredSideMargin 3
        $footer.Add_SizeChanged({
            param($sender, $eventArgs)
            Set-ToolUiFlowButtonSpacing -Panel $sender -PreferredSideMargin 3
        })
    }
    [void]$screen.ShowDialog($form)
    $choice = [string]$screen.Tag
    $screen.Dispose()
    if ($choice -notin @("Action", "DryRun", "Online")) { return $false }

    if ($Mode -eq "AutoCleanup") {
        Start-Cleanup -AutoSafeMode -ScanScope "All"
        return $true
    }
    $scopeMode = if ($Mode -eq "Cleanup") { "Cleanup" } elseif ($Mode -eq "Backup") { "Backup" } else { "Restore" }
    $selectedScope = Show-LicenseScopeChooser -Mode $scopeMode
    if ([string]::IsNullOrWhiteSpace($selectedScope)) { return $false }
    if ($Mode -eq "Cleanup" -and $choice -eq "Online") { Start-SoftwareCatalogOnlineUpdate -ScanScope $selectedScope }
    elseif ($Mode -eq "Backup") { Start-CleanupBackup -Scope $selectedScope }
    elseif ($Mode -eq "Cleanup") { Start-Cleanup -ScanScope $selectedScope -DryRunMode:([bool]($choice -eq 'DryRun')) }
    elseif ($Mode -eq "Restore") { Start-CleanupRestore -Scope $selectedScope }
    return $true
}

function Show-CleanupMenu {
    while ($true) {
        $chooser = New-Object System.Windows.Forms.Form
        $chooser.Text = Get-DashboardText "cleanup.menu.title"
        $chooser.StartPosition = "CenterParent"
        $chooser.FormBorderStyle = "Sizable"
        $chooser.MaximizeBox = $false
        $chooser.MinimizeBox = $false
        $chooser.ShowInTaskbar = $false
        $chooser.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        $chooserWidth = [Math]::Max(700, [Math]::Min(820, $workArea.Width - 70))
        $chooserHeight = [Math]::Max(470, [Math]::Min(540, $workArea.Height - 70))
        $chooser.MinimumSize = New-Object System.Drawing.Size([Math]::Min(700, $chooserWidth), [Math]::Min(470, $chooserHeight))
        $chooser.ClientSize = New-Object System.Drawing.Size($chooserWidth, $chooserHeight)
        $chooser.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
        $chooser.Font = $fontNormal
        $chooser.Tag = ""

        $layout = New-Object System.Windows.Forms.TableLayoutPanel
        $layout.Dock = "Fill"
        $layout.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
        $layout.ColumnCount = 1
        $layout.RowCount = 6
        [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 82)))
        foreach ($unused in 1..4) { [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66))) }
        [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $chooser.Controls.Add($layout)

        $heading = New-Object System.Windows.Forms.Label
        $heading.Text = Get-DashboardText "cleanup.menu.heading"
        $heading.Font = $fontTitle
        $heading.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
        $heading.TextAlign = "MiddleCenter"
        $heading.Dock = "Fill"
        $layout.Controls.Add($heading, 0, 0)

        $menuOptions = @(
            [pscustomobject]@{ Code="Backup"; TextKey="cleanup.menu.backupTitle"; Color=[System.Drawing.Color]::FromArgb(232, 247, 240) },
            [pscustomobject]@{ Code="Cleanup"; TextKey="cleanup.menu.cleanupFullTitle"; Color=[System.Drawing.Color]::FromArgb(255, 248, 230) },
            [pscustomobject]@{ Code="Restore"; TextKey="cleanup.menu.restoreTitle"; Color=[System.Drawing.Color]::FromArgb(234, 242, 255) },
            [pscustomobject]@{ Code="AutoCleanup"; TextKey="cleanup.menu.autoFullTitle"; Color=[System.Drawing.Color]::FromArgb(255, 238, 238) }
        )
        $menuIndex = 0
        foreach ($menuOption in $menuOptions) {
            $menuButton = New-Object System.Windows.Forms.Button
            $menuButton.Text = Get-DashboardText ([string]$menuOption.TextKey)
            $menuButton.Tag = [string]$menuOption.Code
            $menuButton.Font = $fontBold
            $menuButton.TextAlign = "MiddleLeft"
            $menuButton.Dock = "Fill"
            $menuButton.Margin = New-Object System.Windows.Forms.Padding(18, 5, 18, 5)
            $menuButton.BackColor = $menuOption.Color
            $menuButton.Add_Click({
                param($sender, $eventArgs)
                $chooser.Tag = [string]$sender.Tag
                $chooser.Close()
            })
            $layout.Controls.Add($menuButton, 0, (1 + $menuIndex))
            $menuIndex++
        }

        $footer = New-Object System.Windows.Forms.FlowLayoutPanel
        $footer.Dock = "Fill"
        $footer.FlowDirection = "RightToLeft"
        $footer.WrapContents = $false
        $footer.Padding = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)
        $layout.Controls.Add($footer, 0, 5)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = Get-DashboardText "common.back"
        $cancelButton.Font = $fontBold
        $cancelButton.Size = New-Object System.Drawing.Size(132, 40)
        $cancelButton.Add_Click({ $chooser.Close() })
        $chooser.CancelButton = $cancelButton
        $footer.Controls.Add($cancelButton)

        Set-ToolWindowTheme -Root $chooser -Mode $script:dashboardTheme
        [void]$chooser.ShowDialog($form)
        $choice = [string]$chooser.Tag
        $chooser.Dispose()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $status.Text = Get-DashboardText "status.chooseTask"
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
        $output = New-ToolReportRunDirectory -Category "BaoDam-$Operation"
        $arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$assuranceScript`" -Operation `"$Operation`" -OutputDir `"$output`" -Culture `"$script:dashboardCulture`" -Pdf$redactArgument"
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
        $picker.Title = Get-DashboardText "plugin.pickerTitle"
        $picker.Filter = Get-DashboardText "plugin.pickerFilter"
        $picker.Multiselect = $false
        if ($picker.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $package = Read-ToolPluginPackage -Path $picker.FileName -AllowOutsideProtectedDirectory
        if (-not $package.Valid) { throw ($package.Errors -join "`r`n") }
        $plugin = $package.Plugin
        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            (Get-DashboardText "plugin.installPrompt" @($plugin.Name, $plugin.PluginId, $plugin.Version, $plugin.Publisher, @($plugin.Rules).Count, $package.Sha256)),
            (Get-DashboardText "plugin.confirmTitle"),
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $destination = Join-Path $directoryState.Path "$([string]$plugin.PluginId).plugin.json"
        $force = $false
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                (Get-DashboardText "plugin.overwritePrompt"),
                (Get-DashboardText "plugin.existsTitle"), "YesNo", "Warning")
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
            (Get-DashboardText "plugin.installedMessage" @($installed.Path, $installed.Sha256)),
            (Get-DashboardText "plugin.installedTitle"), "OK", "Information") | Out-Null
        Write-ProgressLog (Get-DashboardText "plugin.installedLog" @($installed.PluginId, $installed.Version))
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (Get-DashboardText "plugin.failedTitle"), "OK", "Error") | Out-Null
        Write-ProgressLog (Get-DashboardText "plugin.rejectedLog" @($_.Exception.Message))
    }
}

function Invoke-AssuranceCenterAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Certificate", "PluginAudit", "Timeline", "InstallPlugin", "PluginFolder", "Guide", "History")]
        [string]$Choice
    )

    switch ($Choice) {
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
    $heading.ForeColor = $script:baseUiPalette.Primary
    $descriptionLabel.ForeColor = $script:baseUiPalette.Text
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    if (-not [string]::IsNullOrWhiteSpace($choice)) { Invoke-AssuranceCenterAction -Choice $choice }
}

function Get-DashboardMenuIconKind([int]$Number) {
    switch ($Number) {
        1 { return "Search" }
        2 { return "Hardware" }
        3 { return "Windows" }
        4 { return "Office" }
        5 { return "Software" }
        6 { return "Repair" }
        7 { return "Key" }
        8 { return "License" }
        9 { return "DeepScan" }
        10 { return "Report" }
        default { return "Search" }
    }
}

function Add-MenuButton([int]$number, [string]$titleKey, [string]$descriptionKey, [int]$index, [scriptblock]$action, [bool]$warning) {
    $button = New-Object System.Windows.Forms.Button
    $metadata = [pscustomobject][ordered]@{
        Kind = "QuickAction"
        Number = $number
        TitleKey = $titleKey
        DescriptionKey = $descriptionKey
        Tone = if ($number -eq 8) { "Enterprise" } elseif ($warning) { "Warning" } else { "Normal" }
        IconKind = Get-DashboardMenuIconKind -Number $number
        TitleLabel = $null
        DescriptionLabel = $null
    }
    $button.Text = ""
    $button.Font = $fontTile
    $button.ImageAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 10, 0)
    $row = [Math]::Floor($index / 2)
    $column = $index % 2
    $button.Location = New-Object System.Drawing.Point((14 + ($column * 420)), (34 + ($row * 58)))
    $button.Size = New-Object System.Drawing.Size(410, 50)
    $menuIconImage = New-DashboardTileIconBitmap -Kind ([string]$metadata.IconKind) -IconSize 32 -RightGap 12
    [void]$dashboardIconImages.Add($menuIconImage)
    $button.Image = $menuIconImage
    $initialTilePalette = Get-DashboardTilePalette -Tone ([string]$metadata.Tone) -Mode $script:dashboardTheme
    $button.BackColor = $initialTilePalette.BackColor
    $button.ForeColor = $initialTilePalette.ForeColor
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $metadata
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $titleLabel.Font = $fontBold
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.ForeColor = $initialTilePalette.TitleColor
    $titleLabel.AutoEllipsis = $true
    $titleLabel.UseCompatibleTextRendering = $false
    $titleLabel.UseMnemonic = $false
    $titleLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleLabel.Location = New-Object System.Drawing.Point(60, 4)
    $titleLabel.Size = New-Object System.Drawing.Size(334, 20)
    $titleLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $titleLabel.Add_MouseEnter({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme -Hover).BackColor } })
    $titleLabel.Add_MouseLeave({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme).BackColor } })
    $button.Controls.Add($titleLabel)
    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $descriptionLabel.Font = $fontSupportSmall
    $descriptionLabel.BackColor = [System.Drawing.Color]::Transparent
    $descriptionLabel.ForeColor = $initialTilePalette.DescriptionColor
    $descriptionLabel.AutoEllipsis = $true
    $descriptionLabel.UseCompatibleTextRendering = $false
    $descriptionLabel.UseMnemonic = $false
    $descriptionLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $descriptionLabel.Location = New-Object System.Drawing.Point(60, 24)
    $descriptionLabel.Size = New-Object System.Drawing.Size(334, 19)
    $descriptionLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $descriptionLabel.Add_MouseEnter({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme -Hover).BackColor } })
    $descriptionLabel.Add_MouseLeave({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.BackColor = (Get-DashboardTilePalette -Tone ([string]$sender.Parent.Tag.Tone) -Mode $script:dashboardTheme).BackColor } })
    $button.Controls.Add($descriptionLabel)
    $metadata.TitleLabel = $titleLabel
    $metadata.DescriptionLabel = $descriptionLabel
    $button.AccessibleName = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $button.AccessibleDescription = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
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

function Add-ReportMenuButton([string]$actionId, [string]$titleKey, [string]$descriptionKey, [int]$index, [string]$iconKind) {
    $button = New-Object System.Windows.Forms.Button
    $metadata = [pscustomobject][ordered]@{
        Kind = "ReportAction"
        Number = 0
        ActionId = $actionId
        TitleKey = $titleKey
        DescriptionKey = $descriptionKey
        Tone = "Normal"
        IconKind = $iconKind
        TitleLabel = $null
        DescriptionLabel = $null
    }
    $button.Text = ""
    $button.Font = $fontTile
    $button.ImageAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 10, 0)
    $button.UseMnemonic = $false
    $row = [Math]::Floor($index / 2)
    $column = $index % 2
    $button.Location = New-Object System.Drawing.Point((14 + ($column * 420)), (34 + ($row * 58)))
    $button.Size = New-Object System.Drawing.Size(410, 50)
    $menuIconImage = New-DashboardTileIconBitmap -Kind $iconKind -IconSize 32 -RightGap 12
    [void]$dashboardIconImages.Add($menuIconImage)
    $button.Image = $menuIconImage
    $initialTilePalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
    $button.BackColor = $initialTilePalette.BackColor
    $button.ForeColor = $initialTilePalette.ForeColor
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $metadata
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $titleLabel.Font = $fontBold
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.ForeColor = $initialTilePalette.TitleColor
    $titleLabel.AutoEllipsis = $true
    $titleLabel.UseCompatibleTextRendering = $false
    $titleLabel.UseMnemonic = $false
    $titleLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleLabel.Location = New-Object System.Drawing.Point(60, 4)
    $titleLabel.Size = New-Object System.Drawing.Size(334, 20)
    $titleLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $button.Controls.Add($titleLabel)
    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $descriptionLabel.Font = $fontSupportSmall
    $descriptionLabel.BackColor = [System.Drawing.Color]::Transparent
    $descriptionLabel.ForeColor = $initialTilePalette.DescriptionColor
    $descriptionLabel.AutoEllipsis = $true
    $descriptionLabel.UseCompatibleTextRendering = $false
    $descriptionLabel.UseMnemonic = $false
    $descriptionLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $descriptionLabel.Location = New-Object System.Drawing.Point(60, 24)
    $descriptionLabel.Size = New-Object System.Drawing.Size(334, 19)
    $descriptionLabel.Add_Click({ param($sender, $eventArgs); if ($sender.Parent) { $sender.Parent.PerformClick() } })
    $button.Controls.Add($descriptionLabel)
    foreach ($label in @($titleLabel, $descriptionLabel)) {
        $label.Add_MouseEnter({
            param($sender, $eventArgs)
            if ($sender.Parent) {
                $palette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme -Hover
                $sender.Parent.BackColor = $palette.BackColor
                $sender.Parent.Tag.TitleLabel.ForeColor = $palette.TitleColor
                $sender.Parent.Tag.DescriptionLabel.ForeColor = $palette.DescriptionColor
            }
        })
        $label.Add_MouseLeave({
            param($sender, $eventArgs)
            if ($sender.Parent) {
                $palette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
                $sender.Parent.BackColor = $palette.BackColor
                $sender.Parent.Tag.TitleLabel.ForeColor = $palette.TitleColor
                $sender.Parent.Tag.DescriptionLabel.ForeColor = $palette.DescriptionColor
            }
        })
    }
    $metadata.TitleLabel = $titleLabel
    $metadata.DescriptionLabel = $descriptionLabel
    $button.AccessibleName = Get-ToolText -Key $titleKey -Culture $script:dashboardCulture
    $button.AccessibleDescription = Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture
    $button.Visible = $false
    $button.Add_Click({
        param($sender, $eventArgs)
        Invoke-AssuranceCenterAction -Choice ([string]$sender.Tag.ActionId)
    })
    $button.Add_MouseEnter({
        param($sender, $eventArgs)
        $hoverPalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme -Hover
        $sender.BackColor = $hoverPalette.BackColor
        $sender.ForeColor = $hoverPalette.ForeColor
        if ($sender.Tag.TitleLabel) { $sender.Tag.TitleLabel.ForeColor = $hoverPalette.TitleColor }
        if ($sender.Tag.DescriptionLabel) { $sender.Tag.DescriptionLabel.ForeColor = $hoverPalette.DescriptionColor }
    })
    $button.Add_MouseLeave({
        param($sender, $eventArgs)
        $normalPalette = Get-DashboardTilePalette -Tone "Normal" -Mode $script:dashboardTheme
        $sender.BackColor = $normalPalette.BackColor
        $sender.ForeColor = $normalPalette.ForeColor
        if ($sender.Tag.TitleLabel) { $sender.Tag.TitleLabel.ForeColor = $normalPalette.TitleColor }
        if ($sender.Tag.DescriptionLabel) { $sender.Tag.DescriptionLabel.ForeColor = $normalPalette.DescriptionColor }
    })
    $toolTip.SetToolTip($button, (Get-ToolText -Key $descriptionKey -Culture $script:dashboardCulture))
    [void]$buttons.Add($button)
    $buttonPanel.Controls.Add($button)
}

Add-MenuButton 1 "menu.1.title" "menu.1.description" 0 { Start-Report "All" (Get-ToolText -Key "menu.1.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 2 "menu.2.title" "menu.2.description" 1 { Start-Report "Hardware" (Get-ToolText -Key "menu.2.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 3 "menu.3.title" "menu.3.description" 2 { Start-Report "Windows" (Get-ToolText -Key "menu.3.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 4 "menu.4.title" "menu.4.description" 3 { Start-Report "Office" (Get-ToolText -Key "menu.4.title" -Culture $script:dashboardCulture) } $false
Add-MenuButton 5 "menu.5.title" "menu.5.description" 4 { Start-ThirdPartyManualReview } $false
Add-MenuButton 6 "menu.6.title" "menu.6.description" 5 { Show-CleanupMenu } $true
Add-MenuButton 7 "menu.7.title" "menu.7.description" 6 { Start-OemInspect } $true
Add-MenuButton 8 "menu.8.title" "menu.8.description" 7 { Open-LicenseManager } $false
Add-MenuButton 9 "menu.9.title" "menu.9.description" 8 { Show-AdvancedScanMenu } $false
Add-MenuButton 10 "menu.10.title" "menu.10.description" 9 { Show-AssuranceCenter } $false

Add-ReportMenuButton "Certificate" "assurance.certificate" "dashboard.report.certificate.description" 0 "Shield"
Add-ReportMenuButton "PluginAudit" "assurance.pluginAudit" "dashboard.report.pluginAudit.description" 1 "Software"
Add-ReportMenuButton "Timeline" "assurance.timeline" "dashboard.report.timeline.description" 2 "DeepScan"
Add-ReportMenuButton "InstallPlugin" "assurance.installPlugin" "dashboard.report.installPlugin.description" 3 "License"
Add-ReportMenuButton "PluginFolder" "assurance.pluginFolder" "dashboard.report.pluginFolder.description" 4 "Report"
Add-ReportMenuButton "Guide" "assurance.guide" "dashboard.report.guide.description" 5 "Report"
Add-ReportMenuButton "History" "assurance.history" "dashboard.report.history.description" 6 "License"
Set-DashboardSection -Section "Overview"
Set-DashboardTheme -Mode $script:dashboardTheme
$form.Add_Shown({
    Fit-MainWindowToWorkingArea
    Update-MainLayout
    [void]$form.BeginInvoke([System.Action]{ Update-MainLayout })
    Show-ExecutionEnvironmentWarning
    $updateTimer.Start()
    if (-not $script:offlineMode) { Request-ApplicationUpdateCheck }
})
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
        if ($elapsedSeconds -ge 60 -and -not $script:taskStallWarningShown) {
            $script:taskStallWarningShown = $true
            $slowMessage = Get-ToolText -Key "progress.slowTask" -Culture $script:dashboardCulture
            Write-ProgressLog $slowMessage
            $activityLabel.Text = $slowMessage
            [void](Write-ToolLog -Level "WARN" -Event "Action.Slow" -Message $slowMessage -Data ([ordered]@{
                TaskKind = $script:activeTaskKind
                ModuleId = $script:activeModuleId
                ElapsedSeconds = $elapsedSeconds
            }))
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
        if ($script:applicationUpdateReminderPending -and -not [string]::IsNullOrWhiteSpace($finishedTaskKind)) {
            $script:applicationUpdateTaskObservedAfterDeferral = $true
        }
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
        if ($finishedTaskKind -eq "SoftwareCatalogUpdate") {
            Complete-SoftwareCatalogOnlineUpdate
            Stop-ProgressIfIdle
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
                        [void](Open-ToolReportPresentation -SourcePath ([string]$oemApplyResult.ReportPath) -Title (Get-DashboardText "oem.report.applyTitle") -FilePrefix "BaoCao_KhoiPhuc_Key_OEM")
                    }
                } catch {
                    Write-ProgressLog (Get-DashboardText "oem.apply.reportOpenFailed" @($_.Exception.Message))
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
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.successMessage"), (Get-DashboardText "oem.apply.successTitle"), "OK", "Information") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.successStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.successLog")
                $status.ForeColor = [System.Drawing.Color]::DarkGreen
            } elseif ($exitCode -eq 22) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.mismatchMessage"), (Get-DashboardText "oem.apply.mismatchTitle"), "OK", "Warning") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.mismatchStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.mismatchLog")
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } elseif ($exitCode -eq 23) {
                [System.Windows.Forms.MessageBox]::Show((Get-DashboardText "oem.apply.pendingMessage"), (Get-DashboardText "oem.apply.pendingTitle"), "OK", "Warning") | Out-Null
                $status.Text = Get-DashboardText "oem.apply.pendingStatus"
                Write-ProgressLog (Get-DashboardText "oem.apply.pendingLog")
                $status.ForeColor = [System.Drawing.Color]::DarkOrange
            } else {
                $status.Text = Get-DashboardText "oem.apply.failedStatus" @($exitCode)
                Write-ProgressLog (Get-DashboardText "oem.apply.failedLog" @($exitCode))
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

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 1000
$updateTimer.Add_Tick({
    if ($script:applicationUpdateProcess -and $script:applicationUpdateProcess.HasExited) {
        Complete-ApplicationUpdateCheck
    }
    Invoke-PendingApplicationUpdateWork
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
        [void](Write-ToolLog -Level "WARN" -Event "Application.CloseBlocked" -Message (Get-DashboardText "app.closeBlockedLog") -Data ([ordered]@{ TaskKind=$script:activeTaskKind; ModuleId=$script:activeModuleId; Action=$script:activeAction }))
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ToolText -Key "app.closeBlocked" -Culture $script:dashboardCulture),
            (Get-ToolText -Key "app.closeBlockedTitle" -Culture $script:dashboardCulture), "OK", "Warning") | Out-Null
        $eventArgs.Cancel = $true
    } else {
        [void](Write-ToolLog -Level "INFO" -Event "Application.Stop" -Message (Get-DashboardText "app.closedLog"))
    }
})

$form.Add_FormClosed({
    if ($updateTimer) {
        $updateTimer.Stop()
        $updateTimer.Dispose()
    }
    if ($script:applicationUpdateProcess -and -not $script:applicationUpdateProcess.HasExited) {
        try { $script:applicationUpdateProcess.Kill() } catch {}
    }
    Remove-ApplicationUpdateResultFile
    foreach ($iconImage in @($dashboardIconImages)) {
        if ($iconImage) { $iconImage.Dispose() }
    }
    $dashboardIconImages.Clear()
})

[void]$form.ShowDialog()


