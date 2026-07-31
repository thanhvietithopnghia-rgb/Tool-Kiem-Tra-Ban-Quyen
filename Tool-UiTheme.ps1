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
    Set-ToolControlTheme -Control $Root -Mode $Mode
    Register-ToolUiDynamicContrast -Root $Root -Mode $Mode
    $Root.Invalidate($true)
}

function Get-ToolUiTypography {
    return [pscustomobject][ordered]@{
        FontFamily = "Segoe UI"
        NormalSize = [single]9.6
        SmallSize = [single]8.7
        TileSize = [single]9.2
        IntroTitleSize = [single]10.5
        CardValueSize = [single]11
        DialogTitleSize = [single]16
        DashboardTitleSize = [single]19
        TextRendering = "GDIPlus"
    }
}
