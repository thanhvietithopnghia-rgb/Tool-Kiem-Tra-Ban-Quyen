param(
    [Parameter(Mandatory = $true)][string]$ResultFile,
    [switch]$ConsentGranted,
    [ValidateSet('vi-VN','en-US')][string]$Culture = 'vi-VN',
    [string]$CatalogUrl = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ConsentGranted) {
    # Fail closed before loading the updater or performing any network action.
    exit 2
}
$localizationHelper = Join-Path $PSScriptRoot 'Tool-Localization.ps1'
$offlinePolicyHelper = Join-Path $PSScriptRoot 'Tool-OfflinePolicy.ps1'
$softwareInventoryHelper = Join-Path $PSScriptRoot 'Tool-SoftwareInventory.ps1'
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf) -or
    -not (Test-Path -LiteralPath $offlinePolicyHelper -PathType Leaf) -or
    -not (Test-Path -LiteralPath $softwareInventoryHelper -PathType Leaf)) { exit 12 }
. $localizationHelper
. $offlinePolicyHelper
. $softwareInventoryHelper
$env:TOOL_UI_CULTURE = $Culture

try {
    [void](Assert-ToolNetworkActionAllowed -Scope Internet -Action (Get-ToolTextCurrent 'software.online.action'))
    $arguments = @{ ConsentGranted=$ConsentGranted }
    if (-not [string]::IsNullOrWhiteSpace($CatalogUrl)) { $arguments.CatalogUrl = $CatalogUrl }
    $result = Update-ToolSoftwareLicenseCatalog @arguments
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($ResultFile))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultFile), ($result | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    if ([bool]$result.Success) { exit 0 }
    exit 3
} catch {
    $failure = [pscustomobject][ordered]@{
        Success=$false; CatalogVersion=''; ProductRuleCount=0; CachePath=(Get-ToolSoftwareCatalogCachePath)
        SourceUrl=$CatalogUrl; Sha256=''; StartedAtUtc=''; CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        Error=[string]$_.Exception.Message; UploadedInventory=$false; SentLicenseKeys=$false
    }
    try { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultFile), ($failure | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) } catch {}
    exit 3
}
