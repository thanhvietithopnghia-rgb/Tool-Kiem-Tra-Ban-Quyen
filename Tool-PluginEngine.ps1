$script:ToolPluginSchemaVersion = "1.0"
$script:ToolPluginEngineVersion = "1.0"
$script:ToolPluginToolVersion = "4.3"

function Get-ToolPluginMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolPluginSchemaVersion
        EngineVersion = $script:ToolPluginEngineVersion
        ToolVersion = $script:ToolPluginToolVersion
        Model = "DeclarativeReadOnlyRules"
        SupportedRuleTypes = @("RegistryValue", "File", "Service")
        MaximumPluginBytes = 524288
        MaximumRulesPerPlugin = 128
        ArbitraryCodeAllowed = $false
    }
}

function Get-ToolPluginDirectory {
    $path = [string]$env:TOOL_PLUGIN_DIR
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "plugins"
    }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($path))
}

function Test-ToolPluginDirectory {
    param([string]$Path = (Get-ToolPluginDirectory))

    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            [void]$errors.Add("Thư mục plugin chưa tồn tại.")
        } else {
            $info = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                [void]$errors.Add("Thư mục plugin không được là junction/symlink.")
            }
        }
        if ($env:TOOL_SECURE_LAUNCH -eq "1") {
            $expected = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.3\plugins"
            if (-not $fullPath.Equals([IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) {
                [void]$errors.Add("Thư mục plugin nằm ngoài vùng ProgramData v4.3 được bảo vệ.")
            } elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
                $acl = Get-Acl -LiteralPath $fullPath -ErrorAction Stop
                $allowedSids = @("S-1-5-32-544", "S-1-5-18")
                if (-not $acl.AreAccessRulesProtected) {
                    [void]$errors.Add("ACL thư mục plugin vẫn kế thừa quyền từ thư mục cha.")
                }
                $ownerSid = try {
                    $ownerAccount = New-Object Security.Principal.NTAccount([string]$acl.Owner)
                    $ownerAccount.Translate([Security.Principal.SecurityIdentifier]).Value
                } catch {
                    [string]$acl.Owner
                }
                if ($allowedSids -notcontains $ownerSid) {
                    [void]$errors.Add("Owner thư mục plugin không phải Administrators/SYSTEM.")
                }
                $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor
                    [Security.AccessControl.FileSystemRights]::Modify -bor
                    [Security.AccessControl.FileSystemRights]::FullControl -bor
                    [Security.AccessControl.FileSystemRights]::CreateFiles -bor
                    [Security.AccessControl.FileSystemRights]::CreateDirectories
                foreach ($rule in @($acl.Access)) {
                    if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
                    if (($rule.FileSystemRights -band $writeMask) -eq 0) { continue }
                    $sid = try { $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { [string]$rule.IdentityReference }
                    if ($allowedSids -notcontains $sid) {
                        [void]$errors.Add("ACL cho phép ghi bởi danh tính ngoài Administrators/SYSTEM: $sid")
                    }
                }
            }
        }
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        Path = if ($fullPath) { $fullPath } else { [string]$Path }
        Protected = [bool]($env:TOOL_SECURE_LAUNCH -eq "1" -and $errors.Count -eq 0)
        Errors = @($errors.ToArray())
    }
}

function ConvertTo-ToolPluginSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 512)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`r", " ").Replace("`n", " ").Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', '[PRODUCT-KEY ĐÃ CHE]')
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Get-ToolPluginPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Test-ToolPluginObjectProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Allowed -notcontains [string]$property.Name) {
            [void]$Errors.Add("$Context chứa trường không được hỗ trợ: $($property.Name)")
        }
    }
}

function Read-ToolPluginPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowOutsideProtectedDirectory
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $plugin = $null
    $hash = ""
    $fullPath = ""
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        if (-not $fullPath.EndsWith(".plugin.json", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Plugin phải có phần mở rộng .plugin.json."
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Không tìm thấy tệp plugin." }
        $info = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Tệp plugin không được là symlink/reparse point." }
        if ($info.Length -le 0 -or $info.Length -gt 524288) { throw "Tệp plugin phải nằm trong giới hạn 1–524288 byte." }
        if (-not $AllowOutsideProtectedDirectory) {
            $directoryState = Test-ToolPluginDirectory
            if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
            $expectedPrefix = $directoryState.Path.TrimEnd([char]92) + [char]92
            if (-not $fullPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Plugin nằm ngoài thư mục plugin được bảo vệ."
            }
        }
        $raw = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
        $plugin = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $plugin) { throw "Nội dung JSON rỗng." }
        Test-ToolPluginObjectProperties -Object $plugin -Allowed @(
            "SchemaVersion", "PluginId", "Name", "Version", "Publisher",
            "Description", "MinimumToolVersion", "Enabled", "Rules"
        ) -Context "Plugin" -Errors $errors
        if ([string](Get-ToolPluginPropertyValue $plugin "SchemaVersion" "") -ne $script:ToolPluginSchemaVersion) {
            [void]$errors.Add("SchemaVersion phải là $($script:ToolPluginSchemaVersion).")
        }
        $pluginEnabledProperty = $plugin.PSObject.Properties["Enabled"]
        if ($pluginEnabledProperty -and $pluginEnabledProperty.Value -isnot [bool]) {
            [void]$errors.Add("Enabled của plugin phải là boolean.")
        }
        if ([string](Get-ToolPluginPropertyValue $plugin "PluginId" "") -notmatch '^[a-z0-9][a-z0-9.-]{2,79}$') {
            [void]$errors.Add("PluginId phải dài 3–80 ký tự, chỉ gồm a-z, 0-9, dấu chấm/gạch ngang.")
        }
        foreach ($field in @("Name", "Version", "Publisher")) {
            $value = [string](Get-ToolPluginPropertyValue $plugin $field "")
            if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 160) {
                [void]$errors.Add("$field không hợp lệ.")
            }
        }
        $pluginVersion = $null
        if (-not [Version]::TryParse([string](Get-ToolPluginPropertyValue $plugin "Version" ""), [ref]$pluginVersion)) {
            [void]$errors.Add("Version không đúng định dạng version số.")
        }
        $minimumVersion = $null
        $minimumToolVersionText = [string](Get-ToolPluginPropertyValue $plugin "MinimumToolVersion" "")
        if (-not [string]::IsNullOrWhiteSpace($minimumToolVersionText)) {
            if (-not [Version]::TryParse($minimumToolVersionText, [ref]$minimumVersion)) {
                [void]$errors.Add("MinimumToolVersion không hợp lệ.")
            } elseif ($minimumVersion -gt [Version]$script:ToolPluginToolVersion) {
                [void]$errors.Add("Plugin cần Tool $minimumVersion hoặc mới hơn.")
            }
        }
        $rules = @(Get-ToolPluginPropertyValue $plugin "Rules" @())
        if ($rules.Count -lt 1 -or $rules.Count -gt 128) {
            [void]$errors.Add("Plugin phải có 1–128 quy tắc.")
        }
        $ruleIds = @{}
        $ruleIndex = 0
        foreach ($rule in $rules) {
            $ruleIndex++
            Test-ToolPluginObjectProperties -Object $rule -Allowed @(
                "RuleId", "Type", "Condition", "Hive", "Path", "ValueName",
                "Expected", "Name", "Severity", "Message", "Remediation", "Enabled"
            ) -Context "Rule #$ruleIndex" -Errors $errors
            $ruleId = [string](Get-ToolPluginPropertyValue $rule "RuleId" "")
            $ruleEnabledProperty = $rule.PSObject.Properties["Enabled"]
            if ($ruleEnabledProperty -and $ruleEnabledProperty.Value -isnot [bool]) {
                [void]$errors.Add("Enabled của rule #$ruleIndex phải là boolean.")
            }
            if ($ruleId -notmatch '^[a-z0-9][a-z0-9._-]{2,79}$') {
                [void]$errors.Add("Rule #$ruleIndex có RuleId không hợp lệ.")
            } elseif ($ruleIds.ContainsKey($ruleId)) {
                [void]$errors.Add("RuleId bị lặp: $ruleId")
            } else {
                $ruleIds[$ruleId] = $true
            }
            $type = [string](Get-ToolPluginPropertyValue $rule "Type" "")
            $condition = [string](Get-ToolPluginPropertyValue $rule "Condition" "")
            $allowedConditions = switch ($type) {
                "RegistryValue" { @("Exists", "Missing", "Equals", "NotEquals", "Contains", "Regex") }
                "File" { @("Exists", "Missing", "Sha256NotEquals", "AuthenticodeNotValid") }
                "Service" { @("Exists", "Missing", "StatusEquals", "StartModeEquals") }
                default { @() }
            }
            if ($type -notin @("RegistryValue", "File", "Service")) {
                [void]$errors.Add("Rule $ruleId có Type không được hỗ trợ: $type")
            } elseif ($allowedConditions -notcontains $condition) {
                [void]$errors.Add("Rule $ruleId có Condition không hợp lệ cho $type.")
            }
            if ([string](Get-ToolPluginPropertyValue $rule "Severity" "") -notin @("Info", "Low", "Medium", "High", "Critical")) {
                [void]$errors.Add("Rule $ruleId có Severity không hợp lệ.")
            }
            $messageText = [string](Get-ToolPluginPropertyValue $rule "Message" "")
            $remediationText = [string](Get-ToolPluginPropertyValue $rule "Remediation" "")
            $expectedText = [string](Get-ToolPluginPropertyValue $rule "Expected" "")
            $pathText = [string](Get-ToolPluginPropertyValue $rule "Path" "")
            $nameText = [string](Get-ToolPluginPropertyValue $rule "Name" "")
            if ([string]::IsNullOrWhiteSpace($messageText) -or $messageText.Length -gt 800) {
                [void]$errors.Add("Rule $ruleId thiếu Message hoặc Message quá dài.")
            }
            if ($remediationText.Length -gt 1200 -or $expectedText.Length -gt 512 -or
                $pathText.Length -gt 1024 -or $nameText.Length -gt 256) {
                [void]$errors.Add("Rule $ruleId có trường vượt giới hạn.")
            }
            if ($type -eq "RegistryValue") {
                $hiveText = [string](Get-ToolPluginPropertyValue $rule "Hive" "")
                if ($hiveText -notin @("HKLM", "HKCU") -or [string]::IsNullOrWhiteSpace($pathText) -or
                    $pathText -notmatch '^[^\\/:*?"<>|\x00-\x1F]+(?:\\[^\\/:*?"<>|\x00-\x1F]+)*$' -or
                    @($pathText -split '\\' | Where-Object { $_ -in @(".", "..") }).Count -gt 0 -or
                    [string]::IsNullOrWhiteSpace([string](Get-ToolPluginPropertyValue $rule "ValueName" ""))) {
                    [void]$errors.Add("Rule $ruleId có Registry hive/path không an toàn.")
                }
            }
            if ($type -eq "File" -and [string]::IsNullOrWhiteSpace($pathText)) {
                [void]$errors.Add("Rule $ruleId thiếu Path.")
            }
            if ($type -eq "Service" -and $nameText -notmatch '^[A-Za-z0-9_.-]{1,256}$') {
                [void]$errors.Add("Rule $ruleId có tên service không hợp lệ.")
            }
            if ($condition -eq "Sha256NotEquals" -and $expectedText -notmatch '^[A-Fa-f0-9]{64}$') {
                [void]$errors.Add("Rule $ruleId phải có Expected là SHA-256 gồm 64 ký tự hex.")
            }
            if ($condition -eq "Contains" -and [string]::IsNullOrWhiteSpace($expectedText)) {
                [void]$errors.Add("Rule $ruleId dùng Contains nhưng Expected đang rỗng.")
            }
            if ($condition -eq "StatusEquals" -and $expectedText -notin @("Running", "Stopped", "Paused", "Start Pending", "Stop Pending", "Continue Pending", "Pause Pending")) {
                [void]$errors.Add("Rule $ruleId có trạng thái service Expected không hợp lệ.")
            }
            if ($condition -eq "StartModeEquals" -and $expectedText -notin @("Auto", "Manual", "Disabled")) {
                [void]$errors.Add("Rule $ruleId có StartMode Expected không hợp lệ.")
            }
            if ($condition -eq "Regex") {
                try {
                    if ($expectedText.Length -gt 256) { throw "Regex vượt 256 ký tự." }
                    [void](New-Object Text.RegularExpressions.Regex(
                        $expectedText,
                        [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                        [TimeSpan]::FromMilliseconds(250)))
                } catch {
                    [void]$errors.Add("Rule $ruleId có Regex không hợp lệ: $($_.Exception.Message)")
                }
            }
        }
        $hash = Get-ToolPluginSha256 -Path $fullPath
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        Path = $fullPath
        Sha256 = $hash
        Plugin = $plugin
        Errors = @($errors.ToArray())
    }
}

function Get-ToolPluginSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Assert-ToolPluginPathWithoutReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92)
    $rootPrefix = $root + [char]92
    $cursor = [IO.Path]::GetFullPath($FullPath).TrimEnd([char]92)
    while ($true) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Plugin không được đi qua symlink/junction/reparse point: $cursor"
            }
        }
        if ($cursor.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrWhiteSpace($parent) -or
            (-not $parent.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
             -not $parent.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase))) {
            throw "Không xác minh được chuỗi thư mục của đường dẫn plugin."
        }
        $cursor = $parent.TrimEnd([char]92)
    }
}

function Resolve-ToolPluginSystemFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [IO.Path]::IsPathRooted($expanded) -or $expanded.StartsWith("\\", [StringComparison]::Ordinal)) {
        throw "Plugin chỉ được kiểm tra đường dẫn cục bộ tuyệt đối."
    }
    $fullPath = [IO.Path]::GetFullPath($expanded)
    $allowedRoots = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
        [IO.Path]::GetFullPath([string]$_).TrimEnd([char]92) + [char]92
    } | Select-Object -Unique
    foreach ($root in $allowedRoots) {
        if ($fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Assert-ToolPluginPathWithoutReparsePoint -FullPath $fullPath -AllowedRoot $root
            return $fullPath
        }
    }
    throw "Plugin chỉ được kiểm tra tệp trong Windows, Program Files hoặc ProgramData."
}

function Test-ToolPluginTextCondition {
    param(
        [AllowNull()][object]$Observed,
        [Parameter(Mandatory = $true)][string]$Condition,
        [string]$Expected = ""
    )

    $text = if ($null -eq $Observed) { "" } else { [string]$Observed }
    switch ($Condition) {
        "Equals" { return $text.Equals($Expected, [StringComparison]::OrdinalIgnoreCase) }
        "NotEquals" { return -not $text.Equals($Expected, [StringComparison]::OrdinalIgnoreCase) }
        "Contains" { return ($text.IndexOf($Expected, [StringComparison]::OrdinalIgnoreCase) -ge 0) }
        "Regex" {
            $regex = New-Object Text.RegularExpressions.Regex(
                $Expected,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromMilliseconds(250))
            return $regex.IsMatch($text)
        }
        default { return $false }
    }
}

function Invoke-ToolPluginRule {
    param(
        [Parameter(Mandatory = $true)][object]$Plugin,
        [Parameter(Mandatory = $true)][object]$Rule
    )

    $triggered = $false
    $observed = ""
    $errorText = ""
    try {
        $condition = [string](Get-ToolPluginPropertyValue $Rule "Condition" "")
        switch ([string](Get-ToolPluginPropertyValue $Rule "Type" "")) {
            "RegistryValue" {
                $root = if ([string](Get-ToolPluginPropertyValue $Rule "Hive" "") -eq "HKLM") { "Registry::HKEY_LOCAL_MACHINE" } else { "Registry::HKEY_CURRENT_USER" }
                $registrySubPath = [string](Get-ToolPluginPropertyValue $Rule "Path" "")
                $registryPath = $root + [char]92 + $registrySubPath
                $valueName = [string](Get-ToolPluginPropertyValue $Rule "ValueName" "")
                $keyExists = Test-Path -LiteralPath $registryPath -PathType Container
                $property = $null
                if ($keyExists) {
                    try { $property = Get-ItemProperty -LiteralPath $registryPath -Name $valueName -ErrorAction Stop } catch {}
                }
                $propertyValue = if ($property -and $property.PSObject.Properties[$valueName]) { $property.PSObject.Properties[$valueName].Value } else { $null }
                $valueExists = [bool]($null -ne $propertyValue)
                $observed = if ($valueExists) { ConvertTo-ToolPluginSafeText $propertyValue } else { "<missing>" }
                if ($condition -eq "Exists") { $triggered = $valueExists }
                elseif ($condition -eq "Missing") { $triggered = -not $valueExists }
                else { $triggered = $valueExists -and (Test-ToolPluginTextCondition -Observed $propertyValue -Condition $condition -Expected ([string](Get-ToolPluginPropertyValue $Rule "Expected" ""))) }
            }
            "File" {
                $filePath = Resolve-ToolPluginSystemFile -Path ([string](Get-ToolPluginPropertyValue $Rule "Path" ""))
                $exists = Test-Path -LiteralPath $filePath -PathType Leaf
                $observed = if ($exists) { "Present: $filePath" } else { "Missing: $filePath" }
                if ($condition -eq "Exists") { $triggered = $exists }
                elseif ($condition -eq "Missing") { $triggered = -not $exists }
                elseif ($condition -eq "Sha256NotEquals") {
                    $actualHash = if ($exists) { Get-ToolPluginSha256 -Path $filePath } else { "" }
                    $observed = if ($exists) { "SHA256=$actualHash" } else { "<missing>" }
                    $triggered = $exists -and -not $actualHash.Equals(([string](Get-ToolPluginPropertyValue $Rule "Expected" "")).Trim(), [StringComparison]::OrdinalIgnoreCase)
                } elseif ($condition -eq "AuthenticodeNotValid") {
                    $signature = if ($exists) { Get-AuthenticodeSignature -LiteralPath $filePath } else { $null }
                    $signer = if ($signature -and $signature.SignerCertificate) { ConvertTo-ToolPluginSafeText $signature.SignerCertificate.Subject } else { "<none>" }
                    $observed = if ($signature) { "Authenticode=$([string]$signature.Status); Signer=$signer" } else { "<missing>" }
                    $triggered = $exists -and [string]$signature.Status -ne "Valid"
                }
            }
            "Service" {
                $serviceName = [string](Get-ToolPluginPropertyValue $Rule "Name" "")
                $service = Get-WmiObject -Class Win32_Service -Filter ("Name='" + $serviceName.Replace("'", "''") + "'") -ErrorAction SilentlyContinue | Select-Object -First 1
                $exists = [bool]($null -ne $service)
                $observed = if ($service) { "State=$($service.State); StartMode=$($service.StartMode)" } else { "<missing>" }
                if ($condition -eq "Exists") { $triggered = $exists }
                elseif ($condition -eq "Missing") { $triggered = -not $exists }
                elseif ($condition -eq "StatusEquals") { $triggered = $exists -and ([string]$service.State).Equals([string](Get-ToolPluginPropertyValue $Rule "Expected" ""), [StringComparison]::OrdinalIgnoreCase) }
                elseif ($condition -eq "StartModeEquals") { $triggered = $exists -and ([string]$service.StartMode).Equals([string](Get-ToolPluginPropertyValue $Rule "Expected" ""), [StringComparison]::OrdinalIgnoreCase) }
            }
        }
    } catch {
        $errorText = ConvertTo-ToolPluginSafeText $_.Exception.Message 800
    }
    return [pscustomobject][ordered]@{
        PluginId = [string](Get-ToolPluginPropertyValue $Plugin "PluginId" "")
        PluginName = [string](Get-ToolPluginPropertyValue $Plugin "Name" "")
        RuleId = [string](Get-ToolPluginPropertyValue $Rule "RuleId" "")
        RuleType = [string](Get-ToolPluginPropertyValue $Rule "Type" "")
        Triggered = [bool]$triggered
        Severity = [string](Get-ToolPluginPropertyValue $Rule "Severity" "")
        Message = ConvertTo-ToolPluginSafeText (Get-ToolPluginPropertyValue $Rule "Message" "") 800
        Remediation = ConvertTo-ToolPluginSafeText (Get-ToolPluginPropertyValue $Rule "Remediation" "") 1200
        Observed = ConvertTo-ToolPluginSafeText $observed 800
        Error = $errorText
    }
}

function Invoke-ToolPluginAudit {
    param([string]$PluginDirectory = (Get-ToolPluginDirectory))

    $directoryState = Test-ToolPluginDirectory -Path $PluginDirectory
    $plugins = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    $invalid = New-Object System.Collections.Generic.List[object]
    if (-not $directoryState.Valid) {
        return [pscustomobject][ordered]@{
            SchemaVersion = $script:ToolPluginSchemaVersion
            EngineVersion = $script:ToolPluginEngineVersion
            Directory = $directoryState
            PluginCount = 0
            EnabledPluginCount = 0
            InvalidPluginCount = 0
            EvaluatedRuleCount = 0
            TriggeredFindingCount = 0
            HighOrCriticalCount = 0
            Plugins = @()
            Findings = @()
            InvalidPlugins = @()
            Error = ($directoryState.Errors -join "; ")
        }
    }
    $files = @(Get-ChildItem -LiteralPath $directoryState.Path -Filter "*.plugin.json" -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 32)
    $evaluatedRuleCount = 0
    $enabledCount = 0
    foreach ($file in $files) {
        $package = Read-ToolPluginPackage -Path $file.FullName
        if (-not $package.Valid) {
            [void]$invalid.Add([pscustomobject][ordered]@{ File=$file.Name; Errors=@($package.Errors) })
            continue
        }
        $plugin = $package.Plugin
        $enabled = [bool]($null -eq $plugin.PSObject.Properties["Enabled"] -or [bool]$plugin.Enabled)
        [void]$plugins.Add([pscustomobject][ordered]@{
            PluginId = [string]$plugin.PluginId
            Name = [string]$plugin.Name
            Version = [string]$plugin.Version
            Publisher = [string]$plugin.Publisher
            Enabled = $enabled
            RuleCount = @($plugin.Rules).Count
            Sha256 = $package.Sha256
            Trust = if ($directoryState.Protected) { "ProtectedAdminDirectory" } else { "SourceMode" }
        })
        if (-not $enabled) { continue }
        $enabledCount++
        foreach ($rule in @($plugin.Rules)) {
            if ($rule.PSObject.Properties["Enabled"] -and -not [bool]$rule.Enabled) { continue }
            $evaluatedRuleCount++
            $result = Invoke-ToolPluginRule -Plugin $plugin -Rule $rule
            if ($result.Triggered -or -not [string]::IsNullOrWhiteSpace($result.Error)) { [void]$findings.Add($result) }
        }
    }
    $findingArray = @($findings.ToArray())
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolPluginSchemaVersion
        EngineVersion = $script:ToolPluginEngineVersion
        Directory = $directoryState
        PluginCount = $plugins.Count
        EnabledPluginCount = $enabledCount
        InvalidPluginCount = $invalid.Count
        EvaluatedRuleCount = $evaluatedRuleCount
        TriggeredFindingCount = @($findingArray | Where-Object Triggered).Count
        HighOrCriticalCount = @($findingArray | Where-Object { $_.Triggered -and $_.Severity -in @("High", "Critical") }).Count
        Plugins = @($plugins.ToArray())
        Findings = $findingArray
        InvalidPlugins = @($invalid.ToArray())
        Error = ""
    }
}

function Install-ToolPluginPackage {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [string]$PluginDirectory = (Get-ToolPluginDirectory),
        [switch]$Force
    )

    $directoryState = Test-ToolPluginDirectory -Path $PluginDirectory
    if (-not $directoryState.Valid) { throw ($directoryState.Errors -join "; ") }
    $package = Read-ToolPluginPackage -Path $SourcePath -AllowOutsideProtectedDirectory
    if (-not $package.Valid) { throw ($package.Errors -join "; ") }
    $plugin = $package.Plugin
    $destinationName = "$([string]$plugin.PluginId).plugin.json"
    $destination = Join-Path $directoryState.Path $destinationName
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if (-not $Force) { throw "Plugin $([string]$plugin.PluginId) đã tồn tại." }
        $existing = Get-Item -LiteralPath $destination -Force
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Tệp đích plugin không được là reparse point." }
    }
    $transactionId = [Guid]::NewGuid().ToString("N")
    $temporary = Join-Path $directoryState.Path "$([string]$plugin.PluginId).install-$transactionId.plugin.json"
    $backup = Join-Path $directoryState.Path "$([string]$plugin.PluginId).backup-$transactionId.plugin.json"
    $destinationCreated = $false
    try {
        [IO.File]::Copy($package.Path, $temporary, $false)
        $staged = Read-ToolPluginPackage -Path $temporary
        if (-not $staged.Valid -or -not $staged.Sha256.Equals($package.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Plugin tạm sau khi sao chép không vượt qua xác minh SHA-256/schema."
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            [IO.File]::Replace($temporary, $destination, $backup, $true)
        } else {
            [IO.File]::Move($temporary, $destination)
            $destinationCreated = $true
        }
        $installed = Read-ToolPluginPackage -Path $destination
        if (-not $installed.Valid -or -not $installed.Sha256.Equals($package.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Plugin sau khi cài không vượt qua xác minh SHA-256/schema."
        }
    } catch {
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                [IO.File]::Replace($backup, $destination, $null, $true)
            } else {
                [IO.File]::Move($backup, $destination)
            }
        } elseif ($destinationCreated -and (Test-Path -LiteralPath $destination -PathType Leaf)) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        foreach ($cleanupPath in @($temporary, $backup)) {
            if (Test-Path -LiteralPath $cleanupPath -PathType Leaf) {
                Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return [pscustomobject][ordered]@{
        Installed = $true
        PluginId = [string]$plugin.PluginId
        Name = [string]$plugin.Name
        Version = [string]$plugin.Version
        Publisher = [string]$plugin.Publisher
        Path = $destination
        Sha256 = $installed.Sha256
        Trust = if ($directoryState.Protected) { "ProtectedAdminDirectory" } else { "SourceMode" }
    }
}
