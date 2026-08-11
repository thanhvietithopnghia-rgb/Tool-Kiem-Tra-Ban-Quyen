param(
    [string]$OutputDir = "",
    [string[]]$ApprovedKmsServers = @(),
    [string]$ApprovedKmsServerFile = "",
    [switch]$TreatUnapprovedKmsAsNonCompliant,
    [switch]$Remediate,
    [switch]$DeepClean,
    [switch]$DryRun,
    [switch]$NoRestorePoint,
    [switch]$RedactSensitive,
    [string]$DecisionFile = "",
    [string]$SelectionFile = "",
    [ValidateSet("All", "WindowsOffice", "ThirdParty")]
    [string]$ScanScope = "All",
    [switch]$SkipDeepSoftwareScan,
    [ValidateRange(15, 900)][int]$DeepSoftwareScanTimeoutSeconds = 180,
    [ValidateRange(20, 10000)][int]$DeepSoftwareScanMaximumSignatureChecks = 1400,
    [ValidateRange(20, 10000)][int]$DeepSoftwareScanMaximumHashChecks = 1000,
    [switch]$RepairScanSources,
    [switch]$BridgeEnvironmentProbe,
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN"
)

if ($BridgeEnvironmentProbe) {
    $bridgeInvocationId = [guid]::Empty
    $bridgeContextValid = $env:TOOL_SECURE_LAUNCH -eq '1' -and
        -not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR) -and
        [string]$env:TOOL_MODULE_ID -eq 'cleanup.scan' -and
        [guid]::TryParse([string]$env:TOOL_MODULE_INVOCATION_ID, [ref]$bridgeInvocationId) -and
        $bridgeInvocationId -ne [guid]::Empty
    if ($bridgeContextValid) { exit 0 }
    exit 23
}

if ($DryRun) {
    $Remediate = $true
    $DeepClean = $true
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$safetyPolicyHelper = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
$scanOptimizationHelper = Join-Path $PSScriptRoot "Tool-ScanOptimization.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$softwareInventoryHelper = Join-Path $PSScriptRoot "Tool-SoftwareInventory.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-CleanupText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-CleanupText "report.bootstrap.powerShellRequired"); exit 10 }
try {
    foreach ($requiredPath in @($runtimeHelper, $reportSchemaHelper, $safetyPolicyHelper, $scanOptimizationHelper, $softwareInventoryHelper)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @([IO.Path]::GetFileName($requiredPath))) }
    }
    . $runtimeHelper
    . $reportSchemaHelper
    . $safetyPolicyHelper
    . $scanOptimizationHelper
    . $softwareInventoryHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $nativeScPath = Get-ToolNativeSystemPath "sc.exe"
    $nativeRegPath = Get-ToolNativeSystemPath "reg.exe"
    $nativeCertutilPath = Get-ToolNativeSystemPath "certutil.exe"
    $nativeSfcPath = Get-ToolNativeSystemPath "sfc.exe"
    $nativeMsiExecPath = Get-ToolNativeSystemPath "msiexec.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "Continue"
$releaseVersion = "4.8.0.0"
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra" }
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }
$script:StrictActivatorPattern = "(?i)(kmspico|kmsauto|auto[\s._-]*kms|autokms|kms[\s._-]*vl(?:[\s._-]*all)?|kms-r|aact(?:portable)?|sppextcomobj(?:patcher|hook)|spp[\s._-]*(?:hook|patcher)|microsoft[\s_-]+toolkit|hwidgen|\bmassgrave\b|mas[\s._-]*aio|tsforge|ohook)"
$script:ThirdPartyAdobeActivatorPattern = "(?i)(\badobe[\s._-]*genp\b|\bccmaker\b|\bamtlib[\s._-]*(?:patch|emulator)\b|\badobe.{0,24}\b(?:patcher|activator|crack)\b|\b(?:patcher|activator|crack).{0,24}\badobe\b)"
$script:ThirdPartyAutodeskActivatorPattern = "(?i)(\bxf[\s._-]*adsk\b|\bx[\s._-]*force.{0,20}\b(?:autodesk|adsk)\b|\b(?:autodesk|adsk).{0,24}\b(?:license[\s._-]*patch|patcher|activator|crack)\b|\b(?:patcher|activator|crack).{0,24}\b(?:autodesk|adsk)\b)"
try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
catch { Write-Host (Get-CleanupText "backupReport.securityAssemblyFailed"); exit 11 }
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
    if (Get-Command Reset-ToolSoftwareInventoryCaches -ErrorAction SilentlyContinue) { Reset-ToolSoftwareInventoryCaches }
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
            $text = [regex]::Replace($text, $pattern, (Get-CleanupText "report.redaction.value"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    foreach ($hostName in @($script:SensitiveKmsHosts | Sort-Object Length -Descending -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$hostName)) {
            $text = [regex]::Replace($text, [regex]::Escape([string]$hostName), (Get-CleanupText "cleanupReport.redaction.kms"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $ipv4Part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$ipv4Part(?:\.$ipv4Part){3}(?![0-9.])", (Get-CleanupText "report.redaction.ip"))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-CleanupText "report.redaction.mac"))
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

function Test-ProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowCurrentUserForUserScope
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        $allowedOwners = @("S-1-5-32-544", "S-1-5-18")
        $allowedWriters = @("S-1-5-32-544", "S-1-5-18")
        if ($AllowCurrentUserForUserScope -and [string]$env:TOOL_DATA_SCOPE -ne 'Machine') {
            $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            if (-not [string]::IsNullOrWhiteSpace($currentUserSid)) {
                $allowedOwners += $currentUserSid
                $allowedWriters += $currentUserSid
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
        if ([string]::IsNullOrWhiteSpace($commonData)) { throw (Get-CleanupText "backupReport.programDataUnknown") }
        $versionRoot = Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.6"
    }
    $versionRoot = [IO.Path]::GetFullPath($versionRoot)
    $productRoot = Split-Path -Parent $versionRoot
    $backupRoot = Join-Path $versionRoot "backups"
    foreach ($path in @($productRoot, $versionRoot, $backupRoot)) {
        if (Test-Path -LiteralPath $path) {
            $existing = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "backupReport.invalidRoot" @($path)) }
        } else { Ensure-Dir $path }
        Set-ProtectedBackupAcl $path
        if (-not (Test-ProtectedDirectoryAcl $path)) { throw (Get-CleanupText "backupReport.invalidAcl" @($path)) }
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
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "restoreReport.reparseRejected" @($Path)) }
    if (-not $rootItem.PSIsContainer) { return Get-Sha256 $Path }
    $root = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $lines = New-Object System.Collections.Generic.List[string]
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
    if (@($children | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { throw (Get-CleanupText "cleanupReport.reparseContained" @($Path)) }
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
            $result = @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -OperationTimeoutSec 20 -ErrorAction Stop)
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
        if (-not (Test-Path -LiteralPath $schtasks -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.scan.schtasksMissing") }
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw (Get-CleanupText "cleanupReport.scan.schtasksCsvInvalid") }
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
        if ($records.Count -eq 0) { throw (Get-CleanupText "cleanupReport.scan.schtasksNameInvalid") }
        $result = @($records.ToArray())
        if (-not $NoCache) { $script:ScheduledTaskRecordsCache = @($result) }
        return $result
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-ScanWarning (Get-CleanupText "cleanupReport.scan.tasksFailed" @($detail))
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
        Write-Warning (Get-CleanupText "cleanupReport.kms.fileReadWarning" @($_.Exception.Message))
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
        } catch { [void]$invalid.Add((Get-CleanupText "cleanupReport.kms.fileReadFailed" @($_.Exception.Message))) }
    }
    $warning = if (-not $exists -or $valid.Count -eq 0) {
        Get-CleanupText "cleanupReport.kms.emptyWarning"
    } elseif ($invalid.Count -gt 0) {
        Get-CleanupText "cleanupReport.kms.invalidWarning" @($invalid.Count)
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
            if ([string]::IsNullOrWhiteSpace($summary)) { $summary = Get-CleanupText "cleanupReport.command.noOutput" }
        } else {
            if ($errorLine) { $summary = Get-CleanupText "cleanupReport.command.failed" @($errorLine) }
            elseif ($isHelpOutput) { $summary = Get-CleanupText "cleanupReport.command.slmgrArgumentsInvalid" }
            else { $summary = Get-CleanupText "cleanupReport.command.slmgrExitCode" @($exitCode) }
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
            Summary = Get-CleanupText "cleanupReport.command.failed" @($_.Exception.Message)
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
        $keyMatch = [regex]::Match($block, '(?im)^\s*(?:Last 5 characters of installed product key|5 .{0,24} cu.i[^:]*)\s*:\s*(?<Value>[A-Z0-9]{5})\s*$')
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
            LicenseStatus = if ($statusMatch.Success) { $statusMatch.Groups['Value'].Value.Trim(' ', '-') } else { Get-CleanupText "common.unknown" }
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
            Add-ScanWarning (Get-CleanupText "cleanupReport.scan.officeStatusFailed" @($ospp))
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
        0 { Get-CleanupText "cleanupReport.status.unlicensed" }
        1 { Get-CleanupText "cleanupReport.status.licensed" }
        2 { Get-CleanupText "cleanupReport.status.oobGrace" }
        3 { Get-CleanupText "cleanupReport.status.ootGrace" }
        4 { Get-CleanupText "cleanupReport.status.nonGenuineGrace" }
        5 { Get-CleanupText "cleanupReport.status.notification" }
        6 { Get-CleanupText "cleanupReport.status.extendedGrace" }
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
    return (Get-CleanupText "common.unknown")
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
            @(Get-CimInstance -ClassName SoftwareLicensingProduct -OperationTimeoutSec 25 -ErrorAction Stop)
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
            $script:WindowsLicenseSourceNote = Get-CleanupText "cleanupReport.scan.partialKeyMissingContinue"
            return $windowsProductsWithoutKey
        }

        $queryError = Get-CleanupText "cleanupReport.scan.partialKeyMissing"
    } catch { $queryError = $_.Exception.Message }

    $fallback = @(Get-WindowsLicenseProductsFromSlmgr)
    if ($fallback.Count -gt 0) { return $fallback }
    if ($querySucceeded -and $windowsProductsAny.Count -gt 0) {
        $script:WindowsLicenseSourceNote = Get-CleanupText "cleanupReport.scan.noReadableKey"
        return @()
    }
    if ($querySucceeded -and $allProducts.Count -gt 0 -and $windowsProductsAny.Count -eq 0) {
        $queryError = Get-CleanupText "cleanupReport.scan.noWindowsProduct"
    }
    Add-ScanWarning (Get-CleanupText "cleanupReport.scan.windowsLicenseFailed" @($queryError))
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
                Action = Get-CleanupText "cleanupReport.candidate.disableTask"
            })
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.scan.tasksEvaluateFailed" @($_.Exception.Message)) }

    try {
        Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical") | Where-Object {
            $_.Name -match $regex -or $_.DisplayName -match $regex -or $_.PathName -match $regex
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Service"
                Name = $_.Name
                Location = $_.PathName
                Action = Get-CleanupText "cleanupReport.candidate.stopDisableService"
            })
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.scan.servicesEvaluateFailed" @($_.Exception.Message)) }

    try {
        Get-Process | Where-Object {
            $_.ProcessName -match $regex -or $_.Path -match $regex
        } | ForEach-Object {
            $findings.Add([pscustomobject]@{
                Type = "Process"
                Name = $_.ProcessName
                Location = $_.Path
                Action = Get-CleanupText "cleanupReport.candidate.stopProcess"
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
                        Action = Get-CleanupText "cleanupReport.candidate.reviewFolder"
                    })
                }
        } catch {}
    }

    return $findings
}

function Invoke-CleanupNativeCommandWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [ValidateRange(5, 300)][int]$TimeoutSeconds = 120
    )

    $quotedArguments = @($Arguments | ForEach-Object {
        $argument = [string]$_
        if ($argument -match '[\s"]') { '"' + ($argument -replace '"', '\"') + '"' } else { $argument }
    }) -join ' '
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $quotedArguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw (Get-CleanupText "cleanupReport.native.startFailed" @([IO.Path]::GetFileName($FilePath))) }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit([int]($TimeoutSeconds * 1000))
        if (-not $completed) {
            try { $process.Kill() } catch {}
            try { [void]$process.WaitForExit(3000) } catch {}
        }
        $output = (($stdoutTask.GetAwaiter().GetResult() + " | " + $stderrTask.GetAwaiter().GetResult()) -replace "`0", "").Trim(' ', '|')
        return [pscustomobject]@{
            Completed = [bool]$completed
            TimedOut = [bool](-not $completed)
            ExitCode = if ($completed) { [int]$process.ExitCode } else { -1 }
            Output = $output
        }
    } finally {
        $process.Dispose()
    }
}

function Get-ThirdPartyVendorScope {
    param([string]$Name, [string]$Publisher)
    $text = (([string]$Name) + " " + ([string]$Publisher)).Trim()
    if ($text -match '(?i)\bAdobe\b|\bAcrobat\b|\bPhotoshop\b|\bIllustrator\b|\bInDesign\b|\bLightroom\b|\bPremiere\b|\bAfter Effects\b') { return "Adobe" }
    if ($text -match '(?i)\bAutodesk\b|\bAutoCAD\b|\bRevit\b|\b3ds Max\b|\bCivil 3D\b|\bNavisworks\b|\bInventor\b|\bFusion 360\b') { return "Autodesk" }
    return "Other"
}

function Get-ThirdPartyEvidenceScope {
    param([string]$Text)
    if ([string]$Text -match $script:ThirdPartyAdobeActivatorPattern) { return "Adobe" }
    if ([string]$Text -match $script:ThirdPartyAutodeskActivatorPattern) { return "Autodesk" }
    return ""
}

function ConvertTo-ToolRegistryPath {
    param([string]$NativeRegistryPath)
    if ([string]::IsNullOrWhiteSpace($NativeRegistryPath)) { return "" }
    if ($NativeRegistryPath.StartsWith('HKEY_LOCAL_MACHINE\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKLM:\' + $NativeRegistryPath.Substring('HKEY_LOCAL_MACHINE\'.Length)
    }
    if ($NativeRegistryPath.StartsWith('HKEY_CURRENT_USER\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'HKCU:\' + $NativeRegistryPath.Substring('HKEY_CURRENT_USER\'.Length)
    }
    return $NativeRegistryPath
}

function Get-InstalledSoftwareInventory {
    try {
        return @(Get-ToolInstalledSoftwareInventory -IncludeAppx -IncludeShortcuts -IncludePortable -PortableMaximumResults 220)
    } catch {
        Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.inventorySourceFailed" @('AllSoftwareSources', $_.Exception.Message))
        return @()
    }
}

function Get-ThirdPartyAssessmentStatusLabel {
    param([string]$StatusCode)
    $key = switch ($StatusCode) {
        'FreeOrIncluded' { 'cleanupReport.thirdParty.status.freeOrIncluded' }
        'GenuineVerified' { 'cleanupReport.thirdParty.status.genuineVerified' }
        'Unactivated' { 'cleanupReport.thirdParty.status.unactivated' }
        'NonGenuine' { 'cleanupReport.thirdParty.status.nonGenuine' }
        'IntegrityCompromised' { 'cleanupReport.thirdParty.status.integrityCompromised' }
        'Suspicious' { 'cleanupReport.thirdParty.status.suspicious' }
        'TrialOrUnverified' { 'cleanupReport.thirdParty.status.trialOrUnverified' }
        default { 'cleanupReport.thirdParty.status.unverified' }
    }
    return Get-CleanupText $key
}

function Get-ThirdPartyCorrelationTokens {
    param([string]$Text)
    $ignored = @('software','application','applications','program','professional','enterprise','edition','desktop','studio','editor','viewer','reader','update','helper','service','services','windows','microsoft','corporation','company','limited','inc','ltd','the','and','for','with','x64','x86','bit')
    return @(([regex]::Split(([string]$Text).ToLowerInvariant(), '[^a-z0-9]+') |
        Where-Object { $_.Length -ge 4 -and $_ -notmatch '^\d+$' -and $ignored -notcontains $_ } |
        Sort-Object Length -Descending -Unique | Select-Object -First 8))
}

function Get-ThirdPartyEvidenceTargets {
    param([string]$Text, $ApplicationRecords, [string]$SpecificVendorScope = '')
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($record in @($ApplicationRecords)) {
        $matched = $false
        if ($SpecificVendorScope -and [string]$record.VendorScope -eq $SpecificVendorScope) { $matched=$true }
        if (-not $matched -and $record.InstallRoot -and $Text.IndexOf([string]$record.InstallRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched=$true }
        if (-not $matched -and $record.RepresentativePath -and $Text.IndexOf([string]$record.RepresentativePath, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched=$true }
        if (-not $matched) {
            foreach ($token in @($record.Tokens)) {
                if ($Text -match ('(?i)(?<![a-z0-9])' + [regex]::Escape([string]$token) + '(?![a-z0-9])')) { $matched=$true; break }
            }
        }
        if ($matched -and -not $targets.Contains($record)) { $targets.Add($record) }
    }
    return $targets.ToArray()
}

function Get-ThirdPartyStrongEvidence {
    param($Applications, [AllowNull()][object]$Catalog)
    $evidence = New-Object System.Collections.Generic.List[object]
    $applicationRecords = New-Object System.Collections.Generic.List[object]
    foreach ($app in @($Applications | Where-Object { -not [bool]$_.IsMicrosoft })) {
        $catalogProduct = Find-ToolSoftwareCatalogProduct -Application $app -Catalog $Catalog
        $vendorScope = Get-ToolSoftwareVendorScope -Application $app -CatalogProduct $catalogProduct
        $applicationRecords.Add([pscustomobject][ordered]@{
            Application=$app; ApplicationId=[string]$app.Id; VendorScope=$vendorScope
            InstallRoot=(Get-ThirdPartyNormalizedInstallRoot -Application $app)
            RepresentativePath=[string]$app.RepresentativePath
            Tokens=@(Get-ThirdPartyCorrelationTokens (([string]$app.Name) + ' ' + ([string]$app.Publisher)))
        })
    }
    $addEvidence = {
        param([string]$Type,[string]$Name,[string]$Location,[string]$RegistryPath,[string]$Detail,[string]$SpecificScope,[bool]$KnownSpecific,[bool]$Active,[bool]$FolderOnly,$Targets)
        $resolvedTargets = @($Targets)
        if ($resolvedTargets.Count -eq 0) {
            $evidence.Add([pscustomobject][ordered]@{
                Code=('Uncorrelated' + $Type); Type=$Type; Source=$Type; Name=$Name; Location=$Location; RegistryPath=$RegistryPath
                VendorScope='Uncorrelated'; ApplicationId=''; Strength=$(if ($KnownSpecific) {'Strong'} else {'Moderate'})
                EvidenceGroup=$(if ($Active) {'ActivatorPersistence'} else {'ActivatorArtifact'}); Decisive=$false; Detail=$Detail
            })
            return
        }
        foreach ($target in $resolvedTargets) {
            $decisive = [bool](-not $FolderOnly -and $KnownSpecific -and $Active)
            $strength = if ($decisive) { 'Strong' } else { 'Moderate' }
            $evidence.Add([pscustomobject][ordered]@{
                Code=$(if ($KnownSpecific) {'KnownActivator' + $Type} else {'SuspiciousActivator' + $Type})
                Type=$Type; Source=$Type; Name=$Name; Location=$Location; RegistryPath=$RegistryPath
                VendorScope=[string]$target.VendorScope; ApplicationId=[string]$target.ApplicationId; Strength=$strength
                EvidenceGroup=$(if ($Active) {'ActivatorPersistence'} else {'ActivatorArtifact'}); Decisive=$decisive; Detail=$Detail
            })
        }
    }

    foreach ($record in @($applicationRecords.ToArray())) {
        $app = $record.Application
        $text = (([string]$app.Name) + ' ' + ([string]$app.Publisher) + ' ' + ([string]$app.InstallLocation))
        $specificScope = Get-ThirdPartyEvidenceScope $text
        $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
        $generic = [bool]($knownSpecific -or $text -match $script:ToolSoftwareSuspiciousArtifactPattern)
        if (-not $generic) { continue }
        $targets = if ($specificScope) { @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope) } else { @($record) }
        & $addEvidence 'InstalledActivator' ([string]$app.Name) ([string]$app.InstallLocation) ([string]$app.RegistryPath) `
            (Get-CleanupText "cleanupReport.thirdParty.evidence.installedActivator") $specificScope $knownSpecific $true $false $targets
    }

    try {
        foreach ($task in @(Get-CompatibleScheduledTaskRecords)) {
            $text = (([string]$task.FullName) + ' ' + ([string]$task.ActionsText))
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            & $addEvidence 'ScheduledTask' ([string]$task.FullName) ([string]$task.ActionsText) '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.task") $specificScope $knownSpecific $true $false $targets
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.tasksFailed" @($_.Exception.Message)) }

    try {
        foreach ($service in @(Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical"))) {
            $text = (([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName))
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            & $addEvidence 'Service' ([string]$service.Name) ([string]$service.PathName) '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.service") $specificScope $knownSpecific $true $false $targets
        }
    } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.servicesFailed" @($_.Exception.Message)) }

    try {
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
            $processPath = ''
            try { $processPath = [string]$process.Path } catch {}
            $text = (([string]$process.ProcessName) + ' ' + $processPath)
            $specificScope = Get-ThirdPartyEvidenceScope $text
            $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
            if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
            $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
            & $addEvidence 'Process' ([string]$process.ProcessName) $processPath '' `
                (Get-CleanupText "cleanupReport.thirdParty.evidence.process") $specificScope $knownSpecific $true $false $targets
        }
    } catch {}

    $scanRoots = @($env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($root in $scanRoots) {
        try {
            $levelOne = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 800)
            $bounded = New-Object System.Collections.Generic.List[object]
            foreach ($directory in $levelOne) { $bounded.Add($directory) }
            foreach ($directory in $levelOne) {
                try { foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 200)) { $bounded.Add($child) } } catch {}
                if ($bounded.Count -ge 3000) { break }
            }
            foreach ($directory in @($bounded.ToArray() | Select-Object -First 3000)) {
                $text = [string]$directory.FullName
                $specificScope = Get-ThirdPartyEvidenceScope $text
                $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
                if (-not $knownSpecific -and $text -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
                $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
                & $addEvidence 'Folder' ([string]$directory.Name) $text '' `
                    (Get-CleanupText "cleanupReport.thirdParty.evidence.folder") $specificScope $knownSpecific $false $true $targets
            }
        } catch {}
    }

    if (Get-Command Find-ToolPatternFilesParallel -ErrorAction SilentlyContinue) {
        $artifactRoots = New-Object System.Collections.Generic.List[string]
        foreach ($root in @($env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, $env:TMP,
            [Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))) {
            if ($root -and (Test-Path -LiteralPath $root -PathType Container) -and -not $artifactRoots.Contains([string]$root)) { $artifactRoots.Add([string]$root) }
        }
        try {
            $usersRoot = Join-Path $env:SystemDrive 'Users'
            foreach ($userDirectory in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 40)) {
                foreach ($relative in @('AppData\Local','AppData\Roaming','Downloads','Desktop')) {
                    $candidate = Join-Path $userDirectory.FullName $relative
                    if (Test-Path -LiteralPath $candidate -PathType Container -ErrorAction SilentlyContinue) { $artifactRoots.Add($candidate) }
                }
            }
        } catch {}
        $knownPattern = $script:ToolSoftwareKnownActivatorPattern -replace '^\(\?i\)', ''
        $suspiciousPattern = $script:ToolSoftwareSuspiciousArtifactPattern -replace '^\(\?i\)', ''
        $artifactPattern = '(?i)(?:' + $knownPattern + ')|(?:' + $suspiciousPattern + ')'
        try {
            foreach ($path in @(Find-ToolPatternFilesParallel -Roots @($artifactRoots.ToArray() | Select-Object -Unique | Select-Object -First 24) -Pattern $artifactPattern `
                -MaximumResults 240 -ThrottleLimit 4 -MaximumDepth 4 -PerRootTimeoutSeconds 5)) {
                $text = [string]$path
                if (([IO.Path]::GetExtension($text)).ToLowerInvariant() -notin @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi','.zip','.rar','.7z','.jar')) { continue }
                $specificScope = Get-ThirdPartyEvidenceScope $text
                $knownSpecific = [bool]($specificScope -or $text -match $script:ToolSoftwareKnownActivatorPattern)
                $targets = @(Get-ThirdPartyEvidenceTargets -Text $text -ApplicationRecords $applicationRecords.ToArray() -SpecificVendorScope $specificScope)
                & $addEvidence 'FileArtifact' ([IO.Path]::GetFileName($text)) $text '' `
                    (Get-CleanupText "cleanupReport.thirdParty.evidence.folder") $specificScope $knownSpecific $false $true $targets
            }
        } catch { Add-ScanWarning (Get-CleanupText "cleanupReport.thirdParty.inventorySourceFailed" @('DeepArtifactSearch', $_.Exception.Message)) }
    }

    return @($evidence.ToArray() |
        Group-Object { "$($_.Code)|$($_.Type)|$($_.Name)|$($_.Location)|$($_.VendorScope)|$($_.ApplicationId)" } |
        ForEach-Object { $_.Group[0] } |
        Sort-Object VendorScope, ApplicationId, Type, Name)
}

function Get-ThirdPartyLicenseStatePaths {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Adobe','Autodesk','WinRAR')][string]$RemediationAdapter,
        $Applications = @()
    )
    $paths = New-Object System.Collections.Generic.List[object]
    $candidates = @()
    if ($RemediationAdapter -eq 'Adobe') {
        $candidates = @(
            (Join-Path $env:ProgramData 'Adobe\SLStore'),
            (Join-Path $env:ProgramData 'Adobe\SLCache'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Common Files\Adobe\Adobe PCD\cache\cache.db' }),
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Adobe\OOBE\opm.db' }),
            $(if ($env:APPDATA) { Join-Path $env:APPDATA 'Adobe\OOBE\opm.db' })
        ) | Where-Object { $_ }
    } elseif ($RemediationAdapter -eq 'Autodesk') {
        $candidates = @(
            (Join-Path $env:ProgramData 'Autodesk\CLM\LGS'),
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Autodesk\Web Services\LoginState.xml' })
        ) | Where-Object { $_ }
        $flexRoot = Join-Path $env:ProgramData 'FLEXnet'
        if (Test-Path -LiteralPath $flexRoot -PathType Container) {
            $candidates += @(Get-ChildItem -LiteralPath $flexRoot -File -Filter 'adskflex_*_tsf.data*' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    } else {
        foreach ($application in @($Applications)) {
            $root = Get-ThirdPartyNormalizedInstallRoot -Application $application
            if ($root) { $candidates += (Join-Path $root 'rarreg.key') }
        }
        if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'WinRAR\rarreg.key') }
        if ($env:ProgramData) { $candidates += (Join-Path $env:ProgramData 'WinRAR\rarreg.key') }
    }
    foreach ($path in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { continue }
        $paths.Add([pscustomobject][ordered]@{
            Type=$(if ($item.PSIsContainer) { 'Folder' } else { 'File' })
            Kind='ThirdPartyLicenseState'; Name=[string]$item.Name; Location=[string]$item.FullName
            Detail=(Get-CleanupText "cleanupReport.thirdParty.plan.licenseState" @($RemediationAdapter)); Restorable=$false
        })
    }
    return $paths.ToArray()
}

function Get-ThirdPartyRemediationPlan {
    param([string]$RemediationAdapter, [string]$EvidenceScope, $Evidence, $Applications = @())
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Evidence | Where-Object { [string]$_.VendorScope -eq $EvidenceScope })) {
        switch ([string]$item.Type) {
            'InstalledActivator' {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.RegistryPath)) {
                    $plan.Add([pscustomobject][ordered]@{ Type='Registry'; Kind='ThirdPartyUninstallEntry'; Name=[string]$item.Name; Location=[string]$item.RegistryPath; Detail=[string]$item.Detail; Restorable=$false })
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$item.Location) -and (Test-Path -LiteralPath ([string]$item.Location) -PathType Container)) {
                    $plan.Add([pscustomobject][ordered]@{ Type='Folder'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false })
                }
            }
            'ScheduledTask' { $plan.Add([pscustomobject][ordered]@{ Type='ScheduledTask'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'Service' { $plan.Add([pscustomobject][ordered]@{ Type='Service'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'Process' { $plan.Add([pscustomobject][ordered]@{ Type='Process'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'Folder' { $plan.Add([pscustomobject][ordered]@{ Type='Folder'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location; Detail=[string]$item.Detail; Restorable=$false }) }
            'FileArtifact' {
                if (Test-ThirdPartyArtifactPath -Path ([string]$item.Location) -Applications $Applications -AllowUserArtifactRoots) {
                    $plan.Add([pscustomobject][ordered]@{
                        Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[string]$item.Name; Location=[string]$item.Location
                        Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
                    })
                }
            }
        }
    }
    # Vendor adapters reset shared licensing state, but the same applications
    # can also carry exact hosts/firewall/file residue discovered by the
    # per-application assessment. Include only those tightly scoped supporting
    # actions so the post-check does not rediscover residue left beside a
    # successful Adobe/Autodesk reset.
    foreach ($supportingItem in @(Get-ThirdPartyGenericRemediationPlan -Applications $Applications | Where-Object {
        [string]$_.Type -in @('File','Hosts','Firewall')
    })) { $plan.Add($supportingItem) }
    foreach ($statePath in @(Get-ThirdPartyLicenseStatePaths -RemediationAdapter $RemediationAdapter -Applications $Applications)) { $plan.Add($statePath) }
    return @($plan.ToArray() |
        Group-Object { "$($_.Type)|$($_.Kind)|$($_.Name)|$($_.Location)" } |
        ForEach-Object { $_.Group[0] })
}

function Get-ThirdPartyNormalizedInstallRoot {
    param($Application)
    foreach ($candidate in @([string]$Application.InstallLocation, $(if ($Application.RepresentativePath) { Split-Path -Parent ([string]$Application.RepresentativePath) }))) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
            $root = ([IO.Path]::GetPathRoot($full)).TrimEnd('\')
            if ([string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $isBroadRoot = $false
            foreach ($broadCandidate in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
                    [Environment]::GetFolderPath('UserProfile'), $env:LOCALAPPDATA, $env:APPDATA)) {
                if ([string]::IsNullOrWhiteSpace([string]$broadCandidate)) { continue }
                $broadRoot = ([IO.Path]::GetFullPath([string]$broadCandidate)).TrimEnd('\')
                if ([string]::Equals($full, $broadRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    $isBroadRoot = $true
                    break
                }
            }
            if (-not $isBroadRoot -and $full.Length -ge 8) { return $full }
        } catch {}
    }
    return ''
}

function Get-ThirdPartyMsiProductCode {
    param($Applications)
    $productCodePattern = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
    foreach ($application in @($Applications | Sort-Object @{Expression={ if ([string]$_.SourceKind -eq 'Registry') { 0 } else { 1 } }})) {
        $uninstall = [string]$application.UninstallString
        $registryPath = [string]$application.RegistryPath
        $isRegisteredMsi = [bool](
            $uninstall -match '(?i)^\s*"?(?:[^"\\]+\\)?msiexec(?:\.exe)?"?\s+/(?:i|x)\s*\{[0-9a-f-]{36}\}' -or
            $registryPath -match '(?i)\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\{[0-9a-f-]{36}\}$'
        )
        if (-not $isRegisteredMsi) { continue }
        foreach ($source in @($uninstall, $registryPath)) {
            $match = [regex]::Match([string]$source, $productCodePattern)
            if ($match.Success) { return $match.Value.ToUpperInvariant() }
        }
    }
    return ''
}

function Test-ThirdPartyArtifactPath {
    param([string]$Path, $Applications, [switch]$AllowUserArtifactRoots)
    $allowedExtensions = @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi','.zip','.rar','.7z','.jar')
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $allowedExtensions -notcontains ([IO.Path]::GetExtension($Path)).ToLowerInvariant()) { return $false }
    $artifactName = [IO.Path]::GetFileName($Path)
    $nameMatched = [bool]($artifactName -match '(?i)(crack(?:ed)?|keygen|activator|activation[._ -]*(?:bypass|patch(?:er)?)|licen[cs]e[._ -]*(?:bypass|patch(?:er)?)|serial[._ -]*generator|genp|ccmaker|xf[._ -]*adsk|x[._ -]*force|amtlib[._ -]*(?:patch|emulator)|kms(?:pico|auto|[._ -]*vl)|massgrave|mas[._ -]*aio|tsforge|ohook|microsoft[._ -]+toolkit)')
    $knownPatternVariable = Get-Variable -Name ToolSoftwareKnownActivatorPattern -Scope Script -ErrorAction SilentlyContinue
    $suspiciousPatternVariable = Get-Variable -Name ToolSoftwareSuspiciousArtifactPattern -Scope Script -ErrorAction SilentlyContinue
    if ($knownPatternVariable -and [string]$knownPatternVariable.Value -and $artifactName -match [string]$knownPatternVariable.Value) { $nameMatched = $true }
    if ($suspiciousPatternVariable -and [string]$suspiciousPatternVariable.Value -and $artifactName -match [string]$suspiciousPatternVariable.Value) { $nameMatched = $true }
    if (-not $nameMatched) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }

    $backupRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_DATA_ROOT)) {
        Join-Path ([string]$env:TOOL_DATA_ROOT) 'backups'
    } else {
        $commonData = [Environment]::GetFolderPath('CommonApplicationData')
        if ($commonData) { Join-Path $commonData 'ThanhViet-Tool-Kiem-Tra\v4.6\backups' } else { '' }
    }
    if ($backupRoot) {
        try {
            $backupPrefix = ([IO.Path]::GetFullPath($backupRoot)).TrimEnd('\') + '\'
            if ($fullPath.StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        } catch {}
    }
    foreach ($application in @($Applications)) {
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $application
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $prefix = $root.TrimEnd('\') + '\'
        if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($AllowUserArtifactRoots) {
        $userArtifactRoots = @(
            $env:TEMP, $env:TMP, $env:LOCALAPPDATA, $env:APPDATA,
            [Environment]::GetFolderPath('Desktop'),
            $(if ([Environment]::GetFolderPath('UserProfile')) { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' })
        ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($root in $userArtifactRoots) {
            try {
                $prefix = ([IO.Path]::GetFullPath([string]$root)).TrimEnd('\') + '\'
                if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch {}
        }
        try {
            $usersRoot = (Join-Path $env:SystemDrive 'Users').TrimEnd('\') + '\'
            if ($fullPath.StartsWith($usersRoot, [StringComparison]::OrdinalIgnoreCase) -and
                $fullPath -match '(?i)\\Users\\[^\\]+\\(?:Downloads|Desktop|AppData\\Local|AppData\\Roaming)\\') { return $true }
        } catch {}
    }
    return $false
}

function Test-ThirdPartyApplicationPathScope {
    param([string]$Path, $Applications)
    if ([string]::IsNullOrWhiteSpace($Path) -or ([IO.Path]::GetExtension($Path)).ToLowerInvariant() -notin @('.exe','.com')) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }
    foreach ($application in @($Applications)) {
        $representativePath = [string]$application.RepresentativePath
        if ($representativePath) {
            try {
                if ([string]::Equals($fullPath, [IO.Path]::GetFullPath($representativePath), [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch {}
        }
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $application
        if ($root -and $fullPath.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ThirdPartyHostsUpdate {
    param([string[]]$Lines, [string[]]$Targets)
    $targetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($target in @($Targets)) {
        $normalized = ([string]$target).Trim().TrimEnd('.')
        if ($normalized -match '^[A-Za-z0-9.-]{1,253}$') { [void]$targetSet.Add($normalized) }
    }
    $updatedLines = New-Object System.Collections.Generic.List[string]
    $removedCount = 0
    foreach ($line in @($Lines)) {
        $commentIndex = ([string]$line).IndexOf('#')
        $comment = if ($commentIndex -ge 0) { ([string]$line).Substring($commentIndex) } else { '' }
        $mappings = @(Get-ToolSoftwareHostsLineMappings -Line ([string]$line))
        if ($mappings.Count -eq 0) {
            $updatedLines.Add([string]$line)
            continue
        }
        $rebuiltMappings = New-Object System.Collections.Generic.List[string]
        $lineRemovedCount = 0
        foreach ($mapping in $mappings) {
            $kept = New-Object System.Collections.Generic.List[string]
            foreach ($name in @($mapping.Targets)) {
                if ($targetSet.Contains(([string]$name).TrimEnd('.'))) {
                    $lineRemovedCount++
                } else {
                    $kept.Add([string]$name)
                }
            }
            if ($kept.Count -gt 0) { $rebuiltMappings.Add(([string]$mapping.Address + "`t" + ($kept.ToArray() -join ' '))) }
        }
        if ($lineRemovedCount -eq 0) {
            $updatedLines.Add([string]$line)
            continue
        }
        $removedCount += $lineRemovedCount
        if ($rebuiltMappings.Count -gt 0) {
            for ($mappingIndex = 0; $mappingIndex -lt $rebuiltMappings.Count; $mappingIndex++) {
                $rebuilt = [string]$rebuiltMappings[$mappingIndex]
                if ($comment -and $mappingIndex -eq ($rebuiltMappings.Count - 1)) { $rebuilt += ' ' + $comment }
                $updatedLines.Add($rebuilt)
            }
        } elseif ($comment) {
            $updatedLines.Add([string]$comment)
        }
    }
    return [pscustomobject][ordered]@{
        Lines=$updatedLines.ToArray(); RemovedCount=[int]$removedCount; TargetCount=[int]$targetSet.Count
    }
}

function Get-ThirdPartyGenericRemediationPlan {
    param($Applications)
    $plan = New-Object System.Collections.Generic.List[object]
    $allEvidence = @($Applications | ForEach-Object { @($_.Evidence) } |
        Group-Object { "$($_.Code)|$($_.Source)|$($_.Detail)" } | ForEach-Object { $_.Group[0] })

    foreach ($item in $allEvidence) {
        $code = [string]$item.Code
        $detail = [string]$item.Detail
        if ($code -in @('UnauthorizedArtifactName','KnownActivatorArtifact','SuspiciousArtifactName','KnownActivatorFileArtifact','SuspiciousActivatorFileArtifact') -and
            (Test-ThirdPartyArtifactPath -Path $detail -Applications $Applications -AllowUserArtifactRoots)) {
            $plan.Add([pscustomobject][ordered]@{
                Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=[IO.Path]::GetFileName($detail)
                Location=$detail; Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
            })
        } elseif ($code -eq 'LicenseDomainBlocked' -and $detail -match '^[A-Za-z0-9.-]{1,253}$') {
            $plan.Add([pscustomobject][ordered]@{
                Type='Hosts'; Kind='ThirdPartyHostsEntry'; Name=$detail; Location=$detail
                Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.restoreHosts'); Restorable=$true
            })
        } elseif ($code -eq 'ApplicationOutboundBlocked' -and $detail -match '^(.+?)\s+\|\s+(.+)$') {
            $ruleName = ([string]$matches[1]).Trim()
            $applicationPath = ([string]$matches[2]).Trim()
            if ($ruleName.Length -le 256 -and (Test-ThirdPartyApplicationPathScope -Path $applicationPath -Applications $Applications)) {
                $plan.Add([pscustomobject][ordered]@{
                    Type='Firewall'; Kind='ThirdPartyFirewallBlock'; Name=$ruleName; Location=$applicationPath
                    Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.removeFirewallBlock'); Restorable=$false
                })
            }
        }
    }

    $productCode = Get-ThirdPartyMsiProductCode -Applications $Applications
    $hasUnauthorizedDistribution = [bool](@($allEvidence | Where-Object { [string]$_.Code -in @('KnownUnauthorizedName','CatalogUnauthorizedName') }).Count -gt 0)
    $hasTamperedBinary = [bool](@($allEvidence | Where-Object { [string]$_.Code -in @('SignatureHashMismatch','DeepSignatureHashMismatch','KnownBadFileHash','PaidBinaryNotSigned','ExpectedSignedFileNotSigned','UnexpectedCoreFileSigner') }).Count -gt 0)
    $displayName = @($Applications | Sort-Object @{Expression={ if ([string]$_.SourceKind -eq 'Registry') { 0 } else { 1 } }} | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Select-Object -First 1)
    if ($displayName.Count -eq 0) { $displayName = @((Get-CleanupText 'common.unknown')) }
    if ($productCode) {
        if ($hasUnauthorizedDistribution) {
            $plan.Add([pscustomobject][ordered]@{
                Type='Uninstall'; Kind='ThirdPartyMsiUninstall'; Name=[string]$displayName[0]; Location=$productCode
                Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.uninstallRepack'); Restorable=$false
            })
        } elseif ($hasTamperedBinary) {
            $plan.Add([pscustomobject][ordered]@{
                Type='Repair'; Kind='ThirdPartyMsiRepair'; Name=[string]$displayName[0]; Location=$productCode
                Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.msiRepair'); Restorable=$false
            })
        }
    }

    $officialUrl = @($Applications | ForEach-Object { [string]$_.OfficialReferenceUrl } | Where-Object { $_ } | Select-Object -First 1)
    $plan.Add([pscustomobject][ordered]@{
        Type='Guidance'; Kind='ThirdPartyOfficialSource'; Name=[string]$displayName[0]
        Location=$(if ($officialUrl.Count -gt 0) { [string]$officialUrl[0] } else { '' })
        Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.officialSource'); Restorable=$false
    })
    return @($plan.ToArray() |
        Group-Object { "$($_.Type)|$($_.Kind)|$($_.Name)|$($_.Location)" } |
        ForEach-Object { $_.Group[0] })
}

function Get-ThirdPartyLicenseCandidates {
    param($Applications, $Evidence)
    $candidates = New-Object System.Collections.Generic.List[object]
    $adapterDefinitions = @(
        [pscustomobject]@{ Adapter='Adobe'; EvidenceScope='Adobe'; Mode='VendorSharedReset' },
        [pscustomobject]@{ Adapter='Autodesk'; EvidenceScope='Autodesk'; Mode='VendorSharedReset' },
        [pscustomobject]@{ Adapter='WinRAR'; EvidenceScope='RARLAB'; Mode='LocalLicenseFileReset' }
    )
    foreach ($adapterDefinition in $adapterDefinitions) {
        $adapter = [string]$adapterDefinition.Adapter
        $vendorScope = [string]$adapterDefinition.EvidenceScope
        $vendorApps = @($Applications | Where-Object {
            [string]$_.RemediationAdapter -eq $adapter -and [bool]$_.CleanupFinding -and [bool]$_.ManualEligible
        })
        $vendorEvidence = @($Evidence | Where-Object { [string]$_.VendorScope -eq $vendorScope })
        if ($vendorApps.Count -eq 0) { continue }
        $plan = @(Get-ThirdPartyRemediationPlan -RemediationAdapter $adapter -EvidenceScope $vendorScope -Evidence $vendorEvidence -Applications $vendorApps)
        if ($plan.Count -eq 0) { continue }
        $licenseStateCount = @($plan | Where-Object { [string]$_.Kind -eq 'ThirdPartyLicenseState' }).Count
        $manualOnlyPlanCount = @($plan | Where-Object { [string]$_.Type -in @('Firewall','Uninstall') }).Count
        $applicationNames = @($vendorApps | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $familyName = if ($adapter -in @('Adobe','Autodesk')) {
            Get-CleanupText ("cleanupReport.thirdParty.family." + $adapter.ToLowerInvariant())
        } else {
            [string]($applicationNames | Select-Object -First 1)
        }
        $strongEvidenceCount = [int](($vendorApps | Measure-Object -Property StrongEvidenceCount -Sum).Sum)
        $manualOnlyCount = [int]@($vendorApps | Where-Object { -not [bool]$_.AutoEligible }).Count
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $familyName `
            -Location ($applicationNames -join '; ') -TargetId $adapter `
            -Detail (Get-CleanupText "cleanupReport.thirdParty.candidateDetailExtended" @($vendorApps.Count, $strongEvidenceCount, $manualOnlyCount, $licenseStateCount)) `
            -DefaultSelected $false -VendorScope $vendorScope -AutoEligible:([bool]($licenseStateCount -gt 0 -and $manualOnlyPlanCount -eq 0 -and @($vendorApps | Where-Object { [bool]$_.AutoEligible }).Count -gt 0)) `
            -ApplicationNames $applicationNames -ApplicationIds @($vendorApps | ForEach-Object { [string]$_.Id }) `
            -Evidence $vendorEvidence -PlanItems $plan -RemediationMode ([string]$adapterDefinition.Mode)
        $candidates.Add($candidate)
    }

    $genericApplications = @($Applications | Where-Object {
        [bool]$_.ManualEligible -and [string]$_.RemediationAdapter -notin @('Adobe','Autodesk','WinRAR')
    })
    $genericGroups = @($genericApplications | Group-Object {
        $root = Get-ThirdPartyNormalizedInstallRoot -Application $_
        if ($root) { return (([string]$_.VendorScope) + '|' + $root).ToLowerInvariant() }
        return (([string]$_.VendorScope) + '|' + ([string]$_.Id)).ToLowerInvariant()
    })
    foreach ($group in $genericGroups) {
        $groupApplications = @($group.Group)
        $plan = @(Get-ThirdPartyGenericRemediationPlan -Applications $groupApplications)
        $applicationNames = @($groupApplications | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Sort-Object -Unique)
        $applicationIds = @($groupApplications | ForEach-Object { [string]$_.Id } | Where-Object { $_ } | Select-Object -Unique)
        $allEvidence = @($groupApplications | ForEach-Object { @($_.Evidence) } |
            Group-Object { "$($_.Code)|$($_.Source)|$($_.Detail)" } | ForEach-Object { $_.Group[0] })
        $strongEvidenceCount = [int]@($allEvidence | Where-Object { [string]$_.Strength -in @('Conclusive','Strong') }).Count
        $decisiveEvidenceCount = [int]@($allEvidence | Where-Object {
            if ($_.PSObject.Properties['Decisive']) { return [bool]$_.Decisive -or [string]$_.Strength -eq 'Conclusive' }
            return [bool]([string]$_.Strength -eq 'Conclusive' -or
                [string]$_.Code -in @('SignatureHashMismatch','DeepSignatureHashMismatch','KnownBadFileHash','KnownActivatorArtifact'))
        }).Count
        $hasRepair = [bool](@($plan | Where-Object { [string]$_.Type -eq 'Repair' }).Count -gt 0)
        $hasUninstall = [bool](@($plan | Where-Object { [string]$_.Type -eq 'Uninstall' }).Count -gt 0)
        $hasFirewallChange = [bool](@($plan | Where-Object { [string]$_.Type -eq 'Firewall' }).Count -gt 0)
        $hasSafeAutomaticAction = [bool](@($plan | Where-Object { [string]$_.Type -in @('File','Hosts','Repair') }).Count -gt 0)
        $mode = if ($hasUninstall) { 'ManualOfficialReinstall' } elseif ($hasRepair) { 'AutomaticOfficialRepair' } elseif ($hasSafeAutomaticAction) { 'ArtifactCleanup' } else { 'GuidedOfficialRepair' }
        $displayName = if ($applicationNames.Count -le 1) { [string]$applicationNames[0] } else { ([string]$applicationNames[0] + ' (+' + ($applicationNames.Count - 1) + ')') }
        $location = @($groupApplications | ForEach-Object { Get-ThirdPartyNormalizedInstallRoot -Application $_ } | Where-Object { $_ } | Select-Object -First 1)
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $displayName `
            -Location $(if ($location.Count -gt 0) { [string]$location[0] } else { $applicationNames -join '; ' }) `
            -TargetId $(if ($applicationIds.Count -gt 0) { [string]$applicationIds[0] } else { [guid]::NewGuid().ToString('N') }) `
            -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateDetailGeneric' @($applicationNames.Count, $strongEvidenceCount, @($plan).Count, $mode)) `
            -DefaultSelected $false -VendorScope ([string]$groupApplications[0].VendorScope) `
            -AutoEligible:([bool]($decisiveEvidenceCount -gt 0 -and $hasSafeAutomaticAction -and -not $hasUninstall -and -not $hasFirewallChange)) `
            -ApplicationNames $applicationNames -ApplicationIds $applicationIds -Evidence $allEvidence -PlanItems $plan -RemediationMode $mode
        $candidates.Add($candidate)
    }

    # Tệp activator trong Downloads/Desktop/TEMP có thể không tương quan được
    # với một ứng dụng đã cài. Trước đây chúng xuất hiện trong kết quả quét
    # nhưng không có candidate, nên người dùng không thể chọn cách ly và lần
    # quét sau luôn thấy lại. Chỉ tạo candidate thủ công cho đúng một tệp đã
    # qua kiểm tra tên, phần mở rộng, đường dẫn chuẩn và vùng người dùng.
    $standaloneArtifactGroups = @($Evidence | Where-Object {
        [string]$_.Type -eq 'FileArtifact' -and
        [string]::IsNullOrWhiteSpace([string]$_.ApplicationId) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Location)
    } | Group-Object { ([string]$_.Location).ToLowerInvariant() })
    foreach ($artifactGroup in $standaloneArtifactGroups) {
        $artifactEvidence = @($artifactGroup.Group)[0]
        $artifactPath = [string]$artifactEvidence.Location
        if (-not (Test-ThirdPartyArtifactPath -Path $artifactPath -Applications $Applications -AllowUserArtifactRoots)) { continue }
        $artifactName = [IO.Path]::GetFileName($artifactPath)
        $planItem = [pscustomobject][ordered]@{
            Type='File'; Kind='ThirdPartyUnauthorizedArtifact'; Name=$artifactName; Location=$artifactPath
            Detail=(Get-CleanupText 'cleanupReport.thirdParty.plan.quarantineArtifact'); Restorable=$false
        }
        $candidate = New-CleanupItem -Type 'Application' -Kind 'ThirdPartyLicenseReset' -Name $artifactName `
            -Location $artifactPath -TargetId $artifactPath `
            -Detail (Get-CleanupText 'cleanupReport.thirdParty.candidateDetailStandalone' @($artifactName)) `
            -DefaultSelected $false -VendorScope 'Uncorrelated' -AutoEligible:$false `
            -ApplicationNames @($artifactName) -ApplicationIds @() -Evidence @($artifactGroup.Group) `
            -PlanItems @($planItem) -RemediationMode 'ArtifactCleanup'
        $candidates.Add($candidate)
    }
    return $candidates.ToArray()
}

function Connect-ThirdPartyApplicationsToCandidates {
    param($Applications, $Candidates)
    foreach ($application in @($Applications)) {
        $applicationId = [string]$application.Id
        $candidate = @($Candidates | Where-Object { @($_.ApplicationIds) -contains $applicationId } | Select-Object -First 1)
        $application.TechnicalStatus = Get-ThirdPartyAssessmentStatusLabel -StatusCode ([string]$application.AssessmentCode)
        $hasExecutablePlan = [bool]($candidate.Count -gt 0 -and @($candidate[0].PlanItems | Where-Object { [string]$_.Type -ne 'Guidance' }).Count -gt 0)
        $supported = [bool]($candidate.Count -gt 0 -and [bool]$application.ManualEligible -and $hasExecutablePlan)
        $assessmentAutoEligible = [bool]$application.AutoEligible
        $application.RemediationSupported = $supported
        $application | Add-Member -NotePropertyName AssessmentAutoEligible -NotePropertyValue $assessmentAutoEligible -Force
        $application.AutoEligible = [bool]($candidate.Count -gt 0 -and [bool]$candidate[0].AutoEligible)
        $application | Add-Member -NotePropertyName CleanupCandidateId -NotePropertyValue $(if ($candidate.Count -gt 0) { [string]$candidate[0].Id } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupRemediationMode -NotePropertyValue $(if ($candidate.Count -gt 0) { [string]$candidate[0].RemediationMode } else { '' }) -Force
        $application | Add-Member -NotePropertyName CleanupGuidanceOnly -NotePropertyValue ([bool]($candidate.Count -gt 0 -and -not $hasExecutablePlan)) -Force
    }
}

function New-CleanupItem {
    param(
        [string]$Type,
        [string]$Kind,
        [string]$Name,
        [string]$Location,
        [string]$Detail,
        [string]$TargetId = "",
        [bool]$DefaultSelected = $false,
        [string]$VendorScope = "",
        [bool]$AutoEligible = $false,
        [string[]]$ApplicationNames = @(),
        [string[]]$ApplicationIds = @(),
        $Evidence = @(),
        $PlanItems = @(),
        [string]$RemediationMode = ''
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
        VendorScope = $VendorScope
        AutoEligible = $AutoEligible
        ApplicationNames = @($ApplicationNames)
        ApplicationIds = @($ApplicationIds)
        Evidence = @($Evidence)
        PlanItems = @($PlanItems)
        RemediationMode = $RemediationMode
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
                    -Name (Get-CleanupText "cleanupReport.candidate.unapprovedKms") -Location $path `
                    -Detail (Get-CleanupText "cleanupReport.candidate.unapprovedKmsDetail" @($server))))
            }
        } catch {}
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            $items.Add((New-CleanupItem -Type "Registry" -Kind "SppNoGenTicketPolicy" `
                -Name "Policy SPP NoGenTicket=1" -Location $policyPath `
                -Detail (Get-CleanupText "cleanupReport.candidate.noGenTicketDetail")))
        }
    } catch {}

    foreach ($imageName in @("SppExtComObj.exe", "sppsvc.exe", "osppsvc.exe")) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$imageName"
        try {
            $valueText = (Get-ItemProperty -LiteralPath $path -ErrorAction Stop | Out-String)
            if ($valueText -match "(?i)(\bdebugger\b|\bverifierdlls\b|kms|activator|hook\.dll|sppextcomobj(?:hook|patcher))") {
                $items.Add((New-CleanupItem -Type "Registry" -Kind "IfeoHook" `
                    -Name "IFEO hook: $imageName" -Location $path `
                    -Detail (Get-CleanupText "cleanupReport.candidate.ifeoDetail")))
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
                -Detail (Get-CleanupText "cleanupReport.candidate.hookFileDetail")))
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if ([string]$excludedPath -match $script:StrictActivatorPattern) {
                $items.Add((New-CleanupItem -Type "Defender" -Kind "ExclusionPath" `
                    -Name (Get-CleanupText "cleanupReport.candidate.defenderExclusion") -Location ([string]$excludedPath) `
                    -Detail (Get-CleanupText "cleanupReport.candidate.defenderExclusionDetail")))
            }
        }
    } catch {}

    return @($items | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
}

function Get-AllCleanupCandidates {
    param($Products, $Findings, $OfficeEntries, $ThirdPartyCandidates = @())

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-DeepCleanupCandidates -Findings $Findings)) { $items.Add($item) }

    foreach ($product in @($Products | Where-Object {
        (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
    })) {
        $items.Add((New-CleanupItem -Type "License" -Kind "WindowsKmsLicense" `
            -Name ([string]$product.Name) `
            -Location ("KMS=" + [string]$product.KeyManagementServiceMachine + "; PartialKey=" + [string]$product.PartialProductKey) `
            -TargetId ([string]$product.ID) `
            -Detail (Get-CleanupText "cleanupReport.candidate.windowsKmsDetail")))
    }

    $unapprovedOfficeEntries = @($OfficeEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
    foreach ($entry in $unapprovedOfficeEntries) {
        $last5Label = if ([string]::IsNullOrWhiteSpace([string]$entry.Last5)) { Get-CleanupText "cleanupReport.value.noKey" } else { [string]$entry.Last5 }
        $serverLabel = if ([string]::IsNullOrWhiteSpace([string]$entry.Server)) { Get-CleanupText "cleanupReport.value.dnsNoOverride" } else { [string]$entry.Server }
        $targetId = if (-not [string]::IsNullOrWhiteSpace([string]$entry.SkuId)) { [string]$entry.SkuId } else { "$($entry.Path)|$($entry.Last5)" }
        $items.Add((New-CleanupItem -Type "License" -Kind "OfficeKmsLicense" `
            -Name ("Office KMS $last5Label - " + [string]$entry.LicenseName) `
            -Location ([string]$entry.Path) `
            -TargetId $targetId `
            -Detail (Get-CleanupText "cleanupReport.candidate.officeKmsDetail" @([string]$entry.SkuId, [string]$entry.LicenseStatus, $serverLabel))))
    }

    foreach ($thirdPartyCandidate in @($ThirdPartyCandidates)) { $items.Add($thirdPartyCandidate) }

    return @($items.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object Type, Name, Location)
}

function Get-ScopedCleanupCandidates {
    param(
        $CleanupItems,
        [ValidateSet("All", "WindowsOffice", "ThirdParty")][string]$Scope = "All"
    )

    $items = @($CleanupItems)
    switch ($Scope) {
        "WindowsOffice" {
            return @($items | Where-Object {
                [string]$_.Type -ne "Application" -and [string]$_.Kind -notmatch '^ThirdParty'
            })
        }
        "ThirdParty" {
            return @($items | Where-Object {
                [string]$_.Type -eq "Application" -and [string]$_.Kind -eq "ThirdPartyLicenseReset"
            })
        }
        default { return $items }
    }
}

function Test-CleanupScopeReady {
    param(
        $Verification,
        [ValidateSet("All", "WindowsOffice", "ThirdParty")][string]$Scope = "All"
    )

    if ([int]$Verification.ScanWarningCount -gt 0) { return $false }
    switch ($Scope) {
        "WindowsOffice" {
            return [bool](
                [int]$Verification.ActiveActivatorFindingCount -eq 0 -and
                [int]$Verification.ConfigurationResidueCount -eq 0 -and
                [int]$Verification.UnapprovedWindowsKmsCount -eq 0 -and
                [int]$Verification.UnapprovedOfficeKmsCount -eq 0
            )
        }
        "ThirdParty" {
            $findingCount = if ($Verification.PSObject.Properties['ThirdPartyRemediationFindingCount']) {
                [int]$Verification.ThirdPartyRemediationFindingCount
            } else {
                [int]$Verification.ThirdPartyCandidateCount
            }
            return [bool]($findingCount -eq 0)
        }
        default { return [bool]$Verification.ReadyForOfficialActivation }
    }
}

function Add-ThirdPartyVerification {
    param($Verification, $ThirdPartyCandidates, $ThirdPartyApplications = @())
    $candidateCount = [int]@($ThirdPartyCandidates).Count
    $autoEligibleCount = [int]@($ThirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count
    $reviewCount = [int]@($ThirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    $applicationFindingCount = [int]@($ThirdPartyApplications | Where-Object {
        if ($_.PSObject.Properties['CleanupFinding']) { return [bool]$_.CleanupFinding }
        return [bool]([string]$_.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised'))
    }).Count
    $standaloneFindingCount = [int]@($ThirdPartyCandidates | Where-Object {
        @($_.ApplicationIds).Count -eq 0 -and @($_.PlanItems | Where-Object { [string]$_.Type -eq 'File' }).Count -gt 0
    }).Count
    $remediationFindingCount = [int]($applicationFindingCount + $standaloneFindingCount)
    $unsupportedReviewCount = [int]@($ThirdPartyApplications | Where-Object {
        $isCleanupFinding = if ($_.PSObject.Properties['CleanupFinding']) { [bool]$_.CleanupFinding } else { [string]$_.AssessmentCode -in @('NonGenuine','Suspicious','IntegrityCompromised') }
        $isCleanupFinding -and -not [bool]$_.RemediationSupported
    }).Count
    $Verification | Add-Member -NotePropertyName ThirdPartyCandidateCount -NotePropertyValue $candidateCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyAutoEligibleCount -NotePropertyValue $autoEligibleCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyNeedsReviewCount -NotePropertyValue $reviewCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyRemediationFindingCount -NotePropertyValue $remediationFindingCount -Force
    $Verification | Add-Member -NotePropertyName ThirdPartyUnsupportedReviewCount -NotePropertyValue $unsupportedReviewCount -Force
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($check in @($Verification.ReadinessChecks)) { $checks.Add($check) }
    if ($remediationFindingCount -gt 0) {
        $baseScopeWasReady = [bool]$Verification.ReadyForOfficialActivation
        $thirdPartyBlockedConclusion = Get-CleanupText "cleanupReport.thirdParty.verification.blocked" @($remediationFindingCount, $candidateCount)
        $Verification.ReadyForOfficialActivation = $false
        $Verification.Conclusion = if ($baseScopeWasReady) {
            [string]$thirdPartyBlockedConclusion
        } else {
            ([string]$Verification.Conclusion + ' ' + [string]$thirdPartyBlockedConclusion).Trim()
        }
        $guidance = New-Object System.Collections.Generic.List[string]
        foreach ($step in @($Verification.HandlingGuidance | Where-Object { [string]$_ -ne (Get-CleanupText "cleanupReport.guidance.ready") })) { $guidance.Add([string]$step) }
        $guidance.Add((Get-CleanupText "cleanupReport.thirdParty.guidance" @($remediationFindingCount, $candidateCount, $autoEligibleCount, $unsupportedReviewCount)))
        $Verification.HandlingGuidance = $guidance.ToArray()
        $checks.Add([pscustomobject]@{
            Name=(Get-CleanupText "cleanupReport.thirdParty.readiness.name")
            StatusCode='Fail'; Status=(Get-CleanupText "cleanupReport.status.fail")
            Detail=(Get-CleanupText "cleanupReport.thirdParty.readiness.blocked" @($remediationFindingCount, $candidateCount, $autoEligibleCount, $unsupportedReviewCount))
        })
    } else {
        $checks.Add([pscustomobject]@{
            Name=(Get-CleanupText "cleanupReport.thirdParty.readiness.name")
            StatusCode='Pass'; Status=(Get-CleanupText "cleanupReport.status.pass")
            Detail=(Get-CleanupText "cleanupReport.thirdParty.readiness.pass")
        })
    }
    $Verification.ReadinessChecks = $checks.ToArray()
    $Verification.ScopeNote = ([string]$Verification.ScopeNote + ' ' + (Get-CleanupText "cleanupReport.thirdParty.scope")).Trim()
    return $Verification
}

function Get-SelectedCleanupIds {
    $script:SelectionAccepted = $false
    $script:SelectionErrorCode = 'SelectionFileMissing'
    $script:SelectionErrorDetail = ''
    if ([string]::IsNullOrWhiteSpace($SelectionFile) -or -not (Test-Path -LiteralPath $SelectionFile -PathType Leaf)) { return @() }
    try {
        $allowedRoot = if (-not [string]::IsNullOrWhiteSpace($env:TOOL_SECURE_RUNTIME_DIR)) { $env:TOOL_SECURE_RUNTIME_DIR } else { Join-Path $PSScriptRoot "runtime" }
        if ($env:TOOL_SECURE_LAUNCH -ne "1") { throw 'SecureLaunchRequired' }
        if (-not (Test-ProtectedDirectoryAcl -Path $PSScriptRoot -AllowCurrentUserForUserScope)) { throw 'ToolDirectoryAclInvalid' }
        if (-not (Test-ProtectedDirectoryAcl -Path $allowedRoot -AllowCurrentUserForUserScope)) { throw 'RuntimeDirectoryAclInvalid' }
        $rootFull = ([IO.Path]::GetFullPath($allowedRoot)).TrimEnd('\') + '\'
        $selectionFull = [IO.Path]::GetFullPath($SelectionFile)
        if (-not $selectionFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionFileOutsideRuntime' }
        if (-not [string]::Equals(([IO.Path]::GetDirectoryName($selectionFull).TrimEnd('\') + '\'), $rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionFileMustBeDirectChild' }
        $selectionItem = Get-Item -LiteralPath $selectionFull -Force -ErrorAction Stop
        if (($selectionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SelectionFileReparsePointRejected' }
        if ([int64]$selectionItem.Length -le 0 -or [int64]$selectionItem.Length -gt 262144) { throw 'SelectionFileSizeInvalid' }
        $selection = Get-Content -LiteralPath $selectionFull -Raw -ErrorAction Stop | ConvertFrom-Json
        if ([string]$selection.SchemaVersion -ne '1.0') { throw 'SelectionSchemaInvalid' }
        $requestId = [guid]::Empty
        if (-not [guid]::TryParse([string]$selection.RequestId, [ref]$requestId) -or $requestId -eq [guid]::Empty) { throw 'SelectionRequestIdInvalid' }
        if (-not [string]::Equals([string]$selection.ScanScope, [string]$ScanScope, [StringComparison]::OrdinalIgnoreCase)) { throw 'SelectionScopeMismatch' }
        $createdAtUtc = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$selection.CreatedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$createdAtUtc)) { throw 'SelectionTimestampInvalid' }
        $selectionAge = [DateTimeOffset]::UtcNow - $createdAtUtc.ToUniversalTime()
        if ($selectionAge.TotalMinutes -lt -5 -or $selectionAge.TotalHours -gt 2) { throw 'SelectionExpired' }
        $ids = @($selection.SelectedIds | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
        if ($ids.Count -eq 0 -or $ids.Count -gt 2048 -or @($ids | Where-Object { $_.Length -gt 4096 }).Count -gt 0) { throw 'SelectionIdsInvalid' }
        $script:SelectionAccepted = $true
        $script:SelectionErrorCode = ''
        $script:SelectionErrorDetail = ''
        return $ids
    } catch {
        $selectionError = [string]$_.Exception.Message
        $knownSelectionErrors = @(
            'SecureLaunchRequired','ToolDirectoryAclInvalid','RuntimeDirectoryAclInvalid','SelectionFileOutsideRuntime',
            'SelectionFileMustBeDirectChild','SelectionFileReparsePointRejected','SelectionFileSizeInvalid','SelectionSchemaInvalid',
            'SelectionRequestIdInvalid','SelectionScopeMismatch','SelectionTimestampInvalid','SelectionExpired','SelectionIdsInvalid'
        )
        $script:SelectionErrorCode = if ($knownSelectionErrors -contains $selectionError) { $selectionError } else { 'SelectionReadFailed' }
        $script:SelectionErrorDetail = [string]$_.Exception.GetType().Name
        return @()
    }
}

function Protect-HistoryText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $safe = $Text -replace "(?i)\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b", (Get-CleanupText "cleanupReport.redaction.productKey")
    $safe = $safe -replace '(?i)https?://[^\s"'']+', (Get-CleanupText "cleanupReport.redaction.url")
    $safe = ($safe -replace "\s+", " ").Trim()
    if ($safe.Length -gt 240) { $safe = $safe.Substring(0, 240) + "..." }
    return $safe
}

function Get-InvalidActivationHistory {
    # Lịch sử chỉ là bằng chứng quá khứ, không được dùng một mình để kết luận
    # crack vẫn đang hoạt động hoặc để tự động gỡ product key.
    $history = New-Object System.Collections.Generic.List[object]
    $strictPattern = "(?i)(kmspico|kmsauto|auto[\s._-]*kms|kms[\s._-]*vl(?:[\s._-]*all)?|kms-r|aact(?:portable)?|sppextcomobj(?:hook|patcher)|spp[\s._-]*(?:hook|patcher)|microsoft[\s_-]+toolkit|hwidgen|massgrave|mas[\s._-]*aio|tsforge|ohook|digital license activation|\bactivator\b|0xC004F074|VOLUME_KMSCLIENT)"
    $since = (Get-Date).AddDays(-180)

    $eventQueries = @(
        [pscustomobject]@{ LogName="Application"; ProviderName="Microsoft-Windows-Security-SPP"; Source=(Get-CleanupText "cleanupReport.history.softwareProtection") },
        [pscustomobject]@{ LogName="Microsoft-Windows-Windows Defender/Operational"; ProviderName="Microsoft-Windows-Windows Defender"; Source=(Get-CleanupText "cleanupReport.history.defender") },
        [pscustomobject]@{ LogName="Microsoft-Windows-TaskScheduler/Operational"; ProviderName="Microsoft-Windows-TaskScheduler"; Source=(Get-CleanupText "cleanupReport.history.taskScheduler") }
    )
    foreach ($query in $eventQueries) {
        try {
            Get-WinEvent -FilterHashtable @{ LogName=$query.LogName; StartTime=$since } -MaxEvents 500 -ErrorAction Stop |
                Where-Object { ([string]$_.Message) -match $strictPattern } |
                Select-Object -First 50 | ForEach-Object {
                    $history.Add([pscustomobject]@{
                        Time = if ($_.TimeCreated) { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { Get-CleanupText "common.unknown" }
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
                            Time = if ($lastWrite) { Get-CleanupText "cleanupReport.history.fileUpdated" @($lastWrite.ToString("yyyy-MM-dd HH:mm:ss")) } else { Get-CleanupText "cleanupReport.history.noCommandTime" }
                            Source = Get-CleanupText "cleanupReport.history.powerShell"
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
                $residues.Add([pscustomobject]@{ Type="KMSConfig"; Name=(Get-CleanupText "cleanupReport.residue.unapprovedKms"); Location=$path; Value=$server })
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
            $residues.Add([pscustomobject]@{ Type="HookFile"; Name="SppExtComObjHook.dll"; Location=$dllPath; Value=(Get-CleanupText "cleanupReport.residue.hookFile") })
        }
    }

    try {
        $preference = Get-MpPreference -ErrorAction Stop
        foreach ($excludedPath in @($preference.ExclusionPath)) {
            if ([string]$excludedPath -match $script:StrictActivatorPattern) {
                $residues.Add([pscustomobject]@{ Type="DefenderExclusion"; Name=(Get-CleanupText "cleanupReport.residue.defenderExclusion"); Location=[string]$excludedPath; Value=(Get-CleanupText "cleanupReport.residue.removeExclusion") })
            }
        }
    } catch {}

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try {
        $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction Stop
        if ([int]$policy.NoGenTicket -eq 1) {
            $residues.Add([pscustomobject]@{ Type="SPPPolicy"; Name="NoGenTicket=1"; Location=$policyPath; Value=(Get-CleanupText "cleanupReport.residue.noGenTicket") })
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
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="NotApplicable"; Status=(Get-CleanupText "cleanupReport.status.notApplicable"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceMissing") })
            } elseif ([string]$svc.StartMode -eq "Disabled") {
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceDisabled") })
            } else {
                $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Pass"; Status=(Get-CleanupText "cleanupReport.status.pass"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceState" @($svc.StartMode, $svc.State)) })
            }
        } catch {
            $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.service" @($serviceName)); StatusCode="Unverified"; Status=(Get-CleanupText "cleanupReport.status.unverified"); Detail=(Get-CleanupText "cleanupReport.readiness.serviceUnreadable") })
        }
    }

    foreach ($filePath in @(
        (Get-ToolNativeSystemPath "sppsvc.exe"),
        (Get-ToolNativeSystemPath "SppExtComObj.exe"),
        (Get-ToolNativeSystemPath "sppwinob.dll")
    )) {
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.licenseFile"); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.fileMissing" @($filePath)) })
            continue
        }
        $signature = Get-CleanupText "cleanupReport.value.notChecked"
        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $filePath -ErrorAction Stop
            $signature = [string]$sig.Status
        } catch {}
        $statusCode = if ($signature -eq "Valid") { "Pass" } elseif ($signature -eq "NotSigned") { "Review" } else { "Unverified" }
        $status = Get-CleanupText ("cleanupReport.status." + $statusCode.ToLowerInvariant())
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.licenseFileSignature"); StatusCode=$statusCode; Status=$status; Detail="$filePath | Authenticode=$signature" })
    }

    $pending = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($pending.Count -gt 0) {
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.pendingRestart"); StatusCode="Review"; Status=(Get-CleanupText "cleanupReport.status.review"); Detail=(Get-CleanupText "cleanupReport.readiness.restartRequired") })
    } else {
        $checks.Add([pscustomobject]@{ Name=(Get-CleanupText "cleanupReport.readiness.pendingRestart"); StatusCode="Pass"; Status=(Get-CleanupText "cleanupReport.status.pass"); Detail=(Get-CleanupText "cleanupReport.readiness.noRestartFlag") })
    }
    return $checks.ToArray()
}

function Get-CleanupVerification {
    param(
        $Products, $Findings, $OfficeEntries, $History,
        [ValidateSet('All','WindowsOffice','ThirdParty')][string]$Scope = 'All'
    )
    $includeWindowsOffice = [bool]($Scope -ne 'ThirdParty')
    $unapprovedWindows = @($Products | Where-Object {
        (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
    })
    $unapprovedOffice = @($OfficeEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
    $residues = @($(if ($includeWindowsOffice) { Get-ActivationConfigurationResidues }))
    $blockerCount = [int]($unapprovedWindows.Count + $unapprovedOffice.Count + @($Findings).Count + $residues.Count)
    $scanWarnings = @($script:ScanWarnings | Select-Object -Unique)
    $ready = [bool]($blockerCount -eq 0 -and $scanWarnings.Count -eq 0)
    $protected = if ($includeWindowsOffice) { Get-ProtectedLicenseInfo -Products $Products } else {
        [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
    }
    $readiness = @($(if ($includeWindowsOffice) { Get-ActivationReadinessDiagnostics }))
    $readinessReviewCount = @($readiness | Where-Object { $_.StatusCode -in @("Review", "Unverified") }).Count
    $conclusion = if ($scanWarnings.Count -gt 0) {
        Get-CleanupText "cleanupReport.verification.inconclusive"
    } elseif (-not $ready) {
        Get-CleanupText "cleanupReport.verification.notClean"
    } elseif ([bool]$protected.Protected) {
        Get-CleanupText "cleanupReport.verification.passProtected" @($protected.Channel)
    } else {
        Get-CleanupText "cleanupReport.verification.passReady"
    }
    $handlingGuidance = New-Object System.Collections.Generic.List[string]
    if ($scanWarnings.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.scanFailure"))
    }
    if ($unapprovedWindows.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.windowsKms"))
    }
    if ($unapprovedOffice.Count -gt 0) {
        $officeLabels = @($unapprovedOffice | ForEach-Object {
            $keyLabel = if ([string]::IsNullOrWhiteSpace([string]$_.Last5)) { Get-CleanupText "cleanupReport.value.noKey" } else { [string]$_.Last5 }
            "$([string]$_.LicenseName) [$keyLabel]"
        })
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.officeKms" @($officeLabels -join '; ')))
    }
    if (@($Findings).Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.activeActivator"))
    }
    if ($residues.Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.residues"))
    }
    if ($ready) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.ready"))
    }
    if ($readinessReviewCount -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.readinessReview"))
    }
    if (@($History).Count -gt 0) {
        $handlingGuidance.Add((Get-CleanupText "cleanupReport.guidance.history"))
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
        ScopeNote = Get-CleanupText "cleanupReport.verification.scope"
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
        $next.Add([pscustomobject]@{ Code="RepairScanSources"; Label=(Get-CleanupText "cleanupReport.next.repairScan"); Detail=(Get-CleanupText "cleanupReport.next.repairScanDetail"); CandidateCount=0 })
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.recheck"); Detail=(Get-CleanupText "cleanupReport.next.recheckBeforeChange"); CandidateCount=0 })
    } elseif ([bool]$Verification.ReadyForOfficialActivation) {
        if (-not $ProtectedLicense) {
            $next.Add([pscustomobject]@{ Code="OpenLicenseManager"; Label=(Get-CleanupText "cleanupReport.next.officialActivation"); Detail=(Get-CleanupText "cleanupReport.next.officialActivationDetail"); CandidateCount=0 })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.postCheck"); Detail=(Get-CleanupText "cleanupReport.next.postCheckDetail"); CandidateCount=0 })
    } else {
        if ($remaining.Count -gt 0) {
            $next.Add([pscustomobject]@{ Code="RemediateRemaining"; Label=(Get-CleanupText "cleanupReport.next.remaining"); Detail=(Get-CleanupText "cleanupReport.next.remainingDetail"); CandidateCount=[int]$remaining.Count })
        }
        if ([int]$Verification.UnapprovedWindowsKmsCount -gt 0 -or [int]$Verification.UnapprovedOfficeKmsCount -gt 0) {
            $next.Add([pscustomobject]@{ Code="ConfigureApprovedKms"; Label=(Get-CleanupText "cleanupReport.next.approveKms"); Detail=(Get-CleanupText "cleanupReport.next.approveKmsDetail"); CandidateCount=[int]($Verification.UnapprovedWindowsKmsCount + $Verification.UnapprovedOfficeKmsCount) })
        }
        $next.Add([pscustomobject]@{ Code="Recheck"; Label=(Get-CleanupText "cleanupReport.next.recheck"); Detail=(Get-CleanupText "cleanupReport.next.recheckReadOnly"); CandidateCount=0 })
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $next.Add([pscustomobject]@{ Code="RestoreBackup"; Label=(Get-CleanupText "cleanupReport.next.restore"); Detail=(Get-CleanupText "cleanupReport.next.restoreDetail"); CandidateCount=0 })
    }
    $next.Add([pscustomobject]@{ Code="OpenReport"; Label=(Get-CleanupText "cleanupReport.next.openReport"); Detail=(Get-CleanupText "cleanupReport.next.openReportDetail"); CandidateCount=0 })
    return @($next.ToArray())
}

function Get-ComplianceDecision {
    param($Products, $Findings)
    $oa3 = Get-Oa3KeyPresent
    $licensed = $Products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $current = if ($licensed) { $licensed } else { $Products | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
    if (-not $current) {
        return [pscustomobject]@{
            DecisionCode = "NoLicense"
            Decision = Get-CleanupText "cleanupReport.decision.noLicense"
            Reason = Get-CleanupText "cleanupReport.decision.noProductKey"
            ShouldRemediate = $false
        }
    }

    $channel = Get-LicenseChannel $current
    $kmsServer = [string]$current.KeyManagementServiceMachine
    $hasActivator = ($Findings.Count -gt 0)

    if ($hasActivator) {
        return [pscustomobject]@{
                DecisionCode = "Suspicious"
                Decision = Get-CleanupText "cleanupReport.decision.suspicious"
                Reason = Get-CleanupText "cleanupReport.decision.activatorDetected"
            ShouldRemediate = $true
        }
    }
    if ($channel -eq "KMS") {
        if (Test-ApprovedKms $kmsServer) {
            return [pscustomobject]@{
                DecisionCode = "KeepActivation"
                Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
                Reason = Get-CleanupText "cleanupReport.decision.approvedKms" @($kmsServer)
                ShouldRemediate = $false
            }
        }
        if ($TreatUnapprovedKmsAsNonCompliant) {
            return [pscustomobject]@{
                DecisionCode = "Suspicious"
                Decision = Get-CleanupText "cleanupReport.decision.suspicious"
                Reason = Get-CleanupText "cleanupReport.decision.unapprovedKms"
                ShouldRemediate = $true
            }
        }
        return [pscustomobject]@{
            DecisionCode = "ManualReview"
            Decision = Get-CleanupText "cleanupReport.decision.manualReview"
            Reason = Get-CleanupText "cleanupReport.decision.kmsManualReview"
            ShouldRemediate = $false
        }
    }
    if ($licensed -and $channel -in @("OEM", "Retail", "MAK")) {
        return [pscustomobject]@{
            DecisionCode = "KeepActivation"
            Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
            Reason = Get-CleanupText "cleanupReport.decision.validChannel" @($channel)
            ShouldRemediate = $false
        }
    }
    if ([int]$current.LicenseStatus -ne 1) {
        return [pscustomobject]@{
            DecisionCode = "LicenseReview"
            Decision = Get-CleanupText "cleanupReport.decision.licenseReview"
            Reason = Get-CleanupText "cleanupReport.decision.statusReview" @($channel, (Status-Text $current.LicenseStatus))
            ShouldRemediate = $false
        }
    }
    if ($oa3) {
        return [pscustomobject]@{
            DecisionCode = "KeepActivation"
            Decision = Get-CleanupText "cleanupReport.decision.keepActivation"
            Reason = Get-CleanupText "cleanupReport.decision.oa3Present"
            ShouldRemediate = $false
        }
    }
    return [pscustomobject]@{
        DecisionCode = "ManualReview"
        Decision = Get-CleanupText "cleanupReport.decision.manualReview"
        Reason = Get-CleanupText "cleanupReport.decision.channelUnknown"
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
                Reason = Get-CleanupText "cleanupReport.protected.channel" @($channel)
            }
        }
        if ($channel -eq "KMS" -and (Test-ApprovedKms ([string]$licensed.KeyManagementServiceMachine))) {
            return [pscustomobject]@{
                Protected = $true
                Channel = Get-CleanupText "cleanupReport.protected.approvedKmsChannel"
                Reason = Get-CleanupText "cleanupReport.protected.approvedKms"
            }
        }
    }
    if (Get-Oa3KeyPresent) {
        return [pscustomobject]@{
            Protected = $true
            Channel = "OEM OA3"
            Reason = Get-CleanupText "cleanupReport.protected.oa3"
        }
    }
    return [pscustomobject]@{
        Protected = $false
        Channel = if ($licensed) { Get-LicenseChannel $licensed } else { Get-CleanupText "common.unknown" }
        Reason = Get-CleanupText "cleanupReport.protected.none"
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
        Write-Warning (Get-CleanupText "cleanupReport.output.decisionWriteFailed" @($_.Exception.Message))
    }
}

function Invoke-ScanSourceRepair {
    $actions = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[object]
    $guidance = New-Object System.Collections.Generic.List[string]
    $serviceStateBefore = New-Object System.Collections.Generic.List[object]
    $serviceStateAfter = New-Object System.Collections.Generic.List[object]
    $startedServices = New-Object System.Collections.Generic.List[string]

    function Add-RepairCheck([string]$Name, [string]$StatusCode, [string]$Detail) {
        $checks.Add([pscustomobject]@{
            Name = $Name
            StatusCode = $StatusCode
            Status = Get-CleanupText ("cleanupReport.status." + $StatusCode.ToLowerInvariant())
            Detail = $Detail
        })
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
                    Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.serviceDisabled" @($name))
                    $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceDisabled" @($name)))
                    return
                }
                if (-not [bool]$Policy.AllowStart) {
                    Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.startDisallowed" @($name))
                    return
                }
                Start-Service -Name $name -ErrorAction Stop
                $startedServices.Add($name)
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceStarted" @($name)))
                $svc = Get-Service -Name $name -ErrorAction Stop
            }
            Add-RepairCheck $displayName "Pass" (Get-CleanupText "cleanupReport.repair.serviceState" @($name, $svc.Status, $before.StartMode))
        } catch {
            Add-RepairCheck $displayName "Fail" (Get-CleanupText "cleanupReport.repair.serviceFailed" @($name, $_.Exception.Message))
            $actions.Add((Get-CleanupText "cleanupReport.repair.action.serviceFailed" @($name, $_.Exception.Message)))
        }
    }

    $actions.Add((Get-CleanupText "cleanupReport.repair.action.started"))
    $actions.Add((Get-CleanupText "cleanupReport.repair.action.policy"))
    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) { Repair-ServiceState -Policy $servicePolicy }

    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""

    $products = @(Get-WindowsLicenseProducts)
    if ($products.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Pass" (Get-CleanupText "cleanupReport.repair.windowsLicenseRead" @($products.Count))
    } elseif ($script:WindowsLicenseSourceNote) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Pass" $script:WindowsLicenseSourceNote
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsLicense") "Fail" (Get-CleanupText "cleanupReport.repair.windowsLicenseUnreadable")
    }

    $tasks = @(Get-CompatibleScheduledTaskRecords -NoCache)
    if ($tasks.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.scheduledTasks") "Pass" (Get-CleanupText "cleanupReport.repair.tasksRead" @($tasks.Count))
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.scheduledTasks") "Fail" (Get-CleanupText "cleanupReport.repair.tasksUnreadable")
    }

    $services = @(Safe-Cim -ClassName Win32_Service -CriticalLabel (Get-CleanupText "cleanupReport.scan.servicesCritical") -NoCache)
    if ($services.Count -gt 0) {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsServices") "Pass" (Get-CleanupText "cleanupReport.repair.servicesRead" @($services.Count))
    } else {
        Add-RepairCheck (Get-CleanupText "cleanupReport.repair.windowsServices") "Fail" (Get-CleanupText "cleanupReport.repair.servicesUnreadable")
    }

    foreach ($toolName in @("cscript.exe", "schtasks.exe")) {
        try {
            $toolPath = Get-ToolNativeSystemPath $toolName
            if (Test-Path -LiteralPath $toolPath -PathType Leaf) {
                Add-RepairCheck $toolName "Pass" $toolPath
            } else {
                Add-RepairCheck $toolName "Fail" (Get-CleanupText "cleanupReport.repair.toolMissing")
            }
        } catch {
            Add-RepairCheck $toolName "Fail" $_.Exception.Message
        }
    }

    $warnings = @($script:ScanWarnings | Select-Object -Unique)
    foreach ($warning in $warnings) { $actions.Add((Get-CleanupText "cleanupReport.repair.action.postWarning" @($warning))) }
    $recheckPassed = [bool]($warnings.Count -eq 0 -and @($checks | Where-Object { $_.StatusCode -eq "Fail" }).Count -eq 0)
    $rollbackApplied = $false
    if ($recheckPassed) {
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.pass"))
    } else {
        foreach ($serviceName in @($startedServices)) {
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.rollback" @($serviceName)))
                $rollbackApplied = $true
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.repair.action.rollbackFailed" @($serviceName, $_.Exception.Message)))
            }
        }
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.fail"))
        $guidance.Add((Get-CleanupText "cleanupReport.repair.guidance.partialKey"))
    }

    foreach ($servicePolicy in @(Get-ToolScanSourceServicePolicy)) {
        try { $serviceStateAfter.Add((Get-ServiceStateSnapshot -Name ([string]$servicePolicy.Name) -DisplayName ([string]$servicePolicy.DisplayName))) }
        catch { $serviceStateAfter.Add([pscustomobject]@{ Name=[string]$servicePolicy.Name; DisplayName=[string]$servicePolicy.DisplayName; Status=(Get-CleanupText "common.unknown"); StartMode=(Get-CleanupText "common.unknown"); Error=$_.Exception.Message }) }
    }

    return (New-ToolReportEnvelope -ReportKind "ScanSourceRepair" -ToolVersion "4.8" -Data ([ordered]@{
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
    param($Path, $Products, $Findings, $Decision, $Actions, $History = @(), $Verification = $null, $ThirdPartyApplications = @(), $ThirdPartyEvidence = @(), $ThirdPartyCandidates = @(), $SoftwareDeepScanMetadata = $null)
    $lines = New-Object System.Collections.Generic.List[string]
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    $lines.Add((Get-CleanupText "cleanupReport.report.title"))
    $lines.Add((Get-CleanupText "cleanupReport.report.computer" @($env:COMPUTERNAME)))
    $lines.Add((Get-CleanupText "cleanupReport.report.user" @($env:USERNAME)))
    $lines.Add((Get-CleanupText "cleanupReport.report.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))))
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.initialDecision" @($Decision.Decision)))
    $lines.Add((Get-CleanupText "cleanupReport.report.initialReason" @($Decision.Reason)))
    if ($script:WindowsLicenseSourceNote) { $lines.Add((Get-CleanupText "cleanupReport.report.windowsSourceNote" @($script:WindowsLicenseSourceNote))) }
    $lines.Add((Get-CleanupText "cleanupReport.report.remediationRequested" @($(if ($Remediate) { $yes } else { $no }))))
    $lines.Add((Get-CleanupText "cleanupReport.report.deepCleanup" @($(if ($DeepClean) { $yes } else { $no }))))
    $lines.Add((Get-CleanupText "cleanupReport.report.unapprovedKmsNoncompliant" @($(if ($TreatUnapprovedKmsAsNonCompliant) { $yes } else { $no }))))
    if ($ApprovedKmsServers.Count -gt 0) {
        $lines.Add((Get-CleanupText "cleanupReport.report.approvedKmsServers" @($ApprovedKmsServers -join ', ')))
    } else {
        $lines.Add((Get-CleanupText "cleanupReport.report.approvedKmsServers" @((Get-CleanupText "cleanupReport.value.notConfigured"))))
    }
    $lines.Add((Get-CleanupText "cleanupReport.report.kmsConfigFile" @($approvedKmsConfig.Path)))
    $lines.Add((Get-CleanupText "cleanupReport.report.kmsLineCounts" @($approvedKmsConfig.Valid.Count, $approvedKmsConfig.Invalid.Count)))
    if ($approvedKmsConfig.Warning) { $lines.Add((Get-CleanupText "cleanupReport.report.kmsConfigWarning" @($approvedKmsConfig.Warning))) }
    $lines.Add("")
    if ($Verification) {
        $lines.Add((Get-CleanupText "cleanupReport.report.verificationHeading"))
        $lines.Add((Get-CleanupText "cleanupReport.report.ready" @($(if ($Verification.ReadyForOfficialActivation) { $yes } else { $no }))))
        $lines.Add((Get-CleanupText "cleanupReport.report.conclusion" @($Verification.Conclusion)))
        $lines.Add((Get-CleanupText "cleanupReport.report.activeActivatorCount" @($Verification.ActiveActivatorFindingCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.windowsKmsCount" @($Verification.UnapprovedWindowsKmsCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.officeKmsCount" @($Verification.UnapprovedOfficeKmsCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.residueCount" @($Verification.ConfigurationResidueCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.historyCount" @($Verification.HistoryFindingCount)))
        $lines.Add((Get-CleanupText "cleanupReport.report.scanWarningCount" @($Verification.ScanWarningCount)))
        foreach ($scanWarning in @($Verification.ScanWarnings)) {
            $lines.Add((Get-CleanupText "cleanupReport.report.scanWarning" @($scanWarning)))
        }
        $lines.Add((Get-CleanupText "cleanupReport.report.scope" @($Verification.ScopeNote)))
        $lines.Add("")
        $lines.Add((Get-CleanupText "cleanupReport.report.guidanceHeading"))
        foreach ($step in @($Verification.HandlingGuidance)) {
            $lines.Add("- $step")
        }
        if (@($Verification.HandlingGuidance).Count -eq 0) {
            $lines.Add((Get-CleanupText "cleanupReport.report.noAdditionalAction"))
        }
        $lines.Add("")
        $lines.Add((Get-CleanupText "cleanupReport.report.readinessReviewCount" @($Verification.ReadinessReviewCount)))
        foreach ($c in @($Verification.ReadinessChecks)) {
            $lines.Add("- [$($c.Status)] $($c.Name): $($c.Detail)")
        }
        foreach ($r in @($Verification.Residues)) {
            $lines.Add((Get-CleanupText "cleanupReport.report.residue" @($r.Type, $r.Name, $r.Location, $r.Value)))
        }
        $lines.Add("")
    }
    $lines.Add((Get-CleanupText "cleanupReport.report.windowsLicenses"))
    foreach ($p in $Products) {
        $lines.Add((Get-CleanupText "cleanupReport.report.name" @($p.Name)))
        $lines.Add((Get-CleanupText "cleanupReport.report.description" @($p.Description)))
        $lines.Add((Get-CleanupText "cleanupReport.report.status" @((Status-Text $p.LicenseStatus))))
        $lines.Add((Get-CleanupText "cleanupReport.report.channel" @((Get-LicenseChannel $p))))
        $lines.Add((Get-CleanupText "cleanupReport.report.last5" @($p.PartialProductKey)))
        $lines.Add((Get-CleanupText "cleanupReport.report.kmsServer" @($p.KeyManagementServiceMachine)))
    }
    if ($Products.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.activatorFindings"))
    foreach ($f in $Findings) {
        $lines.Add("- [$($f.Type)] $($f.Name)")
        $lines.Add((Get-CleanupText "cleanupReport.report.location" @($f.Location)))
        $lines.Add((Get-CleanupText "cleanupReport.report.plannedAction" @($f.Action)))
    }
    if ($Findings.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.heading"))
    if ($SoftwareDeepScanMetadata -and [bool]$SoftwareDeepScanMetadata.Enabled) {
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.deepSummary" @(
            $(if ([bool]$SoftwareDeepScanMetadata.Complete) { $yes } else { $no }),
            [int]$SoftwareDeepScanMetadata.ApplicationsScanned,
            [int]$SoftwareDeepScanMetadata.ApplicationsSkipped,
            [int]$SoftwareDeepScanMetadata.RelevantFiles,
            [int]$SoftwareDeepScanMetadata.SignatureChecks,
            [int]$SoftwareDeepScanMetadata.HashChecks,
            [int]$SoftwareDeepScanMetadata.AccessWarningCount)))
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.deepLimits" @(
            $(if ([bool]$SoftwareDeepScanMetadata.IsAdministrator) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.TimeLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.EntryLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.SignatureLimitReached) { $yes } else { $no }),
            $(if ([bool]$SoftwareDeepScanMetadata.HashLimitReached) { $yes } else { $no }),
            [int]$SoftwareDeepScanMetadata.DurationMilliseconds)))
    }
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.summary" @(@($ThirdPartyApplications).Count, @($ThirdPartyEvidence).Count, @($ThirdPartyCandidates).Count, @($ThirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count)))
    foreach ($app in @($ThirdPartyApplications)) {
        $evidenceSummary = @($app.Evidence | ForEach-Object { [string]$_.Code } | Select-Object -Unique) -join ', '
        if ([string]::IsNullOrWhiteSpace($evidenceSummary)) { $evidenceSummary = Get-CleanupText 'common.none' }
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.applicationExtended" @($app.Name, $app.Version, $app.Publisher, $app.LicenseModel, $app.TechnicalStatus, $app.Confidence, $evidenceSummary, $(if ([bool]$app.RemediationSupported) { $yes } else { $no }))))
    }
    if (@($ThirdPartyApplications).Count -eq 0) { $lines.Add("- " + (Get-CleanupText "common.none")) }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.evidenceHeading"))
    foreach ($item in @($ThirdPartyEvidence)) {
        $lines.Add((Get-CleanupText "cleanupReport.thirdParty.report.evidence" @($item.VendorScope, $item.Type, $item.Name, $item.Location, $item.Detail)))
    }
    if (@($ThirdPartyEvidence).Count -eq 0) { $lines.Add("- " + (Get-CleanupText "common.none")) }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.historyHeading"))
    $lines.Add((Get-CleanupText "cleanupReport.report.historyNote"))
    foreach ($h in @($History)) {
        $lines.Add((Get-CleanupText "cleanupReport.report.historyEvent" @($h.Time, $h.Source, $h.EventId)))
        $lines.Add((Get-CleanupText "cleanupReport.report.redactedEvidence" @($h.Evidence)))
    }
    if (@($History).Count -eq 0) {
        $lines.Add((Get-CleanupText "cleanupReport.report.noHistory"))
    }
    $lines.Add("")
    $lines.Add((Get-CleanupText "cleanupReport.report.actions"))
    foreach ($a in $Actions) {
        $lines.Add("- $a")
    }
    if ($Actions.Count -eq 0) {
        $lines.Add("- " + (Get-CleanupText "common.none"))
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
        if ([string]::IsNullOrWhiteSpace($summary)) { $summary = Get-CleanupText "cleanupReport.command.emptyExitCode" @($exitCode) }
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
    [int]$systemChangeCount = 0
    if (-not (Is-Admin)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.adminRequired"))
        return [pscustomobject]@{ Actions=@($actions); SystemChangeCount=0; SystemChangeApplied=$false }
    }

    if (-not $NoRestorePoint -and -not $SkipRestorePoint) {
        try {
            Checkpoint-Computer -Description (Get-CleanupText "cleanupReport.restorePoint.description") -RestorePointType "MODIFY_SETTINGS" | Out-Null
            $actions.Add((Get-CleanupText "cleanupReport.action.restorePointCreated"))
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.restorePointFailed" @($_.Exception.Message)))
        }
    }

    if ($CleanupActivator) {
    foreach ($f in $Findings) {
        if ($f.Type -eq "Process") {
            try {
                Stop-Process -Name $f.Name -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.processStopped" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.processStopFailed" @($f.Name, $_.Exception.Message)))
            }
        }
        if ($f.Type -eq "Service") {
            try {
                Stop-Service -Name $f.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $f.Name -StartupType Disabled -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.serviceDisabled" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.serviceDisableFailed" @($f.Name, $_.Exception.Message)))
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
                $actions.Add((Get-CleanupText "cleanupReport.action.taskDisabled" @($f.Name)))
                $systemChangeCount++
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.taskDisableFailed" @($f.Name, $_.Exception.Message)))
            }
        }
    }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.noActivatorItem"))
    }

    if ($CleanupKmsConfiguration) {
        $ckmsResult = Invoke-SlmgrCommand -SlmgrArguments @('/ckms')
        $actions.Add("slmgr /ckms: $($ckmsResult.Summary)")
        if ([bool]$ckmsResult.Success) { $systemChangeCount++ }
    }

    $windowsTargets = @($WindowsProductsToRemove)
    if ($windowsTargets.Count -gt 0) {
        $removedWindowsKeyCount = 0
        foreach ($targetProduct in $windowsTargets) {
            $activationId = [string]$targetProduct.ID
            if ([string]::IsNullOrWhiteSpace($activationId)) {
                $actions.Add((Get-CleanupText "cleanupReport.action.upkBlocked"))
                continue
            }
            $upkResult = Invoke-SlmgrCommand -SlmgrArguments @('/upk', $activationId)
            $actions.Add((Get-CleanupText "cleanupReport.action.upkSelected" @($upkResult.Summary)))
            if ([bool]$upkResult.Success) {
                $removedWindowsKeyCount++
                $systemChangeCount++
            }
        }
        if ($removedWindowsKeyCount -gt 0) {
            $cpkyResult = Invoke-SlmgrCommand -SlmgrArguments @('/cpky')
            $rilcResult = Invoke-SlmgrCommand -SlmgrArguments @('/rilc')
            $actions.Add("slmgr /cpky: $($cpkyResult.Summary)")
            $actions.Add("slmgr /rilc: $($rilcResult.Summary)")
            if ([bool]$cpkyResult.Success) { $systemChangeCount++ }
            if ([bool]$rilcResult.Success) { $systemChangeCount++ }
        } else {
            $actions.Add((Get-CleanupText "cleanupReport.action.skipCpkyRilc"))
        }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.keepWindowsKey"))
    }

    # Đưa Office KMS về trạng thái chưa kích hoạt: xóa KMS override một lần
    # cho mỗi OSPP.VBS, sau đó gỡ riêng từng Last5/SKU mà người dùng đã chọn.
    # /dstatusall ở bước quét bảo đảm nhiều SKU trên cùng đường dẫn không bị
    # che khuất lẫn nhau.
    $officeEntries = @($OfficeEntries)
    foreach ($path in @($officeEntries | ForEach-Object { [string]$_.Path } | Where-Object { $_ } | Select-Object -Unique)) {
        $remhst = Invoke-OfficeOsppCommand -Path $path -Arguments @('/remhst') -SuccessPattern '(?i)Successfully applied setting|thành công'
        if ([bool]$remhst.Success) {
            $actions.Add((Get-CleanupText "cleanupReport.action.officeRemhstPass" @($path, $remhst.Summary)))
            $systemChangeCount++
        } else {
            $actions.Add((Get-CleanupText "cleanupReport.action.officeRemhstFail" @($path, $remhst.ExitCode, $remhst.Summary)))
        }
    }
    $officeRemoved = 0
    foreach ($entry in @($officeEntries | Group-Object { "$($_.Path)|$($_.SkuId)|$($_.Last5)" } | ForEach-Object { $_.Group[0] })) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Last5)) {
            $unpkey = Invoke-OfficeOsppCommand -Path ([string]$entry.Path) -Arguments @("/unpkey:$($entry.Last5)") -SuccessPattern '(?i)product key uninstall successful|gỡ.+khóa.+thành công'
            if ([bool]$unpkey.Success) {
                $officeRemoved++
                $systemChangeCount++
                $actions.Add((Get-CleanupText "cleanupReport.action.officeUnpkeyPass" @($entry.Last5, $entry.SkuId, $entry.LicenseName, $unpkey.Summary)))
            } else {
                $actions.Add((Get-CleanupText "cleanupReport.action.officeUnpkeyFail" @($entry.Last5, $entry.SkuId, $entry.LicenseName, $unpkey.ExitCode, $unpkey.Summary)))
            }
        } else {
            $actions.Add((Get-CleanupText "cleanupReport.action.officeNoLast5" @($entry.SkuId)))
        }
    }
    if ($officeEntries.Count -eq 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.noOfficeKms"))
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.officeRemovalSummary" @($officeRemoved, @($officeEntries | Where-Object { $_.Last5 }).Count)))
    }
    return [pscustomobject]@{
        Actions = @($actions)
        SystemChangeCount = $systemChangeCount
        SystemChangeApplied = [bool]($systemChangeCount -gt 0)
    }
}

function Invoke-DeepCleanupV35 {
    param($Candidates, [string[]]$SelectedIds)
    $actions = New-Object System.Collections.Generic.List[string]
    $restoreItems = New-Object System.Collections.Generic.List[object]
    $thirdPartyExecutionResults = New-Object System.Collections.Generic.List[object]
    [int]$systemChangeCount = 0

    function Add-ThirdPartyExecutionResult {
        param($Candidate, [string]$Status, [bool]$Changed, [string]$Message = '')
        if (-not $Candidate -or ([string]$Candidate.Kind -notmatch '^ThirdParty' -and [string]$Candidate.Type -ne 'Guidance')) { return }
        $thirdPartyExecutionResults.Add([pscustomobject][ordered]@{
            ParentCandidateId = $(if ($Candidate.PSObject.Properties['ParentCandidateId']) { [string]$Candidate.ParentCandidateId } else { '' })
            TargetId = [string]$Candidate.TargetId
            VendorScope = [string]$Candidate.VendorScope
            Type = [string]$Candidate.Type
            Kind = [string]$Candidate.Kind
            Name = [string]$Candidate.Name
            Target = [string]$Candidate.Location
            Status = $Status
            Changed = [bool]$Changed
            Message = $Message
        })
    }
    if (-not (Is-Admin)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepAdminRequired"))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    $selectedLookup = @{}
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
            $selectedLookup[([string]$selectedId).ToLowerInvariant()] = $true
        }
    }
    $selectedTopLevel = @($Candidates | Where-Object { $selectedLookup.ContainsKey(([string]$_.Id).ToLowerInvariant()) })
    if ($selectedTopLevel.Count -eq 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepNothingSelected"))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    # Dòng Ứng dụng đại diện cho phạm vi giấy phép dùng chung của hãng. Chỉ mở
    # rộng kế hoạch do lần quét hiện tại tạo ra; SelectionFile chỉ chứa ID nên
    # không thể chèn đường dẫn hoặc lệnh tùy ý vào tiến trình Administrator.
    $selectedVendorScopes = @($selectedTopLevel | Where-Object { $_.Type -eq 'Application' } | ForEach-Object { [string]$_.VendorScope } | Where-Object { $_ } | Select-Object -Unique)
    $expanded = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($selectedTopLevel | Where-Object { $_.Type -ne 'Application' })) { $expanded.Add($candidate) }
    foreach ($applicationCandidate in @($selectedTopLevel | Where-Object { $_.Type -eq 'Application' })) {
        foreach ($planItem in @($applicationCandidate.PlanItems)) {
            $child = New-CleanupItem -Type ([string]$planItem.Type) -Kind ([string]$planItem.Kind) `
                -Name ([string]$planItem.Name) -Location ([string]$planItem.Location) -Detail ([string]$planItem.Detail) `
                -TargetId ([string]$applicationCandidate.TargetId) -VendorScope ([string]$applicationCandidate.VendorScope)
            $restorable = $true
            if ($planItem.PSObject.Properties['Restorable']) { $restorable = [bool]$planItem.Restorable }
            $child | Add-Member -NotePropertyName Restorable -NotePropertyValue $restorable -Force
            $child | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$applicationCandidate.Id) -Force
            $expanded.Add($child)
        }
        $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.planExpanded" @($applicationCandidate.Name, @($applicationCandidate.PlanItems).Count)))
    }
    $selected = @($expanded.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] })

    $deepStamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $quarantine = ""
    try {
        $secureBackupRoot = Get-SecureBackupRoot
        $quarantine = Join-Path $secureBackupRoot ("quarantine_$($env:COMPUTERNAME)_${deepStamp}_" + [guid]::NewGuid().ToString("N"))
        Ensure-Dir $quarantine
        Set-ProtectedBackupAcl $quarantine
        if (-not (Test-ProtectedDirectoryAcl $quarantine)) { throw (Get-CleanupText "cleanupReport.deep.invalidAcl") }
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.deepBackupBlocked" @($_.Exception.Message)))
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }
    $manifestPath = Join-Path $quarantine "RESTORE-MANIFEST.json"
    $hmacPath = Join-Path $quarantine "RESTORE-MANIFEST.hmac"
    $authPath = Join-Path $quarantine "RESTORE-AUTH.bin"
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
    $actions.Add((Get-CleanupText "cleanupReport.action.deepConfirmed" @($releaseVersion)))
    $actions.Add((Get-CleanupText "cleanupReport.action.selectedCount" @($selectedTopLevel.Count, @($Candidates).Count)))
    $actions.Add((Get-CleanupText "cleanupReport.action.quarantineDirectory" @($quarantine)))

    function Save-RestoreManifest {
        $manifest = [ordered]@{
            SchemaVersion = "2.0"
        ToolVersion = "4.8"
            BackupMode = "DeepCleanup"
            RemediationScope = $ScanScope
            ComputerName = $env:COMPUTERNAME
            MachineBinding = Get-MachineBinding
            CreatedAt = (Get-Date).ToString("o")
            RestoreScriptSha256 = $restoreScriptSha256
            RuntimeHelperSha256 = $runtimeHelperSha256
            SafetyPolicySha256 = $safetyPolicySha256
            LocalizationHelperSha256 = $localizationHelperSha256
            ViCatalogSha256 = $viCatalogSha256
            EnCatalogSha256 = $enCatalogSha256
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
        if (-not $Item.PSObject.Properties['Restorable']) {
            $Item | Add-Member -NotePropertyName Restorable -NotePropertyValue $true -Force
        }
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
                $nativePath = $nativePath -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
                $backupPath = Join-Path $quarantine (((( [string]$Candidate.Name) -replace '[\\/:*?"<>| ]', '_')) + "_" + [guid]::NewGuid().ToString("N") + ".reg")
                $output = (& $nativeRegPath export $nativePath $backupPath /y 2>&1) -join " | "
                if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw $output }
                $restorable = [bool]([string]$Candidate.Kind -notmatch '^(Activator|ThirdParty)')
                if ($Candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$Candidate.Restorable }
                Add-RestoreItem ([pscustomobject]@{ Type="Registry"; Name=[string]$Candidate.Name; OriginalPath=$psPath; BackupPath=$backupPath; Kind=[string]$Candidate.Kind; Restorable=$restorable })
            }
            $actions.Add((Get-CleanupText "cleanupReport.action.registryBackedUp" @($Candidate.Name, $backupPath)))
            return $true
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.registryBackupFailed" @($Candidate.Name, $_.Exception.Message)))
            return $false
        }
    }

    Save-RestoreManifest
    $restoreBundleReady = $false
    try {
        $restoreSource = Join-Path $PSScriptRoot "windows-license-restore.ps1"
        if (Test-Path -LiteralPath $restoreSource -PathType Leaf) {
            $restoreDestination = Join-Path $quarantine "windows-license-restore.ps1"
            Copy-Item -LiteralPath $restoreSource -Destination $restoreDestination -Force
            $restoreScriptSha256 = Get-Sha256 $restoreDestination
            $runtimeSource = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
            if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.deep.runtimeMissing") }
            $runtimeDestination = Join-Path $quarantine "Tool-Runtime.ps1"
            Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Force
            $runtimeHelperSha256 = Get-Sha256 $runtimeDestination
            $safetyPolicySource = Join-Path $PSScriptRoot "Tool-SafetyPolicy.ps1"
            if (-not (Test-Path -LiteralPath $safetyPolicySource -PathType Leaf)) { throw (Get-CleanupText "cleanupReport.deep.safetyPolicyMissing") }
            $safetyPolicyDestination = Join-Path $quarantine "Tool-SafetyPolicy.ps1"
            Copy-Item -LiteralPath $safetyPolicySource -Destination $safetyPolicyDestination -Force
            $safetyPolicySha256 = Get-Sha256 $safetyPolicyDestination
            $localizationSource = Join-Path $PSScriptRoot "Tool-Localization.ps1"
            if (-not (Test-Path -LiteralPath $localizationSource -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @("Tool-Localization.ps1")) }
            $localizationDestination = Join-Path $quarantine "Tool-Localization.ps1"
            Copy-Item -LiteralPath $localizationSource -Destination $localizationDestination -Force
            $localizationHelperSha256 = Get-Sha256 $localizationDestination
            $viCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.vi-VN.json"
            $enCatalogSource = Join-Path $PSScriptRoot "Tool-Strings.en-US.json"
            foreach ($catalogSource in @($viCatalogSource, $enCatalogSource)) {
                if (-not (Test-Path -LiteralPath $catalogSource -PathType Leaf)) { throw (Get-CleanupText "common.missingDependency" @([IO.Path]::GetFileName($catalogSource))) }
                Copy-Item -LiteralPath $catalogSource -Destination (Join-Path $quarantine ([IO.Path]::GetFileName($catalogSource))) -Force
            }
            $viCatalogSha256 = Get-Sha256 (Join-Path $quarantine "Tool-Strings.vi-VN.json")
            $enCatalogSha256 = Get-Sha256 (Join-Path $quarantine "Tool-Strings.en-US.json")
            @(
                '@echo off',
                'set "TOOL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
                'if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "TOOL_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
                ('"%TOOL_PS%" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-license-restore.ps1" -BackupDir "%~dp0" -Culture "' + $Culture + '"'),
                'pause'
            ) | Set-Content -LiteralPath (Join-Path $quarantine "KHOI-PHUC-TU-DONG.cmd") -Encoding ASCII
            Save-RestoreManifest
            foreach ($requiredBackupComponent in @($manifestPath, $hmacPath, $authPath, $restoreDestination, $runtimeDestination, $safetyPolicyDestination, $localizationDestination)) {
                if (-not (Test-Path -LiteralPath $requiredBackupComponent -PathType Leaf)) {
                    throw (Get-CleanupText "cleanupReport.action.restoreBundleComponentMissing" @([IO.Path]::GetFileName($requiredBackupComponent)))
                }
            }
            $restoreBundleReady = $true
        } else {
            throw (Get-CleanupText "cleanupReport.action.restoreBundleComponentMissing" @("windows-license-restore.ps1"))
        }
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleFailed" @($_.Exception.Message)))
    }
    if (-not $restoreBundleReady) {
        $actions.Add((Get-CleanupText "cleanupReport.action.backupRequiredBlocked"))
        if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }
        return [pscustomobject]@{ Actions=@($actions); BackupDirectory=""; SelectedCount=0; SystemChangeCount=0; SystemChangeApplied=$false; ThirdPartyExecutionResults=@() }
    }

    # Thay đổi product key không thể tự rollback nếu không lưu key đầy đủ.
    # Manifest chỉ ghi thông tin đã che để người dùng biết rõ giới hạn này.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "License" })) {
        Add-RestoreItem ([pscustomobject]@{
            Type="LicenseNotice"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
            BackupPath=""; Kind=[string]$candidate.Kind; Restorable=$false
        })
        $actions.Add((Get-CleanupText "cleanupReport.action.licenseNotRestorable" @($candidate.Name)))
    }

    # Tạm dừng dịch vụ cấp phép chính thức của đúng hãng được chọn để giải phóng
    # tệp trạng thái. Không xóa và không đổi StartupType của các dịch vụ này.
    $vendorLicenseServiceState = @{}
    $vendorServices = New-Object System.Collections.Generic.List[string]
    if ($selectedVendorScopes -contains 'Adobe') { foreach ($name in @('AGSService','AdobeARMservice')) { $vendorServices.Add($name) } }
    if ($selectedVendorScopes -contains 'Autodesk') { $vendorServices.Add('AdskLicensingService') }
    foreach ($serviceName in @($vendorServices.ToArray() | Select-Object -Unique)) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $vendorLicenseServiceState[$serviceName] = [bool]($service.Status -eq 'Running')
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceTemporarilyStopped" @($serviceName)))
            }
        } catch {}
    }

    # Dừng các tiến trình được chọn trước để giải phóng tệp/dịch vụ liên quan.
    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Process" })) {
        try {
            Stop-Process -Name $candidate.Name -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedProcessStopped" @($candidate.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedProcessStopFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    $licenseServiceState = @{}
    if (@($selected | Where-Object { $_.Type -eq "File" -and [string]$_.Kind -notmatch '^ThirdParty' }).Count -gt 0) {
        foreach ($serviceName in @("sppsvc", "osppsvc")) {
            try {
                $svc = Get-Service -Name $serviceName -ErrorAction Stop
                $licenseServiceState[$serviceName] = ($svc.Status -eq "Running")
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Registry" })) {
        if (-not (Backup-RegKeyV35 $candidate)) {
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.backupFailed')
            continue
        }
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
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedKmsRemoved" @($candidate.Location)))
                $systemChangeCount++
            } elseif ($candidate.Kind -eq "SppNoGenTicketPolicy") {
                Remove-ItemProperty -LiteralPath $candidate.Location -Name "NoGenTicket" -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedPolicyRemoved" @($candidate.Location)))
                $systemChangeCount++
            } elseif ($candidate.Kind -eq "IfeoHook") {
                Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedIfeoRemoved" @($candidate.Name)))
                $systemChangeCount++
            } elseif ($candidate.Kind -eq 'ThirdPartyUninstallEntry') {
                $safeUninstallPath = [bool]([string]$candidate.Location -match '(?i)^(HKLM|HKCU):\\SOFTWARE\\(?:WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$')
                $strongName = [bool]((Get-ThirdPartyEvidenceScope (([string]$candidate.Name) + ' ' + ([string]$candidate.Location))) -ne '')
                if (-not $safeUninstallPath -or -not $strongName) { throw (Get-CleanupText "cleanupReport.thirdParty.action.registryScopeRejected") }
                Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.uninstallEntryRemoved" @($candidate.Name)))
                $systemChangeCount++
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
            }
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.registryProcessFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Defender" })) {
        try {
            Add-RestoreItem ([pscustomobject]@{
                Type="Defender"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=""; Kind=[string]$candidate.Kind
            })
            Remove-MpPreference -ExclusionPath ([string]$candidate.Location) -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedDefenderRemoved" @($candidate.Location)))
            $systemChangeCount++
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.defenderRemoveFailed" @($candidate.Location, $_.Exception.Message)))
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "File" })) {
        try {
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Leaf)) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "cleanupReport.deep.reparseRejected") }
            $destination = Join-Path $quarantine ((Split-Path $candidate.Location -Leaf) + "_" + [guid]::NewGuid().ToString("N") + ".quarantine")
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Force -ErrorAction Stop
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="File"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind; Restorable=$restorable
            })
            Remove-Item -LiteralPath $candidate.Location -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedFileQuarantined" @($candidate.Location)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.fileQuarantineFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "ScheduledTask" })) {
        try {
            $task = Get-CompatibleScheduledTaskRecords | Where-Object {
                [string]::Equals([string]$_.FullName, [string]$candidate.Name, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
            if (-not $task) { throw (Get-CleanupText "cleanupReport.deep.selectedTaskMissing") }
            $taskPath = [string]$task.TaskPath
            $taskName = [string]$task.TaskName
            $backupPath = Join-Path $quarantine ("Task_" + ($taskName -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".xml")
            Export-CompatibleScheduledTask -Record $task -Path $backupPath
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="ScheduledTask"; Name=$taskName; OriginalPath=$taskPath; BackupPath=$backupPath
                Kind=[string]$candidate.Kind; WasEnabled=[bool]$task.WasEnabled; Restorable=$restorable
            })
            Remove-CompatibleScheduledTask -Record $task
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedTaskRemoved" @($candidate.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.taskRemoveFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Service" })) {
        try {
            $serviceInfo = Safe-Cim Win32_Service | Where-Object { $_.Name -eq $candidate.Name } | Select-Object -First 1
            if (-not $serviceInfo) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            $nativeServicePath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$($serviceInfo.Name)"
            $serviceBackupPath = Join-Path $quarantine ("Service_" + ($serviceInfo.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N") + ".reg")
            $serviceExport = (& $nativeRegPath export $nativeServicePath $serviceBackupPath /y 2>&1) -join " | "
            if (-not (Test-Path -LiteralPath $serviceBackupPath -PathType Leaf)) { throw $serviceExport }
            $dependencies = @()
            try { $dependencies = @(Get-Service -Name $serviceInfo.Name -ErrorAction Stop | Select-Object -ExpandProperty ServicesDependedOn | Select-Object -ExpandProperty Name) } catch {}
            $sddl = ""
            try { $sddl = ((& $nativeScPath sdshow $serviceInfo.Name 2>$null) | Where-Object { $_ -match '^D:' } | Select-Object -First 1) } catch {}
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="Service"; Name=[string]$serviceInfo.Name; OriginalPath=("HKLM:\SYSTEM\CurrentControlSet\Services\" + [string]$serviceInfo.Name); BackupPath=$serviceBackupPath
                Kind=[string]$candidate.Kind; DisplayName=[string]$serviceInfo.DisplayName
                PathName=[string]$serviceInfo.PathName; StartMode=[string]$serviceInfo.StartMode
                StartName=[string]$serviceInfo.StartName; Description=[string]$serviceInfo.Description
                WasRunning=[bool]($serviceInfo.State -eq "Running"); Dependencies=@($dependencies); SecurityDescriptor=[string]$sddl; Restorable=$restorable
            })
            Stop-Service -Name $serviceInfo.Name -Force -ErrorAction SilentlyContinue
            $deleteOutput = (& $nativeScPath delete $serviceInfo.Name 2>&1) -join " | "
            if ($LASTEXITCODE -ne 0) { throw $deleteOutput }
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedServiceRemoved" @($serviceInfo.Name)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.serviceRemoveFailed" @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { $_.Type -eq "Folder" })) {
        try {
            if (-not (Test-Path -LiteralPath $candidate.Location -PathType Container)) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'NoChange' -Changed $false -Message (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing')
                continue
            }
            if ((((Get-Item -LiteralPath $candidate.Location -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText "cleanupReport.deep.reparseRejected") }
            $destination = Join-Path $quarantine (($candidate.Name -replace '[\\/:*?"<>| ]','_') + "_" + [guid]::NewGuid().ToString("N"))
            Copy-Item -LiteralPath $candidate.Location -Destination $destination -Recurse -Force -ErrorAction Stop
            $restorable = [bool]([string]$candidate.Kind -notmatch '^(Activator|ThirdParty)')
            if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
            Add-RestoreItem ([pscustomobject]@{
                Type="Folder"; Name=[string]$candidate.Name; OriginalPath=[string]$candidate.Location
                BackupPath=$destination; Kind=[string]$candidate.Kind; Restorable=$restorable
            })
            Remove-Item -LiteralPath $candidate.Location -Recurse -Force -ErrorAction Stop
            $actions.Add((Get-CleanupText "cleanupReport.action.selectedFolderQuarantined" @($candidate.Location)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText "cleanupReport.action.folderQuarantineFailed" @($candidate.Location, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    if (@($selected | Where-Object { $_.Type -in @("File", "Registry") -and [string]$_.Kind -notmatch '^ThirdParty' }).Count -gt 0) {
        foreach ($systemFile in @(
            (Get-ToolNativeSystemPath "sppsvc.exe"),
            (Get-ToolNativeSystemPath "SppExtComObj.exe")
        )) {
            if (Test-Path -LiteralPath $systemFile) {
                try {
                    $sfcResult = Invoke-CleanupNativeCommandWithTimeout -FilePath $nativeSfcPath -Arguments @("/scanfile=$systemFile") -TimeoutSeconds 120
                    if ($sfcResult.TimedOut) {
                        $actions.Add((Get-CleanupText "cleanupReport.action.sfcTimedOut" @($systemFile, 120)))
                    } else {
                        $actions.Add("SFC ${systemFile}: $($sfcResult.Output)")
                    }
                } catch {
                    $actions.Add((Get-CleanupText "cleanupReport.action.sfcFailed" @($systemFile, $_.Exception.Message)))
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

    $hostsCandidates = @($selected | Where-Object { [string]$_.Type -eq 'Hosts' -and [string]$_.Kind -eq 'ThirdPartyHostsEntry' })
    if ($hostsCandidates.Count -gt 0) {
        $hostsPath = Join-Path ([Environment]::ExpandEnvironmentVariables('%WINDIR%')) 'System32\drivers\etc\hosts'
        try {
            if (-not (Test-Path -LiteralPath $hostsPath -PathType Leaf)) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.hostsMissing') }
            $hostsUpdate = Get-ThirdPartyHostsUpdate -Lines ([IO.File]::ReadAllLines($hostsPath)) -Targets @($hostsCandidates | ForEach-Object { [string]$_.Location })
            if ([int]$hostsUpdate.TargetCount -eq 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.hostsScopeRejected') }
            $hostsBackup = Join-Path $quarantine ('hosts_' + [guid]::NewGuid().ToString('N') + '.backup')
            Copy-Item -LiteralPath $hostsPath -Destination $hostsBackup -Force -ErrorAction Stop
            Add-RestoreItem ([pscustomobject]@{
                Type='File'; Name='hosts'; OriginalPath=$hostsPath; BackupPath=$hostsBackup
                Kind='ThirdPartyHostsEntry'; Restorable=$true
            })
            if ([int]$hostsUpdate.RemovedCount -gt 0) {
                $hostsTemp = Join-Path (Split-Path -Parent $hostsPath) ('.hosts-' + [guid]::NewGuid().ToString('N') + '.tmp')
                try {
                    [IO.File]::WriteAllLines($hostsTemp, [string[]]$hostsUpdate.Lines, (New-Object Text.UTF8Encoding($false)))
                    Move-Item -LiteralPath $hostsTemp -Destination $hostsPath -Force
                } finally {
                    if ($hostsTemp -and (Test-Path -LiteralPath $hostsTemp -PathType Leaf)) { Remove-Item -LiteralPath $hostsTemp -Force -ErrorAction SilentlyContinue }
                }
                $systemChangeCount++
            }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.hostsRestored' @($hostsUpdate.RemovedCount, $hostsUpdate.TargetCount)))
            foreach ($candidate in $hostsCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate `
                    -Status $(if ([int]$hostsUpdate.RemovedCount -gt 0) { 'Succeeded' } else { 'NoChange' }) `
                    -Changed:([bool]([int]$hostsUpdate.RemovedCount -gt 0)) `
                    -Message $(if ([int]$hostsUpdate.RemovedCount -gt 0) { [string]$candidate.Detail } else { Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing' })
            }
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.hostsFailed' @($_.Exception.Message)))
            foreach ($candidate in $hostsCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
            }
        }
    }
    $firewallCandidates = @($selected | Where-Object { [string]$_.Type -eq 'Firewall' -and [string]$_.Kind -eq 'ThirdPartyFirewallBlock' })
    foreach ($firewallGroup in @($firewallCandidates | Group-Object { ([string]$_.Name).ToLowerInvariant() })) {
        $groupCandidates = @($firewallGroup.Group)
        $ruleName = [string]$groupCandidates[0].Name
        $policy = $null
        try {
            if ([string]::IsNullOrWhiteSpace($ruleName) -or $ruleName.Length -gt 256) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected') }
            $allowedPrograms = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($candidate in $groupCandidates) {
                $programPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$candidate.Location))
                if (-not (Test-Path -LiteralPath $programPath -PathType Leaf)) { throw (Get-CleanupText 'cleanupReport.thirdParty.execution.targetMissing') }
                $programItem = Get-Item -LiteralPath $programPath -Force -ErrorAction Stop
                if (($programItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw (Get-CleanupText 'cleanupReport.deep.reparseRejected') }
                [void]$allowedPrograms.Add($programPath)
            }
            if ($allowedPrograms.Count -eq 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected') }

            $policy = New-Object -ComObject HNetCfg.FwPolicy2
            $matchingRules = New-Object System.Collections.Generic.List[object]
            foreach ($rule in $policy.Rules) {
                if (-not [string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $ruleProgram = ''
                try { $ruleProgram = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$rule.ApplicationName)) } catch {}
                if (-not [bool]$rule.Enabled -or [int]$rule.Action -ne 0 -or [int]$rule.Direction -ne 2 -or
                    -not $ruleProgram -or -not $allowedPrograms.Contains($ruleProgram)) {
                    throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected')
                }
                $matchingRules.Add([pscustomobject]@{
                    Name=[string]$rule.Name; ApplicationName=$ruleProgram; Description=[string]$rule.Description
                    Enabled=[bool]$rule.Enabled; Direction=[int]$rule.Direction; Action=[int]$rule.Action
                })
            }
            if ($matchingRules.Count -eq 0 -or $matchingRules.Count -ne $allowedPrograms.Count) {
                throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallScopeRejected')
            }
            Add-RestoreItem ([pscustomobject]@{
                Type='FirewallNotice'; Name=$ruleName; OriginalPath=(@($matchingRules.ToArray() | ForEach-Object { [string]$_.ApplicationName }) -join '; ')
                BackupPath=''; Kind='ThirdPartyFirewallBlock'; Restorable=$false; RuleSnapshots=$matchingRules.ToArray()
            })

            # FwPolicy2 identifies removals by rule name. Multiple same-name
            # entries are accepted only when every one is an exact selected
            # outbound block; remove/recheck is bounded to the observed count.
            for ($attempt = 0; $attempt -lt $matchingRules.Count; $attempt++) {
                $remainingSameName = 0
                foreach ($rule in $policy.Rules) {
                    if ([string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { $remainingSameName++ }
                }
                if ($remainingSameName -eq 0) { break }
                $policy.Rules.Remove($ruleName)
            }
            $remainingSameName = 0
            foreach ($rule in $policy.Rules) {
                if ([string]::Equals([string]$rule.Name, $ruleName, [StringComparison]::OrdinalIgnoreCase)) { $remainingSameName++ }
            }
            if ($remainingSameName -ne 0) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.firewallRemoveIncomplete' @($remainingSameName)) }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.firewallRemoved' @($ruleName, $matchingRules.Count)))
            $systemChangeCount += [int]$matchingRules.Count
            foreach ($candidate in $groupCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
            }
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.firewallFailed' @($ruleName, $_.Exception.Message)))
            foreach ($candidate in $groupCandidates) {
                Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
            }
        } finally {
            if ($policy) { try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($policy) } catch {} }
        }
    }
    foreach ($serviceName in $vendorLicenseServiceState.Keys) {
        if ([bool]$vendorLicenseServiceState[$serviceName]) {
            try {
                Start-Service -Name $serviceName -ErrorAction Stop
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceRestarted" @($serviceName)))
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.thirdParty.action.serviceRestartFailed" @($serviceName, $_.Exception.Message)))
            }
        }
    }

    foreach ($candidate in @($selected | Where-Object { [string]$_.Type -eq 'Repair' -and [string]$_.Kind -eq 'ThirdPartyMsiRepair' })) {
        try {
            $productCode = ([string]$candidate.Location).Trim().ToUpperInvariant()
            if ($productCode -notmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$') { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiScopeRejected') }
            Add-RestoreItem ([pscustomobject]@{
                Type='RepairNotice'; Name=[string]$candidate.Name; OriginalPath=$productCode
                BackupPath=''; Kind=[string]$candidate.Kind; Restorable=$false
            })
            $result = Invoke-CleanupNativeCommandWithTimeout -FilePath $nativeMsiExecPath -Arguments @('/fa', $productCode, '/qn', '/norestart') -TimeoutSeconds 300
            if ($result.TimedOut) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiTimedOut' @(300)) }
            if ([int]$result.ExitCode -notin @(0, 3010)) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiExitCode' @($result.ExitCode, $result.Output)) }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.msiRepairCompleted' @($candidate.Name, $result.ExitCode)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'SucceededNeedsVerification' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.msiRepairFailed' @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { [string]$_.Type -eq 'Uninstall' -and [string]$_.Kind -eq 'ThirdPartyMsiUninstall' })) {
        try {
            $productCode = ([string]$candidate.Location).Trim().ToUpperInvariant()
            if ($productCode -notmatch '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$') { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiScopeRejected') }
            Add-RestoreItem ([pscustomobject]@{
                Type='UninstallNotice'; Name=[string]$candidate.Name; OriginalPath=$productCode
                BackupPath=''; Kind=[string]$candidate.Kind; Restorable=$false
            })
            $result = Invoke-CleanupNativeCommandWithTimeout -FilePath $nativeMsiExecPath -Arguments @('/x', $productCode, '/qn', '/norestart') -TimeoutSeconds 300
            if ($result.TimedOut) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiTimedOut' @(300)) }
            if ([int]$result.ExitCode -notin @(0, 1605, 3010)) { throw (Get-CleanupText 'cleanupReport.thirdParty.action.msiExitCode' @($result.ExitCode, $result.Output)) }
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.msiUninstallCompleted' @($candidate.Name, $result.ExitCode)))
            $systemChangeCount++
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Succeeded' -Changed $true -Message ([string]$candidate.Detail)
        } catch {
            $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.msiUninstallFailed' @($candidate.Name, $_.Exception.Message)))
            Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'Failed' -Changed $false -Message ([string]$_.Exception.Message)
        }
    }

    foreach ($candidate in @($selected | Where-Object { [string]$_.Type -eq 'Guidance' -and [string]$_.Kind -eq 'ThirdPartyOfficialSource' })) {
        $actions.Add((Get-CleanupText 'cleanupReport.thirdParty.action.officialSourceRequired' @($candidate.Name, $(if ($candidate.Location) { [string]$candidate.Location } else { Get-CleanupText 'common.unknown' }))))
        Add-ThirdPartyExecutionResult -Candidate $candidate -Status 'GuidanceOnly' -Changed $false -Message ([string]$candidate.Detail)
    }

    try {
        Save-RestoreManifest
        $actions | Set-Content -LiteralPath (Join-Path $quarantine "QUARANTINE-MANIFEST.txt") -Encoding UTF8
        @(
            Get-CleanupText "cleanupReport.restoreGuide.title" @($releaseVersion)
            Get-CleanupText "cleanupReport.restoreGuide.step1"
            Get-CleanupText "cleanupReport.restoreGuide.step2"
            Get-CleanupText "cleanupReport.restoreGuide.step3"
            Get-CleanupText "cleanupReport.restoreGuide.step4"
            Get-CleanupText "cleanupReport.restoreGuide.step5"
        ) | Set-Content -LiteralPath (Join-Path $quarantine (Get-CleanupText "cleanupReport.restoreGuide.fileName")) -Encoding UTF8
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleCreated"))
    } catch {
        $actions.Add((Get-CleanupText "cleanupReport.action.restoreBundleFinalizeFailed" @($_.Exception.Message)))
    }

    if ($hmacKey) { [Array]::Clear($hmacKey, 0, $hmacKey.Length) }

    return [pscustomobject]@{
        Actions=@($actions)
        BackupDirectory=$quarantine
        SelectedCount=[int]$selectedTopLevel.Count
        SystemChangeCount=[int]$systemChangeCount
        SystemChangeApplied=[bool]($systemChangeCount -gt 0)
        ThirdPartyExecutionResults=@($thirdPartyExecutionResults.ToArray())
    }
}

if ($RepairScanSources) {
    Ensure-Dir $OutputDir
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $reportComputer = if ($RedactSensitive) { Get-CleanupText "report.file.redactedToken" } else { $env:COMPUTERNAME }
    $repairReportPath = Join-Path $OutputDir ((Get-CleanupText "cleanupReport.file.repairPrefix") + "_${reportComputer}_$stamp.txt")
    $repair = Invoke-ScanSourceRepair
    $repair.ReportPath = [string]$repairReportPath
    $repairLines = New-Object System.Collections.Generic.List[string]
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.title" @($releaseVersion)))
    $repairLines.Add((Get-CleanupText "cleanupReport.report.time" @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.recheckPassed" @($(if ($repair.RecheckPassed) { $yes } else { $no }))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.startupChanged" @($(if ($repair.StartupTypeChanged) { $yes } else { $no }))))
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.rollbackApplied" @($(if ($repair.RollbackApplied) { $yes } else { $no }))))
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.checks"))
    foreach ($check in @($repair.Checks)) { $repairLines.Add("- [$($check.Status)] $($check.Name): $($check.Detail)") }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.actions"))
    foreach ($action in @($repair.Actions)) { $repairLines.Add("- $action") }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.serviceStates"))
    foreach ($before in @($repair.ServiceStateBefore)) {
        $after = @($repair.ServiceStateAfter | Where-Object { $_.Name -eq $before.Name } | Select-Object -First 1)
        $afterText = if ($after.Count -gt 0) { "$($after[0].Status), StartupType=$($after[0].StartMode)" } else { Get-CleanupText "cleanupReport.value.unreadable" }
        $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.serviceState" @($before.Name, $before.Status, $before.StartMode, $afterText)))
    }
    $repairLines.Add("")
    $repairLines.Add((Get-CleanupText "cleanupReport.repairReport.guidance"))
    foreach ($step in @($repair.HandlingGuidance)) { $repairLines.Add("- $step") }
    @($repairLines | ForEach-Object { Protect-CleanupReportText $_ }) | Set-Content -LiteralPath $repairReportPath -Encoding UTF8
    Write-DecisionData -Path $DecisionFile -Data $repair
    Write-Host (Get-CleanupText "cleanupReport.output.repairReport" @($repairReportPath))
    if ($repair.RecheckPassed) { exit 0 }
    exit 3
}

Import-ApprovedKmsServers
$approvedKmsConfig = Get-ApprovedKmsConfiguration
Ensure-Dir $OutputDir
$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$reportComputer = if ($RedactSensitive) { Get-CleanupText "report.file.redactedToken" } else { $env:COMPUTERNAME }
$reportPath = Join-Path $OutputDir ((Get-CleanupText "cleanupReport.file.cleanupPrefix") + "_${reportComputer}_$stamp.txt")

$script:WindowsLicenseSourceNote = ""
$includeWindowsOfficeScan = [bool]($ScanScope -ne 'ThirdParty')
$includeThirdPartyScan = [bool]($ScanScope -ne 'WindowsOffice')
$deepSoftwareScanEnabled = [bool]($includeThirdPartyScan -and -not $SkipDeepSoftwareScan)
$products = @($(if ($includeWindowsOfficeScan) { Get-WindowsLicenseProducts }))
$findings = @($(if ($includeWindowsOfficeScan) { Get-ActivatorFindings }))
$officeKmsEntries = @($(if ($includeWindowsOfficeScan) { Get-OfficeKmsEntries }))
$installedApplications = @($(if ($includeThirdPartyScan) { Get-InstalledSoftwareInventory }))
$softwareCatalog = if ($includeThirdPartyScan) { Get-ToolSoftwareLicenseCatalog -PreferCache } else { $null }
$thirdPartyEvidence = @($(if ($includeThirdPartyScan) { Get-ThirdPartyStrongEvidence -Applications $installedApplications -Catalog $softwareCatalog }))
$thirdPartyApplications = @($(if ($includeThirdPartyScan) {
    Get-ToolSoftwareAssessments `
        -Applications @($installedApplications | Where-Object {
            -not ([bool]$_.IsMicrosoft -and [string]$_.Name -match '(?i)\bWindows\b|\bOffice\b|\bMicrosoft\s*365\b')
        }) `
        -Catalog $softwareCatalog -ExternalEvidence $thirdPartyEvidence -DeepScan:$deepSoftwareScanEnabled `
        -DeepScanMaximumDurationSeconds $DeepSoftwareScanTimeoutSeconds `
        -DeepScanMaximumSignatureChecks $DeepSoftwareScanMaximumSignatureChecks `
        -DeepScanMaximumHashChecks $DeepSoftwareScanMaximumHashChecks
}))
$softwareDeepScanMetadata = Get-ToolSoftwareLastDeepScanMetadata
$thirdPartyCandidates = @(Get-ThirdPartyLicenseCandidates -Applications $thirdPartyApplications -Evidence $thirdPartyEvidence)
Connect-ThirdPartyApplicationsToCandidates -Applications $thirdPartyApplications -Candidates $thirdPartyCandidates
$script:SensitiveKmsHosts = @(
    @($ApprovedKmsServers)
    @($approvedKmsConfig.Valid)
    @($products | ForEach-Object { [string]$_.KeyManagementServiceMachine })
    @($officeKmsEntries | ForEach-Object { [string]$_.Server })
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
$history = @($(if ($includeWindowsOfficeScan) { Get-InvalidActivationHistory }))
$configurationResidues = @($(if ($includeWindowsOfficeScan) { Get-ActivationConfigurationResidues }))
$unapprovedOfficeKmsEntries = @($officeKmsEntries | Where-Object { -not (Test-ApprovedKms ([string]$_.Server)) })
$decision = if ($includeWindowsOfficeScan) { Get-ComplianceDecision -Products $products -Findings $findings } else {
    [pscustomobject]@{
        DecisionCode='ThirdPartyInventory'; Decision=(Get-CleanupText 'cleanupReport.thirdParty.decision')
        Reason=(Get-CleanupText 'cleanupReport.thirdParty.reason' @(0)); ShouldRemediate=$false
    }
}

function Expand-SelectedCleanupCandidates {
    param($Candidates, [string[]]$SelectedIds)

    $selectedLookup = @{}
    foreach ($selectedId in @($SelectedIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedId)) {
            $selectedLookup[([string]$selectedId).ToLowerInvariant()] = $true
        }
    }
    $expanded = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates | Where-Object { $selectedLookup.ContainsKey(([string]$_.Id).ToLowerInvariant()) })) {
        if ([string]$candidate.Type -ne 'Application') {
            $candidate | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$candidate.Id) -Force
            $expanded.Add($candidate)
            continue
        }
        foreach ($planItem in @($candidate.PlanItems)) {
            $child = New-CleanupItem -Type ([string]$planItem.Type) -Kind ([string]$planItem.Kind) `
                -Name ([string]$planItem.Name) -Location ([string]$planItem.Location) -Detail ([string]$planItem.Detail) `
                -TargetId ([string]$candidate.TargetId) -VendorScope ([string]$candidate.VendorScope)
            $restorable = $true
            if ($planItem.PSObject.Properties['Restorable']) { $restorable = [bool]$planItem.Restorable }
            $child | Add-Member -NotePropertyName Restorable -NotePropertyValue $restorable -Force
            $child | Add-Member -NotePropertyName ParentCandidateId -NotePropertyValue ([string]$candidate.Id) -Force
            $expanded.Add($child)
        }
    }
    return @($expanded.ToArray() | Group-Object Id | ForEach-Object { $_.Group[0] })
}

function Get-DryRunRemediationPlan {
    param($Candidates, [string[]]$SelectedIds, [switch]$SkipRestorePoint)

    $plan = New-Object System.Collections.Generic.List[object]
    $expanded = @(Expand-SelectedCleanupCandidates -Candidates $Candidates -SelectedIds $SelectedIds)
    [int]$order = 0

    if (-not $SkipRestorePoint) {
        $order++
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId='system-restore-point'; ParentCandidateId=''; Type='Safety'; Kind='RestorePoint'
            ActionCode='CreateRestorePoint'; Action=(Get-CleanupText 'cleanupReport.dryRun.action.createRestorePoint')
            Name='System Restore'; Target='Windows'; Detail=(Get-CleanupText 'cleanupReport.restorePoint.selectedDescription' @($releaseVersion))
            RequiresAdministrator=$true; BackupPlanned=$false; Restorable=$true; ChangesSystem=$true
        })
    }
    if ($expanded.Count -gt 0) {
        $plannedDataRoot = [string]$env:TOOL_DATA_ROOT
        if ([string]::IsNullOrWhiteSpace($plannedDataRoot)) {
            $plannedDataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ThanhViet-Tool-Kiem-Tra\v4.6'
        }
        $order++
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId='signed-backup-bundle'; ParentCandidateId=''; Type='Safety'; Kind='BackupBundle'
            ActionCode='CreateSignedBackup'; Action=(Get-CleanupText 'cleanupReport.dryRun.action.createBackup')
            Name='RESTORE-MANIFEST'; Target=(Join-Path $plannedDataRoot 'backups'); Detail=(Get-CleanupText 'cleanupReport.dryRun.detail.backup')
            RequiresAdministrator=$true; BackupPlanned=$true; Restorable=$true; ChangesSystem=$true
        })
    }

    foreach ($candidate in $expanded) {
        $order++
        $type = [string]$candidate.Type
        $kind = [string]$candidate.Kind
        $actionCode = 'ManualGuidance'
        $action = Get-CleanupText 'cleanupReport.dryRun.action.guidance'
        $changesSystem = $false
        $backupPlanned = $false
        $restorable = $false
        switch ($type) {
            'Process' { $actionCode='StopProcess'; $action=Get-CleanupText 'cleanupReport.dryRun.action.stopProcess'; $changesSystem=$true }
            'Service' { $actionCode='BackupAndDeleteService'; $action=Get-CleanupText 'cleanupReport.dryRun.action.deleteService'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'ScheduledTask' { $actionCode='BackupAndDeleteTask'; $action=Get-CleanupText 'cleanupReport.dryRun.action.deleteTask'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'Registry' { $actionCode='BackupAndRemoveRegistry'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeRegistry'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Defender' { $actionCode='RemoveDefenderExclusion'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeDefender'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'File' { $actionCode='QuarantineFile'; $action=Get-CleanupText 'cleanupReport.dryRun.action.quarantineFile'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Folder' { $actionCode='QuarantineFolder'; $action=Get-CleanupText 'cleanupReport.dryRun.action.quarantineFolder'; $changesSystem=$true; $backupPlanned=$true; $restorable=[bool]([string]$kind -notmatch '^(Activator|ThirdParty)') }
            'Hosts' { $actionCode='BackupAndRemoveHostsEntry'; $action=Get-CleanupText 'cleanupReport.dryRun.action.cleanHosts'; $changesSystem=$true; $backupPlanned=$true; $restorable=$true }
            'Firewall' { $actionCode='RemoveScopedFirewallBlock'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeFirewallBlock'; $changesSystem=$true; $backupPlanned=$true; $restorable=$false }
            'Repair' { $actionCode='RepairMsiProduct'; $action=Get-CleanupText 'cleanupReport.dryRun.action.repairMsi'; $changesSystem=$true }
            'Uninstall' { $actionCode='UninstallMsiProduct'; $action=Get-CleanupText 'cleanupReport.dryRun.action.uninstallMsi'; $changesSystem=$true }
            'License' {
                if ($kind -eq 'WindowsKmsLicense') { $actionCode='RemoveWindowsKmsLicense'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeWindowsKms' }
                elseif ($kind -eq 'OfficeKmsLicense') { $actionCode='RemoveOfficeKmsLicense'; $action=Get-CleanupText 'cleanupReport.dryRun.action.removeOfficeKms' }
                $changesSystem=$true
            }
        }
        if ($candidate.PSObject.Properties['Restorable']) { $restorable = [bool]$candidate.Restorable }
        $plan.Add([pscustomobject][ordered]@{
            Order=$order; CandidateId=[string]$candidate.Id; ParentCandidateId=[string]$candidate.ParentCandidateId
            Type=$type; Kind=$kind; ActionCode=$actionCode; Action=$action; Name=[string]$candidate.Name
            Target=[string]$candidate.Location; Detail=[string]$candidate.Detail; RequiresAdministrator=[bool]$changesSystem
            BackupPlanned=[bool]$backupPlanned; Restorable=[bool]$restorable; ChangesSystem=[bool]$changesSystem
        })
    }
    return $plan.ToArray()
}
$thirdPartyCandidateCount = [int]$thirdPartyCandidates.Count
if ($thirdPartyCandidateCount -gt 0 -and -not [bool]$decision.ShouldRemediate) {
    $decision.ShouldRemediate = $true
    $decision.DecisionCode = 'ThirdPartyTechnicalEvidence'
    $decision.Decision = Get-CleanupText "cleanupReport.thirdParty.decision"
    $decision.Reason = Get-CleanupText "cleanupReport.thirdParty.reason" @($thirdPartyCandidateCount)
}
$protectedLicense = if ($includeWindowsOfficeScan) { Get-ProtectedLicenseInfo -Products $products } else {
    [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
}
$activeLicensedProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$activeWindowsChannel = if ($activeLicensedProduct) { Get-LicenseChannel $activeLicensedProduct } else { Get-CleanupText "common.unknown" }
$activeApprovedKms = [bool]($activeWindowsChannel -eq "KMS" -and (Test-ApprovedKms ([string]$activeLicensedProduct.KeyManagementServiceMachine)))
$protectedActiveChannel = [bool]($activeWindowsChannel -in @("OEM", "Retail", "MAK") -or $activeApprovedKms)
$unapprovedWindowsKmsProducts = @($products | Where-Object {
    (Get-LicenseChannel $_) -eq "KMS" -and -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine))
})
$unapprovedWindowsKms = [bool]($unapprovedWindowsKmsProducts.Count -gt 0)
$allCleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -ThirdPartyCandidates $thirdPartyCandidates)
$cleanupItems = @(Get-ScopedCleanupCandidates -CleanupItems $allCleanupItems -Scope $ScanScope)
$thirdPartyRemediationFindingCount = [int]@($thirdPartyApplications | Where-Object { $_.PSObject.Properties['CleanupFinding'] -and [bool]$_.CleanupFinding }).Count
$windowsOfficeCleanupCount = [int]@($cleanupItems | Where-Object { [string]$_.Type -ne 'Application' }).Count
$crackDetected = [bool]($windowsOfficeCleanupCount -gt 0 -or $thirdPartyRemediationFindingCount -gt 0 -or $thirdPartyCandidateCount -gt 0)
$removeWindowsLicense = [bool]($unapprovedWindowsKms -and -not $protectedActiveChannel)
$unapprovedWindowsConfigResidues = @($configurationResidues | Where-Object {
    $_.Type -eq "KMSConfig" -and $_.Location -match "Windows NT\\CurrentVersion\\SoftwareProtectionPlatform"
})
$cleanupWindowsKmsConfiguration = [bool]($unapprovedWindowsKms -or $unapprovedWindowsConfigResidues.Count -gt 0)
$verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history -Scope $ScanScope
$verification = Add-ThirdPartyVerification -Verification $verification -ThirdPartyCandidates $thirdPartyCandidates -ThirdPartyApplications $thirdPartyApplications
$scopeReadyForOriginalState = Test-CleanupScopeReady -Verification $verification -Scope $ScanScope
$decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.8" -Data ([ordered]@{
    ScanScope = $ScanScope
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
    InstalledApplicationCount = [int]$installedApplications.Count
    ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
    ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
    ThirdPartyCandidateCount = [int]$thirdPartyCandidateCount
    ThirdPartyAutoEligibleCount = [int]@($thirdPartyCandidates | Where-Object { [bool]$_.AutoEligible }).Count
    ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
    ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
    ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
    ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
    SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
    SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
    SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
    DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
    DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
    DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
    DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
    DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
    DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
    DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
    DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
    DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
    DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
    DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
    DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
    DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
    DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
    DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
    DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
    DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
    DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
    ThirdPartyApplications = @($thirdPartyApplications)
    ThirdPartyEvidence = @($thirdPartyEvidence)
    ThirdPartyCandidates = @($thirdPartyCandidates)
    ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $unapprovedOfficeKmsEntries.Count)
    ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
    ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
    InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
    ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
    DecisionCode = [string]$decision.DecisionCode
    Decision = [string]$decision.Decision
    Reason = [string]$decision.Reason
    ReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
    ScopeReadyForOriginalState = [bool]$scopeReadyForOriginalState
    ReadinessReviewCount = [int]$verification.ReadinessReviewCount
    ScanWarningCount = [int]$verification.ScanWarningCount
    ScanWarnings = $verification.ScanWarnings
    ReadinessChecks = $verification.ReadinessChecks
    DeepCleanupApplied = $false
    SystemChangeApplied = $false
    SystemChangeCount = 0
    ThirdPartyExecutionResults = @()
    DryRunRequested = [bool]$DryRun
    SimulationOnly = [bool]$DryRun
    NoSystemChangesApplied = $true
    PlannedActionCount = 0
    PlannedActions = @()
    SelectedCleanupIds = @()
    SelectionAccepted = $false
    SelectionErrorCode = 'NotRequested'
    SelectionErrorDetail = ''
    UnknownSelectedCleanupIdCount = 0
    BackupWouldBeCreated = $false
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
$script:SelectionAccepted = $false
$script:SelectionErrorCode = $(if ($Remediate -and $DeepClean) { 'SelectionNotRead' } else { 'NotRequested' })
$script:SelectionErrorDetail = ''
$selectedCleanupIds = @($(if ($Remediate -and $DeepClean) { Get-SelectedCleanupIds }))
$knownCleanupIdSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($cleanupItem in @($cleanupItems)) { [void]$knownCleanupIdSet.Add(([string]$cleanupItem.Id).ToLowerInvariant()) }
$unknownSelectedCleanupIds = @($selectedCleanupIds | Where-Object { -not $knownCleanupIdSet.Contains([string]$_) })
if ($script:SelectionAccepted -and $unknownSelectedCleanupIds.Count -gt 0) {
    $script:SelectionAccepted = $false
    $script:SelectionErrorCode = 'SelectionContainsUnknownIds'
    $script:SelectionErrorDetail = [string]$unknownSelectedCleanupIds.Count
    $selectedCleanupIds = @()
}
$backupDirectory = ""
$plannedActions = @()
$thirdPartyExecutionResults = @()
$selectedThirdPartySnapshots = @()
$selectedThirdPartyResolvedCount = 0
$selectedThirdPartyRemainingCount = 0
[int]$systemChangeCount = 0
$finalDecisionCode = [string]$decision.DecisionCode
$finalDecisionText = [string]$decision.Decision
$finalCleanupConclusion = [string]$verification.Conclusion
$finalReadyForOfficialActivation = [bool]$verification.ReadyForOfficialActivation
$finalScopeReadyForOriginalState = [bool]$scopeReadyForOriginalState

if ($Remediate) {
    if ($env:TOOL_SECURE_LAUNCH -ne "1" -or -not (Test-ProtectedDirectoryAcl -Path $PSScriptRoot -AllowCurrentUserForUserScope)) {
        $actions.Add((Get-CleanupText "cleanupReport.action.secureLaunchBlocked"))
    } elseif ([int]$verification.ScanWarningCount -gt 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.scanWarningBlocked"))
    } elseif (-not $DeepClean) {
        $actions.Add((Get-CleanupText "cleanupReport.action.selectionRequired" @($releaseVersion)))
    } elseif (-not $script:SelectionAccepted -or $selectedCleanupIds.Count -eq 0) {
        $actions.Add((Get-CleanupText "cleanupReport.action.selectionMissing"))
        if (-not [string]::IsNullOrWhiteSpace([string]$script:SelectionErrorCode)) {
            $actions.Add((Get-CleanupText 'cleanupReport.action.selectionRejectedDetail' @([string]$script:SelectionErrorCode)))
        }
    } elseif ($crackDetected) {
        $selectedCandidates = @($cleanupItems | Where-Object { $selectedCleanupIds -contains ([string]$_.Id).ToLowerInvariant() })
        $selectedThirdPartySnapshots = @($selectedCandidates | Where-Object {
            [string]$_.Type -eq 'Application' -and [string]$_.Kind -eq 'ThirdPartyLicenseReset'
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                Id=[string]$_.Id; TargetId=[string]$_.TargetId; VendorScope=[string]$_.VendorScope
                Location=[string]$_.Location; Name=[string]$_.Name; ApplicationIds=@($_.ApplicationIds)
            }
        })
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

        if ($DryRun) {
            $plannedActions = @(Get-DryRunRemediationPlan -Candidates $cleanupItems -SelectedIds $selectedCleanupIds -SkipRestorePoint:$NoRestorePoint)
            $actions.Add((Get-CleanupText 'cleanupReport.dryRun.noChanges'))
            foreach ($plannedAction in $plannedActions) {
                $actions.Add((Get-CleanupText 'cleanupReport.dryRun.planLine' @($plannedAction.Order, $plannedAction.Action, $plannedAction.Target)))
            }
        } else {
        if (-not $NoRestorePoint) {
            try {
                Checkpoint-Computer -Description (Get-CleanupText "cleanupReport.restorePoint.selectedDescription" @($releaseVersion)) -RestorePointType "MODIFY_SETTINGS" | Out-Null
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedRestorePointCreated"))
            } catch {
                $actions.Add((Get-CleanupText "cleanupReport.action.selectedRestorePointFailed" @($_.Exception.Message)))
            }
        }

        # Sao lưu/cách ly và ký manifest trước. Chỉ sau khi bước này thành công
        # mới cho phép thay đổi product key đã được người dùng chọn.
        $deepResult = Invoke-DeepCleanupV35 -Candidates $cleanupItems -SelectedIds $selectedCleanupIds
        $backupDirectory = [string]$deepResult.BackupDirectory
        if ($deepResult.PSObject.Properties['SystemChangeCount']) { $systemChangeCount += [int]$deepResult.SystemChangeCount }
        if ($deepResult.PSObject.Properties['ThirdPartyExecutionResults']) { $thirdPartyExecutionResults = @($deepResult.ThirdPartyExecutionResults) }
        foreach ($deepAction in @($deepResult.Actions)) { $actions.Add([string]$deepAction) }
        if ($backupDirectory) {
            $basicResult = Invoke-Remediation -Products $products -Findings $findings `
                -CleanupActivator:$false `
                -CleanupKmsConfiguration:$false `
                -WindowsProductsToRemove $(if ($removeWindowsLicense) { $windowsProductsToRemove } else { @() }) `
                -SkipRestorePoint `
                -OfficeEntries $officeEntriesToClean
            $basicActions = @($basicResult.Actions)
            foreach ($basicAction in $basicActions) { $actions.Add([string]$basicAction) }
            $systemChangeCount += [int]$basicResult.SystemChangeCount
        } else {
            $actions.Add((Get-CleanupText "cleanupReport.action.productKeyBlocked"))
        }
        }
    } else {
        $actions.Add((Get-CleanupText "cleanupReport.action.noThreatNoChange"))
    }

    # Luôn quét lại sau xử lý. Chỉ kết luận sẵn sàng kích hoạt chính thức khi
    # không còn dấu hiệu đang hoạt động hoặc cấu hình KMS chưa phê duyệt.
    Reset-ScanCaches
    $script:ScanWarnings.Clear()
    $script:WindowsLicenseSourceNote = ""
    $products = @($(if ($includeWindowsOfficeScan) { Get-WindowsLicenseProducts }))
    $findings = @($(if ($includeWindowsOfficeScan) { Get-ActivatorFindings }))
    $officeKmsEntries = @($(if ($includeWindowsOfficeScan) { Get-OfficeKmsEntries }))
    $installedApplications = @($(if ($includeThirdPartyScan) { Get-InstalledSoftwareInventory }))
    $softwareCatalog = if ($includeThirdPartyScan) { Get-ToolSoftwareLicenseCatalog -PreferCache } else { $null }
    $thirdPartyEvidence = @($(if ($includeThirdPartyScan) { Get-ThirdPartyStrongEvidence -Applications $installedApplications -Catalog $softwareCatalog }))
    $thirdPartyApplications = @($(if ($includeThirdPartyScan) {
        Get-ToolSoftwareAssessments `
            -Applications @($installedApplications | Where-Object {
                -not ([bool]$_.IsMicrosoft -and [string]$_.Name -match '(?i)\bWindows\b|\bOffice\b|\bMicrosoft\s*365\b')
            }) `
            -Catalog $softwareCatalog -ExternalEvidence $thirdPartyEvidence -DeepScan:$deepSoftwareScanEnabled `
            -DeepScanMaximumDurationSeconds $DeepSoftwareScanTimeoutSeconds `
            -DeepScanMaximumSignatureChecks $DeepSoftwareScanMaximumSignatureChecks `
            -DeepScanMaximumHashChecks $DeepSoftwareScanMaximumHashChecks
    }))
    $softwareDeepScanMetadata = Get-ToolSoftwareLastDeepScanMetadata
    $thirdPartyCandidates = @(Get-ThirdPartyLicenseCandidates -Applications $thirdPartyApplications -Evidence $thirdPartyEvidence)
    Connect-ThirdPartyApplicationsToCandidates -Applications $thirdPartyApplications -Candidates $thirdPartyCandidates
    $allCleanupItems = @(Get-AllCleanupCandidates -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -ThirdPartyCandidates $thirdPartyCandidates)
    $cleanupItems = @(Get-ScopedCleanupCandidates -CleanupItems $allCleanupItems -Scope $ScanScope)
    $history = @($(if ($includeWindowsOfficeScan) { Get-InvalidActivationHistory }))
    $verification = Get-CleanupVerification -Products $products -Findings $findings -OfficeEntries $officeKmsEntries -History $history -Scope $ScanScope
    $verification = Add-ThirdPartyVerification -Verification $verification -ThirdPartyCandidates $thirdPartyCandidates -ThirdPartyApplications $thirdPartyApplications
    $scopeReadyForOriginalState = Test-CleanupScopeReady -Verification $verification -Scope $ScanScope
    $postProtectedLicense = if ($includeWindowsOfficeScan) { Get-ProtectedLicenseInfo -Products $products } else {
        [pscustomobject]@{ Protected=$false; Channel=(Get-CleanupText 'common.unknown'); Reason=(Get-CleanupText 'cleanupReport.protected.none') }
    }
    $postActiveProduct = $products | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    $postActiveChannel = if ($postActiveProduct) { Get-LicenseChannel $postActiveProduct } else { Get-CleanupText "common.unknown" }
    $postCrackDetected = [bool]([int]$verification.ActiveActivatorFindingCount -gt 0 -or [int]$verification.UnapprovedWindowsKmsCount -gt 0 -or [int]$verification.UnapprovedOfficeKmsCount -gt 0 -or [int]$verification.ThirdPartyRemediationFindingCount -gt 0 -or @($thirdPartyCandidates).Count -gt 0)
    $thirdPartyChangedCount = [int]@($thirdPartyExecutionResults | Where-Object { [bool]$_.Changed }).Count
    $thirdPartyFailedCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'Failed' }).Count
    $thirdPartyGuidanceOnlyCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'GuidanceOnly' }).Count
    $remainingSelectedThirdPartyIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($snapshot in @($selectedThirdPartySnapshots)) {
        $snapshotApplicationIds = @($snapshot.ApplicationIds | ForEach-Object { [string]$_ } | Where-Object { $_ })
        $matchedPostCandidate = @($thirdPartyCandidates | Where-Object {
            $sameId = [string]::Equals([string]$_.Id, [string]$snapshot.Id, [StringComparison]::OrdinalIgnoreCase)
            $sameTarget = -not [string]::IsNullOrWhiteSpace([string]$snapshot.TargetId) -and
                [string]::Equals([string]$_.TargetId, [string]$snapshot.TargetId, [StringComparison]::OrdinalIgnoreCase)
            $applicationOverlap = [bool](@($_.ApplicationIds | Where-Object { $snapshotApplicationIds -contains [string]$_ }).Count -gt 0)
            $sameScopedLocation = -not [string]::IsNullOrWhiteSpace([string]$snapshot.VendorScope) -and
                [string]::Equals([string]$_.VendorScope, [string]$snapshot.VendorScope, [StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.Location, [string]$snapshot.Location, [StringComparison]::OrdinalIgnoreCase)
            $sameId -or $sameTarget -or $applicationOverlap -or $sameScopedLocation
        } | Select-Object -First 1)
        if ($matchedPostCandidate.Count -gt 0) { [void]$remainingSelectedThirdPartyIds.Add([string]$snapshot.Id) }
    }
    $selectedThirdPartyRemainingCount = [int]$remainingSelectedThirdPartyIds.Count
    $selectedThirdPartyResolvedCount = [int]([Math]::Max(0, @($selectedThirdPartySnapshots).Count - $selectedThirdPartyRemainingCount))
    foreach ($execution in @($thirdPartyExecutionResults)) {
        $parentId = [string]$execution.ParentCandidateId
        $postCheckStatus = if (-not [string]::IsNullOrWhiteSpace($parentId) -and $remainingSelectedThirdPartyIds.Contains($parentId)) { 'ResidualRemaining' } else { 'Resolved' }
        $execution | Add-Member -NotePropertyName PostCheckStatus -NotePropertyValue $postCheckStatus -Force
    }
    $postReadyForCurrentScope = [bool]$(if ($ScanScope -eq 'ThirdParty') { $scopeReadyForOriginalState } else { $verification.ReadyForOfficialActivation })
    $postDecisionCode = if (-not $DeepClean -or -not $script:SelectionAccepted) {
        'SelectionRejected'
    } elseif ($DryRun) {
        'DryRunCompleted'
    } elseif ($thirdPartyFailedCount -gt 0) {
        'RemediationFailed'
    } elseif ($selectedCleanupIds.Count -gt 0 -and $systemChangeCount -eq 0 -and $thirdPartyGuidanceOnlyCount -gt 0) {
        'NoAutomaticChange'
    } elseif ($postReadyForCurrentScope) {
        'PostCheckPassed'
    } else {
        'ResidueRemaining'
    }
    $postDecisionText = switch ($postDecisionCode) {
        'SelectionRejected' { Get-CleanupText 'cleanupReport.decision.selectionRejected' }
        'DryRunCompleted' { Get-CleanupText 'cleanupReport.dryRun.completed' }
        'RemediationFailed' { Get-CleanupText 'cleanupReport.decision.remediationFailed' }
        'NoAutomaticChange' { Get-CleanupText 'cleanupReport.decision.noAutomaticChange' }
        'PostCheckPassed' { Get-CleanupText 'cleanupReport.decision.postCheckPassed' }
        default { Get-CleanupText 'cleanupReport.decision.residueRemaining' }
    }
    $postConclusion = switch ($postDecisionCode) {
        'SelectionRejected' { Get-CleanupText 'cleanupReport.action.selectionRejectedDetail' @([string]$script:SelectionErrorCode) }
        'RemediationFailed' { Get-CleanupText 'cleanupReport.decision.remediationFailedDetail' @($thirdPartyFailedCount) }
        default { [string]$verification.Conclusion }
    }
    $finalDecisionCode = [string]$postDecisionCode
    $finalDecisionText = [string]$postDecisionText
    $finalCleanupConclusion = [string]$postConclusion
    $postExecutionAccepted = [bool]($postDecisionCode -notin @('SelectionRejected','RemediationFailed'))
    $finalReadyForOfficialActivation = [bool]($verification.ReadyForOfficialActivation -and $postExecutionAccepted)
    $finalScopeReadyForOriginalState = [bool]($scopeReadyForOriginalState -and $postExecutionAccepted)
    if (-not $DryRun) { $actions.Add((Get-CleanupText "cleanupReport.action.postCheck" @($verification.Conclusion))) }
    $decisionData = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.8" -Data ([ordered]@{
        ScanScope = $ScanScope
        CrackDetected = $postCrackDetected
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
        InstalledApplicationCount = [int]$installedApplications.Count
        ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
        ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
        ThirdPartyCandidateCount = [int]$verification.ThirdPartyCandidateCount
        ThirdPartyAutoEligibleCount = [int]$verification.ThirdPartyAutoEligibleCount
        ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
        ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
        ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
        ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
        ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
        SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
        SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
        SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
        DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
        DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
        DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
        DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
        DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
        DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
        DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
        DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
        DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
        DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
        DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
        DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
        DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
        DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
        DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
        DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
        DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
        DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
        ThirdPartyApplications = @($thirdPartyApplications)
        ThirdPartyEvidence = @($thirdPartyEvidence)
        ThirdPartyCandidates = @($thirdPartyCandidates)
        ThirdPartyChangedCount = $thirdPartyChangedCount
        ThirdPartyFailedCount = $thirdPartyFailedCount
        ThirdPartyGuidanceOnlyCount = $thirdPartyGuidanceOnlyCount
        SelectedThirdPartyCandidateCount = [int]@($selectedThirdPartySnapshots).Count
        SelectedThirdPartyResolvedCount = [int]$selectedThirdPartyResolvedCount
        SelectedThirdPartyRemainingCount = [int]$selectedThirdPartyRemainingCount
        ApprovedOfficeKmsCount = [int]($officeKmsEntries.Count - $verification.UnapprovedOfficeKmsCount)
        ApprovedKmsServerFile = [string]$approvedKmsConfig.Path
        ApprovedKmsServerCount = [int]$approvedKmsConfig.Valid.Count
        InvalidApprovedKmsCount = [int]$approvedKmsConfig.Invalid.Count
        ApprovedKmsConfigWarning = [string]$approvedKmsConfig.Warning
        DecisionCode = $postDecisionCode
        Decision = $postDecisionText
        Reason = [string]$postConclusion
        ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
        ScopeReadyForOriginalState = [bool]$finalScopeReadyForOriginalState
        ReadinessReviewCount = [int]$verification.ReadinessReviewCount
        ScanWarningCount = [int]$verification.ScanWarningCount
        ScanWarnings = $verification.ScanWarnings
        ReadinessChecks = $verification.ReadinessChecks
        DeepCleanupApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
        SystemChangeApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
        SystemChangeCount = [int]$systemChangeCount
        ThirdPartyExecutionResults = @($thirdPartyExecutionResults)
        DryRunRequested = [bool]$DryRun
        SimulationOnly = [bool]$DryRun
        NoSystemChangesApplied = [bool]($DryRun -or $systemChangeCount -eq 0)
        PlannedActionCount = [int]@($plannedActions).Count
        PlannedActions = @($plannedActions)
        SelectedCleanupIds = @($selectedCleanupIds)
        SelectionAccepted = [bool]$script:SelectionAccepted
        SelectionErrorCode = [string]$script:SelectionErrorCode
        SelectionErrorDetail = [string]$script:SelectionErrorDetail
        UnknownSelectedCleanupIdCount = [int]$unknownSelectedCleanupIds.Count
        BackupWouldBeCreated = [bool](@($plannedActions | Where-Object { [bool]$_.BackupPlanned }).Count -gt 0)
        CleanupItems = $cleanupItems
        SelectionRequired = [bool]($cleanupItems.Count -gt 0)
        SelectedCleanupItemCount = [int]$selectedCleanupIds.Count
        BackupDirectory = [string]$backupDirectory
        CleanupConclusion = [string]$postConclusion
        HandlingGuidance = $verification.HandlingGuidance
        NextActions = @(Get-CleanupNextActions -Verification $verification -CleanupItems $cleanupItems -ProtectedLicense ([bool]$postProtectedLicense.Protected) -BackupDirectory $backupDirectory)
        ScopeNote = [string]$verification.ScopeNote
        ReportPath = [string]$reportPath
        Actions = @($actions)
    })
    Write-DecisionData -Path $DecisionFile -Data $decisionData
}

$reportVerification = $verification.PSObject.Copy()
$reportVerification.ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
$reportVerification.Conclusion = [string]$finalCleanupConclusion
Write-Report -Path $reportPath -Products $products -Findings $findings -Decision $decision -Actions $actions -History $history -Verification $reportVerification -ThirdPartyApplications $thirdPartyApplications -ThirdPartyEvidence $thirdPartyEvidence -ThirdPartyCandidates $thirdPartyCandidates -SoftwareDeepScanMetadata $softwareDeepScanMetadata

# Bộ tóm tắt máy đọc được và hash đi kèm giúp đối chiếu hậu kiểm mà không
# thay đổi luồng xử lý v3.0. Không ghi product key đầy đủ vào JSON.
$jsonReportPath = [IO.Path]::ChangeExtension($reportPath, ".json")
$hashReportPath = [IO.Path]::ChangeExtension($reportPath, ".sha256")
$cleanupSummary = New-ToolReportEnvelope -ReportKind "CleanupCompliance" -ToolVersion "4.8" -Data ([ordered]@{
    ScanScope = $ScanScope
    ComputerName = $reportComputer
    CreatedAt = (Get-Date).ToString("o")
    Redacted = [bool]$RedactSensitive
    Remediate = [bool]$Remediate
    DeepClean = [bool]$DeepClean
    DryRunRequested = [bool]$DryRun
    SimulationOnly = [bool]$DryRun
    NoSystemChangesApplied = [bool]($DryRun -or $systemChangeCount -eq 0)
    SystemChangeApplied = [bool](-not $DryRun -and $systemChangeCount -gt 0)
    SystemChangeCount = [int]$systemChangeCount
    ThirdPartyExecutionResults = @($thirdPartyExecutionResults)
    ThirdPartyChangedCount = [int]@($thirdPartyExecutionResults | Where-Object { [bool]$_.Changed }).Count
    ThirdPartyFailedCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'Failed' }).Count
    ThirdPartyGuidanceOnlyCount = [int]@($thirdPartyExecutionResults | Where-Object { [string]$_.Status -eq 'GuidanceOnly' }).Count
    SelectedThirdPartyCandidateCount = [int]@($selectedThirdPartySnapshots).Count
    SelectedThirdPartyResolvedCount = [int]$selectedThirdPartyResolvedCount
    SelectedThirdPartyRemainingCount = [int]$selectedThirdPartyRemainingCount
    PlannedActionCount = [int]@($plannedActions).Count
    PlannedActions = @($plannedActions)
    SelectedCleanupIds = @($selectedCleanupIds)
    SelectionAccepted = [bool]$script:SelectionAccepted
    SelectionErrorCode = [string]$script:SelectionErrorCode
    SelectionErrorDetail = [string]$script:SelectionErrorDetail
    UnknownSelectedCleanupIdCount = [int]$unknownSelectedCleanupIds.Count
    BackupWouldBeCreated = [bool](@($plannedActions | Where-Object { [bool]$_.BackupPlanned }).Count -gt 0)
    DecisionCode = [string]$finalDecisionCode
    Decision = [string]$finalDecisionText
    ReadyForOfficialActivation = [bool]$finalReadyForOfficialActivation
    ScopeReadyForOriginalState = [bool]$finalScopeReadyForOriginalState
    CleanupConclusion = [string]$finalCleanupConclusion
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
    InstalledApplicationCount = [int]$installedApplications.Count
    ThirdPartyApplicationCount = [int]$thirdPartyApplications.Count
    ThirdPartyEvidenceCount = [int]$thirdPartyEvidence.Count
    ThirdPartyCandidateCount = [int]$verification.ThirdPartyCandidateCount
    ThirdPartyAutoEligibleCount = [int]$verification.ThirdPartyAutoEligibleCount
    ThirdPartyNeedsReviewCount = [int]@($thirdPartyApplications | Where-Object { [bool]$_.NeedsReview }).Count
    ThirdPartyRemediationFindingCount = [int]$verification.ThirdPartyRemediationFindingCount
    ThirdPartyNonGenuineCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'NonGenuine' }).Count
    ThirdPartySuspiciousCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -eq 'Suspicious' }).Count
    ThirdPartyUnverifiedCount = [int]@($thirdPartyApplications | Where-Object { [string]$_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count
    SoftwareCatalogSource = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogSource } else { 'Unavailable' })
    SoftwareCatalogVersion = $(if ($softwareCatalog) { [string]$softwareCatalog.CatalogVersion } else { '' })
    SoftwareCatalogRuleCount = $(if ($softwareCatalog) { [int]@($softwareCatalog.Products).Count } else { 0 })
    DeepSoftwareScanEnabled = [bool]$softwareDeepScanMetadata.Enabled
    DeepSoftwareScanComplete = [bool]$softwareDeepScanMetadata.Complete
    DeepSoftwareScanAdministrator = [bool]$softwareDeepScanMetadata.IsAdministrator
    DeepSoftwareScanApplicationsScanned = [int]$softwareDeepScanMetadata.ApplicationsScanned
    DeepSoftwareScanApplicationsSkipped = [int]$softwareDeepScanMetadata.ApplicationsSkipped
    DeepSoftwareScanUniqueRoots = [int]$softwareDeepScanMetadata.UniqueRootsScanned
    DeepSoftwareScanRootCacheHits = [int]$softwareDeepScanMetadata.RootCacheHits
    DeepSoftwareScanTotalEntries = [int]$softwareDeepScanMetadata.TotalEntries
    DeepSoftwareScanRelevantFiles = [int]$softwareDeepScanMetadata.RelevantFiles
    DeepSoftwareScanSignatureChecks = [int]$softwareDeepScanMetadata.SignatureChecks
    DeepSoftwareScanHashChecks = [int]$softwareDeepScanMetadata.HashChecks
    DeepSoftwareScanEvidenceCount = [int]$softwareDeepScanMetadata.EvidenceCount
    DeepSoftwareScanDurationMilliseconds = [int]$softwareDeepScanMetadata.DurationMilliseconds
    DeepSoftwareScanTimeLimitReached = [bool]$softwareDeepScanMetadata.TimeLimitReached
    DeepSoftwareScanEntryLimitReached = [bool]$softwareDeepScanMetadata.EntryLimitReached
    DeepSoftwareScanSignatureLimitReached = [bool]$softwareDeepScanMetadata.SignatureLimitReached
    DeepSoftwareScanHashLimitReached = [bool]$softwareDeepScanMetadata.HashLimitReached
    DeepSoftwareScanAccessWarningCount = [int]$softwareDeepScanMetadata.AccessWarningCount
    ThirdPartyApplications = @($thirdPartyApplications)
    ThirdPartyEvidence = @($thirdPartyEvidence)
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
$cleanupSummaryValidation = Test-ToolReportEnvelope -Report $cleanupSummary -ExpectedReportKind "CleanupCompliance" -ExpectedToolVersion "4.8"
if (-not $cleanupSummaryValidation.Valid) { throw (Get-CleanupText "cleanupReport.output.schemaInvalid" @($cleanupSummaryValidation.Errors -join '; ')) }
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

Write-Host (Get-CleanupText "cleanupReport.output.report" @($reportPath))
Write-Host (Get-CleanupText "cleanupReport.output.json" @($jsonReportPath))
Write-Host (Get-CleanupText "cleanupReport.output.sha256" @($hashReportPath))
if ($approvedKmsConfig.Warning) { Write-Warning $approvedKmsConfig.Warning }
Write-Host (Get-CleanupText "cleanupReport.output.decision" @($decision.Decision))
Write-Host (Get-CleanupText "cleanupReport.output.reason" @($decision.Reason))
if ($Remediate) {
    $yes = Get-CleanupText "common.yes"
    $no = Get-CleanupText "common.no"
    Write-Host (Get-CleanupText "cleanupReport.output.actionCount" @($actions.Count))
    Write-Host (Get-CleanupText "cleanupReport.output.ready" @($(if ($verification.ReadyForOfficialActivation) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.deepRequested" @($(if ($DeepClean) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.backupApplied" @($(if ($decisionData.DeepCleanupApplied) { $yes } else { $no })))
    Write-Host (Get-CleanupText "cleanupReport.output.conclusion" @($verification.Conclusion))
    if (-not $DryRun -and -not $verification.ReadyForOfficialActivation) {
        exit 4
    }
}
if ($DryRun) { exit 0 }
if ($decision.DecisionCode -eq "ManualReview") {
    exit 2
}
if ($decision.ShouldRemediate -and -not $Remediate) {
    exit 3
}
exit 0




