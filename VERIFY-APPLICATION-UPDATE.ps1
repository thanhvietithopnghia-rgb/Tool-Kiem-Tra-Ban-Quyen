[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)

function Assert-UpdateTest {
    param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-UpdateThrows {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$oldOfflineMode = [string]$env:TOOL_OFFLINE_MODE
$oldUpdateCacheRoot = [string]$env:TOOL_UPDATE_CACHE_ROOT
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('tool-v470-update-verify-' + [Guid]::NewGuid().ToString('N'))

try {
    foreach ($name in @(
        'Tool-UpdateManager.ps1', 'Giao-Dien.ps1', 'Tool-OfflinePolicy.ps1', 'Tool-ModuleContract.ps1',
        'Tool-Kiem-Tra-v4.8-OneFile.cs', 'BUILD.ps1', 'Tool-Strings.vi-VN.json', 'Tool-Strings.en-US.json'
    )) {
        Assert-UpdateTest (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf) "Missing update component: $name"
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $env:TOOL_OFFLINE_MODE = '1'
    $env:TOOL_UPDATE_CACHE_ROOT = Join-Path $temporaryRoot 'cache'

    $updateManagerPath = Join-Path $root 'Tool-UpdateManager.ps1'
    . $updateManagerPath -Mode Library -Culture 'vi-VN'
    Assert-UpdateTest ($script:ToolUpdateToolVersion -eq '4.8.0.1') 'Updater foundation version is invalid.'
    Assert-UpdateTest ($script:ToolUpdateDefaultManifestUrl -eq 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json') 'Stable manifest URL is invalid.'

    $manifest = [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Channel = 'stable'
        LatestVersion = '4.8.0.1'
        MinimumUpdaterVersion = '4.8.0.0'
        PublishedAtUtc = '2026-08-08T00:00:00Z'
        Title = [pscustomobject]@{ 'vi-VN'='Test release VI'; 'en-US'='Test release' }
        Changes = [pscustomobject]@{ 'vi-VN'=@('Faster scans VI'); 'en-US'=@('Faster scans') }
        ReleasePageUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.8.0.1'
        DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.8.0.1/Tool-Kiem-Tra-v4.8.exe'
        DownloadSha256 = ('A' * 64)
        DownloadSize = 65536
        AuthenticodeRequired = $true
        SignerThumbprints = @(('C' * 40))
    }
    $candidate = ConvertFrom-ToolUpdateManifest -Manifest $manifest -InstalledVersion '4.8.0.0' -SelectedCulture 'vi-VN' -SourceUrl $script:ToolUpdateDefaultManifestUrl
    Assert-UpdateTest ([bool]$candidate.UpdateAvailable) 'A newer version was not detected.'
    Assert-UpdateTest ([bool]$candidate.CanSelfUpdate) 'v4.8.0 must support self-update.'
    Assert-UpdateTest ($candidate.LatestVersion -eq '4.8.0.1' -and $candidate.Title -eq 'Test release VI') 'Manifest result or localization is invalid.'
    Assert-UpdateTest (-not [bool]$candidate.UploadedMachineData -and -not [bool]$candidate.TelemetrySent) 'Update result privacy flags are invalid.'

    $currentManifest = $manifest.PSObject.Copy()
    $currentManifest.LatestVersion = '4.8.0.1'
    $currentManifest.MinimumUpdaterVersion = '4.8.0.0'
    $currentManifest.ReleasePageUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.8.0.1'
    $currentManifest.DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.8.0.1/Tool-Kiem-Tra-v4.8.exe'
    $current = ConvertFrom-ToolUpdateManifest -Manifest $currentManifest -InstalledVersion '4.8.0.1' -SelectedCulture 'en-US'
    Assert-UpdateTest (-not [bool]$current.UpdateAvailable -and -not [bool]$current.SameVersionReplacement) 'The current version without a verified local hash was incorrectly marked as outdated.'
    $sameBuild = ConvertFrom-ToolUpdateManifest -Manifest $currentManifest -InstalledVersion '4.8.0.1' -InstalledSha256 ('A' * 64) -SelectedCulture 'en-US'
    Assert-UpdateTest (-not [bool]$sameBuild.UpdateAvailable -and -not [bool]$sameBuild.SameVersionReplacement) 'The identical current build was incorrectly offered again.'
    $replacementBuild = ConvertFrom-ToolUpdateManifest -Manifest $currentManifest -InstalledVersion '4.8.0.1' -InstalledSha256 ('B' * 64) -SelectedCulture 'vi-VN'
    Assert-UpdateTest ([bool]$replacementBuild.UpdateAvailable -and [bool]$replacementBuild.SameVersionReplacement) 'A different public build with the same version was not detected.'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $currentManifest -InstalledVersion '4.8.0.1' -InstalledSha256 'INVALID' | Out-Null } 'An invalid installed executable SHA-256 was accepted.'

    $olderManifest = $manifest.PSObject.Copy()
    $olderManifest.LatestVersion = '4.6.2.0'
    $olderManifest.MinimumUpdaterVersion = '4.6.1.0'
    $olderManifest.ReleasePageUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.6.2.0'
    $olderManifest.DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.6.2.0/Tool-Kiem-Tra-v4.6.exe'
    $older = ConvertFrom-ToolUpdateManifest -Manifest $olderManifest -InstalledVersion '4.8.0.1' -InstalledSha256 ('B' * 64) -SelectedCulture 'vi-VN'
    Assert-UpdateTest (-not [bool]$older.UpdateAvailable) 'An older release was incorrectly offered as a downgrade.'

    $upgradeManifest = $manifest.PSObject.Copy()
    $upgradeManifest.LatestVersion = '4.8.0.1'
    $upgradeManifest.MinimumUpdaterVersion = '4.6.2.0'
    $upgradeManifest.ReleasePageUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.8.0.1'
    $upgradeManifest.DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.8.0.1/Tool-Kiem-Tra-v4.8.exe'
    $upgradeCandidate = ConvertFrom-ToolUpdateManifest -Manifest $upgradeManifest -InstalledVersion '4.6.2.0' -SelectedCulture 'vi-VN'
    Assert-UpdateTest ([bool]$upgradeCandidate.UpdateAvailable -and [bool]$upgradeCandidate.CanSelfUpdate) 'v4.6.2 cannot self-update to v4.8.0.'

    $foundationGateManifest = $manifest.PSObject.Copy()
    $foundationGate = ConvertFrom-ToolUpdateManifest -Manifest $foundationGateManifest -InstalledVersion '4.6.2.0' -SelectedCulture 'vi-VN'
    Assert-UpdateTest ([bool]$foundationGate.UpdateAvailable -and -not [bool]$foundationGate.CanSelfUpdate) 'MinimumUpdaterVersion did not block an unsupported updater foundation.'

    $badManifest = $manifest.PSObject.Copy()
    $badManifest.DownloadUrl = 'https://example.com/releases/download/v4.8.0.1/Tool-Kiem-Tra-v4.8.exe'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badManifest -InstalledVersion '4.8.0.0' | Out-Null } 'A download host outside the allowlist was accepted.'
    $badAssetManifest = $manifest.PSObject.Copy()
    $badAssetManifest.DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.8.0.1/Other-Tool.exe'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badAssetManifest -InstalledVersion '4.8.0.0' | Out-Null } 'A release asset with the wrong executable name was accepted.'
    $badTagManifest = $manifest.PSObject.Copy()
    $badTagManifest.DownloadUrl = 'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/download/v4.7.0.0/Tool-Kiem-Tra-v4.8.exe'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badTagManifest -InstalledVersion '4.8.0.0' | Out-Null } 'A download URL with the wrong release tag was accepted.'
    $badHashManifest = $manifest.PSObject.Copy()
    $badHashManifest.DownloadSha256 = '1234'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badHashManifest -InstalledVersion '4.8.0.0' | Out-Null } 'An invalid SHA-256 value was accepted.'
    $badSizeManifest = $manifest.PSObject.Copy()
    $badSizeManifest.DownloadSize = 1024
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badSizeManifest -InstalledVersion '4.8.0.0' | Out-Null } 'An unsafe executable size was accepted.'
    $badSignerManifest = $manifest.PSObject.Copy()
    $badSignerManifest.SignerThumbprints = @('NOT-A-THUMBPRINT')
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badSignerManifest -InstalledVersion '4.8.0.0' | Out-Null } 'An invalid signer thumbprint was accepted.'
    $missingSignerManifest = $manifest.PSObject.Copy()
    $missingSignerManifest.AuthenticodeRequired = $true
    $missingSignerManifest.SignerThumbprints = @()
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $missingSignerManifest -InstalledVersion '4.8.0.0' | Out-Null } 'A signed release requirement without a trusted signer was accepted.'
    $unsignedStableManifest = $manifest.PSObject.Copy()
    $unsignedStableManifest.AuthenticodeRequired = $false
    $unsignedStableManifest.SignerThumbprints = @()
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $unsignedStableManifest -InstalledVersion '4.8.0.0' | Out-Null } 'An unsigned stable update manifest was accepted.'
    Assert-UpdateThrows { Assert-ToolUpdateManifestUri ([uri]($script:ToolUpdateDefaultManifestUrl + '?redirect=1')) | Out-Null } 'A manifest URL with a query was accepted.'
    Assert-UpdateThrows { Assert-ToolUpdateReleaseUri ([uri]'https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v4.8.0.0?x=1') | Out-Null } 'A release URL with a query was accepted.'
    $badBooleanManifest = $manifest.PSObject.Copy()
    $badBooleanManifest.AuthenticodeRequired = 'false'
    Assert-UpdateThrows { ConvertFrom-ToolUpdateManifest -Manifest $badBooleanManifest -InstalledVersion '4.8.0.0' | Out-Null } 'A string AuthenticodeRequired value was accepted.'

    $deniedResultPath = Join-Path $temporaryRoot 'denied-result.json'
    $verificationPowerShell = Join-Path $PSHOME 'powershell.exe'
    $deniedArguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$updateManagerPath`" -Mode Check -CurrentVersion 4.8.0.0 -ResultFile `"$deniedResultPath`""
    $deniedProcess = Start-Process -FilePath $verificationPowerShell -ArgumentList $deniedArguments -WindowStyle Hidden -Wait -PassThru
    Assert-UpdateTest ($deniedProcess.ExitCode -eq 2) 'Updater did not fail closed without consent or while Offline.'
    Assert-UpdateTest (-not (Test-Path -LiteralPath $deniedResultPath)) 'Updater wrote a result after the pre-network gate denied execution.'
    $offlineConsentArguments = $deniedArguments + ' -ConsentGranted'
    $offlineConsentProcess = Start-Process -FilePath $verificationPowerShell -ArgumentList $offlineConsentArguments -WindowStyle Hidden -Wait -PassThru
    Assert-UpdateTest ($offlineConsentProcess.ExitCode -eq 2) 'Updater accepted consent while the tool remained Offline.'
    $env:TOOL_OFFLINE_MODE = '0'
    $onlineNoConsentProcess = Start-Process -FilePath $verificationPowerShell -ArgumentList $deniedArguments -WindowStyle Hidden -Wait -PassThru
    Assert-UpdateTest ($onlineNoConsentProcess.ExitCode -eq 2) 'Updater checked Online without explicit consent.'
    $env:TOOL_OFFLINE_MODE = '1'

    $stagedPath = Join-Path $temporaryRoot 'staged.exe'
    $targetPath = Join-Path $temporaryRoot 'Tool-Kiem-Tra-v4.8.exe'
    $cacheDirectory = Join-Path $temporaryRoot 'install-cache'
    New-Item -ItemType Directory -Path $cacheDirectory | Out-Null
    $newBytes = New-Object byte[] 65536
    $newBytes[0] = 0x4D
    $newBytes[1] = 0x5A
    for ($index = 2; $index -lt $newBytes.Length; $index++) { $newBytes[$index] = [byte]($index % 251) }
    [IO.File]::WriteAllBytes($stagedPath, $newBytes)
    $newSha256 = Get-ToolUpdateSha256 $stagedPath
    Assert-UpdateTest (Assert-ToolUpdateExecutable -Path $stagedPath -ExpectedSize 65536 -ExpectedSha256 $newSha256 -AuthenticodeRequired $false) 'A valid test EXE was rejected.'
    Assert-UpdateThrows { Assert-ToolUpdateExecutable -Path $stagedPath -ExpectedSize 65535 -ExpectedSha256 $newSha256 -AuthenticodeRequired $false | Out-Null } 'A staged executable with the wrong size was accepted.'
    Assert-UpdateThrows { Assert-ToolUpdateExecutable -Path $stagedPath -ExpectedSize 65536 -ExpectedSha256 ('B' * 64) -AuthenticodeRequired $false | Out-Null } 'A staged executable with the wrong SHA-256 was accepted.'
    Assert-UpdateThrows { Assert-ToolUpdateExecutable -Path $stagedPath -ExpectedSize 65536 -ExpectedSha256 $newSha256 -AuthenticodeRequired $true -SignerThumbprints @(('C' * 40)) | Out-Null } 'An unsigned staged executable was accepted when Authenticode was required.'
    [IO.File]::WriteAllBytes($targetPath, ([Text.Encoding]::UTF8.GetBytes('MZ-old-version')))
    $oldSha256 = Get-ToolUpdateSha256 $targetPath
    $installResult = Install-ToolUpdateExecutable -StagedPath $stagedPath -TargetPath $targetPath -TargetSha256 $newSha256 -InstalledVersion '4.6.2.0' -TargetVersion '4.8.0.1' -CacheDirectory $cacheDirectory -SkipRestart
    Assert-UpdateTest ([bool]$installResult.Success -and (Get-ToolUpdateSha256 $targetPath) -eq $newSha256) 'Safe EXE replacement failed.'
    Assert-UpdateTest ((Get-ToolUpdateSha256 $installResult.BackupPath) -eq $oldSha256) 'Previous EXE backup is invalid.'

    . (Join-Path $root 'Tool-OfflinePolicy.ps1')
    . (Join-Path $root 'Tool-ModuleContract.ps1')
    $offlineMetadata = Get-ToolOfflinePolicyMetadata
    Assert-UpdateTest ([bool]$offlineMetadata.AutomaticUpdateCheck -and $offlineMetadata.AutomaticUpdateCheckTrigger -eq 'UserEnabledOnline') 'Offline metadata does not gate update checks on user-enabled Online mode.'
    Assert-UpdateTest (-not [bool]$offlineMetadata.BackgroundUpdateService -and -not [bool]$offlineMetadata.SilentUpdate) 'Metadata permits a background service or silent update.'
    $updateDescriptor = Get-ToolModuleDescriptor -ModuleId 'application.update.check'
    Assert-UpdateTest ($updateDescriptor.NetworkScope -eq 'Internet' -and $updateDescriptor.AccessMode -eq 'ReadOnly') 'Update module contract is invalid.'

    $dashboardText = Get-Content -LiteralPath (Join-Path $root 'Giao-Dien.ps1') -Raw -Encoding UTF8
    foreach ($pattern in @(
        'Request-ApplicationUpdateCheck', 'Reset-ApplicationUpdateForOffline', 'applicationUpdateReminderDueUtc',
        'AddHours(2)', 'update.choice.updateNow', 'update.choice.remindLater', 'update.choice.dismissSession',
        'TOOL_LAUNCHER_PID', '-Mode Apply', '-Mode Check', 'ExpectedCurrentSha256', 'currentHashArgument',
        'if (-not $script:offlineMode) { Request-ApplicationUpdateCheck }'
    )) {
        Assert-UpdateTest ($dashboardText.Contains($pattern)) "GUI is missing required update flow: $pattern"
    }
    Assert-UpdateTest ($dashboardText -match 'Verb\s*=\s*"RunAs"') 'Update apply is not elevated on demand.'
    $launcherText = Get-Content -LiteralPath (Join-Path $root 'Tool-Kiem-Tra-v4.8-OneFile.cs') -Raw -Encoding UTF8
    Assert-UpdateTest ($launcherText.Contains('"Tool-UpdateManager.ps1"') -and $launcherText.Contains('TOOL_LAUNCHER_PID') -and $launcherText.Contains('TOOL_TOOL_VERSION"] = "4.8.0.1"')) 'Launcher does not embed or pin the v4.8.0.1 update foundation.'
    $buildText = Get-Content -LiteralPath (Join-Path $root 'BUILD.ps1') -Raw -Encoding UTF8
    Assert-UpdateTest ($buildText.Contains("'Tool-UpdateManager.ps1'") -and $buildText.Contains("'VERIFY-APPLICATION-UPDATE.ps1'")) 'Build does not package or verify the updater.'

    foreach ($catalogName in @('Tool-Strings.vi-VN.json','Tool-Strings.en-US.json')) {
        $catalog = Get-Content -LiteralPath (Join-Path $root $catalogName) -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @('update.choice.updateNow','update.choice.remindLater','update.choice.dismissSession','update.apply.failedMessage','foundation.module.applicationUpdateCheck')) {
            Assert-UpdateTest ($null -ne $catalog.PSObject.Properties[$key]) "$catalogName is missing update key $key."
        }
    }

    $updateManagerText = Get-Content -LiteralPath $updateManagerPath -Raw -Encoding UTF8
    Assert-UpdateTest ($updateManagerText.Contains('-InstalledSha256 $CurrentLauncherSha256')) 'Apply-time manifest recheck does not preserve same-version hash detection.'

    Write-Host 'VERIFY-APPLICATION-UPDATE: OK (Offline/consent gates + signed-stable policy + anti-downgrade + same-version hash replacement + version/asset/hash/size/signer validation + verified swap/backup)' -ForegroundColor Green
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
} finally {
    $env:TOOL_OFFLINE_MODE = $oldOfflineMode
    $env:TOOL_UPDATE_CACHE_ROOT = $oldUpdateCacheRoot
    $temporaryFull = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTempFull = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($temporaryFull.StartsWith($systemTempFull, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($temporaryFull).StartsWith('tool-v470-update-verify-', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $temporaryFull -PathType Container) {
            Remove-Item -LiteralPath $temporaryFull -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
