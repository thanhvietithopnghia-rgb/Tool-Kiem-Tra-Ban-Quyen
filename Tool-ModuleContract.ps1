$script:ToolModuleContractSchemaVersion = "1.0"
$script:ToolModuleResultSchemaVersion = "1.0"
$script:ToolModuleContractToolVersion = "4.3"
$script:ToolModuleCatalogCache = $null

function ConvertTo-ToolContractSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 2048)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`r", " ").Replace("`n", " ").Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function New-ToolModuleDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string]$ScriptFile = "",
        [string]$Operation = "",
        [string]$TaskKind = "",
        [ValidateSet("ReadOnly", "SystemChange")][string]$AccessMode = "ReadOnly",
        [ValidateSet("LocalOnly", "Lan", "Internet")][string]$NetworkScope = "LocalOnly",
        [bool]$RequiresElevation = $false,
        [string[]]$RequiredCapabilities = @("SupportedOperatingSystem"),
        [bool]$IsEntryPoint = $true,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ExitCodeMap
    )

    return [pscustomobject][ordered]@{
        ContractSchemaVersion = $script:ToolModuleContractSchemaVersion
        ResultSchemaVersion = $script:ToolModuleResultSchemaVersion
        ToolVersion = $script:ToolModuleContractToolVersion
        ModuleId = (ConvertTo-ToolContractSafeText $ModuleId 120).ToLowerInvariant()
        Category = ConvertTo-ToolContractSafeText $Category 80
        DisplayName = ConvertTo-ToolContractSafeText $DisplayName 180
        ScriptFile = ConvertTo-ToolContractSafeText $ScriptFile 180
        Operation = ConvertTo-ToolContractSafeText $Operation 80
        TaskKind = ConvertTo-ToolContractSafeText $TaskKind 80
        AccessMode = $AccessMode
        NetworkScope = $NetworkScope
        OfflineCapable = [bool]($NetworkScope -eq "LocalOnly")
        RequiresElevation = [bool]$RequiresElevation
        RequiredCapabilities = @($RequiredCapabilities | ForEach-Object { ConvertTo-ToolContractSafeText $_ 120 })
        IsEntryPoint = [bool]$IsEntryPoint
        ExitCodeMap = $ExitCodeMap
    }
}

function Get-ToolModuleCatalog {
    if ($script:ToolModuleCatalogCache) { return @($script:ToolModuleCatalogCache) }

    $completed = [ordered]@{ "0"="Completed"; "10"="Unsupported"; "12"="Blocked"; "20"="Blocked" }
    $cleanup = [ordered]@{ "0"="Completed"; "2"="CompletedWithFindings"; "3"="ActionRequired"; "4"="CompletedWithFindings"; "10"="Unsupported"; "20"="Blocked" }
    $oemApply = [ordered]@{ "0"="Completed"; "10"="Unsupported"; "20"="Blocked"; "21"="CompletedWithFindings"; "22"="Failed"; "23"="ActionRequired"; "24"="Blocked" }
    $backup = [ordered]@{ "0"="Completed"; "10"="Unsupported"; "11"="Blocked"; "20"="Blocked"; "23"="Failed" }

    $catalog = @(
        (New-ToolModuleDescriptor -ModuleId "report.all" -Category "Report" -DisplayName "Báo cáo toàn bộ" -ScriptFile "kiem-tra-cau-hinh-ban-quyen.ps1" -Operation "All" -TaskKind "Report" -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "report.hardware" -Category "Hardware" -DisplayName "Báo cáo phần cứng" -ScriptFile "kiem-tra-cau-hinh-ban-quyen.ps1" -Operation "Hardware" -TaskKind "Report" -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "report.windows" -Category "Windows" -DisplayName "Báo cáo bản quyền Windows" -ScriptFile "kiem-tra-cau-hinh-ban-quyen.ps1" -Operation "Windows" -TaskKind "Report" -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "report.office" -Category "Office" -DisplayName "Báo cáo bản quyền Office" -ScriptFile "kiem-tra-cau-hinh-ban-quyen.ps1" -Operation "Office" -TaskKind "Report" -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "report.software" -Category "Security" -DisplayName "Báo cáo phần mềm và dấu hiệu activator" -ScriptFile "kiem-tra-cau-hinh-ban-quyen.ps1" -Operation "Software" -TaskKind "Report" -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "cleanup.scan" -Category "Security" -DisplayName "Quét tuân thủ trước cleanup" -ScriptFile "windows-license-compliance-cleanup.ps1" -Operation "Scan" -TaskKind "CleanupScan" -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback", "NativeCscript") -ExitCodeMap $cleanup),
        (New-ToolModuleDescriptor -ModuleId "cleanup.repair" -Category "Security" -DisplayName "Sửa nhanh nguồn quét" -ScriptFile "windows-license-compliance-cleanup.ps1" -Operation "RepairScanSources" -TaskKind "CleanupScanRepair" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback", "NativeCscript") -ExitCodeMap $cleanup),
        (New-ToolModuleDescriptor -ModuleId "cleanup.remediate" -Category "Security" -DisplayName "Khắc phục mục đã chọn" -ScriptFile "windows-license-compliance-cleanup.ps1" -Operation "Remediate" -TaskKind "CleanupRemediate" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback", "NativeCscript") -ExitCodeMap $cleanup),
        (New-ToolModuleDescriptor -ModuleId "cleanup.deep" -Category "Security" -DisplayName "Cleanup sâu có chọn lọc" -ScriptFile "windows-license-compliance-cleanup.ps1" -Operation "DeepClean" -TaskKind "CleanupDeep" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback", "NativeCscript") -ExitCodeMap $cleanup),
        (New-ToolModuleDescriptor -ModuleId "backup.create" -Category "Backup" -DisplayName "Tạo backup trước cleanup" -ScriptFile "windows-license-backup.ps1" -Operation "Create" -TaskKind "CleanupBackup" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback") -ExitCodeMap $backup),
        (New-ToolModuleDescriptor -ModuleId "restore.apply" -Category "Restore" -DisplayName "Khôi phục backup đã xác thực" -ScriptFile "windows-license-restore.ps1" -Operation "Apply" -TaskKind "CleanupRestore" -AccessMode "SystemChange" -RequiresElevation $true -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "oem.inspect" -Category "OEM" -DisplayName "Kiểm tra key OEM OA3" -ScriptFile "windows-oem-license-assistant.ps1" -Operation "Inspect" -TaskKind "OemInspect" -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "oem.apply" -Category "OEM" -DisplayName "Áp dụng key OEM OA3" -ScriptFile "windows-oem-license-assistant.ps1" -Operation "Apply" -TaskKind "OemApply" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "NativeCscript") -ExitCodeMap $oemApply),
        (New-ToolModuleDescriptor -ModuleId "license.deep-scan" -Category "Windows" -DisplayName "Quét bản quyền chuyên sâu" -ScriptFile "windows-license-deep-scan.ps1" -Operation "Scan" -TaskKind "DeepLicenseScan" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "forensics.scan" -Category "Forensics" -DisplayName "Điều tra bản quyền" -ScriptFile "windows-license-forensics.ps1" -Operation "Scan" -TaskKind "ForensicsScan" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "ScheduledTasksModule|ScheduledTasksFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "license.manager" -Category "Enterprise" -DisplayName "Trung tâm quản lý license doanh nghiệp" -ScriptFile "enterprise-license-manager.ps1" -Operation "Open" -TaskKind "EnterpriseCenter" -AccessMode "SystemChange" -NetworkScope "LocalOnly" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "NativeCscript") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "license.manager.local" -Category "Office" -DisplayName "Quản lý giấy phép cục bộ hợp lệ" -ScriptFile "windows-office-license-manager.ps1" -Operation "Open" -TaskKind "LicenseManager" -AccessMode "SystemChange" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "NativeCscript") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "enterprise.server" -Category "Enterprise" -DisplayName "Máy chủ quản lý license doanh nghiệp" -ScriptFile "Tool-EnterpriseHost.ps1" -Operation "Serve" -TaskKind "EnterpriseServer" -AccessMode "SystemChange" -NetworkScope "Lan" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "enterprise.agent" -Category "Enterprise" -DisplayName "Agent máy trạm quản lý license" -ScriptFile "Tool-EnterpriseAgent.ps1" -Operation "Run" -TaskKind "EnterpriseAgent" -AccessMode "SystemChange" -NetworkScope "Lan" -RequiresElevation $true -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback", "NativeCscript") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "assurance.certificates" -Category "Assurance" -DisplayName "Kiểm tra chứng chỉ số Windows/Office" -ScriptFile "windows-license-assurance.ps1" -Operation "CertificateAudit" -TaskKind "CertificateAudit" -RequiredCapabilities @("SupportedOperatingSystem") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "assurance.plugins" -Category "Assurance" -DisplayName "Đánh giá plugin quy tắc kiểm tra" -ScriptFile "windows-license-assurance.ps1" -Operation "PluginAudit" -TaskKind "PluginAudit" -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "assurance.timeline" -Category "Assurance" -DisplayName "Xuất timeline thay đổi bản quyền" -ScriptFile "windows-license-assurance.ps1" -Operation "TimelineExport" -TaskKind "TimelineExport" -RequiredCapabilities @("SupportedOperatingSystem") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "inventory.registry" -Category "Registry" -DisplayName "Nguồn kiểm kê Registry" -ScriptFile "windows-license-deep-scan.ps1" -Operation "Registry" -IsEntryPoint $false -RequiredCapabilities @("SupportedOperatingSystem") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "inventory.service" -Category "Service" -DisplayName "Nguồn kiểm kê Service" -ScriptFile "windows-license-deep-scan.ps1" -Operation "Service" -IsEntryPoint $false -RequiredCapabilities @("SupportedOperatingSystem", "CimCmdlets|WmiFallback") -ExitCodeMap $completed),
        (New-ToolModuleDescriptor -ModuleId "inventory.task" -Category "Task" -DisplayName "Nguồn kiểm kê Scheduled Task" -ScriptFile "windows-license-deep-scan.ps1" -Operation "Task" -IsEntryPoint $false -RequiredCapabilities @("SupportedOperatingSystem", "ScheduledTasksModule|ScheduledTasksFallback") -ExitCodeMap $completed)
    )
    $script:ToolModuleCatalogCache = @($catalog)
    return @($script:ToolModuleCatalogCache)
}

function Get-ToolModuleDescriptor {
    param([Parameter(Mandatory = $true)][string]$ModuleId)

    $normalized = $ModuleId.Trim().ToLowerInvariant()
    return @(Get-ToolModuleCatalog | Where-Object { $_.ModuleId -eq $normalized } | Select-Object -First 1)[0]
}

function Get-ToolReportModuleId {
    param([Parameter(Mandatory = $true)][string]$Mode)

    switch ($Mode.ToLowerInvariant()) {
        "hardware" { return "report.hardware" }
        "windows" { return "report.windows" }
        "office" { return "report.office" }
        "software" { return "report.software" }
        default { return "report.all" }
    }
}

function Test-ToolModuleCapabilityRequirement {
    param(
        [Parameter(Mandatory = $true)][object]$CapabilityProfile,
        [Parameter(Mandatory = $true)][string]$Requirement
    )

    foreach ($option in @($Requirement.Split([char]124))) {
        $name = $option.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $property = $CapabilityProfile.PSObject.Properties[$name]
        if ($property -and [bool]$property.Value) { return $true }
    }
    return $false
}

function Test-ToolModuleAvailability {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [Parameter(Mandatory = $true)][object]$CapabilityProfile,
        [string]$SourceDirectory = ""
    )

    $descriptor = Get-ToolModuleDescriptor -ModuleId $ModuleId
    if (-not $descriptor) {
        return [pscustomobject][ordered]@{ Available=$false; Status="Unsupported"; ModuleId=$ModuleId; MissingRequirements=@("ModuleNotRegistered"); Message="Mô-đun chưa được đăng ký trong catalog v4.3."; Descriptor=$null }
    }
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($requirement in @($descriptor.RequiredCapabilities)) {
        if (-not (Test-ToolModuleCapabilityRequirement -CapabilityProfile $CapabilityProfile -Requirement $requirement)) { [void]$missing.Add($requirement) }
    }
    if ($descriptor.IsEntryPoint -and -not [string]::IsNullOrWhiteSpace($SourceDirectory)) {
        $scriptPath = Join-Path $SourceDirectory $descriptor.ScriptFile
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { [void]$missing.Add("ScriptFile:$($descriptor.ScriptFile)") }
    }
    $available = [bool]($missing.Count -eq 0)
    return [pscustomobject][ordered]@{
        Available = $available
        Status = if ($available) { "Available" } else { "Unsupported" }
        ModuleId = $descriptor.ModuleId
        MissingRequirements = @($missing.ToArray())
        Message = if ($available) { "Mô-đun sẵn sàng theo capability hiện tại." } else { "Thiếu điều kiện: $($missing.ToArray() -join ', ')." }
        Descriptor = $descriptor
    }
}

function Get-ToolModuleStatusForExitCode {
    param(
        [Parameter(Mandatory = $true)][object]$Descriptor,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    $key = [string]$ExitCode
    if ($Descriptor.ExitCodeMap -and $Descriptor.ExitCodeMap.Contains($key)) { return [string]$Descriptor.ExitCodeMap[$key] }
    if ($ExitCode -eq 0) { return "Completed" }
    return "Failed"
}

function New-ToolModuleInvocation {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleId,
        [string]$CorrelationId = $env:TOOL_CORRELATION_ID,
        [string]$InvocationId = $env:TOOL_MODULE_INVOCATION_ID
    )

    $descriptor = Get-ToolModuleDescriptor -ModuleId $ModuleId
    if (-not $descriptor) { throw "Mô-đun chưa đăng ký: $ModuleId" }
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = [Guid]::NewGuid().ToString("N") }
    if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString("N") }
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolModuleContractSchemaVersion
        InvocationId = ConvertTo-ToolContractSafeText $InvocationId 64
        CorrelationId = ConvertTo-ToolContractSafeText $CorrelationId 64
        ModuleId = $descriptor.ModuleId
        ToolVersion = $script:ToolModuleContractToolVersion
        StartedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

function Complete-ToolModuleInvocation {
    param(
        [Parameter(Mandatory = $true)][object]$Invocation,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$Summary = "",
        [string[]]$OutputPaths = @(),
        [int]$FindingCount = 0,
        [int]$WarningCount = 0,
        [int]$ErrorCount = 0
    )

    $descriptor = Get-ToolModuleDescriptor -ModuleId ([string]$Invocation.ModuleId)
    if (-not $descriptor) { throw "Invocation tham chiếu mô-đun chưa đăng ký." }
    $completedAt = [DateTime]::UtcNow
    $startedAt = $completedAt
    try { $startedAt = [DateTime]::Parse([string]$Invocation.StartedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch {}
    $duration = [long][Math]::Max(0, [Math]::Round(($completedAt - $startedAt).TotalMilliseconds))
    $status = Get-ToolModuleStatusForExitCode -Descriptor $descriptor -ExitCode $ExitCode
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolModuleResultSchemaVersion
        InvocationId = ConvertTo-ToolContractSafeText $Invocation.InvocationId 64
        CorrelationId = ConvertTo-ToolContractSafeText $Invocation.CorrelationId 64
        ModuleId = $descriptor.ModuleId
        ToolVersion = $script:ToolModuleContractToolVersion
        Category = $descriptor.Category
        AccessMode = $descriptor.AccessMode
        StartedAtUtc = [string]$Invocation.StartedAtUtc
        CompletedAtUtc = $completedAt.ToString("o")
        DurationMs = $duration
        Status = $status
        ExitCode = [int]$ExitCode
        Summary = ConvertTo-ToolContractSafeText $Summary 2048
        FindingCount = [Math]::Max(0, $FindingCount)
        WarningCount = [Math]::Max(0, $WarningCount)
        ErrorCount = [Math]::Max(0, $ErrorCount)
        OutputPaths = @($OutputPaths | ForEach-Object { ConvertTo-ToolContractSafeText $_ 1024 } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

function Test-ToolModuleResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([string]$Result.SchemaVersion -ne $script:ToolModuleResultSchemaVersion) { [void]$errors.Add("Sai SchemaVersion.") }
    if ([string]$Result.ToolVersion -ne $script:ToolModuleContractToolVersion) { [void]$errors.Add("Sai ToolVersion.") }
    if (-not (Get-ToolModuleDescriptor -ModuleId ([string]$Result.ModuleId))) { [void]$errors.Add("ModuleId chưa đăng ký.") }
    if ([string]$Result.Status -notin @("Completed", "CompletedWithFindings", "ActionRequired", "Blocked", "Failed", "Cancelled", "Unsupported")) { [void]$errors.Add("Status không thuộc hợp đồng.") }
    if ([long]$Result.DurationMs -lt 0 -or [int]$Result.FindingCount -lt 0 -or [int]$Result.WarningCount -lt 0 -or [int]$Result.ErrorCount -lt 0) { [void]$errors.Add("Các bộ đếm/thời lượng không được âm.") }
    return [pscustomobject][ordered]@{ Valid=[bool]($errors.Count -eq 0); Errors=@($errors.ToArray()) }
}

function Get-ToolModuleContractMetadata {
    $catalog = @(Get-ToolModuleCatalog)
    return [pscustomobject][ordered]@{
        ContractSchemaVersion = $script:ToolModuleContractSchemaVersion
        ResultSchemaVersion = $script:ToolModuleResultSchemaVersion
        ToolVersion = $script:ToolModuleContractToolVersion
        ModuleCount = $catalog.Count
        EntryPointCount = @($catalog | Where-Object IsEntryPoint).Count
        Categories = @($catalog.Category | Sort-Object -Unique)
    }
}
