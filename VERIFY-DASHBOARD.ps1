[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    [void]$failures.Add($Message)
}

function Assert-SourcePattern {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { Add-Failure $Message }
}

$guiPath = Join-Path $root 'Giao-Dien.ps1'
$guiAst = $null
if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf)) {
    Add-Failure 'Thiếu Giao-Dien.ps1.'
    $text = ''
} else {
    $tokens = $null
    $parseErrors = $null
    $guiAst = [Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Add-Failure "Lỗi cú pháp Giao-Dien.ps1: $($parseError.Message)"
    }
    $text = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

# The dashboard re-checks TOOL-SHA256SUMS.txt before every elevated action.
# Keep its allow-list exactly synchronized with the generated integrity manifest.
if ($guiAst) {
    $requiredIntegrityAssignment = $guiAst.Find({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$requiredIntegrityFiles'
    }, $true)
    if (-not $requiredIntegrityAssignment) {
        Add-Failure 'Dashboard thiếu danh sách requiredIntegrityFiles.'
    } else {
        try {
            $dashboardIntegrityFiles = @(
                $requiredIntegrityAssignment.Right.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.StringConstantExpressionAst]
                }, $true) | ForEach-Object { $_.Value }
            )
            $manifestIntegrityFiles = @(
                foreach ($manifestLine in Get-Content -LiteralPath (Join-Path $root 'TOOL-SHA256SUMS.txt') -ErrorAction Stop) {
                    if ($manifestLine -match '^[0-9A-Fa-f]{64}\s+\*?(.+)$') { $matches[1].Trim() }
                }
            )
            $dashboardIntegritySet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $manifestIntegritySet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $dashboardIntegrityFiles) { [void]$dashboardIntegritySet.Add([string]$name) }
            foreach ($name in $manifestIntegrityFiles) { [void]$manifestIntegritySet.Add([string]$name) }
            foreach ($name in $manifestIntegrityFiles) {
                if (-not $dashboardIntegritySet.Contains([string]$name)) {
                    Add-Failure "Manifest có tệp nhưng dashboard sẽ khóa là ngoài danh sách: $name"
                }
            }
            foreach ($name in $dashboardIntegrityFiles) {
                if (-not $manifestIntegritySet.Contains([string]$name)) {
                    Add-Failure "Dashboard yêu cầu tệp không có trong manifest: $name"
                }
            }
        } catch {
            Add-Failure "Không thể đối chiếu allow-list toàn vẹn của dashboard: $($_.Exception.Message)"
        }
    }
}

Assert-SourcePattern $text '[$]dashboardSchemaVersion\s*=\s*"2\.0"' 'Dashboard schema không phải 2.0.'
Assert-SourcePattern $text '[$]releaseVersion\s*=\s*"4\.8\.0\.0"' 'Dashboard chưa dùng release 4.8.0.0.'
Assert-SourcePattern $text '[$]releaseBuildDate\s*=\s*"2026\.08\.13"' 'Dashboard chưa dùng ngày build 2026.08.13.'
Assert-SourcePattern $text '[$]officialReleaseUrl\s*=\s*"https://github\.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4\.8\.0\.0"' 'Nút Giới thiệu chưa dùng URL cố định của tag v4.8.0.0.'
if ($text -match '[$]officialReleaseUrl\s*=\s*"https://github\.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest"') {
    Add-Failure 'Nút Giới thiệu vẫn dùng releases/latest và có thể chuyển sang phiên bản khác.'
}
Assert-SourcePattern $text 'System\.Windows\.Forms' 'Dashboard không còn nền WinForms.'
Assert-SourcePattern $text 'System\.Drawing' 'Dashboard thiếu System.Drawing.'
Assert-SourcePattern $text 'AutoScaleMode\]::Dpi' 'Dashboard thiếu DPI scaling.'
Assert-SourcePattern $text 'Fit-MainWindowToWorkingArea' 'Dashboard thiếu điều chỉnh theo vùng làm việc.'
Assert-SourcePattern $text '[$]form\.AutoScroll\s*=\s*[$]false' 'Cửa sổ chính chưa khóa thanh cuộn.'
Assert-SourcePattern $text 'AutoScrollMargin\s*=\s*New-Object\s+System\.Drawing\.Size\(0,\s*0\)' 'Dashboard chưa loại bỏ lề cuộn dư.'
if ($text -match '[$]form\.AutoScroll\s*=\s*[$]true') { Add-Failure 'Cửa sổ chính vẫn có nhánh bật thanh cuộn.' }
Assert-SourcePattern $text '[$]form\.Size\s*=\s*New-Object\s+System\.Drawing\.Size\(1480,\s*900\)' 'Dashboard chưa dùng khung hiện đại 1480 x 900.'
Assert-SourcePattern $text '[$]availableWidth\s*=\s*\[Math\]::Max\(640,\s*[$]workArea\.Width\s*-\s*16\)' 'Dashboard chưa co chiều rộng an toàn theo WorkingArea.'
Assert-SourcePattern $text '[$]availableHeight\s*=\s*\[Math\]::Max\(520,\s*[$]workArea\.Height\s*-\s*12\)' 'Dashboard chưa co chiều cao an toàn theo WorkingArea.'
Assert-SourcePattern $text 'BeginInvoke\(\[System\.Action\]\{\s*Update-MainLayout\s*\}\)' 'Dashboard chưa căn lại layout sau khi Bounds/ClientSize được cập nhật ở message-pump kế tiếp.'
Assert-SourcePattern $text '[$]closeButton\.Width\s*=\s*108' 'Nút Đóng chưa đủ rộng sau khi thêm icon nên vẫn có thể mất chữ.'
Assert-SourcePattern $text 'ClientSize\.Height\s*-lt\s*760' 'Dashboard chưa chuyển sang layout gọn ở chiều cao phù hợp.'
Assert-SourcePattern $text 'ClientSize\.Height\s*-lt\s*640' 'Dashboard thiếu layout siêu gọn cho vùng làm việc thấp.'

# Modern WinForms shell: typography, cards, rounded tiles, hover states and responsive two-column layout.
Assert-SourcePattern $text 'Get-ToolUiTypography' 'Dashboard chưa dùng typography Segoe UI dùng chung.'
Assert-SourcePattern $text '[$]sidebarPanel' 'Dashboard thiếu thanh điều hướng bên trái.'
Assert-SourcePattern $text '[$]headerPanel' 'Dashboard thiếu thanh công cụ trên cùng.'
Assert-SourcePattern $text '[$]activityPanel' 'Dashboard thiếu bảng Hoạt động riêng.'
Assert-SourcePattern $text 'function\s+Set-DashboardSection' 'Điều hướng dashboard chưa lọc được nhóm chức năng.'
Assert-SourcePattern $text 'function\s+Show-DashboardPreferences' 'Dashboard thiếu hộp thoại Cài đặt.'
Assert-SourcePattern $text 'SetCompatibleTextRenderingDefault\([$]false\)' 'Dashboard chưa đồng bộ GDI+ text rendering.'
Assert-SourcePattern $text 'UseCompatibleTextRendering\s*=\s*[$]false' 'Dashboard còn control dùng text rendering cũ.'
Assert-SourcePattern $text 'function\s+Set-DashboardHeaderTitleFont' 'Tiêu đề dài chưa có cơ chế tự co chữ để tránh bị cắt.'
Assert-SourcePattern $text '[$]fontTitleMicro\s*=.*9\.0' 'Tiêu đề thiếu cỡ chữ dự phòng cho cửa sổ hẹp hoặc DPI cao.'
Assert-SourcePattern $text '[$]fontTitleMinimum\s*=.*8\.0' 'Tiêu đề thiếu cỡ chữ tối thiểu để luôn hiện đủ nội dung.'
Assert-SourcePattern $text 'function\s+Get-DashboardComboRequiredWidth' 'Thanh công cụ hẹp chưa co hộp chọn ngôn ngữ theo nội dung.'
Assert-SourcePattern $text 'Get-ToolUiButtonRequiredWidth\s+-Button\s+[$]themeButton' 'Nút giao diện chưa co theo nội dung khi cửa sổ hẹp.'
Assert-SourcePattern $text 'Get-ToolUiButtonRequiredWidth\s+-Button\s+[$]offlineButton' 'Nút mạng chưa co theo nội dung khi cửa sổ hẹp.'
Assert-SourcePattern $text '[$]compactCleanupButtonWidth\s*=\s*90' 'Hàng nút Khắc phục chưa khởi tạo từ chiều rộng gọn theo nội dung.'
Assert-SourcePattern $text 'Set-ToolUiFlowButtonSpacing\s+-Panel\s+[$]footer' 'Hàng nút Khắc phục chưa tự căn để giữ nút Kết nối online trong vùng hiển thị.'
Assert-SourcePattern $text '[$]footer\.Add_SizeChanged' 'Hàng nút Khắc phục chưa căn lại khi cửa sổ đổi kích thước/DPI.'
Assert-SourcePattern $text 'function\s+Set-ModernRoundedRegion' 'Dashboard thiếu bo góc cho card/tile.'
Assert-SourcePattern $text 'FlatAppearance\.BorderSize\s*=\s*0' 'Tile hiện đại chưa dùng nút phẳng.'
Assert-SourcePattern $text 'Add_MouseEnter' 'Tile chưa có hover state.'
Assert-SourcePattern $text '[$]buttonIndex\s*/\s*2' 'Menu chưa có layout hai cột.'
Assert-SourcePattern $text '[$]buttonIndex\s*%\s*2' 'Menu chưa có layout hai cột.'
Assert-SourcePattern $text '[$]descriptionLabel' 'Tile chưa có mô tả chức năng.'
Assert-SourcePattern $text '[$]minimumTileHeight\s*=\s*if\s*\([$]ultraCompactHeight\)' 'Tile chưa có ngưỡng thích ứng cho màn hình thấp.'
Assert-SourcePattern $text 'function\s+Get-DashboardTilePalette' 'Dashboard thiếu palette riêng theo loại tile.'
Assert-SourcePattern $text 'ValidateSet\("Normal",\s*"Warning",\s*"Enterprise"\)' 'Dashboard thiếu tone Enterprise cho Mục 8.'
Assert-SourcePattern $text 'if\s*\([$]number\s+-eq\s+8\)\s*\{\s*"Enterprise"\s*\}' 'Mục 8 chưa được gắn tone Enterprise.'
Assert-SourcePattern $text 'FromArgb\(244,\s*247,\s*251\)' 'Tile Light chưa dùng bề mặt trung tính thống nhất.'
Assert-SourcePattern $text 'FromArgb\(34,\s*42,\s*55\)' 'Tile Dark chưa dùng bề mặt trung tính thống nhất.'
Assert-SourcePattern $text 'Get-DashboardTilePalette\s+-Tone\s+[$]tone\s+-Mode\s+[$]script:dashboardTheme\s+-Hover' 'Mục 8 chưa có hover theo palette riêng.'
Assert-SourcePattern $text 'function\s+New-DashboardIconBitmap' 'Dashboard thiếu bộ icon vector nội bộ.'
Assert-SourcePattern $text 'IconKind="Windows"' 'Thẻ Windows chưa dùng biểu tượng Windows.'
Assert-SourcePattern $text 'IconKind="Office"' 'Thẻ Office chưa dùng biểu tượng Office.'
Assert-SourcePattern $text 'IconKind="Shield"' 'Thẻ chế độ chạy chưa dùng biểu tượng khiên.'
Assert-SourcePattern $text 'IconKind="Check"' 'Thẻ toàn vẹn chưa dùng biểu tượng xác minh.'
Assert-SourcePattern $text 'function\s+Get-DashboardMenuIconKind' 'Các tác vụ nhanh chưa có ánh xạ icon riêng.'
Assert-SourcePattern $text 'TextImageRelation\]::ImageBeforeText' 'Tile/sidebar chưa ghép icon với nội dung.'
Assert-SourcePattern $text 'function\s+Get-DashboardStatusPalette' 'Các thẻ trạng thái chưa có palette màu riêng.'
Assert-SourcePattern $text 'Set-ToolUiActionButtonVisual\s+-Button\s+[$]actionButton' 'Các nút Hoạt động chưa dùng màu và icon hành động chung.'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $root 'Tool-UiTheme.ps1')
$themeText = Get-Content -LiteralPath (Join-Path $root 'Tool-UiTheme.ps1') -Raw -Encoding UTF8
foreach ($themePattern in @(
    'function\s+Get-ToolUiButtonRole',
    'function\s+Get-ToolUiButtonPalette',
    'function\s+Get-ToolUiPrimaryActionPalette',
    'function\s+New-ToolUiActionIconBitmap',
    'function\s+Set-ToolUiActionButtonVisual',
    'function\s+Set-ToolUiPrimaryActionButtonVisual',
    'function\s+Get-ToolUiButtonRequiredWidth',
    'function\s+Set-ToolUiFlowButtonSpacing',
    '[$]Button\.UseMnemonic\s*=\s*[$]false',
    '[$]Button\.Parent\s+-is\s+\[Windows\.Forms\.FlowLayoutPanel\]',
    'TextRenderer\]::MeasureText',
    'function\s+Set-ToolUiLiteralText',
    'Set-ToolUiLiteralText\s+-Root\s+[$]Root',
    'Set-ToolUiActionButtons\s+-Root\s+[$]Root'
)) {
    if ($themeText -notmatch $themePattern) { Add-Failure "Theme dùng chung thiếu action style/icon: $themePattern" }
}
foreach ($buttonMode in @('Light','Dark')) {
    foreach ($buttonTone in @('Primary','Success','Warning','Danger','Purple','Teal','Neutral')) {
        $buttonPalette = Get-ToolUiButtonPalette -Tone $buttonTone -Mode $buttonMode
        $buttonContrast = Get-ToolUiContrastRatio -Foreground $buttonPalette.Fore -Background $buttonPalette.Back
        $buttonHoverContrast = Get-ToolUiContrastRatio -Foreground $buttonPalette.Fore -Background $buttonPalette.Hover
        if ($buttonContrast -lt 4.5) { Add-Failure "Màu nút $buttonMode/$buttonTone không đạt tương phản 4.5:1: $buttonContrast" }
        if ($buttonHoverContrast -lt 4.5) { Add-Failure "Màu hover nút $buttonMode/$buttonTone không đạt tương phản 4.5:1: $buttonHoverContrast" }
    }
}
$fitViCatalog = Get-Content -LiteralPath (Join-Path $root 'Tool-Strings.vi-VN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fitEnCatalog = Get-Content -LiteralPath (Join-Path $root 'Tool-Strings.en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fitPanel = New-Object Windows.Forms.FlowLayoutPanel
$fitPanel.Size = New-Object Drawing.Size(700, 54)
$fitFont = New-Object Drawing.Font('Segoe UI', 9.6, [Drawing.FontStyle]::Bold)
try {
    foreach ($fitCase in @(
        @('Light', [string]$fitViCatalog.'about.openGuide', 126),
        @('Light', [string]$fitViCatalog.'about.openHistory', 174),
        @('Dark', [string]$fitEnCatalog.'about.openGuide', 126),
        @('Dark', [string]$fitEnCatalog.'about.openHistory', 174)
    )) {
        $fitButton = New-Object Windows.Forms.Button
        $fitButton.Text = [string]$fitCase[1]
        $fitButton.Font = $fitFont
        $fitButton.Size = New-Object Drawing.Size([int]$fitCase[2], 30)
        $fitPanel.Controls.Add($fitButton)
        Set-ToolUiActionButtonVisual -Button $fitButton -Mode ([string]$fitCase[0])
        $firstStyledWidth = $fitButton.Width
        Set-ToolUiActionButtonVisual -Button $fitButton -Mode ([string]$fitCase[0])
        $fitTextFlags = [Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix
        $fitTextWidth = [int][Windows.Forms.TextRenderer]::MeasureText($fitButton.Text, $fitButton.Font, [Drawing.Size]::Empty, $fitTextFlags).Width
        $fitContentWidth = $fitTextWidth + $fitButton.Image.Width + $fitButton.Padding.Horizontal + 8
        if ($fitButton.UseMnemonic -or $fitButton.Width -lt $fitContentWidth -or $fitButton.Width -ne $firstStyledWidth) {
            Add-Failure "Nút '$($fitButton.Text)' vẫn có thể mất ký tự hoặc bị cắt sau khi thêm icon."
        }
        $fitPanel.Controls.Remove($fitButton)
        $fitButton.Dispose()
    }
} finally {
    $fitFont.Dispose()
    $fitPanel.Dispose()
}
$privacyFont = New-Object Drawing.Font('Segoe UI', 9.1, [Drawing.FontStyle]::Regular)
$privacyBoldFont = New-Object Drawing.Font('Segoe UI', 9.1, [Drawing.FontStyle]::Bold)
try {
    foreach ($privacyCase in @(
        @('Light', $fitViCatalog),
        @('Dark', $fitViCatalog),
        @('Light', $fitEnCatalog),
        @('Dark', $fitEnCatalog)
    )) {
        $privacyHost = New-Object Windows.Forms.Panel
        $privacyHost.Size = New-Object Drawing.Size(650, 54)
        $privacyButtons = @()
        $privacySpecs = @(
            @('report.privacy.redactedButton', 28, 212, $privacyBoldFont),
            @('report.privacy.internalButton', 252, 220, $privacyFont),
            @('report.privacy.cancelButton', 484, 138, $privacyFont)
        )
        foreach ($privacySpec in $privacySpecs) {
            $privacyButton = New-Object Windows.Forms.Button
            $privacyButton.Text = [string]$privacyCase[1].PSObject.Properties[[string]$privacySpec[0]].Value
            $privacyButton.Location = New-Object Drawing.Point([int]$privacySpec[1], 6)
            $privacyButton.Size = New-Object Drawing.Size([int]$privacySpec[2], 42)
            $privacyButton.Font = $privacySpec[3]
            $privacyHost.Controls.Add($privacyButton)
            $privacyButtons += $privacyButton
        }
        Set-ToolWindowTheme -Root $privacyHost -Mode ([string]$privacyCase[0])
        Set-ToolUiPrimaryActionButtonVisual -Button $privacyButtons[0] -Mode ([string]$privacyCase[0])
        foreach ($privacyButton in $privacyButtons) {
            if ($privacyButton.Width -lt (Get-ToolUiButtonRequiredWidth -Button $privacyButton) -or
                $privacyButton.Right -gt $privacyHost.ClientSize.Width) {
                Add-Failure "Nút riêng tư '$($privacyButton.Text)' bị cắt ở chế độ $([string]$privacyCase[0])."
            }
        }
        foreach ($privacyBackground in @(
            $privacyButtons[0].BackColor,
            $privacyButtons[0].FlatAppearance.MouseOverBackColor,
            $privacyButtons[0].FlatAppearance.MouseDownBackColor
        )) {
            $privacyContrast = Get-ToolUiContrastRatio -Foreground $privacyButtons[0].ForeColor -Background $privacyBackground
            if ($privacyContrast -lt 4.5) {
                Add-Failure "Nút riêng tư chính bị mờ ở chế độ $([string]$privacyCase[0]); tương phản chỉ còn $privacyContrast."
            }
        }
        $privacyHost.Dispose()
    }
} finally {
    $privacyBoldFont.Dispose()
    $privacyFont.Dispose()
}
$cleanupFooterFont = New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Regular)
try {
    foreach ($cleanupFitCase in @(
        @('Light', $fitViCatalog),
        @('Dark', $fitViCatalog),
        @('Light', $fitEnCatalog),
        @('Dark', $fitEnCatalog)
    )) {
        $cleanupFooter = New-Object Windows.Forms.FlowLayoutPanel
        $cleanupFooter.Size = New-Object Drawing.Size(636, 58)
        $cleanupFooter.FlowDirection = [Windows.Forms.FlowDirection]::RightToLeft
        $cleanupFooter.WrapContents = $false
        $cleanupFooter.AutoScroll = $true
        $cleanupFooter.Padding = New-Object Windows.Forms.Padding(0, 7, 0, 0)
        $cleanupButtons = @()
        foreach ($cleanupKey in @('common.back', 'cleanup.menu.cleanupAction', 'cleanup.dryRun.button', 'software.online.button')) {
            $cleanupButton = New-Object Windows.Forms.Button
            $cleanupButton.Text = [string]$cleanupFitCase[1].PSObject.Properties[$cleanupKey].Value
            $cleanupButton.Font = $cleanupFooterFont
            $cleanupButton.Size = New-Object Drawing.Size(90, 40)
            $cleanupFooter.Controls.Add($cleanupButton)
            $cleanupButtons += $cleanupButton
        }
        Set-ToolWindowTheme -Root $cleanupFooter -Mode ([string]$cleanupFitCase[0])
        Set-ToolUiFlowButtonSpacing -Panel $cleanupFooter -PreferredSideMargin 3
        $cleanupFooter.PerformLayout()

        $cleanupUsedWidth = $cleanupFooter.Padding.Horizontal
        $cleanupClipped = $false
        foreach ($cleanupButton in $cleanupButtons) {
            $cleanupUsedWidth += $cleanupButton.Width + $cleanupButton.Margin.Horizontal
            $cleanupRequiredWidth = Get-ToolUiButtonRequiredWidth -Button $cleanupButton
            if ($cleanupButton.Width -lt $cleanupRequiredWidth -or
                $cleanupButton.Left -lt 0 -or
                $cleanupButton.Right -gt $cleanupFooter.ClientSize.Width) {
                $cleanupClipped = $true
            }
        }
        if ($cleanupUsedWidth -gt $cleanupFooter.ClientSize.Width -or
            $cleanupFooter.HorizontalScroll.Visible -or
            $cleanupClipped) {
            Add-Failure "Hàng nút Khắc phục $([string]$cleanupFitCase[0]) vẫn có thể cắt nhãn Kết nối online ở chiều rộng tối thiểu."
        }
        $cleanupFooter.Dispose()
    }
} finally {
    $cleanupFooterFont.Dispose()
}
$enterpriseColorPairs = @(
    @('Light', [Drawing.Color]::FromArgb(30,64,105), [Drawing.Color]::FromArgb(244,247,251)),
    @('LightHover', [Drawing.Color]::FromArgb(30,64,105), [Drawing.Color]::FromArgb(231,238,247)),
    @('Dark', [Drawing.Color]::FromArgb(220,228,239), [Drawing.Color]::FromArgb(34,42,55)),
    @('DarkHover', [Drawing.Color]::FromArgb(220,228,239), [Drawing.Color]::FromArgb(43,53,69))
)
foreach ($colorPair in $enterpriseColorPairs) {
    $contrast = Get-ToolUiContrastRatio -Foreground $colorPair[1] -Background $colorPair[2]
    if ($contrast -lt 4.5) { Add-Failure "Màu Mục 8 $($colorPair[0]) không đạt tương phản 4.5:1." }
}

# Dashboard always starts in Light mode and keeps Dark available per session.
Assert-SourcePattern $text 'function\s+Set-DashboardTheme' 'Thiếu hàm áp dụng theme.'
Assert-SourcePattern $text 'Set-ToolUiLiteralText\s+-Root\s+[$]form' 'Dashboard chưa hiển thị nguyên văn dấu & trên tile và nhãn.'
Assert-SourcePattern $text 'ValidateSet\("Light",\s*"Dark"\)' 'Thiếu lựa chọn theme sáng/tối.'
Assert-SourcePattern $text 'Tool-UiTheme\.ps1' 'Dashboard chưa nạp theme dùng chung.'
Assert-SourcePattern $text 'Set-ToolUiThemePreference' 'Dashboard chưa ghi nhớ theme.'
Assert-SourcePattern $text 'TOOL_UI_THEME' 'Dashboard chưa truyền theme sang tiến trình con.'
Assert-SourcePattern $text '[$]script:dashboardTheme\s*=\s*"Light"' 'Dashboard chưa mặc định mở bằng giao diện sáng.'
$themedDialogCount = [regex]::Matches($text, 'Set-ToolWindowTheme\s+-Root\s+[$](dialog|chooser|screen)\s+-Mode\s+[$]script:dashboardTheme').Count
if ($themedDialogCount -lt 9) {
    Add-Failure "Dark mode chưa phủ đủ cửa sổ con; tìm thấy $themedDialogCount lượt áp dụng."
}

# Compatibility, localization and offline state are first-class dashboard controls.
foreach ($foundationFile in @(
    'Tool-Compatibility.ps1',
    'compatibility-catalog-v1.0.json',
    'Tool-Localization.ps1',
    'Tool-Strings.vi-VN.json',
    'Tool-Strings.en-US.json',
    'Tool-OfflinePolicy.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $foundationFile) -PathType Leaf)) {
        Add-Failure "Thiếu nền tảng dashboard: $foundationFile"
    }
}
$viCatalog = Get-Content -LiteralPath (Join-Path $root 'Tool-Strings.vi-VN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$enCatalog = Get-Content -LiteralPath (Join-Path $root 'Tool-Strings.en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$viCatalog.'menu.6.title' -ne 'Khắc phục KMS/Activator Win, Office & phần mềm') {
    Add-Failure 'Tên tiếng Việt của chức năng khắc phục bản quyền toàn bộ phần mềm chưa đúng yêu cầu.'
}
if ([string]$enCatalog.'menu.6.title' -ne 'Windows, Office & software KMS/Activator remediation') {
    Add-Failure 'Tên tiếng Anh của chức năng khắc phục bản quyền toàn bộ phần mềm chưa đồng bộ.'
}
foreach ($catalogInfo in @(@('vi-VN',$viCatalog), @('en-US',$enCatalog))) {
    foreach ($property in $catalogInfo[1].PSObject.Properties) {
        if ([string]$property.Value -match '(?i)\b(?:Mục|Function)\s*0?[0-9]+') {
            Add-Failure "Catalog $($catalogInfo[0]) còn nhãn đánh số cũ tại $($property.Name)."
        }
    }
}
foreach ($cleanupKey in @('cleanup.menu.backupTitle','cleanup.menu.cleanupTitle','cleanup.menu.cleanupFullTitle','cleanup.menu.restoreTitle','cleanup.menu.autoTitle','cleanup.menu.autoFullTitle')) {
    if ([string]$viCatalog.$cleanupKey -match '^\s*(?:[0-9]+|[A-Z])\.\s+' -or [string]$enCatalog.$cleanupKey -match '^\s*(?:[0-9]+|[A-Z])\.\s+') {
        Add-Failure "Cửa sổ khắc phục còn tiền tố đánh số tại $cleanupKey."
    }
}
foreach ($advancedKey in @('advanced.deep.title','advanced.forensics.title')) {
    if ([string]$viCatalog.$advancedKey -match '^\s*(?:[0-9]+|[A-Z])\.\s+' -or [string]$enCatalog.$advancedKey -match '^\s*(?:[0-9]+|[A-Z])\.\s+') {
        Add-Failure "Cửa sổ kiểm tra chuyên sâu còn tiền tố đánh số tại $advancedKey."
    }
}
if ([string]$viCatalog.'cleanup.menu.title' -ne 'Khắc phục KMS/Activator Windows, Office và đưa phần mềm về trạng thái gốc' -or [string]$enCatalog.'cleanup.menu.title' -ne 'Remediate Windows/Office KMS/Activator and return software to an original state') {
    Add-Failure 'Tiêu đề cửa sổ khắc phục vẫn còn nhãn chức năng đánh số cũ.'
}
if ([string]$viCatalog.'cleanup.menu.cleanupFullTitle' -ne 'Kiểm tra và loại bỏ kích hoạt lậu khỏi Windows, Office và phần mềm' -or
    [string]$viCatalog.'cleanup.scope.scanWindows' -notmatch '^Windows' -or
    [string]$viCatalog.'cleanup.scope.scanOffice' -notmatch '^Office' -or
    [string]$viCatalog.'cleanup.scope.scanThirdParty' -notmatch '^Quét phần mềm khác') {
    Add-Failure 'Luồng khắc phục chưa có đúng tên mới và ba ô tích phạm vi theo yêu cầu.'
}
Assert-SourcePattern $text 'function\s+Show-LicenseScopeChooser' 'Khắc phục thiếu hộp chọn phạm vi dùng chung.'
Assert-SourcePattern $text 'function\s+Show-CleanupScopeChecklist' 'Khắc phục thiếu hộp ba ô tích phạm vi.'
Assert-SourcePattern $text 'Name="Windows";\s*TextKey="cleanup\.scope\.scanWindows"' 'Khắc phục thiếu ô tích Windows.'
Assert-SourcePattern $text 'Name="Office";\s*TextKey="cleanup\.scope\.scanOffice"' 'Khắc phục thiếu ô tích Office.'
Assert-SourcePattern $text 'Name="ThirdParty";\s*TextKey="cleanup\.scope\.scanThirdParty"' 'Khắc phục thiếu ô tích Phần mềm khác.'
Assert-SourcePattern $text 'Start-SoftwareCatalogOnlineUpdate\s+-ScanScope\s+[$]selectedScope' 'Kết nối Online chưa dùng cùng phạm vi người dùng đã tích.'
Assert-SourcePattern $text 'Start-CleanupBackup\s+-Scope\s+[$]selectedScope' 'Backup chưa nhận phạm vi người dùng chọn.'
Assert-SourcePattern $text 'Start-CleanupRestore\s+-Scope\s+[$]selectedScope' 'Khôi phục chưa nhận phạm vi người dùng chọn.'
Assert-SourcePattern $text 'Start-Cleanup\s+-ScanScope\s+[$]selectedScope' 'Quét khắc phục chưa nhận phạm vi người dùng chọn.'
Assert-SourcePattern $text 'progress\.slowTask' 'Dashboard thiếu cảnh báo tác vụ chạy lâu nhưng còn phản hồi.'
if ([string]$viCatalog.'menu.5.title' -ne 'Phần mềm & dấu hiệu can thiệp' -or
    [string]$viCatalog.'menu.5.description' -ne 'Ứng dụng đã cài, activator, crack và KMS cần xác minh' -or
    [string]$enCatalog.'menu.5.title' -ne 'Software & tampering indicators' -or
    [string]$enCatalog.'menu.5.description' -ne 'Installed apps, activators, cracks and KMS items to verify' -or
    [string]$viCatalog.'report.title.software' -ne 'Báo cáo phần mềm và dấu hiệu can thiệp' -or
    [string]$enCatalog.'report.title.software' -ne 'Software and tampering indicator report') {
    Add-Failure 'Mục 5 chưa khôi phục đúng hợp đồng giao diện/báo cáo của v4.3.0.3.'
}
if ([string]$viCatalog.'menu.7.description' -ne 'Kiểm tra key firmware; chỉ áp dụng sau khi xác nhận' -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.card.config.body') -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.card.remediation.body') -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.card.report.body') -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.card.assurance.body') -or
    [string]::IsNullOrWhiteSpace([string]$enCatalog.'about.card.config.body') -or
    [string]::IsNullOrWhiteSpace([string]$enCatalog.'about.card.assurance.body') -or
    [string]$viCatalog.'about.card.config.body' -match '\b(?:0[1-9]|10)\b' -or
    [string]$enCatalog.'about.card.config.body' -match '\b(?:0[1-9]|10)\b') {
    Add-Failure 'Mô tả tile/Năng lực phải đầy đủ và không hiển thị số tác vụ vi-VN/en-US.'
}
foreach ($lightCardColor in @('238,246,255','255,248,232','237,250,244','247,241,255')) {
    Assert-SourcePattern $text ([regex]::Escape("FromArgb($lightCardColor)")) "Khung Năng lực Light thiếu màu nổi bật $lightCardColor."
}
Assert-SourcePattern $text 'Get-ToolCompatibilityMetadata' 'Dashboard chưa hiển thị metadata tương thích.'
Assert-SourcePattern $text 'WindowsReleaseName' 'Dashboard thiếu trạng thái Windows release.'
Assert-SourcePattern $text 'OfficeSummary' 'Dashboard thiếu trạng thái Office.'
Assert-SourcePattern $text 'Get-ToolText' 'Dashboard chưa dùng chuỗi đa ngôn ngữ.'
Assert-SourcePattern $text 'function\s+Set-DashboardLanguage' 'Dashboard thiếu đổi ngôn ngữ trực tiếp.'
Assert-SourcePattern $text 'Get-DashboardText\s+"app\.language\.vi"' 'Dashboard thiếu lựa chọn tiếng Việt từ catalog.'
Assert-SourcePattern $text 'Get-DashboardText\s+"app\.language\.en"' 'Dashboard thiếu lựa chọn tiếng Anh từ catalog.'
if ([string]$viCatalog.'app.language.vi' -ne 'Tiếng Việt' -or
    [string]$viCatalog.'app.language.en' -ne 'English' -or
    [string]$enCatalog.'app.language.vi' -ne 'Tiếng Việt' -or
    [string]$enCatalog.'app.language.en' -ne 'English') {
    Add-Failure 'Catalog thiếu hai lựa chọn ngôn ngữ Tiếng Việt/English.'
}
if ([string]$viCatalog.'app.title' -ne 'CÔNG CỤ KIỂM TRA CẤU HÌNH MÁY VÀ BẢN QUYỀN PHẦN MỀM' -or
    [string]$viCatalog.'app.developer' -ne 'Hỗ trợ người dùng cá nhân và doanh nghiệp' -or
    [string]$viCatalog.'dashboard.sidebar.brand' -ne 'TOOL' -or
    [string]$viCatalog.'dashboard.sidebar.edition' -ne 'KIỂM TRA MÁY TÍNH' -or
    [string]$viCatalog.'dashboard.sidebar.footer' -ne "© 2026 Thanh Việt`r`nPhiên bản phần mềm: {0}" -or
    [string]$enCatalog.'dashboard.sidebar.footer' -ne "© 2026 Thanh Viet`r`nSoftware version: {0}" -or
    [string]$enCatalog.'app.title' -ne 'COMPUTER CONFIGURATION AND SOFTWARE LICENSE CHECK TOOL') {
    Add-Failure 'Tên sản phẩm chưa đúng phạm vi hỗ trợ cá nhân và doanh nghiệp.'
}
Assert-SourcePattern $text 'function\s+Toggle-DashboardOfflineMode' 'Dashboard thiếu điều khiển Offline.'
Assert-SourcePattern $text 'Set-ToolOfflineModePreference' 'Dashboard chưa ghi nhớ lựa chọn Offline.'
Assert-SourcePattern $text 'TOOL_OFFLINE_MODE' 'Dashboard chưa truyền Offline mode sang tiến trình con.'
Assert-SourcePattern $text 'OfflineMode\.Changed' 'Thay đổi Offline mode chưa được audit.'
Assert-SourcePattern $text 'function\s+Refresh-DashboardLocalizedActivity' 'Dashboard chưa làm mới nhật ký khi đổi ngôn ngữ.'
Assert-SourcePattern $text 'function\s+Reset-IdleTaskDisplay' 'Dashboard thiếu trạng thái tác vụ trống khi khởi động.'
Assert-SourcePattern $text '[$]script:hasTaskActivity\s*=\s*[$]false' 'Dashboard chưa để khu vực tác vụ trống khi mở.'
Assert-SourcePattern $text 'function\s+Stop-ActiveTask' 'Dashboard thiếu nút/hàm dừng tác vụ.'
Assert-SourcePattern $text 'taskkill\.exe' 'Nút Dừng chưa kết thúc cây tiến trình con.'
Assert-SourcePattern $text 'taskCancellationRequested' 'Dashboard chưa phân biệt tác vụ bị người dùng dừng.'
Assert-SourcePattern $text 'function\s+Open-Guide' 'Trung tâm bảo đảm thiếu xuất hướng dẫn.'
Assert-SourcePattern $text 'USER-GUIDE-en-US\.md' 'Dashboard chưa tham chiếu hướng dẫn English đầy đủ.'
Assert-SourcePattern $text 'function\s+Open-ToolEmbeddedDocument' 'Dashboard thiếu bộ mở tài liệu HTML/PDF dùng chung.'
Assert-SourcePattern $text 'function\s+Open-VersionHistory' 'Dashboard thiếu mục giới thiệu phiên bản và lịch sử cập nhật.'
Assert-SourcePattern $text 'New-Object\s+System\.Windows\.Forms\.RichTextBox' 'Lịch sử phiên bản chưa hiển thị ngay trong Tool.'
Assert-SourcePattern $text 'function\s+Copy-AllToolLog' 'Dashboard thiếu nút sao chép toàn bộ log.'
Assert-SourcePattern $text 'function\s+Open-ReportDirectory' 'Dashboard thiếu nút mở thư mục báo cáo.'
Assert-SourcePattern $text 'Get-ToolWindowsPath\s+"explorer\.exe"' 'Dashboard đang tìm explorer.exe sai trong System32/Sysnative thay vì thư mục Windows.'
Assert-SourcePattern $text 'function\s+Show-ExecutionEnvironmentWarning' 'Dashboard thiếu cảnh báo máy ảo/Remote Desktop.'
Assert-SourcePattern $text '[$]capabilityState\.ExecutionEnvironment' 'Dashboard chưa dùng hồ sơ môi trường thực thi.'
Assert-SourcePattern $text 'LICH-SU-PHIEN-BAN\.txt' 'Dashboard chưa nhúng tài liệu lịch sử phiên bản.'
Assert-SourcePattern $text 'New-ToolProfessionalHtmlDocument' 'Hướng dẫn chưa dùng bố cục báo cáo HTML chuyên nghiệp.'
Assert-SourcePattern $text 'Convert-ToolHtmlToPdf' 'Hướng dẫn chưa hỗ trợ PDF.'
Assert-SourcePattern $text '[$]documentBasePath\s*=\s*Join-Path\s+[$]documentDirectory\s+"[$]FilePrefix-v[$]releaseVersion-[$]\([$]script:dashboardCulture\)"' 'Hướng dẫn chưa dùng tên tệp ổn định trong thư mục báo cáo theo phiên bản/ngôn ngữ.'
Assert-SourcePattern $text '# Source-SHA256:' 'Hướng dẫn chưa dùng SHA-256 nguồn làm khóa cache.'
Assert-SourcePattern $text '# Renderer-Revision:' 'Hướng dẫn chưa có phiên bản renderer để làm mới cache khi giao diện HTML/PDF thay đổi.'
Assert-SourcePattern $text 'Open-ToolHtmlReport\s+-Path\s+[$]htmlPath' 'Hướng dẫn chưa giới hạn tự mở ở tệp HTML.'
$documentationFunctionIndex = $text.IndexOf('function Open-ToolEmbeddedDocument')
$documentationOpenIndex = if ($documentationFunctionIndex -ge 0) { $text.IndexOf('Open-ToolHtmlReport -Path $htmlPath', $documentationFunctionIndex) } else { -1 }
$documentationPdfIndex = if ($documentationFunctionIndex -ge 0) { $text.IndexOf('Convert-ToolHtmlToPdf -HtmlPath $htmlPath', $documentationFunctionIndex) } else { -1 }
if ($documentationFunctionIndex -lt 0 -or $documentationOpenIndex -lt 0 -or $documentationPdfIndex -lt 0 -or $documentationOpenIndex -ge $documentationPdfIndex) {
    Add-Failure 'Hướng dẫn phải mở HTML trước khi tạo PDF để giảm thời gian chờ.'
}
if ([string]$viCatalog.'about.openHistory' -ne 'Phiên bản & cập nhật' -or
    [string]$enCatalog.'about.openHistory' -ne 'Versions & updates' -or
    [string]$viCatalog.'assurance.history' -match '^\d+[\.)]' -or
    [string]$enCatalog.'assurance.history' -match '^\d+[\.)]' -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.model.body') -or
    [string]::IsNullOrWhiteSpace([string]$enCatalog.'about.model.body') -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'about.technology.body') -or
    [string]::IsNullOrWhiteSpace([string]$enCatalog.'about.technology.body')) {
    Add-Failure 'Giới thiệu/Trung tâm bảo đảm chưa có mô hình, công nghệ và phiên bản cập nhật song ngữ.'
}
if ([string]$viCatalog.'app.offline.enabled' -ne 'Offline' -or
    [string]$viCatalog.'app.offline.disabled' -ne 'Online' -or
    [string]$enCatalog.'app.offline.enabled' -ne 'Offline' -or
    [string]$enCatalog.'app.offline.disabled' -ne 'Online' -or
    [string]$viCatalog.'enterprise.network.stateOnline' -ne 'LAN nội bộ: Bật' -or
    [string]$viCatalog.'enterprise.network.stateOffline' -ne 'LAN nội bộ: Tắt' -or
    [string]$viCatalog.'app.offline.enable' -notmatch 'nhấp để chuyển sang Offline' -or
    [string]$viCatalog.'enterprise.network.tooltipOffline' -notmatch 'LAN nội bộ đang tắt') {
    Add-Failure 'Nút Internet và LAN chưa dùng đúng hai trạng thái độc lập.'
}
if ([string]$viCatalog.'enterprise.client.tab' -ne 'Chức năng máy trạm' -or
    [string]$viCatalog.'enterprise.navigation.back' -ne 'Trở về' -or
    [string]$viCatalog.'enterprise.navigation.close' -ne 'Đóng' -or
    [string]$viCatalog.'enterprise.server.job' -ne 'Lệnh quản lý bản quyền' -or
    [string]::IsNullOrWhiteSpace([string]$viCatalog.'progress.stop')) {
    Add-Failure 'Nhãn Mục 8 hoặc nút Dừng chưa đúng yêu cầu.'
}
$guideViPath = Join-Path $root 'HUONG-DAN.txt'
$guideEnPath = Join-Path $root 'USER-GUIDE-en-US.md'
$historyPath = Join-Path $root 'LICH-SU-PHIEN-BAN.txt'
if (-not (Test-Path -LiteralPath $guideViPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $guideEnPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
    Add-Failure 'Thiếu HDSD vi-VN/en-US hoặc tài liệu lịch sử phiên bản.'
} else {
    $guideViText = Get-Content -LiteralPath $guideViPath -Raw -Encoding UTF8
    $guideEnText = Get-Content -LiteralPath $guideEnPath -Raw -Encoding UTF8
    $historyText = Get-Content -LiteralPath $historyPath -Raw -Encoding UTF8
    foreach ($functionNumber in 1..10) {
        $viTaskTitle = [string]$viCatalog.("menu.$functionNumber.title")
        $enTaskTitle = [string]$enCatalog.("menu.$functionNumber.title")
        if ($guideViText -notmatch "(?m)^##\s+$([regex]::Escape($viTaskTitle))\s*$") {
            Add-Failure "HDSD tiếng Việt thiếu mục hướng dẫn theo tên tác vụ: $viTaskTitle."
        }
        if ($guideEnText -notmatch "(?m)^##\s+$([regex]::Escape($enTaskTitle))\s*$") {
            Add-Failure "English guide thiếu mục hướng dẫn theo tên tác vụ: $enTaskTitle."
        }
    }
    if ($guideViText -match '(?i)(?:Chức năng|Mục)\s+(?:0?[1-9]|10)\b|Chọn\s+(?:0[1-9]|10)\b' -or
        $guideEnText -match '(?i)Functions?\s+(?:0?[1-9]|10)\b|Select\s+(?:0[1-9]|10)\b') {
        Add-Failure 'HDSD còn gọi tác vụ bằng số thay vì tên hiển thị trên giao diện.'
    }
    if ($guideViText -match '(?im)^\s*(Bản|Phiên bản)\s+v?\d' -or $guideEnText -match '(?im)^\s*(Version|Release)\s+v?\d') {
        Add-Failure 'HDSD còn trộn nhật ký cập nhật phiên bản thay vì chỉ hướng dẫn chức năng.'
    }
    if ($historyText -notmatch 'FileVersion:\s*\*\*4\.8\.0\.0\*\*' -or
        $historyText -notmatch 'v4\.8\.0' -or
        $historyText -notmatch 'Nền tảng/công nghệ:' -or
        $historyText -notmatch 'Trọng tâm:') {
        Add-Failure 'Tài liệu phiên bản chưa mô tả bản mới, mô hình triển khai và công nghệ/ngôn ngữ.'
    }
    foreach ($mainVersion in @('1.0','1.1','1.2','1.3','2.4','2.5','2.6','2.7','2.8','2.9','3.0','3.1','3.2','3.3','3.4','3.5','3.6','3.7','3.8','3.9','4.0','4.1','4.2','4.3','4.4','4.6','4.8')) {
        if ($historyText -notmatch "(?m)^##\s+v$([regex]::Escape($mainVersion))\b") {
            Add-Failure "Tài liệu lịch sử thiếu phiên bản chính v$mainVersion."
        }
    }
}
Assert-SourcePattern $text 'function\s+Open-ToolReportPresentation' 'Dashboard thiếu bộ chuyển báo cáo TXT/HTML về giao diện HTML/PDF dùng chung.'
Assert-SourcePattern $text 'Export-ToolTextReportPresentation' 'Báo cáo văn bản chưa được chuyển thành HTML/PDF chuyên nghiệp.'
$buildText = Get-Content -LiteralPath (Join-Path $root 'BUILD.ps1') -Raw -Encoding UTF8
if ($buildText -notmatch '(?s)[$]payloadFiles\s*=.*?''USER-GUIDE-en-US\.md''' -or
    $buildText -notmatch '(?s)[$]integrityFiles\s*=.*?''USER-GUIDE-en-US\.md''') {
    Add-Failure 'Hướng dẫn English chưa được nhúng và bảo vệ toàn vẹn trong EXE.'
}

$reportPath = Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1'
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    $reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    foreach ($reportPattern in @(
        'function\s+Get-SoftwareSignatureState',
        'Get-ReportText\s+"report\.file\.software"',
        'Add-Section\s+"Phan mem da cai"\s+\(\(Add-Table\s+[$]legacyApps\s+@\("Ten phan mem","Phien ban","Hang","Ngay cai"\)\)\s*\+\s*[$]systemAppendixLink\)',
        'Add-Section\s+"Danh gia so bo ban quyen phan mem"\s+\(Add-Table\s+[$]legacySoftwareAudit',
        'Add-Section\s+"Dich vu Windows"\s+\(Add-Table\s+[$]services\s+@\("Ten","Hien thi","Trang thai","Loai khoi dong"\)\)',
        'Add-Section\s+"Kiểm tra bổ sung phần mềm bên thứ ba"',
        'Get-ReportText\s+"report\.text\.045"',
        'Get-ReportText\s+"report\.text\.048"',
        'Get-ReportText\s+"report\.text\.050"',
        'ThirdPartyServices',
        'ThirdPartyScheduledTasks',
        'DetailedInventory',
        'ThirdPartyApplications',
        'Start-Process\s+-FilePath\s+[$]selectPath'
    )) {
        if ($reportText -notmatch $reportPattern) { Add-Failure "Mô-đun báo cáo thiếu nâng cấp Mục 5/mở trực tiếp: $reportPattern" }
    }
    $legacySectionIndex = $reportText.IndexOf('Add-Section "Phan mem da cai"')
    $supplementSectionIndex = $reportText.IndexOf('Add-Section "Kiểm tra bổ sung phần mềm bên thứ ba"')
    if ($legacySectionIndex -lt 0 -or $supplementSectionIndex -le $legacySectionIndex) {
        Add-Failure 'Phần kiểm tra bổ sung phải nằm sau hợp đồng báo cáo Mục 5 của v4.3.0.3.'
    }
    $summaryCardAppendCount = [regex]::Matches($reportText, 'summaryCardsHtml\.Append\("<div class=''card tone-').Count
    if ($summaryCardAppendCount -ne 5) {
        Add-Failure "Mục 5 phải giữ bố cục năm thẻ tổng quan của v4.3.0.3; tìm thấy $summaryCardAppendCount thẻ."
    }
} else {
    Add-Failure 'Thiếu mô-đun báo cáo để kiểm tra Mục 5.'
}

foreach ($schemaVariable in @(
    'TOOL_CAPABILITY_SCHEMA',
    'TOOL_REPORT_SCHEMA',
    'TOOL_SAFETY_POLICY_SCHEMA',
    'TOOL_DASHBOARD_SCHEMA',
    'TOOL_LOCALIZATION_SCHEMA',
    'TOOL_OFFLINE_POLICY_SCHEMA',
    'TOOL_COMPATIBILITY_SCHEMA'
)) {
    if ($text -notmatch [regex]::Escape($schemaVariable)) {
        Add-Failure "Dashboard thiếu fail-closed schema: $schemaVariable"
    }
}

$cardMatches = [regex]::Matches($text, 'Key="(Compatibility|Architecture|SecureLaunch|Integrity)"')
if (@($cardMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique).Count -ne 4) {
    Add-Failure 'Dashboard phải có bốn thẻ Windows, Office, chế độ chạy và toàn vẹn.'
}

$menuMatches = [regex]::Matches(
    $text,
    '(?m)^\s*Add-MenuButton\s+([0-9]+)\s+"menu\.[0-9]+\.title"\s+"menu\.[0-9]+\.description"\s+([0-9]+)\s+\{'
)
if ($menuMatches.Count -ne 10) {
    Add-Failure "Menu phải có đúng 10 mục; tìm thấy $($menuMatches.Count)."
} else {
    for ($index = 0; $index -lt 10; $index++) {
        if ([int]$menuMatches[$index].Groups[1].Value -ne ($index + 1) -or
            [int]$menuMatches[$index].Groups[2].Value -ne $index) {
            Add-Failure "Thứ tự menu sai tại vị trí $($index + 1)."
        }
    }
}

if ($text -match '[$]number\s*=\s*"\{0:00\}"' -or $text -match 'return\s+"[$]number\s+') {
    Add-Failure 'Tile tác vụ vẫn còn ghép số thứ tự 01–10 vào nhãn hiển thị.'
}
Assert-SourcePattern $text '[$]script:dashboardTheme\s*=\s*"Light"' 'Ứng dụng chưa khởi động bằng giao diện sáng.'
Assert-SourcePattern $text '[$]cardValue\.AutoEllipsis\s*=\s*[$]true' 'Thẻ trạng thái chưa có ellipsis/tooltip an toàn khi cửa sổ quá hẹp.'
Assert-SourcePattern $text 'function\s+New-DashboardTileIconBitmap' 'Tile chưa có khoảng đệm ảnh riêng để icon không sát chữ.'
Assert-SourcePattern $text 'IconSize\s+32\s+-RightGap\s+12' 'Khoảng cách icon/chữ của tile chưa được chuẩn hóa.'
Assert-SourcePattern $text '[$]fontTile\s*=.*FontStyle\]::Regular' 'Tile vẫn dùng toàn bộ chữ đậm.'
Assert-SourcePattern $text '(?s)function\s+New-ToolReportRunDirectory.+?return\s+[$]reportRoot' 'Dashboard chưa gom mọi lần xuất vào một thư mục báo cáo dùng chung.'
Assert-SourcePattern $text 'ApprovedKmsServerFile\s+`"[$]approvedKmsFile`"' 'Báo cáo chưa nhận danh sách KMS được phê duyệt để kết luận chặt chẽ.'
Assert-SourcePattern $text '[$]applyButton\.Text\s*=\s*Get-DashboardText\s+"dashboard\.settings\.apply"' 'Cài đặt thiếu nút Áp dụng có nhãn localization.'
Assert-SourcePattern $text '[$]dialog\.AcceptButton\s*=\s*[$]applyButton' 'Nút Áp dụng chưa là hành động chính trong Cài đặt.'
Assert-SourcePattern $text 'function\s+Invoke-AssuranceCenterAction' 'Thiếu bộ định tuyến bảy tác vụ Báo cáo.'
Assert-SourcePattern $text '"Reports"\s*\{\s*@\(\)\s*\}' 'Mục Báo cáo vẫn chỉ hiển thị tile số 10.'
Assert-SourcePattern $text '[$]menuCaption\.ForeColor\s*=\s*[$]primary' 'Tiêu đề Trung tâm báo cáo chưa dùng màu tiêu đề chung.'
Assert-SourcePattern $text 'Kind\s*=\s*"ReportAction"' 'Các ô Trung tâm báo cáo chưa có metadata giao diện riêng.'
Assert-SourcePattern $text '(?s)function\s+Add-ReportMenuButton.+?TitleLabel.+?DescriptionLabel.+?TitleColor.+?DescriptionColor' 'Ô báo cáo chưa tách màu tiêu đề và mô tả như các mục khác.'
Assert-SourcePattern $text '(?s)[$]script:dashboardSection\s+-eq\s+"Reports".+?[$]visibleButtons\.Count\s*%\s*2\s+-eq\s*1' 'Hàng cuối Trung tâm báo cáo chưa được căn giữa khi có bảy ô.'

$reportMenuMatches = [regex]::Matches(
    $text,
    '(?m)^\s*Add-ReportMenuButton\s+"(Certificate|PluginAudit|Timeline|InstallPlugin|PluginFolder|Guide|History)"\s+"assurance\.[^"]+"\s+"dashboard\.report\.[^"]+\.description"'
)
if ($reportMenuMatches.Count -ne 7 -or @($reportMenuMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique).Count -ne 7) {
    Add-Failure "Mục Báo cáo phải hiển thị trực tiếp đúng 7 mục con; tìm thấy $($reportMenuMatches.Count)."
}
foreach ($key in @(
    'dashboard.report.certificate.description',
    'dashboard.report.pluginAudit.description',
    'dashboard.report.timeline.description',
    'dashboard.report.installPlugin.description',
    'dashboard.report.pluginFolder.description',
    'dashboard.report.guide.description',
    'dashboard.report.history.description'
)) {
    if ([string]::IsNullOrWhiteSpace([string]$viCatalog.$key) -or [string]::IsNullOrWhiteSpace([string]$enCatalog.$key)) {
        Add-Failure "Thiếu mô tả song ngữ cho mục Báo cáo: $key"
    }
    if ($historyText -match '(?m)^##\s+v4\.7\b') {
        Add-Failure 'Lịch sử công khai phải thể hiện v4.8 nâng trực tiếp từ v4.6, không có mục phát hành v4.7.'
    }
}

foreach ($pattern in @(
    'Start-Report\s+"All"',
    'Start-Report\s+"Hardware"',
    'Start-Report\s+"Windows"',
    'Start-Report\s+"Office"',
    'Start-Report\s+"Software"',
    'Show-CleanupMenu',
    'Start-OemInspect',
    'Open-LicenseManager',
    'Show-AdvancedScanMenu',
    'Show-AssuranceCenter'
)) {
    if ($text -notmatch $pattern) { Add-Failure "Thiếu hành động menu: $pattern" }
}

Assert-SourcePattern $text 'Start-Process\s+-FilePath\s+[$]launcherPath\s+-ArgumentList\s+"--enterprise-ui"' 'Mục 8 không luôn mở trung tâm đủ 3 chức năng.'
Assert-SourcePattern $text '-File\s+`"[$]licenseManagerScript`"' 'Fallback của Mục 8 không mở trung tâm enterprise.'
if ($text -match '[$]licenseLaunchMode\s*=\s*if\s*\([$]script:offlineMode\)' -or $text -match 'máy chủ/máy trạm bị ẩn') {
    Add-Failure 'Mục 8 vẫn ẩn chức năng Máy chủ/Máy trạm khi Offline.'
}

if ($text -match '(?i)https?://[^''"\s]+(?:\.js|\.css|\.woff)(?:[?#''"\s]|$)') {
    Add-Failure 'Dashboard tham chiếu tài nguyên giao diện từ xa, trái với Offline mode.'
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-DASHBOARD: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-DASHBOARD: PASS (no legacy numbering + shared colored action icons + 7 direct report actions)' -ForegroundColor Green
exit 0
