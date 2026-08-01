param(
    [string]$OutputDir = "",
    [string[]]$ApprovedKmsServers = @(),
    [string]$ApprovedKmsServerFile = "",
    [switch]$TreatUnapprovedKmsAsNonCompliant,
    [switch]$Remediate,
    [switch]$DeepClean,
    [switch]$NoRestorePoint,
    [switch]$RedactSensitive,
    [string]$DecisionFile = "",
    [string]$SelectionFile = "",
    [switch]$RepairScanSources
)

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host "Cong cu can PowerShell 3.0 tro len. Windows 7 co the cai Windows Management Framework 3+ de chay."
    exit 10
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$scanOptimizationHelper = Join-Path $PSScriptRoot "Tool-ScanOptimization.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1." }
    if (-not (Test-Path -LiteralPath $reportSchemaHelper -PathType Leaf)) { throw "Thiếu Tool-ReportSchema.ps1." }
    if (-not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf)) { throw "Thiếu Tool-SafetyPolicy.ps1." }
    if (-not (Test-Path -LiteralPath $scanOptimizationHelper -PathType Leaf)) { throw "Thiếu Tool-ScanOptimization.ps1." }
    . $runtimeHelper
    . $reportSchemaHelper
    . $safetyPolicyHelper
    . $scanOptimizationHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeCertutilPath = Get-ToolNativeSystemPath "certutil.exe"
    $nativeSfcPath = Get-ToolNativeSystemPath "sfc.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $PSScriptRoot "license-cleanup-reports" }
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }
$script:StrictActivatorPattern = "(?i)(kmspico|kmsauto|auto[\s_-]*kms|autokms|kms[_-]?vl|kms-r|aact(?:portable)?|sppextcomobj(?:patcher|hook)|microsoft toolkit|hwidgen|\bmassgrave\b)"
try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
catch { Write-Host "Không tải được System.Security để bảo vệ khóa backup."; exit 11 }
$script:SensitiveKmsHosts = @()
$script:ScanWarnings = New-Object System.Collections.Generic.List[string]
$script:CimCache = @{}
$script:ScheduledTaskRecordsCache = $null
$script:WindowsLicenseSourceNote = ""

function Add-ScanWarning([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and -not $script:ScanWarnings.Contains($Message)) {
        [void]$script:ScanWarnings.Add($Message)
    }
}

function Reset-ScanCaches {
    $script:CimCache = @{}
    $script:ScheduledTaskRecordsCache = $null
}

function Protect-CleanupReportText($Value) {
    if ($null -eq $Value) { return "" }
    # Một số tiện ích native (đặc biệt sfc.exe) có thể trả chuỗi UTF-16 qua
    # console khiến Windows PowerShell chèn NUL giữa từng ký tự. Loại NUL ở
    # ranh giới báo cáo để JSON, hộp thoại và Notepad không hiển thị rác.
    $text = ([string]$Value) -replace "`0", ""
    if (-not $RedactSensitive) { return $text }

    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
            $pattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $pattern, "[ĐÃ CHE]", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    foreach ($hostName in @($script:SensitiveKmsHosts | Sort-Object Length -Descending -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$hostName)) {
            $text = [regex]::Replace($text, [regex]::Escape([string]$hostName), "[KMS ĐÃ CHE]", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $ipv4Part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$ipv4Part(?:\.$ipv4Part){3}(?![0-9.])", "[IP ĐÃ CHE]")
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', '[MAC ĐÃ CHE]')
    return $text
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Set-ProtectedBackupAcl([string]$Path) {
    $administrators = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $system = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administrators)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administrators, "FullControl", $inheritance, "None", "Allow")))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, "FullControl", $inheritance, "None", "Allow")))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Test-ProtectedDirectoryAcl([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ownerSid -notin @("S-1-5-32-544", "S-1-5-18") -or -not $acl.AreAccessRulesProtected) { return $false }
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $allowedWriters -notcontains $rule.IdentityReference.Value -and (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-SecureBackupRoot {
    $commonData = [Environment]::GetFolderPath("CommonApplicationData")
    if ([string]::IsNullOrWhiteSpace($commonData)) { throw "Không xác định được thư mục ProgramData." }
    $productRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra"
    $versionRoot = Join-Path $productRoot "v4.4"
    $backupRoot = Join-Path $versionRoot "backups"
    foreach ($path in @($productRoot, $versionRoot, $backupRoot)) {
        if (Test-Path -LiteralPath $path) {
            $existing = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Vùng backup không hợp lệ hoặc là reparse point: $path" }
        } else { Ensure-Dir $path }
        Set-ProtectedBackupAcl $path
        if (-not (Test-ProtectedDirectoryAcl $path)) { throw "ACL vùng backup không đạt yêu cầu: $path" }
    }
    return $backupRoot
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-PathHash([string]$Path) {
    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Từ chối reparse point: $Path" }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw "Thư mục chứa reparse point: $Path" }
    foreach ($file in @($children | Where-Object { -not $_.PSIsContainer })) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $lines.Add(($relative + "|" + (Get-Sha256 $file.FullName)))
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-MachineBinding {
    $machineGuid = ""
    try { $machineGuid = [string](Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction Stop).MachineGuid } catch {}
    $bytes = [Text.Encoding]::UTF8.GetBytes(($env:COMPUTERNAME + "|" + $machineGuid))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2", [string]$CriticalLabel = "", [switch]$NoCache)
    $cacheKey = ($Namespace + "|" + $ClassName).ToLowerInvariant()
    if (-not $NoCache -and $script:CimCache.ContainsKey($cacheKey)) {
        return @($script:CimCache[$cacheKey])
    }
    $firstError = ""
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $result = @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
            if (-not $NoCache) { $script:CimCache[$cacheKey] = @($result) }
            return $result
        }
    } catch { $firstError = $_.Exception.Message }
    try {
        $result = @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
        if (-not $NoCache) { $script:CimCache[$cacheKey] = @($result) }
        return $result
    } catch {
        if (-not [string]::IsNullOrWhiteSpace($CriticalLabel)) {
            $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
            Add-ScanWarning "${CriticalLabel}: $detail"
        }
        return @()
    }
}

function Get-CompatibleScheduledTaskRecords {
    param([switch]$NoCache)
    if (-not $NoCache -and $null -ne $script:ScheduledTaskRecordsCache) {
        return @($script:ScheduledTaskRecordsCache)
    }
    $firstError = ""
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $records = @(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    TaskName = [string]$_.TaskName
                    TaskPath = [string]$_.TaskPath
                    FullName = ([string]$_.TaskPath + [string]$_.TaskName)
                    ActionsText = [string]($_.Actions | Out-String)
                    WasEnabled = [bool]($_.State -ne "Disabled")
                    Source = "ScheduledTasks"
                }
            })
            if (-not $NoCache) { $script:ScheduledTaskRecordsCache = @($records) }
            return $records
        } catch { $firstError = $_.Exception.Message }
    }

    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw "Không tìm thấy schtasks.exe." }
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw "schtasks không trả danh sách CSV hợp lệ." }
        $rows = @($csvLines | ConvertFrom-Csv)
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($row in $rows) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $fullName = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($fullName)) { continue }
            $lastSlash = $fullName.LastIndexOf('\')
            if ($lastSlash -lt 0 -or $lastSlash -ge ($fullName.Length - 1)) { continue }
            $taskPath = $fullName.Substring(0, $lastSlash + 1)
            $taskName = $fullName.Substring($lastSlash + 1)
            [void]$records.Add([pscustomobject]@{
                TaskName = $taskName
                TaskPath = $taskPath
                FullName = $fullName
                ActionsText = ($values -join " | ")
                WasEnabled = $true
                Source = "Schtasks"
            })
        }
        if ($records.Count -eq 0) { throw "Không phân tích được tên scheduled task từ schtasks." }
        $result = @($records.ToArray())
        if (-not $NoCache) { $script:ScheduledTaskRecordsCache = @($result) }
        return $result
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-ScanWarning "Không thể quét Scheduled Tasks bằng cmdlet hoặc schtasks.exe: $detail"
        return @()
    }
}

function Write-CompatibleTaskXml([string]$Path, [string]$XmlText) {
    $document = New-Object Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.LoadXml($XmlText)
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $settings.Indent = $true
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
}

function Export-CompatibleScheduledTask($Record, [string]$Path) {
    if ([string]$Record.Source -eq "ScheduledTasks" -and (Get-Command Export-ScheduledTask -ErrorAction SilentlyContinue)) {
        $xmlText = [string](Export-ScheduledTask -TaskName ([string]$Record.TaskName) -TaskPath ([string]$Record.TaskPath) -ErrorAction Stop)
        Write-CompatibleTaskXml -Path $Path -XmlText $xmlText
        return
    }
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    $raw = @(& $schtasks /Query /TN ([string]$Record.FullName) /XML 2>&1)
    if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
    Write-CompatibleTaskXml -Path $Path -XmlText (($raw | ForEach-Object { [string]$_ }) -join "`r`n")
}

function Remove-CompatibleScheduledTask($Record) {
    if ([string]$Record.Source -eq "ScheduledTasks" -and (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName ([string]$Record.TaskName) -TaskPath ([string]$Record.TaskPath) -Confirm:$false -ErrorAction Stop
        return
    }
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    $output = @(& $schtasks /Delete /TN ([string]$Record.FullName) /F 2>&1)
    if ($LASTEXITCODE -ne 0) { throw (($output | ForEach-Object { [string]$_ }) -join " | ") }
}

function Import-ApprovedKmsServers {
    if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) {
        return
    }
    if (-not (Test-Path -LiteralPath $ApprovedKmsServerFile)) {
        return
    }
    try {
        $fileServers = Get-Content -LiteralPath $ApprovedKmsServerFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
        if ($fileServers) {
            $combinedServers = @($script:ApprovedKmsServers) + @($fileServers)
            $script:ApprovedKmsServers = @($combinedServers | Select-Object -Unique)
        }
    } catch {
        Write-Warning "Could not read approved KMS server file: $($_.Exception.Message)"
    }
}

function Get-ApprovedKmsConfiguration {
    $valid = New-Object System.Collections.Generic.List[string]
    $invalid = New-Object System.Collections.Generic.List[string]
    $exists = Test-Path -LiteralPath $ApprovedKmsServerFile -PathType Leaf
    if ($exists) {
        try {
            foreach ($line in Get-Content -LiteralPath $ApprovedKmsServerFile -ErrorAction Stop) {
                $value = ([string]$line).Trim()
                if (-not $value -or $value.StartsWith('#')) { continue }
                $candidate = $value -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
                $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
                if ($candidate -match '^[a-zA-Z0-9][a-zA-Z0-9._-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9._-]*)*$' -or
                    $candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$' -or $candidate -match '^[0-9a-fA-F:]+$') {
                    [void]$valid.Add($value)
                } else { [void]$invalid.Add($value) }
            }
        } catch { [void]$invalid.Add("Không đọc được file: $($_.Exception.Message)") }
    }
    $warning = if (-not $exists -or $valid.Count -eq 0) {
        "Danh sách KMS được phê duyệt đang trống; KMS nội bộ hợp pháp có thể bị coi là chưa phê duyệt."
    } elseif ($invalid.Count -gt 0) {
        "Danh sách KMS có $($invalid.Count) dòng không hợp lệ; chỉ các dòng hợp lệ được dùng để bảo vệ KMS."
    } else { "" }
    return [pscustomobject]@{
        Exists = [bool]$exists
        Valid = @($valid | Select-Object -Unique)
        Invalid = @($invalid)
        Warning = $warning
        Path = $ApprovedKmsServerFile
    }
}

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SlmgrCommand {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    $slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
    try {
        $rawOutput = @(& $nativeCscriptPath //nologo $slmgr @SlmgrArguments 2>&1)
        $exitCode = [int]$LASTEXITCODE
        $output = ($rawOutput | ForEach-Object { [string]$_ }) -join "`n"
        $lines = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $isHelpOutput = [bool]($output -match "(?im)^Usage:\s+slmgr\.vbs|^Global Options:|^Advanced Options:")
        $errorLine = $lines | Where-Object {
            $_ -match "(?i)invalid combination of command parameters|(?:^|\s)error(?:\s|:)|0x[0-9a-f]{8}|tham số.+không hợp lệ|(?:^|\s)lỗi(?:\s|:)"
        } | Select-Object -First 1
        $success = [bool]($exitCode -eq 0 -and -not $isHelpOutput -and -not $errorLine)
        if ($success) {
            $summary = ($lines | Select-Object -First 2) -join " | "
            if ([string]::IsNullOrWhiteSpace($summary)) { $summary = "Hoàn tất; lệnh không trả nội dung." }
        } else {
            if ($errorLine) { $summary = "THẤT BẠI: $errorLine" }
            elseif ($isHelpOutput) { $summary = "THẤT BẠI: slmgr không nhận được tổ hợp tham số hợp lệ." }
            else { $summary = "THẤT BẠI: slmgr trả mã thoát $exitCode." }
        }
        if ($summary.Length -gt 320) { $summary = $summary.Substring(0, 317) + "..." }
        return [pscustomobject]@{
            Success = $success
            ExitCode = $exitCode
            Summary = $summary
            Output = $output
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            ExitCode = -1
            Summary = "THẤT BẠI: $($_.Exception.Message)"
            Output = "ERROR: $($_.Exception.Message)"
        }
    }
}

function Run-Cscript {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    return [string](Invoke-SlmgrCommand -SlmgrArguments $SlmgrArguments).Output
}

function Run-SlmgrActionText {
    param([Parameter(Mandatory = $true)][string[]]$SlmgrArguments)
    return [string](Invoke-SlmgrCommand -SlmgrArguments $SlmgrArguments).Summary
}

function ConvertFrom-OfficeLicenseStatus {
    param(
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$Path
    )

    # /dstatusall trả nhiều SKU trong cùng một lần gọi. Bản cũ kiểm tra toàn
    # bộ output như một khối rồi chỉ lấy Last5 đầu tiên, vì vậy gỡ xong một
    # Office KMS mới phát hiện SKU KMS kế tiếp. Tách từng khối SKU để tất cả
    # key KMS đang cài được nhìn thấy và chọn xử lý ngay trong một lượt.
    $entries = New-Object System.Collections.Generic.List[object]
    $normalized = ([string]$StatusText) -replace "`0", "" -replace "`r", ""
    $blocks = [regex]::Split($normalized, '(?m)^\s*-{20,}\s*$')
    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        if ($block -notmatch '(?i)(VOLUME_KMSCLIENT|KMSCLIENT|_KMS_Client)') { continue }

        $skuMatch = [regex]::Match($block, '(?im)^\s*SKU ID\s*:\s*(?<Value>[^\r\n]+)')
        $nameMatch = [regex]::Match($block, '(?im)^\s*LICENSE NAME\s*:\s*(?<Value>[^\r\n]+)')
        $descriptionMatch = [regex]::Match($block, '(?im)^\s*LICENSE DESCRIPTION\s*:\s*(?<Value>[^\r\n]+)')
        $statusMatch = [regex]::Match($block, '(?im)^\s*LICENSE STATUS\s*:\s*(?<Value>[^\r\n]+)')
        $keyMatch = [regex]::Match($block, '(?im)^\s*(?:Last 5 characters of installed product key|5 k(?:ý|y) tự cuối[^:]*)\s*:\s*(?<Value>[A-Z0-9]{5})\s*$')
        $serverMatch = [regex]::Match($block, '(?im)^\s*(?:KMS machine name(?: from DNS)?|KMS machine registry override defined|Key Management Service machine name)\s*:\s*(?<Value>[^\r\n]+)')

        $last5 = if ($keyMatch.Success) { $keyMatch.Groups['Value'].Value.Trim().ToUpperInvariant() } else { '' }
        $server = if ($serverMatch.Success) { $serverMatch.Groups['Value'].Value.Trim() } else { '' }
        if ($server -match '(?i)not available|không (?:có|khả dụng)') { $server = '' }

        # Một license definition KMS_CLIENT không có key, không có override và
        # đang Unlicensed chỉ là SKU được Office cài sẵn; nó không phải KMS đang
        # hoạt động và không được dùng để khóa kết luận "đủ sạch".
        if ([string]::IsNullOrWhiteSpace($last5) -and [string]::IsNullOrWhiteSpace($server)) { continue }

        $entries.Add([pscustomobject][ordered]@{
            Path = $Path
            SkuId = if ($skuMatch.Success) { $skuMatch.Groups['Value'].Value.Trim() } else { '' }
            LicenseName = if ($nameMatch.Success) { $nameMatch.Groups['Value'].Value.Trim() } else { 'Office KMS' }
            Description = if ($descriptionMatch.Success) { $descriptionMatch.Groups['Value'].Value.Trim() } else { 'KMSCLIENT' }
            LicenseStatus = if ($statusMatch.Success) { $statusMatch.Groups['Value'].Value.Trim(' ', '-') } else { 'Không xác định' }
            Last5 = $last5
            Server = $server
            Status = $block.Trim()
        })
    }
    return @($entries.ToArray())
}

function Get-OfficeKmsEntries {
    # Chỉ trả về từng SKU Office KMS có key hoặc KMS override đang hoạt động.
    # Không đụng tới Retail/OEM/MAK và không báo nhầm license definition KMS
    # đã Unlicensed nhưng không còn product key.
    $entries = New-Object System.Collections.Generic.List[object]
    $osppPaths = @(Get-ToolOptimizedOfficeOsppPaths)
    foreach ($statusResult in @(Invoke-ToolParallelOfficeStatus -CscriptPath $nativeCscriptPath -OsppPaths $osppPaths)) {
        $ospp = [string]$statusResult.Path
        $status = [string]$statusResult.Output
        if (-not $statusResult.Readable) {
            Add-ScanWarning "Không đọc được trạng thái giấy phép Office bằng OSPP.VBS: $ospp"
            continue
        }
        foreach ($entry in @(ConvertFrom-OfficeLicenseStatus -StatusText $status -Path $ospp)) {
            $entries.Add($entry)
        }
    }
    return @($entries.ToArray() | Group-Object { "$($_.Path)|$($_.SkuId)|$($_.Last5)" } | ForEach-Object { $_.Group[0] })
}

function Status-Text {
    param($Code)
    switch ([int]$Code) {
        0 { "Unlicensed" }
        1 { "Licensed" }
        2 { "OOB grace" }
        3 { "OOT grace" }
        4 { "Non-genuine grace" }
        5 { "Notification" }
        6 { "Extended grace" }
        default { "$Code" }
    }
}

function Get-LicenseChannel {
    param($Product)
    $desc = [string]$Product.Description
    if ($desc -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($desc -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($desc -match "OEM") { return "OEM" }
    if ($desc -match "RETAIL") { return "Retail" }
    return "Unknown"
}

function Get-Oa3KeyPresent {
    try {
        $svc = Safe-Cim SoftwareLicensingService
        return -not [string]::IsNullOrWhiteSpace($svc.OA3xOriginalProductKey)
    } catch {
        return $false
    }
}

function Get-WindowsLicenseProducts {
    $queryError = ""
    $allProducts = @()
    $windowsProductsAny = @()
    $querySucceeded = $false
    try {
        $allProducts = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop)
        } else {
            @(Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop)
        }
        $querySucceeded = $true
        $windowsProductsAny = @($allProducts | Where-Object { $_.Name -match "Windows" })
        $windowsProductsWithKey = @($allProducts |
            Where-Object { $_.Name -match "Windows" -and $_.PartialProductKey } |
            Sort-Object LicenseStatus -Descending)
        if ($windowsProductsWithKey.Count -gt 0) { return $windowsProductsWithKey }

        $windowsProductsWithoutKey = @($allProducts |
            Where-Object {
                $_.Name -match "Windows" -and (
                    [int]$_.LicenseStatus -ne 0 -or
                    -not [string]::IsNullOrWhiteSpace([string]$_.KeyManagementServiceMachine)
                )
            } |
            Sort-Object LicenseStatus -Descending)
        if ($windowsProductsWithoutKey.Count -gt 0) {
            $script:WindowsLicenseSourceNote = "WMI/CIM đọc được giấy phép Windows nhưng không thấy PartialProductKey; tiếp tục đánh giá bằng trạng thái, channel và cấu hình KMS."
            return $windowsProductsWithoutKey
        }

        $queryError = "WMI/CIM đọc được SoftwareLicensingProduct nhưng không thấy khóa Windows đang expose PartialProductKey."
    } catch { $queryError = $_.Exception.Message }

    $fallback = @(Get-WindowsLicenseProductsFromSlmgr)
    if ($fallback.Count -gt 0) { return $fallback }
    if ($querySucceeded -and $windowsProductsAny.Count -gt 0) {
        $script:WindowsLicenseSourceNote = "Không thấy product key Windows đang expose qua WMI/CIM hoặc slmgr; coi là chưa có key đang đọc được, không phải lỗi nguồn quét."
        return @()
    }
    if ($querySucceeded -and $allProducts.Count -gt 0 -and $windowsProductsAny.Count -eq 0) {
        $queryError = "WMI/CIM đọc được lớp SoftwareLicensingProduct nhưng không trả bất kỳ mục Windows nào; slmgr cũng không trả kết quả Windows hợp lệ."
    }
    Add-ScanWarning "Không đọc được giấy phép Windows bằng WMI/CIM hoặc slmgr: $queryError"
    return @()
}

function Get-WindowsLicenseProductsFromSlmgr {
    $dlv = Run-Cscript -SlmgrArguments @("/dlv")
    if ([string]::IsNullOrWhiteSpace($dlv) -or $dlv -match "^ERROR:") {
        return @()
    }

    $name = Get-RegexValue $dlv "(?im)^(?:Name|Tên)\s*:\s*(.+)$"
    if ($name -notmatch "Windows" -and $dlv -notmatch "(?i)Windows") {
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Windows (slmgr)" }

    $kmsServer = Get-RegexValue $dlv "(?im)^    KMS machine name from DNS:\s*(.+)$"
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^Key Management Service machine name:\s*(.+)$"
    }
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^(?:Tên máy Dịch vụ Quản lý Khóa|Tên máy KMS|Máy chủ KMS)\s*:\s*(.+)$"
    }
    if ([string]::IsNullOrWhiteSpace($kmsServer)) {
        $kmsServer = Get-RegexValue $dlv "(?im)^    KMS machine IP address:\s*(.+)$"
    }
    if ($kmsServer -match "not available") {
        $kmsServer = ""
    }

    return @([pscustomobject]@{
        ID = Get-RegexValue $dlv "(?im)^(?:Activation ID|ID kích hoạt|ID Kích hoạt)\s*:\s*(.+)$"
        Name = $name
        Description = Get-RegexValue $dlv "(?im)^(?:Description|Mô tả)\s*:\s*(.+)$"
        LicenseStatus = Get-LicenseStatusCodeFromText $dlv
        PartialProductKey = Get-RegexValue $dlv "(?im)^(?:Partial Product Key|Khóa sản phẩm một phần|5 ký tự cuối)\s*:\s*(.+)$"
        KeyManagementServiceMachine = $kmsServer
    })
}

function Get-RegexValue {
    param([string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) {
        return $matches[1].Trim()
    }
    return ""
}

function Get-LicenseStatusCodeFromText {
    param([string]$Text)
    if ($Text -match "(?im)^License Status:\s*Licensed\b") { return 1 }
    if ($Text -match "(?im)^License Status:\s*Unlicensed\b") { return 0 }
    if ($Text -match "(?im)^License Status:\s*Notification\b") { return 5 }
    if ($Text -match "(?im)^License Status:\s*Non-genuine") { return 4 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(đã cấp phép|được cấp phép|licensed)") { return 1 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(chưa cấp phép|unlicensed)") { return 0 }
    if ($Text -match "(?im)^Trạng thái giấy phép\s*:\s*.*(thông báo|notification)") { return 5 }
    return 0
}

function Test-ApprovedKms {
    param([string]$Server)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    if ($candidate -match "^([^:]+):\d+$") { $candidate = $matches[1] }
    if ($candidate -match "^\[([^\]]+)\]:\d+$") { $candidate = $matches[1] }
    foreach ($approved in $ApprovedKmsServers) {
        $approvedCandidate = $approved.Trim().ToLowerInvariant()
        if ($approvedCandidate -match "^([^:]+):\d+$") { $approvedCandidate = $matches[1] }
        if ($approvedCandidate -match "^\[([^\]]+)\]:\d+$") { $approvedCandidate = $matches[1] }
        if ($candidate -eq $approvedCandidate) {
            return $true
        }
    }
    return $false
}

function Get-ActivatorFindings {
    # Mẫu đặc hiệu; không dùng chuỗi ngắn như "mas" vì dễ trùng tên hợp lệ.
    $regex = $script:StrictActivatorPattern
    $findings = New-Object System.Collections.Generic.List[object]

    try {
        Get-CompatibleScheduledTaskRecords | Where-Object {
            $_.TaskName -match $regex -or $_.TaskPath -match $regex -or $_.ActionsText -match $regex
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "ScheduledTask"
                Name = [string]$_.FullName
                Location = ([string]$_.ActionsText).Trim()
                Action = "Disable task during remediation"
            })
        }
    } catch { Add-ScanWarning "Không thể đánh giá Scheduled Tasks: $($_.Exception.Message)" }

    try {
        Safe-Cim -ClassName Win32_Service -CriticalLabel "Không thể quét dịch vụ Windows" | Where-Object {
            $_.Name -match $regex -or $_.DisplayName -match $regex -or $_.PathName -match $regex
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Service"
                Name = $_.Name
                Location = $_.PathName
                Action = "Stop and disable service during remediation"
            })
        }
    } catch { Add-ScanWarning "Không thể đánh giá dịch vụ Windows: $($_.Exception.Message)" }

    try {
        Get-Process | Where-Object {
            $_.ProcessName -match $regex -or $_.Path -match $regex
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Process"
                Name = $_.ProcessName
                Location = $_.Path
                Action = "Stop process during remediation"
            })
        }
    } catch {}

    $scanRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        $env:ProgramData,
        (Join-Path $env:SystemDrive "KMS"),
        (Join-Path $env:SystemDrive "KMSAuto"),
        (Join-Path $env:SystemDrive "KMSpico"),
        (Join-Path $env:SystemDrive "AAct")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($root in $scanRoots) {
        try {
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $regex } |
                ForEach-Object {
                    $findings.Add([pscustomobject]@{
                        Type = "Folder"
                        Name = $_.Name
                        Location = $_.FullName
                        Action = "Review manually; script does not delete folders"
                    })
                }
        } catch {}
    }

    return $findings
}

function New-CleanupItem {
    param(
        [string]$Type,
        [string]$Kind,
        [string]$Name,
        [string]$Location,
        [string]$Detail,
        [string]$TargetId = "",
        [bool]$DefaultSelected = $false
    )
    $id = (($Type + "|" + $Kind + "|" + $Name + "|" + $Location).ToLowerInvariant())
    return [pscustomobject]@{
        Id = $id
        Type = $Type
        Kind = $Kind
        Name = $Name
        Location = $Location
        Detail = $Detail
        TargetId = $TargetId
        DefaultSelected = $DefaultSelected
    }
}

function Get-DeepCleanupCandidates {
    param($Findings)
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($finding in @($Findings)) {
        $type = [string]$finding.Type
        if ($type -in @("Process", "Service", "ScheduledTask", "Folder")) {
            $kind = if ($type -eq "ScheduledTask") { "ActivatorTask" } else { "Activator$type" }
            $items.Add((New-CleanupItem -Type $type -Kind $kind -Name ([string]$finding.Name) `
                -Location ([string]$finding.Location) -Detail ([string]$finding.Action)))
        }
    }

    foreach ($path in @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform",
        "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $server = [string]$item.KeyManagementServiceName
            if ($server -and -not (Test-ApprovedKms $server)) {
                $items.Add((New-CleanupItem -Type "Registry" -Kind "KmsOverride" `
                    -Name "Cấu hình KMS chưa phê duyệt" -Location $path `
                    -Detail "Máy chủ: $server. Chỉ các giá trị KMS tại khóa này sẽ bị xóa."))
            }
        } catch {}
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            $items.Add((New-CleanupItem -Type "Registry" -Kind "SppNoGenTicketPolicy" `
                -Name "Policy SPP NoGenTicket=1" -Location $policyPath `
                -Detail "Xóa riêng giá trị NoGenTicket để Windows có thể tạo vé giấy phép số; khóa policy được backup trước."))
        }
    } catch {}

    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $valueText = (Get-ItemProperty -LiteralPath $path -ErrorAction Stop | Out-String)
            if ($valueText -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") {
                $items.Add((New-CleanupItem -Type "Registry" -Kind "IfeoHook" `
                    -Name "IFEO hook: $imageName" -Location $path `
                    -Detail "Khóa IFEO khớp mẫu hook kích hoạt; khóa sẽ được export trước khi gỡ."))
            }
        } catch {}
    }

    foreach ($hookPath in @(
        (Get-ToolNativeSystemPath "SppExtComObjHook.dll"),
        (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll")
    )) {
        if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
            $items.Add((New-CleanupItem -Type "File" -Kind "HookFile" `
                -Name (Split-Path $hookPath -Leaf) -Location $hookPath `
                -Detail "Tệp hook sẽ được chuyển vào khu cách ly, không xóa vĩnh viễn."))
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if ([string]$excludedPath -match $script:StrictActivatorPattern) {
                $items.Add((New-CleanupItem -Type "Defender" -Kind "ExclusionPath" `
                    -Name "Ngoại lệ Defender" -Location ([string]$excludedPath) `
                    -Detail "Ngoại lệ có đường dẫn khớp mẫu activator."))
            }
        }
    } catch {}

    return @($items | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
}

function Get-AllCleanupCandidates {
    param($Products, $Findings, $OfficeEntries)

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-DeepCleanupCandidates -Findings $Findings)) { $items.Add($item) }

    foreach ($product in @($Products | Where-Object {
        (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
    })) {
        $items.Add((New-CleanupItem -Type "License" -Kind "WindowsKmsLicense" `
            -Name ([string]$product.Name) `
            -Location ("KMS=" + [string]$product.KeyManagementServiceMachine + "; PartialKey=" + [string]$product.PartialProductKey) `
            -TargetId ([string]$product.ID) `
            -Detail "Gỡ đúng khóa KMS Windows chưa phê duyệt; OEM/Retail/MAK hợp lệ vẫn được bảo vệ."))
    }

    $unapprovedOfficeEntries = @($OfficeEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
    foreach ($entry in $unapprovedOfficeEntries) {
        $last5Label = if ([string]::IsNullOrWhiteSpace([string]$entry.Last5)) { "không có key" } else { [string]$entry.Last5 }
        $serverLabel = if ([string]::IsNullOrWhiteSpace([string]$entry.Server)) { "DNS/không có override" } else { [string]$entry.Server }
        $targetId = if (-not [string]::IsNullOrWhiteSpace([string]$entry.SkuId)) { [string]$entry.SkuId } else { "$($entry.Path)|$($entry.Last5)" }
        $items.Add((New-CleanupItem -Type "License" -Kind "OfficeKmsLicense" `
            -Name ("Office KMS $last5Label - " + [string]$entry.LicenseName) `
            -Location ([string]$entry.Path) `
            -TargetId $targetId `
            -Detail ("SKU=" + [string]$entry.SkuId + "; trạng thái=" + [string]$entry.LicenseStatus + "; KMS=" + $serverLabel + ". Chỉ gỡ key/override KMS của SKU này.")))
    }

    return @($items.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
}

function Get-SelectedCleanupIds {
    if ([string]::IsNullOrWhiteSpace($SelectionFile) -or -not (Test-Path -LiteralPath $SelectionFile -PathType Leaf)) {
        return @()
    }
    try {
        $allowedRoot = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $PSScriptRoot "runtime" }
        if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedDirectoryAcl $PSScriptRoot) -or -not (Test-ProtectedDirectoryAcl $allowedRoot)) { return @() }
        $rootFull = ([IO.Path]::GetFullPath($allowedRoot)).TrimEnd('\') + '\'
        $selectionFull = [IO.Path]::GetFullPath($SelectionFile)
        if (-not $selectionFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return @() }
        $selectionItem = Get-Item -LiteralPath $selectionFull -Force -ErrorAction Stop
        if (($selectionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return @() }
        $selection = Get-Content -LiteralPath $SelectionFile -Raw -ErrorAction Stop | ConvertFrom-Json
        return @($selection.SelectedIds | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    } catch {
        return @()
    }
}

function Protect-HistoryText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $safe = $Text -replace "(?i)\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b", "[PRODUCT-KEY-DA-CHE]"
    $safe = $safe -replace '(?i)https?://[^\s"'']+', "[URL-DA-CHE]"
    $safe = ($safe -replace "\s+", " ").Trim()
    if ($safe.Length -gt 240) { $safe = $safe.Substring(0, 240) + "..." }
    return $safe
}

function Get-InvalidActivationHistory {
    # Lịch sử chỉ là bằng chứng quá khứ, không được dùng một mình để kết luận
    # crack vẫn đang hoạt động hoặc để tự động gỡ product key.
    $history = New-Object System.Collections.Generic.List[object]
    $strictPattern = "(?i)(kmspico|kmsauto|auto[\s_-]*kms|kms[_-]?vl|kms-r|aact(?:portable)?|sppextcomobj(?:hook|patcher)|microsoft toolkit|hwidgen|massgrave|digital license activation|\bactivator\b|0xC004F074|VOLUME_KMSCLIENT)"
    $since = (Get-Date).AddDays(-180)

    $eventQueries = @(
        [pscustomobject]@{ LogName="Application"; ProviderName="Microsoft-Windows-Security-SPP"; Source="Nhật ký Software Protection" },
        [pscustomobject]@{ LogName="Microsoft-Windows-Windows Defender/Operational"; ProviderName="Microsoft-Windows-Windows Defender"; Source="Lịch sử Microsoft Defender" },
        [pscustomobject]@{ LogName="Microsoft-Windows-TaskScheduler/Operational"; ProviderName="Microsoft-Windows-TaskScheduler"; Source="Lịch sử Task Scheduler" }
    )
    foreach ($query in $eventQueries) {
        try {
            Get-WinEvent -FilterHashtable @{ LogName=$query.LogName; StartTime=$since } -MaxEvents 500 -ErrorAction Stop |
                Where-Object { ([string]$_.Message) -match $strictPattern } |
                Select-Object -First 50 | ForEach-Object {
                    $history.Add([pscustomobject]@{
                        Time = if ($_.TimeCreated) { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { "Không rõ" }
                        Source = $query.Source
                        EventId = [string]$_.Id
                        Evidence = Protect-HistoryText ([string]$_.Message)
                    })
                }
        } catch {}
    }

    # PSReadLine không lưu thời gian từng lệnh. Chỉ lấy dòng khớp mẫu đặc hiệu,
    # che product key/URL và không sao chép các dòng lịch sử khác.
    try {
        $userRoot = Join-Path $env:SystemDrive "Users"
        Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $historyFile = Join-Path $_.FullName "AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
            if (Test-Path -LiteralPath $historyFile) {
                $lastWrite = (Get-Item -LiteralPath $historyFile -ErrorAction SilentlyContinue).LastWriteTime
                Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match $strictPattern } |
                    Select-Object -Last 25 | ForEach-Object {
                        $history.Add([pscustomobject]@{
                            Time = if ($lastWrite) { "Tệp cập nhật " + $lastWrite.ToString("yyyy-MM-dd HH:mm:ss") } else { "Không có thời gian từng lệnh" }
                            Source = "Lịch sử PowerShell (đã lọc và che dữ liệu)"
                            EventId = "PSReadLine"
                            Evidence = Protect-HistoryText ([string]$_)
                        })
                    }
            }
        }
    } catch {}

    return @($history | Sort-Object Time -Descending | Select-Object -First 150)
}

function Get-ActivationConfigurationResidues {
    $residues = New-Object System.Collections.Generic.List[object]
    $sppPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform",
        "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
    )
    foreach ($path in $sppPaths) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $server = [string]$item.KeyManagementServiceName
            if ($server -and -not (Test-ApprovedKms $server)) {
                $residues.Add([pscustomobject]@{ Type="KMSConfig"; Name="Máy chủ KMS chưa phê duyệt"; Location=$path; Value=$server })
            }
        } catch {}
    }

    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $valueText = ($item | Out-String)
            if ($valueText -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") {
                $residues.Add([pscustomobject]@{ Type="IFEO"; Name=$imageName; Location=$path; Value=(Protect-HistoryText $valueText) })
            }
        } catch {}
    }

    foreach ($dllPath in @(
        (Get-ToolNativeSystemPath "SppExtComObjHook.dll"),
        (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll")
    )) {
        if (Test-Path -LiteralPath $dllPath) {
            $residues.Add([pscustomobject]@{ Type="HookFile"; Name="SppExtComObjHook.dll"; Location=$dllPath; Value="Tệp hook cấp phép còn tồn tại" })
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if ([string]$excludedPath -match $script:StrictActivatorPattern) {
                $residues.Add([pscustomobject]@{ Type="DefenderExclusion"; Name="Ngoại lệ Defender đáng ngờ"; Location=[string]$excludedPath; Value="Cần gỡ ngoại lệ" })
            }
        }
    } catch {}

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            $residues.Add([pscustomobject]@{ Type="SPPPolicy"; Name="NoGenTicket=1"; Location=$policyPath; Value="Có thể chặn tạo ticket giấy phép số; cần gỡ nếu không phải chính sách doanh nghiệp." })
        }
    } catch {}
    return $residues
}

function Get-ActivationReadinessDiagnostics {
    # Chẩn đoán bổ sung, chỉ đọc. Các kết quả này không thay đổi quyết định
    # ReadyForOfficialActivation hiện có để giữ tương thích v3.0.
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($serviceName in @("sppsvc", "osppsvc", "w32time")) {
        try {
            $svc = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
            if (-not $svc) {
                $checks.Add([pscustomobject]@{ Name="Dịch vụ $serviceName"; Status="Không cài/không áp dụng"; Detail="Không tìm thấy dịch vụ trên máy này." })
            } elseif ([string]$svc.StartMode -eq "Disabled") {
                $checks.Add([pscustomobject]@{ Name="Dịch vụ $serviceName"; Status="Cần xem xét"; Detail="Dịch vụ đang bị Disabled; không tự bật trong bước kiểm tra." })
            } else {
                $checks.Add([pscustomobject]@{ Name="Dịch vụ $serviceName"; Status="Đạt"; Detail="StartMode=$($svc.StartMode); State=$($svc.State)." })
            }
        } catch {
            $checks.Add([pscustomobject]@{ Name="Dịch vụ $serviceName"; Status="Chưa xác minh"; Detail="Không đọc được trạng thái dịch vụ." })
        }
    }

    foreach ($filePath in @(
        (Get-ToolNativeSystemPath "sppsvc.exe"),
        (Get-ToolNativeSystemPath "SppExtComObj.exe"),
        (Get-ToolNativeSystemPath "sppwinob.dll")
    )) {
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            $checks.Add([pscustomobject]@{ Name="Tệp cấp phép"; Status="Cần xem xét"; Detail="Thiếu: $filePath" })
            continue
        }
        $signature = "Không kiểm tra được"
        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $filePath -ErrorAction Stop
            $signature = [string]$sig.Status
        } catch {}
        $status = if ($signature -eq "Valid") { "Đạt" } elseif ($signature -eq "NotSigned") { "Cần xem xét" } else { "Chưa xác minh" }
        $checks.Add([pscustomobject]@{ Name="Chữ ký tệp cấp phép"; Status=$status; Detail="$filePath | Authenticode=$signature" })
    }

    $pending = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($pending.Count -gt 0) {
        $checks.Add([pscustomobject]@{ Name="Khởi động lại đang chờ"; Status="Cần xem xét"; Detail="Windows có yêu cầu khởi động lại; nên khởi động lại trước khi kích hoạt chính thức." })
    } else {
        $checks.Add([pscustomobject]@{ Name="Khởi động lại đang chờ"; Status="Đạt"; Detail="Không thấy cờ khởi động lại phổ biến." })
    }
    return $checks.ToArray()
}

function Get-CleanupVerification {
    param($Products, $Findings, $OfficeEntries, $History)
    $unapprovedWindows = @($Products | Where-Object {
        (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
    })
    $unapprovedOffice = @($OfficeEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
    $residues = @(Get-ActivationConfigurationResidues)
    $blockerCount = [int]($unapprovedWindows.Count + $unapprovedOffice.Count + @($Findings).Count + $residues.Count)
    $scanWarnings = @($script:ScanWarnings | Select-Object -Unique)
    $ready = [bool]($blockerCount -eq 0 -and $scanWarnings.Count -eq 0)
    $protected = Get-ProtectedLicenseInfo -Products $Products
    $readiness = @(Get-ActivationReadinessDiagnostics)
    $readinessReviewCount = @($readiness | Where-Object { $_.Status -in @("Cần xem xét", "Chưa xác minh") }).Count
    $conclusion = if ($scanWarnings.Count -gt 0) {
        "CHƯA THỂ KẾT LUẬN: một hoặc nhiều nguồn quét quan trọng không đọc được. Tool không được phép báo ĐẠT cho đến khi quét lại đầy đủ."
    } elseif (-not $ready) {
        "CHƯA ĐỦ SẠCH: còn dấu hiệu/cấu hình kích hoạt không hợp lệ. Chưa nên nhập key hoặc đăng nhập bản quyền chính thức."
    } elseif ([bool]$protected.Protected) {
        "ĐẠT: không còn dấu hiệu kích hoạt không hợp lệ đang hoạt động; giấy phép $($protected.Channel) hiện có được bảo vệ."
    } else {
        "ĐẠT: cấu hình kích hoạt không hợp lệ đã được loại bỏ trong phạm vi kiểm tra. Máy đủ điều kiện kỹ thuật để kích hoạt bằng key/tài khoản chính thức."
    }
    $handlingGuidance = New-Object System.Collections.Generic.List[string]
    if ($scanWarnings.Count -gt 0) {
        $handlingGuidance.Add("Nguồn quét bị lỗi: xem mục Cảnh báo quét, chạy lại bằng Administrator; nếu lỗi WMI/CIM hãy sửa WMI, nếu lỗi Scheduled Tasks hãy kiểm tra Task Scheduler/schtasks.exe. Không tiếp tục gỡ hoặc kết luận đủ sạch khi cảnh báo còn tồn tại.")
    }
    if ($unapprovedWindows.Count -gt 0) {
        $handlingGuidance.Add("Windows KMS chưa phê duyệt: nếu là máy cơ quan, kết nối mạng/VPN nội bộ và nhờ bộ phận quản trị hệ thống xác nhận đúng máy chủ KMS trước khi thêm vào danh sách phê duyệt; nếu là máy cá nhân, thay bằng Retail/MAK hoặc giấy phép số chính thức tại Settings > Activation > Change product key.")
    }
    if ($unapprovedOffice.Count -gt 0) {
        $officeLabels = @($unapprovedOffice | ForEach-Object {
            $keyLabel = if ([string]::IsNullOrWhiteSpace([string]$_.Last5)) { "không có key" } else { [string]$_.Last5 }
            "$([string]$_.LicenseName) [$keyLabel]"
        })
        $handlingGuidance.Add("Office KMS còn lại: $($officeLabels -join '; '). Nếu là KMS nội bộ hợp pháp, hãy để quản trị viên xác nhận máy chủ; nếu không, chọn 'Xử lý mục còn lại' để gỡ đúng từng key KMS rồi dùng mục 8 đăng nhập Microsoft 365/nhập key chính thức.")
    }
    if (@($Findings).Count -gt 0) {
        $handlingGuidance.Add("Còn activator đang hoạt động: tạo backup, mở danh sách gỡ sạch nâng cao, đánh dấu đúng từng service/task/process/thư mục được nhận diện, xử lý rồi khởi động lại và quét lại.")
    }
    if ($residues.Count -gt 0) {
        $handlingGuidance.Add("Còn cấu hình/tồn dư: xem từng dòng Tồn dư trong báo cáo, chỉ chọn đúng mục tương ứng để xử lý; không xóa Registry, service hoặc tệp hệ thống bằng tay.")
    }
    if ($ready) {
        $handlingGuidance.Add("Đã đủ sạch: kích hoạt bằng giấy phép chính thức, sau đó chạy lại mục 6 và lưu báo cáo hậu kiểm.")
    }
    if ($readinessReviewCount -gt 0) {
        $handlingGuidance.Add("Có chẩn đoán sẵn sàng cần xem xét: khởi động lại nếu Windows đang chờ reboot; nếu dịch vụ/tệp cấp phép lỗi, sửa Windows/Office bằng công cụ chính thức trước khi kích hoạt.")
    }
    if (@($History).Count -gt 0) {
        $handlingGuidance.Add("Dấu vết lịch sử chỉ để tham khảo; không cần xóa Event Log hoặc lịch sử Defender và không dùng chúng làm lý do tiếp tục gỡ.")
    }
    return [pscustomobject]@{
        ReadyForOfficialActivation = $ready
        ActiveActivatorFindingCount = [int]@($Findings).Count
        UnapprovedWindowsKmsCount = [int]$unapprovedWindows.Count
        UnapprovedOfficeKmsCount = [int]$unapprovedOffice.Count
        ConfigurationResidueCount = [int]$residues.Count
        HistoryFindingCount = [int]@($History).Count
        ReadinessReviewCount = [int]$readinessReviewCount
        ScanWarningCount = [int]$scanWarnings.Count
        ScanWarnings = $scanWarnings
        ReadinessChecks = $readiness
        Residues = $residues
        ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
        ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
        InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
        ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
        Conclusion = $conclusion
        HandlingGuidance = $handlingGuidance.ToArray()
        ScopeNote = "Kết luận phản ánh cấu hình cấp phép trong phạm vi tool kiểm tra, không chứng minh ảnh Windows là bản gốc nhà máy và không thay thế hóa đơn/hồ sơ cấp phép."
    }
}

function Get-CleanupNextActions {
    param(
        $Verification,
        $CleanupItems,
        [bool]$ProtectedLicense,
        [string]$BackupDirectory = ""
    )

    $next = New-Object System.Collections.Generic.List[object]
    $remaining = @($CleanupItems)
    if ([int]$Verification.ScanWarningCount -gt 0) {
        $next.Add([pscustomobject]@{ Code="RepairScanSources"; Label="Sửa nguồn quét"; Detail="Khắc phục nguồn WMI/Task Scheduler/dịch vụ theo policy an toàn rồi hậu kiểm lại."; CandidateCount=0 })
        $next.Add([pscustomobject]@{ Code="Recheck"; Label="Quét lại"; Detail="Chạy lại toàn bộ bước kiểm tra trước khi cho phép thay đổi."; CandidateCount=0 })
    } elseif ([bool]$Verification.ReadyForOfficialActivation) {
        if (-not $ProtectedLicense) {
            $next.Add([pscustomobject]@{ Code="OpenLicenseManager"; Label="Kích hoạt hợp lệ"; Detail="Mở mục 8 để nhập key chính thức hoặc đăng nhập tài khoản có giấy phép."; CandidateCount=0 })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label="Hậu kiểm lại"; Detail="Quét lại sau khi kích hoạt để lưu kết quả cuối."; CandidateCount=0 })
    } else {
        if ($remaining.Count -gt 0) {
            $next.Add([pscustomobject]@{ Code="RemediateRemaining"; Label="Xử lý mục còn lại"; Detail="Mở danh sách mới sau hậu kiểm và chỉ xử lý các mục được đánh dấu."; CandidateCount=[int]$remaining.Count })
        }
        if ([int]$Verification.UnapprovedWindowsKmsCount -gt 0 -or [int]$Verification.UnapprovedOfficeKmsCount -gt 0) {
            $next.Add([pscustomobject]@{ Code="ConfigureApprovedKms"; Label="Xác nhận KMS nội bộ"; Detail="Chỉ dùng khi quản trị viên xác nhận đây là máy chủ KMS hợp pháp của đơn vị."; CandidateCount=[int]($Verification.UnapprovedWindowsKmsCount + $Verification.UnapprovedOfficeKmsCount) })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label="Quét lại"; Detail="Kiểm tra lại trạng thái hiện tại mà không tự thay đổi hệ thống."; CandidateCount=0 })
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $next.Add([pscustomobject]@{ Code="RestoreBackup"; Label="Khôi phục backup"; Detail="Mở luồng khôi phục có kiểm tra ACL, HMAC, đúng máy và SHA-256."; CandidateCount=0 })
    }
    $next.Add([pscustomobject]@{ Code="OpenReport"; Label="Mở báo cáo"; Detail="Xem toàn bộ bằng chứng và nhật ký hành động."; CandidateCount=0 })
    return @($next.ToArray())
}

function Get-ComplianceDecision {
    param($Products, $Findings)
    $oa3 = Get-Oa3KeyPresent
    $licensed = $Products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $current = if ($licensed) { $licensed } else { $Products | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
    if (-not $current) {
        return [pscustomobject]@{
            Decision = "Chưa kích hoạt hoặc chưa có giấy phép"
            Reason = "Không tìm thấy product key Windows để đánh giá."
            ShouldRemediate = $false
        }
    }

    $channel = Get-LicenseChannel $current
    $kmsServer = [string]$current.KeyManagementServiceMachine
    $hasActivator = ($Findings.Count -gt 0)

    if ($hasActivator) {
        return [pscustomobject]@{
                Decision = "Không hợp lệ hoặc đáng ngờ"
                Reason = "Đã phát hiện dấu hiệu activator/KMS/crack."
            ShouldRemediate = $true
        }
    }
    if ($channel -eq "KMS") {
        if (Test-ApprovedKms $kmsServer) {
            return [pscustomobject]@{
                Decision = "Giữ nguyên kích hoạt"
                Reason = "Windows được cấp phép qua máy chủ KMS đã phê duyệt: $kmsServer"
                ShouldRemediate = $false
            }
        }
        if ($TreatUnapprovedKmsAsNonCompliant) {
            return [pscustomobject]@{
                Decision = "Không hợp lệ hoặc đáng ngờ"
                Reason = "KMS không nằm trong danh sách máy chủ được phê duyệt."
                ShouldRemediate = $true
            }
        }
        return [pscustomobject]@{
            Decision = "Cần kiểm tra thủ công"
            Reason = "Đã phát hiện KMS. Hãy thêm máy chủ được phê duyệt hoặc chạy lại với tùy chọn coi KMS chưa phê duyệt là không hợp lệ."
            ShouldRemediate = $false
        }
    }
    if ($licensed -and $channel -in @("OEM", "Retail", "MAK")) {
        return [pscustomobject]@{
            Decision = "Giữ nguyên kích hoạt"
            Reason = "Windows đã kích hoạt, kênh là $channel. Cần đối chiếu hóa đơn/hồ sơ cấp phép riêng."
            ShouldRemediate = $false
        }
    }
    if ([int]$current.LicenseStatus -ne 1) {
        return [pscustomobject]@{
            Decision = "Chưa kích hoạt hoặc giấy phép cần kiểm tra"
            Reason = "Windows có product key kênh $channel nhưng trạng thái là $(Status-Text $current.LicenseStatus). Trạng thái này không đủ chứng minh có crack nên không tự gỡ key."
            ShouldRemediate = $false
        }
    }
    if ($oa3) {
        return [pscustomobject]@{
            Decision = "Giữ nguyên kích hoạt"
            Reason = "Có khóa OEM OA3 trong firmware. Cần kiểm tra khớp phiên bản Windows riêng."
            ShouldRemediate = $false
        }
    }
    return [pscustomobject]@{
        Decision = "Cần kiểm tra thủ công"
        Reason = "Có trạng thái đã cấp phép nhưng chưa xác định được kênh."
        ShouldRemediate = $false
    }
}

function Get-ProtectedLicenseInfo {
    param($Products)
    $licensed = $Products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    if ($licensed) {
        $channel = Get-LicenseChannel $licensed
        if ($channel -in @("OEM", "Retail", "MAK")) {
            return [pscustomobject]@{
                Protected = $true
                Channel = $channel
                Reason = "Windows đang kích hoạt bằng kênh $channel. Khóa này được bảo vệ và không bị gỡ tự động."
            }
        }
        if ($channel -eq "KMS" -and (Test-ApprovedKms ([string]$licensed.KeyManagementServiceMachine))) {
            return [pscustomobject]@{
                Protected = $true
                Channel = "KMS được phê duyệt"
                Reason = "Windows đang dùng máy chủ KMS đã được phê duyệt."
            }
        }
    }
    if (Get-Oa3KeyPresent) {
        return [pscustomobject]@{
            Protected = $true
            Channel = "OEM OA3"
            Reason = "Máy có khóa OEM OA3 trong firmware. Khóa này được bảo vệ và không bị gỡ tự động."
        }
    }
    return [pscustomobject]@{
        Protected = $false
        Channel = if ($licensed) { Get-LicenseChannel $licensed } else { "Chưa xác định" }
        Reason = "Không phát hiện kênh OEM/Retail/MAK hoặc KMS được phê duyệt cần bảo vệ."
    }
}

function Write-DecisionData {
    param([string]$Path, $Data)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $parent = Split-Path -Parent $Path
        if ($parent) { Ensure-Dir $parent }
        $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        Write-Warning "Không thể ghi kết quả kiểm tra nhanh: $($_.Exception.Message)"
    }
}

function Invoke-ScanSourceRepair {
    $actions = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[object]
    $guidance = New-Object System.Collections.Generic.List[string]
    $serviceStateBefore = New-Object System.Collections.Generic.List[object]
    $serviceStateAfter = New-Object System.Collections.Generic.List[object]
    $startedServices = New-Object System.Collections.Generic.List[string]

    function Add-RepairCheck([string]$Name, [string]$Status, [string]$Detail) {
        $checks.Add([pscustomobject]@{ Name=$Name; Status=$Status; Detail=$Detail })
    }

    function Get-ServiceStateSnapshot([string]$Name, [string]$DisplayName) {
        $service = Get-Service -Name $Name -ErrorAction Stop
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
        $startValue = [int]$registry.Start
        $startMode = switch ($startValue) {
            0 { "Boot" }
            1 { "System" }
            2 { if ([int]$registry.DelayedAutoStart -eq 1) { "AutomaticDelayed" } else { "Automatic" } }
            3 { "Manual" }
            4 { "Disabled" }
            default { "Unknown:$startValue" }
        }
        return [pscustomobject][ordered]@{
            Name = $Name
            DisplayName = $DisplayName
            Status = [string]$service.Status
            WasRunning = [bool]($service.Status -eq "Running")
            StartValue = $startValue
            StartMode = $startMode
        }
    }

    function Repair-ServiceState($Policy) {
        $name = [string]$Policy.Name
        $displayName = [string]$Policy.DisplayName
        try {
            $before = Get-ServiceStateSnapshot -Name $name -DisplayName $displayName
            $serviceStateBefore.Add($before)
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                if ($before.StartMode -eq "Disabled") {
                    Add-RepairCheck $displayName "Còn lỗi" "Dịch vụ $name đang Disabled. Quick repair không tự đổi StartupType hoặc ghi đè chính sách quản trị."
                    $actions.Add("KHÔNG THAY ĐỔI: dịch vụ $name đang Disabled; cần quản trị viên xác minh Group Policy/cấu hình hệ thống.")
                    return
                }
                if (-not [bool]$Policy.AllowStart) {
                    Add-RepairCheck $displayName "Còn lỗi" "Chính sách an toàn không cho phép quick repair khởi động dịch vụ $name."
                    return
                }
                Start-Service -Name $name -ErrorAction Stop
                $startedServices.Add($name)
                $actions.Add("Đã khởi động dịch vụ $name bằng StartupType hiện có; không thay đổi cấu hình khởi động.")
                $svc = Get-Service -Name $name -ErrorAction Stop
            }
            Add-RepairCheck $displayName "Đạt" "Dịch vụ $name đang $($svc.Status); StartupType giữ nguyên: $($before.StartMode)."
        } catch {
            Add-RepairCheck $displayName "Còn lỗi" "Không khởi động/đọc được dịch vụ ${name}: $($_.Exception.Message)"
            $actions.Add("CẢNH BÁO: không sửa được dịch vụ ${name}: $($_.Exception.Message)")
        }
    }

    $actions.Add("Bắt đầu kiểm tra/khắc phục nhanh nguồn quét quan trọng theo policy schema 1.0.")
    $actions.Add("Quick repair không thay đổi StartupType; dịch vụ Disabled được giữ nguyên và báo cần quản trị viên xác minh.")
    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) { Repair-ServiceState -Policy $servicePolicy }

    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""

    $products = @(Get-WindowsLicenseProducts)
    if ($products.Count -gt 0) {
        Add-RepairCheck "Giấy phép Windows" "Đạt" "Đọc được $($products.Count) mục SoftwareLicensingProduct/slmgr."
    } elseif ($script:WindowsLicenseSourceNote) {
        Add-RepairCheck "Giấy phép Windows" "Đạt" $script:WindowsLicenseSourceNote
    } else {
        Add-RepairCheck "Giấy phép Windows" "Còn lỗi" "Chưa đọc được giấy phép Windows bằng WMI/CIM hoặc slmgr."
    }

    $tasks = @(Get-CompatibleScheduledTaskRecords -NoCache)
    if ($tasks.Count -gt 0) {
        Add-RepairCheck "Scheduled Tasks" "Đạt" "Đọc được $($tasks.Count) task bằng cmdlet hoặc schtasks.exe."
    } else {
        Add-RepairCheck "Scheduled Tasks" "Còn lỗi" "Task Scheduler/schtasks.exe chưa trả danh sách task hợp lệ."
    }

    $services = @(Safe-Cim -ClassName Win32_Service -CriticalLabel "Không thể quét dịch vụ Windows" -NoCache)
    if ($services.Count -gt 0) {
        Add-RepairCheck "Dịch vụ Windows" "Đạt" "Đọc được $($services.Count) dịch vụ qua WMI/CIM."
    } else {
        Add-RepairCheck "Dịch vụ Windows" "Còn lỗi" "Chưa đọc được danh sách dịch vụ qua WMI/CIM."
    }

    foreach ($toolName in @("cscript.exe", "schtasks.exe")) {
        try {
            $toolPath = Get-ToolNativeSystemPath $toolName
            if (Test-Path -LiteralPath $toolPath -PathType Leaf) {
                Add-RepairCheck $toolName "Đạt" $toolPath
            } else {
                Add-RepairCheck $toolName "Còn lỗi" "Không tìm thấy trong System32/Sysnative."
            }
        } catch {
            Add-RepairCheck $toolName "Còn lỗi" $_.Exception.Message
        }
    }

    $warnings = @($script:ScanWarnings | Select-Object -Unique)
    foreach ($warning in $warnings) { $actions.Add("CẢNH BÁO SAU REPAIR: $warning") }
    $recheckPassed = [bool]($warnings.Count -eq 0 -and @($checks | Where-Object { $_.Status -eq "Còn lỗi" }).Count -eq 0)
    $rollbackApplied = $false
    if ($recheckPassed) {
        $guidance.Add("Nguồn quét đã đạt. Bước tiếp theo: chạy lại mục 6 để quét và mở danh sách xử lý nếu còn KMS/crack.")
    } else {
        foreach ($serviceName in @($startedServices)) {
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $actions.Add("Đã hoàn tác trạng thái chạy của dịch vụ $serviceName vì recheck không đạt; StartupType chưa từng bị thay đổi.")
                $rollbackApplied = $true
            } catch {
                $actions.Add("CẢNH BÁO: không thể hoàn tác trạng thái chạy của dịch vụ ${serviceName}: $($_.Exception.Message)")
            }
        }
        $guidance.Add("Vẫn còn nguồn quét lỗi. Bước tiếp theo: khởi động lại máy rồi quét lại. Nếu còn lỗi, mở PowerShell bằng Administrator chạy: DISM /Online /Cleanup-Image /RestoreHealth; sau đó chạy: sfc /scannow; khởi động lại và quét lại.")
        $guidance.Add("Nếu chỉ thiếu PartialProductKey nhưng WMI/CIM, Scheduled Tasks và dịch vụ đều đọc được, không cần gỡ thủ công theo cảnh báo này; hãy xử lý các mục KMS/activator/tồn dư cụ thể mà báo cáo liệt kê.")
    }

    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) {
        try { $serviceStateAfter.Add((Get-ServiceStateSnapshot -Name ([string]$servicePolicy.Name) -DisplayName ([string]$servicePolicy.DisplayName))) }
        catch { $serviceStateAfter.Add([pscustomobject]@{ Name=[string]$servicePolicy.Name; DisplayName=[string]$servicePolicy.DisplayName; Status="Unknown"; StartMode="Unknown"; Error=$_.Exception.Message }) }
    }

    return (New-ToolReportEnvelope -ReportKind "ScanSourceRepair" -ToolVersion "4.4" -Data ([ordered]@{
        RepairAttempted = $true
        RecheckPassed = $recheckPassed
        StartupTypeChanged = $false
        RollbackApplied = $rollbackApplied
        ScanWarningCount = [int]$warnings.Count
        ScanWarnings = $warnings
        Checks = @($checks)
        Actions = @($actions)
        HandlingGuidance = @($guidance)
        ServiceStateBefore = $serviceStateBefore.ToArray()
        ServiceStateAfter = $serviceStateAfter.ToArray()
        ReportPath = ""
    }))
}

function Write-Report {
    param($Path, $Products, $Findings, $Decision, $Actions, $History = @(), $Verification = $null)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("BÁO CÁO KIỂM TRA VÀ LÀM SẠCH CẤU HÌNH KÍCH HOẠT")
    $lines.Add("Máy tính: $env:COMPUTERNAME")
    $lines.Add("Người dùng: $env:USERNAME")
    $lines.Add("Thời gian: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("")
    $lines.Add("Đánh giá ban đầu: $($Decision.Decision)")
    $lines.Add("Lý do ban đầu: $($Decision.Reason)")
    if ($script:WindowsLicenseSourceNote) { $lines.Add("Ghi chú nguồn giấy phép Windows: $script:WindowsLicenseSourceNote") }
    $lines.Add("Yêu cầu xử lý: $Remediate")
    $lines.Add("Gỡ sạch nâng cao: $DeepClean")
    $lines.Add("Coi KMS chưa phê duyệt là không hợp lệ: $TreatUnapprovedKmsAsNonCompliant")
    if ($ApprovedKmsServers.Count -gt 0) {
        $lines.Add("Máy chủ KMS được phê duyệt: $($ApprovedKmsServers -join ', ')")
    } else {
        $lines.Add("Máy chủ KMS được phê duyệt: Chưa cấu hình")
    }
    $lines.Add("Tệp cấu hình KMS: $($approvedKmsConfig.Path)")
    $lines.Add("Dòng KMS hợp lệ: $($approvedKmsConfig.Valid.Count); dòng không hợp lệ: $($approvedKmsConfig.Invalid.Count)")
    if ($approvedKmsConfig.Warning) { $lines.Add("CẢNH BÁO CẤU HÌNH KMS: $($approvedKmsConfig.Warning)") }
    $lines.Add("")
    if ($Verification) {
        $lines.Add("KẾT LUẬN TRƯỚC KHI KÍCH HOẠT BẢN QUYỀN CHÍNH THỨC")
        $lines.Add("Sẵn sàng kích hoạt chính thức: $($Verification.ReadyForOfficialActivation)")
        $lines.Add("Kết luận: $($Verification.Conclusion)")
        $lines.Add("Dấu hiệu activator còn hoạt động: $($Verification.ActiveActivatorFindingCount)")
        $lines.Add("KMS Windows chưa phê duyệt: $($Verification.UnapprovedWindowsKmsCount)")
        $lines.Add("KMS Office chưa phê duyệt: $($Verification.UnapprovedOfficeKmsCount)")
        $lines.Add("Cấu hình/tồn dư cần xử lý: $($Verification.ConfigurationResidueCount)")
        $lines.Add("Dấu vết lịch sử (không phải lỗi đang hoạt động): $($Verification.HistoryFindingCount)")
        $lines.Add("Cảnh báo nguồn quét quan trọng: $($Verification.ScanWarningCount)")
        foreach ($scanWarning in @($Verification.ScanWarnings)) {
            $lines.Add("- CẢNH BÁO QUÉT: $scanWarning")
        }
        $lines.Add("Phạm vi kết luận: $($Verification.ScopeNote)")
        $lines.Add("")
        $lines.Add("HƯỚNG XỬ LÝ ĐỀ XUẤT")
        foreach ($step in @($Verification.HandlingGuidance)) {
            $lines.Add("- $step")
        }
        if (@($Verification.HandlingGuidance).Count -eq 0) {
            $lines.Add("- Không có thao tác bổ sung trong phạm vi kiểm tra hiện tại.")
        }
        $lines.Add("")
        $lines.Add("Chẩn đoán sẵn sàng bổ sung (không thay đổi kết luận v3.0): $($Verification.ReadinessReviewCount) mục cần xem xét")
        foreach ($c in @($Verification.ReadinessChecks)) {
            $lines.Add("- [$($c.Status)] $($c.Name): $($c.Detail)")
        }
        foreach ($r in @($Verification.Residues)) {
            $lines.Add("- Tồn dư [$($r.Type)] $($r.Name): $($r.Location) | $($r.Value)")
        }
        $lines.Add("")
    }
    $lines.Add("Các giấy phép Windows:")
    foreach ($p in $Products) {
        $lines.Add("- Tên: $($p.Name)")
        $lines.Add("  Mô tả: $($p.Description)")
        $lines.Add("  Trạng thái: $(Status-Text $p.LicenseStatus)")
        $lines.Add("  Kênh: $(Get-LicenseChannel $p)")
        $lines.Add("  5 ký tự cuối: $($p.PartialProductKey)")
        $lines.Add("  Máy chủ KMS: $($p.KeyManagementServiceMachine)")
    }
    if ($Products.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")
    $lines.Add("Dấu hiệu activator/KMS/crack:")
    foreach ($f in $Findings) {
        $lines.Add("- [$($f.Type)] $($f.Name)")
        $lines.Add("  Vị trí: $($f.Location)")
        $lines.Add("  Hành động dự kiến: $($f.Action)")
    }
    if ($Findings.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")
    $lines.Add("LỊCH SỬ DẤU HIỆU KÍCH HOẠT KHÔNG HỢP LỆ (TỐI ĐA 180 NGÀY)")
    $lines.Add("Lưu ý: lịch sử cũ không chứng minh crack vẫn đang hoạt động và không tự làm tool gỡ key.")
    foreach ($h in @($History)) {
        $lines.Add("- [$($h.Time)] [$($h.Source)] Event $($h.EventId)")
        $lines.Add("  Bằng chứng đã che dữ liệu: $($h.Evidence)")
    }
    if (@($History).Count -eq 0) {
        $lines.Add("- Không tìm thấy dấu vết lịch sử theo các nguồn có thể truy cập.")
    }
    $lines.Add("")
    $lines.Add("Hành động đã thực hiện:")
    foreach ($a in $Actions) {
        $lines.Add("- $a")
    }
    if ($Actions.Count -eq 0) {
        $lines.Add("- None")
    }
    @($lines | ForEach-Object { Protect-CleanupReportText $_ }) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-OfficeOsppCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$SuccessPattern = ""
    )

    try {
        $output = (& $nativeCscriptPath //nologo $Path @Arguments 2>&1) -join "`n"
        $exitCode = [int]$LASTEXITCODE
        $output = ([string]$output) -replace "`0", ""
        $failurePattern = '(?im)^\s*(?:ERROR CODE|ERROR DESCRIPTION)\s*:|\b(?:failed|failure|cannot|could not)\b'
        $success = [bool]($exitCode -eq 0 -and $output -notmatch $failurePattern -and (
            [string]::IsNullOrWhiteSpace($SuccessPattern) -or $output -match $SuccessPattern
        ))
        $meaningful = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -and $_ -notmatch '^-{5,}$|^---Processing|^---Exiting'
        })
        $summary = ($meaningful | Select-Object -First 4) -join ' | '
        if ([string]::IsNullOrWhiteSpace($summary)) { $summary = "Không có nội dung; mã thoát $exitCode." }
        if ($summary.Length -gt 420) { $summary = $summary.Substring(0, 417) + '...' }
        return [pscustomobject]@{ Success=$success; ExitCode=$exitCode; Summary=$summary; Output=$output }
    } catch {
        return [pscustomobject]@{ Success=$false; ExitCode=-1; Summary=$_.Exception.Message; Output="ERROR: $($_.Exception.Message)" }
    }
}

function Invoke-Remediation {
    param(
        $Products,
        $Findings,
        [switch]$CleanupActivator,
        [switch]$CleanupKmsConfiguration,
        $WindowsProductsToRemove = @(),
        [switch]$SkipRestorePoint,
        $OfficeEntries = @()
    )
    $actions = New-Object System.Collections.Generic.List[string]
    if (-not (Is-Admin)) {
        $actions.Add("SKIPPED: Remediation requires Run as Administrator.")
        return $actions
    }

    if (-not $NoRestorePoint -and -not $SkipRestorePoint) {
        try {
            Checkpoint-Computer -Description "Before Windows license cleanup" -RestorePointType "MODIFY_SETTINGS" | Out-Null
            $actions.Add("Created restore point.")
        } catch {
            $actions.Add("WARNING: Could not create restore point: $($_.Exception.Message)")
        }
    }

    if ($CleanupActivator) {
    foreach ($f in $Findings) {
        if ($f.Type -eq "Process") {
            try {
                Stop-Process -Name $f.Name -Force -ErrorAction Stop
                $actions.Add("Stopped process: $($f.Name)")
            } catch {
                $actions.Add("WARNING: Could not stop process $($f.Name): $($_.Exception.Message)")
            }
        }
        if ($f.Type -eq "Service") {
            try {
                Stop-Service -Name $f.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $f.Name -StartupType Disabled -ErrorAction Stop
                $actions.Add("Stopped/disabled service: $($f.Name)")
            } catch {
                $actions.Add("WARNING: Could not disable service $($f.Name): $($_.Exception.Message)")
            }
        }
        if ($f.Type -eq "ScheduledTask") {
            try {
                $taskPath = "\"
                $taskName = $f.Name
                if ($f.Name -match "^(.*\\)([^\\]+)$") {
                    $taskPath = $matches[1]
                    $taskName = $matches[2]
                }
                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
                $actions.Add("Disabled scheduled task: $($f.Name)")
            } catch {
                $actions.Add("WARNING: Could not disable scheduled task $($f.Name): $($_.Exception.Message)")
            }
        }
    }
    } else {
        $actions.Add("Dấu vết activator: Không có mục cần xử lý.")
    }

    if ($CleanupKmsConfiguration) {
        $actions.Add("slmgr /ckms: $(Run-SlmgrActionText -SlmgrArguments @('/ckms'))")
    }

    $windowsTargets = @($WindowsProductsToRemove)
    if ($windowsTargets.Count -gt 0) {
        $removedWindowsKeyCount = 0
        foreach ($targetProduct in $windowsTargets) {
            $activationId = [string]$targetProduct.ID
            if ([string]::IsNullOrWhiteSpace($activationId)) {
                $actions.Add("Windows /upk: ĐÃ KHÓA AN TOÀN vì không đọc được Activation ID; không chạy lệnh gỡ khóa diện rộng.")
                continue
            }
            $upkResult = Invoke-SlmgrCommand -SlmgrArguments @('/upk', $activationId)
            $actions.Add("Windows /upk (đúng mục KMS đã chọn): $($upkResult.Summary)")
            if ([bool]$upkResult.Success) { $removedWindowsKeyCount++ }
        }
        if ($removedWindowsKeyCount -gt 0) {
            $actions.Add("slmgr /cpky: $(Run-SlmgrActionText -SlmgrArguments @('/cpky'))")
            $actions.Add("slmgr /rilc: $(Run-SlmgrActionText -SlmgrArguments @('/rilc'))")
        } else {
            $actions.Add("Windows: Bỏ qua /cpky và /rilc vì chưa gỡ được mục KMS đã chọn.")
        }
    } else {
        $actions.Add("Windows: Giữ nguyên khóa bản quyền; không phát hiện KMS/crack cần gỡ khóa hoặc khóa đang thuộc nhóm được bảo vệ.")
    }

    # Đưa Office KMS về trạng thái chưa kích hoạt: xóa KMS override một lần
    # cho mỗi OSPP.VBS, sau đó gỡ riêng từng Last5/SKU mà người dùng đã chọn.
    # /dstatusall ở bước quét bảo đảm nhiều SKU trên cùng đường dẫn không bị
    # che khuất lẫn nhau.
    $officeEntries = @($OfficeEntries)
    foreach ($path in @($officeEntries | ForEach-Object { [string]$_.Path } | Where-Object { $_ } | Select-Object -Unique)) {
        $remhst = Invoke-OfficeOsppCommand -Path $path -Arguments @('/remhst') -SuccessPattern '(?i)Successfully applied setting|thành công'
        if ([bool]$remhst.Success) {
            $actions.Add("Office /remhst ĐẠT ($path): $($remhst.Summary)")
        } else {
            $actions.Add("CẢNH BÁO: Office /remhst THẤT BẠI ($path, mã $($remhst.ExitCode)): $($remhst.Summary)")
        }
    }
    $officeRemoved = 0
    foreach ($entry in @($officeEntries | Group-Object { "$($_.Path)|$($_.SkuId)|$($_.Last5)" } | ForEach-Object { $_.Group[0] })) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Last5)) {
            $unpkey = Invoke-OfficeOsppCommand -Path ([string]$entry.Path) -Arguments @("/unpkey:$($entry.Last5)") -SuccessPattern '(?i)product key uninstall successful|gỡ.+khóa.+thành công'
            if ([bool]$unpkey.Success) {
                $officeRemoved++
                $actions.Add("Office /unpkey:$($entry.Last5) ĐẠT [$($entry.SkuId)] $($entry.LicenseName): $($unpkey.Summary)")
            } else {
                $actions.Add("CẢNH BÁO: Office /unpkey:$($entry.Last5) THẤT BẠI [$($entry.SkuId)] $($entry.LicenseName), mã $($unpkey.ExitCode): $($unpkey.Summary)")
            }
        } else {
            $actions.Add("Office: SKU $($entry.SkuId) không có Last5; chỉ xóa KMS override, không chạy lệnh gỡ key diện rộng.")
        }
    }
    if ($officeEntries.Count -eq 0) {
        $actions.Add("Office: Không phát hiện bản KMS client cần xử lý.")
    } else {
        $actions.Add("Office: đã gỡ thành công $officeRemoved/$(@($officeEntries | Where-Object { $_.Last5 }).Count) key KMS được chọn; hậu kiểm bằng /dstatusall sẽ quyết định bước tiếp theo.")
    }
    return $actions
}

function Invoke-DeepCleanupLegacyV33 {
    param($Findings)
    $actions = New-Object System.Collections.Generic.List[string]
    if (-not (Is-Admin)) {
        $actions.Add("BỎ QUA GỠ SẠCH: cần chạy bằng quyền Administrator.")
        return $actions
    }

    $deepStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $quarantine = Join-Path $OutputDir "quarantine_$($env:COMPUTERNAME)_$deepStamp"
    Ensure-Dir $quarantine
    $actions.Add("Gỡ sạch nâng cao đã được người dùng xác nhận.")
    $actions.Add("Thư mục sao lưu/cách ly: $quarantine")

    function Backup-RegKey {
        param([string]$PsPath, [string]$Label)
        try {
            if (-not (Test-Path -LiteralPath $PsPath)) { return }
            $nativePath = $PsPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
            $safeName = ($Label -replace '[\\/:*?"<>| ]', '_') + ".reg"
            $backupPath = Join-Path $quarantine $safeName
            $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
            $actions.Add("Sao lưu Registry [$Label]: $output")
        } catch {
            $actions.Add("CẢNH BÁO: không thể sao lưu Registry [$Label]: $($_.Exception.Message)")
        }
    }

    # Dừng tạm dịch vụ cấp phép để tệp hook không còn bị khóa. Trạng thái khởi
    # động chỉ được phục hồi nếu activator đã đặt dịch vụ thành Disabled.
    $serviceState = @{}
    foreach ($serviceName in @("sppsvc", "osppsvc")) {
        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            $serviceState[$serviceName] = [pscustomobject]@{ WasRunning=($svc.Status -eq "Running") }
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            $actions.Add("Tạm dừng dịch vụ cấp phép: $serviceName")
        } catch {}
    }

    # Xóa cấu hình KMS chưa phê duyệt, nhưng giữ nguyên máy chủ nằm trong danh
    # sách approved-kms-servers.txt.
    $clearWindowsKmsOverride = $false
    foreach ($path in @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform",
        "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $server = [string]$item.KeyManagementServiceName
            if ($server -and -not (Test-ApprovedKms $server)) {
                Backup-RegKey -PsPath $path -Label (Split-Path $path -Leaf)
                foreach ($name in @(
                    "KeyManagementServiceName", "KeyManagementServicePort",
                    "KeyManagementServiceLookupDomain", "DiscoveredKeyManagementServiceName",
                    "DiscoveredKeyManagementServicePort"
                )) {
                    Remove-ItemProperty -LiteralPath $path -Name $name -Force -ErrorAction SilentlyContinue
                }
                if ($path -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform") {
                    $clearWindowsKmsOverride = $true
                }
                $actions.Add("Đã xóa cấu hình KMS chưa phê duyệt tại: $path")
            }
        } catch {
            $actions.Add("CẢNH BÁO: không thể làm sạch KMS tại ${path}: $($_.Exception.Message)")
        }
    }
    if ($clearWindowsKmsOverride) {
        $actions.Add("Windows /ckms: $(Run-SlmgrActionText -SlmgrArguments @('/ckms'))")
    } else {
        $actions.Add("Windows /ckms: bỏ qua vì không có cấu hình KMS Windows chưa phê duyệt.")
    }

    # Xóa IFEO hook chỉ trên ba tiến trình cấp phép và chỉ khi giá trị có mẫu
    # đặc hiệu. Mỗi khóa được export trước để có thể phục hồi thủ công.
    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $valueText = (Get-ItemProperty -LiteralPath $path -ErrorAction Stop | Out-String)
            if ($valueText -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") {
                Backup-RegKey -PsPath $path -Label ("IFEO_" + $imageName)
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                $actions.Add("Đã gỡ IFEO hook: $imageName")
            }
        } catch {
            if (Test-Path -LiteralPath $path) {
                $actions.Add("CẢNH BÁO: không thể gỡ IFEO ${imageName}: $($_.Exception.Message)")
            }
        }
    }

    # Gỡ ngoại lệ Defender chỉ khi chính đường dẫn có tên activator/hook đặc
    # hiệu; không xóa ngoại lệ rộng hoặc cài đặt Defender không liên quan.
    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if ([string]$excludedPath -match $script:StrictActivatorPattern) {
                Remove-MpPreference -ExclusionPath ([string]$excludedPath) -ErrorAction Stop
                $actions.Add("Đã gỡ ngoại lệ Defender đáng ngờ: $excludedPath")
            }
        }
    } catch {
        $actions.Add("CẢNH BÁO: không thể kiểm tra/gỡ ngoại lệ Defender: $($_.Exception.Message)")
    }

    # Tệp hook được chuyển vào khu cách ly thay vì xóa vĩnh viễn.
    foreach ($hookPath in @(
        (Get-ToolNativeSystemPath "SppExtComObjHook.dll"),
        (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll")
    )) {
        if (Test-Path -LiteralPath $hookPath) {
            try {
                $hash = "Không tính được"
                if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
                    $hash = (Get-FileHash -LiteralPath $hookPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                } else {
                    $certutilOutput = (& $nativeCertutilPath -hashfile $hookPath SHA256 2>$null) -join "`n"
                    if ($certutilOutput -match "(?im)^\s*([0-9a-f]{64})\s*$") { $hash = $matches[1].ToUpperInvariant() }
                }
                $destination = Join-Path $quarantine ((Split-Path $hookPath -Leaf) + "_" + [guid]::NewGuid().ToString("N") + ".quarantine")
                Move-Item -LiteralPath $hookPath -Destination $destination -Force -ErrorAction Stop
                $actions.Add("Đã cách ly tệp hook: $hookPath | SHA256=$hash")
            } catch {
                $actions.Add("CẢNH BÁO: không thể cách ly tệp hook ${hookPath}: $($_.Exception.Message)")
            }
        }
    }

    foreach ($finding in @($Findings)) {
        if ($finding.Type -eq "Process") {
            try {
                Stop-Process -Name $finding.Name -Force -ErrorAction Stop
                $actions.Add("Đã dừng tiến trình activator: $($finding.Name)")
            } catch {}
        }
        if ($finding.Type -eq "ScheduledTask") {
            try {
                $taskPath = "\"
                $taskName = $finding.Name
                if ($finding.Name -match "^(.*\\)([^\\]+)$") { $taskPath=$matches[1]; $taskName=$matches[2] }
                try {
                    $xml = Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
                    $xml | Set-Content -LiteralPath (Join-Path $quarantine ("Task_" + ($taskName -replace '[\\/:*?"<>| ]','_') + ".xml")) -Encoding UTF8
                } catch {}
                if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
                    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
                } else {
                    & (Get-ToolNativeSystemPath "schtasks.exe") /Delete /TN $finding.Name /F | Out-Null
                }
                $actions.Add("Đã gỡ scheduled task activator: $($finding.Name)")
            } catch {
                $actions.Add("CẢNH BÁO: không thể gỡ task $($finding.Name): $($_.Exception.Message)")
            }
        }
        if ($finding.Type -eq "Service") {
            try {
                (& $nativeScPath qc $finding.Name 2>&1) | Set-Content -LiteralPath (Join-Path $quarantine ("Service_" + ($finding.Name -replace '[\\/:*?"<>| ]','_') + ".txt")) -Encoding UTF8
                Stop-Service -Name $finding.Name -Force -ErrorAction SilentlyContinue
                & $nativeScPath delete $finding.Name | Out-Null
                $actions.Add("Đã gỡ đăng ký dịch vụ activator: $($finding.Name)")
            } catch {
                $actions.Add("CẢNH BÁO: không thể gỡ dịch vụ $($finding.Name): $($_.Exception.Message)")
            }
        }
        if ($finding.Type -eq "Folder" -and [string]$finding.Name -match $script:StrictActivatorPattern) {
            try {
                $destination = Join-Path $quarantine (($finding.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N"))
                Move-Item -LiteralPath $finding.Location -Destination $destination -Force -ErrorAction Stop
                $actions.Add("Đã chuyển thư mục activator vào khu cách ly: $($finding.Location)")
            } catch {
                $actions.Add("CẢNH BÁO: không thể cách ly thư mục $($finding.Location): $($_.Exception.Message)")
            }
        }
    }

    # Phục hồi tệp hệ thống cấp phép bằng Component Store của chính Windows.
    foreach ($systemFile in @(
        (Get-ToolNativeSystemPath "sppsvc.exe"),
        (Get-ToolNativeSystemPath "SppExtComObj.exe")
    )) {
        if (Test-Path -LiteralPath $systemFile) {
            try {
                $sfcResult = ((& $nativeSfcPath "/scanfile=$systemFile" 2>&1) -join " | ") -replace "`0", ""
                $actions.Add("SFC ${systemFile}: $sfcResult")
            } catch {
                $actions.Add("CẢNH BÁO: SFC không kiểm tra được ${systemFile}: $($_.Exception.Message)")
            }
        }
    }
    $actions.Add("Windows /rilc: $(Run-SlmgrActionText -SlmgrArguments @('/rilc'))")

    foreach ($serviceName in @("sppsvc", "osppsvc")) {
        try {
            $svcInfo = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
            if ($svcInfo -and [string]$svcInfo.StartMode -eq "Disabled") {
                if ($serviceName -eq "sppsvc") { & $nativeScPath config $serviceName start= delayed-auto | Out-Null }
                else { & $nativeScPath config $serviceName start= auto | Out-Null }
                $actions.Add("Đã phục hồi chế độ khởi động dịch vụ: $serviceName")
            }
            if ($serviceState.ContainsKey($serviceName) -and $serviceState[$serviceName].WasRunning) {
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    try {
        $actions | Set-Content -LiteralPath (Join-Path $quarantine "QUARANTINE-MANIFEST.txt") -Encoding UTF8
        @(
            "HƯỚNG DẪN PHỤC HỒI THỦ CÔNG",
            "1. Chỉ phục hồi khi đã xác minh mục bị cách ly là hợp lệ.",
            "2. File .reg là bản sao Registry trước khi gỡ; nhấp đúp chỉ khi hiểu rõ nội dung.",
            "3. File Task_*.xml dùng để tham khảo/tạo lại scheduled task bằng Task Scheduler.",
            "4. File Service_*.txt ghi cấu hình dịch vụ cũ; không tự chạy file này.",
            "5. Tệp/thư mục .quarantine không được thực thi trực tiếp.",
            "6. Báo cáo license_cleanup đi kèm ghi toàn bộ hành động và kết quả hậu kiểm."
        ) | Set-Content -LiteralPath (Join-Path $quarantine "PHUC-HOI.txt") -Encoding UTF8
        $actions.Add("Đã tạo manifest và hướng dẫn phục hồi trong thư mục cách ly.")
    } catch {
        $actions.Add("CẢNH BÁO: không thể tạo manifest khu cách ly: $($_.Exception.Message)")
    }

    return $actions
}

function Invoke-DeepCleanupV35 {
    param($Candidates, [string[]]$SelectedIds)
    $actions = New-Object System.Collections.Generic.List[string]
    $restoreItems = New-Object System.Collections.Generic.List[object]
    if (-not (Is-Admin)) {
        $actions.Add("BỎ QUA GỠ SẠCH: cần chạy bằng quyền Administrator.")
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0 }
    }

    $selectedLookup = @{}
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
            $selectedLookup[([string]$selectedId).ToLowerInvariant()] = $true
        }
    }
    $selected = @($Candidates | Where-Object { $selectedLookup.ContainsKey(([string]$_.Id).ToLowerInvariant()) })
    if ($selected.Count -eq 0) {
        $actions.Add("BỎ QUA GỠ SẠCH: người dùng chưa chọn service, task, thư mục, tệp hoặc Registry nào.")
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0 }
    }

    $deepStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $quarantine = ""
    try {
        $secureBackupRoot = Get-SecureBackupRoot
        $quarantine = Join-Path $secureBackupRoot ("quarantine_$($env:COMPUTERNAME)_${deepStamp}_" + [guid]::NewGuid().ToString("N"))
        Ensure-Dir $quarantine
        Set-ProtectedBackupAcl $quarantine
        if (-not (Test-ProtectedDirectoryAcl $quarantine)) { throw "ACL thư mục cách ly mới không đạt yêu cầu." }
    } catch {
        $actions.Add("ĐÃ KHÓA GỠ SÂU: không thể tạo vùng backup/cách ly bảo vệ trong ProgramData: $($_.Exception.Message)")
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0 }
    }
    $manifestPath = Join-Path $quarantine "RESTORE-MANIFEST.json"
    $hmacPath = Join-Path $quarantine "RESTORE-MANIFEST.hmac"
    $authPath = Join-Path $quarantine "RESTORE-AUTH.bin"
    $restoreScriptSha256 = ""
    $runtimeHelperSha256 = ""
    $safetyPolicySha256 = ""
    $hmacKey = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($hmacKey) } finally { $rng.Dispose() }
    $protectedKey = [Security.Cryptography.ProtectedData]::Protect($hmacKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [IO.File]::WriteAllBytes($authPath, $protectedKey)
    $actions.Add("Gỡ sạch nâng cao v4.4 đã được người dùng xác nhận theo từng mục.")
    $actions.Add("Số mục được đánh dấu: $($selected.Count)/$(@($Candidates).Count)")
    $actions.Add("Thư mục sao lưu/cách ly: $quarantine")

    function Save-RestoreManifest {
        $manifest = [ordered]@{
            SchemaVersion = "2.0"
            ToolVersion = "4.4"
            BackupMode = "DeepCleanup"
            ComputerName = $env:COMPUTERNAME
            MachineBinding = Get-MachineBinding
            CreatedAt = (Get-Date).ToString("o")
            RestoreScriptSha256 = $restoreScriptSha256
            RuntimeHelperSha256 = $runtimeHelperSha256
            SafetyPolicySha256 = $safetyPolicySha256
            # Tránh lỗi Windows PowerShell 5.1 "Argument types do not match"
            # khi bọc trực tiếp List[object] bằng @().
            Items = $restoreItems.ToArray()
        }
        $tempManifest = Join-Path $quarantine (".manifest-" + [guid]::NewGuid().ToString("N") + ".tmp")
        $tempHmac = $tempManifest + ".hmac"
        [IO.File]::WriteAllText($tempManifest, ($manifest | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
        try { $signature = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($tempManifest))) -replace '-', '').ToUpperInvariant() }
        finally { $hmac.Dispose() }
        [IO.File]::WriteAllText($tempHmac, $signature, [Text.Encoding]::ASCII)
        Move-Item -LiteralPath $tempManifest -Destination $manifestPath -Force
        Move-Item -LiteralPath $tempHmac -Destination $hmacPath -Force
    }

    function Add-RestoreItem {
        param($Item)
        if (-not [string]::IsNullOrWhiteSpace([string]$Item.BackupPath)) {
            $fullBackupPath = [string]$Item.BackupPath
            $Item.BackupPath = [IO.Path]::GetFileName($fullBackupPath)
            $Item | Add-Member -NotePropertyName BackupSha256 -NotePropertyValue (Get-PathHash $fullBackupPath) -Force
        } else {
            $Item | Add-Member -NotePropertyName BackupSha256 -NotePropertyValue "" -Force
        }
        $restoreItems.Add($Item)
        Save-RestoreManifest
    }

    function Backup-RegKeyV35 {
        param($Candidate)
        try {
            $psPath = [string]$Candidate.Location
            if (-not (Test-Path -LiteralPath $psPath)) { return $false }
            if ([string]$Candidate.Kind -in @("KmsOverride", "SppNoGenTicketPolicy")) {
                $key = Get-Item -LiteralPath $psPath -ErrorAction Stop
                $values = New-Object System.Collections.Generic.List[object]
                $valueNames = if ([string]$Candidate.Kind -eq "SppNoGenTicketPolicy") {
                    @("NoGenTicket")
                } else {
                    @(Get-ToolAllowedRegistryValueNames -Path $psPath)
                }
                foreach ($name in $valueNames) {
                    try {
                        $kind = [string]$key.GetValueKind($name)
                        $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        if ($kind -eq "Binary") { $value = [Convert]::ToBase64String([byte[]]$value) }
                        $values.Add([pscustomobject]@{ Name=$name; Kind=$kind; Value=$value })
                    } catch {}
                }
                if ($values.Count -eq 0) { return $false }
                $backupPath = Join-Path $quarantine (((( [string]$Candidate.Name) -replace '[\\/:*?"<>| ]', '_')) + "_" + [guid]::NewGuid().ToString("N") + ".json")
                [pscustomobject]@{ RegistryPath=$psPath; Values=$values.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath -Encoding UTF8
                Add-RestoreItem ([pscustomobject]@{ Type="RegistryValues"; Name=[string]$Candidate.Name; OriginalPath=$psPath; BackupPath=$backupPath; Kind=[string]$Candidate.Kind })
            } else {
                $nativePath = $psPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                $backupPath = Join-Path $quarantine (((( [string]$Candidate.Name) -replace '[\\/:*?"<>| ]', '_')) + "_" + [guid]::NewGuid().ToString("N") + ".reg")
                $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
                if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $output }
                Add-RestoreItem ([pscustomobject]@{ Type="Registry"; Name=[string]$Candidate.Name; OriginalPath=$psPath; BackupPath=$backupPath; Kind=[string]$Candidate.Kind })
            }
            $actions.Add("Đã sao lưu Registry [$($Candidate.Name)]: $backupPath")
            return $true
        } catch {
            $actions.Add("CẢNH BÁO: không thể sao lưu Registry [$($Candidate.Name)]: $($_.Exception.Message)")
            return $false
        }
    }

    Save-RestoreManifest
    try {
        $restoreSource = Join-Path $PSScriptRoot "windows-license-restore.ps1"
        if (Test-Path -LiteralPath $restoreSource -PathType Leaf) {
            $restoreDestination = Join-Path $quarantine "windows-license-restore.ps1"
            Copy-Item -LiteralPath $restoreSource -Destination $restoreDestination -Force
            $restoreScriptSha256 = Get-Sha256 $restoreDestination
            $runtimeSource = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
            if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1 để tạo bộ khôi phục." }
            $runtimeDestination = Join-Path $quarantine "Tool-Runtime.ps1"
            Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Force
            $runtimeHelperSha256 = Get-Sha256 $runtimeDestination
            $safetyPolicySource = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
            if (-not (Test-Path -LiteralPath $safetyPolicySource -PathType Leaf)) { throw "Thiếu Tool-SafetyPolicy.ps1 để tạo bộ khôi phục." }
            $safetyPolicyDestination = Join-Path $quarantine "Tool-SafetyPolicy.ps1"
            Copy-Item -LiteralPath $safetyPolicySource -Destination $safetyPolicyDestination -Force
            $safetyPolicySha256 = Get-Sha256 $safetyPolicyDestination
            @(
                '@echo off',
                'set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
                'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
                '"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-license-restore.ps1" -BackupDir "%~dp0"',
                'pause'
            ) | Set-Content -LiteralPath (Join-Path $quarantine "KHOI-PHUC-TU-DONG.cmd") -Encoding ASCII
            Save-RestoreManifest
        }
    } catch {
        $actions.Add("CẢNH BÁO: không thể tạo bộ khôi phục tự động: $($_.Exception.Message)")
    }

    # Thay đổi product key không thể tự rollback nếu không lưu key đầy đủ.
    # Manifest chỉ ghi thông tin đã che để người dùng biết rõ giới hạn này.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "License" })) {
        Add-RestoreItem ([pscustomobject]@{
            Type="LicenseNotice"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
            BackupPath=""; Kind=[string]$candidate.Kind; Restorable=$false
        })
        $actions.Add("CẢNH BÁO: mục bản quyền '$($candidate.Name)' không thể tự khôi phục vì tool không lưu product key đầy đủ.")
    }

    # Dừng các tiến trình được chọn trước để giải phóng tệp/dịch vụ liên quan.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Process" })) {
        try {
            Stop-Process -Name $candidate.Name -Force -ErrorAction Stop
            $actions.Add("Đã dừng tiến trình đã chọn: $($candidate.Name)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể dừng tiến trình $($candidate.Name): $($_.Exception.Message)")
        }
    }

    $licenseServiceState = @{}
    if (@($selected | Where-Object { $_.Type -eq "File" }).Count -gt 0) {
        foreach ($serviceName in @("sppsvc", "osppsvc")) {
            try {
                $svc = Get-Service -Name $serviceName -ErrorAction Stop
                $licenseServiceState[$serviceName] = ($svc.Status -eq "Running")
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Registry" })) {
        if (-not (Backup-RegKeyV35 $candidate)) { continue }
        try {
            if ($candidate.Kind -eq "KmsOverride") {
                foreach ($name in @(
                    "KeyManagementServiceName", "KeyManagementServicePort",
                    "KeyManagementServiceLookupDomain", "DiscoveredKeyManagementServiceName",
                    "DiscoveredKeyManagementServicePort"
                )) {
                    Remove-ItemProperty -LiteralPath $candidate.Location -Name $name -Force -ErrorAction SilentlyContinue
                }
                if ($candidate.Location -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform") {
                    $actions.Add("Windows /ckms: $(Run-SlmgrActionText -SlmgrArguments @('/ckms'))")
                }
                $actions.Add("Đã xóa cấu hình KMS đã chọn tại: $($candidate.Location)")
            } elseif ($candidate.Kind -eq "SppNoGenTicketPolicy") {
                Remove-ItemProperty -LiteralPath $candidate.Location -Name "NoGenTicket" -Force -ErrorAction Stop
                $actions.Add("Đã xóa policy SPP NoGenTicket=1 đã chọn tại: $($candidate.Location)")
            } elseif ($candidate.Kind -eq "IfeoHook") {
                Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
                $actions.Add("Đã gỡ IFEO hook đã chọn: $($candidate.Name)")
            }
        } catch {
            $actions.Add("CẢNH BÁO: không thể xử lý Registry $($candidate.Location): $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Defender" })) {
        try {
            Add-RestoreItem ([pscustomobject]@{
                Type="Defender"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=""; Kind=[string]$candidate.Kind
            })
            Remove-MpPreference -ExclusionPath ([string]$candidate.Location) -ErrorAction Stop
            $actions.Add("Đã gỡ ngoại lệ Defender đã chọn: $($candidate.Location)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể gỡ ngoại lệ Defender $($candidate.Location): $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "File" })) {
        try {
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Leaf)) { continue }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Từ chối cách ly reparse point." }
            $destination = Join-Path $quarantine ((Split-Path $candidate.Location -Leaf) + "_" + [guid]::NewGuid().ToString("N") + ".quarantine")
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Force -ErrorAction Stop
            Add-RestoreItem ([pscustomobject]@{
                Type="File"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind
            })
            Remove-Item -LiteralPath $candidate.Location -Force -ErrorAction Stop
            $actions.Add("Đã cách ly tệp đã chọn: $($candidate.Location)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể cách ly tệp $($candidate.Location): $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "ScheduledTask" })) {
        try {
            $task = Get-CompatibleScheduledTaskRecords | Where-Object {
                [string]::Equals([string]$_.FullName, [string]$candidate.Name, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
            if (-not $task) { throw "Không còn tìm thấy scheduled task đã chọn." }
            $taskPath = [string]$task.TaskPath
            $taskName = [string]$task.TaskName
            $backupPath = Join-Path $quarantine ("Task_" + ($taskName -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".xml")
            Export-CompatibleScheduledTask -Record $task -Path $backupPath
            Add-RestoreItem ([pscustomobject]@{
                Type="ScheduledTask"; Name=$taskName; OriginalPath=$taskPath; BackupPath=$backupPath
                Kind=[string]$candidate.Kind; WasEnabled=[bool]$task.WasEnabled
            })
            Remove-CompatibleScheduledTask -Record $task
            $actions.Add("Đã gỡ scheduled task đã chọn: $($candidate.Name)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể gỡ task $($candidate.Name): $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Service" })) {
        try {
            $serviceInfo = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $candidate.Name } | Select-Object -First 1
            if (-not $serviceInfo) { continue }
            $nativeServicePath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($serviceInfo.Name)"
            $serviceBackupPath = Join-Path $quarantine ("Service_" + ($serviceInfo.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".reg")
            $serviceExport = (& $nativeRegPath export $nativeServicePath $serviceBackupPath /y 2>&1) -join " | "
            if (-not (Test-Path -LiteralPath $serviceBackupPath -PathType Leaf)) { throw $serviceExport }
            $dependencies = @()
            try { $dependencies = @(Get-Service -Name $serviceInfo.Name -ErrorAction Stop | Select-Object -ExpandProperty ServicesDependedOn | Select-Object -ExpandProperty Name) } catch {}
            $sddl = ""
            try { $sddl = ((& $nativeScPath sdshow $serviceInfo.Name 2>$null) | Where-Object { $_ -match '^D:' } | Select-Object -First 1) } catch {}
            Add-RestoreItem ([pscustomobject]@{
                Type="Service"; Name=[string]$serviceInfo.Name; OriginalPath=("HKLM:\SYSTEM\CurrentControlSet\Services\" + [string]$serviceInfo.Name); BackupPath=$serviceBackupPath
                Kind=[string]$candidate.Kind; DisplayName=[string]$serviceInfo.DisplayName
                PathName=[string]$serviceInfo.PathName; StartMode=[string]$serviceInfo.StartMode
                StartName=[string]$serviceInfo.StartName; Description=[string]$serviceInfo.Description
                WasRunning=[bool]($serviceInfo.State -eq "Running"); Dependencies=@($dependencies); SecurityDescriptor=[string]$sddl
            })
            Stop-Service -Name $serviceInfo.Name -Force -ErrorAction SilentlyContinue
            $deleteOutput = (& $nativeScPath delete $serviceInfo.Name 2>&1) -join " | "
            if ($LASTEXITCODE -ne 0) { throw $deleteOutput }
            $actions.Add("Đã gỡ dịch vụ đã chọn: $($serviceInfo.Name)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể gỡ dịch vụ $($candidate.Name): $($_.Exception.Message)")
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Folder" })) {
        try {
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Container)) { continue }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Từ chối cách ly reparse point." }
            $destination = Join-Path $quarantine (($candidate.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N"))
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Recurse -Force -ErrorAction Stop
            Add-RestoreItem ([pscustomobject]@{
                Type="Folder"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind
            })
            Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
            $actions.Add("Đã cách ly thư mục đã chọn: $($candidate.Location)")
        } catch {
            $actions.Add("CẢNH BÁO: không thể cách ly thư mục $($candidate.Location): $($_.Exception.Message)")
        }
    }

    if (@($selected | Where-Object { $_.Type -in @("File", "Registry") }).Count -gt 0) {
        foreach ($systemFile in @(
            (Get-ToolNativeSystemPath "sppsvc.exe"),
            (Get-ToolNativeSystemPath "SppExtComObj.exe")
        )) {
            if (Test-Path -LiteralPath $systemFile) {
                try {
                    $sfcResult = ((& $nativeSfcPath "/scanfile=$systemFile" 2>&1) -join " | ") -replace "`0", ""
                    $actions.Add("SFC ${systemFile}: $sfcResult")
                } catch {
                    $actions.Add("CẢNH BÁO: SFC không kiểm tra được ${systemFile}: $($_.Exception.Message)")
                }
            }
        }
        $actions.Add("Windows /rilc: $(Run-SlmgrActionText -SlmgrArguments @('/rilc'))")
    }

    foreach ($serviceName in $licenseServiceState.Keys) {
        if ([bool]$licenseServiceState[$serviceName]) {
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        }
    }

    try {
        Save-RestoreManifest
        $actions | Set-Content -LiteralPath (Join-Path $quarantine "QUARANTINE-MANIFEST.txt") -Encoding UTF8
        @(
            "KHÔI PHỤC TỰ ĐỘNG - TOOL KIỂM TRA v4.4",
            "1. Nhấn nút Khôi phục tự động trong mục 6, rồi chọn thư mục này.",
            "2. Hoặc chạy KHOI-PHUC-TU-DONG.cmd bằng quyền Administrator.",
            "3. Tool xác thực HMAC, đúng máy, ACL và SHA-256 từng file trước khi phục hồi.",
            "4. Không ghi đè tệp/thư mục đang tồn tại và không tự thêm lại ngoại lệ Defender.",
            "5. Kiểm tra báo cáo restore_*.txt sau khi hoàn tất."
        ) | Set-Content -LiteralPath (Join-Path $quarantine "PHUC-HOI.txt") -Encoding UTF8
        $actions.Add("Đã tạo manifest và script khôi phục tự động trong thư mục cách ly.")
    } catch {
        $actions.Add("CẢNH BÁO: không thể hoàn thiện bộ khôi phục tự động: $($_.Exception.Message)")
    }

    if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }

    return [pscustomobject]@{
        Actions=@($actions)
        BackupDirectory=$quarantine
        SelectedCount=[int]$selected.Count
    }
}

if ($RepairScanSources) {
    Ensure-Dir $OutputDir
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportComputer = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
    $repairReportPath = Join-Path $OutputDir "scan_source_repair_${reportComputer}_$stamp.txt"
    $repair = Invoke-ScanSourceRepair
    $repair.ReportPath = [string]$repairReportPath
    $repairLines = New-Object System.Collections.Generic.List[string]
    $repairLines.Add("KIỂM TRA/KHẮC PHỤC NGUỒN QUÉT - TOOL KIỂM TRA v4.4")
    $repairLines.Add("Thời gian: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $repairLines.Add("Kết quả quét lại đạt: $($repair.RecheckPassed)")
    $repairLines.Add("Đã thay đổi StartupType: $($repair.StartupTypeChanged)")
    $repairLines.Add("Đã hoàn tác sau lỗi: $($repair.RollbackApplied)")
    $repairLines.Add("")
    $repairLines.Add("KIỂM TRA")
    foreach ($check in @($repair.Checks)) { $repairLines.Add("- [$($check.Status)] $($check.Name): $($check.Detail)") }
    $repairLines.Add("")
    $repairLines.Add("HÀNH ĐỘNG")
    foreach ($action in @($repair.Actions)) { $repairLines.Add("- $action") }
    $repairLines.Add("")
    $repairLines.Add("TRẠNG THÁI DỊCH VỤ TRƯỚC / SAU")
    foreach ($before in @($repair.ServiceStateBefore)) {
        $after = @($repair.ServiceStateAfter | Where-Object { $_.Name -eq $before.Name } | Select-Object -First 1)
        $afterText = if ($after.Count -gt 0) { "$($after[0].Status), StartupType=$($after[0].StartMode)" } else { "không đọc được" }
        $repairLines.Add("- $($before.Name): trước=$($before.Status), StartupType=$($before.StartMode); sau=$afterText")
    }
    $repairLines.Add("")
    $repairLines.Add("HƯỚNG XỬ LÝ")
    foreach ($step in @($repair.HandlingGuidance)) { $repairLines.Add("- $step") }
    @($repairLines | ForEach-Object { Protect-CleanupReportText $_ }) | Set-Content -LiteralPath $repairReportPath -Encoding UTF8
    Write-DecisionData -Path $DecisionFile -Data $repair
    Write-Host "Báo cáo repair nguồn quét: $repairReportPath"
    if ($repair.RecheckPassed) { exit 0 }
    exit 3
}

Import-ApprovedKmsServers
$approvedKmsConfig = Get-ApprovedKmsConfiguration
Ensure-Dir $OutputDir
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportComputer = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
$reportPath = Join-Path $OutputDir "license_cleanup_${reportComputer}_$stamp.txt"

$script:WindowsLicenseSourceNote = ""
$products = @(Get-WindowsLicenseProducts)
$findings = @(Get-ActivatorFindings)
$officeKmsEntries = @(Get-OfficeKmsEntries)
$script:SensitiveKmsHosts = @(
    @($ApprovedKmsServers)
    @($approvedKmsConfig.Valid)
    @($products | ForEach-Object { [string]$_.KeyManagementServiceMachine })
    @($officeKmsEntries | ForEach-Object { [string]$_.Server })
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
$history = @(Get-InvalidActivationHistory)
$configurationResidues = @(Get-ActivationConfigurationResidues)
$unapprovedOfficeKmsEntries = @($officeKmsEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
$decision = Get-ComplianceDecision -Products $products -Findings $findings
$protectedLicense = Get-ProtectedLicenseInfo -Products $products
$activeLicensedProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$activeWindowsChannel = if ($activeLicensedProduct) { Get-LicenseChannel $activeLicensedProduct } else { "Chưa xác định" }
$activeApprovedKms = [bool]($activeWindowsChannel -eq "KMS" -and (Test-ApprovedKms ([string]$activeLicensedProduct.KeyManagementServiceMachine)))
$protectedActiveChannel = [bool]($activeWindowsChannel -in @("OEM", "Retail", "MAK") -or $activeApprovedKms)
$unapprovedWindowsKmsProducts = @($products | Where-Object {
    (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
})
$unapprovedWindowsKms = [bool]($unapprovedWindowsKmsProducts.Count -gt 0)
$cleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries)
$crackDetected = [bool]($unapprovedWindowsKms -or $findings.Count -gt 0 -or $unapprovedOfficeKmsEntries.Count -gt 0 -or $configurationResidues.Count -gt 0)
$removeWindowsLicense = [bool]($unapprovedWindowsKms -and -not $protectedActiveChannel)
$unapprovedWindowsConfigResidues = @($configurationResidues | Where-Object {
    $_.Type -eq "KMSConfig" -and $_.Location -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform"
})
$cleanupWindowsKmsConfiguration = [bool]($unapprovedWindowsKms -or $unapprovedWindowsConfigResidues.Count -gt 0)
$verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history
$decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.4" -Data ([ordered]@{
    CrackDetected = $crackDetected
    ProtectedLicense = [bool]$protectedLicense.Protected
    ProtectedChannel = [string]$protectedLicense.Channel
    ProtectedReason = [string]$protectedLicense.Reason
    ActiveWindowsChannel = [string]$activeWindowsChannel
    RemoveWindowsLicense = $removeWindowsLicense
    ActivatorFindingCount = [int]$findings.Count
    HistoryFindingCount = [int]$history.Count
    ConfigurationResidueCount = [int]$configurationResidues.Count
    WindowsKmsCount = [int]$unapprovedWindowsKmsProducts.Count
    OfficeKmsCount = [int]$unapprovedOfficeKmsEntries.Count
    ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $unapprovedOfficeKmsEntries.Count)
    ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
    ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
    InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
    ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
    Decision = [string]$decision.Decision
    Reason = [string]$decision.Reason
    ReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
    ReadinessReviewCount = [int]$verification.ReadinessReviewCount
    ScanWarningCount = [int]$verification.ScanWarningCount
    ScanWarnings = $verification.ScanWarnings
    ReadinessChecks = $verification.ReadinessChecks
    DeepCleanupApplied = $false
    CleanupItems = $cleanupItems
    SelectionRequired = [bool]($cleanupItems.Count -gt 0)
    SelectedCleanupItemCount = 0
    BackupDirectory = ""
    CleanupConclusion = [string]$verification.Conclusion
    HandlingGuidance = $verification.HandlingGuidance
    NextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $cleanupItems -ProtectedLicense ([bool]$protectedLicense.Protected))
    ScopeNote = [string]$verification.ScopeNote
    ReportPath = [string]$reportPath
})
Write-DecisionData -Path $DecisionFile -Data $decisionData
$actions = New-Object System.Collections.Generic.List[string]
$selectedCleanupIds = @(Get-SelectedCleanupIds)
$backupDirectory = ""

if ($Remediate) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedDirectoryAcl $PSScriptRoot)) {
        $actions.Add("ĐÃ KHÓA XỬ LÝ: chức năng thay đổi chỉ chạy từ bản EXE trong vùng bảo vệ.")
    } elseif ([int]$verification.ScanWarningCount -gt 0) {
        $actions.Add("ĐÃ KHÓA XỬ LÝ: nguồn quét quan trọng chưa đọc đầy đủ; sửa cảnh báo quét rồi chạy lại trước khi thay đổi hệ thống.")
    } elseif (-not $DeepClean) {
        $actions.Add("ĐÃ KHÓA XỬ LÝ: v4.4 bắt buộc dùng danh sách chọn từng mục; không còn chế độ gỡ tự động không chọn.")
    } elseif ($selectedCleanupIds.Count -eq 0) {
        $actions.Add("BỎ QUA GỠ SẠCH: chưa nhận được danh sách mục do người dùng đánh dấu; hệ thống không bị thay đổi.")
    } elseif ($crackDetected) {
        $selectedCandidates = @($cleanupItems | Where-Object { $selectedCleanupIds -contains ([string]$_.Id).ToLowerInvariant() })
        $selectedWindowsActivationIds = @($selectedCandidates | Where-Object {
            $_.Kind -eq "WindowsKmsLicense" -and -not [string]::IsNullOrWhiteSpace([string]$_.TargetId)
        } | ForEach-Object { [string]$_.TargetId })
        $windowsProductsToRemove = @($unapprovedWindowsKmsProducts | Where-Object {
            $selectedWindowsActivationIds -contains [string]$_.ID
        })
        $selectedOfficeTargetIds = @($selectedCandidates | Where-Object { $_.Kind -eq "OfficeKmsLicense" } | ForEach-Object { [string]$_.TargetId })
        $officeEntriesToClean = @($unapprovedOfficeKmsEntries | Where-Object {
            $entryTargetId = if (-not [string]::IsNullOrWhiteSpace([string]$_.SkuId)) { [string]$_.SkuId } else { "$($_.Path)|$($_.Last5)" }
            $selectedOfficeTargetIds -contains $entryTargetId
        })

        if (-not $NoRestorePoint) {
            try {
                Checkpoint-Computer -Description "Before Tool-Kiem-Tra v4.4 selected cleanup" -RestorePointType "MODIFY_SETTINGS" | Out-Null
                $actions.Add("Đã tạo System Restore Point trước mọi thay đổi đã chọn.")
            } catch {
                $actions.Add("CẢNH BÁO: không tạo được System Restore Point; tiếp tục dựa trên backup có HMAC: $($_.Exception.Message)")
            }
        }

        # Sao lưu/cách ly và ký manifest trước. Chỉ sau khi bước này thành công
        # mới cho phép thay đổi product key đã được người dùng chọn.
        $deepResult = Invoke-DeepCleanupV35 -Candidates $cleanupItems -SelectedIds $selectedCleanupIds
        $backupDirectory = [string]$deepResult.BackupDirectory
        foreach ($deepAction in @($deepResult.Actions)) { $actions.Add([string]$deepAction) }
        if ($backupDirectory) {
            $basicActions = @(Invoke-Remediation -Products $products -Findings $findings `
                -CleanupActivator:$false `
                -CleanupKmsConfiguration:$false `
                -WindowsProductsToRemove $(if ($removeWindowsLicense) { $windowsProductsToRemove } else { @() }) `
                -SkipRestorePoint `
                -OfficeEntries $officeEntriesToClean)
            foreach ($basicAction in $basicActions) { $actions.Add([string]$basicAction) }
        } else {
            $actions.Add("ĐÃ KHÓA THAY ĐỔI PRODUCT KEY: chưa tạo được vùng backup/cách ly an toàn.")
        }
    } else {
        $actions.Add("BỎ QUA: Không phát hiện KMS/crack cần xử lý; chương trình không thay đổi bản quyền.")
    }

    # Luôn quét lại sau xử lý. Chỉ kết luận sẵn sàng kích hoạt chính thức khi
    # không còn dấu hiệu đang hoạt động hoặc cấu hình KMS chưa phê duyệt.
    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""
    $products = @(Get-WindowsLicenseProducts)
    $findings = @(Get-ActivatorFindings)
    $officeKmsEntries = @(Get-OfficeKmsEntries)
    $cleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries)
    $history = @(Get-InvalidActivationHistory)
    $verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history
    $postProtectedLicense = Get-ProtectedLicenseInfo -Products $products
    $postActiveProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $postActiveChannel = if ($postActiveProduct) { Get-LicenseChannel $postActiveProduct } else { "Chưa xác định" }
    $actions.Add("KIỂM TRA SAU XỬ LÝ: $($verification.Conclusion)")
    $decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.4" -Data ([ordered]@{
        CrackDetected = [bool](-not $verification.ReadyForOfficialActivation)
        ProtectedLicense = [bool]$postProtectedLicense.Protected
        ProtectedChannel = [string]$postProtectedLicense.Channel
        ProtectedReason = [string]$postProtectedLicense.Reason
        ActiveWindowsChannel = [string]$postActiveChannel
        RemoveWindowsLicense = $removeWindowsLicense
        ActivatorFindingCount = [int]$verification.ActiveActivatorFindingCount
        HistoryFindingCount = [int]$verification.HistoryFindingCount
        ConfigurationResidueCount = [int]$verification.ConfigurationResidueCount
        WindowsKmsCount = [int]$verification.UnapprovedWindowsKmsCount
        OfficeKmsCount = [int]$verification.UnapprovedOfficeKmsCount
        ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $verification.UnapprovedOfficeKmsCount)
        ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
        ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
        InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
        ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
        Decision = if ($verification.ReadyForOfficialActivation) { "Đã kiểm tra sau xử lý" } else { "Còn tồn dư cần xử lý" }
        Reason = [string]$verification.Conclusion
        ReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
        ReadinessReviewCount = [int]$verification.ReadinessReviewCount
        ScanWarningCount = [int]$verification.ScanWarningCount
        ScanWarnings = $verification.ScanWarnings
        ReadinessChecks = $verification.ReadinessChecks
        DeepCleanupApplied = [bool](-not [string]::IsNullOrWhiteSpace($backupDirectory))
        CleanupItems = $cleanupItems
        SelectionRequired = [bool]($cleanupItems.Count -gt 0)
        SelectedCleanupItemCount = [int]$selectedCleanupIds.Count
        BackupDirectory = [string]$backupDirectory
        CleanupConclusion = [string]$verification.Conclusion
        HandlingGuidance = $verification.HandlingGuidance
        NextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $cleanupItems -ProtectedLicense ([bool]$postProtectedLicense.Protected) -BackupDirectory $backupDirectory)
        ScopeNote = [string]$verification.ScopeNote
        ReportPath = [string]$reportPath
        Actions = @($actions)
    })
    Write-DecisionData -Path $DecisionFile -Data $decisionData
}

Write-Report -Path $reportPath -Products $products -Findings $findings -Decision $decision -Actions $actions -History $history -Verification $verification

# Bộ tóm tắt máy đọc được và hash đi kèm giúp đối chiếu hậu kiểm mà không
# thay đổi luồng xử lý v3.0. Không ghi product key đầy đủ vào JSON.
$jsonReportPath = [IO.Path]::ChangeExtension($reportPath, ".json")
$hashReportPath = [IO.Path]::ChangeExtension($reportPath, ".sha256")
$cleanupSummary = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.4" -Data ([ordered]@{
    ComputerName = $reportComputer
    CreatedAt = (Get-Date).ToString("o")
    Redacted = [bool]$RedactSensitive
    Remediate = [bool]$Remediate
    DeepClean = [bool]$DeepClean
    ReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
    CleanupConclusion = [string]$verification.Conclusion
    HandlingGuidance = $verification.HandlingGuidance
    ReadinessReviewCount = [int]$verification.ReadinessReviewCount
    ScanWarningCount = [int]$verification.ScanWarningCount
    ScanWarnings = $verification.ScanWarnings
    WindowsLicenseSourceNote = [string]$script:WindowsLicenseSourceNote
    ReadinessChecks = $verification.ReadinessChecks
    ActivatorFindingCount = [int]$verification.ActiveActivatorFindingCount
    ConfigurationResidueCount = [int]$verification.ConfigurationResidueCount
    WindowsKmsCount = [int]$verification.UnapprovedWindowsKmsCount
    OfficeKmsCount = [int]$verification.UnapprovedOfficeKmsCount
    HistoryFindingCount = [int]$verification.HistoryFindingCount
    CleanupItems = @($cleanupItems)
    NextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $cleanupItems -ProtectedLicense ([bool]$decisionData.ProtectedLicense) -BackupDirectory $backupDirectory)
    ApprovedKmsServerFile = Protect-CleanupReportText ([string]$approvedKmsConfig.Path)
    ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
    InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
    ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
    ReportPath = Protect-CleanupReportText $reportPath
    ScopeNote = Protect-CleanupReportText ([string]$verification.ScopeNote)
    Actions = @($actions | ForEach-Object { Protect-CleanupReportText $_ })
})
$cleanupSummaryValidation = Test-ToolReportEnvelope -Report $cleanupSummary -ExpectedReportKind "CleanupCompliance" -ExpectedToolVersion "4.4"
if (-not $cleanupSummaryValidation.Valid) { throw "Báo cáo cleanup không đạt schema: $($cleanupSummaryValidation.Errors -join '; ')" }
$cleanupJson = $cleanupSummary | ConvertTo-Json -Depth 8
Protect-CleanupReportText $cleanupJson | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8
$reportHash = ""
try {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    } else {
        $stream = [IO.File]::OpenRead($reportPath)
        try { $sha = [Security.Cryptography.SHA256]::Create(); $reportHash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant() } finally { $stream.Dispose() }
    }
} catch {}
"$reportHash  $([IO.Path]::GetFileName($reportPath))" | Set-Content -LiteralPath $hashReportPath -Encoding ASCII

Write-Host "Báo cáo: $reportPath"
Write-Host "Tóm tắt JSON: $jsonReportPath"
Write-Host "SHA-256 báo cáo: $hashReportPath"
if ($approvedKmsConfig.Warning) { Write-Warning $approvedKmsConfig.Warning }
Write-Host "Đánh giá: $($decision.Decision)"
Write-Host "Lý do: $($decision.Reason)"
if ($Remediate) {
    Write-Host "Số hành động xử lý: $($actions.Count)"
    Write-Host "Sẵn sàng kích hoạt chính thức: $($verification.ReadyForOfficialActivation)"
    Write-Host "Đã yêu cầu gỡ sạch nâng cao: $DeepClean"
    Write-Host "Đã áp dụng thay đổi có backup: $($decisionData.DeepCleanupApplied)"
    Write-Host "Kết luận: $($verification.Conclusion)"
    if (-not $verification.ReadyForOfficialActivation) {
        exit 4
    }
}
if ($decision.Decision -eq "Cần kiểm tra thủ công") {
    exit 2
}
if ($decision.ShouldRemediate -and -not $Remediate) {
    exit 3
}
exit 0




