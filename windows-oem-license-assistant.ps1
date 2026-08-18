param(
    [ValidateSet("Inspect", "Apply")]
    [string]$Mode = "Inspect",
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra"),
    [string]$DecisionFile = "",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN"
)

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-OemText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-OemText "common.powerShellRequired" @(3)); exit 10 }
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-OemText "common.missingDependency" @("Tool-Runtime.ps1")) }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw (Get-OemText "common.missingDependency" @("Tool-ReportExport.ps1")) }
    . $runtimeHelper
    . $reportExportHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "Continue"
$releaseVersion = "4.8.0.1"

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
    if (-not $License) { return Get-OemText "common.unknown" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return $description
}

function Mask-Key {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return Get-OemText "common.notFound" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return Get-OemText "oemReport.keyDetectedNoSuffix" }
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
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $basePath = Join-Path $expandedOutput ((Get-OemText "oemReport.fileBase") + "_$($env:COMPUTERNAME)_$stamp")
    $package = Export-ToolTextReportPresentation `
        -Lines $Lines.ToArray() -Title (Get-OemText "oemReport.title") -BasePath $basePath `
        -Subtitle (Get-OemText "oemReport.subtitle") `
        -Eyebrow (Get-OemText "forensicsReport.eyebrow") `
        -Footer (Get-OemText "forensicsReport.footer" @($releaseVersion)) -Culture $Culture -IncludePdf
    Write-Host (Get-OemText "oemReport.output.html" @($package.HtmlPath))
    if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host (Get-OemText "oemReport.output.pdf" @($package.PdfPath)) }
    else { Write-Host (Get-OemText "oemReport.output.pdfFailed" @($package.Pdf.Error)) }
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
$currentEdition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { Get-OemText "common.unknown" }
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
$currentPartialKey = if ($activeLicense.PartialProductKey) { [string]$activeLicense.PartialProductKey } else { Get-OemText "common.unknown" }
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
$report.Add((Get-OemText "oemReport.heading" @($releaseVersion)))
$report.Add((Get-OemText "oemReport.developer"))
$report.Add((Get-OemText "oemReport.computer" @($env:COMPUTERNAME)))
$report.Add((Get-OemText "oemReport.time" @((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))))
$report.Add("")
$report.Add((Get-OemText "oemReport.windows" @($productName)))
$report.Add((Get-OemText "oemReport.edition" @($currentEdition)))
$report.Add((Get-OemText "oemReport.activation" @($(if ($isActivated) { Get-OemText "deepReport.license.licensed" } else { Get-OemText "oemReport.licenseUnconfirmed" }))))
$report.Add((Get-OemText "oemReport.channel" @($currentChannel)))
$report.Add((Get-OemText "oemReport.lastFive" @($currentPartialKey)))
$report.Add((Get-OemText "oemReport.firmwareKey" @($(if ($firmwareKeyFound) { $maskedFirmwareKey } else { Get-OemText "common.notFound" }))))
$report.Add("")
$report.Add((Get-OemText "oemReport.note"))

if ($Mode -eq "Inspect") {
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 0)
    exit 0
}

if (-not (Test-Administrator)) {
    $report.Add((Get-OemText "oemReport.result.adminRequired"))
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 20)
    exit 20
}

if (-not $firmwareKeyFound) {
    $report.Add((Get-OemText "oemReport.result.notFound"))
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 21)
    exit 21
}

$slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
if (-not (Test-Path -LiteralPath $slmgr)) {
    $report.Add((Get-OemText "oemReport.result.slmgrMissing"))
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 24)
    exit 24
}

$report.Add((Get-OemText "oemReport.applyConfirmed"))
$report.Add((Get-OemText "oemReport.safety"))

$installOutput = & $nativeCscriptPath //nologo $slmgr /ipk $firmwareKey 2>&1
$installExitCode = $LASTEXITCODE
$report.Add((Get-OemText "oemReport.installOutput"))
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
    $report.Add((Get-OemText "oemReport.conclusion.rejected"))
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 22)
    exit 22
}

$activationOutput = & $nativeCscriptPath //nologo $slmgr /ato 2>&1
$activationExitCode = $LASTEXITCODE
$report.Add((Get-OemText "oemReport.activationOutput"))
$report.Add((Sanitize-Text $activationOutput $firmwareKey))

$activatedFirmwareLicense = $null
for ($attempt = 1; $attempt -le 3 -and -not $activatedFirmwareLicense; $attempt++) {
    Start-Sleep -Seconds 2
    $activatedFirmwareLicense = Safe-Cim SoftwareLicensingProduct | Where-Object {
        $_.PartialProductKey -eq $lastFive -and $_.Name -match "Windows" -and [int]$_.LicenseStatus -eq 1
    } | Select-Object -First 1
}

if ($activationExitCode -eq 0 -and $activatedFirmwareLicense) {
    $report.Add((Get-OemText "oemReport.conclusion.licensed"))
    [void](Complete-OemReport -Lines $report -State $decision -ExitCode 0)
    exit 0
}

$report.Add((Get-OemText "oemReport.conclusion.pending"))
[void](Complete-OemReport -Lines $report -State $decision -ExitCode 23)
exit 23
