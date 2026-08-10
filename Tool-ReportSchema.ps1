$script:ToolReportSchemaVersion = "1.5"
$script:ToolReportSchemaToolVersion = "4.8"
$script:ToolReportKinds = @(
    "InventoryAndLicense",
    "CleanupCompliance",
    "LicenseForensics",
    "DeepScanDecision",
    "ScanSourceRepair",
    "CertificateAudit",
    "PluginEvaluation",
    "LicenseTimeline",
    "EnterpriseInventory"
)
$script:ToolReportRequiredFieldsByKind = [ordered]@{
    InventoryAndLicense = @("ToolName", "CreatedAt", "Mode")
    CleanupCompliance = @("ReadyForOfficialActivation", "ScanWarningCount", "HandlingGuidance")
    LicenseForensics = @("Overall", "RiskScore", "HighCount", "ReviewCount")
    DeepScanDecision = @("AccessDenied", "Overall", "HighCount", "ReviewCount", "ReportPath")
    ScanSourceRepair = @("RepairAttempted", "RecheckPassed", "StartupTypeChanged", "RollbackApplied", "ServiceStateBefore", "ServiceStateAfter")
    CertificateAudit = @("CreatedAt", "Overall", "ValidSignatureCount", "InvalidSignatureCount", "Targets")
    PluginEvaluation = @("CreatedAt", "PluginCount", "EvaluatedRuleCount", "TriggeredFindingCount")
    LicenseTimeline = @("CreatedAt", "ChainValid", "EventCount", "ChangeCount")
    EnterpriseInventory = @("CreatedAt", "ClientId", "ComputerName", "NetworkAddresses", "WindowsLicenses", "OfficeLicenses", "Privacy")
}

$toolReportSchemaLocalizationPath = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if ((-not (Get-Command Get-ToolTextCurrent -ErrorAction SilentlyContinue) -or
     -not (Get-Variable -Name ToolLocalizationSupportedCultures -Scope Script -ErrorAction SilentlyContinue)) -and
    (Test-Path -LiteralPath $toolReportSchemaLocalizationPath -PathType Leaf)) {
    . $toolReportSchemaLocalizationPath
}

function Get-ToolReportRequiredFields {
    param([Parameter(Mandatory = $true)][string]$ReportKind)
    if (-not $script:ToolReportRequiredFieldsByKind.Contains($ReportKind)) { return @() }
    return @($script:ToolReportRequiredFieldsByKind[$ReportKind])
}

function Get-ToolReportSchemaMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$script:ToolReportSchemaVersion
        ToolVersion = [string]$script:ToolReportSchemaToolVersion
        ReportKinds = @($script:ToolReportKinds)
        RequiredFields = @("SchemaVersion", "ReportSchemaVersion", "ReportKind", "ToolVersion")
        RequiredFieldsByKind = $script:ToolReportRequiredFieldsByKind
    }
}

function New-ToolReportEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportKind,
        [Parameter(Mandatory = $true)][string]$ToolVersion,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Data
    )

    if ($script:ToolReportKinds -notcontains $ReportKind) {
        throw (Get-ToolTextCurrent "foundation.reportSchema.kindUnsupportedForSchema" @($script:ToolReportSchemaVersion, $ReportKind))
    }
    if ([string]::IsNullOrWhiteSpace($ToolVersion)) {
        throw (Get-ToolTextCurrent "foundation.reportSchema.toolVersionRequired")
    }

    $result = [ordered]@{
        SchemaVersion = [string]$script:ToolReportSchemaVersion
        ReportSchemaVersion = [string]$script:ToolReportSchemaVersion
        ReportKind = [string]$ReportKind
        ToolVersion = [string]$ToolVersion
    }

    if ($null -ne $Data) {
        if ($Data -is [System.Collections.IDictionary]) {
            foreach ($key in @($Data.Keys)) {
                $name = [string]$key
                if ($result.Contains($name)) { continue }
                $result[$name] = $Data[$key]
            }
        } else {
            foreach ($property in @($Data.PSObject.Properties)) {
                $name = [string]$property.Name
                if ($result.Contains($name)) { continue }
                $result[$name] = $property.Value
            }
        }
    }

    return [pscustomobject]$result
}

function Test-ToolReportEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$Report,
        [string]$ExpectedReportKind = "",
        [string]$ExpectedToolVersion = ""
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Report) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.reportNull"))
        return [pscustomobject]@{ Valid=$false; Errors=$errors.ToArray() }
    }

    foreach ($field in @("SchemaVersion", "ReportSchemaVersion", "ReportKind", "ToolVersion")) {
        $property = $Report.PSObject.Properties[$field]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.requiredFieldMissing" @($field)))
        }
    }

    $schemaVersionProperty = $Report.PSObject.Properties['SchemaVersion']
    $reportSchemaVersionProperty = $Report.PSObject.Properties['ReportSchemaVersion']
    $reportKindProperty = $Report.PSObject.Properties['ReportKind']
    $toolVersionProperty = $Report.PSObject.Properties['ToolVersion']
    $schemaVersion = if ($null -ne $schemaVersionProperty) { [string]$schemaVersionProperty.Value } else { '' }
    $reportSchemaVersion = if ($null -ne $reportSchemaVersionProperty) { [string]$reportSchemaVersionProperty.Value } else { '' }
    $reportKind = if ($null -ne $reportKindProperty) { [string]$reportKindProperty.Value } else { '' }
    $toolVersion = if ($null -ne $toolVersionProperty) { [string]$toolVersionProperty.Value } else { '' }

    if ($schemaVersion -ne [string]$script:ToolReportSchemaVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.schemaUnsupported" @($schemaVersion)))
    }
    if ($reportSchemaVersion -ne [string]$script:ToolReportSchemaVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.reportSchemaMismatch" @($reportSchemaVersion)))
    }
    if ($script:ToolReportKinds -notcontains $reportKind) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindUnsupported" @($reportKind)))
    } else {
        foreach ($field in @(Get-ToolReportRequiredFields -ReportKind $reportKind)) {
            if ($null -eq $Report.PSObject.Properties[$field]) {
                $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindFieldMissing" @($reportKind, $field)))
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReportKind) -and $reportKind -ne $ExpectedReportKind) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.kindMismatch" @($ExpectedReportKind, $reportKind)))
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedToolVersion) -and $toolVersion -ne $ExpectedToolVersion) {
        $errors.Add((Get-ToolTextCurrent "foundation.reportSchema.toolVersionMismatch" @($ExpectedToolVersion, $toolVersion)))
    }

    return [pscustomobject]@{
        Valid = [bool]($errors.Count -eq 0)
        Errors = $errors.ToArray()
    }
}
