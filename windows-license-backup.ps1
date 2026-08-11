param(
    [string]$OutputDir = "",
    [string]$DecisionFile = "",
    [ValidateSet("All", "Windows", "Office", "ThirdParty")]
    [string]$Scope = "All",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN"
)

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-BackupText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-BackupText "common.powerShellRequired" @(3)); exit 10 }
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-BackupText "common.missingDependency" @("Tool-Runtime.ps1")) }
    if (-not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf)) { throw (Get-BackupText "common.missingDependency" @("Tool-SafetyPolicy.ps1")) }
    . $runtimeHelper
    . $safetyPolicyHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }
$ErrorActionPreference = "Continue"
$releaseVersion = "4.8.0.0"
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra" }
$strictPattern = "(?i)(kmspico|kmsauto|auto[\s._-]*kms|autokms|kms[\s._-]*vl(?:[\s._-]*all)?|kms-r|aact(?:portable)?|sppextcomobj(?:patcher|hook)|spp[\s._-]*(?:hook|patcher)|microsoft[\s_-]+toolkit|hwidgen|\bmassgrave\b|mas[\s._-]*aio|tsforge|ohook)"
$includeWindows = [bool]($Scope -in @("All", "Windows"))
$includeOffice = [bool]($Scope -in @("All", "Office"))
$includeThirdParty = [bool]($Scope -in @("All", "ThirdParty"))
$includeActivationArtifacts = [bool]($includeWindows -or $includeOffice)
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

function Get-ToolDataOwnerSid {
    if ([string]$env:TOOL_DATA_SCOPE -ne 'User') { return $null }
    $configuredSid = [string]$env:TOOL_DATA_OWNER_SID
    if (-not [string]::IsNullOrWhiteSpace($configuredSid)) {
        try {
            $sid = New-Object Security.Principal.SecurityIdentifier($configuredSid)
            if ($sid.IsAccountSid()) { return $sid }
        } catch {}
    }
    return [Security.Principal.WindowsIdentity]::GetCurrent().User
}

function Set-ProtectedBackupAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowCurrentUserForUserScope
    )
    $administrators = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $system = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $dataOwnerSid = if ($AllowCurrentUserForUserScope) { Get-ToolDataOwnerSid } else { $null }
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($(if ($dataOwnerSid) { $dataOwnerSid } else { $administrators }))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administrators, "FullControl", $inheritance, "None", "Allow")))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($system, "FullControl", $inheritance, "None", "Allow")))
    if ($dataOwnerSid) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($dataOwnerSid, "FullControl", $inheritance, "None", "Allow")))
    }
    [IO.Directory]::SetAccessControl([IO.Path]::GetFullPath($Path), $acl)
}

function Test-ProtectedBackupAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowCurrentUserForUserScope
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        $allowedOwners = @("S-1-5-32-544", "S-1-5-18")
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        if ($AllowCurrentUserForUserScope -and [string]$env:TOOL_DATA_SCOPE -eq 'User') {
            $dataOwnerSid = Get-ToolDataOwnerSid
            if ($dataOwnerSid) {
                $allowedOwners += $dataOwnerSid.Value
                $allowedWriters += $dataOwnerSid.Value
            }
        }
        if ($ownerSid -notin $allowedOwners -or -not $acl.AreAccessRulesProtected) { return $false }
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $allowedWriters -notcontains $rule.IdentityReference.Value -and (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-SecureBackupRoot {
    $versionRoot = [string]$env:TOOL_DATA_ROOT
    if ([string]::IsNullOrWhiteSpace($versionRoot)) {
        $commonData = [Environment]::GetFolderPath("CommonApplicationData")
        if ([string]::IsNullOrWhiteSpace($commonData)) { throw (Get-BackupText "backupReport.programDataUnknown") }
        $versionRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.6"
    }
    $versionRoot = [IO.Path]::GetFullPath($versionRoot)
    $productRoot = Split-Path -Parent $versionRoot
    $backupRoot = Join-Path $versionRoot "backups"
    $userScope = [bool]([string]$env:TOOL_DATA_SCOPE -eq 'User')
    foreach ($path in @($productRoot, $versionRoot)) {
        if (Test-Path -LiteralPath $path) {
            $existing = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-BackupText "backupReport.invalidRoot" @($path)) }
        } else { Ensure-Dir $path }
        Set-ProtectedBackupAcl -Path $path -AllowCurrentUserForUserScope:$userScope
        if (-not (Test-ProtectedBackupAcl -Path $path -AllowCurrentUserForUserScope:$userScope)) { throw (Get-BackupText "backupReport.invalidAcl" @($path)) }
    }
    if (Test-Path -LiteralPath $backupRoot) {
        $existing = Get-Item -LiteralPath $backupRoot -Force -ErrorAction Stop
        if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-BackupText "backupReport.invalidRoot" @($backupRoot)) }
    } else { Ensure-Dir $backupRoot }
    Set-ProtectedBackupAcl -Path $backupRoot
    if (-not (Test-ProtectedBackupAcl -Path $backupRoot)) { throw (Get-BackupText "backupReport.invalidAcl" @($backupRoot)) }
    return $backupRoot
}

function Safe-Cim([string]$ClassName) {
    $firstError = ""
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { return @(Get-CimInstance -ClassName $ClassName -OperationTimeoutSec 20 -ErrorAction Stop) }
        return @(Get-WmiObject -Class $ClassName -ErrorAction Stop)
    } catch { $firstError = $_.Exception.Message }
    try { return @(Get-WmiObject -Class $ClassName -ErrorAction Stop) }
    catch {
        Add-BackupScanWarning (Get-BackupText "backupReport.cimFailed" @($ClassName, $firstError, $_.Exception.Message))
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
        if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw (Get-BackupText "backupReport.schtasksMissing") }
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw (Get-BackupText "deepReport.scheduled.invalidCsv") }
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
        if ($records.Count -eq 0) { throw (Get-BackupText "deepReport.scheduled.parseFailed") }
        return $records.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-BackupScanWarning (Get-BackupText "deepReport.scheduled.scanFailed" @($detail))
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
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-BackupText "backupReport.reparseRejected" @($Path)) }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw (Get-BackupText "backupReport.reparseContained" @($Path)) }
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
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=""; ReportPath=""; Message=(Get-BackupText "backupReport.securityAssemblyFailed") })
    exit 11
}

if (-not (Is-Admin)) {
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=""; ReportPath=""; Message=(Get-BackupText "backupReport.adminRequired") })
    exit 20
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$backupDir = ""
try {
    $secureBackupRoot = Get-SecureBackupRoot
    $backupDir = Join-Path $secureBackupRoot ("backup_pre_cleanup_$($env:COMPUTERNAME)_${stamp}_" + [guid]::NewGuid().ToString("N"))
    Ensure-Dir $backupDir
    Set-ProtectedBackupAcl $backupDir
    if (-not (Test-ProtectedBackupAcl $backupDir)) { throw (Get-BackupText "backupReport.newAclInvalid") }
} catch {
    Write-Result ([pscustomobject]@{ Success=$false; ItemCount=0; BackupDirectory=$backupDir; ReportPath=""; Message=(Get-BackupText "backupReport.createRootFailed" @($_.Exception.Message)) })
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
$localizationHelperSha256 = ""
$viCatalogSha256 = ""
$enCatalogSha256 = ""

$hmacKey = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($hmacKey) } finally { $rng.Dispose() }
$protectedKey = [Security.Cryptography.ProtectedData]::Protect($hmacKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
[IO.File]::WriteAllBytes($authPath, $protectedKey)

function Save-Manifest {
    $manifest = [ordered]@{
        SchemaVersion="2.0"
        ToolVersion="4.8"
        BackupMode="PreCleanup"
        BackupScope=$Scope
        ComputerName=$env:COMPUTERNAME
        MachineBinding=(Get-MachineBinding)
        CreatedAt=(Get-Date).ToString("o")
        RestoreScriptSha256=$restoreScriptSha256
        RuntimeHelperSha256=$runtimeHelperSha256
        SafetyPolicySha256=$safetyPolicySha256
        LocalizationHelperSha256=$localizationHelperSha256
        ViCatalogSha256=$viCatalogSha256
        EnCatalogSha256=$enCatalogSha256
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

function Get-InstalledSoftwareBackupInventory {
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($source in @(
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Machine64' },
        [pscustomobject]@{ Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Machine32' },
        [pscustomobject]@{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='CurrentUser' }
    )) {
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) { continue }
        try {
            foreach ($key in @(Get-ChildItem -LiteralPath $source.Path -ErrorAction Stop)) {
                try {
                    $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    if ([string]::IsNullOrWhiteSpace([string]$entry.DisplayName)) { continue }
                    $records.Add([pscustomobject][ordered]@{
                        Name=[string]$entry.DisplayName; Version=[string]$entry.DisplayVersion
                        Publisher=[string]$entry.Publisher; InstallDate=[string]$entry.InstallDate
                        InstallLocation=[string]$entry.InstallLocation; Scope=[string]$source.Scope
                        RegistryKey=[string]$key.Name
                    })
                } catch {}
            }
        } catch { $errors.Add((Get-BackupText "backupReport.error.softwareInventory" @($source.Path, $_.Exception.Message))) }
    }
    return @($records.ToArray() | Group-Object { "$($_.Name)|$($_.Version)|$($_.Scope)" } | ForEach-Object { $_.Group[0] } | Sort-Object Name, Version, Scope)
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
        $actions.Add((Get-BackupText "backupReport.action.registryValues" @($PsPath)))
    } catch { $errors.Add((Get-BackupText "backupReport.error.registryValues" @($PsPath, $_.Exception.Message))) }
}

function Backup-RegistryKey([string]$PsPath, [string]$Label, [string]$Kind, [bool]$Restorable = $true) {
    if (-not (Test-Path -LiteralPath $PsPath)) { return }
    try {
        $nativePath = $PsPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
        $backupPath = Join-Path $backupDir ((($Label -replace '[\\/:*?"<>| ]','_')) + '_' + [guid]::NewGuid().ToString('N') + '.reg')
        $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $output }
        Add-BackupItem (New-FileBackedItem "Registry" $Label $PsPath $backupPath $Kind ([pscustomobject]@{ Restorable=$Restorable }))
        $actions.Add((Get-BackupText "backupReport.action.registry" @($PsPath)))
    } catch { $errors.Add((Get-BackupText "backupReport.error.registry" @($PsPath, $_.Exception.Message))) }
}

Save-Manifest

# Ghi lại toàn bộ danh sách phần mềm trước xử lý. Đây là bằng chứng hậu kiểm,
# không chứa product key/token và không được dùng để phục hồi activator.
if ($includeThirdParty) { try {
    $softwareInventory = @(Get-InstalledSoftwareBackupInventory)
    $softwareInventoryPath = Join-Path $backupDir ("InstalledSoftwareInventory_" + [guid]::NewGuid().ToString('N') + '.json')
    [pscustomobject][ordered]@{
        CreatedAt=(Get-Date).ToString('o'); ComputerName=$env:COMPUTERNAME
        ApplicationCount=[int]$softwareInventory.Count; Applications=$softwareInventory
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $softwareInventoryPath -Encoding UTF8
    Add-BackupItem (New-FileBackedItem "LicenseNotice" (Get-BackupText "backupReport.softwareInventoryName") "InstalledSoftware" $softwareInventoryPath "ThirdPartyInventory" ([pscustomobject]@{ Restorable=$false }))
    $actions.Add((Get-BackupText "backupReport.action.softwareInventory" @($softwareInventory.Count)))
} catch { $errors.Add((Get-BackupText "backupReport.error.softwareInventoryGeneral" @($_.Exception.Message))) } }

# Chỉ lưu các giá trị KMS có thể bị thay đổi; không export toàn bộ SPP hay product key.
$windowsSppPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
$officeSppPath = "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
$windowsPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
if ($includeWindows) {
    Backup-RegistryValues $windowsSppPath (Get-ToolAllowedRegistryValueNames -Path $windowsSppPath) "Windows_SPP_KMS"
    Backup-RegistryValues $windowsPolicyPath (Get-ToolAllowedRegistryValueNames -Path $windowsPolicyPath) "Windows_SPP_Policy"
}
if ($includeOffice) {
    Backup-RegistryValues $officeSppPath (Get-ToolAllowedRegistryValueNames -Path $officeSppPath) "Office_SPP_KMS"
}
$ifeoImageNames = @()
if ($includeWindows) { $ifeoImageNames += @("SppExtComObj.exe", "sppsvc.exe") }
if ($includeOffice) { $ifeoImageNames += "osppsvc.exe" }
foreach ($imageName in @($ifeoImageNames | Select-Object -Unique)) {
    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
    try {
        if ((Get-ItemProperty -LiteralPath $ifeoPath -ErrorAction Stop | Out-String) -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|hook\.dll|sppextcomobj(?:hook|patcher))") {
            Backup-RegistryKey $ifeoPath "IFEO_$imageName" "ActivatorIfeo" $false
        }
    } catch {}
}

if ($includeActivationArtifacts) { foreach ($task in @(Get-CompatibleScheduledTaskRecords | Where-Object {
    $_.TaskName -match $strictPattern -or $_.TaskPath -match $strictPattern -or $_.ActionsText -match $strictPattern
})) {
    try {
        $backupPath = Join-Path $backupDir ("Task_" + ($task.TaskName -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N') + '.xml')
        Export-CompatibleScheduledTask -Record $task -Path $backupPath
        Add-BackupItem (New-FileBackedItem "ScheduledTask" ([string]$task.TaskName) ([string]$task.TaskPath) $backupPath "ActivatorTask" ([pscustomobject]@{ WasEnabled=[bool]$task.WasEnabled; Restorable=$false }))
        $actions.Add((Get-BackupText "backupReport.action.task" @($task.FullName)))
    } catch { $errors.Add((Get-BackupText "backupReport.error.task" @($task.FullName, $_.Exception.Message))) }
} }

if ($includeActivationArtifacts) { foreach ($service in @(Safe-Cim "Win32_Service" | Where-Object {
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
        Add-BackupItem (New-FileBackedItem "Service" ([string]$service.Name) $serviceReg $backupPath "ActivatorService" ([pscustomobject]@{
            DisplayName=[string]$service.DisplayName; PathName=[string]$service.PathName; StartMode=[string]$service.StartMode
            StartName=[string]$service.StartName; Description=[string]$service.Description; WasRunning=[bool]($service.State -eq "Running")
            Dependencies=@($dependencies); SecurityDescriptor=[string]$sddl; Restorable=$false
        }))
        $actions.Add((Get-BackupText "backupReport.action.service" @($service.Name)))
    } catch { $errors.Add((Get-BackupText "backupReport.error.service" @($service.Name, $_.Exception.Message))) }
} }

if ($includeActivationArtifacts) { foreach ($hookPath in @((Get-ToolNativeSystemPath "SppExtComObjHook.dll"), (Join-Path $env:windir "SysWOW64\SppExtComObjHook.dll"))) {
    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) { continue }
    try {
        if (((Get-Item -LiteralPath $hookPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-BackupText "backupReport.reparseRejectedShort") }
        $backupPath = Join-Path $backupDir ((Split-Path $hookPath -Leaf) + '_' + [guid]::NewGuid().ToString('N') + '.backup')
        Copy-Item -LiteralPath $hookPath -Destination $backupPath -Force -ErrorAction Stop
        Add-BackupItem (New-FileBackedItem "File" (Split-Path $hookPath -Leaf) $hookPath $backupPath "ActivatorHook" ([pscustomobject]@{ Restorable=$false }))
        $actions.Add((Get-BackupText "backupReport.action.file" @($hookPath)))
    } catch { $errors.Add((Get-BackupText "backupReport.error.file" @($hookPath, $_.Exception.Message))) }
} }

if ($includeActivationArtifacts) {
$scanRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData, (Join-Path $env:SystemDrive "KMS"), (Join-Path $env:SystemDrive "KMSAuto"), (Join-Path $env:SystemDrive "KMSpico"), (Join-Path $env:SystemDrive "AAct")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
foreach ($root in $scanRoots) {
    try {
        foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $strictPattern })) {
            if (($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $errors.Add((Get-BackupText "backupReport.error.skipReparse" @($folder.FullName))); continue }
            $backupPath = Join-Path $backupDir ("Folder_" + ($folder.Name -replace '[\\/:*?"<>| ]','_') + '_' + [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $folder.FullName -Destination $backupPath -Recurse -Force -ErrorAction Stop
            Add-BackupItem (New-FileBackedItem "Folder" $folder.Name $folder.FullName $backupPath "ActivatorFolder" ([pscustomobject]@{ Restorable=$false }))
            $actions.Add((Get-BackupText "backupReport.action.folder" @($folder.FullName)))
        }
    } catch { $errors.Add((Get-BackupText "backupReport.error.folder" @($root, $_.Exception.Message))) }
}
}

if ($includeActivationArtifacts) { try {
    $preference = Get-MpPreference -ErrorAction Stop
    foreach ($excludedPath in @($preference.ExclusionPath)) {
        if ([string]$excludedPath -match $strictPattern) {
            Add-BackupItem ([pscustomobject]@{ Type="Defender";Name=(Get-BackupText "backupReport.defenderExclusion");OriginalPath=[string]$excludedPath;BackupPath="";BackupSha256="";Kind="ActivatorDefender";Restorable=$false })
            $actions.Add((Get-BackupText "backupReport.action.defender" @($excludedPath)))
        }
    }
} catch { $actions.Add((Get-BackupText "backupReport.defenderUnavailable")) } }

try {
    $restoreSource = Join-Path $PSScriptRoot "windows-license-restore.ps1"
    if (Test-Path -LiteralPath $restoreSource -PathType Leaf) {
        $restoreDestination = Join-Path $backupDir "windows-license-restore.ps1"
        Copy-Item -LiteralPath $restoreSource -Destination $restoreDestination -Force
        $restoreScriptSha256 = Get-Sha256 $restoreDestination
        $runtimeSource = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
        if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) { throw (Get-BackupText "backupReport.restoreDependencyMissing" @("Tool-Runtime.ps1")) }
        $runtimeDestination = Join-Path $backupDir "Tool-Runtime.ps1"
        Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Force
        $runtimeHelperSha256 = Get-Sha256 $runtimeDestination
        $safetyPolicySource = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
        if (-not (Test-Path -LiteralPath $safetyPolicySource -PathType Leaf)) { throw (Get-BackupText "backupReport.restoreDependencyMissing" @("Tool-SafetyPolicy.ps1")) }
        $safetyPolicyDestination = Join-Path $backupDir "Tool-SafetyPolicy.ps1"
        Copy-Item -LiteralPath $safetyPolicySource -Destination $safetyPolicyDestination -Force
        $safetyPolicySha256 = Get-Sha256 $safetyPolicyDestination
        $localizationSource = Join-Path $PSScriptRoot "Tool-Localization.ps1"
        if (-not (Test-Path -LiteralPath $localizationSource -PathType Leaf)) { throw (Get-BackupText "backupReport.restoreDependencyMissing" @("Tool-Localization.ps1")) }
        $localizationDestination = Join-Path $backupDir "Tool-Localization.ps1"
        Copy-Item -LiteralPath $localizationSource -Destination $localizationDestination -Force
        $localizationHelperSha256 = Get-Sha256 $localizationDestination
        $viCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.vi-VN.json"
        $enCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.en-US.json"
        foreach ($catalogSource in @($viCatalogSource, $enCatalogSource)) {
            if (-not (Test-Path -LiteralPath $catalogSource -PathType Leaf)) { throw (Get-BackupText "backupReport.restoreDependencyMissing" @([IO.Path]::GetFileName($catalogSource))) }
            Copy-Item -LiteralPath $catalogSource -Destination (Join-Path $backupDir ([IO.Path]::GetFileName($catalogSource))) -Force
        }
        $viCatalogSha256 = Get-Sha256 (Join-Path $backupDir "Tool-Strings.vi-VN.json")
        $enCatalogSha256 = Get-Sha256 (Join-Path $backupDir "Tool-Strings.en-US.json")
        @(
            '@echo off',
            'set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
            'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
            ('"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-license-restore.ps1" -BackupDir "%~dp0" -Culture "' + $Culture + '"'),
            'pause'
        ) |
            Set-Content -LiteralPath (Join-Path $backupDir "KHOI-PHUC-TU-DONG.cmd") -Encoding ASCII
    }
    @(
        (Get-BackupText "backupReport.restoreGuide.heading" @($releaseVersion)),
        (Get-BackupText "backupReport.restoreGuide.run"),
        (Get-BackupText "backupReport.restoreGuide.scope"),
        (Get-BackupText "backupReport.restoreGuide.validation"),
        (Get-BackupText "backupReport.restoreGuide.defender")
    ) | Set-Content -LiteralPath (Join-Path $backupDir "PHUC-HOI.txt") -Encoding UTF8
} catch { $errors.Add((Get-BackupText "backupReport.restoreBundleFailed" @($_.Exception.Message))) }

foreach ($scanWarning in @($script:BackupScanWarnings)) {
    if (-not $errors.Contains($scanWarning)) { [void]$errors.Add($scanWarning) }
}

Save-Manifest
$backupReport = @(
    (Get-BackupText "backupReport.heading" @($releaseVersion))
    (Get-BackupText "backupReport.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    (Get-BackupText "backupReport.computer" @($env:COMPUTERNAME))
    (Get-BackupText "backupReport.scope" @($Scope))
    (Get-BackupText "backupReport.directory" @($backupDir))
    (Get-BackupText "backupReport.itemCount" @($items.Count))
    (Get-BackupText "backupReport.errorCount" @($errors.Count))
    ""
    (Get-BackupText "backupReport.actionsHeading")
) + $actions.ToArray() + @(
    ""
    (Get-BackupText "backupReport.errorsHeading")
) + $errors.ToArray()
$backupReport | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }

$success = [bool]($errors.Count -eq 0)
Write-Result ([pscustomobject]@{ Success=$success; Scope=$Scope; ItemCount=[int]$items.Count; ErrorCount=[int]$errors.Count; BackupDirectory=$backupDir; ReportPath=$reportPath; Message=if ($success) { Get-BackupText "backupReport.complete" } else { Get-BackupText "backupReport.completeWithWarnings" } })
if ($success) { exit 0 } else { exit 4 }
