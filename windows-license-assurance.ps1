[CmdletBinding()]
param(
    [ValidateSet("CertificateAudit", "PluginAudit", "TimelineExport")]
    [string]$Operation = "CertificateAudit",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [string]$OutputDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "BaoCao-Tool-Kiem-Tra"),
    [switch]$Pdf,
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$ToolVersion = "4.8"
$ReleaseVersion = "4.8.0.0"
$ErrorActionPreference = "Stop"
Set-StrictMode -Off

$localizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationPath -PathType Leaf)) { Write-Host "[common.missingDependency] Tool-Localization.ps1"; exit 12 }
. $localizationPath
$env:TOOL_UI_CULTURE = $Culture
function Get-AssuranceText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    return Get-ToolText -Key $Key -Culture $Culture -FormatArguments $Arguments
}

$helperNames = @(
    "Tool-Runtime.ps1",
    "Tool-Capabilities.ps1",
    "Tool-Logging.ps1",
    "Tool-ModuleContract.ps1",
    "Tool-ReportSchema.ps1",
    "Tool-ReportExport.ps1",
    "Tool-PluginEngine.ps1",
    "Tool-LicenseTimeline.ps1"
)
try {
    foreach ($name in $helperNames) {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (Get-AssuranceText "common.missingDependency" @($name)) }
        . $path
    }
    [void](Assert-ToolNativeArchitecture)
    $capabilityState = Get-ToolCapabilityProfile
    $moduleId = switch ($Operation) {
        "CertificateAudit" { "assurance.certificates" }
        "PluginAudit" { "assurance.plugins" }
        "TimelineExport" { "assurance.timeline" }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_MODULE_ID) -and [string]$env:TOOL_MODULE_ID -ne $moduleId) {
        throw (Get-AssuranceText "assurance.bootstrap.moduleMismatch" @($Operation))
    }
    $moduleAvailability = Test-ToolModuleAvailability -ModuleId $moduleId -CapabilityProfile $capabilityState -SourceDirectory $PSScriptRoot
    if (-not $moduleAvailability.Available) { throw $moduleAvailability.Message }
    $moduleInvocation = New-ToolModuleInvocation -ModuleId $moduleId
    $loggingState = Initialize-ToolLogging -Component "Assurance" -ToolVersion $ToolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $ToolVersion
} catch {
    Write-Host $_.Exception.Message
    exit 12
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$started = Get-Date
$stamp = $started.ToString("yyyyMMdd_HHmmss_fff")
$computer = if ($RedactSensitive) { Get-AssuranceText "assurance.file.redactedToken" } else { [string]$env:COMPUTERNAME }
$toolName = Get-ToolText -Key "app.title" -Culture $Culture
$developer = Get-ToolText -Key "report.footer" -Culture $Culture

function ConvertTo-AssuranceHtmlTable {
    param(
        [object[]]$Rows,
        [string[]]$Columns
    )

    if (-not $Rows -or @($Rows).Count -eq 0) {
        return "<p class='muted'>$(Get-AssuranceText "assurance.text.001")</p>"
    }
    return ConvertTo-ToolHtmlTable -Rows $Rows -Columns $Columns
}

function Protect-AssuranceText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if (-not $RedactSensitive) { return $text }
    $profilePath = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $text = [regex]::Replace($text, [regex]::Escape($profilePath), "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($secret in @($env:COMPUTERNAME, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$secret)) {
            $pattern = '(?<![A-Za-z0-9_.-])' + [regex]::Escape([string]$secret) + '(?![A-Za-z0-9_.-])'
            $text = [regex]::Replace($text, $pattern, (Get-AssuranceText "assurance.text.002"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', (Get-AssuranceText "assurance.text.003"))
    $text = [regex]::Replace($text, '(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d)', (Get-AssuranceText "assurance.text.004"))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Get-AssuranceText "assurance.text.005"))
    return $text
}

function ConvertTo-AssuranceRedactedObject {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0
    )

    if (-not $RedactSensitive -or $null -eq $Value) { return $Value }
    if ($Depth -gt 12) { return Protect-AssuranceText $Value }
    if ($Value -is [string]) { return Protect-AssuranceText $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[[string]$key] = ConvertTo-AssuranceRedactedObject -Value $Value[$key] -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    if ($Value -isnot [string] -and $Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-AssuranceRedactedObject -Value $_ -Depth ($Depth + 1) })
    }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and
        $Value -isnot [ValueType] -and $Value -isnot [DateTime]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties)) {
            $result[[string]$property.Name] = ConvertTo-AssuranceRedactedObject -Value $property.Value -Depth ($Depth + 1)
        }
        return [pscustomobject]$result
    }
    return $Value
}

function Write-AssuranceTimelineEventSafe {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][object]$Data
    )

    if (-not $timelineState.Enabled) { return }
    try {
        [void](Write-ToolLicenseTimelineEvent -EventType $EventType -Source $moduleId -IsChange:$false -Data $Data)
    } catch {
        [void](Write-ToolLog -Level "WARN" -Event "Timeline.WriteRejected" -Message $_.Exception.Message -Data ([ordered]@{ EventType=$EventType }))
    }
}

function Get-OfficeInstallationRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration",
        "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Common\InstallRoot",
        "HKLM:\SOFTWARE\Microsoft\Office\15.0\Common\InstallRoot",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Common\InstallRoot",
        "HKLM:\SOFTWARE\Microsoft\Office\14.0\Common\InstallRoot",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\14.0\Common\InstallRoot"
    )
    foreach ($key in $keys) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($propertyName in @("InstallationPath", "Path", "ClientFolder")) {
                $property = $item.PSObject.Properties[$propertyName]
                if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$property.Value))
                    $allowedRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                        ForEach-Object { [IO.Path]::GetFullPath([string]$_).TrimEnd([char]92) + [char]92 } |
                        Select-Object -Unique
                    foreach ($allowed in $allowedRoots) {
                        if ($candidate.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and
                            (Test-Path -LiteralPath $candidate -PathType Container)) {
                            [void]$roots.Add($candidate)
                            break
                        }
                    }
                }
            }
        } catch {}
    }
    foreach ($fallback in @(
        "$env:ProgramFiles\Microsoft Office",
        "${env:ProgramFiles(x86)}\Microsoft Office",
        "$env:ProgramW6432\Microsoft Office"
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$fallback) -and (Test-Path -LiteralPath $fallback -PathType Container)) {
            [void]$roots.Add([IO.Path]::GetFullPath($fallback))
        }
    }
    return @($roots.ToArray() | Sort-Object -Unique)
}

function Get-CertificateAuditTargets {
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(
        @{ Product="Windows"; Component="Software Protection"; Path=(Get-ToolNativeSystemPath "sppsvc.exe"); Required=$true },
        @{ Product="Windows"; Component="Activation UI"; Path=(Get-ToolNativeSystemPath "slui.exe"); Required=$true },
        @{ Product="Windows"; Component="Windows Script Host"; Path=(Get-ToolNativeSystemPath "cscript.exe"); Required=$true },
        @{ Product="Windows"; Component="Windows PowerShell"; Path=(Get-ToolNativePowerShellPath); Required=$true }
    )) {
        [void]$targets.Add([pscustomobject][ordered]@{
            Product=$entry.Product; Component=$entry.Component; Path=$entry.Path; Required=[bool]$entry.Required
        })
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOOL_LAUNCHER_PATH)) {
        try {
            $launcherPath = [IO.Path]::GetFullPath([string]$env:TOOL_LAUNCHER_PATH)
            if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
                [void]$targets.Add([pscustomobject][ordered]@{ Product="Tool"; Component="Launcher"; Path=$launcherPath; Required=$false })
            }
        } catch {}
    }
    $officeNames = @("WINWORD.EXE", "EXCEL.EXE", "POWERPNT.EXE", "OUTLOOK.EXE", "MSACCESS.EXE", "VISIO.EXE", "WINPROJ.EXE", "OfficeClickToRun.exe")
    foreach ($root in @(Get-OfficeInstallationRoots)) {
        $candidateDirectories = @(
            $root,
            (Join-Path $root "Office16"),
            (Join-Path $root "Office15"),
            (Join-Path $root "Office14"),
            (Join-Path $root "root\Office16"),
            (Join-Path $root "root\Office15"),
            (Join-Path $root "root\Office14"),
            (Join-Path $root "root\Client")
        ) | Select-Object -Unique
        foreach ($directory in $candidateDirectories) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
            foreach ($name in $officeNames) {
                $path = Join-Path $directory $name
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    [void]$targets.Add([pscustomobject][ordered]@{ Product="Microsoft Office"; Component=$name; Path=$path; Required=$false })
                }
            }
        }
    }
    return @($targets.ToArray() | Sort-Object Path -Unique | Select-Object -First 28)
}

function Get-FileCertificateAudit {
    param([Parameter(Mandatory = $true)][object]$Target)

    $path = [string]$Target.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            Product=$Target.Product; Component=$Target.Component; Path=(Protect-AssuranceText $path); Required=[bool]$Target.Required
            SignatureStatus="Missing"; Signer=""; Issuer=""; Thumbprint=""; ValidFrom=""; ValidTo=""; TimestampSigner=""; ChainValid=$false; ChainStatus="FileMissing"
        }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    $certificate = $signature.SignerCertificate
    $chainValid = $false
    $chainStatus = ""
    if ($certificate) {
        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
        try {
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chain.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
            $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(2)
            $chainValid = [bool]$chain.Build($certificate)
            $chainStatus = (@($chain.ChainStatus | ForEach-Object { [string]$_.Status }) -join ",")
            if ([string]::IsNullOrWhiteSpace($chainStatus)) { $chainStatus = "NoError" }
        } finally { $chain.Dispose() }
    } else {
        $chainStatus = "NoSignerCertificate"
    }
    return [pscustomobject][ordered]@{
        Product = [string]$Target.Product
        Component = [string]$Target.Component
        Path = Protect-AssuranceText $path
        Required = [bool]$Target.Required
        SignatureStatus = [string]$signature.Status
        Signer = if ($certificate) { [string]$certificate.Subject } else { "" }
        Issuer = if ($certificate) { [string]$certificate.Issuer } else { "" }
        Thumbprint = if ($certificate) { [string]$certificate.Thumbprint } else { "" }
        ValidFrom = if ($certificate) { $certificate.NotBefore.ToString("o") } else { "" }
        ValidTo = if ($certificate) { $certificate.NotAfter.ToString("o") } else { "" }
        TimestampSigner = if ($signature.TimeStamperCertificate) { [string]$signature.TimeStamperCertificate.Subject } else { "" }
        ChainValid = $chainValid
        ChainStatus = $chainStatus
    }
}

function Complete-AndExportAssuranceReport {
    param(
        [Parameter(Mandatory = $true)][object]$Envelope,
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string]$BaseName,
        [int]$FindingCount = 0,
        [int]$WarningCount = 0
    )

    $basePath = Join-Path $OutputDir $BaseName
    $predictedPaths = @("$basePath.html", "$basePath.json", "$basePath.xml", "${basePath}-SHA256SUMS.txt")
    if ($Pdf) { $predictedPaths += "$basePath.pdf" }
    if ($RedactSensitive) {
        $predictedPaths = @($predictedPaths | ForEach-Object { [IO.Path]::GetFileName($_) })
    }
    $moduleResult = Complete-ToolModuleInvocation -Invocation $moduleInvocation -ExitCode 0 -Summary (Get-AssuranceText "assurance.text.006" @($Operation)) -OutputPaths $predictedPaths -FindingCount $FindingCount -WarningCount $WarningCount
    if ($Envelope.PSObject.Properties["ModuleResult"]) { $Envelope.ModuleResult = $moduleResult }
    else { $Envelope | Add-Member -NotePropertyName ModuleResult -NotePropertyValue $moduleResult }
    $validation = Test-ToolReportEnvelope -Report $Envelope -ExpectedToolVersion $ToolVersion
    if (-not $validation.Valid) { throw (Get-AssuranceText "assurance.schemaFailed" @(($validation.Errors -join '; '))) }
    return Export-ToolReportPackage -Report $Envelope -HtmlContent $Html -BasePath $basePath -IncludePdf:$Pdf -RedactPaths:$RedactSensitive
}

[void](Write-ToolLog -Level "INFO" -Event "Assurance.Start" -Message (Get-AssuranceText "assurance.text.007" @($Operation)))

if ($Operation -eq "CertificateAudit") {
    $targets = @(Get-CertificateAuditTargets)
    $records = @($targets | ForEach-Object { Get-FileCertificateAudit -Target $_ })
    $validCount = @($records | Where-Object { $_.SignatureStatus -eq "Valid" -and $_.ChainValid }).Count
    $invalidRecords = @($records | Where-Object { $_.SignatureStatus -ne "Valid" -or -not $_.ChainValid })
    $requiredFailures = @($invalidRecords | Where-Object Required)
    $officeCount = @($records | Where-Object Product -eq "Microsoft Office").Count
    $overall = if ($requiredFailures.Count -gt 0) { "ActionRequired" } elseif ($invalidRecords.Count -gt 0) { "Review" } elseif ($officeCount -eq 0) { "PassWithNotice" } else { "Pass" }
    $envelope = New-ToolReportEnvelope -ReportKind "CertificateAudit" -ToolVersion $ToolVersion -Data ([ordered]@{
        ToolName = $toolName
        CreatedAt = $started.ToString("o")
        ComputerName = $computer
        Overall = $overall
        ValidSignatureCount = $validCount
        InvalidSignatureCount = $invalidRecords.Count
        RequiredFailureCount = $requiredFailures.Count
        OfficeFileCount = $officeCount
        RevocationMode = Get-AssuranceText "assurance.text.008"
        Targets = $records
        Redacted = [bool]$RedactSensitive
    })
    $certificateColumns = @(
        Get-AssuranceText "assurance.column.product"
        Get-AssuranceText "assurance.column.component"
        Get-AssuranceText "assurance.column.status"
        Get-AssuranceText "assurance.column.trustChain"
        Get-AssuranceText "assurance.column.signer"
        Get-AssuranceText "assurance.column.validUntil"
        Get-AssuranceText "assurance.column.path"
    )
    $tableRows = @($records | ForEach-Object {
        $row = [ordered]@{}
        $row[$certificateColumns[0]]=$_.Product; $row[$certificateColumns[1]]=$_.Component; $row[$certificateColumns[2]]=$_.SignatureStatus
        $row[$certificateColumns[3]]=$(if ($_.ChainValid) { Get-AssuranceText "assurance.text.009" } else { $_.ChainStatus })
        $row[$certificateColumns[4]]=$_.Signer; $row[$certificateColumns[5]]=$_.ValidTo; $row[$certificateColumns[6]]=$_.Path
        [pscustomobject]$row
    })
    $certificateInterpretation = Get-AssuranceText "assurance.text.010"
    $html = New-ToolProfessionalHtmlDocument -Title (Get-AssuranceText "assurance.text.011") `
        -Subtitle (Get-AssuranceText "assurance.text.012") `
        -Metadata @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.013");Value=$computer},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.014");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.meta.schema");Value="Report 1.4 / Certificate audit"},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.015");Value=(Get-AssuranceText "assurance.text.016")}
        ) -Cards @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.017");Value=$overall;Tone=$(if ($requiredFailures.Count -gt 0) {"danger"} elseif ($invalidRecords.Count -gt 0) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.018");Value=$validCount;Tone="ok"},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.019");Value=$invalidRecords.Count;Tone=$(if ($invalidRecords.Count) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.020");Value=$officeCount;Tone="info"}
        ) -Sections @(
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.021");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $tableRows -Columns $certificateColumns)},
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.022");BodyHtml=$certificateInterpretation}
        ) -Footer "$developer · Tool v$ReleaseVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName ((Get-AssuranceText "assurance.file.certificate") + "_${computer}_${stamp}") -FindingCount $invalidRecords.Count
    Write-AssuranceTimelineEventSafe -EventType "CertificateAuditCompleted" -Data ([ordered]@{
        Overall=$overall; ValidSignatureCount=$validCount; InvalidSignatureCount=$invalidRecords.Count; RequiredFailureCount=$requiredFailures.Count
    })
} elseif ($Operation -eq "PluginAudit") {
    $audit = Invoke-ToolPluginAudit
    $reportPlugins = ConvertTo-AssuranceRedactedObject $audit.Plugins
    $reportFindings = ConvertTo-AssuranceRedactedObject $audit.Findings
    $reportInvalidPlugins = ConvertTo-AssuranceRedactedObject $audit.InvalidPlugins
    $envelope = New-ToolReportEnvelope -ReportKind "PluginEvaluation" -ToolVersion $ToolVersion -Data ([ordered]@{
        ToolName = $toolName
        CreatedAt = $started.ToString("o")
        ComputerName = $computer
        PluginModel = Get-AssuranceText "assurance.text.023"
        DirectoryProtected = [bool]$audit.Directory.Protected
        PluginCount = [int]$audit.PluginCount
        EnabledPluginCount = [int]$audit.EnabledPluginCount
        InvalidPluginCount = [int]$audit.InvalidPluginCount
        EvaluatedRuleCount = [int]$audit.EvaluatedRuleCount
        TriggeredFindingCount = [int]$audit.TriggeredFindingCount
        HighOrCriticalCount = [int]$audit.HighOrCriticalCount
        Plugins = $reportPlugins
        Findings = $reportFindings
        InvalidPlugins = $reportInvalidPlugins
        Error = Protect-AssuranceText $audit.Error
    })
    $pluginColumns = @(
        Get-AssuranceText "assurance.column.plugin"
        Get-AssuranceText "assurance.column.id"
        Get-AssuranceText "assurance.column.version"
        Get-AssuranceText "assurance.column.publisher"
        Get-AssuranceText "assurance.column.enabled"
        Get-AssuranceText "assurance.column.ruleCount"
        Get-AssuranceText "assurance.column.trust"
    )
    $findingColumns = @(
        Get-AssuranceText "assurance.column.severity"
        Get-AssuranceText "assurance.column.plugin"
        Get-AssuranceText "assurance.column.rule"
        Get-AssuranceText "assurance.column.observed"
        Get-AssuranceText "assurance.column.assessment"
        Get-AssuranceText "assurance.column.remediation"
        Get-AssuranceText "assurance.column.error"
    )
    $pluginRows = @($reportPlugins | ForEach-Object {
        $row=[ordered]@{}
        $row[$pluginColumns[0]]=$_.Name; $row[$pluginColumns[1]]=$_.PluginId; $row[$pluginColumns[2]]=$_.Version
        $row[$pluginColumns[3]]=$_.Publisher; $row[$pluginColumns[4]]=$_.Enabled; $row[$pluginColumns[5]]=$_.RuleCount; $row[$pluginColumns[6]]=$_.Trust
        [pscustomobject]$row
    })
    $findingRows = @($reportFindings | ForEach-Object {
        $row=[ordered]@{}
        $row[$findingColumns[0]]=$_.Severity; $row[$findingColumns[1]]=$_.PluginName; $row[$findingColumns[2]]=$_.RuleId
        $row[$findingColumns[3]]=$_.Observed; $row[$findingColumns[4]]=$_.Message; $row[$findingColumns[5]]=$_.Remediation; $row[$findingColumns[6]]=$_.Error
        [pscustomobject]$row
    })
    $pluginSafetyBody = Get-AssuranceText "assurance.text.024"
    $html = New-ToolProfessionalHtmlDocument -Title (Get-AssuranceText "assurance.text.025") `
        -Subtitle (Get-AssuranceText "assurance.text.026") `
        -Metadata @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.027");Value=$computer},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.028");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.029");Value=$(if ($audit.Directory.Protected) {Get-AssuranceText "assurance.text.030"} else {Get-AssuranceText "assurance.text.031"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.meta.engine");Value="Plugin schema 1.0"}
        ) -Cards @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.card.plugin");Value=$audit.PluginCount;Tone="info"},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.032");Value=$audit.EvaluatedRuleCount;Tone="info"},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.033");Value=$audit.TriggeredFindingCount;Tone=$(if ($audit.TriggeredFindingCount) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.card.highCritical");Value=$audit.HighOrCriticalCount;Tone=$(if ($audit.HighOrCriticalCount) {"danger"} else {"ok"})}
        ) -Sections @(
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.034");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $pluginRows -Columns $pluginColumns)},
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.035");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $findingRows -Columns $findingColumns)},
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.036");BodyHtml=$pluginSafetyBody}
        ) -Footer "$developer · Tool v$ReleaseVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName ((Get-AssuranceText "assurance.file.plugin") + "_${computer}_${stamp}") -FindingCount ([int]$audit.TriggeredFindingCount) -WarningCount ([int]$audit.InvalidPluginCount)
    Write-AssuranceTimelineEventSafe -EventType "PluginAuditCompleted" -Data ([ordered]@{
        PluginCount=$audit.PluginCount; TriggeredFindingCount=$audit.TriggeredFindingCount; HighOrCriticalCount=$audit.HighOrCriticalCount
    })
} else {
    $history = Get-ToolLicenseTimeline
    $reportEvents = @(ConvertTo-AssuranceRedactedObject $history.Events)
    if ($RedactSensitive) {
        foreach ($event in $reportEvents) {
            if ($event.PSObject.Properties["MachineBinding"]) { $event.MachineBinding = Get-AssuranceText "assurance.text.037" }
            if ($event.PSObject.Properties["CorrelationId"]) { $event.CorrelationId = Get-AssuranceText "assurance.text.038" }
        }
    }
    $timelineColumns = @(
        Get-AssuranceText "assurance.column.sequence"
        Get-AssuranceText "assurance.column.utc"
        Get-AssuranceText "assurance.column.event"
        Get-AssuranceText "assurance.column.source"
        Get-AssuranceText "assurance.column.changed"
        Get-AssuranceText "assurance.column.details"
    )
    $eventRows = @($reportEvents | ForEach-Object {
        $detail = ""
        if ($_.Data -and $_.Data.Changes) { $detail = (@($_.Data.Changes | ForEach-Object { [string]$_.Field }) -join ", ") }
        if ([string]::IsNullOrWhiteSpace($detail) -and $_.Data) {
            $detail = Protect-AssuranceText (($_.Data | ConvertTo-Json -Depth 4 -Compress))
            if ($detail.Length -gt 300) { $detail = $detail.Substring(0,300) + "..." }
        }
        $row=[ordered]@{}
        $row[$timelineColumns[0]]=$_.Sequence; $row[$timelineColumns[1]]=$_.TimestampUtc; $row[$timelineColumns[2]]=$_.EventType
        $row[$timelineColumns[3]]=$_.Source; $row[$timelineColumns[4]]=$(if ($_.IsChange) {Get-AssuranceText "assurance.text.039"} else {Get-AssuranceText "assurance.text.040"}); $row[$timelineColumns[5]]=$detail
        [pscustomobject]$row
    })
    $envelope = New-ToolReportEnvelope -ReportKind "LicenseTimeline" -ToolVersion $ToolVersion -Data ([ordered]@{
        ToolName = $toolName
        CreatedAt = $started.ToString("o")
        ComputerName = $computer
        ChainValid = [bool]$history.Valid
        EventCount = [int]$history.RecordCount
        ChangeCount = [int]$history.ChangeCount
        ValidationErrors = ConvertTo-AssuranceRedactedObject $history.Errors
        Integrity = Get-AssuranceText "assurance.text.041"
        Events = $reportEvents
    })
    $timelineLimitBody = Get-AssuranceText "assurance.text.042"
    $html = New-ToolProfessionalHtmlDocument -Title (Get-AssuranceText "assurance.text.043") `
        -Subtitle (Get-AssuranceText "assurance.text.044") `
        -Metadata @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.045");Value=$computer},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.046");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.047");Value=$(if ($history.Valid) {Get-AssuranceText "assurance.text.048"} else {Get-AssuranceText "assurance.text.049"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.050");Value="DPAPI LocalMachine"}
        ) -Cards @(
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.051");Value=$history.RecordCount;Tone="info"},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.052");Value=$history.ChangeCount;Tone=$(if ($history.ChangeCount) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.text.053");Value=$(if ($history.Valid) {Get-AssuranceText "assurance.text.054"} else {Get-AssuranceText "assurance.text.055"});Tone=$(if ($history.Valid) {"ok"} else {"danger"})},
            [pscustomobject]@{Label=(Get-AssuranceText "assurance.meta.schema");Value="Timeline 1.0";Tone="info"}
        ) -Sections @(
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.056");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $eventRows -Columns $timelineColumns)},
            [pscustomobject]@{Title=(Get-AssuranceText "assurance.text.057");BodyHtml=$timelineLimitBody}
        ) -Footer "$developer · Tool v$ReleaseVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName ((Get-AssuranceText "assurance.file.timeline") + "_${computer}_${stamp}") -WarningCount @($history.Errors).Count
}

[void](Write-ToolLog -Level "INFO" -Event "Assurance.Complete" -Message (Get-AssuranceText "assurance.text.058" @($Operation)) -Data ([ordered]@{
    Html=$package.HtmlPath; Pdf=$package.PdfPath; Json=$package.JsonPath; Xml=$package.XmlPath
}))
Write-Host (Get-AssuranceText "assurance.output.html" @($package.HtmlPath))
if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host (Get-AssuranceText "assurance.output.pdf" @($package.PdfPath)) }
elseif ($Pdf) { Write-Host (Get-AssuranceText "assurance.output.pdfFailed" @($package.Pdf.Error)) }
Write-Host (Get-AssuranceText "assurance.output.json" @($package.JsonPath))
Write-Host (Get-AssuranceText "assurance.output.xml" @($package.XmlPath))
Write-Host (Get-AssuranceText "assurance.output.manifest" @($package.ManifestPath))
if (-not $NoOpen) {
    $preferredPath = $package.HtmlPath
    Start-Process -FilePath $preferredPath
}
exit 0
