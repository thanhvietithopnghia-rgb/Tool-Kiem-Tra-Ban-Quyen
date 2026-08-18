param(
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra"),
    [ValidateSet("All", "Hardware", "Windows", "Office", "Software")]
    [string]$Mode = "All",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [string]$ApprovedKmsServerFile = "",
    [switch]$Pdf,
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$ToolVersion = "4.8"
$ToolReleaseVersion = "4.8.0.1"

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$compatibilityHelper = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
$capabilityHelper = Join-Path $PSScriptRoot "Tool-Capabilities.ps1"
$loggingHelper = Join-Path $PSScriptRoot "Tool-Logging.ps1"
$moduleContractHelper = Join-Path $PSScriptRoot "Tool-ModuleContract.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$pluginEngineHelper = Join-Path $PSScriptRoot "Tool-PluginEngine.ps1"
$timelineHelper = Join-Path $PSScriptRoot "Tool-LicenseTimeline.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
$offlinePolicyHelper = Join-Path $PSScriptRoot "Tool-OfflinePolicy.ps1"
$scanOptimizationHelper = Join-Path $PSScriptRoot "Tool-ScanOptimization.ps1"
$softwareInventoryHelper = Join-Path $PSScriptRoot "Tool-SoftwareInventory.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-ReportText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-ReportText "report.bootstrap.powerShellRequired"); exit 10 }
try {
    foreach ($requiredPath in @($runtimeHelper, $compatibilityHelper, $capabilityHelper, $loggingHelper, $moduleContractHelper, $reportSchemaHelper, $reportExportHelper, $pluginEngineHelper, $timelineHelper, $offlinePolicyHelper, $scanOptimizationHelper, $softwareInventoryHelper)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw (Get-ReportText "common.missingDependency" @([IO.Path]::GetFileName($requiredPath))) }
    }
    . $runtimeHelper
    . $compatibilityHelper
    . $capabilityHelper
    . $loggingHelper
    . $moduleContractHelper
    . $reportSchemaHelper
    . $reportExportHelper
    . $pluginEngineHelper
    . $timelineHelper
    . $offlinePolicyHelper
    . $scanOptimizationHelper
    . $softwareInventoryHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
    $nativeExplorerPath = Get-ToolNativeSystemPath "explorer.exe"
    $capabilityState = Get-ToolCapabilityProfile
    $compatibilityState = Get-ToolCompatibilityMetadata
    $localizationState = Get-ToolLocalizationMetadata
    $offlinePolicyState = Get-ToolOfflinePolicyMetadata
    $reportSchemaState = Get-ToolReportSchemaMetadata
    $script:reportCulture = $Culture
    $script:reportOfflineMode = [bool](Get-ToolOfflineMode)
    $moduleContractState = Get-ToolModuleContractMetadata
    $reportModuleId = Get-ToolReportModuleId -Mode $Mode
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_MODULE_ID) -and [string]$env:TOOL_MODULE_ID -ne $reportModuleId) { throw (Get-ReportText "report.bootstrap.moduleMismatch" @($env:TOOL_MODULE_ID)) }
    $moduleAvailability = Test-ToolModuleAvailability -ModuleId $reportModuleId -CapabilityProfile $capabilityState -SourceDirectory $PSScriptRoot
    if (-not $moduleAvailability.Available) { throw $moduleAvailability.Message }
    $moduleInvocation = New-ToolModuleInvocation -ModuleId $reportModuleId
    $loggingState = Initialize-ToolLogging -Component "Report" -ToolVersion $ToolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $ToolVersion
    [void](Write-ToolLog -Level "INFO" -Event "Report.Start" -Message (Get-ReportText "report.log.started" @($Mode)) -Data ([ordered]@{ ModuleId=$reportModuleId; InvocationId=$moduleInvocation.InvocationId; Mode=$Mode; Culture=$Culture; OfflineMode=[bool]$script:reportOfflineMode; Redacted=[bool]$RedactSensitive; Capabilities=$capabilityState }))
} catch {
    Write-Host $_.Exception.Message
    exit 12
}

$ErrorActionPreference = "SilentlyContinue"
$ToolName = Get-ToolText -Key "app.title" -Culture $Culture
$ToolDescription = Get-ToolText -Key "report.description" -Culture $Culture
$DeveloperCredit = Get-ToolText -Key "report.footer" -Culture $Culture
$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$started = Get-Date
$computer = $env:COMPUTERNAME
$reportComputer = if ($RedactSensitive) { Get-ReportText "report.file.redactedToken" } else { $computer }
$stamp = $started.ToString("yyyyMMdd_HHmmss_fff")
$modeInfo = switch ($Mode) {
    "Hardware" { @{ Suffix=(Get-ReportText "report.file.hardware"); Title=(Get-ToolText -Key "report.title.hardware" -Culture $Culture) } }
    "Windows"  { @{ Suffix=(Get-ReportText "report.file.windows"); Title=(Get-ToolText -Key "report.title.windows" -Culture $Culture) } }
    "Office"   { @{ Suffix=(Get-ReportText "report.file.office"); Title=(Get-ToolText -Key "report.title.office" -Culture $Culture) } }
    "Software" { @{ Suffix=(Get-ReportText "report.file.software"); Title=(Get-ToolText -Key "report.title.software" -Culture $Culture) } }
    default    { @{ Suffix=(Get-ReportText "report.file.all"); Title=(Get-ToolText -Key "report.title.all" -Culture $Culture) } }
}
$wantHardware = $Mode -in @("All", "Hardware")
$wantWindows = $Mode -in @("All", "Windows")
$wantOffice = $Mode -in @("All", "Office")
$wantSoftware = $Mode -in @("All", "Software")
$strongCrackPattern = "(?i)(\bkmspico\b|\bkmsauto\b|\bauto[\s._-]*kms\b|\bautokms\b|\bkms[\s._-]*vl(?:[\s._-]*all)?\b|\bkms-r\b|\baact(?:portable)?\b|\bsppextcomobj(?:patcher|hook)\b|\bspp[\s._-]*(?:hook|patcher)\b|\bmicrosoft[\s_-]+toolkit\b|\bhwidgen\b|\bmassgrave\b|\bmas[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge)\b|\bpmas(?:[\s._-]*(?:aio|all[\s._-]*in[\s._-]*one|activat(?:ion|or)|hwid|kms|ohook|tsforge))?\b|\bmicrosoft[\s._-]*activation[\s._-]*scripts?\b|\bactivation[\s._-]*program[\s._-]*(?:v(?:ersion)?[\s._-]*)?1(?:\.|\s+|[_-])17\b|erturk-dev\.netlify\.app/run|\btsforge\b|\bohook\b|\bget\.activated\.win\b|\badobe[\s._-]*genp\b|\bccmaker\b|\bxf[\s._-]*adsk\b|\bx[\s._-]*force.{0,20}\b(?:autodesk|adsk)\b|\b(?:adobe|autodesk|adsk).{0,24}\b(?:patcher|activator|crack)\b|\bkeygen\b|\bcrack(?:ed)?\b|\bactivation[\s._-]*bypass\b)"
$reportActivatorArtifactExtensions = @('.exe','.dll','.com','.scr','.cmd','.bat','.ps1','.vbs','.js','.msi','.zip','.rar','.7z','.jar')
$crackFindings = @()
$manualReviewFindings = @()
$reportTitle = $modeInfo.Title
$reportBasePath = Join-Path $OutputDir ((Get-ReportText "report.file.prefix") + "_$($modeInfo.Suffix)_${reportComputer}_${stamp}")
$reportPath = "$reportBasePath.html"
$pdfPath = "$reportBasePath.pdf"
$jsonPath = "$reportBasePath.json"
$xmlPath = "$reportBasePath.xml"
$manifestPath = "${reportBasePath}-SHA256SUMS.txt"

$script:reportPresentationCache = @{}
$script:reportLiteralTranslationMaps = @{}

function Get-ReportLiteralTranslationMap {
    param([Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$TargetCulture)

    if ($script:reportLiteralTranslationMaps.ContainsKey($TargetCulture)) {
        return $script:reportLiteralTranslationMaps[$TargetCulture]
    }
    # Literal keys are SHA-256 identifiers in the catalog, but their vi-VN
    # values are the exact source literals used by this report. Building one
    # ordinal reverse map avoids hashing every unique application path, vendor,
    # version and evidence string during JSON/XML preparation.
    $sourceCatalog = Get-ToolLocalizationCatalog -Culture 'vi-VN'
    $targetCatalog = Get-ToolLocalizationCatalog -Culture $TargetCulture
    $map = New-Object Collections.Hashtable ([StringComparer]::Ordinal)
    foreach ($property in $sourceCatalog.PSObject.Properties) {
        if (-not ([string]$property.Name).StartsWith('report.literal.', [StringComparison]::Ordinal)) { continue }
        $sourceText = [string]$property.Value
        $targetProperty = $targetCatalog.PSObject.Properties[[string]$property.Name]
        $map[$sourceText] = if ($targetProperty) { [string]$targetProperty.Value } else { $sourceText }
    }
    $script:reportLiteralTranslationMaps[$TargetCulture] = $map
    return $map
}

function Get-ReportPresentationTextForCulture {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][ValidateSet("vi-VN", "en-US")][string]$TargetCulture
    )

    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    $cacheKey = $TargetCulture + [char]0 + $text
    if ($script:reportPresentationCache.ContainsKey($cacheKey)) { return [string]$script:reportPresentationCache[$cacheKey] }
    $literalMap = Get-ReportLiteralTranslationMap -TargetCulture $TargetCulture
    if ($literalMap.ContainsKey($text)) {
        $literalText = [string]$literalMap[$text]
        $script:reportPresentationCache[$cacheKey] = $literalText
        return $literalText
    }
    if ($text -notmatch '(?im)^(?:San pham|Dong san pham|Phien ban|Kenh|Doi chieu catalog|Nen tang|Trang thai|Mo ta|Partial key):|\b(?:ngay|gio|phut)\b') {
        $script:reportPresentationCache[$cacheKey] = $text
        return $text
    }
    $replacements = @(
        @('(?m)^San pham:', 'report.prefix.product'),
        @('(?m)^Dong san pham:', 'report.prefix.productFamily'),
        @('(?m)^Phien ban:', 'report.prefix.version'),
        @('(?m)^Kenh:', 'report.prefix.channel'),
        @('(?m)^Doi chieu catalog:', 'report.prefix.catalog'),
        @('(?m)^Nen tang:', 'report.prefix.platform'),
        @('(?m)^Trang thai:', 'report.prefix.status'),
        @('(?m)^Mo ta:', 'report.prefix.description'),
        @('(?m)^Partial key:', 'report.prefix.partialKey'),
        @('(?i)\bngay\b', 'report.duration.days'),
        @('(?i)\bgio\b', 'report.duration.hours'),
        @('(?i)\bphut\b', 'report.duration.minutes')
    )
    foreach ($replacement in $replacements) {
        $replacementText = Get-ToolText -Key ([string]$replacement[1]) -Culture $TargetCulture
        $text = [regex]::Replace($text, [string]$replacement[0], $replacementText)
    }
    $script:reportPresentationCache[$cacheKey] = $text
    return $text
}

function Get-ReportPresentationText {
    param([AllowNull()][object]$Value)
    return Get-ReportPresentationTextForCulture -Value $Value -TargetCulture $Culture
}

function Protect-ReportText($value, [switch]$PreserveVersionLike) {
    if ($null -eq $value) { return "" }
    $text = [string]$value
    if (-not $RedactSensitive) { return $text }

    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
            $secretPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $secretPattern, (Get-ReportText "report.redaction.value"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    if (-not $PreserveVersionLike) {
        # IPv6 has too many valid textual forms for a single permissive replacement
        # regex. Select bounded candidates, then require .NET to parse the address as
        # IPv6 before redacting it. Scope IDs are metadata appended to an otherwise
        # valid address, so validate the address portion separately.
        $ipv6RedactionToken = Get-ReportText "report.redaction.ip"
        $ipv6Evaluator = [Text.RegularExpressions.MatchEvaluator]{
            param([Text.RegularExpressions.Match]$match)

            $candidate = [string]$match.Groups['Address'].Value
            $trailingText = ''
            if ($candidate.EndsWith('.')) {
                # A sentence-ending full stop is allowed by the IPv4-mapped address
                # character class but is not part of the address or its scope ID.
                $candidate = $candidate.Substring(0, $candidate.Length - 1)
                $trailingText = '.'
            }

            $scopeIndex = $candidate.IndexOf('%')
            $addressForParsing = if ($scopeIndex -ge 0) {
                $candidate.Substring(0, $scopeIndex)
            } else {
                $candidate
            }
            $parsedAddress = $null
            $isIpv6 = (
                [regex]::Matches($addressForParsing, ':').Count -ge 2 -and
                [Net.IPAddress]::TryParse($addressForParsing, [ref]$parsedAddress) -and
                $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
            )
            if (-not $isIpv6) { return $match.Value }

            $port = if ($match.Groups['Port'].Success) { [string]$match.Groups['Port'].Value } else { '' }
            return $ipv6RedactionToken + $port + $trailingText
        }
        $bracketedIpv6Pattern = '(?i)(?<![0-9A-Z_.:%-])\[(?<Address>[0-9A-F:.]+(?:%[0-9A-Z_.~-]+)?)\](?<Port>:[0-9]{1,5})?(?![0-9A-Z_:%~-])'
        $unbracketedIpv6Pattern = '(?i)(?<![0-9A-Z_.:%-])(?<Address>(?=[0-9A-F:.%_-]*:)[0-9A-F:.]+(?:%[0-9A-Z_.~-]+)?)(?![0-9A-Z_:%~-])'
        $text = [regex]::Replace($text, $bracketedIpv6Pattern, $ipv6Evaluator)
        $text = [regex]::Replace($text, $unbracketedIpv6Pattern, $ipv6Evaluator)

        $ipv4Part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
        $text = [regex]::Replace($text, "(?<![0-9.])$ipv4Part(?:\.$ipv4Part){3}(?![0-9.])", (Get-ReportText "report.redaction.ip"))
    }
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-ReportText "report.redaction.mac"))
    return $text
}

function ConvertTo-ReportRedactedObject {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0,
        [string]$PropertyName = ''
    )

    if (-not $RedactSensitive -or $null -eq $Value) { return $Value }
    $preserveVersionLike = [bool]($PropertyName -match '(?i)(?:version|phien ban|build|schema|date|ngay|sha|hash|thumbprint)' -or
        $PropertyName -match '(?i)^(?:name|software|product|application|title|ten phan mem)$')
    $fullySensitiveProperty = [bool]($PropertyName -match '(?i)^(?:computername|machinename|username|user|.*serial(?:number)?|identifyingnumber|processorid|assettag|smbiosassettag|pnpdeviceid|productid|machineguid|uuid|kmsserver|keymanagementservicemachine|serveraddress|networkaddresses|mac|macaddress)$')
    if ($fullySensitiveProperty -and ($Value -is [string] -or $Value -is [ValueType])) {
        return Get-ReportText 'report.redaction.value'
    }
    if ($Depth -gt 12) { return Protect-ReportText $Value -PreserveVersionLike:$preserveVersionLike }
    if ($Value -is [string]) { return Protect-ReportText $Value -PreserveVersionLike:$preserveVersionLike }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[[string]$key] = ConvertTo-ReportRedactedObject -Value $Value[$key] -Depth ($Depth + 1) -PropertyName ([string]$key)
        }
        return [pscustomobject]$result
    }
    if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-ReportRedactedObject -Value $_ -Depth ($Depth + 1) -PropertyName $PropertyName })
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and
        $Value -isnot [ValueType] -and $Value -isnot [DateTime]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties)) {
            $result[[string]$property.Name] = ConvertTo-ReportRedactedObject -Value $property.Value -Depth ($Depth + 1) -PropertyName ([string]$property.Name)
        }
        return [pscustomobject]$result
    }
    return $Value
}

function ConvertTo-ReportLocalizedExportObject {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0
    )

    if ($null -eq $Value) { return $null }
    if ($Depth -gt 12) { return $Value }
    if ($Value -is [string]) { return Get-ReportPresentationText $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $exportKey = Get-ReportPresentationTextForCulture -Value ([string]$key) -TargetCulture "en-US"
            $result[$exportKey] = ConvertTo-ReportLocalizedExportObject -Value $Value[$key] -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-ReportLocalizedExportObject -Value $_ -Depth ($Depth + 1) })
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and
        $Value -isnot [ValueType] -and $Value -isnot [DateTime]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties)) {
            $exportKey = Get-ReportPresentationTextForCulture -Value ([string]$property.Name) -TargetCulture "en-US"
            $result[$exportKey] = ConvertTo-ReportLocalizedExportObject -Value $property.Value -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    return $Value
}

function Protect-ReportCell($row, [string]$column, $value) {
    if (-not $RedactSensitive) { return $value }
    $rowLabel = ""
    if ($row -and $row.PSObject.Properties["Muc"]) { $rowLabel = [string]$row.PSObject.Properties["Muc"].Value }
    $hardwareSensitiveColumns = @(
        (Get-ReportText 'report.hardware.column.serial'),
        (Get-ReportText 'report.hardware.column.identifier'),
        (Get-ReportText 'report.hardware.column.assetTag'),
        (Get-ReportText 'report.hardware.column.processorId')
    )
    if ($column -match '(?i)^(?:.*Serial(?:Number)?|UUID|ProcessorId|AssetTag|SMBIOSAssetTag|IdentifyingNumber|PNPDeviceID)$' -or
        $hardwareSensitiveColumns -contains $column -or
        $column -match '(?i)^(User|Nguoi dung|Author)$' -or
        ($column -eq "Gia tri" -and $rowLabel -match '(?i)^(May tinh|Nguoi dung|Windows Product ID|Serial BIOS|System UUID|System serial|Baseboard serial|Chassis serial|Asset tag|Processor ID|Domain / Workgroup|KMS server)$')) {
        return Get-ReportText "report.redaction.value"
    }
    $preserveVersionLike = [bool]($column -match '(?i)(?:phien ban|version|build|ngay cai|install date|file version|schema|sha|hash)' -or
        $column -match '(?i)^(?:name|software|product|application|title|ten phan mem)$')
    return Protect-ReportText $value -PreserveVersionLike:$preserveVersionLike
}

function Html($value, [switch]$PreserveVersionLike) {
    $safeValue = Protect-ReportText $value -PreserveVersionLike:$PreserveVersionLike
    $safeValue = Get-ReportPresentationText $safeValue
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch { return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue) }
}

function Size-GB($bytes) {
    if ($null -eq $bytes -or $bytes -eq 0) { return "" }
    return "{0:N1} GB" -f ([double]$bytes / 1GB)
}

function ConvertFrom-ReportEdidText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    try {
        return ((@($Value) | Where-Object { [int]$_ -ne 0 } | ForEach-Object { [char][int]$_ }) -join '').Trim()
    } catch { return '' }
}

function Get-ReportMonitorInventory {
    $identityRows = @(Safe-Cim WmiMonitorID root/wmi)
    $desktopRows = @(Safe-Cim Win32_DesktopMonitor)
    $pnpRows = @(Safe-Cim Win32_PnPEntity | Where-Object {
        [string]$_.PNPDeviceID -match '(?i)^DISPLAY\\' -or [string]$_.PNPClass -eq 'Monitor' -or [string]$_.Service -eq 'monitor'
    })
    $results = New-Object System.Collections.Generic.List[object]
    $matchedPnpIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($identity in $identityRows) {
        $instanceKey = ([string]$identity.InstanceName -replace '(?i)_\d+$','').Trim()
        $pnp = @($pnpRows | Where-Object {
            $pnpKey = ([string]$_.PNPDeviceID -replace '(?i)_\d+$','').Trim()
            $instanceKey -and ($pnpKey.StartsWith($instanceKey, [StringComparison]::OrdinalIgnoreCase) -or
                $instanceKey.StartsWith($pnpKey, [StringComparison]::OrdinalIgnoreCase))
        } | Select-Object -First 1)
        $desktop = @($desktopRows | Where-Object {
            $desktopKey = ([string]$_.PNPDeviceID -replace '(?i)_\d+$','').Trim()
            $instanceKey -and ($desktopKey.StartsWith($instanceKey, [StringComparison]::OrdinalIgnoreCase) -or
                $instanceKey.StartsWith($desktopKey, [StringComparison]::OrdinalIgnoreCase))
        } | Select-Object -First 1)
        $name = ConvertFrom-ReportEdidText $identity.UserFriendlyName
        $manufacturer = ConvertFrom-ReportEdidText $identity.ManufacturerName
        $productCode = ConvertFrom-ReportEdidText $identity.ProductCodeID
        if ([string]::IsNullOrWhiteSpace($name) -and $pnp.Count -gt 0) { $name = [string]$pnp[0].Name }
        if ([string]::IsNullOrWhiteSpace($name) -and $desktop.Count -gt 0) { $name = [string]$desktop[0].Name }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = (@($manufacturer,$productCode) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
        }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-ReportText 'report.hardware.monitorUnknown' }
        $pnpId = if ($pnp.Count -gt 0) { [string]$pnp[0].PNPDeviceID } elseif ($desktop.Count -gt 0) { [string]$desktop[0].PNPDeviceID } else { $instanceKey }
        if ($pnpId) { [void]$matchedPnpIds.Add($pnpId) }
        $results.Add([pscustomobject][ordered]@{
            Name=$name
            Manufacturer=$(if ($manufacturer) { $manufacturer } elseif ($pnp.Count -gt 0) { [string]$pnp[0].Manufacturer } else { '' })
            ProductCode=$productCode
            SerialNumber=(ConvertFrom-ReportEdidText $identity.SerialNumberID)
            ManufactureWeek=$(if ([int]$identity.WeekOfManufacture -gt 0) { [int]$identity.WeekOfManufacture } else { '' })
            ManufactureYear=$(if ([int]$identity.YearOfManufacture -gt 0) { [int]$identity.YearOfManufacture } else { '' })
        })
    }

    foreach ($pnp in $pnpRows) {
        $pnpId = [string]$pnp.PNPDeviceID
        if ($pnpId -and $matchedPnpIds.Contains($pnpId)) { continue }
        $name = [string]$pnp.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$pnp.Caption }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-ReportText 'report.hardware.monitorUnknown' }
        $results.Add([pscustomobject][ordered]@{
            Name=$name; Manufacturer=[string]$pnp.Manufacturer; ProductCode=''; SerialNumber=''; ManufactureWeek=''; ManufactureYear=''
        })
    }
    if ($results.Count -eq 0) {
        foreach ($desktop in $desktopRows) {
            $name = if ([string]::IsNullOrWhiteSpace([string]$desktop.Name)) { Get-ReportText 'report.hardware.monitorUnknown' } else { [string]$desktop.Name }
            $results.Add([pscustomobject][ordered]@{
                Name=$name; Manufacturer=[string]$desktop.MonitorManufacturer; ProductCode=''; SerialNumber=''; ManufactureWeek=''; ManufactureYear=''
            })
        }
    }
    return @($results.ToArray() | Group-Object { "$($_.Name)|$($_.SerialNumber)|$($_.Manufacturer)" } | ForEach-Object { $_.Group[0] })
}

function Get-ReportPropertyValue {
    param([AllowNull()][object]$InputObject, [string[]]$Names)
    if ($null -eq $InputObject) { return $null }
    foreach ($name in @($Names)) {
        $property = $InputObject.PSObject.Properties[[string]$name]
        if ($property -and $null -ne $property.Value) {
            if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$property.Value)) { continue }
            return $property.Value
        }
    }
    return $null
}

function ConvertTo-ReportHardwareTableRows {
    param(
        [AllowNull()][object[]]$Rows,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$ColumnMap
    )
    $projected = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($Rows)) {
        $result = [ordered]@{}
        foreach ($label in @($ColumnMap.Keys)) {
            $sourceName = [string]$ColumnMap[$label]
            $result[[string]$label] = Get-ReportPropertyValue $row @($sourceName)
        }
        $projected.Add([pscustomobject]$result)
    }
    return @($projected.ToArray())
}

function ConvertTo-ReportNullableBoolean {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [bool]) { return [bool]$Value }
    if ([string]$Value -match '^(?i:true|yes|enabled|on|1)$') { return $true }
    if ([string]$Value -match '^(?i:false|no|disabled|off|0)$') { return $false }
    return $null
}

function Get-ReportTpmSecurityState {
    param(
        [AllowNull()][object]$CapabilityProfile,
        [AllowNull()][scriptblock]$TpmQuery,
        [AllowNull()][scriptblock]$TpmWmiQuery
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $sources = New-Object System.Collections.Generic.List[string]
    $cmdletState = $null
    $wmiState = $null
    $cmdletAvailable = [bool](Get-Command Get-Tpm -ErrorAction SilentlyContinue)
    if (-not $TpmQuery -and $cmdletAvailable) { $TpmQuery = { Get-Tpm -ErrorAction Stop } }
    if ($TpmQuery) {
        try {
            $cmdletOutput = @(& $TpmQuery)
            $cmdletState = @($cmdletOutput | Where-Object {
                $_ -and ($_.PSObject.Properties['TpmPresent'] -or $_.PSObject.Properties['TpmReady'] -or $_.PSObject.Properties['TpmEnabled'])
            } | Select-Object -First 1)[0]
            if ($cmdletState) { $sources.Add('Get-Tpm') }
            elseif ($cmdletOutput.Count -gt 0) {
                $cmdletMessage = (@($cmdletOutput | ForEach-Object { [string]$_ } | Where-Object { $_ }) -join ' | ')
                if (-not [string]::IsNullOrWhiteSpace($cmdletMessage)) { $errors.Add($cmdletMessage) }
            }
        } catch { $errors.Add([string]$_.Exception.Message) }
    }
    if (-not $TpmWmiQuery) {
        $TpmWmiQuery = { Safe-Cim Win32_Tpm 'root/CIMV2/Security/MicrosoftTpm' -ThrowOnError }
    }
    $wmiQuerySucceeded = $false
    try {
        $wmiState = @(& $TpmWmiQuery | Select-Object -First 1)[0]
        $wmiQuerySucceeded = $true
        if ($wmiState) { $sources.Add('Win32_Tpm') }
    } catch { $errors.Add([string]$_.Exception.Message) }

    $present = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $cmdletState @('TpmPresent'))
    if ($null -eq $present) {
        if ($wmiState) { $present = $true }
        elseif ($wmiQuerySucceeded) { $present = $false }
    }
    $ready = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $cmdletState @('TpmReady'))
    if ($null -eq $ready) { $ready = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $wmiState @('IsReady_InitialValue')) }
    $enabled = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $cmdletState @('TpmEnabled'))
    if ($null -eq $enabled) { $enabled = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $wmiState @('IsEnabled_InitialValue')) }
    $activated = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $cmdletState @('TpmActivated'))
    if ($null -eq $activated) { $activated = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $wmiState @('IsActivated_InitialValue')) }

    $owned = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $cmdletState @('TpmOwned'))
    if ($null -eq $owned) { $owned = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $wmiState @('IsOwned_InitialValue')) }
    $specVersion = [string](Get-ReportPropertyValue $wmiState @('SpecVersion'))
    if ([string]::IsNullOrWhiteSpace($specVersion)) { $specVersion = [string](Get-ReportPropertyValue $cmdletState @('SpecVersion')) }
    $manufacturer = [string](Get-ReportPropertyValue $cmdletState @('ManufacturerIdTxt','ManufacturerId'))
    if ([string]::IsNullOrWhiteSpace($manufacturer)) { $manufacturer = [string](Get-ReportPropertyValue $wmiState @('ManufacturerIdTxt','ManufacturerId')) }
    $manufacturerVersion = [string](Get-ReportPropertyValue $cmdletState @('ManufacturerVersionFull20','ManufacturerVersion','ManufacturerVersionInfo'))
    if ([string]::IsNullOrWhiteSpace($manufacturerVersion)) { $manufacturerVersion = [string](Get-ReportPropertyValue $wmiState @('ManufacturerVersionFull20','ManufacturerVersion','ManufacturerVersionInfo')) }

    return [pscustomobject][ordered]@{
        Present=$present
        Ready=$ready
        Enabled=$enabled
        Activated=$activated
        Owned=$owned
        SpecVersion=$specVersion
        Manufacturer=$manufacturer
        ManufacturerVersion=$manufacturerVersion
        Source=(@($sources | Sort-Object -Unique) -join ' + ')
        Error=(@($errors | Where-Object { $_ } | Sort-Object -Unique) -join ' | ')
    }
}

function Get-ReportSecureBootSecurityState {
    param(
        [AllowNull()][scriptblock]$ConfirmQuery,
        [AllowNull()][scriptblock]$RegistryQuery
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $supported = $null
    $enabled = $null
    $source = ''
    $confirmAvailable = [bool](Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)
    if (-not $ConfirmQuery -and $confirmAvailable) { $ConfirmQuery = { Confirm-SecureBootUEFI -ErrorAction Stop } }
    if ($ConfirmQuery) {
        try {
            $enabled = ConvertTo-ReportNullableBoolean (& $ConfirmQuery)
            if ($null -ne $enabled) { $supported = $true; $source = 'Confirm-SecureBootUEFI' }
        } catch { $errors.Add([string]$_.Exception.Message) }
    }
    if ($null -eq $enabled) {
        if (-not $RegistryQuery) {
            $RegistryQuery = { Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop }
        }
        try {
            $registryState = & $RegistryQuery
            $enabled = ConvertTo-ReportNullableBoolean (Get-ReportPropertyValue $registryState @('UEFISecureBootEnabled'))
            if ($null -ne $enabled) { $supported = $true; $source = 'SecureBoot registry state' }
        } catch { $errors.Add([string]$_.Exception.Message) }
    }
    if ($null -eq $supported -and (@($errors) -join ' ') -match '(?i)(not supported|not available|unsupported|kh\u00f4ng h\u1ed7 tr\u1ee3|legacy BIOS|non-UEFI)') { $supported = $false }
    $state = if ($supported -eq $false) { 'Unsupported' } elseif ($enabled -eq $true) { 'Enabled' } elseif ($enabled -eq $false) { 'Disabled' } else { 'Unreadable' }
    return [pscustomobject][ordered]@{
        Supported=$supported
        Enabled=$enabled
        State=$state
        Source=$source
        Error=(@($errors | Where-Object { $_ } | Sort-Object -Unique) -join ' | ')
    }
}

function ConvertTo-ReportBitLockerEnum {
    param([string]$Kind, [AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $maps = @{
        Conversion=@('FullyDecrypted','FullyEncrypted','EncryptionInProgress','DecryptionInProgress','EncryptionPaused','DecryptionPaused')
        Protection=@('Off','On','Unknown')
        Lock=@('Unlocked','Locked')
        Encryption=@('None','AES_128_WITH_DIFFUSER','AES_256_WITH_DIFFUSER','AES_128','AES_256','HardwareEncryption','XTS_AES_128','XTS_AES_256')
        Protector=@('Unknown','TPM','ExternalKey','RecoveryPassword','TPMAndPIN','TPMAndStartupKey','TPMAndPINAndStartupKey','PublicKey','Passphrase','TPMCertificate','CNG')
    }
    $numeric = 0
    if ([int]::TryParse([string]$Value, [ref]$numeric) -and $maps.ContainsKey($Kind) -and $numeric -ge 0 -and $numeric -lt $maps[$Kind].Count) { return [string]$maps[$Kind][$numeric] }
    return [string]$Value
}

function Get-ReportBitLockerSecurityState {
    param(
        [AllowNull()][scriptblock]$BitLockerQuery,
        [AllowNull()][scriptblock]$EncryptableVolumeQuery,
        [AllowNull()][scriptblock]$MethodQuery,
        [AllowNull()][scriptblock]$LogicalDiskQuery
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $source = ''
    if (-not $BitLockerQuery -and (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) { $BitLockerQuery = { Get-BitLockerVolume -ErrorAction Stop } }
    if ($BitLockerQuery) {
        try {
            foreach ($volume in @(& $BitLockerQuery)) {
                $protectorTypes = @($volume.KeyProtector | ForEach-Object { [string]$_.KeyProtectorType } | Where-Object { $_ } | Sort-Object -Unique)
                $rows.Add([pscustomobject][ordered]@{
                    MountPoint=[string]$volume.MountPoint; VolumeType=[string]$volume.VolumeType
                    CapacityGB=$(if ($null -ne $volume.CapacityGB) { [Math]::Round([double]$volume.CapacityGB, 2) } else { $null })
                    EncryptionMethod=[string]$volume.EncryptionMethod; VolumeStatus=[string]$volume.VolumeStatus
                    EncryptionPercentage=$(if ($null -ne $volume.EncryptionPercentage) { [int]$volume.EncryptionPercentage } else { $null })
                    ProtectionStatus=[string]$volume.ProtectionStatus; LockStatus=[string]$volume.LockStatus
                    AutoUnlockEnabled=(ConvertTo-ReportNullableBoolean $volume.AutoUnlockEnabled)
                    AutoUnlockKeyStored=(ConvertTo-ReportNullableBoolean $volume.AutoUnlockKeyStored)
                    MetadataVersion=[string]$volume.MetadataVersion; KeyProtectorTypes=@($protectorTypes); Source='Get-BitLockerVolume'; Error=''
                })
            }
            if ($rows.Count -gt 0) { $source = 'Get-BitLockerVolume' }
        } catch { $errors.Add([string]$_.Exception.Message) }
    }
    if ($rows.Count -eq 0) {
        if (-not $EncryptableVolumeQuery) { $EncryptableVolumeQuery = { Safe-Cim Win32_EncryptableVolume 'root/CIMV2/Security/MicrosoftVolumeEncryption' -ThrowOnError } }
        if (-not $LogicalDiskQuery) { $LogicalDiskQuery = { Safe-Cim Win32_LogicalDisk 'root/cimv2' -ThrowOnError } }
        if (-not $MethodQuery) {
            $MethodQuery = {
                param($InputObject, [string]$MethodName, [hashtable]$Arguments)
                if ($InputObject -is [Microsoft.Management.Infrastructure.CimInstance] -and (Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue)) {
                    return Invoke-CimMethod -InputObject $InputObject -MethodName $MethodName -Arguments $Arguments -ErrorAction Stop
                }
                $method = $InputObject.PSObject.Methods[$MethodName]
                if (-not $method) { throw "Method unavailable: $MethodName" }
                if ($Arguments.Count -eq 0) { return $method.Invoke() }
                return $method.Invoke(@($Arguments.Values))
            }
        }
        $logicalDisks = @()
        try { $logicalDisks = @(& $LogicalDiskQuery) }
        catch { $errors.Add([string]$_.Exception.Message) }
        $encryptableVolumes = @()
        try { $encryptableVolumes = @(& $EncryptableVolumeQuery) }
        catch { $errors.Add([string]$_.Exception.Message) }
        foreach ($volume in $encryptableVolumes) {
                $conversion = $protection = $encryption = $lock = $protectors = $null
                try { $conversion = & $MethodQuery $volume 'GetConversionStatus' @{} } catch { $errors.Add([string]$_.Exception.Message) }
                try { $protection = & $MethodQuery $volume 'GetProtectionStatus' @{} } catch { $errors.Add([string]$_.Exception.Message) }
                try { $encryption = & $MethodQuery $volume 'GetEncryptionMethod' @{} } catch { $errors.Add([string]$_.Exception.Message) }
                try { $lock = & $MethodQuery $volume 'GetLockStatus' @{} } catch { $errors.Add([string]$_.Exception.Message) }
                try { $protectors = & $MethodQuery $volume 'GetKeyProtectors' @{ KeyProtectorType=0 } } catch { $errors.Add([string]$_.Exception.Message) }
                $mountPoint = [string](Get-ReportPropertyValue $volume @('DriveLetter'))
                $logical = @($logicalDisks | Where-Object { [string]$_.DeviceID -eq $mountPoint } | Select-Object -First 1)
                $protectorTypes = New-Object System.Collections.Generic.List[string]
                foreach ($protectorId in @(Get-ReportPropertyValue $protectors @('VolumeKeyProtectorID'))) {
                    try {
                        $protector = & $MethodQuery $volume 'GetKeyProtectorType' @{ VolumeKeyProtectorID=[string]$protectorId }
                        $protectorTypes.Add((ConvertTo-ReportBitLockerEnum Protector (Get-ReportPropertyValue $protector @('KeyProtectorType'))))
                    } catch { $errors.Add([string]$_.Exception.Message) }
                }
                $rows.Add([pscustomobject][ordered]@{
                    MountPoint=$mountPoint; VolumeType=''; CapacityGB=$(if ($logical.Count -gt 0 -and $logical[0].Size) { [Math]::Round([double]$logical[0].Size / 1GB, 2) } else { $null })
                    EncryptionMethod=(ConvertTo-ReportBitLockerEnum Encryption (Get-ReportPropertyValue $encryption @('EncryptionMethod')))
                    VolumeStatus=(ConvertTo-ReportBitLockerEnum Conversion (Get-ReportPropertyValue $conversion @('ConversionStatus')))
                    EncryptionPercentage=(Get-ReportPropertyValue $conversion @('EncryptionPercentage'))
                    ProtectionStatus=(ConvertTo-ReportBitLockerEnum Protection (Get-ReportPropertyValue $protection @('ProtectionStatus')))
                    LockStatus=(ConvertTo-ReportBitLockerEnum Lock (Get-ReportPropertyValue $lock @('LockStatus')))
                    AutoUnlockEnabled=$null; AutoUnlockKeyStored=$null; MetadataVersion=''; KeyProtectorTypes=@($protectorTypes | Where-Object { $_ } | Sort-Object -Unique)
                    Source='Win32_EncryptableVolume'; Error=''
                })
        }
        if ($encryptableVolumes.Count -gt 0) { $source = 'Win32_EncryptableVolume' }
    }
    $errorText = (@($errors | Where-Object { $_ } | Sort-Object -Unique) -join ' | ')
    $unsupported = [bool]($rows.Count -eq 0 -and $errorText -match '(?i)(invalid class|invalid namespace|not supported|unsupported|kh\u00f4ng h\u1ed7 tr\u1ee3)')
    return [pscustomobject][ordered]@{
        Supported=$(if ($rows.Count -gt 0) { $true } elseif ($unsupported) { $false } else { $null })
        Source=$source
        Error=$errorText
        Volumes=@($rows.ToArray())
    }
}

function Get-ReportWindowsLicenseChannel {
    param([AllowNull()][object]$License)
    if (-not $License) { return 'Unknown' }
    $description = [string]$License.Description
    if ($description -match '(?i)KMSCLIENT|VOLUME_KMS') { return 'KMS' }
    if ($description -match '(?i)VOLUME_MAK|\bMAK\b') { return 'MAK' }
    if ($description -match '(?i)RETAIL') { return 'Retail' }
    if ($description -match '(?i)OEM') { return 'OEM' }
    if ($description -match '(?i)SUBSCRIPTION') { return 'Subscription' }
    return 'Unknown'
}

function Select-ReportPrimaryWindowsLicense {
    param([AllowNull()][object[]]$Licenses)
    return @($Licenses | Sort-Object `
        @{Expression={ if ([int]$_.LicenseStatus -eq 1) { 2 } elseif ([int]$_.LicenseStatus -gt 1) { 1 } else { 0 } }; Descending=$true}, `
        @{Expression={ if ([string]$_.Name -match '(?i)Windows.*edition' -and [string]$_.Name -notmatch '(?i)add-on') { 2 } else { 0 } }; Descending=$true}, `
        @{Expression={ if ((Get-ReportWindowsLicenseChannel $_) -ne 'Unknown') { 1 } else { 0 } }; Descending=$true} |
        Select-Object -First 1)
}

function Get-ReportActivatorFamilyCode {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    if ($Text -match '(?i)\btsforge\b') { return 'TSforge' }
    if ($Text -match '(?i)\bohook\b|spp[\s._-]*hook') { return 'OHook' }
    if ($Text -match '(?i)\bmicrosoft[\s_-]+toolkit\b') { return 'MicrosoftToolkit' }
    if ($Text -match '(?i)\bmassgrave\b|\bmas[\s._-]*aio\b|get\.activated\.win') { return 'MAS' }
    if ($Text -match '(?i)kmspico|kmsauto|auto[\s._-]*kms|kms[\s._-]*vl|aact') { return 'KmsActivator' }
    if ($Text -match '(?i)hwidgen|digital[\s._-]*license[\s._-]*activation') { return 'DigitalLicenseActivator' }
    if ($Text -match '(?i)sppextcomobj') { return 'SppHook' }
    if ($Text -match '(?i)adobe[\s._-]*genp|ccmaker|amtlib') { return 'AdobeActivator' }
    if ($Text -match '(?i)xf[\s._-]*adsk|x[\s._-]*force') { return 'AutodeskActivator' }
    return 'OtherActivatorEvidence'
}

function Get-ReportActivatorArtifactFindings {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [switch]$IncludeFileSearch
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $addFinding = {
        param([string]$Source, [string]$Name, [string]$Location, [string]$Level)
        $findings.Add([pscustomobject][ordered]@{
            'Nguon'=$Source; 'Dau hieu'=$Name; 'Vi tri'=$Location; 'Muc do'=$Level
        })
    }

    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $processPath = ''
        try { $processPath = [string]$process.Path } catch {}
        if (((( [string]$process.ProcessName) + ' ' + $processPath) -match $Pattern)) {
            & $addFinding 'Process' ([string]$process.ProcessName) $processPath 'Can kiem tra'
        }
    }
    foreach ($service in @(Safe-Cim Win32_Service)) {
        $serviceText = ([string]$service.Name) + ' ' + ([string]$service.DisplayName) + ' ' + ([string]$service.PathName)
        if ($serviceText -match $Pattern) {
            & $addFinding 'Service' ([string]$service.Name) ([string]$service.PathName) 'Can kiem tra'
        }
    }
    foreach ($startupItem in @(Safe-Cim Win32_StartupCommand)) {
        $startupText = ([string]$startupItem.Name) + ' ' + ([string]$startupItem.Command) + ' ' + ([string]$startupItem.Location)
        if ($startupText -match $Pattern) {
            & $addFinding 'Startup' ([string]$startupItem.Name) ([string]$startupItem.Command) 'Can kiem tra'
        }
    }
    try {
        if ($capabilityState.ScheduledTasksModule) {
            foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                (([string]$_.TaskName) + ' ' + ([string]$_.TaskPath) + ' ' + ([string]$_.Author)) -match $Pattern
            } | Select-Object -First 80)) {
                & $addFinding 'Scheduled task' ([string]$task.TaskName) ([string]$task.TaskPath) 'Can kiem tra'
            }
        }
    } catch {}

    if ($IncludeFileSearch -and (Get-Command Find-ToolPatternFilesParallel -ErrorAction SilentlyContinue)) {
        $roots = @(
            $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA,
            [Environment]::GetFolderPath('Desktop'),
            (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'),
            $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
        foreach ($path in @(Find-ToolPatternFilesParallel -Roots $roots -Pattern $Pattern -MaximumResults 80 -ThrottleLimit 4 -MaximumDepth 4 -PerRootTimeoutSeconds 5)) {
            if (([IO.Path]::GetExtension([string]$path)).ToLowerInvariant() -notin $reportActivatorArtifactExtensions) { continue }
            & $addFinding 'File scan' ([IO.Path]::GetFileName([string]$path)) ([string]$path) 'Dau hieu theo ten file'
        }
    }
    return @($findings.ToArray() |
        Group-Object { "$($_.'Nguon')|$($_.'Dau hieu')|$($_.'Vi tri')" } |
        ForEach-Object { $_.Group[0] })
}

function Get-Sha256([string]$path) {
    try {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
        $stream = [IO.File]::OpenRead($path)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToUpperInvariant()
        } finally { $stream.Dispose() }
    } catch { return "" }
}

function Add-Section {
    param(
        [string]$Title,
        [string]$Body,
        [ValidateSet("Hardware", "Windows", "Office", "Software")]
        [string]$Category = "Hardware"
    )
    if ($script:Mode -eq "All" -or $script:Mode -eq $Category) {
        $script:sectionCounter++
        $sectionId = "section-$($script:sectionCounter)"
        $script:tocItems += [pscustomobject]@{ Id=$sectionId; Title=$Title }
        $script:sections += "<section id='$sectionId'><h2>$(Html $Title)</h2>$Body</section>"
    }
}

function Add-Table {
    param([object[]]$Rows, [string[]]$Columns)
    if (-not $Rows -or $Rows.Count -eq 0) {
        return "<p class='muted'>$(Html (Get-ReportText "report.text.001"))</p>"
    }
    if ($Columns.Count -gt 6) {
        $remainingColumnCount = $Columns.Count - 1
        $partCount = [int][Math]::Ceiling($remainingColumnCount / 5.0)
        $groupSize = [int][Math]::Ceiling($remainingColumnCount / [double]$partCount)
        $splitBuilder = New-Object Text.StringBuilder
        $partNumber = 0
        for ($offset = 1; $offset -lt $Columns.Count; $offset += $groupSize) {
            $partNumber++
            $lastIndex = [Math]::Min($Columns.Count - 1, $offset + $groupSize - 1)
            $partColumns = @($Columns[0]) + @($Columns[$offset..$lastIndex])
            [void]$splitBuilder.Append("<div class='table-split-part'><div class='table-split-label'>$partNumber / $partCount</div>")
            [void]$splitBuilder.Append((Add-Table -Rows $Rows -Columns $partColumns))
            [void]$splitBuilder.Append('</div>')
        }
        return $splitBuilder.ToString()
    }
    $profile = Get-ToolHtmlTableProfile -Columns $Columns
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append("<div class='table-wrap'><table class='$($profile.TableClass)'><colgroup>")
    foreach ($columnClass in $profile.Classes) { [void]$builder.Append("<col class='col-$columnClass'>") }
    [void]$builder.Append("</colgroup><thead><tr>")
    for ($columnIndex = 0; $columnIndex -lt $Columns.Count; $columnIndex++) {
        [void]$builder.Append("<th class='cell-$($profile.Classes[$columnIndex])'>$(Html $Columns[$columnIndex])</th>")
    }
    [void]$builder.Append("</tr></thead><tbody>")
    foreach ($row in $Rows) {
        [void]$builder.Append("<tr>")
        for ($columnIndex = 0; $columnIndex -lt $Columns.Count; $columnIndex++) {
            $col = $Columns[$columnIndex]
            $property = $row.PSObject.Properties[$col]
            $value = if ($property) { $property.Value } else { "" }
            $protectedValue = Protect-ReportCell $row $col $value
            [void]$builder.Append("<td class='cell-$($profile.Classes[$columnIndex])'>$(ConvertTo-ToolHtmlTableCell -Value $protectedValue -ColumnClass $profile.Classes[$columnIndex])</td>")
        }
        [void]$builder.Append("</tr>")
    }
    [void]$builder.Append("</tbody></table></div>")
    return $builder.ToString()
}

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2", [switch]$ThrowOnError)
    # Windows 7 thuong chi co PowerShell 2/3, chua co Get-CimInstance.
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
        } else {
            Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop
        }
    } catch {
        try { Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop }
        catch { if ($ThrowOnError) { throw }; @() }
    }
}

function Get-ExecutablePathFromMetadata {
    param(
        [AllowNull()][string[]]$Candidates,
        [AllowNull()][string]$PreferredName = ""
    )

    foreach ($candidateText in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateText)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$candidateText).Trim()
        $candidatePath = ""
        if ($expanded -match '^\s*"([^"]+?\.exe)"') {
            $candidatePath = [string]$matches[1]
        } elseif ($expanded -match '^\s*([^,]+?\.exe)(?:\s|,|$)') {
            $candidatePath = [string]$matches[1]
        }
        $candidatePath = $candidatePath.Trim().Trim('"')
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and [IO.Path]::IsPathRooted($candidatePath)) {
            try {
                $fullPath = [IO.Path]::GetFullPath($candidatePath)
                if (Test-Path -LiteralPath $fullPath -PathType Leaf) { return $fullPath }
            } catch {}
        }

        $directoryPath = $expanded.Trim('"').TrimEnd('\')
        if (-not [IO.Path]::IsPathRooted($directoryPath) -or -not (Test-Path -LiteralPath $directoryPath -PathType Container)) { continue }
        try {
            $preferredToken = ([regex]::Replace([string]$PreferredName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
            $executables = @(Get-ChildItem -LiteralPath $directoryPath -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)^(unins|uninstall|setup|update|helper|crash)' } |
                Select-Object -First 24)
            if ($executables.Count -eq 0) { continue }
            if (-not [string]::IsNullOrWhiteSpace($preferredToken)) {
                $matched = $executables | Where-Object {
                    $fileToken = ([regex]::Replace([string]$_.BaseName, '(?i)[^a-z0-9]+', '')).ToLowerInvariant()
                    $fileToken -and ($preferredToken.Contains($fileToken) -or $fileToken.Contains($preferredToken))
                } | Select-Object -First 1
                if ($matched) { return [string]$matched.FullName }
            }
            return [string]$executables[0].FullName
        } catch {}
    }
    return ""
}

function Get-SoftwareSignatureState {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{ Status="NotChecked"; Publisher=""; FileVersion=""; Path="" }
    }
    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $publisher = ""
        if ($signature.SignerCertificate) {
            $publisher = ConvertTo-ToolHtmlCompactPublisher -Value ([string]$signature.SignerCertificate.Subject)
        }
        $version = ""
        try { $version = [string](Get-Item -LiteralPath $Path -Force).VersionInfo.FileVersion } catch {}
        return [pscustomobject][ordered]@{
            Status = [string]$signature.Status
            Publisher = $publisher
            FileVersion = $version
            Path = $Path
        }
    } catch {
        return [pscustomobject][ordered]@{ Status="UnknownError"; Publisher=""; FileVersion=""; Path=$Path }
    }
}

function Get-CachedSoftwareSignatureState {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        return Get-SoftwareSignatureState -Path ""
    }
    if ($null -eq $script:softwareSignatureCache) { $script:softwareSignatureCache = @{} }
    $cacheKey = ([string]$Path).ToLowerInvariant()
    if (-not $script:softwareSignatureCache.ContainsKey($cacheKey)) {
        $script:softwareSignatureCache[$cacheKey] = Get-SoftwareSignatureState -Path $Path
    }
    return $script:softwareSignatureCache[$cacheKey]
}

function Get-SoftwareSignatureLabel {
    param([AllowNull()][string]$Status)

    switch ([string]$Status) {
        "Valid" { return Get-ReportText "report.text.002" }
        "NotSigned" { return Get-ReportText "report.text.003" }
        "HashMismatch" { return Get-ReportText "report.text.004" }
        "NotTrusted" { return Get-ReportText "report.text.005" }
        "NotSupportedFileFormat" { return Get-ReportText "report.text.006" }
        "UnknownError" { return Get-ReportText "report.text.007" }
        default { return Get-ReportText "report.text.008" }
    }
}

function Get-ReportSoftwareAssessmentLabel {
    param([string]$StatusCode)
    $key = switch ($StatusCode) {
        'FreeOrIncluded' { 'report.software.status.freeOrIncluded' }
        'GenuineVerified' { 'report.software.status.genuineVerified' }
        'Unactivated' { 'report.software.status.unactivated' }
        'NonGenuine' { 'report.software.status.nonGenuine' }
        'IntegrityCompromised' { 'report.software.status.integrityCompromised' }
        'Suspicious' { 'report.software.status.suspicious' }
        'TrialOrUnverified' { 'report.software.status.trialOrUnverified' }
        default { 'report.software.status.unverified' }
    }
    return Get-ReportText $key
}

function Get-ReportSoftwareRemediationEligibility {
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][string]$Publisher,
        [AllowNull()][string]$AssessmentCode,
        [AllowNull()][string]$Confidence,
        [AllowNull()][string]$LicenseModel,
        [AllowNull()][string]$ActivationStateProbe,
        [bool]$RemediationSupported,
        [bool]$HasRemediationEvidence,
        [bool]$StrongTechnicalEvidence
    )

    $licenseRequiresEntitlement = [bool]($LicenseModel -in @('Paid','Commercial','Subscription','Perpetual','Trial','Trialware','Mixed'))
    $isWinRar = [bool](([string]$Name + ' ' + [string]$Publisher) -match '(?i)\bWinRAR\b|\bRARLAB\b|\bwin\.rar\b')

    if ([string]$Confidence -eq 'Low') {
        return Get-ReportText 'report.software.remediationLowConfidence'
    }
    if ([string]$AssessmentCode -eq 'FreeOrIncluded' -and -not $StrongTechnicalEvidence) {
        return Get-ReportText 'report.software.remediationFreeNoAction'
    }
    if ([string]$AssessmentCode -eq 'NonGenuine') {
        if ($RemediationSupported -and $HasRemediationEvidence) {
            return Get-ReportText 'report.software.remediationNonGenuineSupported'
        }
        return Get-ReportText 'report.software.remediationNonGenuineManual'
    }
    if ([string]$AssessmentCode -eq 'Suspicious') {
        if ($HasRemediationEvidence) {
            return Get-ReportText 'report.software.remediationSuspiciousArtifact'
        }
        return Get-ReportText 'report.software.remediationSuspiciousVerify'
    }
    if ([string]$AssessmentCode -eq 'IntegrityCompromised') {
        return Get-ReportText 'report.software.remediationIntegrity'
    }

    # rarreg.key chỉ mô tả trạng thái cục bộ của WinRAR. Hướng dẫn thử dùng
    # chỉ áp dụng khi không có bằng chứng activator/can thiệp độc lập.
    if ($isWinRar -and -not $HasRemediationEvidence -and -not $StrongTechnicalEvidence) {
        if ([string]$ActivationStateProbe -in @('LocalLicenseArtifactPresent','LocalLicensePresent')) {
            return Get-ReportText 'report.software.remediationWinRarLicensePresent'
        }
        if ([string]$ActivationStateProbe -eq 'Unactivated') {
            return Get-ReportText 'report.software.remediationWinRarTrial'
        }
    }
    if ([string]$AssessmentCode -in @('Unverified','TrialOrUnverified','Unactivated')) {
        if ($licenseRequiresEntitlement) {
            return Get-ReportText 'report.software.remediationVerifyCommercial'
        }
        return Get-ReportText 'report.software.remediationNotNeeded'
    }
    if ($RemediationSupported -and $HasRemediationEvidence) {
        return Get-ReportText 'report.software.remediationSupported'
    }
    return Get-ReportText 'report.software.remediationNotNeeded'
}

function Get-ReportParallelVersionRows {
    param([AllowNull()][object[]]$Applications)

    return @(@($Applications) |
        Group-Object {
            $nameKey = (([string]$_.'Ten phan mem').Trim().ToLowerInvariant() -replace '\s+',' ')
            $catalogKey = if (-not [string]::IsNullOrWhiteSpace([string]$_.CatalogProductId)) {
                'catalog:' + ([string]$_.CatalogProductId).Trim().ToLowerInvariant()
            } else {
                'catalog:none'
            }
            # CatalogProductId có thể đại diện cả một họ ứng dụng. Ghép thêm
            # tên để Zalo/Telegram và các sản phẩm Adobe/Autodesk không nhập chung.
            $catalogKey + '|name:' + $nameKey
        } |
        ForEach-Object {
            $group = @($_.Group)
            $versions = @($group.'Phien ban' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
            $installRecords = @($group | ForEach-Object {
                $locationText = ([string]$_.'Duong dan').Trim()
                if (-not [string]::IsNullOrWhiteSpace($locationText)) {
                    $normalizedLocation = try { [IO.Path]::GetFullPath($locationText).TrimEnd('\') } catch { $locationText.TrimEnd('\') }
                    [pscustomobject]@{
                        Version = ([string]$_.'Phien ban').Trim()
                        Location = $normalizedLocation
                        Key = (([string]$_.'Phien ban').Trim().ToLowerInvariant() + '|' + $normalizedLocation.ToLowerInvariant())
                    }
                }
            })
            $locations = @($installRecords.Location | Select-Object -Unique)
            $distinctInstalls = @($installRecords.Key | Select-Object -Unique)
            if ($versions.Count -gt 1 -and $locations.Count -gt 1 -and $distinctInstalls.Count -gt 1) {
                $parallelCountColumn = Get-ReportText 'report.software.column.parallelInstallCount'
                $parallelExplanationColumn = Get-ReportText 'report.software.column.explanation'
                $parallelRow = [ordered]@{}
                $parallelRow['Ten phan mem'] = [string]$group[0].'Ten phan mem'
                $parallelRow[$parallelCountColumn] = $distinctInstalls.Count
                $parallelRow['Phiên bản'] = ($versions -join ', ')
                $parallelRow['Phạm vi'] = (@($group.'Phạm vi' | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                $parallelRow[$parallelExplanationColumn] = Get-ReportText 'report.software.parallelExplanation'
                [pscustomobject]$parallelRow
            }
        })
}

function Test-MicrosoftSoftwarePublisher {
    param([AllowNull()][string]$Publisher)
    if ([string]::IsNullOrWhiteSpace([string]$Publisher)) { return $false }
    return [bool]($Publisher -match '(?i)^\s*Microsoft(?:\s+Corporation)?\b')
}

function Find-Browser {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramW6432\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramW6432\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return ""
}

function Convert-HtmlToPdf {
    param([string]$HtmlPath, [string]$OutPath)
    $browser = Find-Browser
    if (-not $browser) {
        Write-Host (Get-ReportText "report.pdf.browserMissing")
        return $false
    }
    $htmlUri = ([System.Uri](Resolve-Path -LiteralPath $HtmlPath).Path).AbsoluteUri
    $args = @(
        "--headless",
        "--disable-gpu",
        "--no-first-run",
        "--print-to-pdf=$OutPath",
        $htmlUri
    )
    $process = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Hidden
    $process.WaitForExit(30000) | Out-Null
    return (Test-Path -LiteralPath $OutPath)
}

function License-StatusText($code) {
    switch ([int]$code) {
        0 { Get-ReportText "report.literal.2ef4b7e7e08830fa83d8e6f618177c845d5fd18b287b232d65e75d1816e2bd17" }
        1 { Get-ReportText "common.licensed" }
        2 { Get-ReportText "report.literal.ee9915f8a9441f5477ae37d0b53af5a44368d8178bcbf47a5516cba4e2f7eb90" }
        3 { Get-ReportText "report.literal.a65075fb5cef0cfe3de837b9c7f96f6df9d9108cf482d8e869b50edff0f31cc1" }
        4 { Get-ReportText "report.literal.d1900b3c9e587a3afa63930fd4132a377c45d6d096dd8188c996c79d792e6e02" }
        5 { Get-ReportText "report.literal.a9b656f50b4edb647d37c4ce076024f0b369f67f38f522a5f0099a4f8fe3b09b" }
        6 { Get-ReportText "report.literal.c9438d141f962154461744c674dad517d7e2da5a0642167708364fff3e1916a0" }
        default { "$code" }
    }
}

function Normalize-ReportKmsServer {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $candidate = $Value.Trim().ToLowerInvariant()
    $candidate = $candidate -replace '^\[([^\]]+)\](?::\d+)?$', '$1'
    $candidate = $candidate -replace '^([^:]+):\d+$', '$1'
    return $candidate
}

function Get-ReportApprovedKmsServers {
    $path = [string]$ApprovedKmsServerFile
    if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$env:TOOL_APPROVED_KMS_FILE }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Configured=$false; Entries=@(); Path=$path }
    }
    $entries = @(
        Get-Content -LiteralPath $path -ErrorAction SilentlyContinue |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { Normalize-ReportKmsServer $_ } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    return [pscustomobject]@{ Configured=$true; Entries=$entries; Path=$path }
}

function Test-ReportKmsServerApproved {
    param(
        [AllowNull()][string]$Server,
        [AllowNull()][object]$ApprovedState
    )
    $normalized = Normalize-ReportKmsServer $Server
    if (-not $normalized -or -not $ApprovedState -or -not [bool]$ApprovedState.Configured) { return $false }
    return [bool](@($ApprovedState.Entries) -contains $normalized)
}

function New-ReportLicenseVerdict {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$ConclusionKey,
        [Parameter(Mandatory = $true)][string]$LevelKey,
        [Parameter(Mandatory = $true)][ValidateSet('ok','warning','danger','info')][string]$Tone,
        [Parameter(Mandatory = $true)][string]$DirectionKey
    )
    return [pscustomobject][ordered]@{
        Code = $Code
        Conclusion = Get-ReportText $ConclusionKey
        VerificationLevel = Get-ReportText $LevelKey
        Tone = $Tone
        Direction = Get-ReportText $DirectionKey
    }
}

function Get-WindowsLicenseVerdict {
    param(
        [bool]$Requested,
        [AllowNull()][object]$ActiveLicense,
        [AllowNull()][object[]]$Licenses,
        [AllowNull()][string]$ActivationOutput,
        [int]$SlmgrExitCode,
        [AllowNull()][object]$ApprovedKmsState
    )
    if (-not $Requested) {
        return New-ReportLicenseVerdict 'NotScanned' 'report.license.notScanned' 'report.license.level.notScanned' 'info' 'report.license.direction.notScanned'
    }
    $licenseList = @($Licenses)
    $activationSearchText = ConvertTo-ToolHtmlSearchKey -Value $ActivationOutput
    $licensingError = $SlmgrExitCode -ne 0 -or $activationSearchText -match '(?i)0xC004|error|loi'
    if (-not $ActiveLicense) {
        if ($licenseList.Count -eq 0 -or $licensingError) {
            return New-ReportLicenseVerdict 'Unverifiable' 'report.license.windows.unverifiable' 'report.license.level.undetermined' 'warning' 'report.license.direction.unverifiable'
        }
        return New-ReportLicenseVerdict 'NotLicensed' 'report.license.windows.notLicensed' 'report.license.level.high' 'danger' 'report.license.direction.windowsLicense'
    }

    $isKms = [string]$ActiveLicense.Description -match 'KMSCLIENT|VOLUME_KMS'
    if ($isKms) {
        $kmsServer = [string]$ActiveLicense.KeyManagementServiceMachine
        if (Test-ReportKmsServerApproved -Server $kmsServer -ApprovedState $ApprovedKmsState) {
            return New-ReportLicenseVerdict 'KmsApprovedHost' 'report.license.windows.kmsApproved' 'report.license.level.review' 'warning' 'report.license.direction.kmsRecords'
        }
        if (-not [string]::IsNullOrWhiteSpace($kmsServer) -and [bool]$ApprovedKmsState.Configured) {
            return New-ReportLicenseVerdict 'KmsUnapprovedHost' 'report.license.windows.kmsUnapproved' 'report.license.level.high' 'danger' 'report.license.direction.kmsUnapproved'
        }
        return New-ReportLicenseVerdict 'KmsEntitlementUnverified' 'report.license.windows.kmsUnverified' 'report.license.level.high' 'danger' 'report.license.direction.kmsRecords'
    }
    return New-ReportLicenseVerdict 'ActivatedEntitlementUnverified' 'report.license.windows.activatedUnverified' 'report.license.level.review' 'warning' 'report.license.direction.windowsRecords'
}

function Get-OfficeLicenseVerdict {
    param(
        [bool]$Requested,
        [bool]$Detected,
        [bool]$Activated,
        [AllowNull()][object]$ActiveLicense,
        [AllowNull()][string]$RawStatus,
        [AllowNull()][object]$ApprovedKmsState
    )
    if (-not $Requested) {
        return New-ReportLicenseVerdict 'NotScanned' 'report.license.notScanned' 'report.license.level.notScanned' 'info' 'report.license.direction.notScanned'
    }
    if (-not $Detected) {
        return New-ReportLicenseVerdict 'NotDetected' 'report.license.office.notDetected' 'report.license.level.notScanned' 'info' 'report.license.direction.officeNotDetected'
    }
    if (-not $Activated) {
        if ([string]::IsNullOrWhiteSpace($RawStatus) -and -not $ActiveLicense) {
            return New-ReportLicenseVerdict 'Unverifiable' 'report.license.office.unverifiable' 'report.license.level.undetermined' 'warning' 'report.license.direction.unverifiable'
        }
        return New-ReportLicenseVerdict 'NotLicensed' 'report.license.office.notLicensed' 'report.license.level.high' 'danger' 'report.license.direction.officeLicense'
    }

    $description = if ($ActiveLicense) { [string]$ActiveLicense.Description } else { [string]$RawStatus }
    $isKms = $description -match '(?i)KMSCLIENT|VOLUME_KMS|KMS'
    if ($isKms) {
        $kmsServer = if ($ActiveLicense) { [string]$ActiveLicense.KeyManagementServiceMachine } else { '' }
        if (Test-ReportKmsServerApproved -Server $kmsServer -ApprovedState $ApprovedKmsState) {
            return New-ReportLicenseVerdict 'KmsApprovedHost' 'report.license.office.kmsApproved' 'report.license.level.review' 'warning' 'report.license.direction.kmsRecords'
        }
        if (-not [string]::IsNullOrWhiteSpace($kmsServer) -and [bool]$ApprovedKmsState.Configured) {
            return New-ReportLicenseVerdict 'KmsUnapprovedHost' 'report.license.office.kmsUnapproved' 'report.license.level.high' 'danger' 'report.license.direction.kmsUnapproved'
        }
        return New-ReportLicenseVerdict 'KmsEntitlementUnverified' 'report.license.office.kmsUnverified' 'report.license.level.high' 'danger' 'report.license.direction.kmsRecords'
    }
    return New-ReportLicenseVerdict 'ActivatedEntitlementUnverified' 'report.license.office.activatedUnverified' 'report.license.level.review' 'warning' 'report.license.direction.officeRecords'
}

$sections = @()
$tocItems = @()
$sectionCounter = 0
$os = Safe-Cim Win32_OperatingSystem | Select-Object -First 1
$cs = Safe-Cim Win32_ComputerSystem | Select-Object -First 1
$biosSourceRows = @(Safe-Cim Win32_BIOS)
$processorSourceRows = @(Safe-Cim Win32_Processor)
$baseboardSourceRows = @(Safe-Cim Win32_BaseBoard)
$systemProductSourceRows = @()
$enclosureSourceRows = @()
if ($wantHardware) {
    $systemProductSourceRows = @(Safe-Cim Win32_ComputerSystemProduct)
    $enclosureSourceRows = @(Safe-Cim Win32_SystemEnclosure)
}
$bios = $biosSourceRows | Select-Object -First 1
$cpu = $processorSourceRows | Select-Object -First 1
$board = $baseboardSourceRows | Select-Object -First 1
$systemProduct = $systemProductSourceRows | Select-Object -First 1
$enclosure = $enclosureSourceRows | Select-Object -First 1

$uptime = ""
if ($os.LastBootUpTime) {
    $span = (Get-Date) - $os.LastBootUpTime
    $uptime = "{0} ngay {1} gio {2} phut" -f [int]$span.TotalDays, $span.Hours, $span.Minutes
}

$summary = @(
    [pscustomobject]@{ "Muc"="May tinh"; "Gia tri"=$computer },
    [pscustomobject]@{ "Muc"="Nguoi dung"; "Gia tri"=$env:USERNAME },
    [pscustomobject]@{ "Muc"="Ngay kiem tra"; "Gia tri"=$started.ToString("yyyy-MM-dd HH:mm:ss") },
    [pscustomobject]@{ "Muc"="He dieu hanh"; "Gia tri"="$($os.Caption) $($os.Version) build $($os.BuildNumber)" },
    [pscustomobject]@{ "Muc"="Kien truc"; "Gia tri"=$os.OSArchitecture },
    [pscustomobject]@{ "Muc"="Windows Product ID"; "Gia tri"=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductId },
    [pscustomobject]@{ "Muc"="Ngay cai Windows"; "Gia tri"=(ConvertTo-ToolSoftwareInstallDateText -Value $os.InstallDate) },
    [pscustomobject]@{ "Muc"="Lan khoi dong cuoi"; "Gia tri"=$(if ($os.LastBootUpTime) { ([DateTime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }) },
    [pscustomobject]@{ "Muc"="Uptime"; "Gia tri"=$uptime },
    [pscustomobject]@{ "Muc"="Hang / Model"; "Gia tri"="$($cs.Manufacturer) $($cs.Model)" },
    [pscustomobject]@{ "Muc"="Domain / Workgroup"; "Gia tri"=$cs.Domain },
    [pscustomobject]@{ "Muc"="System type"; "Gia tri"=$cs.SystemType },
    [pscustomobject]@{ "Muc"="Serial BIOS"; "Gia tri"=$bios.SerialNumber },
    [pscustomobject]@{ "Muc"="BIOS"; "Gia tri"="$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) $($bios.ReleaseDate)" },
    [pscustomobject]@{ "Muc"="Mainboard"; "Gia tri"="$($board.Manufacturer) $($board.Product)" },
    [pscustomobject]@{ "Muc"="CPU"; "Gia tri"=$cpu.Name },
    [pscustomobject]@{ "Muc"="RAM"; "Gia tri"=(Size-GB $cs.TotalPhysicalMemory) }
)
if ($wantHardware) {
    $summary += @(
        [pscustomobject]@{ "Muc"="System UUID"; "Gia tri"=$systemProduct.UUID },
        [pscustomobject]@{ "Muc"="System serial"; "Gia tri"=$systemProduct.IdentifyingNumber },
        [pscustomobject]@{ "Muc"="Baseboard serial"; "Gia tri"=$board.SerialNumber },
        [pscustomobject]@{ "Muc"="Chassis serial"; "Gia tri"=$enclosure.SerialNumber },
        [pscustomobject]@{ "Muc"="Asset tag"; "Gia tri"=$enclosure.SMBIOSAssetTag },
        [pscustomobject]@{ "Muc"="Processor ID"; "Gia tri"=$cpu.ProcessorId }
    )
}
Add-Section "Tổng quan" (Add-Table $summary @("Muc","Gia tri"))

$capabilityRows = @(
    [pscustomobject]@{ "Thành phần"=(Get-ReportText "report.capability.moduleContract"); "Trạng thái"="schema $($moduleContractState.ContractSchemaVersion)"; "Phương án"="$reportModuleId / $($moduleAvailability.Descriptor.AccessMode)" },
    [pscustomobject]@{ "Thành phần"="Windows release"; "Trạng thái"="$($capabilityState.WindowsReleaseName) build $($capabilityState.FullBuildNumber)"; "Phương án"=(Get-ReportText "report.capability.catalogLifecycle" @($compatibilityState.CatalogVersion, $compatibilityState.CatalogHealth, $compatibilityState.CatalogAgeDays, $compatibilityState.MaximumReviewAgeDays, $capabilityState.WindowsServicingState)) },
    [pscustomobject]@{ "Thành phần"="Office compatibility"; "Trạng thái"=$capabilityState.OfficeSummary; "Phương án"=if ($capabilityState.OfficeCompatibility -and $capabilityState.OfficeCompatibility.Detected) { "$($capabilityState.OfficeCompatibility.Version) · $($capabilityState.OfficeCompatibility.Channel) · $($capabilityState.OfficeCompatibility.Currency)" } else { Get-ReportText "report.capability.clickToRunMissing" } },
    [pscustomobject]@{ "Thành phần"="Offline policy"; "Trạng thái"=if ($script:reportOfflineMode) { "Offline" } else { "Network allowed" }; "Phương án"=(Get-ReportText "report.capability.offlineNote") },
    [pscustomobject]@{ "Thành phần"=(Get-ReportText "report.capability.compatibilityLevel"); "Trạng thái"=$capabilityState.CompatibilityTier; "Phương án"=(Get-ReportText "report.capability.adaptive") },
    [pscustomobject]@{ "Thành phần"="CIM"; "Trạng thái"=[bool]$capabilityState.CimCmdlets; "Phương án"=if ($capabilityState.CimCmdlets) { Get-ReportText "report.capability.preferCim" } elseif ($capabilityState.WmiFallback) { Get-ReportText "report.capability.wmiFallback" } else { Get-ReportText "report.capability.managementUnavailable" } },
    [pscustomobject]@{ "Thành phần"="Scheduled Tasks"; "Trạng thái"=[bool]$capabilityState.ScheduledTasksModule; "Phương án"=if ($capabilityState.ScheduledTasksModule) { "ScheduledTasks module" } elseif ($capabilityState.ScheduledTasksFallback) { "schtasks.exe fallback" } else { "Không khả dụng" } },
    [pscustomobject]@{ "Thành phần"="Microsoft Defender cmdlets"; "Trạng thái"=[bool]$capabilityState.DefenderCmdlets; "Phương án"=if ($capabilityState.DefenderCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } },
    [pscustomobject]@{ "Thành phần"="TPM cmdlets"; "Trạng thái"=[bool]$capabilityState.TpmCmdlets; "Phương án"=if ($capabilityState.TpmCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } },
    [pscustomobject]@{ "Thành phần"="BitLocker cmdlets"; "Trạng thái"=[bool]$capabilityState.BitLockerCmdlets; "Phương án"=if ($capabilityState.BitLockerCmdlets) { "Có thể truy vấn" } else { "Ẩn/ghi không hỗ trợ" } }
)
Add-Section "Khả năng tương thích hệ thống" (Add-Table $capabilityRows @("Thành phần","Trạng thái","Phương án"))

$activationText = ""
$slmgrExitCode = -1
$licenseRows = @()
$windowsLicenses = @()
$windowsLicenseBody = ""
if ($wantWindows) {
try {
    $slmgr = & $nativeCscriptPath //nologo (Get-ToolNativeSystemPath "slmgr.vbs") /xpr 2>&1
    $slmgrExitCode = [int]$LASTEXITCODE
    $activationText = ($slmgr -join "`n").Trim()
} catch { $activationText = $_.Exception.Message }
$licenseRows = @(
    [pscustomobject]@{ "Muc"="Trang thai kich hoat Windows"; "Gia tri"=$activationText }
)
$windowsLicenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Windows" -and
    (-not $_.ApplicationID -or [string]$_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f')
} | Sort-Object LicenseStatus -Descending
foreach ($license in $windowsLicenses) {
    $method = "Khong xac dinh"
    if ($license.Description -match "KMSCLIENT|VOLUME_KMS") {
        $method = "KMS client / kich hoat qua KMS"
    } elseif ($license.Description -match "VOLUME_MAK|MAK") {
        $method = "Volume MAK"
    } elseif ($license.Description -match "RETAIL") {
        $method = "Retail"
    } elseif ($license.Description -match "OEM") {
        $method = "OEM"
    }
    $licenseRows += [pscustomobject]@{ "Muc"="Windows edition"; "Gia tri"=$license.Name }
    $licenseRows += [pscustomobject]@{ "Muc"="Mo ta / kenh key"; "Gia tri"=$license.Description }
    $licenseRows += [pscustomobject]@{ "Muc"="Phuong thuc kich hoat so bo"; "Gia tri"=$method }
    $licenseRows += [pscustomobject]@{ "Muc"="Trang thai license"; "Gia tri"=(License-StatusText $license.LicenseStatus) }
    $licenseRows += [pscustomobject]@{ "Muc"="Partial product key"; "Gia tri"=$license.PartialProductKey }
    if ($license.KeyManagementServiceMachine) {
        $licenseRows += [pscustomobject]@{ "Muc"="KMS server"; "Gia tri"=$license.KeyManagementServiceMachine }
    }
    if ($license.KeyManagementServicePort) {
        $licenseRows += [pscustomobject]@{ "Muc"="KMS port"; "Gia tri"=$license.KeyManagementServicePort }
    }
    if ((Get-ReportWindowsLicenseChannel $license) -eq 'KMS' -and $license.PSObject.Properties['GracePeriodRemaining']) {
        $graceMinutes = [int]$license.GracePeriodRemaining
        $graceDays = [Math]::Round($graceMinutes / 1440.0, 1)
        $graceExpiry = (Get-Date).AddMinutes($graceMinutes).ToString('yyyy-MM-dd HH:mm')
        $licenseRows += [pscustomobject]@{
            "Muc"=(Get-ReportText 'report.license.windows.kmsValidity')
            "Gia tri"=(Get-ReportText 'report.license.windows.kmsValidityValue' @($graceMinutes, $graceDays, $graceExpiry))
        }
    }
}
$windowsLicenseBody = Add-Table $licenseRows @("Muc","Gia tri")
}

$officeRows = @()
$officeRawStatus = @()
$officeCimLicenses = @()
$clickToRun = $null
if ($wantOffice) {
$osppPaths = @(Get-ToolOptimizedOfficeOsppPaths)
$officeStatusResults = @(Invoke-ToolParallelOfficeStatus -CscriptPath $nativeCscriptPath -OsppPaths $osppPaths)
foreach ($statusResult in $officeStatusResults) {
    if (-not $statusResult.Readable) { continue }
    $status = @([string]$statusResult.Output -split "`r?`n")
    $officeRawStatus += $status
    $officeRows += [pscustomobject]@{
        "Thanh phan"="Microsoft Office"
        "Thong tin"=(($status | Where-Object { $_ -match "LICENSE|PRODUCT ID|LICENSE DESCRIPTION|Last 5|KMS|ERROR" }) -join "`n")
        "Nguon"=[string]$statusResult.Path
    }
}

$clickToRun = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
if (-not $clickToRun) {
    $clickToRun = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
}
if ($clickToRun) {
    $officeRows += [pscustomobject]@{
        "Thanh phan"="Office Click-to-Run"
        "Thong tin"="San pham: $($clickToRun.ProductReleaseIds)`nDong san pham: $($capabilityState.OfficeCompatibility.Family)`nPhien ban: $($clickToRun.ClientVersionToReport)`nKenh: $($capabilityState.OfficeCompatibility.Channel)`nDoi chieu catalog: $($capabilityState.OfficeCompatibility.Currency)`nNen tang: $($clickToRun.Platform)"
        "Nguon"="Office ClickToRun Configuration + compatibility catalog"
    }
}

$officeCimLicenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Office"
} | Sort-Object LicenseStatus -Descending
foreach ($license in $officeCimLicenses) {
    $officeRows += [pscustomobject]@{
        "Thanh phan"=$license.Name
        "Thong tin"="Trang thai: $(License-StatusText $license.LicenseStatus)`nMo ta: $($license.Description)`nPartial key: $($license.PartialProductKey)"
        "Nguon"="SoftwareLicensingProduct"
    }
}
}

$activeWindowsLicense = Select-ReportPrimaryWindowsLicense -Licenses @($windowsLicenses | Where-Object { $_.LicenseStatus -eq 1 })
$primaryWindowsLicense = if ($activeWindowsLicense) { $activeWindowsLicense } else { Select-ReportPrimaryWindowsLicense -Licenses $windowsLicenses }
$windowsActivated = [bool]($null -ne $activeWindowsLicense)
$windowsSummaryStatus = if ($activeWindowsLicense) {
    Get-ReportText "report.literal.469ed875460f4d9aac099f3638c114fd1f306336432eef0686c2d2798425b200"
} elseif ($windowsLicenses) {
    Get-ReportText "report.literal.b416005dc249c9d2aed359bdd8e40760a9da0684a10a8b63c3acb1e181974481"
} else {
    Get-ReportText "report.literal.7328f6ec44c8cb946163ebcdea81773122962b30acc45ac7b4d0c112ad9d7f96"
}
$windowsSummaryChannel = if ($primaryWindowsLicense) {
    switch (Get-ReportWindowsLicenseChannel $primaryWindowsLicense) {
        'KMS' { 'KMS client / Volume KMS' }
        'MAK' { 'Volume MAK' }
        'Retail' { 'Retail' }
        'OEM' { 'OEM' }
        'Subscription' { 'Subscription' }
        default { [string]$primaryWindowsLicense.Description }
    }
} else {
    "Khong xac dinh"
}

$officeStatusText = ($officeRawStatus -join "`n")
$activeOfficeLicense = $officeCimLicenses | Where-Object { $_.LicenseStatus -eq 1 } | Select-Object -First 1
$officeDetected = ($officeRows.Count -gt 0)
$officeActivated = [bool]($activeOfficeLicense -or $officeStatusText -match "LICENSE STATUS:\s+---LICENSED---")
$officeSummaryStatus = if ($officeActivated) {
    Get-ReportText "report.literal.469ed875460f4d9aac099f3638c114fd1f306336432eef0686c2d2798425b200"
} elseif ($officeStatusText -match "LICENSE STATUS" -or $officeCimLicenses) {
    Get-ReportText "report.literal.a34540e5d56b9b931d3c2d2aba6dbb8a50409473067cb68f40299bcd160db6b1"
} elseif ($officeDetected) {
    Get-ReportText "report.literal.e1570579d8c5ea326f7eb4f27c2946e8f39da617887672e85ae3121a2492d5b5"
} else {
    Get-ReportText "report.literal.1354cb33be9c44fa682e988efee9a1b96d77d89fd4f4255fa6cf6f48dcea41ff"
}

$approvedKmsState = Get-ReportApprovedKmsServers
$windowsVerdict = Get-WindowsLicenseVerdict -Requested $wantWindows -ActiveLicense $activeWindowsLicense -Licenses $windowsLicenses -ActivationOutput $activationText -SlmgrExitCode $slmgrExitCode -ApprovedKmsState $approvedKmsState
$officeVerdict = Get-OfficeLicenseVerdict -Requested $wantOffice -Detected $officeDetected -Activated $officeActivated -ActiveLicense $activeOfficeLicense -RawStatus $officeStatusText -ApprovedKmsState $approvedKmsState

$licenseOverviewRows = @(
    [pscustomobject]@{ "San pham"="Windows"; "Trang thai kich hoat"=$windowsSummaryStatus; "Ket luan ky thuat"=$windowsVerdict.Conclusion; "Muc xac minh"=$windowsVerdict.VerificationLevel; "Kenh / thong tin"=$windowsSummaryChannel },
    [pscustomobject]@{ "San pham"="Microsoft Office"; "Trang thai kich hoat"=$officeSummaryStatus; "Ket luan ky thuat"=$officeVerdict.Conclusion; "Muc xac minh"=$officeVerdict.VerificationLevel; "Kenh / thong tin"=if ($activeOfficeLicense) { $activeOfficeLicense.Description } elseif ($clickToRun) { $clickToRun.ProductReleaseIds } else { "Khong xac dinh" } }
)
$licenseOverviewNote = Get-ReportText "report.text.009"
$windowsOverviewNote = Get-ReportText "report.text.010"
$officeOverviewNote = Get-ReportText "report.text.011"
$noteLabel = Get-ReportText "report.text.012"
$licenseOverviewColumns = @("San pham","Trang thai kich hoat","Ket luan ky thuat","Muc xac minh","Kenh / thong tin")
$licenseOverviewBody = (Add-Table $licenseOverviewRows $licenseOverviewColumns) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $licenseOverviewNote)</p>"
$windowsOverviewBody = (Add-Table @($licenseOverviewRows | Where-Object { $_."San pham" -eq "Windows" }) $licenseOverviewColumns) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $windowsOverviewNote)</p>"
$officeOverviewBody = (Add-Table @($licenseOverviewRows | Where-Object { $_."San pham" -eq "Microsoft Office" }) $licenseOverviewColumns) + "<p class='license-warning'><strong>$(Html $noteLabel)</strong> $(Html $officeOverviewNote)</p>"

Add-Section "Tổng quan bản quyền Windows" $windowsOverviewBody "Windows"
Add-Section "Chi tiết kích hoạt Windows" $windowsLicenseBody "Windows"
Add-Section "Tổng quan bản quyền Microsoft Office" $officeOverviewBody "Office"
Add-Section "Chi tiết giấy phép Microsoft Office" (Add-Table $officeRows @("Thanh phan","Thong tin","Nguon")) "Office"

if ($wantHardware) {
$systemProducts = @($systemProductSourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        Vendor=[string]$_.Vendor; Name=[string]$_.Name; Version=[string]$_.Version
        SystemSerialNumber=[string]$_.IdentifyingNumber; UUID=[string]$_.UUID; SKUNumber=[string]$_.SKUNumber
    }
})
$biosInventory = @($biosSourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        Manufacturer=[string]$_.Manufacturer; Name=[string]$_.Name; SMBIOSBIOSVersion=[string]$_.SMBIOSBIOSVersion
        Version=[string]$_.Version; ReleaseDate=$_.ReleaseDate; SerialNumber=[string]$_.SerialNumber
        SMBIOSMajorVersion=$_.SMBIOSMajorVersion; SMBIOSMinorVersion=$_.SMBIOSMinorVersion; Status=[string]$_.Status
    }
})
$baseboards = @($baseboardSourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        Manufacturer=[string]$_.Manufacturer; Product=[string]$_.Product; Model=[string]$_.Model; Version=[string]$_.Version
        BaseboardSerialNumber=[string]$_.SerialNumber; PartNumber=[string]$_.PartNumber; SKU=[string]$_.SKU; Status=[string]$_.Status
    }
})
$enclosures = @($enclosureSourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        Manufacturer=[string]$_.Manufacturer; Model=[string]$_.Model; Version=[string]$_.Version
        ChassisSerialNumber=[string]$_.SerialNumber; SMBIOSAssetTag=[string]$_.SMBIOSAssetTag
        PartNumber=[string]$_.PartNumber; SKU=[string]$_.SKU; ChassisTypes=(@($_.ChassisTypes) -join ', '); Status=[string]$_.Status
    }
})
$processors = @($processorSourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        DeviceID=[string]$_.DeviceID; SocketDesignation=[string]$_.SocketDesignation; Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer
        ProcessorId=[string]$_.ProcessorId; ProcessorSerialNumber=[string]$_.SerialNumber; PartNumber=[string]$_.PartNumber; AssetTag=[string]$_.AssetTag
        NumberOfCores=$_.NumberOfCores; NumberOfEnabledCores=$_.NumberOfEnabledCore; NumberOfLogicalProcessors=$_.NumberOfLogicalProcessors
        CurrentClockSpeedMHz=$_.CurrentClockSpeed; MaxClockSpeedMHz=$_.MaxClockSpeed; Architecture=$_.Architecture; Status=[string]$_.Status
    }
})

$systemProductColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.vendor')='Vendor'; (Get-ReportText 'report.hardware.column.name')='Name'
    (Get-ReportText 'report.hardware.column.version')='Version'; (Get-ReportText 'report.hardware.column.serial')='SystemSerialNumber'
    (Get-ReportText 'report.hardware.column.uuid')='UUID'; (Get-ReportText 'report.hardware.column.sku')='SKUNumber'
}
Add-Section (Get-ReportText 'report.hardware.section.systemProduct') (Add-Table (ConvertTo-ReportHardwareTableRows $systemProducts $systemProductColumns) @($systemProductColumns.Keys))
$biosColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'; (Get-ReportText 'report.hardware.column.name')='Name'
    (Get-ReportText 'report.hardware.column.biosVersion')='SMBIOSBIOSVersion'; (Get-ReportText 'report.hardware.column.version')='Version'
    (Get-ReportText 'report.hardware.column.releaseDate')='ReleaseDate'; (Get-ReportText 'report.hardware.column.serial')='SerialNumber'
    (Get-ReportText 'report.hardware.column.status')='Status'
}
Add-Section (Get-ReportText 'report.hardware.section.bios') (Add-Table (ConvertTo-ReportHardwareTableRows $biosInventory $biosColumns) @($biosColumns.Keys))
$baseboardColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'; (Get-ReportText 'report.hardware.column.product')='Product'
    (Get-ReportText 'report.hardware.column.model')='Model'; (Get-ReportText 'report.hardware.column.version')='Version'
    (Get-ReportText 'report.hardware.column.serial')='BaseboardSerialNumber'; (Get-ReportText 'report.hardware.column.partNumber')='PartNumber'
    (Get-ReportText 'report.hardware.column.sku')='SKU'; (Get-ReportText 'report.hardware.column.status')='Status'
}
Add-Section (Get-ReportText 'report.hardware.section.baseboard') (Add-Table (ConvertTo-ReportHardwareTableRows $baseboards $baseboardColumns) @($baseboardColumns.Keys))
$chassisColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'; (Get-ReportText 'report.hardware.column.model')='Model'
    (Get-ReportText 'report.hardware.column.version')='Version'; (Get-ReportText 'report.hardware.column.serial')='ChassisSerialNumber'
    (Get-ReportText 'report.hardware.column.assetTag')='SMBIOSAssetTag'; (Get-ReportText 'report.hardware.column.partNumber')='PartNumber'
    (Get-ReportText 'report.hardware.column.chassisTypes')='ChassisTypes'; (Get-ReportText 'report.hardware.column.status')='Status'
}
Add-Section (Get-ReportText 'report.hardware.section.chassis') (Add-Table (ConvertTo-ReportHardwareTableRows $enclosures $chassisColumns) @($chassisColumns.Keys))
$processorColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.deviceId')='DeviceID'; (Get-ReportText 'report.hardware.column.socket')='SocketDesignation'
    (Get-ReportText 'report.hardware.column.name')='Name'; (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'
    (Get-ReportText 'report.hardware.column.processorId')='ProcessorId'; (Get-ReportText 'report.hardware.column.serial')='ProcessorSerialNumber'
    (Get-ReportText 'report.hardware.column.cores')='NumberOfCores'; (Get-ReportText 'report.hardware.column.logicalProcessors')='NumberOfLogicalProcessors'
    (Get-ReportText 'report.hardware.column.currentClockMHz')='CurrentClockSpeedMHz'; (Get-ReportText 'report.hardware.column.maxClockMHz')='MaxClockSpeedMHz'
    (Get-ReportText 'report.hardware.column.status')='Status'
}
Add-Section (Get-ReportText 'report.hardware.section.processors') (Add-Table (ConvertTo-ReportHardwareTableRows $processors $processorColumns) @($processorColumns.Keys))

$tpmState = Get-ReportTpmSecurityState -CapabilityProfile $capabilityState
$secureBootState = Get-ReportSecureBootSecurityState
$bitLockerState = Get-ReportBitLockerSecurityState
$platformRows = @(
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmPresent'); "Gia tri"=$tpmState.Present },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmReady'); "Gia tri"=$tpmState.Ready },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmEnabled'); "Gia tri"=$tpmState.Enabled },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmActivated'); "Gia tri"=$tpmState.Activated },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmOwned'); "Gia tri"=$tpmState.Owned },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmSpecVersion'); "Gia tri"=$tpmState.SpecVersion },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmManufacturer'); "Gia tri"=$tpmState.Manufacturer },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmManufacturerVersion'); "Gia tri"=$tpmState.ManufacturerVersion },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmSource'); "Gia tri"=$tpmState.Source },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.secureBootState'); "Gia tri"=$secureBootState.State },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.secureBootSupported'); "Gia tri"=$secureBootState.Supported },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.secureBootEnabled'); "Gia tri"=$secureBootState.Enabled },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.secureBootSource'); "Gia tri"=$secureBootState.Source },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.bitLockerSupported'); "Gia tri"=$bitLockerState.Supported },
    [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.bitLockerSource'); "Gia tri"=$bitLockerState.Source }
)
if (-not [string]::IsNullOrWhiteSpace([string]$tpmState.Error)) { $platformRows += [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.tpmError'); "Gia tri"=$tpmState.Error } }
if (-not [string]::IsNullOrWhiteSpace([string]$secureBootState.Error)) { $platformRows += [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.secureBootError'); "Gia tri"=$secureBootState.Error } }
if (-not [string]::IsNullOrWhiteSpace([string]$bitLockerState.Error)) { $platformRows += [pscustomobject]@{ "Muc"=(Get-ReportText 'report.hardware.state.bitLockerError'); "Gia tri"=$bitLockerState.Error } }
Add-Section (Get-ReportText 'report.hardware.section.platformSecurity') (Add-Table $platformRows @("Muc","Gia tri"))

$bitLockerDisplayRows = @($bitLockerState.Volumes | ForEach-Object {
    [pscustomobject][ordered]@{
        MountPoint=$_.MountPoint; VolumeType=$_.VolumeType; CapacityGB=$_.CapacityGB; EncryptionMethod=$_.EncryptionMethod
        VolumeStatus=$_.VolumeStatus; EncryptionPercentage=$_.EncryptionPercentage; ProtectionStatus=$_.ProtectionStatus
        LockStatus=$_.LockStatus; AutoUnlockEnabled=$_.AutoUnlockEnabled; AutoUnlockKeyStored=$_.AutoUnlockKeyStored
        MetadataVersion=$_.MetadataVersion; KeyProtectorTypes=(@($_.KeyProtectorTypes) -join ', '); Source=$_.Source; Error=$_.Error
    }
})
$bitLockerColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.mountPoint')='MountPoint'; (Get-ReportText 'report.hardware.column.volumeType')='VolumeType'
    (Get-ReportText 'report.hardware.column.capacityGB')='CapacityGB'; (Get-ReportText 'report.hardware.column.encryptionMethod')='EncryptionMethod'
    (Get-ReportText 'report.hardware.column.volumeStatus')='VolumeStatus'; (Get-ReportText 'report.hardware.column.encryptionPercentage')='EncryptionPercentage'
    (Get-ReportText 'report.hardware.column.protectionStatus')='ProtectionStatus'; (Get-ReportText 'report.hardware.column.lockStatus')='LockStatus'
    (Get-ReportText 'report.hardware.column.autoUnlockEnabled')='AutoUnlockEnabled'; (Get-ReportText 'report.hardware.column.autoUnlockKeyStored')='AutoUnlockKeyStored'
    (Get-ReportText 'report.hardware.column.metadataVersion')='MetadataVersion'; (Get-ReportText 'report.hardware.column.keyProtectorTypes')='KeyProtectorTypes'
    (Get-ReportText 'report.hardware.column.source')='Source'; (Get-ReportText 'report.hardware.column.error')='Error'
}
Add-Section (Get-ReportText 'report.hardware.section.bitLockerVolumes') (Add-Table (ConvertTo-ReportHardwareTableRows $bitLockerDisplayRows $bitLockerColumns) @($bitLockerColumns.Keys))

$memory = Safe-Cim Win32_PhysicalMemory | ForEach-Object {
    [pscustomobject]@{
        "Khe"=$_.DeviceLocator
        "Hang"=$_.Manufacturer
        "Dung luong"=(Size-GB $_.Capacity)
        "Toc do"=$_.Speed
        "Serial"=$_.SerialNumber
    }
}
Add-Section "RAM" (Add-Table $memory @("Khe","Hang","Dung luong","Toc do","Serial"))

$gpu = Safe-Cim Win32_VideoController | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "RAM"=(Size-GB $_.AdapterRAM)
        "Driver"=$_.DriverVersion
        "Do phan giai"="$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        "Trang thai"=$_.Status
    }
}
Add-Section "Đồ họa" (Add-Table $gpu @("Ten","RAM","Driver","Do phan giai","Trang thai"))

$monitors = @()
try { $monitors = @(Get-ReportMonitorInventory) } catch {}
$monitorColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.name')='Name'; (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'
    (Get-ReportText 'report.hardware.column.productCode')='ProductCode'; (Get-ReportText 'report.hardware.column.serial')='SerialNumber'
    (Get-ReportText 'report.hardware.column.manufactureWeek')='ManufactureWeek'; (Get-ReportText 'report.hardware.column.manufactureYear')='ManufactureYear'
}
Add-Section (Get-ReportText 'report.hardware.section.monitors') (Add-Table (ConvertTo-ReportHardwareTableRows $monitors $monitorColumns) @($monitorColumns.Keys))

$sound = Safe-Cim Win32_SoundDevice | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "Hang"=$_.Manufacturer
        "Trang thai"=$_.Status
    }
}
Add-Section "Âm thanh" (Add-Table $sound @("Ten","Hang","Trang thai"))

$batterySourceClass = 'Win32_PortableBattery'
$batterySourceRows = @(Safe-Cim Win32_PortableBattery)
if ($batterySourceRows.Count -eq 0) {
    $batterySourceClass = 'Win32_Battery'
    $batterySourceRows = @(Safe-Cim Win32_Battery)
}
$batteries = @($batterySourceRows | ForEach-Object {
    [pscustomobject][ordered]@{
        Name=[string]$_.Name; Manufacturer=[string]$_.Manufacturer; DeviceID=[string]$_.DeviceID; PNPDeviceID=[string]$_.PNPDeviceID
        Status=[string]$_.Status; BatteryStatus=$_.BatteryStatus; EstimatedChargeRemaining=$_.EstimatedChargeRemaining
        EstimatedRunTime=$_.EstimatedRunTime; DesignCapacity=$_.DesignCapacity; FullChargeCapacity=$_.FullChargeCapacity
        DesignVoltage=$_.DesignVoltage; Chemistry=$_.Chemistry; SmartBatteryVersion=[string]$_.SmartBatteryVersion; Source=$batterySourceClass
    }
})
$batteryColumns = [ordered]@{
    (Get-ReportText 'report.hardware.column.name')='Name'; (Get-ReportText 'report.hardware.column.manufacturer')='Manufacturer'
    (Get-ReportText 'report.hardware.column.deviceId')='DeviceID'; (Get-ReportText 'report.hardware.column.identifier')='PNPDeviceID'
    (Get-ReportText 'report.hardware.column.status')='Status'; (Get-ReportText 'report.hardware.column.batteryStatus')='BatteryStatus'
    (Get-ReportText 'report.hardware.column.chargePercent')='EstimatedChargeRemaining'; (Get-ReportText 'report.hardware.column.estimatedRuntime')='EstimatedRunTime'
    (Get-ReportText 'report.hardware.column.designCapacity')='DesignCapacity'; (Get-ReportText 'report.hardware.column.fullChargeCapacity')='FullChargeCapacity'
    (Get-ReportText 'report.hardware.column.designVoltage')='DesignVoltage'; (Get-ReportText 'report.hardware.column.chemistry')='Chemistry'
    (Get-ReportText 'report.hardware.column.source')='Source'
}
Add-Section (Get-ReportText 'report.hardware.section.batteries') (Add-Table (ConvertTo-ReportHardwareTableRows $batteries $batteryColumns) @($batteryColumns.Keys))

$disks = Safe-Cim Win32_DiskDrive | ForEach-Object {
    [pscustomobject]@{
        "Model"=$_.Model
        "Loai"=$_.MediaType
        "Dung luong"=(Size-GB $_.Size)
        "Serial"=$_.SerialNumber
        "Interface"=$_.InterfaceType
        "Trang thai"=$_.Status
    }
}
Add-Section "Ổ đĩa vật lý" (Add-Table $disks @("Model","Loai","Dung luong","Serial","Interface","Trang thai"))

$volumes = Safe-Cim Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
    [pscustomobject]@{
        "O"=$_.DeviceID
        "Nhan"=$_.VolumeName
        "File system"=$_.FileSystem
        "Tong"=(Size-GB $_.Size)
        "Con trong"=(Size-GB $_.FreeSpace)
    }
}
Add-Section "Phân vùng" (Add-Table $volumes @("O","Nhan","File system","Tong","Con trong"))

$network = @()
try {
    if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
        $network = Get-NetIPConfiguration | ForEach-Object {
            [pscustomobject]@{
                "Adapter"=$_.InterfaceAlias
                "IPv4"=(($_.IPv4Address | Select-Object -ExpandProperty IPAddress) -join ", ")
                "Gateway"=(($_.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop) -join ", ")
                "DNS"=(($_.DNSServer.ServerAddresses) -join ", ")
            }
        }
    } else {
        $network = Safe-Cim Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | ForEach-Object {
            [pscustomobject]@{
                "Adapter"=$_.Description
                "IPv4"=(($_.IPAddress | Where-Object { $_ -match '^\d+\.' }) -join ", ")
                "Gateway"=(($_.DefaultIPGateway) -join ", ")
                "DNS"=(($_.DNSServerSearchOrder) -join ", ")
            }
        }
    }
} catch {}
Add-Section "Mạng" (Add-Table $network @("Adapter","IPv4","Gateway","DNS"))

$adapters = @()
try {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        $adapters = Get-NetAdapter | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Mo ta"=$_.InterfaceDescription
                "MAC"=$_.MacAddress
                "Toc do"=$_.LinkSpeed
                "Trang thai"=$_.Status
            }
        }
    } else {
        $adapters = Safe-Cim Win32_NetworkAdapter | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.NetConnectionID
                "Mo ta"=$_.Name
                "MAC"=$_.MACAddress
                "Toc do"=$_.Speed
                "Trang thai"=$_.NetConnectionStatus
            }
        }
    }
} catch {}
Add-Section "Card mạng" (Add-Table $adapters @("Ten","Mo ta","MAC","Toc do","Trang thai"))
}

if ($wantWindows) {
$hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 80 | ForEach-Object {
    [pscustomobject]@{
        "HotFix"=$_.HotFixID
        "Mo ta"=$_.Description
        "Ngay cai"=$(if ($_.InstalledOn) { ([DateTime]$_.InstalledOn).ToString('yyyy-MM-dd') } else { '' })
        "Nguoi cai"=$_.InstalledBy
    }
}
Add-Section "Ban cap nhat Windows gan day" (Add-Table $hotfixes @("HotFix","Mo ta","Ngay cai","Nguoi cai")) "Windows"
}

# Báo cáo Windows/Office riêng vẫn phải rà dấu vết activator đang hiện hữu.
# Bản cũ chỉ chạy nhánh này trong báo cáo Phần mềm/Toàn bộ nên có thể hiển thị
# kênh license nhưng bỏ qua MAS/OHook/TSforge/Toolkit còn nằm trên máy.
if (($wantWindows -or $wantOffice) -and -not $wantSoftware) {
    $crackFindings = @(Get-ReportActivatorArtifactFindings -Pattern $strongCrackPattern -IncludeFileSearch)
    Add-Section "Dau hieu crack / activator / KMS" `
        (Add-Table $crackFindings @("Nguon","Dau hieu","Vi tri","Muc do")) `
        $(if ($wantWindows) { 'Windows' } else { 'Office' })
}

if ($wantSoftware) {
    Write-Host (Get-ReportText "report.progress.softwareInventory")
    # Kiểm kê toàn máy: Registry chỉ là một nguồn. Bổ sung AppX/MSIX, shortcut
    # Start Menu/Desktop và ứng dụng portable trong các vùng chương trình phổ
    # biến. Desktop chỉ là nguồn phát hiện phụ, không phải phạm vi quét.
    $completeSoftwareInventory = @(Get-ToolInstalledSoftwareInventory -IncludeAppx -IncludeShortcuts -IncludePortable -PortableMaximumResults 220)
    $softwareCatalog = Get-ToolSoftwareLicenseCatalog -PreferCache
    $softwareAssessments = @(Get-ToolSoftwareAssessments -Applications $completeSoftwareInventory -Catalog $softwareCatalog)
    $discoverySourceColumn = Get-ReportText "report.software.column.discoverySource"
    $licenseModelColumn = Get-ReportText "report.software.column.licenseModel"
    $assessmentCodeColumn = Get-ReportText "report.software.column.assessmentCode"
    $confidenceColumn = Get-ReportText "report.software.column.confidence"
    $catalogSourceColumn = Get-ReportText "report.software.column.catalogSource"
    $officialReferenceColumn = Get-ReportText "report.software.column.officialReference"
    $evidenceColumn = Get-ReportText "report.software.column.evidence"
    $vendorScopeColumn = Get-ReportText "report.software.column.vendorScope"
    $technicalStatusColumn = Get-ReportText "report.software.column.technicalStatus"
    $remediationEligibilityColumn = Get-ReportText "report.software.column.remediationEligibility"
    $apps = @($softwareAssessments | ForEach-Object {
        $assessment = $_
        $licenseRequiresEntitlement = [bool]([string]$assessment.LicenseModel -in @('Paid','Commercial','Subscription','Perpetual','Trial','Trialware','Mixed'))
        [pscustomobject][ordered]@{
            "Ten phan mem" = [string]$assessment.Name
            "Phien ban" = [string]$assessment.Version
            "Hang" = [string]$assessment.Publisher
            "Ngay cai" = [string]$assessment.InstallDate
            "Phân loại" = if ([bool]$assessment.IsMicrosoft) { Get-ReportText "report.text.017" } else { Get-ReportText "report.text.018" }
            "Phạm vi" = [string]$assessment.Scope
            "Kiến trúc" = [string]$assessment.Architecture
            $discoverySourceColumn = (@($assessment.DiscoverySources) -join ', ')
            "Duong dan" = [string]$assessment.InstallLocation
            "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$assessment.SignatureStatus)
            "Nhà phát hành chữ ký" = [string]$assessment.SignaturePublisher
            "Tệp kiểm tra" = [string]$assessment.RepresentativePath
            "Phiên bản tệp" = [string]$assessment.FileVersion
            "Có trình gỡ" = if (-not [string]::IsNullOrWhiteSpace([string]$assessment.UninstallString)) { Get-ReportText "report.text.019" } else { Get-ReportText "report.text.020" }
            "Metadata cập nhật" = if ([string]$assessment.SourceKind -eq 'Registry') { Get-ReportText "report.text.021" } else { Get-ReportText "report.text.022" }
            "Lệnh gỡ" = [string]$assessment.UninstallString
            "Khóa đăng ký" = [string]$assessment.RegistryPath
            $licenseModelColumn = [string]$assessment.LicenseModel
            $assessmentCodeColumn = [string]$assessment.AssessmentCode
            $confidenceColumn = [string]$assessment.Confidence
            $catalogSourceColumn = [string]$assessment.CatalogSource
            $officialReferenceColumn = [string]$assessment.OfficialReferenceUrl
            $evidenceColumn = (@($assessment.Evidence | ForEach-Object { [string]$_.Code } | Select-Object -Unique) -join ', ')
            IsMicrosoft = [bool]$assessment.IsMicrosoft
            SignatureStatus = [string]$assessment.SignatureStatus
            AssessmentCode = [string]$assessment.AssessmentCode
            LicenseModel = [string]$assessment.LicenseModel
            LicenseRequiresEntitlement = $licenseRequiresEntitlement
            NeedsReview = [bool]$assessment.NeedsReview
            RemediationSupported = [bool]$assessment.RemediationSupported
            ManualEligible = [bool]$assessment.ManualEligible
            AutoEligible = [bool]$assessment.AutoEligible
            RemediationAdapter = [string]$assessment.RemediationAdapter
            RemediationEvidenceCount = [int]$assessment.RemediationEvidenceCount
            RemediationImpact = [string]$assessment.RemediationImpact
            ActivationStateProbe = [string]$assessment.ActivationStateProbe
            CatalogProductId = [string]$assessment.CatalogProductId
            CatalogVersion = [string]$assessment.CatalogVersion
            CatalogLicenseModel = [string]$assessment.CatalogLicenseModel
            CatalogMatchReason = [string]$assessment.CatalogMatchReason
            CatalogNamePattern = [string]$assessment.CatalogNamePattern
            LicenseModelReason = [string]$assessment.LicenseModelReason
            LicenseTechnicalState = [string]$assessment.LicenseTechnicalState
            AssessmentSortPriority = [int]$assessment.AssessmentSortPriority
            PublisherVerification = $assessment.PublisherVerification
            TechnicalEvidence = @($assessment.Evidence)
            EvidenceCount = [int]$assessment.EvidenceCount
            ConclusiveEvidenceCount = [int]$assessment.ConclusiveEvidenceCount
            StrongEvidenceCount = [int]$assessment.StrongEvidenceCount
            ModerateEvidenceCount = [int]$assessment.ModerateEvidenceCount
            WeakEvidenceCount = [int]$assessment.WeakEvidenceCount
            DecisiveEvidenceCount = [int]$assessment.DecisiveEvidenceCount
            IndependentStrongEvidenceGroupCount = [int]$assessment.IndependentStrongEvidenceGroupCount
            CleanupFinding = [bool]$assessment.CleanupFinding
            VendorScope = [string]$assessment.VendorScope
            IsSystemComponent = [bool]$assessment.IsSystemComponent
            SystemComponentReason = [string]$assessment.SystemComponentReason
            PostRemediationStateExpectation = [string]$assessment.PostRemediationStateExpectation
            DeepScanEnabled = [bool]$assessment.DeepScanEnabled
            DeepScanStatus = [string]$assessment.DeepScanStatus
            DeepScanComplete = [bool]$assessment.DeepScanComplete
            DeepScanRoots = @($assessment.DeepScanRoots)
            DeepScanFilesEnumerated = [int]$assessment.DeepScanFilesEnumerated
            DeepScanSignatureChecks = [int]$assessment.DeepScanSignatureChecks
            DeepScanHashChecks = [int]$assessment.DeepScanHashChecks
            MergedRecordCount = [int]$assessment.MergedRecordCount
        }
    } | Sort-Object AssessmentSortPriority, "Ten phan mem", "Phien ban", "Phạm vi")

    # Giữ toàn bộ dữ liệu trong JSON/XML nhưng chỉ đưa ứng dụng người dùng vào
    # luồng đọc chính. Thành phần hệ thống và ứng dụng mặc định được chuyển sang
    # một phụ lục có liên kết nội bộ để PDF không bị kéo dài khó đọc.
    $systemApps = @($apps | Where-Object { [bool]$_.IsSystemComponent })
    $primaryApps = @($apps | Where-Object { -not [bool]$_.IsSystemComponent })

    # Hợp đồng hiển thị Mục 5 của v4.3.0.3 được giữ nguyên. Dữ liệu giàu hơn
    # vẫn được thu thập trong $apps nhưng bốn cột truyền thống là nguồn cho
    # các bảng cũ và việc dò dấu hiệu cũ.
    $legacyApps = @($primaryApps |
        Select-Object "Ten phan mem", "Phien ban", "Hang", "Ngay cai" |
        Sort-Object "Ten phan mem", "Phien ban" -Unique)

    # Từ "portable" hoặc thiếu metadata không phải là bằng chứng crack. Mục
    # đánh giá sơ bộ chỉ giữ các tên thực sự có ngữ cảnh kích hoạt/can thiệp.
    $genericReviewPattern = "(?i)(\bactivator\b|\bactivation\b|\bpatch(?:er)?\b|\brepack\b|\bbypass\b|\br2r\b|\bthuoc\b|\bauto[\s._-]*activat(?:e|ed|ion)\b)"
    $legacySoftwareAudit = @($legacyApps | ForEach-Object {
        $name = $_."Ten phan mem"
        $publisher = $_."Hang"
        $status = "Khong co chi bao kich hoat lau"
        $reason = "Khong dua vao danh sach nghi van neu chi co thong tin cai dat."
        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $status = "Co dau hieu nghi khong chinh hang"
            $reason = "Ten phan mem/publisher khop mau activator dac hieu; van can xac minh chu ky va nguon cai dat."
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $status = "Tu khoa chung - can xac minh thu cong"
            $reason = "Tu khoa activation/patch/portable co the hop le; khong du de ket luan crack neu khong co bang chung khac."
        }
        [pscustomobject]@{
            "Ten phan mem" = $name
            "Phien ban" = $_."Phien ban"
            "Hang" = $publisher
            "Danh gia so bo" = $status
            "Ly do" = $reason
        }
    })
    $legacySoftwareAuditDisplay = @($legacySoftwareAudit | Where-Object {
        [string]$_.'Danh gia so bo' -ne 'Khong co chi bao kich hoat lau'
    })

    $softwareAudit = @($primaryApps | ForEach-Object {
        $app = $_
        $name = [string]$app."Ten phan mem"
        $publisher = [string]$app."Hang"
        $reviewRank = 0
        $reasons = New-Object System.Collections.ArrayList

        switch ([string]$app.AssessmentCode) {
            'NonGenuine' {
                $reviewRank = 2
                [void]$reasons.Add((Get-ReportText "report.software.reason.nonGenuineEvidence"))
            }
            'Suspicious' {
                $reviewRank = [Math]::Max($reviewRank, 2)
                [void]$reasons.Add((Get-ReportText "report.software.reason.suspiciousEvidence"))
            }
            'IntegrityCompromised' {
                $reviewRank = [Math]::Max($reviewRank, 2)
                [void]$reasons.Add((Get-ReportText "report.software.reason.integrityCompromised"))
            }
            'Unverified' {
                $reviewRank = [Math]::Max($reviewRank, 1)
                [void]$reasons.Add((Get-ReportText "report.software.reason.licenseUnverified"))
            }
            'TrialOrUnverified' {
                $reviewRank = [Math]::Max($reviewRank, 1)
                [void]$reasons.Add((Get-ReportText "report.software.reason.trialUnverified"))
            }
        }

        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $reviewRank = 2
            [void]$reasons.Add((Get-ReportText "report.text.023"))
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.024"))
        }
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.025"))
        }
        if ([string]::IsNullOrWhiteSpace([string]$app."Phien ban")) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.026"))
        }
        if ([string]$app.SignatureStatus -in @("HashMismatch", "NotTrusted", "UnknownError")) {
            $reviewRank = 2
            [void]$reasons.Add((Get-ReportText "report.text.027"))
        } elseif ([string]$app.SignatureStatus -eq "NotSigned") {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.028"))
        }
        if ([string]$app."Duong dan" -match '(?i)\\(temp|downloads?)(\\|$)') {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.029"))
        }
        if ([string]$app."Có trình gỡ" -eq (Get-ReportText "report.text.020")) {
            $reviewRank = [Math]::Max($reviewRank, 1)
            [void]$reasons.Add((Get-ReportText "report.text.030"))
        }
        if ($reasons.Count -eq 0) {
            [void]$reasons.Add((Get-ReportText "report.text.031"))
        }
        $reviewLevel = switch ($reviewRank) {
            2 { Get-ReportText "report.text.032" }
            1 { Get-ReportText "report.text.033" }
            default { Get-ReportText "report.text.034" }
        }
        $vendorScope = if (-not [string]::IsNullOrWhiteSpace([string]$app.VendorScope)) {
            [string]$app.VendorScope
        } elseif ((($name + ' ' + $publisher) -match '(?i)\bAdobe\b')) {
            'Adobe'
        } elseif ((($name + ' ' + $publisher) -match '(?i)\bAutodesk\b|\bAutoCAD\b|\bRevit\b|\b3ds Max\b|\bCivil 3D\b|\bNavisworks\b|\bInventor\b|\bFusion 360\b')) {
            'Autodesk'
        } else {
            Get-ReportText "report.software.vendorOther"
        }
        $strongTechnicalEvidence = [bool]([int]$app.StrongEvidenceCount -gt 0 -or ($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern))
        $technicalStatus = Get-ReportSoftwareAssessmentLabel -StatusCode ([string]$app.AssessmentCode)
        $hasRemediationEvidence = [bool]([int]$app.RemediationEvidenceCount -gt 0)
        # Điều kiện xử lý phải phản ánh đúng bằng chứng. Low/Unverified không
        # bao giờ là căn cứ xóa ứng dụng hoặc đưa vào hàng đợi khắc phục.
        $remediationEligibility = Get-ReportSoftwareRemediationEligibility `
            -Name $name `
            -Publisher $publisher `
            -AssessmentCode ([string]$app.AssessmentCode) `
            -Confidence ([string]$app.$confidenceColumn) `
            -LicenseModel ([string]$app.LicenseModel) `
            -ActivationStateProbe ([string]$app.ActivationStateProbe) `
            -RemediationSupported ([bool]$app.RemediationSupported) `
            -HasRemediationEvidence $hasRemediationEvidence `
            -StrongTechnicalEvidence $strongTechnicalEvidence
        [pscustomobject][ordered]@{
            "Ten phan mem" = $name
            "Phien ban" = [string]$app."Phien ban"
            "Hang" = $publisher
            "Phân loại" = [string]$app."Phân loại"
            "Mức rà soát" = $reviewLevel
            "Lý do rà soát" = ($reasons -join " ")
            "Chữ ký" = [string]$app."Chữ ký"
            "Duong dan" = [string]$app."Duong dan"
            $licenseModelColumn = [string]$app.LicenseModel
            $assessmentCodeColumn = [string]$app.AssessmentCode
            $confidenceColumn = [string]$app.$confidenceColumn
            $evidenceColumn = [string]$app.$evidenceColumn
            $officialReferenceColumn = [string]$app.$officialReferenceColumn
            $vendorScopeColumn = $vendorScope
            $technicalStatusColumn = $technicalStatus
            $remediationEligibilityColumn = $remediationEligibility
            ReviewRank = $reviewRank
            StrongTechnicalEvidence = $strongTechnicalEvidence
            HasRemediationEvidence = $hasRemediationEvidence
            LicenseRequiresEntitlement = [bool]$app.LicenseRequiresEntitlement
        }
    })

    $thirdPartyApps = @($primaryApps | Where-Object { -not [bool]$_.IsMicrosoft })
    $thirdPartyAudit = @($softwareAudit | Where-Object { $_."Phân loại" -eq (Get-ReportText "report.text.018") })
    $thirdPartyReview = @($thirdPartyAudit | Where-Object { [int]$_.ReviewRank -gt 0 })
    # Chỉ gọi là cài song song khi có cả phiên bản lẫn vị trí cài khác nhau.
    # Nhiều record Registry/AppX/shortcut của cùng một bản không còn bị đếm
    # thành các bản cài riêng, như trường hợp Zalo/Telegram trước đây.
    $parallelInstallCountColumn = Get-ReportText 'report.software.column.parallelInstallCount'
    $parallelExplanationColumn = Get-ReportText 'report.software.column.explanation'
    $parallelVersions = @(Get-ReportParallelVersionRows -Applications $thirdPartyApps)

    $softwareOverview = @(
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.035"); "Gia tri"=@($apps).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.primary"); "Gia tri"=@($primaryApps).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.system"); "Gia tri"=@($systemApps).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.036"); "Gia tri"=@($thirdPartyApps).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.037"); "Gia tri"=@($apps | Where-Object { [bool]$_.IsMicrosoft }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.038"); "Gia tri"=@($apps | Where-Object { $_.SignatureStatus -eq "Valid" }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.039"); "Gia tri"=@($thirdPartyReview).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.text.040"); "Gia tri"=@($parallelVersions).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.nonGenuine"); "Gia tri"=@($apps | Where-Object { $_.AssessmentCode -eq 'NonGenuine' }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.suspicious"); "Gia tri"=@($apps | Where-Object { $_.AssessmentCode -eq 'Suspicious' }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.integrityCompromised"); "Gia tri"=@($apps | Where-Object { $_.AssessmentCode -eq 'IntegrityCompromised' }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.unverified"); "Gia tri"=@($apps | Where-Object { $_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count },
        [pscustomobject]@{ "Muc"=(Get-ReportText "report.software.overview.catalog"); "Gia tri"=$(if ($softwareCatalog) { "$($softwareCatalog.CatalogSource) · $($softwareCatalog.CatalogVersion) · $(@($softwareCatalog.Products).Count)" } else { Get-ReportText 'common.unknown' }) }
    )

    $systemAppendixLink = "<p class='note system-app-link'><a href='#system-software-appendix'>$(Html (Get-ReportText 'report.software.system.open' @(@($systemApps).Count)))</a></p>"
    Add-Section "Phan mem da cai" ((Add-Table $legacyApps @("Ten phan mem","Phien ban","Hang","Ngay cai")) + $systemAppendixLink) "Software"
    Add-Section "Danh gia so bo ban quyen phan mem" (Add-Table $legacySoftwareAuditDisplay @("Ten phan mem","Phien ban","Hang","Danh gia so bo","Ly do")) "Software"
    $softwareAssessmentRows = @($softwareAudit | Where-Object {
        $code = [string]$_.$assessmentCodeColumn
        $commercialModel = [bool]$_.LicenseRequiresEntitlement
        return [bool](
            [bool]$_.StrongTechnicalEvidence -or
            $code -in @('NonGenuine','Suspicious','IntegrityCompromised','Unactivated') -or
            ($commercialModel -and $code -in @('Unverified','TrialOrUnverified') -and [string]$_.$confidenceColumn -ne 'Low')
        )
    } | Select-Object "Ten phan mem","Phien ban","Hang",$licenseModelColumn,$assessmentCodeColumn,$confidenceColumn,$evidenceColumn,$officialReferenceColumn,$vendorScopeColumn,$technicalStatusColumn,$remediationEligibilityColumn)
    $softwareAssessmentEvidenceRows = @($softwareAudit | Where-Object { [int]$_.ReviewRank -ge 2 -or [bool]$_.StrongTechnicalEvidence } | Select-Object "Ten phan mem","Phien ban","Hang",$licenseModelColumn,$assessmentCodeColumn,$confidenceColumn,$evidenceColumn,$officialReferenceColumn,$vendorScopeColumn,$technicalStatusColumn,$remediationEligibilityColumn)
    $softwareAssessmentOverview = "<p class='note software-license-model-note'>$(Html (Get-ReportText 'report.software.assessmentNote'))</p>" + `
        (Add-Table $softwareAssessmentRows @("Ten phan mem","Phien ban","Hang",$licenseModelColumn,$technicalStatusColumn,$confidenceColumn,$remediationEligibilityColumn))
    $softwareAssessmentEvidence = "<h3>$(Html (Get-ReportText 'report.software.assessmentEvidence'))</h3>" + `
        "<p class='note software-evidence-note'>$(Html (Get-ReportText 'report.software.evidenceOnlyNote'))</p>" + `
        (Add-Table $softwareAssessmentEvidenceRows @("Ten phan mem",$licenseModelColumn,$assessmentCodeColumn,$evidenceColumn,$vendorScopeColumn,$officialReferenceColumn))
    Add-Section (Get-ReportText "report.software.assessmentSection") ($softwareAssessmentOverview + $softwareAssessmentEvidence) "Software"

    Write-Host (Get-ReportText "report.progress.supportingSignals")
    $startup = @(Safe-Cim Win32_StartupCommand | Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{
            "Ten" = [string]$_.Name
            "Lenh" = [string]$_.Command
            "Vi tri" = [string]$_.Location
            "Nguoi dung" = [string]$_.User
        }
    })
    Add-Section "Startup" (Add-Table $startup @("Ten","Lenh","Vi tri","Nguoi dung")) "Software"

    $thirdPartyAutoruns = @($startup | ForEach-Object {
        $startupFile = Get-ExecutablePathFromMetadata -Candidates @([string]$_.Lenh) -PreferredName ([string]$_.Ten)
        $isWindowsPath = -not [string]::IsNullOrWhiteSpace($startupFile) -and
            $startupFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase)
        if (-not $isWindowsPath) {
            $startupSignature = Get-CachedSoftwareSignatureState -Path $startupFile
            $isMicrosoftSignature = Test-MicrosoftSoftwarePublisher -Publisher ([string]$startupSignature.Publisher)
            if (-not $isMicrosoftSignature) {
                [pscustomobject][ordered]@{
                    "Ten" = [string]$_.Ten
                    "Lenh" = [string]$_.Lenh
                    "Vi tri" = [string]$_."Vi tri"
                    "Nguoi dung" = [string]$_."Nguoi dung"
                    "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$startupSignature.Status)
                    "Tệp kiểm tra" = [string]$startupFile
                }
            }
        }
    })

    $serviceInventory = @(Safe-Cim Win32_Service | Sort-Object State, Name | ForEach-Object {
        [pscustomobject][ordered]@{
            "Ten" = [string]$_.Name
            "Hien thi" = [string]$_.DisplayName
            "Trang thai" = [string]$_.State
            "Loai khoi dong" = [string]$_.StartMode
            "Duong dan" = [string]$_.PathName
        }
    })
    $thirdPartyServices = @($serviceInventory | ForEach-Object {
        $serviceFile = Get-ExecutablePathFromMetadata -Candidates @([string]$_."Duong dan") -PreferredName ([string]$_.Ten)
        $isWindowsPath = -not [string]::IsNullOrWhiteSpace($serviceFile) -and
            $serviceFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase)
        if (-not $isWindowsPath) {
            $serviceSignature = Get-CachedSoftwareSignatureState -Path $serviceFile
            $isMicrosoftSignature = Test-MicrosoftSoftwarePublisher -Publisher ([string]$serviceSignature.Publisher)
            if (-not $isMicrosoftSignature) {
                [pscustomobject][ordered]@{
                    "Ten" = [string]$_.Ten
                    "Hien thi" = [string]$_."Hien thi"
                    "Trang thai" = [string]$_."Trang thai"
                    "Loai khoi dong" = [string]$_."Loai khoi dong"
                    "Duong dan" = [string]$_."Duong dan"
                    "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$serviceSignature.Status)
                    "Tệp kiểm tra" = [string]$serviceFile
                }
            }
        }
    })
    $services = @(Get-Service | Sort-Object Status, Name | ForEach-Object {
        [pscustomobject]@{
            "Ten" = $_.Name
            "Hien thi" = $_.DisplayName
            "Trang thai" = $_.Status
            "Loai khoi dong" = $_.StartType
        }
    })
    Add-Section "Dich vu Windows" (Add-Table $services @("Ten","Hien thi","Trang thai","Loai khoi dong")) "Software"

    $crackFindings = @()
    $manualReviewFindings = @()
    foreach ($app in $legacyApps) {
        $name = [string]$app."Ten phan mem"
        $publisher = [string]$app."Hang"
        if (($name -match $strongCrackPattern) -or ($publisher -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Installed software"
                "Dau hieu" = $name
                "Vi tri" = $publisher
                "Muc do" = "Can kiem tra ngay"
            }
        } elseif (($name -match $genericReviewPattern) -or ($publisher -match $genericReviewPattern)) {
            $manualReviewFindings += [pscustomobject]@{
                "Nguon" = "Installed software"
                "Dau hieu" = $name
                "Vi tri" = $publisher
                "Muc do" = "Tu khoa chung - khong du ket luan"
            }
        }
    }
    foreach ($item in $startup) {
        if (($item.Ten -match $strongCrackPattern) -or ($item.Lenh -match $strongCrackPattern) -or ($item."Vi tri" -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Startup"
                "Dau hieu" = $item.Ten
                "Vi tri" = $item.Lenh
                "Muc do" = "Can kiem tra"
            }
        }
    }
    foreach ($svc in $services) {
        if (($svc.Ten -match $strongCrackPattern) -or ($svc."Hien thi" -match $strongCrackPattern)) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Service"
                "Dau hieu" = $svc.Ten
                "Vi tri" = $svc."Hien thi"
                "Muc do" = "Can kiem tra"
            }
        }
    }
    $scheduledTaskObjectsAll = @()
    try {
        if ($capabilityState.ScheduledTasksModule) {
            $scheduledTaskObjectsAll = @(Get-ScheduledTask)
        }
        $taskFindings = $scheduledTaskObjectsAll | Where-Object {
            ($_.TaskName -match $strongCrackPattern) -or ($_.TaskPath -match $strongCrackPattern) -or ($_.Author -match $strongCrackPattern)
        } | Select-Object -First 80
        foreach ($task in $taskFindings) {
            $crackFindings += [pscustomobject]@{
                "Nguon" = "Scheduled task"
                "Dau hieu" = $task.TaskName
                "Vi tri" = $task.TaskPath
                "Muc do" = "Can kiem tra"
            }
        }
    } catch {}
    $installedProductRoots = @($softwareAssessments |
        Where-Object {
            -not [bool]$_.IsSystemComponent -and
            -not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation) -and
            ([bool]$_.NeedsReview -or [string]$_.LicenseModel -notin @('Free','OpenSource','Freeware','SystemComponent','Driver','Runtime'))
        } |
        Sort-Object @{Expression={ if ([bool]$_.NeedsReview) { 0 } else { 1 } }}, Name |
        ForEach-Object { [string]$_.InstallLocation } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        Select-Object -Unique |
        Select-Object -First 32)
    $scanRoots = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyDocuments"),
        "$env:USERPROFILE\Downloads",
        "$env:ProgramData",
        $env:LOCALAPPDATA,
        $env:APPDATA
        $installedProductRoots
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($path in @(Find-ToolPatternFilesParallel -Roots $scanRoots -Pattern $strongCrackPattern -MaximumResults 120 -ThrottleLimit 4 -MaximumDepth 4 -PerRootTimeoutSeconds 5)) {
        if (([IO.Path]::GetExtension([string]$path)).ToLowerInvariant() -notin $reportActivatorArtifactExtensions) { continue }
        $crackFindings += [pscustomobject]@{
            "Nguon" = "File scan"
            "Dau hieu" = [IO.Path]::GetFileName($path)
            "Vi tri" = $path
            "Muc do" = "Dau hieu theo ten file"
        }
    }
    Add-Section "Dau hieu crack / activator / KMS" (Add-Table $crackFindings @("Nguon","Dau hieu","Vi tri","Muc do")) "Software"
    Add-Section "Tu khoa chung can xac minh thu cong (khong ket luan crack)" (Add-Table $manualReviewFindings @("Nguon","Dau hieu","Vi tri","Muc do")) "Software"
}

if ($wantHardware) {
$securityRows = @()
try {
    $av = Safe-Cim AntivirusProduct root/SecurityCenter2
    foreach ($item in $av) {
        $securityRows += [pscustomobject]@{
            "Loai"="Antivirus"
            "Ten"=$item.displayName
            "Trang thai"=$item.productState
            "Duong dan"=$item.pathToSignedProductExe
        }
    }
} catch {}
try {
    $fwProfiles = Get-NetFirewallProfile
    foreach ($profile in $fwProfiles) {
        $securityRows += [pscustomobject]@{
            "Loai"="Firewall"
            "Ten"=$profile.Name
            "Trang thai"=$profile.Enabled
            "Duong dan"=""
        }
    }
} catch {}
Add-Section "Bao mat" (Add-Table $securityRows @("Loai","Ten","Trang thai","Duong dan"))

$users = @()
try {
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $users = Get-LocalUser | ForEach-Object {
            [pscustomobject]@{
                "User"=$_.Name
                "Enabled"=$_.Enabled
                "LastLogon"=$_.LastLogon
                "PasswordRequired"=$_.PasswordRequired
            }
        }
    } else {
        $users = Safe-Cim Win32_UserAccount | Where-Object { $_.LocalAccount } | ForEach-Object {
            [pscustomobject]@{
                "User"=$_.Name
                "Enabled"=(-not $_.Disabled)
                "LastLogon"="Khong co thong tin"
                "PasswordRequired"="Khong co thong tin"
            }
        }
    }
} catch {}
Add-Section "Local users" (Add-Table $users @("User","Enabled","LastLogon","PasswordRequired"))

$printers = @()
try {
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
        $printers = Get-Printer | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Driver"=$_.DriverName
                "Port"=$_.PortName
                "Default"=$_.Default
            }
        }
    } else {
        $printers = Safe-Cim Win32_Printer | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                "Ten"=$_.Name
                "Driver"=$_.DriverName
                "Port"=$_.PortName
                "Default"=$_.Default
            }
        }
    }
} catch {}
Add-Section "May in" (Add-Table $printers @("Ten","Driver","Port","Default"))

$usb = Safe-Cim Win32_PnPEntity | Where-Object {
    $_.PNPClass -in @("USB","DiskDrive","Image","Camera","Bluetooth")
} | Sort-Object PNPClass, Name | ForEach-Object {
    [pscustomobject]@{
        "Loai"=$_.PNPClass
        "Ten"=$_.Name
        "Manufacturer"=$_.Manufacturer
        "Trang thai"=$_.Status
    }
}
Add-Section "Thiet bi USB / ngoai vi" (Add-Table $usb @("Loai","Ten","Manufacturer","Trang thai"))

$shares = Safe-Cim Win32_Share | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        "Ten"=$_.Name
        "Duong dan"=$_.Path
        "Loai"=$_.Type
        "Mo ta"=$_.Description
    }
}
Add-Section "Thu muc chia se" (Add-Table $shares @("Ten","Duong dan","Loai","Mo ta"))
}

if ($wantSoftware) {
Write-Host (Get-ReportText "report.progress.scheduledTasks")
$tasks = @()
$thirdPartyTasks = @()
if ($capabilityState.ScheduledTasksModule) {
    # Reuse the same read-only snapshot collected for crack-indicator matching.
    # Calling Get-ScheduledTask twice was one of the visible processing delays.
    $scheduledTaskObjects = @($scheduledTaskObjectsAll | Where-Object { $_.State -ne "Disabled" } | Select-Object -First 120)
    $tasks = $scheduledTaskObjects | ForEach-Object {
        [pscustomobject]@{
            "Task"=$_.TaskName
            "Path"=$_.TaskPath
            "State"=$_.State
            "Author"=$_.Author
        }
    }
    $thirdPartyTasks = @($scheduledTaskObjects | ForEach-Object {
        $taskObject = $_
        $isKnownMicrosoftTask = ([string]$taskObject.TaskPath -like "\Microsoft\*") -or
            ([string]$taskObject.Author -match '(?i)\bMicrosoft\b')
        if (-not $isKnownMicrosoftTask) {
            $actionText = @($taskObject.Actions | ForEach-Object {
                @([string]$_.Execute, [string]$_.Arguments) -join " "
            }) -join "; "
            $taskFile = Get-ExecutablePathFromMetadata -Candidates @($actionText) -PreferredName ([string]$taskObject.TaskName)
            $isWindowsPath = -not [string]::IsNullOrWhiteSpace($taskFile) -and
                $taskFile.StartsWith([Environment]::ExpandEnvironmentVariables("%WINDIR%"), [StringComparison]::OrdinalIgnoreCase)
            if (-not $isWindowsPath) {
                $taskSignature = Get-CachedSoftwareSignatureState -Path $taskFile
                if (-not (Test-MicrosoftSoftwarePublisher -Publisher ([string]$taskSignature.Publisher))) {
                    [pscustomobject][ordered]@{
                        "Task" = [string]$taskObject.TaskName
                        "Path" = [string]$taskObject.TaskPath
                        "State" = [string]$taskObject.State
                        "Author" = [string]$taskObject.Author
                        "Hành động" = $actionText.Trim()
                        "Chữ ký" = Get-SoftwareSignatureLabel -Status ([string]$taskSignature.Status)
                        "Tệp kiểm tra" = [string]$taskFile
                    }
                }
            }
        }
    })
} elseif ($capabilityState.ScheduledTasksFallback) {
    $tasks = @([pscustomobject]@{
        "Task"=(Get-ReportText "report.capability.scheduledModuleMissing")
        "Path"=(Get-ReportText "report.capability.schtasksAvailable")
        "State"=(Get-ReportText "report.capability.deepUse")
        "Author"="Windows compatibility"
    })
} else {
    $tasks = @([pscustomobject]@{
        "Task"=(Get-ReportText "report.capability.scheduledUnreadable")
        "Path"=""
        "State"=(Get-ReportText "report.capability.unsupported")
        "Author"=""
    })
}
Add-Section "Scheduled tasks dang bat" (Add-Table $tasks @("Task","Path","State","Author")) "Software"
}

# Plugin v4.6 chỉ dùng JSON khai báo và các nguồn đọc đã giới hạn. Không dot-source
# hoặc thực thi mã do plugin cung cấp.
$pluginAudit = $null
if ($wantSoftware) {
    try {
        $pluginAudit = Invoke-ToolPluginAudit
        $pluginRows = @($pluginAudit.Plugins | ForEach-Object {
            [pscustomobject]@{
                "Plugin"=$_.Name
                "Phiên bản"=$_.Version
                "Nhà phát hành"=$_.Publisher
                "Bật"=$_.Enabled
                "Quy tắc"=$_.RuleCount
                "Tin cậy"=$_.Trust
            }
        })
        $pluginFindingRows = @($pluginAudit.Findings | ForEach-Object {
            [pscustomobject]@{
                "Mức"=$_.Severity
                "Plugin"=$_.PluginName
                "Quy tắc"=$_.RuleId
                "Quan sát"=$_.Observed
                "Nhận định"=$_.Message
                "Hướng xử lý"=$_.Remediation
                "Lỗi"=$_.Error
            }
        })
        $pluginBody = (Add-Table $pluginRows @("Plugin","Phiên bản","Nhà phát hành","Bật","Quy tắc","Tin cậy"))
        $pluginBody += "<h3>$(Html (Get-ReportText "report.text.041"))</h3>"
        $pluginBody += (Add-Table $pluginFindingRows @("Mức","Plugin","Quy tắc","Quan sát","Nhận định","Hướng xử lý","Lỗi"))
        $pluginBody += "<p class='note'>$(Html (Get-ReportText "report.text.042"))</p>"
        Add-Section "Quy tắc mở rộng bằng plugin" $pluginBody "Software"
    } catch {
        $pluginAudit = [pscustomobject]@{
            PluginCount=0; EnabledPluginCount=0; InvalidPluginCount=0; EvaluatedRuleCount=0
            TriggeredFindingCount=0; HighOrCriticalCount=0; Plugins=@(); Findings=@(); InvalidPlugins=@()
            Error=$_.Exception.Message
        }
        $pluginLockedLabel = Get-ReportText "report.text.043"
        Add-Section "Quy tắc mở rộng bằng plugin" "<p class='license-warning'>$(Html $pluginLockedLabel): $(Html $_.Exception.Message)</p>" "Software"
    }
}

# Phần nâng cao chỉ được nối thêm sau toàn bộ bảng Mục 5 của v4.3.0.3.
# Không đổi tên, thứ tự hoặc số cột của các bảng cũ ở phía trên.
if ($wantSoftware) {
    $supplementNote = Get-ReportText "report.text.044"
    $supplementBody = "<p class='note'>$(Html $supplementNote)</p>"
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.045"))</h3>"
    $supplementBody += (Add-Table $softwareOverview @("Muc","Gia tri"))
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.048"))</h3>"
    $supplementBody += (Add-Table @($thirdPartyReview | Where-Object { [int]$_.ReviewRank -ge 2 }) @("Ten phan mem","Phien ban","Hang","Mức rà soát",$technicalStatusColumn,$remediationEligibilityColumn,"Lý do rà soát","Chữ ký","Duong dan"))
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.049"))</h3>"
    $supplementBody += "<p class='note software-parallel-note'>$(Html (Get-ReportText 'report.software.parallelNote'))</p>"
    $supplementBody += (Add-Table $parallelVersions @("Ten phan mem",$parallelInstallCountColumn,"Phiên bản","Phạm vi",$parallelExplanationColumn))
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.050"))</h3>"
    $supplementBody += (Add-Table $thirdPartyAutoruns @("Ten","Lenh","Vi tri","Nguoi dung","Chữ ký","Tệp kiểm tra"))
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.051"))</h3>"
    $supplementBody += (Add-Table $thirdPartyServices @("Ten","Hien thi","Trang thai","Loai khoi dong","Duong dan","Chữ ký","Tệp kiểm tra"))
    $supplementBody += "<h3>$(Html (Get-ReportText "report.text.052"))</h3>"
    $supplementBody += (Add-Table $thirdPartyTasks @("Task","Path","State","Author","Hành động","Chữ ký","Tệp kiểm tra"))
    Add-Section "Kiểm tra bổ sung phần mềm bên thứ ba" $supplementBody "Software"

    $systemAppendixRows = @($systemApps | ForEach-Object {
        [pscustomobject][ordered]@{
            "Ten phan mem"=[string]$_.'Ten phan mem'
            "Phien ban"=[string]$_.'Phien ban'
            "Hang"=[string]$_.'Hang'
            $licenseModelColumn=[string]$_.LicenseModel
            $technicalStatusColumn=(Get-ReportSoftwareAssessmentLabel -StatusCode ([string]$_.AssessmentCode))
            $discoverySourceColumn=[string]$_.$discoverySourceColumn
        }
    })
    $systemAppendixTitle = Get-ReportText 'report.software.system.appendixTitle'
    $systemAppendixBody = "<p class='note'>$(Html (Get-ReportText 'report.software.system.appendixNote'))</p>" + `
        (Add-Table $systemAppendixRows @("Ten phan mem","Phien ban","Hang",$discoverySourceColumn)) + `
        "<p class='back-link'><a href='#section-1'>$(Html (Get-ReportText 'report.software.system.back'))</a></p>"
    $tocItems += [pscustomobject]@{ Id='system-software-appendix'; Title=$systemAppendixTitle }
    $sections += "<section id='system-software-appendix' class='system-software-appendix'><h2>$(Html $systemAppendixTitle)</h2>$systemAppendixBody</section>"
}

# Phần kết luận luôn hiển thị để người quản trị có hướng xử lý rõ ràng.
$assessmentRows = @()
$verificationLevelColumn = Get-ReportText 'report.license.column.verificationLevel'
if ($wantWindows) {
    $assessmentRow = [ordered]@{ "Đối tượng"="Windows"; "Đánh giá"=$windowsVerdict.Conclusion; "Phương hướng xử lý"=$windowsVerdict.Direction }
    $assessmentRow[$verificationLevelColumn] = $windowsVerdict.VerificationLevel
    $assessmentRows += [pscustomobject]$assessmentRow
}
if ($wantOffice) {
    $assessmentRow = [ordered]@{ "Đối tượng"="Microsoft Office"; "Đánh giá"=$officeVerdict.Conclusion; "Phương hướng xử lý"=$officeVerdict.Direction }
    $assessmentRow[$verificationLevelColumn] = $officeVerdict.VerificationLevel
    $assessmentRows += [pscustomobject]$assessmentRow
}
if ($wantSoftware) {
    $softwareDirection = if (@($crackFindings).Count -gt 0) {
        Get-ReportText "report.text.059"
    } elseif (@($manualReviewFindings).Count -gt 0) {
        Get-ReportText "report.text.060"
    } else {
        Get-ReportText "report.text.061"
    }
    $softwareAssessment = if (@($crackFindings).Count -gt 0) {
        Get-ReportText "report.text.062"
    } elseif (@($manualReviewFindings).Count -gt 0) {
        Get-ReportText "report.text.063"
    } else {
        Get-ReportText "report.text.064"
    }
    $softwareTarget = Get-ReportText "report.text.065"
    $assessmentRow = [ordered]@{ "Đối tượng"=$softwareTarget; "Đánh giá"=$softwareAssessment; "Phương hướng xử lý"=$softwareDirection }
    $assessmentRow[$verificationLevelColumn] = Get-ReportText 'report.license.level.technicalSignals'
    $assessmentRows += [pscustomobject]$assessmentRow
}
if ($assessmentRows.Count -gt 0) {
    $sectionCounter++
    $assessmentId = "section-$sectionCounter"
    $assessmentTitle = Get-ReportText "report.text.066"
    $assessmentNote = Get-ReportText "report.text.067"
    $directInterferenceEvidence = New-Object System.Collections.Generic.List[string]
    if ([string]$activationText -match '(?i)Rearm\s+successful|Rearms?\s+Remaining|AutoKMS|KMS\s*activator|Microsoft\s+Activation\s+Scripts|Activation[\s._-]*Program[\s._-]*1(?:\.|\s+|[_-])17|erturk-dev\.netlify\.app/run') {
        $directInterferenceEvidence.Add('Windows licensing output')
    }
    foreach ($finding in @($crackFindings)) {
        $findingText = @([string]$finding.Nguon, [string]$finding.'Dau hieu', [string]$finding.'Vi tri') -join ' '
        if ($findingText -match '(?i)AutoKMS|KMS(?:Pico|Auto|38)?|activator|rearm|Microsoft[ ._-]*Activation[ ._-]*Scripts|HWIDGEN|\bP?MAS\b|Activation[ ._-]*Program[ ._-]*1(?:\.|\s+|[_-])17|erturk-dev\.netlify\.app/run') {
            $directInterferenceEvidence.Add($findingText)
        }
    }
    $assessmentBody = Add-Table $assessmentRows @("Đối tượng","Đánh giá",$verificationLevelColumn,"Phương hướng xử lý")
    if ($directInterferenceEvidence.Count -gt 0) {
        $assessmentBody += "<p class='license-warning'><strong>$(Html (Get-ReportText 'report.license.interferenceWarning'))</strong></p>"
    }
    $assessmentBody += "<p class='note'>$(Html $assessmentNote)</p>"
    $tocItems += [pscustomobject]@{ Id=$assessmentId; Title=$assessmentTitle }
    $sections += "<section id='$assessmentId'><h2>$(Html $assessmentTitle)</h2>$assessmentBody</section>"
}

$professionalCss = Get-ToolProfessionalReportCss
$tocLinks = @($tocItems | ForEach-Object { "<li><a href='#$(Html $_.Id)'>$(Html $_.Title)</a></li>" }) -join ""
$tocLabel = Get-ToolText -Key "report.toc" -Culture $Culture
$tocBlock = if ($tocItems.Count -gt 1) { "<nav class='toc'><strong>$(Html $tocLabel)</strong><ol>$tocLinks</ol></nav>" } else { "" }
$notScannedLabel = Get-ToolText -Key "report.notScanned" -Culture $Culture
$windowsCardValue = if (-not $wantWindows) {
    $notScannedLabel
} elseif ([string]$windowsVerdict.Code -eq 'Unverifiable') {
    Get-ReportText 'report.license.windows.unverifiableShort'
} else {
    [string]$windowsVerdict.Conclusion
}
$officeCardValue = if (-not $wantOffice) {
    $notScannedLabel
} elseif ([string]$officeVerdict.Code -eq 'Unverifiable') {
    Get-ReportText 'report.license.office.unverifiableShort'
} else {
    [string]$officeVerdict.Conclusion
}
$pluginHighCount = if ($pluginAudit) { [int]$pluginAudit.HighOrCriticalCount } else { 0 }
$windowsTone = if ($wantWindows) { [string]$windowsVerdict.Tone } else { "info" }
$officeTone = if ($wantOffice) { [string]$officeVerdict.Tone } else { "info" }
$findingTone = if (@($crackFindings).Count -gt 0) { "danger" } else { "ok" }
$manualReviewTone = if (@($manualReviewFindings).Count -gt 0) { "warning" } else { "ok" }
$htmlLanguage = if ($Culture -eq "en-US") { "en" } else { "vi" }
$offlineCardValue = Get-ToolText -Key $(if ($script:reportOfflineMode) { "report.offlineYes" } else { "report.offlineNo" }) -Culture $Culture
$offlineTone = if ($script:reportOfflineMode) { "ok" } else { "warning" }
$thirdPartyCount = if ($wantSoftware) { [int]@($thirdPartyApps).Count } else { 0 }
$thirdPartyReviewCount = if ($wantSoftware) { [int]@($thirdPartyReview).Count } else { 0 }
$thirdPartyHighCount = if ($wantSoftware) { [int]@($thirdPartyReview | Where-Object { [int]$_.ReviewRank -ge 2 }).Count } else { 0 }
$summaryCardsHtml = New-Object Text.StringBuilder
[void]$summaryCardsHtml.Append("<div class='card tone-$windowsTone'><div class='card-label'>Windows</div><div class='card-value'>$(Html $windowsCardValue)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$officeTone'><div class='card-label'>Microsoft Office</div><div class='card-value'>$(Html $officeCardValue)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$findingTone'><div class='card-label'>$(Html (Get-ToolText -Key 'report.specificFindings' -Culture $Culture))</div><div class='card-value'>$(@($crackFindings).Count)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$manualReviewTone'><div class='card-label'>$(Html (Get-ToolText -Key 'report.manualReviewFindings' -Culture $Culture))</div><div class='card-value'>$(@($manualReviewFindings).Count)</div></div>")
[void]$summaryCardsHtml.Append("<div class='card tone-$offlineTone'><div class='card-label'>$(Html (Get-ToolText -Key 'report.offline' -Culture $Culture))</div><div class='card-value'>$(Html $offlineCardValue)</div></div>")
$reportModeLabel = if ($Mode -eq "Software") {
    if ($script:reportOfflineMode) { "OFFLINE" } else { "NETWORK ALLOWED" }
} elseif ($script:reportOfflineMode) {
    Get-ReportText "report.text.068"
} else {
    Get-ReportText "report.text.069"
}

$summaryHardwareSection = ""
if ($wantHardware) {
    $hardwareItems = @(
        [pscustomobject]@{ Label=(Get-ReportText "report.summary.model"); Value=("$($cs.Manufacturer) $($cs.Model)".Trim()) },
        [pscustomobject]@{ Label=(Get-ReportText "report.summary.operatingSystem"); Value=("$($os.Caption) $($os.Version) build $($os.BuildNumber)".Trim()) },
        [pscustomobject]@{ Label="CPU"; Value=([string]$cpu.Name).Trim() },
        [pscustomobject]@{ Label="RAM"; Value=(Size-GB $cs.TotalPhysicalMemory) }
    )
    $hardwareOverview = New-Object Text.StringBuilder
    foreach ($item in $hardwareItems) {
        $itemValue = if ([string]::IsNullOrWhiteSpace([string]$item.Value)) { Get-ReportText "report.summary.unavailable" } else { [string]$item.Value }
        [void]$hardwareOverview.Append("<article class='summary-result'><div class='summary-label'>$(Html $item.Label)</div><h3>$(Html $itemValue)</h3></article>")
    }
    $summaryHardwareSection = "<section><h2>$(Html (Get-ReportText 'report.summary.hardwareTitle'))</h2><div class='summary-grid'>$($hardwareOverview.ToString())</div></section>"
}

$summaryConclusionSection = ""
if (@($assessmentRows).Count -gt 0) {
    $summaryConclusionItems = New-Object Text.StringBuilder
    foreach ($row in @($assessmentRows)) {
        $verificationProperty = $row.PSObject.Properties[$verificationLevelColumn]
        $verificationValue = if ($verificationProperty) { [string]$verificationProperty.Value } else { "" }
        [void]$summaryConclusionItems.Append("<article class='summary-result summary-conclusion'><h3>$(Html ([string]$row.'Đối tượng'))</h3><p class='summary-verdict'>$(Html ([string]$row.'Đánh giá'))</p><div class='summary-detail-grid'><div class='summary-detail-box summary-detail-verification'><span class='summary-label'>$(Html (Get-ReportText 'report.summary.verificationLevel'))</span><div class='summary-detail-value'>$(Html $verificationValue)</div></div><div class='summary-detail-box summary-detail-direction'><span class='summary-label'>$(Html (Get-ReportText 'report.summary.direction'))</span><div class='summary-detail-value'>$(Html ([string]$row.'Phương hướng xử lý'))</div></div></div></article>")
    }
    $summaryConclusionSection = "<section><h2>$(Html (Get-ReportText 'report.summary.mainConclusions'))</h2><div class='summary-grid'>$($summaryConclusionItems.ToString())</div><p class='note'>$(Html (Get-ReportText 'report.summary.conclusionLimit'))</p></section>"
}

$summaryAlertSection = ""
if (@($crackFindings).Count -gt 0) {
    $summaryAlertSection = "<section class='summary-alert summary-alert-danger'><h2>$(Html (Get-ReportText 'report.summary.attentionTitle'))</h2><p>$(Html (Get-ReportText 'report.summary.alertSpecific' @(@($crackFindings).Count)))</p></section>"
} elseif (@($manualReviewFindings).Count -gt 0) {
    $summaryAlertSection = "<section class='summary-alert summary-alert-warning'><h2>$(Html (Get-ReportText 'report.summary.attentionTitle'))</h2><p>$(Html (Get-ReportText 'report.summary.alertReview' @(@($manualReviewFindings).Count)))</p></section>"
} elseif ($wantWindows -or $wantOffice -or $wantSoftware) {
    $summaryAlertSection = "<section class='summary-alert'><h2>$(Html (Get-ReportText 'report.summary.attentionTitle'))</h2><p>$(Html (Get-ReportText 'report.summary.alertClear'))</p></section>"
}

$summarySystemSection = ""
if ($wantSoftware -and @($systemAppendixRows).Count -gt 0) {
    $summarySystemSection = "<section><h2>$(Html $systemAppendixTitle)</h2><details class='system-summary-details'><summary>$(Html (Get-ReportText 'report.software.system.open' @(@($systemAppendixRows).Count)))</summary><p class='note'>$(Html (Get-ReportText 'report.software.system.appendixNote'))</p>$(Add-Table $systemAppendixRows @('Ten phan mem','Phien ban','Hang',$discoverySourceColumn))</details></section>"
}

$summaryReportTitle = Get-ReportText "report.summary.title" @($reportTitle)
$detailReportTitle = Get-ReportText "report.detail.title" @($reportTitle)
$detailedHtml = @"
<!doctype html>
<html lang="$htmlLanguage" data-report-view="detailed">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
<title>$(Html $detailReportTitle) - $(Html $reportComputer)</title>
<style>$professionalCss</style>
</head>
<body>
<main class="page">
<header class="hero">
<div class="report-mode">$(Html $reportModeLabel)</div>
<div class="eyebrow">$(Html (Get-ToolText -Key "report.eyebrow" -Culture $Culture))</div>
<h1>$(Html $detailReportTitle)</h1>
<div class="subtitle">$(Html $ToolDescription)</div>
<div class="meta-grid">
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.machine" -Culture $Culture))</b>$(Html $reportComputer)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.time" -Culture $Culture))</b>$(Html $started.ToString("yyyy-MM-dd HH:mm:ss"))</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.mode" -Culture $Culture))</b>$(Html $Mode)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.version" -Culture $Culture))</b>$(Html $ToolReleaseVersion -PreserveVersionLike) / Report $(Html $reportSchemaState.SchemaVersion -PreserveVersionLike)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.privacy" -Culture $Culture))</b>$(Html (Get-ToolText -Key $(if ($RedactSensitive) { "report.redacted" } else { "report.internal" }) -Culture $Culture))</div>
</div>
</header>
<div class="cards cards-count-5">
$($summaryCardsHtml.ToString())
</div>
$tocBlock
<section><h2>$(Html (Get-ToolText -Key "report.scope" -Culture $Culture))</h2><p>$(Html $ToolDescription)</p><p class="note">$(Html $DeveloperCredit)</p></section>
$($sections -join "`n")
<div class="footer"><div class="footer-line">$(Html $ToolName)</div><div class="footer-line">$(Html $DeveloperCredit)</div></div>
</main>
</body>
</html>
"@

$html = @"
<!doctype html>
<html lang="$htmlLanguage" data-report-view="summary">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
<title>$(Html $summaryReportTitle) - $(Html $reportComputer)</title>
<style>$professionalCss</style>
</head>
<body>
<main class="page">
<header class="hero">
<div class="report-mode">$(Html $reportModeLabel)</div>
<div class="eyebrow">$(Html (Get-ToolText -Key "report.eyebrow" -Culture $Culture))</div>
<h1>$(Html $summaryReportTitle)</h1>
<div class="subtitle">$(Html (Get-ReportText "report.summary.description"))</div>
<div class="meta-grid">
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.machine" -Culture $Culture))</b>$(Html $reportComputer)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.time" -Culture $Culture))</b>$(Html $started.ToString("yyyy-MM-dd HH:mm:ss"))</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.mode" -Culture $Culture))</b>$(Html $Mode)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.version" -Culture $Culture))</b>$(Html $ToolReleaseVersion -PreserveVersionLike) / Report $(Html $reportSchemaState.SchemaVersion -PreserveVersionLike)</div>
<div class="meta-item"><b>$(Html (Get-ToolText -Key "report.privacy" -Culture $Culture))</b>$(Html (Get-ToolText -Key $(if ($RedactSensitive) { "report.redacted" } else { "report.internal" }) -Culture $Culture))</div>
</div>
</header>
<div class="cards cards-summary cards-count-5">
$($summaryCardsHtml.ToString())
</div>
<section class="summary-intro"><h2>$(Html (Get-ReportText "report.summary.quickViewTitle"))</h2><p>$(Html (Get-ReportText "report.summary.quickViewBody"))</p></section>
$summaryHardwareSection
$summaryConclusionSection
$summaryAlertSection
$summarySystemSection
{{TOOL_REPORT_PDF_GUIDE}}
<section><h2>$(Html (Get-ToolText -Key "report.scope" -Culture $Culture))</h2><p>$(Html $ToolDescription)</p><p class="note">$(Html (Get-ReportText "report.summary.scopeNote"))</p></section>
<div class="footer"><div class="footer-line">$(Html $ToolName)</div><div class="footer-line">$(Html $DeveloperCredit)</div></div>
</main>
</body>
</html>
"@

$timelineSnapshot = [pscustomobject][ordered]@{ Written=$false; Changed=$false; Changes=@(); Sequence=0; Error=[string]$timelineState.Error }
if ($timelineState.Enabled) {
    try {
        if ($Mode -in @("All", "Windows", "Office")) {
            $windowsLicenseStatusCode = if ($primaryWindowsLicense) {
                switch ([int]$primaryWindowsLicense.LicenseStatus) {
                    1 { 'Licensed' }; 2 { 'OOBGrace' }; 3 { 'OOTGrace' }; 4 { 'NonGenuineGrace' }; 5 { 'Notification' }; 6 { 'ExtendedGrace' }; default { 'Unlicensed' }
                }
            } else { 'Unknown' }
            $windowsChannelCode = Get-ReportWindowsLicenseChannel $primaryWindowsLicense
            $windowsGraceMinutes = if ($primaryWindowsLicense -and $primaryWindowsLicense.PSObject.Properties['GracePeriodRemaining']) { [int]$primaryWindowsLicense.GracePeriodRemaining } else { -1 }
            $kmsTrust = if ($windowsChannelCode -ne 'KMS') {
                'NotKms'
            } elseif (Test-ReportKmsServerApproved -Server ([string]$primaryWindowsLicense.KeyManagementServiceMachine) -ApprovedState $approvedKmsState) {
                'ApprovedEnterpriseHost'
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$primaryWindowsLicense.KeyManagementServiceMachine) -and [bool]$approvedKmsState.Configured) {
                'UnapprovedHost'
            } else {
                'EntitlementUnverified'
            }
            $activationProfile = if ($windowsChannelCode -eq 'KMS' -and $activationText -match '2038') {
                'KMS38'
            } elseif ($windowsChannelCode -eq 'KMS' -and $windowsGraceMinutes -gt 0 -and $windowsGraceMinutes -le 260640) {
                'KMSRenewalUpTo180Days'
            } elseif ($windowsChannelCode -eq 'KMS' -and $windowsGraceMinutes -eq 0) {
                'KmsExpiredOrNotification'
            } elseif ($windowsChannelCode -eq 'KMS') {
                'KmsConfigured'
            } else {
                $windowsChannelCode
            }
            $activatorFamilies = @($crackFindings | ForEach-Object {
                Get-ReportActivatorFamilyCode (([string]$_.DauHieu) + ' ' + ([string]$_.'Dau hieu') + ' ' + ([string]$_.ViTri) + ' ' + ([string]$_.'Vi tri'))
            } | Where-Object { $_ } | Sort-Object -Unique)
            $timelineSnapshot = Save-ToolLicenseSnapshot -Source $reportModuleId -State ([pscustomobject][ordered]@{
                WindowsStatus = $windowsLicenseStatusCode
                WindowsChannel = $windowsChannelCode
                WindowsLicenseId = $(if ($primaryWindowsLicense) { [string]$primaryWindowsLicense.ID } else { '' })
                WindowsPartialKeyLast5 = $(if ($primaryWindowsLicense) { [string]$primaryWindowsLicense.PartialProductKey } else { '' })
                WindowsGracePeriodMinutes = $windowsGraceMinutes
                WindowsActivationProfile = $activationProfile
                WindowsKmsTrust = $kmsTrust
                OfficeStatus = $(if (-not $officeDetected) { 'NotDetected' } elseif ($officeActivated) { 'Licensed' } else { 'NotLicensed' })
                OfficeChannel = $(if ($activeOfficeLicense) { [string]$activeOfficeLicense.Description } elseif ($officeStatusText -match '(?i)KMS') { 'KMS' } elseif ($clickToRun) { [string]$clickToRun.ProductReleaseIds } else { 'Unknown' })
                OfficeDetected = [bool]$officeDetected
                SuspiciousFindingCount = [int]@($crackFindings).Count
                ActivatorEvidenceCurrent = [bool](@($activatorFamilies).Count -gt 0)
                ActivatorEvidenceFamilies = @($activatorFamilies)
                PluginHighOrCriticalCount = $pluginHighCount
            })
        } else {
            $timelineWrite = Write-ToolLicenseTimelineEvent -EventType "ReportGenerated" -Source $reportModuleId -Data ([ordered]@{
                Mode=$Mode; SuspiciousFindingCount=[int]@($crackFindings).Count; PluginHighOrCriticalCount=$pluginHighCount
            })
            $timelineSnapshot = [pscustomobject][ordered]@{
                Written=[bool]$timelineWrite.Written; Changed=$false; Changes=@(); Sequence=[int]$timelineWrite.Sequence; Error=[string]$timelineWrite.Error
            }
        }
    } catch {
        $timelineSnapshot = [pscustomobject][ordered]@{
            Written=$false; Changed=$false; Changes=@(); Sequence=0; Error=(Get-ReportText "report.timeline.writeRejected" @($_.Exception.Message))
        }
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $timelineSnapshot.Error)
    }
}
$moduleOutputPaths = @(
    (Protect-ReportText $reportPath),
    (Protect-ReportText $jsonPath),
    (Protect-ReportText $xmlPath),
    (Protect-ReportText $manifestPath)
)
$moduleWarningCount = [int]@($manualReviewFindings).Count
$moduleSummaryText = Get-ReportText "report.text.070" @($Mode)
$moduleResult = Complete-ToolModuleInvocation -Invocation $moduleInvocation -ExitCode 0 -Summary $moduleSummaryText -OutputPaths $moduleOutputPaths -FindingCount ([int]@($crackFindings).Count) -WarningCount $moduleWarningCount
$moduleValidation = Test-ToolModuleResult -Result $moduleResult
if (-not $moduleValidation.Valid) { throw (Get-ReportText "report.moduleResultInvalid" @(($moduleValidation.Errors -join '; '))) }
$pluginAuditForExport = ConvertTo-ReportRedactedObject $pluginAudit
$timelineSnapshotForExport = ConvertTo-ReportRedactedObject $timelineSnapshot
$detailedInventory = [ordered]@{
    RenderedSectionCount = [int]$sectionCounter
    Assessment = @($assessmentRows)
    ActivatorFindings = @($crackFindings)
}
if ($wantHardware) {
    $detailedInventory.Hardware = [ordered]@{
        ComputerSystem = [ordered]@{
            Manufacturer=[string]$cs.Manufacturer; Model=[string]$cs.Model; SystemType=[string]$cs.SystemType
            TotalPhysicalMemoryBytes=$(if ($null -ne $cs.TotalPhysicalMemory) { [uint64]$cs.TotalPhysicalMemory } else { $null })
        }
        ComputerSystemProducts = @($systemProducts)
        BIOS = @($biosInventory)
        Baseboards = @($baseboards)
        Chassis = @($enclosures)
        Processors = @($processors)
        MemoryModules = @($memory)
        PhysicalDisks = @($disks)
        LogicalVolumes = @($volumes)
        Graphics = @($gpu)
        Monitors = @($monitors)
        Batteries = @($batteries)
        NetworkConfigurations = @($network)
        NetworkAdapters = @($adapters)
        Security = [ordered]@{
            TPM = $tpmState
            SecureBoot = $secureBootState
            BitLocker = $bitLockerState
        }
    }
}
if ($wantSoftware) {
    $detailedInventory.Software = [ordered]@{
        LegacyInstalledApplications = @($legacyApps)
        LegacyPreliminaryAssessment = @($legacySoftwareAudit)
        InstalledApplications = @($apps)
        PrimaryApplications = @($primaryApps)
        SystemApplications = @($systemApps)
        ThirdPartyApplications = @($thirdPartyApps)
        ThirdPartyAssessment = @($thirdPartyAudit)
        ThirdPartyReviewItems = @($thirdPartyReview)
        ThirdPartyRemediationCandidates = @($thirdPartyAudit | Where-Object { [bool]$_.StrongTechnicalEvidence -and [string]$_.PSObject.Properties[$vendorScopeColumn].Value -in @('Adobe','Autodesk') })
        ParallelVersions = @($parallelVersions)
        StartupEntries = @($startup)
        ThirdPartyAutoruns = @($thirdPartyAutoruns)
        Services = @($serviceInventory)
        ThirdPartyServices = @($thirdPartyServices)
        EnabledScheduledTasks = @($tasks)
        ThirdPartyScheduledTasks = @($thirdPartyTasks)
        SpecificFindings = @($crackFindings)
        ManualReviewFindings = @($manualReviewFindings)
        SoftwareCatalog = $(if ($softwareCatalog) { [ordered]@{
            Source=[string]$softwareCatalog.CatalogSource
            Version=[string]$softwareCatalog.CatalogVersion
            RuleCount=[int]@($softwareCatalog.Products).Count
            Sha256=[string]$softwareCatalog.CatalogSha256
            SignatureValid=[bool]$softwareCatalog.CatalogSignatureValid
            SignatureFile=$(if (-not [string]::IsNullOrWhiteSpace([string]$softwareCatalog.CatalogSignaturePath)) { [IO.Path]::GetFileName([string]$softwareCatalog.CatalogSignaturePath) } else { '' })
            TrustedForDecisiveEvidence=[bool](Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $softwareCatalog)
        } } else { $null })
        InventoryMetadata = Get-ToolSoftwareInventoryMetadata -Applications $completeSoftwareInventory -Catalog $softwareCatalog
    }
}
$detailedInventoryForExport = ConvertTo-ReportRedactedObject (ConvertTo-ReportLocalizedExportObject $detailedInventory)
if ($detailedInventoryForExport.PSObject.Properties['ActivatorFindings']) {
    $localizedActivatorFindings = $detailedInventoryForExport.ActivatorFindings
    $detailedInventoryForExport.ActivatorFindings = if (@($crackFindings).Count -eq 0) {
        [object[]]@()
    } else {
        [object[]]@($localizedActivatorFindings)
    }
}
$summary = New-ToolReportEnvelope -ReportKind "InventoryAndLicense" -ToolVersion $ToolVersion -Data ([ordered]@{
    ToolName = $ToolName
    Capabilities = $capabilityState
    Compatibility = $compatibilityState
    Localization = $localizationState
    OfflinePolicy = $offlinePolicyState
    ModuleContract = $moduleContractState
    ModuleResult = $moduleResult
    ComputerName = $reportComputer
    CreatedAt = $started.ToString("o")
    Mode = $Mode
    Culture = $Culture
    OfflineMode = [bool]$script:reportOfflineMode
    HtmlReport = Protect-ReportText $reportPath
    PdfReport = ""
    WindowsStatus = [string]$windowsSummaryStatus
    WindowsChannel = [string]$windowsSummaryChannel
    WindowsConclusionCode = [string]$windowsVerdict.Code
    WindowsConclusion = [string]$windowsVerdict.Conclusion
    WindowsVerificationLevel = [string]$windowsVerdict.VerificationLevel
    OfficeStatus = [string]$officeSummaryStatus
    OfficeDetected = [bool]$officeDetected
    OfficeConclusionCode = [string]$officeVerdict.Code
    OfficeConclusion = [string]$officeVerdict.Conclusion
    OfficeVerificationLevel = [string]$officeVerdict.VerificationLevel
    SuspiciousFindingCount = [int]@($crackFindings).Count
    ManualReviewFindingCount = [int]@($manualReviewFindings).Count
    ThirdPartyApplicationCount = $thirdPartyCount
    ThirdPartyReviewCount = $thirdPartyReviewCount
    ThirdPartyHighSeverityCount = $thirdPartyHighCount
    SoftwareNonGenuineCount = $(if ($wantSoftware) { [int]@($apps | Where-Object { $_.AssessmentCode -eq 'NonGenuine' }).Count } else { 0 })
    SoftwareSuspiciousCount = $(if ($wantSoftware) { [int]@($apps | Where-Object { $_.AssessmentCode -eq 'Suspicious' }).Count } else { 0 })
    SoftwareIntegrityCompromisedCount = $(if ($wantSoftware) { [int]@($apps | Where-Object { $_.AssessmentCode -eq 'IntegrityCompromised' }).Count } else { 0 })
    SoftwareSystemComponentCount = $(if ($wantSoftware) { [int]@($systemApps).Count } else { 0 })
    SoftwareUnverifiedCount = $(if ($wantSoftware) { [int]@($apps | Where-Object { $_.AssessmentCode -in @('Unverified','TrialOrUnverified') }).Count } else { 0 })
    PluginAudit = $pluginAuditForExport
    Timeline = $timelineSnapshotForExport
    DetailedInventory = $detailedInventoryForExport
    Redacted = [bool]$RedactSensitive
    Privacy = if ($RedactSensitive) {
        Get-ReportText "report.text.071"
    } else {
        Get-ReportText "report.text.072"
    }
})
$summaryValidation = Test-ToolReportEnvelope -Report $summary -ExpectedReportKind "InventoryAndLicense" -ExpectedToolVersion $ToolVersion
if (-not $summaryValidation.Valid) { throw (Get-ReportText "report.jsonSchemaInvalid" @(($summaryValidation.Errors -join '; '))) }
Write-Host (Get-ReportText "report.progress.export")
$package = Export-ToolReportPackage -Report $summary -HtmlContent $html -PdfHtmlContent $detailedHtml -BasePath $reportBasePath -IncludePdf:$Pdf -RedactPaths:$RedactSensitive
Write-Host $DeveloperCredit
Write-Host (Get-ReportText "report.output.html" @($package.HtmlPath))
if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host (Get-ReportText "report.output.pdf" @($package.PdfPath)) }
elseif ($Pdf) { Write-Host (Get-ReportText "report.output.pdfFailed" @($package.Pdf.Error)) }
Write-Host (Get-ReportText "report.output.json" @($package.JsonPath))
Write-Host (Get-ReportText "report.output.xml" @($package.XmlPath))
Write-Host (Get-ReportText "report.output.manifest" @($package.ManifestPath))
[void](Write-ToolLog -Level "INFO" -Event "Report.Complete" -Message (Get-ReportText "report.log.completed" @($Mode)) -DurationMs ([long][Math]::Round(((Get-Date) - $started).TotalMilliseconds)) -Data ([ordered]@{
    ModuleId = $moduleResult.ModuleId
    InvocationId = $moduleResult.InvocationId
    ModuleStatus = $moduleResult.Status
    Mode = $Mode
    Culture = $Culture
    OfflineMode = [bool]$script:reportOfflineMode
    Redacted = [bool]$RedactSensitive
    SuspiciousFindingCount = [int]@($crackFindings).Count
    ManualReviewFindingCount = [int]@($manualReviewFindings).Count
    PdfStatus = [string]$summary.Export.PdfStatus
    PdfEngine = [string]$summary.Export.PdfEngine
    PdfPath = [string]$summary.Export.PdfPath
    PdfError = [string]$summary.Export.PdfError
}))
if (-not $NoOpen) {
    $selectPath = $package.HtmlPath
    Start-Process -FilePath $selectPath
}
