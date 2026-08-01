param(
    [string]$OutputDir = "",
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
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $PSScriptRoot "license-cleanup-reports" }
$strictPattern = "(?i)(kmspico|kmsauto|auto[\s_-]*kms|autokms|kms[_-]?vl|kms-r|aact(?:portable)?|sppextcomobj(?:patcher|hook)|microsoft toolkit|hwidgen|\bmassgrave\b)"
$script:BackupScanWarnings = New-Object System.Collections.Generic.List[string]

function Add-BackupScanWarning([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and -not $script:BackupScanWarnings.Contains($Message)) {
        [void]$script:BackupScanWarnings.Add($Message)
    }
}

function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
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

function Test-ProtectedBackupAcl([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
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
        if (-not (Test-ProtectedBackupAcl $path)) { throw "ACL vùng backup không đạt yêu cầu: $path" }
    }
    return $backupRoot
}

function Safe-Cim([string]$ClassName) {
    $firstError = ""
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop) }
        return @(Get-WmiObject -Class $ClassName -ErrorAction Stop)
    } catch { $firstError = $_.Exception.Message }
    try { return @(Get-WmiObject -Class $ClassName -ErrorAction Stop) }
    catch {
        Add-BackupScanWarning "Không thể đọc ${ClassName}: $firstError | $($_.Exception.Message)"
        return @()
    }
}

function Get-CompatibleScheduledTaskRecords {
    $firstError = ""
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            return @(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    TaskName=[string]$_.TaskName; TaskPath=[string]$_.TaskPath
                    FullName=([string]$_.TaskPath + [string]$_.TaskName)
                    ActionsText=[string]($_.Actions | Out-String)
                    WasEnabled=[bool]($_.State -ne "Disabled"); Source="ScheduledTasks"
                }
            })
        } catch { $firstError = $_.Exception.Message }
    }
    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw "Không tìm thấy schtasks.exe." }
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw "schtasks không trả danh sách CSV hợp lệ." }
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($row in @($csvLines | ConvertFrom-Csv)) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $fullName = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($fullName)) { continue }
            $lastSlash = $fullName.LastIndexOf('\')
            if ($lastSlash -lt 0 -or $lastSlash -ge ($fullName.Length - 1)) { continue }
            [void]$records.Add([pscustomobject]@{
                TaskName=$fullName.Substring($lastSlash + 1)
                TaskPath=$fullName.Substring(0, $lastSlash + 1)
                FullName=$fullName; ActionsText=($values -join " | ")
                WasEnabled=$true; Source="Schtasks"
            })
        }
        if ($records.Count -eq 0) { throw "Không phân tích được tên scheduled task từ schtasks." }
        return $records.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-BackupScanWarning "Không thể quét Scheduled Tasks: $detail"
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
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Từ chối backup reparse point: $Path" }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw "Thư mục backup chứa reparse point: $Path" }
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

function Write-Result($Data) {
    if ([string]::IsNullOrWhiteSpace($DecisionFile)) { return }
    try { $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8 } catch {}
}

try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
catch {
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=""; ReportPath=""; Message="Không tải được System.Security để bảo vệ khóa backup." })
    exit 11
}

if (-not (Is-Admin)) {
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=""; ReportPath=""; Message="Cần quyền Administrator để tạo backup đầy đủ." })
    exit 20
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = ""
try {
    $secureBackupRoot = Get-SecureBackupRoot
    $backupDir = Join-Path $secureBackupRoot ("backup_pre_cleanup_$($env:COMPUTERNAME)_${stamp}_" + [guid]::NewGuid().ToString("N"))
    Ensure-Dir $backupDir
    Set-ProtectedBackupAcl $backupDir
    if (-not (Test-ProtectedBackupAcl $backupDir)) { throw "ACL thư mục backup mới không đạt yêu cầu." }
} catch {
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=$backupDir; ReportPath=""; Message="Không thể tạo vùng backup bảo vệ trong ProgramData: $($_.Exception.Message)" })
    exit 23
}

$manifestPath = Join-Path $backupDir "RESTORE-MANIFEST.json"
$hmacPath = Join-Path $backupDir "RESTORE-MANIFEST.hmac"
$authPath = Join-Path $backupDir "RESTORE-AUTH.bin"
$reportPath = Join-Path $backupDir "BACKUP-REPORT.txt"
$items = New-Object System.Collections.Generic.List[object]
$actions = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]
$restoreScriptSha256 = ""
$runtimeHelperSha256 = ""
$safetyPolicySha256 = ""

$hmacKey = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($hmacKey) } finally { $rng.Dispose() }
$protectedKey = [Security.Cryptography.ProtectedData]::Protect($hmacKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
[IO.File]::WriteAllBytes($authPath, $protectedKey)

function Save-Manifest {
    $manifest = [ordered]@{
        SchemaVersion="2.0"
        ToolVersion="4.4"
        BackupMode="PreCleanup"
        ComputerName=$env:COMPUTERNAME
        MachineBinding=(Get-MachineBinding)
        CreatedAt=(Get-Date).ToString("o")
        RestoreScriptSha256=$restoreScriptSha256
        RuntimeHelperSha256=$runtimeHelperSha256
        SafetyPolicySha256=$safetyPolicySha256
        # Windows PowerShell 5.1 can throw "Argument types do not match" when
        # @() is applied directly to List[object]. ToArray() is compatible with
        # PowerShell 3+ and keeps the manifest shape deterministic.
        Items=$items.ToArray()
    }
    $tempManifest = Join-Path $backupDir (".manifest-" + [guid]::NewGuid().ToString("N") + ".tmp")
    $tempHmac = $tempManifest + ".hmac"
    [IO.File]::WriteAllText($tempManifest, ($manifest | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
    try { $signature = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($tempManifest))) -replace '-', '').ToUpperInvariant() }
    finally { $hmac.Dispose() }
    [IO.File]::WriteAllText($tempHmac, $signature, [Text.Encoding]::ASCII)
    Move-Item -LiteralPath $tempManifest -Destination $manifestPath -Force
    Move-Item -LiteralPath $tempHmac -Destination $hmacPath -Force
}

function Add-BackupItem($Item) {
    $items.Add($Item)
    Save-Manifest
}

function New-FileBackedItem([string]$Type, [string]$Name, [string]$OriginalPath, [string]$BackupPath, [string]$Kind, $Extra) {
    $relative = [IO.Path]::GetFileName($BackupPath)
    $data = [ordered]@{ Type=$Type; Name=$Name; OriginalPath=$OriginalPath; BackupPath=$relative; BackupSha256=(Get-PathHash $BackupPath); Kind=$Kind }
    if ($Extra) { foreach ($property in $Extra.PSObject.Properties) { $data[$property.Name] = $property.Value } }
    return [pscustomobject]$data
}

function Backup-RegistryValues([string]$PsPath, [string[]]$Names, [string]$Label) {
    if (-not (Test-Path -LiteralPath $PsPath)) { return }
    try {
        $key = Get-Item -LiteralPath $PsPath -ErrorAction Stop
        $values = New-Object System.Collections.Generic.List[object]
        foreach ($name in $Names) {
            try {
                $kind = [string]$key.GetValueKind($name)
                $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($kind -eq "Binary") { $value = [Convert]::ToBase64String([byte[]]$value) }
                $values.Add([pscustomobject]@{ Name=$name; Kind=$kind; Value=$value })
            } catch {}
        }
        if ($values.Count -eq 0) { return }
        $fileName = (($Label -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N') + '.json')
        $backupPath = Join-Path $backupDir $fileName
        [pscustomobject]@{ RegistryPath=$PsPath; Values=$values.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath -Encoding UTF8
        Add-BackupItem (New-FileBackedItem "RegistryValues" $Label $PsPath $backupPath "PreCleanup" $null)
        $actions.Add("Đã backup các giá trị KMS cần thiết: $PsPath")
    } catch { $errors.Add("Không thể backup giá trị Registry ${PsPath}: $($_.Exception.Message)") }
}

function Backup-RegistryKey([string]$PsPath, [string]$Label, [string]$Kind) {
    if (-not (Test-Path -LiteralPath $PsPath)) { return }
    try {
        $nativePath = $PsPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
        $backupPath = Join-Path $backupDir ((($Label -replace '[\\/:*?"<>| ]','_')) + '_' + [guid]::NewGuid().ToString('N') + '.reg')
        $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $output }
        Add-BackupItem (New-FileBackedItem "Registry" $Label $PsPath $backupPath $Kind $null)
        $actions.Add("Đã backup Registry: $PsPath")
    } catch { $errors.Add("Không thể backup Registry ${PsPath}: $($_.Exception.Message)") }
}

Save-Manifest

# Chỉ lưu các giá trị KMS có thể bị thay đổi; không export toàn bộ SPP hay product key.
$windowsSppPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
$officeSppPath = "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
$windowsPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
Backup-RegistryValues $windowsSppPath (Get-ToolAllowedRegistryValueNames -Path $windowsSppPath) "Windows_SPP_KMS"
Backup-RegistryValues $officeSppPath (Get-ToolAllowedRegistryValueNames -Path $officeSppPath) "Office_SPP_KMS"
Backup-RegistryValues $windowsPolicyPath (Get-ToolAllowedRegistryValueNames -Path $windowsPolicyPath) "Windows_SPP_Policy"
foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
    try {
        if ((Get-ItemProperty -LiteralPath $ifeoPath -ErrorAction Stop | Out-String) -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|hook\.dll|sppextcomobj(?:hook|patcher))") {
            Backup-RegistryKey $ifeoPath "IFEO_$imageName" "PreCleanup"
        }
    } catch {}
}

foreach ($task in @(Get-CompatibleScheduledTaskRecords | Where-Object {
    $_.TaskName -match $strictPattern -or $_.TaskPath -match $strictPattern -or $_.ActionsText -match $strictPattern
})) {
    try {
        $backupPath = Join-Path $backupDir ("Task_" + ($task.TaskName -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N') + '.xml')
        Export-CompatibleScheduledTask -Record $task -Path $backupPath
        Add-BackupItem (New-FileBackedItem "ScheduledTask" ([string]$task.TaskName) ([string]$task.TaskPath) $backupPath "PreCleanup" ([pscustomobject]@{ WasEnabled=[bool]$task.WasEnabled }))
        $actions.Add("Đã backup task: $($task.FullName)")
    } catch { $errors.Add("Không thể backup task $($task.FullName): $($_.Exception.Message)") }
}

foreach ($service in @(Safe-Cim "Win32_Service" | Where-Object {
    $_.Name -match $strictPattern -or $_.DisplayName -match $strictPattern -or $_.PathName -match $strictPattern
})) {
    try {
        $serviceReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.Name)"
        $nativeServiceReg = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($service.Name)"
        $backupPath = Join-Path $backupDir ("Service_" + ($service.Name -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N') + '.reg')
        $regOutput = (& $nativeRegPath export $nativeServiceReg $backupPath /y 2>&1) -join " | "
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $regOutput }
        $dependencies = @()
        try { $dependencies = @(Get-Service -Name $service.Name -ErrorAction Stop | Select-Object -ExpandProperty ServicesDependedOn | Select-Object -ExpandProperty Name) } catch {}
        $sddl = ""
        try { $sddl = ((& $nativeScPath sdshow $service.Name 2>$null) | Where-Object { $_ -match '^D:' } | Select-Object -First 1) } catch {}
        Add-BackupItem (New-FileBackedItem "Service" ([string]$service.Name) $serviceReg $backupPath "PreCleanup" ([pscustomobject]@{
            DisplayName=[string]$service.DisplayName; PathName=[string]$service.PathName; StartMode=[string]$service.StartMode
            StartName=[string]$service.StartName; Description=[string]$service.Description; WasRunning=[bool]($service.State -eq "Running")
            Dependencies=@($dependencies); SecurityDescriptor=[string]$sddl
        }))
        $actions.Add("Đã backup đầy đủ cấu hình service: $($service.Name)")
    } catch { $errors.Add("Không thể backup service $($service.Name): $($_.Exception.Message)") }
}

foreach ($hookPath in @((Get-ToolNativeSystemPath "SppExtComObjHook.dll"), (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll"))) {
    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) { continue }
    try {
        if (((Get-Item -LiteralPath $hookPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Từ chối reparse point." }
        $backupPath = Join-Path $backupDir ((Split-Path $hookPath -Leaf) + '_' + [guid]::NewGuid().ToString('N') + '.backup')
        Copy-Item -LiteralPath $hookPath -Destination $backupPath -Force -ErrorAction Stop
        Add-BackupItem (New-FileBackedItem "File" (Split-Path $hookPath -Leaf) $hookPath $backupPath "PreCleanup" $null)
        $actions.Add("Đã backup tệp: $hookPath")
    } catch { $errors.Add("Không thể backup tệp ${hookPath}: $($_.Exception.Message)") }
}

$scanRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData, (Join-Path $env:SystemDrive "KMS"), (Join-Path $env:SystemDrive "KMSAuto"), (Join-Path $env:SystemDrive "KMSpico"), (Join-Path $env:SystemDrive "AAct")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
foreach ($root in $scanRoots) {
    try {
        foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $strictPattern })) {
            if (($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $errors.Add("Bỏ qua reparse point: $($folder.FullName)"); continue }
            $backupPath = Join-Path $backupDir ("Folder_" + ($folder.Name -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $folder.FullName -Destination $backupPath -Recurse -Force -ErrorAction Stop
            Add-BackupItem (New-FileBackedItem "Folder" $folder.Name $folder.FullName $backupPath "PreCleanup" $null)
            $actions.Add("Đã backup thư mục: $($folder.FullName)")
        }
    } catch { $errors.Add("Không thể backup thư mục trong ${root}: $($_.Exception.Message)") }
}

try {
    $preference = Get-MpPreference -ErrorAction Stop
    foreach ($excludedPath in @($preference.ExclusionPath)) {
        if ([string]$excludedPath -match $strictPattern) {
            Add-BackupItem ([pscustomobject]@{ Type="Defender";Name="Ngoại lệ Defender";OriginalPath=[string]$excludedPath;BackupPath="";BackupSha256="";Kind="PreCleanup" })
            $actions.Add("Đã ghi nhận ngoại lệ Defender (chỉ để tham khảo, không tự khôi phục): $excludedPath")
        }
    }
} catch { $actions.Add("Không đọc được ngoại lệ Defender hoặc Defender không khả dụng.") }

try {
    $restoreSource = Join-Path $PSScriptRoot "windows-license-restore.ps1"
    if (Test-Path -LiteralPath $restoreSource -PathType Leaf) {
        $restoreDestination = Join-Path $backupDir "windows-license-restore.ps1"
        Copy-Item -LiteralPath $restoreSource -Destination $restoreDestination -Force
        $restoreScriptSha256 = Get-Sha256 $restoreDestination
        $runtimeSource = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
        if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) { throw "Thiếu Tool-Runtime.ps1 để tạo bộ khôi phục." }
        $runtimeDestination = Join-Path $backupDir "Tool-Runtime.ps1"
        Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Force
        $runtimeHelperSha256 = Get-Sha256 $runtimeDestination
        $safetyPolicySource = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
        if (-not (Test-Path -LiteralPath $safetyPolicySource -PathType Leaf)) { throw "Thiếu Tool-SafetyPolicy.ps1 để tạo bộ khôi phục." }
        $safetyPolicyDestination = Join-Path $backupDir "Tool-SafetyPolicy.ps1"
        Copy-Item -LiteralPath $safetyPolicySource -Destination $safetyPolicyDestination -Force
        $safetyPolicySha256 = Get-Sha256 $safetyPolicyDestination
        @(
            '@echo off',
            'set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
            'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
            '"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-license-restore.ps1" -BackupDir "%~dp0"',
            'pause'
        ) |
            Set-Content -LiteralPath (Join-Path $backupDir "KHOI-PHUC-TU-DONG.cmd") -Encoding ASCII
    }
    @(
        "BACKUP TRƯỚC KHI THỰC HIỆN - TOOL v4.4",
        "Dùng nút Khôi phục tự động trong mục 6 hoặc chạy KHOI-PHUC-TU-DONG.cmd bằng quyền Administrator.",
        "Backup không export toàn bộ khóa SPP/product key; chỉ lưu giá trị KMS cần thiết và các mục nghi vấn đã xác định.",
        "Manifest, từng tệp backup và đúng máy sẽ được xác thực trước khi khôi phục.",
        "Ngoại lệ Defender chỉ được ghi nhận, không tự động thêm lại."
    ) | Set-Content -LiteralPath (Join-Path $backupDir "PHUC-HOI.txt") -Encoding UTF8
} catch { $errors.Add("Không thể tạo bộ khôi phục tự động: $($_.Exception.Message)") }

foreach ($scanWarning in @($script:BackupScanWarnings)) {
    if (-not $errors.Contains($scanWarning)) { [void]$errors.Add($scanWarning) }
}

Save-Manifest
$backupReport = @(
    "BACKUP TRƯỚC KHI THỰC HIỆN - TOOL KIỂM TRA v4.4"
    "Thời gian: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Máy: $env:COMPUTERNAME"
    "Thư mục: $backupDir"
    "Số mục backup: $($items.Count)"
    "Số cảnh báo/lỗi: $($errors.Count)"
    ""
    "HÀNH ĐỘNG:"
) + $actions.ToArray() + @(
    ""
    "CẢNH BÁO/LỖI:"
) + $errors.ToArray()
$backupReport | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }

$success = [bool]($errors.Count -eq 0)
Write-Result ([pscustomobject]@{ Success=$success; ItemCount=[int]$items.Count; ErrorCount=[int]$errors.Count; BackupDirectory=$backupDir; ReportPath=$reportPath; Message=if ($success) { "Backup hoàn tất và đã xác thực." } else { "Backup hoàn tất nhưng có cảnh báo/lỗi; hãy xem báo cáo." } })
if ($success) { exit 0 } else { exit 4 }
