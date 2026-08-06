function Get-ToolArchitectureState {
    $is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    $is64BitProcess = [Environment]::Is64BitProcess
    $processArchitecture = if ($is64BitProcess) { "x64" } else { "x86" }
    $operatingSystemArchitecture = if ($is64BitOperatingSystem) { "x64" } else { "x86" }
    $expectedArchitecture = ([string]$env:TOOL_EXPECTED_PROCESS_ARCHITECTURE).Trim().ToLowerInvariant()
    $supported = $true
    $message = Get-ToolTextCurrent "foundation.runtime.architectureNative" @($processArchitecture)

    if ($is64BitOperatingSystem -and -not $is64BitProcess) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.architectureWow64"
    } elseif ($expectedArchitecture -eq "x64" -and -not $is64BitProcess) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.x64In32Bit"
    } elseif ($expectedArchitecture -eq "x86" -and ($is64BitOperatingSystem -or $is64BitProcess)) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.x86LabelInvalid"
    } elseif ($expectedArchitecture -and $expectedArchitecture -notin @("x64", "x86")) {
        $supported = $false
        $message = Get-ToolTextCurrent "foundation.runtime.architectureLabelInvalid" @($expectedArchitecture)
    }

    return [pscustomobject]@{
        Supported = [bool]$supported
        ProcessArchitecture = $processArchitecture
        OperatingSystemArchitecture = $operatingSystemArchitecture
        ExpectedArchitecture = $expectedArchitecture
        Message = $message
    }
}

$toolRuntimeLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolRuntimeLocalizationPath -PathType Leaf)) {
    . $toolRuntimeLocalizationPath
}

function Assert-ToolNativeArchitecture {
    $state = Get-ToolArchitectureState
    if (-not $state.Supported) { throw $state.Message }
    return $state
}

function Get-ToolWindowsDirectory {
    $windowsDirectory = [string]$env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) {
        $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    }
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { throw (Get-ToolTextCurrent "foundation.runtime.windowsDirectoryMissing") }
    return $windowsDirectory
}

function Get-ToolWindowsPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw (Get-ToolTextCurrent "foundation.runtime.windowsPathUnsafe" @($RelativePath))
    }
    return (Join-Path (Get-ToolWindowsDirectory) $RelativePath)
}

function Get-ToolNativeSystemDirectory {
    $windowsDirectory = Get-ToolWindowsDirectory

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $sysnative = Join-Path $windowsDirectory "Sysnative"
        if (Test-Path -LiteralPath $sysnative -PathType Container) { return $sysnative }
    }
    return (Join-Path $windowsDirectory "System32")
}

function Get-ToolNativeSystemPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw (Get-ToolTextCurrent "foundation.runtime.systemPathUnsafe" @($RelativePath))
    }
    return (Join-Path (Get-ToolNativeSystemDirectory) $RelativePath)
}

function Get-ToolNativePowerShellPath {
    $expectedPath = Get-ToolNativeSystemPath "WindowsPowerShell\v1.0\powershell.exe"
    $launcherPath = [string]$env:TOOL_POWERSHELL_PATH

    if ($env:TOOL_SECURE_LAUNCH -eq "1" -and -not [string]::IsNullOrWhiteSpace($launcherPath)) {
        $launcherFull = [IO.Path]::GetFullPath($launcherPath)
        $expectedFull = [IO.Path]::GetFullPath($expectedPath)
        if (-not [string]::Equals($launcherFull, $expectedFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw (Get-ToolTextCurrent "foundation.runtime.powerShellPathMismatch")
        }
    }

    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw (Get-ToolTextCurrent "foundation.runtime.powerShellMissing" @($expectedPath))
    }
    return $expectedPath
}
