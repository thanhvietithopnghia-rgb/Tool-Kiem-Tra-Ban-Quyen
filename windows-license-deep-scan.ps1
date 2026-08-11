param(
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra"),
    [string]$ApprovedKmsServerFile = "",
    [string]$DecisionFile = "",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$toolVersion = "4.8"
$releaseVersion = "4.8.0.0"
$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-DeepText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-DeepText "common.powerShellRequired" @(3)); exit 10 }
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-DeepText "common.missingDependency" @("Tool-Runtime.ps1")) }
    if (-not (Test-Path -LiteralPath $reportSchemaHelper -PathType Leaf)) { throw (Get-DeepText "common.missingDependency" @("Tool-ReportSchema.ps1")) }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw (Get-DeepText "common.missingDependency" @("Tool-ReportExport.ps1")) }
    . $runtimeHelper
    . $reportSchemaHelper
    . $reportExportHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "SilentlyContinue"
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }

$statusStrong = Get-DeepText "deepReport.status.strong"
$statusClear = Get-DeepText "deepReport.status.clear"
$statusReview = Get-DeepText "deepReport.status.review"
$statusUnverified = Get-DeepText "deepReport.status.unverified"

function Safe-Cim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2")
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
        }
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
    } catch {
        try { return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop) }
        catch { return @() }
    }
}

function Get-CompatibleScheduledTaskRows {
    $firstError = ""
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            return @(Get-ScheduledTask -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name=([string]$_.TaskPath + [string]$_.TaskName); Actions=[string]($_.Actions | Out-String) }
            })
        } catch { $firstError = $_.Exception.Message }
    }
    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw (Get-DeepText "deepReport.scheduled.invalidCsv") }
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($row in @($csvLines | ConvertFrom-Csv)) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $name = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if ($name) { [void]$rows.Add([pscustomobject]@{ Name=$name; Actions=($values -join " | ") }) }
        }
        if ($rows.Count -eq 0) { throw (Get-DeepText "deepReport.scheduled.parseFailed") }
        return $rows.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        throw (Get-DeepText "deepReport.scheduled.scanFailed" @($detail))
    }
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

if (-not (Test-Administrator)) {
    if (-not [string]::IsNullOrWhiteSpace($DecisionFile)) {
        $parent = Split-Path -Parent $DecisionFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $accessDeniedDecision = New-ToolReportEnvelope -ReportKind "DeepScanDecision" -ToolVersion $toolVersion -Data ([ordered]@{
            AccessDenied = $true
            Overall = Get-DeepText "deepReport.accessDeniedOverall"
            HighCount = 0
            ReviewCount = 0
            ReportPath = ""
        })
        $accessDeniedDecision | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
    }
    Write-Host (Get-DeepText "deepReport.accessDeniedMessage")
    exit 20
}

function Protect-Text($Value) {
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if (-not $RedactSensitive) { return $text }
    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if ($profilePath) { $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME, $kmsServer) + @($approvedKmsServers)) {
        if ($secret) {
            $secretPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $secretPattern, (Get-DeepText "report.redaction.value"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$part(?:\.$part){3}(?![0-9.])", (Get-DeepText "report.redaction.ip"))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-DeepText "report.redaction.mac"))
    return $text
}

function Html {
    param($Value)
    $safeValue = Protect-Text $Value
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue)
    }
}

function Get-Channel {
    param($License)
    if (-not $License) { return Get-DeepText "common.unknown" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return Get-DeepText "common.unknown"
}

function New-Result {
    param([int]$Id, [string]$Name, [string]$Status, [string]$Evidence, [string]$Recommendation)
    return [pscustomobject]@{
        Id = $Id
        Name = $Name
        Status = $Status
        Evidence = $Evidence
        Recommendation = $Recommendation
    }
}

function Get-SignatureSummary {
    param([object[]]$Paths)
    $items = New-Object System.Collections.Generic.List[string]
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { return Get-DeepText "deepReport.signature.unsupported" }
    foreach ($path in @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            $signer = if ($signature.SignerCertificate.Subject) { $signature.SignerCertificate.Subject } else { Get-DeepText "deepReport.signature.noCertificate" }
            $items.Add("$([IO.Path]::GetFileName($path)): $($signature.Status); $signer")
        } catch { $items.Add((Get-DeepText "deepReport.signature.readFailed" @([IO.Path]::GetFileName($path)))) }
    }
    if ($items.Count -eq 0) { return Get-DeepText "deepReport.signature.noPaths" }
    return ($items -join " | ")
}

function Mask-Key {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return Get-DeepText "common.notFound" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return Get-DeepText "deepReport.detected" }
    return "*****-*****-*****-*****-" + $compact.Substring($compact.Length - 5)
}

$approvedKmsServers = @()
if (Test-Path -LiteralPath $ApprovedKmsServerFile) {
    $approvedKmsServers = @(Get-Content -LiteralPath $ApprovedKmsServerFile | ForEach-Object {
        ($_ -replace "#.*$", "").Trim().ToLowerInvariant()
    } | Where-Object { $_ })
}

function Test-ApprovedKms {
    param([string]$Server)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    foreach ($approved in $approvedKmsServers) {
        $item = $approved
        if ($item -match "^([^:]+):\d+$") { $item = $matches[1] }
        if ($candidate -eq $item) { return $true }
    }
    return $false
}

function Test-LicenseHostsBlockLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.TrimStart().StartsWith("#")) { return $false }
    if ($Line -notmatch "(?i)^\s*(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+") { return $false }
    $licenseHostPattern = "(?i)(microsoft|windows|office|sls\.microsoft|activation\.sls|genuine|licensing).*(activation|validation|sls|genuine|licensing)|" +
        "(activation|validation|sls|genuine|licensing).*(microsoft|windows|office)"
    return [bool]($Line -match $licenseHostPattern)
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$started = Get-Date
$stamp = $started.ToString("yyyyMMdd_HHmmss_fff")
$reportMachine = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
$reportPath = Join-Path $OutputDir "BaoCao_BanQuyenWindows_ChuyenSau_${reportMachine}_$stamp.html"
$pdfPath = [IO.Path]::ChangeExtension($reportPath, ".pdf")
$manifestPath = [IO.Path]::ChangeExtension($reportPath, $null) + "-SHA256SUMS.txt"
$results = New-Object System.Collections.Generic.List[object]

$currentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
$edition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { Get-DeepText "common.unknown" }
$installDate = Get-DeepText "common.unknown"
$os = Safe-Cim Win32_OperatingSystem | Select-Object -First 1
if ($os.InstallDate) {
    try { $installDate = ([DateTime]$os.InstallDate).ToString('yyyy-MM-dd') }
    catch { $installDate = [string]$os.InstallDate }
}

$service = Safe-Cim SoftwareLicensingService | Select-Object -First 1
$oemKey = if ($service) { [string]$service.OA3xOriginalProductKey } else { "" }
$oemMasked = Mask-Key $oemKey
$oemPresent = -not [string]::IsNullOrWhiteSpace($oemKey)

$licenses = Safe-Cim SoftwareLicensingProduct | Where-Object {
    $_.PartialProductKey -and $_.Name -match "Windows" -and
    (-not $_.ApplicationID -or [string]$_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f')
}
$activeLicense = $licenses | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$licenseForAnalysis = if ($activeLicense) { $activeLicense } else { $licenses | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
$isActivated = [bool]$activeLicense
$channel = Get-Channel $licenseForAnalysis
$partialKey = if ($licenseForAnalysis.PartialProductKey) { [string]$licenseForAnalysis.PartialProductKey } else { Get-DeepText "common.unknown" }
$kmsServer = if ($licenseForAnalysis.KeyManagementServiceMachine) { [string]$licenseForAnalysis.KeyManagementServiceMachine } else { "" }

$slmgr = Get-ToolNativeSystemPath "slmgr.vbs"
$xprText = ""
if (Test-Path -LiteralPath $slmgr) {
    $xprText = (& $nativeCscriptPath //nologo $slmgr /xpr 2>$null) -join "`n"
}

# 1. KMS server/configuration
if ($channel -eq "KMS") {
    $knownPublicPattern = "(?i)^(127\.0\.0\.1|0\.0\.0\.0|localhost)$|massgrave|kms\.loli|kms\.msgang|kms\.digiboy|kms\.03k|kms\.tee"
    if ($kmsServer -match $knownPublicPattern) {
        $results.Add((New-Result 1 (Get-DeepText "deepReport.group.kms") $statusStrong (Get-DeepText "deepReport.kms.public" @($kmsServer)) (Get-DeepText "deepReport.kms.publicRecommendation")))
    } elseif (Test-ApprovedKms $kmsServer) {
        $results.Add((New-Result 1 (Get-DeepText "deepReport.group.kms") $statusClear (Get-DeepText "deepReport.kms.approved" @($kmsServer)) (Get-DeepText "deepReport.kms.approvedRecommendation")))
    } else {
        $shownServer = if ($kmsServer) { $kmsServer } else { Get-DeepText "deepReport.kms.serverUnreadable" }
        $results.Add((New-Result 1 (Get-DeepText "deepReport.group.kms") $statusReview (Get-DeepText "deepReport.kms.unapproved" @($shownServer)) (Get-DeepText "deepReport.kms.unapprovedRecommendation")))
    }
} else {
    $results.Add((New-Result 1 (Get-DeepText "deepReport.group.kms") $statusClear (Get-DeepText "deepReport.kms.currentChannel" @($channel)) (Get-DeepText "deepReport.kms.channelRecommendation")))
}

# 2. Services/processes/history markers. History content is never copied to the report.
$activatorRegex = "(?i)(kmspico|kmsauto|auto[\s._-]*kms|kms[\s._-]*vl(?:[\s._-]*all)?|aact|sppextcomobj(?:hook|patcher)|spp[\s._-]*(?:hook|patcher)|microsoft[\s_-]+toolkit|hwidgen|massgrave|mas[\s._-]*aio|tsforge|ohook|digital license activation)"
$serviceHits = @(Safe-Cim Win32_Service | Where-Object {
    $_.Name -match $activatorRegex -or $_.DisplayName -match $activatorRegex -or $_.PathName -match $activatorRegex
})
$processHits = @(Get-Process | Where-Object { $_.ProcessName -match $activatorRegex })
$runtimePaths = @($serviceHits | Select-Object -ExpandProperty PathName) + @($processHits | Select-Object -ExpandProperty Path)
$historyHitCount = 0
$historyPath = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
if (Test-Path -LiteralPath $historyPath) {
    $historyRegex = "(?i)(massgrave|get\.activated\.win|kmspico|kmsauto|kms[\s._-]*vl(?:[\s._-]*all)?|hwidgen|mas[\s._-]*aio|tsforge|ohook|microsoft[\s_-]+toolkit|irm\s+https?://.+\|\s*iex)"
    $historyHitCount = @((Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue) | Where-Object { $_ -match $historyRegex }).Count
}
$runtimeCount = $serviceHits.Count + $processHits.Count
if ($runtimeCount -gt 0) {
    $names = @($serviceHits | Select-Object -ExpandProperty Name) + @($processHits | Select-Object -ExpandProperty ProcessName)
    $signatureSummary = Get-SignatureSummary $runtimePaths
    $results.Add((New-Result 2 (Get-DeepText "deepReport.group.activator") $statusStrong (Get-DeepText "deepReport.activator.runtime" @(($names -join ', '), $historyHitCount, $signatureSummary)) (Get-DeepText "deepReport.activator.runtimeRecommendation")))
} elseif ($historyHitCount -gt 0) {
    $results.Add((New-Result 2 (Get-DeepText "deepReport.group.activator") $statusClear (Get-DeepText "deepReport.activator.historyOnly" @($historyHitCount)) (Get-DeepText "deepReport.activator.historyRecommendation")))
} else {
    $results.Add((New-Result 2 (Get-DeepText "deepReport.group.activator") $statusClear (Get-DeepText "deepReport.activator.none") (Get-DeepText "deepReport.noAutomaticAction")))
}

# 3. KMS38/expiration pattern
if ($channel -eq "KMS" -and $xprText -match "2038") {
    $results.Add((New-Result 3 (Get-DeepText "deepReport.group.kms38") $statusStrong (Get-DeepText "deepReport.kms38.detected") (Get-DeepText "deepReport.kms38.recommendation")))
} elseif ($channel -eq 'KMS') {
    $graceMinutes = if ($licenseForAnalysis -and $licenseForAnalysis.PSObject.Properties['GracePeriodRemaining']) { [int]$licenseForAnalysis.GracePeriodRemaining } else { -1 }
    $graceDays = if ($graceMinutes -ge 0) { [Math]::Round($graceMinutes / 1440.0, 1) } else { -1 }
    $kmsLifecycleStatus = if (Test-ApprovedKms $kmsServer) { $statusClear } else { $statusReview }
    $results.Add((New-Result 3 (Get-DeepText 'deepReport.group.kmsLifecycle') $kmsLifecycleStatus `
        (Get-DeepText 'deepReport.kmsLifecycle.detected' @($graceMinutes, $graceDays)) `
        (Get-DeepText 'deepReport.kmsLifecycle.recommendation')))
} else {
    $summaryXpr = ($xprText -replace "\s+", " ").Trim()
    if ($summaryXpr.Length -gt 180) { $summaryXpr = $summaryXpr.Substring(0,180) + "..." }
    $results.Add((New-Result 3 (Get-DeepText "deepReport.group.kms38") $statusClear $summaryXpr (Get-DeepText "deepReport.activationNotEntitlement")))
}

# 4. Generic key/digital-license logic: informational only, never treated as proof of piracy.
$genericLast5 = @("3V66T","T83GX","YKHCF","TXYCV","8HVX7","233PK","8XC4K","WFG99","6F4BT","YTDFH","2YT43","H8Q99","7CFBY","VCFB2","J8JXD","8HV2C","PDQGT","YY74H","2YV77","6Q84J")
if ($genericLast5 -contains $partialKey) {
    $oemText = if ($oemPresent) { Get-DeepText "deepReport.key.oemPresent" @($oemMasked) } else { Get-DeepText "deepReport.key.oemMissing" }
    $results.Add((New-Result 4 (Get-DeepText "deepReport.group.keyLogic") $statusReview (Get-DeepText "deepReport.key.generic" @($partialKey, $oemText)) (Get-DeepText "deepReport.key.genericRecommendation")))
} else {
    $results.Add((New-Result 4 (Get-DeepText "deepReport.group.keyLogic") $statusClear (Get-DeepText "deepReport.key.normal" @($channel, $partialKey, $oemMasked)) (Get-DeepText "deepReport.key.normalRecommendation")))
}

# 5. Suspicious activator folders
$folderCandidates = @(
    (Join-Path $env:windir "KMS"),
    (Join-Path $env:windir "AutoKMS"),
    (Join-Path $env:ProgramData "KMSAutoS"),
    (Join-Path $env:SystemDrive "KMSpico"),
    (Join-Path $env:SystemDrive "AAct")
) | Where-Object { $_ }
$folderHits = @($folderCandidates | Where-Object { Test-Path -LiteralPath $_ })
if ($folderHits.Count -gt 0) {
    $results.Add((New-Result 5 (Get-DeepText "deepReport.group.folders") $statusStrong ($folderHits -join "; ") (Get-DeepText "deepReport.folders.recommendation")))
} else {
    $results.Add((New-Result 5 (Get-DeepText "deepReport.group.folders") $statusClear (Get-DeepText "deepReport.folders.none") (Get-DeepText "deepReport.noAutomaticAction")))
}

# 6. Scheduled tasks
$taskHits = @()
$taskScanError = ""
try {
    $taskHits = @(Get-CompatibleScheduledTaskRows | Where-Object { $_.Name -match $activatorRegex -or $_.Actions -match $activatorRegex })
} catch { $taskScanError = $_.Exception.Message }
if ($taskScanError) {
    $results.Add((New-Result 6 (Get-DeepText "deepReport.group.tasks") $statusUnverified $taskScanError (Get-DeepText "deepReport.tasks.errorRecommendation")))
} elseif ($taskHits.Count -gt 0) {
    $taskNames = @($taskHits | ForEach-Object { [string]$_.Name })
    $results.Add((New-Result 6 (Get-DeepText "deepReport.group.tasks") $statusStrong ($taskNames -join "; ") (Get-DeepText "deepReport.tasks.detectedRecommendation")))
} else {
    $results.Add((New-Result 6 (Get-DeepText "deepReport.group.tasks") $statusClear (Get-DeepText "deepReport.tasks.none") (Get-DeepText "deepReport.noAutomaticAction")))
}

# 7. Registry policy and hosts; report only, never overwrite either source.
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
$policy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
$policyNames = New-Object System.Collections.Generic.List[string]
if ($policy.KeyManagementServiceName) { $policyNames.Add("KeyManagementServiceName") }
if ($policy.KeyManagementServicePort) { $policyNames.Add("KeyManagementServicePort") }
if ([int]$policy.NoGenTicket -eq 1) { $policyNames.Add("NoGenTicket=1") }
$hostsPath = Get-ToolNativeSystemPath "drivers\etc\hosts"
$hostsHitCount = 0
if (Test-Path -LiteralPath $hostsPath) {
    $hostsHitCount = @((Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue) | Where-Object {
        Test-LicenseHostsBlockLine $_
    }).Count
}
if ($policyNames.Count -gt 0 -or $hostsHitCount -gt 0) {
    $policyEvidence = if ($policyNames.Count) { $policyNames -join ', ' } else { Get-DeepText "deepReport.registry.noSuspiciousPolicy" }
    $evidence = Get-DeepText "deepReport.registry.evidence" @($policyEvidence, $hostsHitCount)
    $results.Add((New-Result 7 (Get-DeepText "deepReport.group.registry") $statusReview $evidence (Get-DeepText "deepReport.registry.recommendation")))
} else {
    $results.Add((New-Result 7 (Get-DeepText "deepReport.group.registry") $statusClear (Get-DeepText "deepReport.registry.none") (Get-DeepText "deepReport.noAutomaticAction")))
}

$highCount = @($results | Where-Object { $_.Status -eq $statusStrong }).Count
$reviewCount = @($results | Where-Object { $_.Status -in @($statusReview, $statusUnverified) }).Count
$overall = if ($highCount -gt 0) {
    Get-DeepText "deepReport.overall.strong"
} elseif ($reviewCount -gt 0) {
    Get-DeepText "deepReport.overall.review"
} else {
    Get-DeepText "deepReport.overall.clear"
}
$reviewItems = @($results | Where-Object { $_.Status -in @($statusReview, $statusUnverified, $statusStrong) } | ForEach-Object {
    [pscustomobject]@{
        Name = [string]$_.Name
        Status = [string]$_.Status
        Evidence = [string]$_.Evidence
        Recommendation = [string]$_.Recommendation
    }
})
$handlingGuidance = New-Object System.Collections.Generic.List[string]
if ($highCount -gt 0) {
    $handlingGuidance.Add((Get-DeepText "deepReport.guidance.strong"))
}
if (@($results | Where-Object { $_.Name -eq (Get-DeepText "deepReport.group.registry") -and $_.Evidence -match "NoGenTicket=1" }).Count -gt 0) {
    $handlingGuidance.Add((Get-DeepText "deepReport.guidance.noGenTicket"))
}
if ($reviewCount -gt 0 -and $handlingGuidance.Count -eq 0) {
    $handlingGuidance.Add((Get-DeepText "deepReport.guidance.review"))
}
if ($reviewCount -eq 0 -and $highCount -eq 0) {
    $handlingGuidance.Add((Get-DeepText "deepReport.guidance.clear"))
}

$reportColumns = @(
    "#",
    (Get-DeepText "deepReport.column.group"),
    (Get-DeepText "deepReport.column.status"),
    (Get-DeepText "deepReport.column.evidence"),
    (Get-DeepText "deepReport.column.recommendation")
)
$reportRows = @($results | ForEach-Object {
    $row = [ordered]@{}
    $row[$reportColumns[0]] = [string]$_.Id
    $row[$reportColumns[1]] = [string]$_.Name
    $row[$reportColumns[2]] = [string]$_.Status
    $row[$reportColumns[3]] = [string]$_.Evidence
    $row[$reportColumns[4]] = [string]$_.Recommendation
    [pscustomobject]$row
})
$licenseState = if ($isActivated) { Get-DeepText "deepReport.license.licensed" } else { Get-DeepText "deepReport.license.notLicensed" }
$summaryBody = "<p><strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.result'))</strong> $(ConvertTo-ToolHtmlText $overall)</p>" +
    "<p><strong>Windows:</strong> $(ConvertTo-ToolHtmlText "$productName - $edition")<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.installDate'))</strong> $(ConvertTo-ToolHtmlText $installDate)<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.licenseState'))</strong> $(ConvertTo-ToolHtmlText $licenseState)<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.channel'))</strong> $(ConvertTo-ToolHtmlText $channel)<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.lastFive'))</strong> $(ConvertTo-ToolHtmlText $partialKey)<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.summary.oemKey'))</strong> $(ConvertTo-ToolHtmlText $oemMasked)</p>"
$guidanceBody = "<ul>" + ((@($handlingGuidance) | ForEach-Object { "<li>$(ConvertTo-ToolHtmlText $_)</li>" }) -join "") + "</ul>" +
    "<p class='note'><strong>$(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.noteLabel'))</strong> $(ConvertTo-ToolHtmlText (Get-DeepText 'deepReport.note'))</p>"
$html = New-ToolProfessionalHtmlDocument `
    -Title (Get-DeepText "deepReport.title") `
    -Subtitle (Get-DeepText "deepReport.subtitle") `
    -Eyebrow (Get-DeepText "deepReport.eyebrow") `
    -Metadata @(
        [pscustomobject]@{Label=(Get-DeepText "deepReport.meta.computer");Value=$reportMachine},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.meta.time");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.meta.permission");Value=(Get-DeepText "deepReport.meta.adminReadOnly")},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.meta.privacy");Value=$(if ($RedactSensitive) { Get-DeepText "report.redacted" } else { Get-DeepText "deepReport.privacy.internal" })}
    ) `
    -Cards @(
        [pscustomobject]@{Label=(Get-DeepText "deepReport.card.result");Value=$overall;Tone=$(if ($highCount -gt 0) {"danger"} elseif ($reviewCount -gt 0) {"warning"} else {"ok"})},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.card.strong");Value=[string]$highCount;Tone=$(if ($highCount -gt 0) {"danger"} else {"ok"})},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.card.review");Value=[string]$reviewCount;Tone=$(if ($reviewCount -gt 0) {"warning"} else {"ok"})},
        [pscustomobject]@{Label=(Get-DeepText "deepReport.card.groups");Value=[string]$reportRows.Count;Tone="info"}
    ) `
    -Sections @(
        [pscustomobject]@{Title=(Get-DeepText "deepReport.section.overview");BodyHtml=$summaryBody},
        [pscustomobject]@{Title=(Get-DeepText "deepReport.section.results");BodyHtml=(ConvertTo-ToolHtmlTable -Rows $reportRows -Columns $reportColumns)},
        [pscustomobject]@{Title=(Get-DeepText "deepReport.section.guidance");BodyHtml=$guidanceBody}
    ) `
    -Footer "$(Get-DeepText 'report.footer') · v$releaseVersion" -Culture $Culture -OfflineMode $true
[IO.File]::WriteAllText($reportPath, $html, (New-Object Text.UTF8Encoding($false)))
if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $reportPath)) { throw (Get-DeepText "deepReport.offlineSafetyFailed") }
$pdfResult = Convert-ToolHtmlToPdf -HtmlPath $reportPath -PdfPath $pdfPath
$hashLines = @((Get-DeepText "deepReport.manifestHeader"))
foreach ($path in @($reportPath, $pdfPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { $hashLines += "$(Get-ToolSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))" }
}
[IO.File]::WriteAllLines($manifestPath, $hashLines, (New-Object Text.UTF8Encoding($false)))

$decision = New-ToolReportEnvelope -ReportKind "DeepScanDecision" -ToolVersion $toolVersion -Data ([ordered]@{
    AccessDenied = $false
    ReportPath = $reportPath
    PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
    Overall = $overall
    HighCount = $highCount
    ReviewCount = $reviewCount
    OemKeyPresent = $oemPresent
    ActiveChannel = $channel
    ReviewItems = $reviewItems
    HandlingGuidance = $handlingGuidance.ToArray()
})
$decisionValidation = Test-ToolReportEnvelope -Report $decision -ExpectedReportKind "DeepScanDecision" -ExpectedToolVersion $toolVersion
if (-not $decisionValidation.Valid) { throw (Get-DeepText "deepReport.schemaFailed" @(($decisionValidation.Errors -join '; '))) }
if (-not [string]::IsNullOrWhiteSpace($DecisionFile)) {
    $decision | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
}

Write-Host (Get-DeepText "common.reportPath" @($reportPath))
if ($pdfResult.Success) { Write-Host (Get-DeepText "deepReport.output.pdf" @($pdfPath)) } else { Write-Host (Get-DeepText "deepReport.pdfFailed" @($pdfResult.Error)) }
Write-Host (Get-DeepText "deepReport.resultHost" @($overall))
if (-not $NoOpen) { Start-Process -FilePath $reportPath }
exit 0
