[CmdletBinding()]
param(
    [string]$SourceDirectory = "",
    [string]$OutputFile = "",
    [switch]$SkipNetwork,
    [switch]$FailOnReviewRequired
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$catalogPath = Join-Path $root "compatibility-catalog-v1.0.json"
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "Missing compatibility catalog: $catalogPath" }
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '') }
    finally { $algorithm.Dispose() }
}

function ConvertTo-ComparablePageText {
    param([Parameter(Mandatory = $true)][string]$Html)
    $withoutScripts = [regex]::Replace($Html, '(?is)<(script|style)[^>]*>.*?</\1>', ' ')
    $withoutTags = [regex]::Replace($withoutScripts, '(?s)<[^>]+>', ' ')
    return [Net.WebUtility]::HtmlDecode(([regex]::Replace($withoutTags, '\s+', ' ')))
}

function Get-ExpectedSourceTokens {
    param([Parameter(Mandatory = $true)][string]$SourceName)
    $tokens = New-Object System.Collections.Generic.List[string]
    switch ($SourceName) {
        "WindowsReleaseHealth" {
            foreach ($release in @($catalog.WindowsReleases | Where-Object { [string]$_.OperatingSystemFamily -ne "Windows10" })) {
                [void]$tokens.Add([string]$release.DisplayVersion)
                [void]$tokens.Add("$([int64]$release.Build).$([int64]$release.LatestKnownRevision)")
            }
        }
        "Windows10ReleaseHealth" {
            foreach ($release in @($catalog.WindowsReleases | Where-Object { [string]$_.OperatingSystemFamily -eq "Windows10" })) {
                [void]$tokens.Add([string]$release.DisplayVersion)
                [void]$tokens.Add("$([int64]$release.Build).$([int64]$release.LatestKnownRevision)")
            }
        }
        "Office2024Overview" { [void]$tokens.Add("Office LTSC 2024") }
        "OfficeProductIds" {
            foreach ($propertyName in @("Office2021ProductIds", "Office2024ProductIds", "Microsoft365ProductIds")) {
                $property = $catalog.PSObject.Properties[$propertyName]
                if ($property) { foreach ($productId in @($property.Value)) { [void]$tokens.Add([string]$productId) } }
            }
        }
        "Microsoft365UpdateHistory" {
            foreach ($channel in @($catalog.Microsoft365Channels)) {
                [void]$tokens.Add([string]$channel.Name)
                [void]$tokens.Add(([string]$channel.LatestKnownBuild -replace '^16\.0\.', ''))
            }
        }
        "Microsoft365Channels" {
            foreach ($channel in @($catalog.Microsoft365Channels)) { [void]$tokens.Add([string]$channel.Name) }
        }
    }
    return @($tokens.ToArray() | Where-Object { $_ } | Select-Object -Unique)
}

$reviewReasons = New-Object System.Collections.Generic.List[string]
$sourceResults = New-Object System.Collections.Generic.List[object]
$allowedHosts = @("learn.microsoft.com")
if ($catalog.PSObject.Properties["SourcePolicy"] -and $catalog.SourcePolicy.PSObject.Properties["AllowedHosts"]) {
    $allowedHosts = @($catalog.SourcePolicy.AllowedHosts | ForEach-Object { ([string]$_).ToLowerInvariant() })
}

foreach ($source in @($catalog.Sources.PSObject.Properties)) {
    $sourceName = [string]$source.Name
    $sourceUrl = [string]$source.Value
    $uri = $null
    if (-not [uri]::TryCreate($sourceUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne "https" -or $allowedHosts -notcontains $uri.DnsSafeHost.ToLowerInvariant()) {
        throw "Catalog source is outside the allowed Microsoft HTTPS hosts: $sourceName"
    }

    $statusCode = 0
    $content = ""
    $missingTokens = @()
    $sourceReviewReasons = New-Object System.Collections.Generic.List[string]
    $etag = ""
    $lastModified = ""
    if (-not $SkipNetwork) {
        try {
            $response = Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 45 -Headers @{ "Accept-Language"="en-US"; "User-Agent"="ThanhViet-Tool-Kiem-Tra-Catalog-Review/1.0" }
            $statusCode = [int]$response.StatusCode
            if ($statusCode -lt 200 -or $statusCode -ge 400) { throw "HTTP $statusCode" }
            $content = [string]$response.Content
            $etag = [string]$response.Headers["ETag"]
            $lastModified = [string]$response.Headers["Last-Modified"]
            $missingTokens = @(Get-ExpectedSourceTokens -SourceName $sourceName | Where-Object { $content.IndexOf([string]$_, [StringComparison]::OrdinalIgnoreCase) -lt 0 })
            if ($missingTokens.Count -gt 0) {
                [void]$sourceReviewReasons.Add("Expected catalog values missing from Microsoft source: $($missingTokens -join ', ')")
            }

            if ($sourceName -in @("WindowsReleaseHealth", "Windows10ReleaseHealth")) {
                $pageText = ConvertTo-ComparablePageText -Html $content
                $knownBuilds = @{}
                foreach ($release in @($catalog.WindowsReleases)) { $knownBuilds[[string]([int64]$release.Build)] = $release }
                $highestKnownBuild = [int64](($catalog.WindowsReleases | Measure-Object -Property Build -Maximum).Maximum)
                foreach ($releaseMatch in [regex]::Matches($pageText, 'Version\s+(?<version>\d{2}H[12])\s+\(OS build\s+(?<build>\d{4,6})\)', 'IgnoreCase')) {
                    $discoveredBuild = [string]$releaseMatch.Groups["build"].Value
                    if (-not $knownBuilds.ContainsKey($discoveredBuild) -and [int64]$discoveredBuild -gt $highestKnownBuild) {
                        [void]$sourceReviewReasons.Add("New Windows release candidate: $($releaseMatch.Groups['version'].Value) build $discoveredBuild")
                    }
                }
                foreach ($knownBuild in @($knownBuilds.Keys)) {
                    $revisionMatches = [regex]::Matches($pageText, "(?<!\d)$([regex]::Escape($knownBuild))\.(?<revision>\d+)(?!\d)")
                    if ($revisionMatches.Count -gt 0) {
                        $latestObservedRevision = [int64](($revisionMatches | ForEach-Object { [int64]$_.Groups["revision"].Value } | Measure-Object -Maximum).Maximum)
                        $catalogRevision = [int64]$knownBuilds[$knownBuild].LatestKnownRevision
                        if ($latestObservedRevision -gt $catalogRevision) {
                            [void]$sourceReviewReasons.Add("New Windows revision candidate: $knownBuild.$latestObservedRevision (catalog $knownBuild.$catalogRevision)")
                        }
                    }
                }
            }

            if ($sourceName -eq "Microsoft365UpdateHistory") {
                $pageText = ConvertTo-ComparablePageText -Html $content
                foreach ($channel in @($catalog.Microsoft365Channels | Where-Object { [string]$_.Name -in @("Current Channel", "Monthly Enterprise Channel") })) {
                    $channelName = [regex]::Escape([string]$channel.Name)
                    $match = [regex]::Match($pageText, "$channelName\s+(?<version>\d{4})\s+(?<build>\d{4,6}\.\d{4,6})", "IgnoreCase")
                    if ($match.Success) {
                        $observedVersion = [string]$match.Groups["version"].Value
                        $observedBuild = "16.0.$([string]$match.Groups['build'].Value)"
                        if ($observedVersion -ne [string]$channel.LatestKnownVersion -or $observedBuild -ne [string]$channel.LatestKnownBuild) {
                            [void]$sourceReviewReasons.Add("Microsoft 365 channel changed: $($channel.Name) $observedVersion/$observedBuild")
                        }
                    }
                }
            }
        } catch {
            throw "Microsoft source check failed for ${sourceName}: $($_.Exception.Message)"
        }
    }

    foreach ($reason in $sourceReviewReasons.ToArray()) { [void]$reviewReasons.Add("${sourceName}: $reason") }
    [void]$sourceResults.Add([pscustomobject][ordered]@{
        Name = $sourceName
        Url = $uri.AbsoluteUri
        StatusCode = $statusCode
        ETag = $etag
        LastModified = $lastModified
        ContentLength = [Text.Encoding]::UTF8.GetByteCount($content)
        ContentSha256 = if ($content) { Get-TextSha256 -Text $content } else { "" }
        MissingExpectedTokens = @($missingTokens)
        ReviewReasons = @($sourceReviewReasons.ToArray())
    })
}

$reviewedAt = [DateTime]::Parse([string]$catalog.ReviewedAtUtc).ToUniversalTime()
$catalogAgeDays = [Math]::Max(0, [int][Math]::Floor(([DateTime]::UtcNow - $reviewedAt).TotalDays))
$warningAgeDays = if ($catalog.PSObject.Properties["ReviewWarningAgeDays"]) { [int]$catalog.ReviewWarningAgeDays } else { 30 }
if ($catalogAgeDays -ge $warningAgeDays) { [void]$reviewReasons.Add("Catalog age reached the review warning threshold: $catalogAgeDays/$warningAgeDays days") }

$report = [pscustomobject][ordered]@{
    SchemaVersion = "1.0"
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    CatalogPath = $catalogPath
    CatalogSchemaVersion = [string]$catalog.SchemaVersion
    CatalogVersion = [string]$catalog.CatalogVersion
    CatalogReviewedAtUtc = $reviewedAt.ToString("o")
    CatalogAgeDays = $catalogAgeDays
    NetworkChecked = [bool](-not $SkipNetwork)
    ReviewRequired = [bool]($reviewReasons.Count -gt 0)
    ReviewReasons = @($reviewReasons.ToArray() | Select-Object -Unique)
    Sources = @($sourceResults.ToArray())
}

if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $fullOutputPath = [IO.Path]::GetFullPath($OutputFile)
    $outputDirectory = Split-Path -Parent $fullOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    [IO.File]::WriteAllText($fullOutputPath, ($report | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

if ($report.ReviewRequired) {
    foreach ($reason in @($report.ReviewReasons)) { Write-Warning $reason }
    Write-Host "MICROSOFT-CATALOG-SOURCES: REVIEW REQUIRED ($(@($report.ReviewReasons).Count) reasons)"
    if ($FailOnReviewRequired) { exit 2 }
} else {
    Write-Host "MICROSOFT-CATALOG-SOURCES: CURRENT ($(@($report.Sources).Count) official sources)" -ForegroundColor Green
}
exit 0
