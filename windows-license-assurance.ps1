[CmdletBinding()]
param(
    [ValidateSet("CertificateAudit", "PluginAudit", "TimelineExport")]
    [string]$Operation = "CertificateAudit",
    [ValidateSet("vi-VN", "en-US")]
    [string]$Culture = "vi-VN",
    [string]$OutputDir = [Environment]::GetFolderPath("Desktop"),
    [switch]$Pdf,
    [switch]$RedactSensitive,
    [switch]$NoOpen
)

$ToolVersion = "4.4"
$ErrorActionPreference = "Stop"
Set-StrictMode -Off

$helperNames = @(
    "Tool-Runtime.ps1",
    "Tool-Capabilities.ps1",
    "Tool-Logging.ps1",
    "Tool-ModuleContract.ps1",
    "Tool-ReportSchema.ps1",
    "Tool-ReportExport.ps1",
    "Tool-PluginEngine.ps1",
    "Tool-LicenseTimeline.ps1",
    "Tool-Localization.ps1"
)
try {
    foreach ($name in $helperNames) {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Thiếu $name." }
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
        throw "ModuleId launcher không khớp Operation $Operation."
    }
    $moduleAvailability = Test-ToolModuleAvailability -ModuleId $moduleId -CapabilityProfile $capabilityState -SourceDirectory $PSScriptRoot
    if (-not $moduleAvailability.Available) { throw $moduleAvailability.Message }
    $moduleInvocation = New-ToolModuleInvocation -ModuleId $moduleId
    $loggingState = Initialize-ToolLogging -Component "Assurance" -ToolVersion $ToolVersion
    $timelineState = Initialize-ToolLicenseTimeline -ToolVersion $ToolVersion
    $env:TOOL_UI_CULTURE = $Culture
} catch {
    Write-Host $_.Exception.Message
    exit 12
}

$OutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$started = Get-Date
$stamp = $started.ToString("yyyyMMdd_HHmmss")
$computer = if ($RedactSensitive) { if ($Culture -eq "en-US") { "REDACTED" } else { "AN_DANH" } } else { [string]$env:COMPUTERNAME }
$toolName = Get-ToolText -Key "app.title" -Culture $Culture
$developer = Get-ToolText -Key "app.developer" -Culture $Culture

function Select-AssuranceText {
    param(
        [Parameter(Mandatory = $true)][string]$Vietnamese,
        [Parameter(Mandatory = $true)][string]$English
    )
    if ($Culture -eq "en-US") { return $English }
    return $Vietnamese
}

function ConvertTo-AssuranceHtmlTable {
    param(
        [object[]]$Rows,
        [string[]]$Columns,
        [hashtable]$EnglishLabels
    )

    if (-not $Rows -or @($Rows).Count -eq 0) {
        return "<p class='muted'>$(Select-AssuranceText 'Không có dữ liệu.' 'No data available.')</p>"
    }
    if ($Culture -ne "en-US") {
        return ConvertTo-ToolHtmlTable -Rows $Rows -Columns $Columns
    }
    $localizedColumns = New-Object System.Collections.Generic.List[string]
    $localizedRows = @()
    foreach ($column in $Columns) {
        $label = if ($EnglishLabels -and $EnglishLabels.ContainsKey($column)) { [string]$EnglishLabels[$column] } else { [string]$column }
        [void]$localizedColumns.Add($label)
    }
    foreach ($row in @($Rows)) {
        $localizedRow = [ordered]@{}
        for ($index = 0; $index -lt $Columns.Count; $index++) {
            $sourceColumn = [string]$Columns[$index]
            $targetColumn = [string]$localizedColumns[$index]
            $localizedRow[$targetColumn] = $row.PSObject.Properties[$sourceColumn].Value
        }
        $localizedRows += [pscustomobject]$localizedRow
    }
    return ConvertTo-ToolHtmlTable -Rows $localizedRows -Columns $localizedColumns.ToArray()
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
            $text = [regex]::Replace($text, $pattern, (Select-AssuranceText "[ĐÃ CHE]" "[REDACTED]"), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', (Select-AssuranceText '[PRODUCT-KEY ĐÃ CHE]' '[PRODUCT KEY REDACTED]'))
    $text = [regex]::Replace($text, '(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d)', (Select-AssuranceText '[IP ĐÃ CHE]' '[IP REDACTED]'))
    $text = [regex]::Replace($text, '(?i)(?<![0-9A-F])(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}(?![0-9A-F])', (Select-AssuranceText '[MAC ĐÃ CHE]' '[MAC REDACTED]'))
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
    $moduleResult = Complete-ToolModuleInvocation -Invocation $moduleInvocation -ExitCode 0 -Summary (Select-AssuranceText "Đã hoàn tất $Operation." "Completed $Operation.") -OutputPaths $predictedPaths -FindingCount $FindingCount -WarningCount $WarningCount
    if ($Envelope.PSObject.Properties["ModuleResult"]) { $Envelope.ModuleResult = $moduleResult }
    else { $Envelope | Add-Member -NotePropertyName ModuleResult -NotePropertyValue $moduleResult }
    $validation = Test-ToolReportEnvelope -Report $Envelope -ExpectedToolVersion $ToolVersion
    if (-not $validation.Valid) { throw "Báo cáo không đạt schema: $($validation.Errors -join '; ')" }
    return Export-ToolReportPackage -Report $Envelope -HtmlContent $Html -BasePath $basePath -IncludePdf:$Pdf -RedactPaths:$RedactSensitive
}

[void](Write-ToolLog -Level "INFO" -Event "Assurance.Start" -Message (Select-AssuranceText "Bắt đầu $Operation." "Started $Operation."))

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
        RevocationMode = Select-AssuranceText "Offline/NoCheck (không phát sinh truy cập mạng)" "Offline/NoCheck (no network access)"
        Targets = $records
        Redacted = [bool]$RedactSensitive
    })
    $tableRows = @($records | ForEach-Object {
        [pscustomobject][ordered]@{
            "Sản phẩm"=$_.Product; "Thành phần"=$_.Component; "Trạng thái"=$_.SignatureStatus
            "Chuỗi tin cậy"=$(if ($_.ChainValid) { Select-AssuranceText "Hợp lệ" "Valid" } else { $_.ChainStatus })
            "Chủ thể ký"=$_.Signer; "Hết hạn"=$_.ValidTo; "Đường dẫn"=$_.Path
        }
    })
    $certificateLabels = @{
        "Sản phẩm"="Product"; "Thành phần"="Component"; "Trạng thái"="Status"
        "Chuỗi tin cậy"="Trust chain"; "Chủ thể ký"="Signer subject"; "Hết hạn"="Valid until"; "Đường dẫn"="Path"
    }
    $certificateInterpretation = Select-AssuranceText `
        "<p>Trạng thái <b>Valid</b> xác nhận chữ ký Authenticode tại thời điểm quét. Kiểm tra chuỗi dùng kho chứng chỉ cục bộ và không kiểm tra thu hồi trực tuyến, vì vậy hệ thống tích hợp nên thực hiện OCSP/CRL riêng nếu chính sách yêu cầu.</p><p class='note'>Chứng chỉ ký tệp không tự chứng minh Windows/Office đã được cấp phép hợp lệ; cần đối chiếu thêm kênh bản quyền và hồ sơ mua hàng.</p>" `
        "<p>A <b>Valid</b> state confirms the Authenticode signature at scan time. Chain validation uses the local certificate store without online revocation checks; integrated environments should perform OCSP/CRL validation separately when policy requires it.</p><p class='note'>A file-signing certificate does not by itself prove that Windows or Office is properly licensed; reconcile the licensing channel and purchase records as well.</p>"
    $html = New-ToolProfessionalHtmlDocument -Title (Select-AssuranceText "Kiểm tra chứng chỉ số Windows/Office" "Windows/Office digital certificate inspection") `
        -Subtitle (Select-AssuranceText "Xác minh Authenticode và chuỗi tin cậy của các tệp lõi Windows, Office đã phát hiện và chính launcher." "Verify Authenticode signatures and trust chains for core Windows files, detected Office files, and the launcher.") `
        -Metadata @(
            [pscustomobject]@{Label=(Select-AssuranceText "Máy" "Computer");Value=$computer},
            [pscustomobject]@{Label=(Select-AssuranceText "Thời điểm" "Time");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label="Schema";Value="Report 1.4 / Certificate audit"},
            [pscustomobject]@{Label=(Select-AssuranceText "Chế độ thu hồi" "Revocation mode");Value=(Select-AssuranceText "Ngoại tuyến, không truy cập mạng" "Offline, no network access")}
        ) -Cards @(
            [pscustomobject]@{Label=(Select-AssuranceText "Kết luận" "Conclusion");Value=$overall;Tone=$(if ($requiredFailures.Count -gt 0) {"danger"} elseif ($invalidRecords.Count -gt 0) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Select-AssuranceText "Chữ ký hợp lệ" "Valid signatures");Value=$validCount;Tone="ok"},
            [pscustomobject]@{Label=(Select-AssuranceText "Cần xem lại" "Requires review");Value=$invalidRecords.Count;Tone=$(if ($invalidRecords.Count) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Select-AssuranceText "Tệp Office" "Office files");Value=$officeCount;Tone="info"}
        ) -Sections @(
            [pscustomobject]@{Title=(Select-AssuranceText "Kết quả theo tệp" "Per-file results");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $tableRows -Columns @("Sản phẩm","Thành phần","Trạng thái","Chuỗi tin cậy","Chủ thể ký","Hết hạn","Đường dẫn") -EnglishLabels $certificateLabels)},
            [pscustomobject]@{Title=(Select-AssuranceText "Cách diễn giải" "Interpretation");BodyHtml=$certificateInterpretation}
        ) -Footer "$developer · Tool v$ToolVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName "BaoCao_ChungChi_${computer}_${stamp}" -FindingCount $invalidRecords.Count
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
        PluginModel = Select-AssuranceText "Khai báo chỉ đọc; không chạy script/command từ plugin" "Declarative read-only; plugin scripts and commands are never executed"
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
    $pluginRows = @($reportPlugins | ForEach-Object {
        [pscustomobject][ordered]@{"Plugin"=$_.Name;"ID"=$_.PluginId;"Phiên bản"=$_.Version;"Nhà phát hành"=$_.Publisher;"Bật"=$_.Enabled;"Số quy tắc"=$_.RuleCount;"Tin cậy"=$_.Trust}
    })
    $findingRows = @($reportFindings | ForEach-Object {
        [pscustomobject][ordered]@{"Mức"=$_.Severity;"Plugin"=$_.PluginName;"Quy tắc"=$_.RuleId;"Kết quả quan sát"=$_.Observed;"Nhận định"=$_.Message;"Hướng xử lý"=$_.Remediation;"Lỗi"=$_.Error}
    })
    $pluginLabels = @{
        "Phiên bản"="Version"; "Nhà phát hành"="Publisher"; "Bật"="Enabled"; "Số quy tắc"="Rule count"; "Tin cậy"="Trust"
        "Mức"="Severity"; "Quy tắc"="Rule"; "Kết quả quan sát"="Observed result"; "Nhận định"="Assessment"; "Hướng xử lý"="Remediation"; "Lỗi"="Error"
    }
    $pluginSafetyBody = Select-AssuranceText `
        "<p>Engine chỉ hỗ trợ ba nguồn đọc: Registry value, tệp trong Windows/Program Files/ProgramData và Windows service. Mọi trường ngoài schema đều bị từ chối.</p><p class='note'>Plugin nằm trong ProgramData có ACL chỉ Administrators/SYSTEM được ghi. Việc cài plugin cần xác nhận của quản trị viên và luôn đối chiếu lại SHA-256 sau khi sao chép.</p>" `
        "<p>The engine supports only three read sources: registry values, files under Windows/Program Files/ProgramData, and Windows services. Fields outside the schema are rejected.</p><p class='note'>Plugins under ProgramData use an ACL that permits writes only by Administrators/SYSTEM. Plugin installation requires administrator confirmation and SHA-256 is verified after copying.</p>"
    $html = New-ToolProfessionalHtmlDocument -Title (Select-AssuranceText "Đánh giá plugin quy tắc kiểm tra" "Inspection-rule plugin assessment") `
        -Subtitle (Select-AssuranceText "Plugin v4.4 là JSON khai báo, chỉ đọc và không được phép chứa mã PowerShell, lệnh hệ thống hoặc tải mạng." "v4.4 plugins are declarative, read-only JSON and cannot contain PowerShell code, system commands, or network downloads.") `
        -Metadata @(
            [pscustomobject]@{Label=(Select-AssuranceText "Máy" "Computer");Value=$computer},
            [pscustomobject]@{Label=(Select-AssuranceText "Thời điểm" "Time");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label=(Select-AssuranceText "Thư mục bảo vệ" "Protected directory");Value=$(if ($audit.Directory.Protected) {Select-AssuranceText "Có" "Yes"} else {Select-AssuranceText "Không / chế độ source" "No / source mode"})},
            [pscustomobject]@{Label="Engine";Value="Plugin schema 1.0"}
        ) -Cards @(
            [pscustomobject]@{Label="Plugin";Value=$audit.PluginCount;Tone="info"},
            [pscustomobject]@{Label=(Select-AssuranceText "Quy tắc đã chạy" "Evaluated rules");Value=$audit.EvaluatedRuleCount;Tone="info"},
            [pscustomobject]@{Label=(Select-AssuranceText "Phát hiện" "Findings");Value=$audit.TriggeredFindingCount;Tone=$(if ($audit.TriggeredFindingCount) {"warning"} else {"ok"})},
            [pscustomobject]@{Label="High/Critical";Value=$audit.HighOrCriticalCount;Tone=$(if ($audit.HighOrCriticalCount) {"danger"} else {"ok"})}
        ) -Sections @(
            [pscustomobject]@{Title=(Select-AssuranceText "Plugin đã nạp" "Loaded plugins");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $pluginRows -Columns @("Plugin","ID","Phiên bản","Nhà phát hành","Bật","Số quy tắc","Tin cậy") -EnglishLabels $pluginLabels)},
            [pscustomobject]@{Title=(Select-AssuranceText "Phát hiện của plugin" "Plugin findings");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $findingRows -Columns @("Mức","Plugin","Quy tắc","Kết quả quan sát","Nhận định","Hướng xử lý","Lỗi") -EnglishLabels $pluginLabels)},
            [pscustomobject]@{Title=(Select-AssuranceText "Mô hình an toàn" "Safety model");BodyHtml=$pluginSafetyBody}
        ) -Footer "$developer · Tool v$ToolVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName "BaoCao_Plugin_${computer}_${stamp}" -FindingCount ([int]$audit.TriggeredFindingCount) -WarningCount ([int]$audit.InvalidPluginCount)
    Write-AssuranceTimelineEventSafe -EventType "PluginAuditCompleted" -Data ([ordered]@{
        PluginCount=$audit.PluginCount; TriggeredFindingCount=$audit.TriggeredFindingCount; HighOrCriticalCount=$audit.HighOrCriticalCount
    })
} else {
    $history = Get-ToolLicenseTimeline
    $reportEvents = @(ConvertTo-AssuranceRedactedObject $history.Events)
    if ($RedactSensitive) {
        foreach ($event in $reportEvents) {
            if ($event.PSObject.Properties["MachineBinding"]) { $event.MachineBinding = Select-AssuranceText "[ĐÃ CHE]" "[REDACTED]" }
            if ($event.PSObject.Properties["CorrelationId"]) { $event.CorrelationId = Select-AssuranceText "[ĐÃ CHE]" "[REDACTED]" }
        }
    }
    $eventRows = @($reportEvents | ForEach-Object {
        $detail = ""
        if ($_.Data -and $_.Data.Changes) { $detail = (@($_.Data.Changes | ForEach-Object { [string]$_.Field }) -join ", ") }
        if ([string]::IsNullOrWhiteSpace($detail) -and $_.Data) {
            $detail = Protect-AssuranceText (($_.Data | ConvertTo-Json -Depth 4 -Compress))
            if ($detail.Length -gt 300) { $detail = $detail.Substring(0,300) + "..." }
        }
        [pscustomobject][ordered]@{
            "STT"=$_.Sequence; "UTC"=$_.TimestampUtc; "Sự kiện"=$_.EventType; "Nguồn"=$_.Source
            "Có thay đổi"=$(if ($_.IsChange) {Select-AssuranceText "Có" "Yes"} else {Select-AssuranceText "Không" "No"}); "Chi tiết"=$detail
        }
    })
    $envelope = New-ToolReportEnvelope -ReportKind "LicenseTimeline" -ToolVersion $ToolVersion -Data ([ordered]@{
        ToolName = $toolName
        CreatedAt = $started.ToString("o")
        ComputerName = $computer
        ChainValid = [bool]$history.Valid
        EventCount = [int]$history.RecordCount
        ChangeCount = [int]$history.ChangeCount
        ValidationErrors = ConvertTo-AssuranceRedactedObject $history.Errors
        Integrity = Select-AssuranceText "HMAC-SHA256 + chuỗi PreviousRecordHash; khóa DPAPI LocalMachine" "HMAC-SHA256 + PreviousRecordHash chain; DPAPI LocalMachine key"
        Events = $reportEvents
    })
    $timelineLabels = @{
        "Sự kiện"="Event"; "Nguồn"="Source"; "Có thay đổi"="Changed"; "Chi tiết"="Details"
    }
    $timelineLimitBody = Select-AssuranceText `
        "<p>Timeline chứng minh tính liên tục của các bản ghi do tool tạo trên máy này; nó không thay thế Windows Event Log, hồ sơ mua bản quyền hoặc hệ thống SIEM.</p><p class='note'>Không xóa/sửa thủ công timeline hay tệp khóa. Nếu chuỗi không hợp lệ, tool dừng nối thêm để giữ nguyên bằng chứng.</p>" `
        "<p>The timeline demonstrates continuity for records created by this tool on this computer; it does not replace Windows Event Log, purchase records, or a SIEM.</p><p class='note'>Do not manually delete or edit the timeline or its key file. If chain validation fails, the tool stops appending records to preserve the evidence.</p>"
    $html = New-ToolProfessionalHtmlDocument -Title (Select-AssuranceText "Nhật ký thay đổi bản quyền" "License change timeline") `
        -Subtitle (Select-AssuranceText "Timeline bền vững ghi snapshot và thao tác liên quan bản quyền, có HMAC-SHA256, chuỗi hash và ràng buộc theo máy." "A durable timeline of licensing snapshots and actions protected by HMAC-SHA256, a hash chain, and machine binding.") `
        -Metadata @(
            [pscustomobject]@{Label=(Select-AssuranceText "Máy" "Computer");Value=$computer},
            [pscustomobject]@{Label=(Select-AssuranceText "Thời điểm xuất" "Export time");Value=$started.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label=(Select-AssuranceText "Xác minh chuỗi" "Chain validation");Value=$(if ($history.Valid) {Select-AssuranceText "Hợp lệ" "Valid"} else {Select-AssuranceText "Không hợp lệ" "Invalid"})},
            [pscustomobject]@{Label=(Select-AssuranceText "Bảo vệ khóa" "Key protection");Value="DPAPI LocalMachine"}
        ) -Cards @(
            [pscustomobject]@{Label=(Select-AssuranceText "Sự kiện" "Events");Value=$history.RecordCount;Tone="info"},
            [pscustomobject]@{Label=(Select-AssuranceText "Thay đổi" "Changes");Value=$history.ChangeCount;Tone=$(if ($history.ChangeCount) {"warning"} else {"ok"})},
            [pscustomobject]@{Label=(Select-AssuranceText "Chuỗi HMAC/hash" "HMAC/hash chain");Value=$(if ($history.Valid) {Select-AssuranceText "Hợp lệ" "Valid"} else {Select-AssuranceText "Lỗi" "Error"});Tone=$(if ($history.Valid) {"ok"} else {"danger"})},
            [pscustomobject]@{Label="Schema";Value="Timeline 1.0";Tone="info"}
        ) -Sections @(
            [pscustomobject]@{Title=(Select-AssuranceText "Dòng thời gian" "Timeline");BodyHtml=(ConvertTo-AssuranceHtmlTable -Rows $eventRows -Columns @("STT","UTC","Sự kiện","Nguồn","Có thay đổi","Chi tiết") -EnglishLabels $timelineLabels)},
            [pscustomobject]@{Title=(Select-AssuranceText "Giới hạn và cách dùng" "Limits and usage");BodyHtml=$timelineLimitBody}
        ) -Footer "$developer · Tool v$ToolVersion" -Culture $Culture -OfflineMode $true
    $package = Complete-AndExportAssuranceReport -Envelope $envelope -Html $html -BaseName "BaoCao_Timeline_${computer}_${stamp}" -WarningCount @($history.Errors).Count
}

[void](Write-ToolLog -Level "INFO" -Event "Assurance.Complete" -Message (Select-AssuranceText "Đã hoàn tất $Operation." "Completed $Operation.") -Data ([ordered]@{
    Html=$package.HtmlPath; Pdf=$package.PdfPath; Json=$package.JsonPath; Xml=$package.XmlPath
}))
Write-Host "HTML: $($package.HtmlPath)"
if (-not [string]::IsNullOrWhiteSpace([string]$package.PdfPath)) { Write-Host "PDF: $($package.PdfPath)" }
elseif ($Pdf) { Write-Host "$(Select-AssuranceText 'Không tạo được PDF' 'PDF could not be created'): $($package.Pdf.Error)" }
Write-Host "JSON: $($package.JsonPath)"
Write-Host "XML: $($package.XmlPath)"
Write-Host "SHA-256: $($package.ManifestPath)"
if (-not $NoOpen) {
    $preferredPath = $package.HtmlPath
    Start-Process -FilePath $preferredPath
}
exit 0
