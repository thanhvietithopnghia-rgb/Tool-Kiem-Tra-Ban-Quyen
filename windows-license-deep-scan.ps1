param(
    [string]$OutputDir = [Environment]::GetFolderPath("Desktop"),
    [string]$ApprovedKmsServerFile = "",
    [string]$DecisionFile = "",
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "Cong cu can PowerShell 3.0 tro len."
    exit 10
}

$toolVersion = "4.4"
$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1." }
    if (-not (Test-Path -LiteralPath $reportSchemaHelper -PathType Leaf)) { throw "Thiếu Tool-ReportSchema.ps1." }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw "Thiếu Tool-ReportExport.ps1." }
    . $runtimeHelper
    . $reportSchemaHelper
    . $reportExportHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "SilentlyContinue"
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2")
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
        }
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
    } catch {
        try { return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop) }
        catch { return @() }
    }
}

function Get-CompatibleScheduledTaskRows {
    $firstError = ""
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            return @(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name=([string]$_.TaskPath + [string]$_.TaskName); Actions=[string]($_.Actions | Out-String) }
            })
        } catch { $firstError = $_.Exception.Message }
    }
    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw "schtasks không trả CSV hợp lệ." }
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($row in @($csvLines | ConvertFrom-Csv)) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $name = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if ($name) { [void]$rows.Add([pscustomobject]@{ Name=$name; Actions=($values -join " | ") }) }
        }
        if ($rows.Count -eq 0) { throw "Không phân tích được scheduled task." }
        return $rows.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        throw "Không thể quét Scheduled Tasks: $detail"
    }
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Administrator)) {
    if (-not [string]::IsNullOrWhiteSpace($DecisionFile)) {
        $parent = Split-Path -Parent $DecisionFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $accessDeniedDecision = New-ToolReportEnvelope -ReportKind "DeepScanDecision" -ToolVersion $toolVersion -Data ([ordered]@{
            AccessDenied = $true
            Overall = "Chưa chạy: cần quyền Administrator"
            HighCount = 0
            ReviewCount = 0
            ReportPath = ""
        })
        $accessDeniedDecision | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
    }
    Write-Host "Kiểm tra chuyên sâu cần được chạy bằng quyền Administrator để đọc đủ thành phần hệ thống."
    exit 20
}

function Protect-Text($Value) {
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if (-not $RedactSensitive) { return $text }
    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if ($profilePath) { $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME, $kmsServer) + @($approvedKmsServers)) {
        if ($secret) {
            $secretPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $secretPattern, "[ĐÃ CHE]", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$part(?:\.$part){3}(?![0-9.])", "[IP ĐÃ CHE]")
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', '[MAC ĐÃ CHE]')
    return $text
}

function Html {
    param($Value)
    $safeValue = Protect-Text $Value
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue)
    }
}

function Get-Channel {
    param($License)
    if (-not $License) { return "Không xác định" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return "Không xác định"
}

function New-Result {
    param([int]$Id, [string]$Name, [string]$Status, [string]$Evidence, [string]$Recommendation)
    return [pscustomobject]@{
        Id = $Id
        Name = $Name
        Status = $Status
        Evidence = $Evidence
        Recommendation = $Recommendation
    }
}

function Get-SignatureSummary {
    param([object[]]$Paths)
    $items = New-Object System.Collections.Generic.List[string]
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { return "Không hỗ trợ đọc chữ ký trên PowerShell này." }
    foreach ($path in @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            $signer = if ($signature.SignerCertificate.Subject) { $signature.SignerCertificate.Subject } else { "không có chứng thư" }
            $items.Add("$([IO.Path]::GetFileName($path)): $($signature.Status); $signer")
        } catch { $items.Add("$([IO.Path]::GetFileName($path)): không đọc được chữ ký") }
    }
    if ($items.Count -eq 0) { return "Không có đường dẫn tệp để kiểm tra chữ ký." }
    return ($items -join " | ")
}

function Mask-Key {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return "Không tìm thấy" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return "Đã phát hiện" }
    return "*****-*****-*****-*****-" + $compact.Substring($compact.Length - 5)
}

$approvedKmsServers = @()
if (Test-Path -LiteralPath $ApprovedKmsServerFile) {
    $approvedKmsServers = @(Get-Content -LiteralPath $ApprovedKmsServerFile | ForEach-Object {
        ($_ -replace "#.*$", "").Trim().ToLowerInvariant()
    } | Where-Object { $_ })
}

function Test-ApprovedKms {
    param([string]$Server)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    foreach ($approved in $approvedKmsServers) {
        $item = $approved
        if ($item -match "^([^:]+):\d+$") { $item = $matches[1] }
        if ($candidate -eq $item) { return $true }
    }
    return $false
}

function Test-LicenseHostsBlockLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.TrimStart().StartsWith("#")) { return $false }
    if ($Line -notmatch "(?i)^\s*(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+") { return $false }
    $licenseHostPattern = "(?i)(microsoft|windows|office|sls\.microsoft|activation\.sls|genuine|licensing).*(activation|validation|sls|genuine|licensing)|" +
        "(activation|validation|sls|genuine|licensing).*(microsoft|windows|office)"
    return [bool]($Line -match $licenseHostPattern)
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$started = Get-Date
$stamp = $started.ToString("yyyyMMdd_HHmmss")
$reportMachine = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
$reportPath = Join-Path $OutputDir "BaoCao_BanQuyenWindows_ChuyenSau_${reportMachine}_$stamp.html"
$pdfPath = [IO.Path]::ChangeExtension($reportPath, ".pdf")
$manifestPath = [IO.Path]::ChangeExtension($reportPath, $null) + "-SHA256SUMS.txt"
$results = New-Object System.Collections.Generic.List[object]

$currentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
$edition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { "Không xác định" }
$installDate = "Không xác định"
$os = Safe-Cim Win32_OperatingSystem | Select-Object -First 1
if ($os.InstallDate) { $installDate = [string]$os.InstallDate }

$service = Safe-Cim SoftwareLicensingService | Select-Object -First 1
$oemKey = if ($service) { [string]$service.OA3xOriginalProductKey } else { "" }
$oemMasked = Mask-Key $oemKey
$oemPresent = -not [string]::IsNullOrWhiteSpace($oemKey)

$licenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Windows"
}
$activeLicense = $licenses | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$licenseForAnalysis = if ($activeLicense) { $activeLicense } else { $licenses | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
$isActivated = [bool]$activeLicense
$channel = Get-Channel $licenseForAnalysis
$partialKey = if ($licenseForAnalysis.PartialProductKey) { [string]$licenseForAnalysis.PartialProductKey } else { "Không xác định" }
$kmsServer = if ($licenseForAnalysis.KeyManagementServiceMachine) { [string]$licenseForAnalysis.KeyManagementServiceMachine } else { "" }

$slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
$xprText = ""
if (Test-Path -LiteralPath $slmgr) {
    $xprText = (& $nativeCscriptPath //nologo $slmgr /xpr 2>$null) -join "`n"
}

# 1. KMS server/configuration
if ($channel -eq "KMS") {
    $knownPublicPattern = "(?i)^(127\.0\.0\.1|0\.0\.0\.0|localhost)$|massgrave|kms\.loli|kms\.msgang|kms\.digiboy|kms\.03k|kms\.tee"
    if ($kmsServer -match $knownPublicPattern) {
        $results.Add((New-Result 1 "KMS server / cấu hình KMS" "Phát hiện dấu hiệu mạnh" "KMS trỏ đến máy chủ công cộng/ảo: $kmsServer" "Gỡ cấu hình KMS sau khi xác nhận máy không có giấy phép KMS hợp lệ."))
    } elseif (Test-ApprovedKms $kmsServer) {
        $results.Add((New-Result 1 "KMS server / cấu hình KMS" "Không phát hiện bất thường" "Máy chủ KMS đã phê duyệt: $kmsServer" "Giữ nguyên và đối chiếu hồ sơ cấp phép doanh nghiệp."))
    } else {
        $shownServer = if ($kmsServer) { $kmsServer } else { "không đọc được tên máy chủ" }
        $results.Add((New-Result 1 "KMS server / cấu hình KMS" "Cần xác minh" "Windows dùng kênh KMS; $shownServer chưa nằm trong danh sách phê duyệt." "Xác minh với quản trị viên và thêm KMS hợp lệ vào approved-kms-servers.txt."))
    }
} else {
    $results.Add((New-Result 1 "KMS server / cấu hình KMS" "Không phát hiện bất thường" "Kênh hiện tại: $channel" "Tiếp tục đối chiếu hóa đơn hoặc hồ sơ cấp phép."))
}

# 2. Services/processes/history markers. History content is never copied to the report.
$activatorRegex = "(?i)(kmspico|kmsauto|autokms|aact|sppextcomobj(?:hook|patcher)|microsoft toolkit|hwidgen|massgrave|digital license activation)"
$serviceHits = @(Safe-Cim Win32_Service | Where-Object {
    $_.Name -match $activatorRegex -or $_.DisplayName -match $activatorRegex -or $_.PathName -match $activatorRegex
})
$processHits = @(Get-Process | Where-Object { $_.ProcessName -match $activatorRegex })
$runtimePaths = @($serviceHits | Select-Object -ExpandProperty PathName) + @($processHits | Select-Object -ExpandProperty Path)
$historyHitCount = 0
$historyPath = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
if (Test-Path -LiteralPath $historyPath) {
    $historyRegex = "(?i)(massgrave|get\.activated\.win|kmspico|kmsauto|hwidgen|irm\s+https?://.+\|\s*iex)"
    $historyHitCount = @((Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue) | Where-Object { $_ -match $historyRegex }).Count
}
$runtimeCount = $serviceHits.Count + $processHits.Count
if ($runtimeCount -gt 0) {
    $names = @($serviceHits | Select-Object -ExpandProperty Name) + @($processHits | Select-Object -ExpandProperty ProcessName)
    $signatureSummary = Get-SignatureSummary $runtimePaths
    $results.Add((New-Result 2 "Activator / MAS / HWID" "Phát hiện dấu hiệu mạnh" "Dịch vụ/tiến trình nghi vấn: $($names -join ', '). Lịch sử có $historyHitCount dòng khớp mẫu; nội dung không được lưu. Chữ ký tệp: $signatureSummary" "Kiểm tra chữ ký và nguồn tệp trước khi dùng mục gỡ KMS/crack."))
} elseif ($historyHitCount -gt 0) {
    $results.Add((New-Result 2 "Activator / MAS / HWID" "Không phát hiện bất thường" "Không thấy tiến trình/dịch vụ đang chạy; chỉ có lịch sử cũ $historyHitCount dòng khớp mẫu. Nội dung lịch sử không được lưu." "Không cần xử lý lịch sử lệnh; chỉ dùng để tham khảo nếu còn dấu hiệu đang hoạt động ở nhóm khác."))
} else {
    $results.Add((New-Result 2 "Activator / MAS / HWID" "Không phát hiện bất thường" "Không thấy dịch vụ, tiến trình hoặc dấu lịch sử theo các mẫu đặc hiệu." "Không cần xử lý tự động."))
}

# 3. KMS38/expiration pattern
if ($channel -eq "KMS" -and $xprText -match "2038") {
    $results.Add((New-Result 3 "KMS38 / thời hạn kích hoạt" "Phát hiện dấu hiệu mạnh" "Kênh KMS có thời hạn hiển thị năm 2038, không phù hợp chu kỳ KMS thông thường." "Xác minh và gỡ cấu hình kích hoạt không hợp lệ nếu không có hồ sơ hợp pháp."))
} else {
    $summaryXpr = ($xprText -replace "\s+", " ").Trim()
    if ($summaryXpr.Length -gt 180) { $summaryXpr = $summaryXpr.Substring(0,180) + "..." }
    $results.Add((New-Result 3 "KMS38 / thời hạn kích hoạt" "Không phát hiện bất thường" $summaryXpr "Trạng thái kích hoạt không tự chứng minh quyền sở hữu giấy phép."))
}

# 4. Generic key/digital-license logic: informational only, never treated as proof of piracy.
$genericLast5 = @("3V66T","T83GX","YKHCF","TXYCV","8HVX7","233PK","8XC4K","WFG99","6F4BT","YTDFH","2YT43","H8Q99","7CFBY","VCFB2","J8JXD","8HV2C","PDQGT","YY74H","2YV77","6Q84J")
if ($genericLast5 -contains $partialKey) {
    $oemText = if ($oemPresent) { "Có key OEM BIOS $oemMasked." } else { "Không tìm thấy key OEM BIOS." }
    $results.Add((New-Result 4 "Logic key / giấy phép số" "Cần xác minh" "Windows dùng key chung theo 5 ký tự cuối $partialKey. $oemText" "Key chung có thể đi cùng Digital License hợp lệ; đối chiếu tài khoản, hóa đơn hoặc lịch sử nâng cấp."))
} else {
    $results.Add((New-Result 4 "Logic key / giấy phép số" "Không phát hiện bất thường" "Kênh $channel; 5 ký tự cuối $partialKey; OEM BIOS: $oemMasked" "Đối chiếu hồ sơ mua hàng để kết luận pháp lý."))
}

# 5. Suspicious activator folders
$folderCandidates = @(
    (Join-Path $env:windir "KMS"),
    (Join-Path $env:windir "AutoKMS"),
    (Join-Path $env:ProgramData "KMSAutoS"),
    (Join-Path $env:SystemDrive "KMSpico"),
    (Join-Path $env:SystemDrive "AAct")
) | Where-Object { $_ }
$folderHits = @($folderCandidates | Where-Object { Test-Path -LiteralPath $_ })
if ($folderHits.Count -gt 0) {
    $results.Add((New-Result 5 "Thư mục công cụ kích hoạt" "Phát hiện dấu hiệu mạnh" ($folderHits -join "; ") "Kiểm tra nội dung và sao lưu trước khi xóa; báo cáo này không xóa thư mục."))
} else {
    $results.Add((New-Result 5 "Thư mục công cụ kích hoạt" "Không phát hiện bất thường" "Không thấy các thư mục activator phổ biến tại vị trí hệ thống." "Không cần xử lý tự động."))
}

# 6. Scheduled tasks
$taskHits = @()
$taskScanError = ""
try {
    $taskHits = @(Get-CompatibleScheduledTaskRows | Where-Object { $_.Name -match $activatorRegex -or $_.Actions -match $activatorRegex })
} catch { $taskScanError = $_.Exception.Message }
if ($taskScanError) {
    $results.Add((New-Result 6 "Tác vụ chạy ngầm" "Chưa xác minh" $taskScanError "Kiểm tra Task Scheduler/schtasks.exe rồi chạy lại; không kết luận sạch khi nguồn này chưa đọc được."))
} elseif ($taskHits.Count -gt 0) {
    $taskNames = @($taskHits | ForEach-Object { [string]$_.Name })
    $results.Add((New-Result 6 "Tác vụ chạy ngầm" "Phát hiện dấu hiệu mạnh" ($taskNames -join "; ") "Dùng mục gỡ KMS/crack để vô hiệu hóa sau khi xác nhận."))
} else {
    $results.Add((New-Result 6 "Tác vụ chạy ngầm" "Không phát hiện bất thường" "Không thấy scheduled task khớp mẫu activator." "Không cần xử lý tự động."))
}

# 7. Registry policy and hosts; report only, never overwrite either source.
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
$policy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
$policyNames = New-Object System.Collections.Generic.List[string]
if ($policy.KeyManagementServiceName) { $policyNames.Add("KeyManagementServiceName") }
if ($policy.KeyManagementServicePort) { $policyNames.Add("KeyManagementServicePort") }
if ([int]$policy.NoGenTicket -eq 1) { $policyNames.Add("NoGenTicket=1") }
$hostsPath = Get-ToolNativeSystemPath "drivers\etc\hosts"
$hostsHitCount = 0
if (Test-Path -LiteralPath $hostsPath) {
    $hostsHitCount = @((Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue) | Where-Object {
        Test-LicenseHostsBlockLine $_
    }).Count
}
if ($policyNames.Count -gt 0 -or $hostsHitCount -gt 0) {
    $evidence = "Registry: $(if ($policyNames.Count) { $policyNames -join ', ' } else { 'không thấy policy nghi vấn' }); hosts có $hostsHitCount dòng cần kiểm tra."
    $results.Add((New-Result 7 "Registry / file hosts" "Cần xác minh" $evidence "Xác minh chính sách doanh nghiệp. Không ghi đè hosts; chỉ sửa đúng dòng/key sau khi có xác nhận."))
} else {
    $results.Add((New-Result 7 "Registry / file hosts" "Không phát hiện bất thường" "Không thấy policy SPP hoặc dòng hosts theo mẫu chặn kích hoạt." "Không cần xử lý tự động."))
}

$highCount = @($results | Where-Object { $_.Status -eq "Phát hiện dấu hiệu mạnh" }).Count
$reviewCount = @($results | Where-Object { $_.Status -in @("Cần xác minh", "Chưa xác minh") }).Count
$overall = if ($highCount -gt 0) {
    "Phát hiện dấu hiệu kỹ thuật cần xử lý"
} elseif ($reviewCount -gt 0) {
    "Cần xác minh hồ sơ hoặc cấu hình"
} else {
    "Không phát hiện dấu hiệu kỹ thuật rõ"
}
$reviewItems = @($results | Where-Object { $_.Status -in @("Cần xác minh", "Chưa xác minh", "Phát hiện dấu hiệu mạnh") } | ForEach-Object {
    [pscustomobject]@{
        Name = [string]$_.Name
        Status = [string]$_.Status
        Evidence = [string]$_.Evidence
        Recommendation = [string]$_.Recommendation
    }
})
$handlingGuidance = New-Object System.Collections.Generic.List[string]
if ($highCount -gt 0) {
    $handlingGuidance.Add("Có dấu hiệu mạnh: chạy mục 6 để backup, chọn đúng từng mục KMS/activator/tồn dư và xử lý; sau đó khởi động lại và quét lại mục 6 + mục 9.")
}
if (@($results | Where-Object { $_.Name -eq "Registry / file hosts" -and $_.Evidence -match "NoGenTicket=1" }).Count -gt 0) {
    $handlingGuidance.Add("NoGenTicket=1 có thể cản giấy phép số. Nếu không phải chính sách doanh nghiệp, chạy mục 6, chọn mục policy SPP/NoGenTicket, xử lý rồi khởi động lại.")
}
if ($reviewCount -gt 0 -and $handlingGuidance.Count -eq 0) {
    $handlingGuidance.Add("Mở báo cáo chi tiết, xử lý từng mục Cần xác minh theo cột Khuyến nghị rồi chạy lại kiểm tra.")
}
if ($reviewCount -eq 0 -and $highCount -eq 0) {
    $handlingGuidance.Add("Không cần gỡ thêm theo mục 9; kích hoạt bằng giấy phép chính thức rồi lưu báo cáo hậu kiểm.")
}

$reportRows = @($results | ForEach-Object {
    [pscustomobject][ordered]@{
        "#" = [string]$_.Id
        "Nhóm kiểm tra" = [string]$_.Name
        "Trạng thái" = [string]$_.Status
        "Bằng chứng kỹ thuật" = [string]$_.Evidence
        "Khuyến nghị" = [string]$_.Recommendation
    }
})
$summaryBody = "<p><strong>Kết quả tổng hợp:</strong> $(ConvertTo-ToolHtmlText $overall)</p>" +
    "<p><strong>Windows:</strong> $(ConvertTo-ToolHtmlText "$productName - $edition")<br>" +
    "<strong>Ngày cài đặt:</strong> $(ConvertTo-ToolHtmlText $installDate)<br>" +
    "<strong>Trạng thái cấp phép:</strong> $(ConvertTo-ToolHtmlText $(if ($isActivated) { 'Đã cấp phép' } else { 'Chưa cấp phép hoặc đang ở trạng thái thông báo/gia hạn' }))<br>" +
    "<strong>Kênh hiện tại:</strong> $(ConvertTo-ToolHtmlText $channel)<br>" +
    "<strong>5 ký tự cuối:</strong> $(ConvertTo-ToolHtmlText $partialKey)<br>" +
    "<strong>Key OEM BIOS:</strong> $(ConvertTo-ToolHtmlText $oemMasked)</p>"
$guidanceBody = "<ul>" + ((@($handlingGuidance) | ForEach-Object { "<li>$(ConvertTo-ToolHtmlText $_)</li>" }) -join "") + "</ul>" +
    "<p class='note'><strong>Lưu ý:</strong> Báo cáo chỉ đọc, không sửa Registry, file hosts, firewall, product key, task, service hoặc lịch sử PowerShell. Trạng thái kích hoạt không tự động chứng minh bản quyền hợp pháp; cần đối chiếu hóa đơn, hợp đồng, tài khoản hoặc hồ sơ cấp phép.</p>"
$html = New-ToolProfessionalHtmlDocument `
    -Title "Kiểm tra bản quyền Windows chuyên sâu - 7 nhóm tiêu chí" `
    -Subtitle "Báo cáo chuyên sâu chỉ đọc, dùng chung giao diện với toàn bộ báo cáo HTML/PDF của Tool." `
    -Eyebrow "Báo cáo kiểm kê và bảo đảm bản quyền" `
    -Metadata @(
        [pscustomobject]@{Label="Máy";Value=$reportMachine},
        [pscustomobject]@{Label="Thời điểm";Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
        [pscustomobject]@{Label="Quyền";Value="Administrator · chỉ đọc"},
        [pscustomobject]@{Label="Riêng tư";Value=$(if ($RedactSensitive) { "Đã che dữ liệu nhạy cảm" } else { "Báo cáo đầy đủ nội bộ" })}
    ) `
    -Cards @(
        [pscustomobject]@{Label="Kết quả";Value=$overall;Tone=$(if ($highCount -gt 0) {"danger"} elseif ($reviewCount -gt 0) {"warning"} else {"ok"})},
        [pscustomobject]@{Label="Dấu hiệu mạnh";Value=[string]$highCount;Tone=$(if ($highCount -gt 0) {"danger"} else {"ok"})},
        [pscustomobject]@{Label="Cần xác minh";Value=[string]$reviewCount;Tone=$(if ($reviewCount -gt 0) {"warning"} else {"ok"})},
        [pscustomobject]@{Label="Nhóm kiểm tra";Value=[string]$reportRows.Count;Tone="info"}
    ) `
    -Sections @(
        [pscustomobject]@{Title="Tổng quan";BodyHtml=$summaryBody},
        [pscustomobject]@{Title="Kết quả 7 nhóm kiểm tra";BodyHtml=(ConvertTo-ToolHtmlTable -Rows $reportRows -Columns @("#","Nhóm kiểm tra","Trạng thái","Bằng chứng kỹ thuật","Khuyến nghị"))},
        [pscustomobject]@{Title="Hướng xử lý và giới hạn";BodyHtml=$guidanceBody}
    ) `
    -Footer "Phát triển bởi Thanh Việt · Tool v$toolVersion" -Culture "vi-VN" -OfflineMode $true
[IO.File]::WriteAllText($reportPath, $html, (New-Object Text.UTF8Encoding($false)))
if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $reportPath)) { throw "Báo cáo chuyên sâu không đạt kiểm tra HTML ngoại tuyến." }
$pdfResult = Convert-ToolHtmlToPdf -HtmlPath $reportPath -PdfPath $pdfPath
$hashLines = @("# SHA-256 deep scan report package.")
foreach ($path in @($reportPath, $pdfPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { $hashLines += "$(Get-ToolSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))" }
}
[IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))

$decision = New-ToolReportEnvelope -ReportKind "DeepScanDecision" -ToolVersion $toolVersion -Data ([ordered]@{
    AccessDenied = $false
    ReportPath = $reportPath
    PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
    Overall = $overall
    HighCount = $highCount
    ReviewCount = $reviewCount
    OemKeyPresent = $oemPresent
    ActiveChannel = $channel
    ReviewItems = $reviewItems
    HandlingGuidance = $handlingGuidance.ToArray()
})
$decisionValidation = Test-ToolReportEnvelope -Report $decision -ExpectedReportKind "DeepScanDecision" -ExpectedToolVersion $toolVersion
if (-not $decisionValidation.Valid) { throw "DeepScanDecision không đạt schema: $($decisionValidation.Errors -join '; ')" }
if (-not [string]::IsNullOrWhiteSpace($DecisionFile)) {
    $decision | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
}

Write-Host "Báo cáo: $reportPath"
if ($pdfResult.Success) { Write-Host "PDF: $pdfPath" } else { Write-Host "PDF chưa tạo được: $($pdfResult.Error)" }
Write-Host "Kết quả: $overall"
if (-not $NoOpen) { Start-Process -FilePath $reportPath }
exit 0
