$script:ToolLocalizationSchemaVersion = "1.0"
$script:ToolLocalizationToolVersion = "4.8.0.1"
$script:ToolLocalizationDefaultCulture = "vi-VN"
$script:ToolLocalizationSupportedCultures = @("vi-VN", "en-US")
$script:ToolLocalizationCatalogCache = @{}

function Get-ToolLocalizationSettingsPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_UI_CULTURE_SETTINGS_PATH)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$env:TOOL_UI_CULTURE_SETTINGS_PATH))
    }
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($localAppData)) { return "" }
    return Join-Path $localAppData "ThanhViet-Tool-Kiem-Tra\localization-settings.json"
}

function Test-ToolSupportedCulture {
    param([AllowNull()][string]$Culture)
    return [bool]($script:ToolLocalizationSupportedCultures -contains [string]$Culture)
}

function Get-ToolCulture {
    $environmentCulture = [string]$env:TOOL_UI_CULTURE
    if (Test-ToolSupportedCulture $environmentCulture) { return $environmentCulture }

    $settingsPath = Get-ToolLocalizationSettingsPath
    if (-not [string]::IsNullOrWhiteSpace($settingsPath) -and (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (Test-ToolSupportedCulture ([string]$settings.Culture)) { return [string]$settings.Culture }
        } catch {}
    }
    return $script:ToolLocalizationDefaultCulture
}

function Set-ToolCulturePreference {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)

    $env:TOOL_UI_CULTURE = $Culture
    $settingsPath = Get-ToolLocalizationSettingsPath
    if ([string]::IsNullOrWhiteSpace($settingsPath)) { return $false }
    try {
        $directory = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $settings = [ordered]@{
            SchemaVersion = $script:ToolLocalizationSchemaVersion
            Culture = $Culture
            ModifiedAtUtc = [DateTime]::UtcNow.ToString("o")
        }
        [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch {
        return $false
    }
}

function Get-ToolLocalizationCatalogPath {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)
    return Join-Path $PSScriptRoot "Tool-Strings.$Culture.json"
}

function Get-ToolLocalizationCatalog {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$Culture)

    if ($script:ToolLocalizationCatalogCache.ContainsKey($Culture)) {
        return $script:ToolLocalizationCatalogCache[$Culture]
    }
    $path = Get-ToolLocalizationCatalogPath -Culture $Culture
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($Culture -ne $script:ToolLocalizationDefaultCulture) {
            return Get-ToolLocalizationCatalog -Culture $script:ToolLocalizationDefaultCulture
        }
        throw "[localization.catalogMissing] $path"
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 2 -or $item.Length -gt 1048576) {
        throw "[localization.catalogUnsafe] $path"
    }
    $catalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:ToolLocalizationCatalogCache[$Culture] = $catalog
    return $catalog
}

function Get-ToolText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Culture = "",
        [AllowNull()][object[]]$FormatArguments = @()
    )

    if ([string]::IsNullOrWhiteSpace($Culture)) { $Culture = Get-ToolCulture }
    if (-not (Test-ToolSupportedCulture $Culture)) { $Culture = $script:ToolLocalizationDefaultCulture }

    $catalog = Get-ToolLocalizationCatalog -Culture $Culture
    $property = $catalog.PSObject.Properties[$Key]
    if (-not $property -and $Culture -ne $script:ToolLocalizationDefaultCulture) {
        $fallback = Get-ToolLocalizationCatalog -Culture $script:ToolLocalizationDefaultCulture
        $property = $fallback.PSObject.Properties[$Key]
    }
    $text = if ($property) { [string]$property.Value } else { "[$Key]" }
    if ($null -ne $FormatArguments -and @($FormatArguments).Count -gt 0) {
        try {
            $cultureInfo = [Globalization.CultureInfo]::GetCultureInfo($Culture)
            return [string]::Format($cultureInfo, $text, [object[]]$FormatArguments)
        } catch {
            return $text
        }
    }
    return $text
}

function Get-ToolTextCurrent {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$FormatArguments = @()
    )

    return Get-ToolText -Key $Key -Culture (Get-ToolCulture) -FormatArguments $FormatArguments
}

function Get-ToolLocalizationMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolLocalizationSchemaVersion
        ToolVersion = $script:ToolLocalizationToolVersion
        DefaultCulture = $script:ToolLocalizationDefaultCulture
        SupportedCultures = @($script:ToolLocalizationSupportedCultures)
        CurrentCulture = Get-ToolCulture
        CatalogFiles = @($script:ToolLocalizationSupportedCultures | ForEach-Object { "Tool-Strings.$_.json" })
    }
}
