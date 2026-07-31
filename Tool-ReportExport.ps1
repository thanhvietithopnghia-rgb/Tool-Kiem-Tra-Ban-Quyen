$script:ToolReportExportToolVersion = "4.3"
$script:ToolReportExportSchemaVersion = "1.2"

function Get-ToolReportExportMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolReportExportSchemaVersion
        ToolVersion = $script:ToolReportExportToolVersion
        Formats = @("HTML", "PDF", "JSON", "XML")
        PdfEngines = @("Microsoft Edge", "Google Chrome", "Microsoft Word")
        PdfProfileRoot = "%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf"
        PdfProfileAcl = "Current user + SYSTEM"
        PdfProfileCleanup = "Bounded retry after every browser export"
        XmlFormat = "Native integration XML"
        OfflineSafe = $true
        ExternalAssets = $false
        HtmlCultures = @("vi-VN", "en-US")
        PrintProfile = "A4 / safe page breaks / local assets only / network disabled"
    }
}

function ConvertTo-ToolHtmlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }
    try { return [System.Net.WebUtility]::HtmlEncode([string]$Value) }
    catch {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode([string]$Value)
    }
}

function Get-ToolProfessionalReportCss {
    return @'
:root{color-scheme:light;--ink:#172033;--muted:#667085;--line:#d8e0ea;--paper:#fff;--canvas:#edf2f8;--brand:#123b74;--brand2:#2563a7;--ok:#147a4b;--warn:#a35b00;--bad:#b42318;--info:#175cd3;--shadow:0 8px 26px rgba(16,24,40,.08)}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{font-family:"Segoe UI",Arial,sans-serif;background:linear-gradient(180deg,#e7eef7 0,var(--canvas) 360px);color:var(--ink);font-feature-settings:"tnum" 1;margin:0;line-height:1.5}
.page{max-width:1180px;margin:0 auto;padding:30px 24px 48px}
.hero{background:linear-gradient(135deg,#0d2e5c 0,var(--brand) 46%,var(--brand2) 100%);border:1px solid rgba(255,255,255,.16);border-radius:20px;color:#fff;overflow:hidden;padding:30px 32px;position:relative;box-shadow:0 18px 44px rgba(18,59,116,.22)}
.hero:after{background:radial-gradient(circle,rgba(255,255,255,.17) 0,rgba(255,255,255,0) 66%);content:"";height:320px;pointer-events:none;position:absolute;right:-100px;top:-170px;width:320px}
.eyebrow{font-size:12px;font-weight:700;letter-spacing:.12em;opacity:.86;text-transform:uppercase}
h1{font-size:31px;letter-spacing:-.025em;line-height:1.2;margin:8px 0 9px}
.subtitle{font-size:15px;max-width:900px;opacity:.92}
.report-mode{align-items:center;background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.25);border-radius:999px;display:inline-flex;font-size:10px;font-weight:800;letter-spacing:.09em;padding:5px 10px;position:absolute;right:22px;text-transform:uppercase;top:20px}
.report-mode:before{background:#65d99b;border-radius:50%;content:"";height:7px;margin-right:7px;width:7px}
.meta-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px 20px;margin-top:22px;padding-top:17px;border-top:1px solid rgba(255,255,255,.28);font-size:12px}
.meta-item b{display:block;font-size:11px;letter-spacing:.05em;opacity:.75;text-transform:uppercase}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:13px;margin:20px 0}
.card{background:var(--paper);border:1px solid var(--line);border-radius:15px;min-height:82px;padding:16px 17px;position:relative;box-shadow:var(--shadow)}
.card:before{background:var(--info);border-radius:5px;content:"";height:4px;left:16px;position:absolute;top:0;width:42px}
.tone-ok:before{background:var(--ok)}.tone-warning:before{background:var(--warn)}.tone-danger:before{background:var(--bad)}
.card-label{color:var(--muted);font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase}
.card-value{font-size:18px;font-weight:700;letter-spacing:-.015em;margin-top:7px;overflow-wrap:anywhere}
.tone-ok .card-value,.status-ok{color:var(--ok)}
.tone-warning .card-value,.status-warning{color:var(--warn)}
.tone-danger .card-value,.status-danger{color:var(--bad)}
.tone-info .card-value,.status-info{color:var(--info)}
.toc{background:#f7fbff;border:1px solid #c9dcef;border-radius:14px;margin:0 0 17px;padding:15px 19px;box-shadow:0 3px 12px rgba(18,59,116,.04)}
.toc strong{color:var(--brand)}
.toc ol{columns:2;column-gap:32px;margin:8px 0 0;padding-left:22px}
.toc a{color:var(--brand2);text-decoration:none}
section{background:var(--paper);border:1px solid var(--line);border-radius:15px;margin:0 0 16px;padding:20px 21px;box-shadow:var(--shadow);break-inside:avoid-page}
section h2{border-bottom:1px solid #e8edf3;color:var(--brand);font-size:19px;margin:0 0 13px;padding:0 0 9px}
.table-wrap{max-width:100%;overflow-x:auto}
table{border-collapse:collapse;font-size:12.5px;width:100%}
th,td{border:1px solid #dfe6ee;padding:8px 9px;text-align:left;vertical-align:top;overflow-wrap:anywhere}
th{background:#eaf2fb;color:#183b66;font-weight:700}
tr:nth-child(even) td{background:#fafcff}
.muted{color:var(--muted)}
.note{background:#f5f8fc;border:1px solid #dde5ef;border-left:4px solid #8292a8;border-radius:7px;color:#475467;font-size:12.5px;margin:12px 0 0;padding:10px 12px}
.license-warning{background:#fff7e8;border:1px solid #f4d7a7;border-left:4px solid #f0a000;border-radius:7px;color:#6b4300;margin:12px 0 0;padding:10px 12px}
.text-report{font-family:"Segoe UI",Arial,sans-serif;font-size:12.5px;line-height:1.55;margin:0;overflow-wrap:anywhere;white-space:pre-wrap;word-break:break-word}
.badge{border-radius:999px;display:inline-block;font-size:11px;font-weight:700;padding:3px 8px}
.badge-ok{background:#eaf8f0;color:var(--ok)}
.badge-warning{background:#fff3df;color:var(--warn)}
.badge-danger{background:#feeceb;color:var(--bad)}
.footer{color:var(--muted);font-size:11.5px;margin-top:22px;text-align:center}
@media(prefers-color-scheme:dark){:root{color-scheme:dark;--ink:#e6ebf2;--muted:#a9b4c5;--line:#3b4658;--paper:#202733;--canvas:#141923;--brand:#8bb8ff;--brand2:#a8caff;--ok:#71d6a1;--warn:#ffc36e;--bad:#ff8a82;--info:#8eb9ff;--shadow:0 8px 26px rgba(0,0,0,.25)}body{background:linear-gradient(180deg,#101722,var(--canvas) 360px)}.hero{background:linear-gradient(135deg,#17345f,#234d85)}.toc,.note{background:#1c2634;border-color:#3b4d64;color:#cbd4e2}section h2{border-bottom-color:#3b4658}.license-warning{background:#3a2d1a;border-color:#6b512b;color:#ffd494}th{background:#293d58;color:#dceaff}tr:nth-child(even) td{background:#1b222d}}
@media(max-width:720px){.page{padding:14px 10px 28px}.hero{border-radius:13px;padding:22px 18px}.report-mode{position:static;margin-bottom:12px}.toc ol{columns:1}h1{font-size:24px}section{padding:15px 12px;overflow-x:auto}.cards{grid-template-columns:1fr 1fr}}
@media print{@page{size:A4;margin:12mm}:root{color-scheme:light;--ink:#172033;--muted:#667085;--line:#b9c3cf;--paper:#fff;--canvas:#fff;--brand:#123b74;--brand2:#2563a7;--ok:#147a4b;--warn:#7a4700;--bad:#9e2018;--info:#175cd3}html,body{height:auto!important;overflow:visible!important}body{background:#fff!important;color:#000}.page{max-width:none;padding:0}.hero{background:#fff!important;border:2px solid #123b74;border-radius:0;color:#123b74;box-shadow:none;break-inside:avoid-page;padding:14px 16px}.hero:after{display:none}.report-mode{border-color:#7591b3;color:#123b74;right:12px;top:10px}.report-mode:before{background:#147a4b}.meta-grid{border-top-color:#b8c8db}.cards{grid-template-columns:repeat(4,1fr);gap:6px}.card,section,.toc{background:#fff!important;border-color:#b9c3cf;border-radius:0;box-shadow:none}.card{break-inside:avoid-page;min-height:68px;padding:11px 12px}.toc{display:none}section{break-inside:auto!important;page-break-inside:auto!important;orphans:3;widows:3}section h2{break-after:avoid-page;page-break-after:avoid}.table-wrap{max-width:none;overflow:visible!important}table{font-size:9.5pt;page-break-inside:auto;table-layout:auto}thead{display:table-header-group}tfoot{display:table-footer-group}tr{break-inside:avoid-page;page-break-inside:avoid}th,td{overflow-wrap:anywhere;word-break:break-word}a{color:#000;text-decoration:none}th{background:#e8edf3!important;color:#183b66!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}.text-report{font-size:9.5pt;overflow:visible}.footer{position:running(report-footer)}}
'@
}

function ConvertTo-ToolHtmlTable {
    param(
        [AllowNull()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Columns
    )

    if (-not $Rows -or @($Rows).Count -eq 0) {
        return "<p class='muted'>Không có dữ liệu.</p>"
    }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append("<div class='table-wrap'><table><thead><tr>")
    foreach ($column in $Columns) {
        [void]$builder.Append("<th>$(ConvertTo-ToolHtmlText $column)</th>")
    }
    [void]$builder.Append("</tr></thead><tbody>")
    foreach ($row in @($Rows)) {
        [void]$builder.Append("<tr>")
        foreach ($column in $Columns) {
            $property = if ($row) { $row.PSObject.Properties[$column] } else { $null }
            $value = if ($property) { $property.Value } else { "" }
            [void]$builder.Append("<td>$(ConvertTo-ToolHtmlText $value)</td>")
        }
        [void]$builder.Append("</tr>")
    }
    [void]$builder.Append("</tbody></table></div>")
    return $builder.ToString()
}

function New-ToolProfessionalHtmlDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle = "",
        [string]$Eyebrow = "",
        [AllowNull()][object[]]$Metadata = @(),
        [AllowNull()][object[]]$Cards = @(),
        [AllowNull()][object[]]$Sections = @(),
        [string]$Footer = "",
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN",
        [bool]$OfflineMode = $true
    )

    if ([string]::IsNullOrWhiteSpace($Eyebrow)) {
        $Eyebrow = if ($Culture -eq "en-US") { "License assurance report" } else { "Báo cáo bảo đảm bản quyền" }
    }
    $metaHtml = New-Object Text.StringBuilder
    foreach ($item in @($Metadata)) {
        [void]$metaHtml.Append("<div class='meta-item'><b>$(ConvertTo-ToolHtmlText $item.Label)</b>$(ConvertTo-ToolHtmlText $item.Value)</div>")
    }
    $cardsHtml = New-Object Text.StringBuilder
    foreach ($card in @($Cards)) {
        $tone = [string]$card.Tone
        if ($tone -notin @("ok", "warning", "danger", "info")) { $tone = "info" }
        [void]$cardsHtml.Append("<div class='card tone-$tone'><div class='card-label'>$(ConvertTo-ToolHtmlText $card.Label)</div><div class='card-value'>$(ConvertTo-ToolHtmlText $card.Value)</div></div>")
    }
    $tocHtml = New-Object Text.StringBuilder
    $sectionsHtml = New-Object Text.StringBuilder
    $index = 0
    foreach ($section in @($Sections)) {
        $index++
        $id = "section-$index"
        [void]$tocHtml.Append("<li><a href='#$id'>$(ConvertTo-ToolHtmlText $section.Title)</a></li>")
        [void]$sectionsHtml.Append("<section id='$id'><h2>$(ConvertTo-ToolHtmlText $section.Title)</h2>$([string]$section.BodyHtml)</section>")
    }
    $tocLabel = if ($Culture -eq "en-US") { "Contents" } else { "Mục lục" }
    $modeLabel = if ($OfflineMode) {
        if ($Culture -eq "en-US") { "Offline report" } else { "Báo cáo offline" }
    } else {
        if ($Culture -eq "en-US") { "Network allowed" } else { "Đã cho phép mạng" }
    }
    $htmlLanguage = if ($Culture -eq "en-US") { "en" } else { "vi" }
    $tocBlock = if ($index -gt 1) { "<nav class='toc'><strong>$tocLabel</strong><ol>$($tocHtml.ToString())</ol></nav>" } else { "" }
    $cardsBlock = if (@($Cards).Count -gt 0) { "<div class='cards'>$($cardsHtml.ToString())</div>" } else { "" }
    $css = Get-ToolProfessionalReportCss
    return @"
<!doctype html>
<html lang="$htmlLanguage">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
<title>$(ConvertTo-ToolHtmlText $Title)</title>
<style>$css</style>
</head>
<body>
<main class="page">
<header class="hero">
<div class="report-mode">$(ConvertTo-ToolHtmlText $modeLabel)</div>
<div class="eyebrow">$(ConvertTo-ToolHtmlText $Eyebrow)</div>
<h1>$(ConvertTo-ToolHtmlText $Title)</h1>
<div class="subtitle">$(ConvertTo-ToolHtmlText $Subtitle)</div>
<div class="meta-grid">$($metaHtml.ToString())</div>
</header>
$cardsBlock
$tocBlock
$($sectionsHtml.ToString())
<div class="footer">$(ConvertTo-ToolHtmlText $Footer)</div>
</main>
</body>
</html>
"@
}

function Export-ToolTextReportPresentation {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [string]$Subtitle = "",
        [string]$Eyebrow = "",
        [AllowNull()][object[]]$Metadata = @(),
        [AllowNull()][object[]]$Cards = @(),
        [string]$SectionTitle = "",
        [string]$Footer = "",
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN",
        [switch]$IncludePdf
    )

    $baseFull = [IO.Path]::GetFullPath($BasePath)
    $directory = Split-Path -Parent $baseFull
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle = if ($Culture -eq "en-US") { "Complete report content" } else { "Nội dung báo cáo đầy đủ" }
    }
    if ([string]::IsNullOrWhiteSpace($Subtitle)) {
        $Subtitle = if ($Culture -eq "en-US") {
            "The original technical content is preserved in full and presented with the shared HTML/PDF report layout."
        } else {
            "Nội dung kỹ thuật gốc được giữ đầy đủ và trình bày bằng giao diện HTML/PDF dùng chung."
        }
    }
    if ([string]::IsNullOrWhiteSpace($Footer)) {
        $Footer = if ($Culture -eq "en-US") {
            "Configuration & License Assurance Tool · Local report"
        } else {
            "Công cụ kiểm tra cấu hình và bản quyền · Báo cáo cục bộ"
        }
    }
    if (@($Metadata).Count -eq 0) {
        $Metadata = @(
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Computer" } else { "Máy" }
                Value = [string]$env:COMPUTERNAME
            },
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Export time" } else { "Thời điểm xuất" }
                Value = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            },
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Format" } else { "Định dạng" }
                Value = "HTML / PDF · A4"
            }
        )
    }
    if (@($Cards).Count -eq 0) {
        $Cards = @(
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Content" } else { "Nội dung" }
                Value = if ($Culture -eq "en-US") { "Complete" } else { "Đầy đủ" }
                Tone = "ok"
            },
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Text lines" } else { "Dòng nội dung" }
                Value = [string]@($Lines).Count
                Tone = "info"
            },
            [pscustomobject]@{
                Label = if ($Culture -eq "en-US") { "Storage" } else { "Nơi lưu" }
                Value = if ($Culture -eq "en-US") { "Desktop" } else { "Màn hình nền" }
                Tone = "info"
            }
        )
    }

    $completeText = (@($Lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    $bodyHtml = "<pre class='text-report'>$(ConvertTo-ToolHtmlText $completeText)</pre>"
    $html = New-ToolProfessionalHtmlDocument `
        -Title $Title -Subtitle $Subtitle -Eyebrow $Eyebrow `
        -Metadata $Metadata -Cards $Cards `
        -Sections @([pscustomobject]@{ Title=$SectionTitle; BodyHtml=$bodyHtml }) `
        -Footer $Footer -Culture $Culture -OfflineMode $true

    $htmlPath = "$baseFull.html"
    $pdfPath = "$baseFull.pdf"
    $manifestPath = "${baseFull}-SHA256SUMS.txt"
    foreach ($stalePath in @($htmlPath, $pdfPath, $manifestPath)) {
        if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
            Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
        }
    }
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) {
        throw "HTML report presentation failed the local-only safety check."
    }

    $pdfResult = [pscustomobject][ordered]@{ Success=$false; Engine=""; Path=""; Error="Không yêu cầu xuất PDF." }
    if ($IncludePdf) {
        $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
    }
    $hashLines = @("# SHA-256 professional text report package schema $($script:ToolReportExportSchemaVersion).")
    foreach ($path in @($htmlPath, $pdfPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hashLines += "$(Get-ToolSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))"
        }
    }
    [IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject][ordered]@{
        Success = $true
        HtmlPath = $htmlPath
        PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
        ManifestPath = $manifestPath
        Pdf = $pdfResult
    }
}

function Write-ToolXmlNode {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlWriter]$Writer,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Value
    )

    $safeName = [Xml.XmlConvert]::EncodeLocalName($Name)
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "Value" }
    $Writer.WriteStartElement($safeName)
    if ($null -eq $Value) {
        $Writer.WriteAttributeString("type", "null")
        $Writer.WriteAttributeString("nil", "true")
        $Writer.WriteEndElement()
        return
    }
    if ($Value -is [Collections.IDictionary]) {
        $Writer.WriteAttributeString("type", "object")
        foreach ($key in $Value.Keys) {
            Write-ToolXmlNode -Writer $Writer -Name ([string]$key) -Value $Value[$key]
        }
        $Writer.WriteEndElement()
        return
    }
    if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
        $Writer.WriteAttributeString("type", "array")
        $itemIndex = 0
        foreach ($item in $Value) {
            $Writer.WriteStartElement("Item")
            $Writer.WriteAttributeString("index", [string]$itemIndex)
            if ($null -eq $item) {
                $Writer.WriteAttributeString("type", "null")
                $Writer.WriteAttributeString("nil", "true")
            } elseif ($item -is [Collections.IDictionary]) {
                $Writer.WriteAttributeString("type", "object")
                foreach ($key in $item.Keys) {
                    Write-ToolXmlNode -Writer $Writer -Name ([string]$key) -Value $item[$key]
                }
            } elseif ($item.PSObject -and @($item.PSObject.Properties).Count -gt 0 -and
                $item -isnot [ValueType] -and $item -isnot [DateTime]) {
                $Writer.WriteAttributeString("type", "object")
                foreach ($property in @($item.PSObject.Properties)) {
                    Write-ToolXmlNode -Writer $Writer -Name ([string]$property.Name) -Value $property.Value
                }
            } else {
                $itemType = if ($item -is [bool]) { "boolean" } elseif ($item -is [DateTime]) { "dateTime" } elseif ($item -is [ValueType]) { "number" } else { "string" }
                $Writer.WriteAttributeString("type", $itemType)
                if ($item -is [DateTime]) {
                    $Writer.WriteString($item.ToUniversalTime().ToString("o"))
                } elseif ($item -is [bool]) {
                    $Writer.WriteString(([string]$item).ToLowerInvariant())
                } else {
                    $Writer.WriteString([string]$item)
                }
            }
            $Writer.WriteEndElement()
            $itemIndex++
        }
        $Writer.WriteEndElement()
        return
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and
        $Value -isnot [ValueType] -and $Value -isnot [DateTime] -and $Value -isnot [string]) {
        $Writer.WriteAttributeString("type", "object")
        foreach ($property in @($Value.PSObject.Properties)) {
            Write-ToolXmlNode -Writer $Writer -Name ([string]$property.Name) -Value $property.Value
        }
        $Writer.WriteEndElement()
        return
    }
    $typeName = if ($Value -is [bool]) { "boolean" } elseif ($Value -is [DateTime]) { "dateTime" } elseif ($Value -is [ValueType]) { "number" } else { "string" }
    $Writer.WriteAttributeString("type", $typeName)
    if ($Value -is [DateTime]) {
        $Writer.WriteString($Value.ToUniversalTime().ToString("o"))
    } elseif ($Value -is [bool]) {
        $Writer.WriteString(([string]$Value).ToLowerInvariant())
    } else {
        $Writer.WriteString([string]$Value)
    }
    $Writer.WriteEndElement()
}

function Export-ToolReportXml {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.OmitXmlDeclaration = $false
    $settings.NewLineChars = [Environment]::NewLine
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement("ToolReport")
        foreach ($property in @($Report.PSObject.Properties)) {
            Write-ToolXmlNode -Writer $writer -Name ([string]$property.Name) -Value $property.Value
        }
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    } finally {
        $writer.Dispose()
    }
}

function Get-ToolSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Test-ToolHtmlOfflineSafe {
    param([Parameter(Mandatory = $true)][string]$HtmlPath)

    if (-not (Test-Path -LiteralPath $HtmlPath -PathType Leaf)) { return $false }
    try {
        $item = Get-Item -LiteralPath $HtmlPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 52428800) { return $false }
        $html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
        $blockedPatterns = @(
            '(?is)<\s*(script|iframe|object|embed)\b',
            '(?is)(src|href)\s*=\s*["'']\s*(https?:)?//',
            '(?is)@import\s+',
            '(?is)url\(\s*["'']?\s*(https?:)?//'
        )
        foreach ($pattern in $blockedPatterns) {
            if ($html -match $pattern) { return $false }
        }
        return [bool]($html -match '(?is)<meta\s+http-equiv=["'']Content-Security-Policy["'']')
    } catch {
        return $false
    }
}

function Get-ToolPdfBrowser {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramW6432\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramW6432\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return ""
}

function Get-ToolPdfProfileRoot {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = [string]$env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw "Không xác định được LocalApplicationData của người dùng hiện tại."
    }

    $localAppDataFull = [IO.Path]::GetFullPath($localAppData).TrimEnd([char]92)
    $localTempFull = [IO.Path]::GetFullPath((Join-Path $localAppDataFull "Temp"))
    $expectedPrefix = $localAppDataFull + [char]92
    if (-not $localTempFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Thư mục Temp không nằm trong LocalApplicationData của người dùng hiện tại."
    }

    return [IO.Path]::GetFullPath((Join-Path $localTempFull "ThanhViet-Tool-Kiem-Tra\pdf"))
}

function New-ToolPdfProfileAcl {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) {
        throw "Không xác định được SID của người dùng hiện tại."
    }

    $currentUserSid = $identity.User
    $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($currentUserSid)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentUserSid, "FullControl", $inheritance, "None", "Allow")))
    if ($currentUserSid.Value -ne $systemSid.Value) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
    }
    return $acl
}

function Test-ToolPdfProfileDirectoryAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $false
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $identity -or $null -eq $identity.User) { return $false }
        $currentUserSid = $identity.User.Value
        $allowedWriters = @($currentUserSid, "S-1-5-18")
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        if (-not $acl.AreAccessRulesProtected) { return $false }

        $ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($ownerSid -ne $currentUserSid -and $ownerSid -ne "S-1-5-18") { return $false }

        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
            [Security.AccessControl.FileSystemRights]::Modify -bor
            [Security.AccessControl.FileSystemRights]::FullControl -bor
            [Security.AccessControl.FileSystemRights]::Delete -bor
            [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
            [Security.AccessControl.FileSystemRights]::TakeOwnership
        $currentUserCanWrite = $false
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
            if (($rule.FileSystemRights -band $writeMask) -eq 0) { continue }
            if ($allowedWriters -notcontains $rule.IdentityReference.Value) { return $false }
            if ($rule.IdentityReference.Value -eq $currentUserSid) { $currentUserCanWrite = $true }
        }
        return $currentUserCanWrite
    } catch {
        return $false
    }
}

function New-ToolPdfProfileDirectory {
    $profileRoot = Get-ToolPdfProfileRoot
    $profileAcl = New-ToolPdfProfileAcl

    if (Test-Path -LiteralPath $profileRoot) {
        $rootItem = Get-Item -LiteralPath $profileRoot -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Vùng profile PDF là reparse point hoặc không phải thư mục."
        }
    } else {
        [void][IO.Directory]::CreateDirectory($profileRoot, $profileAcl)
    }
    [IO.Directory]::SetAccessControl($profileRoot, $profileAcl)
    if (-not (Test-ToolPdfProfileDirectoryAcl -Path $profileRoot)) {
        throw "ACL vùng profile PDF không chỉ giới hạn cho người dùng hiện tại và SYSTEM."
    }

    $profilePath = Join-Path $profileRoot ("pdf-profile-" + [Guid]::NewGuid().ToString("N"))
    [void][IO.Directory]::CreateDirectory($profilePath, $profileAcl)
    if (-not (Test-ToolPdfProfileDirectoryAcl -Path $profilePath)) {
        throw "ACL profile PDF tạm không hợp lệ."
    }

    return [pscustomobject][ordered]@{
        RootPath = $profileRoot
        ProfilePath = $profilePath
        OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
}

function Remove-ToolPdfProfileDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ProfilePath,
        [Parameter(Mandatory = $true)][string]$ProfileRoot,
        [int]$RetryCount = 8
    )

    try {
        $profileFull = [IO.Path]::GetFullPath($ProfilePath)
        $rootFull = [IO.Path]::GetFullPath($ProfileRoot).TrimEnd([char]92) + [char]92
        $profileName = [IO.Path]::GetFileName($profileFull)
        if (-not $profileFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
            $profileName -notmatch '^pdf-profile-[a-f0-9]{32}$') {
            return $false
        }
        if (-not (Test-Path -LiteralPath $profileFull)) { return $true }

        $item = Get-Item -LiteralPath $profileFull -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $false
        }

        $attempts = [Math]::Max(1, [Math]::Min(20, $RetryCount))
        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            try {
                Remove-Item -LiteralPath $profileFull -Recurse -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $profileFull)) { return $true }
            } catch {
                if ($attempt -ge $attempts) { return $false }
            }
            Start-Sleep -Milliseconds 150
        }
    } catch {}
    return $false
}

function Convert-ToolHtmlToPdf {
    param(
        [Parameter(Mandatory = $true)][string]$HtmlPath,
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [int]$TimeoutSeconds = 45
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $HtmlPath)) {
        return [pscustomobject][ordered]@{
            Success = $false
            Engine = ""
            Path = ""
            Error = "HTML không đạt chính sách offline: chỉ cho phép CSS/data cục bộ, không cho script hoặc tài nguyên mạng."
        }
    }
    $browser = Get-ToolPdfBrowser
    if (-not [string]::IsNullOrWhiteSpace($browser)) {
        $profileRoot = ""
        $profilePath = ""
        try {
            $profileState = New-ToolPdfProfileDirectory
            $profileRoot = [string]$profileState.RootPath
            $profilePath = [string]$profileState.ProfilePath
            $htmlUri = ([Uri](Resolve-Path -LiteralPath $HtmlPath).Path).AbsoluteUri
            $arguments = @(
                "--headless",
                "--disable-gpu",
                "--disable-extensions",
                "--disable-background-networking",
                "--disable-component-update",
                "--disable-domain-reliability",
                "--disable-sync",
                "--metrics-recording-only",
                "--host-resolver-rules=`"MAP * 0.0.0.0`"",
                "--no-first-run",
                "--no-default-browser-check",
                "--run-all-compositor-stages-before-draw",
                "--no-pdf-header-footer",
                "--print-to-pdf-no-header",
                "--user-data-dir=`"$profilePath`"",
                "--print-to-pdf=`"$PdfPath`"",
                "`"$htmlUri`""
            )
            $process = Start-Process -FilePath $browser -ArgumentList $arguments -PassThru -WindowStyle Hidden
            if (-not $process.WaitForExit([Math]::Max(5, $TimeoutSeconds) * 1000)) {
                try { $process.Kill() } catch {}
                throw "Trình duyệt vượt quá thời gian chờ $TimeoutSeconds giây."
            }
            if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $PdfPath -PathType Leaf) -and (Get-Item -LiteralPath $PdfPath).Length -gt 1024) {
                return [pscustomobject][ordered]@{ Success=$true; Engine=[IO.Path]::GetFileNameWithoutExtension($browser); Path=$PdfPath; Error="" }
            }
            throw "Trình duyệt kết thúc với mã $($process.ExitCode) hoặc PDF không hợp lệ."
        } catch {
            [void]$errors.Add("Browser: $($_.Exception.Message)")
        } finally {
            if (-not [string]::IsNullOrWhiteSpace($profilePath) -and -not [string]::IsNullOrWhiteSpace($profileRoot)) {
                [void](Remove-ToolPdfProfileDirectory -ProfilePath $profilePath -ProfileRoot $profileRoot)
            }
        }
    } else {
        [void]$errors.Add("Browser: không tìm thấy Microsoft Edge hoặc Google Chrome.")
    }

    $word = $null
    $document = $null
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Visible = $false
        $word.DisplayAlerts = 0
        try { $word.AutomationSecurity = 3 } catch {}
        $document = $word.Documents.Open($HtmlPath, $false, $true, $false)
        $document.ExportAsFixedFormat($PdfPath, 17)
        if ((Test-Path -LiteralPath $PdfPath -PathType Leaf) -and (Get-Item -LiteralPath $PdfPath).Length -gt 1024) {
            return [pscustomobject][ordered]@{ Success=$true; Engine="Microsoft Word"; Path=$PdfPath; Error="" }
        }
        throw "Word không tạo được tệp PDF hợp lệ."
    } catch {
        [void]$errors.Add("Word: $($_.Exception.Message)")
    } finally {
        if ($document) { try { $document.Close(0) } catch {}; try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($document) } catch {} }
        if ($word) { try { $word.Quit() } catch {}; try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) } catch {} }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
    return [pscustomobject][ordered]@{ Success=$false; Engine=""; Path=""; Error=($errors.ToArray() -join " | ") }
}

function Export-ToolReportPackage {
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$HtmlContent,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [switch]$IncludePdf,
        [switch]$RedactPaths
    )

    $baseFull = [IO.Path]::GetFullPath($BasePath)
    $directory = Split-Path -Parent $baseFull
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $htmlPath = "$baseFull.html"
    $pdfPath = "$baseFull.pdf"
    $jsonPath = "$baseFull.json"
    $xmlPath = "$baseFull.xml"
    $manifestPath = "${baseFull}-SHA256SUMS.txt"
    foreach ($stalePath in @($htmlPath, $pdfPath, $jsonPath, $xmlPath, $manifestPath)) {
        if (Test-Path -LiteralPath $stalePath -PathType Leaf) {
            Remove-Item -LiteralPath $stalePath -Force -ErrorAction Stop
        }
    }
    [IO.File]::WriteAllText($htmlPath, $HtmlContent, (New-Object Text.UTF8Encoding($false)))

    $pdfResult = [pscustomobject][ordered]@{ Success=$false; Engine=""; Path=""; Error="Không yêu cầu xuất PDF." }
    if ($IncludePdf) {
        $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath
    }
    $displayHtmlPath = if ($RedactPaths) { [IO.Path]::GetFileName($htmlPath) } else { $htmlPath }
    $displayPdfPath = if ($RedactPaths) { [IO.Path]::GetFileName($pdfPath) } else { $pdfPath }
    $displayJsonPath = if ($RedactPaths) { [IO.Path]::GetFileName($jsonPath) } else { $jsonPath }
    $displayXmlPath = if ($RedactPaths) { [IO.Path]::GetFileName($xmlPath) } else { $xmlPath }
    $displayManifestPath = if ($RedactPaths) { [IO.Path]::GetFileName($manifestPath) } else { $manifestPath }
    $displayPdfError = [string]$pdfResult.Error
    if ($RedactPaths) {
        foreach ($secret in @($directory, [Environment]::GetFolderPath("UserProfile"))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
                $displayPdfError = [regex]::Replace(
                    $displayPdfError,
                    [regex]::Escape([string]$secret),
                    "[ĐÃ CHE]",
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
        }
        foreach ($secret in @($env:USERNAME, $env:COMPUTERNAME)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
                $identityPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
                $displayPdfError = [regex]::Replace(
                    $displayPdfError,
                    $identityPattern,
                    "[ĐÃ CHE]",
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
        }
    }
    $exportData = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolReportExportSchemaVersion
        HtmlPath = $displayHtmlPath
        PdfPath = if ($pdfResult.Success) { $displayPdfPath } else { "" }
        JsonPath = $displayJsonPath
        XmlPath = $displayXmlPath
        ManifestPath = $displayManifestPath
        PdfStatus = if ($pdfResult.Success) { "Created" } elseif ($IncludePdf) { "Unavailable" } else { "NotRequested" }
        PdfEngine = [string]$pdfResult.Engine
        PdfError = $displayPdfError
    }
    if ($Report.PSObject.Properties["Export"]) { $Report.Export = $exportData }
    else { $Report | Add-Member -NotePropertyName Export -NotePropertyValue $exportData }
    if ($Report.PSObject.Properties["HtmlReport"]) { $Report.HtmlReport = $displayHtmlPath }
    if ($Report.PSObject.Properties["PdfReport"]) { $Report.PdfReport = if ($pdfResult.Success) { $displayPdfPath } else { "" } }

    [IO.File]::WriteAllText($jsonPath, ($Report | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    Export-ToolReportXml -Report $Report -Path $xmlPath

    $hashLines = @("# SHA-256 report package schema $($script:ToolReportExportSchemaVersion).")
    foreach ($path in @($htmlPath, $pdfPath, $jsonPath, $xmlPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hashLines += "$(Get-ToolSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))"
        }
    }
    [IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject][ordered]@{
        Success = $true
        HtmlPath = $htmlPath
        PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
        JsonPath = $jsonPath
        XmlPath = $xmlPath
        ManifestPath = $manifestPath
        Pdf = $pdfResult
    }
}
