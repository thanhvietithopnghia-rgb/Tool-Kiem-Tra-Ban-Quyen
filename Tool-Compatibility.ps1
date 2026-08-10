$script:ToolCompatibilitySchemaVersion = "1.0"
$script:ToolCompatibilityToolVersion = "4.8"
$script:ToolCompatibilityCatalogSchemaVersions = @("1.0", "1.1")
$script:ToolCompatibilityCatalogCache = $null
$script:ToolCompatibilityCatalogCachePath = ""

$toolCompatibilityLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolCompatibilityLocalizationPath -PathType Leaf)) {
    . $toolCompatibilityLocalizationPath
}

function Reset-ToolCompatibilityCatalogCache {
    $script:ToolCompatibilityCatalogCache = $null
    $script:ToolCompatibilityCatalogCachePath = ""
}

function Get-ToolCompatibilityCatalogPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_COMPATIBILITY_CATALOG)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$env:TOOL_COMPATIBILITY_CATALOG))
    }
    return Join-Path $PSScriptRoot "compatibility-catalog-v1.0.json"
}

function Get-ToolCompatibilityOfficeFamilyDefinitions {
    param([Parameter(Mandatory = $true)]$Catalog)

    $definitions = New-Object System.Collections.Generic.List[object]
    if ($Catalog.PSObject.Properties["OfficeProductFamilies"] -and @($Catalog.OfficeProductFamilies).Count -gt 0) {
        foreach ($family in @($Catalog.OfficeProductFamilies)) {
            $propertyName = [string]$family.ProductIdProperty
            $property = if ($propertyName) { $Catalog.PSObject.Properties[$propertyName] } else { $null }
            $productIds = if ($property) { @($property.Value) } else { @() }
            [void]$definitions.Add([pscustomobject][ordered]@{
                Id = [string]$family.Id
                Name = [string]$family.Name
                ProductIdProperty = $propertyName
                LicenseModel = [string]$family.LicenseModel
                ProductIds = @($productIds)
            })
        }
    } else {
        [void]$definitions.Add([pscustomobject][ordered]@{
            Id = "office-2024"; Name = "Office 2024 / LTSC 2024"; ProductIdProperty = "Office2024ProductIds"
            LicenseModel = "Perpetual"; ProductIds = @($Catalog.Office2024ProductIds)
        })
        [void]$definitions.Add([pscustomobject][ordered]@{
            Id = "microsoft-365"; Name = "Microsoft 365 Apps"; ProductIdProperty = "Microsoft365ProductIds"
            LicenseModel = "Subscription"; ProductIds = @($Catalog.Microsoft365ProductIds)
        })
    }
    return @($definitions.ToArray())
}

function Get-ToolCompatibilityCatalog {
    $path = Get-ToolCompatibilityCatalogPath
    if ($script:ToolCompatibilityCatalogCache -and $script:ToolCompatibilityCatalogCachePath -eq $path) {
        return $script:ToolCompatibilityCatalogCache
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (Get-ToolTextCurrent "foundation.compatibility.catalogMissing" @($path)) }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 2 -or $item.Length -gt 524288) {
        throw (Get-ToolTextCurrent "foundation.compatibility.catalogUnsafe")
    }
    $catalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($script:ToolCompatibilityCatalogSchemaVersions -notcontains [string]$catalog.SchemaVersion) {
        throw (Get-ToolTextCurrent "foundation.compatibility.schemaInvalid" @($catalog.SchemaVersion))
    }
    if (-not $catalog.WindowsReleases -or -not $catalog.Microsoft365Channels) {
        throw (Get-ToolTextCurrent "foundation.compatibility.categoriesMissing")
    }

    $reviewedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$catalog.ReviewedAtUtc, [ref]$reviewedAt)) {
        throw (Get-ToolTextCurrent "foundation.compatibility.reviewedAtInvalid")
    }
    $reviewedAtUtc = $reviewedAt.ToUniversalTime()
    if ($reviewedAtUtc -gt [DateTime]::UtcNow.AddDays(1)) {
        throw (Get-ToolTextCurrent "foundation.compatibility.reviewedAtFuture")
    }
    $maximumAgeDays = [int]$catalog.MaximumReviewAgeDays
    $warningAgeDays = if ($catalog.PSObject.Properties["ReviewWarningAgeDays"]) { [int]$catalog.ReviewWarningAgeDays } else { [Math]::Max(1, $maximumAgeDays - 15) }
    if ($maximumAgeDays -lt 2 -or $maximumAgeDays -gt 180 -or $warningAgeDays -lt 1 -or $warningAgeDays -ge $maximumAgeDays) {
        throw (Get-ToolTextCurrent "foundation.compatibility.agePolicyInvalid")
    }

    $allowedHosts = @("learn.microsoft.com")
    if ($catalog.PSObject.Properties["SourcePolicy"] -and $catalog.SourcePolicy.PSObject.Properties["AllowedHosts"]) {
        $allowedHosts = @($catalog.SourcePolicy.AllowedHosts | ForEach-Object { ([string]$_).ToLowerInvariant() })
    }
    $sources = @($catalog.Sources.PSObject.Properties)
    if ($sources.Count -lt 1 -or $sources.Count -gt 32) { throw (Get-ToolTextCurrent "foundation.compatibility.sourceInvalid") }
    foreach ($source in $sources) {
        $uri = $null
        if (-not [uri]::TryCreate([string]$source.Value, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -ne "https" -or $allowedHosts -notcontains $uri.DnsSafeHost.ToLowerInvariant()) {
            throw (Get-ToolTextCurrent "foundation.compatibility.sourceInvalid")
        }
    }

    $seenBuilds = @{}
    foreach ($release in @($catalog.WindowsReleases)) {
        $build = [int64]$release.Build
        if ([string]::IsNullOrWhiteSpace([string]$release.Name) -or
            [string]::IsNullOrWhiteSpace([string]$release.DisplayVersion) -or
            $build -le 0 -or [int64]$release.LatestKnownRevision -lt 0 -or $seenBuilds.ContainsKey([string]$build)) {
            throw (Get-ToolTextCurrent "foundation.compatibility.releaseInvalid")
        }
        $seenBuilds[[string]$build] = $true
    }

    $officeFamilies = @(Get-ToolCompatibilityOfficeFamilyDefinitions -Catalog $catalog)
    if ($officeFamilies.Count -lt 1 -or $officeFamilies.Count -gt 20) {
        throw (Get-ToolTextCurrent "foundation.compatibility.categoriesMissing")
    }
    $knownOfficeIds = @{}
    foreach ($family in $officeFamilies) {
        if ([string]::IsNullOrWhiteSpace([string]$family.Id) -or
            [string]::IsNullOrWhiteSpace([string]$family.Name) -or @($family.ProductIds).Count -eq 0 -or @($family.ProductIds).Count -gt 500) {
            throw (Get-ToolTextCurrent "foundation.compatibility.officeFamilyInvalid")
        }
        foreach ($productId in @($family.ProductIds)) {
            $id = [string]$productId
            if ([string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 128 -or $knownOfficeIds.ContainsKey($id)) {
                throw (Get-ToolTextCurrent "foundation.compatibility.officeFamilyInvalid")
            }
            $knownOfficeIds[$id] = [string]$family.Id
        }
    }

    $seenChannels = @{}
    foreach ($channel in @($catalog.Microsoft365Channels)) {
        $id = [string]$channel.Id
        $buildVersion = $null
        if ([string]::IsNullOrWhiteSpace($id) -or $seenChannels.ContainsKey($id) -or
            -not [Version]::TryParse([string]$channel.LatestKnownBuild, [ref]$buildVersion)) {
            throw (Get-ToolTextCurrent "foundation.compatibility.channelInvalid")
        }
        $seenChannels[$id] = $true
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
    $maximumAgeDays = [Math]::Max(2, [int]$catalog.MaximumReviewAgeDays)
    $warningAgeDays = if ($catalog.PSObject.Properties["ReviewWarningAgeDays"]) { [int]$catalog.ReviewWarningAgeDays } else { [Math]::Max(1, $maximumAgeDays - 15) }
    $health = if ($ageDays -gt $maximumAgeDays) { "Stale" } elseif ($ageDays -ge $warningAgeDays) { "Warning" } else { "Fresh" }
    return [pscustomobject][ordered]@{
        CatalogVersion = if ($catalog.PSObject.Properties["CatalogVersion"]) { [string]$catalog.CatalogVersion } else { "1.0.0.0" }
        CatalogSchemaVersion = [string]$catalog.SchemaVersion
        ReviewedAtUtc = $reviewedAt.ToString("o")
        AgeDays = $ageDays
        ReviewWarningAgeDays = $warningAgeDays
        MaximumReviewAgeDays = $maximumAgeDays
        ExpiresAtUtc = $reviewedAt.AddDays($maximumAgeDays).ToString("o")
        Health = $health
        Fresh = [bool]($health -ne "Stale")
        ReviewRecommended = [bool]($health -ne "Fresh")
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
        $requiresReview = [bool]($catalogStatus.ReviewRecommended -or $currency -in @("RevisionUnknown", "AheadOfCatalog"))
        $compatibilityMode = if ($catalogStatus.Health -eq "Stale") {
            "ReadOnlyCatalogStale"
        } elseif ($currency -eq "AheadOfCatalog") {
            "ReadOnlyAheadOfCatalog"
        } elseif ($currency -eq "RevisionUnknown") {
            "ReadOnlyRevisionUnknown"
        } else {
            "Normal"
        }
        return [pscustomobject][ordered]@{
            Detected = $true
            Name = [string]$release.Name
            OperatingSystemFamily = if ($release.PSObject.Properties["OperatingSystemFamily"]) { [string]$release.OperatingSystemFamily } elseif ($BuildNumber -ge 22000) { "Windows11" } else { "Windows10" }
            DisplayVersion = [string]$release.DisplayVersion
            Build = [int64]$BuildNumber
            Revision = [int64]$Ubr
            FullBuild = if ($Ubr -gt 0) { "$BuildNumber.$Ubr" } else { [string]$BuildNumber }
            ServicingState = [string]$release.ServicingState
            CatalogLatestBuild = "$([int64]$release.Build).$knownRevision"
            Currency = $currency
            CatalogHealth = [string]$catalogStatus.Health
            CatalogFresh = [bool]$catalogStatus.Fresh
            RequiresCatalogReview = $requiresReview
            CompatibilityMode = $compatibilityMode
            AutomaticVersionSensitiveActionsAllowed = [bool](-not $requiresReview)
        }
    }

    $latestKnownBuild = [int64](($catalog.WindowsReleases | Measure-Object -Property Build -Maximum).Maximum)
    $isWindows11 = [bool]($BuildNumber -ge 22000)
    $isWindows10 = [bool]($BuildNumber -ge 10240 -and $BuildNumber -lt 22000)
    $futureRelease = [bool]($BuildNumber -gt $latestKnownBuild)
    return [pscustomobject][ordered]@{
        Detected = $false
        Name = if ($isWindows11) { Get-ToolTextCurrent "foundation.compatibility.windows11UnknownBuild" } elseif ($isWindows10) { Get-ToolTextCurrent "foundation.compatibility.windows10UnknownBuild" } else { "Windows legacy" }
        OperatingSystemFamily = if ($isWindows11) { "Windows11" } elseif ($isWindows10) { "Windows10" } else { "WindowsLegacy" }
        DisplayVersion = $DisplayVersion
        Build = [int64]$BuildNumber
        Revision = [int64]$Ubr
        FullBuild = if ($Ubr -gt 0) { "$BuildNumber.$Ubr" } else { [string]$BuildNumber }
        ServicingState = if ($isWindows11 -or $isWindows10) { "ManualReview" } else { "Legacy" }
        CatalogLatestBuild = ""
        Currency = if ($futureRelease) { "FutureReleaseUnverified" } else { "UnknownRelease" }
        CatalogHealth = [string]$catalogStatus.Health
        CatalogFresh = [bool]$catalogStatus.Fresh
        RequiresCatalogReview = $true
        CompatibilityMode = "ReadOnlyManualReview"
        AutomaticVersionSensitiveActionsAllowed = $false
    }
}

function Resolve-ToolOfficeProductFamily {
    param([AllowNull()][string[]]$ProductReleaseIds)
    $catalog = Get-ToolCompatibilityCatalog
    $ids = @($ProductReleaseIds | ForEach-Object {
        @([string]$_ -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } | Select-Object -Unique)
    $definitions = @(Get-ToolCompatibilityOfficeFamilyDefinitions -Catalog $catalog)
    $matches = New-Object System.Collections.Generic.List[object]
    $knownIds = @{}
    foreach ($definition in $definitions) {
        foreach ($productId in @($definition.ProductIds)) { $knownIds[[string]$productId] = [string]$definition.Id }
        $matchedIds = @($ids | Where-Object { @($definition.ProductIds) -contains $_ })
        if ($matchedIds.Count -gt 0) {
            [void]$matches.Add([pscustomobject][ordered]@{
                Id = [string]$definition.Id
                Name = [string]$definition.Name
                LicenseModel = [string]$definition.LicenseModel
                ProductIds = @($matchedIds)
            })
        }
    }
    $unknownIds = @($ids | Where-Object { -not $knownIds.ContainsKey([string]$_) })
    $matchedNames = @($matches.ToArray() | ForEach-Object { [string]$_.Name })
    $family = if ($matchedNames.Count -gt 0) {
        $matchedNames -join " + "
    } elseif ($ids.Count -gt 0) {
        "Office Click-to-Run (unverified product IDs)"
    } else {
        "Not detected"
    }
    $matchedFamilyIds = @($matches.ToArray() | ForEach-Object { [string]$_.Id })
    return [pscustomobject][ordered]@{
        Family = $family
        ProductReleaseIds = @($ids)
        MatchedFamilyIds = @($matchedFamilyIds)
        MatchedFamilies = @($matches.ToArray())
        UnknownProductIds = @($unknownIds)
        Office2021ProductIds = @($matches.ToArray() | Where-Object { $_.Id -eq "office-2021" } | ForEach-Object { @($_.ProductIds) })
        Office2024ProductIds = @($matches.ToArray() | Where-Object { $_.Id -eq "office-2024" } | ForEach-Object { @($_.ProductIds) })
        Microsoft365ProductIds = @($matches.ToArray() | Where-Object { $_.Id -eq "microsoft-365" } | ForEach-Object { @($_.ProductIds) })
        Office2021Detected = [bool]($matchedFamilyIds -contains "office-2021")
        Office2024Detected = [bool]($matchedFamilyIds -contains "office-2024")
        Microsoft365Detected = [bool]($matchedFamilyIds -contains "microsoft-365")
        RequiresCatalogReview = [bool]($unknownIds.Count -gt 0)
        CatalogDriven = $true
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
    $catalogStatus = Get-ToolCompatibilityCatalogStatus
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
            UnknownProductIds = @()
            Version = ""
            Platform = ""
            Channel = "Not detected"
            ChannelId = ""
            CatalogLatestVersion = ""
            CatalogLatestBuild = ""
            Currency = "NotDetected"
            CatalogHealth = [string]$catalogStatus.Health
            RequiresCatalogReview = [bool]$catalogStatus.ReviewRecommended
            CompatibilityMode = if ($catalogStatus.Health -eq "Stale") { "ReadOnlyCatalogStale" } else { "Normal" }
            AutomaticVersionSensitiveActionsAllowed = [bool](-not $catalogStatus.ReviewRecommended)
            RegistryPath = ""
        }
    }

    $family = Resolve-ToolOfficeProductFamily -ProductReleaseIds @([string]$configuration.ProductReleaseIds)
    $channel = Resolve-ToolMicrosoft365Channel -UpdateChannel ([string]$configuration.UpdateChannel)
    $catalogBuild = if ($channel) { [string]$channel.LatestKnownBuild } else { "" }
    $requiresReview = [bool]($catalogStatus.ReviewRecommended -or $family.RequiresCatalogReview -or ($family.Microsoft365Detected -and -not $channel))
    return [pscustomobject][ordered]@{
        Detected = $true
        Family = [string]$family.Family
        ProductReleaseIds = @($family.ProductReleaseIds)
        MatchedFamilyIds = @($family.MatchedFamilyIds)
        UnknownProductIds = @($family.UnknownProductIds)
        Office2021Detected = [bool]$family.Office2021Detected
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
        CatalogHealth = [string]$catalogStatus.Health
        RequiresCatalogReview = $requiresReview
        CompatibilityMode = if ($requiresReview) { "ReadOnlyManualReview" } else { "Normal" }
        AutomaticVersionSensitiveActionsAllowed = [bool](-not $requiresReview)
        RegistryPath = $sourcePath
    }
}

function Get-ToolCompatibilityMetadata {
    $catalog = Get-ToolCompatibilityCatalog
    $status = Get-ToolCompatibilityCatalogStatus
    $officeFamilies = @(Get-ToolCompatibilityOfficeFamilyDefinitions -Catalog $catalog)
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolCompatibilitySchemaVersion
        ToolVersion = $script:ToolCompatibilityToolVersion
        CatalogSchemaVersion = [string]$catalog.SchemaVersion
        CatalogVersion = [string]$status.CatalogVersion
        ReviewedAtUtc = [string]$status.ReviewedAtUtc
        CatalogAgeDays = [int]$status.AgeDays
        CatalogHealth = [string]$status.Health
        CatalogFresh = [bool]$status.Fresh
        CatalogReviewRecommended = [bool]$status.ReviewRecommended
        ReviewWarningAgeDays = [int]$status.ReviewWarningAgeDays
        MaximumReviewAgeDays = [int]$status.MaximumReviewAgeDays
        CatalogExpiresAtUtc = [string]$status.ExpiresAtUtc
        WindowsReleaseCount = [int]@($catalog.WindowsReleases).Count
        WindowsReleaseNames = @($catalog.WindowsReleases | ForEach-Object { "$([string]$_.Name) build $([int64]$_.Build)" })
        OfficeFamilyCount = [int]$officeFamilies.Count
        OfficeFamilyNames = @($officeFamilies | ForEach-Object { [string]$_.Name })
        Office2021ProductIdCount = if ($catalog.PSObject.Properties["Office2021ProductIds"]) { [int]@($catalog.Office2021ProductIds).Count } else { 0 }
        Office2024ProductIdCount = [int]@($catalog.Office2024ProductIds).Count
        Microsoft365ProductIdCount = [int]@($catalog.Microsoft365ProductIds).Count
        Microsoft365ChannelCount = [int]@($catalog.Microsoft365Channels).Count
        RuntimeNetworkRequired = $false
        AutomaticRuntimeUpdateCheck = $false
        FutureCompatibilityMode = "ReadOnlyManualReview"
    }
}
