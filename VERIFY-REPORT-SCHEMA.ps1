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
    if ([string]$metadata.SchemaVersion -ne '1.5' -or [string]$metadata.ToolVersion -ne '4.3') {
        Add-Failure 'Metadata schema báo cáo không phải 1.5 / tool 4.3.'
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
            $fixture = New-ToolReportEnvelope -ReportKind $kind -ToolVersion '4.3' -Data $fixtures[$kind]
            $roundTrip = $fixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $validation = Test-ToolReportEnvelope -Report $roundTrip -ExpectedReportKind $kind -ExpectedToolVersion '4.3'
            if (-not $validation.Valid) { Add-Failure "Fixture $kind không đạt sau JSON round-trip: $($validation.Errors -join '; ')" }
            if ([string]$roundTrip.SchemaVersion -ne '1.5' -or [string]$roundTrip.ReportSchemaVersion -ne '1.5') {
                Add-Failure "Fixture $kind mất trường schema 1.5 sau round-trip."
            }
        } catch { Add-Failure "Không tạo/kiểm tra được fixture ${kind}: $($_.Exception.Message)" }
    }

    try {
        [void](New-ToolReportEnvelope -ReportKind 'UnknownKind' -ToolVersion '4.3' -Data @{})
        Add-Failure 'New-ToolReportEnvelope chấp nhận ReportKind không xác định.'
    } catch {}

    $negative = New-ToolReportEnvelope -ReportKind 'DeepScanDecision' -ToolVersion '4.3' -Data $fixtures.DeepScanDecision
    $negative.PSObject.Properties.Remove('SchemaVersion')
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận báo cáo thiếu SchemaVersion.' }

    $negative = New-ToolReportEnvelope -ReportKind 'DeepScanDecision' -ToolVersion '4.3' -Data $fixtures.DeepScanDecision
    $negative.PSObject.Properties.Remove('AccessDenied')
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận DeepScanDecision thiếu trường bắt buộc theo loại.' }

    $negative = New-ToolReportEnvelope -ReportKind 'CleanupCompliance' -ToolVersion '4.3' -Data $fixtures.CleanupCompliance
    $negative.ReportSchemaVersion = '1.3'
    if ((Test-ToolReportEnvelope -Report $negative).Valid) { Add-Failure 'Schema chấp nhận ReportSchemaVersion cũ.' }

    $negative = New-ToolReportEnvelope -ReportKind 'LicenseForensics' -ToolVersion '4.3' -Data $fixtures.LicenseForensics
    if ((Test-ToolReportEnvelope -Report $negative -ExpectedToolVersion '9.9').Valid) { Add-Failure 'Schema không bắt sai ToolVersion kỳ vọng.' }
}

$inventoryText = Read-SourceText 'kiem-tra-cau-hinh-ban-quyen.ps1'
$cleanupText = Read-SourceText 'windows-license-compliance-cleanup.ps1'
$forensicsText = Read-SourceText 'windows-license-forensics.ps1'
$deepScanText = Read-SourceText 'windows-license-deep-scan.ps1'
$assuranceText = Read-SourceText 'windows-license-assurance.ps1'
$guiText = Read-SourceText 'Giao-Dien.ps1'

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

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-REPORT-SCHEMA: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-REPORT-SCHEMA: OK (9 kinds + negative fixtures + source integration)' -ForegroundColor Green
exit 0
