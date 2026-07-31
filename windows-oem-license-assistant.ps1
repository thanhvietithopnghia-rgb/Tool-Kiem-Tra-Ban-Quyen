param(
    [ValidateSet("Inspect", "Apply")]
    [string]$Mode = "Inspect",
    [string]$OutputDir = [Environment]::GetFolderPath("Desktop"),
    [string]$DecisionFile = ""
)

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "Cong cu can PowerShell 3.0 tro len."
    exit 10
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1." }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw "Thiếu Tool-ReportExport.ps1." }
    . $runtimeHelper
    . $reportExportHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "Continue"

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

function Get-LicenseChannel {
    param($License)
    if (-not $License) { return "Không xác định" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return $description
}

function Mask-Key {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return "Không tìm thấy" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return "Đã phát hiện (không đọc được 5 ký tự cuối)" }
    return "*****-*****-*****-*****-" + $compact.Substring($compact.Length - 5)
}

function Sanitize-Text {
    param([object[]]$Lines, [string]$Secret)
    $text = ($Lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if (-not [string]::IsNullOrWhiteSpace($Secret)) {
        $text = $text -replace [regex]::Escape($Secret), (Mask-Key $Secret)
    }
    return $text.Trim()
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Write-Decision {
    param($Value)
    if ([string]::IsNullOrWhiteSpace($DecisionFile)) { return }
    $parent = Split-Path -Parent $DecisionFile
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
}

function Write-Report {
    param([System.Collections.Generic.List[string]]$Lines)
    $expandedOutput = [Environment]::ExpandEnvironmentVariables($OutputDir)
    if (-not (Test-Path -LiteralPath $expandedOutput)) {
        New-Item -ItemType Directory -Path $expandedOutput -Force | Out-Null
    }
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $basePath = Join-Path $expandedOutput "BaoCao_Key_OEM_BIOS_$($env:COMPUTERNAME)_$stamp"
    $package = Export-ToolTextReportPresentation `
        -Lines $Lines.ToArray() -Title "Báo cáo key OEM trong BIOS" -BasePath $basePath `
        -Subtitle "Kiểm tra key OEM OA3 trong firmware, trạng thái Windows và kết quả áp dụng có xác nhận." `
        -Eyebrow "Báo cáo kiểm kê và bảo đảm bản quyền" `
        -Footer "Phát triển bởi Thanh Việt · Tool v4.3" -Culture "vi-VN" -IncludePdf
    Write-Host "HTML: $($package.HtmlPath)"
    if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host "PDF: $($package.PdfPath)" }
    else { Write-Host "PDF chưa tạo được: $($package.Pdf.Error)" }
    return $package
}

function Complete-OemReport {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )
    $package = Write-Report -Lines $Lines
    $result = [ordered]@{}
    foreach ($property in @($State.PSObject.Properties)) { $result[[string]$property.Name] = $property.Value }
    $result.ReportPath = [string]$package.HtmlPath
    $result.PdfPath = [string]$package.PdfPath
    $result.ExitCode = $ExitCode
    Write-Decision ([pscustomobject]$result)
    return $package
}

$currentVersion = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$currentEdition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { "Không xác định" }
$productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }

$licensingService = Safe-Cim SoftwareLicensingService | Select-Object -First 1
$firmwareKey = if ($licensingService) { [string]$licensingService.OA3xOriginalProductKey } else { "" }
$firmwareKeyFound = -not [string]::IsNullOrWhiteSpace($firmwareKey)
$maskedFirmwareKey = Mask-Key $firmwareKey

$windowsLicenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Windows"
}
$activeLicense = $windowsLicenses | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$currentChannel = Get-LicenseChannel $activeLicense
$currentPartialKey = if ($activeLicense.PartialProductKey) { [string]$activeLicense.PartialProductKey } else { "Không xác định" }
$isActivated = [bool]$activeLicense

$decision = [pscustomobject]@{
    FirmwareKeyFound = $firmwareKeyFound
    FirmwareKeyMasked = $maskedFirmwareKey
    ProductName = $productName
    CurrentEdition = $currentEdition
    IsActivated = $isActivated
    CurrentChannel = $currentChannel
    CurrentPartialKey = $currentPartialKey
}

$report = New-Object 'System.Collections.Generic.List[string]'
$report.Add("CÔNG CỤ KIỂM TRA KEY OEM TRONG BIOS - PHIÊN BẢN 4.3")
$report.Add("Phát triển bởi Thanh Việt")
$report.Add("Máy: $env:COMPUTERNAME")
$report.Add("Thời điểm: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
$report.Add("")
$report.Add("Windows: $productName")
$report.Add("Edition hiện tại: $currentEdition")
$report.Add("Trạng thái kích hoạt hiện tại: $(if ($isActivated) { 'Đã cấp phép' } else { 'Chưa xác nhận được cấp phép' })")
$report.Add("Kênh cấp phép hiện tại: $currentChannel")
$report.Add("5 ký tự cuối key hiện tại: $currentPartialKey")
$report.Add("Key OEM OA3 trong BIOS: $(if ($firmwareKeyFound) { $maskedFirmwareKey } else { 'Không tìm thấy' })")
$report.Add("")
$report.Add("Lưu ý: Công cụ không lưu hoặc hiển thị product key đầy đủ. Có key OEM trong BIOS không tự động chứng minh edition Windows đang cài khớp với key đó.")

if ($Mode -eq "Inspect") {
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 0)
    exit 0
}

if (-not (Test-Administrator)) {
    $report.Add("Kết quả: Cần quyền Quản trị viên để cài key OEM.")
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 20)
    exit 20
}

if (-not $firmwareKeyFound) {
    $report.Add("Kết quả: Không tìm thấy key OEM OA3 trong BIOS; không thay đổi hệ thống.")
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 21)
    exit 21
}

$slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
if (-not (Test-Path -LiteralPath $slmgr)) {
    $report.Add("Kết quả: Không tìm thấy slmgr.vbs; không thay đổi hệ thống.")
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 24)
    exit 24
}

$report.Add("Đã được người dùng xác nhận cài key OEM từ BIOS.")
$report.Add("Cơ chế bảo vệ: không chạy /upk hoặc /cpky trước; nếu Windows từ chối key OEM, cấu hình key hiện tại không bị gỡ trước.")

$installOutput = & $nativeCscriptPath //nologo $slmgr /ipk $firmwareKey 2>&1
$installExitCode = $LASTEXITCODE
$report.Add("Kết quả cài key (đã ẩn key):")
$report.Add((Sanitize-Text $installOutput $firmwareKey))

$lastFive = ($firmwareKey -replace "[^A-Za-z0-9]", "")
if ($lastFive.Length -ge 5) { $lastFive = $lastFive.Substring($lastFive.Length - 5) }
$installedLicense = $null
for ($attempt = 1; $attempt -le 3 -and -not $installedLicense; $attempt++) {
    Start-Sleep -Seconds 2
    $installedLicense = Safe-Cim SoftwareLicensingProduct | Where-Object {
        $_.PartialProductKey -eq $lastFive -and $_.Name -match "Windows"
    } | Select-Object -First 1
}

if ($installExitCode -ne 0 -or -not $installedLicense) {
    $report.Add("Kết luận: Windows không chấp nhận key OEM cho edition hiện tại. Công cụ không gỡ key cũ trước khi thử cài.")
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 22)
    exit 22
}

$activationOutput = & $nativeCscriptPath //nologo $slmgr /ato 2>&1
$activationExitCode = $LASTEXITCODE
$report.Add("Kết quả yêu cầu kích hoạt:")
$report.Add((Sanitize-Text $activationOutput $firmwareKey))

$activatedFirmwareLicense = $null
for ($attempt = 1; $attempt -le 3 -and -not $activatedFirmwareLicense; $attempt++) {
    Start-Sleep -Seconds 2
    $activatedFirmwareLicense = Safe-Cim SoftwareLicensingProduct | Where-Object {
        $_.PartialProductKey -eq $lastFive -and $_.Name -match "Windows" -and [int]$_.LicenseStatus -eq 1
    } | Select-Object -First 1
}

if ($activationExitCode -eq 0 -and $activatedFirmwareLicense) {
    $report.Add("Kết luận: Đã cài key OEM và Windows xác nhận trạng thái đã cấp phép.")
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 0)
    exit 0
}

$report.Add("Kết luận: Key OEM đã được Windows chấp nhận nhưng chưa xác nhận kích hoạt. Hãy kiểm tra edition, kết nối mạng hoặc liên hệ Microsoft/nhà sản xuất.")
[void](Complete-OemReport -Lines $report -State $decision -ExitCode 23)
exit 23
