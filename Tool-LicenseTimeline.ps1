$script:ToolTimelineSchemaVersion = "1.0"
$script:ToolTimelineToolVersion = "4.3"
$script:ToolTimelineState = $null

function Get-ToolTimelineMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolTimelineSchemaVersion
        ToolVersion = $script:ToolTimelineToolVersion
        Format = "HMAC-SHA256 chained JSONL"
        KeyProtection = "DPAPI LocalMachine"
        MaximumBytes = 52428800
        MaximumRecords = 100000
    }
}

function Get-ToolTimelineSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "") }
    finally { $sha.Dispose() }
}

function Get-ToolTimelineSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    return Get-ToolTimelineSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-ToolTimelineMachineBinding {
    $machineGuid = ""
    try {
        $machineGuid = [string](Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction Stop).MachineGuid
    } catch {
        $machineGuid = "$env:COMPUTERNAME|$([Environment]::OSVersion.VersionString)"
    }
    $bindingBytes = [Text.Encoding]::UTF8.GetBytes("Tool-Kiem-Tra-v4.3|$machineGuid")
    return Get-ToolTimelineSha256Bytes -Bytes $bindingBytes
}

function Assert-ToolTimelineDirectoryAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected) {
        throw "ACL thư mục timeline vẫn kế thừa quyền từ thư mục cha."
    }
    $allowedSids = @("S-1-5-32-544", "S-1-5-18")
    $ownerSid = try {
        $ownerAccount = New-Object Security.Principal.NTAccount([string]$acl.Owner)
        $ownerAccount.Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        [string]$acl.Owner
    }
    if ($allowedSids -notcontains $ownerSid) {
        throw "Owner thư mục timeline không phải Administrators/SYSTEM."
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
            throw "ACL timeline cho phép ghi bởi danh tính ngoài Administrators/SYSTEM: $sid"
        }
    }
}

function Test-ToolTimelinePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Extension
    )

    if (-not [IO.Path]::IsPathRooted($Path)) { throw "Đường dẫn timeline phải là đường dẫn tuyệt đối." }
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.Path]::GetExtension($fullPath).Equals($Extension, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Đường dẫn timeline phải dùng phần mở rộng $Extension."
    }
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Thư mục timeline chưa được launcher tạo." }
    $directoryInfo = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
    if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Thư mục timeline không được là reparse point." }
    if (Test-Path -LiteralPath $fullPath) {
        $fileInfo = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
        if (($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Tệp timeline không được là reparse point." }
    }
    if ($env:TOOL_SECURE_LAUNCH -eq "1") {
        $expectedRoot = Join-Path ([Environment]::GetFolderPath("CommonApplicationData")) "ThanhViet-Tool-Kiem-Tra\v4.3\timeline"
        $expectedPrefix = [IO.Path]::GetFullPath($expectedRoot).TrimEnd([char]92) + [char]92
        if (-not $fullPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Đường dẫn timeline nằm ngoài vùng ProgramData v4.3 được bảo vệ."
        }
        Assert-ToolTimelineDirectoryAcl -Path $directory
    }
    return $fullPath
}

function Initialize-ToolLicenseTimeline {
    [CmdletBinding()]
    param([string]$ToolVersion = "4.3")

    $state = [pscustomobject][ordered]@{
        Enabled = $false
        TimelinePath = ""
        KeyPath = ""
        ToolVersion = $ToolVersion
        MachineBinding = ""
        Error = ""
    }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $timelinePath = [string]$env:TOOL_TIMELINE_PATH
        $keyPath = [string]$env:TOOL_TIMELINE_KEY_PATH
        if ([string]::IsNullOrWhiteSpace($timelinePath) -or [string]::IsNullOrWhiteSpace($keyPath)) {
            throw "Launcher chưa thiết lập TOOL_TIMELINE_PATH/TOOL_TIMELINE_KEY_PATH; timeline bền vững đang tắt."
        }
        $timelinePath = Test-ToolTimelinePath -Path $timelinePath -Extension ".jsonl"
        $keyPath = Test-ToolTimelinePath -Path $keyPath -Extension ".key"
        if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
            $random = New-Object byte[] 32
            $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
            try { $rng.GetBytes($random) } finally { $rng.Dispose() }
            $protected = [Security.Cryptography.ProtectedData]::Protect(
                $random,
                [Text.Encoding]::UTF8.GetBytes("ThanhViet.ToolKiemTra.v4.3.Timeline"),
                [Security.Cryptography.DataProtectionScope]::LocalMachine)
            [IO.File]::WriteAllBytes($keyPath, $protected)
        }
        $keyInfo = Get-Item -LiteralPath $keyPath -Force -ErrorAction Stop
        if ($keyInfo.Length -lt 32 -or $keyInfo.Length -gt 4096) { throw "Khóa timeline có kích thước không hợp lệ." }
        [void](Get-ToolTimelineKey -Path $keyPath)
        $state.Enabled = $true
        $state.TimelinePath = $timelinePath
        $state.KeyPath = $keyPath
        $state.MachineBinding = Get-ToolTimelineMachineBinding
    } catch {
        $state.Error = $_.Exception.Message
    }
    $script:ToolTimelineState = $state
    return $state
}

function Get-ToolTimelineKey {
    param([string]$Path = "")

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if (-not $script:ToolTimelineState) { throw "Timeline chưa được khởi tạo." }
        $Path = [string]$script:ToolTimelineState.KeyPath
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $protected = [IO.File]::ReadAllBytes($Path)
    $key = [Security.Cryptography.ProtectedData]::Unprotect(
        $protected,
        [Text.Encoding]::UTF8.GetBytes("ThanhViet.ToolKiemTra.v4.3.Timeline"),
        [Security.Cryptography.DataProtectionScope]::LocalMachine)
    if ($key.Length -ne 32) { throw "Khóa HMAC timeline không đúng 256 bit." }
    return $key
}

function ConvertTo-ToolTimelineSafeData {
    param([AllowNull()][object]$Data)

    if ($null -eq $Data) { return [pscustomobject][ordered]@{} }
    $json = $Data | ConvertTo-Json -Depth 8 -Compress
    if ($json.Length -gt 24576) { throw "Dữ liệu timeline vượt giới hạn 24 KB." }
    $json = [regex]::Replace($json, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', '[PRODUCT-KEY ĐÃ CHE]')
    return $json | ConvertFrom-Json
}

function Get-ToolLicenseTimeline {
    [CmdletBinding()]
    param(
        [string]$TimelinePath = "",
        [string]$KeyPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($TimelinePath) -or [string]::IsNullOrWhiteSpace($KeyPath)) {
        if (-not $script:ToolTimelineState) { [void](Initialize-ToolLicenseTimeline) }
        if (-not $script:ToolTimelineState.Enabled) {
            return [pscustomobject][ordered]@{
                Valid=$false; RecordCount=0; ChangeCount=0; Events=@(); Errors=@($script:ToolTimelineState.Error); LastRecordHash=("0" * 64)
            }
        }
        $TimelinePath = $script:ToolTimelineState.TimelinePath
        $KeyPath = $script:ToolTimelineState.KeyPath
    } else {
        $TimelinePath = Test-ToolTimelinePath -Path $TimelinePath -Extension ".jsonl"
        $KeyPath = Test-ToolTimelinePath -Path $KeyPath -Extension ".key"
    }
    if (-not (Test-Path -LiteralPath $TimelinePath -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            Valid=$true; RecordCount=0; ChangeCount=0; Events=@(); Errors=@(); LastRecordHash=("0" * 64)
        }
    }
    $timelineInfo = Get-Item -LiteralPath $TimelinePath -Force
    if ($timelineInfo.Length -gt 52428800) {
        return [pscustomobject][ordered]@{
            Valid=$false; RecordCount=0; ChangeCount=0; Events=@(); Errors=@("Timeline vượt giới hạn 50 MB."); LastRecordHash=("0" * 64)
        }
    }
    $errors = New-Object System.Collections.Generic.List[string]
    $events = New-Object System.Collections.Generic.List[object]
    $key = Get-ToolTimelineKey -Path $KeyPath
    $previousHash = "0" * 64
    $lines = [IO.File]::ReadAllLines($TimelinePath, [Text.Encoding]::UTF8)
    if ($lines.Count -gt 100000) {
        return [pscustomobject][ordered]@{
            Valid=$false; RecordCount=0; ChangeCount=0; Events=@(); Errors=@("Timeline vượt giới hạn 100000 bản ghi."); LastRecordHash=$previousHash
        }
    }
    $expectedSequence = 1
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ([string]$record.SchemaVersion -ne $script:ToolTimelineSchemaVersion) { throw "Sai record SchemaVersion." }
            if ([string]$record.PayloadBase64 -notmatch '^[A-Za-z0-9+/]+={0,2}$') { throw "PayloadBase64 không hợp lệ." }
            if ([string]$record.HmacSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "HmacSha256 không hợp lệ." }
            $payloadBytes = [Convert]::FromBase64String([string]$record.PayloadBase64)
            $hmac = New-Object Security.Cryptography.HMACSHA256
            try {
                $hmac.Key = $key
                $actualHmac = ([BitConverter]::ToString($hmac.ComputeHash($payloadBytes))).Replace("-", "")
            } finally { $hmac.Dispose() }
            if (-not $actualHmac.Equals([string]$record.HmacSha256, [StringComparison]::OrdinalIgnoreCase)) { throw "HMAC không khớp." }
            $payloadJson = [Text.Encoding]::UTF8.GetString($payloadBytes)
            $payload = $payloadJson | ConvertFrom-Json -ErrorAction Stop
            if ([int]$payload.Sequence -ne $expectedSequence) { throw "Sequence không liên tục." }
            if (-not ([string]$payload.PreviousRecordHash).Equals($previousHash, [StringComparison]::OrdinalIgnoreCase)) { throw "Chuỗi PreviousRecordHash bị đứt." }
            if ([string]$payload.MachineBinding -ne (Get-ToolTimelineMachineBinding)) { throw "Timeline không thuộc máy hiện tại." }
            [void]$events.Add($payload)
            $previousHash = Get-ToolTimelineSha256Text -Text $line
            $expectedSequence++
        } catch {
            [void]$errors.Add("Bản ghi ${expectedSequence}: $($_.Exception.Message)")
            break
        }
    }
    $eventArray = @($events.ToArray())
    return [pscustomobject][ordered]@{
        Valid = [bool]($errors.Count -eq 0)
        RecordCount = $eventArray.Count
        ChangeCount = @($eventArray | Where-Object { [bool]$_.IsChange }).Count
        Events = $eventArray
        Errors = @($errors.ToArray())
        LastRecordHash = $previousHash
    }
}

function Write-ToolLicenseTimelineEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$Source,
        [AllowNull()][object]$Data = $null,
        [switch]$IsChange
    )

    if (-not $script:ToolTimelineState) { [void](Initialize-ToolLicenseTimeline) }
    if (-not $script:ToolTimelineState.Enabled) {
        return [pscustomobject][ordered]@{ Written=$false; Sequence=0; EventType=$EventType; Error=$script:ToolTimelineState.Error }
    }
    if ($EventType -notmatch '^[A-Za-z][A-Za-z0-9._-]{2,119}$') { throw "EventType timeline không hợp lệ." }
    if ($Source -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$') { throw "Source timeline không hợp lệ." }
    $mutex = $null
    $lockTaken = $false
    try {
        try { $mutex = New-Object Threading.Mutex($false, "Global\ThanhViet.ToolKiemTra.v4.3.Timeline") }
        catch { $mutex = New-Object Threading.Mutex($false, "Local\ThanhViet.ToolKiemTra.v4.3.Timeline") }
        $lockTaken = $mutex.WaitOne(10000)
        if (-not $lockTaken) { throw "Không lấy được khóa ghi timeline trong 10 giây." }
        $existing = Get-ToolLicenseTimeline
        if (-not $existing.Valid) { throw "Timeline hiện tại không hợp lệ; từ chối nối thêm: $($existing.Errors -join '; ')" }
        $safeData = ConvertTo-ToolTimelineSafeData -Data $Data
        $payload = [pscustomobject][ordered]@{
            SchemaVersion = $script:ToolTimelineSchemaVersion
            Sequence = [int]$existing.RecordCount + 1
            TimestampUtc = [DateTime]::UtcNow.ToString("o")
            ToolVersion = [string]$script:ToolTimelineState.ToolVersion
            EventType = $EventType
            Source = $Source
            CorrelationId = if ([string]::IsNullOrWhiteSpace([string]$env:TOOL_CORRELATION_ID)) { "" } else { [string]$env:TOOL_CORRELATION_ID }
            IsChange = [bool]$IsChange
            MachineBinding = [string]$script:ToolTimelineState.MachineBinding
            PreviousRecordHash = [string]$existing.LastRecordHash
            Data = $safeData
        }
        $payloadJson = $payload | ConvertTo-Json -Depth 8 -Compress
        $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payloadJson)
        $key = Get-ToolTimelineKey
        $hmac = New-Object Security.Cryptography.HMACSHA256
        try {
            $hmac.Key = $key
            $hmacHex = ([BitConverter]::ToString($hmac.ComputeHash($payloadBytes))).Replace("-", "")
        } finally { $hmac.Dispose() }
        $record = [pscustomobject][ordered]@{
            SchemaVersion = $script:ToolTimelineSchemaVersion
            PayloadBase64 = [Convert]::ToBase64String($payloadBytes)
            HmacSha256 = $hmacHex
        }
        $line = $record | ConvertTo-Json -Depth 3 -Compress
        if ($line.Length -gt 32768) { throw "Bản ghi timeline vượt giới hạn 32 KB." }
        [IO.File]::AppendAllText($script:ToolTimelineState.TimelinePath, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        return [pscustomobject][ordered]@{ Written=$true; Sequence=$payload.Sequence; EventType=$EventType; Error="" }
    } finally {
        if ($lockTaken -and $mutex) { try { $mutex.ReleaseMutex() } catch {} }
        if ($mutex) { $mutex.Dispose() }
    }
}

function Save-ToolLicenseSnapshot {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [string]$Source = "LicenseReport"
    )

    if (-not $script:ToolTimelineState) { [void](Initialize-ToolLicenseTimeline) }
    if (-not $script:ToolTimelineState.Enabled) {
        return [pscustomobject][ordered]@{ Written=$false; Changed=$false; Changes=@(); Error=$script:ToolTimelineState.Error }
    }
    $history = Get-ToolLicenseTimeline
    if (-not $history.Valid) { throw "Không thể tạo snapshot vì timeline không hợp lệ." }
    $previous = @($history.Events | Where-Object { $_.EventType -in @("LicenseStateObserved", "LicenseStateChanged") } | Select-Object -Last 1)
    $changes = New-Object System.Collections.Generic.List[object]
    if ($previous.Count -eq 1 -and $previous[0].Data -and $previous[0].Data.State) {
        $oldState = $previous[0].Data.State
        $names = @(@($State.PSObject.Properties.Name) + @($oldState.PSObject.Properties.Name) | Sort-Object -Unique)
        foreach ($name in $names) {
            $newProperty = $State.PSObject.Properties[$name]
            $oldProperty = $oldState.PSObject.Properties[$name]
            $newValue = if ($newProperty) { $newProperty.Value | ConvertTo-Json -Depth 5 -Compress } else { "null" }
            $oldValue = if ($oldProperty) { $oldProperty.Value | ConvertTo-Json -Depth 5 -Compress } else { "null" }
            if ($newValue -ne $oldValue) {
                [void]$changes.Add([pscustomobject][ordered]@{
                    Field = [string]$name
                    Previous = $oldValue
                    Current = $newValue
                })
            }
        }
    }
    $changed = [bool]($changes.Count -gt 0)
    $eventType = if ($changed) { "LicenseStateChanged" } else { "LicenseStateObserved" }
    $writeResult = Write-ToolLicenseTimelineEvent -EventType $eventType -Source $Source -IsChange:$changed -Data ([pscustomobject][ordered]@{
        State = $State
        Changes = @($changes.ToArray())
        PreviousSnapshotPresent = [bool]($previous.Count -eq 1)
    })
    return [pscustomobject][ordered]@{
        Written = [bool]$writeResult.Written
        Changed = $changed
        Changes = @($changes.ToArray())
        Sequence = [int]$writeResult.Sequence
        Error = [string]$writeResult.Error
    }
}
