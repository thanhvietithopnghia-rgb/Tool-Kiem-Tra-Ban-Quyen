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
if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf)) {
    Add-Failure 'Thiếu Giao-Dien.ps1.'
    $text = ''
} else {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Add-Failure "Lỗi cú pháp Giao-Dien.ps1: $($parseError.Message)"
    }
    $text = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

Assert-SourcePattern $text '[$]dashboardSchemaVersion\s*=\s*"2\.0"' 'Dashboard schema không phải 2.0.'
Assert-SourcePattern $text '[$]releaseVersion\s*=\s*"4\.3\.0\.8"' 'Dashboard chưa dùng release 4.3.0.8.'
Assert-SourcePattern $text '[$]releaseBuildDate\s*=\s*"2026\.07\.31"' 'Dashboard chưa dùng ngày build 2026.07.31.'
Assert-SourcePattern $text 'System\.Windows\.Forms' 'Dashboard không còn nền WinForms.'
Assert-SourcePattern $text 'System\.Drawing' 'Dashboard thiếu System.Drawing.'
Assert-SourcePattern $text 'AutoScaleMode\]::Dpi' 'Dashboard thiếu DPI scaling.'
Assert-SourcePattern $text 'Fit-MainWindowToWorkingArea' 'Dashboard thiếu điều chỉnh theo vùng làm việc.'
Assert-SourcePattern $text '[$]form\.AutoScroll\s*=\s*[$]false' 'Cửa sổ chính chưa khóa thanh cuộn.'
Assert-SourcePattern $text 'AutoScrollMargin\s*=\s*New-Object\s+System\.Drawing\.Size\(0,\s*0\)' 'Dashboard chưa loại bỏ lề cuộn dư.'
if ($text -match '[$]form\.AutoScroll\s*=\s*[$]true') { Add-Failure 'Cửa sổ chính vẫn có nhánh bật thanh cuộn.' }
Assert-SourcePattern $text '[$]form\.Size\s*=\s*New-Object\s+System\.Drawing\.Size\(1040,\s*820\)' 'Dashboard chưa dùng kích thước vừa đủ 1040 x 820.'
Assert-SourcePattern $text '[$]availableWidth\s*=\s*\[Math\]::Max\(640,\s*[$]workArea\.Width\s*-\s*16\)' 'Dashboard chưa co chiều rộng an toàn theo WorkingArea.'
Assert-SourcePattern $text '[$]availableHeight\s*=\s*\[Math\]::Max\(520,\s*[$]workArea\.Height\s*-\s*12\)' 'Dashboard chưa co chiều cao an toàn theo WorkingArea.'
Assert-SourcePattern $text 'ClientSize\.Height\s*-lt\s*760' 'Dashboard chưa chuyển sang layout gọn ở chiều cao phù hợp.'
Assert-SourcePattern $text 'ClientSize\.Height\s*-lt\s*640' 'Dashboard thiếu layout siêu gọn cho vùng làm việc thấp.'

# Modern WinForms shell: typography, cards, rounded tiles, hover states and responsive two-column layout.
Assert-SourcePattern $text 'Get-ToolUiTypography' 'Dashboard chưa dùng typography Segoe UI dùng chung.'
Assert-SourcePattern $text 'SetCompatibleTextRenderingDefault\([$]false\)' 'Dashboard chưa đồng bộ GDI+ text rendering.'
Assert-SourcePattern $text 'UseCompatibleTextRendering\s*=\s*[$]false' 'Dashboard còn control dùng text rendering cũ.'
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
Assert-SourcePattern $text 'FromArgb\(232,\s*247,\s*240\)' 'Mục 8 thiếu màu xanh riêng ở Light mode.'
Assert-SourcePattern $text 'FromArgb\(26,\s*72,\s*62\)' 'Mục 8 thiếu màu xanh riêng ở Dark mode.'
Assert-SourcePattern $text 'Get-DashboardTilePalette\s+-Tone\s+[$]tone\s+-Mode\s+[$]script:dashboardTheme\s+-Hover' 'Mục 8 chưa có hover theo palette riêng.'
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'Tool-UiTheme.ps1')
$enterpriseColorPairs = @(
    @('Light', [Drawing.Color]::FromArgb(14,111,78), [Drawing.Color]::FromArgb(232,247,240)),
    @('LightHover', [Drawing.Color]::FromArgb(14,111,78), [Drawing.Color]::FromArgb(210,240,226)),
    @('Dark', [Drawing.Color]::FromArgb(139,233,190), [Drawing.Color]::FromArgb(26,72,62)),
    @('DarkHover', [Drawing.Color]::FromArgb(139,233,190), [Drawing.Color]::FromArgb(34,91,78))
)
foreach ($colorPair in $enterpriseColorPairs) {
    $contrast = Get-ToolUiContrastRatio -Foreground $colorPair[1] -Background $colorPair[2]
    if ($contrast -lt 4.5) { Add-Failure "Màu Mục 8 $($colorPair[0]) không đạt tương phản 4.5:1." }
}

# Dashboard starts Light; the user can still toggle Dark during the session.
Assert-SourcePattern $text 'function\s+Set-DashboardTheme' 'Thiếu hàm áp dụng theme.'
Assert-SourcePattern $text 'ValidateSet\("Light",\s*"Dark"\)' 'Thiếu lựa chọn theme sáng/tối.'
Assert-SourcePattern $text 'Tool-UiTheme\.ps1' 'Dashboard chưa nạp theme dùng chung.'
Assert-SourcePattern $text 'Set-ToolUiThemePreference' 'Dashboard chưa ghi nhớ theme.'
Assert-SourcePattern $text 'TOOL_UI_THEME' 'Dashboard chưa truyền theme sang tiến trình con.'
Assert-SourcePattern $text '[$]script:dashboardTheme\s*=\s*"Light"' 'Dashboard chưa luôn mở mặc định ở giao diện sáng.'
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
if ([string]$viCatalog.'menu.6.title' -ne 'Khắc phục KMS/Activator, đưa về trạng thái gốc') {
    Add-Failure 'Tên tiếng Việt của Mục 6 chưa đúng yêu cầu.'
}
if ([string]$enCatalog.'menu.6.title' -ne 'Remediate KMS/Activator and restore original state') {
    Add-Failure 'Tên tiếng Anh của Mục 6 chưa đồng bộ.'
}
if ([string]$viCatalog.'menu.5.title' -ne 'Phần mềm & dấu hiệu can thiệp' -or
    [string]$viCatalog.'menu.5.description' -ne 'Ứng dụng đã cài, activator, crack và KMS cần xác minh' -or
    [string]$enCatalog.'menu.5.title' -ne 'Software & tampering indicators' -or
    [string]$enCatalog.'menu.5.description' -ne 'Installed apps, activators, cracks and KMS items to verify' -or
    [string]$viCatalog.'report.title.software' -ne 'Báo cáo phần mềm và dấu hiệu can thiệp' -or
    [string]$enCatalog.'report.title.software' -ne 'Software and tampering indicator report') {
    Add-Failure 'Mục 5 chưa khôi phục đúng hợp đồng giao diện/báo cáo của v4.3.0.3.'
}
if ([string]$viCatalog.'menu.7.description' -ne 'Kiểm tra key firmware; chỉ áp dụng sau khi xác nhận' -or
    [string]$viCatalog.'about.card.config.body' -notmatch 'chức năng 01–05' -or
    [string]$viCatalog.'about.card.remediation.body' -notmatch 'chức năng 06' -or
    [string]$viCatalog.'about.card.report.body' -notmatch '01–05, 09 và 10' -or
    [string]$viCatalog.'about.card.assurance.body' -notmatch 'chức năng 09' -or
    [string]$enCatalog.'about.card.config.body' -notmatch 'functions 01–05' -or
    [string]$enCatalog.'about.card.assurance.body' -notmatch 'function 10') {
    Add-Failure 'Mô tả tile/Năng lực chưa ngắn gọn hoặc chưa chỉ rõ số chức năng vi-VN/en-US.'
}
foreach ($lightCardColor in @('238,246,255','255,248,232','237,250,244','247,241,255')) {
    Assert-SourcePattern $text ([regex]::Escape("FromArgb($lightCardColor)")) "Khung Năng lực Light thiếu màu nổi bật $lightCardColor."
}
Assert-SourcePattern $text 'Get-ToolCompatibilityMetadata' 'Dashboard chưa hiển thị metadata tương thích.'
Assert-SourcePattern $text 'WindowsReleaseName' 'Dashboard thiếu trạng thái Windows release.'
Assert-SourcePattern $text 'OfficeSummary' 'Dashboard thiếu trạng thái Office.'
Assert-SourcePattern $text 'Get-ToolText' 'Dashboard chưa dùng chuỗi đa ngôn ngữ.'
Assert-SourcePattern $text 'function\s+Set-DashboardLanguage' 'Dashboard thiếu đổi ngôn ngữ trực tiếp.'
Assert-SourcePattern $text '"Tiếng Việt"' 'Dashboard thiếu lựa chọn tiếng Việt.'
Assert-SourcePattern $text '"English"' 'Dashboard thiếu lựa chọn tiếng Anh.'
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
Assert-SourcePattern $text 'LICH-SU-PHIEN-BAN\.txt' 'Dashboard chưa nhúng tài liệu lịch sử phiên bản.'
Assert-SourcePattern $text 'New-ToolProfessionalHtmlDocument' 'Hướng dẫn chưa dùng bố cục báo cáo HTML chuyên nghiệp.'
Assert-SourcePattern $text 'Convert-ToolHtmlToPdf' 'Hướng dẫn chưa hỗ trợ PDF.'
Assert-SourcePattern $text '[$]documentBasePath\s*=\s*Join-Path\s+[$]desktop\s+"[$]FilePrefix-v[$]releaseVersion-[$]\([$]script:dashboardCulture\)"' 'Hướng dẫn chưa dùng tên tệp ổn định theo phiên bản/ngôn ngữ.'
Assert-SourcePattern $text '# Source-SHA256:' 'Hướng dẫn chưa dùng SHA-256 nguồn làm khóa cache.'
Assert-SourcePattern $text '# Renderer-Revision:' 'Hướng dẫn chưa có phiên bản renderer để làm mới cache khi giao diện HTML/PDF thay đổi.'
Assert-SourcePattern $text 'Start-Process\s+-FilePath\s+[$]htmlPath' 'Hướng dẫn chưa mở trực tiếp HTML bằng trình duyệt mặc định.'
$documentationFunctionIndex = $text.IndexOf('function Open-ToolEmbeddedDocument')
$documentationOpenIndex = if ($documentationFunctionIndex -ge 0) { $text.IndexOf('Start-Process -FilePath $htmlPath', $documentationFunctionIndex) } else { -1 }
$documentationPdfIndex = if ($documentationFunctionIndex -ge 0) { $text.IndexOf('Convert-ToolHtmlToPdf -HtmlPath $htmlPath', $documentationFunctionIndex) } else { -1 }
if ($documentationFunctionIndex -lt 0 -or $documentationOpenIndex -lt 0 -or $documentationPdfIndex -lt 0 -or $documentationOpenIndex -ge $documentationPdfIndex) {
    Add-Failure 'Hướng dẫn phải mở HTML trước khi tạo PDF để giảm thời gian chờ.'
}
if ([string]$viCatalog.'about.openHistory' -ne 'Phiên bản & cập nhật' -or
    [string]$enCatalog.'about.openHistory' -ne 'Versions & updates' -or
    [string]$viCatalog.'assurance.history' -notmatch '^7\.' -or
    [string]$enCatalog.'assurance.history' -notmatch '^7\.' -or
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
    [string]$viCatalog.'enterprise.network.allow' -ne 'Online' -or
    [string]$viCatalog.'enterprise.network.disable' -ne 'Offline') {
    Add-Failure 'Nút mạng chưa dùng đúng hai nhãn ngắn Offline/Online.'
}
if ([string]$viCatalog.'enterprise.client.tab' -ne 'Chức năng máy trạm' -or
    [string]$viCatalog.'enterprise.navigation.back' -ne '← Back' -or
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
        $padded = '{0:D2}' -f $functionNumber
        if ($guideViText -notmatch "Chức năng\s+$padded\b") { Add-Failure "HDSD tiếng Việt thiếu hướng dẫn Chức năng $padded." }
        if ($guideEnText -notmatch "Function\s+$padded\b") { Add-Failure "English guide thiếu Function $padded." }
    }
    if ($guideViText -match '(?im)^\s*(Bản|Phiên bản)\s+v?\d' -or $guideEnText -match '(?im)^\s*(Version|Release)\s+v?\d') {
        Add-Failure 'HDSD còn trộn nhật ký cập nhật phiên bản thay vì chỉ hướng dẫn chức năng.'
    }
    if ($historyText -notmatch 'FileVersion:\s*\*\*4\.3\.0\.8\*\*' -or
        $historyText -notmatch 'Mô hình triển khai hiện tại' -or
        $historyText -notmatch 'Công nghệ và ngôn ngữ hiện tại') {
        Add-Failure 'Tài liệu phiên bản chưa mô tả bản mới, mô hình triển khai và công nghệ/ngôn ngữ.'
    }
    if ($historyText -match '(?m)^##\s+v\d+\.\d+\.\d+') {
        Add-Failure 'Tài liệu lịch sử vẫn tách riêng bản vá lẻ thay vì gộp theo phiên bản chính.'
    }
    foreach ($mainVersion in @('1.0','1.1','1.2','1.3','2.4','2.5','2.6','2.7','2.8','2.9','3.0','3.1','3.2','3.3','3.4','3.5','3.6','3.7','3.8','3.9','4.0','4.1','4.2','4.3')) {
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
        'Suffix="BanQuyenPhanMem"',
        'Add-Section\s+"Phan mem da cai"\s+\(Add-Table\s+[$]legacyApps\s+@\("Ten phan mem","Phien ban","Hang","Ngay cai"\)\)',
        'Add-Section\s+"Danh gia so bo ban quyen phan mem"\s+\(Add-Table\s+[$]legacySoftwareAudit',
        'Add-Section\s+"Dich vu Windows"\s+\(Add-Table\s+[$]services\s+@\("Ten","Hien thi","Trang thai","Loai khoi dong"\)\)',
        'Add-Section\s+"Kiểm tra bổ sung phần mềm bên thứ ba"',
        'Tổng quan phần mềm bên thứ ba',
        'Danh sách phần mềm bên thứ ba',
        'Tự khởi động của bên thứ ba',
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

if ($text -match '(?i)https?://[^''"\s]+(?:\.js|\.css|\.woff)') {
    Add-Failure 'Dashboard tham chiếu tài nguyên giao diện từ xa, trái với Offline mode.'
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-DASHBOARD: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-DASHBOARD: PASS (no main scroll + Light default + blank idle activity + Stop button + Online/Offline + main-version history)' -ForegroundColor Green
exit 0
