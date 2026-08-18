param(
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [string]$DecisionFile = "",
    [ValidateSet("All", "Windows", "Office", "ThirdParty")]
    [string]$Scope = "All",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN"
)

$catalogPath = Join-Path $PSScriptRoot "Tool-Strings.$Culture.json"
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Strings.$Culture.json"; exit 12 }
try { $script:restoreCatalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Host "[localization.catalogInvalid] Tool-Strings.$Culture.json"; exit 12 }
function Get-RestoreText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    $property = $script:restoreCatalog.PSObject.Properties[$Key]
    $text = if ($property) { [string]$property.Value } else { "[$Key]" }
    if ($Arguments -and @($Arguments).Count -gt 0) {
        try { return [string]::Format([Globalization.CultureInfo]::GetCultureInfo($Culture), $text, [object[]]$Arguments) } catch { return $text }
    }
    return $text
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-RestoreText "common.powerShellRequired" @(3)); exit 10 }
$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-RestoreText "common.missingDependency" @("Tool-Runtime.ps1")) }
    if (-not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf)) { throw (Get-RestoreText "common.missingDependency" @("Tool-SafetyPolicy.ps1")) }
    . $runtimeHelper
    . $safetyPolicyHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }
$ErrorActionPreference = "Continue"
$releaseVersion = "4.8.0.1"

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
catch { Fail-Restore 11 (Get-RestoreText "restoreReport.securityAssemblyFailed") }

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
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-RestoreText "restoreReport.reparseRejected" @($Path)) }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw (Get-RestoreText "restoreReport.reparseContained" @($Path)) }
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

function Get-RestoreItemScope($Item) {
    $kind = [string]$Item.Kind
    $name = [string]$Item.Name
    $path = [string]$Item.OriginalPath
    $combined = "$kind|$name|$path"
    if ($kind -match '^ThirdParty' -or $combined -match '(?i)ThirdPartyInventory|InstalledSoftware') { return "ThirdParty" }
    if ($kind -match '^Office' -or $combined -match '(?i)OfficeSoftwareProtectionPlatform|\bospp(?:svc|\.vbs)?\b|Office_SPP') { return "Office" }
    if ($kind -match '^Windows' -or $combined -match '(?i)Windows NT\\CurrentVersion\\SoftwareProtectionPlatform|\bsppsvc\b|SppExtComObj|Windows_SPP|NoGenTicket') { return "Windows" }
    return "WindowsOfficeShared"
}

function Get-RestoreItemsForScope {
    param($Items, [ValidateSet("All", "Windows", "Office", "ThirdParty")][string]$RequestedScope)
    $allItems = @($Items)
    switch ($RequestedScope) {
        "Windows" { return @($allItems | Where-Object { (Get-RestoreItemScope $_) -in @("Windows", "WindowsOfficeShared") }) }
        "Office" { return @($allItems | Where-Object { (Get-RestoreItemScope $_) -in @("Office", "WindowsOfficeShared") }) }
        "ThirdParty" { return @($allItems | Where-Object { (Get-RestoreItemScope $_) -eq "ThirdParty" }) }
        default { return $allItems }
    }
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

if (-not (Is-Admin)) { Fail-Restore 20 (Get-RestoreText "restoreReport.adminRequired") }
try { $script:backupRoot = ([IO.Path]::GetFullPath($BackupDir)).TrimEnd('\') } catch { Fail-Restore 21 (Get-RestoreText "restoreReport.invalidPath") }
if (-not (Test-Path -LiteralPath $script:backupRoot -PathType Container)) { Fail-Restore 21 (Get-RestoreText "restoreReport.directoryMissing") }
$commonData = [Environment]::GetFolderPath("CommonApplicationData")
$currentDataRoot = [string]$env:TOOL_DATA_ROOT
if ([string]::IsNullOrWhiteSpace($currentDataRoot)) { $currentDataRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.6" }
$legacyDataRoot = [string]$env:TOOL_LEGACY_DATA_ROOT
if ([string]::IsNullOrWhiteSpace($legacyDataRoot)) { $legacyDataRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.4" }
$allowedBackupRoots = @($currentDataRoot, $legacyDataRoot) | ForEach-Object {
    try { ([IO.Path]::GetFullPath((Join-Path $_ "backups"))).TrimEnd('\') } catch { $null }
} | Where-Object { $_ } | Select-Object -Unique
$insideAllowedRoot = $false
foreach ($allowedRoot in $allowedBackupRoots) {
    if ($script:backupRoot.StartsWith(($allowedRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) { $insideAllowedRoot = $true; break }
}
if (-not $insideAllowedRoot) { Fail-Restore 23 (Get-RestoreText "restoreReport.outsideProtectedRoot") }
foreach ($protectedPath in @($productRoot, $versionRoot, $expectedBackupRoot, $script:backupRoot)) {
    if (-not (Test-ProtectedBackupAcl $protectedPath)) { Fail-Restore 23 (Get-RestoreText "restoreReport.unsafeAcl") }
}

$manifestPath = Join-Path $script:backupRoot "RESTORE-MANIFEST.json"
$hmacPath = Join-Path $script:backupRoot "RESTORE-MANIFEST.hmac"
$authPath = Join-Path $script:backupRoot "RESTORE-AUTH.bin"
foreach ($required in @($manifestPath, $hmacPath, $authPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { Fail-Restore 21 (Get-RestoreText "restoreReport.authComponentMissing") }
    if (((Get-Item -LiteralPath $required -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail-Restore 23 (Get-RestoreText "restoreReport.authComponentReparse") }
}

try {
    $protectedKey = [IO.File]::ReadAllBytes($authPath)
    $hmacKey = [Security.Cryptography.ProtectedData]::Unprotect($protectedKey, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $expectedHmac = ([IO.File]::ReadAllText($hmacPath)).Trim().ToUpperInvariant()
    if ($expectedHmac -notmatch '^[0-9A-F]{64}$') { throw (Get-RestoreText "restoreReport.hmacInvalid") }
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$hmacKey)
    try { $actualHmac = ([BitConverter]::ToString($hmac.ComputeHash([IO.File]::ReadAllBytes($manifestPath))) -replace '-', '').ToUpperInvariant() }
    finally { $hmac.Dispose() }
    if ($actualHmac -ne $expectedHmac) { throw (Get-RestoreText "restoreReport.hmacMismatch") }
    if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }
} catch { Fail-Restore 24 (Get-RestoreText "restoreReport.manifestAuthFailed" @($_.Exception.Message)) }

try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { Fail-Restore 22 (Get-RestoreText "restoreReport.manifestInvalid" @($_.Exception.Message)) }
if ([string]$manifest.SchemaVersion -ne "2.0" -or [string]$manifest.ToolVersion -notin @("4.6", "4.7", "4.8")) { Fail-Restore 25 (Get-RestoreText "restoreReport.manifestVersionUnsupported") }
if ([string]$manifest.ComputerName -ne $env:COMPUTERNAME -or [string]$manifest.MachineBinding -ne (Get-MachineBinding)) { Fail-Restore 26 (Get-RestoreText "restoreReport.wrongDevice") }
$allManifestItems = @($manifest.Items)
if ($allManifestItems.Count -eq 0 -or $allManifestItems.Count -gt 5000) { Fail-Restore 27 (Get-RestoreText "restoreReport.itemCountInvalid") }
$manifestItems = @(Get-RestoreItemsForScope -Items $allManifestItems -RequestedScope $Scope)
if ($manifestItems.Count -eq 0) { Fail-Restore 27 (Get-RestoreText "restoreReport.scopeNoItems" @($Scope)) }

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::Equals(([IO.Path]::GetFullPath($scriptDirectory)).TrimEnd('\'), $script:backupRoot, [StringComparison]::OrdinalIgnoreCase)) {
    if ([string]$manifest.RestoreScriptSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-Sha256 $MyInvocation.MyCommand.Path) -ne ([string]$manifest.RestoreScriptSha256).ToUpperInvariant()) {
        Fail-Restore 28 (Get-RestoreText "restoreReport.integrity.restoreScript")
    }
    if ([string]$manifest.RuntimeHelperSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf) -or
        (Get-Sha256 $runtimeHelper) -ne ([string]$manifest.RuntimeHelperSha256).ToUpperInvariant()) {
        Fail-Restore 28 (Get-RestoreText "restoreReport.integrity.runtime")
    }
    if ([string]$manifest.SafetyPolicySha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $safetyPolicyHelper -PathType Leaf) -or
        (Get-Sha256 $safetyPolicyHelper) -ne ([string]$manifest.SafetyPolicySha256).ToUpperInvariant()) {
        Fail-Restore 28 (Get-RestoreText "restoreReport.integrity.safetyPolicy")
    }
    $localizationHelper = Join-Path $scriptDirectory "Tool-Localization.ps1"
    if ([string]$manifest.LocalizationHelperSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $localizationHelper -PathType Leaf) -or
        (Get-Sha256 $localizationHelper) -ne ([string]$manifest.LocalizationHelperSha256).ToUpperInvariant()) {
        Fail-Restore 28 (Get-RestoreText "restoreReport.integrity.localization")
    }
    $viCatalogPath = Join-Path $scriptDirectory "Tool-Strings.vi-VN.json"
    $enCatalogPath = Join-Path $scriptDirectory "Tool-Strings.en-US.json"
    if ([string]$manifest.ViCatalogSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $viCatalogPath -PathType Leaf) -or
        (Get-Sha256 $viCatalogPath) -ne ([string]$manifest.ViCatalogSha256).ToUpperInvariant() -or
        [string]$manifest.EnCatalogSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
        -not (Test-Path -LiteralPath $enCatalogPath -PathType Leaf) -or
        (Get-Sha256 $enCatalogPath) -ne ([string]$manifest.EnCatalogSha256).ToUpperInvariant()) {
        Fail-Restore 28 (Get-RestoreText "restoreReport.integrity.catalogs")
    }
}

# Tiền kiểm toàn bộ trước khi thực hiện bất kỳ thay đổi nào.
$allowedTypes = @("RegistryValues", "Registry", "ScheduledTask", "Service", "File", "Folder", "Defender", "LicenseNotice", "FirewallNotice")
$resolvedPaths = @{}
foreach ($item in $manifestItems) {
    if ($allowedTypes -notcontains [string]$item.Type) { Fail-Restore 29 (Get-RestoreText "restoreReport.unsupportedItem" @($item.Type)) }
    if (-not [string]::IsNullOrWhiteSpace([string]$item.BackupPath)) {
        $source = Resolve-BackupPath ([string]$item.BackupPath)
        if (-not $source -or -not (Test-Path -LiteralPath $source)) { Fail-Restore 30 (Get-RestoreText "restoreReport.dataMissing" @($item.Type, $item.Name)) }
        if ([string]$item.BackupSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-PathHash $source) -ne ([string]$item.BackupSha256).ToUpperInvariant()) {
            Fail-Restore 31 (Get-RestoreText "restoreReport.dataHashMismatch" @($item.Name))
        }
        $resolvedPaths[[string]$item.BackupPath] = $source
    } elseif ([string]$item.Type -notin @("Defender", "LicenseNotice", "FirewallNotice")) {
        Fail-Restore 32 (Get-RestoreText "restoreReport.dataPathMissing" @($item.Type, $item.Name))
    }
}

$actions = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]
$restored = 0
$skipped = 0
$reportPath = Join-Path $script:backupRoot ("restore_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + ".txt")
$registryValueRestorePolicy = @(Get-ToolRegistryValueRestorePolicy)

foreach ($item in $manifestItems) {
    try {
        $source = if ([string]$item.BackupPath) { [string]$resolvedPaths[[string]$item.BackupPath] } else { "" }
        if ($item.PSObject.Properties['Restorable'] -and -not [bool]$item.Restorable) {
            $actions.Add((Get-RestoreText "restoreReport.action.nonRestorableSkipped" @($item.Name, $item.Kind))); $skipped++; continue
        }
        switch ([string]$item.Type) {
            "RegistryValues" {
                $allowedNamesForPath = @(Get-ToolAllowedRegistryValueNames -Path ([string]$item.OriginalPath))
                if ($allowedNamesForPath.Count -eq 0) { throw (Get-RestoreText "restoreReport.registryValuesOutsideScope") }
                $data = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
                if ([string]$data.RegistryPath -ne [string]$item.OriginalPath) { throw (Get-RestoreText "restoreReport.registryValuesPathMismatch") }
                $key = Get-Item -LiteralPath ([string]$item.OriginalPath) -ErrorAction Stop
                foreach ($entry in @($data.Values)) {
                    if (-not (Test-ToolRegistryValueRestoreAllowed -Path ([string]$item.OriginalPath) -ValueName ([string]$entry.Name))) { throw (Get-RestoreText "restoreReport.registryValueOutsideScope" @($entry.Name)) }
                    $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$entry.Kind, $true))
                    $value = $entry.Value
                    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $value = [Convert]::FromBase64String([string]$value) }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $value = [int]$value }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord) { $value = [long]$value }
                    elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $value = [string[]]@($value) }
                    else { $value = [string]$value }
                    $key.SetValue([string]$entry.Name, $value, $kind)
                }
                $actions.Add((Get-RestoreText "restoreReport.action.registryValues" @($item.Name))); $restored++
            }
            "Registry" {
                $nativePath = ([string]$item.OriginalPath) -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                $allowed = $nativePath -like 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\*'
                if (-not $allowed -or -not (Test-RegFileScope $source $nativePath)) { throw (Get-RestoreText "restoreReport.registryOutsideScope") }
                $output = (& $nativeRegPath import $source 2>&1) -join " | "; if ($LASTEXITCODE -ne 0) { throw $output }
                $actions.Add((Get-RestoreText "restoreReport.action.registry" @($item.Name))); $restored++
            }
            "ScheduledTask" {
                $taskName = [string]$item.Name; $taskPath = [string]$item.OriginalPath
                if ([string]::IsNullOrWhiteSpace($taskName) -or -not $taskPath.StartsWith('\') -or $taskPath.Contains('..')) { throw (Get-RestoreText "restoreReport.taskInvalid") }
                if (Test-CompatibleScheduledTask -TaskName $taskName -TaskPath $taskPath) { $actions.Add((Get-RestoreText "restoreReport.action.taskExists" @($taskPath + $taskName))); $skipped++; break }
                Register-CompatibleScheduledTask -TaskName $taskName -TaskPath $taskPath -XmlPath $source -WasEnabled ([bool]$item.WasEnabled)
                $actions.Add((Get-RestoreText "restoreReport.action.task" @($taskPath + $taskName))); $restored++
            }
            "Service" {
                $serviceName = [string]$item.Name
                if ($serviceName -notmatch '^[A-Za-z0-9_.-]{1,256}$') { throw (Get-RestoreText "restoreReport.serviceNameInvalid") }
                $nativePath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$serviceName"
                if (-not (Test-RegFileScope $source $nativePath)) { throw (Get-RestoreText "restoreReport.serviceRegistryOutsideScope") }
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
                if ([string]$item.StartName -and ([string]$item.StartName -notmatch '^(LocalSystem|NT AUTHORITY\\(LocalService|NetworkService))$')) { $actions.Add((Get-RestoreText "restoreReport.action.serviceCredential" @($serviceName))) }
                $actions.Add((Get-RestoreText "restoreReport.action.service" @($serviceName))); $restored++
            }
            { $_ -in @("File", "Folder") } {
                $destination = [string]$item.OriginalPath
                if (-not [IO.Path]::IsPathRooted($destination)) { throw (Get-RestoreText "restoreReport.destinationNotAbsolute") }
                if (Test-Path -LiteralPath $destination) { $actions.Add((Get-RestoreText "restoreReport.action.destinationExists" @($destination))); $skipped++; break }
                $parent = Split-Path -Parent $destination; if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $source -Destination $destination -Recurse:([string]$item.Type -eq "Folder") -Force -ErrorAction Stop
                $actions.Add((Get-RestoreText "restoreReport.action.path" @($item.Type, $destination))); $restored++
            }
            "Defender" {
                $actions.Add((Get-RestoreText "restoreReport.action.defenderSkipped" @($item.OriginalPath))); $skipped++
            }
            "LicenseNotice" {
                $actions.Add((Get-RestoreText "restoreReport.action.licenseSkipped" @($item.Name))); $skipped++
            }
        }
    } catch {
        $message = Get-RestoreText "restoreReport.action.error" @($item.Type, $item.Name, $_.Exception.Message)
        $errors.Add($message); $actions.Add($message)
    }
}

$restoreGuidance = if ($errors.Count -gt 0) {
    @(
        (Get-RestoreText "restoreReport.guidance.error.stop")
        (Get-RestoreText "restoreReport.guidance.error.validation")
        (Get-RestoreText "restoreReport.guidance.error.retry")
    )
} else {
    @(
        (Get-RestoreText "restoreReport.guidance.success.rescan")
        (Get-RestoreText "restoreReport.guidance.success.license")
    )
}
$restoreReport = @(
    (Get-RestoreText "restoreReport.heading" @($releaseVersion))
    (Get-RestoreText "restoreReport.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    (Get-RestoreText "restoreReport.directory" @($script:backupRoot))
    (Get-RestoreText "restoreReport.scope" @($Scope))
    (Get-RestoreText "restoreReport.restored" @($restored))
    (Get-RestoreText "restoreReport.skipped" @($skipped))
    (Get-RestoreText "restoreReport.errors" @($errors.Count))
    ""
    (Get-RestoreText "restoreReport.detailsHeading")
) + $actions.ToArray() + @(
    ""
    (Get-RestoreText "restoreReport.guidanceHeading")
) + $restoreGuidance
$restoreReport | Set-Content -LiteralPath $reportPath -Encoding UTF8
$success = [bool]($errors.Count -eq 0)
Write-ResultFile ([pscustomobject]@{ Success=$success; Scope=$Scope; RestoredCount=[int]$restored; SkippedCount=[int]$skipped; ErrorCount=[int]$errors.Count; ReportPath=$reportPath; Message=if ($success) { Get-RestoreText "restoreReport.complete" } else { Get-RestoreText "restoreReport.completeWithErrors" } })
if ($success) { exit 0 } else { exit 4 }
