function Test-ToolCommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

if (-not (Get-Command Get-ToolWindowsReleaseProfile -ErrorAction SilentlyContinue)) {
    $compatibilityHelperPath = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
    if (Test-Path -LiteralPath $compatibilityHelperPath -PathType Leaf) { . $compatibilityHelperPath }
}

function Get-ToolCapabilityProfile {
    [CmdletBinding()]
    param()

    $osVersion = [Environment]::OSVersion.Version
    $osArchitecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $processArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    $currentVersion = $null
    try {
        $currentVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    } catch {}

    $detectedMajor = [int]$osVersion.Major
    $detectedMinor = [int]$osVersion.Minor
    if ($currentVersion) {
        if ($null -ne $currentVersion.CurrentMajorVersionNumber) {
            $detectedMajor = [int]$currentVersion.CurrentMajorVersionNumber
            $detectedMinor = [int]$currentVersion.CurrentMinorVersionNumber
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$currentVersion.CurrentVersion)) {
            $parsedVersion = $null
            if ([Version]::TryParse([string]$currentVersion.CurrentVersion, [ref]$parsedVersion)) {
                $detectedMajor = [int]$parsedVersion.Major
                $detectedMinor = [int]$parsedVersion.Minor
            }
        }
    }

    $productName = if ($currentVersion -and $currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
    $displayVersion = if ($currentVersion -and $currentVersion.DisplayVersion) {
        [string]$currentVersion.DisplayVersion
    } elseif ($currentVersion -and $currentVersion.ReleaseId) {
        [string]$currentVersion.ReleaseId
    } else {
        ""
    }
    $buildNumber = if ($currentVersion -and $currentVersion.CurrentBuildNumber) {
        [string]$currentVersion.CurrentBuildNumber
    } else {
        [string]$osVersion.Build
    }
    $updateBuildRevision = if ($currentVersion -and $null -ne $currentVersion.UBR) { [int64]$currentVersion.UBR } else { 0 }

    if ($detectedMajor -ge 10 -and [int64]$buildNumber -ge 22000 -and $productName -match "Windows 10") {
        $productName = $productName -replace "Windows 10", "Windows 11"
    }

    $servicePack = if ($currentVersion -and $currentVersion.CSDVersion) { [string]$currentVersion.CSDVersion } else { [string][Environment]::OSVersion.ServicePack }
    $windowsRelease = $null
    $officeCompatibility = $null
    $compatibilityMetadata = $null
    try {
        if (Get-Command Get-ToolWindowsReleaseProfile -ErrorAction SilentlyContinue) {
            $windowsRelease = Get-ToolWindowsReleaseProfile -BuildNumber ([int64]$buildNumber) -DisplayVersion $displayVersion -Ubr $updateBuildRevision
            $officeCompatibility = Get-ToolOfficeCompatibilityProfile
            $compatibilityMetadata = Get-ToolCompatibilityMetadata
        }
    } catch {}
    $compatibilityTier = if ($detectedMajor -lt 6 -or ($detectedMajor -eq 6 -and $detectedMinor -lt 1)) {
        "Unsupported"
    } elseif ($detectedMajor -eq 6 -and $detectedMinor -eq 1 -and $servicePack -notmatch "Service Pack 1") {
        "Unsupported"
    } elseif ($detectedMajor -eq 6 -and $detectedMinor -eq 1) {
        "Legacy-Windows7"
    } elseif ($detectedMajor -eq 6) {
        "Legacy-Windows8"
    } elseif ($windowsRelease -and $windowsRelease.Detected -and -not [string]::IsNullOrWhiteSpace([string]$windowsRelease.DisplayVersion)) {
        "Modern-Windows11-$($windowsRelease.DisplayVersion)"
    } else {
        "Modern-Windows10Plus"
    }

    $nativeSystemDirectory = ""
    try {
        if (Get-Command Get-ToolNativeSystemDirectory -ErrorAction SilentlyContinue) {
            $nativeSystemDirectory = [string](Get-ToolNativeSystemDirectory)
        }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($nativeSystemDirectory)) {
        $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        $nativeSystemDirectory = Join-Path $windowsDirectory "System32"
    }

    $schtasksPath = Join-Path $nativeSystemDirectory "schtasks.exe"
    $cscriptPath = Join-Path $nativeSystemDirectory "cscript.exe"
    $dismPath = Join-Path $nativeSystemDirectory "dism.exe"

    return [pscustomobject][ordered]@{
        SchemaVersion = "1.1"
        ToolVersion = "4.3"
        CheckedAtUtc = [DateTime]::UtcNow.ToString("o")
        SupportedOperatingSystem = [bool]($compatibilityTier -ne "Unsupported")
        CompatibilityTier = $compatibilityTier
        ProductName = $productName
        DisplayVersion = $displayVersion
        Version = "$detectedMajor.$detectedMinor.$buildNumber"
        BuildNumber = $buildNumber
        UpdateBuildRevision = $updateBuildRevision
        FullBuildNumber = if ($updateBuildRevision -gt 0) { "$buildNumber.$updateBuildRevision" } else { $buildNumber }
        WindowsRelease = $windowsRelease
        WindowsReleaseName = if ($windowsRelease) { [string]$windowsRelease.Name } else { "$productName $displayVersion" }
        WindowsServicingState = if ($windowsRelease) { [string]$windowsRelease.ServicingState } else { "Unknown" }
        CompatibilityCatalog = $compatibilityMetadata
        OfficeCompatibility = $officeCompatibility
        OfficeSummary = if ($officeCompatibility) { [string]$officeCompatibility.Family } else { "Not detected" }
        ServicePack = $servicePack
        OperatingSystemArchitecture = $osArchitecture
        ProcessArchitecture = $processArchitecture
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        CimCmdlets = [bool](Test-ToolCommandAvailable "Get-CimInstance")
        WmiFallback = [bool](Test-ToolCommandAvailable "Get-WmiObject")
        ScheduledTasksModule = [bool](Test-ToolCommandAvailable "Get-ScheduledTask")
        ScheduledTasksFallback = [bool](Test-Path -LiteralPath $schtasksPath -PathType Leaf)
        DefenderCmdlets = [bool](Test-ToolCommandAvailable "Get-MpPreference")
        TpmCmdlets = [bool](Test-ToolCommandAvailable "Get-Tpm")
        BitLockerCmdlets = [bool](Test-ToolCommandAvailable "Get-BitLockerVolume")
        SecureBootCmdlet = [bool](Test-ToolCommandAvailable "Confirm-SecureBootUEFI")
        NativeCscript = [bool](Test-Path -LiteralPath $cscriptPath -PathType Leaf)
        NativeDism = [bool](Test-Path -LiteralPath $dismPath -PathType Leaf)
    }
}

function Test-ToolCapability {
    param(
        [Parameter(Mandatory = $true)][object]$Profile,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Profile.PSObject.Properties[$Name]
    if (-not $property) { return $false }
    return [bool]$property.Value
}

function Get-ToolCapabilitySummary {
    param([Parameter(Mandatory = $true)][object]$Profile)

    $taskMode = if ($Profile.ScheduledTasksModule) { "ScheduledTasks module" } elseif ($Profile.ScheduledTasksFallback) { "schtasks fallback" } else { "không khả dụng" }
    $managementMode = if ($Profile.CimCmdlets) { "CIM" } elseif ($Profile.WmiFallback) { "WMI fallback" } else { "không khả dụng" }
    $windowsLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Profile.WindowsReleaseName)) { [string]$Profile.WindowsReleaseName } else { [string]$Profile.ProductName }
    $officeLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Profile.OfficeSummary)) { [string]$Profile.OfficeSummary } else { "Not detected" }
    return "Tương thích: $windowsLabel build $($Profile.FullBuildNumber); Office: $officeLabel; $($Profile.OperatingSystemArchitecture)/$($Profile.ProcessArchitecture); quản trị: $managementMode; task: $taskMode."
}
