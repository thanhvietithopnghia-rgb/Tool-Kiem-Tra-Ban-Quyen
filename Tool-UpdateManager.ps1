[CmdletBinding()]
param(
    [ValidateSet('Library','Check','Apply')][string]$Mode = 'Library',
    [switch]$ConsentGranted,
    [ValidateSet('vi-VN','en-US')][string]$Culture = 'vi-VN',
    [string]$CurrentVersion = '',
    [string]$ExpectedVersion = '',
    [string]$ResultFile = '',
    [string]$ManifestUrl = '',
    [string]$LauncherPath = '',
    [int]$LauncherProcessId = 0,
    [string]$ExpectedCurrentSha256 = '',
    [switch]$NoRestart,
    [switch]$NoUi
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:ToolUpdateSchemaVersion = '1.0'
$script:ToolUpdateToolVersion = '4.8.0.1'
$script:ToolUpdateDefaultManifestUrl = 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/update-manifest-v1.json'
$script:ToolUpdateManifestHost = 'raw.githubusercontent.com'
$script:ToolUpdateDownloadHosts = @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')
$script:ToolUpdateRepositoryPath = '/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/'
$script:ToolUpdateMaximumManifestBytes = 131072
$script:ToolUpdateMaximumExecutableBytes = 104857600
$script:ToolUpdateMinimumExecutableBytes = 65536
$script:ToolUpdateRestartAttempted = $false

# Every executable entry point fails closed before loading helpers or making a
# request. Library mode exists only for deterministic local verification.
if ($Mode -ne 'Library' -and (
    -not $ConsentGranted -or
    [string]$env:TOOL_OFFLINE_MODE -ne '0' -or
    [string]$env:TOOL_SELF_UPDATE_ALLOWED -ne '1'
)) {
    exit 2
}

$localizationPath = Join-Path $PSScriptRoot 'Tool-Localization.ps1'
if (Test-Path -LiteralPath $localizationPath -PathType Leaf) {
    . $localizationPath
    $env:TOOL_UI_CULTURE = $Culture
}

function Get-ToolUpdateText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    if (Get-Command Get-ToolText -ErrorAction SilentlyContinue) {
        return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
    }
    return "[$Key]"
}

function Get-ToolUpdateSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
        finally { $sha.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function ConvertTo-ToolUpdateVersion {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$') {
        throw "Invalid four-part update version: $Value"
    }
    $parsed = $null
    if (-not [Version]::TryParse($Value, [ref]$parsed)) {
        throw "Invalid update version: $Value"
    }
    return $parsed
}

function Get-ToolUpdateProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Required
    )
    if ($null -eq $InputObject) {
        if ($Required) { throw "Update manifest is missing $Name." }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if (-not $property) {
        if ($Required) { throw "Update manifest is missing $Name." }
        return $null
    }
    return $property.Value
}

function Get-ToolUpdateLocalizedText {
    param(
        [AllowNull()][object]$Container,
        [Parameter(Mandatory = $true)][string]$SelectedCulture,
        [int]$MaximumLength = 300
    )
    if ($null -eq $Container) { return '' }
    $property = $Container.PSObject.Properties[$SelectedCulture]
    if (-not $property) { $property = $Container.PSObject.Properties['vi-VN'] }
    if (-not $property) { $property = $Container.PSObject.Properties['en-US'] }
    if (-not $property) { return '' }
    $text = ([string]$property.Value).Replace([char]13, ' ').Replace([char]10, ' ').Trim()
    if ($text.Length -gt $MaximumLength) { throw 'Localized update text is too long.' }
    return $text
}

function Get-ToolUpdateLocalizedChanges {
    param(
        [AllowNull()][object]$Container,
        [Parameter(Mandatory = $true)][string]$SelectedCulture
    )
    if ($null -eq $Container) { return @() }
    $property = $Container.PSObject.Properties[$SelectedCulture]
    if (-not $property) { $property = $Container.PSObject.Properties['vi-VN'] }
    if (-not $property) { $property = $Container.PSObject.Properties['en-US'] }
    if (-not $property) { return @() }
    $changes = @($property.Value)
    if ($changes.Count -gt 20) { throw 'Update manifest has too many change entries.' }
    $safe = New-Object System.Collections.Generic.List[string]
    foreach ($item in $changes) {
        $text = ([string]$item).Replace([char]13, ' ').Replace([char]10, ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 400) {
            throw 'Update manifest contains an invalid change entry.'
        }
        [void]$safe.Add($text)
    }
    return @($safe.ToArray())
}

function Assert-ToolUpdateManifestUri {
    param([Parameter(Mandatory = $true)][uri]$Uri)
    $expectedPath = $script:ToolUpdateRepositoryPath + 'main/update-manifest-v1.json'
    if ($Uri.Scheme -ne 'https' -or
        $Uri.DnsSafeHost.ToLowerInvariant() -ne $script:ToolUpdateManifestHost -or
        $Uri.AbsolutePath -ne $expectedPath -or
        -not [string]::IsNullOrWhiteSpace($Uri.UserInfo) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Query) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Fragment)) {
        throw 'Update manifest URL is outside the fixed HTTPS allowlist.'
    }
    return $Uri
}

function Assert-ToolUpdateReleaseUri {
    param([Parameter(Mandatory = $true)][uri]$Uri)
    if ($Uri.Scheme -ne 'https' -or
        $Uri.DnsSafeHost.ToLowerInvariant() -ne 'github.com' -or
        -not $Uri.AbsolutePath.StartsWith(($script:ToolUpdateRepositoryPath + 'releases/'), [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::IsNullOrWhiteSpace($Uri.UserInfo) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Query) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Fragment)) {
        throw 'Update release URL is outside the project GitHub allowlist.'
    }
    return $Uri
}

function Assert-ToolUpdateDownloadUri {
    param([Parameter(Mandatory = $true)][uri]$Uri)
    $requiredPrefix = $script:ToolUpdateRepositoryPath + 'releases/download/'
    if ($Uri.Scheme -ne 'https' -or
        $Uri.DnsSafeHost.ToLowerInvariant() -ne 'github.com' -or
        -not $Uri.AbsolutePath.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $Uri.AbsolutePath.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or
        $Uri.AbsolutePath.Contains('..') -or
        -not [string]::IsNullOrWhiteSpace($Uri.UserInfo) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Query) -or
        -not [string]::IsNullOrWhiteSpace($Uri.Fragment)) {
        throw 'Update executable URL is outside the project release allowlist.'
    }
    return $Uri
}

function Assert-ToolUpdateRedirectUri {
    param([Parameter(Mandatory = $true)][uri]$Uri)
    if ($Uri.Scheme -ne 'https' -or
        $script:ToolUpdateDownloadHosts -notcontains $Uri.DnsSafeHost.ToLowerInvariant() -or
        -not [string]::IsNullOrWhiteSpace($Uri.UserInfo)) {
        throw 'Update redirect is outside the HTTPS asset allowlist.'
    }
    return $Uri
}

function ConvertFrom-ToolUpdateManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$InstalledVersion,
        [string]$InstalledSha256 = '',
        [ValidateSet('vi-VN','en-US')][string]$SelectedCulture = 'vi-VN',
        [string]$SourceUrl = ''
    )
    $schemaVersion = [string](Get-ToolUpdateProperty $Manifest 'SchemaVersion' -Required)
    $channel = [string](Get-ToolUpdateProperty $Manifest 'Channel' -Required)
    if ($schemaVersion -ne $script:ToolUpdateSchemaVersion -or $channel -ne 'stable') {
        throw 'Unsupported update manifest schema or channel.'
    }

    $current = ConvertTo-ToolUpdateVersion $InstalledVersion
    $latestText = [string](Get-ToolUpdateProperty $Manifest 'LatestVersion' -Required)
    $minimumUpdaterText = [string](Get-ToolUpdateProperty $Manifest 'MinimumUpdaterVersion' -Required)
    $latest = ConvertTo-ToolUpdateVersion $latestText
    $minimumUpdater = ConvertTo-ToolUpdateVersion $minimumUpdaterText
    if ($minimumUpdater -gt $latest) { throw 'Minimum updater version cannot exceed the release version.' }
    $downloadSha256 = ([string](Get-ToolUpdateProperty $Manifest 'DownloadSha256' -Required)).ToUpperInvariant()
    if ($downloadSha256 -notmatch '^[0-9A-F]{64}$') { throw 'Update executable SHA-256 is invalid.' }
    $installedSha256Normalized = $InstalledSha256.Trim().ToUpperInvariant()
    if ($installedSha256Normalized -and $installedSha256Normalized -notmatch '^[0-9A-F]{64}$') {
        throw 'Installed executable SHA-256 is invalid.'
    }
    $downloadSize = [long](Get-ToolUpdateProperty $Manifest 'DownloadSize' -Required)
    if ($downloadSize -lt $script:ToolUpdateMinimumExecutableBytes -or $downloadSize -gt $script:ToolUpdateMaximumExecutableBytes) {
        throw 'Update executable size is outside the allowed range.'
    }

    $downloadUri = Assert-ToolUpdateDownloadUri ([uri]([string](Get-ToolUpdateProperty $Manifest 'DownloadUrl' -Required)))
    $releaseUri = Assert-ToolUpdateReleaseUri ([uri]([string](Get-ToolUpdateProperty $Manifest 'ReleasePageUrl' -Required)))
    $expectedDownloadTag = '/releases/download/v' + $latestText + '/'
    $expectedReleaseTag = '/releases/tag/v' + $latestText
    $expectedAssetName = 'Tool-Kiem-Tra-v' + $latest.Major + '.' + $latest.Minor + '.exe'
    $actualAssetName = [Uri]::UnescapeDataString([IO.Path]::GetFileName($downloadUri.AbsolutePath))
    if ($downloadUri.AbsolutePath.IndexOf($expectedDownloadTag, [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        -not $releaseUri.AbsolutePath.Equals(($script:ToolUpdateRepositoryPath.TrimEnd('/') + $expectedReleaseTag), [StringComparison]::OrdinalIgnoreCase) -or
        -not $actualAssetName.Equals($expectedAssetName, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Update URLs do not match the declared release version.'
    }
    $publishedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
        [string](Get-ToolUpdateProperty $Manifest 'PublishedAtUtc' -Required),
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$publishedAt)) {
        throw 'Update publication timestamp is invalid.'
    }

    $title = Get-ToolUpdateLocalizedText (Get-ToolUpdateProperty $Manifest 'Title' -Required) $SelectedCulture 240
    $changes = @(Get-ToolUpdateLocalizedChanges (Get-ToolUpdateProperty $Manifest 'Changes' -Required) $SelectedCulture)
    if ([string]::IsNullOrWhiteSpace($title) -or $changes.Count -eq 0) {
        throw 'Update manifest is missing localized release information.'
    }
    $authenticodeValue = Get-ToolUpdateProperty $Manifest 'AuthenticodeRequired'
    if ($null -ne $authenticodeValue -and $authenticodeValue -isnot [bool]) {
        throw 'AuthenticodeRequired must be a JSON boolean.'
    }
    $authenticodeRequired = [bool]$authenticodeValue
    $signerThumbprints = New-Object System.Collections.Generic.List[string]
    foreach ($signerValue in @(Get-ToolUpdateProperty $Manifest 'SignerThumbprints')) {
        $thumbprint = ([string]$signerValue).Replace(' ', '').ToUpperInvariant()
        if ($thumbprint -notmatch '^[0-9A-F]{40,64}$') {
            throw 'Update manifest contains an invalid signer thumbprint.'
        }
        if (-not $signerThumbprints.Contains($thumbprint)) { [void]$signerThumbprints.Add($thumbprint) }
    }
    if ($authenticodeRequired -and $signerThumbprints.Count -eq 0) {
        throw 'Signed update is required but no trusted signer thumbprint is declared.'
    }
    if ($channel -eq 'stable' -and -not $authenticodeRequired) {
        throw 'Stable update manifests must require a pinned Authenticode signer.'
    }

    # A release may replace the public build without changing its four-part
    # product version. Offer that in-place maintenance build only when the
    # caller supplied the SHA-256 of the running EXE and it differs from the
    # pinned release hash. Missing/invalid local identity therefore fails
    # closed, while newer-version and anti-downgrade behavior stays unchanged.
    $sameVersionReplacement = [bool](
        $latest -eq $current -and
        $installedSha256Normalized -and
        $installedSha256Normalized -ne $downloadSha256)
    $updateAvailable = [bool]($latest -gt $current -or $sameVersionReplacement)

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolUpdateSchemaVersion
        Success = $true
        UpdateAvailable = $updateAvailable
        SameVersionReplacement = $sameVersionReplacement
        CanSelfUpdate = [bool]($current -ge $minimumUpdater)
        CurrentVersion = $current.ToString()
        LatestVersion = $latest.ToString()
        MinimumUpdaterVersion = $minimumUpdater.ToString()
        Title = $title
        Changes = @($changes)
        PublishedAtUtc = $publishedAt.ToUniversalTime().ToString('o')
        ReleasePageUrl = $releaseUri.AbsoluteUri
        DownloadUrl = $downloadUri.AbsoluteUri
        DownloadSha256 = $downloadSha256
        DownloadSize = $downloadSize
        AuthenticodeRequired = $authenticodeRequired
        SignerThumbprints = @($signerThumbprints.ToArray())
        ManifestUrl = $SourceUrl
        CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
        UploadedMachineData = $false
        TelemetrySent = $false
    }
}

function Invoke-ToolUpdateManifestDownload {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [int]$TimeoutMilliseconds = 15000
    )
    [void](Assert-ToolUpdateManifestUri $Uri)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'ThanhViet-Tool-Kiem-Tra/4.8.0 update-check'
    $response = $null
    $stream = $null
    $memory = $null
    try {
        $response = [Net.HttpWebResponse]$request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw ('HTTP ' + [int]$response.StatusCode) }
        if ($response.ContentLength -gt $script:ToolUpdateMaximumManifestBytes) { throw 'Update manifest exceeds the size limit.' }
        $stream = $response.GetResponseStream()
        $memory = New-Object IO.MemoryStream
        $buffer = New-Object byte[] 8192
        $total = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $script:ToolUpdateMaximumManifestBytes) { throw 'Update manifest exceeds the size limit.' }
            $memory.Write($buffer, 0, $read)
        }
        return (New-Object Text.UTF8Encoding($false, $true)).GetString($memory.ToArray())
    } finally {
        if ($memory) { $memory.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Invoke-ToolUpdateCheck {
    param(
        [Parameter(Mandatory = $true)][string]$InstalledVersion,
        [Parameter(Mandatory = $true)][switch]$ExplicitConsent,
        [string]$InstalledSha256 = '',
        [ValidateSet('vi-VN','en-US')][string]$SelectedCulture = 'vi-VN',
        [string]$SourceUrl = $script:ToolUpdateDefaultManifestUrl
    )
    if (-not $ExplicitConsent -or [string]$env:TOOL_OFFLINE_MODE -ne '0') {
        throw 'Update checks require explicit Online mode.'
    }
    $uri = Assert-ToolUpdateManifestUri ([uri]$SourceUrl)
    $raw = Invoke-ToolUpdateManifestDownload -Uri $uri
    $manifest = $raw | ConvertFrom-Json
    return ConvertFrom-ToolUpdateManifest -Manifest $manifest -InstalledVersion $InstalledVersion -InstalledSha256 $InstalledSha256 -SelectedCulture $SelectedCulture -SourceUrl $uri.AbsoluteUri
}

function Get-ToolUpdateCacheRoot {
    $root = [string]$env:TOOL_UPDATE_CACHE_ROOT
    if ([string]::IsNullOrWhiteSpace($root)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
        if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'Per-user update cache is unavailable.' }
        $root = Join-Path $localAppData 'ThanhViet-Tool-Kiem-Tra\updates'
    }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($root))
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Update cache cannot be a reparse point.'
    }
    return $full
}

function Invoke-ToolUpdateExecutableDownload {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][long]$ExpectedSize,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [scriptblock]$ProgressCallback
    )
    [void](Assert-ToolUpdateDownloadUri $Uri)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $currentUri = $Uri
    for ($redirectCount = 0; $redirectCount -le 4; $redirectCount++) {
        if ($redirectCount -gt 0) { [void](Assert-ToolUpdateRedirectUri $currentUri) }
        $request = [Net.HttpWebRequest]::Create($currentUri)
        $request.Method = 'GET'
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 30000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = 'ThanhViet-Tool-Kiem-Tra/4.8.0 update-download'
        $response = $null
        try {
            $response = [Net.HttpWebResponse]$request.GetResponse()
            $statusCode = [int]$response.StatusCode
            if ($statusCode -in @(301,302,303,307,308)) {
                $location = [string]$response.Headers['Location']
                if ([string]::IsNullOrWhiteSpace($location)) { throw 'Update redirect has no destination.' }
                $currentUri = New-Object Uri($currentUri, $location)
                continue
            }
            if ($statusCode -ne 200) { throw "HTTP $statusCode" }
            if ($response.ContentLength -gt $script:ToolUpdateMaximumExecutableBytes) { throw 'Update executable exceeds the size limit.' }
            if ($response.ContentLength -ge 0 -and $response.ContentLength -ne $ExpectedSize) { throw 'Update executable size does not match the manifest.' }

            $stream = $null
            $output = $null
            $sha = $null
            try {
                $stream = $response.GetResponseStream()
                $output = New-Object IO.FileStream($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $sha = [Security.Cryptography.SHA256]::Create()
                $buffer = New-Object byte[] 65536
                [long]$total = 0
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $total += $read
                    if ($total -gt $ExpectedSize -or $total -gt $script:ToolUpdateMaximumExecutableBytes) {
                        throw 'Update executable exceeded the declared size.'
                    }
                    $output.Write($buffer, 0, $read)
                    [void]$sha.TransformBlock($buffer, 0, $read, $null, 0)
                    if ($ProgressCallback) {
                        $percent = [int][Math]::Min(99, [Math]::Floor(($total * 100.0) / $ExpectedSize))
                        & $ProgressCallback $percent $total $ExpectedSize
                    }
                }
                [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                $actualSha256 = ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToUpperInvariant()
                if ($total -ne $ExpectedSize -or $actualSha256 -ne $ExpectedSha256.ToUpperInvariant()) {
                    throw 'Downloaded update failed size or SHA-256 verification.'
                }
                return [pscustomobject][ordered]@{
                    Path = $DestinationPath
                    Size = $total
                    Sha256 = $actualSha256
                    FinalUrl = $currentUri.AbsoluteUri
                }
            } finally {
                if ($sha) { $sha.Dispose() }
                if ($output) { $output.Dispose() }
                if ($stream) { $stream.Dispose() }
            }
        } finally {
            if ($response) { $response.Dispose() }
        }
    }
    throw 'Update download exceeded the redirect limit.'
}

function Assert-ToolUpdateExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$ExpectedSize,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [bool]$AuthenticodeRequired,
        [string[]]$SignerThumbprints = @()
    )
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $ExpectedSize) {
        throw 'Staged update executable has an unsafe type or unexpected size.'
    }
    $stream = [IO.File]::OpenRead($item.FullName)
    try {
        if ($stream.ReadByte() -ne 0x4D -or $stream.ReadByte() -ne 0x5A) {
            throw 'Staged update is not a Windows executable.'
        }
    } finally {
        $stream.Dispose()
    }
    $actualSha256 = Get-ToolUpdateSha256 $item.FullName
    if ($actualSha256 -ne $ExpectedSha256.ToUpperInvariant()) { throw 'Staged update SHA-256 is invalid.' }
    if ($AuthenticodeRequired) {
        $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName
        $thumbprint = if ($signature.SignerCertificate) { ([string]$signature.SignerCertificate.Thumbprint).Replace(' ', '').ToUpperInvariant() } else { '' }
        if ($signature.Status -ne 'Valid' -or $SignerThumbprints -notcontains $thumbprint) {
            throw 'Staged update does not have the required trusted Authenticode signature.'
        }
    }
    return $true
}

function New-ToolUpdateProgressWindow {
    if ($NoUi) { return $null }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = Get-ToolUpdateText 'update.apply.windowTitle'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(570, 205)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = Get-ToolUpdateText 'update.apply.preparing'
    $label.Location = New-Object System.Drawing.Point(24, 24)
    $label.Size = New-Object System.Drawing.Size(510, 54)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.Controls.Add($label)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(24, 92)
    $bar.Size = New-Object System.Drawing.Size(510, 22)
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Style = 'Continuous'
    $form.Controls.Add($bar)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = Get-ToolUpdateText 'update.apply.privacy'
    $privacy.Location = New-Object System.Drawing.Point(24, 126)
    $privacy.Size = New-Object System.Drawing.Size(510, 36)
    $privacy.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $form.Controls.Add($privacy)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    return [pscustomobject]@{ Form=$form; Label=$label; ProgressBar=$bar }
}

function Set-ToolUpdateProgress {
    param(
        [AllowNull()][object]$Window,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$Percent = -1
    )
    if (-not $Window) { return }
    $Window.Label.Text = $Message
    if ($Percent -ge 0) { $Window.ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Percent)) }
    [System.Windows.Forms.Application]::DoEvents()
}

function Close-ToolUpdateProgressWindow {
    param([AllowNull()][object]$Window)
    if (-not $Window) { return }
    $Window.Form.Close()
    $Window.Form.Dispose()
}

function Write-ToolUpdateJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText($fullPath, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function Wait-ToolUpdateLauncherExit {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [int]$TimeoutSeconds = 90
    )
    if ($ProcessId -le 0 -or $ProcessId -eq $PID) { throw 'Launcher process identifier is invalid.' }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out while waiting for the current Tool to close.' }
        Start-Sleep -Milliseconds 250
    }
}

function Install-ToolUpdateExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$TargetSha256,
        [Parameter(Mandatory = $true)][string]$InstalledVersion,
        [Parameter(Mandatory = $true)][string]$TargetVersion,
        [Parameter(Mandatory = $true)][string]$CacheDirectory,
        [switch]$SkipRestart
    )
    $targetFull = [IO.Path]::GetFullPath($TargetPath)
    $targetItem = Get-Item -LiteralPath $targetFull -Force
    if ($targetItem.Extension -ne '.exe' -or ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Current Tool launcher path is unsafe.'
    }
    $targetDirectory = Split-Path -Parent $targetFull
    $backupPath = Join-Path $CacheDirectory ("Tool-Kiem-Tra-$InstalledVersion-backup.exe")
    Copy-Item -LiteralPath $targetFull -Destination $backupPath -Force

    $swapNew = Join-Path $targetDirectory ('.tool-update-new-' + [Guid]::NewGuid().ToString('N') + '.exe')
    $swapBackup = Join-Path $targetDirectory ('.tool-update-old-' + [Guid]::NewGuid().ToString('N') + '.exe')
    Copy-Item -LiteralPath $StagedPath -Destination $swapNew
    if ((Get-ToolUpdateSha256 $swapNew) -ne $TargetSha256) {
        Remove-Item -LiteralPath $swapNew -Force -ErrorAction SilentlyContinue
        throw 'Update changed while staging beside the launcher.'
    }

    $replaced = $false
    $rollbackCompleted = $false
    try {
        try {
            [IO.File]::Replace($swapNew, $targetFull, $swapBackup)
            $replaced = $true
        } catch {
            if (Test-Path -LiteralPath $swapBackup -PathType Leaf) { Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue }
            [IO.File]::Move($targetFull, $swapBackup)
            try {
                [IO.File]::Move($swapNew, $targetFull)
                $replaced = $true
            } catch {
                if (-not (Test-Path -LiteralPath $targetFull -PathType Leaf) -and (Test-Path -LiteralPath $swapBackup -PathType Leaf)) {
                    [IO.File]::Move($swapBackup, $targetFull)
                }
                throw
            }
        }
        if ((Get-ToolUpdateSha256 $targetFull) -ne $TargetSha256) {
            throw 'Installed Tool does not match the verified update.'
        }

        if (-not $SkipRestart) {
            $script:ToolUpdateRestartAttempted = $true
            $newProcess = Start-Process -FilePath $targetFull -WorkingDirectory $targetDirectory -PassThru
            Start-Sleep -Seconds 5
            if ($newProcess.HasExited) {
                $rollbackNew = Join-Path $targetDirectory ('.tool-update-rollback-' + [Guid]::NewGuid().ToString('N') + '.exe')
                Copy-Item -LiteralPath $backupPath -Destination $rollbackNew
                try { [IO.File]::Replace($rollbackNew, $targetFull, $null) }
                catch {
                    if (Test-Path -LiteralPath $targetFull -PathType Leaf) { Remove-Item -LiteralPath $targetFull -Force }
                    [IO.File]::Move($rollbackNew, $targetFull)
                }
                $rollbackCompleted = $true
                [void](Start-Process -FilePath $targetFull -WorkingDirectory $targetDirectory)
                throw 'The new Tool exited during startup; the previous version was restored.'
            }
        }
    } catch {
        $installError = $_
        if ($replaced -and -not $rollbackCompleted -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            $rollbackNew = Join-Path $targetDirectory ('.tool-update-rollback-' + [Guid]::NewGuid().ToString('N') + '.exe')
            try {
                Copy-Item -LiteralPath $backupPath -Destination $rollbackNew
                try { [IO.File]::Replace($rollbackNew, $targetFull, $null) }
                catch {
                    if (Test-Path -LiteralPath $targetFull -PathType Leaf) { Remove-Item -LiteralPath $targetFull -Force }
                    [IO.File]::Move($rollbackNew, $targetFull)
                }
                $rollbackCompleted = $true
            } finally {
                if (Test-Path -LiteralPath $rollbackNew -PathType Leaf) { Remove-Item -LiteralPath $rollbackNew -Force -ErrorAction SilentlyContinue }
            }
        }
        throw $installError
    } finally {
        if (Test-Path -LiteralPath $swapNew -PathType Leaf) { Remove-Item -LiteralPath $swapNew -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $swapBackup -PathType Leaf) { Remove-Item -LiteralPath $swapBackup -Force -ErrorAction SilentlyContinue }
        if (-not $replaced -and -not (Test-Path -LiteralPath $targetFull -PathType Leaf) -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupPath -Destination $targetFull -Force
        }
    }
    return [pscustomobject][ordered]@{
        Success = $true
        PreviousVersion = $InstalledVersion
        InstalledVersion = $TargetVersion
        LauncherPath = $targetFull
        BackupPath = $backupPath
        InstalledSha256 = $TargetSha256
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Invoke-ToolUpdateApply {
    param(
        [Parameter(Mandatory = $true)][string]$InstalledVersion,
        [Parameter(Mandatory = $true)][string]$RequiredVersion,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [Parameter(Mandatory = $true)][string]$CurrentLauncherPath,
        [Parameter(Mandatory = $true)][int]$CurrentLauncherProcessId,
        [Parameter(Mandatory = $true)][string]$CurrentLauncherSha256
    )
    if ([string]$env:TOOL_SECURE_LAUNCH -ne '1') { throw 'Self-update is available only from the verified EXE launcher.' }
    if ([string]$env:TOOL_SELF_UPDATE_ALLOWED -ne '1') { throw 'Self-update is unavailable for this build.' }
    if (-not $ConsentGranted -or [string]$env:TOOL_OFFLINE_MODE -ne '0') { throw 'Update requires explicit Online mode.' }
    if ([string]$env:TOOL_LAUNCHER_PID -notmatch '^[0-9]{1,10}$' -or [int]$env:TOOL_LAUNCHER_PID -ne $CurrentLauncherProcessId) {
        throw 'Launcher process identifier does not match the secure launch environment.'
    }
    if ($CurrentLauncherSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Current launcher SHA-256 is invalid.' }
    $launcherFull = [IO.Path]::GetFullPath($CurrentLauncherPath)
    if ([string]::IsNullOrWhiteSpace([string]$env:TOOL_LAUNCHER_PATH) -or
        -not $launcherFull.Equals([IO.Path]::GetFullPath([string]$env:TOOL_LAUNCHER_PATH), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Launcher path does not match the secure launch environment.'
    }
    if ((Get-ToolUpdateSha256 $launcherFull) -ne $CurrentLauncherSha256.ToUpperInvariant()) {
        throw 'Current launcher changed after the update prompt.'
    }

    $window = New-ToolUpdateProgressWindow
    $cacheRoot = Get-ToolUpdateCacheRoot
    $cacheDirectory = Join-Path $cacheRoot ($RequiredVersion.Replace('.', '_'))
    if (-not (Test-Path -LiteralPath $cacheDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    }
    $cacheDirectoryItem = Get-Item -LiteralPath $cacheDirectory -Force
    if (($cacheDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Version update cache cannot be a reparse point.'
    }
    $stagedPath = Join-Path $cacheDirectory ('download-' + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Set-ToolUpdateProgress $window (Get-ToolUpdateText 'update.apply.checking') 3
        $candidate = Invoke-ToolUpdateCheck -InstalledVersion $InstalledVersion -InstalledSha256 $CurrentLauncherSha256 -ExplicitConsent -SelectedCulture $Culture -SourceUrl $SourceUrl
        if (-not $candidate.UpdateAvailable -or $candidate.LatestVersion -ne (ConvertTo-ToolUpdateVersion $RequiredVersion).ToString()) {
            throw 'The available update changed after confirmation. Recheck from the Tool.'
        }
        if (-not $candidate.CanSelfUpdate) { throw 'This update requires a newer updater foundation.' }

        $progressCallback = {
            param($percent, $received, $total)
            Set-ToolUpdateProgress $window (Get-ToolUpdateText 'update.apply.downloading' @($candidate.LatestVersion, $percent)) $percent
        }
        [void](Invoke-ToolUpdateExecutableDownload -Uri ([uri]$candidate.DownloadUrl) -DestinationPath $stagedPath -ExpectedSize ([long]$candidate.DownloadSize) -ExpectedSha256 ([string]$candidate.DownloadSha256) -ProgressCallback $progressCallback)
        Set-ToolUpdateProgress $window (Get-ToolUpdateText 'update.apply.verifying') 100
        [void](Assert-ToolUpdateExecutable -Path $stagedPath -ExpectedSize ([long]$candidate.DownloadSize) -ExpectedSha256 ([string]$candidate.DownloadSha256) -AuthenticodeRequired ([bool]$candidate.AuthenticodeRequired) -SignerThumbprints @($candidate.SignerThumbprints))
        Set-ToolUpdateProgress $window (Get-ToolUpdateText 'update.apply.waiting') 100
        Wait-ToolUpdateLauncherExit -ProcessId $CurrentLauncherProcessId
        Set-ToolUpdateProgress $window (Get-ToolUpdateText 'update.apply.installing') 100
        $result = Install-ToolUpdateExecutable -StagedPath $stagedPath -TargetPath $launcherFull -TargetSha256 ([string]$candidate.DownloadSha256) -InstalledVersion $InstalledVersion -TargetVersion ([string]$candidate.LatestVersion) -CacheDirectory $cacheDirectory -SkipRestart:$NoRestart
        $resultPath = Join-Path $cacheRoot 'last-update-result.json'
        Write-ToolUpdateJson $resultPath $result
        Close-ToolUpdateProgressWindow $window
        $window = $null
        return $result
    } finally {
        if (Test-Path -LiteralPath $stagedPath -PathType Leaf) { Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue }
        Close-ToolUpdateProgressWindow $window
    }
}

if ($Mode -eq 'Library') {
    return
}

try {
    if ([string]::IsNullOrWhiteSpace($ManifestUrl)) { $ManifestUrl = $script:ToolUpdateDefaultManifestUrl }
    if ($Mode -eq 'Check') {
        if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or [string]::IsNullOrWhiteSpace($ResultFile)) {
            throw 'Check mode requires CurrentVersion and ResultFile.'
        }
        $checkResult = Invoke-ToolUpdateCheck -InstalledVersion $CurrentVersion -InstalledSha256 $ExpectedCurrentSha256 -ExplicitConsent -SelectedCulture $Culture -SourceUrl $ManifestUrl
        Write-ToolUpdateJson $ResultFile $checkResult
        exit 0
    }
    if ($Mode -eq 'Apply') {
        if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or
            [string]::IsNullOrWhiteSpace($ExpectedVersion) -or
            [string]::IsNullOrWhiteSpace($LauncherPath) -or
            $LauncherProcessId -le 0 -or
            [string]::IsNullOrWhiteSpace($ExpectedCurrentSha256)) {
            throw 'Apply mode is missing a required secure-update parameter.'
        }
        $applyResult = Invoke-ToolUpdateApply -InstalledVersion $CurrentVersion -RequiredVersion $ExpectedVersion -SourceUrl $ManifestUrl -CurrentLauncherPath $LauncherPath -CurrentLauncherProcessId $LauncherProcessId -CurrentLauncherSha256 $ExpectedCurrentSha256
        if (-not [string]::IsNullOrWhiteSpace($ResultFile)) { Write-ToolUpdateJson $ResultFile $applyResult }
        exit 0
    }
    throw 'Unsupported update mode.'
} catch {
    $failure = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolUpdateSchemaVersion
        Success = $false
        Mode = $Mode
        CurrentVersion = $CurrentVersion
        ExpectedVersion = $ExpectedVersion
        Error = [string]$_.Exception.Message
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
        UploadedMachineData = $false
        TelemetrySent = $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultFile)) {
        try { Write-ToolUpdateJson $ResultFile $failure } catch {}
    }
    if ($Mode -eq 'Apply') {
        if (-not $NoUi) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show(
                    (Get-ToolUpdateText 'update.apply.failedMessage' @([string]$_.Exception.Message)),
                    (Get-ToolUpdateText 'update.apply.failedTitle'),
                    'OK',
                    'Error') | Out-Null
            } catch {}
        }
        if (-not $NoRestart -and -not $script:ToolUpdateRestartAttempted -and (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
            try {
                # The UI requests its own shutdown immediately after starting this
                # helper, but an early network/manifest failure can reach this catch
                # before the launcher has actually released its single-instance
                # mutex. Wait for that exact trusted launcher process so reopening
                # the unchanged build cannot be lost to the still-running instance.
                if ($CurrentLauncherProcessId -gt 0 -and $CurrentLauncherProcessId -ne $PID -and (Get-Process -Id $CurrentLauncherProcessId -ErrorAction SilentlyContinue)) {
                    Wait-ToolUpdateLauncherExit -ProcessId $CurrentLauncherProcessId -TimeoutSeconds 30
                }
                $script:ToolUpdateRestartAttempted = $true
                [void](Start-Process -FilePath ([IO.Path]::GetFullPath($LauncherPath)) -WorkingDirectory (Split-Path -Parent ([IO.Path]::GetFullPath($LauncherPath))))
            } catch {}
        }
    }
    exit 3
}
