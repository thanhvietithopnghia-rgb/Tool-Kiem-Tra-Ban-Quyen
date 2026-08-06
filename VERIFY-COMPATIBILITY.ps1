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
        $catalogVersion = $null
        if ([string]$catalog.SchemaVersion -ne "1.1" -or [string]$catalog.ToolVersion -ne "4.6" -or
            -not [Version]::TryParse([string]$catalog.CatalogVersion, [ref]$catalogVersion)) {
            Fail "Catalog không dùng schema 1.1 / tool 4.6 / CatalogVersion hợp lệ."
        }
        $reviewedAt = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$catalog.ReviewedAtUtc, [ref]$reviewedAt)) {
            Fail "ReviewedAtUtc không hợp lệ."
        } elseif (([DateTime]::UtcNow - $reviewedAt.ToUniversalTime()).TotalDays -gt $MaximumCatalogAgeDays) {
            Fail "Catalog đã quá $MaximumCatalogAgeDays ngày; bắt buộc rà soát lại Microsoft Learn."
        }
        if ([int]$catalog.ReviewWarningAgeDays -lt 1 -or
            [int]$catalog.ReviewWarningAgeDays -ge [int]$catalog.MaximumReviewAgeDays -or
            [int]$catalog.MaximumReviewAgeDays -ne $MaximumCatalogAgeDays) {
            Fail "Chính sách cảnh báo/hết hạn catalog không hợp lệ."
        }

        foreach ($source in @($catalog.Sources.PSObject.Properties)) {
            $uri = $null
            if (-not [uri]::TryCreate([string]$source.Value, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -ne "https" -or $uri.DnsSafeHost -ne "learn.microsoft.com") {
                Fail "Nguồn catalog không thuộc Microsoft Learn HTTPS: $($source.Name)"
            }
        }

        foreach ($expected in @(
            @{ DisplayVersion="22H2"; Build=19045 },
            @{ DisplayVersion="23H2"; Build=22631 },
            @{ DisplayVersion="24H2"; Build=26100 },
            @{ DisplayVersion="25H2"; Build=26200 },
            @{ DisplayVersion="26H1"; Build=28000 }
        )) {
            $match = @($catalog.WindowsReleases | Where-Object {
                [string]$_.DisplayVersion -eq $expected.DisplayVersion -and [int]$_.Build -eq $expected.Build
            })
            if ($match.Count -ne 1) { Fail "Thiếu Windows $($expected.DisplayVersion) build $($expected.Build)." }
        }
        foreach ($productId in @("ProPlus2021Volume", "ProPlus2024Volume", "O365ProPlusRetail", "O365BusinessRetail")) {
            $found = [bool](($catalog.Office2021ProductIds -contains $productId) -or
                ($catalog.Office2024ProductIds -contains $productId) -or
                ($catalog.Microsoft365ProductIds -contains $productId))
            if (-not $found) { Fail "Thiếu Office product ID: $productId" }
        }
        if (@($catalog.OfficeProductFamilies).Count -lt 3) { Fail "Thiếu mô hình OfficeProductFamilies điều khiển bằng dữ liệu." }

        $previousCatalog = [string]$env:TOOL_COMPATIBILITY_CATALOG
        try {
            $env:TOOL_COMPATIBILITY_CATALOG = $catalogPath
            . $helperPath
            Reset-ToolCompatibilityCatalogCache

            $statusFresh = Get-ToolCompatibilityCatalogStatus -NowUtc $reviewedAt.ToUniversalTime().AddDays(1)
            $statusWarning = Get-ToolCompatibilityCatalogStatus -NowUtc $reviewedAt.ToUniversalTime().AddDays([int]$catalog.ReviewWarningAgeDays)
            $statusStale = Get-ToolCompatibilityCatalogStatus -NowUtc $reviewedAt.ToUniversalTime().AddDays([int]$catalog.MaximumReviewAgeDays + 1)
            if ($statusFresh.Health -ne "Fresh" -or $statusFresh.ReviewRecommended) { Fail "Trạng thái catalog Fresh sai." }
            if ($statusWarning.Health -ne "Warning" -or -not $statusWarning.ReviewRecommended) { Fail "Trạng thái Catalog Age Warning sai." }
            if ($statusStale.Health -ne "Stale" -or $statusStale.Fresh) { Fail "Catalog quá hạn không fail-closed đúng." }

            $win10 = Get-ToolWindowsReleaseProfile -BuildNumber 19045 -DisplayVersion "22H2" -Ubr 7548
            $win11 = Get-ToolWindowsReleaseProfile -BuildNumber 26100 -DisplayVersion "24H2" -Ubr 8973
            $ahead = Get-ToolWindowsReleaseProfile -BuildNumber 26200 -DisplayVersion "25H2" -Ubr 9999
            $maximumKnownBuild = [int64](($catalog.WindowsReleases | Measure-Object -Property Build -Maximum).Maximum)
            $future = Get-ToolWindowsReleaseProfile -BuildNumber ($maximumKnownBuild + 1000) -DisplayVersion "Future" -Ubr 1
            if (-not $win10.Detected -or $win10.OperatingSystemFamily -ne "Windows10" -or $win10.Currency -ne "MatchesCatalog") {
                Fail "Nhận diện Windows 10 22H2 không đạt."
            }
            if (-not $win11.Detected -or $win11.Name -ne "Windows 11 24H2" -or $win11.Currency -ne "MatchesCatalog") {
                Fail "Nhận diện Windows 11 24H2 không đạt."
            }
            if (-not $ahead.Detected -or $ahead.Currency -ne "AheadOfCatalog" -or $ahead.AutomaticVersionSensitiveActionsAllowed) {
                Fail "Build Windows vượt catalog chưa chuyển tác vụ nhạy phiên bản sang chỉ đọc."
            }
            if ($future.Detected -or $future.Currency -ne "FutureReleaseUnverified" -or
                $future.CompatibilityMode -ne "ReadOnlyManualReview" -or $future.AutomaticVersionSensitiveActionsAllowed) {
                Fail "Build Windows tương lai không fail-soft/read-only để rà soát."
            }

            $office2021 = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("ProPlus2021Volume")
            $office2024 = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("ProPlus2024Volume")
            $m365 = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("O365ProPlusRetail")
            $futureOffice = Resolve-ToolOfficeProductFamily -ProductReleaseIds @("FutureOfficeRetail")
            if (-not $office2021.Office2021Detected -or $office2021.Office2024Detected) { Fail "Phân loại Office 2021 sai." }
            if (-not $office2024.Office2024Detected -or $office2024.Microsoft365Detected) { Fail "Phân loại Office 2024 sai." }
            if (-not $m365.Microsoft365Detected -or $m365.Office2024Detected) { Fail "Phân loại Microsoft 365 sai." }
            if (-not $futureOffice.RequiresCatalogReview -or @($futureOffice.UnknownProductIds).Count -ne 1) {
                Fail "Product ID Office tương lai không chuyển sang trạng thái chưa xác minh."
            }
            if ((Compare-ToolOfficeBuild "16.0.20228.20158" "16.0.20228.20158") -ne "MatchesCatalog") { Fail "So sánh build Office sai." }
            if ((Compare-ToolOfficeBuild "16.0.20000.10000" "16.0.20228.20158") -ne "OlderThanCatalog") { Fail "Không nhận ra build Office cũ." }

            $metadata = Get-ToolCompatibilityMetadata
            if ([string]$metadata.CatalogSchemaVersion -ne "1.1" -or [string]$metadata.CatalogVersion -ne "1.1.0.0" -or
                [int]$metadata.WindowsReleaseCount -lt 5 -or [int]$metadata.OfficeFamilyCount -lt 3 -or
                [string]$metadata.FutureCompatibilityMode -ne "ReadOnlyManualReview" -or [bool]$metadata.AutomaticRuntimeUpdateCheck) {
                Fail "Metadata vòng đời catalog/tương thích tương lai chưa đầy đủ."
            }
        } finally {
            $env:TOOL_COMPATIBILITY_CATALOG = $previousCatalog
            if (Get-Command Reset-ToolCompatibilityCatalogCache -ErrorAction SilentlyContinue) { Reset-ToolCompatibilityCatalogCache }
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
Write-Host "VERIFY-COMPATIBILITY: OK (catalog lifecycle 1.1 + Windows 10/11 future-safe + Office 2021/2024/Microsoft 365)" -ForegroundColor Green
exit 0
