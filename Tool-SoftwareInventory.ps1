$script:ToolSoftwareInventorySchemaVersion = '1.0'
$script:ToolSoftwareCatalogSchemaVersion = '1.0'
$script:ToolSoftwareCatalogFileName = 'software-license-catalog-v1.0.json'
$script:ToolSoftwareCatalogDefaultUrl = 'https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/software-license-catalog-v1.0.json'
$script:ToolSoftwareCatalogAllowedHosts = @('raw.githubusercontent.com')
$script:ToolSoftwareSignatureCache = @{}
$script:ToolSoftwareFileHashCache = @{}
$script:ToolSoftwareLocationEvidenceCache = @{}
$script:ToolSoftwareHostsEvidenceCache = @{}
$script:ToolSoftwareDeepFileCache = @{}
$script:ToolSoftwareDeepDirectoryCache = @{}
$script:ToolSoftwareDeepSystemSnapshotCache = $null
$script:ToolSoftwareLastDeepScanMetadata = $null
$script:ToolSoftwareCatalogTrustCache = @{}
$script:ToolSoftwareKnownActivatorPattern = '(?i)(\bkmspico\b|\bkmsauto\b|\bauto[\s._-]*kms\b|\bkms[\s._-]*vl(?:[\s._-]*all)?\b|\baact(?:portable)?\b|\bhwidgen\b|\bmassgrave\b|\bmas[\s._-]*aio\b|\btsforge\b|\bohook\b|\bmicrosoft[\s_-]+toolkit\b|\bspp(?:extcomobj)?[\s._-]*(?:hook|patcher)\b|\badobe[\s._-]*genp\b|\bccmaker\b|\bamtlib[\s._-]*(?:patch|emulator)\b|\bxf[\s._-]*adsk\b|\bx[\s._-]*force\b|\bby\s+sandy[d]?\b)'
$script:ToolSoftwareSuspiciousArtifactPattern = '(?i)(\bcrack(?:ed)?\b|\bkeygen\b|\bactivator\b|\bactivation[\s._-]*(?:bypass|patch(?:er)?)\b|\blicen[cs]e[\s._-]*(?:bypass|patch(?:er)?)\b|\bserial[\s._-]*generator\b)'
$script:ToolSoftwareDeepRelevantExtensions = @('.exe','.dll','.sys','.ocx','.cpl','.scr','.com','.msi','.cmd','.bat','.ps1','.vbs','.js','.jar','.zip','.rar','.7z')
$script:ToolSoftwareAuthenticodeExtensions = @('.exe','.dll','.sys','.ocx','.cpl','.scr','.com','.msi','.ps1','.vbs','.js')

function Reset-ToolSoftwareInventoryCaches {
    $script:ToolSoftwareSignatureCache = @{}
    $script:ToolSoftwareFileHashCache = @{}
    $script:ToolSoftwareLocationEvidenceCache = @{}
    $script:ToolSoftwareHostsEvidenceCache = @{}
    $script:ToolSoftwareDeepFileCache = @{}
    $script:ToolSoftwareDeepDirectoryCache = @{}
    $script:ToolSoftwareDeepSystemSnapshotCache = $null
    $script:ToolSoftwareLastDeepScanMetadata = $null
    $script:ToolSoftwareCatalogTrustCache = @{}
}

function Get-ToolSoftwareOptionalPropertyValues {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return @() }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return @() }
    return @($property.Value)
}

function Get-ToolSoftwareOptionalPropertyString {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name, [string]$Default = '')
    $values = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $InputObject -Name $Name)
    if ($values.Count -eq 0 -or $null -eq $values[0]) { return $Default }
    return [string]$values[0]
}

function ConvertTo-ToolSoftwareInstallDateText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToString('yyyy-MM-dd') }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $dateParts = $null
    if ($text -match '^(?<year>\d{4})(?<month>\d{2})(?<day>\d{2})(?:\d{6}(?:\.\d{6})?[+\-]\d{3})?$') {
        try {
            $dateParts = New-Object DateTime ([int]$matches.year, [int]$matches.month, [int]$matches.day)
            return $dateParts.ToString('yyyy-MM-dd')
        } catch { return $text }
    }
    if ($text -match '^\d{9,11}$') {
        try {
            $unixSeconds = [int64]$text
            $dateParts = ([DateTime]'1970-01-01T00:00:00Z').AddSeconds($unixSeconds).ToLocalTime()
            if ($dateParts.Year -ge 2000 -and $dateParts.Year -le 2100) { return $dateParts.ToString('yyyy-MM-dd') }
        } catch {}
    }
    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse($text, [Globalization.CultureInfo]::CurrentCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed) -or
        [DateTime]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        return $parsed.ToString('yyyy-MM-dd')
    }
    return $text
}

function Get-ToolSoftwareCatalogCachePath {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($localAppData)) { return '' }
    return Join-Path $localAppData ('ThanhViet-Tool-Kiem-Tra\catalogs\' + $script:ToolSoftwareCatalogFileName)
}

function Get-ToolSoftwareCatalogBundledPath {
    return Join-Path $PSScriptRoot $script:ToolSoftwareCatalogFileName
}

function Get-ToolSoftwareSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToUpperInvariant()
    } finally { $sha.Dispose() }
}

function Get-ToolSoftwareFileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [long]$MaximumBytes = 536870912
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $stream = $null
    $sha = $null
    try {
        $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ([long]$file.Length -gt $MaximumBytes) { return '' }
        $fullPath = [IO.Path]::GetFullPath([string]$file.FullName)
        $cacheKey = ($fullPath.ToLowerInvariant() + '|' + [string]$file.Length + '|' + [string]$file.LastWriteTimeUtc.Ticks)
        if ($script:ToolSoftwareFileHashCache.ContainsKey($cacheKey)) { return [string]$script:ToolSoftwareFileHashCache[$cacheKey] }
        $sha = [Security.Cryptography.SHA256]::Create()
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $hash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant()
        $script:ToolSoftwareFileHashCache[$cacheKey] = $hash
        return $hash
    } catch { return '' }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

function Get-ToolSoftwareStableId {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (Get-ToolSoftwareSha256Text -Text $Value).Substring(0, 24).ToLowerInvariant()
}

function Test-ToolSoftwareCatalogObject {
    param([AllowNull()][object]$Catalog)
    if ($null -eq $Catalog) { return $false }
    if ((Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'SchemaVersion') -ne $script:ToolSoftwareCatalogSchemaVersion) { return $false }
    $products = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $Catalog -Name 'Products')
    if ($products.Count -eq 0 -or $products.Count -gt 5000) { return $false }
    $catalogRegexProperties = @('KnownActivatorNamePatterns','SuspiciousArtifactNamePatterns')
    $deepScanValues = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $Catalog -Name 'DeepScan')
    if ($deepScanValues.Count -gt 0) {
        $deepScan = $deepScanValues[0]
        foreach ($propertyName in $catalogRegexProperties) {
            foreach ($pattern in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $deepScan -Name $propertyName)) {
                if ([string]::IsNullOrWhiteSpace([string]$pattern) -or ([string]$pattern).Length -gt 320) { return $false }
                try { [void][regex]::new([string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
                catch { return $false }
            }
        }
        $catalogKnownBadHashes = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $deepScan -Name 'KnownBadSha256')
        if ($catalogKnownBadHashes.Count -gt 4096) { return $false }
        foreach ($hash in @($catalogKnownBadHashes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
            if ([string]$hash -notmatch '^[0-9A-Fa-f]{64}$') { return $false }
        }
    }
    $productRegexProperties = @('NamePatterns','PublisherPatterns','UnauthorizedNamePatterns','CriticalFilePatterns',
        'ExpectedSignedFilePatterns','ExpectedSignerPatterns','KnownActivatorNamePatterns','SuspiciousArtifactNamePatterns','LicenseProcessPatterns')
    foreach ($product in $products) {
        $namePatterns = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $product -Name 'NamePatterns')
        if ([string]::IsNullOrWhiteSpace((Get-ToolSoftwareOptionalPropertyString -InputObject $product -Name 'Id')) -or
            [string]::IsNullOrWhiteSpace((Get-ToolSoftwareOptionalPropertyString -InputObject $product -Name 'LicenseModel')) -or
            $namePatterns.Count -eq 0) { return $false }
        $allPatterns = New-Object System.Collections.Generic.List[object]
        foreach ($propertyName in $productRegexProperties) {
            foreach ($pattern in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $product -Name $propertyName)) { $allPatterns.Add($pattern) }
        }
        foreach ($pattern in $allPatterns.ToArray()) {
            if ([string]$pattern -and ([string]$pattern).Length -gt 320) { return $false }
            try { if ([string]$pattern) { [void][regex]::new([string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase) } }
            catch { return $false }
        }
        $knownBadHashes = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $product -Name 'KnownBadSha256')
        if ($knownBadHashes.Count -gt 2048) { return $false }
        foreach ($hash in @($knownBadHashes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
            if ([string]$hash -notmatch '^[0-9A-Fa-f]{64}$') { return $false }
        }
    }
    return $true
}

function Import-ToolSoftwareCatalogFile {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Source = 'Bundled')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.Encoding]::UTF8)
        if ([Text.Encoding]::UTF8.GetByteCount($raw) -gt 2097152) { return $null }
        $catalog = $raw | ConvertFrom-Json
        if (-not (Test-ToolSoftwareCatalogObject -Catalog $catalog)) { return $null }
        $catalog | Add-Member -NotePropertyName CatalogSource -NotePropertyValue $Source -Force
        $catalog | Add-Member -NotePropertyName CatalogPath -NotePropertyValue ([IO.Path]::GetFullPath($Path)) -Force
        $catalog | Add-Member -NotePropertyName CatalogSha256 -NotePropertyValue (Get-ToolSoftwareSha256Text -Text $raw) -Force
        return $catalog
    } catch { return $null }
}

function Get-ToolSoftwareLicenseCatalog {
    param([switch]$PreferCache)
    $bundled = Import-ToolSoftwareCatalogFile -Path (Get-ToolSoftwareCatalogBundledPath) -Source 'Bundled'
    $cache = $null
    $cachePath = Get-ToolSoftwareCatalogCachePath
    if ($PreferCache -and -not [string]::IsNullOrWhiteSpace($cachePath)) {
        $cache = Import-ToolSoftwareCatalogFile -Path $cachePath -Source 'OnlineCache'
    }
    if ($cache) {
        $cacheVersion = [version]'0.0'
        $bundledVersion = [version]'0.0'
        try { $cacheVersion = [version](Get-ToolSoftwareOptionalPropertyString -InputObject $cache -Name 'CatalogVersion' -Default '0.0') } catch {}
        try { if ($bundled) { $bundledVersion = [version](Get-ToolSoftwareOptionalPropertyString -InputObject $bundled -Name 'CatalogVersion' -Default '0.0') } } catch {}
        if (-not $bundled -or $cacheVersion -ge $bundledVersion) { return $cache }
    }
    return $bundled
}

function Test-ToolSoftwareCatalogTrustedForDecisiveEvidence {
    param([AllowNull()][object]$Catalog)
    if (-not $Catalog) { return $false }
    $catalogSource = Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogSource'
    $catalogSha256 = Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogSha256'
    if ($catalogSource -in @('Bundled','Fixture')) { return $true }
    if ($catalogSource -ne 'OnlineCache' -or [string]::IsNullOrWhiteSpace($catalogSha256)) { return $false }
    $cacheKey = ($catalogSource + '|' + $catalogSha256)
    if ($script:ToolSoftwareCatalogTrustCache.ContainsKey($cacheKey)) { return [bool]$script:ToolSoftwareCatalogTrustCache[$cacheKey] }
    $bundled = Import-ToolSoftwareCatalogFile -Path (Get-ToolSoftwareCatalogBundledPath) -Source 'Bundled'
    $trusted = [bool]($bundled -and
        (Get-ToolSoftwareOptionalPropertyString -InputObject $bundled -Name 'CatalogSha256') -eq $catalogSha256)
    $script:ToolSoftwareCatalogTrustCache[$cacheKey] = $trusted
    return $trusted
}

function Invoke-ToolSoftwareCatalogHttpGet {
    param([Parameter(Mandatory = $true)][uri]$Uri, [int]$TimeoutMilliseconds = 15000)
    if ($Uri.Scheme -ne 'https' -or $script:ToolSoftwareCatalogAllowedHosts -notcontains $Uri.DnsSafeHost.ToLowerInvariant()) {
        throw 'Catalog URL is outside the HTTPS allowlist.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'ThanhViet-Tool-Kiem-Tra/4.8 software-catalog'
    $response = $null
    $stream = $null
    $reader = $null
    try {
        $response = [Net.HttpWebResponse]$request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw ('HTTP ' + [int]$response.StatusCode) }
        if ($response.ContentLength -gt 2097152) { throw 'Catalog exceeds the 2 MiB limit.' }
        $stream = $response.GetResponseStream()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true, 8192)
        $builder = New-Object Text.StringBuilder
        $buffer = New-Object char[] 8192
        $total = 0
        while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt 2097152) { throw 'Catalog exceeds the 2 MiB limit.' }
            [void]$builder.Append($buffer, 0, $read)
        }
        return $builder.ToString()
    } finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Update-ToolSoftwareLicenseCatalog {
    param(
        [Parameter(Mandatory = $true)][switch]$ConsentGranted,
        [string]$CatalogUrl = $script:ToolSoftwareCatalogDefaultUrl
    )
    if (-not $ConsentGranted) { throw 'Explicit user consent is required.' }
    $started = [DateTime]::UtcNow
    $uri = [uri]$CatalogUrl
    $tempPath = ''
    try {
        $raw = Invoke-ToolSoftwareCatalogHttpGet -Uri $uri
        $catalog = $raw | ConvertFrom-Json
        if (-not (Test-ToolSoftwareCatalogObject -Catalog $catalog)) { throw 'Downloaded catalog failed schema validation.' }
        $cachePath = Get-ToolSoftwareCatalogCachePath
        if ([string]::IsNullOrWhiteSpace($cachePath)) { throw 'Local catalog cache is unavailable.' }
        $cacheDirectory = Split-Path -Parent $cachePath
        if (-not (Test-Path -LiteralPath $cacheDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
        }
        $tempPath = Join-Path $cacheDirectory ('.catalog-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($tempPath, $raw, (New-Object Text.UTF8Encoding($false)))
        $verified = Import-ToolSoftwareCatalogFile -Path $tempPath -Source 'OnlineCache'
        if (-not $verified) { throw 'Downloaded catalog could not be reopened safely.' }
        Move-Item -LiteralPath $tempPath -Destination $cachePath -Force
        return [pscustomobject][ordered]@{
            Success=$true
            CatalogVersion=(Get-ToolSoftwareOptionalPropertyString -InputObject $catalog -Name 'CatalogVersion')
            ProductRuleCount=[int]@(Get-ToolSoftwareOptionalPropertyValues -InputObject $catalog -Name 'Products').Count
            CachePath=$cachePath; SourceUrl=$uri.AbsoluteUri; Sha256=(Get-ToolSoftwareSha256Text -Text $raw)
            StartedAtUtc=$started.ToString('o'); CompletedAtUtc=[DateTime]::UtcNow.ToString('o'); Error=''
            UploadedInventory=$false; SentLicenseKeys=$false
        }
    } catch {
        return [pscustomobject][ordered]@{
            Success=$false; CatalogVersion=''; ProductRuleCount=0; CachePath=(Get-ToolSoftwareCatalogCachePath)
            SourceUrl=$uri.AbsoluteUri; Sha256=''; StartedAtUtc=$started.ToString('o'); CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
            Error=[string]$_.Exception.Message; UploadedInventory=$false; SentLicenseKeys=$false
        }
    } finally {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-ToolSoftwareRegistryPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ([string]$Path -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')
}

function Get-ToolSoftwareExecutablePath {
    param([string[]]$Candidates, [string]$PreferredName = '')
    foreach ($candidateText in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateText)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$candidateText).Trim()
        $candidatePath = ''
        if ($expanded -match '^\s*"([^"]+?\.exe)"') { $candidatePath = [string]$matches[1] }
        elseif ($expanded -match '^\s*([^,]+?\.exe)(?:\s|,|$)') { $candidatePath = [string]$matches[1] }
        $candidatePath = $candidatePath.Trim().Trim('"')
        if ($candidatePath -and [IO.Path]::IsPathRooted($candidatePath)) {
            try {
                $full = [IO.Path]::GetFullPath($candidatePath)
                if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
            } catch {}
        }
        $directory = $expanded.Trim('"').TrimEnd('\')
        if (-not [IO.Path]::IsPathRooted($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        try {
            $preferredToken = ([regex]::Replace($PreferredName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
            $files = @(Get-ChildItem -LiteralPath $directory -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)^(unins|uninstall|setup|update|helper|crash|report)' } | Select-Object -First 40)
            if ($files.Count -eq 0) { continue }
            if ($preferredToken) {
                $match = $files | Where-Object {
                    $fileToken = ([regex]::Replace([string]$_.BaseName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
                    $fileToken -and ($preferredToken.Contains($fileToken) -or $fileToken.Contains($preferredToken))
                } | Select-Object -First 1
                if ($match) { return [string]$match.FullName }
            }
            return [string]$files[0].FullName
        } catch {}
    }
    return ''
}

function Get-ToolSoftwareSignatureState {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ Status='NotChecked'; Publisher=''; FileVersion=''; ProductName=''; CompanyName=''; Path='' }
    }
    $key = ''
    try {
        $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $key = (([IO.Path]::GetFullPath([string]$file.FullName)).ToLowerInvariant() + '|' + [string]$file.Length + '|' + [string]$file.LastWriteTimeUtc.Ticks)
        if ($script:ToolSoftwareSignatureCache.ContainsKey($key)) { return $script:ToolSoftwareSignatureCache[$key] }
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $publisher = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        $result = [pscustomobject][ordered]@{
            Status=[string]$signature.Status; Publisher=$publisher; FileVersion=[string]$file.VersionInfo.FileVersion
            ProductName=[string]$file.VersionInfo.ProductName; CompanyName=[string]$file.VersionInfo.CompanyName; Path=[string]$file.FullName
        }
    } catch {
        $result = [pscustomobject][ordered]@{ Status='UnknownError'; Publisher=''; FileVersion=''; ProductName=''; CompanyName=''; Path=$Path }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$key)) { $script:ToolSoftwareSignatureCache[$key] = $result }
    return $result
}

function Get-ToolSoftwareSignatureStatesParallel {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        [ValidateRange(1, 6)][int]$ThrottleLimit = 4,
        [AllowNull()][object]$RunspacePool
    )
    $results = @{}
    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($path in @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $pathKey = ([string]$path).ToLowerInvariant()
        try {
            $file = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            $fullPath = [IO.Path]::GetFullPath([string]$file.FullName)
            $pathKey = $fullPath.ToLowerInvariant()
            $cacheKey = ($pathKey + '|' + [string]$file.Length + '|' + [string]$file.LastWriteTimeUtc.Ticks)
            if ($script:ToolSoftwareSignatureCache.ContainsKey($cacheKey)) {
                $results[$pathKey] = $script:ToolSoftwareSignatureCache[$cacheKey]
            } else {
                $pending.Add([pscustomobject][ordered]@{ Path=$fullPath; PathKey=$pathKey; CacheKey=$cacheKey })
            }
        } catch {
            $results[$pathKey] = [pscustomobject][ordered]@{
                Status='UnknownError'; Publisher=''; FileVersion=''; ProductName=''; CompanyName=''; Path=[string]$path
            }
        }
    }
    if ($pending.Count -eq 0) { return $results }
    if ($pending.Count -eq 1) {
        $item = $pending[0]
        $result = Get-ToolSoftwareSignatureState -Path ([string]$item.Path)
        $results[[string]$item.PathKey] = $result
        return $results
    }

    $ownsPool = [bool]($null -eq $RunspacePool)
    $pool = $RunspacePool
    if ($ownsPool) {
        $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($ThrottleLimit, $pending.Count))
        $pool.Open()
    }
    $workers = New-Object System.Collections.Generic.List[object]
    $workerScript = @'
param($SignaturePath,$SignatureCacheKey,$SignaturePathKey)
try {
    $file = Get-Item -LiteralPath $SignaturePath -Force -ErrorAction Stop
    $signature = Get-AuthenticodeSignature -FilePath $SignaturePath -ErrorAction Stop
    [pscustomobject][ordered]@{
        CacheKey=$SignatureCacheKey; PathKey=$SignaturePathKey; Status=[string]$signature.Status
        Publisher=$(if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' })
        FileVersion=[string]$file.VersionInfo.FileVersion; ProductName=[string]$file.VersionInfo.ProductName
        CompanyName=[string]$file.VersionInfo.CompanyName; Path=[string]$file.FullName
    }
} catch {
    [pscustomobject][ordered]@{
        CacheKey=$SignatureCacheKey; PathKey=$SignaturePathKey; Status='UnknownError'; Publisher=''
        FileVersion=''; ProductName=''; CompanyName=''; Path=$SignaturePath
    }
}
'@
    try {
        foreach ($item in $pending) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($workerScript).AddArgument([string]$item.Path).AddArgument([string]$item.CacheKey).AddArgument([string]$item.PathKey)
            $workers.Add([pscustomobject][ordered]@{ PowerShell=$powerShell; Handle=$powerShell.BeginInvoke(); Item=$item })
        }
        foreach ($worker in $workers) {
            $output = @()
            try { $output = @($worker.PowerShell.EndInvoke($worker.Handle)) }
            finally { $worker.PowerShell.Dispose() }
            $value = @($output | Select-Object -First 1)
            if ($value.Count -eq 0) {
                $fallback = Get-ToolSoftwareSignatureState -Path ([string]$worker.Item.Path)
                $results[[string]$worker.Item.PathKey] = $fallback
                continue
            }
            $raw = $value[0]
            $result = [pscustomobject][ordered]@{
                Status=[string]$raw.Status; Publisher=[string]$raw.Publisher; FileVersion=[string]$raw.FileVersion
                ProductName=[string]$raw.ProductName; CompanyName=[string]$raw.CompanyName; Path=[string]$raw.Path
            }
            $script:ToolSoftwareSignatureCache[[string]$raw.CacheKey] = $result
            $results[[string]$raw.PathKey] = $result
        }
    } finally {
        foreach ($worker in $workers) { try { $worker.PowerShell.Dispose() } catch {} }
        if ($ownsPool) {
            try { $pool.Close() } catch {}
            $pool.Dispose()
        }
    }
    return $results
}

function ConvertTo-ToolSoftwareIdentityToken {
    param([AllowNull()][string]$Value, [switch]$Name)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $token = $Value.Trim().ToLowerInvariant()
    if ($Name) {
        $token = [regex]::Replace($token, '(?i)\s*(?:\(|\[)?(?:x64|x86|64-bit|32-bit|amd64|arm64)(?:\)|\])?\s*$', '')
        $token = [regex]::Replace($token, '(?i)\s+version\s+[0-9][0-9a-z._-]*\s*$', '')
    }
    return ([regex]::Replace($token, '[^\p{L}\p{Nd}]+', ' ')).Trim()
}

function Get-ToolSoftwareNormalizedLocation {
    param([AllowNull()][object]$Record)
    foreach ($candidate in @([string]$Record.InstallLocation, $(if ($Record.RepresentativePath) { Split-Path -Parent ([string]$Record.RepresentativePath) }))) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try { return ([IO.Path]::GetFullPath($candidate)).TrimEnd('\').ToLowerInvariant() } catch {}
    }
    return ''
}

function Test-ToolSoftwareLikelySystemComponent {
    param(
        [string]$Name, [string]$Publisher, [string]$SourceKind, [string]$InstallLocation,
        [bool]$DeclaredSystemComponent = $false, [string]$ReleaseType = '', [bool]$NonRemovable = $false
    )
    if ($DeclaredSystemComponent -or $NonRemovable) { return $true }
    if ($ReleaseType -match '(?i)^(?:update|security update|hotfix|driver|language pack)$') { return $true }
    if ($Name -match '(?i)^(?:Update for |Security Update for |Hotfix for |Windows Driver Package|Microsoft Windows Desktop Runtime|Microsoft ASP\.NET Core|Microsoft \.NET Framework|Microsoft Visual C\+\+.*Redistributable|Microsoft Edge(?: Update| WebView2 Runtime)?$|Microsoft OneDrive$|Internet Explorer$|Windows SDK|Windows Software Development Kit|Windows App Certification Kit|Windows PC Health Check|Microsoft(?:®|\s+\(R\))? Windows(?:®|\s+\(R\))? Operating System)') { return $true }
    if ($Publisher -match '(?i)\bMicrosoft(?: Corporation)?\b' -and $Name -match '(?i)\b(?:Setup Support Files|Native Client|System CLR Types|Transact-SQL (?:Compiler Service|ScriptDom)|VSS Writer|Prerequisites|Multi-Targeting Pack|Policies|Meeting Add-in|Help Viewer|Update Health Tools)\b') { return $true }
    if ($Name -match '(?i)^(?:uninstall(?:er)?\b|.*\(remove only\)$)|\b(?:driver|runtime|redistributable|language pack|support component|service components|update service|framework|sdk|hal)\b' -and
        $Publisher -match '(?i)\b(?:Microsoft|Intel|AMD|NVIDIA|Realtek|Qualcomm|Broadcom|ASUS|ASUSTeK|Canon|Toshiba)\b') { return $true }
    if ($Publisher -match '(?i)\b(?:ASUS|ASUSTeK|Intel|AMD|NVIDIA|Realtek|Qualcomm|Broadcom)\b' -and
        $Name -match '(?i)(?:HAL|Framework|SDK|Service|Driver)(?:32|64)?$') { return $true }
    if ($Name -match '(?i)\b(?:driver|chipset|runtime|redistributable|language pack|support component|update service)\b' -and
        $Publisher -match '(?i)\b(?:Microsoft|Intel|AMD|NVIDIA|Realtek|Qualcomm|Broadcom)\b') { return $true }
    # AppX do Microsoft phát hành phần lớn là thành phần/hộp thư mặc định của
    # Windows. Giữ Teams và Visual Studio Code trong luồng ứng dụng chính;
    # phần còn lại vẫn có đủ dữ liệu trong phụ lục/JSON nhưng không làm dài
    # bảng tổng quan và PDF.
    if ($SourceKind -eq 'Appx' -and $Publisher -match '(?i)(?:Microsoft|CN=Microsoft)' -and
        $Name -notmatch '(?i)^(?:MSTeams|Microsoft\.VisualStudioCode)$') { return $true }
    if ($SourceKind -eq 'Appx' -and $Name -match '(?i)(?:CoreApp|ShellExtension|ImageExtension|VideoExtension|MediaExtension|Runtime|Framework|Utility|Service)$') { return $true }
    if ($InstallLocation -and $InstallLocation -match '(?i)\\Windows\\(?:System32|SysWOW64|WinSxS|SystemApps)(?:\\|$)') { return $true }
    return $false
}

function ConvertTo-ToolSoftwarePublisherToken {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $publisher = $Value.Trim()
    $cn = [regex]::Match($publisher, '(?i)(?:^|,\s*)CN\s*=\s*("(?:[^"]|"")*"|[^,]+)')
    if ($cn.Success) { $publisher = $cn.Groups[1].Value.Trim().Trim('"') }
    $publisher = ConvertTo-ToolSoftwareIdentityToken -Value $publisher
    $publisher = [regex]::Replace($publisher, '(?i)\b(?:incorporated|inc|corporation|corp|company|co|limited|ltd|llc|pte|plc)\b', ' ')
    return ([regex]::Replace($publisher, '\s+', ' ')).Trim()
}

function Test-ToolSoftwareVersionCompatible {
    param([AllowNull()][string]$Left, [AllowNull()][string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $true }
    $leftToken = (ConvertTo-ToolSoftwareIdentityToken -Value $Left)
    $rightToken = (ConvertTo-ToolSoftwareIdentityToken -Value $Right)
    if ($leftToken -eq $rightToken) { return $true }
    $leftVersion = [regex]::Replace([regex]::Match($Left, '\d+(?:\.\d+){0,5}').Value, '(?:\.0)+$', '')
    $rightVersion = [regex]::Replace([regex]::Match($Right, '\d+(?:\.\d+){0,5}').Value, '(?:\.0)+$', '')
    if (-not $leftVersion -or -not $rightVersion) { return $false }
    return [bool]($leftVersion -eq $rightVersion -or
        $leftVersion.StartsWith($rightVersion + '.', [StringComparison]::OrdinalIgnoreCase) -or
        $rightVersion.StartsWith($leftVersion + '.', [StringComparison]::OrdinalIgnoreCase))
}

function Get-ToolSoftwareComparableVersion {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $match = [regex]::Match($Value, '\d+(?:\.\d+){0,5}')
    if (-not $match.Success) { return '' }
    return [regex]::Replace($match.Value, '(?:\.0)+$', '')
}

function New-ToolSoftwareMergeDescriptor {
    param([Parameter(Mandatory = $true)]$Record, [int]$OriginalIndex)
    $versionText = [string]$Record.Version
    $versionParts = @([regex]::Matches($versionText, '\d+') | ForEach-Object { $_.Value })
    $sourceKind = [string]$Record.SourceKind
    $nameKey = ConvertTo-ToolSoftwareIdentityToken -Value ([string]$Record.Name) -Name
    $nameSeparator = $nameKey.IndexOf(' ')
    return [pscustomobject][ordered]@{
        Record = $Record
        OriginalIndex = $OriginalIndex
        NameKey = $nameKey
        NameBucket = $(if ($nameSeparator -gt 0) { $nameKey.Substring(0, $nameSeparator) } else { $nameKey })
        VersionText = $versionText
        VersionKey = ConvertTo-ToolSoftwareIdentityToken -Value $versionText
        ComparableVersion = Get-ToolSoftwareComparableVersion -Value $versionText
        VersionFamily = $(if ($versionParts.Count -ge 3) { $versionParts[0..2] -join '.' } else { '' })
        PublisherKey = ConvertTo-ToolSoftwarePublisherToken -Value ([string]$Record.Publisher)
        LocationKey = Get-ToolSoftwareNormalizedLocation -Record $Record
        SourceKind = $sourceKind
        SourceRank = $(switch ($sourceKind) { 'Registry' {0}; 'Appx' {1}; 'Shortcut' {2}; default {3} })
    }
}

function Test-ToolSoftwareMergeVersionCompatible {
    param([Parameter(Mandatory = $true)]$Left, [Parameter(Mandatory = $true)]$Right)
    if ([string]::IsNullOrWhiteSpace([string]$Left.VersionText) -or [string]::IsNullOrWhiteSpace([string]$Right.VersionText)) { return $true }
    if ([string]$Left.VersionKey -eq [string]$Right.VersionKey) { return $true }
    $leftVersion = [string]$Left.ComparableVersion
    $rightVersion = [string]$Right.ComparableVersion
    if (-not $leftVersion -or -not $rightVersion) { return $false }
    return [bool]($leftVersion -eq $rightVersion -or
        $leftVersion.StartsWith($rightVersion + '.', [StringComparison]::OrdinalIgnoreCase) -or
        $rightVersion.StartsWith($leftVersion + '.', [StringComparison]::OrdinalIgnoreCase))
}

function Merge-ToolSoftwareInventoryRecords {
    param([object[]]$Records)

    # Precompute normalized identity fields once. The previous implementation
    # recalculated several regex/path transforms for every record/cluster pair;
    # on a 400+ application machine that dominated the entire scan time while
    # producing the same merge decision.
    $descriptors = New-Object System.Collections.Generic.List[object]
    $sortedRecords = @($Records | Where-Object { $null -ne $_ } | Sort-Object Name,Version,Publisher)
    for ($recordIndex = 0; $recordIndex -lt $sortedRecords.Count; $recordIndex++) {
        $descriptors.Add((New-ToolSoftwareMergeDescriptor -Record $sortedRecords[$recordIndex] -OriginalIndex $recordIndex))
    }

    $clusters = New-Object System.Collections.Generic.List[object]
    $clustersByNameBucket = @{}
    foreach ($descriptor in $descriptors) {
        $record = $descriptor.Record
        $nameKey = [string]$descriptor.NameKey
        $publisherKey = [string]$descriptor.PublisherKey
        $locationKey = [string]$descriptor.LocationKey
        $matchedCluster = $null
        # A merge requires equal normalized names or a prefix alias. Both cases
        # necessarily share the first normalized name token. Restricting the
        # candidate list to that token preserves the exact decision order while
        # avoiding an O(n^2) walk across unrelated products.
        $nameBucket = [string]$descriptor.NameBucket
        $candidateClusters = if ($nameBucket -and $clustersByNameBucket.ContainsKey($nameBucket)) {
            $clustersByNameBucket[$nameBucket]
        } elseif ($nameBucket) {
            @()
        } else {
            $clusters
        }
        foreach ($cluster in $candidateClusters) {
            $headDescriptor = $cluster.Head
            $head = $headDescriptor.Record
            $headName = [string]$headDescriptor.NameKey
            $headPublisher = [string]$headDescriptor.PublisherKey
            $headLocation = [string]$headDescriptor.LocationKey
            $versionCompatible = Test-ToolSoftwareMergeVersionCompatible -Left $descriptor -Right $headDescriptor
            $publisherCompatible = [bool](-not $publisherKey -or -not $headPublisher -or $publisherKey -eq $headPublisher -or
                ($publisherKey.Length -ge 4 -and $headPublisher.Length -ge 4 -and
                    ($publisherKey.StartsWith($headPublisher + ' ', [StringComparison]::OrdinalIgnoreCase) -or
                     $headPublisher.StartsWith($publisherKey + ' ', [StringComparison]::OrdinalIgnoreCase))))
            $locationCompatible = [bool](-not $locationKey -or -not $headLocation -or $locationKey -eq $headLocation -or
                $locationKey.StartsWith($headLocation + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $headLocation.StartsWith($locationKey + '\', [StringComparison]::OrdinalIgnoreCase))
            $sameLocation = [bool]($locationKey -and $headLocation -and $locationKey -eq $headLocation)
            $recordSource = [string]$descriptor.SourceKind
            $headSource = [string]$headDescriptor.SourceKind
            $complementarySources = [bool](
                ($recordSource -eq 'Registry' -and $headSource -in @('Shortcut','PortableDiscovery','Appx')) -or
                ($headSource -eq 'Registry' -and $recordSource -in @('Shortcut','PortableDiscovery','Appx'))
            )
            $sameVersionFamily = [bool]($descriptor.VersionFamily -and $headDescriptor.VersionFamily -and
                [string]$descriptor.VersionFamily -eq [string]$headDescriptor.VersionFamily)
            $nameCompatible = [bool]($nameKey -eq $headName)
            $exactProductIdentity = [bool]($nameKey -eq $headName -and $publisherKey -and $headPublisher -and
                $publisherCompatible -and ($versionCompatible -or $sameVersionFamily))
            # Registry/shortcut/Appx đôi khi thêm hậu tố edition hoặc dấu vết
            # nhận diện vào cùng sản phẩm (ví dụ "FineReader PDF by ..."). Chỉ
            # cho phép alias chứa nhau khi version, publisher và thư mục cài
            # trùng chính xác để không gộp nhầm hai sản phẩm cùng hãng.
            if (-not $nameCompatible -and ($sameLocation -or $complementarySources) -and $versionCompatible -and $publisherCompatible -and
                $nameKey.Length -ge 5 -and $headName.Length -ge 5) {
                $nameCompatible = [bool]($nameKey.StartsWith($headName + ' ', [StringComparison]::OrdinalIgnoreCase) -or
                    $headName.StartsWith($nameKey + ' ', [StringComparison]::OrdinalIgnoreCase))
            }
            if (-not $nameCompatible) { continue }
            $architectureConflict = [bool]([string]$record.Architecture -match '32' -and [string]$head.Architecture -match '64' -or
                [string]$record.Architecture -match '64' -and [string]$head.Architecture -match '32')
            $versionCompatibleForMerge = [bool]($versionCompatible -or
                $exactProductIdentity -or
                ($nameCompatible -and $publisherCompatible -and $complementarySources -and ($sameLocation -or $sameVersionFamily)))
            if ($versionCompatibleForMerge -and $publisherCompatible -and ($locationCompatible -or $complementarySources -or $exactProductIdentity) -and
                (-not $architectureConflict -or $locationKey -eq $headLocation -or $exactProductIdentity)) {
                $matchedCluster = $cluster
                break
            }
        }
        if ($null -eq $matchedCluster) {
            $matchedCluster = [pscustomobject][ordered]@{
                Head = $descriptor
                Items = New-Object System.Collections.Generic.List[object]
            }
            $clusters.Add($matchedCluster)
            if ($nameBucket) {
                if (-not $clustersByNameBucket.ContainsKey($nameBucket)) {
                    $clustersByNameBucket[$nameBucket] = New-Object System.Collections.Generic.List[object]
                }
                $clustersByNameBucket[$nameBucket].Add($matchedCluster)
            }
        }
        $matchedCluster.Items.Add($descriptor)
    }

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($cluster in $clusters) {
        # PowerShell 5.1 can throw "Argument types do not match" when a generic
        # List[object] is wrapped directly in @(). Enumerating it explicitly keeps
        # this path compatible with the runtime used by the packaged EXE.
        $clusterDescriptors = @($cluster.Items | ForEach-Object { $_ })
        $clusterRecords = @($clusterDescriptors | ForEach-Object { $_.Record })
        # Keep the exact legacy tie-breaking behavior for records discovered from
        # the same source rank, so optimization cannot change the displayed name,
        # scope or representative path of an existing merged product.
        $preferred = @($clusterRecords | Sort-Object @{Expression={ switch ([string]$_.SourceKind) { 'Registry' {0}; 'Appx' {1}; 'Shortcut' {2}; default {3} } }})[0]
        foreach ($propertyName in @('Version','Publisher','InstallDate','InstallLocation','DisplayIcon','UninstallString','RegistryPath','Scope','Architecture','RepresentativePath','SignaturePublisher','FileVersion')) {
            if (-not [string]::IsNullOrWhiteSpace([string]$preferred.$propertyName)) { continue }
            $value = @($clusterRecords | ForEach-Object { $_.$propertyName } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
            if ($value.Count -gt 0) { $preferred | Add-Member -NotePropertyName $propertyName -NotePropertyValue $value[0] -Force }
        }
        $sources = @($clusterRecords | ForEach-Object {
            if ($_.PSObject.Properties['DiscoverySources']) { @($_.DiscoverySources) }
            if ($_.PSObject.Properties['SourceKind']) { [string]$_.SourceKind }
        } | Where-Object { $_ } | Select-Object -Unique)
        $details = @($clusterRecords | ForEach-Object { [string]$_.SourceDetail } | Where-Object { $_ } | Select-Object -Unique)
        $registryPaths = @($clusterRecords | ForEach-Object { [string]$_.RegistryPath } | Where-Object { $_ } | Select-Object -Unique)
        $installLocations = @($clusterDescriptors | ForEach-Object { [string]$_.LocationKey } | Where-Object { $_ } | Select-Object -Unique)
        $architectures = @($clusterRecords | ForEach-Object { [string]$_.Architecture } | Where-Object { $_ } | Select-Object -Unique)
        $systemComponent = [bool](@($clusterRecords | Where-Object { $_.PSObject.Properties['IsSystemComponent'] -and [bool]$_.IsSystemComponent }).Count -gt 0)
        $systemReasons = @($clusterRecords | ForEach-Object { [string]$_.SystemComponentReason } | Where-Object { $_ } | Select-Object -Unique)
        $preferred | Add-Member -NotePropertyName DiscoverySources -NotePropertyValue $sources -Force
        $preferred | Add-Member -NotePropertyName DiscoveryDetails -NotePropertyValue $details -Force
        $preferred | Add-Member -NotePropertyName RegistryPaths -NotePropertyValue $registryPaths -Force
        $preferred | Add-Member -NotePropertyName InstallLocations -NotePropertyValue $installLocations -Force
        $preferred | Add-Member -NotePropertyName Architectures -NotePropertyValue $architectures -Force
        if ($architectures.Count -gt 1) { $preferred | Add-Member -NotePropertyName Architecture -NotePropertyValue ($architectures -join ', ') -Force }
        $preferred | Add-Member -NotePropertyName MergedRecordCount -NotePropertyValue ([int]$clusterRecords.Count) -Force
        $preferred | Add-Member -NotePropertyName IsSystemComponent -NotePropertyValue $systemComponent -Force
        $preferred | Add-Member -NotePropertyName SystemComponentReason -NotePropertyValue ($systemReasons -join '; ') -Force
        $stableIdentity = (@((ConvertTo-ToolSoftwareIdentityToken -Value ([string]$preferred.Name) -Name),([string]$preferred.Version),(Get-ToolSoftwareNormalizedLocation -Record $preferred)) -join '|').ToLowerInvariant()
        $preferred | Add-Member -NotePropertyName Id -NotePropertyValue (Get-ToolSoftwareStableId -Value $stableIdentity) -Force
        $merged.Add($preferred)
    }
    return @($merged.ToArray() | Sort-Object Name,Version,Publisher)
}

function New-ToolSoftwareInventoryRecord {
    param(
        [string]$Name, [string]$Version, [string]$Publisher, [string]$InstallDate,
        [string]$InstallLocation, [string]$DisplayIcon, [string]$UninstallString,
        [string]$RegistryPath, [string]$Scope, [string]$Architecture,
        [string]$SourceKind, [string]$RepresentativePath, [string]$SourceDetail = '',
        [bool]$IsSystemComponent = $false, [string]$SystemComponentReason = '', [string]$ReleaseType = '', [bool]$NonRemovable = $false,
        [switch]$SkipSignature, [switch]$SkipExecutableDiscovery
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    if (-not $SkipExecutableDiscovery -and [string]::IsNullOrWhiteSpace($RepresentativePath)) {
        $RepresentativePath = Get-ToolSoftwareExecutablePath -Candidates @($DisplayIcon, $InstallLocation, $UninstallString) -PreferredName $Name
    }
    $signature = if ($SkipSignature) {
        [pscustomobject][ordered]@{ Status='NotChecked'; Publisher=''; FileVersion=''; ProductName=''; CompanyName=''; Path='' }
    } else { Get-ToolSoftwareSignatureState -Path $RepresentativePath }
    if ([string]::IsNullOrWhiteSpace($Publisher) -and $signature.CompanyName) { $Publisher = [string]$signature.CompanyName }
    if ([string]::IsNullOrWhiteSpace($Version) -and $signature.FileVersion) { $Version = [string]$signature.FileVersion }
    if ([string]::IsNullOrWhiteSpace($InstallLocation) -and $RepresentativePath) { $InstallLocation = Split-Path -Parent $RepresentativePath }
    $identity = (@($Name,$Version,$Publisher,$InstallLocation,$RepresentativePath,$SourceKind) -join '|').ToLowerInvariant()
    $classifiedAsSystem = Test-ToolSoftwareLikelySystemComponent -Name $Name -Publisher $Publisher -SourceKind $SourceKind `
        -InstallLocation $InstallLocation -DeclaredSystemComponent:$IsSystemComponent -ReleaseType $ReleaseType -NonRemovable:$NonRemovable
    if ($classifiedAsSystem -and [string]::IsNullOrWhiteSpace($SystemComponentReason)) { $SystemComponentReason = 'HeuristicOrPlatformMetadata' }
    return [pscustomobject][ordered]@{
        Id=Get-ToolSoftwareStableId -Value $identity; Name=$Name.Trim(); Version=$Version; Publisher=$Publisher
        InstallDate=(ConvertTo-ToolSoftwareInstallDateText -Value $InstallDate); InstallLocation=$InstallLocation; DisplayIcon=$DisplayIcon; UninstallString=$UninstallString
        RegistryPath=$RegistryPath; Scope=$Scope; Architecture=$Architecture; SourceKind=$SourceKind; SourceDetail=$SourceDetail
        RepresentativePath=$RepresentativePath; SignatureStatus=[string]$signature.Status; SignaturePublisher=[string]$signature.Publisher
        FileVersion=[string]$signature.FileVersion; IsMicrosoft=[bool]($Publisher -match '(?i)\bMicrosoft\b' -or $Name -match '(?i)^\s*(Microsoft|Windows)\b')
        IsSystemComponent=[bool]$classifiedAsSystem; SystemComponentReason=$SystemComponentReason
    }
}

function Get-ToolRegistrySoftwareInventory {
    $records = New-Object System.Collections.Generic.List[object]
    $sources = New-Object System.Collections.Generic.List[object]
    $sources.Add([pscustomobject]@{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Machine64'; Architecture=$(if ([Environment]::Is64BitOperatingSystem) {'64-bit'} else {'32-bit'}) })
    $sources.Add([pscustomobject]@{ Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='Machine32'; Architecture='32-bit' })
    $sources.Add([pscustomobject]@{ Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope='CurrentUser'; Architecture='CurrentUser' })
    try {
        foreach ($sid in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' })) {
            $sources.Add([pscustomobject]@{ Path=('Registry::HKEY_USERS\' + $sid.PSChildName + '\Software\Microsoft\Windows\CurrentVersion\Uninstall'); Scope=('User:' + $sid.PSChildName); Architecture='CurrentUser' })
        }
    } catch {}
    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) { continue }
        try {
            foreach ($key in @(Get-ChildItem -LiteralPath $source.Path -ErrorAction Stop)) {
                try {
                    $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    if ([string]::IsNullOrWhiteSpace([string]$entry.DisplayName)) { continue }
                    $record = New-ToolSoftwareInventoryRecord -Name ([string]$entry.DisplayName) -Version ([string]$entry.DisplayVersion) `
                        -Publisher ([string]$entry.Publisher) -InstallDate ([string]$entry.InstallDate) -InstallLocation ([string]$entry.InstallLocation) `
                        -DisplayIcon ([string]$entry.DisplayIcon) -UninstallString ([string]$entry.UninstallString) `
                        -RegistryPath (ConvertTo-ToolSoftwareRegistryPath ([string]$key.PSPath)) -Scope ([string]$source.Scope) `
                        -Architecture ([string]$source.Architecture) -SourceKind 'Registry' `
                        -IsSystemComponent:([bool]([int]$entry.SystemComponent -eq 1 -or -not [string]::IsNullOrWhiteSpace([string]$entry.ParentKeyName))) `
                        -SystemComponentReason $(if ([int]$entry.SystemComponent -eq 1) {'Registry:SystemComponent'} elseif ($entry.ParentKeyName) {'Registry:ParentKeyName'} else {''}) `
                        -ReleaseType ([string]$entry.ReleaseType) -SkipSignature
                    if ($record) { $records.Add($record) }
                } catch {}
            }
        } catch {}
    }
    return $records.ToArray()
}

function Get-ToolAppxSoftwareInventory {
    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return $records.ToArray() }
    $packages = @()
    try { $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
    catch { try { $packages = @(Get-AppxPackage -ErrorAction Stop) } catch { $packages = @() } }
    foreach ($package in $packages) {
        if ([bool]$package.IsFramework -or [bool]$package.IsResourcePackage) { continue }
        $name = if ($package.Name) { [string]$package.Name } else { [string]$package.PackageFamilyName }
        $record = New-ToolSoftwareInventoryRecord -Name $name -Version ([string]$package.Version) -Publisher ([string]$package.Publisher) `
            -InstallDate '' -InstallLocation ([string]$package.InstallLocation) -DisplayIcon '' -UninstallString '' -RegistryPath '' `
            -Scope 'Appx' -Architecture ([string]$package.Architecture) -SourceKind 'Appx' -SourceDetail ([string]$package.PackageFullName) `
            -NonRemovable:([bool]$package.NonRemovable) -SystemComponentReason $(if ([bool]$package.NonRemovable) {'Appx:NonRemovable'} else {''}) `
            -SkipSignature -SkipExecutableDiscovery
        if ($record) { $records.Add($record) }
    }
    return $records.ToArray()
}

function Get-ToolShortcutSoftwareInventory {
    $records = New-Object System.Collections.Generic.List[object]
    $roots = @(
        [Environment]::GetFolderPath('CommonStartMenu'), [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('DesktopDirectory')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return $records.ToArray() }
    try {
        $count = 0
        foreach ($root in $roots) {
            foreach ($shortcutFile in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($count -ge 1000) { break }
                $count++
                try {
                    $shortcut = $shell.CreateShortcut($shortcutFile.FullName)
                    $target = [Environment]::ExpandEnvironmentVariables([string]$shortcut.TargetPath)
                    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Leaf) -or [IO.Path]::GetExtension($target) -ne '.exe') { continue }
                    $windowsRoot = [Environment]::ExpandEnvironmentVariables('%WINDIR%')
                    if ($target.StartsWith($windowsRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
                    $targetFile = Get-Item -LiteralPath $target -Force -ErrorAction Stop
                    $name = if ($targetFile.VersionInfo.ProductName) { [string]$targetFile.VersionInfo.ProductName } else { [string]$shortcutFile.BaseName }
                    $record = New-ToolSoftwareInventoryRecord -Name $name -Version ([string]$targetFile.VersionInfo.FileVersion) -Publisher ([string]$targetFile.VersionInfo.CompanyName) `
                        -InstallDate '' -InstallLocation (Split-Path -Parent $target) -DisplayIcon $target -UninstallString '' -RegistryPath '' `
                        -Scope 'Shortcut' -Architecture '' -SourceKind 'Shortcut' -RepresentativePath $target -SourceDetail ([string]$shortcutFile.FullName) -SkipSignature
                    if ($record) { $records.Add($record) }
                } catch {}
            }
        }
    } finally { if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } }
    return $records.ToArray()
}

function Get-ToolBoundedExecutableFiles {
    param([string[]]$Roots, [int]$MaximumDepth = 2, [int]$MaximumResults = 600)
    $results = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Queue
    foreach ($root in @($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique)) {
        $queue.Enqueue([pscustomobject]@{ Path=[IO.Path]::GetFullPath($root); Depth=0 })
    }
    $seen = @{}
    while ($queue.Count -gt 0 -and $results.Count -lt $MaximumResults) {
        $current = $queue.Dequeue()
        $key = ([string]$current.Path).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        try {
            $directory = Get-Item -LiteralPath $current.Path -Force -ErrorAction Stop
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $directory.FullName -Filter '*.exe' -File -Force -ErrorAction SilentlyContinue)) {
                if ($results.Count -ge $MaximumResults) { break }
                if ($file.Name -match '(?i)^(unins|uninstall|setup|update|helper|crash|report|install|vc_redist|dotnet)') { continue }
                $results.Add([string]$file.FullName)
            }
            if ([int]$current.Depth -lt $MaximumDepth) {
                foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 160)) {
                    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $queue.Enqueue([pscustomobject]@{ Path=[string]$child.FullName; Depth=([int]$current.Depth + 1) })
                    }
                }
            }
        } catch {}
    }
    return $results.ToArray()
}

function Get-ToolPortableSoftwareInventory {
    param([int]$MaximumResults = 350, [string[]]$ExcludedRoots = @())
    $records = New-Object System.Collections.Generic.List[object]
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' }))) {
        if ($root -and (Test-Path -LiteralPath $root -PathType Container)) { $roots.Add([string]$root) }
    }
    try {
        foreach ($drive in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
            foreach ($folder in @('PortableApps','Apps','Programs','Tools','Software')) {
                $candidate = Join-Path ([string]$drive.DeviceID + '\') $folder
                if (Test-Path -LiteralPath $candidate -PathType Container) { $roots.Add($candidate) }
            }
        }
    } catch {}
    $candidatePaths = @(Get-ToolBoundedExecutableFiles -Roots $roots.ToArray() -MaximumDepth 2 -MaximumResults ($MaximumResults * 4) | Where-Object {
        $candidatePath = [string]$_
        $excluded = $false
        foreach ($excludedRoot in @($ExcludedRoots)) {
            if ($candidatePath.Equals($excludedRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $candidatePath.StartsWith(($excludedRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
                $excluded = $true
                break
            }
        }
        -not $excluded
    })
    $representatives = @($candidatePaths | Group-Object { Split-Path -Parent ([string]$_) } | ForEach-Object {
        $directoryName = Split-Path ([string]$_.Name) -Leaf
        $directoryToken = ([regex]::Replace($directoryName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
        @($_.Group | ForEach-Object {
            $file = Get-Item -LiteralPath ([string]$_) -Force -ErrorAction SilentlyContinue
            if ($file) {
                $fileToken = ([regex]::Replace([string]$file.BaseName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
                [pscustomobject]@{
                    Path=[string]$file.FullName
                    Score=$(if ($directoryToken -and ($fileToken -eq $directoryToken -or $fileToken.Contains($directoryToken) -or $directoryToken.Contains($fileToken))) { 2 } else { 0 })
                    Length=[long]$file.Length
                }
            }
        } | Sort-Object Score,Length -Descending | Select-Object -First 1).Path
    } | Where-Object { $_ } | Select-Object -First $MaximumResults)
    foreach ($path in $representatives) {
        if ($records.Count -ge $MaximumResults) { break }
        $portableFile = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $portableFile) { continue }
        $name = [string]$portableFile.VersionInfo.ProductName
        if ([string]::IsNullOrWhiteSpace($name)) {
            $parentName = Split-Path (Split-Path -Parent $path) -Leaf
            if ($parentName -match '(?i)^(bin|x64|x86|amd64|app|application)$') { $parentName = Split-Path (Split-Path (Split-Path -Parent $path) -Parent) -Leaf }
            $name = $parentName
        }
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -lt 2) { continue }
        $record = New-ToolSoftwareInventoryRecord -Name $name -Version ([string]$portableFile.VersionInfo.FileVersion) -Publisher ([string]$portableFile.VersionInfo.CompanyName) `
            -InstallDate '' -InstallLocation (Split-Path -Parent $path) -DisplayIcon $path -UninstallString '' -RegistryPath '' `
            -Scope 'PortableDiscovery' -Architecture '' -SourceKind 'PortableDiscovery' -RepresentativePath $path -SkipSignature
        if ($record) { $records.Add($record) }
    }
    return $records.ToArray()
}

function Get-ToolInstalledSoftwareInventory {
    param([switch]$IncludeAppx, [switch]$IncludeShortcuts, [switch]$IncludePortable, [int]$PortableMaximumResults = 220)
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ToolRegistrySoftwareInventory)) { $all.Add($item) }
    if ($IncludeAppx) { foreach ($item in @(Get-ToolAppxSoftwareInventory)) { $all.Add($item) } }
    if ($IncludeShortcuts) { foreach ($item in @(Get-ToolShortcutSoftwareInventory)) { $all.Add($item) } }
    if ($IncludePortable) {
        $broadRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' })) |
            Where-Object { $_ } | ForEach-Object { try { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') } catch {} }
        $knownRoots = @($all.ToArray() | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation)) {
                try { [IO.Path]::GetFullPath([string]$_.InstallLocation).TrimEnd('\') } catch {}
            }
        } | Where-Object {
            $_ -and $_.Length -ge 8 -and $broadRoots -notcontains $_
        } | Sort-Object Length -Descending -Unique)
        foreach ($item in @(Get-ToolPortableSoftwareInventory -MaximumResults $PortableMaximumResults -ExcludedRoots $knownRoots)) {
            $candidatePath = ''
            try { if ($item.RepresentativePath) { $candidatePath = [IO.Path]::GetFullPath([string]$item.RepresentativePath) } } catch {}
            $coveredByRegisteredApplication = $false
            if ($candidatePath) {
                foreach ($knownRoot in $knownRoots) {
                    if ($candidatePath.Equals($knownRoot, [StringComparison]::OrdinalIgnoreCase) -or
                        $candidatePath.StartsWith(($knownRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) {
                        $coveredByRegisteredApplication = $true
                        break
                    }
                }
            }
            if (-not $coveredByRegisteredApplication) { $all.Add($item) }
        }
    }
    return @(Merge-ToolSoftwareInventoryRecords -Records $all.ToArray())
}

function Find-ToolSoftwareCatalogProduct {
    param([Parameter(Mandatory = $true)]$Application, [AllowNull()][object]$Catalog)
    if (-not $Catalog) { return $null }
    $name = [string]$Application.Name
    $publisher = [string]$Application.Publisher
    foreach ($product in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $Catalog -Name 'Products')) {
        $nameMatched = $false
        foreach ($pattern in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $product -Name 'NamePatterns')) { if ($name -match [string]$pattern) { $nameMatched = $true; break } }
        if (-not $nameMatched) { continue }
        $publisherPatterns = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $product -Name 'PublisherPatterns')
        if ($publisherPatterns.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($publisher)) {
            $publisherMatched = $false
            foreach ($pattern in $publisherPatterns) { if ($publisher -match [string]$pattern) { $publisherMatched = $true; break } }
            if (-not $publisherMatched) { continue }
        }
        return $product
    }
    return $null
}

function Get-ToolSoftwareKnownActivationState {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [AllowNull()][object]$CatalogProduct
    )

    if (-not $CatalogProduct) { return '' }
    $catalogProductId = Get-ToolSoftwareOptionalPropertyString -InputObject $CatalogProduct -Name 'Id'
    if ([string]$catalogProductId -ne 'winrar') { return '' }

    # WinRAR keeps its local registration in rarreg.key.  The program remains
    # usable in trial mode after this file is removed, therefore "the program
    # still opens" must never be interpreted as "the license is still active".
    # Probe only bounded, product-specific locations and report Unactivated
    # only when at least one real WinRAR location can be inspected.
    $locations = New-Object System.Collections.Generic.List[string]
    $probeAvailable = $false
    foreach ($rootCandidate in @([string]$Application.InstallLocation, $(if ($Application.RepresentativePath) { Split-Path -Parent ([string]$Application.RepresentativePath) }))) {
        if ([string]::IsNullOrWhiteSpace($rootCandidate)) { continue }
        try {
            $root = [IO.Path]::GetFullPath($rootCandidate).TrimEnd('\')
            if (Test-Path -LiteralPath $root -PathType Container) {
                $probeAvailable = $true
                $locations.Add((Join-Path $root 'rarreg.key'))
            }
        } catch {}
    }
    if ($env:APPDATA) {
        $userRoot = Join-Path $env:APPDATA 'WinRAR'
        if (Test-Path -LiteralPath $userRoot -PathType Container) { $probeAvailable = $true }
        $locations.Add((Join-Path $userRoot 'rarreg.key'))
    }
    if ($env:ProgramData) {
        $machineRoot = Join-Path $env:ProgramData 'WinRAR'
        if (Test-Path -LiteralPath $machineRoot -PathType Container) { $probeAvailable = $true }
        $locations.Add((Join-Path $machineRoot 'rarreg.key'))
    }

    foreach ($path in @($locations.ToArray() | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return 'LocalLicensePresent' }
    }
    if ($probeAvailable) { return 'Unactivated' }
    return ''
}

function Get-ToolSoftwareBlockedHostEvidence {
    param([AllowNull()][object]$CatalogProduct)
    $evidence = New-Object System.Collections.Generic.List[object]
    $licenseDomains = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'LicenseDomains')
    if (-not $CatalogProduct -or $licenseDomains.Count -eq 0) { return $evidence.ToArray() }
    $catalogProductId = Get-ToolSoftwareOptionalPropertyString -InputObject $CatalogProduct -Name 'Id'
    $cacheKey = if ($catalogProductId) { $catalogProductId } else { ($licenseDomains -join '|') }
    if ($script:ToolSoftwareHostsEvidenceCache.ContainsKey($cacheKey)) { return @($script:ToolSoftwareHostsEvidenceCache[$cacheKey]) }
    $hostsPath = Join-Path ([Environment]::ExpandEnvironmentVariables('%WINDIR%')) 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $hostsPath -PathType Leaf)) { return $evidence.ToArray() }
    try {
        $lines = [IO.File]::ReadAllLines($hostsPath)
        foreach ($line in $lines) {
            $trimmed = ([string]$line).Split('#')[0].Trim()
            if ($trimmed -notmatch '^(?:0\.0\.0\.0|127\.0\.0\.1|::1)\s+(.+)$') { continue }
            $targets = @($matches[1] -split '\s+' | Where-Object { $_ })
            foreach ($domainPattern in $licenseDomains) {
                foreach ($target in $targets) {
                    if ($target -match [string]$domainPattern) {
                        $evidence.Add([pscustomobject][ordered]@{ Code='LicenseDomainBlocked'; Strength='Moderate'; Source='Hosts'; Detail=$target })
                    }
                }
            }
        }
    } catch {}
    $result = $evidence.ToArray()
    $script:ToolSoftwareHostsEvidenceCache[$cacheKey] = $result
    return $result
}

function Get-ToolSoftwareLocationEvidence {
    param([Parameter(Mandatory = $true)]$Application)
    $evidence = New-Object System.Collections.Generic.List[object]
    $location = [string]$Application.InstallLocation
    if ([string]::IsNullOrWhiteSpace($location) -or -not (Test-Path -LiteralPath $location -PathType Container)) { return $evidence.ToArray() }
    try { $fullLocation = [IO.Path]::GetFullPath($location) } catch { return $evidence.ToArray() }
    if ($fullLocation.Length -lt 8) { return $evidence.ToArray() }
    $cacheKey = $fullLocation.ToLowerInvariant()
    if ($script:ToolSoftwareLocationEvidenceCache.ContainsKey($cacheKey)) { return @($script:ToolSoftwareLocationEvidenceCache[$cacheKey]) }
    $strictPattern = '(?i)(\bcrack(?:ed)?\b|\bkeygen\b|\bactivator\b|\blicense[._ -]*bypass\b|\badobe[._ -]*genp\b|\bccmaker\b|\bxf[._ -]*adsk\b|\bx[._ -]*force\b|\bamtlib[._ -]*(?:patch|emulator)\b)'
    $executableArtifactExtensions = @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi')
    try {
        $files = New-Object System.Collections.Generic.List[object]
        foreach ($file in @(Get-ChildItem -LiteralPath $fullLocation -File -Force -ErrorAction SilentlyContinue | Select-Object -First 180)) { $files.Add($file) }
        foreach ($directory in @(Get-ChildItem -LiteralPath $fullLocation -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 40)) {
            foreach ($file in @(Get-ChildItem -LiteralPath $directory.FullName -File -Force -ErrorAction SilentlyContinue | Select-Object -First 80)) {
                if ($files.Count -ge 500) { break }
                $files.Add($file)
            }
            if ($files.Count -ge 500) { break }
        }
        foreach ($file in $files) {
            if ($executableArtifactExtensions -contains ([string]$file.Extension).ToLowerInvariant() -and [string]$file.Name -match $strictPattern) {
                $evidence.Add([pscustomobject][ordered]@{ Code='UnauthorizedArtifactName'; Strength='Strong'; Source='InstallLocation'; Detail=[string]$file.FullName })
            }
        }
    } catch {}
    $result = $evidence.ToArray()
    $script:ToolSoftwareLocationEvidenceCache[$cacheKey] = $result
    return $result
}

function Test-ToolSoftwareAnyPattern {
    param([string]$Text, [object[]]$Patterns)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    foreach ($pattern in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) { continue }
        try {
            if ([regex]::IsMatch($Text, [string]$pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(300))) { return $true }
        } catch {}
    }
    return $false
}

function Test-ToolSoftwarePathWithinRoot {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))).TrimEnd('\')
        $fullRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Root.Trim().Trim('"'))).TrimEnd('\')
        return [bool]($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith(($fullRoot + '\'), [StringComparison]::OrdinalIgnoreCase))
    } catch { return $false }
}

function Get-ToolSoftwareDeepScanRoots {
    param([Parameter(Mandatory = $true)]$Application)
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace([string]$Application.RepresentativePath)) {
        try {
            $representative = [IO.Path]::GetFullPath([string]$Application.RepresentativePath)
            if (Test-Path -LiteralPath $representative -PathType Leaf) { $candidates.Add((Split-Path -Parent $representative)) }
        } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Application.InstallLocation)) {
        try {
            $location = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$Application.InstallLocation)).TrimEnd('\')
            if (Test-Path -LiteralPath $location -PathType Container) { $candidates.Add($location) }
        } catch {}
    }
    $excluded = @(
        $(if ($env:SystemDrive) { ([IO.Path]::GetFullPath($env:SystemDrive + '\')).TrimEnd('\') }),
        $(if ($env:WINDIR) { ([IO.Path]::GetFullPath($env:WINDIR)).TrimEnd('\') }),
        $(if ($env:ProgramFiles) { ([IO.Path]::GetFullPath($env:ProgramFiles)).TrimEnd('\') }),
        $(if (${env:ProgramFiles(x86)}) { ([IO.Path]::GetFullPath(${env:ProgramFiles(x86)})).TrimEnd('\') }),
        $(if ($env:ProgramData) { ([IO.Path]::GetFullPath($env:ProgramData)).TrimEnd('\') }),
        $(if ($env:LOCALAPPDATA) { ([IO.Path]::GetFullPath($env:LOCALAPPDATA)).TrimEnd('\') }),
        $([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))
    ) | Where-Object { $_ } | Select-Object -Unique
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($candidates.ToArray() | Sort-Object Length -Descending -Unique)) {
        try {
            $full = [IO.Path]::GetFullPath([string]$candidate).TrimEnd('\')
            if ($full.Length -lt 8 -or $excluded -contains $full) { continue }
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (-not $roots.Contains($full)) { $roots.Add($full) }
            if ($roots.Count -ge 2) { break }
        } catch {}
    }
    return $roots.ToArray()
}

function New-ToolSoftwareDeepScanState {
    param(
        [ValidateRange(15, 900)][int]$MaximumDurationSeconds = 180,
        [ValidateRange(1000, 500000)][int]$MaximumTotalEntries = 120000,
        [ValidateRange(20, 10000)][int]$MaximumTotalSignatureChecks = 1400,
        [ValidateRange(20, 10000)][int]$MaximumTotalHashChecks = 1000,
        [ValidateRange(100, 10000)][int]$MaximumFilesPerRoot = 1600,
        [ValidateRange(500, 100000)][int]$MaximumEntriesPerRoot = 14000,
        [ValidateRange(1, 8)][int]$MaximumDepth = 4,
        [ValidateRange(2, 60)][int]$MaximumSecondsPerRoot = 10
    )
    $isAdministrator = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    $started = [DateTime]::UtcNow
    return [pscustomobject][ordered]@{
        Enabled=$true; StartedAtUtc=$started; DeadlineUtc=$started.AddSeconds($MaximumDurationSeconds)
        MaximumTotalEntries=$MaximumTotalEntries; MaximumTotalSignatureChecks=$MaximumTotalSignatureChecks
        MaximumTotalHashChecks=$MaximumTotalHashChecks; MaximumFilesPerRoot=$MaximumFilesPerRoot
        MaximumEntriesPerRoot=$MaximumEntriesPerRoot; MaximumDepth=$MaximumDepth; MaximumSecondsPerRoot=$MaximumSecondsPerRoot
        IsAdministrator=[bool]$isAdministrator; ApplicationsScanned=0; ApplicationsSkipped=0; UniqueRootsScanned=0
        RootCacheHits=0; UniqueDirectoriesScanned=0; DirectoryCacheHits=0
        TotalEntries=0; RelevantFiles=0; SignatureChecks=0; HashChecks=0; EvidenceCount=0
        SignaturePaths=@{}; HashPaths=@{}
        TimeLimitReached=$false; EntryLimitReached=$false; SignatureLimitReached=$false; HashLimitReached=$false
        AccessWarningCount=0
    }
}

function Get-ToolSoftwareDeepDirectoryListing {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)
    $fullPath = ''
    try { $fullPath = [IO.Path]::GetFullPath($DirectoryPath).TrimEnd('\') } catch {}
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        return [pscustomobject][ordered]@{
            CacheHit=$false
            Listing=[pscustomobject][ordered]@{ Path=$DirectoryPath; Files=@(); Directories=@(); FileCount=0; AccessWarnings=1; Success=$false }
        }
    }
    $cacheKey = $fullPath.ToLowerInvariant()
    if ($script:ToolSoftwareDeepDirectoryCache.ContainsKey($cacheKey)) {
        return [pscustomobject][ordered]@{ CacheHit=$true; Listing=$script:ToolSoftwareDeepDirectoryCache[$cacheKey] }
    }

    $files = New-Object System.Collections.Generic.List[object]
    $directories = New-Object System.Collections.Generic.List[string]
    $fileCount = 0
    $accessWarnings = 0
    $success = $true
    try {
        $directory = New-Object IO.DirectoryInfo($fullPath)
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $success = $false
        } else {
            foreach ($entry in $directory.EnumerateFileSystemInfos()) {
                try {
                    if ($entry -is [IO.DirectoryInfo]) {
                        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                            $directories.Add([string]$entry.FullName)
                        }
                        continue
                    }
                    if ($entry -isnot [IO.FileInfo]) { continue }
                    $fileCount++
                    $extension = ([string]$entry.Extension).ToLowerInvariant()
                    $pathText = [string]$entry.FullName
                    if ($script:ToolSoftwareDeepRelevantExtensions -contains $extension -or
                        $pathText -match $script:ToolSoftwareKnownActivatorPattern -or $pathText -match $script:ToolSoftwareSuspiciousArtifactPattern) {
                        $files.Add([pscustomobject][ordered]@{
                            Path=$pathText; Name=[string]$entry.Name; Extension=$extension; Length=[long]$entry.Length
                            LastWriteTimeUtc=$entry.LastWriteTimeUtc.ToString('o'); Ordinal=[int]$fileCount
                        })
                    }
                } catch { $accessWarnings++ }
            }
        }
    } catch {
        $accessWarnings++
        $success = $false
    }
    $listing = [pscustomobject][ordered]@{
        Path=$fullPath; Files=$files.ToArray(); Directories=$directories.ToArray(); FileCount=[int]$fileCount
        AccessWarnings=[int]$accessWarnings; Success=[bool]$success
    }
    $script:ToolSoftwareDeepDirectoryCache[$cacheKey] = $listing
    return [pscustomobject][ordered]@{ CacheHit=$false; Listing=$listing }
}

function Get-ToolSoftwareDeepFileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$State)
    $fullRoot = ''
    try { $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') } catch {}
    if ([string]::IsNullOrWhiteSpace($fullRoot) -or -not (Test-Path -LiteralPath $fullRoot -PathType Container)) {
        return [pscustomobject][ordered]@{ Root=$Root; Files=@(); Complete=$false; TimedOut=$false; EntryLimitReached=$false; AccessWarnings=1 }
    }
    $cacheKey = $fullRoot.ToLowerInvariant()
    if ($script:ToolSoftwareDeepFileCache.ContainsKey($cacheKey)) {
        $State.RootCacheHits = [int]$State.RootCacheHits + 1
        return $script:ToolSoftwareDeepFileCache[$cacheKey]
    }
    $files = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ Path=$fullRoot; Depth=0 })
    $seen = @{}
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $entries = 0
    $accessWarnings = 0
    $timedOut = $false
    $entryLimit = $false
    while ($queue.Count -gt 0 -and $files.Count -lt [int]$State.MaximumFilesPerRoot) {
        if ([DateTime]::UtcNow -ge [DateTime]$State.DeadlineUtc -or $watch.Elapsed.TotalSeconds -ge [int]$State.MaximumSecondsPerRoot) {
            $timedOut = $true
            break
        }
        if ([int]$State.TotalEntries -ge [int]$State.MaximumTotalEntries -or $entries -ge [int]$State.MaximumEntriesPerRoot) {
            $entryLimit = $true
            break
        }
        $current = $queue.Dequeue()
        $key = ([string]$current.Path).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        try {
            $directoryResult = Get-ToolSoftwareDeepDirectoryListing -DirectoryPath ([string]$current.Path)
            $listing = $directoryResult.Listing
            if ([bool]$directoryResult.CacheHit) {
                $State.DirectoryCacheHits = [int]$State.DirectoryCacheHits + 1
            } else {
                $State.UniqueDirectoriesScanned = [int]$State.UniqueDirectoriesScanned + 1
            }
            $accessWarnings += [int]$listing.AccessWarnings
            if (-not [bool]$listing.Success) { continue }

            $remainingRootEntries = [Math]::Max(0, [int]$State.MaximumEntriesPerRoot - $entries)
            $processedFileCount = [Math]::Min([int]$listing.FileCount, $remainingRootEntries)
            $remainingTotalEntries = [Math]::Max(0, [int]$State.MaximumTotalEntries - [int]$State.TotalEntries)
            $processedFileCount = [Math]::Min($processedFileCount, $remainingTotalEntries)
            $State.TotalEntries = [int]$State.TotalEntries + $processedFileCount
            $entries += $processedFileCount
            foreach ($file in @($listing.Files | Where-Object { [int]$_.Ordinal -le $processedFileCount })) {
                $files.Add([pscustomobject][ordered]@{
                    Path=[string]$file.Path; Name=[string]$file.Name; Extension=[string]$file.Extension; Length=[long]$file.Length
                    LastWriteTimeUtc=[string]$file.LastWriteTimeUtc; Depth=[int]$current.Depth
                })
                if ($files.Count -ge [int]$State.MaximumFilesPerRoot) { break }
            }

            $directoryFullyProcessed = [bool]($processedFileCount -ge [int]$listing.FileCount)
            if (-not $directoryFullyProcessed) { $entryLimit = $true }
            if ([int]$current.Depth -lt [int]$State.MaximumDepth -and $directoryFullyProcessed -and -not $timedOut -and
                $files.Count -lt [int]$State.MaximumFilesPerRoot) {
                foreach ($childPath in @($listing.Directories)) {
                    $queue.Enqueue([pscustomobject]@{ Path=[string]$childPath; Depth=([int]$current.Depth + 1) })
                }
            }
        } catch { $accessWarnings++ }
    }
    $watch.Stop()
    if ([DateTime]::UtcNow -ge [DateTime]$State.DeadlineUtc) { $State.TimeLimitReached = $true }
    if ($entryLimit) { $State.EntryLimitReached = $true }
    $State.AccessWarningCount = [int]$State.AccessWarningCount + $accessWarnings
    $State.UniqueRootsScanned = [int]$State.UniqueRootsScanned + 1
    $State.RelevantFiles = [int]$State.RelevantFiles + $files.Count
    $snapshot = [pscustomobject][ordered]@{
        Root=$fullRoot; Files=$files.ToArray(); Complete=[bool](-not $timedOut -and -not $entryLimit -and $queue.Count -eq 0)
        TimedOut=[bool]$timedOut; EntryLimitReached=[bool]$entryLimit; AccessWarnings=[int]$accessWarnings
    }
    $script:ToolSoftwareDeepFileCache[$cacheKey] = $snapshot
    return $snapshot
}

function Get-ToolSoftwareDeepSystemSnapshot {
    if ($null -ne $script:ToolSoftwareDeepSystemSnapshotCache) { return $script:ToolSoftwareDeepSystemSnapshotCache }
    $ifeo = New-Object System.Collections.Generic.List[object]
    $firewall = New-Object System.Collections.Generic.List[object]
    $services = New-Object System.Collections.Generic.List[object]
    $autoruns = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        try {
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop | Select-Object -First 3000)) {
                try {
                    $value = Get-ItemProperty -LiteralPath $key.PSPath -Name Debugger -ErrorAction Stop
                    if (-not [string]::IsNullOrWhiteSpace([string]$value.Debugger)) {
                        $ifeo.Add([pscustomobject][ordered]@{ Target=[string]$key.PSChildName; Debugger=[string]$value.Debugger; RegistryPath=[string]$key.PSPath })
                    }
                } catch {}
            }
        } catch { $warnings.Add('IFEO:' + [string]$_.Exception.Message) }
    }
    try {
        $policy = New-Object -ComObject HNetCfg.FwPolicy2
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $count = 0
        foreach ($rule in $policy.Rules) {
            if ($count -ge 5000 -or $watch.Elapsed.TotalSeconds -ge 8) { break }
            $count++
            try {
                if ([bool]$rule.Enabled -and [int]$rule.Action -eq 0 -and [int]$rule.Direction -eq 2 -and
                    -not [string]::IsNullOrWhiteSpace([string]$rule.ApplicationName)) {
                    $firewall.Add([pscustomobject][ordered]@{
                        Name=[string]$rule.Name; ApplicationName=[Environment]::ExpandEnvironmentVariables([string]$rule.ApplicationName)
                        Description=[string]$rule.Description
                    })
                }
            } catch {}
        }
        $watch.Stop()
        try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($policy) } catch {}
    } catch { $warnings.Add('Firewall:' + [string]$_.Exception.Message) }
    try {
        $serviceItems = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            @(Get-CimInstance Win32_Service -ErrorAction Stop)
        } else { @(Get-WmiObject Win32_Service -ErrorAction Stop) }
        foreach ($service in $serviceItems) {
            $services.Add([pscustomobject][ordered]@{
                Name=[string]$service.Name; DisplayName=[string]$service.DisplayName; StartMode=[string]$service.StartMode
                State=[string]$service.State; PathName=[string]$service.PathName
            })
        }
    } catch { $warnings.Add('Services:' + [string]$_.Exception.Message) }
    foreach ($runRoot in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )) {
        if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) { continue }
        try {
            $values = Get-ItemProperty -LiteralPath $runRoot -ErrorAction Stop
            foreach ($property in @($values.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })) {
                if (-not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    $autoruns.Add([pscustomobject][ordered]@{ Name=[string]$property.Name; Command=[string]$property.Value; RegistryPath=$runRoot })
                }
            }
        } catch { $warnings.Add('Autorun:' + [string]$_.Exception.Message) }
    }
    $script:ToolSoftwareDeepSystemSnapshotCache = [pscustomobject][ordered]@{
        Ifeo=$ifeo.ToArray(); Firewall=$firewall.ToArray(); Services=$services.ToArray(); Autoruns=$autoruns.ToArray(); Warnings=$warnings.ToArray()
    }
    return $script:ToolSoftwareDeepSystemSnapshotCache
}

function New-ToolSoftwareTechnicalEvidence {
    param(
        [string]$Code, [ValidateSet('Conclusive','Strong','Moderate','Weak')][string]$Strength,
        [string]$Source, [string]$Detail, [string]$EvidenceGroup = '', [switch]$Decisive
    )
    return [pscustomobject][ordered]@{
        Code=$Code; Strength=$Strength; Source=$Source; Detail=$Detail
        EvidenceGroup=$(if ($EvidenceGroup) { $EvidenceGroup } else { $Source }); Decisive=[bool]$Decisive
    }
}

function Get-ToolSoftwareIdentityTokens {
    param([Parameter(Mandatory = $true)]$Application)
    $ignored = @('software','application','applications','program','professional','enterprise','edition','desktop','studio','editor','viewer','reader','update','helper','service','services','windows','microsoft','corporation','company','limited','inc','ltd','the','and','for','with','x64','x86','bit')
    $text = (([string]$Application.Name) + ' ' + ([string]$Application.Publisher)).ToLowerInvariant()
    return @([regex]::Split($text, '[^a-z0-9]+') | Where-Object {
        $_.Length -ge 5 -and $_ -notmatch '^\d+$' -and $ignored -notcontains $_
    } | Sort-Object Length -Descending -Unique | Select-Object -First 8)
}

function Get-ToolSoftwareDeepSystemEvidence {
    param([Parameter(Mandatory = $true)]$Application, [string[]]$Roots, [Parameter(Mandatory = $true)]$Snapshot, [AllowNull()][object]$CatalogProduct)
    $evidence = New-Object System.Collections.Generic.List[object]
    $identityTokens = @(Get-ToolSoftwareIdentityTokens -Application $Application)
    $licenseProcessPatterns = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'LicenseProcessPatterns')
    $representativeName = ''
    try { if ($Application.RepresentativePath) { $representativeName = [IO.Path]::GetFileName([string]$Application.RepresentativePath) } } catch {}
    foreach ($entry in @($Snapshot.Ifeo)) {
        if (-not $representativeName -or -not ([string]$entry.Target).Equals($representativeName, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $knownActivator = [bool]([string]$entry.Debugger -match $script:ToolSoftwareKnownActivatorPattern)
        $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'ApplicationIfeoDebugger' -Strength $(if ($knownActivator) {'Strong'} else {'Moderate'}) `
            -Source 'IFEO' -EvidenceGroup 'ExecutionInterception' -Detail (([string]$entry.Target) + ' -> ' + ([string]$entry.Debugger)) -Decisive:$knownActivator))
    }
    foreach ($rule in @($Snapshot.Firewall)) {
        $matched = $false
        foreach ($root in @($Roots)) { if (Test-ToolSoftwarePathWithinRoot -Path ([string]$rule.ApplicationName) -Root $root) { $matched=$true; break } }
        $ruleText = (([string]$rule.Name) + ' ' + ([string]$rule.ApplicationName) + ' ' + ([string]$rule.Description))
        if (-not $matched -and (Test-ToolSoftwareAnyPattern -Text $ruleText -Patterns $licenseProcessPatterns)) { $matched=$true }
        if (-not $matched -and $ruleText -match '(?i)licen[cs]|activat|entitlement|subscription|genuine|auth') {
            foreach ($token in $identityTokens) { if ($ruleText -match ('(?i)(?<![a-z0-9])' + [regex]::Escape($token) + '(?![a-z0-9])')) { $matched=$true; break } }
        }
        if ($matched) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'ApplicationOutboundBlocked' -Strength 'Moderate' -Source 'Firewall' `
                -EvidenceGroup 'LicenseConnectivity' -Detail (([string]$rule.Name) + ' | ' + ([string]$rule.ApplicationName))))
        }
    }
    foreach ($service in @($Snapshot.Services)) {
        if ([string]$service.StartMode -ne 'Disabled' -or
            (([string]$service.Name + ' ' + [string]$service.DisplayName + ' ' + [string]$service.PathName) -notmatch '(?i)licen[cs]|activat|entitlement|subscription|genuine|auth')) { continue }
        $matched = $false
        foreach ($root in @($Roots)) { if (Test-ToolSoftwarePathWithinRoot -Path ([string]$service.PathName) -Root $root) { $matched=$true; break } }
        $serviceText = (([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName))
        if (-not $matched -and (Test-ToolSoftwareAnyPattern -Text $serviceText -Patterns $licenseProcessPatterns)) { $matched=$true }
        if (-not $matched) {
            foreach ($token in $identityTokens) { if ($serviceText -match ('(?i)(?<![a-z0-9])' + [regex]::Escape($token) + '(?![a-z0-9])')) { $matched=$true; break } }
        }
        if ($matched) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'LicenseRelatedServiceDisabled' -Strength 'Weak' -Source 'Service' `
                -EvidenceGroup 'LicenseServiceState' -Detail (([string]$service.Name) + ' | Disabled | ' + ([string]$service.PathName))))
        }
    }
    foreach ($autorun in @($Snapshot.Autoruns)) {
        $commandText = [string]$autorun.Command
        if ($commandText -notmatch $script:ToolSoftwareKnownActivatorPattern -and $commandText -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) { continue }
        $matched = $false
        foreach ($root in @($Roots)) { if ($commandText.IndexOf($root, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $matched=$true; break } }
        if ($matched) {
            $knownActivator = [bool]($commandText -match $script:ToolSoftwareKnownActivatorPattern)
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'SuspiciousApplicationAutorun' -Strength $(if ($knownActivator) {'Strong'} else {'Moderate'}) `
                -Source 'Autorun' -EvidenceGroup 'Persistence' -Detail (([string]$autorun.Name) + ' | ' + $commandText) -Decisive:$knownActivator))
        }
    }
    return $evidence.ToArray()
}

function New-ToolSoftwareDeepScanPreparation {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [AllowNull()][object]$CatalogProduct,
        [AllowNull()][object]$Catalog,
        [Parameter(Mandatory = $true)]$State
    )
    $evidence = New-Object System.Collections.Generic.List[object]
    $roots = @(Get-ToolSoftwareDeepScanRoots -Application $Application)
    if ($roots.Count -eq 0) {
        $State.ApplicationsSkipped = [int]$State.ApplicationsSkipped + 1
        return [pscustomobject][ordered]@{
            Evidence=@(); Roots=@(); FilesEnumerated=0; Complete=$false; Status='NoSafeRoot'
            SignatureCandidates=@(); HashCandidates=@(); KnownBadHashes=@(); ExpectedSignerPatterns=@()
            CatalogTrustedForDecisiveEvidence=$false
        }
    }
    $State.ApplicationsScanned = [int]$State.ApplicationsScanned + 1
    $knownPatterns = New-Object System.Collections.Generic.List[object]
    $suspiciousPatterns = New-Object System.Collections.Generic.List[object]
    $criticalPatterns = New-Object System.Collections.Generic.List[object]
    $expectedSignedPatterns = New-Object System.Collections.Generic.List[object]
    $expectedSignerPatterns = New-Object System.Collections.Generic.List[object]
    $knownBadHashes = New-Object System.Collections.Generic.List[string]
    $catalogTrustedForDecisiveEvidence = Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $Catalog
    $catalogDeepScanValues = @(Get-ToolSoftwareOptionalPropertyValues -InputObject $Catalog -Name 'DeepScan')
    if ($catalogDeepScanValues.Count -gt 0) {
        $catalogDeepScan = $catalogDeepScanValues[0]
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $catalogDeepScan -Name 'KnownActivatorNamePatterns')) { if ($value) { $knownPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $catalogDeepScan -Name 'SuspiciousArtifactNamePatterns')) { if ($value) { $suspiciousPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $catalogDeepScan -Name 'KnownBadSha256')) { if ($value) { $knownBadHashes.Add(([string]$value).ToUpperInvariant()) } }
    }
    if ($CatalogProduct) {
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'KnownActivatorNamePatterns')) { if ($value) { $knownPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'SuspiciousArtifactNamePatterns')) { if ($value) { $suspiciousPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'CriticalFilePatterns')) { if ($value) { $criticalPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'ExpectedSignedFilePatterns')) { if ($value) { $expectedSignedPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'ExpectedSignerPatterns')) { if ($value) { $expectedSignerPatterns.Add($value) } }
        foreach ($value in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $CatalogProduct -Name 'KnownBadSha256')) { if ($value) { $knownBadHashes.Add(([string]$value).ToUpperInvariant()) } }
    }
    $snapshots = New-Object System.Collections.Generic.List[object]
    $fileCandidates = New-Object System.Collections.Generic.List[object]
    $hashFileCandidates = New-Object System.Collections.Generic.List[object]
    $filesEnumerated = 0
    $complete = $true
    foreach ($root in $roots) {
        $snapshot = Get-ToolSoftwareDeepFileSnapshot -Root $root -State $State
        $snapshots.Add($snapshot)
        $filesEnumerated += @($snapshot.Files).Count
        if (-not [bool]$snapshot.Complete) { $complete=$false }
        foreach ($file in @($snapshot.Files)) {
            $pathText = [string]$file.Path
            $artifactExtensionEligible = [bool]($script:ToolSoftwareDeepRelevantExtensions -contains ([string]$file.Extension))
            $knownActivator = [bool]($artifactExtensionEligible -and
                ($pathText -match $script:ToolSoftwareKnownActivatorPattern -or (Test-ToolSoftwareAnyPattern -Text $pathText -Patterns $knownPatterns.ToArray())))
            $suspiciousArtifact = [bool]($artifactExtensionEligible -and
                ($knownActivator -or $pathText -match $script:ToolSoftwareSuspiciousArtifactPattern -or (Test-ToolSoftwareAnyPattern -Text $pathText -Patterns $suspiciousPatterns.ToArray())))
            $critical = Test-ToolSoftwareAnyPattern -Text $pathText -Patterns $criticalPatterns.ToArray()
            $expectedSigned = Test-ToolSoftwareAnyPattern -Text $pathText -Patterns $expectedSignedPatterns.ToArray()
            if ($knownActivator) {
                $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'KnownActivatorArtifact' -Strength 'Strong' -Source 'DeepFileScan' `
                    -EvidenceGroup 'KnownActivator' -Detail $pathText -Decisive))
            } elseif ($suspiciousArtifact) {
                $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'SuspiciousArtifactName' -Strength 'Moderate' -Source 'DeepFileScan' `
                    -EvidenceGroup 'ArtifactName' -Detail $pathText))
            }
            if ($script:ToolSoftwareAuthenticodeExtensions -contains ([string]$file.Extension)) {
                $priority = 0
                $licenseRelevant = [bool]([string]$file.Name -match '(?i)licen[cs]|activat|entitlement|subscription|genuine|auth|amtlib')
                if ($critical -or $expectedSigned) { $priority=5 }
                elseif ($knownActivator -or $suspiciousArtifact) { $priority=4 }
                elseif ($licenseRelevant -or [string]$file.Name -match '(?i)core') { $priority=3 }
                elseif ([string]$file.Extension -eq '.exe' -and [int]$file.Depth -le 2) { $priority=2 }
                elseif ([int]$file.Depth -le 1) { $priority=1 }
                if ($priority -gt 0) {
                    $fileCandidates.Add([pscustomobject][ordered]@{
                        Path=$pathText; Priority=$priority; Depth=[int]$file.Depth; Critical=[bool]$critical
                        ExpectedSigned=[bool]$expectedSigned; LicenseRelevant=$licenseRelevant; Representative=$false
                    })
                }
                if ($knownBadHashes.Count -gt 0) {
                    $hashPriority = if ($critical -or $expectedSigned) { 5 } elseif ($knownActivator -or $suspiciousArtifact) { 4 } elseif ([int]$file.Depth -le 1) { 3 } elseif ([string]$file.Extension -eq '.exe') { 2 } else { 1 }
                    $hashFileCandidates.Add([pscustomobject][ordered]@{ Path=$pathText; Priority=$hashPriority; Depth=[int]$file.Depth })
                }
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Application.RepresentativePath) -and (Test-Path -LiteralPath ([string]$Application.RepresentativePath) -PathType Leaf)) {
        $fileCandidates.Add([pscustomobject][ordered]@{
            Path=[string]$Application.RepresentativePath; Priority=6; Depth=0; Critical=$false
            ExpectedSigned=$false; LicenseRelevant=$false; Representative=$true
        })
        if ($knownBadHashes.Count -gt 0) { $hashFileCandidates.Add([pscustomobject][ordered]@{ Path=[string]$Application.RepresentativePath; Priority=6; Depth=0 }) }
    }
    $preparedSignatureCandidates = @($fileCandidates.ToArray() |
        Group-Object { ([string]$_.Path).ToLowerInvariant() } | ForEach-Object { @($_.Group | Sort-Object Priority -Descending)[0] } |
        Sort-Object @{Expression='Priority';Descending=$true},@{Expression='Depth';Ascending=$true},Path)
    $preparedHashCandidates = @($hashFileCandidates.ToArray() |
        Group-Object { ([string]$_.Path).ToLowerInvariant() } | ForEach-Object { @($_.Group | Sort-Object Priority -Descending)[0] } |
        Sort-Object @{Expression='Priority';Descending=$true},@{Expression='Depth';Ascending=$true},Path)
    return [pscustomobject][ordered]@{
        Evidence=$evidence.ToArray(); Roots=$roots; FilesEnumerated=[int]$filesEnumerated; Complete=[bool]$complete; Status='Prepared'
        SignatureCandidates=$preparedSignatureCandidates; HashCandidates=$preparedHashCandidates
        KnownBadHashes=$knownBadHashes.ToArray(); ExpectedSignerPatterns=$expectedSignerPatterns.ToArray()
        CatalogTrustedForDecisiveEvidence=[bool]$catalogTrustedForDecisiveEvidence
    }
}

function Get-ToolSoftwareDeepScanEvidence {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [AllowNull()][object]$CatalogProduct,
        [AllowNull()][object]$Catalog,
        [Parameter(Mandatory = $true)]$State,
        [ValidateRange(1, 200)][int]$MaximumSignatureChecksPerApplication = 18,
        [ValidateRange(4, 500)][int]$MaximumHashChecksPerApplication = 160,
        [AllowNull()][object]$SignatureRunspacePool,
        [AllowNull()][object]$Preparation
    )
    if ($null -eq $Preparation) {
        $Preparation = New-ToolSoftwareDeepScanPreparation -Application $Application -CatalogProduct $CatalogProduct -Catalog $Catalog -State $State
    }
    if ([string]$Preparation.Status -eq 'NoSafeRoot') {
        return [pscustomobject][ordered]@{
            Evidence=@(); Roots=@(); FilesEnumerated=0; SignatureChecks=0; HashChecks=0
            Complete=$false; Status='NoSafeRoot'; RepresentativeSignature=$null
        }
    }
    $evidence = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Preparation.Evidence)) { $evidence.Add($item) }
    $roots = @($Preparation.Roots)
    $filesEnumerated = [int]$Preparation.FilesEnumerated
    $complete = [bool]$Preparation.Complete
    $knownBadHashes = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Preparation.KnownBadHashes)) { if ($item) { $knownBadHashes.Add([string]$item) } }
    $expectedSignerPatterns = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Preparation.ExpectedSignerPatterns)) { if ($item) { $expectedSignerPatterns.Add($item) } }
    $catalogTrustedForDecisiveEvidence = [bool]$Preparation.CatalogTrustedForDecisiveEvidence
    $signatureChecks = 0
    $representativeSignature = $null
    $signatureCandidates = @($Preparation.SignatureCandidates)
    $scheduledSignatureCandidates = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $signatureCandidates) {
        if ($signatureChecks -ge $MaximumSignatureChecksPerApplication) { break }
        if ([DateTime]::UtcNow -ge [DateTime]$State.DeadlineUtc) { $State.TimeLimitReached=$true; $complete=$false; break }
        $signaturePathKey = ([string]$candidate.Path).ToLowerInvariant()
        $alreadyChecked = $State.SignaturePaths.ContainsKey($signaturePathKey)
        if (-not $alreadyChecked -and [int]$State.SignatureChecks -ge [int]$State.MaximumTotalSignatureChecks) { $State.SignatureLimitReached=$true; $complete=$false; break }
        $signatureChecks++
        if (-not $alreadyChecked) {
            $State.SignaturePaths[$signaturePathKey] = $true
            $State.SignatureChecks = [int]$State.SignatureChecks + 1
        }
        $scheduledSignatureCandidates.Add($candidate)
    }
    $signatureResults = Get-ToolSoftwareSignatureStatesParallel `
        -Paths @($scheduledSignatureCandidates.ToArray() | ForEach-Object { [string]$_.Path }) `
        -ThrottleLimit 4 -RunspacePool $SignatureRunspacePool
    foreach ($candidate in $scheduledSignatureCandidates) {
        $signaturePathKey = ''
        try { $signaturePathKey = ([IO.Path]::GetFullPath([string]$candidate.Path)).ToLowerInvariant() }
        catch { $signaturePathKey = ([string]$candidate.Path).ToLowerInvariant() }
        $signature = if ($signatureResults.ContainsKey($signaturePathKey)) {
            $signatureResults[$signaturePathKey]
        } else { Get-ToolSoftwareSignatureState -Path ([string]$candidate.Path) }
        if ([bool]$candidate.Representative) { $representativeSignature = $signature }
        if ([string]$signature.Status -eq 'HashMismatch') {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'DeepSignatureHashMismatch' `
                -Strength 'Strong' -Source 'Authenticode' -EvidenceGroup 'FileIntegrity' -Detail ([string]$candidate.Path)))
        } elseif ([string]$signature.Status -eq 'NotSigned' -and [bool]$candidate.ExpectedSigned) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'ExpectedSignedFileNotSigned' -Strength 'Strong' -Source 'Authenticode' `
                -EvidenceGroup 'FileIntegrity' -Detail ([string]$candidate.Path)))
        } elseif ([string]$signature.Status -eq 'NotSigned' -and [bool]$candidate.Critical) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'CriticalFileNotSigned' -Strength 'Moderate' -Source 'Authenticode' `
                -EvidenceGroup 'FileIntegrity' -Detail ([string]$candidate.Path)))
        } elseif ([string]$signature.Status -eq 'NotTrusted' -and ([bool]$candidate.Critical -or [bool]$candidate.ExpectedSigned)) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'CriticalFileSignatureNotTrusted' -Strength 'Moderate' -Source 'Authenticode' `
                -EvidenceGroup 'FileTrust' -Detail (([string]$candidate.Path) + ' | NotTrusted')))
        }
        if ([string]$signature.Status -eq 'Valid' -and $expectedSignerPatterns.Count -gt 0 -and
            -not (Test-ToolSoftwareAnyPattern -Text ([string]$signature.Publisher) -Patterns $expectedSignerPatterns.ToArray())) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'UnexpectedCoreFileSigner' -Strength 'Strong' -Source 'Authenticode' `
                -EvidenceGroup 'PublisherMismatch' -Detail (([string]$candidate.Path) + ' | ' + ([string]$signature.Publisher))))
        }
    }
    if ([DateTime]::UtcNow -ge [DateTime]$State.DeadlineUtc) { $State.TimeLimitReached=$true; $complete=$false }
    $hashChecks = 0
    if ($knownBadHashes.Count -gt 0) {
        $hashCandidates = @($Preparation.HashCandidates)
        foreach ($candidate in $hashCandidates) {
            if ($hashChecks -ge $MaximumHashChecksPerApplication) { break }
            if ([DateTime]::UtcNow -ge [DateTime]$State.DeadlineUtc) { $State.TimeLimitReached=$true; $complete=$false; break }
            $hashPathKey = ([string]$candidate.Path).ToLowerInvariant()
            $hashAlreadyChecked = $State.HashPaths.ContainsKey($hashPathKey)
            if (-not $hashAlreadyChecked -and [int]$State.HashChecks -ge [int]$State.MaximumTotalHashChecks) { $State.HashLimitReached=$true; $complete=$false; break }
            $hash = Get-ToolSoftwareFileSha256 -Path ([string]$candidate.Path)
            $hashChecks++
            if (-not $hashAlreadyChecked) {
                $State.HashPaths[$hashPathKey] = $true
                $State.HashChecks = [int]$State.HashChecks + 1
            }
            if ($hash -and $knownBadHashes.Contains($hash)) {
                $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'KnownBadFileHash' `
                    -Strength $(if ($catalogTrustedForDecisiveEvidence) {'Conclusive'} else {'Strong'}) -Source 'SHA256' `
                    -EvidenceGroup 'KnownBadHash' -Detail (([string]$candidate.Path) + ' | ' + $hash) -Decisive:$catalogTrustedForDecisiveEvidence))
            }
        }
    }
    $systemSnapshot = Get-ToolSoftwareDeepSystemSnapshot
    foreach ($item in @(Get-ToolSoftwareDeepSystemEvidence -Application $Application -Roots $roots -Snapshot $systemSnapshot -CatalogProduct $CatalogProduct)) { $evidence.Add($item) }
    $uniqueEvidence = @($evidence.ToArray() | Group-Object { "$($_.Code)|$($_.Source)|$($_.Detail)" } | ForEach-Object { $_.Group[0] })
    $State.EvidenceCount = [int]$State.EvidenceCount + $uniqueEvidence.Count
    return [pscustomobject][ordered]@{
        Evidence=$uniqueEvidence; Roots=$roots; FilesEnumerated=[int]$filesEnumerated; SignatureChecks=[int]$signatureChecks
        HashChecks=[int]$hashChecks; Complete=[bool]($complete -and [bool]$State.IsAdministrator -and -not $State.TimeLimitReached -and -not $State.EntryLimitReached -and -not $State.SignatureLimitReached -and -not $State.HashLimitReached)
        Status=$(if ($complete -and [bool]$State.IsAdministrator) {'Scanned'} else {'CoverageLimited'})
        RepresentativeSignature=$representativeSignature
    }
}

function Get-ToolSoftwareLastDeepScanMetadata {
    if ($null -ne $script:ToolSoftwareLastDeepScanMetadata) { return $script:ToolSoftwareLastDeepScanMetadata }
    return [pscustomobject][ordered]@{
        Enabled=$false; Complete=$false; IsAdministrator=$false; ApplicationsScanned=0; ApplicationsSkipped=0
        UniqueRootsScanned=0; RootCacheHits=0; UniqueDirectoriesScanned=0; DirectoryCacheHits=0
        TotalEntries=0; RelevantFiles=0; SignatureChecks=0; HashChecks=0
        EvidenceCount=0; DurationMilliseconds=0; TimeLimitReached=$false; EntryLimitReached=$false
        SignatureLimitReached=$false; HashLimitReached=$false; AccessWarningCount=0
    }
}

function Get-ToolSoftwareVendorScope {
    param([Parameter(Mandatory = $true)]$Application, [AllowNull()][object]$CatalogProduct)
    $catalogVendor = Get-ToolSoftwareOptionalPropertyString -InputObject $CatalogProduct -Name 'Vendor'
    if (-not [string]::IsNullOrWhiteSpace($catalogVendor)) { return $catalogVendor }
    $text = (([string]$Application.Name) + ' ' + ([string]$Application.Publisher))
    if ($text -match '(?i)\bAdobe\b|\bAcrobat\b|\bPhotoshop\b|\bIllustrator\b|\bLightroom\b|\bPremiere\b') { return 'Adobe' }
    if ($text -match '(?i)\bAutodesk\b|\bAutoCAD\b|\bRevit\b|\b3ds Max\b|\bCivil 3D\b|\bNavisworks\b|\bInventor\b') { return 'Autodesk' }
    if ($text -match '(?i)\bABBYY\b|\bFineReader\b') { return 'ABBYY' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Application.Publisher)) { return [string]$Application.Publisher }
    return 'Other'
}

function Get-ToolSoftwareAssessments {
    param(
        [Parameter(Mandatory = $true)]$Applications,
        [AllowNull()][object]$Catalog,
        $ExternalEvidence = @(),
        [switch]$DeepScan,
        [ValidateRange(15, 900)][int]$DeepScanMaximumDurationSeconds = 180,
        [ValidateRange(20, 10000)][int]$DeepScanMaximumSignatureChecks = 1400,
        [ValidateRange(20, 10000)][int]$DeepScanMaximumHashChecks = 1000
    )
    $results = New-Object System.Collections.Generic.List[object]
    $strictIdentityPattern = '(?i)(\bkmspico\b|\bkmsauto\b|\bauto[\s._-]*kms\b|\baact(?:portable)?\b|\bhwidgen\b|\bmassgrave\b|\badobe[\s._-]*genp\b|\bccmaker\b|\bxf[\s._-]*adsk\b|\bx[\s._-]*force\b|\bkeygen\b|\bcrack(?:ed)?\b|\bactivation[\s._-]*bypass\b|\bby\s+sandy[d]?\b)'
    $script:ToolSoftwareDeepFileCache = @{}
    $script:ToolSoftwareDeepDirectoryCache = @{}
    $script:ToolSoftwareDeepSystemSnapshotCache = $null
    $deepState = $null
    if ($DeepScan) {
        $deepState = New-ToolSoftwareDeepScanState -MaximumDurationSeconds $DeepScanMaximumDurationSeconds `
            -MaximumTotalSignatureChecks $DeepScanMaximumSignatureChecks -MaximumTotalHashChecks $DeepScanMaximumHashChecks
    } else {
        $script:ToolSoftwareLastDeepScanMetadata = $null
    }
    $signatureRunspacePool = $null
    if ($DeepScan) {
        try {
            $signatureRunspacePool = [RunspaceFactory]::CreateRunspacePool(1, 4)
            $signatureRunspacePool.Open()
        } catch {
            if ($signatureRunspacePool) { try { $signatureRunspacePool.Dispose() } catch {} }
            $signatureRunspacePool = $null
        }
    }
    try {
    $applicationList = @($Applications)
    $originalIndexById = @{}
    $externalEvidenceByApplication = @{}
    $externalEvidenceByVendor = @{}
    foreach ($externalItem in @($ExternalEvidence)) {
        $externalApplicationId = if ($externalItem.PSObject.Properties['ApplicationId']) { [string]$externalItem.ApplicationId } else { '' }
        if ($externalApplicationId) {
            if (-not $externalEvidenceByApplication.ContainsKey($externalApplicationId)) {
                $externalEvidenceByApplication[$externalApplicationId] = New-Object System.Collections.Generic.List[object]
            }
            $externalEvidenceByApplication[$externalApplicationId].Add($externalItem)
            continue
        }
        $externalVendor = if ($externalItem.PSObject.Properties['VendorScope']) { [string]$externalItem.VendorScope } else { '' }
        if ($externalVendor -and $externalVendor -notin @('Other','Uncorrelated')) {
            if (-not $externalEvidenceByVendor.ContainsKey($externalVendor)) {
                $externalEvidenceByVendor[$externalVendor] = New-Object System.Collections.Generic.List[object]
            }
            $externalEvidenceByVendor[$externalVendor].Add($externalItem)
        }
    }
    $applicationEntries = New-Object System.Collections.Generic.List[object]
    for ($entryIndex = 0; $entryIndex -lt $applicationList.Count; $entryIndex++) {
        $entryApplication = $applicationList[$entryIndex]
        $entryCatalogProduct = Find-ToolSoftwareCatalogProduct -Application $entryApplication -Catalog $Catalog
        $entryVendorScope = Get-ToolSoftwareVendorScope -Application $entryApplication -CatalogProduct $entryCatalogProduct
        $entryLicenseModel = if ($entryCatalogProduct) { Get-ToolSoftwareOptionalPropertyString -InputObject $entryCatalogProduct -Name 'LicenseModel' -Default 'Unknown' } else { 'Unknown' }
        $entryIdentityText = (([string]$entryApplication.Name) + ' ' + ([string]$entryApplication.Publisher) + ' ' + ([string]$entryApplication.InstallLocation))
        $entryApplicationId = [string]$entryApplication.Id
        $entryHasExternalEvidence = [bool](
            ($entryApplicationId -and $externalEvidenceByApplication.ContainsKey($entryApplicationId)) -or
            ($entryVendorScope -and $externalEvidenceByVendor.ContainsKey($entryVendorScope))
        )
        $entryPriority = 1
        if ($entryHasExternalEvidence -or $entryIdentityText -match $strictIdentityPattern -or
            $entryLicenseModel -in @('Paid','Subscription','Perpetual','Trialware','Freemium')) {
            $entryPriority = 0
        } elseif ($entryLicenseModel -in @('Free','OpenSource','Freeware','SystemComponent','Driver','Runtime')) {
            $entryPriority = 2
        }
        if (-not [string]::IsNullOrWhiteSpace($entryApplicationId)) { $originalIndexById[$entryApplicationId] = $entryIndex }
        $signatureWeight = if ($entryPriority -eq 0) { 6 } elseif ($entryPriority -eq 1) { 2 } else { 1 }
        # Hồ sơ nhanh vẫn kiểm tra chữ ký cho mọi ứng dụng có tệp đại diện,
        # nhưng tập trung nhiều lượt hơn vào phần mềm trả phí/dùng thử hoặc đã
        # có dấu vết. Quét tên artifact, cây tệp và dấu vết hệ thống giữ nguyên.
        $desiredSignatureLimit = if ($entryPriority -eq 0) { 6 } elseif ($entryPriority -eq 1) { 3 } else { 1 }
        $applicationEntries.Add([pscustomobject][ordered]@{
            Application=$entryApplication; CatalogProduct=$entryCatalogProduct; VendorScope=$entryVendorScope
            LicenseModel=$entryLicenseModel; IdentityText=$entryIdentityText; ScanPriority=$entryPriority; OriginalIndex=$entryIndex
            SignatureWeight=$signatureWeight; DesiredSignatureLimit=$desiredSignatureLimit
        })
    }
    $scanEntries = if ($DeepScan) {
        @($applicationEntries.ToArray() | Sort-Object ScanPriority, OriginalIndex)
    } else { @($applicationEntries.ToArray()) }
    $quickSignatureResults = @{}
    if (-not $DeepScan) {
        # Các chữ ký này độc lập với nhau. Gom đúng cùng tập đường dẫn mà vòng
        # lặp cũ kiểm tra rồi chạy tối đa bốn worker giúp rút ngắn thời gian mà
        # không bỏ mẫu, không đổi kết luận và vẫn dùng chung bộ nhớ đệm an toàn.
        $quickSignaturePaths = @($scanEntries | Where-Object {
            $candidate = $_.Application
            [string]$candidate.SignatureStatus -eq 'NotChecked' -and
            -not [string]::IsNullOrWhiteSpace([string]$candidate.RepresentativePath) -and
            ([string]$_.LicenseModel -in @('Paid','Subscription','Perpetual','Trialware','Freemium') -or
                [string]$_.IdentityText -match $strictIdentityPattern)
        } | ForEach-Object { [string]$_.Application.RepresentativePath } | Select-Object -Unique)
        if ($quickSignaturePaths.Count -gt 0) {
            $quickSignatureResults = Get-ToolSoftwareSignatureStatesParallel -Paths $quickSignaturePaths -ThrottleLimit 4
        }
    }
    $remainingSignatureWeight = [int](($scanEntries | Measure-Object -Property SignatureWeight -Sum).Sum)
    foreach ($applicationEntry in $scanEntries) {
        $application = $applicationEntry.Application
        $catalogProduct = $applicationEntry.CatalogProduct
        $vendorScope = [string]$applicationEntry.VendorScope
        $licenseModel = [string]$applicationEntry.LicenseModel
        $evidence = New-Object System.Collections.Generic.List[object]
        $deepResult = [pscustomobject][ordered]@{
            Evidence=@(); Roots=@(); FilesEnumerated=0; SignatureChecks=0; HashChecks=0
            Complete=$false; Status='NotRequested'; RepresentativeSignature=$null
        }
        $identityText = [string]$applicationEntry.IdentityText
        $signatureStatus = [string]$application.SignatureStatus
        if (-not $DeepScan -and $signatureStatus -eq 'NotChecked' -and -not [string]::IsNullOrWhiteSpace([string]$application.RepresentativePath) -and
            ($licenseModel -in @('Paid','Subscription','Perpetual','Trialware','Freemium') -or $identityText -match $strictIdentityPattern)) {
            $signaturePath = [string]$application.RepresentativePath
            $signaturePathKey = $signaturePath.ToLowerInvariant()
            try { $signaturePathKey = ([IO.Path]::GetFullPath($signaturePath)).ToLowerInvariant() } catch {}
            $signature = if ($quickSignatureResults -and $quickSignatureResults.ContainsKey($signaturePathKey)) {
                $quickSignatureResults[$signaturePathKey]
            } else {
                # Fallback bảo toàn hành vi cũ nếu worker bị gián đoạn hoặc đường
                # dẫn đổi trạng thái giữa lúc lập lô và lúc dùng kết quả.
                Get-ToolSoftwareSignatureState -Path $signaturePath
            }
            $signatureStatus = [string]$signature.Status
            $application | Add-Member -NotePropertyName SignatureStatus -NotePropertyValue $signatureStatus -Force
            $application | Add-Member -NotePropertyName SignaturePublisher -NotePropertyValue ([string]$signature.Publisher) -Force
            if ([string]::IsNullOrWhiteSpace([string]$application.Publisher) -and $signature.CompanyName) {
                $application | Add-Member -NotePropertyName Publisher -NotePropertyValue ([string]$signature.CompanyName) -Force
            }
            if ([string]::IsNullOrWhiteSpace([string]$application.Version) -and $signature.FileVersion) {
                $application | Add-Member -NotePropertyName Version -NotePropertyValue ([string]$signature.FileVersion) -Force
            }
        }
        if ($identityText -match $strictIdentityPattern) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'KnownUnauthorizedName' -Strength 'Strong' -Source 'Identity' `
                -EvidenceGroup 'KnownActivator' -Detail ([string]$matches[0]) -Decisive))
        }
        if ($catalogProduct) {
            $catalogTrustedForDecisiveEvidence = Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $Catalog
            foreach ($pattern in @(Get-ToolSoftwareOptionalPropertyValues -InputObject $catalogProduct -Name 'UnauthorizedNamePatterns')) {
                if (Test-ToolSoftwareAnyPattern -Text $identityText -Patterns @($pattern)) {
                    $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'CatalogUnauthorizedName' -Strength 'Strong' -Source 'Catalog' `
                        -EvidenceGroup 'KnownUnauthorizedPackage' -Detail ([string]$pattern) -Decisive:$catalogTrustedForDecisiveEvidence))
                }
            }
        }
        if ($licenseModel -notin @('Free','OpenSource','Freeware','SystemComponent','Driver','Runtime')) {
            if (-not $DeepScan) {
                foreach ($item in @(Get-ToolSoftwareLocationEvidence -Application $application)) { $evidence.Add($item) }
            }
        }
        if ($DeepScan) {
            $remainingSignatureBudget = [Math]::Max(0, [int]$deepState.MaximumTotalSignatureChecks - [int]$deepState.SignatureChecks)
            # Phân bổ có trọng số trên toàn bộ ứng dụng còn lại: phần mềm trả
            # phí/dùng thử hoặc đã có dấu vết nhận trọng số cao hơn, nhưng nhóm
            # chưa biết và miễn phí vẫn được giữ lượt. Root không có ứng viên
            # không tiêu ngân sách nên phần dư tự dồn cho các ứng dụng sau.
            $currentSignatureWeight = [Math]::Max(1, [int]$applicationEntry.SignatureWeight)
            $weightedSignatureLimit = [Math]::Max(1, [int][Math]::Floor(
                ($remainingSignatureBudget * $currentSignatureWeight) / [Math]::Max(1, $remainingSignatureWeight)))
            $perApplicationSignatureLimit = [Math]::Min([int]$applicationEntry.DesiredSignatureLimit, $weightedSignatureLimit)
            $remainingSignatureWeight = [Math]::Max(0, $remainingSignatureWeight - $currentSignatureWeight)
            $deepResult = Get-ToolSoftwareDeepScanEvidence -Application $application -CatalogProduct $catalogProduct -Catalog $Catalog -State $deepState `
                -MaximumSignatureChecksPerApplication $perApplicationSignatureLimit -SignatureRunspacePool $signatureRunspacePool
            foreach ($item in @($deepResult.Evidence)) { $evidence.Add($item) }
            if ($null -ne $deepResult.RepresentativeSignature) {
                $signature = $deepResult.RepresentativeSignature
                $signatureStatus = [string]$signature.Status
                $application | Add-Member -NotePropertyName SignatureStatus -NotePropertyValue $signatureStatus -Force
                $application | Add-Member -NotePropertyName SignaturePublisher -NotePropertyValue ([string]$signature.Publisher) -Force
                if ([string]::IsNullOrWhiteSpace([string]$application.Publisher) -and $signature.CompanyName) {
                    $application | Add-Member -NotePropertyName Publisher -NotePropertyValue ([string]$signature.CompanyName) -Force
                }
                if ([string]::IsNullOrWhiteSpace([string]$application.Version) -and $signature.FileVersion) {
                    $application | Add-Member -NotePropertyName Version -NotePropertyValue ([string]$signature.FileVersion) -Force
                }
            }
        }
        if ($signatureStatus -eq 'HashMismatch') {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'SignatureHashMismatch' -Strength 'Strong' -Source 'Authenticode' `
                -EvidenceGroup 'FileIntegrity' -Detail ([string]$application.RepresentativePath)))
        } elseif ($signatureStatus -eq 'NotTrusted') {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'SignatureNotTrusted' -Strength 'Moderate' -Source 'Authenticode' `
                -EvidenceGroup 'FileTrust' -Detail $signatureStatus))
        } elseif ($signatureStatus -eq 'NotSigned' -and $licenseModel -in @('Paid','Subscription','Perpetual','Trialware')) {
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code 'PaidBinaryNotSigned' -Strength 'Moderate' -Source 'Authenticode' `
                -EvidenceGroup 'FileIntegrity' -Detail ([string]$application.RepresentativePath)))
        }
        foreach ($item in @(Get-ToolSoftwareBlockedHostEvidence -CatalogProduct $catalogProduct)) { $evidence.Add($item) }
        $applicationId = [string]$application.Id
        $applicationExternalEvidence = New-Object System.Collections.Generic.List[object]
        if ($applicationId -and $externalEvidenceByApplication.ContainsKey($applicationId)) {
            foreach ($externalItem in $externalEvidenceByApplication[$applicationId]) { $applicationExternalEvidence.Add($externalItem) }
        }
        if ($vendorScope -and $externalEvidenceByVendor.ContainsKey($vendorScope)) {
            foreach ($externalItem in $externalEvidenceByVendor[$vendorScope]) { $applicationExternalEvidence.Add($externalItem) }
        }
        foreach ($item in $applicationExternalEvidence) {
            $strength = if ([string]$item.Strength) { [string]$item.Strength } else { 'Strong' }
            if ($strength -notin @('Conclusive','Strong','Moderate','Weak')) { $strength='Strong' }
            $externalCode = if ($item.PSObject.Properties['Code'] -and $item.Code) { [string]$item.Code } else { 'External' + [string]$item.Type }
            $externalSource = if ($item.PSObject.Properties['Source'] -and $item.Source) { [string]$item.Source } else { [string]$item.Type }
            $externalGroup = if ($item.PSObject.Properties['EvidenceGroup'] -and $item.EvidenceGroup) { [string]$item.EvidenceGroup } else { $externalSource }
            $externalDetail = if ($item.PSObject.Properties['Location'] -and $item.Location) { [string]$item.Location } else { [string]$item.Detail }
            $externalDecisive = [bool](($item.PSObject.Properties['Decisive'] -and [bool]$item.Decisive) -or $strength -eq 'Conclusive')
            $evidence.Add((New-ToolSoftwareTechnicalEvidence -Code $externalCode -Strength $strength -Source $externalSource `
                -EvidenceGroup $externalGroup -Detail $externalDetail -Decisive:$externalDecisive))
        }
        $uniqueEvidence = @($evidence.ToArray() | Group-Object { "$($_.Code)|$($_.Source)|$($_.Detail)" } | ForEach-Object { $_.Group[0] })
        $conclusiveCount = @($uniqueEvidence | Where-Object { [string]$_.Strength -eq 'Conclusive' }).Count
        $strongCount = @($uniqueEvidence | Where-Object { [string]$_.Strength -in @('Conclusive','Strong') }).Count
        $moderateCount = @($uniqueEvidence | Where-Object { [string]$_.Strength -eq 'Moderate' }).Count
        $weakCount = @($uniqueEvidence | Where-Object { [string]$_.Strength -eq 'Weak' }).Count
        $decisiveCount = @($uniqueEvidence | Where-Object {
            [string]$_.Strength -eq 'Conclusive' -or ($_.PSObject.Properties['Decisive'] -and [bool]$_.Decisive)
        }).Count
        $strongEvidenceGroupCount = @($uniqueEvidence | Where-Object { [string]$_.Strength -in @('Conclusive','Strong') } | ForEach-Object {
            if ($_.PSObject.Properties['EvidenceGroup'] -and $_.EvidenceGroup) { [string]$_.EvidenceGroup } else { [string]$_.Source }
        } | Select-Object -Unique).Count
        $integrityEvidenceCount = @($uniqueEvidence | Where-Object {
            [string]$_.Code -in @('SignatureHashMismatch','DeepSignatureHashMismatch')
        }).Count
        $independentLicenseRiskCount = @($uniqueEvidence | Where-Object {
            [string]$_.Strength -in @('Conclusive','Strong') -and
            [string]$_.EvidenceGroup -notin @('FileIntegrity','FileTrust','PublisherMismatch')
        }).Count
        $licensingDecisiveCount = @($uniqueEvidence | Where-Object {
            ([string]$_.Strength -eq 'Conclusive' -or ($_.PSObject.Properties['Decisive'] -and [bool]$_.Decisive)) -and
            [string]$_.EvidenceGroup -notin @('FileIntegrity','FileTrust','PublisherMismatch')
        }).Count
        $knownActivationState = Get-ToolSoftwareKnownActivationState -Application $application -CatalogProduct $catalogProduct
        $statusCode = 'Unverified'
        $confidence = 'Low'
        if ($licensingDecisiveCount -gt 0 -or ($independentLicenseRiskCount -gt 0 -and $strongCount -ge 2 -and $strongEvidenceGroupCount -ge 2)) { $statusCode='NonGenuine'; $confidence='High' }
        elseif ($integrityEvidenceCount -gt 0 -and $independentLicenseRiskCount -eq 0) { $statusCode='IntegrityCompromised'; $confidence='High' }
        elseif ($strongCount -gt 0 -or $moderateCount -gt 0 -or $weakCount -ge 2) { $statusCode='Suspicious'; $confidence='Medium' }
        elseif ($knownActivationState -eq 'Unactivated') { $statusCode='Unactivated'; $confidence='High' }
        elseif ($licenseModel -in @('Free','OpenSource','Freeware','SystemComponent','Driver','Runtime')) { $statusCode='FreeOrIncluded'; $confidence=$(if ($catalogProduct) {'High'} else {'Medium'}) }
        elseif ($licenseModel -eq 'Trialware') { $statusCode='TrialOrUnverified'; $confidence='Medium' }
        elseif ($catalogProduct) { $statusCode='Unverified'; $confidence='Medium' }

        $remediationAdapter = if ($catalogProduct -and $catalogProduct.PSObject.Properties['RemediationAdapter']) {
            [string]$catalogProduct.RemediationAdapter
        } else { '' }
        if ([string]::IsNullOrWhiteSpace($remediationAdapter)) {
            if ($vendorScope -eq 'Adobe' -and [string]$application.SourceKind -ne 'Appx' -and [string]$application.Name -match '(?i)\b(?:Acrobat|Distiller|Photoshop|Illustrator|InDesign|Lightroom|Premiere|After Effects|Audition|Animate|Dreamweaver)\b') { $remediationAdapter = 'Adobe' }
            elseif ($vendorScope -eq 'Autodesk' -and [string]$application.SourceKind -ne 'Appx' -and [string]$application.Name -match '(?i)\b(?:Autodesk|AutoCAD|Revit|3ds Max|Civil 3D|Navisworks|Inventor|Fusion 360)\b') { $remediationAdapter = 'Autodesk' }
        }
        # Tách khả năng nhận diện/chọn khỏi adapter theo hãng. Mọi ứng dụng có
        # bằng chứng NonGenuine/Suspicious đều có thể được người dùng chọn, trừ
        # thành phần hệ thống/driver/runtime. Adapter Generic chỉ cho phép các
        # thao tác đã khóa phạm vi (cách ly artifact chính xác, sửa hosts chính
        # xác, Repair MSI đã xác thực hoặc hướng dẫn cài lại chính thức).
        $knownLocalResetEligible = [bool](
            $remediationAdapter -eq 'WinRAR' -and
            $knownActivationState -eq 'LocalLicensePresent'
        )
        $manualEligible = [bool](
            (($statusCode -in @('NonGenuine','Suspicious')) -or $knownLocalResetEligible) -and
            $licenseModel -notin @('SystemComponent','Driver','Runtime')
        )
        if ($manualEligible -and [string]::IsNullOrWhiteSpace($remediationAdapter)) {
            $remediationAdapter = 'Generic'
        }
        # AutoEligible ở lớp đánh giá chỉ biểu thị có bằng chứng mạnh. Lớp lập
        # kế hoạch còn phải chứng minh tồn tại hành động tự động an toàn trước
        # khi mục thực sự được đưa vào chế độ Tự động an toàn.
        $autoEligible = [bool]($manualEligible -and -not $knownLocalResetEligible -and $decisiveCount -gt 0)
        $needsReview = [bool]($statusCode -notin @('FreeOrIncluded','GenuineVerified','Unactivated'))
        $referenceUrl = Get-ToolSoftwareOptionalPropertyString -InputObject $catalogProduct -Name 'OfficialUrl'
        $remediationImpact = if (-not $manualEligible) {
            'NoChangeProposed'
        } elseif ($remediationAdapter -in @('Adobe','Autodesk')) {
            'VendorSharedLicenseState'
        } elseif ($knownLocalResetEligible) {
            'LocalLicenseFileReset'
        } else {
            'GenericArtifactCleanupOrOfficialRepair'
        }
        # Building an ordered property bag is materially faster than thousands
        # of Add-Member calls and produces the same PSCustomObject contract.
        $resultData = [ordered]@{}
        foreach ($property in $application.PSObject.Properties) { $resultData[$property.Name] = $property.Value }
        $applicationSystemComponent = $application.PSObject.Properties['IsSystemComponent']
        $applicationSystemReason = $application.PSObject.Properties['SystemComponentReason']
        $catalogIdentifiesUserApplication = [bool]($catalogProduct -and $licenseModel -notin @('SystemComponent','Driver','Runtime','Unknown'))
        $isSystemComponent = [bool]((($applicationSystemComponent -and [bool]$applicationSystemComponent.Value) -and -not $catalogIdentifiesUserApplication) -or
            $licenseModel -in @('SystemComponent','Driver','Runtime'))
        $systemComponentReason = if ($applicationSystemReason) { [string]$applicationSystemReason.Value } else { '' }
        if ($isSystemComponent -and [string]::IsNullOrWhiteSpace($systemComponentReason)) {
            $systemComponentReason = if ($licenseModel -in @('SystemComponent','Driver','Runtime')) { 'Catalog:' + $licenseModel } else { 'HeuristicOrPlatformMetadata' }
        }
        foreach ($pair in @(
            @('VendorScope',$vendorScope), @('CatalogProductId',$(Get-ToolSoftwareOptionalPropertyString -InputObject $catalogProduct -Name 'Id')),
            @('LicenseModel',$licenseModel), @('OfficialReferenceUrl',$referenceUrl), @('AssessmentCode',$statusCode),
            @('Confidence',$confidence), @('Evidence',$uniqueEvidence), @('EvidenceCount',[int]$uniqueEvidence.Count),
            @('ConclusiveEvidenceCount',[int]$conclusiveCount), @('StrongEvidenceCount',[int]$strongCount),
            @('ModerateEvidenceCount',[int]$moderateCount), @('WeakEvidenceCount',[int]$weakCount),
            @('DecisiveEvidenceCount',[int]$decisiveCount), @('IndependentStrongEvidenceGroupCount',[int]$strongEvidenceGroupCount),
            @('TechnicalStatus',$statusCode), @('NeedsReview',$needsReview), @('ActivationStateProbe',$knownActivationState),
            @('DeepScanEnabled',[bool]$DeepScan), @('DeepScanStatus',[string]$deepResult.Status), @('DeepScanComplete',[bool]$deepResult.Complete),
            @('DeepScanRoots',@($deepResult.Roots)), @('DeepScanFilesEnumerated',[int]$deepResult.FilesEnumerated),
            @('DeepScanSignatureChecks',[int]$deepResult.SignatureChecks), @('DeepScanHashChecks',[int]$deepResult.HashChecks),
            @('RemediationAdapter',$remediationAdapter), @('RemediationSupported',$manualEligible), @('ManualEligible',$manualEligible),
            @('AutoEligible',$autoEligible), @('RemediationImpact',$remediationImpact),
            @('IsSystemComponent',$isSystemComponent), @('SystemComponentReason',$systemComponentReason),
            @('CatalogSource',$(if ($Catalog) {Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogSource' -Default 'Unavailable'} else {'Unavailable'})),
            @('CatalogVersion',$(Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogVersion'))
        )) { $resultData[[string]$pair[0]] = $pair[1] }
        $results.Add([pscustomobject]$resultData)
    }
    if ($DeepScan) {
        $systemWarningCount = if ($null -ne $script:ToolSoftwareDeepSystemSnapshotCache) { [int]@($script:ToolSoftwareDeepSystemSnapshotCache.Warnings).Count } else { 0 }
        $duration = [int][Math]::Min([int]::MaxValue, ([DateTime]::UtcNow - [DateTime]$deepState.StartedAtUtc).TotalMilliseconds)
        $script:ToolSoftwareLastDeepScanMetadata = [pscustomobject][ordered]@{
            Enabled=$true
            Complete=[bool]([bool]$deepState.IsAdministrator -and -not $deepState.TimeLimitReached -and -not $deepState.EntryLimitReached -and -not $deepState.SignatureLimitReached -and -not $deepState.HashLimitReached)
            IsAdministrator=[bool]$deepState.IsAdministrator; ApplicationsScanned=[int]$deepState.ApplicationsScanned
            ApplicationsSkipped=[int]$deepState.ApplicationsSkipped; UniqueRootsScanned=[int]$deepState.UniqueRootsScanned
            RootCacheHits=[int]$deepState.RootCacheHits; UniqueDirectoriesScanned=[int]$deepState.UniqueDirectoriesScanned
            DirectoryCacheHits=[int]$deepState.DirectoryCacheHits; TotalEntries=[int]$deepState.TotalEntries; RelevantFiles=[int]$deepState.RelevantFiles
            SignatureChecks=[int]$deepState.SignatureChecks; HashChecks=[int]$deepState.HashChecks; EvidenceCount=[int]$deepState.EvidenceCount
            DurationMilliseconds=$duration; TimeLimitReached=[bool]$deepState.TimeLimitReached; EntryLimitReached=[bool]$deepState.EntryLimitReached
            SignatureLimitReached=[bool]$deepState.SignatureLimitReached; HashLimitReached=[bool]$deepState.HashLimitReached
            AccessWarningCount=([int]$deepState.AccessWarningCount + $systemWarningCount)
        }
    }
    return @($results.ToArray() | Sort-Object @{Expression={
        $resultId = [string]$_.Id
        if ($originalIndexById.ContainsKey($resultId)) { return [int]$originalIndexById[$resultId] }
        return [int]::MaxValue
    }})
    } finally {
        if ($signatureRunspacePool) {
            try { $signatureRunspacePool.Close() } catch {}
            $signatureRunspacePool.Dispose()
        }
    }
}

function Get-ToolSoftwareInventoryMetadata {
    param($Applications, [AllowNull()][object]$Catalog)
    return [pscustomobject][ordered]@{
        SchemaVersion=$script:ToolSoftwareInventorySchemaVersion
        ApplicationCount=[int]@($Applications).Count
        RegistryCount=[int]@($Applications | Where-Object { $_.DiscoverySources -contains 'Registry' -or $_.SourceKind -eq 'Registry' }).Count
        AppxCount=[int]@($Applications | Where-Object { $_.DiscoverySources -contains 'Appx' -or $_.SourceKind -eq 'Appx' }).Count
        PortableOrShortcutCount=[int]@($Applications | Where-Object { $_.SourceKind -in @('Shortcut','PortableDiscovery') }).Count
        CatalogSource=$(if ($Catalog) {Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogSource' -Default 'Unavailable'} else {'Unavailable'})
        CatalogVersion=$(Get-ToolSoftwareOptionalPropertyString -InputObject $Catalog -Name 'CatalogVersion')
        CatalogRuleCount=$(if ($Catalog) {[int]@(Get-ToolSoftwareOptionalPropertyValues -InputObject $Catalog -Name 'Products').Count} else {0})
        DeepScan=(Get-ToolSoftwareLastDeepScanMetadata)
        GeneratedAtUtc=[DateTime]::UtcNow.ToString('o')
    }
}
