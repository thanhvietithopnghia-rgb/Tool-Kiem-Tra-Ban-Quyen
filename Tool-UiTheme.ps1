<#
    Bộ theme WinForms dùng chung cho Tool Kiểm Tra.
    Chỉ lưu tên theme (Light/Dark), không lưu dữ liệu máy hoặc thông tin license.
    Các API và control đều có trên Windows 7 SP1 / Windows PowerShell 3+.
#>

if (-not (Get-Variable -Name ToolUiContrastControls -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ToolUiContrastControls = New-Object "System.Collections.Generic.HashSet[int]"
}
if (-not (Get-Variable -Name ToolUiContrastUpdate -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ToolUiContrastUpdate = $false
}
if (-not (Get-Variable -Name ToolUiActionIconCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ToolUiActionIconCache = @{}
}

function Get-ToolUiThemeSettingsPath {
    $override = [string]$env:TOOL_UI_THEME_SETTINGS_PATH
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return [IO.Path]::GetFullPath($override)
    }
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = [IO.Path]::GetTempPath()
    }
    return (Join-Path (Join-Path $localAppData "ThanhViet-Tool-Kiem-Tra") "ui-settings.json")
}

function Get-ToolUiTheme {
    $environmentTheme = [string]$env:TOOL_UI_THEME
    if ($environmentTheme -in @("Light", "Dark")) { return $environmentTheme }
    try {
        $settingsPath = Get-ToolUiThemeSettingsPath
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $savedTheme = [string]$settings.Theme
            if ($savedTheme -in @("Light", "Dark")) {
                $env:TOOL_UI_THEME = $savedTheme
                return $savedTheme
            }
        }
    } catch {}
    $env:TOOL_UI_THEME = "Light"
    return "Light"
}

function Set-ToolUiThemePreference {
    param([Parameter(Mandatory = $true)][ValidateSet("Light", "Dark")][string]$Mode)

    $env:TOOL_UI_THEME = $Mode
    $temporaryPath = ""
    try {
        $settingsPath = Get-ToolUiThemeSettingsPath
        $settingsDirectory = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        $temporaryPath = $settingsPath + "." + [Guid]::NewGuid().ToString("N") + ".tmp"
        $json = [pscustomobject][ordered]@{
            SchemaVersion = "1.0"
            Theme = $Mode
        } | ConvertTo-Json -Depth 3
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $settingsPath, $null, $true)
        } else {
            [IO.File]::Move($temporaryPath, $settingsPath)
        }
        return $true
    } catch {
        try {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath -PathType Leaf)) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        return $false
    }
}

function Get-ToolUiPalette {
    param([ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme))

    if ($Mode -eq "Dark") {
        return [pscustomobject][ordered]@{
            Mode           = "Dark"
            Background     = [Drawing.Color]::FromArgb(20, 24, 33)
            Surface        = [Drawing.Color]::FromArgb(31, 36, 48)
            SurfaceAlt     = [Drawing.Color]::FromArgb(39, 46, 61)
            Input          = [Drawing.Color]::FromArgb(24, 29, 39)
            Primary        = [Drawing.Color]::FromArgb(126, 174, 255)
            Text           = [Drawing.Color]::FromArgb(226, 231, 239)
            Muted          = [Drawing.Color]::FromArgb(164, 174, 192)
            Border         = [Drawing.Color]::FromArgb(83, 96, 117)
            Button         = [Drawing.Color]::FromArgb(39, 54, 78)
            ButtonHover    = [Drawing.Color]::FromArgb(49, 68, 98)
            InfoSurface    = [Drawing.Color]::FromArgb(30, 44, 65)
            SuccessSurface = [Drawing.Color]::FromArgb(29, 63, 52)
            WarningSurface = [Drawing.Color]::FromArgb(78, 57, 30)
            PurpleSurface  = [Drawing.Color]::FromArgb(64, 48, 83)
            Success        = [Drawing.Color]::FromArgb(114, 213, 155)
            Warning        = [Drawing.Color]::FromArgb(255, 199, 117)
            Danger         = [Drawing.Color]::FromArgb(255, 138, 138)
        }
    }

    return [pscustomobject][ordered]@{
        Mode           = "Light"
        Background     = [Drawing.Color]::FromArgb(244, 246, 249)
        Surface        = [Drawing.Color]::White
        SurfaceAlt     = [Drawing.Color]::FromArgb(244, 246, 249)
        Input          = [Drawing.Color]::White
        Primary        = [Drawing.Color]::FromArgb(18, 59, 116)
        Text           = [Drawing.Color]::FromArgb(52, 64, 84)
        Muted          = [Drawing.Color]::FromArgb(102, 112, 133)
        Border         = [Drawing.Color]::FromArgb(148, 163, 184)
        Button         = [Drawing.Color]::FromArgb(234, 242, 255)
        ButtonHover    = [Drawing.Color]::FromArgb(215, 229, 250)
        InfoSurface    = [Drawing.Color]::FromArgb(235, 244, 255)
        SuccessSurface = [Drawing.Color]::FromArgb(232, 247, 240)
        WarningSurface = [Drawing.Color]::FromArgb(255, 248, 230)
        PurpleSurface  = [Drawing.Color]::FromArgb(245, 238, 255)
        Success        = [Drawing.Color]::FromArgb(28, 125, 69)
        Warning        = [Drawing.Color]::DarkOrange
        Danger         = [Drawing.Color]::DarkRed
    }
}

function Get-ToolUiButtonRole {
    param([Parameter(Mandatory = $true)][Windows.Forms.Button]$Button)

    $text = ([string]$Button.Text).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) { return "Default" }

    switch -Regex ($text) {
        'sao chép|copy' { return "Copy" }
        'mở.+thư mục|chọn.+thư mục|mở.+tệp|open.+folder|open.+directory|choose.+directory|select.+folder|open.+file' { return "Folder" }
        'tự động làm sạch|automatic safe cleanup|auto(?:matic)? cleanup' { return "AutoFix" }
        'khôi phục|restore' { return "Restore" }
        'backup|sao lưu' { return "Backup" }
        'xóa|delete|remove' { return "Delete" }
        'dừng|stop' { return "Stop" }
        'trở về|quay lại|\bback\b|go back' { return "Back" }
        'đóng|close|hủy|cancel|thoát|exit' { return "Close" }
        'bỏ chọn|clear all|select none|deselect' { return "Clear" }
        'chọn tất cả|select all' { return "SelectAll" }
        'lưu|save' { return "Save" }
        'áp dụng|apply|xác nhận|confirm|đồng ý|\bok\b' { return "Apply" }
        'quét lại|làm mới|refresh|retry|recheck|rescan' { return "Refresh" }
        'khắc phục|sửa nhanh|sửa lỗi|repair|remediat|cleanup|làm sạch|gỡ' { return "Repair" }
        'kiểm tra|điều tra|phát hiện|thử kết nối|quét|scan|inspect|forensic|audit|check|discover|connection test' { return "Scan" }
        'báo cáo|report' { return "Report" }
        'xuất|export' { return "Export" }
        'lịch sử|history|timeline|nhật ký' { return "History" }
        'hướng dẫn|guide|help' { return "Guide" }
        'plugin|extension' { return "Plugin" }
        'chứng chỉ|certificate|authenticode|bảo đảm|assurance' { return "Shield" }
        'mạng|online|offline|network|firewall|lan|ghép nối|pair|enroll|kết nối|connect' { return "Network" }
        'cài đặt|giao diện|theme|settings|preference' { return "Settings" }
        'giới thiệu|about|information|thông tin' { return "Info" }
        'kích hoạt|activation|license|bản quyền|product key|nhập key|redeem|store' { return "License" }
        'gửi|send' { return "Export" }
        'bật|enable' { return "Apply" }
        'tắt|disable' { return "Stop" }
        'bắt đầu|start|tiếp tục|continue|chạy|tạo|create|\brun\b|open' { return "Start" }
        default { return "Default" }
    }
}

function Get-ToolUiButtonTone {
    param([Parameter(Mandatory = $true)][string]$Role)

    switch ($Role) {
        { $_ -in @("Backup", "Save", "Apply", "SelectAll", "License") } { return "Success" }
        { $_ -in @("Repair") } { return "Warning" }
        { $_ -in @("AutoFix", "Delete", "Stop") } { return "Danger" }
        { $_ -in @("Copy", "History", "Plugin") } { return "Purple" }
        { $_ -in @("Folder", "Report", "Export", "Network") } { return "Teal" }
        { $_ -in @("Back", "Close", "Clear", "Settings", "Default") } { return "Neutral" }
        default { return "Primary" }
    }
}

function Get-ToolUiButtonPalette {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Primary", "Success", "Warning", "Danger", "Purple", "Teal", "Neutral")]
        [string]$Tone,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )

    $dark = [bool]($Mode -eq "Dark")
    if ($dark) {
        switch ($Tone) {
            "Success" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(23,55,45); Fore=[Drawing.Color]::FromArgb(142,237,190); Border=[Drawing.Color]::FromArgb(53,128,92); Hover=[Drawing.Color]::FromArgb(31,75,60); Accent=[Drawing.Color]::FromArgb(28,180,111) } }
            "Warning" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(82,57,24); Fore=[Drawing.Color]::FromArgb(255,205,128); Border=[Drawing.Color]::FromArgb(154,105,43); Hover=[Drawing.Color]::FromArgb(108,76,30); Accent=[Drawing.Color]::FromArgb(235,150,30) } }
            "Danger"  { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(78,37,43); Fore=[Drawing.Color]::FromArgb(255,166,166); Border=[Drawing.Color]::FromArgb(156,76,86); Hover=[Drawing.Color]::FromArgb(104,49,57); Accent=[Drawing.Color]::FromArgb(225,86,94) } }
            "Purple"  { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(64,48,83); Fore=[Drawing.Color]::FromArgb(213,180,255); Border=[Drawing.Color]::FromArgb(116,83,151); Hover=[Drawing.Color]::FromArgb(82,61,106); Accent=[Drawing.Color]::FromArgb(156,100,230) } }
            "Teal"    { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(22,62,61); Fore=[Drawing.Color]::FromArgb(134,231,220); Border=[Drawing.Color]::FromArgb(46,125,119); Hover=[Drawing.Color]::FromArgb(29,81,79); Accent=[Drawing.Color]::FromArgb(0,170,150) } }
            "Neutral" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(39,46,61); Fore=[Drawing.Color]::FromArgb(226,231,239); Border=[Drawing.Color]::FromArgb(83,96,117); Hover=[Drawing.Color]::FromArgb(49,58,77); Accent=[Drawing.Color]::FromArgb(118,134,158) } }
            default   { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(30,52,82); Fore=[Drawing.Color]::FromArgb(164,205,255); Border=[Drawing.Color]::FromArgb(72,118,176); Hover=[Drawing.Color]::FromArgb(42,69,108); Accent=[Drawing.Color]::FromArgb(65,150,255) } }
        }
    }

    switch ($Tone) {
        "Success" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(231,248,239); Fore=[Drawing.Color]::FromArgb(0,100,62); Border=[Drawing.Color]::FromArgb(112,184,147); Hover=[Drawing.Color]::FromArgb(208,241,225); Accent=[Drawing.Color]::FromArgb(0,158,96) } }
        "Warning" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(255,247,224); Fore=[Drawing.Color]::FromArgb(128,64,0); Border=[Drawing.Color]::FromArgb(224,172,82); Hover=[Drawing.Color]::FromArgb(255,235,184); Accent=[Drawing.Color]::FromArgb(235,138,0) } }
        "Danger"  { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(255,236,236); Fore=[Drawing.Color]::FromArgb(151,35,35); Border=[Drawing.Color]::FromArgb(225,126,126); Hover=[Drawing.Color]::FromArgb(255,215,215); Accent=[Drawing.Color]::FromArgb(200,50,55) } }
        "Purple"  { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(246,238,255); Fore=[Drawing.Color]::FromArgb(98,53,156); Border=[Drawing.Color]::FromArgb(176,132,224); Hover=[Drawing.Color]::FromArgb(233,218,252); Accent=[Drawing.Color]::FromArgb(126,75,214) } }
        "Teal"    { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(231,248,246); Fore=[Drawing.Color]::FromArgb(0,101,91); Border=[Drawing.Color]::FromArgb(94,179,167); Hover=[Drawing.Color]::FromArgb(207,239,234); Accent=[Drawing.Color]::FromArgb(0,132,112) } }
        "Neutral" { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(244,246,249); Fore=[Drawing.Color]::FromArgb(52,64,84); Border=[Drawing.Color]::FromArgb(148,163,184); Hover=[Drawing.Color]::FromArgb(228,233,240); Accent=[Drawing.Color]::FromArgb(90,105,130) } }
        default   { return [pscustomobject]@{ Back=[Drawing.Color]::FromArgb(231,241,255); Fore=[Drawing.Color]::FromArgb(0,75,170); Border=[Drawing.Color]::FromArgb(123,165,222); Hover=[Drawing.Color]::FromArgb(211,229,252); Accent=[Drawing.Color]::FromArgb(0,120,212) } }
    }
}

function Get-ToolUiPrimaryActionPalette {
    param([ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme))

    if ($Mode -eq "Dark") {
        return [pscustomobject][ordered]@{
            Back    = [Drawing.Color]::FromArgb(126, 174, 255)
            Fore    = [Drawing.Color]::FromArgb(18, 26, 38)
            Border  = [Drawing.Color]::FromArgb(154, 192, 255)
            Hover   = [Drawing.Color]::FromArgb(154, 192, 255)
            Pressed = [Drawing.Color]::FromArgb(104, 154, 235)
        }
    }

    return [pscustomobject][ordered]@{
        Back    = [Drawing.Color]::FromArgb(18, 59, 116)
        Fore    = [Drawing.Color]::White
        Border  = [Drawing.Color]::FromArgb(12, 46, 92)
        Hover   = [Drawing.Color]::FromArgb(27, 78, 145)
        Pressed = [Drawing.Color]::FromArgb(12, 46, 92)
    }
}

function Set-ToolUiPrimaryActionButtonVisual {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Button]$Button,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )

    # Giữ icon/spacing chung, sau đó áp palette CTA có tương phản ổn định ở cả
    # trạng thái thường, hover và nhấn. Việc chỉ đổi BackColor/ForeColor khiến
    # WinForms giữ MouseOverBackColor cũ và có thể làm chữ trắng bị nhòe/mất.
    Set-ToolUiActionButtonVisual -Button $Button -Mode $Mode
    $visual = Get-ToolUiPrimaryActionPalette -Mode $Mode
    $Button.UseVisualStyleBackColor = $false
    $Button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $Button.BackColor = $visual.Back
    $Button.ForeColor = $visual.Fore
    $Button.FlatAppearance.BorderColor = $visual.Border
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.MouseOverBackColor = $visual.Hover
    $Button.FlatAppearance.MouseDownBackColor = $visual.Pressed
}

function New-ToolUiActionIconBitmap {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][Drawing.Color]$Accent,
        [ValidateRange(16, 32)][int]$Size = 20
    )

    # Chừa 4 px trong suốt bên phải để icon không dính sát chữ trên WinForms cũ.
    $bitmap = New-Object Drawing.Bitmap(($Size + 4), $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $accentBrush = New-Object Drawing.SolidBrush($Accent)
    $whiteBrush = New-Object Drawing.SolidBrush([Drawing.Color]::White)
    $whitePen = New-Object Drawing.Pen([Drawing.Color]::White, 1.8)
    $whiteThinPen = New-Object Drawing.Pen([Drawing.Color]::White, 1.35)
    foreach ($pen in @($whitePen, $whiteThinPen)) {
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
    }
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.ScaleTransform([single]($Size / 24.0), [single]($Size / 24.0))
        $graphics.FillEllipse($accentBrush, 1, 1, 22, 22)

        switch ($Role) {
            "Copy" {
                $graphics.DrawRectangle($whiteThinPen, 6, 6, 9, 11)
                $graphics.DrawRectangle($whitePen, 9, 9, 9, 11)
            }
            "Folder" {
                $graphics.FillPolygon($whiteBrush, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(5,8)), (New-Object Drawing.PointF(10,8)),
                    (New-Object Drawing.PointF(12,10)), (New-Object Drawing.PointF(19,10)),
                    (New-Object Drawing.PointF(18,18)), (New-Object Drawing.PointF(5,18))))
                $graphics.DrawLine($whiteThinPen, 6, 11, 18, 11)
            }
            "Back" {
                $graphics.DrawLine($whitePen, 7, 12, 18, 12)
                $graphics.DrawLine($whitePen, 7, 12, 11, 8)
                $graphics.DrawLine($whitePen, 7, 12, 11, 16)
            }
            { $_ -in @("Close", "Delete") } {
                $graphics.DrawLine($whitePen, 8, 8, 16, 16)
                $graphics.DrawLine($whitePen, 16, 8, 8, 16)
            }
            "Stop" { $graphics.FillRectangle($whiteBrush, 8, 8, 8, 8) }
            "Save" {
                $graphics.DrawRectangle($whitePen, 6, 5, 12, 14)
                $graphics.FillRectangle($whiteBrush, 9, 6, 6, 4)
                $graphics.DrawRectangle($whiteThinPen, 9, 13, 6, 5)
            }
            "Backup" {
                $graphics.DrawLine($whitePen, 12, 6, 12, 15)
                $graphics.DrawLine($whitePen, 8, 11, 12, 15)
                $graphics.DrawLine($whitePen, 16, 11, 12, 15)
                $graphics.DrawLine($whitePen, 7, 18, 17, 18)
            }
            "Restore" {
                $graphics.DrawArc($whitePen, 6, 6, 12, 12, 35, 285)
                $graphics.FillPolygon($whiteBrush, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(5,8)), (New-Object Drawing.PointF(10,7)),
                    (New-Object Drawing.PointF(8,12))))
            }
            { $_ -in @("Repair", "AutoFix") } {
                $graphics.DrawLine($whitePen, 8, 17, 16, 9)
                $graphics.DrawArc($whitePen, 13, 6, 5, 5, 25, 240)
                $graphics.DrawEllipse($whiteThinPen, 6, 15, 4, 4)
            }
            "Scan" {
                $graphics.DrawEllipse($whitePen, 6, 6, 9, 9)
                $graphics.DrawLine($whitePen, 14, 14, 18, 18)
            }
            "Report" {
                $graphics.DrawRectangle($whitePen, 7, 5, 10, 14)
                $graphics.DrawLine($whiteThinPen, 9, 9, 15, 9)
                $graphics.DrawLine($whiteThinPen, 9, 12, 15, 12)
                $graphics.DrawLine($whiteThinPen, 9, 15, 14, 15)
            }
            "Export" {
                $graphics.DrawLine($whitePen, 12, 5, 12, 15)
                $graphics.DrawLine($whitePen, 8, 9, 12, 5)
                $graphics.DrawLine($whitePen, 16, 9, 12, 5)
                $graphics.DrawLine($whitePen, 7, 18, 17, 18)
            }
            "History" {
                $graphics.DrawEllipse($whitePen, 6, 6, 12, 12)
                $graphics.DrawLine($whiteThinPen, 12, 8, 12, 12)
                $graphics.DrawLine($whiteThinPen, 12, 12, 15, 14)
            }
            "Guide" {
                $graphics.DrawRectangle($whiteThinPen, 5, 7, 6, 11)
                $graphics.DrawRectangle($whiteThinPen, 13, 7, 6, 11)
                $graphics.DrawLine($whitePen, 12, 7, 12, 18)
            }
            "Plugin" {
                foreach ($x in @(7,13)) { foreach ($y in @(7,13)) { $graphics.FillRectangle($whiteBrush, $x, $y, 4, 4) } }
            }
            "Shield" {
                $graphics.FillPolygon($whiteBrush, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(12,4)), (New-Object Drawing.PointF(18,7)),
                    (New-Object Drawing.PointF(17,15)), (New-Object Drawing.PointF(12,20)),
                    (New-Object Drawing.PointF(7,15)), (New-Object Drawing.PointF(6,7))))
                $checkPen = New-Object Drawing.Pen($Accent, 1.7)
                try {
                    $checkPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
                    $checkPen.EndCap = [Drawing.Drawing2D.LineCap]::Round
                    $graphics.DrawLines($checkPen, [Drawing.PointF[]]@(
                        (New-Object Drawing.PointF(9,12)), (New-Object Drawing.PointF(11,14)),
                        (New-Object Drawing.PointF(15,10))))
                } finally { $checkPen.Dispose() }
            }
            { $_ -in @("Apply", "SelectAll") } {
                $graphics.DrawLines($whitePen, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(7,12)), (New-Object Drawing.PointF(10,15)),
                    (New-Object Drawing.PointF(17,8))))
            }
            "Clear" { $graphics.DrawLine($whitePen, 7, 12, 17, 12) }
            "Refresh" {
                $graphics.DrawArc($whitePen, 6, 6, 12, 12, 35, 240)
                $graphics.FillPolygon($whiteBrush, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(18,7)), (New-Object Drawing.PointF(18,12)),
                    (New-Object Drawing.PointF(14,9))))
            }
            "Network" {
                $graphics.DrawLine($whiteThinPen, 8, 15, 12, 9)
                $graphics.DrawLine($whiteThinPen, 12, 9, 17, 15)
                $graphics.FillEllipse($whiteBrush, 6, 14, 4, 4)
                $graphics.FillEllipse($whiteBrush, 10, 6, 4, 4)
                $graphics.FillEllipse($whiteBrush, 15, 14, 4, 4)
            }
            "Settings" {
                $graphics.DrawEllipse($whitePen, 8, 8, 8, 8)
                $graphics.FillEllipse($whiteBrush, 10, 10, 4, 4)
                foreach ($angle in @(0,45,90,135)) {
                    $radians = $angle * [Math]::PI / 180
                    $dx = [single](5 * [Math]::Cos($radians)); $dy = [single](5 * [Math]::Sin($radians))
                    $graphics.DrawLine($whiteThinPen, [single](12-$dx), [single](12-$dy), [single](12+$dx), [single](12+$dy))
                }
            }
            "Info" {
                $graphics.DrawEllipse($whiteThinPen, 7, 5, 10, 14)
                $graphics.FillEllipse($whiteBrush, 11, 8, 2, 2)
                $graphics.DrawLine($whitePen, 12, 12, 12, 16)
            }
            "License" {
                $graphics.DrawRectangle($whitePen, 6, 7, 12, 10)
                $graphics.DrawLine($whiteThinPen, 8, 10, 16, 10)
                $graphics.DrawLine($whiteThinPen, 8, 13, 13, 13)
            }
            default {
                $graphics.FillPolygon($whiteBrush, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(9,7)), (New-Object Drawing.PointF(17,12)),
                    (New-Object Drawing.PointF(9,17))))
            }
        }
    } finally {
        $whiteThinPen.Dispose()
        $whitePen.Dispose()
        $whiteBrush.Dispose()
        $accentBrush.Dispose()
        $graphics.Dispose()
    }
    return $bitmap
}

function Get-ToolUiActionIcon {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][Drawing.Color]$Accent,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme),
        [ValidateRange(16, 32)][int]$Size = 20
    )
    $cacheKey = "{0}|{1}|{2}|{3}" -f $Role, $Mode, $Size, $Accent.ToArgb()
    if (-not $script:ToolUiActionIconCache.ContainsKey($cacheKey)) {
        $script:ToolUiActionIconCache[$cacheKey] = New-ToolUiActionIconBitmap -Role $Role -Accent $Accent -Size $Size
    }
    return $script:ToolUiActionIconCache[$cacheKey]
}

function Set-ToolUiRoundedButtonRegion {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Button]$Button,
        [ValidateRange(3, 12)][int]$Radius = 7
    )
    if ($Button.AutoSize -or $Button.Width -lt 12 -or $Button.Height -lt 12) { return }
    $diameter = [single]([Math]::Min($Radius * 2, [Math]::Min($Button.Width, $Button.Height)))
    $width = [single]$Button.Width
    $height = [single]$Button.Height
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    try {
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc(($width - $diameter - 1), 0, $diameter, $diameter, 270, 90)
        $path.AddArc(($width - $diameter - 1), ($height - $diameter - 1), $diameter, $diameter, 0, 90)
        $path.AddArc(0, ($height - $diameter - 1), $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $oldRegion = $Button.Region
        $Button.Region = New-Object Drawing.Region($path)
        if ($oldRegion) { $oldRegion.Dispose() }
    } finally {
        $path.Dispose()
    }
}

function Get-ToolUiButtonRequiredWidth {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Button]$Button,
        [ValidateRange(4, 40)][int]$HorizontalSafety = 14
    )

    if ([string]::IsNullOrWhiteSpace([string]$Button.Text)) {
        return [Math]::Max(1, $Button.Padding.Horizontal + $HorizontalSafety)
    }
    $textFlags = [Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix
    $textWidth = 0
    foreach ($textLine in @(([string]$Button.Text) -split "`r?`n")) {
        $lineWidth = [int][Windows.Forms.TextRenderer]::MeasureText($textLine, $Button.Font, [Drawing.Size]::Empty, $textFlags).Width
        if ($lineWidth -gt $textWidth) { $textWidth = $lineWidth }
    }
    $imageWidth = if ($Button.Image -and $Button.TextImageRelation -ne [Windows.Forms.TextImageRelation]::Overlay) { [int]$Button.Image.Width } else { 0 }
    return [int]($textWidth + $imageWidth + $Button.Padding.Horizontal + $HorizontalSafety)
}

function Set-ToolUiFlowButtonSpacing {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.FlowLayoutPanel]$Panel,
        [ValidateRange(0, 12)][int]$PreferredSideMargin = 3
    )

    $buttons = @($Panel.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Visible })
    if ($buttons.Count -eq 0) { return }

    $buttonWidth = 0
    foreach ($button in $buttons) { $buttonWidth += [int]$button.Width }
    $availableWidth = [Math]::Max(0, $Panel.ClientSize.Width - $Panel.Padding.Horizontal)
    $sideMargin = 0
    if ($availableWidth -gt $buttonWidth) {
        $sideMargin = [Math]::Min(
            $PreferredSideMargin,
            [Math]::Max(0, [Math]::Floor(($availableWidth - $buttonWidth) / (2 * $buttons.Count))))
    }

    foreach ($button in $buttons) {
        # Preserve the normal vertical breathing room while collapsing only the
        # horizontal gaps when a DPI-scaled/localized footer becomes narrow.
        $button.Margin = New-Object Windows.Forms.Padding($sideMargin, 3, $sideMargin, 3)
    }
    $Panel.AutoScroll = ($buttonWidth -gt $availableWidth)
    $Panel.PerformLayout()
}

function Set-ToolUiActionButtonVisual {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Button]$Button,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme),
        [switch]$PreserveColors
    )

    $role = Get-ToolUiButtonRole -Button $Button
    $tone = Get-ToolUiButtonTone -Role $role
    $visual = Get-ToolUiButtonPalette -Tone $tone -Mode $Mode
    $Button.UseVisualStyleBackColor = $false
    # Nội dung localization dùng dấu & theo nghĩa ký tự hiển thị (ví dụ
    # "Phiên bản & cập nhật"), không phải phím tắt mnemonic của WinForms.
    # Tắt mnemonic cho toàn bộ nút để không làm mất ký tự này trên giao diện.
    $Button.UseMnemonic = $false
    $Button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $Button.Cursor = [Windows.Forms.Cursors]::Hand
    if (-not $PreserveColors) {
        $Button.BackColor = $visual.Back
        $Button.ForeColor = $visual.Fore
        $Button.FlatAppearance.BorderColor = $visual.Border
        $Button.FlatAppearance.BorderSize = 1
        $Button.FlatAppearance.MouseOverBackColor = $visual.Hover
        $Button.FlatAppearance.MouseDownBackColor = $visual.Hover
    }

    if ($Button.Width -ge 90 -and $Button.Height -ge 26 -and -not [string]::IsNullOrWhiteSpace([string]$Button.Text)) {
        $iconSize = if ($Button.Height -le 28) { 16 } elseif ($Button.Height -ge 40) { 22 } else { 18 }
        $marker = "ToolUiIcon:{0}:{1}:{2}" -f $role, $Mode, $iconSize
        $managedImage = ([string]$Button.AccessibleDescription).StartsWith("ToolUiIcon:", [StringComparison]::Ordinal)
        if ($null -eq $Button.Image -or $managedImage) {
            $Button.Image = Get-ToolUiActionIcon -Role $role -Accent $visual.Accent -Mode $Mode -Size $iconSize
            $Button.AccessibleDescription = $marker
            $Button.ImageAlign = [Drawing.ContentAlignment]::MiddleLeft
            $Button.TextImageRelation = [Windows.Forms.TextImageRelation]::ImageBeforeText
            $Button.Padding = New-Object Windows.Forms.Padding(10, 0, 9, 0)
        }
    }

    # FlowLayoutPanel có thể mở rộng nút an toàn mà không làm chồng các control.
    # Sau khi thêm icon, tăng chiều rộng theo kích thước ưu tiên để chữ không bị
    # cắt ở DPI cao hoặc với nhãn dài hơn trong vi-VN/en-US.
    if ($Button.Parent -is [Windows.Forms.FlowLayoutPanel] -and
        $Button.Dock -eq [Windows.Forms.DockStyle]::None -and
        -not [string]::IsNullOrWhiteSpace([string]$Button.Text)) {
        $safeWidth = Get-ToolUiButtonRequiredWidth -Button $Button
        if ($Button.Width -lt $safeWidth) {
            $Button.Width = [int]$safeWidth
        }
    }
    Set-ToolUiRoundedButtonRegion -Button $Button -Radius $(if ($Button.Height -ge 40) { 8 } else { 6 })
}

function Set-ToolUiActionButtons {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Root,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )
    if ($Root -is [Windows.Forms.Button]) {
        Set-ToolUiActionButtonVisual -Button $Root -Mode $Mode
    }
    foreach ($child in $Root.Controls) {
        Set-ToolUiActionButtons -Root $child -Mode $Mode
    }
}

function Set-ToolUiLiteralText {
    param([Parameter(Mandatory = $true)][Windows.Forms.Control]$Root)

    if ($Root -is [Windows.Forms.ButtonBase] -or $Root -is [Windows.Forms.Label]) {
        $Root.UseMnemonic = $false
    }
    foreach ($child in $Root.Controls) {
        Set-ToolUiLiteralText -Root $child
    }
}

function Get-ToolUiStatusColor {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Primary", "Text", "Muted", "Success", "Warning", "Danger")][string]$Kind,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )
    $palette = Get-ToolUiPalette -Mode $Mode
    return $palette.$Kind
}

function Get-ToolUiColorKey {
    param([Drawing.Color]$Color)
    return ("{0},{1},{2}" -f $Color.R, $Color.G, $Color.B)
}

function Get-ToolUiRelativeLuminance {
    param([Parameter(Mandatory = $true)][Drawing.Color]$Color)
    $channels = @(
        ([double]$Color.R / 255.0)
        ([double]$Color.G / 255.0)
        ([double]$Color.B / 255.0)
    )
    $linear = @()
    foreach ($channel in $channels) {
        $linear += if ($channel -le 0.03928) {
            $channel / 12.92
        } else {
            [Math]::Pow((($channel + 0.055) / 1.055), 2.4)
        }
    }
    return (0.2126 * $linear[0]) + (0.7152 * $linear[1]) + (0.0722 * $linear[2])
}

function Get-ToolUiContrastRatio {
    param(
        [Parameter(Mandatory = $true)][Drawing.Color]$Foreground,
        [Parameter(Mandatory = $true)][Drawing.Color]$Background
    )
    $first = Get-ToolUiRelativeLuminance -Color $Foreground
    $second = Get-ToolUiRelativeLuminance -Color $Background
    $lighter = [Math]::Max($first, $second)
    $darker = [Math]::Min($first, $second)
    return (($lighter + 0.05) / ($darker + 0.05))
}

function Update-ToolUiDynamicTextColor {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Control,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )
    if ($script:ToolUiContrastUpdate) { return }
    $palette = Get-ToolUiPalette -Mode $Mode
    $colorKey = Get-ToolUiColorKey $Control.ForeColor
    $target = switch ($colorKey) {
        "18,59,116" { $palette.Primary; break }
        "126,174,255" { $palette.Primary; break }
        "52,64,84" { $palette.Text; break }
        "226,231,239" { $palette.Text; break }
        "90,98,112" { $palette.Muted; break }
        "102,112,133" { $palette.Muted; break }
        "164,174,192" { $palette.Muted; break }
        "0,100,0" { $palette.Success; break }
        "28,125,69" { $palette.Success; break }
        "114,213,155" { $palette.Success; break }
        "255,140,0" { $palette.Warning; break }
        "255,199,117" { $palette.Warning; break }
        "139,0,0" { $palette.Danger; break }
        "255,138,138" { $palette.Danger; break }
        default { $null }
    }
    if ($target -and $Control.ForeColor.ToArgb() -ne $target.ToArgb()) {
        $script:ToolUiContrastUpdate = $true
        try { $Control.ForeColor = $target } finally { $script:ToolUiContrastUpdate = $false }
    }
}

function Register-ToolUiDynamicContrast {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Root,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )
    $controlId = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Root)
    if ($script:ToolUiContrastControls.Add($controlId)) {
        $Root.Add_ForeColorChanged({
            param($sender, $eventArgs)
            Update-ToolUiDynamicTextColor -Control $sender -Mode (Get-ToolUiTheme)
        })
    }
    Update-ToolUiDynamicTextColor -Control $Root -Mode $Mode
    foreach ($child in $Root.Controls) {
        Register-ToolUiDynamicContrast -Root $child -Mode $Mode
    }
}

function Set-ToolUiTabTheme {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.TabControl]$TabControl,
        [Parameter(Mandatory = $true)][ValidateSet("Light", "Dark")][string]$Mode
    )
    if ($Mode -ne "Dark" -or $TabControl.DrawMode -eq [Windows.Forms.TabDrawMode]::OwnerDrawFixed) { return }
    $TabControl.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $TabControl.Add_DrawItem({
        param($sender, $eventArgs)
        $palette = Get-ToolUiPalette -Mode "Dark"
        $selected = [bool]($sender.SelectedIndex -eq $eventArgs.Index)
        $backColor = if ($selected) { $palette.Button } else { $palette.SurfaceAlt }
        $foreColor = if ($selected) { $palette.Primary } else { $palette.Text }
        $backBrush = New-Object Drawing.SolidBrush($backColor)
        $textBrush = New-Object Drawing.SolidBrush($foreColor)
        $format = New-Object Drawing.StringFormat
        try {
            $format.Alignment = [Drawing.StringAlignment]::Center
            $format.LineAlignment = [Drawing.StringAlignment]::Center
            $bounds = New-Object Drawing.RectangleF
            $bounds.X = [float]$eventArgs.Bounds.X
            $bounds.Y = [float]$eventArgs.Bounds.Y
            $bounds.Width = [float]$eventArgs.Bounds.Width
            $bounds.Height = [float]$eventArgs.Bounds.Height
            $eventArgs.Graphics.FillRectangle($backBrush, $eventArgs.Bounds)
            $eventArgs.Graphics.DrawString($sender.TabPages[$eventArgs.Index].Text, $sender.Font, $textBrush, $bounds, $format)
        } finally {
            $format.Dispose()
            $backBrush.Dispose()
            $textBrush.Dispose()
        }
    })
}

function Set-ToolControlTheme {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Control,
        [Parameter(Mandatory = $true)][ValidateSet("Light", "Dark")][string]$Mode
    )

    if ($Mode -ne "Dark") { return }
    $palette = Get-ToolUiPalette -Mode $Mode
    $originalBack = Get-ToolUiColorKey $Control.BackColor
    $originalFore = Get-ToolUiColorKey $Control.ForeColor

    if ($Control -is [Windows.Forms.Form]) {
        $Control.BackColor = $palette.Background
        $Control.ForeColor = $palette.Text
    } elseif ($Control -is [Windows.Forms.TabControl]) {
        $Control.BackColor = $palette.Background
        $Control.ForeColor = $palette.Text
        Set-ToolUiTabTheme -TabControl $Control -Mode $Mode
    } elseif ($Control -is [Windows.Forms.TabPage]) {
        $Control.BackColor = switch ($originalBack) {
            "255,248,230" { $palette.WarningSurface; break }
            "232,247,240" { $palette.SuccessSurface; break }
            "245,238,255" { $palette.PurpleSurface; break }
            "239,246,255" { $palette.InfoSurface; break }
            "240,253,250" { $palette.SuccessSurface; break }
            default { $palette.Surface }
        }
        $Control.ForeColor = $palette.Text
    } elseif ($Control -is [Windows.Forms.RichTextBox]) {
        $Control.BackColor = $palette.Input
        $Control.ForeColor = $palette.Text
        if ($Control.TextLength -gt 0) {
            $selectionStart = $Control.SelectionStart
            $selectionLength = $Control.SelectionLength
            $Control.SelectAll()
            $Control.SelectionColor = $palette.Text
            $Control.SelectionBackColor = $palette.Input
            $Control.SelectionStart = [Math]::Min($selectionStart, $Control.TextLength)
            $Control.SelectionLength = [Math]::Min($selectionLength, $Control.TextLength - $Control.SelectionStart)
        }
    } elseif ($Control -is [Windows.Forms.ListView]) {
        $Control.BackColor = $palette.Input
        $Control.ForeColor = $palette.Text
        foreach ($item in $Control.Items) {
            $item.BackColor = $palette.Input
            $item.ForeColor = $palette.Text
        }
    } elseif ($Control -is [Windows.Forms.TextBoxBase] -or
              $Control -is [Windows.Forms.ListBox] -or
              $Control -is [Windows.Forms.TreeView] -or
              $Control -is [Windows.Forms.ComboBox] -or
              $Control -is [Windows.Forms.NumericUpDown]) {
        $Control.BackColor = $palette.Input
        $Control.ForeColor = $palette.Text
    } elseif ($Control -is [Windows.Forms.DataGridView]) {
        $Control.EnableHeadersVisualStyles = $false
        $Control.BackgroundColor = $palette.Input
        $Control.GridColor = $palette.Border
        $Control.DefaultCellStyle.BackColor = $palette.Input
        $Control.DefaultCellStyle.ForeColor = $palette.Text
        $Control.DefaultCellStyle.SelectionBackColor = $palette.Button
        $Control.DefaultCellStyle.SelectionForeColor = $palette.Text
        $Control.ColumnHeadersDefaultCellStyle.BackColor = $palette.SurfaceAlt
        $Control.ColumnHeadersDefaultCellStyle.ForeColor = $palette.Text
    } elseif ($Control -is [Windows.Forms.Button]) {
        $Control.UseVisualStyleBackColor = $false
        $Control.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $Control.FlatAppearance.BorderColor = $palette.Border
        $Control.FlatAppearance.BorderSize = 1
        $Control.BackColor = switch ($originalBack) {
            "255,248,230" { $palette.WarningSurface; break }
            "232,247,240" { $palette.SuccessSurface; break }
            "245,238,255" { $palette.PurpleSurface; break }
            "235,244,255" { $palette.InfoSurface; break }
            default { $palette.Button }
        }
        $Control.FlatAppearance.MouseOverBackColor = $palette.ButtonHover
        $Control.ForeColor = if ($originalFore -eq "128,64,0") { $palette.Warning } else { $palette.Text }
    } elseif ($Control -is [Windows.Forms.LinkLabel]) {
        $Control.ForeColor = $palette.Primary
        $Control.LinkColor = $palette.Primary
        $Control.ActiveLinkColor = $palette.Warning
        $Control.VisitedLinkColor = $palette.Muted
    } elseif ($Control -is [Windows.Forms.Label] -or
              $Control -is [Windows.Forms.CheckBox] -or
              $Control -is [Windows.Forms.RadioButton] -or
              $Control -is [Windows.Forms.GroupBox]) {
        $Control.ForeColor = switch ($originalFore) {
            "18,59,116" { $palette.Primary; break }
            "102,112,133" { $palette.Muted; break }
            "90,98,112" { $palette.Muted; break }
            "0,100,0" { $palette.Success; break }
            "255,140,0" { $palette.Warning; break }
            "139,0,0" { $palette.Danger; break }
            default { $palette.Text }
        }
        if ($Control -is [Windows.Forms.GroupBox]) { $Control.BackColor = $palette.Surface }
    } elseif ($Control -is [Windows.Forms.Panel] -or
              $Control -is [Windows.Forms.TableLayoutPanel] -or
              $Control -is [Windows.Forms.FlowLayoutPanel] -or
              $Control -is [Windows.Forms.SplitContainer]) {
        if ($Control.BackColor -ne [Drawing.Color]::Transparent) {
            $Control.BackColor = switch ($originalBack) {
                "255,248,230" { $palette.WarningSurface; break }
                "232,247,240" { $palette.SuccessSurface; break }
                "245,238,255" { $palette.PurpleSurface; break }
                "235,244,255" { $palette.InfoSurface; break }
                default { $palette.Surface }
            }
        }
        $Control.ForeColor = $palette.Text
    } else {
        $Control.ForeColor = $palette.Text
    }

    foreach ($child in $Control.Controls) {
        Set-ToolControlTheme -Control $child -Mode $Mode
    }
}

function Set-ToolWindowTheme {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Root,
        [ValidateSet("Light", "Dark")][string]$Mode = (Get-ToolUiTheme)
    )
    $env:TOOL_UI_THEME = $Mode
    Set-ToolUiLiteralText -Root $Root
    Set-ToolControlTheme -Control $Root -Mode $Mode
    Register-ToolUiDynamicContrast -Root $Root -Mode $Mode
    Set-ToolUiActionButtons -Root $Root -Mode $Mode
    $Root.Invalidate($true)
}

function Get-ToolUiTypography {
    return [pscustomobject][ordered]@{
        FontFamily = "Segoe UI"
        NormalSize = [single]9.1
        SmallSize = [single]8.2
        TileSize = [single]8.5
        IntroTitleSize = [single]9.8
        CardValueSize = [single]10.0
        DialogTitleSize = [single]15.0
        DashboardTitleSize = [single]18.0
        TextRendering = "GDIPlus"
    }
}
