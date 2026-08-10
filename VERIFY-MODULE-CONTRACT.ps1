[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][ValidateSet("x64", "x86")][string]$ExpectedArchitecture
)

$ErrorActionPreference = "Stop"
try {
    . (Join-Path $SourceDirectory "Tool-Runtime.ps1")
    . (Join-Path $SourceDirectory "Tool-Capabilities.ps1")
    . (Join-Path $SourceDirectory "Tool-ModuleContract.ps1")

    $actualArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    if ($actualArchitecture -ne $ExpectedArchitecture) { throw "Verifier đang chạy $actualArchitecture, cần $ExpectedArchitecture." }

    $metadata = Get-ToolModuleContractMetadata
if ([string]$metadata.ContractSchemaVersion -ne "1.0" -or [string]$metadata.ResultSchemaVersion -ne "1.0" -or [string]$metadata.ToolVersion -ne "4.8") { throw "Metadata hợp đồng mô-đun không hợp lệ." }
    if ([int]$metadata.ModuleCount -ne 27 -or [int]$metadata.EntryPointCount -ne 24) { throw "Catalog không đúng 27 mô-đun/24 entry point." }
    foreach ($category in @("Windows", "Office", "OEM", "Registry", "Service", "Task", "Backup", "Restore", "Forensics", "Report", "Security", "Assurance", "Enterprise", "Foundation")) {
        if ($metadata.Categories -notcontains $category) { throw "Catalog thiếu category: $category" }
    }

    $catalog = @(Get-ToolModuleCatalog)
    $duplicateIds = @($catalog | Group-Object ModuleId | Where-Object Count -ne 1)
    if ($duplicateIds.Count -gt 0) { throw "Catalog có ModuleId trùng." }
    foreach ($descriptor in $catalog) {
if ([string]$descriptor.ContractSchemaVersion -ne "1.0" -or [string]$descriptor.ResultSchemaVersion -ne "1.0" -or [string]$descriptor.ToolVersion -ne "4.8") { throw "Descriptor sai schema: $($descriptor.ModuleId)" }
        if ([string]$descriptor.NetworkScope -notin @("LocalOnly","Lan","Internet")) { throw "Descriptor thiếu NetworkScope: $($descriptor.ModuleId)" }
        if ([bool]$descriptor.OfflineCapable -ne ([string]$descriptor.NetworkScope -eq "LocalOnly")) { throw "OfflineCapable không khớp NetworkScope: $($descriptor.ModuleId)" }
        if ([string]::IsNullOrWhiteSpace([string]$descriptor.ModuleId) -or [string]::IsNullOrWhiteSpace([string]$descriptor.Category) -or [string]::IsNullOrWhiteSpace([string]$descriptor.DisplayName)) { throw "Descriptor thiếu trường bắt buộc." }
        if ($descriptor.IsEntryPoint -and -not (Test-Path -LiteralPath (Join-Path $SourceDirectory $descriptor.ScriptFile) -PathType Leaf)) { throw "Entry point không tồn tại: $($descriptor.ModuleId)" }
    }

    $profile = Get-ToolCapabilityProfile
    $reportAvailability = Test-ToolModuleAvailability -ModuleId "report.all" -CapabilityProfile $profile -SourceDirectory $SourceDirectory
    if (-not $reportAvailability.Available) { throw "report.all phải khả dụng trên máy kiểm thử: $($reportAvailability.Message)" }
    $updateDescriptor = Get-ToolModuleDescriptor -ModuleId "application.update.check"
    if (-not $updateDescriptor -or [string]$updateDescriptor.NetworkScope -ne "Internet" -or [string]$updateDescriptor.AccessMode -ne "ReadOnly" -or [string]$updateDescriptor.ScriptFile -ne "Tool-UpdateManager.ps1") {
        throw "Descriptor kiểm tra cập nhật ứng dụng không hợp lệ."
    }

    $limitedProfile = $profile.PSObject.Copy()
    $limitedProfile.ScheduledTasksModule = $false
    $limitedProfile.ScheduledTasksFallback = $false
    $cleanupAvailability = Test-ToolModuleAvailability -ModuleId "cleanup.scan" -CapabilityProfile $limitedProfile -SourceDirectory $SourceDirectory
    if ($cleanupAvailability.Available -or $cleanupAvailability.MissingRequirements -notcontains "ScheduledTasksModule|ScheduledTasksFallback") { throw "Capability gate không khóa đúng Scheduled Tasks." }

    $invocation = New-ToolModuleInvocation -ModuleId "cleanup.scan" -CorrelationId "contract-$ExpectedArchitecture"
    $result = Complete-ToolModuleInvocation -Invocation $invocation -ExitCode 3 -Summary "Yêu cầu xử lý`r`nđã làm phẳng" -FindingCount 2 -WarningCount 1 -OutputPaths @("report.json")
    $validation = Test-ToolModuleResult -Result $result
    if (-not $validation.Valid) { throw "ModuleResult không đạt: $($validation.Errors -join '; ')" }
    if ([string]$result.Status -ne "ActionRequired" -or [string]$result.CorrelationId -ne "contract-$ExpectedArchitecture" -or [string]$result.Summary -ne "Yêu cầu xử lý  đã làm phẳng" -or [int]$result.FindingCount -ne 2) { throw "Ánh xạ exit code hoặc chuẩn hóa ModuleResult sai." }

    $reportInvocation = New-ToolModuleInvocation -ModuleId "report.windows" -CorrelationId "contract-$ExpectedArchitecture" -InvocationId "inherited-$ExpectedArchitecture"
    $reportResult = Complete-ToolModuleInvocation -Invocation $reportInvocation -ExitCode 0 -Summary "Hoàn tất"
    if ([string]$reportResult.Status -ne "Completed" -or [string]$reportResult.InvocationId -ne "inherited-$ExpectedArchitecture" -or -not (Test-ToolModuleResult $reportResult).Valid) { throw "Kết quả report.windows không hợp lệ." }

    Write-Host "MODULE-CONTRACT $ExpectedArchitecture`: ĐẠT ($($metadata.ModuleCount) modules, schema 1.0)" -ForegroundColor Green
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
