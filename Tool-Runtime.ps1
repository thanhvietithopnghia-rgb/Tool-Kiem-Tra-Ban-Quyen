function Get-ToolArchitectureState {
    $is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    $is64BitProcess = [Environment]::Is64BitProcess
    $processArchitecture = if ($is64BitProcess) { "x64" } else { "x86" }
    $operatingSystemArchitecture = if ($is64BitOperatingSystem) { "x64" } else { "x86" }
    $expectedArchitecture = ([string]$env:TOOL_EXPECTED_PROCESS_ARCHITECTURE).Trim().ToLowerInvariant()
    $supported = $true
    $message = "Đang chạy đúng kiến trúc native $processArchitecture."

    if ($is64BitOperatingSystem -and -not $is64BitProcess) {
        $supported = $false
        $message = "Windows đang là 64-bit nhưng tiến trình PowerShell là 32-bit. Hãy chạy trực tiếp Tool-Kiem-Tra-v4.4.exe để bản AnyCPU tự dùng PowerShell 64-bit, tránh Registry/System32 bị WOW64 chuyển hướng."
    } elseif ($expectedArchitecture -eq "x64" -and -not $is64BitProcess) {
        $supported = $false
        $message = "Bản x64 không được chạy trong tiến trình 32-bit."
    } elseif ($expectedArchitecture -eq "x86" -and ($is64BitOperatingSystem -or $is64BitProcess)) {
        $supported = $false
        $message = "Nhãn x86 chỉ hợp lệ khi cả Windows và tiến trình đều là 32-bit."
    } elseif ($expectedArchitecture -and $expectedArchitecture -notin @("x64", "x86")) {
        $supported = $false
        $message = "Nhãn kiến trúc từ launcher không hợp lệ: $expectedArchitecture"
    }

    return [pscustomobject]@{
        Supported = [bool]$supported
        ProcessArchitecture = $processArchitecture
        OperatingSystemArchitecture = $operatingSystemArchitecture
        ExpectedArchitecture = $expectedArchitecture
        Message = $message
    }
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
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { throw "Không xác định được thư mục Windows." }
    return $windowsDirectory
}

function Get-ToolWindowsPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Đường dẫn thành phần Windows không an toàn: $RelativePath"
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
        throw "Đường dẫn thành phần hệ thống không an toàn: $RelativePath"
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
            throw "Launcher truyền đường dẫn PowerShell không đúng System32 native."
        }
    }

    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw "Không tìm thấy Windows PowerShell native: $expectedPath"
    }
    return $expectedPath
}
