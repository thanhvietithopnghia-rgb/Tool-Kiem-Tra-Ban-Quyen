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
    $nativeNetshPath = Get-ToolNativeSystemPath "netsh.exe"
    $nativeW32tmPath = Get-ToolNativeSystemPath "w32tm.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "SilentlyContinue"
$toolVersion = "4.3"
$scanStarted = Get-Date
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Write-DecisionFile($Value) {
    if ([string]::IsNullOrWhiteSpace($DecisionFile)) { return }
    $parent = Split-Path -Parent $DecisionFile
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
}

if (-not (Test-Administrator)) {
    Write-DecisionFile (New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
        AccessDenied = $true
        Overall = "Chưa chạy: cần quyền Administrator"
        RiskScore = 0
        RiskLevel = "Chưa xác định"
        HighCount = 0
        ReviewCount = 0
        NewFindingCount = 0
        ReportPath = ""
        EvidenceFolder = ""
    }))
    Write-Host "Che do dieu tra chuyen sau can quyen Administrator."
    exit 20
}

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
                $execute = @($_.Actions | Select-Object -ExpandProperty Execute -ErrorAction SilentlyContinue) | Select-Object -First 1
                [pscustomobject]@{
                    Name=([string]$_.TaskPath + [string]$_.TaskName)
                    Actions=[string]($_.Actions | Out-String)
                    Execute=[string]$execute
                }
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
            if (-not $name) { continue }
            $actionText = ($values -join " | ")
            $execute = Get-ExecutablePath $actionText
            [void]$rows.Add([pscustomobject]@{ Name=$name; Actions=$actionText; Execute=$execute })
        }
        if ($rows.Count -eq 0) { throw "Không phân tích được scheduled task." }
        return $rows.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        throw "Không thể quét Scheduled Tasks: $detail"
    }
}

function Protect-Text($Value) {
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if (-not $RedactSensitive) { return $text }
    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if ($profilePath) { $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    $kmsNames = @($kmsServer) + @($script:approvedKmsServers)
    if ($officeKms) { $kmsNames += @($officeKms | ForEach-Object { [string]$_.KeyManagementServiceMachine }) }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME) + @($kmsNames)) {
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

function Html($Value) {
    $safeValue = Protect-Text $Value
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue)
    }
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    try {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
        $stream = [IO.File]::OpenRead($Path)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "").ToUpperInvariant() }
            finally { $sha.Dispose() }
        } finally { $stream.Dispose() }
    } catch { return "" }
}

function Get-ExecutablePath([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return "" }
    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.(exe|com|bat|cmd|ps1|vbs|dll))"') { return $matches[1] }
    if ($expanded -match '^\s*([^\s]+\.(exe|com|bat|cmd|ps1|vbs|dll))') { return $matches[1] }
    return ""
}

function Test-LicenseHostsBlockLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.TrimStart().StartsWith("#")) { return $false }
    if ($Line -notmatch "(?i)^\s*(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+") { return $false }
    $licenseHostPattern = "(?i)(microsoft|windows|office|sls\.microsoft|activation\.sls|genuine|licensing).*(activation|validation|sls|genuine|licensing)|" +
        "(activation|validation|sls|genuine|licensing).*(microsoft|windows|office)"
    return [bool]($Line -match $licenseHostPattern)
}

function Get-FileEvidence([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "Không tìm thấy tệp để kiểm tra."
    }
    $signatureText = "Không hỗ trợ"
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        $signer = if ($signature.SignerCertificate.Subject) { $signature.SignerCertificate.Subject } else { "không có chứng thư" }
        $signatureText = "$($signature.Status); $signer"
    } catch { $signatureText = "Không đọc được chữ ký" }
    $hash = Get-Sha256 $Path
    return "$Path | Chữ ký: $signatureText | SHA-256: $hash"
}

function Get-LicenseChannel($License) {
    if (-not $License) { return "Không xác định" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return "Không xác định"
}

function Mask-Key([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return "Không tìm thấy" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return "Đã phát hiện" }
    return "*****-*****-*****-*****-" + $compact.Substring($compact.Length - 5)
}

function New-Finding {
    param(
        [string]$Id,
        [string]$Category,
        [ValidateSet("OK", "Thông tin", "Cần xác minh", "Rủi ro cao")][string]$Status,
        [int]$Score,
        [string]$Evidence,
        [string]$Recommendation
    )
    return [pscustomobject]@{
        Id = $Id
        Category = $Category
        Status = $Status
        Score = [Math]::Max(0, $Score)
        Evidence = $Evidence
        Recommendation = $Recommendation
    }
}

function Add-Finding {
    param($Finding)
    $script:findings.Add($Finding)
}

function Test-ApprovedKms([string]$Server) {
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    foreach ($approved in $script:approvedKmsServers) {
        $item = $approved
        if ($item -match "^([^:]+):\d+$") { $item = $matches[1] }
        if ($candidate -eq $item) { return $true }
    }
    return $false
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$stamp = $scanStarted.ToString("yyyyMMdd_HHmmss")
$reportMachine = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
$bundleName = "LicenseForensics_${reportMachine}_$stamp"
$bundleDir = Join-Path $OutputDir $bundleName
New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
$htmlPath = Join-Path $OutputDir "$bundleName.html"
$pdfPath = Join-Path $OutputDir "$bundleName.pdf"
$jsonPath = Join-Path $bundleDir "$bundleName.json"
$csvPath = Join-Path $bundleDir "$bundleName.csv"
$manifestPath = Join-Path $bundleDir "SHA256SUMS.txt"
$findings = New-Object System.Collections.Generic.List[object]

$approvedKmsServers = @()
if (Test-Path -LiteralPath $ApprovedKmsServerFile) {
    $approvedKmsServers = @(Get-Content -LiteralPath $ApprovedKmsServerFile | ForEach-Object {
        ($_ -replace "#.*$", "").Trim().ToLowerInvariant()
    } | Where-Object { $_ })
}

# 1. Trạng thái giấy phép Windows và kênh kích hoạt.
$licenses = @(Safe-Cim SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -match "Windows" })
$activeLicense = $licenses | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$licenseForAnalysis = if ($activeLicense) { $activeLicense } else { $licenses | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
$channel = Get-LicenseChannel $licenseForAnalysis
$partialKey = if ($licenseForAnalysis.PartialProductKey) { [string]$licenseForAnalysis.PartialProductKey } else { "Không xác định" }
$kmsServer = if ($licenseForAnalysis.KeyManagementServiceMachine) { [string]$licenseForAnalysis.KeyManagementServiceMachine } else { "" }
$knownPublicKms = "(?i)^(127\.0\.0\.1|0\.0\.0\.0|localhost)$|massgrave|kms\.loli|kms\.msgang|kms\.digiboy|kms\.03k|kms\.tee"
if (-not $activeLicense) {
    Add-Finding (New-Finding "WIN-LICENSE" "Giấy phép Windows" "Cần xác minh" 8 "Windows chưa ở trạng thái LicenseStatus=1. Kênh: $channel; 5 ký tự cuối: $partialKey." "Mở Activation, kiểm tra lỗi và đối chiếu giấy phép hợp lệ.")
} elseif ($channel -eq "KMS" -and $kmsServer -match $knownPublicKms) {
    Add-Finding (New-Finding "WIN-LICENSE" "Giấy phép Windows" "Rủi ro cao" 30 "Kênh KMS trỏ đến máy chủ công cộng/ảo: $kmsServer." "Xác minh nguồn cấp phép; nếu không hợp lệ, dùng quy trình gỡ KMS/crack có sao lưu.")
} elseif ($channel -eq "KMS" -and -not (Test-ApprovedKms $kmsServer)) {
    Add-Finding (New-Finding "WIN-LICENSE" "Giấy phép Windows" "Cần xác minh" 12 "Windows dùng KMS; máy chủ '$kmsServer' chưa có trong danh sách phê duyệt." "Đối chiếu với quản trị viên hoặc hồ sơ Volume Licensing.")
} else {
    $kmsNote = if ($channel -eq "KMS") { "Máy chủ KMS đã phê duyệt: $kmsServer" } else { "Kênh $channel" }
    Add-Finding (New-Finding "WIN-LICENSE" "Giấy phép Windows" "OK" 0 "Windows đã cấp phép; $kmsNote; 5 ký tự cuối: $partialKey." "Tiếp tục đối chiếu hóa đơn/hợp đồng vì kích hoạt không tự chứng minh quyền sở hữu.")
}

# 2. Key OEM firmware và logic edition.
$licensingService = Safe-Cim SoftwareLicensingService | Select-Object -First 1
$oemKey = if ($licensingService) { [string]$licensingService.OA3xOriginalProductKey } else { "" }
$oemMasked = Mask-Key $oemKey
$currentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
$edition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { "Không xác định" }
if ($oemKey) {
    Add-Finding (New-Finding "OEM-FIRMWARE" "OEM trong firmware" "Thông tin" 0 "Phát hiện key OA3 dạng che: $oemMasked; edition đang cài: $edition." "Chỉ thử khôi phục bằng chức năng OEM nếu edition phù hợp; tool không ghi key đầy đủ.")
} else {
    Add-Finding (New-Finding "OEM-FIRMWARE" "OEM trong firmware" "Thông tin" 0 "Không tìm thấy key OEM OA3 trong BIOS/UEFI." "Điều này bình thường với máy Retail, Volume hoặc thiết bị không kèm Windows.")
}

# 3. Tính toàn vẹn thành phần cấp phép cốt lõi.
$coreFiles = @(
    (Get-ToolNativeSystemPath "sppsvc.exe"),
    (Get-ToolNativeSystemPath "sppcomapi.dll"),
    (Get-ToolNativeSystemPath "slc.dll")
)
$coreEvidence = New-Object System.Collections.Generic.List[string]
$coreBad = 0
$coreMissing = 0
foreach ($coreFile in $coreFiles) {
    if (-not (Test-Path -LiteralPath $coreFile -PathType Leaf)) {
        $coreMissing++
        $coreEvidence.Add("Thiếu: $coreFile")
        continue
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $coreFile
    $subject = if ($signature.SignerCertificate.Subject) { [string]$signature.SignerCertificate.Subject } else { "" }
    if ($signature.Status -ne "Valid" -or $subject -notmatch "Microsoft") { $coreBad++ }
    $coreEvidence.Add((Get-FileEvidence $coreFile))
}
$sppService = Get-Service -Name sppsvc -ErrorAction SilentlyContinue
$sppStart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\sppsvc" -ErrorAction SilentlyContinue).Start
if ($coreBad -gt 0 -or $coreMissing -gt 0) {
    Add-Finding (New-Finding "CORE-INTEGRITY" "Toàn vẹn thành phần cấp phép" "Rủi ro cao" 35 (($coreEvidence -join "`n") + "`nSPP service: $($sppService.Status); Start=$sppStart") "Chạy DISM/SFC từ nguồn Microsoft và kiểm tra malware; không thay tệp hệ thống bằng bản tải không rõ nguồn.")
} elseif ($sppStart -eq 4) {
    Add-Finding (New-Finding "CORE-INTEGRITY" "Toàn vẹn thành phần cấp phép" "Rủi ro cao" 25 (($coreEvidence -join "`n") + "`nDịch vụ Software Protection đang Disabled.") "Khôi phục cấu hình dịch vụ bằng công cụ Windows hoặc quản trị viên hệ thống.")
} else {
    Add-Finding (New-Finding "CORE-INTEGRITY" "Toàn vẹn thành phần cấp phép" "OK" 0 (($coreEvidence -join "`n") + "`nSPP service: $($sppService.Status); Start=$sppStart") "Không cần thay đổi.")
}

# 4. Dấu vết activator trong tiến trình, dịch vụ, task và startup.
$activatorRegex = "(?i)(kmspico|kmsauto|autokms|aact|sppextcomobj(?:hook|patcher)|microsoft toolkit|hwidgen|massgrave|digital license activation|get\.activated\.win)"
$artifactRows = New-Object System.Collections.Generic.List[object]
foreach ($serviceItem in @(Safe-Cim Win32_Service | Where-Object { $_.Name -match $activatorRegex -or $_.DisplayName -match $activatorRegex -or $_.PathName -match $activatorRegex })) {
    $path = Get-ExecutablePath ([string]$serviceItem.PathName)
    $artifactRows.Add([pscustomobject]@{ Type="Service"; Name=$serviceItem.Name; Path=$path; Evidence=(Get-FileEvidence $path) })
}
foreach ($processItem in @(Get-Process | Where-Object { $_.ProcessName -match $activatorRegex })) {
    $path = ""
    try { $path = [string]$processItem.Path } catch {}
    $artifactRows.Add([pscustomobject]@{ Type="Process"; Name=$processItem.ProcessName; Path=$path; Evidence=(Get-FileEvidence $path) })
}
$taskScanWarning = ""
try {
    foreach ($task in @(Get-CompatibleScheduledTaskRows | Where-Object { $_.Name -match $activatorRegex -or $_.Actions -match $activatorRegex })) {
        $artifactRows.Add([pscustomobject]@{ Type="ScheduledTask"; Name=[string]$task.Name; Path=[string]$task.Execute; Evidence=(Get-FileEvidence ([string]$task.Execute)) })
    }
} catch { $taskScanWarning = $_.Exception.Message }
foreach ($startup in @(Safe-Cim Win32_StartupCommand | Where-Object { $_.Name -match $activatorRegex -or $_.Command -match $activatorRegex })) {
    $path = Get-ExecutablePath ([string]$startup.Command)
    $artifactRows.Add([pscustomobject]@{ Type="Startup"; Name=$startup.Name; Path=$path; Evidence=(Get-FileEvidence $path) })
}
$artifactFolders = @(
    (Join-Path $env:windir "KMS"), (Join-Path $env:windir "AutoKMS"),
    (Join-Path $env:ProgramData "KMSAutoS"), (Join-Path $env:SystemDrive "KMSpico"),
    (Join-Path $env:SystemDrive "AAct")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
if ($artifactRows.Count -gt 0 -or $artifactFolders.Count -gt 0) {
    $artifactText = @($artifactRows | ForEach-Object { "$($_.Type): $($_.Name) | $($_.Evidence)" }) + @($artifactFolders | ForEach-Object { "Folder: $_" })
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" "Dấu vết activator/persistence" "Rủi ro cao" 35 ($artifactText -join "`n") "Xác minh từng tệp bằng chữ ký/hash; dùng chức năng gỡ KMS/crack sau khi sao lưu và xác nhận.")
} elseif ($taskScanWarning) {
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" "Dấu vết activator/persistence" "Cần xác minh" 8 $taskScanWarning "Kiểm tra Task Scheduler/schtasks.exe rồi chạy lại; không kết luận sạch khi nguồn này chưa đọc được.")
} else {
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" "Dấu vết activator/persistence" "OK" 0 "Không thấy tiến trình, dịch vụ, task, startup hoặc thư mục khớp mẫu đặc hiệu." "Không cần xử lý tự động.")
}

# 5. Registry, hosts và proxy có thể can thiệp kích hoạt.
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
$policy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
$policyItems = @()
if ($policy.KeyManagementServiceName) { $policyItems += "KeyManagementServiceName=$($policy.KeyManagementServiceName)" }
if ($policy.KeyManagementServicePort) { $policyItems += "KeyManagementServicePort=$($policy.KeyManagementServicePort)" }
if ([int]$policy.NoGenTicket -eq 1) { $policyItems += "NoGenTicket=1" }
$hostsPath = Get-ToolNativeSystemPath "drivers\etc\hosts"
$hostsHits = @()
if (Test-Path -LiteralPath $hostsPath) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue) {
        $lineNumber++
        if (Test-LicenseHostsBlockLine $line) {
            $hostsHits += "Dòng $lineNumber (nội dung được ẩn để tránh lộ cấu hình): khớp mẫu chặn kích hoạt"
        }
    }
}
$winHttpProxy = (& $nativeNetshPath winhttp show proxy 2>$null) -join " "
$proxyConfigured = $winHttpProxy -and $winHttpProxy -notmatch "(?i)(Direct access|truy cập trực tiếp)"
if ($hostsHits.Count -gt 0) {
    Add-Finding (New-Finding "NETWORK-TAMPER" "Hosts/Registry/proxy kích hoạt" "Rủi ro cao" 25 ("Hosts: " + ($hostsHits -join "; ") + "; Policy: " + ($policyItems -join ", ") + "; WinHTTP proxy: " + $winHttpProxy) "Đối chiếu chính sách doanh nghiệp; chỉ sửa đúng dòng/key sau khi xác nhận.")
} elseif ($policyItems.Count -gt 0 -or $proxyConfigured) {
    Add-Finding (New-Finding "NETWORK-TAMPER" "Hosts/Registry/proxy kích hoạt" "Cần xác minh" 8 ("Policy: " + ($policyItems -join ", ") + "; WinHTTP proxy: " + $winHttpProxy) "Cấu hình có thể hợp lệ trong doanh nghiệp; xác minh với quản trị viên.")
} else {
    Add-Finding (New-Finding "NETWORK-TAMPER" "Hosts/Registry/proxy kích hoạt" "OK" 0 "Không thấy dòng hosts chặn kích hoạt, policy SPP đáng chú ý hoặc WinHTTP proxy tùy chỉnh." "Không cần thay đổi.")
}

# 6. Nhật ký Software Protection trong 30 ngày; chỉ lưu thống kê, không chép nội dung sự kiện.
$eventStart = (Get-Date).AddDays(-30)
$licensingEvents = @()
foreach ($provider in @("Software Protection Platform Service", "Microsoft-Windows-Security-SPP", "Office Software Protection Platform Service")) {
    try {
        $licensingEvents += @(Get-WinEvent -FilterHashtable @{ LogName="Application"; ProviderName=$provider; StartTime=$eventStart } -ErrorAction Stop)
    } catch {}
}
$licensingErrors = @($licensingEvents | Where-Object { $_.Level -in @(1,2) })
$lastEvent = $licensingEvents | Sort-Object TimeCreated -Descending | Select-Object -First 1
$eventEvidence = "30 ngày: $($licensingEvents.Count) sự kiện SPP; lỗi/nghiêm trọng: $($licensingErrors.Count); gần nhất: $(if ($lastEvent) { $lastEvent.TimeCreated } else { 'không có' }). Nội dung sự kiện không được lưu."
if ($licensingErrors.Count -ge 10) {
    Add-Finding (New-Finding "SPP-EVENTS" "Nhật ký cấp phép" "Cần xác minh" 10 $eventEvidence "Mở Event Viewer để xem mã lỗi lặp lại và đối chiếu thời điểm thay đổi key/KMS.")
} else {
    Add-Finding (New-Finding "SPP-EVENTS" "Nhật ký cấp phép" "Thông tin" 0 $eventEvidence "Không kết luận vi phạm chỉ từ số lượng sự kiện.")
}

# 7. Đồng bộ thời gian và múi giờ.
$timeService = Get-Service -Name W32Time -ErrorAction SilentlyContinue
$timeStatus = (& $nativeW32tmPath /query /status 2>$null) -join " | "
if ($timeService -and $timeService.StartType -eq "Disabled") {
    Add-Finding (New-Finding "TIME-SYNC" "Đồng bộ thời gian" "Cần xác minh" 6 "W32Time đang Disabled; múi giờ: $([TimeZoneInfo]::Local.Id)." "Bật đồng bộ thời gian theo chính sách tổ chức; sai giờ có thể gây lỗi xác thực.")
} else {
    $timeSummary = ($timeStatus -replace "\s+", " ").Trim()
    if ($timeSummary.Length -gt 300) { $timeSummary = $timeSummary.Substring(0,300) + "..." }
    Add-Finding (New-Finding "TIME-SYNC" "Đồng bộ thời gian" "Thông tin" 0 "W32Time: $($timeService.Status); múi giờ: $([TimeZoneInfo]::Local.Id); $timeSummary" "Nếu kích hoạt lỗi, kiểm tra lại ngày giờ và nguồn NTP.")
}

# 8. Office: trạng thái, kênh và KMS.
$officeLicenses = @(Safe-Cim SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -match "Office" })
$officeActive = @($officeLicenses | Where-Object { [int]$_.LicenseStatus -eq 1 })
$officeKms = @($officeLicenses | Where-Object { $_.Description -match "KMSCLIENT|VOLUME_KMS" })
$officeEvidence = @($officeLicenses | ForEach-Object {
    "$($_.Name) | Status=$($_.LicenseStatus) | $($_.Description) | Last5=$($_.PartialProductKey) | KMS=$($_.KeyManagementServiceMachine)"
})
if ($officeKms.Count -gt 0) {
    $unapprovedOfficeKms = @($officeKms | Where-Object { -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine)) })
    if ($unapprovedOfficeKms.Count -gt 0) {
        Add-Finding (New-Finding "OFFICE-LICENSE" "Giấy phép Microsoft Office" "Cần xác minh" 15 ($officeEvidence -join "`n") "Đối chiếu KMS/MAK/Microsoft 365 với hồ sơ cấp phép và tài khoản tổ chức.")
    } else {
        Add-Finding (New-Finding "OFFICE-LICENSE" "Giấy phép Microsoft Office" "OK" 0 ($officeEvidence -join "`n") "KMS Office nằm trong danh sách phê duyệt; vẫn cần hồ sơ Volume Licensing.")
    }
} elseif ($officeLicenses.Count -eq 0) {
    Add-Finding (New-Finding "OFFICE-LICENSE" "Giấy phép Microsoft Office" "Thông tin" 0 "Không phát hiện bản Office dùng SoftwareLicensingProduct. Microsoft 365 gắn tài khoản có thể không hiện đầy đủ tại đây." "Mở Word > Tệp > Tài khoản để xác minh sản phẩm và tài khoản.")
} elseif ($officeActive.Count -eq 0) {
    Add-Finding (New-Finding "OFFICE-LICENSE" "Giấy phép Microsoft Office" "Cần xác minh" 8 ($officeEvidence -join "`n") "Kiểm tra trong ứng dụng Office và tài khoản Microsoft 365.")
} else {
    Add-Finding (New-Finding "OFFICE-LICENSE" "Giấy phép Microsoft Office" "OK" 0 ($officeEvidence -join "`n") "Đối chiếu hóa đơn/tài khoản; trạng thái kích hoạt không tự chứng minh quyền sở hữu.")
}

# 9. Phần mềm cài đặt có tên/publisher khớp mẫu đặc hiệu.
$uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$suspiciousApps = @()
foreach ($root in $uninstallRoots) {
    $suspiciousApps += @(Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match $activatorRegex -or $_.Publisher -match $activatorRegex
    } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion) | $($_.Publisher)" })
}
$suspiciousApps = @($suspiciousApps | Sort-Object -Unique)
if ($suspiciousApps.Count -gt 0) {
    Add-Finding (New-Finding "SUSPICIOUS-APPS" "Phần mềm kích hoạt đáng ngờ" "Rủi ro cao" 30 ($suspiciousApps -join "`n") "Gỡ bằng cơ chế chuẩn sau khi xác minh; quét Defender và kiểm tra persistence.")
} else {
    Add-Finding (New-Finding "SUSPICIOUS-APPS" "Phần mềm kích hoạt đáng ngờ" "OK" 0 "Không thấy mục cài đặt khớp mẫu activator đặc hiệu." "Tên phần mềm chỉ là một tín hiệu; kết quả không bao phủ ứng dụng portable.")
}

# 10. Trạng thái Microsoft Defender và tường lửa.
$defenderText = "Không đọc được Microsoft Defender."
$defenderStatus = "Thông tin"
$defenderScore = 0
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($mp) {
        $defenderText = "Antivirus=$($mp.AntivirusEnabled); RealTime=$($mp.RealTimeProtectionEnabled); Behavior=$($mp.BehaviorMonitorEnabled); TamperProtected=$($mp.IsTamperProtected); SignatureAge=$($mp.AntivirusSignatureAge) ngày"
        if (-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled) { $defenderStatus = "Cần xác minh"; $defenderScore = 7 }
    }
}
$firewallText = ""
if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
    $firewallText = (@(Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join "; ")
}
Add-Finding (New-Finding "SECURITY-POSTURE" "Bảo vệ hệ thống" $defenderStatus $defenderScore "$defenderText; Firewall: $firewallText" "Bảo vệ bị tắt không chứng minh crack, nhưng làm tăng rủi ro khi máy từng chạy activator.")

# 11. Secure Boot, TPM và BitLocker - tín hiệu an toàn bổ trợ.
$secureBoot = "Không hỗ trợ/không xác định"
if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
    try { $secureBoot = [string](Confirm-SecureBootUEFI -ErrorAction Stop) } catch {}
}
$tpmText = "Không hỗ trợ/không xác định"
if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
    try { $tpm = Get-Tpm; $tpmText = "Present=$($tpm.TpmPresent); Ready=$($tpm.TpmReady); Enabled=$($tpm.TpmEnabled)" } catch {}
}
$bitLockerText = "Không hỗ trợ/không xác định"
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    try { $bitLockerText = (@(Get-BitLockerVolume | ForEach-Object { "$($_.MountPoint):$($_.ProtectionStatus)" }) -join "; ") } catch {}
}
Add-Finding (New-Finding "PLATFORM-SECURITY" "Nền tảng bảo mật" "Thông tin" 0 "SecureBoot=$secureBoot; TPM: $tpmText; BitLocker: $bitLockerText" "Thông tin này đánh giá mức bảo vệ, không phải bằng chứng pháp lý về giấy phép.")

# 12. Tệp token cấp phép và ACL cơ bản.
$tokenCandidates = @(
    (Get-ToolNativeSystemPath "spp\store\2.0\tokens.dat"),
    (Join-Path $env:windir "ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SoftwareProtectionPlatform\tokens.dat")
)
$tokenPath = $tokenCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($tokenPath) {
    $tokenInfo = Get-Item -LiteralPath $tokenPath
    $tokenHash = Get-Sha256 $tokenPath
    Add-Finding (New-Finding "TOKEN-ARTIFACT" "Kho token cấp phép" "Thông tin" 0 "Tệp token tồn tại; kích thước=$($tokenInfo.Length); sửa cuối=$($tokenInfo.LastWriteTime); SHA-256=$tokenHash. Không sao chép nội dung." "Hash giúp đối chiếu thay đổi giữa các lần quét; không dùng để phục hồi sang máy khác.")
} else {
    Add-Finding (New-Finding "TOKEN-ARTIFACT" "Kho token cấp phép" "Cần xác minh" 10 "Không tìm thấy tokens.dat tại các vị trí chuẩn được hỗ trợ." "Chạy trình khắc phục Activation hoặc DISM/SFC; không tải tokens.dat từ Internet.")
}

$rawScore = [int](($findings | Measure-Object -Property Score -Sum).Sum)
$riskScore = [Math]::Min(100, $rawScore)
$highCount = @($findings | Where-Object { $_.Status -eq "Rủi ro cao" }).Count
$reviewCount = @($findings | Where-Object { $_.Status -eq "Cần xác minh" }).Count
$riskLevel = if ($riskScore -ge 70) { "Rất cao" } elseif ($riskScore -ge 40) { "Cao" } elseif ($riskScore -ge 20) { "Trung bình" } elseif ($riskScore -gt 0) { "Thấp" } else { "Không phát hiện rủi ro kỹ thuật" }
$overall = if ($highCount -gt 0) { "Phát hiện dấu hiệu kỹ thuật mạnh" } elseif ($reviewCount -gt 0) { "Có mục cần xác minh" } else { "Không phát hiện dấu hiệu kỹ thuật rõ" }

# So sánh với lần quét JSON gần nhất của cùng máy.
$previousFile = Get-ChildItem -LiteralPath $OutputDir -Recurse -Filter "LicenseForensics_${reportMachine}_*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $jsonPath } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$previous = $null
if ($previousFile) {
    try { $previous = Get-Content -LiteralPath $previousFile.FullName -Raw | ConvertFrom-Json } catch {}
}
$currentProblemIds = @($findings | Where-Object { $_.Status -in @("Rủi ro cao", "Cần xác minh") } | Select-Object -ExpandProperty Id)
$previousProblemIds = @()
if ($previous -and $previous.Findings) {
    $previousProblemIds = @($previous.Findings | Where-Object { $_.Status -in @("Rủi ro cao", "Cần xác minh") } | Select-Object -ExpandProperty Id)
}
$newIds = @($currentProblemIds | Where-Object { $previousProblemIds -notcontains $_ })
$resolvedIds = @($previousProblemIds | Where-Object { $currentProblemIds -notcontains $_ })
$unchangedIds = @($currentProblemIds | Where-Object { $previousProblemIds -contains $_ })

$outputFindings = @($findings | ForEach-Object {
    [pscustomobject]@{
        Id=$_.Id; Category=$_.Category; Status=$_.Status; Score=$_.Score
        Evidence=(Protect-Text $_.Evidence); Recommendation=(Protect-Text $_.Recommendation)
    }
})
$scanObject = New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
    ComputerName = $reportMachine
    ScanTime = $scanStarted.ToString("o")
    Windows = "$productName - $edition"
    ActiveChannel = $channel
    OemKeyPresent = [bool]$oemKey
    Overall = $overall
    RiskScore = $riskScore
    RiskLevel = $riskLevel
    HighCount = $highCount
    ReviewCount = $reviewCount
    Baseline = [pscustomobject]@{
        PreviousFile = if ($previousFile) { Protect-Text $previousFile.FullName } else { "" }
        PreviousRiskScore = if ($previous) { [string]$previous.RiskScore } else { "" }
        NewFindingIds = $newIds
        ResolvedFindingIds = $resolvedIds
        UnchangedFindingIds = $unchangedIds
    }
    Findings = $outputFindings
    Redacted = [bool]$RedactSensitive
    Privacy = if ($RedactSensitive) { "Đã che tên máy/người dùng, KMS nội bộ, IP, MAC và đường dẫn hồ sơ người dùng." } else { "Báo cáo đầy đủ nội bộ; không gửi Internet và không lưu product key đầy đủ." }
})
$scanValidation = Test-ToolReportEnvelope -Report $scanObject -ExpectedReportKind "LicenseForensics" -ExpectedToolVersion $toolVersion
if (-not $scanValidation.Valid) { throw "Báo cáo forensics không đạt schema: $($scanValidation.Errors -join '; ')" }
$scanObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$outputFindings | Select-Object Id,Category,Status,Score,Evidence,Recommendation | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$baselineText = if ($previous) {
    "Điểm trước: $($previous.RiskScore)/100 | Mới: $(if ($newIds.Count) { $newIds -join ', ' } else { 'không có' }) | Đã hết: $(if ($resolvedIds.Count) { $resolvedIds -join ', ' } else { 'không có' }) | Không đổi: $(if ($unchangedIds.Count) { $unchangedIds -join ', ' } else { 'không có' })"
} else { "Đây là lần quét đầu tiên; chưa có baseline để so sánh." }
$findingRows = @($outputFindings | ForEach-Object {
    [pscustomobject][ordered]@{
        "Mã" = [string]$_.Id
        "Nhóm" = [string]$_.Category
        "Trạng thái" = [string]$_.Status
        "Điểm" = [string]$_.Score
        "Bằng chứng" = [string]$_.Evidence
        "Khuyến nghị" = [string]$_.Recommendation
    }
})
$overviewBody = "<p><strong>Kết luận:</strong> $(ConvertTo-ToolHtmlText $overall)</p>" +
    "<p><strong>Windows:</strong> $(ConvertTo-ToolHtmlText "$productName - $edition")<br>" +
    "<strong>Kênh:</strong> $(ConvertTo-ToolHtmlText $channel)<br>" +
    "<strong>Key OEM BIOS:</strong> $(ConvertTo-ToolHtmlText $(if ($oemKey) { 'Có (đã che)' } else { 'Không tìm thấy' }))</p>"
$limitBody = "<p><strong>Giới hạn kết luận:</strong> Điểm rủi ro phản ánh dấu hiệu kỹ thuật trên máy, không phải kết luận pháp lý. Kích hoạt thành công không tự chứng minh quyền sở hữu; cần đối chiếu hóa đơn, hợp đồng, tài khoản hoặc hồ sơ cấp phép.</p>" +
    "<p class='note'><strong>Quyền riêng tư:</strong> Không gửi dữ liệu ra Internet; không lưu product key đầy đủ, nội dung lịch sử PowerShell hoặc nội dung Event Log.</p>"
$html = New-ToolProfessionalHtmlDocument `
    -Title "Điều tra bản quyền và chấm điểm rủi ro" `
    -Subtitle "Báo cáo forensics chỉ đọc theo 12 nhóm kỹ thuật, dùng chung giao diện HTML/PDF của Tool." `
    -Eyebrow "Báo cáo kiểm kê và bảo đảm bản quyền" `
    -Metadata @(
        [pscustomobject]@{Label="Máy";Value=$reportMachine},
        [pscustomobject]@{Label="Thời điểm";Value=$scanStarted.ToString("yyyy-MM-dd HH:mm:ss")},
        [pscustomobject]@{Label="Chế độ";Value="Forensics · chỉ đọc"},
        [pscustomobject]@{Label="Riêng tư";Value=$(if ($RedactSensitive) { "Đã che dữ liệu nhạy cảm" } else { "Báo cáo đầy đủ nội bộ" })}
    ) `
    -Cards @(
        [pscustomobject]@{Label="Điểm rủi ro";Value="$riskScore/100";Tone=$(if ($riskScore -ge 70) {"danger"} elseif ($riskScore -ge 20) {"warning"} else {"ok"})},
        [pscustomobject]@{Label="Mức rủi ro";Value=$riskLevel;Tone=$(if ($riskScore -ge 70) {"danger"} elseif ($riskScore -ge 20) {"warning"} else {"ok"})},
        [pscustomobject]@{Label="Rủi ro cao";Value=[string]$highCount;Tone=$(if ($highCount -gt 0) {"danger"} else {"ok"})},
        [pscustomobject]@{Label="Cần xác minh";Value=[string]$reviewCount;Tone=$(if ($reviewCount -gt 0) {"warning"} else {"ok"})}
    ) `
    -Sections @(
        [pscustomobject]@{Title="Tổng quan";BodyHtml=$overviewBody},
        [pscustomobject]@{Title="So sánh với lần quét trước";BodyHtml="<p>$(ConvertTo-ToolHtmlText $baselineText)</p>"},
        [pscustomobject]@{Title="12 nhóm kiểm tra kỹ thuật";BodyHtml=(ConvertTo-ToolHtmlTable -Rows $findingRows -Columns @("Mã","Nhóm","Trạng thái","Điểm","Bằng chứng","Khuyến nghị"))},
        [pscustomobject]@{Title="Giới hạn và quyền riêng tư";BodyHtml=$limitBody}
    ) `
    -Footer "Phát triển bởi Thanh Việt · Tool v$toolVersion" -Culture "vi-VN" -OfflineMode $true
[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) { throw "Báo cáo forensics không đạt kiểm tra HTML ngoại tuyến." }
$pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath

$manifestLines = @()
foreach ($file in @($htmlPath, $pdfPath, $jsonPath, $csvPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $manifestLines += "$(Get-Sha256 $file)  $([IO.Path]::GetFileName($file))"
}
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding ASCII

$decision = New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
    AccessDenied = $false
    Overall = $overall
    RiskScore = $riskScore
    RiskLevel = $riskLevel
    HighCount = $highCount
    ReviewCount = $reviewCount
    NewFindingCount = $newIds.Count
    ResolvedFindingCount = $resolvedIds.Count
    ReportPath = $htmlPath
    PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
    EvidenceFolder = $bundleDir
    ManifestPath = $manifestPath
})
Write-DecisionFile $decision

Write-Host "Báo cáo: $htmlPath"
if ($pdfResult.Success) { Write-Host "PDF: $pdfPath" } else { Write-Host "PDF chưa tạo được: $($pdfResult.Error)" }
Write-Host "Điểm rủi ro: $riskScore/100 - $riskLevel"
if (-not $NoOpen) { Start-Process -FilePath $htmlPath }
exit 0
