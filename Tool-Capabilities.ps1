function Test-ToolCommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

$toolCapabilitiesLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolCapabilitiesLocalizationPath -PathType Leaf)) {
    . $toolCapabilitiesLocalizationPath
}

if (-not (Get-Command Get-ToolWindowsReleaseProfile -ErrorAction SilentlyContinue)) {
    $compatibilityHelperPath = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
    if (Test-Path -LiteralPath $compatibilityHelperPath -PathType Leaf) { . $compatibilityHelperPath }
}

function Get-ToolExecutionEnvironmentProfile {
    [CmdletBinding()]
    param()

    $manufacturer = ""
    $model = ""
    $biosManufacturer = ""
    $biosVersion = ""
    try {
        $computerSystem = if (Test-ToolCommandAvailable "Get-CimInstance") {
            Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        }
        $manufacturer = [string]$computerSystem.Manufacturer
        $model = [string]$computerSystem.Model
    } catch {}
    try {
        $bios = Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -ErrorAction Stop
        $biosManufacturer = [string]$bios.BIOSVendor
        $biosVersion = @([string]$bios.BIOSVersion, [string]$bios.SystemFamily, [string]$bios.SystemProductName) -join " "
    } catch {}

    $fingerprint = "$manufacturer $model $biosManufacturer $biosVersion"
    $provider = ""
    $virtualPatterns = [ordered]@{
        "Microsoft Hyper-V" = '(?i)(microsoft corporation.*virtual machine|virtual machine.*microsoft corporation|hyper-v)'
        "VMware" = '(?i)(vmware|vmw virtual)'
        "Oracle VirtualBox" = '(?i)(virtualbox|innotek)'
        "QEMU/KVM" = '(?i)(qemu|kvm|bochs)'
        "Xen" = '(?i)(xen|hvm domu)'
        "Parallels" = '(?i)(parallels)'
        "Virtual PC" = '(?i)(virtual pc)'
        "Cloud/virtual platform" = '(?i)(amazon ec2|google compute engine|openstack|digitalocean)'
    }
    foreach ($entry in $virtualPatterns.GetEnumerator()) {
        if ($fingerprint -match [string]$entry.Value) {
            $provider = [string]$entry.Key
            break
        }
    }

    $sessionName = [string]$env:SESSIONNAME
    $clientName = [string]$env:CLIENTNAME
    $remoteDesktop = [bool](
        $sessionName -match '^(?i)RDP-' -or
        (-not [string]::IsNullOrWhiteSpace($clientName) -and $clientName -notmatch '^(?i)(console|unknown)$')
    )
    return [pscustomobject][ordered]@{
        VirtualMachineDetected = [bool](-not [string]::IsNullOrWhiteSpace($provider))
        VirtualizationProvider = $provider
        Manufacturer = $manufacturer
        Model = $model
        RemoteDesktopDetected = $remoteDesktop
        SessionName = $sessionName
        RemoteClientName = $clientName
    }
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
        $catalogFamily = if ([string]::IsNullOrWhiteSpace([string]$windowsRelease.OperatingSystemFamily)) { "Windows" } else { [string]$windowsRelease.OperatingSystemFamily }
        "Modern-$catalogFamily-$($windowsRelease.DisplayVersion)"
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
    $executionEnvironment = Get-ToolExecutionEnvironmentProfile

    return [pscustomobject][ordered]@{
        SchemaVersion = "1.1"
        ToolVersion = "4.8"
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
        WindowsCompatibilityMode = if ($windowsRelease) { [string]$windowsRelease.CompatibilityMode } else { "ReadOnlyManualReview" }
        AutomaticVersionSensitiveActionsAllowed = [bool]($windowsRelease -and $windowsRelease.AutomaticVersionSensitiveActionsAllowed)
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
        ExecutionEnvironment = $executionEnvironment
        VirtualMachineDetected = [bool]$executionEnvironment.VirtualMachineDetected
        VirtualizationProvider = [string]$executionEnvironment.VirtualizationProvider
        RemoteDesktopDetected = [bool]$executionEnvironment.RemoteDesktopDetected
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

    $taskMode = if ($Profile.ScheduledTasksModule) { "ScheduledTasks module" } elseif ($Profile.ScheduledTasksFallback) { "schtasks fallback" } else { Get-ToolTextCurrent "foundation.capabilities.unavailable" }
    $managementMode = if ($Profile.CimCmdlets) { "CIM" } elseif ($Profile.WmiFallback) { "WMI fallback" } else { Get-ToolTextCurrent "foundation.capabilities.unavailable" }
    $windowsLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Profile.WindowsReleaseName)) { [string]$Profile.WindowsReleaseName } else { [string]$Profile.ProductName }
    $officeLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Profile.OfficeSummary)) { [string]$Profile.OfficeSummary } else { "Not detected" }
    return Get-ToolTextCurrent "foundation.capabilities.summary" @($windowsLabel, $Profile.FullBuildNumber, $officeLabel, $Profile.OperatingSystemArchitecture, $Profile.ProcessArchitecture, $managementMode, $taskMode)
}
