[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$source = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("Tool-Kiem-Tra-v4.6-extensions-" + [Guid]::NewGuid().ToString("N"))
$previousSecureLaunch = [string]$env:TOOL_SECURE_LAUNCH
$previousPluginDir = [string]$env:TOOL_PLUGIN_DIR
$previousTimelinePath = [string]$env:TOOL_TIMELINE_PATH
$previousTimelineKeyPath = [string]$env:TOOL_TIMELINE_KEY_PATH
$previousSecureRuntimeDir = [string]$env:TOOL_SECURE_RUNTIME_DIR
$pdfProfileState = $null

function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

try {
    foreach ($name in @("Tool-ReportSchema.ps1","Tool-ReportExport.ps1","Tool-PluginEngine.ps1","Tool-LicenseTimeline.ps1")) {
        $path = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu $name." }
        . $path
    }
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $pluginDir = Join-Path $tempRoot "plugins"
    $timelineDir = Join-Path $tempRoot "timeline"
    $reportDir = Join-Path $tempRoot "reports"
    New-Item -ItemType Directory -Path $pluginDir, $timelineDir, $reportDir -Force | Out-Null

    $env:TOOL_SECURE_LAUNCH = ""
    $env:TOOL_PLUGIN_DIR = $pluginDir
    $env:TOOL_TIMELINE_PATH = Join-Path $timelineDir "license-timeline.jsonl"
    $env:TOOL_TIMELINE_KEY_PATH = Join-Path $timelineDir "timeline-hmac.key"

    $mockProtectedRuntime = Join-Path $tempRoot "mock-programdata-runtime"
    New-Item -ItemType Directory -Path $mockProtectedRuntime -Force | Out-Null
    $env:TOOL_SECURE_RUNTIME_DIR = $mockProtectedRuntime
    $pdfProfileState = New-ToolPdfProfileDirectory
    $expectedPdfRoot = Get-ToolPdfProfileRoot
    $profileFull = [IO.Path]::GetFullPath([string]$pdfProfileState.ProfilePath)
    $expectedPdfPrefix = [IO.Path]::GetFullPath($expectedPdfRoot).TrimEnd([char]92) + [char]92
    $mockRuntimePrefix = [IO.Path]::GetFullPath($mockProtectedRuntime).TrimEnd([char]92) + [char]92
    if (-not $profileFull.StartsWith($expectedPdfPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $profileFull.StartsWith($mockRuntimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "Profile PDF vẫn phụ thuộc vùng runtime ProgramData thay vì LocalApplicationData\\Temp."
    }
    if (-not (Test-ToolPdfProfileDirectoryAcl -Path $pdfProfileState.ProfilePath)) {
        Add-Failure "Profile PDF không có ACL chỉ dành cho người dùng hiện tại và SYSTEM."
    }
    $pdfSentinel = Join-Path $pdfProfileState.ProfilePath "browser-write-test.txt"
    [IO.File]::WriteAllText($pdfSentinel, "ok", (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::ReadAllText($pdfSentinel, [Text.Encoding]::UTF8) -ne "ok") {
        Add-Failure "Không ghi/đọc được profile PDF tạm."
    }
    $outsideProfile = Join-Path $tempRoot ("pdf-profile-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $outsideProfile -Force | Out-Null
    if ((Remove-ToolPdfProfileDirectory -ProfilePath $outsideProfile -ProfileRoot $expectedPdfRoot) -or
        -not (Test-Path -LiteralPath $outsideProfile -PathType Container)) {
        Add-Failure "Cơ chế dọn profile PDF đã xóa đường dẫn ngoài vùng cho phép."
    }
    if (-not (Remove-ToolPdfProfileDirectory -ProfilePath $pdfProfileState.ProfilePath -ProfileRoot $pdfProfileState.RootPath) -or
        (Test-Path -LiteralPath $pdfProfileState.ProfilePath)) {
        Add-Failure "Không dọn sạch profile PDF tạm sau khi dùng."
    } else {
        $pdfProfileState = $null
    }

    Copy-Item -LiteralPath (Join-Path $source "builtin-windows-office-trust.plugin.json") -Destination (Join-Path $pluginDir "builtin.plugin.json")
    $pluginPackage = Read-ToolPluginPackage -Path (Join-Path $pluginDir "builtin.plugin.json")
    if (-not $pluginPackage.Valid -or @($pluginPackage.Plugin.Rules).Count -ne 3) {
        Add-Failure "Plugin tích hợp không đạt schema/rule count (Valid=$($pluginPackage.Valid); Rules=$(@($pluginPackage.Plugin.Rules).Count); Errors=$($pluginPackage.Errors -join ' | '))."
    }
    $pluginAudit = Invoke-ToolPluginAudit -PluginDirectory $pluginDir
    if ($pluginAudit.PluginCount -ne 1 -or $pluginAudit.EvaluatedRuleCount -ne 3 -or $pluginAudit.InvalidPluginCount -ne 0) {
        Add-Failure "Plugin audit không nạp/evaluate đúng plugin tích hợp (Plugins=$($pluginAudit.PluginCount); Rules=$($pluginAudit.EvaluatedRuleCount); Invalid=$($pluginAudit.InvalidPluginCount); Error=$($pluginAudit.Error))."
    }
    $installedPlugin = Install-ToolPluginPackage -SourcePath (Join-Path $source "builtin-windows-office-trust.plugin.json") -PluginDirectory $pluginDir
    if (-not $installedPlugin.Installed -or -not (Test-Path -LiteralPath $installedPlugin.Path -PathType Leaf) -or
        $installedPlugin.Sha256 -ne $pluginPackage.Sha256) {
        Add-Failure "Cài plugin theo transaction/hash thất bại."
    } else {
        $reinstalledPlugin = Install-ToolPluginPackage -SourcePath (Join-Path $source "builtin-windows-office-trust.plugin.json") -PluginDirectory $pluginDir -Force
        if (-not $reinstalledPlugin.Installed -or $reinstalledPlugin.Sha256 -ne $installedPlugin.Sha256) {
            Add-Failure "Cập nhật plugin transaction bằng Force thất bại."
        }
    }
    $maliciousPath = Join-Path $tempRoot "malicious.plugin.json"
    [IO.File]::WriteAllText($maliciousPath, @'
{"SchemaVersion":"1.0","PluginId":"test.bad.plugin","Name":"Bad","Version":"1.0.0","Publisher":"Test","Rules":[{"RuleId":"bad.command","Type":"File","Condition":"Exists","Path":"%SystemRoot%\\notepad.exe","Severity":"Info","Message":"bad","Command":"powershell.exe"}]}
'@, (New-Object Text.UTF8Encoding($false)))
    $malicious = Read-ToolPluginPackage -Path $maliciousPath -AllowOutsideProtectedDirectory
    if ($malicious.Valid -or ($malicious.Errors -join " ") -notmatch "Command") {
        Add-Failure "Plugin có trường Command không bị từ chối (Valid=$($malicious.Valid); Errors=$($malicious.Errors -join ' | '))."
    }
    $traversalPath = Join-Path $tempRoot "traversal.plugin.json"
    [IO.File]::WriteAllText($traversalPath, @'
{"SchemaVersion":"1.0","PluginId":"test.bad.registry","Name":"Bad Registry","Version":"1.0.0","Publisher":"Test","Rules":[{"RuleId":"bad.registry.path","Type":"RegistryValue","Condition":"Exists","Hive":"HKLM","Path":"SOFTWARE\\..\\SYSTEM","ValueName":"Test","Severity":"Info","Message":"bad"}]}
'@, (New-Object Text.UTF8Encoding($false)))
    $traversal = Read-ToolPluginPackage -Path $traversalPath -AllowOutsideProtectedDirectory
    $traversalErrorText = ($traversal.Errors -join " ")
    if ($traversal.Valid -or $traversalErrorText -notmatch "(?i)(không an toàn|unsafe)") {
        Add-Failure "Plugin có Registry traversal không bị từ chối đúng quy tắc an toàn (Valid=$($traversal.Valid); Errors=$traversalErrorText)."
    }

$timelineState = Initialize-ToolLicenseTimeline -ToolVersion "4.8"
    if (-not $timelineState.Enabled) { Add-Failure "Không khởi tạo được timeline test: $($timelineState.Error)" }
    if ($timelineState.Enabled) {
        $first = Write-ToolLicenseTimelineEvent -EventType "TestObserved" -Source "Verifier" -Data ([ordered]@{ Status="Licensed" })
        $second = Write-ToolLicenseTimelineEvent -EventType "TestChanged" -Source "Verifier" -IsChange -Data ([ordered]@{ Status="Notification"; ProductKey="AAAAA-BBBBB-CCCCC-DDDDD-EEEEE" })
        $history = Get-ToolLicenseTimeline
        if (-not $first.Written -or -not $second.Written -or -not $history.Valid -or $history.RecordCount -ne 2 -or $history.ChangeCount -ne 1) {
            Add-Failure "Timeline round-trip/HMAC/hash chain thất bại."
        }
        $timelineRaw = [IO.File]::ReadAllText($env:TOOL_TIMELINE_PATH, [Text.Encoding]::UTF8)
        if ($timelineRaw -match "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE") { Add-Failure "Timeline làm lộ product key đầy đủ." }
        $tamperedPath = Join-Path $timelineDir "tampered.jsonl"
        $tampered = $timelineRaw -replace '"HmacSha256":"[A-F0-9]', '"HmacSha256":"0'
        [IO.File]::WriteAllText($tamperedPath, $tampered, (New-Object Text.UTF8Encoding($false)))
        $tamperedHistory = Get-ToolLicenseTimeline -TimelinePath $tamperedPath -KeyPath $env:TOOL_TIMELINE_KEY_PATH
        if ($tamperedHistory.Valid) { Add-Failure "Timeline bị sửa vẫn được chấp nhận." }
    }

$envelope = New-ToolReportEnvelope -ReportKind "CertificateAudit" -ToolVersion "4.8" -Data ([ordered]@{
        CreatedAt=[DateTime]::UtcNow.ToString("o"); Overall="Pass"; ValidSignatureCount=1; InvalidSignatureCount=0
        Targets=@([pscustomobject]@{ Product="Windows"; Component="sppsvc"; ChainValid=$true })
    })
    $detailedHtml = New-ToolProfessionalHtmlDocument -Title "Fixture detail only" -Cards @([pscustomobject]@{Label="Status";Value="Pass";Tone="ok"}) `
        -Sections @([pscustomobject]@{Title="Data";BodyHtml=(ConvertTo-ToolHtmlTable -Rows $envelope.Targets -Columns @("Product","Component","ChainValid"))})
    $html = '<!doctype html><html lang="vi" data-report-view="summary"><head><meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''"><meta charset="utf-8"><style>body{font-family:Segoe UI}</style></head><body><h1>Fixture summary only</h1>{{TOOL_REPORT_PDF_GUIDE}}</body></html>'
    $package = Export-ToolReportPackage -Report $envelope -HtmlContent $html -PdfHtmlContent $detailedHtml -BasePath (Join-Path $reportDir "fixture")
    foreach ($path in @($package.HtmlPath,$package.JsonPath,$package.XmlPath,$package.ManifestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "Thiếu output report: $path" }
    }
    $summaryFixture = [IO.File]::ReadAllText($package.HtmlPath, [Text.Encoding]::UTF8)
    if ($summaryFixture -match '<table\b|Fixture detail only|TOOL_REPORT_PDF_GUIDE' -or
        $summaryFixture -notmatch 'data-report-view="summary"' -or
        $summaryFixture -notmatch 'pdf-guide') {
        Add-Failure "HTML tổng quan còn lẫn nội dung chi tiết hoặc thiếu hướng dẫn PDF."
    }
    try {
        [xml]$xml = [IO.File]::ReadAllText($package.XmlPath, [Text.Encoding]::UTF8)
        if ($xml.ToolReport.ReportKind.'#text' -ne "CertificateAudit" -and [string]$xml.ToolReport.ReportKind -ne "CertificateAudit") {
            throw "ReportKind XML không đúng."
        }
        if ([string]$xml.ToolReport.Targets.type -ne "array" -or [string]$xml.ToolReport.Targets.Item.type -ne "object") {
            throw "XML không giữ type metadata của array/object."
        }
    } catch { Add-Failure "XML integration không parse được: $($_.Exception.Message)" }
    try {
        $json = [IO.File]::ReadAllText($package.JsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$validation = Test-ToolReportEnvelope -Report $json -ExpectedReportKind "CertificateAudit" -ExpectedToolVersion "4.8"
        if (-not $validation.Valid) { throw ($validation.Errors -join "; ") }
        if ([string]$json.Export.SchemaVersion -ne '1.4' -or [string]$json.Export.HtmlPresentation -ne 'Summary') {
            throw "Metadata tách HTML tổng quan/PDF chi tiết không đúng."
        }
    } catch { Add-Failure "JSON integration không đạt schema: $($_.Exception.Message)" }

    $pluginEngineText = Get-Content -LiteralPath (Join-Path $source "Tool-PluginEngine.ps1") -Raw -Encoding UTF8
    if ($pluginEngineText -match '(?i)\bInvoke-Expression\b|\bEncodedCommand\b|\bInvoke-WebRequest\b|\bInvoke-RestMethod\b') {
        Add-Failure "Plugin engine chứa primitive thực thi/tải mạng không được phép."
    }
    $reportExportText = Get-Content -LiteralPath (Join-Path $source "Tool-ReportExport.ps1") -Raw -Encoding UTF8
    if ($reportExportText -match 'TOOL_SECURE_RUNTIME_DIR' -or
        $reportExportText -notmatch 'LocalApplicationData' -or
        $reportExportText -notmatch 'Test-ToolPdfProfileDirectoryAcl' -or
        $reportExportText -notmatch 'Remove-ToolPdfProfileDirectory') {
        Add-Failure "Bộ xuất PDF chưa tách profile trình duyệt khỏi ProgramData hoặc thiếu ACL/dọn dẹp an toàn."
    }
    foreach ($scriptName in @("Tool-ReportExport.ps1","Tool-PluginEngine.ps1","Tool-LicenseTimeline.ps1","windows-license-assurance.ps1","SIGN-RELEASE.ps1","VERIFY-AUTHENTICODE.ps1")) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source $scriptName), [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Add-Failure "Parser $scriptName $($parseError.Extent.StartLineNumber): $($parseError.Message)" }
    }
} catch {
    Add-Failure $_.Exception.Message
} finally {
    $env:TOOL_SECURE_LAUNCH = $previousSecureLaunch
    $env:TOOL_PLUGIN_DIR = $previousPluginDir
    $env:TOOL_TIMELINE_PATH = $previousTimelinePath
    $env:TOOL_TIMELINE_KEY_PATH = $previousTimelineKeyPath
    $env:TOOL_SECURE_RUNTIME_DIR = $previousSecureRuntimeDir
    if ($null -ne $pdfProfileState) {
        try {
            [void](Remove-ToolPdfProfileDirectory -ProfilePath $pdfProfileState.ProfilePath -ProfileRoot $pdfProfileState.RootPath)
        } catch {}
    }
    try {
        $tempFull = [IO.Path]::GetFullPath($tempRoot)
        $expectedPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92) + [char]92
        if ($tempFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($tempFull).StartsWith("Tool-Kiem-Tra-v4.6-extensions-", [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $tempFull -PathType Container)) {
            Remove-Item -LiteralPath $tempFull -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-EXTENSIONS: FAILED ($($failures.Count))"
    exit 1
}
Write-Host "VERIFY-EXTENSIONS: OK (HTML/JSON/XML + PDF profile ACL/cleanup + plugin sandbox + timeline HMAC/hash chain)" -ForegroundColor Green
exit 0
