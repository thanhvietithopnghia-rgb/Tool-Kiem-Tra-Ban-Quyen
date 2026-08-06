[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][ValidateSet("x64", "x86")][string]$ExpectedArchitecture
)

$ErrorActionPreference = "Stop"
$originalLogPath = [string]$env:TOOL_LOG_PATH
$originalCorrelationId = [string]$env:TOOL_CORRELATION_ID
$originalSecureLaunch = [string]$env:TOOL_SECURE_LAUNCH
$originalModuleId = [string]$env:TOOL_MODULE_ID
$originalModuleInvocationId = [string]$env:TOOL_MODULE_INVOCATION_ID
$tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ("Tool-Kiem-Tra-v4.6-foundation-" + [Guid]::NewGuid().ToString("N"))
$tempLogPath = Join-Path $tempDirectory "foundation.jsonl"

try {
    . (Join-Path $SourceDirectory "Tool-Capabilities.ps1")
    . (Join-Path $SourceDirectory "Tool-Logging.ps1")
    . (Join-Path $SourceDirectory "Tool-ReportSchema.ps1")
    . (Join-Path $SourceDirectory "Tool-SafetyPolicy.ps1")

    $actualArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    if ($actualArchitecture -ne $ExpectedArchitecture) { throw "Verifier đang chạy $actualArchitecture, cần $ExpectedArchitecture." }

    $profile = Get-ToolCapabilityProfile
    if ([string]$profile.SchemaVersion -ne "1.1" -or [string]$profile.ToolVersion -ne "4.6") { throw "Capability schema/version không hợp lệ." }
    if ([string]$profile.ProcessArchitecture -ne $ExpectedArchitecture) { throw "Capability nhận sai kiến trúc tiến trình." }
    if (-not $profile.SupportedOperatingSystem) { throw "Máy kiểm thử không thuộc phạm vi hệ điều hành hỗ trợ." }
    if (-not $profile.CimCmdlets -and -not $profile.WmiFallback) { throw "Không có cả CIM lẫn WMI fallback." }
    if (-not $profile.ScheduledTasksModule -and -not $profile.ScheduledTasksFallback) { throw "Không có cả ScheduledTasks module lẫn schtasks fallback." }

    $reportMetadata = Get-ToolReportSchemaMetadata
    if ([string]$reportMetadata.SchemaVersion -ne "1.5" -or [string]$reportMetadata.ToolVersion -ne "4.6" -or @($reportMetadata.ReportKinds).Count -ne 9) {
        throw "Report schema foundation không hợp lệ."
    }
    $safetyMetadata = Get-ToolSafetyPolicyMetadata
    if ([string]$safetyMetadata.SchemaVersion -ne "1.0" -or [string]$safetyMetadata.ToolVersion -ne "4.6" -or [bool]$safetyMetadata.StartupTypeChangesAllowedByQuickRepair) {
        throw "Safety policy foundation không hợp lệ."
    }

    [IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
    $env:TOOL_LOG_PATH = $tempLogPath
    $env:TOOL_CORRELATION_ID = "foundation-$ExpectedArchitecture"
    $env:TOOL_SECURE_LAUNCH = "0"
    $env:TOOL_MODULE_ID = "report.all"
    $env:TOOL_MODULE_INVOCATION_ID = "foundation-invocation-$ExpectedArchitecture"
    $state = Initialize-ToolLogging -Component "FoundationVerifier" -ToolVersion "4.6"
    if (-not $state.Enabled) { throw "Không khởi tạo được log: $($state.Error)" }
    $written = Write-ToolLog -Level "INFO" -Event "Foundation.Test" -Message "Dòng 1`r`nDòng 2" -DurationMs 12 -Data ([ordered]@{ Architecture=$ExpectedArchitecture; Marker="safe" })
    if (-not $written -or -not (Test-Path -LiteralPath $tempLogPath -PathType Leaf)) { throw "Không ghi được JSONL log." }

    $lines = @(Get-Content -LiteralPath $tempLogPath -Encoding UTF8)
    if ($lines.Count -ne 1) { throw "JSONL phải có đúng một bản ghi/một dòng." }
    $record = $lines[0] | ConvertFrom-Json
    if ([string]$record.SchemaVersion -ne "1.0" -or [string]$record.ToolVersion -ne "4.6" -or
        [string]$record.Event -ne "Foundation.Test" -or [string]$record.CorrelationId -ne "foundation-$ExpectedArchitecture" -or
        [string]$record.ModuleId -ne "report.all" -or [string]$record.ModuleInvocationId -ne "foundation-invocation-$ExpectedArchitecture" -or
        [string]$record.Message -ne "Dòng 1  Dòng 2" -or [string]$record.Data.Marker -ne "safe") {
        throw "Bản ghi JSONL sai schema hoặc chưa làm phẳng ký tự xuống dòng."
    }

    Write-Host "FOUNDATION $ExpectedArchitecture`: ĐẠT (capability + JSONL + report/safety schemas)" -ForegroundColor Green
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
} finally {
    $env:TOOL_LOG_PATH = $originalLogPath
    $env:TOOL_CORRELATION_ID = $originalCorrelationId
    $env:TOOL_SECURE_LAUNCH = $originalSecureLaunch
    $env:TOOL_MODULE_ID = $originalModuleId
    $env:TOOL_MODULE_INVOCATION_ID = $originalModuleInvocationId
    if (Test-Path -LiteralPath $tempLogPath -PathType Leaf) { [IO.File]::Delete($tempLogPath) }
    if (Test-Path -LiteralPath $tempDirectory -PathType Container) { [IO.Directory]::Delete($tempDirectory, $false) }
}
