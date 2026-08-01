param(
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$DecisionFile = ""
)

if ($PSVersionTable.PSVersion.Major -lt 3) { exit 10 }
$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1." }
    if (-not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf)) { throw "Thiếu Tool-SafetyPolicy.ps1." }
    . $runtimeHelper
    . $safetyPolicyHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }
$ErrorActionPreference = "Continue"

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ResultFile($Data) {
    if ([string]::IsNullOrWhiteSpace($DecisionFile)) { return }
    try { $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8 } catch {}
}

function Fail-Restore([int]$Code, [string]$Message) {
    Write-ResultFile ([pscustomobject]@{ Success=$false; RestoredCount=0; SkippedCount=0; ErrorCount=1; ReportPath=""; Message=$Message })
    exit $Code
}

try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
catch { Fail-Restore 11 "Không tải được System.Security để xác thực backup." }

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
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw "Dữ liệu backup chứa reparse point: $Path" }
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

function Test-ProtectedBackupAcl([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ownerSid -ne "S-1-5-32-544" -or -not $acl.AreAccessRulesProtected) { return $false }
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $allowedWriters -notcontains $rule.IdentityReference.Value -and (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch { return $false }
}

$script:backupRoot = ""
function Resolve-BackupPath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) { return "" }
    try {
        $candidate = [IO.Path]::GetFullPath((Join-Path $script:backupRoot $RelativePath))
        $prefix = $script:backupRoot.TrimEnd('\') + '\'
        if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return "" }
        return $candidate
    } catch { return "" }
}

function Test-RegFileScope([string]$FilePath, [string]$ExpectedNativePath) {
    try {
        $headers = @(Get-Content -LiteralPath $FilePath -ErrorAction Stop | ForEach-Object {
            if ($_ -match '^\[-?(HKEY_[^\]]+)\]$') { $matches[1] }
        })
        if ($headers.Count -eq 0) { return $false }
        foreach ($header in $headers) {
            if ($header -ne $ExpectedNativePath -and -not $header.StartsWith($ExpectedNativePath + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Test-CompatibleScheduledTask([string]$TaskName, [string]$TaskPath) {
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            return [bool](Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop)
        } catch { return $false }
    }
    $fullName = $TaskPath + $TaskName
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    & $schtasks /Query /TN $fullName 1>$null 2>$null
    return [bool]($LASTEXITCODE -eq 0)
}

function Register-CompatibleScheduledTask([string]$TaskName, [string]$TaskPath, [string]$XmlPath, [bool]$WasEnabled) {
    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml (Get-Content -LiteralPath $XmlPath -Raw) -Force -ErrorAction Stop | Out-Null
        if (-not $WasEnabled) { Disable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop | Out-Null }
        return
    }
    $fullName = $TaskPath + $TaskName
    $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
    $createOutput = @(& $schtasks /Create /TN $fullName /XML $XmlPath /F 2>&1)
    if ($LASTEXITCODE -ne 0) { throw (($createOutput | ForEach-Object { [string]$_ }) -join " | ") }
    if (-not $WasEnabled) {
        $disableOutput = @(& $schtasks /Change /TN $fullName /Disable 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($disableOutput | ForEach-Object { [string]$_ }) -join " | ") }
    }
}

if (-not (Is-Admin)) { Fail-Restore 20 "Cần quyền Administrator." }
try { $script:backupRoot = ([IO.Path]::GetFullPath($BackupDir)).TrimEnd('\') } catch { Fail-Restore 21 "Đường dẫn backup không hợp lệ." }
if (-not (Test-Path -LiteralPath $script:backupRoot -PathType Container)) { Fail-Restore 21 "Không tìm thấy thư mục backup." }
$commonData = [Environment]::GetFolderPath("CommonApplicationData")
$productRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra"
$versionRoot = Join-Path $productRoot "v4.4"
$expectedBackupRoot = Join-Path $versionRoot "backups"
try { $expectedBackupRoot = ([IO.Path]::GetFullPath($expectedBackupRoot)).TrimEnd('\') } catch { Fail-Restore 21 "Không xác định được vùng backup bảo vệ." }
$expectedPrefix = $expectedBackupRoot + '\'
if (-not $script:backupRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { Fail-Restore 23 "Chỉ khôi phục backup nguyên bản trong vùng ProgramData được bảo vệ." }
foreach ($protectedPath in @($productRoot, $versionRoot, $expectedBackupRoot, $script:backupRoot)) {
    if (-not (Test-ProtectedBackupAcl $protectedPath)) { Fail-Restore 23 "Thư mục backup hoặc thư mục cha không còn ACL an toàn." }
}

$manifestPath = Join-Path $script:backupRoot "RESTORE-MANIFEST.json"
$hmacPath = Join-Path $script:backupRoot "RESTORE-MANIFEST.hmac"
$authPath = Join-Path $script:backupRoot "RESTORE-AUTH.bin"
foreach ($required in @($manifestPath, $hmacPath, $authPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { Fail-Restore 21 "Bộ backup thiếu thành phần xác thực bắt buộc." }
    if (((Get-Item -LiteralPath $required -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail-Restore 23 "Thành phần xác thực backup là reparse point không an toàn." }
}

try {
    $protectedKey = [IO.File]::ReadAllBytes($authPath)
    $hmacKey = [Security.Cryptography.ProtectedData]::Unprotect($protectedKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $expectedHmac = ([IO.File]::ReadAllText($hmacPath)).Trim().ToUpperInvariant()
    if ($expectedHmac -notmatch '^[0-9A-F]{64}$') { throw "HMAC sai định dạng." }
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
    try { $actualHmac = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($manifestPath))) -replace '-', '').ToUpperInvariant() }
    finally { $hmac.Dispose() }
    if ($actualHmac -ne $expectedHmac) { throw "HMAC của manifest không khớp." }
    if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }
} catch { Fail-Restore 24 "Xác thực manifest thất bại: $($_.Exception.Message)" }

try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { Fail-Restore 22 "Manifest không hợp lệ: $($_.Exception.Message)" }
if ([string]$manifest.SchemaVersion -ne "2.0" -or [string]$manifest.ToolVersion -ne "4.4") { Fail-Restore 25 "Phiên bản manifest không được hỗ trợ an toàn." }
if ([string]$manifest.ComputerName -ne $env:COMPUTERNAME -or [string]$manifest.MachineBinding -ne (Get-MachineBinding)) { Fail-Restore 26 "Backup không thuộc đúng máy hiện tại." }
$manifestItems = @($manifest.Items)
if ($manifestItems.Count -eq 0 -or $manifestItems.Count -gt 5000) { Fail-Restore 27 "Số lượng mục trong manifest không hợp lệ." }

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::Equals(([IO.Path]::GetFullPath($scriptDirectory)).TrimEnd('\'), $script:backupRoot, [StringComparison]::OrdinalIgnoreCase)) {
    if ([string]$manifest.RestoreScriptSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-Sha256 $MyInvocation.MyCommand.Path) -ne ([string]$manifest.RestoreScriptSha256).ToUpperInvariant()) {
        Fail-Restore 28 "Script khôi phục trong thư mục backup không còn nguyên vẹn."
    }
    if ([string]$manifest.RuntimeHelperSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf) -or
        (Get-Sha256 $runtimeHelper) -ne ([string]$manifest.RuntimeHelperSha256).ToUpperInvariant()) {
        Fail-Restore 28 "Tool-Runtime.ps1 trong thư mục backup không còn nguyên vẹn."
    }
    if ([string]$manifest.SafetyPolicySha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf) -or
        (Get-Sha256 $safetyPolicyHelper) -ne ([string]$manifest.SafetyPolicySha256).ToUpperInvariant()) {
        Fail-Restore 28 "Tool-SafetyPolicy.ps1 trong thư mục backup không còn nguyên vẹn."
    }
}

# Tiền kiểm toàn bộ trước khi thực hiện bất kỳ thay đổi nào.
$allowedTypes = @("RegistryValues", "Registry", "ScheduledTask", "Service", "File", "Folder", "Defender", "LicenseNotice")
$resolvedPaths = @{}
foreach ($item in $manifestItems) {
    if ($allowedTypes -notcontains [string]$item.Type) { Fail-Restore 29 "Manifest chứa loại mục không được hỗ trợ: $($item.Type)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$item.BackupPath)) {
        $source = Resolve-BackupPath ([string]$item.BackupPath)
        if (-not $source -or -not (Test-Path -LiteralPath $source)) { Fail-Restore 30 "Thiếu dữ liệu backup cho $($item.Type): $($item.Name)" }
        if ([string]$item.BackupSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-PathHash $source) -ne ([string]$item.BackupSha256).ToUpperInvariant()) {
            Fail-Restore 31 "SHA-256 dữ liệu backup không khớp: $($item.Name)"
        }
        $resolvedPaths[[string]$item.BackupPath] = $source
    } elseif ([string]$item.Type -notin @("Defender", "LicenseNotice")) {
        Fail-Restore 32 "Mục backup thiếu đường dẫn dữ liệu: $($item.Type) - $($item.Name)"
    }
}

$actions = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]
$restored = 0
$skipped = 0
$reportPath = Join-Path $script:backupRoot ("restore_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
$registryValueRestorePolicy = @(Get-ToolRegistryValueRestorePolicy)

foreach ($item in $manifestItems) {
    try {
        $source = if ([string]$item.BackupPath) { [string]$resolvedPaths[[string]$item.BackupPath] } else { "" }
        switch ([string]$item.Type) {
            "RegistryValues" {
                $allowedNamesForPath = @(Get-ToolAllowedRegistryValueNames -Path ([string]$item.OriginalPath))
                if ($allowedNamesForPath.Count -eq 0) { throw "RegistryValues nằm ngoài phạm vi SPP/policy cho phép." }
                $data = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
                if ([string]$data.RegistryPath -ne [string]$item.OriginalPath) { throw "Đường dẫn RegistryValues không khớp manifest." }
                $key = Get-Item -LiteralPath ([string]$item.OriginalPath) -ErrorAction Stop
                foreach ($entry in @($data.Values)) {
                    if (-not (Test-ToolRegistryValueRestoreAllowed -Path ([string]$item.OriginalPath) -ValueName ([string]$entry.Name))) { throw "Tên Registry value nằm ngoài phạm vi cho phép tại đường dẫn này: $($entry.Name)" }
                    $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$entry.Kind, $true))
                    $value = $entry.Value
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $value = [Convert]::FromBase64String([string]$value) }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $value = [int]$value }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $value = [long]$value }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $value = [string[]]@($value) }
                    else { $value = [string]$value }
                    $key.SetValue([string]$entry.Name, $value, $kind)
                }
                $actions.Add("Đã phục hồi các giá trị Registry: $($item.Name)"); $restored++
            }
            "Registry" {
                $nativePath = ([string]$item.OriginalPath) -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                $allowed = $nativePath -like 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\*'
                if (-not $allowed -or -not (Test-RegFileScope $source $nativePath)) { throw "File Registry nằm ngoài phạm vi IFEO đã xác thực." }
                $output = (& $nativeRegPath import $source 2>&1) -join " | "; if ($LASTEXITCODE -ne 0) { throw $output }
                $actions.Add("Đã phục hồi Registry: $($item.Name)"); $restored++
            }
            "ScheduledTask" {
                $taskName = [string]$item.Name; $taskPath = [string]$item.OriginalPath
                if ([string]::IsNullOrWhiteSpace($taskName) -or -not $taskPath.StartsWith('\') -or $taskPath.Contains('..')) { throw "Tên hoặc đường dẫn task không hợp lệ." }
                if (Test-CompatibleScheduledTask -TaskName $taskName -TaskPath $taskPath) { $actions.Add("BỎ QUA task đã tồn tại: $taskPath$taskName"); $skipped++; break }
                Register-CompatibleScheduledTask -TaskName $taskName -TaskPath $taskPath -XmlPath $source -WasEnabled ([bool]$item.WasEnabled)
                $actions.Add("Đã phục hồi scheduled task: $taskPath$taskName"); $restored++
            }
            "Service" {
                $serviceName = [string]$item.Name
                if ($serviceName -notmatch '^[A-Za-z0-9_.-]{1,256}$') { throw "Tên service không hợp lệ." }
                $nativePath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$serviceName"
                if (-not (Test-RegFileScope $source $nativePath)) { throw "File Registry service vượt ra ngoài khóa service đã xác thực." }
                if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
                    $startMode = switch ([string]$item.StartMode) { "Auto" { "auto" }; "Automatic" { "auto" }; "Disabled" { "disabled" }; default { "demand" } }
                    $arguments = @("create", $serviceName, "binPath=", [string]$item.PathName, "start=", $startMode, "DisplayName=", [string]$item.DisplayName)
                    $builtInAccount = switch -Regex ([string]$item.StartName) { '^LocalSystem$' { 'LocalSystem'; break }; '^NT AUTHORITY\\LocalService$' { 'NT AUTHORITY\LocalService'; break }; '^NT AUTHORITY\\NetworkService$' { 'NT AUTHORITY\NetworkService'; break }; default { '' } }
                    if ($builtInAccount) { $arguments += @("obj=", $builtInAccount) }
                    if (@($item.Dependencies).Count -gt 0) { $arguments += @("depend=", (@($item.Dependencies) -join '/')) }
                    $createOutput = (& $nativeScPath @arguments 2>&1) -join " | "; if ($LASTEXITCODE -ne 0) { throw $createOutput }
                }
                $regOutput = (& $nativeRegPath import $source 2>&1) -join " | "; if ($LASTEXITCODE -ne 0) { throw $regOutput }
                if ([string]$item.SecurityDescriptor -match '^D:') { & $nativeScPath sdset $serviceName ([string]$item.SecurityDescriptor) | Out-Null }
                if ([bool]$item.WasRunning -and ([string]$item.StartName -match '^(LocalSystem|NT AUTHORITY\\(LocalService|NetworkService))$')) { Start-Service -Name $serviceName -ErrorAction SilentlyContinue }
                if ([string]$item.StartName -and ([string]$item.StartName -notmatch '^(LocalSystem|NT AUTHORITY\\(LocalService|NetworkService))$')) { $actions.Add("LƯU Ý: service $serviceName dùng tài khoản riêng; cần nhập lại mật khẩu dịch vụ trước khi chạy.") }
                $actions.Add("Đã phục hồi cấu hình service đã sao lưu: $serviceName"); $restored++
            }
            { $_ -in @("File", "Folder") } {
                $destination = [string]$item.OriginalPath
                if (-not [IO.Path]::IsPathRooted($destination)) { throw "Đường dẫn đích không tuyệt đối." }
                if (Test-Path -LiteralPath $destination) { $actions.Add("BỎ QUA vì đích đã tồn tại: $destination"); $skipped++; break }
                $parent = Split-Path -Parent $destination; if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $source -Destination $destination -Recurse:([string]$item.Type -eq "Folder") -Force -ErrorAction Stop
                $actions.Add("Đã phục hồi $([string]$item.Type): $destination"); $restored++
            }
            "Defender" {
                $actions.Add("BỎ QUA AN TOÀN ngoại lệ Defender, không tự động thêm lại: $($item.OriginalPath)"); $skipped++
            }
            "LicenseNotice" {
                $actions.Add("KHÔNG THỂ TỰ KHÔI PHỤC product key (tool không lưu key đầy đủ): $($item.Name)"); $skipped++
            }
        }
    } catch {
        $message = "LỖI [$($item.Type)] $($item.Name): $($_.Exception.Message)"
        $errors.Add($message); $actions.Add($message)
    }
}

$restoreGuidance = if ($errors.Count -gt 0) {
    @(
        "Dừng mọi lần gỡ tiếp theo; không xóa hoặc di chuyển thư mục backup."
        "Không bỏ qua cảnh báo ACL, HMAC, ràng buộc máy hoặc SHA-256."
        "Mở báo cáo này, xử lý nguyên nhân được ghi ở phần CHI TIẾT rồi chạy lại chức năng xem trước bằng bản tool mới nhất."
    )
} else {
    @(
        "Quét lại mục 6 để xác nhận KMS/activator/tồn dư đã về 0."
        "Nếu Windows hoặc Office chưa kích hoạt, chỉ dùng giấy phép chính thức hoặc KMS nội bộ đã được đơn vị xác nhận."
    )
}
$restoreReport = @(
    "KHÔI PHỤC TỰ ĐỘNG - TOOL KIỂM TRA v4.4"
    "Thời gian: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Thư mục backup: $script:backupRoot"
    "Đã phục hồi: $restored"
    "Bỏ qua: $skipped"
    "Lỗi: $($errors.Count)"
    ""
    "CHI TIẾT:"
) + $actions.ToArray() + @(
    ""
    "HƯỚNG XỬ LÝ TIẾP:"
) + $restoreGuidance
$restoreReport | Set-Content -LiteralPath $reportPath -Encoding UTF8
$success = [bool]($errors.Count -eq 0)
Write-ResultFile ([pscustomobject]@{ Success=$success; RestoredCount=[int]$restored; SkippedCount=[int]$skipped; ErrorCount=[int]$errors.Count; ReportPath=$reportPath; Message=if ($success) { "Khôi phục hoàn tất sau khi xác thực toàn bộ backup." } else { "Khôi phục hoàn tất nhưng có mục lỗi." } })
if ($success) { exit 0 } else { exit 4 }
