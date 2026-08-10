param(
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra"),
    [string]$ApprovedKmsServerFile = "",
    [string]$DecisionFile = "",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
$reportSchemaHelper = Join-Path $PSScriptRoot "Tool-ReportSchema.ps1"
$reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationHelper
$env:TOOL_UI_CULTURE = $Culture
function Get-ForensicsText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments = @())
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}
if ($PSVersionTable.PSVersion.Major -lt 3) { Write-Host (Get-ForensicsText "common.powerShellRequired" @(3)); exit 10 }
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-ForensicsText "common.missingDependency" @("Tool-Runtime.ps1")) }
    if (-not (Test-Path -LiteralPath $reportSchemaHelper -PathType Leaf)) { throw (Get-ForensicsText "common.missingDependency" @("Tool-ReportSchema.ps1")) }
    if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw (Get-ForensicsText "common.missingDependency" @("Tool-ReportExport.ps1")) }
    . $runtimeHelper
    . $reportSchemaHelper
    . $reportExportHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeNetshPath = Get-ToolNativeSystemPath "netsh.exe"
    $nativeW32tmPath = Get-ToolNativeSystemPath "w32tm.exe"
} catch { Write-Host $_.Exception.Message; exit 12 }

$ErrorActionPreference = "SilentlyContinue"
$toolVersion = "4.8"
$releaseVersion = "4.8.0.0"
$scanStarted = Get-Date
if ([string]::IsNullOrWhiteSpace($ApprovedKmsServerFile)) { $ApprovedKmsServerFile = Join-Path $PSScriptRoot "approved-kms-servers.txt" }

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Write-DecisionFile($Value) {
    if ([string]::IsNullOrWhiteSpace($DecisionFile)) { return }
    $parent = Split-Path -Parent $DecisionFile
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $DecisionFile -Encoding UTF8
}

if (-not (Test-Administrator)) {
    Write-DecisionFile (New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
        AccessDenied = $true
        Overall = Get-ForensicsText "forensicsReport.accessDeniedOverall"
        RiskScore = 0
        RiskLevel = Get-ForensicsText "common.unknown"
        HighCount = 0
        ReviewCount = 0
        NewFindingCount = 0
        ReportPath = ""
        EvidenceFolder = ""
    }))
    Write-Host (Get-ForensicsText "forensicsReport.accessDeniedMessage")
    exit 20
}

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
                $execute = @($_.Actions | Select-Object -ExpandProperty Execute -ErrorAction SilentlyContinue) | Select-Object -First 1
                [pscustomobject]@{
                    Name=([string]$_.TaskPath + [string]$_.TaskName)
                    Actions=[string]($_.Actions | Out-String)
                    Execute=[string]$execute
                }
            })
        } catch { $firstError = $_.Exception.Message }
    }
    try {
        $schtasks = Get-ToolNativeSystemPath "schtasks.exe"
        $raw = @(& $schtasks /Query /FO CSV /V 2>&1)
        if ($LASTEXITCODE -ne 0) { throw (($raw | ForEach-Object { [string]$_ }) -join " | ") }
        $csvLines = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*"' })
        if ($csvLines.Count -lt 2) { throw (Get-ForensicsText "deepReport.scheduled.invalidCsv") }
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($row in @($csvLines | ConvertFrom-Csv)) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value })
            $name = [string]($values | Where-Object { $_ -match '^\\[^\\]+' } | Select-Object -First 1)
            if (-not $name) { continue }
            $actionText = ($values -join " | ")
            $execute = Get-ExecutablePath $actionText
            [void]$rows.Add([pscustomobject]@{ Name=$name; Actions=$actionText; Execute=$execute })
        }
        if ($rows.Count -eq 0) { throw (Get-ForensicsText "deepReport.scheduled.parseFailed") }
        return $rows.ToArray()
    } catch {
        $detail = if ($firstError) { "$firstError | $($_.Exception.Message)" } else { $_.Exception.Message }
        throw (Get-ForensicsText "deepReport.scheduled.scanFailed" @($detail))
    }
}

function Protect-Text($Value) {
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if (-not $RedactSensitive) { return $text }
    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if ($profilePath) { $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    $kmsNames = @($kmsServer) + @($script:approvedKmsServers)
    if ($officeKms) { $kmsNames += @($officeKms | ForEach-Object { [string]$_.KeyManagementServiceMachine }) }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME) + @($kmsNames)) {
        if ($secret) {
            $secretPattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $secretPattern, (Get-ForensicsText "report.redaction.value"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $part = '(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
    $text = [regex]::Replace($text, "(?<![0-9.])$part(?:\.$part){3}(?![0-9.])", (Get-ForensicsText "report.redaction.ip"))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-ForensicsText "report.redaction.mac"))
    return $text
}

function Html($Value) {
    $safeValue = Protect-Text $Value
    try { return [System.Net.WebUtility]::HtmlEncode([string]$safeValue) }
    catch {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode([string]$safeValue)
    }
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    try {
        if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
        $stream = [IO.File]::OpenRead($Path)
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "").ToUpperInvariant() }
            finally { $sha.Dispose() }
        } finally { $stream.Dispose() }
    } catch { return "" }
}

function Get-ExecutablePath([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return "" }
    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded -match '^\s*"([^"]+\.(exe|com|bat|cmd|ps1|vbs|dll))"') { return $matches[1] }
    if ($expanded -match '^\s*([^\s]+\.(exe|com|bat|cmd|ps1|vbs|dll))') { return $matches[1] }
    return ""
}

function Test-LicenseHostsBlockLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.TrimStart().StartsWith("#")) { return $false }
    if ($Line -notmatch "(?i)^\s*(127\.0\.0\.1|0\.0\.0\.0|::1)\s+\S+") { return $false }
    $licenseHostPattern = "(?i)(microsoft|windows|office|sls\.microsoft|activation\.sls|genuine|licensing).*(activation|validation|sls|genuine|licensing)|" +
        "(activation|validation|sls|genuine|licensing).*(microsoft|windows|office)"
    return [bool]($Line -match $licenseHostPattern)
}

function Get-FileEvidence([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return Get-ForensicsText "forensicsReport.file.notFound"
    }
    $signatureText = Get-ForensicsText "forensicsReport.file.unsupported"
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        $signer = if ($signature.SignerCertificate.Subject) { $signature.SignerCertificate.Subject } else { Get-ForensicsText "deepReport.signature.noCertificate" }
        $signatureText = "$($signature.Status); $signer"
    } catch { $signatureText = Get-ForensicsText "forensicsReport.file.signatureUnreadable" }
    $hash = Get-Sha256 $Path
    return Get-ForensicsText "forensicsReport.file.evidence" @($Path, $signatureText, $hash)
}

function Get-LicenseChannel($License) {
    if (-not $License) { return Get-ForensicsText "common.unknown" }
    $description = [string]$License.Description
    if ($description -match "VOLUME_KMSCLIENT|KMSCLIENT") { return "KMS" }
    if ($description -match "VOLUME_MAK|MAK") { return "MAK" }
    if ($description -match "OEM") { return "OEM" }
    if ($description -match "RETAIL") { return "Retail" }
    return Get-ForensicsText "common.unknown"
}

function Mask-Key([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return Get-ForensicsText "common.notFound" }
    $compact = ($Key -replace "[^A-Za-z0-9]", "").ToUpperInvariant()
    if ($compact.Length -lt 5) { return Get-ForensicsText "deepReport.detected" }
    return "*****-*****-*****-*****-" + $compact.Substring($compact.Length - 5)
}

function New-Finding {
    param(
        [string]$Id,
        [string]$Category,
        [ValidateSet("OK", "Info", "Review", "High")][string]$StatusCode,
        [int]$Score,
        [string]$Evidence,
        [string]$Recommendation
    )
    $status = switch ($StatusCode) {
        "High" { Get-ForensicsText "forensicsReport.status.high" }
        "Review" { Get-ForensicsText "forensicsReport.status.review" }
        "Info" { Get-ForensicsText "forensicsReport.status.info" }
        default { Get-ForensicsText "forensicsReport.status.ok" }
    }
    return [pscustomobject]@{
        Id = $Id
        Category = $Category
        StatusCode = $StatusCode
        Status = $status
        Score = [Math]::Max(0, $Score)
        Evidence = $Evidence
        Recommendation = $Recommendation
    }
}

function Add-Finding {
    param($Finding)
    $script:findings.Add($Finding)
}

function Test-ApprovedKms([string]$Server) {
    if ([string]::IsNullOrWhiteSpace($Server)) { return $false }
    $candidate = $Server.Trim().ToLowerInvariant()
    foreach ($approved in $script:approvedKmsServers) {
        $item = $approved
        if ($item -match "^([^:]+):\d+$") { $item = $matches[1] }
        if ($candidate -eq $item) { return $true }
    }
    return $false
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$stamp = $scanStarted.ToString("yyyyMMdd_HHmmss_fff")
$reportMachine = if ($RedactSensitive) { "AN_DANH" } else { $env:COMPUTERNAME }
$bundleName = "LicenseForensics_${reportMachine}_$stamp"
$bundleDir = Join-Path $OutputDir $bundleName
New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
$htmlPath = Join-Path $OutputDir "$bundleName.html"
$pdfPath = Join-Path $OutputDir "$bundleName.pdf"
$jsonPath = Join-Path $bundleDir "$bundleName.json"
$csvPath = Join-Path $bundleDir "$bundleName.csv"
$manifestPath = Join-Path $bundleDir "SHA256SUMS.txt"
$findings = New-Object System.Collections.Generic.List[object]

$approvedKmsServers = @()
if (Test-Path -LiteralPath $ApprovedKmsServerFile) {
    $approvedKmsServers = @(Get-Content -LiteralPath $ApprovedKmsServerFile | ForEach-Object {
        ($_ -replace "#.*$", "").Trim().ToLowerInvariant()
    } | Where-Object { $_ })
}

# 1. Trạng thái giấy phép Windows và kênh kích hoạt.
$licenses = @(Safe-Cim SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -match "Windows" })
$activeLicense = $licenses | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
$licenseForAnalysis = if ($activeLicense) { $activeLicense } else { $licenses | Sort-Object LicenseStatus -Descending | Select-Object -First 1 }
$channel = Get-LicenseChannel $licenseForAnalysis
$partialKey = if ($licenseForAnalysis.PartialProductKey) { [string]$licenseForAnalysis.PartialProductKey } else { Get-ForensicsText "common.unknown" }
$kmsServer = if ($licenseForAnalysis.KeyManagementServiceMachine) { [string]$licenseForAnalysis.KeyManagementServiceMachine } else { "" }
$knownPublicKms = "(?i)^(127\.0\.0\.1|0\.0\.0\.0|localhost)$|massgrave|kms\.loli|kms\.msgang|kms\.digiboy|kms\.03k|kms\.tee"
if (-not $activeLicense) {
    Add-Finding (New-Finding "WIN-LICENSE" (Get-ForensicsText "forensicsReport.category.windows") "Review" 8 (Get-ForensicsText "forensicsReport.windows.unlicensed" @($channel, $partialKey)) (Get-ForensicsText "forensicsReport.windows.unlicensedRecommendation"))
} elseif ($channel -eq "KMS" -and $kmsServer -match $knownPublicKms) {
    Add-Finding (New-Finding "WIN-LICENSE" (Get-ForensicsText "forensicsReport.category.windows") "High" 30 (Get-ForensicsText "forensicsReport.windows.publicKms" @($kmsServer)) (Get-ForensicsText "forensicsReport.windows.publicKmsRecommendation"))
} elseif ($channel -eq "KMS" -and -not (Test-ApprovedKms $kmsServer)) {
    Add-Finding (New-Finding "WIN-LICENSE" (Get-ForensicsText "forensicsReport.category.windows") "Review" 12 (Get-ForensicsText "forensicsReport.windows.unapprovedKms" @($kmsServer)) (Get-ForensicsText "forensicsReport.windows.unapprovedKmsRecommendation"))
} else {
    $kmsNote = if ($channel -eq "KMS") { Get-ForensicsText "forensicsReport.windows.approvedKms" @($kmsServer) } else { Get-ForensicsText "forensicsReport.windows.channel" @($channel) }
    Add-Finding (New-Finding "WIN-LICENSE" (Get-ForensicsText "forensicsReport.category.windows") "OK" 0 (Get-ForensicsText "forensicsReport.windows.licensed" @($kmsNote, $partialKey)) (Get-ForensicsText "forensicsReport.windows.licensedRecommendation"))
}

# 2. Key OEM firmware và logic edition.
$licensingService = Safe-Cim SoftwareLicensingService | Select-Object -First 1
$oemKey = if ($licensingService) { [string]$licensingService.OA3xOriginalProductKey } else { "" }
$oemMasked = Mask-Key $oemKey
$currentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
$edition = if ($currentVersion.EditionID) { [string]$currentVersion.EditionID } else { Get-ForensicsText "common.unknown" }
if ($oemKey) {
    Add-Finding (New-Finding "OEM-FIRMWARE" (Get-ForensicsText "forensicsReport.category.oem") "Info" 0 (Get-ForensicsText "forensicsReport.oem.found" @($oemMasked, $edition)) (Get-ForensicsText "forensicsReport.oem.foundRecommendation"))
} else {
    Add-Finding (New-Finding "OEM-FIRMWARE" (Get-ForensicsText "forensicsReport.category.oem") "Info" 0 (Get-ForensicsText "forensicsReport.oem.missing") (Get-ForensicsText "forensicsReport.oem.missingRecommendation"))
}

# 3. Tính toàn vẹn thành phần cấp phép cốt lõi.
$coreFiles = @(
    (Get-ToolNativeSystemPath "sppsvc.exe"),
    (Get-ToolNativeSystemPath "sppcomapi.dll"),
    (Get-ToolNativeSystemPath "slc.dll")
)
$coreEvidence = New-Object System.Collections.Generic.List[string]
$coreBad = 0
$coreMissing = 0
foreach ($coreFile in $coreFiles) {
    if (-not (Test-Path -LiteralPath $coreFile -PathType Leaf)) {
        $coreMissing++
        $coreEvidence.Add((Get-ForensicsText "forensicsReport.core.missing" @($coreFile)))
        continue
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $coreFile
    $subject = if ($signature.SignerCertificate.Subject) { [string]$signature.SignerCertificate.Subject } else { "" }
    if ($signature.Status -ne "Valid" -or $subject -notmatch "Microsoft") { $coreBad++ }
    $coreEvidence.Add((Get-FileEvidence $coreFile))
}
$sppService = Get-Service -Name sppsvc -ErrorAction SilentlyContinue
$sppStart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\sppsvc" -ErrorAction SilentlyContinue).Start
if ($coreBad -gt 0 -or $coreMissing -gt 0) {
    Add-Finding (New-Finding "CORE-INTEGRITY" (Get-ForensicsText "forensicsReport.category.core") "High" 35 (($coreEvidence -join "`n") + "`n" + (Get-ForensicsText "forensicsReport.core.serviceEvidence" @($sppService.Status, $sppStart))) (Get-ForensicsText "forensicsReport.core.badRecommendation"))
} elseif ($sppStart -eq 4) {
    Add-Finding (New-Finding "CORE-INTEGRITY" (Get-ForensicsText "forensicsReport.category.core") "High" 25 (($coreEvidence -join "`n") + "`n" + (Get-ForensicsText "forensicsReport.core.serviceDisabled")) (Get-ForensicsText "forensicsReport.core.disabledRecommendation"))
} else {
    Add-Finding (New-Finding "CORE-INTEGRITY" (Get-ForensicsText "forensicsReport.category.core") "OK" 0 (($coreEvidence -join "`n") + "`n" + (Get-ForensicsText "forensicsReport.core.serviceEvidence" @($sppService.Status, $sppStart))) (Get-ForensicsText "forensicsReport.noChange"))
}

# 4. Dấu vết activator trong tiến trình, dịch vụ, task và startup.
$activatorRegex = "(?i)(kmspico|kmsauto|autokms|aact|sppextcomobj(?:hook|patcher)|microsoft toolkit|hwidgen|massgrave|digital license activation|get\.activated\.win)"
$artifactRows = New-Object System.Collections.Generic.List[object]
foreach ($serviceItem in @(Safe-Cim Win32_Service | Where-Object { $_.Name -match $activatorRegex -or $_.DisplayName -match $activatorRegex -or $_.PathName -match $activatorRegex })) {
    $path = Get-ExecutablePath ([string]$serviceItem.PathName)
    $artifactRows.Add([pscustomobject]@{ Type=(Get-ForensicsText "forensicsReport.artifact.service"); Name=$serviceItem.Name; Path=$path; Evidence=(Get-FileEvidence $path) })
}
foreach ($processItem in @(Get-Process | Where-Object { $_.ProcessName -match $activatorRegex })) {
    $path = ""
    try { $path = [string]$processItem.Path } catch {}
    $artifactRows.Add([pscustomobject]@{ Type=(Get-ForensicsText "forensicsReport.artifact.process"); Name=$processItem.ProcessName; Path=$path; Evidence=(Get-FileEvidence $path) })
}
$taskScanWarning = ""
try {
    foreach ($task in @(Get-CompatibleScheduledTaskRows | Where-Object { $_.Name -match $activatorRegex -or $_.Actions -match $activatorRegex })) {
        $artifactRows.Add([pscustomobject]@{ Type=(Get-ForensicsText "forensicsReport.artifact.task"); Name=[string]$task.Name; Path=[string]$task.Execute; Evidence=(Get-FileEvidence ([string]$task.Execute)) })
    }
} catch { $taskScanWarning = $_.Exception.Message }
foreach ($startup in @(Safe-Cim Win32_StartupCommand | Where-Object { $_.Name -match $activatorRegex -or $_.Command -match $activatorRegex })) {
    $path = Get-ExecutablePath ([string]$startup.Command)
    $artifactRows.Add([pscustomobject]@{ Type=(Get-ForensicsText "forensicsReport.artifact.startup"); Name=$startup.Name; Path=$path; Evidence=(Get-FileEvidence $path) })
}
$artifactFolders = @(
    (Join-Path $env:windir "KMS"), (Join-Path $env:windir "AutoKMS"),
    (Join-Path $env:ProgramData "KMSAutoS"), (Join-Path $env:SystemDrive "KMSpico"),
    (Join-Path $env:SystemDrive "AAct")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
if ($artifactRows.Count -gt 0 -or $artifactFolders.Count -gt 0) {
    $artifactText = @($artifactRows | ForEach-Object { Get-ForensicsText "forensicsReport.artifact.evidence" @($_.Type, $_.Name, $_.Evidence) }) + @($artifactFolders | ForEach-Object { Get-ForensicsText "forensicsReport.artifact.folder" @($_) })
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" (Get-ForensicsText "forensicsReport.category.activator") "High" 35 ($artifactText -join "`n") (Get-ForensicsText "forensicsReport.activator.detectedRecommendation"))
} elseif ($taskScanWarning) {
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" (Get-ForensicsText "forensicsReport.category.activator") "Review" 8 $taskScanWarning (Get-ForensicsText "deepReport.tasks.errorRecommendation"))
} else {
    Add-Finding (New-Finding "ACTIVATOR-PERSISTENCE" (Get-ForensicsText "forensicsReport.category.activator") "OK" 0 (Get-ForensicsText "forensicsReport.activator.none") (Get-ForensicsText "deepReport.noAutomaticAction"))
}

# 5. Registry, hosts và proxy có thể can thiệp kích hoạt.
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
$policy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
$policyItems = @()
if ($policy.KeyManagementServiceName) { $policyItems += "KeyManagementServiceName=$($policy.KeyManagementServiceName)" }
if ($policy.KeyManagementServicePort) { $policyItems += "KeyManagementServicePort=$($policy.KeyManagementServicePort)" }
if ([int]$policy.NoGenTicket -eq 1) { $policyItems += "NoGenTicket=1" }
$hostsPath = Get-ToolNativeSystemPath "drivers\etc\hosts"
$hostsHits = @()
if (Test-Path -LiteralPath $hostsPath) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue) {
        $lineNumber++
        if (Test-LicenseHostsBlockLine $line) {
            $hostsHits += Get-ForensicsText "forensicsReport.network.hostsLine" @($lineNumber)
        }
    }
}
$winHttpProxy = (& $nativeNetshPath winhttp show proxy 2>$null) -join " "
$proxyConfigured = $winHttpProxy -and $winHttpProxy -notmatch "(?i)(Direct access|truy cập trực tiếp)"
if ($hostsHits.Count -gt 0) {
    Add-Finding (New-Finding "NETWORK-TAMPER" (Get-ForensicsText "forensicsReport.category.network") "High" 25 (Get-ForensicsText "forensicsReport.network.fullEvidence" @(($hostsHits -join '; '), ($policyItems -join ', '), $winHttpProxy)) (Get-ForensicsText "forensicsReport.network.highRecommendation"))
} elseif ($policyItems.Count -gt 0 -or $proxyConfigured) {
    Add-Finding (New-Finding "NETWORK-TAMPER" (Get-ForensicsText "forensicsReport.category.network") "Review" 8 (Get-ForensicsText "forensicsReport.network.policyEvidence" @(($policyItems -join ', '), $winHttpProxy)) (Get-ForensicsText "forensicsReport.network.reviewRecommendation"))
} else {
    Add-Finding (New-Finding "NETWORK-TAMPER" (Get-ForensicsText "forensicsReport.category.network") "OK" 0 (Get-ForensicsText "forensicsReport.network.none") (Get-ForensicsText "forensicsReport.noChange"))
}

# 6. Nhật ký Software Protection trong 30 ngày; chỉ lưu thống kê, không chép nội dung sự kiện.
$eventStart = (Get-Date).AddDays(-30)
$licensingEvents = @()
foreach ($provider in @("Software Protection Platform Service", "Microsoft-Windows-Security-SPP", "Office Software Protection Platform Service")) {
    try {
        $licensingEvents += @(Get-WinEvent -FilterHashtable @{ LogName="Application"; ProviderName=$provider; StartTime=$eventStart } -ErrorAction Stop)
    } catch {}
}
$licensingErrors = @($licensingEvents | Where-Object { $_.Level -in @(1,2) })
$lastEvent = $licensingEvents | Sort-Object TimeCreated -Descending | Select-Object -First 1
$lastEventText = if ($lastEvent) { $lastEvent.TimeCreated } else { Get-ForensicsText "common.none" }
$eventEvidence = Get-ForensicsText "forensicsReport.events.evidence" @($licensingEvents.Count, $licensingErrors.Count, $lastEventText)
if ($licensingErrors.Count -ge 10) {
    Add-Finding (New-Finding "SPP-EVENTS" (Get-ForensicsText "forensicsReport.category.events") "Review" 10 $eventEvidence (Get-ForensicsText "forensicsReport.events.reviewRecommendation"))
} else {
    Add-Finding (New-Finding "SPP-EVENTS" (Get-ForensicsText "forensicsReport.category.events") "Info" 0 $eventEvidence (Get-ForensicsText "forensicsReport.events.infoRecommendation"))
}

# 7. Đồng bộ thời gian và múi giờ.
$timeService = Get-Service -Name W32Time -ErrorAction SilentlyContinue
$timeStatus = (& $nativeW32tmPath /query /status 2>$null) -join " | "
if ($timeService -and $timeService.StartType -eq "Disabled") {
    Add-Finding (New-Finding "TIME-SYNC" (Get-ForensicsText "forensicsReport.category.time") "Review" 6 (Get-ForensicsText "forensicsReport.time.disabled" @([TimeZoneInfo]::Local.Id)) (Get-ForensicsText "forensicsReport.time.disabledRecommendation"))
} else {
    $timeSummary = ($timeStatus -replace "\s+", " ").Trim()
    if ($timeSummary.Length -gt 300) { $timeSummary = $timeSummary.Substring(0,300) + "..." }
    Add-Finding (New-Finding "TIME-SYNC" (Get-ForensicsText "forensicsReport.category.time") "Info" 0 (Get-ForensicsText "forensicsReport.time.evidence" @($timeService.Status, [TimeZoneInfo]::Local.Id, $timeSummary)) (Get-ForensicsText "forensicsReport.time.recommendation"))
}

# 8. Office: trạng thái, kênh và KMS.
$officeLicenses = @(Safe-Cim SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -match "Office" })
$officeActive = @($officeLicenses | Where-Object { [int]$_.LicenseStatus -eq 1 })
$officeKms = @($officeLicenses | Where-Object { $_.Description -match "KMSCLIENT|VOLUME_KMS" })
$officeEvidence = @($officeLicenses | ForEach-Object {
    Get-ForensicsText "forensicsReport.office.evidence" @($_.Name, $_.LicenseStatus, $_.Description, $_.PartialProductKey, $_.KeyManagementServiceMachine)
})
if ($officeKms.Count -gt 0) {
    $unapprovedOfficeKms = @($officeKms | Where-Object { -not (Test-ApprovedKms ([string]$_.KeyManagementServiceMachine)) })
    if ($unapprovedOfficeKms.Count -gt 0) {
        Add-Finding (New-Finding "OFFICE-LICENSE" (Get-ForensicsText "forensicsReport.category.office") "Review" 15 ($officeEvidence -join "`n") (Get-ForensicsText "forensicsReport.office.unapprovedRecommendation"))
    } else {
        Add-Finding (New-Finding "OFFICE-LICENSE" (Get-ForensicsText "forensicsReport.category.office") "OK" 0 ($officeEvidence -join "`n") (Get-ForensicsText "forensicsReport.office.approvedRecommendation"))
    }
} elseif ($officeLicenses.Count -eq 0) {
    Add-Finding (New-Finding "OFFICE-LICENSE" (Get-ForensicsText "forensicsReport.category.office") "Info" 0 (Get-ForensicsText "forensicsReport.office.none") (Get-ForensicsText "forensicsReport.office.noneRecommendation"))
} elseif ($officeActive.Count -eq 0) {
    Add-Finding (New-Finding "OFFICE-LICENSE" (Get-ForensicsText "forensicsReport.category.office") "Review" 8 ($officeEvidence -join "`n") (Get-ForensicsText "forensicsReport.office.inactiveRecommendation"))
} else {
    Add-Finding (New-Finding "OFFICE-LICENSE" (Get-ForensicsText "forensicsReport.category.office") "OK" 0 ($officeEvidence -join "`n") (Get-ForensicsText "forensicsReport.office.activeRecommendation"))
}

# 9. Phần mềm cài đặt có tên/publisher khớp mẫu đặc hiệu.
$uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$suspiciousApps = @()
foreach ($root in $uninstallRoots) {
    $suspiciousApps += @(Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match $activatorRegex -or $_.Publisher -match $activatorRegex
    } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion) | $($_.Publisher)" })
}
$suspiciousApps = @($suspiciousApps | Sort-Object -Unique)
if ($suspiciousApps.Count -gt 0) {
    Add-Finding (New-Finding "SUSPICIOUS-APPS" (Get-ForensicsText "forensicsReport.category.apps") "High" 30 ($suspiciousApps -join "`n") (Get-ForensicsText "forensicsReport.apps.detectedRecommendation"))
} else {
    Add-Finding (New-Finding "SUSPICIOUS-APPS" (Get-ForensicsText "forensicsReport.category.apps") "OK" 0 (Get-ForensicsText "forensicsReport.apps.none") (Get-ForensicsText "forensicsReport.apps.noneRecommendation"))
}

# 10. Trạng thái Microsoft Defender và tường lửa.
$defenderText = Get-ForensicsText "forensicsReport.security.defenderUnreadable"
$defenderStatus = "Info"
$defenderScore = 0
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($mp) {
        $defenderText = Get-ForensicsText "forensicsReport.security.defenderEvidence" @($mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled, $mp.BehaviorMonitorEnabled, $mp.IsTamperProtected, $mp.AntivirusSignatureAge)
        if (-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled) { $defenderStatus = "Review"; $defenderScore = 7 }
    }
}
$firewallText = ""
if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
    $firewallText = (@(Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join "; ")
}
Add-Finding (New-Finding "SECURITY-POSTURE" (Get-ForensicsText "forensicsReport.category.security") $defenderStatus $defenderScore (Get-ForensicsText "forensicsReport.security.evidence" @($defenderText, $firewallText)) (Get-ForensicsText "forensicsReport.security.recommendation"))

# 11. Secure Boot, TPM và BitLocker - tín hiệu an toàn bổ trợ.
$secureBoot = Get-ForensicsText "forensicsReport.platform.unsupported"
if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
    try { $secureBoot = [string](Confirm-SecureBootUEFI -ErrorAction Stop) } catch {}
}
$tpmText = Get-ForensicsText "forensicsReport.platform.unsupported"
if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
    try { $tpm = Get-Tpm; $tpmText = Get-ForensicsText "forensicsReport.platform.tpmState" @($tpm.TpmPresent, $tpm.TpmReady, $tpm.TpmEnabled) } catch {}
}
$bitLockerText = Get-ForensicsText "forensicsReport.platform.unsupported"
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    try { $bitLockerText = (@(Get-BitLockerVolume | ForEach-Object { Get-ForensicsText "forensicsReport.platform.volumeState" @($_.MountPoint, $_.ProtectionStatus) }) -join "; ") } catch {}
}
Add-Finding (New-Finding "PLATFORM-SECURITY" (Get-ForensicsText "forensicsReport.category.platform") "Info" 0 (Get-ForensicsText "forensicsReport.platform.evidence" @($secureBoot, $tpmText, $bitLockerText)) (Get-ForensicsText "forensicsReport.platform.recommendation"))

# 12. Tệp token cấp phép và ACL cơ bản.
$tokenCandidates = @(
    (Get-ToolNativeSystemPath "spp\store\2.0\tokens.dat"),
    (Join-Path $env:windir "ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SoftwareProtectionPlatform\tokens.dat")
)
$tokenPath = $tokenCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($tokenPath) {
    $tokenInfo = Get-Item -LiteralPath $tokenPath
    $tokenHash = Get-Sha256 $tokenPath
    Add-Finding (New-Finding "TOKEN-ARTIFACT" (Get-ForensicsText "forensicsReport.category.token") "Info" 0 (Get-ForensicsText "forensicsReport.token.found" @($tokenInfo.Length, $tokenInfo.LastWriteTime, $tokenHash)) (Get-ForensicsText "forensicsReport.token.foundRecommendation"))
} else {
    Add-Finding (New-Finding "TOKEN-ARTIFACT" (Get-ForensicsText "forensicsReport.category.token") "Review" 10 (Get-ForensicsText "forensicsReport.token.missing") (Get-ForensicsText "forensicsReport.token.missingRecommendation"))
}

$rawScore = [int](($findings | Measure-Object -Property Score -Sum).Sum)
$riskScore = [Math]::Min(100, $rawScore)
$highCount = @($findings | Where-Object { $_.StatusCode -eq "High" }).Count
$reviewCount = @($findings | Where-Object { $_.StatusCode -eq "Review" }).Count
$riskLevel = if ($riskScore -ge 70) { Get-ForensicsText "forensicsReport.risk.veryHigh" } elseif ($riskScore -ge 40) { Get-ForensicsText "forensicsReport.risk.high" } elseif ($riskScore -ge 20) { Get-ForensicsText "forensicsReport.risk.medium" } elseif ($riskScore -gt 0) { Get-ForensicsText "forensicsReport.risk.low" } else { Get-ForensicsText "forensicsReport.risk.none" }
$overall = if ($highCount -gt 0) { Get-ForensicsText "forensicsReport.overall.high" } elseif ($reviewCount -gt 0) { Get-ForensicsText "forensicsReport.overall.review" } else { Get-ForensicsText "forensicsReport.overall.clear" }

# So sánh với lần quét JSON gần nhất của cùng máy.
$previousFile = Get-ChildItem -LiteralPath $OutputDir -Recurse -Filter "LicenseForensics_${reportMachine}_*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $jsonPath } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$previous = $null
if ($previousFile) {
    try { $previous = Get-Content -LiteralPath $previousFile.FullName -Raw | ConvertFrom-Json } catch {}
}
$currentProblemIds = @($findings | Where-Object { $_.StatusCode -in @("High", "Review") } | Select-Object -ExpandProperty Id)
$previousProblemIds = @()
if ($previous -and $previous.Findings) {
    $previousProblemIds = @($previous.Findings | Where-Object { $_.StatusCode -in @("High", "Review") -or $_.Status -in @("Rủi ro cao", "Cần xác minh", "High risk", "Requires verification") } | Select-Object -ExpandProperty Id)
}
$newIds = @($currentProblemIds | Where-Object { $previousProblemIds -notcontains $_ })
$resolvedIds = @($previousProblemIds | Where-Object { $currentProblemIds -notcontains $_ })
$unchangedIds = @($currentProblemIds | Where-Object { $previousProblemIds -contains $_ })

$outputFindings = @($findings | ForEach-Object {
    [pscustomobject]@{
        Id=$_.Id; Category=$_.Category; StatusCode=$_.StatusCode; Status=$_.Status; Score=$_.Score
        Evidence=(Protect-Text $_.Evidence); Recommendation=(Protect-Text $_.Recommendation)
    }
})
$scanObject = New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
    ComputerName = $reportMachine
    ScanTime = $scanStarted.ToString("o")
    Windows = "$productName - $edition"
    ActiveChannel = $channel
    OemKeyPresent = [bool]$oemKey
    Overall = $overall
    RiskScore = $riskScore
    RiskLevel = $riskLevel
    HighCount = $highCount
    ReviewCount = $reviewCount
    Baseline = [pscustomobject]@{
        PreviousFile = if ($previousFile) { Protect-Text $previousFile.FullName } else { "" }
        PreviousRiskScore = if ($previous) { [string]$previous.RiskScore } else { "" }
        NewFindingIds = $newIds
        ResolvedFindingIds = $resolvedIds
        UnchangedFindingIds = $unchangedIds
    }
    Findings = $outputFindings
    Redacted = [bool]$RedactSensitive
    Privacy = if ($RedactSensitive) { Get-ForensicsText "forensicsReport.privacy.redacted" } else { Get-ForensicsText "forensicsReport.privacy.internal" }
})
$scanValidation = Test-ToolReportEnvelope -Report $scanObject -ExpectedReportKind "LicenseForensics" -ExpectedToolVersion $toolVersion
if (-not $scanValidation.Valid) { throw (Get-ForensicsText "forensicsReport.schemaFailed" @(($scanValidation.Errors -join '; '))) }
$scanObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$csvColumns = @(
    (Get-ForensicsText "forensicsReport.column.id"),
    (Get-ForensicsText "forensicsReport.column.category"),
    (Get-ForensicsText "forensicsReport.column.status"),
    (Get-ForensicsText "forensicsReport.column.score"),
    (Get-ForensicsText "forensicsReport.column.evidence"),
    (Get-ForensicsText "forensicsReport.column.recommendation")
)
$csvRows = @($outputFindings | ForEach-Object {
    $row=[ordered]@{}
    $row[$csvColumns[0]]=$_.Id; $row[$csvColumns[1]]=$_.Category; $row[$csvColumns[2]]=$_.Status
    $row[$csvColumns[3]]=$_.Score; $row[$csvColumns[4]]=$_.Evidence; $row[$csvColumns[5]]=$_.Recommendation
    [pscustomobject]$row
})
$csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$baselineText = if ($previous) {
    $noneText=Get-ForensicsText "common.none"
    Get-ForensicsText "forensicsReport.baseline.summary" @($previous.RiskScore, $(if ($newIds.Count) { $newIds -join ', ' } else { $noneText }), $(if ($resolvedIds.Count) { $resolvedIds -join ', ' } else { $noneText }), $(if ($unchangedIds.Count) { $unchangedIds -join ', ' } else { $noneText }))
} else { Get-ForensicsText "forensicsReport.baseline.first" }
$findingRows = $csvRows
$oemStateText = if ($oemKey) { Get-ForensicsText "forensicsReport.oem.presentRedacted" } else { Get-ForensicsText "common.notFound" }
$overviewBody = "<p><strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.overview.conclusion'))</strong> $(ConvertTo-ToolHtmlText $overall)</p>" +
    "<p><strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.overview.windows'))</strong> $(ConvertTo-ToolHtmlText "$productName - $edition")<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.overview.channel'))</strong> $(ConvertTo-ToolHtmlText $channel)<br>" +
    "<strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.overview.oemKey'))</strong> $(ConvertTo-ToolHtmlText $oemStateText)</p>"
$limitBody = "<p><strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.limit.label'))</strong> $(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.limit.text'))</p>" +
    "<p class='note'><strong>$(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.privacy.label'))</strong> $(ConvertTo-ToolHtmlText (Get-ForensicsText 'forensicsReport.privacy.text'))</p>"
$html = New-ToolProfessionalHtmlDocument `
    -Title (Get-ForensicsText "forensicsReport.title") `
    -Subtitle (Get-ForensicsText "forensicsReport.subtitle") `
    -Eyebrow (Get-ForensicsText "forensicsReport.eyebrow") `
    -Metadata @(
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.meta.computer");Value=$reportMachine},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.meta.time");Value=$scanStarted.ToString("yyyy-MM-dd HH:mm:ss")},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.meta.mode");Value=(Get-ForensicsText "forensicsReport.meta.readOnly")},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.meta.privacy");Value=$(if ($RedactSensitive) { Get-ForensicsText "forensicsReport.privacy.redacted" } else { Get-ForensicsText "forensicsReport.privacy.internal" })}
    ) `
    -Cards @(
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.card.score");Value="$riskScore/100";Tone=$(if ($riskScore -ge 70) {"danger"} elseif ($riskScore -ge 20) {"warning"} else {"ok"})},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.card.level");Value=$riskLevel;Tone=$(if ($riskScore -ge 70) {"danger"} elseif ($riskScore -ge 20) {"warning"} else {"ok"})},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.card.high");Value=[string]$highCount;Tone=$(if ($highCount -gt 0) {"danger"} else {"ok"})},
        [pscustomobject]@{Label=(Get-ForensicsText "forensicsReport.card.review");Value=[string]$reviewCount;Tone=$(if ($reviewCount -gt 0) {"warning"} else {"ok"})}
    ) `
    -Sections @(
        [pscustomobject]@{Title=(Get-ForensicsText "forensicsReport.section.overview");BodyHtml=$overviewBody},
        [pscustomobject]@{Title=(Get-ForensicsText "forensicsReport.section.baseline");BodyHtml="<p>$(ConvertTo-ToolHtmlText $baselineText)</p>"},
        [pscustomobject]@{Title=(Get-ForensicsText "forensicsReport.section.results");BodyHtml=(ConvertTo-ToolHtmlTable -Rows $findingRows -Columns $csvColumns)},
        [pscustomobject]@{Title=(Get-ForensicsText "forensicsReport.section.limits");BodyHtml=$limitBody}
    ) `
    -Footer (Get-ForensicsText "forensicsReport.footer" @($releaseVersion)) -Culture $Culture -OfflineMode $true
[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) { throw (Get-ForensicsText "forensicsReport.offlineSafetyFailed") }
$pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath

$manifestLines = @()
foreach ($file in @($htmlPath, $pdfPath, $jsonPath, $csvPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $manifestLines += "$(Get-Sha256 $file)  $([IO.Path]::GetFileName($file))"
}
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding ASCII

$decision = New-ToolReportEnvelope -ReportKind "LicenseForensics" -ToolVersion $toolVersion -Data ([ordered]@{
    AccessDenied = $false
    Overall = $overall
    RiskScore = $riskScore
    RiskLevel = $riskLevel
    HighCount = $highCount
    ReviewCount = $reviewCount
    NewFindingCount = $newIds.Count
    ResolvedFindingCount = $resolvedIds.Count
    ReportPath = $htmlPath
    PdfPath = if ($pdfResult.Success) { $pdfPath } else { "" }
    EvidenceFolder = $bundleDir
    ManifestPath = $manifestPath
})
Write-DecisionFile $decision

Write-Host (Get-ForensicsText "forensicsReport.output.report" @($htmlPath))
if ($pdfResult.Success) { Write-Host (Get-ForensicsText "forensicsReport.output.pdf" @($pdfPath)) } else { Write-Host (Get-ForensicsText "forensicsReport.output.pdfFailed" @($pdfResult.Error)) }
Write-Host (Get-ForensicsText "forensicsReport.output.score" @($riskScore, $riskLevel))
if (-not $NoOpen) { Start-Process -FilePath $htmlPath }
exit 0
