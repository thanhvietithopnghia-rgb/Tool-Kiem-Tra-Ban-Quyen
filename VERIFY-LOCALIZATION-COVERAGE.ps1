[CmdletBinding()]
param(
    [string]$SourceDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$SourceDirectory = if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $PSScriptRoot } else { [IO.Path]::GetFullPath($SourceDirectory) }
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message)) { [void]$failures.Add($Message) }
}

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Get-Catalog([string]$Name) {
    $path = Join-Path $SourceDirectory $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing localization catalog: $Name"
        return $null
    }
    try {
        $raw = Read-Utf8 $path
        $object = $raw | ConvertFrom-Json
        $map = @{}
        foreach ($property in $object.PSObject.Properties) {
            $map[[string]$property.Name] = [string]$property.Value
        }
        $declared = @([regex]::Matches($raw, '(?m)^\s*"(?<Key>[^"\\]+)"\s*:') | ForEach-Object { $_.Groups['Key'].Value })
        if ($declared.Count -ne @($declared | Select-Object -Unique).Count) {
            Add-Failure "$Name contains duplicate JSON keys."
        }
        if ($map.Count -lt 1) { Add-Failure "$Name is empty." }
        return $map
    } catch {
        Add-Failure ("Cannot parse {0}: {1}" -f $Name, $_.Exception.Message)
        return $null
    }
}

$vi = Get-Catalog 'Tool-Strings.vi-VN.json'
$en = Get-Catalog 'Tool-Strings.en-US.json'
if ($vi -and $en) {
    foreach ($key in @($vi.Keys | Sort-Object)) {
        if (-not $en.ContainsKey($key)) { Add-Failure "en-US catalog is missing key: $key"; continue }
        if ([string]::IsNullOrWhiteSpace([string]$vi[$key])) { Add-Failure "vi-VN value is empty: $key" }
        if ([string]::IsNullOrWhiteSpace([string]$en[$key])) { Add-Failure "en-US value is empty: $key" }
        $viPlaceholders = @([regex]::Matches([string]$vi[$key], '\{(?<Index>\d+)(?:[^}]*)\}') | ForEach-Object { $_.Groups['Index'].Value } | Sort-Object -Unique)
        $enPlaceholders = @([regex]::Matches([string]$en[$key], '\{(?<Index>\d+)(?:[^}]*)\}') | ForEach-Object { $_.Groups['Index'].Value } | Sort-Object -Unique)
        if (($viPlaceholders -join ',') -cne ($enPlaceholders -join ',')) {
            Add-Failure "Placeholder mismatch for key $key (vi=$($viPlaceholders -join ','); en=$($enPlaceholders -join ','))."
        }
    }
    foreach ($key in @($en.Keys | Sort-Object)) {
        if (-not $vi.ContainsKey($key)) { Add-Failure "vi-VN catalog is missing key: $key" }
    }
}

$sourceNames = @(
    'Giao-Dien.ps1',
    'kiem-tra-cau-hinh-ban-quyen.ps1',
    'Tool-Runtime.ps1',
    'Tool-Compatibility.ps1',
    'Tool-Capabilities.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-OfflinePolicy.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1',
    'windows-license-assurance.ps1',
    'windows-license-backup.ps1',
    'windows-license-compliance-cleanup.ps1',
    'windows-license-deep-scan.ps1',
    'windows-license-forensics.ps1',
    'windows-license-restore.ps1',
    'windows-oem-license-assistant.ps1',
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1',
    'windows-office-license-manager.ps1',
    'Tool-Kiem-Tra-v4.6-OneFile.cs'
)

$staticKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
foreach ($name in $sourceNames) {
    $path = Join-Path $SourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "Missing localization source: $name"; continue }
    $text = Read-Utf8 $path
    foreach ($match in [regex]::Matches($text, '\bGet-[A-Za-z0-9]+Text(?:Current)?\s+(?:-Key\s+)?["''](?<Key>[^"'']+)["'']')) {
        [void]$staticKeys.Add($match.Groups['Key'].Value)
    }
    if ($name -like '*.cs') {
        foreach ($match in [regex]::Matches($text, '\bL\("(?<Key>[^"]+)"')) { [void]$staticKeys.Add($match.Groups['Key'].Value) }
    }
}
foreach ($requiredDynamicKey in @(
    'cleanupReport.status.fail',
    'cleanupReport.status.pass',
    'cleanupReport.status.review',
    'cleanupReport.status.unverified'
)) { [void]$staticKeys.Add($requiredDynamicKey) }

$builtinPluginPath = Join-Path $SourceDirectory 'builtin-windows-office-trust.plugin.json'
if (-not (Test-Path -LiteralPath $builtinPluginPath -PathType Leaf)) {
    Add-Failure 'Missing built-in Windows/Office trust plugin.'
} else {
    try {
        $builtinPlugin = (Read-Utf8 $builtinPluginPath) | ConvertFrom-Json
        foreach ($field in @('Name','Description')) {
            if ($builtinPlugin.PSObject.Properties[$field] -and
                -not [string]::IsNullOrWhiteSpace([string]$builtinPlugin.$field)) {
                Add-Failure "Built-in plugin contains a hard-coded presentation field: $field"
            }
        }
        foreach ($field in @('NameKey','DescriptionKey')) {
            $key = [string]$builtinPlugin.$field
            if ([string]::IsNullOrWhiteSpace($key)) { Add-Failure "Built-in plugin is missing $field." }
            else { [void]$staticKeys.Add($key) }
        }
        foreach ($rule in @($builtinPlugin.Rules)) {
            foreach ($field in @('Message','Remediation')) {
                if ($rule.PSObject.Properties[$field] -and
                    -not [string]::IsNullOrWhiteSpace([string]$rule.$field)) {
                    Add-Failure "Built-in plugin rule $($rule.RuleId) contains a hard-coded presentation field: $field"
                }
            }
            foreach ($field in @('MessageKey','RemediationKey')) {
                $key = [string]$rule.$field
                if ([string]::IsNullOrWhiteSpace($key)) { Add-Failure "Built-in plugin rule $($rule.RuleId) is missing $field." }
                else { [void]$staticKeys.Add($key) }
            }
        }
    } catch {
        Add-Failure ("Cannot validate the built-in plugin localization metadata: {0}" -f $_.Exception.Message)
    }
}

if ($vi -and $en) {
    foreach ($key in @($staticKeys | Sort-Object)) {
        if (-not $vi.ContainsKey($key) -or -not $en.ContainsKey($key)) { Add-Failure "Source uses a missing localization key: $key" }
    }
}

$enterpriseSourceNames = @(
    'Tool-Enterprise.ps1',
    'Tool-EnterpriseHost.ps1',
    'Tool-EnterpriseAgent.ps1',
    'enterprise-license-manager.ps1'
)
foreach ($name in $enterpriseSourceNames) {
    $path = Join-Path $SourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Read-Utf8 $path
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "$name parser error: $($parseError.Message)" }
    $nonAsciiStrings = @($ast.FindAll({
        param($node)
        if ($node -isnot [Management.Automation.Language.StringConstantExpressionAst] -and
            $node -isnot [Management.Automation.Language.ExpandableStringExpressionAst]) { return $false }
        foreach ($character in ([string]$node.Value).ToCharArray()) {
            if ([int]$character -gt 127) { return $true }
        }
        return $false
    }, $true))
    foreach ($node in $nonAsciiStrings) {
        $nodeValue = [string]$node.Value
        $nodeCodes = @($nodeValue.ToCharArray() | ForEach-Object { [int]$_ })
        $allowedEnglishLeakDetector = (
            [string]::Equals($name, 'enterprise-license-manager.ps1', [StringComparison]::Ordinal) -and
            $nodeCodes.Count -eq 5 -and
            ($nodeCodes -join ',') -eq '91,192,45,7929,93'
        )
        if (-not $allowedEnglishLeakDetector) {
            Add-Failure "$name contains a hard-coded non-ASCII presentation string at line $($node.Extent.StartLineNumber): $($node.Value)"
        }
    }
    if ($name -ne 'enterprise-license-manager.ps1') {
        foreach ($pattern in @(
            '\bthrow\s+["'']',
            'WriteLine\(\s*["'']',
            '\bMessage\s*=\s*["''][^"'']+'
        )) {
            if ($text -match $pattern) { Add-Failure "$name contains a hard-coded presentation message matching: $pattern" }
        }
    }
}

$foundationSourceNames = @(
    'Tool-Runtime.ps1',
    'Tool-Compatibility.ps1',
    'Tool-Capabilities.ps1',
    'Tool-Logging.ps1',
    'Tool-ModuleContract.ps1',
    'Tool-OfflinePolicy.ps1',
    'Tool-ReportSchema.ps1',
    'Tool-ReportExport.ps1',
    'Tool-PluginEngine.ps1',
    'Tool-LicenseTimeline.ps1'
)
foreach ($name in $foundationSourceNames) {
    $path = Join-Path $SourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Read-Utf8 $path
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "$name parser error: $($parseError.Message)" }
    $nonAsciiStrings = @($ast.FindAll({
        param($node)
        if ($node -isnot [Management.Automation.Language.StringConstantExpressionAst] -and
            $node -isnot [Management.Automation.Language.ExpandableStringExpressionAst]) { return $false }
        foreach ($character in ([string]$node.Value).ToCharArray()) {
            if ([int]$character -gt 127) { return $true }
        }
        return $false
    }, $true))
    foreach ($node in $nonAsciiStrings) {
        Add-Failure "$name contains a hard-coded non-ASCII presentation string at line $($node.Extent.StartLineNumber): $($node.Value)"
    }
    foreach ($pattern in @(
        '\bthrow\s+["'']',
        'WriteLine\(\s*["'']',
        '\bMessage\s*=\s*["''][^"'']+'
    )) {
        if ($text -match $pattern) { Add-Failure "$name contains a hard-coded presentation message matching: $pattern" }
    }
}

$launcherPath = Join-Path $SourceDirectory 'Tool-Kiem-Tra-v4.6-OneFile.cs'
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $launcher = Read-Utf8 $launcherPath
    if ($launcher -match '\bUiText\s*\(') { Add-Failure 'Launcher still contains the legacy UiText(vietnamese, english) selector.' }
    if ($launcher -match 'MessageBox\.Show\(\s*"') { Add-Failure 'Launcher has a hard-coded MessageBox message.' }
    if ($launcher -match 'throw\s+new\s+[A-Za-z0-9_.]+Exception\(\s*"') { Add-Failure 'Launcher has a hard-coded exception message.' }
    if ($launcher -notmatch 'TOOL_UI_CULTURE"\]\s*=\s*GetUiCulture\(\)') { Add-Failure 'Launcher does not propagate the selected culture to PowerShell.' }
    foreach ($historyName in @('LICH-SU-PHIEN-BAN.txt','VERSION-HISTORY-en-US.md')) {
        if ($launcher -notmatch [regex]::Escape('"' + $historyName + '"')) { Add-Failure "Launcher payload is missing $historyName." }
    }
}

$cleanupPath = Join-Path $SourceDirectory 'windows-license-compliance-cleanup.ps1'
if (Test-Path -LiteralPath $cleanupPath -PathType Leaf) {
    $cleanupText = Read-Utf8 $cleanupPath
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($cleanupText, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "Cleanup parser error: $($parseError.Message)" }
    $accentedStrings = @($ast.FindAll({
        param($node)
        ($node -is [Management.Automation.Language.StringConstantExpressionAst] -or
         $node -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and
        $node.Value -cmatch '[\u00C0-\u1EF9]'
    }, $true))
    foreach ($node in $accentedStrings) {
        $value = [string]$node.Value
        $allowedParserLiteral = $value.StartsWith('(?') -and (
            $value -match 'invalid combination|slmgr|Last 5|not available|Name|Activation ID|Description|Partial Product Key|KMS|licensed|unlicensed|notification|Successfully|product key uninstall'
        )
        if (-not $allowedParserLiteral) {
            Add-Failure "Cleanup contains a hard-coded Vietnamese presentation string at line $($node.Extent.StartLineNumber): $value"
        }
    }
    if ($cleanupText -notmatch '\[ValidateSet\("vi-VN"\s*,\s*"en-US"\)\]' -or -not $cleanupText.Contains('[string]$Culture')) { Add-Failure 'Cleanup module does not expose a vi-VN/en-US Culture parameter.' }
    foreach ($hashName in @('LocalizationHelperSha256','ViCatalogSha256','EnCatalogSha256')) {
        if ($cleanupText -notmatch [regex]::Escape($hashName)) { Add-Failure "Deep-cleanup restore manifest is missing $hashName." }
    }
}

$dashboardPath = Join-Path $SourceDirectory 'Giao-Dien.ps1'
if (Test-Path -LiteralPath $dashboardPath -PathType Leaf) {
    $dashboard = Read-Utf8 $dashboardPath
    if (-not $dashboard.Contains('$selectedHistoryFile = if ($script:dashboardCulture -eq "en-US")'.Replace('\',''))) { Add-Failure 'Version history does not select a file by culture.' }
    if (-not $dashboard.Contains('$selectedGuideFile = if ($script:dashboardCulture -eq "en-US")'.Replace('\',''))) { Add-Failure 'User guide does not select a file by culture.' }
    $moduleVariables = [ordered]@{
        'windows-license-compliance-cleanup.ps1' = '$cleanupScript'
        'windows-license-deep-scan.ps1' = '$deepScanScript'
        'windows-license-forensics.ps1' = '$forensicsScript'
        'windows-oem-license-assistant.ps1' = '$oemScript'
        'windows-license-backup.ps1' = '$backupScript'
        'windows-license-restore.ps1' = '$restoreScript'
    }
    foreach ($module in $moduleVariables.Keys) {
        $variable = [regex]::Escape([string]$moduleVariables[$module])
        if ($dashboard -notmatch "(?m)^\s*[$]arguments\s*=.*-File.*$variable.*-Culture") { Add-Failure "Dashboard does not propagate culture to $module." }
    }
}

$mainReportPath = Join-Path $SourceDirectory 'kiem-tra-cau-hinh-ban-quyen.ps1'
if (Test-Path -LiteralPath $mainReportPath -PathType Leaf) {
    $mainReportText = Read-Utf8 $mainReportPath
    $tokens = $null
    $parseErrors = $null
    $mainReportAst = [Management.Automation.Language.Parser]::ParseInput($mainReportText, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "Main report parser error: $($parseError.Message)" }
    foreach ($node in @($mainReportAst.FindAll({
        param($candidate)
        if ($candidate -isnot [Management.Automation.Language.StringConstantExpressionAst] -and
            $candidate -isnot [Management.Automation.Language.ExpandableStringExpressionAst]) { return $false }
        return [bool]([string]$candidate.Value -cmatch '[\u00C0-\u1EF9]')
    }, $true))) {
        $value = [string]$node.Value
        if ($node -is [Management.Automation.Language.ExpandableStringExpressionAst] -and $value.Contains('$(')) { continue }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $literalHash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)) }
        finally { $sha.Dispose() }
        $literalKey = 'report.literal.' + (([BitConverter]::ToString($literalHash)) -replace '-', '').ToLowerInvariant()
        if (-not $vi.ContainsKey($literalKey) -or -not $en.ContainsKey($literalKey)) {
            Add-Failure "Main report contains an uncatalogued presentation literal at line $($node.Extent.StartLineNumber): $value"
        }
    }
    if ($mainReportText -notmatch 'ConvertTo-ReportLocalizedExportObject\s+\$detailedInventory') {
        Add-Failure 'Detailed JSON/XML inventory is not passed through the localized export converter.'
    }
    foreach ($legacyStatus in @('"Đã kích hoạt"','"Đã cấp phép"','"Chưa cấp phép"')) {
        if ($mainReportText.Contains($legacyStatus)) { Add-Failure "Main report still hard-codes a localized license status: $legacyStatus" }
    }
}

foreach ($pair in @(
    @('HUONG-DAN.txt','USER-GUIDE-en-US.md'),
    @('LICH-SU-PHIEN-BAN.txt','VERSION-HISTORY-en-US.md')
)) {
    foreach ($name in $pair) {
        $path = Join-Path $SourceDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -lt 512) {
            Add-Failure "Missing or incomplete localized document: $name"
        }
    }
}

$legacyPatterns = @('Select-ReportText','EnglishLabels','Get-ReportEnglishLiteralMap')
foreach ($name in $sourceNames) {
    $path = Join-Path $SourceDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Read-Utf8 $path
    foreach ($pattern in $legacyPatterns) {
        if ($text -match [regex]::Escape($pattern)) { Add-Failure "$name still contains legacy localization construct: $pattern" }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "LOCALIZATION COVERAGE: FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    exit 1
}

Write-Host "LOCALIZATION COVERAGE: PASS ($($vi.Count) synchronized keys; $($staticKeys.Count) statically referenced keys)" -ForegroundColor Green
exit 0
