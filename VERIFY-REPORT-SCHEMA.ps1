[CmdletBinding()]
param(
    [string]$SourceDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$sourceDirectoryFull = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) { $failures.Add($Message) }

function Read-SourceText([string]$Name) {
    $path = Join-Path $sourceDirectoryFull $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Thiếu tệp nguồn: $Name"
        return ''
    }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "Lỗi cú pháp ${Name}: $($parseError.Message)" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

$helperPath = Join-Path $sourceDirectoryFull 'Tool-ReportSchema.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    Add-Failure 'Thiếu Tool-ReportSchema.ps1.'
} else {
    . $helperPath
}

if (Get-Command Get-ToolReportSchemaMetadata -ErrorAction SilentlyContinue) {
    $metadata = Get-ToolReportSchemaMetadata
if ([string]$metadata.SchemaVersion -ne '1.5' -or [string]$metadata.ToolVersion -ne '4.8') {
        Add-Failure 'Metadata schema báo cáo không phải 1.5 / tool 4.8.'
    }
    if (@($metadata.ReportKinds).Count -ne 9) { Add-Failure 'Schema phải khai báo đúng 9 ReportKind.' }

    $fixtures = [ordered]@{
        InventoryAndLicense = [ordered]@{ ToolName='Fixture'; CreatedAt='2026-07-23T00:00:00.0000000Z'; Mode='All' }
        CleanupCompliance = [ordered]@{ ReadyForOfficialActivation=$false; ScanWarningCount=1; HandlingGuidance=@('Quét lại') }
        LicenseForensics = [ordered]@{ Overall='Cần xác minh'; RiskScore=20; HighCount=0; ReviewCount=1 }
        DeepScanDecision = [ordered]@{ AccessDenied=$false; Overall='Không phát hiện rủi ro cao'; HighCount=0; ReviewCount=0; ReportPath='fixture.html' }
        ScanSourceRepair = [ordered]@{ RepairAttempted=$true; RecheckPassed=$false; StartupTypeChanged=$false; RollbackApplied=$true; ServiceStateBefore=@(); ServiceStateAfter=@() }
        CertificateAudit = [ordered]@{ CreatedAt='2026-07-23T00:00:00.0000000Z'; Overall='Pass'; ValidSignatureCount=4; InvalidSignatureCount=0; Targets=@() }
        PluginEvaluation = [ordered]@{ CreatedAt='2026-07-23T00:00:00.0000000Z'; PluginCount=1; EvaluatedRuleCount=3; TriggeredFindingCount=0 }
        LicenseTimeline = [ordered]@{ CreatedAt='2026-07-23T00:00:00.0000000Z'; ChainValid=$true; EventCount=2; ChangeCount=1 }
        EnterpriseInventory = [ordered]@{ CreatedAt='2026-07-24T00:00:00.0000000Z'; ClientId='00000000000000000000000000000001'; ComputerName='FIXTURE'; NetworkAddresses=@('127.0.0.1'); WindowsLicenses=@(); OfficeLicenses=@(); Privacy=[ordered]@{ FullProductKeyIncluded=$false } }
    }

    foreach ($kind in @($fixtures.Keys)) {
        try {
    $fixture = New-ToolReportEnvelope -ReportKind $kind -ToolVersion '4.8' -Data $fixtures[$kind]
            $roundTrip = $fixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $validation = Test-ToolReportEnvelope -Report $roundTrip -ExpectedReportKind $kind -ExpectedToolVersion '4.8'
            if (-not $validation.Valid) { Add-Failure "Fixture $kind không đạt sau JSON round-trip: $($validation.Errors -join '; ')" }
            if ([string]$roundTrip.SchemaVersion -ne '1.5' -or [string]$roundTrip.ReportSchemaVersion -ne '1.5') {
                Add-Failure "Fixture $kind mất trường schema 1.5 sau round-trip."
            }
        } catch { Add-Failure "Không tạo/kiểm tra được fixture ${kind}: $($_.Exception.Message)" }
    }

    try {
    [void](New-ToolReportEnvelope -ReportKind 'UnknownKind' -ToolVersion '4.8' -Data @{})
        Add-Failure 'New-ToolReportEnvelope chấp nhận ReportKind không xác định.'
    } catch {}

$negative = New-ToolReportEnvelope -ReportKind 'DeepScanDecision' -ToolVersion '4.8' -Data $fixtures.DeepScanDecision
    $negative.PSObject.Properties.Remove('SchemaVersion')
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận báo cáo thiếu SchemaVersion.' }

$negative = New-ToolReportEnvelope -ReportKind 'DeepScanDecision' -ToolVersion '4.8' -Data $fixtures.DeepScanDecision
    $negative.PSObject.Properties.Remove('AccessDenied')
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận DeepScanDecision thiếu trường bắt buộc theo loại.' }

$negative = New-ToolReportEnvelope -ReportKind 'CleanupCompliance' -ToolVersion '4.8' -Data $fixtures.CleanupCompliance
    $negative.ReportSchemaVersion = '1.3'
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận ReportSchemaVersion cũ.' }

$negative = New-ToolReportEnvelope -ReportKind 'LicenseForensics' -ToolVersion '4.8' -Data $fixtures.LicenseForensics
    if ((Test-ToolReportEnvelope -Report $negative -ExpectedToolVersion '9.9').Valid) { Add-Failure 'Schema không bắt sai ToolVersion kỳ vọng.' }
}

$inventoryText = Read-SourceText 'kiem-tra-cau-hinh-ban-quyen.ps1'
$cleanupText = Read-SourceText 'windows-license-compliance-cleanup.ps1'
$forensicsText = Read-SourceText 'windows-license-forensics.ps1'
$deepScanText = Read-SourceText 'windows-license-deep-scan.ps1'
$assuranceText = Read-SourceText 'windows-license-assurance.ps1'
$guiText = Read-SourceText 'Giao-Dien.ps1'
$reportExportText = Read-SourceText 'Tool-ReportExport.ps1'

try {
    . (Join-Path $sourceDirectoryFull 'Tool-ReportExport.ps1')
    $tableProfileFixtures = @(
        @{ Name='VI assessment context split'; Columns=@('Ten phan mem','Phien ban','Hang','Mô hình bản quyền'); Expected='table-profile-assessment-context' },
        @{ Name='VI assessment decision split'; Columns=@('Ten phan mem','Trạng thái kỹ thuật','Độ tin cậy','Điều kiện khắc phục'); Expected='table-profile-assessment-decision' },
        @{ Name='VI assessment overview'; Columns=@('Ten phan mem','Phien ban','Hang','Trạng thái kỹ thuật','Độ tin cậy','Điều kiện khắc phục'); Expected='table-profile-assessment-overview' },
        @{ Name='EN assessment evidence'; Columns=@('Software name','License model','Assessment code','Evidence','Vendor scope','Official reference'); Expected='table-profile-assessment-evidence' },
        @{ Name='VI system software appendix'; Columns=@('Ten phan mem','Phien ban','Hang','Nguồn phát hiện'); Expected='table-profile-system-software' },
        @{ Name='compact table'; Columns=@('Muc','Gia tri'); Expected='table-profile-compact' }
    )
    foreach ($fixture in $tableProfileFixtures) {
        $profile = Get-ToolHtmlTableProfile -Columns $fixture.Columns
        if ([string]$profile.TableClass -notmatch [regex]::Escape([string]$fixture.Expected)) {
            Add-Failure "Renderer không gắn profile bảng $($fixture.Name): $($fixture.Expected)"
        }
    }
    $splitColumns = @('Ten phan mem','Phien ban','Hang','Mô hình bản quyền','Trạng thái kỹ thuật','Độ tin cậy','Điều kiện khắc phục')
    $splitRow = [pscustomobject][ordered]@{
        'Ten phan mem'='Fixture'; 'Phien ban'='1.0'; 'Hang'='Fixture Vendor'; 'Mô hình bản quyền'='Commercial'
        'Trạng thái kỹ thuật'='Chưa xác minh'; 'Độ tin cậy'='Low'; 'Điều kiện khắc phục'='Chỉ xem xét thủ công'
    }
    $splitHtml = ConvertTo-ToolHtmlTable -Rows @($splitRow) -Columns $splitColumns
    if ([regex]::Matches($splitHtml, "class='table-split-part'").Count -ne 2 -or
        $splitHtml -notmatch 'table-profile-assessment-context' -or
        $splitHtml -notmatch 'table-profile-assessment-decision') {
        Add-Failure 'Bảng đánh giá bảy cột chưa tách thành hai nhóm ngữ cảnh/quyết định dễ đọc.'
    }
    $referenceCell = ConvertTo-ToolHtmlTableCell -Value 'https://www.wiris.com/en/mathtype/' -ColumnClass path
    if ($referenceCell -notmatch "class='cell-reference'" -or $referenceCell -notmatch "href='https://www\.wiris\.com/en/mathtype/'") {
        Add-Failure 'Renderer chưa biến tham chiếu HTTPS chính thức thành liên kết rõ ràng trong HTML/PDF.'
    }
    $longPathFixture = 'C:\fixture\' + ('long-segment-' * 14) + 'file.exe'
    $longPathCell = ConvertTo-ToolHtmlTableCell -Value $longPathFixture -ColumnClass path
    if ($longPathCell -notmatch "class='cell-compact'" -or $longPathCell -notmatch "class='cell-full'" -or
        $longPathCell -notmatch [regex]::Escape($longPathFixture)) {
        Add-Failure 'Renderer đường dẫn dài chưa giữ nguyên dữ liệu đầy đủ cho bản PDF.'
    }
} catch {
    Add-Failure "Không chạy được fixture profile/độ dễ đọc PDF: $($_.Exception.Message)"
}

try {
    $inventoryPath = Join-Path $sourceDirectoryFull 'kiem-tra-cau-hinh-ban-quyen.ps1'
    $inventoryAst = [Management.Automation.Language.Parser]::ParseFile($inventoryPath, [ref]$null, [ref]$null)
    foreach ($functionName in @('Protect-ReportText','ConvertTo-ReportRedactedObject','Get-ReportWindowsLicenseChannel','Select-ReportPrimaryWindowsLicense','Get-ReportActivatorFamilyCode','Get-ReportSoftwareRemediationEligibility','Get-ReportParallelVersionRows')) {
        $functionAst = $inventoryAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true)
        if (-not $functionAst) { throw "Thiếu hàm $functionName" }
        Invoke-Expression ("function script:" + $functionName + " " + $functionAst.Body.Extent.Text)
    }
    function script:Get-ReportText {
        param([string]$Key, [object[]]$Arguments=@())
        switch ($Key) {
            'report.redaction.ip' { return '[IP]' }
            'report.redaction.mac' { return '[MAC]' }
            default {
                if ($Key -like 'report.software.*') { return $Key }
                return '[ĐÃ CHE]'
            }
        }
    }
    $script:RedactSensitive = $true
    $redactionFixture = ConvertTo-ReportRedactedObject ([pscustomobject][ordered]@{
        Software='FormatFactory 5.13.0.0'
        Version='5.13.0.0'
        ServerAddress='192.168.2.5'
        SerialNumber='SERIAL-FIXTURE-001'
        UserName='fixture-user'
        KmsServer='kms.example.internal'
        Evidence='Máy chủ 192.168.2.5'
    })
    if ([string]$redactionFixture.Software -ne 'FormatFactory 5.13.0.0' -or
        [string]$redactionFixture.Version -ne '5.13.0.0' -or
        [string]$redactionFixture.ServerAddress -ne '[ĐÃ CHE]' -or
        [string]$redactionFixture.SerialNumber -ne '[ĐÃ CHE]' -or
        [string]$redactionFixture.UserName -ne '[ĐÃ CHE]' -or
        [string]$redactionFixture.KmsServer -ne '[ĐÃ CHE]' -or
        [string]$redactionFixture.Evidence -notmatch '\[IP\]') {
        Add-Failure 'Ẩn dữ liệu nhạy cảm đang che nhầm phiên bản hoặc làm lọt IP/serial/user/KMS host.'
    }
    $notificationKms = [pscustomobject]@{ Name='Windows(R), Professional edition'; Description='Windows Operating System, VOLUME_KMSCLIENT channel'; LicenseStatus=5 }
    $licensedRetail = [pscustomobject]@{ Name='Windows(R), Professional edition'; Description='Windows Operating System, RETAIL channel'; LicenseStatus=1 }
    if ((Get-ReportWindowsLicenseChannel (Select-ReportPrimaryWindowsLicense @($notificationKms))) -ne 'KMS' -or
        (Get-ReportWindowsLicenseChannel (Select-ReportPrimaryWindowsLicense @($notificationKms,$licensedRetail))) -ne 'Retail') {
        Add-Failure 'Tổng quan Windows không giữ kênh KMS khi Notification hoặc không ưu tiên license đang hoạt động.'
    }
    foreach ($familyFixture in @{
        'TSforge Activation'='TSforge'; 'Office OHook'='OHook'; 'Microsoft Toolkit'='MicrosoftToolkit'; 'MAS_AIO'='MAS'; 'KMS_VL_ALL'='KmsActivator'
    }.GetEnumerator()) {
        if ((Get-ReportActivatorFamilyCode $familyFixture.Key) -ne $familyFixture.Value) { Add-Failure "Không nhận diện family activator: $($familyFixture.Key)" }
    }

    $crossProductRows = @(Get-ReportParallelVersionRows -Applications @(
        [pscustomobject]@{ 'Ten phan mem'='Zalo'; 'Phien ban'='24.1'; 'Duong dan'='C:\Program Files\Zalo'; 'Phạm vi'='Machine'; CatalogProductId='communication-free' },
        [pscustomobject]@{ 'Ten phan mem'='Telegram Desktop'; 'Phien ban'='5.2'; 'Duong dan'='C:\Program Files\Telegram Desktop'; 'Phạm vi'='Machine'; CatalogProductId='communication-free' }
    ))
    $actualParallelRows = @(Get-ReportParallelVersionRows -Applications @(
        [pscustomobject]@{ 'Ten phan mem'='Zalo'; 'Phien ban'='23.9'; 'Duong dan'='C:\Program Files\Zalo-23'; 'Phạm vi'='Machine'; CatalogProductId='communication-free' },
        [pscustomobject]@{ 'Ten phan mem'='  ZALO '; 'Phien ban'='24.1'; 'Duong dan'='C:\Program Files\Zalo-24'; 'Phạm vi'='Machine'; CatalogProductId='communication-free' }
    ))
    $duplicateDiscoveryRows = @(Get-ReportParallelVersionRows -Applications @(
        [pscustomobject]@{ 'Ten phan mem'='Zalo'; 'Phien ban'='24.1'; 'Duong dan'='C:\Program Files\Zalo'; 'Phạm vi'='Registry'; CatalogProductId='communication-free' },
        [pscustomobject]@{ 'Ten phan mem'='Zalo'; 'Phien ban'='24.1'; 'Duong dan'='C:\Program Files\Zalo'; 'Phạm vi'='Shortcut'; CatalogProductId='communication-free' }
    ))
    if ($crossProductRows.Count -ne 0 -or $actualParallelRows.Count -ne 1 -or $duplicateDiscoveryRows.Count -ne 0) {
        Add-Failure 'Phiên bản cài song song đang ghép chéo Zalo/Telegram, bỏ sót hai bản Zalo thật hoặc đếm lặp nguồn khám phá.'
    }

    $cleanWinRarGuidance = Get-ReportSoftwareRemediationEligibility -Name 'WinRAR' -Publisher 'win.rar GmbH' -AssessmentCode 'Unverified' -Confidence 'Medium' -LicenseModel 'Trialware' -ActivationStateProbe 'LocalLicensePresent' -RemediationSupported $true -HasRemediationEvidence $false -StrongTechnicalEvidence $false
    $crackedWinRarGuidance = Get-ReportSoftwareRemediationEligibility -Name 'WinRAR' -Publisher 'win.rar GmbH' -AssessmentCode 'NonGenuine' -Confidence 'High' -LicenseModel 'Trialware' -ActivationStateProbe 'LocalLicensePresent' -RemediationSupported $true -HasRemediationEvidence $true -StrongTechnicalEvidence $true
    $suspiciousWinRarGuidance = Get-ReportSoftwareRemediationEligibility -Name 'WinRAR' -Publisher 'win.rar GmbH' -AssessmentCode 'Suspicious' -Confidence 'Medium' -LicenseModel 'Trialware' -ActivationStateProbe 'Unactivated' -RemediationSupported $true -HasRemediationEvidence $true -StrongTechnicalEvidence $true
    if ($cleanWinRarGuidance -ne 'report.software.remediationWinRarLicensePresent' -or
        $crackedWinRarGuidance -ne 'report.software.remediationNonGenuineSupported' -or
        $suspiciousWinRarGuidance -ne 'report.software.remediationSuspiciousArtifact') {
        Add-Failure 'Hướng khắc phục WinRAR chưa ưu tiên bằng chứng crack/can thiệp độc lập trước trạng thái rarreg.key/thử dùng.'
    }
} catch {
    Add-Failure "Không chạy được fixture ẩn IP/giữ phiên bản: $($_.Exception.Message)"
}

$integrationChecks = @(
    @{ Name='inventory envelope'; Text=$inventoryText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"InventoryAndLicense"' },
    @{ Name='cleanup envelope'; Text=$cleanupText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"CleanupCompliance"' },
    @{ Name='scan-source repair envelope'; Text=$cleanupText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"ScanSourceRepair"' },
    @{ Name='forensics envelope'; Text=$forensicsText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"LicenseForensics"' },
    @{ Name='deep-scan success envelope'; Text=$deepScanText; Pattern='(?s)\$decision\s*=\s*New-ToolReportEnvelope\s+-ReportKind\s+"DeepScanDecision".+?AccessDenied\s*=\s*\$false.+?Test-ToolReportEnvelope\s+-Report\s+\$decision' },
    @{ Name='deep-scan access-denied envelope'; Text=$deepScanText; Pattern='(?s)\$accessDeniedDecision\s*=\s*New-ToolReportEnvelope\s+-ReportKind\s+"DeepScanDecision".+?AccessDenied\s*=\s*\$true' },
    @{ Name='certificate audit envelope'; Text=$assuranceText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"CertificateAudit"' },
    @{ Name='plugin evaluation envelope'; Text=$assuranceText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"PluginEvaluation"' },
    @{ Name='timeline envelope'; Text=$assuranceText; Pattern='New-ToolReportEnvelope\s+-ReportKind\s+"LicenseTimeline"' },
    @{ Name='GUI uses schema metadata'; Text=$guiText; Pattern='Get-ToolReportSchemaMetadata' }
)
foreach ($check in $integrationChecks) {
    if ($check.Text -notmatch $check.Pattern) { Add-Failure "Tích hợp schema thất bại: $($check.Name)" }
}

if ([regex]::Matches($deepScanText, 'New-ToolReportEnvelope\s+-ReportKind\s+"DeepScanDecision"').Count -lt 2) {
    Add-Failure 'Deep scan phải tạo envelope cho cả nhánh từ chối quyền và nhánh thành công.'
}

if ($inventoryText -notmatch 'class="cards cards-count-5"' -or
    $inventoryText -notmatch 'class="cards cards-summary cards-count-5"' -or
    $reportExportText -notmatch '\.cards-summary\{grid-template-columns:repeat\(5,minmax\(0,1fr\)\)\}') {
    Add-Failure 'HTML/PDF chưa gắn đúng bố cục năm ô thông tin trên cùng một hàng.'
}
if (-not $reportExportText.Contains('cards-count-$cardCount') -or
    $reportExportText -notmatch '\.cards\.cards-count-5\{grid-template-columns:repeat\(5,minmax\(0,1fr\)\)\}') {
    Add-Failure 'Các loại báo cáo dùng chung chưa tự gắn số cột hoặc chưa giữ năm ô cùng hàng khi in PDF.'
}
foreach ($requiredClass in @('summary-detail-verification','summary-detail-direction','summary-detail-value')) {
    if (-not $inventoryText.Contains($requiredClass) -or -not $reportExportText.Contains(".$requiredClass")) {
        Add-Failure "HTML tổng quan thiếu ô riêng hoặc CSS cho $requiredClass."
    }
}
if ([regex]::Matches($inventoryText, '<div class="footer-line">').Count -lt 4 -or
    $reportExportText -notmatch '\.footer-line\+\.footer-line') {
    Add-Failure 'Chân báo cáo HTML/PDF chưa được chia ổn định thành hai hàng.'
}

if ($guiText -notmatch 'function\s+New-ToolReportRunDirectory' -or
    $guiText -notmatch '(?s)function\s+New-ToolReportRunDirectory.+?return\s+\$reportRoot' -or
    $guiText -match '(?s)function\s+New-ToolReportRunDirectory.+?Join-Path\s+\$reportRoot\s+\$runName') {
    Add-Failure 'Dashboard chưa gom mọi lần quét vào một thư mục báo cáo dùng chung.'
}
if ($inventoryText -notmatch 'Desktop"\)\)\s+"BaoCao-Tool-Kiem-Tra"' -or
    $inventoryText -notmatch 'yyyyMMdd_HHmmss_fff') {
    Add-Failure 'Báo cáo trực tiếp chưa dùng thư mục chung hoặc tên tệp mili-giây chống ghi đè.'
}
foreach ($requiredToken in @('$primaryApps','$systemApps','system-software-appendix','system-app-link','back-link','PrimaryApplications','SystemApplications','SoftwareIntegrityCompromisedCount')) {
    if (-not $inventoryText.Contains($requiredToken)) { Add-Failure "Báo cáo phần mềm thiếu bộ lọc/phụ lục chi tiết: $requiredToken" }
}
foreach ($requiredToken in @('Get-ReportMonitorInventory','WmiMonitorID','Win32_DesktopMonitor','Win32_PnPEntity','Select-ReportPrimaryWindowsLicense','Get-ReportActivatorArtifactFindings','IncludeFileSearch','reportActivatorArtifactExtensions','installedProductRoots','WindowsActivationProfile','WindowsKmsTrust','ActivatorEvidenceCurrent','KMSRenewalUpTo180Days')) {
    if (-not $inventoryText.Contains($requiredToken)) { Add-Failure "Báo cáo thiếu hồi quy màn hình/KMS/timeline: $requiredToken" }
}
foreach ($requiredToken in @('tsforge','ohook','deepReport.kmsLifecycle.detected','forensicsReport.kmsLifecycle.renewal')) {
    if (-not $deepScanText.Contains($requiredToken) -and -not $forensicsText.Contains($requiredToken)) { Add-Failure "Quét sâu/forensics thiếu dấu hiệu: $requiredToken" }
}
if ($inventoryText -notmatch 'Add-Table\s+\$softwareAssessmentRows\s+@\("Ten phan mem","Phien ban","Hang",(?:\$licenseModelColumn,)?\$technicalStatusColumn,\$confidenceColumn,\$remediationEligibilityColumn\)' -or
    $inventoryText -notmatch 'Add-Table\s+\$softwareAssessmentEvidenceRows\s+@\("Ten phan mem",\$licenseModelColumn,\$assessmentCodeColumn,\$evidenceColumn,\$vendorScopeColumn,\$officialReferenceColumn\)') {
    Add-Failure 'Bảng đánh giá phần mềm chưa được tách thành tổng quan và bằng chứng để tránh ép cột PDF.'
}
foreach ($cssToken in @('.cell-details summary{display:none!important}',".cell-details .detail-content{display:block!important",'.cell-compact{display:none!important}',".cell-full{display:block!important",'table-layout:fixed','line-height:1.46','padding:6px 7px','orphans:3','widows:3','.system-software-appendix{background:linear-gradient','.system-summary-details>summary','.table-split-part','tbody tr:nth-child(even) td','thead{display:table-header-group}','print-color-adjust:exact')) {
    if (-not $reportExportText.Contains($cssToken)) { Add-Failure "CSS PDF thiếu bảo vệ chống khuyết dòng/hàng: $cssToken" }
}
foreach ($profileClass in @('table-profile-assessment-context','table-profile-assessment-decision','table-profile-assessment-overview','table-profile-assessment-evidence','table-profile-system-software','table-profile-compact')) {
    if (-not $reportExportText.Contains($profileClass)) { Add-Failure "CSS/renderer thiếu profile dễ đọc: $profileClass" }
}
if ($reportExportText -notmatch '\$Columns\.Count\s+-gt\s+6' -or
    $inventoryText -notmatch '\$Columns\.Count\s+-gt\s+6') {
    Add-Failure 'Bảng rộng chưa được tự tách thành các phần tối đa sáu cột.'
}
if ($reportExportText -notmatch 'New-ToolReportPdfGuideHtml' -or
    -not $reportExportText.Contains("href='`$safeFileName'") -or
    $reportExportText -notmatch 'HtmlContent\.Replace\("\{\{TOOL_REPORT_PDF_GUIDE\}\}"') {
    Add-Failure 'HTML chưa có liên kết cục bộ tới đúng tệp PDF chi tiết.'
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-REPORT-SCHEMA: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-REPORT-SCHEMA: OK (9 kinds + negative fixtures + source integration)' -ForegroundColor Green
exit 0
