[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 24000)]
    [string]$PayloadBase64
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$bridgeFailureExitCode = 87

function Get-BridgeAccountSid {
    param([string]$Account)
    try {
        return (New-Object Security.Principal.NTAccount($Account)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        return ''
    }
}

function Test-BridgeProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('User','Machine')][string]$DataScope
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ownerSid = Get-BridgeAccountSid ([string]$acl.Owner)
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $allowedOwners = @('S-1-5-32-544','S-1-5-18')
        $allowedWriters = @('S-1-5-32-544','S-1-5-18')
        if ($DataScope -eq 'User') {
            $allowedOwners += $currentUserSid
            $allowedWriters += $currentUserSid
        }
        if ($ownerSid -notin $allowedOwners -or -not $acl.AreAccessRulesProtected) { return $false }
        $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
            [Security.AccessControl.FileSystemRights]::Modify -bor
            [Security.AccessControl.FileSystemRights]::FullControl -bor
            [Security.AccessControl.FileSystemRights]::Delete -bor
            [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
            [Security.AccessControl.FileSystemRights]::TakeOwnership
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $allowedWriters -notcontains $rule.IdentityReference.Value -and
                (($rule.FileSystemRights -band $writeMask) -ne 0)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'ElevatedBridgeArchitectureMismatch' }
    $payloadBytes = [Convert]::FromBase64String($PayloadBase64)
    if ($payloadBytes.Length -le 0 -or $payloadBytes.Length -gt 18000) { throw 'ElevatedBridgePayloadSizeInvalid' }
    $payload = [Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json
    if ([string]$payload.SchemaVersion -ne '1.0') { throw 'ElevatedBridgeSchemaInvalid' }

    $createdAtUtc = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$payload.CreatedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$createdAtUtc)) {
        throw 'ElevatedBridgeTimestampInvalid'
    }
    $age = [DateTimeOffset]::UtcNow - $createdAtUtc.ToUniversalTime()
    if ($age.TotalMinutes -lt -5 -or $age.TotalMinutes -gt 15) { throw 'ElevatedBridgeExpired' }

    $allowedEnvironmentNames = @(
        'TOOL_APPROVED_KMS_FILE','TOOL_BUILD_ARCHITECTURE','TOOL_CAPABILITY_SCHEMA',
        'TOOL_COMPATIBILITY_CATALOG','TOOL_COMPATIBILITY_SCHEMA','TOOL_CORRELATION_ID',
        'TOOL_DASHBOARD_SCHEMA','TOOL_DATA_ROOT','TOOL_DATA_SCHEMA_VERSION','TOOL_DATA_SCOPE',
        'TOOL_ENTERPRISE_NETWORK_ALLOWED','TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH','TOOL_ENTERPRISE_ROOT',
        'TOOL_ENTERPRISE_SCHEMA','TOOL_EXPECTED_PROCESS_ARCHITECTURE','TOOL_LAUNCHER_PATH',
        'TOOL_LAUNCHER_PID','TOOL_LAUNCH_MODE','TOOL_LEGACY_DATA_ROOT','TOOL_LOCALIZATION_SCHEMA',
        'TOOL_LOG_PATH','TOOL_MODULE_CONTRACT_SCHEMA','TOOL_MODULE_ID','TOOL_MODULE_INVOCATION_ID',
        'TOOL_OFFLINE_MODE','TOOL_OFFLINE_POLICY_SCHEMA','TOOL_OFFLINE_SETTINGS_PATH','TOOL_PLUGIN_DIR',
        'TOOL_POWERSHELL_PATH','TOOL_REPORT_SCHEMA','TOOL_SAFETY_POLICY_SCHEMA','TOOL_SECURE_LAUNCH',
        'TOOL_SECURE_RUNTIME_DIR','TOOL_SECURE_RUNTIME_FAILED','TOOL_TIMELINE_KEY_PATH','TOOL_TIMELINE_PATH',
        'TOOL_TOOL_VERSION','TOOL_UI_CULTURE','TOOL_UI_CULTURE_SETTINGS_PATH','TOOL_UI_THEME',
        'TOOL_UI_THEME_SETTINGS_PATH','TOOL_UPDATE_CACHE_ROOT'
    )
    $environmentValues = @{}
    foreach ($property in @($payload.Environment.PSObject.Properties)) {
        $name = [string]$property.Name
        if ($allowedEnvironmentNames -notcontains $name) { throw 'ElevatedBridgeEnvironmentNameInvalid' }
        $environmentValues[$name] = if ($null -eq $property.Value) { $null } else { [string]$property.Value }
    }
    if ([string]$environmentValues['TOOL_SECURE_LAUNCH'] -ne '1') { throw 'ElevatedBridgeSecureLaunchRequired' }
    $dataScope = [string]$environmentValues['TOOL_DATA_SCOPE']
    if ($dataScope -notin @('User','Machine')) { throw 'ElevatedBridgeDataScopeInvalid' }
    $moduleId = [string]$environmentValues['TOOL_MODULE_ID']
    $invocationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$environmentValues['TOOL_MODULE_INVOCATION_ID'], [ref]$invocationId) -or $invocationId -eq [guid]::Empty) {
        throw 'ElevatedBridgeInvocationIdInvalid'
    }

    $moduleScripts = @{
        'cleanup.scan' = 'windows-license-compliance-cleanup.ps1'
        'cleanup.deep' = 'windows-license-compliance-cleanup.ps1'
        'cleanup.repair' = 'windows-license-compliance-cleanup.ps1'
        'oem.apply' = 'windows-oem-license-assistant.ps1'
        'license.deep-scan' = 'windows-license-deep-scan.ps1'
        'forensics.scan' = 'windows-license-forensics.ps1'
        'license.manager' = 'enterprise-license-manager.ps1'
        'backup.create' = 'windows-license-backup.ps1'
        'restore.apply' = 'windows-license-restore.ps1'
    }
    if (-not $moduleScripts.ContainsKey($moduleId)) { throw 'ElevatedBridgeModuleIdInvalid' }

    $bridgeRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $runtimeRoot = [IO.Path]::GetFullPath((Join-Path $bridgeRoot 'runtime')).TrimEnd('\')
    $declaredRuntimeRoot = [IO.Path]::GetFullPath([string]$environmentValues['TOOL_SECURE_RUNTIME_DIR']).TrimEnd('\')
    if (-not [string]::Equals($runtimeRoot, $declaredRuntimeRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ElevatedBridgeRuntimeMismatch' }
    if (-not (Test-BridgeProtectedDirectoryAcl -Path $bridgeRoot -DataScope $dataScope)) { throw 'ElevatedBridgeToolDirectoryAclInvalid' }
    if (-not (Test-BridgeProtectedDirectoryAcl -Path $runtimeRoot -DataScope $dataScope)) { throw 'ElevatedBridgeRuntimeDirectoryAclInvalid' }

    $targetFilePath = [IO.Path]::GetFullPath([string]$payload.TargetFilePath)
    $expectedPowerShellPath = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'))
    if (-not [string]::Equals($targetFilePath, $expectedPowerShellPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $targetFilePath -PathType Leaf)) { throw 'ElevatedBridgeTargetInvalid' }

    $targetArguments = [string]$payload.TargetArguments
    if ([string]::IsNullOrWhiteSpace($targetArguments) -or $targetArguments.Length -gt 16000 -or $targetArguments -match "[`0`r`n]") {
        throw 'ElevatedBridgeArgumentsInvalid'
    }
    if ($targetArguments -notmatch '(?i)^\s*-NoProfile\s+-ExecutionPolicy\s+RemoteSigned\s+-File\s+"' -or
        $targetArguments -match '(?i)(?:^|\s)-(?:[A-Za-z]*Command|EncodedArguments)\b') {
        throw 'ElevatedBridgeArgumentsInvalid'
    }
    $fileMatches = [regex]::Matches($targetArguments, '(?i)(?:^|\s)-File\s+"([^"]+)"')
    if ($fileMatches.Count -ne 1) { throw 'ElevatedBridgeScriptBindingInvalid' }
    $actualScriptPath = [IO.Path]::GetFullPath([string]$fileMatches[0].Groups[1].Value)
    $expectedScriptPath = [IO.Path]::GetFullPath((Join-Path $bridgeRoot ([string]$moduleScripts[$moduleId])))
    if (-not [string]::Equals($actualScriptPath, $expectedScriptPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $actualScriptPath -PathType Leaf)) { throw 'ElevatedBridgeScriptBindingInvalid' }
    $scriptItem = Get-Item -LiteralPath $actualScriptPath -Force -ErrorAction Stop
    if (($scriptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ElevatedBridgeScriptReparsePointRejected' }

    # Do not use Start-Process/ShellExecute for this second hop.  On a real
    # RunAs boundary Windows can ask the shell broker to create the child;
    # that broker then supplies its own environment instead of the values
    # restored in this elevated bridge.  The cleanup process consequently
    # sees TOOL_SECURE_LAUNCH as empty and rejects the signed selection file.
    #
    # UseShellExecute=false makes this process create the child directly and
    # lets us attach the reviewed TOOL_* contract as an explicit environment
    # block.  All other ordinary Windows variables remain inherited from the
    # already-elevated bridge.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $targetFilePath
    $startInfo.Arguments = $targetArguments
    $startInfo.WorkingDirectory = $bridgeRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = [bool]$payload.HiddenWindow
    if ([bool]$payload.HiddenWindow) {
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    }
    foreach ($name in $allowedEnvironmentNames) {
        if ($environmentValues.ContainsKey($name) -and $null -ne $environmentValues[$name]) {
            $startInfo.EnvironmentVariables[$name] = [string]$environmentValues[$name]
        } else {
            [void]$startInfo.EnvironmentVariables.Remove($name)
        }
    }

    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $startInfo
    if (-not $child.Start()) { throw 'ElevatedBridgeChildMissing' }
    try {
        $child.WaitForExit()
        $childExitCode = [int]$child.ExitCode
    } finally {
        $child.Dispose()
    }
    exit $childExitCode
} catch {
    [Console]::Error.WriteLine('Tool elevated bridge failed: ' + [string]$_.Exception.Message)
    exit $bridgeFailureExitCode
}
