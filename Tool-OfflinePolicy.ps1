$script:ToolOfflinePolicySchemaVersion = "1.0"
$script:ToolOfflinePolicyToolVersion = "4.6"

$toolOfflineLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolOfflineLocalizationPath -PathType Leaf)) {
    . $toolOfflineLocalizationPath
}

function Get-ToolOfflineSettingsPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_OFFLINE_SETTINGS_PATH)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$env:TOOL_OFFLINE_SETTINGS_PATH))
    }
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($localAppData)) { return "" }
    return Join-Path $localAppData "ThanhViet-Tool-Kiem-Tra\offline-settings.json"
}

function Get-ToolEnterpriseNetworkSettingsPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH))
    }
    $dataRoot = [string]$env:TOOL_DATA_ROOT
    if ([string]::IsNullOrWhiteSpace($dataRoot)) {
        $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
        if ([string]::IsNullOrWhiteSpace($commonData)) { $commonData = [string]$env:ProgramData }
        if ([string]::IsNullOrWhiteSpace($commonData)) { return "" }
        $dataRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.6"
    }
    return Join-Path ([IO.Path]::GetFullPath($dataRoot)) "enterprise-network-settings.json"
}

function Get-ToolOfflineMode {
    if ([string]$env:TOOL_OFFLINE_MODE -eq "1") { return $true }
    if ([string]$env:TOOL_OFFLINE_MODE -eq "0") { return $false }

    $settingsPath = Get-ToolOfflineSettingsPath
    if (-not [string]::IsNullOrWhiteSpace($settingsPath) -and (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $settings.OfflineMode) { return [bool]$settings.OfflineMode }
        } catch {}
    }
    return $true
}

function Set-ToolOfflineModePreference {
    param([Parameter(Mandatory = $true)][bool]$OfflineMode)

    $env:TOOL_OFFLINE_MODE = if ($OfflineMode) { "1" } else { "0" }
    $settingsPath = Get-ToolOfflineSettingsPath
    if ([string]::IsNullOrWhiteSpace($settingsPath)) { return $false }
    try {
        $directory = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $settings = [ordered]@{
            SchemaVersion = $script:ToolOfflinePolicySchemaVersion
            OfflineMode = [bool]$OfflineMode
            ModifiedAtUtc = [DateTime]::UtcNow.ToString("o")
        }
        [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch {
        return $false
    }
}

function Get-ToolEnterpriseNetworkAllowed {
    if ([string]$env:TOOL_ENTERPRISE_NETWORK_ALLOWED -eq "1") { return $true }
    if ([string]$env:TOOL_ENTERPRISE_NETWORK_ALLOWED -eq "0") { return $false }

    $settingsPath = Get-ToolEnterpriseNetworkSettingsPath
    if (-not [string]::IsNullOrWhiteSpace($settingsPath)) {
        try {
            if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf -ErrorAction Stop)) { return $false }
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $settings.Allowed) { return [bool]$settings.Allowed }
        } catch {}
    }
    return $false
}

function Set-ToolEnterpriseNetworkAllowedPreference {
    param([Parameter(Mandatory = $true)][bool]$Allowed)

    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = if ($Allowed) { "1" } else { "0" }
    $settingsPath = Get-ToolEnterpriseNetworkSettingsPath
    if ([string]::IsNullOrWhiteSpace($settingsPath)) { return $false }
    try {
        $directory = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $settings = [ordered]@{
            SchemaVersion = $script:ToolOfflinePolicySchemaVersion
            Allowed = [bool]$Allowed
            Scope = "Section8"
            ModifiedAtUtc = [DateTime]::UtcNow.ToString("o")
        }
        [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        return $true
    } catch {
        return $false
    }
}

function Test-ToolNetworkActionAllowed {
    param([ValidateSet("Internet", "Lan", "Loopback")][string]$Scope = "Internet")
    return [bool](-not (Get-ToolOfflineMode))
}

function Test-ToolEnterpriseNetworkActionAllowed {
    return [bool](Get-ToolEnterpriseNetworkAllowed)
}

function Assert-ToolNetworkActionAllowed {
    param(
        [ValidateSet("Internet", "Lan", "Loopback")][string]$Scope = "Internet",
        [string]$Action = ""
    )
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = Get-ToolTextCurrent "foundation.offline.defaultNetworkAction" }
    if (-not (Test-ToolNetworkActionAllowed -Scope $Scope)) {
        throw (Get-ToolTextCurrent "foundation.offline.actionBlocked" @($Action))
    }
    return $true
}

function Assert-ToolEnterpriseNetworkActionAllowed {
    param([string]$Action = "")
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = Get-ToolTextCurrent "foundation.offline.defaultEnterpriseAction" }
    if (-not (Test-ToolEnterpriseNetworkActionAllowed)) {
        throw (Get-ToolTextCurrent "foundation.offline.enterpriseActionBlocked" @($Action))
    }
    return $true
}

function Get-ToolOfflinePolicyMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolOfflinePolicySchemaVersion
        ToolVersion = $script:ToolOfflinePolicyToolVersion
        DefaultMode = "Offline"
        CurrentOfflineMode = [bool](Get-ToolOfflineMode)
        BlockedScopes = @("Internet", "Lan", "Loopback")
        AllowedResources = @("LocalFile", "Registry", "CIM", "WMI", "LocalProcess")
        EnterpriseNetworkDefault = "Blocked"
        CurrentEnterpriseNetworkAllowed = [bool](Get-ToolEnterpriseNetworkAllowed)
        Telemetry = "Disabled"
        AutomaticUpdateCheck = $false
    }
}
