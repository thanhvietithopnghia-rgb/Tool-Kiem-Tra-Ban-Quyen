$script:ToolCompatibilitySchemaVersion = "1.0"
$script:ToolCompatibilityToolVersion = "4.4"
$script:ToolCompatibilityCatalogCache = $null
$script:ToolCompatibilityCatalogCachePath = ""

function Get-ToolCompatibilityCatalogPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_COMPATIBILITY_CATALOG)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$env:TOOL_COMPATIBILITY_CATALOG))
    }
    return Join-Path $PSScriptRoot "compatibility-catalog-v1.0.json"
}

function Get-ToolCompatibilityCatalog {
    $path = Get-ToolCompatibilityCatalogPath
    if ($script:ToolCompatibilityCatalogCache -and $script:ToolCompatibilityCatalogCachePath -eq $path) {
        return $script:ToolCompatibilityCatalogCache
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu compatibility catalog: $path" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 2 -or $item.Length -gt 524288) {
        throw "Compatibility catalog không an toàn hoặc vượt giới hạn."
    }
    $catalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$catalog.SchemaVersion -ne $script:ToolCompatibilitySchemaVersion) {
        throw "Compatibility catalog sai schema: $($catalog.SchemaVersion)"
    }
    if (-not $catalog.WindowsReleases -or -not $catalog.Office2024ProductIds -or -not $catalog.Microsoft365ProductIds) {
        throw "Compatibility catalog thiếu danh mục bắt buộc."
    }
    $reviewedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$catalog.ReviewedAtUtc, [ref]$reviewedAt)) {
        throw "Compatibility catalog có ReviewedAtUtc không hợp lệ."
    }
    $script:ToolCompatibilityCatalogCache = $catalog
    $script:ToolCompatibilityCatalogCachePath = $path
    return $catalog
}

function Get-ToolCompatibilityCatalogStatus {
    param([DateTime]$NowUtc = [DateTime]::UtcNow)
    $catalog = Get-ToolCompatibilityCatalog
    $reviewedAt = [DateTime]::Parse([string]$catalog.ReviewedAtUtc).ToUniversalTime()
    $ageDays = [Math]::Max(0, [int][Math]::Floor(($NowUtc.ToUniversalTime() - $reviewedAt).TotalDays))
    $maximumAgeDays = [Math]::Max(1, [int]$catalog.MaximumReviewAgeDays)
    return [pscustomobject][ordered]@{
        ReviewedAtUtc = $reviewedAt.ToString("o")
        AgeDays = $ageDays
        MaximumReviewAgeDays = $maximumAgeDays
        Fresh = [bool]($ageDays -le $maximumAgeDays)
        SourceCount = [int]@($catalog.Sources.PSObject.Properties).Count
    }
}

function Get-ToolWindowsReleaseProfile {
    param(
        [Parameter(Mandatory = $true)][int64]$BuildNumber,
        [string]$DisplayVersion = "",
        [int64]$Ubr = 0
    )
    $catalog = Get-ToolCompatibilityCatalog
    $catalogStatus = Get-ToolCompatibilityCatalogStatus
    $match = @($catalog.WindowsReleases | Where-Object {
        [int64]$_.Build -eq $BuildNumber -or
        (-not [string]::IsNullOrWhiteSpace($DisplayVersion) -and [string]$_.DisplayVersion -eq $DisplayVersion)
    } | Select-Object -First 1)

    if ($match.Count -eq 1) {
        $release = $match[0]
        $knownRevision = [int64]$release.LatestKnownRevision
        $currency = if ($Ubr -le 0) {
            "RevisionUnknown"
        } elseif ($Ubr -lt $knownRevision) {
            "OlderThanCatalog"
        } elseif ($Ubr -eq $knownRevision) {
            "MatchesCatalog"
        } else {
            "AheadOfCatalog"
        }
        return [pscustomobject][ordered]@{
            Detected = $true
            Name = [string]$release.Name
            DisplayVersion = [string]$release.DisplayVersion
            Build = [int64]$BuildNumber
            Revision = [int64]$Ubr
            FullBuild = if ($Ubr -gt 0) { "$BuildNumber.$Ubr" } else { [string]$BuildNumber }
            ServicingState = [string]$release.ServicingState
            CatalogLatestBuild = "$([int64]$release.Build).$knownRevision"
            Currency = $currency
            CatalogFresh = [bool]$catalogStatus.Fresh
        }
    }

    $isWindows11 = [bool]($BuildNumber -ge 22000)
    return [pscustomobject][ordered]@{
        Detected = $false
        Name = if ($isWindows11) { "Windows 11 (build mới/chưa có trong catalog)" } else { "Windows legacy" }
        DisplayVersion = $DisplayVersion
        Build = [int64]$BuildNumber
        Revision = [int64]$Ubr
        FullBuild = if ($Ubr -gt 0) { "$BuildNumber.$Ubr" } else { [string]$BuildNumber }
        ServicingState = if ($isWindows11) { "ManualReview" } else { "Legacy" }
        CatalogLatestBuild = ""
        Currency = "UnknownRelease"
        CatalogFresh = [bool]$catalogStatus.Fresh
    }
}

function Resolve-ToolOfficeProductFamily {
    param([AllowNull()][string[]]$ProductReleaseIds)
    $catalog = Get-ToolCompatibilityCatalog
    $ids = @($ProductReleaseIds | ForEach-Object {
        @([string]$_ -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } | Select-Object -Unique)
    $office2024 = @($ids | Where-Object { $catalog.Office2024ProductIds -contains $_ })
    $microsoft365 = @($ids | Where-Object { $catalog.Microsoft365ProductIds -contains $_ })
    $family = if ($microsoft365.Count -gt 0 -and $office2024.Count -gt 0) {
        "Microsoft 365 + Office 2024 components"
    } elseif ($microsoft365.Count -gt 0) {
        "Microsoft 365 Apps"
    } elseif ($office2024.Count -gt 0) {
        "Office 2024 / LTSC 2024"
    } elseif ($ids.Count -gt 0) {
        "Office Click-to-Run"
    } else {
        "Not detected"
    }
    return [pscustomobject][ordered]@{
        Family = $family
        ProductReleaseIds = @($ids)
        Office2024ProductIds = @($office2024)
        Microsoft365ProductIds = @($microsoft365)
        Office2024Detected = [bool]($office2024.Count -gt 0)
        Microsoft365Detected = [bool]($microsoft365.Count -gt 0)
    }
}

function Resolve-ToolMicrosoft365Channel {
    param([AllowNull()][string]$UpdateChannel)
    $catalog = Get-ToolCompatibilityCatalog
    $channel = @($catalog.Microsoft365Channels | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$UpdateChannel) -and
        [string]$UpdateChannel -match [regex]::Escape([string]$_.Id)
    } | Select-Object -First 1)
    if ($channel.Count -eq 1) { return $channel[0] }
    return $null
}

function Compare-ToolOfficeBuild {
    param(
        [AllowNull()][string]$InstalledBuild,
        [AllowNull()][string]$CatalogBuild
    )
    $installed = $null
    $expected = $null
    if (-not [Version]::TryParse([string]$InstalledBuild, [ref]$installed) -or
        -not [Version]::TryParse([string]$CatalogBuild, [ref]$expected)) {
        return "Unknown"
    }
    if ($installed -lt $expected) { return "OlderThanCatalog" }
    if ($installed -gt $expected) { return "AheadOfCatalog" }
    return "MatchesCatalog"
}

function Get-ToolOfficeCompatibilityProfile {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"
    )
    $configuration = $null
    $sourcePath = ""
    foreach ($path in $registryPaths) {
        try {
            $candidate = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            if ($candidate) {
                $configuration = $candidate
                $sourcePath = $path
                break
            }
        } catch {}
    }
    if (-not $configuration) {
        return [pscustomobject][ordered]@{
            Detected = $false
            Family = "Not detected"
            ProductReleaseIds = @()
            Version = ""
            Platform = ""
            Channel = "Not detected"
            ChannelId = ""
            CatalogLatestVersion = ""
            CatalogLatestBuild = ""
            Currency = "NotDetected"
            RegistryPath = ""
        }
    }

    $family = Resolve-ToolOfficeProductFamily -ProductReleaseIds @([string]$configuration.ProductReleaseIds)
    $channel = Resolve-ToolMicrosoft365Channel -UpdateChannel ([string]$configuration.UpdateChannel)
    $catalogBuild = if ($channel) { [string]$channel.LatestKnownBuild } else { "" }
    return [pscustomobject][ordered]@{
        Detected = $true
        Family = [string]$family.Family
        ProductReleaseIds = @($family.ProductReleaseIds)
        Office2024Detected = [bool]$family.Office2024Detected
        Microsoft365Detected = [bool]$family.Microsoft365Detected
        Version = [string]$configuration.ClientVersionToReport
        Platform = [string]$configuration.Platform
        Channel = if ($channel) { [string]$channel.Name } else { "Unknown / managed" }
        ChannelId = if ($channel) { [string]$channel.Id } else { "" }
        CatalogLatestVersion = if ($channel) { [string]$channel.LatestKnownVersion } else { "" }
        CatalogLatestBuild = $catalogBuild
        Currency = if ($family.Microsoft365Detected -and $channel) {
            Compare-ToolOfficeBuild -InstalledBuild ([string]$configuration.ClientVersionToReport) -CatalogBuild $catalogBuild
        } else {
            "NotApplicable"
        }
        RegistryPath = $sourcePath
    }
}

function Get-ToolCompatibilityMetadata {
    $catalog = Get-ToolCompatibilityCatalog
    $status = Get-ToolCompatibilityCatalogStatus
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolCompatibilitySchemaVersion
        ToolVersion = $script:ToolCompatibilityToolVersion
        CatalogSchemaVersion = [string]$catalog.SchemaVersion
        ReviewedAtUtc = [string]$status.ReviewedAtUtc
        CatalogFresh = [bool]$status.Fresh
        MaximumReviewAgeDays = [int]$status.MaximumReviewAgeDays
        WindowsReleaseCount = [int]@($catalog.WindowsReleases).Count
        Office2024ProductIdCount = [int]@($catalog.Office2024ProductIds).Count
        Microsoft365ProductIdCount = [int]@($catalog.Microsoft365ProductIds).Count
        Microsoft365ChannelCount = [int]@($catalog.Microsoft365Channels).Count
        RuntimeNetworkRequired = $false
    }
}
