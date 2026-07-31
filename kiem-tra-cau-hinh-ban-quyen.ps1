param(
    [string]$OutputDir = [Environment]::GetFolderPath("Desktop"),
    [ValidateSet("All", "Hardware", "Windows", "Office", "Software")]
    [string]$Mode = "All",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [switch]$Pdf,
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$ToolVersion = "4.3"
$ToolReleaseVersion = "4.3.0.7"

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "Cong cu can PowerShell 3.0 tro len. Windows 7 co the cai Windows Management Framework 3+ de chay."
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
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$offlinePolicyHelper = Join-Path $PSScriptRoot "Tool-OfflinePolicy.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1." }
    if (-not (Test-Path -LiteralPath $compatibilityHelper -PathType Leaf)) { throw "Thiếu Tool-Compatibility.ps1." }
    if (-not (Test-Path -LiteralPath $capabilityHelper -PathType Leaf)) { throw "Thiếu Tool-Capabilities.ps1." }
    if (-not (Test-Path -LiteralPath $loggingHelper -PathType Leaf)) { throw "Thiếu Tool-Logging.ps1." }
    if (-not (Test-Path -LiteralPath $moduleContractHelper -PathType Leaf)) { throw "Thiếu Tool-ModuleContract.ps1." }
    if (-not (Test-Path -LiteralPath $reportSchemaHelper -PathType Leaf)) { throw "Thiếu Tool-ReportSchema.ps1." }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw "Thiếu Tool-ReportExport.ps1." }
    if (-not (Test-Path -LiteralPath $pluginEngineHelper -PathType Leaf)) { throw "Thiếu Tool-PluginEngine.ps1." }
    if (-not (Test-Path -LiteralPath $timelineHelper -PathType Leaf)) { throw "Thiếu Tool-LicenseTimeline.ps1." }
    if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { throw "Thiếu Tool-Localization.ps1." }
    if (-not (Test-Path -LiteralPath $offlinePolicyHelper -PathType Leaf)) { throw "Thiếu Tool-OfflinePolicy.ps1." }
    . $runtimeHelper
    . $compatibilityHelper
    . $capabilityHelper
    . $loggingHelper
    . $moduleContractHelper
    . $reportSchemaHelper
    . $reportExportHelper
    . $pluginEngineHelper
    . $timelineHelper
    . $localizationHelper
    . $offlinePolicyHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $nativeExplorerPath = Get-ToolNativeSystemPath "explorer.exe"
    $capabilityState = Get-ToolCapabilityProfile
    $compatibilityState = Get-ToolCompatibilityMetadata
    $localizationState = Get-ToolLocalizationMetadata
    $offlinePolicyState = Get-ToolOfflinePolicyMetadata
    $reportSchemaState = Get-ToolReportSchemaMetadata
    $script:reportCulture = $Culture
    $script:reportOfflineMode = [bool](Get-ToolOfflineMode)
    $env:TOOL_UI_CULTURE = $Culture
    $moduleContractState = Get-ToolModuleContractMetadata
    $reportModuleId = Get-ToolReportModuleId -Mode $Mode
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_MODULE_ID) -and [string]$env:TOOL_MODULE_ID -ne $reportModuleId) { throw "ModuleId launcher không khớp chế độ báo cáo: $($env:TOOL_MODULE_ID)." }
    $moduleAvailability = Test-ToolModuleAvailability -ModuleId $reportModuleId -CapabilityProfile $capabilityState -SourceDirectory $PSScriptRoot
    if (-not $moduleAvailability.Available) { throw $moduleAvailability.Message }
    $moduleInvocation = New-ToolModuleInvocation -ModuleId $reportModuleId
    $loggingState = Initialize-ToolLogging -Component "Report" -ToolVersion $ToolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $ToolVersion
    [void](Write-ToolLog -Level "INFO" -Event "Report.Start" -Message "Bắt đầu tạo báo cáo $Mode." -Data ([ordered]@{ ModuleId=$reportModuleId; InvocationId=$moduleInvocation.InvocationId; Mode=$Mode; Culture=$Culture; OfflineMode=[bool]$script:reportOfflineMode; Redacted=[bool]$RedactSensitive; Capabilities=$capabilityState }))
} catch {
    Write-Host $_.Exception.Message
    exit 12
}

$ErrorActionPreference = "SilentlyContinue"
$ToolName = Get-ToolText -Key "app.title" -Culture $Culture
$ToolDescription = Get-ToolText -Key "report.description" -Culture $Culture
$DeveloperCredit = Get-ToolText -Key "app.developer" -Culture $Culture
$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$started = Get-Date
$computer = $env:COMPUTERNAME
$reportComputer = if ($RedactSensitive) { "AN_DANH" } else { $computer }
$stamp = $started.ToString("yyyyMMdd_HHmmss")
$modeInfo = switch ($Mode) {
    "Hardware" { @{ Suffix="CauHinh"; Title=(Get-ToolText -Key "report.title.hardware" -Culture $Culture) } }
    "Windows"  { @{ Suffix="BanQuyenWindows"; Title=(Get-ToolText -Key "report.title.windows" -Culture $Culture) } }
    "Office"   { @{ Suffix="BanQuyenOffice"; Title=(Get-ToolText -Key "report.title.office" -Culture $Culture) } }
    "Software" { @{ Suffix="BanQuyenPhanMem"; Title=(Get-ToolText -Key "report.title.software" -Culture $Culture) } }
    default    { @{ Suffix="ToanBo"; Title=(Get-ToolText -Key "report.title.all" -Culture $Culture) } }
}
$wantHardware = $Mode -in @("All", "Hardware")
$wantWindows = $Mode -in @("All", "Windows")
$wantOffice = $Mode -in @("All", "Office")
$wantSoftware = $Mode -in @("All", "Software")
$crackFindings = @()
$manualReviewFindings = @()
$reportTitle = $modeInfo.Title
$reportBasePath = Join-Path $OutputDir "BaoCao_$($modeInfo.Suffix)_${reportComputer}_${stamp}"
$reportPath = "$reportBasePath.html"
$pdfPath = "$reportBasePath.pdf"
$jsonPath = "$reportBasePath.json"
$xmlPath = "$reportBasePath.xml"
$manifestPath = "${reportBasePath}-SHA256SUMS.txt"

$script:reportEnglishTextMap = @{
    "Tổng quan" = "Overview"
    "Khả năng tương thích hệ thống" = "System compatibility"
    "Tổng quan bản quyền Windows" = "Windows licensing overview"
    "Chi tiết kích hoạt Windows" = "Windows activation details"
    "Tổng quan bản quyền Microsoft Office" = "Microsoft Office licensing overview"
    "Chi tiết giấy phép Microsoft Office" = "Microsoft Office license details"
    "Bảo mật phần cứng" = "Hardware security"
    "Đồ họa" = "Graphics"
    "Màn hình" = "Displays"
    "Âm thanh" = "Audio"
    "Ổ đĩa vật lý" = "Physical disks"
    "Phân vùng" = "Volumes"
    "Mạng" = "Network"
    "Card mạng" = "Network adapters"
    "Ban cap nhat Windows gan day" = "Recent Windows updates"
    "Phan mem da cai" = "Installed software"
    "Danh gia so bo ban quyen phan mem" = "Preliminary software license review"
    "Dich vu Windows" = "Windows services"
    "Dau hieu crack / activator / KMS" = "Crack / activator / KMS indicators"
    "Tu khoa chung can xac minh thu cong (khong ket luan crack)" = "Generic keywords requiring manual review (not a crack verdict)"
    "Bao mat" = "Security software"
    "May in" = "Printers"
    "Thiet bi USB / ngoai vi" = "USB and peripheral devices"
    "Thu muc chia se" = "Shared folders"
    "Scheduled tasks dang bat" = "Enabled scheduled tasks"
    "Quy tắc mở rộng bằng plugin" = "Plugin extension rules"
    "Đánh giá và phương hướng xử lý" = "Assessment and recommended handling"
    "Kiểm tra bổ sung phần mềm bên thứ ba" = "Additional third-party software inspection"
    "Tổng quan phần mềm bên thứ ba" = "Third-party software overview"
    "Danh sách phần mềm bên thứ ba" = "Third-party software inventory"
    "Chữ ký và nguồn cài đặt" = "Signatures and installation sources"
    "Phần mềm cần rà soát" = "Software requiring review"
    "Phiên bản cài song song" = "Parallel installed versions"
    "Tự khởi động của bên thứ ba" = "Third-party autoruns"
    "Muc" = "Item"
    "Gia tri" = "Value"
    "Thành phần" = "Component"
    "Trạng thái" = "Status"
    "Phương án" = "Handling"
    "San pham" = "Product"
    "Kenh / thong tin" = "Channel / details"
    "Thanh phan" = "Component"
    "Thong tin" = "Information"
    "Nguon" = "Source"
    "Khe" = "Slot"
    "Hang" = "Publisher"
    "Dung luong" = "Capacity"
    "Toc do" = "Speed"
    "Ten" = "Name"
    "Do phan giai" = "Resolution"
    "Trang thai" = "Status"
    "Nam SX" = "Year"
    "Hang ID" = "Vendor ID"
    "Loai" = "Type"
    "Tong" = "Total"
    "Con trong" = "Free"
    "Mo ta" = "Description"
    "Ngay cai" = "Install date"
    "Nguoi cai" = "Installed by"
    "Ten phan mem" = "Software"
    "Phien ban" = "Version"
    "Danh gia so bo" = "Preliminary assessment"
    "Ly do" = "Reason"
    "Lenh" = "Command"
    "Vi tri" = "Location"
    "Nguoi dung" = "User"
    "Hien thi" = "Display name"
    "Loai khoi dong" = "Startup type"
    "Dau hieu" = "Indicator"
    "Muc do" = "Severity"
    "Duong dan" = "Path"
    "Nhan" = "Label"
    "O" = "Drive"
    "Đối tượng" = "Target"
    "Đánh giá" = "Assessment"
    "Phương hướng xử lý" = "Recommended handling"
    "Phiên bản" = "Version"
    "Nhà phát hành" = "Publisher"
    "Bật" = "Enabled"
    "Quy tắc" = "Rules"
    "Tin cậy" = "Trust"
    "Mức" = "Severity"
    "Quan sát" = "Observed"
    "Nhận định" = "Assessment"
    "Hướng xử lý" = "Remediation"
    "Lỗi" = "Error"
    "Phân loại" = "Classification"
    "Phạm vi" = "Scope"
    "Kiến trúc" = "Architecture"
    "Chữ ký" = "Signature"
    "Nhà phát hành chữ ký" = "Signature publisher"
    "Tệp kiểm tra" = "Inspected file"
    "Phiên bản tệp" = "File version"
    "Có trình gỡ" = "Uninstaller"
    "Metadata cập nhật" = "Update metadata"
    "Lệnh gỡ" = "Uninstall command"
    "Khóa đăng ký" = "Registry key"
    "Mức rà soát" = "Review level"
    "Lý do rà soát" = "Review reason"
    "Số lượng" = "Count"
    "Hành động" = "Action"
    "Nhóm" = "Group"
    "May tinh" = "Computer"
    "Ngay kiem tra" = "Inspection time"
    "He dieu hanh" = "Operating system"
    "Kien truc" = "Architecture"
    "Ngay cai Windows" = "Windows install date"
    "Lan khoi dong cuoi" = "Last boot"
    "Hang / Model" = "Vendor / model"
    "Không phát hiện Click-to-Run" = "Click-to-Run was not detected"
    "Không khả dụng" = "Unavailable"
    "Có thể truy vấn" = "Available for query"
    "Ẩn/ghi không hỗ trợ" = "Hidden / recorded as unsupported"
    "Nguồn quản trị không khả dụng" = "Management source unavailable"
    "Chưa cấp phép" = "Unlicensed"
    "Đã cấp phép" = "Licensed"
    "Thời gian gia hạn OOB" = "OOB grace period"
    "Thời gian gia hạn OOT" = "OOT grace period"
    "Gia hạn không chính hãng" = "Non-genuine grace period"
    "Thông báo" = "Notification"
    "Gia hạn mở rộng" = "Extended grace"
    "Khong xac dinh" = "Unknown"
    "Đã kích hoạt" = "Activated"
    "Chưa kích hoạt hoặc đang ở thời gian gia hạn/thông báo" = "Not activated or in grace/notification state"
    "Không đọc được thông tin giấy phép" = "License information could not be read"
    "Chưa kích hoạt hoặc giấy phép cần kiểm tra" = "Not activated or the license needs review"
    "Đã phát hiện Office, chưa xác nhận được giấy phép" = "Office detected; licensing not confirmed"
    "Không phát hiện Microsoft Office" = "Microsoft Office was not detected"
    "Có cmdlet nhưng không đọc được" = "The cmdlet exists but data could not be read"
    "Không hỗ trợ trên cấu hình Windows hiện tại" = "Not supported by the current Windows configuration"
    "Có cmdlet nhưng firmware không hỗ trợ/không đọc được" = "The cmdlet exists but firmware is unsupported or unreadable"
    "Can doi chieu hoa don/license" = "Invoice/license reconciliation required"
    "Co thong tin cai dat, chua xac minh duoc ban quyen that neu khong doi chieu ho so." = "Installation metadata exists; entitlement cannot be confirmed without purchase/license records."
    "Co dau hieu nghi khong chinh hang" = "Specific suspicious indicator detected"
    "Ten phan mem/publisher khop mau activator dac hieu; van can xac minh chu ky va nguon cai dat." = "The software/publisher name matches a specific activator pattern; verify its signature and installation source."
    "Tu khoa chung - can xac minh thu cong" = "Generic keyword — manual review required"
    "Tu khoa activation/patch/portable co the hop le; khong du de ket luan crack neu khong co bang chung khac." = "Activation/patch/portable keywords can be legitimate and are not sufficient for a crack verdict without other evidence."
    "Thieu thong tin nha phat hanh" = "Publisher information missing"
    "Can kiem tra nguon cai dat va hoa don/license." = "Review the installation source and purchase/license records."
    "Can kiem tra ngay" = "Review promptly"
    "Tu khoa chung - khong du ket luan" = "Generic keyword — insufficient for a verdict"
    "Can kiem tra" = "Review required"
    "Dau hieu theo ten file" = "Filename indicator"
    "Đã che dữ liệu nhạy cảm" = "Sensitive data redacted"
    "Báo cáo đầy đủ nội bộ" = "Complete internal report"
    "[ĐÃ CHE]" = "[REDACTED]"
    "[IP ĐÃ CHE]" = "[IP REDACTED]"
    "[MAC ĐÃ CHE]" = "[MAC REDACTED]"
}

function Get-ReportPresentationText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if ($Culture -ne "en-US") { return $text }
    if ($script:reportEnglishTextMap.ContainsKey($text)) { return [string]$script:reportEnglishTextMap[$text] }
    $replacements = @(
        @('(?m)^San pham:', 'Product:'),
        @('(?m)^Dong san pham:', 'Product family:'),
        @('(?m)^Phien ban:', 'Version:'),
        @('(?m)^Kenh:', 'Channel:'),
        @('(?m)^Doi chieu catalog:', 'Catalog comparison:'),
        @('(?m)^Nen tang:', 'Platform:'),
        @('(?m)^Trang thai:', 'Status:'),
        @('(?m)^Mo ta:', 'Description:'),
        @('(?m)^Partial key:', 'Partial key:'),
        @('(?i)\bngay\b', 'days'),
        @('(?i)\bgio\b', 'hours'),
        @('(?i)\bphut\b', 'minutes')
    )
    foreach ($replacement in $replacements) {
        $text = [regex]::Replace($text, [string]$replacement[0], [string]$replacement[1])
    }
    return $text
}

function Select-ReportText {
    param(
        [Parameter(Mandatory = $true)][string]$Vietnamese,
        [Parameter(Mandatory = $true)][string]$English
    )
    if ($Culture -eq "en-US") { return $English }
    return $Vietnamese
}

function Protect-ReportText($value) {
    if ($null -eq $value) { return "" }
    $text = [string]$value
    if (-not $RedactSensitive) { return $text }

    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
            $secretPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $secretPattern, "[ĐÃ CHE]", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $ipv4Part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$ipv4Part(?:\.$ipv4Part){3}(?![0-9.])", "[IP ĐÃ CHE]")
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', '[MAC ĐÃ CHE]')
    return $text
}

function ConvertTo-ReportRedactedObject {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0
    )

    if (-not $RedactSensitive -or $null -eq $Value) { return $Value }
    if ($Depth -gt 12) { return Protect-ReportText $Value }
    if ($Value -is [string]) { return Protect-ReportText $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[[string]$key] = ConvertTo-ReportRedactedObject -Value $Value[$key] -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-ReportRedactedObject -Value $_ -Depth ($Depth + 1) })
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and
        $Value -isnot [ValueType] -and $Value -isnot [DateTime]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties)) {
            $result[[string]$property.Name] = ConvertTo-ReportRedactedObject -Value $property.Value -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    return $Value
}

function Protect-ReportCell($row, [string]$column, $value) {
    if (-not $RedactSensitive) { return $value }
    $rowLabel = ""
    if ($row -and $row.PSObject.Properties["Muc"]) { $rowLabel = [string]$row.PSObject.Properties["Muc"].Value }
    if ($column -match '(?i)^Serial$' -or
        $column -match '(?i)^(User|Nguoi dung|Author)$' -or
        ($column -eq "Gia tri" -and $rowLabel -match '(?i)^(May tinh|Nguoi dung|Windows Product ID|Serial BIOS)$')) {
        return "[ĐÃ CHE]"
    }
    return Protect-ReportText $value
}

function Html($value) {
    $safeValue = Protect-ReportText $value
    $safeValue = Get-ReportPresentationText $safeValue
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch { return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue) }
}

function Size-GB($bytes) {
    if ($null -eq $bytes -or $bytes -eq 0) { return "" }
    return "{0:N1} GB" -f ([double]$bytes / 1GB)
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
        } finally { $stream.Dispose() }
    } catch { return "" }
}

function Add-Section {
    param(
        [string]$Title,
        [string]$Body,
        [ValidateSet("Hardware", "Windows", "Office", "Software")]
        [string]$Category = "Hardware"
    )
    if ($script:Mode -eq "All" -or $script:Mode -eq $Category) {
        $script:sectionCounter++
        $sectionId = "section-$($script:sectionCounter)"
        $script:tocItems += [pscustomobject]@{ Id=$sectionId; Title=$Title }
        $script:sections += "<section id='$sectionId'><h2>$(Html $Title)</h2>$Body</section>"
    }
}

function Add-Table {
    param([object[]]$Rows, [string[]]$Columns)
    if (-not $Rows -or $Rows.Count -eq 0) {
        return "<p class='muted'>$(Html (Select-ReportText -Vietnamese 'Không có dữ liệu.' -English 'No data available.'))</p>"
    }
    $html = "<table><thead><tr>"
    foreach ($col in $Columns) { $html += "<th>$(Html $col)</th>" }
    $html += "</tr></thead><tbody>"
    foreach ($row in $Rows) {
        $html += "<tr>"
        foreach ($col in $Columns) {
            $value = $row.PSObject.Properties[$col].Value
            $html += "<td>$(Html (Protect-ReportCell $row $col $value))</td>"
        }
        $html += "</tr>"
    }
    $html += "</tbody></table>"
    return $html
}

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2")
    # Windows 7 thuong chi co PowerShell 2/3, chua co Get-CimInstance.
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
        } else {
            Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop
        }
    } catch {
        try { Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop } catch { @() }
    }
}

function Get-ExecutablePathFromMetadata {
    param(
        [AllowNull()][string[]]$Candidates,
        [AllowNull()][string]$PreferredName = ""
    )

    foreach ($candidateText in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateText)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$candidateText).Trim()
        $candidatePath = ""
        if ($expanded -match '^\s*"([^"]+?\.exe)"') {
            $candidatePath = [string]$matches[1]
        } elseif ($expanded -match '^\s*([^,]+?\.exe)(?:\s|,|$)') {
            $candidatePath = [string]$matches[1]
        }
        $candidatePath = $candidatePath.Trim().Trim('"')
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and [IO.Path]::IsPathRooted($candidatePath)) {
            try {
                $fullPath = [IO.Path]::GetFullPath($candidatePath)
                if (Test-Path -LiteralPath $fullPath -PathType Leaf) { return $fullPath }
            } catch {}
        }

        $directoryPath = $expanded.Trim('"').TrimEnd('\')
        if (-not [IO.Path]::IsPathRooted($directoryPath) -or -not (Test-Path -LiteralPath $directoryPath -PathType Container)) { continue }
        try {
            $preferredToken = ([regex]::Replace([string]$PreferredName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
            $executables = @(Get-ChildItem -LiteralPath $directoryPath -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)^(unins|uninstall|setup|update|helper|crash)' } |
                Select-Object -First 24)
            if ($executables.Count -eq 0) { continue }
            if (-not [string]::IsNullOrWhiteSpace($preferredToken)) {
                $matched = $executables | Where-Object {
                    $fileToken = ([regex]::Replace([string]$_.BaseName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
                    $fileToken -and ($preferredToken.Contains($fileToken) -or $fileToken.Contains($preferredToken))
                } | Select-Object -First 1
                if ($matched) { return [string]$matched.FullName }
            }
            return [string]$executables[0].FullName
        } catch {}
    }
    return ""
}

function Get-SoftwareSignatureState {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ Status="NotChecked"; Publisher=""; FileVersion=""; Path="" }
    }
    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $publisher = ""
        if ($signature.SignerCertificate) { $publisher = [string]$signature.SignerCertificate.Subject }
        $version = ""
        try { $version = [string](Get-Item -LiteralPath $Path -Force).VersionInfo.FileVersion } catch {}
        return [pscustomobject][ordered]@{
            Status = [string]$signature.Status
            Publisher = $publisher
            FileVersion = $version
            Path = $Path
        }
    } catch {
        return [pscustomobject][ordered]@{ Status="UnknownError"; Publisher=""; FileVersion=""; Path=$Path }
    }
}

function Get-CachedSoftwareSignatureState {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return Get-SoftwareSignatureState -Path ""
    }
    if ($null -eq $script:softwareSignatureCache) { $script:softwareSignatureCache = @{} }
    $cacheKey = ([string]$Path).ToLowerInvariant()
    if (-not $script:softwareSignatureCache.ContainsKey($cacheKey)) {
        $script:softwareSignatureCache[$cacheKey] = Get-SoftwareSignatureState -Path $Path
    }
    return $script:softwareSignatureCache[$cacheKey]
}

function Get-SoftwareSignatureLabel {
    param([AllowNull()][string]$Status)

    switch ([string]$Status) {
        "Valid" { return Select-ReportText -Vietnamese "Hợp lệ" -English "Valid" }
        "NotSigned" { return Select-ReportText -Vietnamese "Không ký" -English "Unsigned" }
        "HashMismatch" { return Select-ReportText -Vietnamese "Sai mã băm" -English "Hash mismatch" }
        "NotTrusted" { return Select-ReportText -Vietnamese "Không tin cậy" -English "Untrusted" }
        "NotSupportedFileFormat" { return Select-ReportText -Vietnamese "Định dạng không hỗ trợ" -English "Unsupported format" }
        "UnknownError" { return Select-ReportText -Vietnamese "Lỗi kiểm tra" -English "Inspection error" }
        default { return Select-ReportText -Vietnamese "Chưa kiểm tra (không tìm thấy tệp đại diện)" -English "Not inspected (representative file not found)" }
    }
}

function Test-MicrosoftSoftwarePublisher {
    param([AllowNull()][string]$Publisher)
    if ([string]::IsNullOrWhiteSpace([string]$Publisher)) { return $false }
    return [bool]($Publisher -match '(?i)^\s*Microsoft(?:\s+Corporation)?\b')
}

function Find-Browser {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramW6432\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramW6432\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return ""
}

function Convert-HtmlToPdf {
    param([string]$HtmlPath, [string]$OutPath)
    $browser = Find-Browser
    if (-not $browser) {
        Write-Host "Khong tim thay Edge/Chrome de xuat PDF."
        return $false
    }
    $htmlUri = ([System.Uri](Resolve-Path -LiteralPath $HtmlPath).Path).AbsoluteUri
    $args = @(
        "--headless",
        "--disable-gpu",
        "--no-first-run",
        "--print-to-pdf=$OutPath",
        $htmlUri
    )
    $process = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Hidden
    $process.WaitForExit(30000) | Out-Null
    return (Test-Path -LiteralPath $OutPath)
}

function License-StatusText($code) {
    switch ([int]$code) {
        0 { "Chưa cấp phép" }
        1 { "Đã cấp phép" }
        2 { "Thời gian gia hạn OOB" }
        3 { "Thời gian gia hạn OOT" }
        4 { "Gia hạn không chính hãng" }
        5 { "Thông báo" }
        6 { "Gia hạn mở rộng" }
        default { "$code" }
    }
}

$sections = @()
$tocItems = @()
$sectionCounter = 0
$os = Safe-Cim Win32_OperatingSystem | Select-Object -First 1
$cs = Safe-Cim Win32_ComputerSystem | Select-Object -First 1
$bios = Safe-Cim Win32_BIOS | Select-Object -First 1
$cpu = Safe-Cim Win32_Processor | Select-Object -First 1
$board = Safe-Cim Win32_BaseBoard | Select-Object -First 1

$uptime = ""
if ($os.LastBootUpTime) {
    $span = (Get-Date) - $os.LastBootUpTime
    $uptime = "{0} ngay {1} gio {2} phut" -f [int]$span.TotalDays, $span.Hours, $span.Minutes
}

$summary = @(
    [pscustomobject]@{ "Muc"="May tinh"; "Gia tri"=$computer },
    [pscustomobject]@{ "Muc"="Nguoi dung"; "Gia tri"=$env:USERNAME },
    [pscustomobject]@{ "Muc"="Ngay kiem tra"; "Gia tri"=$started.ToString("yyyy-MM-dd HH:mm:ss") },
    [pscustomobject]@{ "Muc"="He dieu hanh"; "Gia tri"="$($os.Caption) $($os.Version) build $($os.BuildNumber)" },
    [pscustomobject]@{ "Muc"="Kien truc"; "Gia tri"=$os.OSArchitecture },
    [pscustomobject]@{ "Muc"="Windows Product ID"; "Gia tri"=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductId },
    [pscustomobject]@{ "Muc"="Ngay cai Windows"; "Gia tri"=$os.InstallDate },
    [pscustomobject]@{ "Muc"="Lan khoi dong cuoi"; "Gia tri"=$os.LastBootUpTime },
    [pscustomobject]@{ "Muc"="Uptime"; "Gia tri"=$uptime },
    [pscustomobject]@{ "Muc"="Hang / Model"; "Gia tri"="$($cs.Manufacturer) $($cs.Model)" },
    [pscustomobject]@{ "Muc"="Domain / Workgroup"; "Gia tri"=$cs.Domain },
    [pscustomobject]@{ "Muc"="System type"; "Gia tri"=$cs.SystemType },
    [pscustomobject]@{ "Muc"="Serial BIOS"; "Gia tri"=$bios.SerialNumber },
    [pscustomobject]@{ "Muc"="BIOS"; "Gia tri"="$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) $($bios.ReleaseDate)" },
    [pscustomobject]@{ "Muc"="Mainboard"; "Gia tri"="$($board.Manufacturer) $($board.Product)" },
    [pscustomobject]@{ "Muc"="CPU"; "Gia tri"=$cpu.Name },
    [pscustomobject]@{ "Muc"="RAM"; "Gia tri"=(Size-GB $cs.TotalPhysicalMemory) }
)
Add-Section "Tổng quan" (Add-Table $summary @("Muc","Gia tri"))

$capabilityRows = @(
    [pscustomobject]@{ "Thành phần"="Hợp đồng mô-đun"; "Trạng thái"="schema $($moduleContractState.ContractSchemaVersion)"; "Phương án"="$reportModuleId / $($moduleAvailability.Descriptor.AccessMode)" },
    [pscustomobject]@{ "Thành phần"="Windows release"; "Trạng thái"="$($capabilityState.WindowsReleaseName) build $($capabilityState.FullBuildNumber)"; "Phương án"="Catalog $($compatibilityState.ReviewedAtUtc); servicing $($capabilityState.WindowsServicingState)" },
    [pscustomobject]@{ "Thành phần"="Office compatibility"; "Trạng thái"=$capabilityState.OfficeSummary; "Phương án"=if ($capabilityState.OfficeCompatibility -and $capabilityState.OfficeCompatibility.Detected) { "$($capabilityState.OfficeCompatibility.Version) · $($capabilityState.OfficeCompatibility.Channel) · $($capabilityState.OfficeCompatibility.Currency)" } else { "Không phát hiện Click-to-Run" } },
    [pscustomobject]@{ "Thành phần"="Offline policy"; "Trạng thái"=if ($script:reportOfflineMode) { "Offline" } else { "Network allowed" }; "Phương án"="Không telemetry; HTML/PDF chỉ dùng tài nguyên cục bộ" },
    [pscustomobject]@{ "Thành phần"="Mức tương thích"; "Trạng thái"=$capabilityState.CompatibilityTier; "Phương án"="Tự chọn tính năng/fallback theo hệ điều hành" },
    [pscustomobject]@{ "Thành phần"="CIM"; "Trạng thái"=[bool]$capabilityState.CimCmdlets; "Phương án"=if ($capabilityState.CimCmdlets) { "Ưu tiên Get-CimInstance" } elseif ($capabilityState.WmiFallback) { "Dùng WMI fallback" } else { "Nguồn quản trị không khả dụng" } },
    [pscustomobject]@{ "Thành phần"="Scheduled Tasks"; "Trạng thái"=[bool]$capabilityState.ScheduledTasksModule; "Phương án"=if ($capabilityState.ScheduledTasksModule) { "ScheduledTasks module" } elseif ($capabilityState.ScheduledTasksFallback) { "schtasks.exe fallback" } else { "Không khả dụng" } },
    [pscustomobject]@{ "Thành phần"="Microsoft Defender cmdlets"; "Trạng thái"=[bool]$capabilityState.DefenderCmdlets; "Phương án"=if ($capabilityState.DefenderCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } },
    [pscustomobject]@{ "Thành phần"="TPM cmdlets"; "Trạng thái"=[bool]$capabilityState.TpmCmdlets; "Phương án"=if ($capabilityState.TpmCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } },
    [pscustomobject]@{ "Thành phần"="BitLocker cmdlets"; "Trạng thái"=[bool]$capabilityState.BitLockerCmdlets; "Phương án"=if ($capabilityState.BitLockerCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } }
)
Add-Section "Khả năng tương thích hệ thống" (Add-Table $capabilityRows @("Thành phần","Trạng thái","Phương án"))

$activationText = ""
$licenseRows = @()
$windowsLicenses = @()
$windowsLicenseBody = ""
if ($wantWindows) {
try {
    $slmgr = & $nativeCscriptPath //nologo (Get-ToolNativeSystemPath "slmgr.vbs") /xpr 2>$null
    $activationText = ($slmgr -join "`n").Trim()
} catch {}
$licenseRows = @(
    [pscustomobject]@{ "Muc"="Trang thai kich hoat Windows"; "Gia tri"=$activationText }
)
$windowsLicenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Windows"
} | Sort-Object LicenseStatus -Descending
foreach ($license in $windowsLicenses) {
    $method = "Khong xac dinh"
    if ($license.Description -match "KMSCLIENT|VOLUME_KMS") {
        $method = "KMS client / kich hoat qua KMS"
    } elseif ($license.Description -match "VOLUME_MAK|MAK") {
        $method = "Volume MAK"
    } elseif ($license.Description -match "RETAIL") {
        $method = "Retail"
    } elseif ($license.Description -match "OEM") {
        $method = "OEM"
    }
    $licenseRows += [pscustomobject]@{ "Muc"="Windows edition"; "Gia tri"=$license.Name }
    $licenseRows += [pscustomobject]@{ "Muc"="Mo ta / kenh key"; "Gia tri"=$license.Description }
    $licenseRows += [pscustomobject]@{ "Muc"="Phuong thuc kich hoat so bo"; "Gia tri"=$method }
    $licenseRows += [pscustomobject]@{ "Muc"="Trang thai license"; "Gia tri"=(License-StatusText $license.LicenseStatus) }
    $licenseRows += [pscustomobject]@{ "Muc"="Partial product key"; "Gia tri"=$license.PartialProductKey }
    if ($license.KeyManagementServiceMachine) {
        $licenseRows += [pscustomobject]@{ "Muc"="KMS server"; "Gia tri"=$license.KeyManagementServiceMachine }
    }
    if ($license.KeyManagementServicePort) {
        $licenseRows += [pscustomobject]@{ "Muc"="KMS port"; "Gia tri"=$license.KeyManagementServicePort }
    }
    if ($license.GracePeriodRemaining) {
        $licenseRows += [pscustomobject]@{ "Muc"="Grace con lai"; "Gia tri"="$($license.GracePeriodRemaining) phut" }
    }
}
$windowsLicenseBody = Add-Table $licenseRows @("Muc","Gia tri")
}

$officeRows = @()
$officeRawStatus = @()
$officeCimLicenses = @()
$clickToRun = $null
if ($wantOffice) {
$osppRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
    Where-Object { $_ } | Select-Object -Unique | ForEach-Object { Join-Path $_ "Microsoft Office" }
foreach ($root in $osppRoots) {
    if (Test-Path -LiteralPath $root) {
        $ospp = Get-ChildItem -LiteralPath $root -Recurse -Filter OSPP.VBS -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ospp) {
            try {
                $status = & $nativeCscriptPath //nologo $ospp.FullName /dstatus 2>$null
                $officeRawStatus += $status
                $officeRows += [pscustomobject]@{
                    "Thanh phan"="Microsoft Office"
                    "Thong tin"=(($status | Where-Object { $_ -match "LICENSE|PRODUCT ID|LICENSE DESCRIPTION|Last 5|KMS|ERROR" }) -join "`n")
                    "Nguon"=$ospp.FullName
                }
            } catch {}
        }
    }
}

$clickToRun = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
if (-not $clickToRun) {
    $clickToRun = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
}
if ($clickToRun) {
    $officeRows += [pscustomobject]@{
        "Thanh phan"="Office Click-to-Run"
        "Thong tin"="San pham: $($clickToRun.ProductReleaseIds)`nDong san pham: $($capabilityState.OfficeCompatibility.Family)`nPhien ban: $($clickToRun.ClientVersionToReport)`nKenh: $($capabilityState.OfficeCompatibility.Channel)`nDoi chieu catalog: $($capabilityState.OfficeCompatibility.Currency)`nNen tang: $($clickToRun.Platform)"
        "Nguon"="Office ClickToRun Configuration + compatibility catalog"
    }
}

$officeCimLicenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Office"
} | Sort-Object LicenseStatus -Descending
foreach ($license in $officeCimLicenses) {
    $officeRows += [pscustomobject]@{
        "Thanh phan"=$license.Name
        "Thong tin"="Trang thai: $(License-StatusText $license.LicenseStatus)`nMo ta: $($license.Description)`nPartial key: $($license.PartialProductKey)"
        "Nguon"="SoftwareLicensingProduct"
    }
}
}

$activeWindowsLicense = $windowsLicenses | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
$windowsSummaryStatus = if ($activeWindowsLicense) {
    "Đã kích hoạt"
} elseif ($windowsLicenses) {
    "Chưa kích hoạt hoặc đang ở thời gian gia hạn/thông báo"
} else {
    "Không đọc được thông tin giấy phép"
}
$windowsSummaryChannel = if ($activeWindowsLicense) {
    if ($activeWindowsLicense.Description -match "KMSCLIENT|VOLUME_KMS") { "KMS client / Volume KMS" }
    elseif ($activeWindowsLicense.Description -match "VOLUME_MAK|MAK") { "Volume MAK" }
    elseif ($activeWindowsLicense.Description -match "RETAIL") { "Retail" }
    elseif ($activeWindowsLicense.Description -match "OEM") { "OEM" }
    else { $activeWindowsLicense.Description }
} else {
    "Khong xac dinh"
}

$officeStatusText = ($officeRawStatus -join "`n")
$activeOfficeLicense = $officeCimLicenses | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
$officeDetected = ($officeRows.Count -gt 0)
$officeSummaryStatus = if ($activeOfficeLicense -or $officeStatusText -match "LICENSE STATUS:\s+---LICENSED---") {
    "Đã kích hoạt"
} elseif ($officeStatusText -match "LICENSE STATUS" -or $officeCimLicenses) {
    "Chưa kích hoạt hoặc giấy phép cần kiểm tra"
} elseif ($officeDetected) {
    "Đã phát hiện Office, chưa xác nhận được giấy phép"
} else {
    "Không phát hiện Microsoft Office"
}

$licenseOverviewRows = @(
    [pscustomobject]@{ "San pham"="Windows"; "Trang thai"=$windowsSummaryStatus; "Kenh / thong tin"=$windowsSummaryChannel },
    [pscustomobject]@{ "San pham"="Microsoft Office"; "Trang thai"=$officeSummaryStatus; "Kenh / thong tin"=if ($activeOfficeLicense) { $activeOfficeLicense.Description } elseif ($clickToRun) { $clickToRun.ProductReleaseIds } else { "Khong xac dinh" } }
)
$licenseOverviewNote = Select-ReportText `
    "Trạng thái đã kích hoạt không tự động chứng minh bản quyền hợp lệ. Cần đối chiếu hóa đơn, hợp đồng, tài khoản Microsoft 365 hoặc hồ sơ cấp phép để kết luận." `
    "An activated state does not by itself prove valid entitlement. Reconcile it with invoices, agreements, the licensed Microsoft 365 account, or other license records."
$windowsOverviewNote = Select-ReportText `
    "Trạng thái đã kích hoạt không tự động chứng minh bản quyền hợp lệ. Cần đối chiếu hóa đơn, hợp đồng hoặc hồ sơ cấp phép để kết luận." `
    "An activated state does not by itself prove valid entitlement. Reconcile it with invoices, agreements, or other license records."
$officeOverviewNote = Select-ReportText `
    "Trạng thái đã kích hoạt không tự động chứng minh bản quyền hợp lệ. Cần đối chiếu hóa đơn, tài khoản Microsoft 365 hoặc hồ sơ cấp phép để kết luận." `
    "An activated state does not by itself prove valid entitlement. Reconcile it with invoices, the licensed Microsoft 365 account, or other license records."
$noteLabel = Select-ReportText "Lưu ý:" "Note:"
$licenseOverviewBody = (Add-Table $licenseOverviewRows @("San pham","Trang thai","Kenh / thong tin")) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $licenseOverviewNote)</p>"
$windowsOverviewBody = (Add-Table @($licenseOverviewRows | Where-Object { $_."San pham" -eq "Windows" }) @("San pham","Trang thai","Kenh / thong tin")) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $windowsOverviewNote)</p>"
$officeOverviewBody = (Add-Table @($licenseOverviewRows | Where-Object { $_."San pham" -eq "Microsoft Office" }) @("San pham","Trang thai","Kenh / thong tin")) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $officeOverviewNote)</p>"

Add-Section "Tổng quan bản quyền Windows" $windowsOverviewBody "Windows"
Add-Section "Chi tiết kích hoạt Windows" $windowsLicenseBody "Windows"
Add-Section "Tổng quan bản quyền Microsoft Office" $officeOverviewBody "Office"
Add-Section "Chi tiết giấy phép Microsoft Office" (Add-Table $officeRows @("Thanh phan","Thong tin","Nguon")) "Office"

if ($wantHardware) {
$platformRows = @()
if ($capabilityState.TpmCmdlets) {
    try {
        $tpm = Get-Tpm
        $platformRows += [pscustomobject]@{ "Muc"="TPM present"; "Gia tri"=$tpm.TpmPresent }
        $platformRows += [pscustomobject]@{ "Muc"="TPM ready"; "Gia tri"=$tpm.TpmReady }
        $platformRows += [pscustomobject]@{ "Muc"="TPM enabled"; "Gia tri"=$tpm.TpmEnabled }
    } catch {
        $platformRows += [pscustomobject]@{ "Muc"="TPM"; "Gia tri"="Có cmdlet nhưng không đọc được" }
    }
} else {
    $platformRows += [pscustomobject]@{ "Muc"="TPM"; "Gia tri"="Không hỗ trợ trên cấu hình Windows hiện tại" }
}
if ($capabilityState.SecureBootCmdlet) {
    try {
        $platformRows += [pscustomobject]@{ "Muc"="Secure Boot"; "Gia tri"=(Confirm-SecureBootUEFI) }
    } catch {
        $platformRows += [pscustomobject]@{ "Muc"="Secure Boot"; "Gia tri"="Có cmdlet nhưng firmware không hỗ trợ/không đọc được" }
    }
} else {
    $platformRows += [pscustomobject]@{ "Muc"="Secure Boot"; "Gia tri"="Không hỗ trợ trên cấu hình Windows hiện tại" }
}
if ($capabilityState.BitLockerCmdlets) {
    try {
        $bitlocker = Get-BitLockerVolume -ErrorAction Stop 2>$null
        foreach ($volume in $bitlocker) {
            $platformRows += [pscustomobject]@{
                "Muc"="BitLocker $($volume.MountPoint)"
                "Gia tri"="$($volume.ProtectionStatus) / $($volume.VolumeStatus)"
            }
        }
    } catch {
        $platformRows += [pscustomobject]@{ "Muc"="BitLocker"; "Gia tri"="Có cmdlet nhưng không đọc được" }
    }
} else {
    $platformRows += [pscustomobject]@{ "Muc"="BitLocker"; "Gia tri"="Không hỗ trợ trên cấu hình Windows hiện tại" }
}
Add-Section "Bảo mật phần cứng" (Add-Table $platformRows @("Muc","Gia tri"))

$memory = Safe-Cim Win32_PhysicalMemory | ForEach-Object {
    [pscustomobject]@{
        "Khe"=$_.DeviceLocator
        "Hang"=$_.Manufacturer
        "Dung luong"=(Size-GB $_.Capacity)
        "Toc do"=$_.Speed
        "Serial"=$_.SerialNumber
    }
}
Add-Section "RAM" (Add-Table $memory @("Khe","Hang","Dung luong","Toc do","Serial"))

$gpu = Safe-Cim Win32_VideoController | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "RAM"=(Size-GB $_.AdapterRAM)
        "Driver"=$_.DriverVersion
        "Do phan giai"="$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        "Trang thai"=$_.Status
    }
}
Add-Section "Đồ họa" (Add-Table $gpu @("Ten","RAM","Driver","Do phan giai","Trang thai"))

$monitors = @()
try {
    $monitors = Safe-Cim WmiMonitorID root/wmi | ForEach-Object {
        $name = ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
        $serial = ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
        [pscustomobject]@{
            "Ten"=$name
            "Serial"=$serial
            "Nam SX"=$_.YearOfManufacture
            "Hang ID"=$_.ManufacturerName
        }
    }
} catch {}
Add-Section "Màn hình" (Add-Table $monitors @("Ten","Serial","Nam SX","Hang ID"))

$sound = Safe-Cim Win32_SoundDevice | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "Hang"=$_.Manufacturer
        "Trang thai"=$_.Status
    }
}
Add-Section "Âm thanh" (Add-Table $sound @("Ten","Hang","Trang thai"))

$disks = Safe-Cim Win32_DiskDrive | ForEach-Object {
    [pscustomobject]@{
        "Model"=$_.Model
        "Loai"=$_.MediaType
        "Dung luong"=(Size-GB $_.Size)
        "Serial"=$_.SerialNumber
        "Interface"=$_.InterfaceType
        "Trang thai"=$_.Status
    }
}
Add-Section "Ổ đĩa vật lý" (Add-Table $disks @("Model","Loai","Dung luong","Serial","Interface","Trang thai"))

$volumes = Safe-Cim Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
    [pscustomobject]@{
        "O"=$_.DeviceID
        "Nhan"=$_.VolumeName
        "File system"=$_.FileSystem
        "Tong"=(Size-GB $_.Size)
        "Con trong"=(Size-GB $_.FreeSpace)
    }
}
Add-Section "Phân vùng" (Add-Table $volumes @("O","Nhan","File system","Tong","Con trong"))

$network = @()
try {
    if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
        $network = Get-NetIPConfiguration | ForEach-Object {
            [pscustomobject]@{
                "Adapter"=$_.InterfaceAlias
                "IPv4"=(($_.IPv4Address | Select-Object -ExpandProperty IPAddress) -join ", ")
                "Gateway"=(($_.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop) -join ", ")
                "DNS"=(($_.DNSServer.ServerAddresses) -join ", ")
            }
        }
    } else {
        $network = Safe-Cim Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | ForEach-Object {
            [pscustomobject]@{
                "Adapter"=$_.Description
                "IPv4"=(($_.IPAddress | Where-Object { $_ -match '^\d+\.' }) -join ", ")
                "Gateway"=(($_.DefaultIPGateway) -join ", ")
                "DNS"=(($_.DNSServerSearchOrder) -join ", ")
            }
        }
    }
} catch {}
Add-Section "Mạng" (Add-Table $network @("Adapter","IPv4","Gateway","DNS"))

$adapters = @()
try {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        $adapters = Get-NetAdapter | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Mo ta"=$_.InterfaceDescription
                "MAC"=$_.MacAddress
                "Toc do"=$_.LinkSpeed
                "Trang thai"=$_.Status
            }
        }
    } else {
        $adapters = Safe-Cim Win32_NetworkAdapter | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.NetConnectionID
                "Mo ta"=$_.Name
                "MAC"=$_.MACAddress
                "Toc do"=$_.Speed
                "Trang thai"=$_.NetConnectionStatus
            }
        }
    }
} catch {}
Add-Section "Card mạng" (Add-Table $adapters @("Ten","Mo ta","MAC","Toc do","Trang thai"))
}

if ($wantWindows) {
$hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 80 | ForEach-Object {
    [pscustomobject]@{
        "HotFix"=$_.HotFixID
        "Mo ta"=$_.Description
        "Ngay cai"=$_.InstalledOn
        "Nguoi cai"=$_.InstalledBy
    }
}
Add-Section "Ban cap nhat Windows gan day" (Add-Table $hotfixes @("HotFix","Mo ta","Ngay cai","Nguoi cai")) "Windows"
}

if ($wantSoftware) {
    $apps = @()
    $machineArchitecture = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
    $uninstallSources = @(
        [pscustomobject]@{
            Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Scope = (Select-ReportText -Vietnamese "Máy" -English "Machine")
            Architecture = $machineArchitecture
        },
        [pscustomobject]@{
            Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Scope = (Select-ReportText -Vietnamese "Máy" -English "Machine")
            Architecture = "32-bit"
        },
        [pscustomobject]@{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Scope = (Select-ReportText -Vietnamese "Người dùng hiện tại" -English "Current user")
            Architecture = (Select-ReportText -Vietnamese "Không xác định" -English "Unknown")
        }
    )

    foreach ($source in $uninstallSources) {
        $registryItems = @(Get-ItemProperty -Path $source.Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
        foreach ($item in $registryItems) {
            $representativeFile = Get-ExecutablePathFromMetadata -Candidates @(
                [string]$item.DisplayIcon,
                [string]$item.ModifyPath,
                [string]$item.InstallLocation
            ) -PreferredName ([string]$item.DisplayName)
            $signature = Get-CachedSoftwareSignatureState -Path $representativeFile
            $publisher = [string]$item.Publisher
            $isMicrosoft = (Test-MicrosoftSoftwarePublisher -Publisher $publisher) -or
                ([string]$item.DisplayName -match '(?i)^\s*(Microsoft|Windows)\b')
            $hasUninstaller = -not [string]::IsNullOrWhiteSpace([string]$item.UninstallString)
            $hasUpdateMetadata = -not [string]::IsNullOrWhiteSpace(
                [string](@($item.URLUpdateInfo, $item.HelpLink, $item.ModifyPath, $item.InstallSource) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    Select-Object -First 1)
            )
            $registryKey = [string]$item.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
            $apps += [pscustomobject][ordered]@{
                "Ten phan mem" = [string]$item.DisplayName
                "Phien ban" = [string]$item.DisplayVersion
                "Hang" = $publisher
                "Ngay cai" = [string]$item.InstallDate
                "Phân loại" = if ($isMicrosoft) {
                    Select-ReportText -Vietnamese "Microsoft / hệ điều hành" -English "Microsoft / operating system"
                } else {
                    Select-ReportText -Vietnamese "Bên thứ ba" -English "Third-party"
                }
                "Phạm vi" = [string]$source.Scope
                "Kiến trúc" = [string]$source.Architecture
                "Duong dan" = [string]$item.InstallLocation
                "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$signature.Status)
                "Nhà phát hành chữ ký" = [string]$signature.Publisher
                "Tệp kiểm tra" = [string]$signature.Path
                "Phiên bản tệp" = [string]$signature.FileVersion
                "Có trình gỡ" = if ($hasUninstaller) { Select-ReportText -Vietnamese "Có" -English "Yes" } else { Select-ReportText -Vietnamese "Không" -English "No" }
                "Metadata cập nhật" = if ($hasUpdateMetadata) { Select-ReportText -Vietnamese "Có" -English "Yes" } else { Select-ReportText -Vietnamese "Không" -English "No" }
                "Lệnh gỡ" = [string]$item.UninstallString
                "Khóa đăng ký" = $registryKey
                IsMicrosoft = [bool]$isMicrosoft
                SignatureStatus = [string]$signature.Status
            }
        }
    }
    $apps = @($apps |
        Group-Object { "$($_.'Ten phan mem')|$($_.'Phien ban')|$($_.'Phạm vi')|$($_.'Kiến trúc')" } |
        ForEach-Object { $_.Group | Select-Object -First 1 } |
        Sort-Object "Ten phan mem", "Phien ban", "Phạm vi")

    # Hợp đồng hiển thị Mục 5 của v4.3.0.3 được giữ nguyên. Dữ liệu giàu hơn
    # vẫn được thu thập trong $apps nhưng bốn cột truyền thống là nguồn cho
    # các bảng cũ và việc dò dấu hiệu cũ.
    $legacyApps = @($apps |
        Select-Object "Ten phan mem", "Phien ban", "Hang", "Ngay cai" |
        Sort-Object "Ten phan mem", "Phien ban" -Unique)

    $strongCrackPattern = "(?i)(\bkmspico\b|\bkmsauto\b|\bauto[\s._-]*kms\b|\bautokms\b|\bkms[_-]?vl(?:_all)?\b|\bkms-r\b|\baact(?:portable)?\b|\bsppextcomobj(?:patcher|hook)\b|\bmicrosoft toolkit\b|\bhwidgen\b|\bmassgrave\b|\bget\.activated\.win\b|\bgenp\b|\bkeygen\b|\bcrack(?:ed)?\b|\bactivation[\s._-]*bypass\b)"
    $genericReviewPattern = "(?i)(\bactivator\b|\bactivation\b|\bpatch(?:er)?\b|\brepack\b|\bportable\b|\bbypass\b|\br2r\b|\bthuoc\b)"
    $legacySoftwareAudit = @($legacyApps | ForEach-Object {
        $name = $_."Ten phan mem"
        $publisher = $_."Hang"
        $status = "Can doi chieu hoa don/license"
        $reason = "Co thong tin cai dat, chua xac minh duoc ban quyen that neu khong doi chieu ho so."
        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $status = "Co dau hieu nghi khong chinh hang"
            $reason = "Ten phan mem/publisher khop mau activator dac hieu; van can xac minh chu ky va nguon cai dat."
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $status = "Tu khoa chung - can xac minh thu cong"
            $reason = "Tu khoa activation/patch/portable co the hop le; khong du de ket luan crack neu khong co bang chung khac."
        } elseif ([string]::IsNullOrWhiteSpace($publisher)) {
            $status = "Thieu thong tin nha phat hanh"
            $reason = "Can kiem tra nguon cai dat va hoa don/license."
        }
        [pscustomobject]@{
            "Ten phan mem" = $name
            "Phien ban" = $_."Phien ban"
            "Hang" = $publisher
            "Danh gia so bo" = $status
            "Ly do" = $reason
        }
    })

    $softwareAudit = @($apps | ForEach-Object {
        $app = $_
        $name = [string]$app."Ten phan mem"
        $publisher = [string]$app."Hang"
        $reviewRank = 0
        $reasons = New-Object System.Collections.ArrayList

        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $reviewRank = 2
            [void]$reasons.Add((Select-ReportText -Vietnamese "Tên hoặc nhà phát hành khớp mẫu activator/crack đặc hiệu." -English "The name or publisher matches a specific activator/crack pattern."))
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Có từ khóa chung như activation/patch/portable; cần xác minh, chưa đủ để kết luận." -English "A generic activation/patch/portable keyword requires verification and is not sufficient for a verdict."))
        }
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Thiếu thông tin nhà phát hành." -English "Publisher information is missing."))
        }
        if ([string]::IsNullOrWhiteSpace([string]$app."Phien ban")) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Thiếu thông tin phiên bản." -English "Version information is missing."))
        }
        if ([string]$app.SignatureStatus -in @("HashMismatch", "NotTrusted", "UnknownError")) {
            $reviewRank = 2
            [void]$reasons.Add((Select-ReportText -Vietnamese "Chữ ký tệp đại diện không hợp lệ hoặc không tin cậy." -English "The representative file signature is invalid or untrusted."))
        } elseif ([string]$app.SignatureStatus -eq "NotSigned") {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Tệp đại diện không có chữ ký số." -English "The representative file is unsigned."))
        }
        if ([string]$app."Duong dan" -match '(?i)\\(temp|downloads?)(\\|$)') {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Nguồn cài đặt nằm trong thư mục tạm hoặc tải xuống." -English "The installation source is under a temporary or downloads folder."))
        }
        if ([string]$app."Có trình gỡ" -in @("Không", "No")) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Select-ReportText -Vietnamese "Không có lệnh gỡ cài đặt được khai báo." -English "No uninstall command is registered."))
        }
        if ($reasons.Count -eq 0) {
            [void]$reasons.Add((Select-ReportText -Vietnamese "Không thấy chỉ báo kỹ thuật nổi bật; vẫn cần đối chiếu giấy phép hoặc hóa đơn khi áp dụng." -English "No prominent technical indicator was found; reconcile entitlement or purchase records where applicable."))
        }
        $reviewLevel = switch ($reviewRank) {
            2 { Select-ReportText -Vietnamese "Cao" -English "High" }
            1 { Select-ReportText -Vietnamese "Cần rà soát" -English "Review" }
            default { Select-ReportText -Vietnamese "Thông tin" -English "Information" }
        }
        [pscustomobject][ordered]@{
            "Ten phan mem" = $name
            "Phien ban" = [string]$app."Phien ban"
            "Hang" = $publisher
            "Phân loại" = [string]$app."Phân loại"
            "Mức rà soát" = $reviewLevel
            "Lý do rà soát" = ($reasons -join " ")
            "Chữ ký" = [string]$app."Chữ ký"
            "Duong dan" = [string]$app."Duong dan"
            ReviewRank = $reviewRank
        }
    })

    $thirdPartyApps = @($apps | Where-Object { -not [bool]$_.IsMicrosoft })
    $thirdPartyAudit = @($softwareAudit | Where-Object { $_."Phân loại" -in @("Bên thứ ba", "Third-party") })
    $thirdPartyReview = @($thirdPartyAudit | Where-Object { [int]$_.ReviewRank -gt 0 })
    $parallelVersions = @($thirdPartyApps |
        Group-Object "Ten phan mem" |
        Where-Object { @($_.Group."Phien ban" | Where-Object { $_ } | Select-Object -Unique).Count -gt 1 } |
        ForEach-Object {
            [pscustomobject][ordered]@{
                "Ten phan mem" = [string]$_.Name
                "Số lượng" = @($_.Group).Count
                "Phiên bản" = (@($_.Group."Phien ban" | Where-Object { $_ } | Select-Object -Unique) -join ", ")
                "Phạm vi" = (@($_.Group."Phạm vi" | Where-Object { $_ } | Select-Object -Unique) -join ", ")
            }
        })

    $softwareOverview = @(
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Tổng mục cài đặt" -English "Total installed entries"); "Gia tri"=@($apps).Count },
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Phần mềm bên thứ ba" -English "Third-party software"); "Gia tri"=@($thirdPartyApps).Count },
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Thành phần Microsoft / hệ điều hành" -English "Microsoft / operating-system components"); "Gia tri"=@($apps | Where-Object { [bool]$_.IsMicrosoft }).Count },
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Tệp đại diện có chữ ký hợp lệ" -English "Representative files with valid signatures"); "Gia tri"=@($apps | Where-Object { $_.SignatureStatus -eq "Valid" }).Count },
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Mục bên thứ ba cần rà soát" -English "Third-party entries requiring review"); "Gia tri"=@($thirdPartyReview).Count },
        [pscustomobject]@{ "Muc"=(Select-ReportText -Vietnamese "Nhóm cài song song nhiều phiên bản" -English "Parallel-version groups"); "Gia tri"=@($parallelVersions).Count }
    )

    Add-Section "Phan mem da cai" (Add-Table $legacyApps @("Ten phan mem","Phien ban","Hang","Ngay cai")) "Software"
    Add-Section "Danh gia so bo ban quyen phan mem" (Add-Table $legacySoftwareAudit @("Ten phan mem","Phien ban","Hang","Danh gia so bo","Ly do")) "Software"

    $startup = @(Safe-Cim Win32_StartupCommand | Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{
            "Ten" = [string]$_.Name
            "Lenh" = [string]$_.Command
            "Vi tri" = [string]$_.Location
            "Nguoi dung" = [string]$_.User
        }
    })
    Add-Section "Startup" (Add-Table $startup @("Ten","Lenh","Vi tri","Nguoi dung")) "Software"

    $thirdPartyAutoruns = @($startup | ForEach-Object {
        $startupFile = Get-ExecutablePathFromMetadata -Candidates @([string]$_.Lenh) -PreferredName ([string]$_.Ten)
        $startupSignature = Get-CachedSoftwareSignatureState -Path $startupFile
        $isWindowsPath = -not [string]::IsNullOrWhiteSpace($startupFile) -and
            $startupFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase)
        $isMicrosoftSignature = Test-MicrosoftSoftwarePublisher -Publisher ([string]$startupSignature.Publisher)
        if (-not $isWindowsPath -and -not $isMicrosoftSignature) {
            [pscustomobject][ordered]@{
                "Ten" = [string]$_.Ten
                "Lenh" = [string]$_.Lenh
                "Vi tri" = [string]$_."Vi tri"
                "Nguoi dung" = [string]$_."Nguoi dung"
                "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$startupSignature.Status)
                "Tệp kiểm tra" = [string]$startupFile
            }
        }
    })

    $serviceInventory = @(Safe-Cim Win32_Service | Sort-Object State, Name | ForEach-Object {
        [pscustomobject][ordered]@{
            "Ten" = [string]$_.Name
            "Hien thi" = [string]$_.DisplayName
            "Trang thai" = [string]$_.State
            "Loai khoi dong" = [string]$_.StartMode
            "Duong dan" = [string]$_.PathName
        }
    })
    $thirdPartyServices = @($serviceInventory | ForEach-Object {
        $serviceFile = Get-ExecutablePathFromMetadata -Candidates @([string]$_."Duong dan") -PreferredName ([string]$_.Ten)
        $serviceSignature = Get-CachedSoftwareSignatureState -Path $serviceFile
        $isWindowsPath = -not [string]::IsNullOrWhiteSpace($serviceFile) -and
            $serviceFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase)
        $isMicrosoftSignature = Test-MicrosoftSoftwarePublisher -Publisher ([string]$serviceSignature.Publisher)
        if (-not $isWindowsPath -and -not $isMicrosoftSignature) {
            [pscustomobject][ordered]@{
                "Ten" = [string]$_.Ten
                "Hien thi" = [string]$_."Hien thi"
                "Trang thai" = [string]$_."Trang thai"
                "Loai khoi dong" = [string]$_."Loai khoi dong"
                "Duong dan" = [string]$_."Duong dan"
                "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$serviceSignature.Status)
                "Tệp kiểm tra" = [string]$serviceFile
            }
        }
    })
    $services = @(Get-Service | Sort-Object Status, Name | ForEach-Object {
        [pscustomobject]@{
            "Ten" = $_.Name
            "Hien thi" = $_.DisplayName
            "Trang thai" = $_.Status
            "Loai khoi dong" = $_.StartType
        }
    })
    Add-Section "Dich vu Windows" (Add-Table $services @("Ten","Hien thi","Trang thai","Loai khoi dong")) "Software"

    $crackFindings = @()
    $manualReviewFindings = @()
    foreach ($app in $legacyApps) {
        $name = [string]$app."Ten phan mem"
        $publisher = [string]$app."Hang"
        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Installed software"
                "Dau hieu" = $name
                "Vi tri" = $publisher
                "Muc do" = "Can kiem tra ngay"
            }
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $manualReviewFindings += [pscustomobject]@{
                "Nguon" = "Installed software"
                "Dau hieu" = $name
                "Vi tri" = $publisher
                "Muc do" = "Tu khoa chung - khong du ket luan"
            }
        }
    }
    foreach ($item in $startup) {
        if (($item.Ten -match $strongCrackPattern) -or ($item.Lenh -match $strongCrackPattern) -or ($item."Vi tri" -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Startup"
                "Dau hieu" = $item.Ten
                "Vi tri" = $item.Lenh
                "Muc do" = "Can kiem tra"
            }
        }
    }
    foreach ($svc in $services) {
        if (($svc.Ten -match $strongCrackPattern) -or ($svc."Hien thi" -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Service"
                "Dau hieu" = $svc.Ten
                "Vi tri" = $svc."Hien thi"
                "Muc do" = "Can kiem tra"
            }
        }
    }
    try {
        $taskFindings = Get-ScheduledTask | Where-Object {
            ($_.TaskName -match $strongCrackPattern) -or ($_.TaskPath -match $strongCrackPattern) -or ($_.Author -match $strongCrackPattern)
        } | Select-Object -First 80
        foreach ($task in $taskFindings) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Scheduled task"
                "Dau hieu" = $task.TaskName
                "Vi tri" = $task.TaskPath
                "Muc do" = "Can kiem tra"
            }
        }
    } catch {}
    $scanRoots = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyDocuments"),
        "$env:USERPROFILE\Downloads",
        "$env:ProgramData"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($root in $scanRoots) {
        try {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $strongCrackPattern -or $_.FullName -match $strongCrackPattern } |
                Select-Object -First 60 |
                ForEach-Object {
                    $crackFindings += [pscustomobject]@{
                        "Nguon" = "File scan"
                        "Dau hieu" = $_.Name
                        "Vi tri" = $_.FullName
                        "Muc do" = "Dau hieu theo ten file"
                    }
                }
        } catch {}
    }
    Add-Section "Dau hieu crack / activator / KMS" (Add-Table $crackFindings @("Nguon","Dau hieu","Vi tri","Muc do")) "Software"
    Add-Section "Tu khoa chung can xac minh thu cong (khong ket luan crack)" (Add-Table $manualReviewFindings @("Nguon","Dau hieu","Vi tri","Muc do")) "Software"
}

if ($wantHardware) {
$securityRows = @()
try {
    $av = Safe-Cim AntivirusProduct root/SecurityCenter2
    foreach ($item in $av) {
        $securityRows += [pscustomobject]@{
            "Loai"="Antivirus"
            "Ten"=$item.displayName
            "Trang thai"=$item.productState
            "Duong dan"=$item.pathToSignedProductExe
        }
    }
} catch {}
try {
    $fwProfiles = Get-NetFirewallProfile
    foreach ($profile in $fwProfiles) {
        $securityRows += [pscustomobject]@{
            "Loai"="Firewall"
            "Ten"=$profile.Name
            "Trang thai"=$profile.Enabled
            "Duong dan"=""
        }
    }
} catch {}
Add-Section "Bao mat" (Add-Table $securityRows @("Loai","Ten","Trang thai","Duong dan"))

$users = @()
try {
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $users = Get-LocalUser | ForEach-Object {
            [pscustomobject]@{
                "User"=$_.Name
                "Enabled"=$_.Enabled
                "LastLogon"=$_.LastLogon
                "PasswordRequired"=$_.PasswordRequired
            }
        }
    } else {
        $users = Safe-Cim Win32_UserAccount | Where-Object { $_.LocalAccount } | ForEach-Object {
            [pscustomobject]@{
                "User"=$_.Name
                "Enabled"=(-not $_.Disabled)
                "LastLogon"="Khong co thong tin"
                "PasswordRequired"="Khong co thong tin"
            }
        }
    }
} catch {}
Add-Section "Local users" (Add-Table $users @("User","Enabled","LastLogon","PasswordRequired"))

$printers = @()
try {
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
        $printers = Get-Printer | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Driver"=$_.DriverName
                "Port"=$_.PortName
                "Default"=$_.Default
            }
        }
    } else {
        $printers = Safe-Cim Win32_Printer | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Driver"=$_.DriverName
                "Port"=$_.PortName
                "Default"=$_.Default
            }
        }
    }
} catch {}
Add-Section "May in" (Add-Table $printers @("Ten","Driver","Port","Default"))

$usb = Safe-Cim Win32_PnPEntity | Where-Object {
    $_.PNPClass -in @("USB","DiskDrive","Image","Camera","Bluetooth")
} | Sort-Object PNPClass, Name | ForEach-Object {
    [pscustomobject]@{
        "Loai"=$_.PNPClass
        "Ten"=$_.Name
        "Manufacturer"=$_.Manufacturer
        "Trang thai"=$_.Status
    }
}
Add-Section "Thiet bi USB / ngoai vi" (Add-Table $usb @("Loai","Ten","Manufacturer","Trang thai"))

$shares = Safe-Cim Win32_Share | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "Duong dan"=$_.Path
        "Loai"=$_.Type
        "Mo ta"=$_.Description
    }
}
Add-Section "Thu muc chia se" (Add-Table $shares @("Ten","Duong dan","Loai","Mo ta"))
}

if ($wantSoftware) {
$tasks = @()
$thirdPartyTasks = @()
if ($capabilityState.ScheduledTasksModule) {
    $scheduledTaskObjects = @(Get-ScheduledTask | Where-Object { $_.State -ne "Disabled" } | Select-Object -First 120)
    $tasks = $scheduledTaskObjects | ForEach-Object {
        [pscustomobject]@{
            "Task"=$_.TaskName
            "Path"=$_.TaskPath
            "State"=$_.State
            "Author"=$_.Author
        }
    }
    $thirdPartyTasks = @($scheduledTaskObjects | ForEach-Object {
        $taskObject = $_
        $actionText = @($taskObject.Actions | ForEach-Object {
            @([string]$_.Execute, [string]$_.Arguments) -join " "
        }) -join "; "
        $taskFile = Get-ExecutablePathFromMetadata -Candidates @($actionText) -PreferredName ([string]$taskObject.TaskName)
        $taskSignature = Get-CachedSoftwareSignatureState -Path $taskFile
        $isMicrosoftTask = ([string]$taskObject.TaskPath -like "\Microsoft\*") -or
            ([string]$taskObject.Author -match '(?i)\bMicrosoft\b') -or
            (Test-MicrosoftSoftwarePublisher -Publisher ([string]$taskSignature.Publisher)) -or
            (-not [string]::IsNullOrWhiteSpace($taskFile) -and
                $taskFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase))
        if (-not $isMicrosoftTask) {
            [pscustomobject][ordered]@{
                "Task" = [string]$taskObject.TaskName
                "Path" = [string]$taskObject.TaskPath
                "State" = [string]$taskObject.State
                "Author" = [string]$taskObject.Author
                "Hành động" = $actionText.Trim()
                "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$taskSignature.Status)
                "Tệp kiểm tra" = [string]$taskFile
            }
        }
    })
} elseif ($capabilityState.ScheduledTasksFallback) {
    $tasks = @([pscustomobject]@{
        "Task"="ScheduledTasks module không có"
        "Path"="schtasks.exe fallback khả dụng"
        "State"="Dùng trong quét chuyên sâu/cleanup"
        "Author"="Windows compatibility"
    })
} else {
    $tasks = @([pscustomobject]@{
        "Task"="Không đọc được Scheduled Tasks"
        "Path"=""
        "State"="Không hỗ trợ"
        "Author"=""
    })
}
Add-Section "Scheduled tasks dang bat" (Add-Table $tasks @("Task","Path","State","Author")) "Software"
}

# Plugin v4.3 chỉ dùng JSON khai báo và các nguồn đọc đã giới hạn. Không dot-source
# hoặc thực thi mã do plugin cung cấp.
$pluginAudit = $null
if ($wantSoftware) {
    try {
        $pluginAudit = Invoke-ToolPluginAudit
        $pluginRows = @($pluginAudit.Plugins | ForEach-Object {
            [pscustomobject]@{
                "Plugin"=$_.Name
                "Phiên bản"=$_.Version
                "Nhà phát hành"=$_.Publisher
                "Bật"=$_.Enabled
                "Quy tắc"=$_.RuleCount
                "Tin cậy"=$_.Trust
            }
        })
        $pluginFindingRows = @($pluginAudit.Findings | ForEach-Object {
            [pscustomobject]@{
                "Mức"=$_.Severity
                "Plugin"=$_.PluginName
                "Quy tắc"=$_.RuleId
                "Quan sát"=$_.Observed
                "Nhận định"=$_.Message
                "Hướng xử lý"=$_.Remediation
                "Lỗi"=$_.Error
            }
        })
        $pluginBody = (Add-Table $pluginRows @("Plugin","Phiên bản","Nhà phát hành","Bật","Quy tắc","Tin cậy"))
        $pluginBody += "<h3>$(Html (Select-ReportText "Phát hiện của plugin" "Plugin findings"))</h3>"
        $pluginBody += (Add-Table $pluginFindingRows @("Mức","Plugin","Quy tắc","Quan sát","Nhận định","Hướng xử lý","Lỗi"))
        $pluginBody += "<p class='note'>$(Html (Select-ReportText "Plugin v4.3 là JSON chỉ đọc; engine không chạy script, command hoặc tải mạng từ plugin." "v4.3 plugins are read-only JSON declarations; the engine does not run scripts, commands, or network downloads from a plugin."))</p>"
        Add-Section "Quy tắc mở rộng bằng plugin" $pluginBody "Software"
    } catch {
        $pluginAudit = [pscustomobject]@{
            PluginCount=0; EnabledPluginCount=0; InvalidPluginCount=0; EvaluatedRuleCount=0
            TriggeredFindingCount=0; HighOrCriticalCount=0; Plugins=@(); Findings=@(); InvalidPlugins=@()
            Error=$_.Exception.Message
        }
        $pluginLockedLabel = Select-ReportText "Plugin bị khóa an toàn" "Plugin was safely blocked"
        Add-Section "Quy tắc mở rộng bằng plugin" "<p class='license-warning'>$(Html $pluginLockedLabel): $(Html $_.Exception.Message)</p>" "Software"
    }
}

# Phần nâng cao chỉ được nối thêm sau toàn bộ bảng Mục 5 của v4.3.0.3.
# Không đổi tên, thứ tự hoặc số cột của các bảng cũ ở phía trên.
if ($wantSoftware) {
    $supplementNote = Select-ReportText `
        "Phần này bổ sung dữ liệu kỹ thuật; giao diện và các bảng Mục 5 truyền thống phía trên vẫn giữ nguyên như v4.3.0.3. Kết quả là chỉ báo cần xác minh, không tự kết luận vi phạm bản quyền." `
        "This section adds technical data; the traditional Function 5 interface and tables above remain compatible with v4.3.0.3. Findings require verification and are not an automatic licensing verdict."
    $supplementBody = "<p class='note'>$(Html $supplementNote)</p>"
    $supplementBody += "<h3>$(Html (Select-ReportText 'Tổng quan phần mềm bên thứ ba' 'Third-party software overview'))</h3>"
    $supplementBody += (Add-Table $softwareOverview @("Muc","Gia tri"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Danh sách phần mềm bên thứ ba' 'Third-party software inventory'))</h3>"
    $supplementBody += (Add-Table $thirdPartyApps @("Ten phan mem","Phien ban","Hang","Ngay cai","Phạm vi","Kiến trúc","Duong dan"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Chữ ký và nguồn cài đặt' 'Signatures and installation sources'))</h3>"
    $supplementBody += (Add-Table $thirdPartyApps @("Ten phan mem","Chữ ký","Nhà phát hành chữ ký","Tệp kiểm tra","Phiên bản tệp","Có trình gỡ","Metadata cập nhật"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Phần mềm cần rà soát' 'Software requiring review'))</h3>"
    $supplementBody += (Add-Table $thirdPartyReview @("Ten phan mem","Phien ban","Hang","Mức rà soát","Lý do rà soát","Chữ ký","Duong dan"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Phiên bản cài song song' 'Parallel installed versions'))</h3>"
    $supplementBody += (Add-Table $parallelVersions @("Ten phan mem","Số lượng","Phiên bản","Phạm vi"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Tự khởi động của bên thứ ba' 'Third-party autoruns'))</h3>"
    $supplementBody += (Add-Table $thirdPartyAutoruns @("Ten","Lenh","Vi tri","Nguoi dung","Chữ ký","Tệp kiểm tra"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Dịch vụ bên thứ ba' 'Third-party services'))</h3>"
    $supplementBody += (Add-Table $thirdPartyServices @("Ten","Hien thi","Trang thai","Loai khoi dong","Duong dan","Chữ ký","Tệp kiểm tra"))
    $supplementBody += "<h3>$(Html (Select-ReportText 'Tác vụ bên thứ ba đang bật' 'Enabled third-party scheduled tasks'))</h3>"
    $supplementBody += (Add-Table $thirdPartyTasks @("Task","Path","State","Author","Hành động","Chữ ký","Tệp kiểm tra"))
    Add-Section "Kiểm tra bổ sung phần mềm bên thứ ba" $supplementBody "Software"
}

# Phần kết luận luôn hiển thị để người quản trị có hướng xử lý rõ ràng.
$assessmentRows = @()
if ($wantWindows) {
    $windowsDirection = if ($windowsSummaryChannel -match "KMS") {
        Select-ReportText `
            "Đối chiếu máy chủ KMS và hồ sơ cấp phép; nếu không được phê duyệt, dùng mục gỡ KMS/crack sau khi sao lưu." `
            "Reconcile the KMS server and licensing records; if they are not approved, use the KMS/crack removal module after creating a backup."
    } elseif ($windowsSummaryStatus -match "Đã kích hoạt") {
        Select-ReportText `
            "Giữ nguyên, nhưng cần đối chiếu hóa đơn, tài khoản hoặc giấy phép với hồ sơ nội bộ." `
            "Keep the current state, but reconcile invoices, licensed accounts, or entitlements with internal records."
    } else {
        Select-ReportText `
            "Cấp giấy phép Windows hợp lệ rồi kích hoạt lại; không dùng activator không rõ nguồn." `
            "Assign a valid Windows license and activate again; do not use an activator from an unknown source."
    }
    $assessmentRows += [pscustomobject]@{ "Đối tượng"="Windows"; "Đánh giá"=(Get-ReportPresentationText $windowsSummaryStatus); "Phương hướng xử lý"=$windowsDirection }
}
if ($wantOffice) {
    $officeDirection = if ($officeSummaryStatus -match "Đã kích hoạt") {
        Select-ReportText `
            "Đối chiếu tài khoản Microsoft 365, Retail/Volume hoặc hồ sơ mua bản quyền." `
            "Reconcile the Microsoft 365 account, Retail/Volume channel, or purchase records."
    } elseif ($officeDetected) {
        Select-ReportText `
            "Kiểm tra kênh cấp phép; gỡ KMS/crack nếu không hợp lệ và cài lại Office chính hãng khi cần." `
            "Inspect the licensing channel; remove unauthorized KMS/crack components and reinstall genuine Office when required."
    } else {
        Select-ReportText `
            "Không phát hiện Office; kiểm tra lại nếu máy cần sử dụng bộ Office." `
            "Microsoft Office was not detected; inspect again if this device is expected to use Office."
    }
    $assessmentRows += [pscustomobject]@{ "Đối tượng"="Microsoft Office"; "Đánh giá"=(Get-ReportPresentationText $officeSummaryStatus); "Phương hướng xử lý"=$officeDirection }
}
if ($wantSoftware) {
    $softwareDirection = if (@($crackFindings).Count -gt 0) {
        Select-ReportText `
            "Cô lập và gỡ phần mềm/tác vụ đáng ngờ, kiểm tra lại nguồn cài đặt và giấy phép." `
            "Isolate and remove suspicious software or tasks, then verify installation sources and licensing."
    } elseif (@($manualReviewFindings).Count -gt 0) {
        Select-ReportText `
            "Có tên chứa từ khóa chung; xác minh chữ ký, nhà phát hành và nguồn cài đặt trước khi kết luận." `
            "Generic keywords were found; verify signatures, publishers, and installation sources before reaching a conclusion."
    } else {
        Select-ReportText `
            "Chưa thấy dấu hiệu theo tên; vẫn cần đối chiếu hóa đơn và nguồn cài đặt." `
            "No name-based indicator was found; purchase records and installation sources still require reconciliation."
    }
    $softwareAssessment = if (@($crackFindings).Count -gt 0) {
        Select-ReportText "Có dấu hiệu đặc hiệu cần kiểm tra" "Specific indicators require inspection"
    } elseif (@($manualReviewFindings).Count -gt 0) {
        Select-ReportText "Có từ khóa chung, chưa đủ kết luận" "Generic keywords were found; there is insufficient evidence for a verdict"
    } else {
        Select-ReportText "Chưa thấy dấu hiệu theo mẫu đặc hiệu" "No specific pattern-based indicator was found"
    }
    $softwareTarget = Select-ReportText "Phần mềm" "Software"
    $assessmentRows += [pscustomobject]@{ "Đối tượng"=$softwareTarget; "Đánh giá"=$softwareAssessment; "Phương hướng xử lý"=$softwareDirection }
}
if ($assessmentRows.Count -gt 0) {
    $sectionCounter++
    $assessmentId = "section-$sectionCounter"
    $assessmentTitle = Select-ReportText "Đánh giá và phương hướng xử lý" "Assessment and recommended handling"
    $assessmentNote = Select-ReportText `
        "Đây là đánh giá kỹ thuật tự động, không thay thế việc xác minh hóa đơn, hợp đồng hoặc tài khoản cấp phép." `
        "This automated technical assessment does not replace verification of invoices, agreements, or licensed accounts."
    $tocItems += [pscustomobject]@{ Id=$assessmentId; Title=$assessmentTitle }
    $sections += "<section id='$assessmentId'><h2>$(Html $assessmentTitle)</h2>$(Add-Table $assessmentRows @("Đối tượng","Đánh giá","Phương hướng xử lý"))<p class='note'>$(Html $assessmentNote)</p></section>"
}

$professionalCss = Get-ToolProfessionalReportCss
$tocLinks = @($tocItems | ForEach-Object { "<li><a href='#$(Html $_.Id)'>$(Html $_.Title)</a></li>" }) -join ""
$tocLabel = Get-ToolText -Key "report.toc" -Culture $Culture
$tocBlock = if ($tocItems.Count -gt 1) { "<nav class='toc'><strong>$(Html $tocLabel)</strong><ol>$tocLinks</ol></nav>" } else { "" }
$notScannedLabel = Get-ToolText -Key "report.notScanned" -Culture $Culture
$windowsCardValue = if ($wantWindows) { [string]$windowsSummaryStatus } else { $notScannedLabel }
$officeCardValue = if ($wantOffice) { [string]$officeSummaryStatus } else { $notScannedLabel }
$pluginHighCount = if ($pluginAudit) { [int]$pluginAudit.HighOrCriticalCount } else { 0 }
$windowsTone = if ($windowsCardValue -match "Đã kích hoạt|Đã cấp phép") { "ok" } elseif ($wantWindows) { "warning" } else { "info" }
$officeTone = if ($officeCardValue -match "Đã kích hoạt|Đã cấp phép") { "ok" } elseif ($wantOffice) { "warning" } else { "info" }
$findingTone = if (@($crackFindings).Count -gt 0) { "danger" } else { "ok" }
$pluginTone = if ($pluginHighCount -gt 0) { "danger" } elseif ($pluginAudit -and $pluginAudit.TriggeredFindingCount -gt 0) { "warning" } else { "ok" }
$htmlLanguage = if ($Culture -eq "en-US") { "en" } else { "vi" }
$offlineCardValue = Get-ToolText -Key $(if ($script:reportOfflineMode) { "report.offlineYes" } else { "report.offlineNo" }) -Culture $Culture
$offlineTone = if ($script:reportOfflineMode) { "ok" } else { "warning" }
$thirdPartyCount = if ($wantSoftware) { [int]@($thirdPartyApps).Count } else { 0 }
$thirdPartyReviewCount = if ($wantSoftware) { [int]@($thirdPartyReview).Count } else { 0 }
$thirdPartyHighCount = if ($wantSoftware) { [int]@($thirdPartyReview | Where-Object { [int]$_.ReviewRank -ge 2 }).Count } else { 0 }
$summaryCardsHtml = New-Object Text.StringBuilder
[void]$summaryCardsHtml.Append("<div class='card tone-$windowsTone'><div class='card-label'>Windows</div><div class='card-value'>$(Html $windowsCardValue)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$officeTone'><div class='card-label'>Microsoft Office</div><div class='card-value'>$(Html $officeCardValue)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$findingTone'><div class='card-label'>$(Html (Get-ToolText -Key 'report.specificFindings' -Culture $Culture))</div><div class='card-value'>$(@($crackFindings).Count)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$pluginTone'><div class='card-label'>Plugin High/Critical</div><div class='card-value'>$pluginHighCount</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$offlineTone'><div class='card-label'>$(Html (Get-ToolText -Key 'report.offline' -Culture $Culture))</div><div class='card-value'>$(Html $offlineCardValue)</div></div>")
$reportModeLabel = if ($Mode -eq "Software") {
    if ($script:reportOfflineMode) { "OFFLINE" } else { "NETWORK ALLOWED" }
} elseif ($script:reportOfflineMode) {
    Select-ReportText "NGOẠI TUYẾN" "OFFLINE"
} else {
    Select-ReportText "CHO PHÉP MẠNG" "NETWORK ALLOWED"
}
$html = @"
<!doctype html>
<html lang="$htmlLanguage">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
<title>$(Html $reportTitle) - $(Html $reportComputer)</title>
<style>$professionalCss</style>
</head>
<body>
<main class="page">
<header class="hero">
<div class="report-mode">$(Html $reportModeLabel)</div>
<div class="eyebrow">$(Html (Get-ToolText -Key "report.eyebrow" -Culture $Culture))</div>
<h1>$(Html $reportTitle)</h1>
<div class="subtitle">$(Html $ToolDescription)</div>
<div class="meta-grid">
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.machine" -Culture $Culture))</b>$(Html $reportComputer)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.time" -Culture $Culture))</b>$(Html $started.ToString("yyyy-MM-dd HH:mm:ss"))</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.mode" -Culture $Culture))</b>$(Html $Mode)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.version" -Culture $Culture))</b>$(Html $ToolReleaseVersion) / Report $(Html $reportSchemaState.SchemaVersion)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.privacy" -Culture $Culture))</b>$(Html (Get-ToolText -Key $(if ($RedactSensitive) { "report.redacted" } else { "report.internal" }) -Culture $Culture))</div>
</div>
</header>
<div class="cards">
$($summaryCardsHtml.ToString())
</div>
$tocBlock
<section><h2>$(Html (Get-ToolText -Key "report.scope" -Culture $Culture))</h2><p>$(Html $ToolDescription)</p><p class="note">$(Html $DeveloperCredit)</p></section>
$($sections -join "`n")
<div class="footer">$(Html $ToolName) &mdash; $(Html $DeveloperCredit)</div>
</main>
</body>
</html>
"@

$timelineSnapshot = [pscustomobject][ordered]@{ Written=$false; Changed=$false; Changes=@(); Sequence=0; Error=[string]$timelineState.Error }
if ($timelineState.Enabled) {
    try {
        if ($Mode -eq "All") {
            $timelineSnapshot = Save-ToolLicenseSnapshot -Source $reportModuleId -State ([pscustomobject][ordered]@{
                WindowsStatus = [string]$windowsSummaryStatus
                WindowsChannel = [string]$windowsSummaryChannel
                OfficeStatus = [string]$officeSummaryStatus
                OfficeDetected = [bool]$officeDetected
                SuspiciousFindingCount = [int]@($crackFindings).Count
                PluginHighOrCriticalCount = $pluginHighCount
            })
        } else {
            $timelineWrite = Write-ToolLicenseTimelineEvent -EventType "ReportGenerated" -Source $reportModuleId -Data ([ordered]@{
                Mode=$Mode; SuspiciousFindingCount=[int]@($crackFindings).Count; PluginHighOrCriticalCount=$pluginHighCount
            })
            $timelineSnapshot = [pscustomobject][ordered]@{
                Written=[bool]$timelineWrite.Written; Changed=$false; Changes=@(); Sequence=[int]$timelineWrite.Sequence; Error=[string]$timelineWrite.Error
            }
        }
    } catch {
        $timelineSnapshot = [pscustomobject][ordered]@{
            Written=$false; Changed=$false; Changes=@(); Sequence=0; Error="Timeline từ chối ghi: $($_.Exception.Message)"
        }
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $timelineSnapshot.Error)
    }
}
$moduleOutputPaths = @(
    (Protect-ReportText $reportPath),
    (Protect-ReportText $jsonPath),
    (Protect-ReportText $xmlPath),
    (Protect-ReportText $manifestPath)
)
$moduleWarningCount = [int]@($manualReviewFindings).Count
$moduleSummaryText = Select-ReportText "Đã tạo báo cáo $Mode." "Created the $Mode report."
$moduleResult = Complete-ToolModuleInvocation -Invocation $moduleInvocation -ExitCode 0 -Summary $moduleSummaryText -OutputPaths $moduleOutputPaths -FindingCount ([int]@($crackFindings).Count) -WarningCount $moduleWarningCount
$moduleValidation = Test-ToolModuleResult -Result $moduleResult
if (-not $moduleValidation.Valid) { throw "ModuleResult báo cáo không hợp lệ: $($moduleValidation.Errors -join '; ')" }
$pluginAuditForExport = ConvertTo-ReportRedactedObject $pluginAudit
$timelineSnapshotForExport = ConvertTo-ReportRedactedObject $timelineSnapshot
$detailedInventory = [ordered]@{
    RenderedSectionCount = [int]$sectionCounter
    Assessment = @($assessmentRows)
}
if ($wantSoftware) {
    $detailedInventory.Software = [ordered]@{
        LegacyInstalledApplications = @($legacyApps)
        LegacyPreliminaryAssessment = @($legacySoftwareAudit)
        InstalledApplications = @($apps)
        ThirdPartyApplications = @($thirdPartyApps)
        ThirdPartyAssessment = @($thirdPartyAudit)
        ThirdPartyReviewItems = @($thirdPartyReview)
        ParallelVersions = @($parallelVersions)
        StartupEntries = @($startup)
        ThirdPartyAutoruns = @($thirdPartyAutoruns)
        Services = @($serviceInventory)
        ThirdPartyServices = @($thirdPartyServices)
        EnabledScheduledTasks = @($tasks)
        ThirdPartyScheduledTasks = @($thirdPartyTasks)
        SpecificFindings = @($crackFindings)
        ManualReviewFindings = @($manualReviewFindings)
    }
}
$detailedInventoryForExport = ConvertTo-ReportRedactedObject $detailedInventory
$summary = New-ToolReportEnvelope -ReportKind "InventoryAndLicense" -ToolVersion $ToolVersion -Data ([ordered]@{
    ToolName = $ToolName
    Capabilities = $capabilityState
    Compatibility = $compatibilityState
    Localization = $localizationState
    OfflinePolicy = $offlinePolicyState
    ModuleContract = $moduleContractState
    ModuleResult = $moduleResult
    ComputerName = $reportComputer
    CreatedAt = $started.ToString("o")
    Mode = $Mode
    Culture = $Culture
    OfflineMode = [bool]$script:reportOfflineMode
    HtmlReport = Protect-ReportText $reportPath
    PdfReport = ""
    WindowsStatus = [string]$windowsSummaryStatus
    WindowsChannel = [string]$windowsSummaryChannel
    OfficeStatus = [string]$officeSummaryStatus
    OfficeDetected = [bool]$officeDetected
    SuspiciousFindingCount = [int]@($crackFindings).Count
    ManualReviewFindingCount = [int]@($manualReviewFindings).Count
    ThirdPartyApplicationCount = $thirdPartyCount
    ThirdPartyReviewCount = $thirdPartyReviewCount
    ThirdPartyHighSeverityCount = $thirdPartyHighCount
    PluginAudit = $pluginAuditForExport
    Timeline = $timelineSnapshotForExport
    DetailedInventory = $detailedInventoryForExport
    Redacted = [bool]$RedactSensitive
    Privacy = if ($RedactSensitive) {
        Select-ReportText `
            "Đã che tên máy/người dùng, serial, IP, MAC và đường dẫn hồ sơ người dùng trong nội dung chia sẻ." `
            "Device/user names, serial numbers, IP/MAC addresses, and user-profile paths were redacted from the shareable content."
    } else {
        Select-ReportText `
            "Báo cáo đầy đủ dùng nội bộ; không lưu product key đầy đủ nhưng có thể chứa thông tin nhận dạng máy." `
            "Complete internal report; full product keys are not stored, but device-identifying information may be present."
    }
})
$summaryValidation = Test-ToolReportEnvelope -Report $summary -ExpectedReportKind "InventoryAndLicense" -ExpectedToolVersion $ToolVersion
if (-not $summaryValidation.Valid) { throw "Báo cáo JSON không đạt schema: $($summaryValidation.Errors -join '; ')" }
$package = Export-ToolReportPackage -Report $summary -HtmlContent $html -BasePath $reportBasePath -IncludePdf:$Pdf -RedactPaths:$RedactSensitive
Write-Host $DeveloperCredit
Write-Host "HTML: $($package.HtmlPath)"
if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host "PDF: $($package.PdfPath)" }
elseif ($Pdf) { Write-Host "PDF chưa tạo được: $($package.Pdf.Error)" }
Write-Host "JSON: $($package.JsonPath)"
Write-Host "XML: $($package.XmlPath)"
Write-Host "Manifest SHA-256: $($package.ManifestPath)"
[void](Write-ToolLog -Level "INFO" -Event "Report.Complete" -Message "Đã tạo báo cáo $Mode." -DurationMs ([long][Math]::Round(((Get-Date) - $started).TotalMilliseconds)) -Data ([ordered]@{
    ModuleId = $moduleResult.ModuleId
    InvocationId = $moduleResult.InvocationId
    ModuleStatus = $moduleResult.Status
    Mode = $Mode
    Culture = $Culture
    OfflineMode = [bool]$script:reportOfflineMode
    Redacted = [bool]$RedactSensitive
    SuspiciousFindingCount = [int]@($crackFindings).Count
    ManualReviewFindingCount = [int]@($manualReviewFindings).Count
}))
if (-not $NoOpen) {
    $selectPath = $package.HtmlPath
    Start-Process -FilePath $selectPath
}





