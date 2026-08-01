$script:ToolLogState = $null

function ConvertTo-ToolLogSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 4096)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`r", " ").Replace("`n", " ").Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Initialize-ToolLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        [string]$ToolVersion = "4.4"
    )

    $path = [string]$env:TOOL_LOG_PATH
    $correlationId = [string]$env:TOOL_CORRELATION_ID
    if ([string]::IsNullOrWhiteSpace($correlationId)) { $correlationId = [Guid]::NewGuid().ToString("N") }

    $state = [pscustomobject][ordered]@{
        Enabled = $false
        Path = ""
        Component = (ConvertTo-ToolLogSafeText $Component 120)
        ToolVersion = (ConvertTo-ToolLogSafeText $ToolVersion 32)
        CorrelationId = (ConvertTo-ToolLogSafeText $correlationId 64)
        ModuleId = (ConvertTo-ToolLogSafeText $env:TOOL_MODULE_ID 120)
        ModuleInvocationId = (ConvertTo-ToolLogSafeText $env:TOOL_MODULE_INVOCATION_ID 64)
        Error = ""
    }

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            $state.Error = "TOOL_LOG_PATH chưa được launcher thiết lập; logging bền vững đang tắt."
            $script:ToolLogState = $state
            return $state
        }
        if (-not [IO.Path]::IsPathRooted($path)) { throw "Đường dẫn log phải là đường dẫn tuyệt đối." }
        $fullPath = [IO.Path]::GetFullPath($path)
        if ([IO.Path]::GetExtension($fullPath) -ne ".jsonl") { throw "Log phải dùng phần mở rộng .jsonl." }
        $directory = Split-Path -Parent $fullPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Thư mục log chưa được launcher tạo." }
        $directoryInfo = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
        if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Thư mục log không được là reparse point." }

        if ($env:TOOL_SECURE_LAUNCH -eq "1") {
            $expectedRoot = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.4\logs"
            $expectedFull = [IO.Path]::GetFullPath($expectedRoot).TrimEnd([char]92) + [char]92
            if (-not $fullPath.StartsWith($expectedFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Launcher truyền đường dẫn log ngoài vùng ProgramData bảo vệ."
            }
        }

        $state.Enabled = $true
        $state.Path = $fullPath
    } catch {
        $state.Error = ConvertTo-ToolLogSafeText $_.Exception.Message 512
    }

    $script:ToolLogState = $state
    return $state
}

function Write-ToolLog {
    [CmdletBinding()]
    param(
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "AUDIT")][string]$Level = "INFO",
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Message = "",
        [AllowNull()][object]$Data = $null,
        [Nullable[long]]$DurationMs = $null
    )

    if (-not $script:ToolLogState -or -not $script:ToolLogState.Enabled) { return $false }
    try {
        $record = [ordered]@{
            SchemaVersion = "1.0"
            TimestampUtc = [DateTime]::UtcNow.ToString("o")
            ToolVersion = $script:ToolLogState.ToolVersion
            Component = $script:ToolLogState.Component
            CorrelationId = $script:ToolLogState.CorrelationId
            ModuleId = $script:ToolLogState.ModuleId
            ModuleInvocationId = $script:ToolLogState.ModuleInvocationId
            ProcessId = $PID
            ProcessArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
            Level = $Level
            Event = ConvertTo-ToolLogSafeText $Event 160
            Message = ConvertTo-ToolLogSafeText $Message 4096
        }
        if ($null -ne $DurationMs) { $record.DurationMs = [long]$DurationMs }
        if ($null -ne $Data) { $record.Data = $Data }
        $line = ([pscustomobject]$record | ConvertTo-Json -Depth 6 -Compress)
        if ($line.Length -gt 32768) { throw "Bản ghi log vượt giới hạn 32 KB." }
        $encoding = New-Object Text.UTF8Encoding($false)
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                [IO.File]::AppendAllText($script:ToolLogState.Path, $line + [Environment]::NewLine, $encoding)
                return $true
            } catch [IO.IOException] {
                if ($attempt -eq 4) { throw }
                Start-Sleep -Milliseconds (25 * ($attempt + 1))
            }
        }
    } catch {
        $script:ToolLogState.Error = ConvertTo-ToolLogSafeText $_.Exception.Message 512
    }
    return $false
}

function Get-ToolLogState {
    return $script:ToolLogState
}
