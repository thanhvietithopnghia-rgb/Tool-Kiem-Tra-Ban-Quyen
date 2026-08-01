[CmdletBinding()]
param(
    [string]$SourceDirectory = "",
    [int]$MaximumCatalogAgeDays = 45
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { [void]$failures.Add($Message) }

$helperPath = Join-Path $root "Tool-Compatibility.ps1"
$catalogPath = Join-Path $root "compatibility-catalog-v1.0.json"
foreach ($path in @($helperPath, $catalogPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Thiếu tệp: $path" }
}

if ($failures.Count -eq 0) {
    try {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Fail "Lỗi cú pháp Tool-Compatibility.ps1: $($parseError.Message)" }

        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$catalog.SchemaVersion -ne "1.0" -or [string]$catalog.ToolVersion -ne "4.4") {
            Fail "Catalog không dùng schema 1.0 / tool 4.4."
        }
        $reviewedAt = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$catalog.ReviewedAtUtc, [ref]$reviewedAt)) {
            Fail "ReviewedAtUtc không hợp lệ."
        } elseif (([DateTime]::UtcNow - $reviewedAt.ToUniversalTime()).TotalDays -gt $MaximumCatalogAgeDays) {
            Fail "Catalog đã quá $MaximumCatalogAgeDays ngày; bắt buộc rà soát lại Microsoft Learn."
        }
        foreach ($expected in @(
            @{ DisplayVersion="24H2"; Build=26100 },
            @{ DisplayVersion="25H2"; Build=26200 },
            @{ DisplayVersion="26H1"; Build=28000 }
        )) {
            $match = @($catalog.WindowsReleases | Where-Object {
                [string]$_.DisplayVersion -eq $expected.DisplayVersion -and [int]$_.Build -eq $expected.Build
            })
            if ($match.Count -ne 1) { Fail "Thiếu Windows 11 $($expected.DisplayVersion) build $($expected.Build)." }
        }
        foreach ($productId in @("ProPlus2024Volume", "Standard2024Volume", "O365ProPlusRetail", "O365BusinessRetail")) {
            $found = [bool](($catalog.Office2024ProductIds -contains $productId) -or ($catalog.Microsoft365ProductIds -contains $productId))
            if (-not $found) { Fail "Thiếu Office product ID: $productId" }
        }

        $previousCatalog = [string]$env:TOOL_COMPATIBILITY_CATALOG
        try {
            $env:TOOL_COMPATIBILITY_CATALOG = $catalogPath
            . $helperPath
            $win24 = Get-ToolWindowsReleaseProfile -BuildNumber 26100 -DisplayVersion "24H2" -Ubr 8875
            $win25 = Get-ToolWindowsReleaseProfile -BuildNumber 26200 -DisplayVersion "25H2" -Ubr 9000
            $future = Get-ToolWindowsReleaseProfile -BuildNumber 29999 -DisplayVersion "Future" -Ubr 1
            if (-not $win24.Detected -or $win24.Name -ne "Windows 11 24H2" -or $win24.Currency -ne "MatchesCatalog") {
                Fail "Nhận diện Windows 11 24H2 không đạt."
            }
            if (-not $win25.Detected -or $win25.Currency -ne "AheadOfCatalog") { Fail "Nhận diện Windows 11 25H2 không đạt." }
            if ($future.Detected -or $future.ServicingState -ne "ManualReview") { Fail "Build Windows tương lai không được fail-soft để rà soát." }

            $office2024 = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("ProPlus2024Volume")
            $m365 = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("O365ProPlusRetail")
            if (-not $office2024.Office2024Detected -or $office2024.Microsoft365Detected) { Fail "Phân loại Office 2024 sai." }
            if (-not $m365.Microsoft365Detected -or $m365.Office2024Detected) { Fail "Phân loại Microsoft 365 sai." }
            if ((Compare-ToolOfficeBuild "16.0.20131.20154" "16.0.20131.20154") -ne "MatchesCatalog") { Fail "So sánh build Office sai." }
            if ((Compare-ToolOfficeBuild "16.0.20000.10000" "16.0.20131.20154") -ne "OlderThanCatalog") { Fail "Không nhận ra build Office cũ." }
        } finally {
            $env:TOOL_COMPATIBILITY_CATALOG = $previousCatalog
        }
    } catch {
        Fail "Kiểm thử compatibility thất bại: $($_.Exception.Message)"
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-COMPATIBILITY: FAILED ($($failures.Count) errors)"
    exit 1
}
Write-Host "VERIFY-COMPATIBILITY: OK (Windows 11 24H2/25H2/26H1 + Office 2024/Microsoft 365)" -ForegroundColor Green
exit 0
